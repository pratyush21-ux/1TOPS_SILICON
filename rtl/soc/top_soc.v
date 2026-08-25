`include "rv32i_defines.vh"
// ============================================================
// top_soc : rv32i_core + uart_debug_unit
// Exposes instruction bus + a single (muxed) data bus to the
// outside (testbench / FPGA memory). The UART debug unit is a
// second master on the data bus, taking priority while active.
// ============================================================
module top_soc #(
  parameter CLKS_PER_BIT = 868
)(
  input  clk,
  input  rst_n,
  input  fetch_enable_i,
  input  [31:0] boot_addr_i,
  // serial
  input  rx_i,
  output tx_o,
  // instruction bus
  output        instr_req_o,
  input         instr_gnt_i,
  input         instr_rvalid_i,
  output [31:0] instr_addr_o,
  input  [31:0] instr_rdata_i,
  // unified data bus (core OR uart-debug master)
  output        data_req_o,
  input         data_gnt_i,
  input         data_rvalid_i,
  output        data_we_o,
  output [3:0]  data_be_o,
  output [31:0] data_addr_o,
  output [31:0] data_wdata_o,
  input  [31:0] data_rdata_i
);
  // ---- core <-> uart debug bus ----
  wire        dbg_req, dbg_gnt, dbg_rvalid, dbg_we;
  wire [14:0] dbg_addr;
  wire [31:0] dbg_wdata, dbg_rdata;

  // ---- uart debug memory master ----
  wire        um_req, um_gnt, um_rvalid, um_we;
  wire [3:0]  um_be;
  wire [31:0] um_addr, um_wdata;

  // ---- core data bus ----
  wire        c_req, c_gnt, c_rvalid, c_we;
  wire [3:0]  c_be;
  wire [31:0] c_addr, c_wdata;
wire [31:0] um_rdata_bus;
  // ---- data-bus arbiter: uart-debug master takes priority ----
  // Hold ownership from request until the matching rvalid so read data
  // (returned a cycle after grant) is routed back to the uart master.
  reg um_active;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)              um_active <= 1'b0;
    else if(um_req)         um_active <= 1'b1;
    else if(data_rvalid_i)  um_active <= 1'b0;
  end
  wire uart_owns = um_req | um_active;
  assign data_req_o   = uart_owns ? um_req   : c_req;
  assign data_we_o    = uart_owns ? um_we    : c_we;
  assign data_be_o    = uart_owns ? um_be    : c_be;
  assign data_addr_o  = uart_owns ? um_addr  : c_addr;
  assign data_wdata_o = uart_owns ? um_wdata : c_wdata;
  // grant/rvalid steered to whoever owns the bus
  assign um_gnt    = uart_owns ? data_gnt_i    : 1'b0;
  assign um_rvalid = uart_owns ? data_rvalid_i : 1'b0;
  assign c_gnt     = uart_owns ? 1'b0 : data_gnt_i;
  assign c_rvalid  = uart_owns ? 1'b0 : data_rvalid_i;
  assign um_rdata_bus = data_rdata_i; // shared read data
  

  rv32i_core #(.N_EXT_PERF_COUNTER(0), .RV32E(0)) core (
    .clk_i(clk), .rst_ni(rst_n), .clock_en_i(1'b1), .test_en_i(1'b0),
    .core_id_i(4'h0), .cluster_id_i(6'h0), .boot_addr_i(boot_addr_i),
    .instr_req_o(instr_req_o), .instr_gnt_i(instr_gnt_i), .instr_rvalid_i(instr_rvalid_i),
    .instr_addr_o(instr_addr_o), .instr_rdata_i(instr_rdata_i),
    .data_req_o(c_req), .data_gnt_i(c_gnt), .data_rvalid_i(c_rvalid),
    .data_we_o(c_we), .data_be_o(c_be), .data_wdata_o(c_wdata), .data_addr_o(c_addr),
    .data_rdata_i(data_rdata_i), .data_err_i(1'b0),
    .irq_i(1'b0), .irq_id_i(5'h0), .irq_ack_o(), .irq_id_o(),
    .debug_req_i(dbg_req), .debug_gnt_o(dbg_gnt), .debug_rvalid_o(dbg_rvalid),
    .debug_addr_i(dbg_addr), .debug_we_i(dbg_we), .debug_wdata_i(dbg_wdata),
    .debug_rdata_o(dbg_rdata), .debug_halted_o(), .debug_halt_i(1'b0), .debug_resume_i(1'b0),
    .fetch_enable_i(fetch_enable_i), .core_busy_o(), .ext_perf_counters_i(2'b0)
  );

  uart_debug_unit #(.CLKS_PER_BIT(CLKS_PER_BIT)) udbg (
    .clk(clk), .rst_n(rst_n), .rx_i(rx_i), .tx_o(tx_o),
    .dbg_req_o(dbg_req), .dbg_gnt_i(dbg_gnt), .dbg_rvalid_i(dbg_rvalid),
    .dbg_addr_o(dbg_addr), .dbg_we_o(dbg_we), .dbg_wdata_o(dbg_wdata), .dbg_rdata_i(dbg_rdata),
    .mem_req_o(um_req), .mem_gnt_i(um_gnt), .mem_rvalid_i(um_rvalid),
    .mem_we_o(um_we), .mem_be_o(um_be), .mem_addr_o(um_addr), .mem_wdata_o(um_wdata),
    .mem_rdata_i(um_rdata_bus)
  );
endmodule