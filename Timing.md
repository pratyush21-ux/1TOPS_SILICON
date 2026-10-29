# Timing Analysis and GF 28 nm Projection: RV32IC Core

## Summary

| | Result |
|---|---|
| Target | **500 MHz (2.0 ns)** on GlobalFoundries 28 nm |
| Measured on Sky130 HD (tt, 1.8 V, pre-layout) | **≈ 95 MHz** (critical path 10.5 ns ≈ 131 FO4) |
| Projected on GF 28 nm, typical corner | ≈ 340–510 MHz |
| Projected on GF 28 nm, sign-off (slow) corner | ≈ 250–380 MHz (≈ 310–470 MHz with commercial synthesis) |
| Projected GF 28 nm cell area | ≈ 7,500–10,300 µm² as synthesized, ≈ 9,000–14,300 µm² once closed for timing |
| **500 MHz verdict** | **Not reachable at sign-off with the current RTL.** The critical path must be cut (see Section 5). |

The 28 nm numbers are **projections**. The GF 28 nm libraries are under NDA and were not available here. Sky130 results are converted using FO4 delay and NAND2-equivalent gate area (Section 4), so expect at least ±30 % error until the real GF library is used.

---

## 1. Method

| Item | Setting |
|---|---|
| Netlist | `rv32i_core` (default `N_PERF_CNT = 2`), flattened, mapped by Yosys/ABC with a 2.0 ns target |
| Library | `sky130_fd_sc_hd__tt_025C_1v80` (only corner available here) |
| Timer | NLDM graph-based STA (`synth/sta/sta.py`), see note below |
| Clock | 2.0 ns, ideal (no skew or latency), 0.10 ns clock slew; gated clocks treated as ideal |
| Wires | None in the baseline; sensitivity runs with 1–2 fF per fanout |
| High-fanout nets | Modelled as an ideal `buf_4` tree above 30 fF, standing in for the buffering place-and-route would insert |
| Paths checked | Flop → flop, flop → latch (register file, clock-gate enables), latch → flop, inputs → outputs |
| Not checked | Hold, async reset recovery, latch time-borrowing, clock-tree skew |

**Why not OpenSTA.** OpenSTA has no package in this environment, and building it from source was not permitted. Timing was instead computed with a small Python STA that reads the same Liberty tables (cell delay and slew vs. input slew and load, setup constraints) and propagates rise/fall arrivals through the netlist. It is a pre-layout estimate, not sign-off. An OpenSTA script and SDC are included (`synth/sta/run_opensta.tcl`, `core_500MHz.sdc`) to run in WSL once OpenSTA is installed. That script is **untested**.

---

## 2. Sky130 Results (500 MHz constraint)

| Metric | Value |
|---|---|
| Worst negative slack (WNS) | −8.52 ns |
| Total negative slack (TNS) | −2,296 ns |
| Failing endpoints | 501 of 1,565 |
| Minimum period | 10.52 ns → **≈ 95 MHz** |
| Area (500 MHz-targeted synthesis, flat) | 67,823 µm² |

### Sensitivity

| Variant | Min period | Fmax |
|---|---:|---:|
| Baseline (buffered high fanout, no wires) | 10.52 ns | 95 MHz |
| Debug-unit start points included | 10.76 ns | 93 MHz |
| No fanout buffering | 11.46 ns | 87 MHz |
| + 1 fF wire per fanout | 12.43 ns | 80 MHz |
| + 2 fF wire per fanout | 14.19 ns | 70 MHz |

Realistic Sky130 pre-CTS range: **≈ 70–95 MHz at the typical corner.**

---

## 3. Critical Path

Start: `id_stage_i.decoder_i.instr_rdata_i` (instruction register, ID stage).
End: `rv32i_if_stage.prefetch_i.fifo_i.addr_Q` (fetch FIFO address).
Logic depth: 46 cells.

Segment boundaries below are approximate, read from the cell types along the path.

| Segment | Arrival (ns) | Share | Logic |
|---|---:|---:|---|
| Clock → Q of instruction register | 0.69 | 7 % | `dfrtp_1` |
| Register-file read | 0.69 → 2.54 | 18 % | address decode + latch read mux |
| ALU adder / comparator | 2.54 → 6.64 | 39 % | 32-bit carry chain (`maj3`, `a21oi`/`o21ai`, `a311oi`/`o311ai`) |
| Branch decision | 6.64 → 7.44 | 8 % | `branch_set_n` |
| Fetch redirect: target / prefetch address increment | 7.44 → 10.43 | 28 % | `nand4`/`nor4` carry chain into FIFO address |
| Setup | 0.10 | 1 % | |

The whole sequence (register-file read → ALU compare → branch decision → new fetch address) runs in **one cycle**. That is the cost of the 2-stage (zero-riscy style) pipeline.

**Other long paths:**
- `instr_addr_o` (to instruction memory) is combinational from the branch decision and arrives at **7.4 ns**. At SoC level, the instruction-memory access time is added on top of this, inside the same cycle.
- Register-file write-enable decode to the clock-gate latches: 4.0 ns.
- The CSR unit and load/store unit are not on the critical path.

---

## 4. Projection to GF 28 nm

### 4.1 Timing

The path is converted to FO4 inverter delays: Sky130 HD tt FO4 = **80.5 ps** (computed from `inv_1` in the library), so the critical path is 10.52 ns / 80.5 ps ≈ **131 FO4**.

