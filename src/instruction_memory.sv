//==============================================================================
// instruction_memory.sv
//
// Read-only program storage. The PC feeds in a byte address; this module
// hands back the 32-bit instruction sitting there.
//==============================================================================

module instruction_memory #(
    parameter MEM_DEPTH_WORDS = 256,        // how many instructions of ROM
    parameter INIT_FILE = "program.hex"     // hex file loaded at sim start
) (
    input  logic [31:0] addr,               // byte address (comes from PC)
    output logic [31:0] instruction
);

  logic [31:0] mem [0:MEM_DEPTH_WORDS-1];

  initial begin
    for (int i = 0; i < MEM_DEPTH_WORDS; i++) begin
      mem[i] = 32'h00000013;   // ADDI x0, x0, 0 == NOP
    end

    $readmemh(INIT_FILE, mem);
  end

  assign instruction = mem[addr[31:2]];

endmodule