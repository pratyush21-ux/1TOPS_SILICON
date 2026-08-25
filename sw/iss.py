#!/usr/bin/env python3
"""
Tiny RV32I instruction-set simulator (dynamic golden model).

Independent golden model for the test programs: it runs the same .hex image
the RTL testbench loads, so a mismatch in simulation points at the core rather
than at the program or the assembler.

Works with ANY .hex file, not just sort. By default it auto-dumps every word
of data memory the program actually touched. Use flags to inspect specific
regions, dump strings, change the boot address, etc.

Usage:
    python iss.py PROG.hex [options]

Options:
    -n, --limit N       max instructions to execute        (default 200000)
    -b, --boot ADDR     boot / reset PC                     (default 0x80)
    -d, --dump A[:C]    dump C words (default 12) of data memory from addr A
                        repeatable, e.g.  -d 0x100:16 -d 0x200:4
    -s, --str  A[:C]    dump C bytes from addr A as ASCII   (default 32)
    -r, --regs          print all 32 registers (not just x1..x9)
    -a, --all           print every non-zero data word that was written
    -q, --quiet         suppress the auto memory dump
    --signed            show dumped words as signed decimals too

If no -d/-s/-a is given, every non-zero written word is shown (like --all).
ADDR and COUNT accept decimal or 0x-hex.  A:C means "start:count".
"""

import sys

M32 = 0xFFFFFFFF


def sx(v, bits):
    """Sign-extend the low `bits` of v."""
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


class ISS:
    def __init__(self, image, boot=0x80):
        self.imem = image          # dict: word index -> 32-bit value
        self.dmem = {}             # dict: word index -> 32-bit value
        self.written = set()       # word indices the program stored to
        self.x = [0] * 32
        self.pc = boot
        self.trapped = None

    def load(self, addr):
        return self.dmem.get(addr >> 2, 0)

    def store(self, addr, val, mask):
        idx = addr >> 2
        old = self.dmem.get(idx, 0)
        self.dmem[idx] = ((old & ~mask) | (val & mask)) & M32
        self.written.add(idx)

    def step(self):
        ins = self.imem.get(self.pc >> 2, 0)
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 0x1F
        rs2 = (ins >> 20) & 0x1F
        f7 = (ins >> 25) & 0x7F
        a, b = self.x[rs1], self.x[rs2]
        npc = self.pc + 4

        def wr(v):
            if rd:
                self.x[rd] = v & M32

        if op == 0x37:                                   # lui
            wr(ins & 0xFFFFF000)
        elif op == 0x17:                                 # auipc
            wr(self.pc + (ins & 0xFFFFF000))
        elif op == 0x6F:                                 # jal
            imm = sx((((ins >> 31) & 1) << 20) | (((ins >> 21) & 0x3FF) << 1) |
                     (((ins >> 20) & 1) << 11) | (((ins >> 12) & 0xFF) << 12), 21)
            wr(npc)
            npc = (self.pc + imm) & M32
        elif op == 0x67:                                 # jalr
            imm = sx(ins >> 20, 12)
            t = npc
            npc = (a + imm) & ~1 & M32
            wr(t)
        elif op == 0x63:                                 # branches
            imm = sx((((ins >> 31) & 1) << 12) | (((ins >> 25) & 0x3F) << 5) |
                     (((ins >> 8) & 0xF) << 1) | (((ins >> 7) & 1) << 11), 13)
            sa, sb = sx(a, 32), sx(b, 32)
            take = [sa == sb, sa != sb, None, None,
                    sa < sb, sa >= sb, a < b, a >= b][f3]
            if take is None:
                self.trapped = "illegal branch"
                return False
            if take:
                npc = (self.pc + imm) & M32
        elif op == 0x03:                                 # loads
            addr = (a + sx(ins >> 20, 12)) & M32
            w = self.load(addr)
            sh = (addr & 3) * 8
            if f3 == 0:   wr(sx(w >> sh, 8))
            elif f3 == 1: wr(sx(w >> sh, 16))
            elif f3 == 2: wr(w)
            elif f3 == 4: wr((w >> sh) & 0xFF)
            elif f3 == 5: wr((w >> sh) & 0xFFFF)
            else:
                self.trapped = "illegal load"
                return False
        elif op == 0x23:                                 # stores
            imm = sx((f7 << 5) | rd, 12)
            addr = (a + imm) & M32
            sh = (addr & 3) * 8
            if f3 == 0:   self.store(addr, b << sh, 0xFF << sh)
            elif f3 == 1: self.store(addr, b << sh, 0xFFFF << sh)
            elif f3 == 2: self.store(addr, b, M32)
            else:
                self.trapped = "illegal store"
                return False
        elif op in (0x13, 0x33):                         # ALU reg/imm
            imm = sx(ins >> 20, 12)
            src = b if op == 0x33 else imm
            sh = (src & 0x1F)
            if f3 == 0:
                wr(a - b if (op == 0x33 and f7 == 0x20) else a + src)
            elif f3 == 1: wr(a << sh)
            elif f3 == 2: wr(1 if sx(a, 32) < sx(src, 32) else 0)
            elif f3 == 3: wr(1 if a < (src & M32) else 0)
            elif f3 == 4: wr(a ^ src)
            elif f3 == 5: wr(sx(a, 32) >> sh if f7 == 0x20 else a >> sh)
            elif f3 == 6: wr(a | src)
            elif f3 == 7: wr(a & src)
        else:
            self.trapped = f"illegal opcode 0x{op:02x} at pc=0x{self.pc:08x}"
            return False

        self.pc = npc & M32
        return True

    def run(self, limit):
        for n in range(limit):
            prev = self.pc
            if not self.step():
                return n, "trap"
            if self.pc == prev:            # `j self` parking loop
                return n, "halted"
        return limit, "limit"


