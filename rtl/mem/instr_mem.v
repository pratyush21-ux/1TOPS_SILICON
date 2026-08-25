// ============================================================
// instr_mem — instruction ROM for the rv32i instruction bus
//
// Handshake matches the core's OBI-style protocol:
//   req_i asserted -> gnt_o same cycle (this memory is never busy)
//   rvalid_o + rdata_o one cycle after the granted request
//
// The image is preloaded from HEXFILE with $readmemh, one 32-bit word
// per line starting at byte address 0, so line N holds address 4*N.
// Anything the file does not cover reads back as NOP, which keeps a
// runaway fetch from decoding garbage.
// ============================================================
module instr_mem #(
  parameter ADDR_W  = 12,          // byte-address bits -> 2**ADDR_W bytes
  parameter HEXFILE = ""
)(
  input             clk,
  input             rst_n,
  input             req_i,
  output            gnt_o,
  output reg        rvalid_o,
  input      [31:0] addr_i,
  output reg [31:0] rdata_o
);
  localparam WORDS = 1 << (ADDR_W - 2);
  localparam NOP   = 32'h00000013;   // addi x0, x0, 0

  reg [31:0] mem [0:WORDS-1];

  integer i;
  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = NOP;
    if (HEXFILE != "") $readmemh(HEXFILE, mem);
  end

  assign gnt_o = req_i;              // always ready to accept

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid_o <= 1'b0;
      rdata_o  <= NOP;
    end else begin
      rvalid_o <= req_i;
      if (req_i) rdata_o <= mem[addr_i[ADDR_W-1:2]];
    end
  end
endmodule
