//==============================================================================
// mem_wb_reg.sv
//
// The pipeline register between MEM and WB -- the last one. Both possible
// write-back values (the ALU result, and whatever was loaded from memory)
// are carried through raw, along with mem_to_reg as the select bit. The
// actual choosing between them happens in WB, on the other side of this
// register, not before it.
//
// rd_addr and reg_write also have to ride along all the way out here --
// they're what eventually drive register_file's rd_addr/reg_write write
// port back in datapath_pipelined.sv. Unlike the single-cycle design,
// where reg_write went straight from control_unit to register_file in
// the same cycle, here it has to survive three clock edges (ID/EX,
// EX/MEM, MEM/WB) attached to the same instruction before the write it
// describes actually happens.
//==============================================================================

module mem_wb_reg (
    input  logic        clk,

    input  logic [31:0] debug_pc_in,

    input  logic [31:0] alu_result_in,
    input  logic [31:0] mem_read_data_in,
    input  logic [4:0]  rd_addr_in,
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,

    output logic [31:0] debug_pc_out,

    output logic [31:0] alu_result_out,
    output logic [31:0] mem_read_data_out,
    output logic [4:0]  rd_addr_out,
    output logic        reg_write_out,
    output logic        mem_to_reg_out
);

  initial begin
    debug_pc_out      = 32'd0;
    alu_result_out    = 32'd0;
    mem_read_data_out = 32'd0;
    rd_addr_out       = 5'd0;
    reg_write_out     = 1'b0;
    mem_to_reg_out    = 1'b0;
  end

  always_ff @(posedge clk) begin
    debug_pc_out      <= debug_pc_in;
    alu_result_out    <= alu_result_in;
    mem_read_data_out <= mem_read_data_in;
    rd_addr_out       <= rd_addr_in;
    reg_write_out     <= reg_write_in;
    mem_to_reg_out    <= mem_to_reg_in;
  end

endmodule