# ---------------------------------------------------------------- CLI parsing
def parse_addr_count(s, default_count):
    """'0x100:16' -> (0x100, 16); '0x100' -> (0x100, default_count)."""
    if ":" in s:
        a, c = s.split(":", 1)
        return int(a, 0), int(c, 0)
    return int(s, 0), default_count


def parse_args(argv):
    opts = {
        "path": None, "limit": 200000, "boot": 0x80,
        "dumps": [], "strs": [], "regs": False, "all": False,
        "quiet": False, "signed": False,
    }
    i = 0
    while i < len(argv):
        t = argv[i]
        if t in ("-n", "--limit"):
            i += 1; opts["limit"] = int(argv[i], 0)
        elif t in ("-b", "--boot"):
            i += 1; opts["boot"] = int(argv[i], 0)
        elif t in ("-d", "--dump"):
            i += 1; opts["dumps"].append(parse_addr_count(argv[i], 12))
        elif t in ("-s", "--str"):
            i += 1; opts["strs"].append(parse_addr_count(argv[i], 32))
        elif t in ("-r", "--regs"):
            opts["regs"] = True
        elif t in ("-a", "--all"):
            opts["all"] = True
        elif t in ("-q", "--quiet"):
            opts["quiet"] = True
        elif t == "--signed":
            opts["signed"] = True
        elif t in ("-h", "--help"):
            print(__doc__); sys.exit(0)
        elif t.startswith("-"):
            print(f"unknown option: {t}\n"); print(__doc__); sys.exit(1)
        else:
            if opts["path"] is None:
                opts["path"] = t
            else:  # bare number after path == old positional limit
                opts["limit"] = int(t, 0)
        i += 1
    if opts["path"] is None:
        print(__doc__); sys.exit(1)
    return opts


# ---------------------------------------------------------------- dumping
def dump_words(iss, base, count, signed):
    print(f"  data @0x{base:04x}:")
    for i in range(count):
        addr = base + 4 * i
        w = iss.load(addr)
        line = f"    0x{addr:04x} = 0x{w:08x}"
        if signed:
            line += f"  ({sx(w, 32)})"
        print(line)


def dump_str(iss, base, count):
    chars = []
    for i in range(count):
        w = iss.load((base + i) & ~3)
        byte = (w >> ((i & 3) * 8)) & 0xFF
        if byte == 0:
            break
        chars.append(chr(byte) if 32 <= byte < 127 else ".")
    print(f"  str  @0x{base:04x} = \"{''.join(chars)}\"")


def dump_written(iss, signed):
    if not iss.written:
        print("  (no data memory written)")
        return
    print("  data memory written:")
    for idx in sorted(iss.written):
        w = iss.dmem[idx]
        line = f"    0x{idx*4:04x} = 0x{w:08x}"
        if signed:
            line += f"  ({sx(w, 32)})"
        print(line)


def main():
    o = parse_args(sys.argv[1:])
    with open(o["path"]) as f:
        image = {i: int(line, 16) for i, line in
                 enumerate(l.strip() for l in f) if line}

    iss = ISS(image, boot=o["boot"])
    n, why = iss.run(o["limit"])
    print(f"{o['path']}: {n} instructions retired, stopped: {why}")
    if iss.trapped:
        print(f"  TRAP: {iss.trapped}")

    # status / trap markers (convention shared by all the test programs)
    st = iss.load(0x000)
    tm = iss.load(0x004)
    print(f"  status  @0x000 = 0x{st:08x}"
          f"{'  (DONE)' if st == 0xC0DE0001 else ''}")
    print(f"  trapmk  @0x004 = 0x{tm:08x}"
          f"{'  (TRAP FIRED!)' if tm else ''}")

    # memory views. Explicit -d/-s always print. -q only suppresses the
    # automatic "all writes" dump that happens when nothing was requested.
    for base, cnt in o["dumps"]:
        dump_words(iss, base, cnt, o["signed"])
    for base, cnt in o["strs"]:
        dump_str(iss, base, cnt)
    if o["all"] or (not o["quiet"] and not o["dumps"] and not o["strs"]):
        dump_written(iss, o["signed"])

    # registers
    rng = range(1, 32) if o["regs"] else range(1, 10)
    regs = " ".join(f"x{i}=0x{iss.x[i]:08x}" for i in rng)
    print("  regs: " + regs)


if __name__ == "__main__":
    main()