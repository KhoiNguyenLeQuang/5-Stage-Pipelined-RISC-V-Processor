//==============================================================================
// datapath_pipelined.sv
//
// The 5-stage pipeline skeleton: IF -> ID -> EX -> MEM -> WB, with a
// pipeline register at every boundary. This is Phase 3 -- there is no
// forwarding, no stalling, and no flush logic yet. That means:
//
//   - A data-dependent instruction reading a register too soon WILL get
//     a stale value (the producer hasn't reached WB yet).
//   - A taken branch's 2 wrong-path instructions WILL still execute
//     (nothing cancels them).
//
// Both are expected and correct for this phase -- Phase 4 fixes both.
// The thing THIS phase needs to get right is structural: each instruction
// should advance exactly one stage per clock cycle, with the right data
// arriving at the right time.
//
// How to read this against the old single-cycle datapath.sv: every
// module instantiated here (pc_register, instruction_memory,
// control_unit, register_file, imm_generator, alu, data_memory) is
// IDENTICAL to before -- same ports, same internal logic, same job. What
// changed is everything AROUND them: instead of one shared pc_current /
// instruction / alu_result / etc. that the whole datapath reads in the
// same cycle, there are now five separate "generations" of those same
// signals in flight simultaneously (if_..., id_..., ex_..., mem_...,
// wb_...), one per pipeline stage, each one cycle older than the last.
// The prefix on a signal name tells you which stage currently owns it.
//==============================================================================

