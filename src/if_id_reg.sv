//==============================================================================
// if_id_reg.sv
//
// The pipeline register between IF and ID. Every clock edge, it takes a
// snapshot of "what IF just fetched" and holds it steady for exactly one
// cycle, so ID has a stable value to work with while IF has already moved
// on to fetching the next instruction.
//
// No stall or flush inputs yet -- that's Phase 4. Right now this is a
// plain pass-through register: whatever comes in gets latched, every
// single cycle, no exceptions.
//==============================================================================

module if_id_reg (
    input  logic        clk,

    input  logic [31:0] pc_in,             // IF's pc_current -- this instruction's own address
    input  logic [31:0] pc_plus4_in,       // IF's pc_current + 4, carried forward for later stages
    input  logic [31:0] instruction_in,    // the raw 32-bit word instruction_memory just fetched

    output logic [31:0] pc_out,
    output logic [31:0] pc_plus4_out,
    output logic [31:0] instruction_out
);

  // This is the same idea as data_memory.sv's combinational-read-vs-
  // synchronous-write split, just applied to an entire pipeline stage
  // instead of one array: everything in this module is purely
  // always_ff/clocked -- there is no combinational path from input to
  // output anywhere in here. That's the whole point of a pipeline
  // register. IF and ID need to be working on two DIFFERENT instructions
  // at the same time (IF fetching instruction N+1 while ID decodes
  // instruction N) -- if this were just plain wires (like the "Instruction
  // Decode: just field slicing" section in the old single-cycle
  // datapath.sv), ID would see whatever IF is fetching THIS cycle, not
  // last cycle's fetch, and the pipeline stages would collapse into each
  // other instead of overlapping.
  initial begin
    pc_out          = 32'd0;
    pc_plus4_out    = 32'd0;
    instruction_out = 32'h00000013;   // NOP, so the pipeline starts "empty" cleanly
  end

  always_ff @(posedge clk) begin
    pc_out          <= pc_in;
    pc_plus4_out    <= pc_plus4_in;
    instruction_out <= instruction_in;
  end

endmodule
