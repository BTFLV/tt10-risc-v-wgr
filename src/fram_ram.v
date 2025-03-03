`default_nettype none

module fram_ram
#(
    parameter ADDR_WIDTH = 16
)
(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              req_valid,   // cpu signals load or store
    output reg               req_ready,   // signal back when finished
    input  wire [31:0]       addr,
    input  wire              write_en,    // 1=store, 0=load
    input  wire [1:0]        size,        // 00=byte, 01=halfword, 10=word
    input  wire              sign_ext,
    input  wire [31:0]       wdata,
    output reg  [31:0]       rdata,
    output wire              spi_sck,
    output wire              spi_cs_n,
    output wire              spi_mosi,
    input  wire              spi_miso
);

    wire [7:0] spi_read_data;
    reg  [7:0] spi_write_data;
    wire       spi_done;
    wire       spi_busy;
    reg        spi_read_enable;
    reg        spi_write_enable;
    reg [ADDR_WIDTH-1:0] spi_addr;

    fram_spi #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_fram_spi
    (
        .clk         (clk),
        .rst_n       (rst_n),
        .addr        (spi_addr),
        .write_data  (spi_write_data),
        .read_enable (spi_read_enable),
        .write_enable(spi_write_enable),
        .read_data   (spi_read_data),
        .busy        (spi_busy),
        .done        (spi_done),
        .spi_sck     (spi_sck),
        .spi_cs_n    (spi_cs_n),
        .spi_mosi    (spi_mosi),
        .spi_miso    (spi_miso)
    );

    localparam [3:0]
        ST_IDLE     = 4'd0,
        ST_B0_RW    = 4'd1,
        ST_B1_RW    = 4'd2,
        ST_B2_RW    = 4'd3,
        ST_B3_RW    = 4'd4,
        ST_COMPLETE = 4'd5;

    reg [3:0] state, next_state;
    reg [7:0] read_bytes [0:3];
    reg [2:0] total_bytes;
    reg [2:0] byte_index;

    always @*
    begin
        next_state = state;
        case (state)
            ST_IDLE:
                if (req_valid)
                    next_state = ST_B0_RW;
            ST_B0_RW:
                if (spi_done)
                begin
                    if (total_bytes > 1)
                        next_state = ST_B1_RW;
                    else
                        next_state = ST_COMPLETE;
                end
            ST_B1_RW:
                if (spi_done)
                begin
                    if (total_bytes > 2)
                        next_state = ST_B2_RW;
                    else
                        next_state = ST_COMPLETE;
                end
            ST_B2_RW:
                if (spi_done)
                begin
                    if (total_bytes > 3)
                        next_state = ST_B3_RW;
                    else
                        next_state = ST_COMPLETE;
                end
            ST_B3_RW:
                if (spi_done)
                    next_state = ST_COMPLETE;
            ST_COMPLETE:
                next_state = ST_IDLE;
            default:
                next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            total_bytes <= 3'd0;
        else if (req_valid && (state == ST_IDLE))
        begin
            case (size)
                2'b00: total_bytes <= 1;
                2'b01: total_bytes <= 2;
                2'b10: total_bytes <= 4;
                default: total_bytes <= 1;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            byte_index <= 0;
        else
        begin
            if ((state == ST_IDLE) && req_valid)
                byte_index <= 0;
            else if ((state == ST_B0_RW || state == ST_B1_RW ||
                      state == ST_B2_RW || state == ST_B3_RW) && spi_done)
                byte_index <= byte_index + 1;
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            spi_addr         <= 0;
            spi_write_data   <= 0;
            spi_read_enable  <= 1'b0;
            spi_write_enable <= 1'b0;

            read_bytes[0] <= 8'd0;
            read_bytes[1] <= 8'd0;
            read_bytes[2] <= 8'd0;
            read_bytes[3] <= 8'd0;
        end
        else
        begin
            spi_read_enable  <= 1'b0;
            spi_write_enable <= 1'b0;

            case (next_state)
                ST_B0_RW:
                begin
                    if (state == ST_IDLE)
                    begin
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 0;
                        spi_write_data <= wdata[7:0];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                end

                ST_B1_RW:
                begin
                    if ((state == ST_B0_RW) && spi_done)
                    begin
                        if (!write_en)
                            read_bytes[0] <= spi_read_data;
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 1;
                        spi_write_data <= wdata[15:8];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                end

                ST_B2_RW:
                begin
                    if ((state == ST_B1_RW) && spi_done)
                    begin
                        if (!write_en)
                            read_bytes[1] <= spi_read_data;
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 2;
                        spi_write_data <= wdata[23:16];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                end

                ST_B3_RW:
                begin
                    if ((state == ST_B2_RW) && spi_done)
                    begin
                        if (!write_en)
                            read_bytes[2] <= spi_read_data;
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 3;
                        spi_write_data <= wdata[31:24];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                end

                ST_COMPLETE:
                begin
                    if ((state == ST_B3_RW) && spi_done)
                        read_bytes[3] <= spi_read_data;
                    else if ((state == ST_B2_RW) && spi_done && (total_bytes == 3))
                        read_bytes[2] <= spi_read_data;
                    else if ((state == ST_B1_RW) && spi_done && (total_bytes == 2))
                        read_bytes[1] <= spi_read_data;
                    else if ((state == ST_B0_RW) && spi_done && (total_bytes == 1))
                        read_bytes[0] <= spi_read_data;
                end

                default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            rdata <= 32'd0;
        else if (state == ST_COMPLETE)
        begin
            if (!write_en)
            begin
                case (size)
                    2'b00: // Byte
                    begin
                        if (sign_ext && read_bytes[0][7])
                            rdata <= {24'hFFFFFF, read_bytes[0]};
                        else
                            rdata <= {24'h000000, read_bytes[0]};
                    end

                    2'b01: // Halfword
                    begin
                        if (sign_ext && read_bytes[1][7])
									  rdata <= {16'hFFFF, read_bytes[1], read_bytes[0]};
								 else
									  rdata <= {16'h0000, read_bytes[1], read_bytes[0]};
                    end

                    2'b10: // Word
                    begin
                        rdata <= {read_bytes[3], read_bytes[2],
                                  read_bytes[1], read_bytes[0]};
                    end

                    default:
                        rdata <= 32'h00000000;
                endcase
            end
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            req_ready <= 1'b1;
        else
        begin
            if (req_valid && req_ready)
                req_ready <= 1'b0;
            else if (state == ST_COMPLETE)
                req_ready <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

endmodule
