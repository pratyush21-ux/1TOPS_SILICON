// ============================================================
// data_mem — byte-writable data RAM for the rv32i data bus
//
// Same handshake as instr_mem: combinational grant, registered rvalid.
// rvalid is returned for writes as well as reads, which is what the
// LSU and the UART debug master both wait on.
//
// Writes are applied at the grant cycle so a read issued in the very
// next cycle observes them.
// ============================================================
module data_mem #(
  parameter ADDR_W = 12            // byte-address bits -> 2**ADDR_W bytes
)(
  input             clk,
  input             rst_n,
  input             req_i,
  output            gnt_o,
  output reg        rvalid_o,
  input             we_i,
  input      [3:0]  be_i,
  input      [31:0] addr_i,
  input      [31:0] wdata_i,
  output reg [31:0] rdata_o
);
  localparam WORDS = 1 << (ADDR_W - 2);

  reg [31:0] mem [0:WORDS-1];
  wire [ADDR_W-3:0] widx = addr_i[ADDR_W-1:2];

  integer i;
  initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0;

  assign gnt_o = req_i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid_o <= 1'b0;
      rdata_o  <= 32'h0;
    end else begin
      rvalid_o <= req_i;
      if (req_i) begin
        if (we_i) begin
          if (be_i[0]) mem[widx][ 7: 0] <= wdata_i[ 7: 0];
          if (be_i[1]) mem[widx][15: 8] <= wdata_i[15: 8];
          if (be_i[2]) mem[widx][23:16] <= wdata_i[23:16];
          if (be_i[3]) mem[widx][31:24] <= wdata_i[31:24];
        end else begin
          rdata_o <= mem[widx];
        end
      end
    end
  end
endmodule
