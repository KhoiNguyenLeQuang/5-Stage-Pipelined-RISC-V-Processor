//==============================================================================
// datapath_pipelined.sv
//
// Phase 4: the full 5-stage pipeline WITH hazard handling.
//   - Forwarding unit: resolves data hazards where the producer is 1 or 2
//     instructions ahead (EX/MEM->EX and MEM/WB->EX).
//   - Hazard detection unit: catches the one case forwarding can't --
//     load-use -- with a 1-cycle stall.
//   - Branch flush: a taken branch (resolved in EX) flushes IF/ID and
//     ID/EX, cancelling the 2 instructions fetched on the wrong path.
//
// With all three in place, this should now produce IDENTICAL final
// register/memory values to the Phase 2 single-cycle datapath, on the
// same test program -- that equivalence is the actual Phase 4 exit
// criteria from the project plan.
//==============================================================================

module datapath_pipelined #(
    parameter INIT_FILE = "program.hex"
) (
    input logic clk
);

  // ==========================================================================
  // IF stage
  // ==========================================================================
  logic [31:0] if_pc;
  logic [31:0] if_pc_plus4;
  logic [31:0] if_instruction;

  // Fed back from EX's combinational output below (not the EX/MEM register)
  // -- the redirect has to affect the very next fetch, not wait a cycle.
  logic        ex_branch_taken;
  logic [31:0] ex_branch_target;

  // Driven by hazard_detection_unit below -- declared here since
  // pc_register and if_id_reg (both instantiated in this section) need it.
  // Order doesn't matter for continuous/structural connections in HDL --
  // same pattern already used for ex_branch_taken/ex_branch_target above.
  logic        stall;

  pc_register u_pc (
      .clk           (clk),
      .stall         (stall),
      .branch_taken  (ex_branch_taken),
      .branch_target (ex_branch_target),
      .pc_current    (if_pc)
  );

  instruction_memory #(
      .INIT_FILE (INIT_FILE)
  ) u_imem (
      .addr        (if_pc),
      .instruction (if_instruction)
  );

  assign if_pc_plus4 = if_pc + 32'd4;

  // ==========================================================================
  // IF/ID
  // ==========================================================================
  logic [31:0] id_pc, id_pc_plus4, id_instruction;

  if_id_reg u_if_id (
      .clk             (clk),
      .stall           (stall),
      .flush           (ex_branch_taken),
      .pc_in           (if_pc),
      .pc_plus4_in     (if_pc_plus4),
      .instruction_in  (if_instruction),
      .pc_out          (id_pc),
      .pc_plus4_out    (id_pc_plus4),
      .instruction_out (id_instruction)
  );

  // ==========================================================================
  // ID stage
  // ==========================================================================
  logic [6:0] id_opcode;
  logic [2:0] id_funct3;
  logic       id_funct7_5;
  logic [4:0] id_rs1_addr, id_rs2_addr, id_rd_addr;

  assign id_opcode   = id_instruction[6:0];
  assign id_funct3   = id_instruction[14:12];
  assign id_funct7_5 = id_instruction[30];
  assign id_rs1_addr = id_instruction[19:15];
  assign id_rs2_addr = id_instruction[24:20];
  assign id_rd_addr  = id_instruction[11:7];

  logic [1:0] id_alu_op;
  logic       id_reg_write, id_mem_read, id_mem_write, id_mem_to_reg, id_branch, id_alu_src;

  control_unit u_control (
      .opcode     (id_opcode),
      .funct3     (id_funct3),
      .funct7_5   (id_funct7_5),
      .alu_op     (id_alu_op),
      .reg_write  (id_reg_write),
      .mem_read   (id_mem_read),
      .mem_write  (id_mem_write),
      .mem_to_reg (id_mem_to_reg),
      .branch     (id_branch),
      .alu_src    (id_alu_src)
  );

  logic [31:0] id_rs1_data, id_rs2_data;

  // Register file's write port is driven by the WB stage, far below --
  // one shared instance, read in ID, written in WB.
  logic [4:0]  wb_rd_addr;
  logic [31:0] wb_write_back_data;
  logic        wb_reg_write;

  register_file u_regfile (
      .clk       (clk),
      .rs1_addr  (id_rs1_addr),
      .rs2_addr  (id_rs2_addr),
      .rs1_data  (id_rs1_data),
      .rs2_data  (id_rs2_data),
      .rd_addr   (wb_rd_addr),
      .rd_data   (wb_write_back_data),
      .reg_write (wb_reg_write)
  );

  logic [31:0] id_imm;

  imm_generator u_immgen (
      .instruction (id_instruction),
      .imm_out     (id_imm)
  );

  // Branch target computed here, in ID -- PC (the branch instruction's
  // own address) + immediate. By the time we reach ID/EX, only PC+4 is
  // carried forward (per the plan), so this has to be computed now while
  // the real PC is still available, and the RESULT carried onward instead.
  logic [31:0] id_branch_target;
  assign id_branch_target = id_pc + id_imm;

  // ---- Hazard detection: load-use hazard, checked against EX's occupant ----
  // (ex_mem_read / ex_rd_addr are ID/EX's OUTPUTS -- the instruction
  // currently occupying EX -- declared further below where id_ex_reg is
  // instantiated. Same forward-reference pattern as stall/branch above.)
  logic ex_mem_read;
  logic [4:0] ex_rd_addr;

  hazard_detection_unit u_hazard (
      .ex_mem_read (ex_mem_read),
      .ex_rd_addr  (ex_rd_addr),
      .id_rs1_addr (id_rs1_addr),
      .id_rs2_addr (id_rs2_addr),
      .stall       (stall)
  );

  // ID/EX gets a bubble if EITHER a load-use stall OR a branch flush is in
  // effect this cycle. These two can never both be true on the same cycle
  // -- see hazard_detection_unit.sv's header -- so there's no priority
  // question, just "insert a bubble if either fires."
  logic id_ex_flush;
  assign id_ex_flush = stall || ex_branch_taken;

  // ==========================================================================
  // ID/EX
  // ==========================================================================
  logic [31:0] ex_debug_pc;
  logic [31:0] ex_pc_plus4;
  logic [31:0] ex_rs1_data, ex_rs2_data, ex_imm;
  logic [4:0]  ex_rs1_addr, ex_rs2_addr;
  logic [31:0] ex_branch_target_staged;
  logic [1:0]  ex_alu_op;
  logic        ex_alu_src, ex_mem_write, ex_reg_write, ex_mem_to_reg, ex_branch;

  id_ex_reg u_id_ex (
      .clk               (clk),
      .flush             (id_ex_flush),
      .debug_pc_in       (id_pc),
      .pc_plus4_in       (id_pc_plus4),
      .rs1_data_in       (id_rs1_data),
      .rs2_data_in       (id_rs2_data),
      .imm_in            (id_imm),
      .rd_addr_in        (id_rd_addr),
      .rs1_addr_in       (id_rs1_addr),
      .rs2_addr_in       (id_rs2_addr),
      .branch_target_in  (id_branch_target),
      .alu_op_in         (id_alu_op),
      .alu_src_in        (id_alu_src),
      .mem_read_in       (id_mem_read),
      .mem_write_in      (id_mem_write),
      .reg_write_in      (id_reg_write),
      .mem_to_reg_in     (id_mem_to_reg),
      .branch_in         (id_branch),

      .debug_pc_out      (ex_debug_pc),
      .pc_plus4_out      (ex_pc_plus4),
      .rs1_data_out      (ex_rs1_data),
      .rs2_data_out      (ex_rs2_data),
      .imm_out           (ex_imm),
      .rd_addr_out       (ex_rd_addr),
      .rs1_addr_out      (ex_rs1_addr),
      .rs2_addr_out      (ex_rs2_addr),
      .branch_target_out (ex_branch_target_staged),
      .alu_op_out        (ex_alu_op),
      .alu_src_out       (ex_alu_src),
      .mem_read_out      (ex_mem_read),
      .mem_write_out     (ex_mem_write),
      .reg_write_out     (ex_reg_write),
      .mem_to_reg_out    (ex_mem_to_reg),
      .branch_out        (ex_branch)
  );

  // ==========================================================================
  // EX stage
  // ==========================================================================

  // ---- Forwarding: does EX need a value still sitting in EX/MEM or MEM/WB? ----
  // (mem_rd_addr/mem_reg_write and wb_rd_addr/wb_reg_write are declared
  // further below, where EX/MEM and MEM/WB actually live -- forward
  // reference, same as elsewhere in this file.)
  logic [4:0] mem_rd_addr;
  logic       mem_reg_write;

  logic [1:0] forward_a, forward_b;

  forwarding_unit u_forward (
      .ex_rs1_addr   (ex_rs1_addr),
      .ex_rs2_addr   (ex_rs2_addr),
      .mem_rd_addr   (mem_rd_addr),
      .mem_reg_write (mem_reg_write),
      .wb_rd_addr    (wb_rd_addr),
      .wb_reg_write  (wb_reg_write),
      .forward_a     (forward_a),
      .forward_b     (forward_b)
  );

  logic [31:0] mem_alu_result;   // EX/MEM's forwarding source (declared below, forward-referenced)

  logic [31:0] ex_operand_a;
  logic [31:0] forwarded_rs2;    // used by BOTH the ALU (via ALUSrc mux) and SW's stored value

  always_comb begin
    unique case (forward_a)
      2'b10:   ex_operand_a = mem_alu_result;      // EX/MEM
      2'b01:   ex_operand_a = wb_write_back_data;  // MEM/WB
      default: ex_operand_a = ex_rs1_data;         // no forwarding
    endcase

    unique case (forward_b)
      2'b10:   forwarded_rs2 = mem_alu_result;
      2'b01:   forwarded_rs2 = wb_write_back_data;
      default: forwarded_rs2 = ex_rs2_data;
    endcase
  end

  logic [31:0] ex_operand_b;
  logic [31:0] ex_alu_result;
  logic        ex_alu_zero;

  assign ex_operand_b = ex_alu_src ? ex_imm : forwarded_rs2;

  alu u_alu (
      .operand_a (ex_operand_a),
      .operand_b (ex_operand_b),
      .alu_op    (ex_alu_op),
      .result    (ex_alu_result),
      .zero      (ex_alu_zero)
  );

  // The branch decision resolves here, combinationally, this cycle -- and
  // feeds straight back up to the PC mux and the flush inputs above, so
  // it affects the very next fetch and cancels the 2 wrong-path
  // instructions already in the pipeline.
  assign ex_branch_taken  = ex_branch && ex_alu_zero;
  assign ex_branch_target = ex_branch_target_staged;

  // ==========================================================================
  // EX/MEM
  // ==========================================================================
  logic [31:0] mem_debug_pc;
  logic [31:0] mem_rs2_data;
  logic        mem_mem_read, mem_mem_write, mem_mem_to_reg;
  logic        mem_branch_taken;
  logic [31:0] mem_branch_target;

  ex_mem_reg u_ex_mem (
      .clk               (clk),
      .debug_pc_in       (ex_debug_pc),
      .alu_result_in     (ex_alu_result),
      .rs2_data_in       (forwarded_rs2),   // <-- forwarded value, not raw ex_rs2_data (fixes SW hazard)
      .rd_addr_in        (ex_rd_addr),
      .mem_read_in       (ex_mem_read),
      .mem_write_in      (ex_mem_write),
      .reg_write_in      (ex_reg_write),
      .mem_to_reg_in     (ex_mem_to_reg),
      .branch_taken_in   (ex_branch_taken),
      .branch_target_in  (ex_branch_target),

      .debug_pc_out      (mem_debug_pc),
      .alu_result_out    (mem_alu_result),
      .rs2_data_out      (mem_rs2_data),
      .rd_addr_out       (mem_rd_addr),
      .mem_read_out      (mem_mem_read),
      .mem_write_out     (mem_mem_write),
      .reg_write_out     (mem_reg_write),
      .mem_to_reg_out    (mem_mem_to_reg),
      .branch_taken_out  (mem_branch_taken),
      .branch_target_out (mem_branch_target)
  );

  // ==========================================================================
  // MEM stage
  // ==========================================================================
  logic [31:0] mem_read_data;

  data_memory u_dmem (
      .clk        (clk),
      .addr       (mem_alu_result),
      .write_data (mem_rs2_data),
      .mem_read   (mem_mem_read),
      .mem_write  (mem_mem_write),
      .read_data  (mem_read_data)
  );

  // ==========================================================================
  // MEM/WB
  // ==========================================================================
  logic [31:0] wb_debug_pc;
  logic [31:0] wb_alu_result, wb_mem_read_data;
  logic        wb_mem_to_reg;

  mem_wb_reg u_mem_wb (
      .clk               (clk),
      .debug_pc_in       (mem_debug_pc),
      .alu_result_in     (mem_alu_result),
      .mem_read_data_in  (mem_read_data),
      .rd_addr_in        (mem_rd_addr),
      .reg_write_in      (mem_reg_write),
      .mem_to_reg_in     (mem_mem_to_reg),

      .debug_pc_out      (wb_debug_pc),
      .alu_result_out    (wb_alu_result),
      .mem_read_data_out (wb_mem_read_data),
      .rd_addr_out       (wb_rd_addr),
      .reg_write_out     (wb_reg_write),
      .mem_to_reg_out    (wb_mem_to_reg)
  );

  // ==========================================================================
  // WB stage -- result feeds back up to the register file's write port,
  // AND up to the forwarding unit's MEM/WB source (both uses of the exact
  // same value).
  // ==========================================================================
  assign wb_write_back_data = wb_mem_to_reg ? wb_mem_read_data : wb_alu_result;

endmodule
