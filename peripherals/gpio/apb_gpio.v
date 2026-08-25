// ============================================================
// apb_gpio — Simple 32-bit GPIO with APB slave interface
//
// Features:
//   - 32 independently configurable I/O pins
//   - Direction register (0 = input, 1 = output)
//   - Output data register
//   - Input data register (directly samples pad)
//   - Rising/falling edge interrupt support
//
// Register map (byte addresses):
//   0x00  GPIO_DIR      R/W   direction  (1 = output)
//   0x04  GPIO_OUT      R/W   output data
//   0x08  GPIO_IN       R     input  data (read-only)
//   0x0C  GPIO_IRQ_EN   R/W   interrupt enable per pin
//   0x10  GPIO_IRQ_FLAG R/W1C interrupt flags (write 1 to clear)
//   0x14  GPIO_IRQ_EDGE R/W   edge select (0=rising, 1=falling)
//
// APB interface:
//   Single-cycle access, no wait states. pready_o is always 1.
// ============================================================
module apb_gpio #(
  parameter WIDTH = 32
)(
  input                  clk,
  input                  rst_n,
  // APB slave
  input                  psel_i,
  input                  penable_i,
  input                  pwrite_i,
  input           [5:0]  paddr_i,      // byte address (6 bits covers 0x00–0x3F)
  input      [WIDTH-1:0] pwdata_i,
  output reg [WIDTH-1:0] prdata_o,
  output                 pready_o,
  // GPIO pads
  input      [WIDTH-1:0] gpio_i,       // pin inputs
  output     [WIDTH-1:0] gpio_o,       // pin outputs
  output     [WIDTH-1:0] gpio_oe_o,    // output enable (active high)
  // Interrupt
  output                 irq_o
);

  // ------ registers ------
  reg [WIDTH-1:0] dir_r;       // direction
  reg [WIDTH-1:0] out_r;       // output data
  reg [WIDTH-1:0] irq_en_r;   // interrupt enable
  reg [WIDTH-1:0] irq_flag_r; // interrupt flags
  reg [WIDTH-1:0] irq_edge_r; // 0=rising, 1=falling

  // Input synchronizer (2-stage)
  reg [WIDTH-1:0] gpio_sync1, gpio_sync2, gpio_prev;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gpio_sync1 <= {WIDTH{1'b0}};
      gpio_sync2 <= {WIDTH{1'b0}};
      gpio_prev  <= {WIDTH{1'b0}};
    end else begin
      gpio_sync1 <= gpio_i;
      gpio_sync2 <= gpio_sync1;
      gpio_prev  <= gpio_sync2;
    end
  end

  // Edge detection
  wire [WIDTH-1:0] rising  = gpio_sync2 & ~gpio_prev;
  wire [WIDTH-1:0] falling = ~gpio_sync2 & gpio_prev;
  wire [WIDTH-1:0] edge_det = (irq_edge_r & falling) | (~irq_edge_r & rising);

  // ------ APB write ------
  wire apb_wr = psel_i & penable_i & pwrite_i;
  wire apb_rd = psel_i & ~pwrite_i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dir_r      <= {WIDTH{1'b0}};
      out_r      <= {WIDTH{1'b0}};
      irq_en_r   <= {WIDTH{1'b0}};
      irq_flag_r <= {WIDTH{1'b0}};
      irq_edge_r <= {WIDTH{1'b0}};
    end else begin
      // Set interrupt flags on edge events
      irq_flag_r <= irq_flag_r | (edge_det & irq_en_r);

      if (apb_wr) begin
        case (paddr_i[5:2])
          4'd0: dir_r      <= pwdata_i;                  // 0x00
          4'd1: out_r      <= pwdata_i;                  // 0x04
          // 0x08 is read-only
          4'd3: irq_en_r   <= pwdata_i;                  // 0x0C
          4'd4: irq_flag_r <= irq_flag_r & ~pwdata_i;    // 0x10 W1C
          4'd5: irq_edge_r <= pwdata_i;                  // 0x14
          default: ;
        endcase
      end
    end
  end

  // ------ APB read ------
  always @(*) begin
    prdata_o = {WIDTH{1'b0}};
    if (apb_rd) begin
      case (paddr_i[5:2])
        4'd0: prdata_o = dir_r;
        4'd1: prdata_o = out_r;
        4'd2: prdata_o = gpio_sync2;    // 0x08 input data
        4'd3: prdata_o = irq_en_r;
        4'd4: prdata_o = irq_flag_r;
        4'd5: prdata_o = irq_edge_r;
        default: prdata_o = {WIDTH{1'b0}};
      endcase
    end
  end

  // ------ outputs ------
  assign gpio_o    = out_r;
  assign gpio_oe_o = dir_r;
  assign pready_o  = 1'b1;              // no wait states
  assign irq_o     = |(irq_flag_r & irq_en_r);

endmodule
