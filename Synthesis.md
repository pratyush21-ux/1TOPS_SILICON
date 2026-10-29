# Synthesis Results and Findings: RV32IC Core on SkyWater SKY130

## Summary

The `rv32i_core` (RV32I + C extension) in `rtl/core/` was synthesized to the SkyWater 130 nm high-density standard-cell library (`sky130_fd_sc_hd`) using Yosys. The netlist mapped cleanly: the post-mapping `check` reported no errors and no warnings.

| Metric | Result |
|---|---|
| Total cell area | **69,957 µm² (0.070 mm²)** |
| Standard cells | **7,952** |
| Flip-flops | **542** |
| Latches | **1,025** (992 register-file storage, 33 clock-gate) |
| Combinational cells | 6,378 (+ 7 tie cells) |
| NAND2-equivalent gate count | ≈ 18.6 k GE |
| Estimated core area after layout | ≈ 0.100 mm² at 70 % utilization |

This puts the core in the expected range for a small 2-stage RV32IC microcontroller core. The register file is the largest block (40 %), followed by the fetch FIFO and the CSR unit (about 11 % each).

These results use the default configuration `N_PERF_CNT = 2` (cycle and instruction counters only). The original design had 11 hard-wired performance counters and measured 87,424 µm²; this change reduced the core area by 20 % (see Section 4).

---

## 1. Synthesis Setup

| Item | Value |
|---|---|
| Top module | `rv32i_core` (`N_PERF_CNT = 2`, `N_EXT_PERF_COUNTER = 0`, `RV32E = 0`) |
| RTL | 16 files in `rtl/core/` + `rtl/soc/cluster_clock_gating.v` |
| Tool | Yosys 0.70: `synth` → `dfflibmap` → `abc` |
| Liberty | `sky130_fd_sc_hd__tt_025C_1v80.lib` (typical corner, 25 °C, 1.80 V) |
| ABC delay target | 10 ns (100 MHz) |
| Excluded cells | `*lpflow*`, `*probe*`, `*clkdly*`, `*dlygate*`, `*dlymetal*`, `*_0` (the same set OpenLane excludes) |
| Tie cells | `sky130_fd_sc_hd__conb_1` |

Memories (`rtl/mem`) and the SoC wrapper (`rtl/soc/top_soc.v`, UART) are not included; the results cover the CPU core only.

---

## 2. Results

### 2.1 Area by cell category

| Category | Cells | Area (µm²) | Share |
|---|---:|---:|---:|
| Flip-flops | 542 | 13,578 | 19.4 % |
| Latches | 1,025 | 15,390 | 22.0 % |
| Combinational logic + tie cells | 6,385 | 40,989 | 58.6 % |
| **Total** | **7,952** | **69,957** | **100 %** |

Yosys reports a sequential share of 19.4 %, but that figure leaves out latches. With latches included, storage elements make up **41.4 %** of the core.

### 2.2 Sequential cells

| Cell | Function | Count | Area (µm²) |
|---|---|---:|---:|
| `sky130_fd_sc_hd__dfrtp_1` | D flip-flop, async reset | 530 | 13,263 |
| `sky130_fd_sc_hd__dfstp_1` | D flip-flop, async set | 12 | 315 |
| `sky130_fd_sc_hd__dlxtp_1` | Latch, active-high enable | 992 | 14,894 |
| `sky130_fd_sc_hd__dlxtn_1` | Latch, active-low enable | 33 | 495 |

409 of the 542 flops have a load enable. The SKY130 HD library has no enable flop with async reset, so each enable is built as a mux in front of a `dfrtp_1`. These muxes make up a large part of the 552 `mux2`/`mux2i` cells.

### 2.3 Area by module

| Module | Cells | Flops | Latches | Area (µm²) | Share |
|---|---:|---:|---:|---:|---:|
| `rv32i_register_file` | 2,843 | 32 | 992 | 27,901 | 39.9 % |
| `rv32i_fetch_fifo` | 879 | 131 | 0 | 7,955 | 11.4 % |
| `rv32i_cs_registers` | 914 | 110 | 0 | 7,540 | 10.8 % |
| `rv32i_load_store_unit` | 641 | 76 | 0 | 5,946 | 8.5 % |
| `rv32i_alu` | 747 | 0 | 0 | 4,493 | 6.4 % |
| `rv32i_debug_unit` | 354 | 68 | 0 | 3,578 | 5.1 % |
| `rv32i_if_stage` | 247 | 68 | 0 | 3,144 | 4.5 % |
| `rv32i_id_stage` | 427 | 2 | 0 | 2,526 | 3.6 % |
| `rv32i_prefetch_buffer` | 242 | 34 | 0 | 2,163 | 3.1 % |
| `rv32i_compressed_decoder` | 207 | 0 | 0 | 1,175 | 1.7 % |
| `cluster_clock_gating` (33 instances) | 99 | 0 | 33 | 908 | 1.3 % |
| `rv32i_decoder` | 172 | 0 | 0 | 927 | 1.3 % |
| `rv32i_controller` | 112 | 12 | 0 | 871 | 1.2 % |
| `rv32i_core` (top-level glue) | 58 | 1 | 0 | 574 | 0.8 % |
| `rv32i_int_controller` | 20 | 8 | 0 | 300 | 0.4 % |
| `rv32i_ex_block` | 1 | 0 | 0 | 6 | ~0 % |

