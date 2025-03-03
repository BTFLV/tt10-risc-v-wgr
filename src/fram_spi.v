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
        ST_IDLE            = 4'd0,
        // WREN command states
        ST_WREN_ASSERT_CS  = 4'd1,
        ST_WREN_SHIFT      = 4'd2,
        ST_WREN_DEASSERT   = 4'd3,
        // WRITE command states
        ST_WRITE_ASSERT_CS = 4'd4,
        ST_WRITE_SHIFT     = 4'd5,
        ST_WRITE_DEASSERT  = 4'd6,
        // READ command states
        ST_READ_ASSERT_CS  = 4'd7,
        ST_READ_SHIFT      = 4'd8,
        ST_READ_DEASSERT   = 4'd9;

    localparam integer CMD_WIDTH = 8 + ADDR_WIDTH + 8;
    localparam integer CMD_WIDTH_WREN = 8;

    wire [CMD_WIDTH-1:0] init_data_write;
    wire [CMD_WIDTH-1:0] init_data_read;
    assign init_data_write = {OPCODE_WRITE, addr, write_data};
    assign init_data_read  = {OPCODE_READ, addr, 8'd0};

    reg [3:0] state, next_state;
    reg [5:0] bit_count;
    reg [CMD_WIDTH-1:0] shift_reg;
    reg sck_reg;
    reg cs_hold;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            sck_reg <= 1'b0;
        else if (busy)
            sck_reg <= ~sck_reg;
        else
            sck_reg <= 1'b0;
    end

    always @*
        spi_sck = sck_reg;

    always @*
    begin
        if (cs_hold)
            spi_cs_n = 1'b0;
        else
            spi_cs_n = 1'b1;
    end

    always @*
    begin
        next_state = state;
        case (state)
            ST_IDLE:
            begin
                if (write_enable)
                    next_state = ST_WREN_ASSERT_CS;
                else if (read_enable)
                    next_state = ST_READ_ASSERT_CS;
            end
            ST_WREN_ASSERT_CS:
                next_state = ST_WREN_SHIFT;
            ST_WREN_SHIFT:
            begin
                if ((bit_count < CMD_WIDTH_WREN) && (sck_reg == 1'b1))
                    next_state = ST_WREN_SHIFT;
                else if ((bit_count == CMD_WIDTH_WREN) && (sck_reg == 1'b0))
                    next_state = ST_WREN_DEASSERT;
            end
            ST_WREN_DEASSERT:
                next_state = ST_WRITE_ASSERT_CS;
            ST_WRITE_ASSERT_CS:
                next_state = ST_WRITE_SHIFT;
            ST_WRITE_SHIFT:
            begin
                if ((bit_count < CMD_WIDTH) && (sck_reg == 1'b1))
                    next_state = ST_WRITE_SHIFT;
                else if ((bit_count == CMD_WIDTH) && (sck_reg == 1'b0))
                    next_state = ST_WRITE_DEASSERT;
            end
            ST_WRITE_DEASSERT:
                next_state = ST_IDLE;
            ST_READ_ASSERT_CS:
                next_state = ST_READ_SHIFT;
            ST_READ_SHIFT:
            begin
                if ((bit_count < CMD_WIDTH) && (sck_reg == 1'b1))
                    next_state = ST_READ_SHIFT;
                else if ((bit_count == CMD_WIDTH) && (sck_reg == 1'b0))
                    next_state = ST_READ_DEASSERT;
            end
            ST_READ_DEASSERT:
                next_state = ST_IDLE;
            default:
                next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            state      <= ST_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            bit_count  <= 6'd0;
            shift_reg  <= {CMD_WIDTH{1'b0}};
            spi_mosi   <= 1'b0;
            read_data  <= 8'd0;
            cs_hold    <= 1'b0;
        end 
        else
        begin
            state <= next_state;
            done  <= 1'b0;

            case (next_state)
                ST_IDLE:
                begin
                    busy      <= 1'b0;
                    spi_mosi  <= 1'b0;
                    bit_count <= 6'd0;
                    cs_hold   <= 1'b0;
                end

                ST_WREN_ASSERT_CS:
                begin
                    busy      <= 1'b1;
                    bit_count <= 6'd0;
                    shift_reg <= { {(CMD_WIDTH - CMD_WIDTH_WREN){1'b0}}, OPCODE_WREN };
                    spi_mosi  <= OPCODE_WREN[7];
                    cs_hold   <= 1'b1;
                end

                ST_WREN_SHIFT:
                begin
                    if (sck_reg == 1'b1)
                    begin
                        bit_count <= bit_count + 1;
                        shift_reg[CMD_WIDTH_WREN-1:0] <= { shift_reg[CMD_WIDTH_WREN-2:0], 1'b0 };
                        spi_mosi <= shift_reg[CMD_WIDTH_WREN-2];
                    end
                end

                ST_WREN_DEASSERT:
                begin
                    cs_hold <= 1'b0;
                end

                ST_WRITE_ASSERT_CS:
                begin
                    busy      <= 1'b1;
                    bit_count <= 6'd0;
                    shift_reg <= init_data_write;
                    cs_hold   <= 1'b1;
                    spi_mosi  <= init_data_write[CMD_WIDTH-1];
                end

                ST_WRITE_SHIFT:
                begin
                    if (sck_reg == 1'b1)
                    begin
                        bit_count <= bit_count + 1;
                        shift_reg <= {shift_reg[CMD_WIDTH-2:0], 1'b0};
                        spi_mosi  <= shift_reg[CMD_WIDTH-2];
                    end
                end

                ST_WRITE_DEASSERT:
                begin
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    cs_hold <= 1'b0;
                end

                ST_READ_ASSERT_CS:
                begin
                    busy      <= 1'b1;
                    bit_count <= 6'd0;
                    shift_reg <= init_data_read;
                    cs_hold   <= 1'b1;
                    spi_mosi  <= init_data_read[CMD_WIDTH-1];
                    read_data <= 8'd0;
                end

                ST_READ_SHIFT:
                begin
                    if (sck_reg == 1'b1)
                    begin
                        bit_count <= bit_count + 1;
                        shift_reg <= {shift_reg[CMD_WIDTH-2:0], 1'b0};
                        spi_mosi  <= shift_reg[CMD_WIDTH-2];
                    end
                    else if (sck_reg == 1'b0)
                    begin
                        if ((bit_count >= (8 + ADDR_WIDTH)) && (bit_count < CMD_WIDTH))
                            read_data <= {read_data[6:0], spi_miso};
                    end
                end

                ST_READ_DEASSERT:
                begin
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    cs_hold <= 1'b0;
                end

                default:
                    ;
            endcase
        end
    end

endmodule
