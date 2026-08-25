# Source list for the RV32I core + UART debug SoC.
# Paths are relative to the repo root — run simulators from there.
#
# Note: rv32i_register_file.v is the flop-based version used for
# simulation. cluster_clock_gating.v is the live ICG wrapper.

# --- core pipeline & support ---
rtl/core/rv32i_core.v
rtl/core/rv32i_if_stage.v
rtl/core/rv32i_id_stage.v
rtl/core/rv32i_ex_block.v
rtl/core/rv32i_Alu.v
rtl/core/rv32i_decoder.v
rtl/core/rv32i_controller.v
rtl/core/rv32i_cs_registers.v
rtl/core/rv32i_load_store_unit.v
rtl/core/rv32i_register_file.v
rtl/core/rv32i_debug_unit.v
rtl/core/rv32i_int_controller.v
rtl/core/rv32i_prefetch_buffer.v
rtl/core/rv32i_fetch_fifo.v
rtl/core/rv32i_compressed_decoder.v
rtl/core/rv32i_imm_gen.v

# --- SoC integration (UART debug bridge + clock gating) ---
rtl/soc/cluster_clock_gating.v
rtl/soc/uart_rx.v
rtl/soc/uart_tx.v
rtl/soc/uart_debug_unit.v
rtl/soc/top_soc.v

# --- simulation memories ---
rtl/mem/instr_mem.v
rtl/mem/data_mem.v
