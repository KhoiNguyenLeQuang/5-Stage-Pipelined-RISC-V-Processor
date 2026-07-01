//==============================================================================
// id_ex_reg.sv
//
// The pipeline register between ID and EX. New in Phase 4: a `flush`
// input. When asserted, EX gets a bubble next cycle instead of whatever
// ID actually decoded -- every control signal forced to 0 (crucially
// reg_write and mem_write), so the bubble is guaranteed inert as it
// continues through the rest of the pipeline.
//
// flush is asserted for two different reasons (see datapath_pipelined.sv):
//   - a load-use stall needs EX to do nothing for one cycle while the
//     real instruction waits in ID, OR
//   - a branch just resolved taken, and the instruction currently in ID
//     was fetched on the wrong path.
// These two conditions can't coincide (see hazard_detection_unit.sv's
// header), so there's no priority conflict to worry about -- flush just
// means "insert a bubble," regardless of which reason triggered it.
//
// rs1_addr/rs2_addr are carried through for Phase 4's forwarding unit to
// compare against EX/MEM and MEM/WB's rd_addr.
//
// branch_target is computed back in ID (PC + immediate) and just carried
// through here -- see datapath_pipelined.sv for why.
//
// debug_pc is NOT part of the real datapath -- it's the originating
// instruction's PC, threaded through purely so a testbench can print
// "this PC is now in EX" without guessing.
//==============================================================================

module id_ex_reg (
    input  logic        clk,
    input  logic        flush,

    input  logic [31:0] debug_pc_in,

    input  logic [31:0] pc_plus4_in,    // unused by this project's ISA --
                                         // plumbed through for future JAL/JALR
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] rs2_data_in,
    input  logic [31:0] imm_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [4:0]  rs1_addr_in,
    input  logic [4:0]  rs2_addr_in,
    input  logic [31:0] branch_target_in,

    input  logic [1:0]  alu_op_in,
    input  logic        alu_src_in,
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,
    input  logic        branch_in,

    output logic [31:0] debug_pc_out,

    output logic [31:0] pc_plus4_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] rs2_data_out,
    output logic [31:0] imm_out,
    output logic [4:0]  rd_addr_out,
    output logic [4:0]  rs1_addr_out,
    output logic [4:0]  rs2_addr_out,
    output logic [31:0] branch_target_out,

    output logic [1:0]  alu_op_out,
    output logic        alu_src_out,
    output logic        mem_read_out,
    output logic        mem_write_out,
    output logic        reg_write_out,
    output logic        mem_to_reg_out,
    output logic        branch_out
);

  initial begin
    debug_pc_out      = 32'd0;
    pc_plus4_out      = 32'd0;
    rs1_data_out      = 32'd0;
    rs2_data_out      = 32'd0;
    imm_out           = 32'd0;
    rd_addr_out       = 5'd0;
    rs1_addr_out      = 5'd0;
    rs2_addr_out      = 5'd0;
    branch_target_out = 32'd0;
    alu_op_out        = 2'd0;
    alu_src_out       = 1'b0;
    mem_read_out      = 1'b0;
    mem_write_out     = 1'b0;
    reg_write_out     = 1'b0;
    mem_to_reg_out    = 1'b0;
    branch_out        = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (flush) begin
      debug_pc_out      <= 32'd0;
      pc_plus4_out      <= 32'd0;
      rs1_data_out      <= 32'd0;
      rs2_data_out      <= 32'd0;
      imm_out           <= 32'd0;
      rd_addr_out       <= 5'd0;
      rs1_addr_out      <= 5'd0;
      rs2_addr_out      <= 5'd0;
      branch_target_out <= 32'd0;
      alu_op_out        <= 2'd0;
      alu_src_out       <= 1'b0;
      mem_read_out      <= 1'b0;
      mem_write_out     <= 1'b0;
      reg_write_out     <= 1'b0;
      mem_to_reg_out    <= 1'b0;
      branch_out        <= 1'b0;
    end else begin
      debug_pc_out      <= debug_pc_in;
      pc_plus4_out      <= pc_plus4_in;
      rs1_data_out      <= rs1_data_in;
      rs2_data_out      <= rs2_data_in;
      imm_out           <= imm_in;
      rd_addr_out       <= rd_addr_in;
      rs1_addr_out      <= rs1_addr_in;
      rs2_addr_out      <= rs2_addr_in;
      branch_target_out <= branch_target_in;
      alu_op_out        <= alu_op_in;
      alu_src_out       <= alu_src_in;
      mem_read_out      <= mem_read_in;
      mem_write_out     <= mem_write_in;
      reg_write_out     <= reg_write_in;
      mem_to_reg_out    <= mem_to_reg_in;
      branch_out        <= branch_in;
    end
  end

endmodule
