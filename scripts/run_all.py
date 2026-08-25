#!/usr/bin/env python3
"""
run_all.py — Master automation: assemble → ISS verify → RTL simulate.

Chains together the full test flow for the zeroriscy RV32I core:

  1. Assemble:  all .s files in sw/asm/ → sw/hex/
  2. ISS:       run golden-model checks on every hex image
  3. RTL sim:   compile and simulate using Icarus Verilog or QuestaSim

Usage:
    python scripts/run_all.py                       # full flow (auto-detect simulator)
    python scripts/run_all.py --sim iverilog         # force Icarus Verilog
    python scripts/run_all.py --sim questa           # force QuestaSim
    python scripts/run_all.py --sim skip             # skip RTL simulation
    python scripts/run_all.py --test sort            # only assemble/verify/sim sort
    python scripts/run_all.py --verbose              # detailed ISS output
"""

import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# Force UTF-8 output on Windows to handle Unicode symbols (checkmarks, arrows)
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
SIM_DIR    = REPO_ROOT / "sim"
TB_DIR     = REPO_ROOT / "tb"
BUILD_DIR  = REPO_ROOT / "sim" / "build"   # for iverilog outputs


def banner(title: str):
    w = 60
    print(f"\n{'='*w}")
    print(f" {title}")
    print(f"{'='*w}")


