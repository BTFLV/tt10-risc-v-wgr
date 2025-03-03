`default_nettype none

module fram_ram
#(
    parameter ADDR_WIDTH = 16
)
(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              req_valid, 
    output reg               req_ready,
    input  wire [31:0]       addr,
    input  wire              write_en,
    input  wire [1:0]        size,
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

    fram_spi
    #(
        .ADDR_WIDTH(ADDR_WIDTH)
    )
    u_fram_spi
    (
        .clk(clk),
        .rst_n(rst_n),
        .addr(spi_addr),
        .write_data(spi_write_data),
        .read_enable(spi_read_enable),
        .write_enable(spi_write_enable),
        .read_data(spi_read_data),
        .busy(spi_busy),
        .done(spi_done),
        .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    localparam [2:0] 
        ST_IDLE     = 3'd0,
        ST_BYTE0    = 3'd1,
        ST_BYTE1    = 3'd2,
        ST_BYTE2    = 3'd3,
        ST_BYTE3    = 3'd4,
        ST_COMPLETE = 3'd5;

    reg [2:0] state, next_state;
    reg [2:0] total_bytes;
    reg [1:0] byte_index;

    reg [7:0] read_bytes [0:3];

    always @*
    begin
        next_state = state;
        case (state)
            ST_IDLE:
                if (req_valid)
                    next_state = ST_BYTE0;
            ST_BYTE0:
                if (spi_done)
                    if (total_bytes > 1)
                        next_state = ST_BYTE1;
                    else
                        next_state = ST_COMPLETE;
            ST_BYTE1:
                if (spi_done)
                    if (total_bytes > 2)
                        next_state = ST_BYTE2;
                    else
                        next_state = ST_COMPLETE;
            ST_BYTE2:
                if (spi_done)
                    if (total_bytes > 3)
                        next_state = ST_BYTE3;
                    else
                        next_state = ST_COMPLETE;
            ST_BYTE3:
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
        else if (state == ST_IDLE && req_valid)
        begin
            case (size)
                2'b00: total_bytes <= 3'd1;
                2'b01: total_bytes <= 3'd2;
                2'b10: total_bytes <= 3'd4;
                default: total_bytes <= 3'd1;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            byte_index <= 2'd0;
        else if (state == ST_IDLE && req_valid)
            byte_index <= 2'd0;
        else if ((state == ST_BYTE0 || state == ST_BYTE1 || state == ST_BYTE2 || state == ST_BYTE3) && spi_done)
            byte_index <= byte_index + 1;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            spi_addr         <= {ADDR_WIDTH{1'b0}};
            spi_write_data   <= 8'd0;
            spi_read_enable  <= 1'b0;
            spi_write_enable <= 1'b0;
            read_bytes[0]    <= 8'd0;
            read_bytes[1]    <= 8'd0;
            read_bytes[2]    <= 8'd0;
            read_bytes[3]    <= 8'd0;
        end
        else
        begin
            spi_read_enable  <= 1'b0;
            spi_write_enable <= 1'b0;

            case (next_state)
                ST_BYTE0:
                begin
                    if (state == ST_IDLE && req_valid)
                    begin
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 0;
                        spi_write_data <= wdata[7:0];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                    if (!write_en && spi_done)
                        read_bytes[0] <= spi_read_data;
                end

                ST_BYTE1:
                begin
                    if ((state == ST_BYTE0) && spi_done)
                    begin
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 1;
                        spi_write_data <= wdata[15:8];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                    if (!write_en && spi_done)
                        read_bytes[1] <= spi_read_data;
                end

                ST_BYTE2:
                begin
                    if ((state == ST_BYTE1) && spi_done)
                    begin
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 2;
                        spi_write_data <= wdata[23:16];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                    if (!write_en && spi_done)
                        read_bytes[2] <= spi_read_data;
                end

                ST_BYTE3:
                begin
                    if ((state == ST_BYTE2) && spi_done)
                    begin
                        spi_addr       <= addr[ADDR_WIDTH-1:0] + 3;
                        spi_write_data <= wdata[31:24];
                        if (write_en)
                            spi_write_enable <= 1'b1;
                        else
                            spi_read_enable <= 1'b1;
                    end
                    if (!write_en && spi_done)
                        read_bytes[3] <= spi_read_data;
                end

                ST_COMPLETE:
                begin
                    if (!write_en && spi_done)
                    begin
                        if (byte_index == 0 && total_bytes == 1)
                            read_bytes[0] <= spi_read_data;
                        else if (byte_index == 1 && total_bytes == 2)
                            read_bytes[1] <= spi_read_data;
                        else if (byte_index == 2 && total_bytes == 3)
                            read_bytes[2] <= spi_read_data;
                    end
                end

                default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            rdata <= 32'd0;
        else if (state == ST_COMPLETE && !write_en)
        begin
            case (size)
                2'b00:
                begin
                    if (sign_ext && read_bytes[0][7])
                        rdata <= {24'hFFFFFF, read_bytes[0]};
                    else
                        rdata <= {24'h000000, read_bytes[0]};
                end
                2'b01:
                begin
                    if (sign_ext && read_bytes[1][7])
                        rdata <= {16'hFFFF, read_bytes[1], read_bytes[0]};
                    else
                        rdata <= {16'h0000, read_bytes[1], read_bytes[0]};
                end
                2'b10:
                begin
                    rdata <= {read_bytes[3], read_bytes[2], read_bytes[1], read_bytes[0]};
                end
                default:
                    rdata <= 32'h00000000;
            endcase
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
