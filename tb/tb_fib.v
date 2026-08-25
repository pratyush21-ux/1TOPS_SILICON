`timescale 1ns/1ps
// ============================================================
//  tb_fib — full-core test for rv32i (iterative Fibonacci)
//  Loads sw/hex/fib.hex into the ROM, runs to the 0xC0DE0001 done flag,
//  then checks the result region two ways: backdoor peek of
//  data_mem and UART-debug read-back over the serial link.
// ============================================================
module tb_fib;

  localparam CPB    = 8;
  localparam NCHK   = 12;
  localparam ARRAY  = 32'h0000_0100;
  localparam STATUS = 32'h0000_0000;
  localparam TRAPMK = 32'h0000_0004;
  localparam DONE   = 32'hC0DE_0001;

  reg clk = 0, rst_n = 0, fetch_enable = 0;
  reg rx = 1;
  wire tx;

  wire        instr_req, instr_gnt, instr_rvalid;
  wire [31:0] instr_addr, instr_rdata;
  wire        data_req, data_gnt, data_rvalid, data_we;
  wire [3:0]  data_be;
  wire [31:0] data_addr, data_wdata, data_rdata;

  always #5 clk = ~clk;

  top_soc #(.CLKS_PER_BIT(CPB)) dut (
    .clk(clk), .rst_n(rst_n),
    .fetch_enable_i(fetch_enable), .boot_addr_i(32'h0),
    .rx_i(rx), .tx_o(tx),
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata),
    .data_req_o(data_req), .data_gnt_i(data_gnt), .data_rvalid_i(data_rvalid),
    .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr),
    .data_wdata_o(data_wdata), .data_rdata_i(data_rdata)
  );

  instr_mem #(.ADDR_W(12), .HEXFILE("sw/hex/fib.hex")) imem (
    .clk(clk), .rst_n(rst_n),
    .req_i(instr_req), .gnt_o(instr_gnt), .rvalid_o(instr_rvalid),
    .addr_i(instr_addr), .rdata_o(instr_rdata)
  );

  data_mem #(.ADDR_W(12)) dmem (
    .clk(clk), .rst_n(rst_n),
    .req_i(data_req), .gnt_o(data_gnt), .rvalid_o(data_rvalid),
    .we_i(data_we), .be_i(data_be), .addr_i(data_addr),
    .wdata_i(data_wdata), .rdata_o(data_rdata)
  );

  reg signed [31:0] expected [0:NCHK-1];
  initial begin
    expected[0]=0;  expected[1]=1;  expected[2]=1;  expected[3]=2;
    expected[4]=3;  expected[5]=5;  expected[6]=8;  expected[7]=13;
    expected[8]=21; expected[9]=34; expected[10]=55; expected[11]=89;
  end

  integer pass = 0, fail = 0;
  task check32(input [31:0] got, input [31:0] exp, input [255:0] name);
    begin
      if (got === exp) begin
        $display("  PASS  %0s = %0d (0x%08h)", name, $signed(got), got);
        pass = pass + 1;
      end else begin
        $display("  FAIL  %0s = %0d (0x%08h), expected %0d (0x%08h)",
                 name, $signed(got), got, $signed(exp), exp);
        fail = fail + 1;
      end
    end
  endtask

  task check_arr(input integer idx, input [31:0] got, input [31:0] exp,
                 input [63:0] via);
    begin
      if (got === exp) begin
        $display("  PASS  a[%0d] %0s = %0d", idx, via, $signed(got));
        pass = pass + 1;
      end else begin
        $display("  FAIL  a[%0d] %0s = %0d (0x%08h), expected %0d",
                 idx, via, $signed(got), got, $signed(exp));
        fail = fail + 1;
      end
    end
  endtask

  localparam real BIT_T = CPB * 10.0;
  task send_byte(input [7:0] b);
    integer i;
    begin
      rx = 1'b0; #(BIT_T);
      for (i = 0; i < 8; i = i + 1) begin rx = b[i]; #(BIT_T); end
      rx = 1'b1; #(BIT_T);
      #(BIT_T);
    end
  endtask

  reg [7:0] rxq [0:1023];
  integer wptr = 0, rptr = 0;
  reg mon_en = 0;
  initial begin
    @(posedge mon_en);
    forever begin : moncap
      reg [7:0] b; integer i;
      @(negedge tx);
      #(BIT_T + BIT_T/2.0);
      for (i = 0; i < 8; i = i + 1) begin b[i] = tx; #(BIT_T); end
      rxq[wptr] = b; wptr = wptr + 1;
      #(BIT_T/2.0);
    end
  end

  task recv_byte(output [7:0] b);
    begin
      while (rptr >= wptr) #(BIT_T/4.0);
      b = rxq[rptr]; rptr = rptr + 1;
    end
  endtask

  reg [7:0] r0, r1, r2, r3;
  task uart_read_mem(input [31:0] addr, output [31:0] data);
    begin
      send_byte(8'h40);
      send_byte(addr[7:0]);   send_byte(addr[15:8]);
      send_byte(addr[23:16]); send_byte(addr[31:24]);
      recv_byte(r0); recv_byte(r1); recv_byte(r2); recv_byte(r3);
      data = {r3, r2, r1, r0};
    end
  endtask

  task uart_read_gpr(input [4:0] idx, output [31:0] data);
    begin
      send_byte(8'h10); send_byte({3'b0, idx});
      recv_byte(r0); recv_byte(r1); recv_byte(r2); recv_byte(r3);
      data = {r3, r2, r1, r0};
    end
  endtask

  integer cycles = 0, i;
  reg [31:0] got, status, trapmk;
  reg done_seen = 0;
  always @(posedge clk) if (rst_n) cycles = cycles + 1;

  initial begin
    $display("======= rv32i full-core test: fib =======");
    repeat (6) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    fetch_enable = 1;
    mon_en = 1;

    while (!done_seen && cycles < 100000) begin
      @(posedge clk);
      if (dmem.mem[STATUS >> 2] === DONE) done_seen = 1;
    end

    if (!done_seen) begin
      $display("FAIL  no done flag: status=0x%08h after %0d cycles",
               dmem.mem[STATUS >> 2], cycles);
      fail = fail + 1;
    end else begin
      $display("Program finished after %0d cycles.", cycles);
    end

    $display("--- A. data memory (backdoor) ---");
    status = dmem.mem[STATUS >> 2];
    trapmk = dmem.mem[TRAPMK >> 2];
    check32(status, DONE, "status flag");
    check32(trapmk, 32'h0, "trap marker (0 = no exception)");
    for (i = 0; i < NCHK; i = i + 1) begin
      got = dmem.mem[(ARRAY >> 2) + i];
      check_arr(i, got, expected[i], "backdoor");
    end

    $display("--- B. UART debug read-back ---");
    send_byte(8'h01);
    recv_byte(r0);
    if (r0 == 8'h90) begin
      $display("  PASS  HALT acknowledged"); pass = pass + 1;
    end else begin
      $display("  FAIL  HALT ack = 0x%02h (expected 0x90)", r0); fail = fail + 1;
    end

    send_byte(8'h04);
    recv_byte(r0);
    if (r0[0]) begin
      $display("  PASS  core reports halted"); pass = pass + 1;
    end else begin
      $display("  FAIL  core not halted, status=0x%02h", r0); fail = fail + 1;
    end

    for (i = 0; i < NCHK; i = i + 1) begin
      uart_read_mem(ARRAY + 4*i, got);
      check_arr(i, got, expected[i], "via UART");
    end

    $display("=============================================");
    if (fail == 0) $display("RESULT: ALL %0d CHECKS PASSED", pass);
    else           $display("RESULT: %0d passed, %0d FAILED", pass, fail);
    $display("=============================================");
    $finish;
  end

  initial begin
    #20_000_000;
    $display("TIMEOUT: %0d passed, %0d failed before timeout", pass, fail);
    $finish;
  end
endmodule
