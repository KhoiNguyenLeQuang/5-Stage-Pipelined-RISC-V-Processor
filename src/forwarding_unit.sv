//==============================================================================
// forwarding_unit.sv
//
// The instruction sitting in EX read its operands back in ID, one cycle
// ago -- from the register file. If the instruction that's SUPPOSED to
// produce one of those operands hasn't written it back yet, that read was
// stale. This unit checks for exactly that: does EX/MEM or MEM/WB
// currently hold a not-yet-committed result for the same register EX is
// about to use?
//
// EX/MEM (1 instruction ahead) takes priority over MEM/WB (2 instructions
// ahead) when both would apply to the same register -- EX/MEM is the more
// recent result, and it's what a real chip would give you first anyway.
//==============================================================================

module forwarding_unit (
    input  logic [4:0] ex_rs1_addr,
    input  logic [4:0] ex_rs2_addr,

    input  logic [4:0] mem_rd_addr,     // instruction currently in MEM (EX/MEM's rd)
    input  logic       mem_reg_write,

    input  logic [4:0] wb_rd_addr,      // instruction currently in WB (MEM/WB's rd)
    input  logic       wb_reg_write,

    output logic [1:0] forward_a,       // 00 = no forward, 01 = from MEM/WB, 10 = from EX/MEM
    output logic [1:0] forward_b
);

  always_comb begin
    // operand A (rs1)
    if (mem_reg_write && (mem_rd_addr != 5'd0) && (mem_rd_addr == ex_rs1_addr))
      forward_a = 2'b10;
    else if (wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == ex_rs1_addr))
      forward_a = 2'b01;
    else
      forward_a = 2'b00;

    // operand B (rs2) -- identical logic, independent decision
    if (mem_reg_write && (mem_rd_addr != 5'd0) && (mem_rd_addr == ex_rs2_addr))
      forward_b = 2'b10;
    else if (wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == ex_rs2_addr))
      forward_b = 2'b01;
    else
      forward_b = 2'b00;
  end

endmodule
