//==============================================================================
// single_cycle_tb.sv
//
// Phase 2 testbench: runs the datapath for comfortably more cycles
// than the test program needs, then prints final register and memory
// values so you can compare them against the expected-values table by
// eye. Also sets up waveform dumping for GTKWave.
//==============================================================================

`timescale 1ns/1ps

module single_cycle_tb;

  logic clk;

  datapath dut (
      .clk (clk)
  );

  // Free-running simulation clock. The period itself is arbitrary -- this
  // is a single-cycle design with no real timing constraints to meet.
  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, single_cycle_tb);

    // The test program needs 13 clock edges to fully execute. Running 20
    // gives margin without depending on that count being razor-precise --
    // any extra cycles just execute harmless NOPs.
    repeat (20) @(posedge clk);

    $display("-----------------------------------------------");
    $display(" Final register values");
    $display("-----------------------------------------------");
    for (int i = 0; i <= 11; i++) begin
      $display(" x%0d = %0d (0x%08h)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);
    end
    $display("-----------------------------------------------");
    $display(" Mem[0] = %0d (0x%08h)", dut.u_dmem.mem[0], dut.u_dmem.mem[0]);
    $display("-----------------------------------------------");

    $finish;
  end

endmodule