//==============================================================================
// pipeline_tb.sv
//
// Phase 3 testbench. This is NOT checking final register values -- with no
// forwarding or flush logic yet, those are expected to be wrong (see
// datapath_pipelined.sv's header). What this checks instead: does each
// instruction advance exactly one pipeline stage per clock cycle?
//
// Each cycle, it prints the PC currently sitting in each of the 5 stages.
// You should see a clean "staircase": the PC in IF this cycle should be
// the PC that was in ID last cycle, which should be the PC that was in EX
// the cycle before that, and so on -- one stage to the right, every cycle.
//
// The first few cycles will show 0x00000000 in stages that haven't been
// reached yet (the pipeline is still "filling") -- that's expected, not
// an error. Once it fills (after cycle 4 or so), the real staircase
// becomes clearly visible.
//==============================================================================

`timescale 1ns/1ps

module pipeline_tb;

  logic clk;

  datapath_pipelined dut (
      .clk (clk)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  int cycle_num;

  initial begin
    $dumpfile("waves_pipelined.vcd");
    $dumpvars(0, pipeline_tb);

    cycle_num = 0;

    $display("cyc | IF(pc)     ID(pc)     EX(pc)     MEM(pc)    WB(pc)");
    $display("----+--------------------------------------------------");

    repeat (25) begin
      @(posedge clk);
      cycle_num = cycle_num + 1;
      $display(" %3d | 0x%08h 0x%08h 0x%08h 0x%08h 0x%08h",
                cycle_num,
                dut.if_pc,
                dut.id_pc,
                dut.ex_debug_pc,
                dut.mem_debug_pc,
                dut.wb_debug_pc);
    end

    $display("\n-----------------------------------------------");
    $display(" Final register values (Phase 4: WITH forwarding/");
    $display(" stall/flush -- these should now EXACTLY MATCH the");
    $display(" Phase 2 single-cycle results.)");
    $display("-----------------------------------------------");
    for (int i = 0; i <= 11; i++) begin
      $display(" x%0d = %0d (0x%08h)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);
    end
    $display("-----------------------------------------------");

    $finish;
  end

endmodule
