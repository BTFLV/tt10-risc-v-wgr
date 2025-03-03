`default_nettype none

module wgr_v_asic
(
    input  wire [7:0] ui_in,   
    output wire [7:0] uo_out,  
    input  wire [7:0] uio_in,  
    output wire [7:0] uio_out, 
    output wire [7:0] uio_oe,  
    input  wire       ena,
    input  wire       clk,     
    input  wire       rst_n    
);

	// ui_in[0] : spi_miso
	// uo_out[0]: spi_mosi
	// uo_out[1]: spi_clk
	// uo_out[2]: spi_cs
	// uo_out[3]: pwm_out
	// uo_out[4]: uart_tx
	// uo_out[5]: mem_read
	// uo_out[6]: mem_write
	// uo_out[7]: mem_busy

  wire reset = ~rst_n;

  wire [31:0] mem_addr;
  wire [31:0] mem_write_data;
  wire [31:0] mem_read_data;
  wire        mem_read;
  wire        mem_write;
  wire        halt;
  wire        mem_busy;
  wire [1:0]  mem_size;
  wire        mem_signed;

  wire [7:0] debug_out;
  
  wire spi_miso;
  wire spi_mosi;
  wire spi_clk;
  wire spi_cs;

  wire pwm_out;
  wire uart_tx;

  cpu rv32i_cpu (
      .clk           (clk),
      .reset         (reset),
      .mem_addr      (mem_addr),
      .mem_write_data(mem_write_data),
      .mem_read_data (mem_read_data),
      .mem_read      (mem_read),
      .mem_write     (mem_write),
      .halt          (halt),
      .mem_busy      (mem_busy),
      .mem_size      (mem_size),
      .mem_signed    (mem_signed)
  );

  memory system_memory (
      .clk       (clk),
      .reset     (reset),
      .address   (mem_addr),
      .write_data(mem_write_data),
      .read_data (mem_read_data),
      .we        (mem_write),
      .re        (mem_read),
      .mem_size  (mem_size),
      .mem_signed(mem_signed),
      .debug_out (debug_out),
      .pwm_out   (pwm_out),
      .spi_mosi  (spi_mosi),
      .spi_miso  (spi_miso),
      .spi_clk   (spi_clk),
      .spi_cs    (spi_cs),
      .mem_busy  (mem_busy),
      .uart_tx   (uart_tx)
  );

  assign spi_miso = ui_in[0];
  assign uo_out[0] = spi_mosi; 
  assign uo_out[1] = spi_clk;  
  assign uo_out[2] = spi_cs;   
  assign uo_out[3] = pwm_out;
  assign uo_out[4] = uart_tx;
  assign uo_out[5] = mem_read;
  assign uo_out[6] = mem_write;
  assign uo_out[7] = mem_busy;
  
  assign uio_out = mem_addr[7:0]; 
  assign uio_oe  = 8'hFF;

  wire _unused = &{ui_in[7:1], uio_in, ena};

endmodule
