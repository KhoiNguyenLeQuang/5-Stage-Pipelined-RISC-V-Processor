// scoreboard_tb.sv
// Runs all 5 test programs at once (one DUT each) and auto-checks final
// register values against expected results. Prints PASS/FAIL per check
// plus an overall summary -- no manual comparison needed.

`timescale 1ns/1ps

module scoreboard_tb;

  logic clk;                 // shared clock, all 5 DUTs run in parallel
  initial clk = 0;
  always #5 clk = ~clk;

  int fail_count = 0;        // total failed checks, across all tests

  // one DUT per test program -- each independent hardware, own hex file
  datapath_pipelined #(.INIT_FILE("test1_raw_hazard.hex"))       dut1 (.clk(clk));  // RAW hazard, forwarding only
  datapath_pipelined #(.INIT_FILE("test2_load_use.hex"))         dut2 (.clk(clk));  // load-use hazard, needs a stall
  datapath_pipelined #(.INIT_FILE("test3_branch_taken.hex"))     dut3 (.clk(clk));  // taken branch, needs a flush
  datapath_pipelined #(.INIT_FILE("test4_branch_not_taken.hex")) dut4 (.clk(clk));  // not-taken branch, no flush
  datapath_pipelined #(.INIT_FILE("test5_combined.hex"))         dut5 (.clk(clk));  // original Phase 2 program, everything at once

  // compares one register against its expected value, logs PASS/FAIL
  task automatic check(string test, string reg_name, int actual, int expected);
    if (actual !== expected) begin
      $display("  FAIL  %s.%s = %0d (expected %0d)", test, reg_name, actual, expected);
      fail_count++;
    end else begin
      $display("  pass  %s.%s = %0d", test, reg_name, actual);
    end
  endtask

  initial begin
    $dumpfile("waves_scoreboard.vcd");   // waveform output, for GTKWave
    $dumpvars(0, scoreboard_tb);

    repeat (30) @(posedge clk);          // margin past the slowest test (test5, 20 cycles)

    $display("\n=== test1_raw_hazard ===");
    check("test1", "x1", dut1.u_regfile.regs[1], 10);   // ADDI, no dependency
    check("test1", "x2", dut1.u_regfile.regs[2], 20);   // ADDI, no dependency
    check("test1", "x3", dut1.u_regfile.regs[3], 30);   // x1+x2, needs forwarding
    check("test1", "x4", dut1.u_regfile.regs[4], 20);   // x3-x1, needs forwarding

    $display("\n=== test2_load_use ===");
    check("test2", "x1", dut2.u_regfile.regs[1], 99);    // ADDI
    check("test2", "x2", dut2.u_regfile.regs[2], 99);    // loaded from memory
    check("test2", "x3", dut2.u_regfile.regs[3], 198);   // x2+x2, right after the load -- needs the stall

    $display("\n=== test3_branch_taken ===");
    check("test3", "x1", dut3.u_regfile.regs[1], 7);
    check("test3", "x2", dut3.u_regfile.regs[2], 7);
    check("test3", "x3", dut3.u_regfile.regs[3], 0);    // must stay 0 -- this instruction gets flushed
    check("test3", "x4", dut3.u_regfile.regs[4], 4);    // lands here after the branch redirect

    $display("\n=== test4_branch_not_taken ===");
    check("test4", "x1", dut4.u_regfile.regs[1], 7);
    check("test4", "x2", dut4.u_regfile.regs[2], 3);
    check("test4", "x3", dut4.u_regfile.regs[3], 111);  // must run -- branch correctly not taken
    check("test4", "x4", dut4.u_regfile.regs[4], 4);

    $display("\n=== test5_combined ===");
    check("test5", "x1", dut5.u_regfile.regs[1], 5);
    check("test5", "x2", dut5.u_regfile.regs[2], 3);
    check("test5", "x3", dut5.u_regfile.regs[3], 8);
    check("test5", "x4", dut5.u_regfile.regs[4], 2);
    check("test5", "x5", dut5.u_regfile.regs[5], 1);
    check("test5", "x6", dut5.u_regfile.regs[6], 7);
    check("test5", "x7", dut5.u_regfile.regs[7], 8);
    check("test5", "x8", dut5.u_regfile.regs[8], 0);     // flushed, same as test3's x3
    check("test5", "x9", dut5.u_regfile.regs[9], 42);
    check("test5", "x10", dut5.u_regfile.regs[10], 77);
    check("test5", "x11", dut5.u_regfile.regs[11], 11);

    $display("\n=====================================");
    if (fail_count == 0)
      $display(" ALL TESTS PASSED");    // every check above matched
    else
      $display(" %0d CHECK(S) FAILED", fail_count);
    $display("=====================================");

    $finish;
  end

endmodule
