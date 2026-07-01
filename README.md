# 5-Stage Pipelined RISC-V Processor

A from-scratch RV32I-subset CPU in SystemVerilog, built and verified in five phases: single-cycle baseline → pipeline skeleton → hazard handling (forwarding, stalling, branch flush) → automated verification suite.

**Status: complete.** All five phases implemented and verified — see [Verification](#verification) for how.

## Table of Contents
- [Overview](#overview)
- [Instruction Set](#instruction-set)
- [Architecture](#architecture)
- [Hazard Handling](#hazard-handling)
- [Verification](#verification)
- [Results](#results)
- [Project Structure](#project-structure)
- [Building and Running](#building-and-running)
- [Design Decisions Worth Knowing](#design-decisions-worth-knowing)
- [Why This Project](#why-this-project)

## Overview

A RISC-V (RV32I subset) processor implementing the classic 5-stage pipeline — Instruction Fetch, Decode, Execute, Memory, Write-back — simulated with Icarus Verilog. Built incrementally on purpose: a single-cycle datapath first, to establish a known-correct reference; then a pipeline skeleton with *no* hazard handling, to isolate structural bugs from timing bugs; then the actual hazard-resolution logic, verified independently before being trusted.

**Tools used:** [Icarus Verilog](https://bleyer.org/icarus/) (simulation), [GTKWave](https://gtkwave.sourceforge.net/) (waveform inspection), Python 3 (verification tooling — see [Verification](#verification)).

## Instruction Set

8 RV32I instructions:

| Instr | Format | Opcode | funct3 | funct7 | Semantics |
|-------|--------|--------|--------|--------|-----------|
| ADD  | R | `0110011` | `000` | `0000000` | rd = rs1 + rs2 |
| SUB  | R | `0110011` | `000` | `0100000` | rd = rs1 - rs2 |
| AND  | R | `0110011` | `111` | `0000000` | rd = rs1 & rs2 |
| OR   | R | `0110011` | `110` | `0000000` | rd = rs1 \| rs2 |
| ADDI | I | `0010011` | `000` | — | rd = rs1 + sext(imm12) |
| LW   | I | `0000011` | `010` | — | rd = Mem[rs1 + sext(imm12)] |
| SW   | S | `0100011` | `010` | — | Mem[rs1 + sext(imm12)] = rs2 |
| BEQ  | B | `1100011` | `000` | — | if (rs1==rs2) PC += sext(imm13) |

## Architecture

```
                    +----------+
              +---->|   PC     |
              |     +----+-----+
              |          |
              |          v
              |   +-------------+
              |   | Instruction |
              |   |   Memory    |
              |   +------+------+
              |          |
              |          v
              |   +-------------+      +----------------+
              |   |   Decode    |----->|  Register File |
              |   | (opcode,    |      |  rs1, rs2, rd  |
              |   |  funct3/7,  |      +-------+--------+
              |   |  rd, imm)   |              |
              |   +------+------+              |
              |          |                     v
              |          |              +-------------+
              |          +------------->|     ALU     |
              |                         | (rs1 op rs2 |
              |                         |  or rs1+imm)|
              |                         +------+------+
              |                                |
              |                  +-------------+-------------+
              |                  |                           |
              |                  v                           v
              |          +---------------+          +----------------+
              |          | Data Memory   |          | Branch Compare |
              |          | (LW/SW)       |          | (BEQ: ALU==0)  |
              |          +-------+-------+          +--------+-------+
              |                  |                           |
              |                  v                           |
              |          +---------------+                   |
              +----------| WB Mux        |                   |
              |          | (ALU result   |                   |
              |          |  or Mem data) |                   |
              |          +-------+-------+                   |
              |                  |                           |
              |                  +------> back to RegFile rd |
              |                                               |
              +-----------------------------------------------+
                          PC + 4, or PC + branch_offset
```

The pipelined version inserts a register at every stage boundary (IF/ID, ID/EX, EX/MEM, MEM/WB) and adds the hazard-handling logic below — every other module (ALU, register file, control unit, immediate generator, instruction/data memory) is reused **unchanged** from the single-cycle version.

| Stage | Name | What happens |
|-------|------|---------------|
| IF  | Instruction Fetch | Read instruction at PC; compute PC+4 |
| ID  | Instruction Decode | Decode opcode/funct fields; read register file; generate immediate |
| EX  | Execute | ALU operation; branch comparison (zero flag) |
| MEM | Memory Access | Load/store to data memory |
| WB  | Write Back | Write ALU result or loaded data back to the register file |

## Hazard Handling

### Data hazards — forwarding

Two paths resolve most register dependencies without stalling: **EX/MEM → EX** (producer 1 instruction ahead) and **MEM/WB → EX** (producer 2 instructions ahead), with EX/MEM taking priority when both would apply to the same register. A third case — producer exactly 3 instructions ahead, where its write-back and the consumer's register read land on the *same* clock edge — needs no explicit forwarding path at all: the register file has an internal write-read bypass that handles it for free.

### The one hazard forwarding can't fix — load-use

A load immediately followed by a dependent instruction can't be forwarded, because the loaded value doesn't exist yet — data memory hasn't been read at the point it would be needed. A dedicated hazard detection unit catches exactly this case and inserts a single stall cycle, after which ordinary MEM/WB → EX forwarding supplies the value.

### Control hazards — branch flush

Branches resolve in EX using static not-taken prediction (the simplest possible policy: keep fetching sequentially, and correct course if wrong). If a branch resolves taken, the two instructions already fetched on the wrong path are flushed — turned into bubbles — rather than allowed to execute, and the PC redirects to the branch target. Cost: 2 cycles per taken branch, 0 per correctly-predicted not-taken branch.

Worth being able to explain: the stall and flush conditions can never fire on the same cycle in this design. Both are properties of the single instruction currently in EX — a stall requires it to be a load, a flush requires it to be a branch — and it can't be both at once. That's a structural guarantee, not a coincidence being relied on.

## Verification

Rather than trusting any single check, this project used several independent, increasingly strict verification layers:

1. **Single-cycle datapath** — the test program's machine code was generated by a small Python encoder, then independently decoded back and checked field-by-field against intent. Expected final register/memory values were computed by a separate Python instruction-set simulator (not hand-traced) and matched exactly in simulation.
2. **Pipeline skeleton, no hazard handling** — structural correctness checked via a per-cycle trace confirming each instruction's PC advances exactly one pipeline stage per clock cycle.
3. **Hazard-handling design** — before any SystemVerilog was written, the forwarding/stall/flush algorithm was implemented as an independent cycle-accurate Python model and checked against the single-cycle results. Full match, including a compound stall-then-flush interaction the model surfaced without being specifically designed to test for it.
4. **Real hardware** — the actual SystemVerilog simulation matched the Python model's predictions exactly, cycle for cycle, including the precise cycle a stall and a subsequent flush occurred.
5. **Automated regression suite** — 5 targeted test programs (pure RAW forwarding, load-use, branch-taken, branch-not-taken, and the original combined program) run through a self-checking scoreboard testbench. All passing.

## Results

CPI measured per test (see `build_phase5_tests.py`), confirmed against the real SystemVerilog via `scoreboard_tb.sv`:

| Test | Instructions retired | Cycles | CPI | What it isolates |
|------|----------------------|--------|-----|-------------------|
| test1_raw_hazard | 4 | 8 | 2.00 | Pure forwarding, zero stalls/flushes |
| test2_load_use | 4 | 9 | 2.25 | +1 cycle: load-use stall |
| test3_branch_taken | 4 (1 flushed) | 10 | 2.50 | +2 cycles: taken-branch flush |
| test4_branch_not_taken | 5 | 9 | 1.80 | Correctly-predicted branch costs nothing |
| test5_combined | 13 (1 flushed) | 20 | 1.54 | Original combined program, everything at once |

CPI sits well above the textbook "1.0" figure because these are short programs — a 5-stage pipeline has a fixed ~4-cycle fill cost that only amortizes over long ones (test1's 2.00 is exactly `(4+4)/4`, the zero-hazard formula for 4 instructions). The number that actually demonstrates the hazard-handling work is the *increment* between tests: +1 cycle per load-use stall, +2 cycles per taken-branch flush, +0 for a correctly-predicted not-taken branch — matching the design exactly.

## Project Structure

```
.
├── src/
│   ├── common/                   # shared by both single-cycle and pipelined versions
│   │   ├── alu.sv                 # ADD/SUB/AND/OR + zero flag
│   │   ├── register_file.sv       # 32x32-bit regs, x0 hardwired, write-read bypass
│   │   ├── instruction_memory.sv  # ROM, hex-loaded, NOP-padded past program end
│   │   ├── imm_generator.sv       # I/S/B-type immediate extraction + sign-extend
│   │   ├── control_unit.sv        # opcode -> control signal decode
│   │   └── data_memory.sv         # word-granular RAM for LW/SW
│   ├── single_cycle/
│   │   ├── pc_register.sv         # PC + next-PC mux (no stall port needed here)
│   │   └── datapath.sv            # wires common/ + this together
│   └── pipelined/
│       ├── pc_register.sv         # adds a stall port vs. the single-cycle version
│       ├── if_id_reg.sv           # IF -> ID pipeline register (stall + flush)
│       ├── id_ex_reg.sv           # ID -> EX pipeline register (flush)
│       ├── ex_mem_reg.sv          # EX -> MEM pipeline register
│       ├── mem_wb_reg.sv          # MEM -> WB pipeline register
│       ├── forwarding_unit.sv     # EX/MEM->EX and MEM/WB->EX forwarding
│       ├── hazard_detection_unit.sv # load-use hazard -> 1-cycle stall
│       └── datapath.sv  # wires common/ + all of the above together
├── tb/
│   ├── single_cycle_tb.sv         # Phase 2: prints final register/memory state
│   ├── pipeline_tb.sv             # Phase 3: per-cycle pipeline stage trace
│   └── scoreboard_tb.sv           # Phase 5: auto-checks all 5 test programs
├── program.hex                    # 14-instruction program, all 8 instructions
├── test1_raw_hazard.hex           # back-to-back RAW dependency, forwarding only
├── test2_load_use.hex             # load immediately followed by dependent use
├── test3_branch_taken.hex         # taken branch, exercises the flush
├── test4_branch_not_taken.hex     # not-taken branch, no flush needed
├── test5_combined.hex             # same program as program.hex
├── build_phase5_tests.py          # generates the test-suite .hex files + expected values
```

## Building and Running

Requires [Icarus Verilog](https://bleyer.org/icarus/). Run from the project root (the `.hex` files are loaded relative to wherever `vvp` runs from).

**Single-cycle** (Phase 2 baseline):
```bash
iverilog -g2012 -o sim.vvp src/common/*.sv src/single_cycle/*.sv tb/single_cycle_tb.sv
vvp sim.vvp
```

**Pipelined, structural trace** (Phase 3-style per-cycle stage view):
```bash
iverilog -g2012 -o sim_pipe.vvp src/common/*.sv src/pipelined/*.sv tb/pipeline_tb.sv
vvp sim_pipe.vvp
```

**Full verification suite** (Phase 5 — the one that matters):
```bash
iverilog -g2012 -o sim_score.vvp src/common/*.sv src/pipelined/*.sv tb/scoreboard_tb.sv
vvp sim_score.vvp
```
Expect `ALL TESTS PASSED`.

Each testbench also writes a `.vcd` waveform file, viewable with `gtkwave <file>.vcd` — useful signals to inspect: `forward_a`/`forward_b` (forwarding mux selects), `stall`, and `id_ex_flush`/`ex_branch_taken`.

## Design Decisions Worth Knowing

- **The register file's write-read bypass** (built in Phase 2, before pipelining existed) turned out to be load-bearing once pipelined — it transparently handles the "producer 3 instructions back" hazard case, so the forwarding unit only ever needs to cover 1- and 2-back.
- **Instruction memory pre-fills with NOPs** before loading the real program, so a PC that runs past the end of the program — which always happens once the program "finishes" but the clock keeps ticking — executes harmlessly instead of propagating unknown (`X`) values into the pipeline.
- **Branch targets are computed once, in ID** (PC + immediate), and the result is carried forward through the pipeline registers — not recomputed in EX — because only PC+4, not the raw PC, survives past the ID/EX boundary.
- **`debug_pc` is threaded through every pipeline register** purely for testbench visibility (so a trace can print "this instruction is now in EX") — it's not part of the real datapath and a real CPU wouldn't include it.
- **Stall and flush are structurally mutually exclusive** in this design (see [Hazard Handling](#hazard-handling)), which simplified the pipeline register logic — no priority arbitration between them was needed.
