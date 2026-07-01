//==============================================================================
// Combinational ALU for the single-cycle / pipelined RV32I-subset processor.
// Implements the 4 operations this project's ISA actually needs:
//   ADD  -> ADD, ADDI, and address calculation for LW/SW
//   SUB  -> SUB, and BEQ comparison (rs1 - rs2; branch taken when zero == 1)
//   AND  -> AND
//   OR   -> OR
//
// This module only computes -- it has no idea what instruction is running.
//==============================================================================

module alu (
    input  logic [31:0] operand_a,   // first number (always rs1)
    input  logic [31:0] operand_b,   // second number (rs2, or an immediate)
    input  logic [1:0]  alu_op,      // select operations
 
    output logic [31:0] result,      
    output logic        zero         // 1 if result is exactly 0, else 0 (for BEQ and EX)
);

  localparam logic [1:0] ALU_ADD = 2'b00;   // 00 = add
  localparam logic [1:0] ALU_SUB = 2'b01;   // 01 = subtract
  localparam logic [1:0] ALU_AND = 2'b10;   // 10 = bitwise AND
  localparam logic [1:0] ALU_OR  = 2'b11;   // 11 = bitwise OR
 
  always_comb begin
    unique case (alu_op)
      ALU_ADD: result = operand_a + operand_b;  
      ALU_SUB: result = operand_a - operand_b;   
      ALU_AND: result = operand_a & operand_b;   
      ALU_OR:  result = operand_a | operand_b;   
 
      default: result = 32'd0;
    endcase
  end
 
  assign zero = (result == 32'd0);
 
endmodule