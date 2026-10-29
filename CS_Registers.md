# CSR Unit: `rv32i_cs_registers`

Control and Status Register (CSR) unit of the RV32IC core.
Source: `rtl/core/rv32i_cs_registers.v`

---

## 1. Overview

| Feature | Description |
|---|---|
| Privilege mode | Machine mode only (M-mode) |
| Machine CSRs | `mstatus`, `mtvec`, `mepc`, `mcause`, `mhartid` |
| Performance counters | 2 by default (cycles, instructions), configurable from 1 to 11 |
| CSR operations | Read, write, set bits, clear bits (`CSRRW`/`CSRRS`/`CSRRC` and their immediate forms) |
| Trap support | Saves PC, cause and interrupt-enable state on exception entry; restores them on `mret` |
| Unimplemented CSRs | Read as `0`; writes are ignored |

---

## 2. Parameters

| Parameter | Default | Range | Description |
|---|---|---|---|
| `N_PERF_CNT` | `2` | 1–11 | Number of built-in performance counters |
| `N_EXT_CNT` | `0` | ≥ 0 | Number of external event counters, placed after the built-in ones |

At the core level, `rv32i_core` passes `N_PERF_CNT` (default `2`) through to this unit.

| Configuration | `N_PERF_CNT` | Counters available |
|---|---|---|
| Default (tapeout) | 2 | Cycles, instructions |
| Full profiling | 11 | All events listed in Section 4.2 |

---

## 3. Machine-Mode CSR Map

| Address | Name | Access | Reset value | Description |
|---|---|---|---|---|
| `0x300` | `mstatus` | R/W | `0x0000_1800` | Machine status |
| `0x305` | `mtvec` | RO | `{boot_addr[31:8], 8'h00}` | Trap vector base |
| `0x341` | `mepc` | R/W | `0x0000_0000` | Exception program counter |
| `0x342` | `mcause` | R/W | `0x0000_0000` | Trap cause |
| `0xF14` | `mhartid` | RO | from `core_id_i` and `cluster_id_i` | Hardware thread ID |

### 3.1 `mstatus` (0x300)

| Bits | Field | Access | Description |
|---|---|---|---|
| 3 | `MIE` | R/W | Global machine interrupt enable |
| 7 | `MPIE` | R/W | Previous `MIE`, saved on trap entry |
| 12:11 | `MPP` | RO = `2'b11` | Previous privilege, fixed to M-mode |
| others | — | RO = 0 | Reserved |

### 3.2 `mtvec` (0x305)

| Bits | Field | Description |
|---|---|---|
| 31:8 | `BASE` | Comes from `boot_addr_i[31:8]` |
| 7:0 | — | Always `0` |

`mtvec` is read-only, so software cannot move the trap vector. The vector table is always 256-byte aligned at the boot address.

### 3.3 `mepc` (0x341)

| Bits | Field | Description |
|---|---|---|
| 31:0 | `EPC` | Address of the instruction that trapped |

The value is written by hardware on a trap (from `pc_if_i` or `pc_id_i`), and software can also read and write it. `mepc` drives the `mepc_o` output, which is the return address used by `mret`.

### 3.4 `mcause` (0x342)

| Bits | Field | Description |
|---|---|---|
| 31 | `INTERRUPT` | 1 = interrupt, 0 = exception |
| 4:0 | `CODE` | Exception or interrupt code |
| 30:5 | — | Always `0` |

Internally this is a 6-bit register: bit 5 of `csr_cause_i` maps to bit 31 of `mcause`.

### 3.5 `mhartid` (0xF14)

| Bits | Field |
|---|---|
| 10:5 | `cluster_id_i[5:0]` |
| 4 | `0` |
| 3:0 | `core_id_i[3:0]` |
| 31:11 | `0` |

---

## 4. Performance Counters

### 4.1 Performance counter CSR map

| Address | Name | Access | Reset value | Description |
|---|---|---|---|---|
| `0x780` | `PCCR0` | R/W | `0` | Counter 0: cycles |
| `0x781` | `PCCR1` | R/W | `0` | Counter 1: instructions |
| `0x782`–`0x79E` | — | RO = 0 | — | Not implemented in the default configuration |
| `0x79F` | `PCCR_ALL` | WO | — | A write updates all counters at once (reads return 0) |
| `0x7A0` | `PCER` | R/W | `0` | Per-counter enable, one bit per counter |
| `0x7A1` | `PCMR` | R/W | `2'b11` | Counter mode |

### 4.2 Counter events

| Index | Address | Event | Default (`N_PERF_CNT = 2`) |
|---:|---|---|:---:|
| 0 | `0x780` | Every clock cycle | ✔ |
| 1 | `0x781` | Instruction issued (`id_valid_i & is_decoding_i`) | ✔ |
| 2 | `0x782` | Reserved (never counts) | — |
| 3 | `0x783` | Reserved (never counts) | — |
| 4 | `0x784` | Instruction-fetch wait cycle (`imiss_i & ~pc_set_i`) | — |
| 5 | `0x785` | Load | — |
| 6 | `0x786` | Store | — |
| 7 | `0x787` | Jump | — |
| 8 | `0x788` | Branch | — |
| 9 | `0x789` | Taken branch | — |
| 10 | `0x78A` | Compressed instruction | — |