| Assumption | Value | Basis |
|---|---|---|
| GF 28 nm FO4 at typical corner | 12 / 15 / 18 ps | Fast (HPP-like) / mid / low-power (SLP-like); assumed |
| Extra wire delay at 28 nm | +25 % | Wires take a bigger share at 28 nm than at 130 nm; assumed |
| Slow (sign-off) corner derate | × 1.35 | Typical ss vs. tt ratio; assumed |
| Commercial synthesis (Genus / DC) gain | −20 % delay | Timing-driven restructuring vs. Yosys/ABC; assumed |

| GF 28 nm FO4 | tt period | tt Fmax | ss period | ss Fmax | ss with commercial tool |
|---:|---:|---:|---:|---:|---:|
| 12 ps | 1.96 ns | **510 MHz** | 2.65 ns | 380 MHz | 470 MHz |
| 15 ps | 2.45 ns | 410 MHz | 3.31 ns | 300 MHz | 380 MHz |
| 18 ps | 2.94 ns | 340 MHz | 3.97 ns | 250 MHz | 315 MHz |

For 500 MHz at the slow corner with the fast (12 ps) library, the path must be at most about **100 FO4** (2.0 ns ÷ (12 ps × 1.25 × 1.35)), and less with a slower library. The current path is ≈ 131 FO4.

### 4.2 Area

| Item | Value |
|---|---|
| Sky130 cell area (relaxed synthesis) | 69,957 µm² = **18.6 k NAND2-equivalent gates** (NAND2_1 = 3.754 µm²) |
| GF 28 nm NAND2 area | 0.40–0.55 µm² (9-track to 12-track library; assumed) |
| **GF 28 nm cell area, relaxed** | **≈ 7,500–10,300 µm²** |
| Overhead to close 500 MHz (upsizing, buffering) | +20–40 % (assumed) |
| **GF 28 nm cell area at 500 MHz** | **≈ 9,000–14,300 µm²** |
| Core area at 70 % utilization | ≈ 0.013–0.020 mm² |

Flop and latch counts do not depend on the technology: 542 flops and 1,025 latches.

### 4.3 Power (order of magnitude only)

| Item | Value |
|---|---|
| Sky130 total input-pin capacitance | 52.7 pF (clock pins 2.8 pF) |
| Scaled to 28 nm (× 0.25), wire and internal power included (× 2–3) | ≈ 25–40 pF switched capacitance |
| Activity | 0.1 for data, 1.0 for clock |
| Supply / frequency | 0.9 V / 500 MHz |
| **Dynamic power** | **≈ 1.5–5 mW (≈ 3–10 µW/MHz)** |
| Leakage | Depends on threshold-voltage mix: µW range (HVT) to tens of µW (LVT) |

This is a back-of-envelope estimate. Real numbers need the GF library and switching activity from simulation.

---

## 5. Reaching 500 MHz

| # | Change | Expected effect | Cost |
|---|---|---|---|
| 1 | **Register the branch decision.** Add a pipeline flop after `branch_set` and resolve the fetch redirect in the next cycle. | Longest stage drops from ≈ 131 to ≈ 95 FO4 (≈ +40 % Fmax) | +1 cycle per taken branch (higher CPI) |
| 2 | **Dedicated branch comparator.** Use an equality / fast magnitude compare instead of the full ALU adder result. | Removes most of the 4.1 ns adder segment from the branch path | Small area increase |
| 3 | **Register the fetch address (`instr_addr_o`).** | Gives instruction-memory access a full cycle; required at 500 MHz | Fetch logic change |
| 4 | **Fast adder.** Use a parallel-prefix (Kogge-Stone / Brent-Kung) ALU adder; commercial tools usually infer one. | Adder segment ≈ 4.1 → ≈ 2 ns-equivalent | More area in the ALU |
| 5 | **LVT cells on critical paths, commercial synthesis.** | 10–25 % faster | Leakage |

Changes 1 + 3 (or 2 + 3 + 4) should bring the core to about 90–100 FO4, which is about 500 MHz at the GF 28 nm slow corner with a fast library. **Confirm with the real GF library before committing to an RTL change.**

---

## 6. Limitations

- Pre-layout only: ideal clocks, no clock-tree skew, no extracted wires. Wire impact is covered only by the sensitivity runs.
- Sky130 typical corner only. The slow corner was not available here.
- Hold, recovery/removal and latch time-borrowing were not analysed.
- The Python STA is not sign-off. Run OpenSTA (or Tempus / PrimeTime) on the real GF 28 nm netlist.
- Every 28 nm figure depends on the assumptions in Section 4. Replace them with GF library data when available.

---

## 7. Reproducing the Results

From WSL, after `synth/run_synth.sh` has fetched the library:

```bash
cd synth/sta
bash run_sta_lite.sh        # Python STA, writes reports/sta_500MHz_tt.rpt
sta -exit run_opensta.tcl   # OpenSTA (if installed); uses core_500MHz.sdc
```

| File in `synth/sta/` | Content |
|---|---|
| `run_sta_lite.sh` | Flattened 500 MHz synthesis + Python STA |
| `sta.py`, `libparse.py` | Python STA and Liberty parser |
| `core_500MHz.sdc` | Constraints (2.0 ns clock, 20 % I/O delay) |
| `run_opensta.tcl` | OpenSTA script (untested) |
| `reports/sta_500MHz_tt.rpt` | Main timing report with the top 5 paths |
| `reports/sta_500MHz_tt_incl_debug.rpt` | Same run with debug-unit start points included |
| `reports/sta_500MHz_tt_wire1fF.rpt` | Same run with 1 fF wire per fanout |
| `reports/area_flat_500MHz_target.rpt` | Area of the 500 MHz-targeted netlist |
