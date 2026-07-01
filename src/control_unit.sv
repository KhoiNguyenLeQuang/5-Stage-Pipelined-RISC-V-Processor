//==============================================================================
// control_unit.sv
//
// Looks at WHICH instruction is currently being executed (its opcode,
// funct3, and one bit of funct7), and decides how every other module in
// the datapath should behave.
//==============================================================================

module control_unit (
    input  logic [6:0] opcode,      // instruction[6:0] (what type of operations is this ?)
    input  logic [2:0] funct3,      // instruction[14:12] (Mathematical/AND/OR)
    input  logic       funct7_5,    // instruction[30] - distinguishes ADD (0) from SUB (1)

    output logic [1:0] alu_op,      // ALU operation option. Tells which operation to perform
    output logic       reg_write,   // 1 = write the result of the ALU to the register file, 0 = don't write
    output logic       mem_read,    // 1 = read from data memory, 0 = don't read from data memory
    output logic       mem_write,   // 1 = write to data memory, 0 = don't write to data memory
    output logic       mem_to_reg,  // selects write-back source: 1 = data memory, 0 = ALU result (only relevant when reg_write = 1)
    output logic       branch,      // A flag for when ALU is set to SUB
    output logic       alu_src      // 1 = ALU's 2nd operand is the output from imm_generator, 0 = it's the value from the register file
);

  localparam logic [6:0] OPC_RTYPE  = 7'b0110011;
  localparam logic [6:0] OPC_ADDI   = 7'b0010011;
  localparam logic [6:0] OPC_LOAD   = 7'b0000011;
  localparam logic [6:0] OPC_STORE  = 7'b0100011;
  localparam logic [6:0] OPC_BRANCH = 7'b1100011;

  localparam logic [1:0] ALU_ADD = 2'b00;
  localparam logic [1:0] ALU_SUB = 2'b01;
  localparam logic [1:0] ALU_AND = 2'b10;
  localparam logic [1:0] ALU_OR  = 2'b11;

  always_comb begin
    alu_op     = ALU_ADD;
    reg_write  = 1'b0;
    mem_read   = 1'b0;
    mem_write  = 1'b0;
    mem_to_reg = 1'b0;
    branch     = 1'b0;
    alu_src    = 1'b0;

    unique case (opcode)

      OPC_RTYPE: begin              // ADD / SUB / AND / OR
        reg_write = 1'b1;
        alu_src   = 1'b0;           // both ALU operands come from registers
        unique case (funct3)
          3'b000:  alu_op = funct7_5 ? ALU_SUB : ALU_ADD;
          3'b111:  alu_op = ALU_AND;
          3'b110:  alu_op = ALU_OR;
          default: alu_op = ALU_ADD;   // not reachable for this project's ISA subset
        endcase
      end

      OPC_ADDI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;           // 2nd operand is the immediate
        alu_op    = ALU_ADD;
      end

      OPC_LOAD: begin               // LW
        reg_write  = 1'b1;
        alu_src    = 1'b1;          // address = rs1 + immediate
        alu_op     = ALU_ADD;
        mem_read   = 1'b1;
        mem_to_reg = 1'b1;          // write-back value comes from memory
      end

      OPC_STORE: begin              // SW
        alu_src   = 1'b1;           // address = rs1 + immediate
        alu_op    = ALU_ADD;
        mem_write = 1'b1;
        // reg_write stays 0 - SW never writes a register
      end

      OPC_BRANCH: begin             // BEQ
        alu_src = 1'b0;             // compare two register values directly
        alu_op  = ALU_SUB;          // subtract; ALU's zero flag means "equal"
        branch  = 1'b1;
        // reg_write stays 0 - BEQ never writes a register
      end

      default: ; 

    endcase
  end

endmodule