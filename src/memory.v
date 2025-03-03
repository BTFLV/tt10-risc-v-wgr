`default_nettype none

module memory
(
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    output wire [31:0] read_data,
    input  wire        we,
    input  wire        re,
    input  wire [1:0]  mem_size,
    input  wire        mem_signed,
    output wire [7:0]  debug_out,
    output wire        pwm_out,
    output wire        mem_busy,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_clk,
    output wire        spi_cs,
    output wire        uart_tx
);

  wire is_ram = (address >= 32'h00004000);
  wire [31:0] ram_addr = address - 32'h00004000;

  wire [31:0] fram_rdata;
  wire        fram_req_ready;
  
  wire fram_req_valid = (we || re) && is_ram;
  
  fram_ram #(
      .ADDR_WIDTH(16)
  ) fram_inst (
      .clk         (clk),
      .rst_n       (~reset),
      .req_valid   (fram_req_valid),
      .req_ready   (fram_req_ready),
      .addr        (ram_addr[15:0]),
      .write_en   (we && is_ram),
      .size        (mem_size),
      .sign_ext    (mem_signed),
      .wdata       (write_data),
      .rdata       (fram_rdata),
      .spi_sck     (spi_clk),
      .spi_cs_n    (spi_cs),
      .spi_mosi    (spi_mosi),
      .spi_miso    (spi_miso)
  );

  wire [31:0] peri_rdata;
  peri_bus peri_inst (
      .clk       (clk),
      .reset     (reset),
      .address   (address),
      .write_data(write_data),
      .we        (we),
      .re        (re),
      .read_data (peri_rdata),
      .debug_out (debug_out),
      .pwm_out   (pwm_out),
      .uart_tx   (uart_tx)
  );

  assign read_data = is_ram ? fram_rdata : peri_rdata;
  
  assign mem_busy  = is_ram ? ~fram_req_ready : 1'b0;

endmodule
