#!/usr/bin/env python3
"""
iss_verify.py — Run the ISS golden model on all hex images and verify results.

Uses sw/iss.py (the project's RV32I instruction-set simulator) to execute each
.hex file and checks:
  1. The program halts (does not hit the instruction limit)
  2. status @0x000 == 0xC0DE0001 (done flag)
  3. trapmk @0x004 == 0x00000000 (no exception)
  4. Program-specific data checks (sorted array, fib sequence, gcd, etc.)

Usage:
    python scripts/iss_verify.py              # verify all hex files
    python scripts/iss_verify.py sort fib     # verify only sort and fib
    python scripts/iss_verify.py --verbose    # show data memory dumps
"""

import argparse
import importlib.util
import io
import sys
from pathlib import Path

# Force UTF-8 output on Windows to handle Unicode symbols (checkmarks, arrows)
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# Resolve project paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
HEX_DIR    = REPO_ROOT / "sw" / "hex"
ISS_TOOL   = REPO_ROOT / "sw" / "iss.py"

DONE_FLAG  = 0xC0DE0001


def load_iss():
    """Dynamically import iss.py."""
    spec = importlib.util.spec_from_file_location("iss", str(ISS_TOOL))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Expected results per test program
# ---------------------------------------------------------------------------
# Each entry: { "name": { "addr": expected_value, ... } }
# Addresses are byte addresses for data memory words.
# A value of None means "just check it's non-zero" (useful for partial checks).
EXPECTED = {
    "sort": {
        "description": "Bubble sort of 12 signed integers",
        "data": {
            0x100: -999, 0x104: -128, 0x108: -7,   0x10C: -1,
            0x110: 0,    0x114: 3,    0x118: 5,    0x11C: 19,
            0x120: 42,   0x124: 77,   0x128: 255,  0x12C: 1000,
        },
    },
    "fib": {
        "description": "First 12 Fibonacci numbers",
        "data": {
            0x100: 0,  0x104: 1,  0x108: 1,  0x10C: 2,
            0x110: 3,  0x114: 5,  0x118: 8,  0x11C: 13,
            0x120: 21, 0x124: 34, 0x128: 55, 0x12C: 89,
        },
    },
    "gcd": {
        "description": "GCD(1071, 462) = 21",
        "data": {
            0x100: 21,
        },
    },
    "rv32i_compliance": {
        "description": "Full RV32I instruction compliance (41 sub-tests)",
        "data": {
            # Pass count
            0x0FC: 41,
            # Each test result: 1 = pass
            0x100: 1, 0x104: 1, 0x108: 1, 0x10C: 1,   # add, add-neg, sub, sub-neg
            0x110: 1, 0x114: 1, 0x118: 1, 0x11C: 1,   # and, or, xor, sll
            0x120: 1, 0x124: 1, 0x128: 1, 0x12C: 1,   # srl, sra, slt-yes, slt-no
            0x130: 1,                                   # sltu
            0x134: 1, 0x138: 1, 0x13C: 1, 0x140: 1,   # addi, andi, ori, xori
            0x144: 1, 0x148: 1, 0x14C: 1, 0x150: 1,   # slti, sltiu, slli, srli
            0x154: 1,                                   # srai
            0x158: 1, 0x15C: 1, 0x160: 1, 0x164: 1,   # sw+lw, sb+lbu, lb-sext, sh+lhu
            0x168: 1,                                   # lh-sext
            0x16C: 1, 0x170: 1, 0x174: 1, 0x178: 1,   # beq-y, beq-n, bne, blt
            0x17C: 1, 0x180: 1, 0x184: 1,              # bge, bltu, bgeu
            0x188: 1, 0x18C: 1,                         # lui, auipc
            0x190: 1, 0x194: 1,                         # jal, jalr
            0x198: 1, 0x19C: 1, 0x1A0: 1,              # x0-immut, overflow, srl-neg
        },
    },
}

M32 = 0xFFFFFFFF