Counters 2–10 exist only when `N_PERF_CNT = 11`.

### 4.3 `PCER` (0x7A0): counter enable

| Bits | Description |
|---|---|
| `N_PERF_CNT-1 : 0` | `1` = counter *i* enabled |
| others | Always `0` |

### 4.4 `PCMR` (0x7A1): counter mode

| Bit | Field | Reset | Description |
|---|---|---|---|
| 0 | `GE` | 1 | Global enable for all counters |
| 1 | `SAT` | 1 | `1` = counters stop at `0xFFFF_FFFF`; `0` = counters wrap to 0 |

### 4.5 Counter behaviour

- A counter increments only when its event occurs **and** `PCER[i] = 1` **and** `PCMR.GE = 1`.
- **All counters are disabled after reset** (`PCER = 0`). Software must set `PCER` before counting starts.
- The count appears in the CSR **one cycle after** the event, because the increment request is registered.
- A software write to a counter has priority over an increment in the same cycle.
- Counters are 32 bits wide. At the maximum value they either saturate or wrap, depending on `PCMR.SAT`.

### 4.6 Software usage example

```asm
    csrwi  0x780, 0        # clear cycle counter
    csrwi  0x781, 0        # clear instruction counter
    csrwi  0x7A0, 3        # enable counters 0 and 1 (PCER)
    # ... code to measure ...
    csrwi  0x7A0, 0        # stop counting
    csrr   t0, 0x780       # t0 = cycles
    csrr   t1, 0x781       # t1 = instructions   ->  CPI = t0 / t1
```

---

## 5. CSR Access Operations

| `csr_op_i` | Operation | New value | Instruction |
|---|---|---|---|
| `2'b00` | NONE (read only) | unchanged | — |
| `2'b01` | WRITE | `wdata` | `CSRRW`, `CSRRWI` |
| `2'b10` | SET | `old \| wdata` | `CSRRS`, `CSRRSI` |
| `2'b11` | CLEAR | `old & ~wdata` | `CSRRC`, `CSRRCI` |

- Reads are combinational: `csr_rdata_o` returns the old value in the same cycle as the access.
- Read-only CSRs (`mtvec`, `mhartid`) ignore writes.

---

## 6. Trap Handling

### 6.1 Exception or interrupt entry (`csr_save_cause_i = 1`)

| Register | Update |
|---|---|
| `mepc` | `pc_if_i` if `csr_save_if_i`, otherwise `pc_id_i` if `csr_save_id_i` |
| `mstatus.MPIE` | ← `mstatus.MIE` |
| `mstatus.MIE` | ← `0` (interrupts disabled) |
| `mcause` | ← `csr_cause_i` |

If a trap entry and a software CSR write happen in the same cycle, the trap entry wins.

### 6.2 Return from trap (`mret`, `csr_restore_mret_i = 1`)

| Register | Update |
|---|---|
| `mstatus.MIE` | ← `mstatus.MPIE` |
| `mstatus.MPIE` | ← `1` |

---

## 7. Interface Signals

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock, active-low asynchronous reset |
| `core_id_i` | in | 4 | Core ID, used in `mhartid` |
| `cluster_id_i` | in | 6 | Cluster ID, used in `mhartid` |
| `boot_addr_i` | in | 24 | Boot address [31:8], used as `mtvec` |
| `csr_access_i` | in | 1 | CSR access valid |
| `csr_addr_i` | in | 12 | CSR address |
| `csr_wdata_i` | in | 32 | Write data |
| `csr_op_i` | in | 2 | Operation (NONE / WRITE / SET / CLEAR) |
| `csr_rdata_o` | out | 32 | Read data |
| `m_irq_enable_o` | out | 1 | `mstatus.MIE`, sent to the interrupt controller |
| `mepc_o` | out | 32 | `mepc`, used as the `mret` return address |
| `pc_if_i`, `pc_id_i` | in | 32 | PCs that can be saved into `mepc` |
| `csr_save_if_i`, `csr_save_id_i` | in | 1 | Select which PC to save |
| `csr_save_cause_i` | in | 1 | Trap entry |
| `csr_cause_i` | in | 6 | Trap cause |
| `csr_restore_mret_i` | in | 1 | `mret` executed |
| `id_valid_i`, `is_decoding_i` | in | 1 | Instruction-issued event (counter 1) |
| `is_compressed_i`, `imiss_i`, `pc_set_i`, `jump_i`, `branch_i`, `branch_taken_i`, `mem_load_i`, `mem_store_i` | in | 1 | Events for counters 4–10 (full configuration only) |
| `if_valid_i` | in | 1 | Not used; kept for port compatibility |
| `ext_counters_i` | in | `N_EXT_CNT` | External event inputs |
