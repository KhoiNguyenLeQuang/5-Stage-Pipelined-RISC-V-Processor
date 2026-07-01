//==============================================================================
// if_id_reg.sv
//
// The pipeline register between IF and ID. Now has two new inputs beyond
// the Phase 3 version:
//
//   stall -- hold current contents instead of latching new ones. Used
//            when the hazard detection unit needs the instruction sitting
//            here to stay put for an extra cycle (load-use hazard).
//
//   flush -- force a bubble (NOP) instead of latching new contents. Used
//            when a branch resolves taken -- whatever IF just fetched was
//            fetched on the wrong path and needs to be cancelled.
//
// flush takes priority if both are ever asserted at once, though by this
// design's construction (see hazard_detection_unit.sv / datapath_pipelined.sv)
// the two conditions can never actually coincide.
//==============================================================================

module if_id_reg (
    input  logic        clk,
    input  logic        stall,
    input  logic        flush,

    input  logic [31:0] pc_in,
    input  logic [31:0] pc_plus4_in,
    input  logic [31:0] instruction_in,

    output logic [31:0] pc_out,
    output logic [31:0] pc_plus4_out,
    output logic [31:0] instruction_out
);

  initial begin
    pc_out          = 32'd0;
    pc_plus4_out    = 32'd0;
    instruction_out = 32'h00000013;   // NOP, so the pipeline starts "empty" cleanly
  end

  always_ff @(posedge clk) begin
    if (flush) begin
      pc_out          <= 32'd0;
      pc_plus4_out    <= 32'd0;
      instruction_out <= 32'h00000013;   // NOP
    end else if (!stall) begin
      pc_out          <= pc_in;
      pc_plus4_out    <= pc_plus4_in;
      instruction_out <= instruction_in;
    end
    // else (stall, no flush): hold current values -- no assignment needed
  end

endmodule
