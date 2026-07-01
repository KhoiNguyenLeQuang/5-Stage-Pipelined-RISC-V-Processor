//==============================================================================
// register_file.sv
//
// The CPU's 32 general-purpose registers (x0-x31), each 32 bits wide.
//
// Two things make this more than a plain array:
//   1. x0 is hardwired to zero -- reading it always returns 0, and writes
//      to it are silently thrown away. This is a RISC-V architectural rule,
//      not a choice this design makes.
//   2. "Write-read bypass": if something writes to a register on the same
//      clock edge that something else is reading that same register, the
//      read returns the NEW value being written, not the old stored one.
//      Single-cycle doesn't strictly need this (only one instruction is
//      ever active at a time), but it matters once you pipeline -- it lets
//      WB (writing back register N) and ID (reading register N) happen on
//      the same clock edge for two different instructions without needing
//      extra hazard-handling logic. Building it in now means Phase 4 has
//      one less hazard case to worry about.
//==============================================================================

module register_file (
    input  logic        clk,

    input  logic [4:0]  rs1_addr,   // which register to read (source 1)
    input  logic [4:0]  rs2_addr,   // which register to read (source 2)
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,

    input  logic [4:0]  rd_addr,    // which register to write
    input  logic [31:0] rd_data,    // value to write
    input  logic        reg_write   // write enable
);

  logic [31:0] regs [0:31];

  // Simulation-only startup value -- without this, an unwritten register
  // would read back as 'X' (unknown) the first time something reads it,
  // which makes early debugging confusing for no good reason.
  initial begin
    for (int i = 0; i < 32; i++) begin
      regs[i] = 32'd0;
    end
  end

  // Reads: combinational (no clock needed -- the value is just there)
  always_comb begin
    if (rs1_addr == 5'd0)
      rs1_data = 32'd0;
    else if (reg_write && (rd_addr == rs1_addr))
      rs1_data = rd_data;            // write-read bypass
    else
      rs1_data = regs[rs1_addr];

    if (rs2_addr == 5'd0)
      rs2_data = 32'd0;
    else if (reg_write && (rd_addr == rs2_addr))
      rs2_data = rd_data;            // write-read bypass
    else
      rs2_data = regs[rs2_addr];
  end

  // Write: synchronous, on the rising clock edge
  always_ff @(posedge clk) begin
    if (reg_write && (rd_addr != 5'd0)) begin
      regs[rd_addr] <= rd_data;
    end
  end

endmodule