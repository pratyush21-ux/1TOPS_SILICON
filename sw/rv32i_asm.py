#!/usr/bin/env python3
"""
Minimal two-pass RV32I assembler.

Enough of the base ISA to build test programs for the zeroriscy core:
R/I/S/B/U/J formats, labels, and the `li` / `nop` / `j` pseudo-ops.

Usage:  python rv32i_asm.py sort.s sort.hex
Output: one 32-bit hex word per line, starting at byte address 0, so the
        file can be dropped straight into $readmemh (word N == address 4*N).
"""

import re
import sys

XLEN_NOP = 0x00000013  # addi x0, x0, 0

# ---------------------------------------------------------------- encodings
R_TYPE = {  # name: (funct7, funct3)
    "add": (0x00, 0b000), "sub": (0x20, 0b000),
    "sll": (0x00, 0b001), "slt": (0x00, 0b010), "sltu": (0x00, 0b011),
    "xor": (0x00, 0b100), "srl": (0x00, 0b101), "sra": (0x20, 0b101),
    "or":  (0x00, 0b110), "and": (0x00, 0b111),
}
I_TYPE = {  # name: funct3   (opcode 0010011)
    "addi": 0b000, "slti": 0b010, "sltiu": 0b011,
    "xori": 0b100, "ori": 0b110, "andi": 0b111,
}
SHIFT_I = {  # name: (funct3, funct7)
    "slli": (0b001, 0x00), "srli": (0b101, 0x00), "srai": (0b101, 0x20),
}
LOAD = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORE = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCH = {
    "beq": 0b000, "bne": 0b001,
    "blt": 0b100, "bge": 0b101, "bltu": 0b110, "bgeu": 0b111,
}

OP_R, OP_I, OP_LOAD, OP_STORE = 0b0110011, 0b0010011, 0b0000011, 0b0100011
OP_BRANCH, OP_LUI, OP_AUIPC, OP_JAL, OP_JALR = 0b1100011, 0b0110111, 0b0010111, 0b1101111, 0b1100111

ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4, "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9, "a0": 10, "a1": 11, "a2": 12, "a3": 13,
    "a4": 14, "a5": 15, "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20,
    "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}


class AsmError(Exception):
    pass


def reg(tok):
    t = tok.strip().lower()
    if t in ABI:
        return ABI[t]
    m = re.fullmatch(r"x(\d+)", t)
    if not m or int(m.group(1)) > 31:
        raise AsmError(f"bad register '{tok}'")
    return int(m.group(1))


def s32(v, bits):
    """Range-check a signed immediate and return it masked to `bits`."""
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= v <= hi:
        raise AsmError(f"immediate {v} does not fit in {bits} signed bits")
    return v & ((1 << bits) - 1)


def const(tok, labels):
    """Evaluate an immediate: number, label, or label+/-number."""
    t = tok.strip()
    m = re.fullmatch(r"([A-Za-z_.][\w.]*)\s*([+-])\s*(\S+)", t)
    if m and m.group(1) in labels:
        return labels[m.group(1)] + (1 if m.group(2) == "+" else -1) * int(m.group(3), 0)
    if t in labels:
        return labels[t]
    try:
        return int(t, 0)
    except ValueError:
        raise AsmError(f"cannot resolve '{tok}'")


def split_mem(tok):
    """'8(x5)' -> (8, 'x5')"""
    m = re.fullmatch(r"(-?\w+)?\s*\(\s*(\S+?)\s*\)", tok.strip())
    if not m:
        raise AsmError(f"bad memory operand '{tok}'")
    return (m.group(1) or "0"), m.group(2)


# ---------------------------------------------------------------- pseudo-ops
def li_words(imm):
    """How many machine instructions `li rd, imm` expands to."""
    imm &= 0xFFFFFFFF
    signed = imm - (1 << 32) if imm & 0x80000000 else imm
    return 1 if -2048 <= signed <= 2047 else 2


def encode_li(rd, imm, force2=False):
    imm &= 0xFFFFFFFF
    signed = imm - (1 << 32) if imm & 0x80000000 else imm
    if -2048 <= signed <= 2047 and not force2:
        return [(s32(signed, 12) << 20) | (0 << 15) | (0b000 << 12) | (rd << 7) | OP_I]
    # lui takes the high 20 bits, rounded so the signed addi below corrects it
    upper = ((imm + 0x800) >> 12) & 0xFFFFF
    lower = imm - ((upper << 12) & 0xFFFFFFFF)
    lower = ((lower + 0x800) & 0xFFF) - 0x800  # sign-extend to 12 bits
    return [
        (upper << 12) | (rd << 7) | OP_LUI,
        ((lower & 0xFFF) << 20) | (rd << 15) | (0b000 << 12) | (rd << 7) | OP_I,
    ]


# ---------------------------------------------------------------- assembling
def literal(tok):
    """Return the value if `tok` is a plain number, else None."""
    try:
        return int(tok.strip(), 0)
    except ValueError:
        return None


def inst_size(mnem, ops):
    """Word count for pass 1. `li` is the only variable-length op: a numeric
    immediate is sized exactly, a label-valued one is always widened to
    lui+addi so its size does not depend on a not-yet-known address."""
    if mnem != "li":
        return 1
    imm = literal(ops[1]) if len(ops) > 1 else None
    return 2 if imm is None else li_words(imm)