def sx32(v):
    """Sign-extend a 32-bit value."""
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def verify_hex(iss_mod, hex_path: Path, verbose: bool) -> tuple:
    """
    Run one hex file through the ISS and check results.
    Returns (pass_count, fail_count, test_name).
    """
    name = hex_path.stem
    passes, fails = 0, 0
    messages = []

    def check(condition, pass_msg, fail_msg):
        nonlocal passes, fails
        if condition:
            passes += 1
            if verbose:
                messages.append(f"    ✓ {pass_msg}")
        else:
            fails += 1
            messages.append(f"    ✗ {fail_msg}")

    # Load the hex image
    with open(hex_path) as f:
        image = {}
        for i, line in enumerate(f):
            line = line.strip()
            if line:
                image[i] = int(line, 16)

    # Run ISS
    iss = iss_mod.ISS(image, boot=0x80)
    n, why = iss.run(200000)

    messages.append(f"  {name}.hex: {n} instructions, stopped: {why}")

    # Basic checks
    check(why == "halted",
          f"Program halted normally after {n} instructions",
          f"Program did not halt cleanly (reason: {why})")

    status = iss.load(0x000)
    trapmk = iss.load(0x004)

    check(status == DONE_FLAG,
          "Done flag = 0xC0DE0001",
          f"Done flag = 0x{status:08X} (expected 0xC0DE0001)")

    check(trapmk == 0,
          "No exception (trap marker = 0)",
          f"EXCEPTION FIRED: trap marker = 0x{trapmk:08X}")

    # Program-specific data checks
    if name in EXPECTED:
        desc = EXPECTED[name]["description"]
        messages.append(f"    Checking: {desc}")
        for addr, exp_val in sorted(EXPECTED[name]["data"].items()):
            got = sx32(iss.load(addr))
            check(got == exp_val,
                  f"@0x{addr:04X} = {got}",
                  f"@0x{addr:04X} = {got}, expected {exp_val}")
    else:
        messages.append(f"    (no specific data checks defined for '{name}')")

    # Register dump in verbose mode
    if verbose:
        regs = " ".join(f"x{i}=0x{iss.x[i]:08X}" for i in range(1, 10))
        messages.append(f"    regs: {regs}")

    return passes, fails, name, messages


def main():
    parser = argparse.ArgumentParser(
        description="Verify hex images using the ISS golden model")
    parser.add_argument(
        "names", nargs="*",
        help="Base names (without .hex) to verify. "
             "If omitted, all .hex files in sw/hex/ are checked.")
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Show detailed pass/fail for each data check.")
    args = parser.parse_args()

    if not ISS_TOOL.is_file():
        sys.exit(f"ERROR: ISS not found: {ISS_TOOL}")
    if not HEX_DIR.is_dir():
        sys.exit(f"ERROR: hex directory not found: {HEX_DIR}\n"
                 f"       Run 'python scripts/assemble.py' first.")

    iss_mod = load_iss()

    # Discover hex files
    if args.names:
        hex_files = [HEX_DIR / f"{n}.hex" for n in args.names]
        missing = [h for h in hex_files if not h.exists()]
        if missing:
            sys.exit(f"ERROR: hex file(s) not found: "
                     f"{', '.join(h.name for h in missing)}\n"
                     f"       Run 'python scripts/assemble.py' first.")
    else:
        hex_files = sorted(HEX_DIR.glob("*.hex"))

    if not hex_files:
        sys.exit("No .hex files found. Run 'python scripts/assemble.py' first.")

    # Run verification
    print(f"\n{'='*60}")
    print(f" ISS Golden-Model Verification  ({len(hex_files)} test(s))")
    print(f"{'='*60}")

    total_pass, total_fail = 0, 0
    results = []

    for hf in hex_files:
        p, f, name, msgs = verify_hex(iss_mod, hf, args.verbose)
        total_pass += p
        total_fail += f
        results.append((name, p, f))
        for m in msgs:
            print(m)
        print()

    # Summary table
    print(f"{'='*60}")
    print(f" {'Test':<20s} {'Pass':>6s} {'Fail':>6s}  {'Status':<10s}")
    print(f" {'-'*20} {'-'*6} {'-'*6}  {'-'*10}")
    for name, p, f in results:
        status = "✓ PASS" if f == 0 else "✗ FAIL"
        print(f" {name:<20s} {p:>6d} {f:>6d}  {status}")
    print(f" {'-'*20} {'-'*6} {'-'*6}  {'-'*10}")
    print(f" {'TOTAL':<20s} {total_pass:>6d} {total_fail:>6d}  "
          f"{'✓ ALL PASSED' if total_fail == 0 else '✗ FAILURES'}")
    print(f"{'='*60}\n")

    sys.exit(1 if total_fail else 0)


if __name__ == "__main__":
    main()
