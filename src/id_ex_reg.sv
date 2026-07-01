//==============================================================================
// id_ex_reg.sv
//
// The pipeline register between ID and EX. By the time something reaches
// here, it's been fully decoded -- this register's job is just to hold
// all of it steady for one cycle so EX has stable inputs.
//
// rs1_addr/rs2_addr are carried through even though EX doesn't need them
// for anything in Phase 3 -- they're listed here because Phase 4's
// forwarding unit needs to compare them against EX/MEM and MEM/WB's
// rd_addr. Easy field to forget; including it now saves a rework later.
//
// branch_target is computed back in ID (PC + immediate) and just carried
// through here -- see datapath_pipelined.sv for why.
//
// debug_pc is NOT part of the real datapath -- it's the originating
// instruction's PC, threaded through purely so a testbench can print
// "this PC is now in EX" without guessing.
//
// Why control_unit's outputs (alu_op, reg_write, mem_read, etc.) show up
// as plain fields on a pipeline register, instead of being recomputed
// fresh every stage: in the single-cycle design, control_unit ran once
// per instruction and every module read its outputs in the same cycle.
// Here, control_unit still only runs ONCE per instruction -- in ID -- but
// that instruction's ALU operation doesn't happen until EX, one cycle
// later, and its memory access doesn't happen until MEM, two cycles
// later. The decode has to happen once and then physically travel
// alongside the instruction's data (rs1_data, rs2_data, imm) through
// every later pipeline register, so the right control signals are still
// sitting next to the right instruction by the time each stage needs
// them. Decoding fresh in every stage isn't an option -- by the time an
// instruction reaches MEM, the opcode bits that produced these signals
// are long gone, several instructions back in IF.
//==============================================================================

module id_ex_reg (
    input  logic        clk,

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

    input  logic [1:0]  alu_op_in,      // from control_unit -- which ALU op this instruction needs
    input  logic        alu_src_in,     // from control_unit -- ALU operand B: immediate (1) or rs2 (0)
    input  logic        mem_read_in,    // from control_unit -- LW will read data_memory in MEM
    input  logic        mem_write_in,   // from control_unit -- SW will write data_memory in MEM
    input  logic        reg_write_in,   // from control_unit -- does this instruction write a register at all
    input  logic        mem_to_reg_in,  // from control_unit -- write-back source select, used later in WB
    input  logic        branch_in,      // from control_unit -- "this is a BEQ" (NOT the same thing as
                                         // branch_taken -- that's branch_in ANDed with the ALU's zero
                                         // flag, and doesn't exist until EX actually runs the subtraction)

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
    // Everything starts off / zero. reg_write_out=0 and mem_write_out=0
    // matter most here -- they guarantee an empty pipeline slot can never
    // accidentally write a register or memory location before a real
    // instruction has actually arrived.
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

endmodule
