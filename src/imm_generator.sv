//==============================================================================
// imm_generator.sv
//
// RISC-V has alot of different instruction formats, and this module is used
// to look at the opcode, figure out the format, and put the value back as a 32
// bit value.
// Used between the modules.
//==============================================================================

module imm_generator (
    input  logic [31:0] instruction,
    output logic [31:0] imm_out    // feeds into the ALU-source mux as one of two candidates for the ALU's second operand.
);

  logic [6:0]  opcode;
  logic        sign_bit;     // instruction[31] -- the universal sign bit
  logic [11:0] i_imm_bits;   // instruction[31:20], I-type
  logic [6:0]  s_imm_hi;     // instruction[31:25], S-type
  logic [4:0]  s_imm_lo;     // instruction[11:7],  S-type
  logic        b_imm_11;     // instruction[7],     B-type
  logic [5:0]  b_imm_10_5;   // instruction[30:25], B-type
  logic [3:0]  b_imm_4_1;    // instruction[11:8],  B-type

  assign opcode     = instruction[6:0];
  assign sign_bit   = instruction[31];
  assign i_imm_bits = instruction[31:20];
  assign s_imm_hi   = instruction[31:25];
  assign s_imm_lo   = instruction[11:7];
  assign b_imm_11   = instruction[7];
  assign b_imm_10_5 = instruction[30:25];
  assign b_imm_4_1  = instruction[11:8];

  localparam logic [6:0] OPC_RTYPE  = 7'b0110011;   // ADD/SUB/AND/OR -- no immediate
  localparam logic [6:0] OPC_ADDI   = 7'b0010011;   // I-type
  localparam logic [6:0] OPC_LOAD   = 7'b0000011;   // I-type (LW)
  localparam logic [6:0] OPC_STORE  = 7'b0100011;   // S-type (SW)
  localparam logic [6:0] OPC_BRANCH = 7'b1100011;   // B-type (BEQ)

  always_comb begin
    unique case (opcode)

      OPC_ADDI, OPC_LOAD: begin
        // I-type: a contiguous 12-bit immediate -- just sign-extend it.
        imm_out = {{20{sign_bit}}, i_imm_bits};
      end

      OPC_STORE: begin
        // S-type: the 12-bit immediate is split into two pieces because
        // the destination register field (rd) was repurposed to hold the
        // bottom half instead -- S-type instructions don't have a
        // destination register, so that field was free to reuse. Glue
        // the two pieces back together in the right order, then
        // sign-extend.
        imm_out = {{20{sign_bit}}, s_imm_hi, s_imm_lo};
      end

      OPC_BRANCH: begin
        // B-type: the most scrambled one. The immediate bits are
        // deliberately rearranged so the sign bit always lands in
        // instruction[31] regardless of format, keeping the
        // sign-extension hardware identical across every format. Bit 0
        // of a branch offset is never stored at all -- it's always 0
        // (branch targets are always an even number of bytes away) -- so
        // a literal 0 is tacked on instead of being read from anywhere.
        imm_out = {{19{sign_bit}}, sign_bit, b_imm_11, b_imm_10_5, b_imm_4_1, 1'b0};
      end

      default: begin
        // R-type (and anything unrecognized): no immediate is used here,
        // so the value is irrelevant. Zero is a harmless default.
        imm_out = 32'd0;
      end

    endcase
  end

endmodule