//==============================================================================
// ex_mem_reg.sv
//
// The pipeline register between EX and MEM. By here, the ALU has already
// produced its result and the branch decision is already known -- this
// register just holds it all steady for one cycle so MEM has stable
// inputs.
//
// mem_to_reg is carried through even though MEM doesn't use it -- it's
// needed in WB (the final mux: ALU result or loaded data), so it has to
// physically pass through this register to get there.
//
// branch_taken/branch_target are captured here mainly as a record for
// Phase 4's flush logic to reference -- the actual PC redirect already
// happens straight out of EX, combinationally, one cycle earlier than
// this register would make it available (see datapath_pipelined.sv).
//==============================================================================

module ex_mem_reg (
    input  logic        clk,

    input  logic [31:0] debug_pc_in,

    input  logic [31:0] alu_result_in,   // the address for LW/SW, OR the result for R-type/ADDI
    input  logic [31:0] rs2_data_in,     // for SW
    input  logic [4:0]  rd_addr_in,
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,
    input  logic        branch_taken_in,   // branch_in (control_unit) AND alu_zero, already
                                            // combined back in EX -- see the long discussion in
                                            // datapath_pipelined.sv: this is "should we have
                                            // jumped," not "is this a branch instruction"
    input  logic [31:0] branch_target_in,  // pc_current + imm_out, computed back in ID --
                                            // "where we WOULD have jumped to," whether or not
                                            // branch_taken_in ends up being 1

    output logic [31:0] debug_pc_out,

    output logic [31:0] alu_result_out,
    output logic [31:0] rs2_data_out,
    output logic [4:0]  rd_addr_out,
    output logic        mem_read_out,
    output logic        mem_write_out,
    output logic        reg_write_out,
    output logic        mem_to_reg_out,
    output logic        branch_taken_out,
    output logic [31:0] branch_target_out
);

  initial begin
    debug_pc_out      = 32'd0;
    alu_result_out    = 32'd0;
    rs2_data_out      = 32'd0;
    rd_addr_out       = 5'd0;
    mem_read_out      = 1'b0;
    mem_write_out     = 1'b0;
    reg_write_out     = 1'b0;
    mem_to_reg_out    = 1'b0;
    branch_taken_out  = 1'b0;
    branch_target_out = 32'd0;
  end

  always_ff @(posedge clk) begin
    debug_pc_out      <= debug_pc_in;
    alu_result_out    <= alu_result_in;
    rs2_data_out      <= rs2_data_in;
    rd_addr_out       <= rd_addr_in;
    mem_read_out      <= mem_read_in;
    mem_write_out     <= mem_write_in;
    reg_write_out     <= reg_write_in;
    mem_to_reg_out    <= mem_to_reg_in;
    branch_taken_out  <= branch_taken_in;
    branch_target_out <= branch_target_in;
  end

endmodule
