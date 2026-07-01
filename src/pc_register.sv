//==============================================================================
// pc_register.sv
//
// Holds the address of the instruction currently being fetched, and
// decides what address comes next: normally PC+4 (the next instruction in
// sequence), unless a branch was just taken, in which case it's the
// branch target instead.
//==============================================================================

module pc_register (
    input  logic        clk,
    input  logic        branch_taken,    // from datapath.sv: Branch control bit AND the ALU's zero flag
    input  logic [31:0] branch_target,   // PC + branch immediate, computed in datapath.sv
    output logic [31:0] pc_current
);

  logic [31:0] pc_next;
  // if branch_taken is true, the it will take the value from the branch target
  assign pc_next = branch_taken ? branch_target : (pc_current + 32'd4);

  initial begin
    pc_current = 32'd0;   // every program starts executing at address 0
  end

  always_ff @(posedge clk) begin
    pc_current <= pc_next;
  end

endmodule