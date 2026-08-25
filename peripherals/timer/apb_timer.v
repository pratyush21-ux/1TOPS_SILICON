// ============================================================
// apb_timer — 32-bit timer/counter with APB slave interface
//
// Features:
//   - 32-bit free-running counter with configurable prescaler
//   - Compare-match interrupt (counter == compare value)
//   - Overflow interrupt
//   - One-shot and continuous modes
//   - Enable/disable control
//
// Register map (byte addresses):
//   0x00  TIMER_CTRL    R/W   control register
//         [0]   EN       — timer enable
//         [1]   IRQ_EN   — interrupt enable
//         [2]   ONE_SHOT — 0=continuous, 1=one-shot (stop on match)
//         [3]   OVF_EN   — overflow interrupt enable
//   0x04  TIMER_COUNT   R/W   current counter value
//   0x08  TIMER_CMP     R/W   compare value (match → interrupt)
//   0x0C  TIMER_PSC     R/W   prescaler reload value
//                              counter increments every (PSC+1) clk cycles
//   0x10  TIMER_STATUS  R/W1C status / interrupt flags
//         [0]   MATCH    — compare match occurred
//         [1]   OVF      — counter overflow occurred
// ============================================================
module apb_timer (
  input             clk,
  input             rst_n,
  // APB slave
  input             psel_i,
  input             penable_i,
  input             pwrite_i,
  input      [4:0]  paddr_i,        // byte address
  input      [31:0] pwdata_i,
  output reg [31:0] prdata_o,
  output            pready_o,
  // Interrupt
  output            irq_o
);

  // ------ registers ------
  reg        ctrl_en;
  reg        ctrl_irq_en;
  reg        ctrl_one_shot;
  reg        ctrl_ovf_en;
  reg [31:0] count_r;
  reg [31:0] cmp_r;
  reg [31:0] psc_r;
  reg        flag_match;
  reg        flag_ovf;

  // Prescaler counter
  reg [31:0] psc_cnt;

  // ------ prescaler tick ------
  wire tick = (psc_cnt == psc_r);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psc_cnt <= 32'd0;
    end else if (!ctrl_en) begin
      psc_cnt <= 32'd0;
    end else if (tick) begin
      psc_cnt <= 32'd0;
    end else begin
      psc_cnt <= psc_cnt + 32'd1;
    end
  end

  // ------ counter ------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_r    <= 32'd0;
      flag_match <= 1'b0;
      flag_ovf   <= 1'b0;
    end else begin
      // APB write to count (load)
      if (psel_i & penable_i & pwrite_i && paddr_i[4:2] == 3'd1) begin
        count_r <= pwdata_i;
      end
      // APB W1C to status
      else if (psel_i & penable_i & pwrite_i && paddr_i[4:2] == 3'd4) begin
        if (pwdata_i[0]) flag_match <= 1'b0;
        if (pwdata_i[1]) flag_ovf   <= 1'b0;
      end
      // Normal counting
      else if (ctrl_en && tick) begin
        if (count_r == cmp_r) begin
          flag_match <= 1'b1;
          if (ctrl_one_shot)
            ; // stop — don't increment
          else
            count_r <= 32'd0;           // wrap to 0 in continuous mode
        end else begin
          if (count_r == 32'hFFFF_FFFF) begin
            flag_ovf <= 1'b1;
            count_r  <= 32'd0;
          end else begin
            count_r <= count_r + 32'd1;
          end
        end
      end
    end
  end

  // ------ APB write (control & compare) ------
  wire apb_wr = psel_i & penable_i & pwrite_i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_en       <= 1'b0;
      ctrl_irq_en   <= 1'b0;
      ctrl_one_shot <= 1'b0;
      ctrl_ovf_en   <= 1'b0;
      cmp_r         <= 32'hFFFF_FFFF;
      psc_r         <= 32'd0;
    end else if (apb_wr) begin
      case (paddr_i[4:2])
        3'd0: begin                     // 0x00 CTRL
          ctrl_en       <= pwdata_i[0];
          ctrl_irq_en   <= pwdata_i[1];
          ctrl_one_shot <= pwdata_i[2];
          ctrl_ovf_en   <= pwdata_i[3];
        end
        // 3'd1: count handled above
        3'd2: cmp_r <= pwdata_i;        // 0x08 CMP
        3'd3: psc_r <= pwdata_i;        // 0x0C PSC
        // 3'd4: status W1C handled above
        default: ;
      endcase
    end
  end

  // ------ one-shot auto-disable ------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      ; // ctrl_en handled above
    else if (ctrl_en && ctrl_one_shot && tick && count_r == cmp_r)
      ctrl_en <= 1'b0;
  end

  // ------ APB read ------
  wire apb_rd = psel_i & ~pwrite_i;

  always @(*) begin
    prdata_o = 32'd0;
    if (apb_rd) begin
      case (paddr_i[4:2])
        3'd0: prdata_o = {28'd0, ctrl_ovf_en, ctrl_one_shot, ctrl_irq_en, ctrl_en};
        3'd1: prdata_o = count_r;
        3'd2: prdata_o = cmp_r;
        3'd3: prdata_o = psc_r;
        3'd4: prdata_o = {30'd0, flag_ovf, flag_match};
        default: prdata_o = 32'd0;
      endcase
    end
  end

  // ------ outputs ------
  assign pready_o = 1'b1;
  assign irq_o    = (flag_match & ctrl_irq_en) | (flag_ovf & ctrl_ovf_en);

endmodule
