`default_nettype none

module cpu
(
    input  wire         clk,
    input  wire         reset,
    output reg [31:0]   mem_addr,
    output reg [31:0]   mem_write_data,
    input  wire [31:0]  mem_read_data,
    output reg          mem_read,
    output reg          mem_write,
    output reg          halt,
    input  wire         mem_busy,
    output reg [1:0]    mem_size,
    output reg          mem_signed
);

  localparam REG_BASE  = 32'h00005F80;
  localparam INST_BASE = 32'h00004000;

  reg [31:0] reg_rs1, reg_rs2;

  reg [31:0] PC;
  reg [31:0] instruction;

  reg [31:0] reg_write_data;
  reg        reg_write_en;
  reg [4:0]  reg_write_addr;

  wire [4:0] rs1    = instruction[19:15];
  wire [4:0] rs2    = instruction[24:20];
  wire [4:0] rd     = instruction[11:7];
  wire [6:0] opcode = instruction[6:0];
  wire [2:0] funct3 = instruction[14:12];
  wire [6:0] funct7 = instruction[31:25];

  reg [31:0] imm;
  always @(*) begin
    case (opcode)
      7'b0010011, 7'b0000011, 7'b1100111:
        imm = {{20{instruction[31]}}, instruction[31:20]};
      7'b0100011:
        imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
      7'b1100011:
        imm = {{19{instruction[31]}}, instruction[31], instruction[7],
               instruction[30:25], instruction[11:8], 1'b0};
      7'b0110111, 7'b0010111:
        imm = {instruction[31:12], 12'b0};
      7'b1101111:
        imm = {{11{instruction[31]}}, instruction[31], instruction[19:12],
               instruction[20], instruction[30:21], 1'b0};
      default:
        imm = 32'd0;
    endcase
  end

  reg [31:0] alu_operand1, alu_operand2;
  reg [3:0]  alu_op;
  wire [31:0] alu_result;
  wire        alu_zero;

  alu alu_inst (
      .operand1 (alu_operand1),
      .operand2 (alu_operand2),
      .operation(alu_op),
      .result   (alu_result),
      .zero     (alu_zero)
  );

  reg [31:0] mem_addr_reg;
  always @(*) begin
    mem_addr = mem_addr_reg;
  end

  localparam [3:0]
    ST_FETCH         = 4'd0,
    ST_FETCH_WAIT    = 4'd1,
    ST_DECODE        = 4'd2,
    ST_READ_REG1     = 4'd3,
    ST_READ_REG1_WAIT= 4'd4,
    ST_READ_REG2     = 4'd5,
    ST_READ_REG2_WAIT= 4'd6,
    ST_EXECUTE       = 4'd7,
    ST_MEM_ACCESS    = 4'd8,
    ST_MEM_WAIT      = 4'd9,
    ST_WRITEBACK     = 4'd10,
    ST_REG_WRITE     = 4'd11,
    ST_REG_WRITE_WAIT= 4'd12,
    ST_UPDATE_PC     = 4'd13,
    ST_HALT          = 4'd14;

  reg [3:0] state, next_state;

  always @(*) begin
    case (state)
      ST_FETCH:         next_state = ST_FETCH_WAIT;
      ST_FETCH_WAIT:    next_state = mem_busy ? ST_FETCH_WAIT : ST_DECODE;
      ST_DECODE:        next_state = ST_READ_REG1;
      ST_READ_REG1:     next_state = ST_READ_REG1_WAIT;
      ST_READ_REG1_WAIT:next_state = mem_busy ? ST_READ_REG1_WAIT : ST_READ_REG2;
      ST_READ_REG2:     next_state = ST_READ_REG2_WAIT;
      ST_READ_REG2_WAIT:next_state = mem_busy ? ST_READ_REG2_WAIT : ST_EXECUTE;
      ST_EXECUTE:       next_state = ((opcode == 7'b0000011) || (opcode == 7'b0100011))
                                      ? ST_MEM_ACCESS : ST_WRITEBACK;
      ST_MEM_ACCESS:    next_state = ST_MEM_WAIT;
      ST_MEM_WAIT:      next_state = mem_busy ? ST_MEM_WAIT : ST_WRITEBACK;
      ST_WRITEBACK:     next_state = (rd != 5'd0) ? ST_REG_WRITE : ST_UPDATE_PC;
      ST_REG_WRITE:     next_state = ST_REG_WRITE_WAIT;
      ST_REG_WRITE_WAIT:next_state = mem_busy ? ST_REG_WRITE_WAIT : ST_UPDATE_PC;
      ST_UPDATE_PC:     next_state = ST_FETCH;
      ST_HALT:          next_state = ST_HALT;
      default:          next_state = ST_FETCH;
    endcase
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      PC            <= INST_BASE;
      state         <= ST_FETCH;
      halt          <= 1'b0;
      mem_addr_reg  <= 32'd0;
      mem_read      <= 1'b0;
      mem_write     <= 1'b0;
      mem_size      <= 2'b10;
      mem_signed    <= 1'b0;
      reg_rs1       <= 32'd0;
      reg_rs2       <= 32'd0;
      reg_write_data<= 32'd0;
      reg_write_en  <= 1'b0;
      
      instruction   <= 32'd0;
    end else begin
      state <= next_state;
      mem_read  <= 1'b0;
      mem_write <= 1'b0;
      halt      <= 1'b0;
      
      case (state)
        ST_FETCH: begin
          mem_addr_reg <= PC;
          mem_read     <= 1'b1;
          halt         <= 1'b1;
        end

        ST_FETCH_WAIT: begin
          mem_read <= 1'b1;
          halt     <= 1'b1;
        end

        ST_DECODE: begin
          instruction <= mem_read_data;
        end

        ST_READ_REG1: begin
          if (rs1 == 5'd0)
            reg_rs1 <= 32'd0;
          else begin
            mem_addr_reg <= REG_BASE + ({27'd0, rs1} << 2);
            mem_read     <= 1'b1;
            halt         <= 1'b1;
          end
        end

        ST_READ_REG1_WAIT: begin
          if (rs1 != 5'd0)
            reg_rs1 <= mem_read_data;
          halt <= 1'b1;
        end

        ST_READ_REG2: begin
          if (rs2 == 5'd0)
            reg_rs2 <= 32'd0;
          else begin
            mem_addr_reg <= REG_BASE + ({27'd0, rs2} << 2);
            mem_read     <= 1'b1;
            halt         <= 1'b1;
          end
        end

        ST_READ_REG2_WAIT: begin
          if (rs2 != 5'd0)
            reg_rs2 <= mem_read_data;
          halt <= 1'b1;
        end

        ST_EXECUTE: begin
          case (opcode)
            7'b0110011: begin // R-type
              alu_operand1 <= reg_rs1;
              alu_operand2 <= reg_rs2;
              case ({funct7, funct3})
                {7'b0000000, 3'b000}: alu_op <= 4'b0000; // ADD
                {7'b0100000, 3'b000}: alu_op <= 4'b0001; // SUB
                {7'b0000000, 3'b111}: alu_op <= 4'b0010; // AND
                {7'b0000000, 3'b110}: alu_op <= 4'b0011; // OR
                {7'b0000000, 3'b100}: alu_op <= 4'b0100; // XOR
                {7'b0000000, 3'b001}: alu_op <= 4'b0101; // SLL
                {7'b0000000, 3'b101}: alu_op <= 4'b0110; // SRL
                {7'b0100000, 3'b101}: alu_op <= 4'b0111; // SRA
                {7'b0000000, 3'b010}: alu_op <= 4'b1000; // SLT
                {7'b0000000, 3'b011}: alu_op <= 4'b1001; // SLTU
                default: alu_op <= 4'b1111;
              endcase
            end

            7'b0010011: begin // I-type ALU
              alu_operand1 <= reg_rs1;
              alu_operand2 <= imm;
              case (funct3)
                3'b000: alu_op <= 4'b0000; // ADDI
                3'b111: alu_op <= 4'b0010; // ANDI
                3'b110: alu_op <= 4'b0011; // ORI
                3'b100: alu_op <= 4'b0100; // XORI
                3'b010: alu_op <= 4'b1000; // SLTI
                3'b011: alu_op <= 4'b1001; // SLTIU
                3'b001: alu_op <= 4'b0101; // SLLI
                3'b101: alu_op <= (instruction[30]) ? 4'b0111 : 4'b0110; // SRAI/SRLI
                default: alu_op <= 4'b1111;
              endcase
            end

            7'b0000011, 7'b0100011: begin
              alu_operand1 <= reg_rs1;
              alu_operand2 <= imm;
              alu_op       <= 4'b0000; // ADD
            end

            7'b1101111: begin // JAL
              alu_operand1 <= PC;
              alu_operand2 <= imm;
              alu_op       <= 4'b0000; // ADD
            end

            7'b1100111: begin // JALR
              alu_operand1 <= reg_rs1;
              alu_operand2 <= imm;
              alu_op       <= 4'b0000; // ADD
            end

            7'b1100011: begin // Branches
              alu_operand1 <= reg_rs1;
              alu_operand2 <= reg_rs2;
              alu_op       <= 4'b0001;
            end

            7'b0010111: begin // AUIPC
              alu_operand1 <= PC;
              alu_operand2 <= imm;
              alu_op       <= 4'b0000; // ADD
            end

            7'b0110111: begin // LUI
              alu_operand1 <= 32'd0;
              alu_operand2 <= imm;
              alu_op       <= 4'b0000;
            end

            default: begin
              alu_operand1 <= 32'd0;
              alu_operand2 <= 32'd0;
              alu_op       <= 4'b1111;
            end
          endcase
			 
          mem_addr_reg <= alu_result;
        end

        ST_MEM_ACCESS: begin
          if (opcode == 7'b0000011) begin // LOAD
            case (funct3)
              3'b000: begin mem_size <= 2'b00; mem_signed <= 1'b1; end // LB
              3'b100: begin mem_size <= 2'b00; mem_signed <= 1'b0; end // LBU
              3'b001: begin mem_size <= 2'b01; mem_signed <= 1'b1; end // LH
              3'b101: begin mem_size <= 2'b01; mem_signed <= 1'b0; end // LHU
              3'b010: begin mem_size <= 2'b10; mem_signed <= 1'b0; end // LW
              default: begin mem_size <= 2'b10; mem_signed <= 1'b0; end
            endcase
            mem_read <= 1'b1;
            halt     <= 1'b1;
          end else if (opcode == 7'b0100011) begin // STORE
            case (funct3)
              3'b000: mem_size <= 2'b00; // SB
              3'b001: mem_size <= 2'b01; // SH
              3'b010: mem_size <= 2'b10; // SW
              default: mem_size <= 2'b10;
            endcase
            mem_signed <= 1'b0;
            mem_write_data <= reg_rs2;
            mem_write <= 1'b1;
            halt <= 1'b1;
          end
        end

        ST_MEM_WAIT: begin
          halt <= 1'b1;
        end

        ST_WRITEBACK: begin
          if (rd != 5'd0) begin
            if (opcode == 7'b0000011)  // LOAD
              reg_write_data <= mem_read_data;
            else if (opcode == 7'b1101111 || opcode == 7'b1100111)
              reg_write_data <= PC + 4;
            else if (opcode == 7'b0110111)  // LUI
              reg_write_data <= imm;
            else if (opcode == 7'b0010111)  // AUIPC
              reg_write_data <= PC + imm;
            else
              reg_write_data <= alu_result;
            reg_write_en <= 1'b1;
          end else
            reg_write_en <= 1'b0;
        end

        ST_REG_WRITE: begin
          if (rd != 5'd0) begin
            mem_addr_reg   <= REG_BASE + ({27'd0, rd} << 2);
            mem_write_data <= reg_write_data;
            mem_write      <= 1'b1;
            halt           <= 1'b1;
          end
        end

        ST_REG_WRITE_WAIT: begin
          mem_write_data <= reg_write_data;
          mem_write      <= 1'b1;
          halt           <= 1'b1;
        end

        ST_UPDATE_PC: begin
          if (opcode == 7'b1101111)
            PC <= alu_result;
          else if (opcode == 7'b1100111)
            PC <= alu_result & ~32'd1;
          else if (opcode == 7'b1100011) begin
            case (funct3)
              3'b000: PC <= (alu_zero)           ? (PC + imm) : (PC + 4); // BEQ
              3'b001: PC <= (!alu_zero)          ? (PC + imm) : (PC + 4); // BNE
              3'b100: PC <= ($signed(reg_rs1) < $signed(reg_rs2)) ? (PC + imm) : (PC + 4); // BLT
              3'b101: PC <= ($signed(reg_rs1) >= $signed(reg_rs2))? (PC + imm) : (PC + 4); // BGE
              3'b110: PC <= (reg_rs1 < reg_rs2)   ? (PC + imm) : (PC + 4); // BLTU
              3'b111: PC <= (reg_rs1 >= reg_rs2)  ? (PC + imm) : (PC + 4); // BGEU
              default: PC <= PC + 4;
            endcase
          end
          else begin
            PC <= PC + 4;
          end
        end

        ST_HALT: begin
          halt <= 1'b1;
        end

        default: ;
      endcase
    end
  end

endmodule
