//==============================================================================
// hazard_detection_unit.sv
//
// Forwarding fixes most data hazards, but not this one: if the instruction
// currently in EX is a LOAD, its loaded value doesn't exist yet -- it
// won't show up until MEM finishes reading data memory, next cycle.
// There's nothing to forward because the value hasn't been produced.
//
// So instead: if EX currently holds a load, and the instruction right
// behind it (currently in ID) needs that load's destination register,
// freeze everything upstream for exactly one cycle. That gives the load
// time to reach MEM (and then MEM/WB), at which point normal MEM/WB->EX
// forwarding picks up the value correctly.
//==============================================================================

module hazard_detection_unit (
    input  logic       ex_mem_read,     // is the instruction in EX a load?
    input  logic [4:0] ex_rd_addr,      // its destination register

    input  logic [4:0] id_rs1_addr,     // source registers of the instruction now in ID
    input  logic [4:0] id_rs2_addr,

    output logic       stall
);

  always_comb begin
    stall = ex_mem_read &&
            (ex_rd_addr != 5'd0) &&
            ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr));
  end

endmodule