module datapath_pipelined #(
    parameter INIT_FILE = "program.hex"
) (
    input logic clk
);

  // ==========================================================================
  // IF stage
  // ==========================================================================
  logic [31:0] if_pc;          // this cycle's fetch address (== pc_current from before)
  logic [31:0] if_pc_plus4;
  logic [31:0] if_instruction;

  // branch_taken/branch_target are fed back from EX's COMBINATIONAL output
  // below (not from the EX/MEM register) - the redirect has to affect the
  // very next fetch, not wait an extra cycle.
  logic        ex_branch_taken;
  logic [31:0] ex_branch_target;

  // Same pc_register module as the single-cycle design, unmodified - it
  // doesn't know or care that it's now sitting inside a pipeline. Its
  // branch_taken/branch_target inputs are wired to EX's combinational
  // outputs further down this file (ex_branch_taken/ex_branch_target),
  // NOT to anything coming out of a pipeline register - see the EX
  // stage comment below for why that distinction matters.
  pc_register u_pc (
      .clk           (clk),
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
  // This is where the pipelining actually happens - everything above is
  // wires, computed fresh every cycle. From here down, what control_unit
  // and friends see is one cycle STALE relative to if_pc/if_instruction:
  // id_instruction is whatever IF fetched LAST cycle, while IF (above)
  // has already moved on to fetching the NEXT instruction this same
  // cycle. That overlap - two different instructions, two different
  // stages, same clock edge - is the entire point of pipelining.
  logic [31:0] id_pc, id_pc_plus4, id_instruction;

  if_id_reg u_if_id (
      .clk             (clk),
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
  // Identical field slicing to the single-cycle datapath.sv's "Instruction
  // Decode" section - the only difference is it now reads id_instruction
  // (one cycle stale, from the IF/ID register) instead of reading
  // instruction directly off instruction_memory's output.
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

  // Same control_unit module as before, unmodified. It still only looks
  // at opcode/funct3/funct7_5 and produces the same 7 outputs - it has
  // no idea it's now running once per cycle on a constant stream of
  // instructions instead of once per "the" instruction. Note this only
  // DECODES the instruction; it doesn't compute anything (no ALU result,
  // no branch_taken) - those still happen later, in EX.
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

  // Register file's write port is driven by the WB stage, far below -
  // one shared instance, read in ID, written in WB.
  //
  // The write-read bypass built into register_file.sv (see that file's
  // header) is what makes this safe: WB (finishing instruction N) and ID
  // (reading registers for instruction N+3, since 3 other instructions
  // are mid-flight between them) can land on the exact same clock edge.
  // Without the bypass, ID would read register_file's OLD stored value
  // and only see instruction N's write one cycle too late. This is
  // exactly the scenario the Phase 2 register_file.sv comment said
  // pipelining would need - it's now actually being exercised here.
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

  // Branch target computed here, in ID - PC (the branch instruction's
  // own address) + immediate. By the time we reach ID/EX, only PC+4 is
  // carried forward (per the plan), so this has to be computed now while
  // the real PC is still available, and the RESULT carried onward instead.
  //
  // This is the exact same pc_current + imm_out addition the single-cycle
  // datapath did (there it was called branch_target, computed once,
  // right before being used). Here it has to be computed one stage
  // earlier than where it's actually consumed (EX), purely because id_pc
  // - this instruction's own fetch address - only exists as a live
  // signal during ID. One stage later (EX), all that's left of "this
  // instruction's PC" is id_ex_reg's debug_pc field, which isn't wired
  // into any real computation - so the addition has to happen now, and
  // only the finished RESULT (id_branch_target) rides the pipeline
  // register forward.
  logic [31:0] id_branch_target;
  assign id_branch_target = id_pc + id_imm;

  // ==========================================================================
  // ID/EX
  // ==========================================================================
  // Every signal control_unit/imm_generator/register_file produced above
  // gets latched here, all at once, so they all advance to EX together,
  // still attached to the same instruction. This is the field-by-field
  // mapping into id_ex_reg's ports - see id_ex_reg.sv for what each
  // field is for and why it has to travel this way.
  logic [31:0] ex_debug_pc;
  logic [31:0] ex_pc_plus4;
  logic [31:0] ex_rs1_data, ex_rs2_data, ex_imm;
  logic [4:0]  ex_rd_addr, ex_rs1_addr, ex_rs2_addr;
  logic [31:0] ex_branch_target_staged;
  logic [1:0]  ex_alu_op;
  logic        ex_alu_src, ex_mem_read, ex_mem_write, ex_reg_write, ex_mem_to_reg, ex_branch;

  id_ex_reg u_id_ex (
      .clk               (clk),
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
  // Same ALU-source mux and alu module as the single-cycle design -
  // ex_alu_src picks between the immediate and rs2's value exactly the
  // way alu_src did before, just now reading the ID/EX-staged copies of
  // those signals instead of the live ones.
  logic [31:0] ex_operand_b;
  logic [31:0] ex_alu_result;
  logic        ex_alu_zero;

  assign ex_operand_b = ex_alu_src ? ex_imm : ex_rs2_data;

  alu u_alu (
      .operand_a (ex_rs1_data),
      .operand_b (ex_operand_b),
      .alu_op    (ex_alu_op),
      .result    (ex_alu_result),
      .zero      (ex_alu_zero)
  );

  // The branch decision resolves here, combinationally, this cycle - and
  // feeds straight back up to the PC mux at the top of this file, so it
  // affects the very next fetch. (No flush logic yet, so the 2
  // instructions already fetched on the wrong path will still run - see
  // the file header.)
  //
  // This is exactly the branch/branch_taken/branch_target relationship
  // from the single-cycle design, unchanged in substance, just split
  // across stages now:
  //   - ex_branch        ("is this instruction a BEQ at all") was decided
  //     back in ID by control_unit, then just rode the ID/EX register
  //     here as branch_in/branch_out - pure opcode decode, no math.
  //   - ex_alu_zero       ("did rs1 - rs2 come out to 0") is brand new
  //     this cycle - the ALU directly above just computed it.
  //   - ex_branch_taken   is the AND of those two - "should we actually
  //     jump" -- and it cannot exist any earlier than THIS line, because
  //     it needs alu_zero, and alu_zero doesn't exist until the ALU above
  //     has run.
  //   - ex_branch_target  is NOT computed here - it's id_branch_target
  //     (pc_current + imm_out), computed back in ID, simply staged
  //     through the ID/EX register and renamed on the way out
  //     (branch_target_out -> ex_branch_target_staged). EX doesn't add
  //     anything to it; it just forwards the already-finished address
  //     alongside branch_taken so both arrive at the PC mux together.
  //
  // Critically, ex_branch_taken/ex_branch_target feed pc_register at the
  // TOP of this file as plain combinational wires, not through a pipeline
  // register - if they had to wait for the EX/MEM register like
  // everything else this stage produces, the corrected fetch wouldn't
  // happen until one cycle later than necessary, which would mean 3
  // wrong-path instructions in flight instead of 2.
  assign ex_branch_taken  = ex_branch && ex_alu_zero;
  assign ex_branch_target = ex_branch_target_staged;

  // ==========================================================================
  // EX/MEM
  // ==========================================================================
  // branch_taken_in/branch_target_in here are recording a decision that's
  // already old news by the time it lands - the actual PC redirect
  // already happened, one cycle earlier, straight out of the EX stage
  // above. These staged copies exist for Phase 4 (flush logic needs to
  // know, while looking at MEM, "was the instruction that's now in EX/MEM
  // a taken branch").
  logic [31:0] mem_debug_pc;
  logic [31:0] mem_alu_result, mem_rs2_data;
  logic [4:0]  mem_rd_addr;
  logic        mem_mem_read, mem_mem_write, mem_reg_write, mem_mem_to_reg;
  logic        mem_branch_taken;
  logic [31:0] mem_branch_target;

  ex_mem_reg u_ex_mem (
      .clk               (clk),
      .debug_pc_in       (ex_debug_pc),
      .alu_result_in     (ex_alu_result),
      .rs2_data_in       (ex_rs2_data),
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
  // Same data_memory module as the single-cycle design, unmodified -
  // still a combinational read / synchronous write, exactly as discussed
  // for the single-cycle version. mem_alu_result here plays the same role
  // alu_result did before: for LW/SW it's an address (rs1 + imm); for
  // everything else it's just a result passing through untouched (LW/SW
  // are the only opcodes where mem_mem_read/mem_mem_write are ever 1, so
  // a non-memory instruction's mem_alu_result gets fed in as an address
  // here but is simply never acted on).
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
  // The last pipeline boundary - one more clock edge between "memory
  // read finished" and "write-back actually happens."
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
  // WB stage - result feeds back up to the register file's write port
  // ==========================================================================
  // The exact same write-back mux from the single-cycle datapath.sv,
  // unchanged in logic - mem_to_reg still just picks "loaded value" vs
  // "ALU result." The only thing that's different is timing: wb_rd_addr
  // and wb_reg_write (declared up in the ID stage section, since that's
  // where register_file needed them as inputs) are driven from all the
  // way down here, four pipeline registers and four clock edges after
  // that same instruction was originally fetched in IF.
  assign wb_write_back_data = wb_mem_to_reg ? wb_mem_read_data : wb_alu_result;

endmodule
