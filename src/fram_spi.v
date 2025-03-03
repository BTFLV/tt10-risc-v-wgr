`default_nettype none

module fram_spi 
#(
    parameter ADDR_WIDTH = 16
)
(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [ADDR_WIDTH-1:0]  addr,
    input  wire [7:0]             write_data,
    input  wire                   read_enable,
    input  wire                   write_enable,
    output reg  [7:0]             read_data,
    output reg                    busy,
    output reg                    done,
    output reg                    spi_sck,
    output reg                    spi_cs_n,
    output reg                    spi_mosi,
    input  wire                   spi_miso
);

    // MB85RS64V opcodes
    localparam [7:0] OPCODE_WREN  = 8'h06;  // Write Enable
    localparam [7:0] OPCODE_WRITE = 8'h02;  // Write
    localparam [7:0] OPCODE_READ  = 8'h03;  // Read

    localparam [3:0] 
	  ST_IDLE           = 4'd0,

	  // WREN command
	  ST_WREN_ASSERT_CS = 4'd1,
	  ST_WREN_SHIFT     = 4'd2,
	  ST_WREN_DEASSERT  = 4'd3,

	  // WRITE command
	  ST_WRITE_ASSERT_CS= 4'd4,
	  ST_WRITE_SHIFT    = 4'd5,
	  ST_WRITE_DEASSERT = 4'd6,

	  // READ command
	  ST_READ_ASSERT_CS = 4'd7,
	  ST_READ_SHIFT     = 4'd8,
	  ST_READ_DEASSERT  = 4'd9;

    reg [3:0]  state, next_state;

    reg [31:0] shift_reg;

    reg [5:0]  bit_count;

    reg        sck_reg;

    reg        cs_hold;

    // SPI Mode 0 (CPOL=0, CPHA=0)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sck_reg <= 1'b0;
        else if (busy)
            sck_reg <= ~sck_reg;  
        else
            sck_reg <= 1'b0;
    end

    always @*
        spi_sck = sck_reg;

    always @* begin
        spi_cs_n = 1'b1;
        if (cs_hold)
            spi_cs_n = 1'b0;
    end

    always @* begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (write_enable)
                    next_state = ST_WREN_ASSERT_CS;
                else if (read_enable)
                    next_state = ST_READ_ASSERT_CS;
            end

            // WREN
            ST_WREN_ASSERT_CS:
                next_state = ST_WREN_SHIFT;

            ST_WREN_SHIFT: begin
                if ((bit_count == 6'd8) && (sck_reg == 1'b0))
                    next_state = ST_WREN_DEASSERT;
            end

            ST_WREN_DEASSERT:
                next_state = ST_WRITE_ASSERT_CS;

            // WRITE
            ST_WRITE_ASSERT_CS:
                next_state = ST_WRITE_SHIFT;

            ST_WRITE_SHIFT: begin
                if ((bit_count == 6'd32) && (sck_reg == 1'b0))
                    next_state = ST_WRITE_DEASSERT;
            end

            ST_WRITE_DEASSERT:
                next_state = ST_IDLE;

            // READ
            ST_READ_ASSERT_CS:
                next_state = ST_READ_SHIFT;

            ST_READ_SHIFT: begin
                if ((bit_count == 6'd32) && (sck_reg == 1'b0))
                    next_state = ST_READ_DEASSERT;
            end

            ST_READ_DEASSERT:
                next_state = ST_IDLE;

            default:
                next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            shift_reg  <= 32'd0;
            bit_count  <= 6'd0;
            spi_mosi   <= 1'b0;
            read_data  <= 8'd0;
            cs_hold    <= 1'b0;
        end 
        else begin
            state <= next_state;
            done <= 1'b0;

            case (next_state)
				
                ST_IDLE: begin
                    busy      <= 1'b0;
                    spi_mosi  <= 1'b0;
                    bit_count <= 0;
                    cs_hold   <= 1'b0;
                end
					 
                ST_WREN_ASSERT_CS: begin
                    busy       <= 1'b1;
                    bit_count  <= 0;
                    shift_reg  <= {24'd0, OPCODE_WREN};
                    spi_mosi   <= OPCODE_WREN[7];
                    cs_hold    <= 1'b1;
                end

                ST_WREN_SHIFT: begin
                    if (sck_reg == 1'b0) begin
                        bit_count <= bit_count + 1;
                        shift_reg <= {shift_reg[30:0], 1'b0};
                        spi_mosi  <= shift_reg[30];
                    end
                end

                ST_WREN_DEASSERT: begin
                    cs_hold <= 1'b0;
                end

                ST_WRITE_ASSERT_CS: begin
                    busy       <= 1'b1;
                    bit_count  <= 0;
                    shift_reg  <= {OPCODE_WRITE, addr, write_data};
                    spi_mosi   <= OPCODE_WRITE[7];
                    cs_hold    <= 1'b1;
                end

                ST_WRITE_SHIFT: begin
                    if (sck_reg == 1'b0) begin
                        bit_count <= bit_count + 1;
                        shift_reg <= {shift_reg[30:0], 1'b0};
                        spi_mosi  <= shift_reg[30];
                    end
                end

                ST_WRITE_DEASSERT: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    cs_hold <= 1'b0;
                end

                ST_READ_ASSERT_CS: begin
                    busy      <= 1'b1;
                    bit_count <= 0;
                    shift_reg <= {OPCODE_READ, addr, 8'd0};
                    spi_mosi  <= OPCODE_READ[7];
                    cs_hold   <= 1'b1;
                end

                ST_READ_SHIFT: begin
                    if (sck_reg == 1'b0) begin
                        bit_count <= bit_count + 1;
                        shift_reg <= {shift_reg[30:0], 1'b0};
                        spi_mosi  <= shift_reg[30];
                    end
                    else begin
                        if (bit_count >= 24 && bit_count < 32)
                            read_data <= {read_data[6:0], spi_miso};
                    end
                end

                ST_READ_DEASSERT: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    cs_hold <= 1'b0;
                end

                default: ;
            endcase
        end
    end

endmodule