def run_step(name: str, cmd: list, cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    """Run a subprocess, printing a header and streaming output."""
    print(f"\n--- {name} ---")
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    print(f"  cwd: {cwd}\n")
    result = subprocess.run(
        cmd, cwd=str(cwd),
        capture_output=True, text=True, timeout=300
    )
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    if check and result.returncode != 0:
        print(f"\n  ✗  {name} FAILED (exit code {result.returncode})")
    return result


# ---------------------------------------------------------------------------
# Step 1: Assemble
# ---------------------------------------------------------------------------
def step_assemble(test_names: list) -> bool:
    banner("Step 1: Assemble .s → .hex")
    cmd = [sys.executable, str(SCRIPT_DIR / "assemble.py")]
    if test_names:
        cmd.extend(test_names)
    result = run_step("Assemble", cmd, REPO_ROOT, check=False)
    return result.returncode == 0


# ---------------------------------------------------------------------------
# Step 2: ISS verification
# ---------------------------------------------------------------------------
def step_iss_verify(test_names: list, verbose: bool) -> bool:
    banner("Step 2: ISS Golden-Model Verification")
    cmd = [sys.executable, str(SCRIPT_DIR / "iss_verify.py")]
    if verbose:
        cmd.append("--verbose")
    if test_names:
        cmd.extend(test_names)
    result = run_step("ISS Verify", cmd, REPO_ROOT, check=False)
    return result.returncode == 0


# ---------------------------------------------------------------------------
# Step 3: RTL simulation
# ---------------------------------------------------------------------------
def detect_simulator() -> str:
    """Auto-detect available simulator."""
    if shutil.which("iverilog"):
        return "iverilog"
    if shutil.which("vsim"):
        return "questa"
    return "none"


def sim_iverilog(test_names: list) -> bool:
    """Compile and run with Icarus Verilog."""
    banner("Step 3: RTL Simulation (Icarus Verilog)")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # Read the filelist
    core_f = SIM_DIR / "core.f"
    with open(core_f) as f:
        src_files = [
            line.strip() for line in f
            if line.strip() and not line.strip().startswith("#")
        ]

    # Determine which testbenches to run
    testbenches = []
    if test_names:
        for name in test_names:
            tb_file = TB_DIR / f"tb_{name}.v"
            if tb_file.exists():
                testbenches.append((name, tb_file))
            else:
                print(f"  Warning: no testbench tb_{name}.v found, skipping RTL sim for '{name}'")
    else:
        for tb_file in sorted(TB_DIR.glob("tb_*.v")):
            name = tb_file.stem.replace("tb_", "")
            testbenches.append((name, tb_file))

    if not testbenches:
        print("  No testbenches found to simulate.")
        return True

    all_pass = True
    for name, tb_file in testbenches:
        vvp_out = BUILD_DIR / f"tb_{name}.vvp"

        # Compile
        compile_cmd = [
            "iverilog", "-g2005",
            "-I", str(REPO_ROOT / "rtl" / "core"),
            "-o", str(vvp_out),
        ] + [str(REPO_ROOT / sf) for sf in src_files] + [str(tb_file)]

        result = run_step(f"Compile tb_{name}", compile_cmd, REPO_ROOT, check=False)
        if result.returncode != 0:
            all_pass = False
            continue

        # Simulate
        sim_cmd = ["vvp", str(vvp_out)]
        result = run_step(f"Simulate tb_{name}", sim_cmd, REPO_ROOT, check=False)

        # Parse results
        output = result.stdout + result.stderr
        if "RESULT: ALL" in output and "PASSED" in output:
            print(f"  ✓  tb_{name}: ALL CHECKS PASSED")
        elif "FAIL" in output:
            print(f"  ✗  tb_{name}: FAILURES DETECTED")
            all_pass = False
        elif "TIMEOUT" in output:
            print(f"  ✗  tb_{name}: TIMED OUT")
            all_pass = False
        else:
            print(f"  ?  tb_{name}: could not parse result")

    return all_pass


def sim_questa(test_names: list) -> bool:
    """Run with QuestaSim/ModelSim using run.do."""
    banner("Step 3: RTL Simulation (QuestaSim/ModelSim)")
    cmd = ["vsim", "-c", "-do", "sim/run.do"]
    result = run_step("QuestaSim", cmd, REPO_ROOT, check=False)
    output = result.stdout + result.stderr
    if "RESULT: ALL" in output and "PASSED" in output:
        print("  ✓  All QuestaSim tests PASSED")
        return True
    else:
        print("  ✗  QuestaSim simulation had failures or did not complete")
        return False


def step_rtl_sim(sim_tool: str, test_names: list) -> bool:
    """Run RTL simulation with the specified tool."""
    if sim_tool == "skip":
        banner("Step 3: RTL Simulation (SKIPPED)")
        print("  Skipped by --sim skip")
        return True

    if sim_tool == "auto":
        sim_tool = detect_simulator()
        if sim_tool == "none":
            banner("Step 3: RTL Simulation (SKIPPED — no simulator found)")
            print("  Neither 'iverilog' nor 'vsim' found in PATH.")
            print("  Install Icarus Verilog or QuestaSim to run RTL simulation.")
            print("  Steps 1-2 (assemble + ISS verify) are still valid.\n")
            return True

    if sim_tool == "iverilog":
        return sim_iverilog(test_names)
    elif sim_tool == "questa":
        return sim_questa(test_names)
    else:
        print(f"  Unknown simulator: {sim_tool}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Master test automation: assemble → ISS → RTL sim")
    parser.add_argument(
        "--sim", choices=["auto", "iverilog", "questa", "skip"],
        default="auto",
        help="RTL simulator to use (default: auto-detect)")
    parser.add_argument(
        "--test", nargs="*", dest="test_names",
        help="Specific test names (e.g., sort fib). Default: all.")
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Verbose ISS output")
    parser.add_argument(
        "--skip-asm", action="store_true",
        help="Skip the assembly step (use existing hex files)")
    parser.add_argument(
        "--skip-iss", action="store_true",
        help="Skip the ISS verification step")
    args = parser.parse_args()

    test_names = args.test_names or []

    banner("RV32I Zeroriscy — Full Test Pipeline")
    print(f"  Repo root : {REPO_ROOT}")
    print(f"  Simulator : {args.sim}")
    print(f"  Tests     : {', '.join(test_names) if test_names else 'all'}")

    t0 = time.time()
    results = {}

    # Step 1
    if not args.skip_asm:
        results["Assemble"] = step_assemble(test_names)
        if not results["Assemble"]:
            print("\n  Assembly failed — cannot continue.")
            sys.exit(1)
    else:
        print("\n  Skipping assembly step (--skip-asm)")
        results["Assemble"] = True

    # Step 2
    if not args.skip_iss:
        results["ISS Verify"] = step_iss_verify(test_names, args.verbose)
    else:
        print("\n  Skipping ISS verification (--skip-iss)")
        results["ISS Verify"] = True

    # Step 3
    results["RTL Sim"] = step_rtl_sim(args.sim, test_names)

    # Final summary
    elapsed = time.time() - t0
    banner("Final Summary")
    all_pass = True
    for step_name, passed in results.items():
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"  {step_name:<20s}  {status}")
        if not passed:
            all_pass = False

    print(f"\n  Total time: {elapsed:.1f}s")
    if all_pass:
        print("  🎉 ALL STEPS PASSED")
    else:
        print("  ⚠  SOME STEPS FAILED — see output above")
    print()

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
