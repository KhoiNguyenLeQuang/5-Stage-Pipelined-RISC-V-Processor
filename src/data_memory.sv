//==============================================================================
// data_memory.sv
//
// Storage for LW/SW. This project's instruction subset only ever loads or
// stores a full 32-bit word at a time (no LB/LH/byte-level access), so --
// just like instruction_memory.sv -- the address coming in is a byte
// address, but storage internally is indexed one slot per word.
//==============================================================================

module data_memory #(
    parameter MEM_DEPTH_WORDS = 256
) (
    input  logic        clk,
    input  logic [31:0] addr,         // byte memory address (from the ALU: rs1 + imm)
    input  logic [31:0] write_data,   // value to store (SW only)
    input  logic        mem_read,
    input  logic        mem_write,
    output logic [31:0] read_data
);

  logic [31:0] mem [0:MEM_DEPTH_WORDS-1];

// Reset memory to zero
  initial begin
    for (int i = 0; i < MEM_DEPTH_WORDS; i++) begin
      mem[i] = 32'd0;
    end
  end

  // Reads are combinational. If mem_read isn't asserted this cycle, the
  // value just isn't used by anything downstream -- no harm driving it unconditionally.
  assign read_data = mem[addr[31:2]]; // byte address, so word index is addr[31:2]

  always_ff @(posedge clk) begin
    if (mem_write) begin
      mem[addr[31:2]] <= write_data;
    end
  end

endmodule