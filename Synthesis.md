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

---

## 2. Results

### 2.1 Area by cell category

| Category | Cells | Area (µm²) | Share |
|---|---:|---:|---:|
| Flip-flops | 542 | 13,578 | 19.4 % |
| Latches | 1,025 | 15,390 | 22.0 % |
| Combinational logic + tie cells | 6,385 | 40,989 | 58.6 % |
| **Total** | **7,952** | **69,957** | **100 %** |

### 2.2 Sequential cells

| Cell | Function | Count | Area (µm²) |
|---|---|---:|---:|
| `sky130_fd_sc_hd__dfrtp_1` | D flip-flop, async reset | 530 | 13,263 |
| `sky130_fd_sc_hd__dfstp_1` | D flip-flop, async set | 12 | 315 |
| `sky130_fd_sc_hd__dlxtp_1` | Latch, active-high enable | 992 | 14,894 |
| `sky130_fd_sc_hd__dlxtn_1` | Latch, active-low enable | 33 | 495 |

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

