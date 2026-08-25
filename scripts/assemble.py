#!/usr/bin/env python3
"""
assemble.py — Batch-assemble all RV32I .s files into .hex images.

Scans sw/asm/ for assembly source files and runs the project's rv32i_asm.py
assembler on each one, placing the output hex in sw/hex/.

Usage:
    python scripts/assemble.py              # assemble all
    python scripts/assemble.py sort fib     # assemble only sort.s and fib.s
    python scripts/assemble.py --clean      # delete all hex files first
"""

import argparse
import io
import os
import sys
import importlib.util
from pathlib import Path

# Force UTF-8 output on Windows to handle Unicode symbols (checkmarks, arrows)
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# Resolve project paths (script lives in <repo>/scripts/)
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
ASM_DIR    = REPO_ROOT / "sw" / "asm"
HEX_DIR    = REPO_ROOT / "sw" / "hex"
ASM_TOOL   = REPO_ROOT / "sw" / "rv32i_asm.py"


def load_assembler():
    """Dynamically import rv32i_asm.py so we can call assemble() directly."""
    spec = importlib.util.spec_from_file_location("rv32i_asm", str(ASM_TOOL))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def assemble_file(asm_mod, src: Path, dst: Path) -> bool:
    """Assemble one .s file → .hex.  Returns True on success."""
    try:
        with open(src) as f:
            image, labels = asm_mod.assemble(f.read())

        top = max(image) if image else 0
        dst.parent.mkdir(parents=True, exist_ok=True)
        with open(dst, "w", newline="\n") as f:
            for i in range(top + 1):
                f.write(f"{image.get(i, asm_mod.XLEN_NOP):08x}\n")

        n_inst = len(image)
        label_list = ", ".join(
            f"{name}=0x{addr:04x}"
            for name, addr in sorted(labels.items(), key=lambda kv: kv[1])
            if not name.startswith("_")
        )
        print(f"  ✓  {src.name:20s} → {dst.name:20s}  "
              f"({n_inst} instrs, 0x0000–0x{top*4:04x})")
        if label_list:
            print(f"     labels: {label_list}")
        return True

    except Exception as e:
        print(f"  ✗  {src.name}: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Batch-assemble RV32I .s files → .hex images")
    parser.add_argument(
        "names", nargs="*",
        help="Base names (without .s) to assemble. "
             "If omitted, all .s files in sw/asm/ are assembled.")
    parser.add_argument(
        "--clean", action="store_true",
        help="Delete all .hex files in sw/hex/ before assembling.")
    args = parser.parse_args()

    # Sanity checks
    if not ASM_DIR.is_dir():
        sys.exit(f"ERROR: assembly source directory not found: {ASM_DIR}")
    if not ASM_TOOL.is_file():
        sys.exit(f"ERROR: assembler not found: {ASM_TOOL}")

    # Clean
    if args.clean:
        for h in HEX_DIR.glob("*.hex"):
            h.unlink()
            print(f"  deleted {h.name}")

    # Discover sources
    if args.names:
        sources = [ASM_DIR / f"{n}.s" for n in args.names]
        missing = [s for s in sources if not s.exists()]
        if missing:
            sys.exit(f"ERROR: source(s) not found: "
                     f"{', '.join(s.name for s in missing)}")
    else:
        sources = sorted(ASM_DIR.glob("*.s"))

    if not sources:
        sys.exit("No .s files found in sw/asm/")

    # Load assembler module
    asm_mod = load_assembler()
    HEX_DIR.mkdir(parents=True, exist_ok=True)

    # Assemble
    print(f"\n{'='*60}")
    print(f" Assembling {len(sources)} file(s)")
    print(f"{'='*60}")
    ok, fail = 0, 0
    for src in sources:
        dst = HEX_DIR / src.with_suffix(".hex").name
        if assemble_file(asm_mod, src, dst):
            ok += 1
        else:
            fail += 1

    print(f"\n{'='*60}")
    if fail == 0:
        print(f" ALL {ok} assemblies PASSED")
    else:
        print(f" {ok} passed, {fail} FAILED")
    print(f"{'='*60}\n")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
