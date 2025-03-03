`default_nettype none

module peri_bus
(
    input  wire            clk,
    input  wire            reset,
    input  wire [31:0]     address,
    input  wire [31:0]     write_data,
    input  wire            we,
    input  wire            re,
    output reg  [31:0]     read_data,
    output wire [7:0]      debug_out,
    output wire            pwm_out,
    output wire            uart_tx
);

  always @(posedge clk or posedge reset) begin
    if (reset)
      read_data <= 32'd0;
    else if (re)
      read_data <= 32'd0;
  end

  assign debug_out = 8'd0;
  assign pwm_out   = 1'b0;
  assign uart_tx   = 1'b1;

endmodule