Module areas exclude child instances. The hierarchical total (70,008 µm²) is 51 µm² higher than the flat result, because buffers at module boundaries are removed after flattening.

---

## 3. Findings

**F1. Storage dominates the core, not the datapath.**
The ALU, both decoders and the ID stage together take only 13 % of the area. Most of the core is state: the register file, fetch buffering and CSRs.

**F2. The latch-based register file is an efficient choice.**
The register file stores 31 × 32 bits in 992 latches (14,894 µm²). The same storage in flip-flops would take about 24,800 µm², so the latch design saves roughly 10,000 µm², about 14 % of the current core. The trade-off is 32 clock-gating cells and stricter timing and DFT handling in the backend.

**F3. The performance-counter overhead has been removed.**
In the original design, 11 hard-wired 32-bit counters made the CSR unit the second-largest block (24,998 µm², 28.6 % of the core). Two of the counters had inputs tied to `1'b0`, and all of them were disabled at reset and unused by software. The counter count is now a parameter that defaults to 2, which brings the CSR unit down to 7,540 µm² (110 flops).

**F4. The fetch path is now the largest block after the register file.**
The fetch FIFO (131 flops) and prefetch buffer (34 flops) together take 14.5 % of the area, more than the ALU and decoders combined. This makes the fetch path the next candidate for area reduction.

**F5. The instruction counter now counts issued instructions.**
Counter 1 previously counted `if_valid_i`, a fetch-stage handoff that can include flushed instructions. It now counts `id_valid_i & is_decoding_i`, which gives an accurate instruction count for CPI measurement.

**F6. The clock gate is not a library ICG cell.**
`cluster_clock_gating` maps to a generic latch plus AND gate (`dlxtn_1` + `and2`), so clock-tree synthesis will not recognize it as a clock gate. For place-and-route it should be mapped to `sky130_fd_sc_hd__dlclkp_1`.

**F7. All latch warnings are intended.**
The "Latch inferred" messages come only from `rv32i_register_file` and `cluster_clock_gating`; no unintended latches were found.

---

## 4. Area Optimization: Performance Counters

| Metric | Original (11 counters) | Current (`N_PERF_CNT = 2`) | Change |
|---|---:|---:|---:|
| Core area | 87,424 µm² | 69,957 µm² | **−17,467 µm² (−20.0 %)** |
| CSR unit area | 24,998 µm² | 7,540 µm² | −69.8 % |
| CSR unit flip-flops | 414 | 110 | −304 |
| Core flip-flops | 846 | 542 | −35.9 % |
| Standard cells | 9,926 | 7,952 | −19.9 % |
| NAND2-equivalent gates | ≈ 23.3 k | ≈ 18.6 k | −4.7 k |

**What changed:**
- `rv32i_cs_registers.v` has a new parameter `N_PERF_CNT` (1–11, default 2). `rv32i_core.v` passes it through.
- Counter 1 changed from `if_valid_i` to `id_valid_i & is_decoding_i`.
- The CSR SV testbench (`1TOPS_VERIFICATION/rv32i_cs_registers`) now follows the same setting through `Csr_tb_cfg.svh`, and `run_sim.py` has a new `--ncnt` option.

**Effect:**
- CPU behaviour is unchanged, because the counters never feed back into the pipeline.
- No existing software uses the performance-counter CSRs.
- Cycle and instruction counts remain available for benchmarking and CPI.
- The full 11-counter set is still available by setting `N_PERF_CNT = 11`.

---

## 5. Recommendations

| # | Action | Expected effect |
|---|---|---|
| 1 | Evaluate a shallower fetch FIFO. | Estimated 2,000–3,000 µm² less; impact on IPC must be checked in simulation |
| 2 | Put the debug unit behind a parameter for builds that do not need it. | Up to 3,600 µm² less |
| 3 | Map `cluster_clock_gating` to `sky130_fd_sc_hd__dlclkp_1` before place-and-route. | Correct clock-tree handling of the clock gates |
| 4 | Run static timing analysis (OpenSTA) on the netlist. | Confirms whether the 100 MHz target is met |

---

## 6. Limitations

- These are logic-synthesis results only. No timing analysis, place-and-route, wire-load or power analysis was performed.
- Only the typical corner (tt, 25 °C, 1.80 V) was used.
- Yosys/ABC typically reports 10–20 % more area than commercial synthesis tools.
- The post-layout area figures are estimates from target utilization, not from a real floorplan.

---

## 7. Reproducing the Results

Run from WSL:

```bash
cd /mnt/c/Users/LENOVO/Downloads/1TOPS_SILICON-main/1TOPS_SILICON-main/synth
bash run_synth.sh
```

The script takes the liberty file from `$PDK_ROOT` if that variable is set, and downloads it otherwise.

| File in `synth/` | Content |
|---|---|
| `rv32i_core_sky130.ys` | Yosys synthesis script |
| `run_synth.sh` | Wrapper script |
| `reports/area_flat.rpt` | Flat cell and area report |
| `reports/area_hier.rpt` | Per-module area report |
| `reports/pre_map_stat.rpt` | Generic cell and flop types before mapping |
| `reports/check.rpt` | Netlist check (clean) |
| `reports/yosys.log.gz` | Full synthesis log |
| `netlist/rv32i_core_sky130.v` | Flat gate-level netlist |
| `netlist/rv32i_core_sky130_hier.v` | Hierarchical gate-level netlist |