def encode(mnem, ops, pc, labels):
    """Encode one mnemonic into a list of 32-bit words."""
    if mnem == "nop":
        return [XLEN_NOP]

    if mnem == "li":
        return encode_li(reg(ops[0]), const(ops[1], labels),
                         force2=literal(ops[1]) is None)

    if mnem == "j":  # j label  ->  jal x0, label
        mnem, ops = "jal", ["x0", ops[0]]

    if mnem in R_TYPE:
        f7, f3 = R_TYPE[mnem]
        rd, rs1, rs2 = reg(ops[0]), reg(ops[1]), reg(ops[2])
        return [(f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | OP_R]

    if mnem in I_TYPE:
        f3 = I_TYPE[mnem]
        rd, rs1 = reg(ops[0]), reg(ops[1])
        imm = s32(const(ops[2], labels), 12)
        return [(imm << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | OP_I]

    if mnem in SHIFT_I:
        f3, f7 = SHIFT_I[mnem]
        rd, rs1 = reg(ops[0]), reg(ops[1])
        sh = const(ops[2], labels)
        if not 0 <= sh <= 31:
            raise AsmError(f"shift amount {sh} out of range")
        return [(f7 << 25) | (sh << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | OP_I]

    if mnem in LOAD:
        f3 = LOAD[mnem]
        rd = reg(ops[0])
        off_t, base_t = split_mem(ops[1])
        imm = s32(const(off_t, labels), 12)
        return [(imm << 20) | (reg(base_t) << 15) | (f3 << 12) | (rd << 7) | OP_LOAD]

    if mnem in STORE:
        f3 = STORE[mnem]
        rs2 = reg(ops[0])
        off_t, base_t = split_mem(ops[1])
        imm = s32(const(off_t, labels), 12)
        return [((imm >> 5) << 25) | (rs2 << 20) | (reg(base_t) << 15) |
                (f3 << 12) | ((imm & 0x1F) << 7) | OP_STORE]

    if mnem in BRANCH:
        f3 = BRANCH[mnem]
        rs1, rs2 = reg(ops[0]), reg(ops[1])
        off = const(ops[2], labels) - pc
        if off & 1:
            raise AsmError("branch target is not 2-byte aligned")
        imm = s32(off, 13)
        return [(((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) |
                (rs2 << 20) | (rs1 << 15) | (f3 << 12) |
                (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | OP_BRANCH]

    if mnem == "jal":
        rd = reg(ops[0])
        off = const(ops[1], labels) - pc
        imm = s32(off, 21)
        return [(((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) |
                (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) |
                (rd << 7) | OP_JAL]

    if mnem == "jalr":
        rd = reg(ops[0])
        off_t, base_t = split_mem(ops[1]) if "(" in ops[1] else (ops[2], ops[1])
        imm = s32(const(off_t, labels), 12)
        return [(imm << 20) | (reg(base_t) << 15) | (0b000 << 12) | (rd << 7) | OP_JALR]

    if mnem in ("lui", "auipc"):
        rd = reg(ops[0])
        opc = OP_LUI if mnem == "lui" else OP_AUIPC
        return [((const(ops[1], labels) & 0xFFFFF) << 12) | (rd << 7) | opc]

    raise AsmError(f"unknown mnemonic '{mnem}'")


def parse(src):
    """Strip comments/blanks, return [(lineno, label|None, mnem|None, ops, org)]."""
    out = []
    for n, raw in enumerate(src.splitlines(), 1):
        line = raw.split("#", 1)[0].split("//", 1)[0].strip()
        while line:
            m = re.match(r"([A-Za-z_.][\w.]*)\s*:", line)
            if m:
                out.append((n, m.group(1), None, [], None))
                line = line[m.end():].strip()
                continue
            m = re.match(r"\.org\s+(\S+)", line)
            if m:
                out.append((n, None, None, [], int(m.group(1), 0)))
                break
            parts = line.split(None, 1)
            mnem = parts[0].lower()
            ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
            out.append((n, None, mnem, ops, None))
            break
    return out


def assemble(src):
    items = parse(src)

    # ---- pass 1: resolve label addresses ----
    labels, pc = {}, 0
    for lineno, label, mnem, ops, org in items:
        if org is not None:
            if org < pc:
                raise AsmError(f"line {lineno}: .org 0x{org:x} moves backwards")
            pc = org
        elif label is not None:
            labels[label] = pc
        elif mnem is not None:
            pc += 4 * inst_size(mnem, ops)

    # ---- pass 2: encode ----
    image, pc = {}, 0
    for lineno, label, mnem, ops, org in items:
        if org is not None:
            pc = org
        elif label is not None:
            # Guards against a pass-1 size estimate that disagrees with what
            # pass 2 actually emits, which would silently skew every branch.
            if labels[label] != pc:
                raise AsmError(
                    f"line {lineno}: label '{label}' resolved to "
                    f"0x{labels[label]:x} but lands at 0x{pc:x}")
        elif mnem is not None:
            try:
                words = encode(mnem, ops, pc, labels)
            except AsmError as e:
                raise AsmError(f"line {lineno}: {e}") from None
            for w in words:
                image[pc >> 2] = w & 0xFFFFFFFF
                pc += 4
    return image, labels


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    with open(sys.argv[1]) as f:
        image, labels = assemble(f.read())

    top = max(image) if image else 0
    with open(sys.argv[2], "w", newline="\n") as f:
        for i in range(top + 1):
            f.write(f"{image.get(i, XLEN_NOP):08x}\n")

    print(f"{sys.argv[1]} -> {sys.argv[2]}: {len(image)} instructions, "
          f"image 0x0000-0x{top * 4:04x}")
    for name, addr in sorted(labels.items(), key=lambda kv: kv[1]):
        print(f"  0x{addr:08x}  {name}")


if __name__ == "__main__":
    main()
