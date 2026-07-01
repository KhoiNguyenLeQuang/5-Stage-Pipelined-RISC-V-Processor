//==============================================================================
// datapath.sv
//
// Wires every module above into the complete single-cycle datapath from
// the project plan's diagram: PC -> instruction memory -> decode ->
// {control unit, register file, immediate generator} -> ALU -> data
// memory -> write-back mux -> back into the register file, with the
// branch-target/PC+4 decision feeding back into the PC.
//
//==============================================================================

module datapath #(
    parameter INIT_FILE = "program.hex"
) (
    input logic clk
);

  // Program Counter
  logic [31:0] pc_current;
  logic        branch_taken;
  logic [31:0] branch_target;

  pc_register u_pc (
      .clk           (clk),
      .branch_taken  (branch_taken),
      .branch_target (branch_target),
      .pc_current    (pc_current)
  );

  // Instruction Fetch
  logic [31:0] instruction;

  instruction_memory #(
      .INIT_FILE (INIT_FILE)
  ) u_imem (
      .addr        (pc_current),
      .instruction (instruction)
  );

  // Instruction Decode: just field slicing, no separate module needed
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic       funct7_5;
  logic [4:0] rs1_addr;
  logic [4:0] rs2_addr;
  logic [4:0] rd_addr;

  assign opcode   = instruction[6:0];
  assign funct3   = instruction[14:12];
  assign funct7_5 = instruction[30];
  assign rs1_addr = instruction[19:15];
  assign rs2_addr = instruction[24:20];
  assign rd_addr  = instruction[11:7];

  // Control Unit
  logic [1:0] alu_op;
  logic       reg_write, mem_read, mem_write, mem_to_reg, branch, alu_src;

  control_unit u_control (
      .opcode     (opcode),
      .funct3     (funct3),
      .funct7_5   (funct7_5),
      .alu_op     (alu_op),
      .reg_write  (reg_write),
      .mem_read   (mem_read),
      .mem_write  (mem_write),
      .mem_to_reg (mem_to_reg),
      .branch     (branch),
      .alu_src    (alu_src)
  );

  // Register File
  logic [31:0] rs1_data, rs2_data, write_back_data;

  register_file u_regfile (
      .clk       (clk),
      .rs1_addr  (rs1_addr),
      .rs2_addr  (rs2_addr),
      .rs1_data  (rs1_data),
      .rs2_data  (rs2_data),
      .rd_addr   (rd_addr),
      .rd_data   (write_back_data),
      .reg_write (reg_write)
  );

  // Immediate Generator
  logic [31:0] imm_out;

  imm_generator u_immgen (
      .instruction (instruction),
      .imm_out     (imm_out)
  );

  // ALU, with the ALUSrc mux feeding its 2nd operand
  logic [31:0] alu_operand_b;
  logic [31:0] alu_result;
  logic        alu_zero;

  assign alu_operand_b = alu_src ? imm_out : rs2_data;

  alu u_alu (
      .operand_a (rs1_data),
      .operand_b (alu_operand_b),
      .alu_op    (alu_op),
      .result    (alu_result),
      .zero      (alu_zero)
  );

  // Data Memory
  logic [31:0] mem_read_data;

  data_memory u_dmem (
      .clk        (clk),
      .addr       (alu_result),
      .write_data (rs2_data),
      .mem_read   (mem_read),
      .mem_write  (mem_write),
      .read_data  (mem_read_data)
  );

  // Write-Back mux: ALU result, or loaded memory data
  assign write_back_data = mem_to_reg ? mem_read_data : alu_result;

  assign branch_target = pc_current + imm_out;
  assign branch_taken  = branch && alu_zero; // check if branch condition is met

endmodule