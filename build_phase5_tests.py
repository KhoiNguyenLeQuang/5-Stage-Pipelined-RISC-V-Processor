#!/usr/bin/env python3
"""
Builds 5 test programs (4 new + the original combined one), encodes each to
.hex, and runs the SAME verified cycle-accurate pipeline model from Phase 4
against each one to get: expected final register values (for the scoreboard
testbench) and real cycle counts (for CPI).
"""
MASK32 = 0xFFFFFFFF
def to_s32(x):
    x &= MASK32
    return x - (1 << 32) if x & 0x8000_0000 else x

def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm12 &= 0xFFF
    hi, lo = (imm12 >> 5) & 0x7F, imm12 & 0x1F
    return (hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (lo << 7) | opcode
def enc_b(imm13, rs2, rs1, funct3, opcode):
    imm = imm13 & 0x1FFF
    b12, b11 = (imm >> 12) & 1, (imm >> 11) & 1
    b10_5, b4_1 = (imm >> 5) & 0x3F, (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode

OPC_R, OPC_I, OPC_LOAD, OPC_STORE, OPC_BRANCH = 0b0110011, 0b0010011, 0b0000011, 0b0100011, 0b1100011
def ADD(rd,rs1,rs2): return enc_r(0,rs2,rs1,0,rd,OPC_R)
def SUB(rd,rs1,rs2): return enc_r(0b0100000,rs2,rs1,0,rd,OPC_R)
def AND(rd,rs1,rs2): return enc_r(0,rs2,rs1,0b111,rd,OPC_R)
def OR(rd,rs1,rs2):  return enc_r(0,rs2,rs1,0b110,rd,OPC_R)
def ADDI(rd,rs1,imm):return enc_i(imm,rs1,0,rd,OPC_I)
def LW(rd,rs1,imm):  return enc_i(imm,rs1,0b010,rd,OPC_LOAD)
def SW(rs2,rs1,imm): return enc_s(imm,rs2,rs1,0b010,OPC_STORE)
def BEQ(rs1,rs2,imm):return enc_b(imm,rs2,rs1,0,OPC_BRANCH)
NOP = ADDI(0,0,0)

def assemble(prog):
    addr, labels, addressed = 0, {}, []
    for entry in prog:
        label = entry[-1] if isinstance(entry[-1], str) else None
        if label and entry[0] != "BEQ":
            labels[label] = addr
        addressed.append((addr, entry)); addr += 4
    words = {}
    for a, entry in addressed:
        op = entry[0]
        if op == "ADDI": words[a] = ADDI(entry[1], entry[2], entry[3])
        elif op == "ADD": words[a] = ADD(entry[1], entry[2], entry[3])
        elif op == "SUB": words[a] = SUB(entry[1], entry[2], entry[3])
        elif op == "AND": words[a] = AND(entry[1], entry[2], entry[3])
        elif op == "OR": words[a] = OR(entry[1], entry[2], entry[3])
        elif op == "SW": words[a] = SW(entry[1], entry[2], entry[3])
        elif op == "LW": words[a] = LW(entry[1], entry[2], entry[3])
        elif op == "BEQ": words[a] = BEQ(entry[1], entry[2], labels[entry[3]] - a)
    return words, addr  # addr == program_end

def decode_control(opcode, funct3, funct7_5):
    c = dict(alu_op=0, reg_write=0, mem_read=0, mem_write=0, mem_to_reg=0, branch=0, alu_src=0)
    if opcode == OPC_R:
        c['reg_write'] = 1
        c['alu_op'] = (1 if funct7_5 else 0) if funct3==0 else (2 if funct3==0b111 else 3)
    elif opcode == OPC_I:
        c['reg_write']=1; c['alu_src']=1; c['alu_op']=0
    elif opcode == OPC_LOAD:
        c['reg_write']=1; c['alu_src']=1; c['alu_op']=0; c['mem_read']=1; c['mem_to_reg']=1
    elif opcode == OPC_STORE:
        c['alu_src']=1; c['alu_op']=0; c['mem_write']=1
    elif opcode == OPC_BRANCH:
        c['alu_op']=1; c['branch']=1
    return c

def imm_gen(instr):
    opcode = instr & 0x7F
    if opcode in (OPC_I, OPC_LOAD):
        return to_s32((instr >> 20) << 20) >> 20
    if opcode == OPC_STORE:
        hi, lo = (instr>>25)&0x7F, (instr>>7)&0x1F
        return to_s32(((hi<<5)|lo) << 20) >> 20
    if opcode == OPC_BRANCH:
        b12,b11,b10_5,b4_1 = (instr>>31)&1,(instr>>7)&1,(instr>>25)&0x3F,(instr>>8)&0xF
        imm = (b12<<12)|(b11<<11)|(b10_5<<5)|(b4_1<<1)
        return to_s32(imm << 19) >> 19
    return 0

def alu_exec(op, a, b):
    a, b = a & MASK32, b & MASK32
    if op == 0: return (a + b) & MASK32
    if op == 1: return (a - b) & MASK32
    if op == 2: return a & b
    if op == 3: return a | b

BUBBLE_IDEX = dict(pc=None, rs1_data=0, rs2_data=0, imm=0, rd_addr=0, rs1_addr=0, rs2_addr=0,
                    branch_target=0, alu_op=0, alu_src=0, mem_read=0, mem_write=0, reg_write=0,
                    mem_to_reg=0, branch=0)
BUBBLE_EXMEM = dict(pc=None, alu_result=0, rs2_data=0, rd_addr=0, mem_read=0, mem_write=0,
                     reg_write=0, mem_to_reg=0)
BUBBLE_MEMWB = dict(pc=None, alu_result=0, mem_read_data=0, rd_addr=0, reg_write=0, mem_to_reg=0)

def run(words, program_end, num_real_instrs, max_cycles=60, debug=False):
    """Cycle-accurate model: forwarding + load-use stall + branch flush.
       Returns (final_regs, final_mem, cycles_to_drain, instrs_retired).

       Completion is NOT tracked by waiting for exactly num_real_instrs
       retirements -- a taken branch can permanently skip an instruction
       (it's fetched, then flushed, and never reaches WB), so that count
       can be unreachable. Instead: run a fixed, generous number of
       cycles (comfortably more than any of these short programs need,
       even with stalls/flushes), and report the LAST cycle any real
       instruction actually retired -- that's the true completion point,
       regardless of how many of the originally-fetched instructions
       ended up flushed away."""
    def fetch(pc): return words.get(pc, NOP)
    regs = [0]*32
    mem = {}
    pc = 0
    if_id = dict(pc=None, instruction=NOP)
    id_ex = dict(BUBBLE_IDEX)
    ex_mem = dict(BUBBLE_EXMEM)
    mem_wb = dict(BUBBLE_MEMWB)
    def rd(i): return 0 if i == 0 else regs[i]
    def wr(i, v):
        if i != 0: regs[i] = v & MASK32

    retired = 0
    last_retire_cycle = 0
    for cycle in range(1, max_cycles + 1):
        instr = if_id['instruction']
        id_opcode, id_funct3, id_funct7_5 = instr & 0x7F, (instr>>12)&0x7, (instr>>30)&1
        id_rs1_addr, id_rs2_addr, id_rd_addr = (instr>>15)&0x1F, (instr>>20)&0x1F, (instr>>7)&0x1F
        id_ctrl = decode_control(id_opcode, id_funct3, id_funct7_5)
        wb_write_back_data = mem_wb['mem_read_data'] if mem_wb['mem_to_reg'] else mem_wb['alu_result']
        def reg_read(addr_):
            if addr_ == 0: return 0
            if mem_wb['reg_write'] and mem_wb['rd_addr'] == addr_: return wb_write_back_data
            return rd(addr_)
        id_rs1_data, id_rs2_data = reg_read(id_rs1_addr), reg_read(id_rs2_addr)
        id_imm = imm_gen(instr)
        id_branch_target = (if_id['pc'] + id_imm) & MASK32 if if_id['pc'] is not None else 0

        stall = bool(id_ex['mem_read'] and id_ex['rd_addr'] != 0 and
                     (id_ex['rd_addr'] == id_rs1_addr or id_ex['rd_addr'] == id_rs2_addr))

        def forward(addr_):
            if ex_mem['reg_write'] and ex_mem['rd_addr'] != 0 and ex_mem['rd_addr'] == addr_:
                return ex_mem['alu_result']
            if mem_wb['reg_write'] and mem_wb['rd_addr'] != 0 and mem_wb['rd_addr'] == addr_:
                return wb_write_back_data
            return None
        fwd_a = forward(id_ex['rs1_addr'])
        fwd_b = forward(id_ex['rs2_addr'])
        ex_operand_a = fwd_a if fwd_a is not None else id_ex['rs1_data']
        forwarded_rs2 = fwd_b if fwd_b is not None else id_ex['rs2_data']
        ex_operand_b = id_ex['imm'] if id_ex['alu_src'] else forwarded_rs2
        ex_alu_result = alu_exec(id_ex['alu_op'], ex_operand_a, ex_operand_b)
        ex_branch_taken = bool(id_ex['branch'] and ex_alu_result == 0)
        ex_branch_target = id_ex['branch_target']

        mem_read_data = mem.get(ex_mem['alu_result'], 0) if ex_mem['mem_read'] else 0

        if mem_wb['reg_write']:
            wr(mem_wb['rd_addr'], wb_write_back_data)
        if mem_wb['pc'] is not None:      # a REAL instruction reached WB this cycle
            retired += 1
            last_retire_cycle = cycle
        if ex_mem['mem_write']:
            mem[ex_mem['alu_result'] & MASK32] = ex_mem['rs2_data'] & MASK32

        if debug:
            print(f"cyc{cycle}: IF.pc={if_id['pc']} ID.instr={instr:#010x} "
                  f"id_ex.rd={id_ex['rd_addr']} ex_alu={ex_alu_result} "
                  f"mem_wb.pc={mem_wb['pc']} mem_wb.rd={mem_wb['rd_addr']} mem_wb.rw={mem_wb['reg_write']} "
                  f"wb_data={wb_write_back_data} retired={retired}")

        new_mem_wb = dict(pc=ex_mem['pc'], alu_result=ex_mem['alu_result'], mem_read_data=mem_read_data,
                           rd_addr=ex_mem['rd_addr'], reg_write=ex_mem['reg_write'],
                           mem_to_reg=ex_mem['mem_to_reg'])
        new_ex_mem = dict(pc=id_ex['pc'], alu_result=ex_alu_result, rs2_data=forwarded_rs2, rd_addr=id_ex['rd_addr'],
                           mem_read=id_ex['mem_read'], mem_write=id_ex['mem_write'],
                           reg_write=id_ex['reg_write'], mem_to_reg=id_ex['mem_to_reg'])
        id_ex_flush = stall or ex_branch_taken
        new_id_ex = dict(BUBBLE_IDEX) if id_ex_flush else dict(
            pc=if_id['pc'], rs1_data=id_rs1_data, rs2_data=id_rs2_data, imm=id_imm, rd_addr=id_rd_addr,
            rs1_addr=id_rs1_addr, rs2_addr=id_rs2_addr, branch_target=id_branch_target,
            alu_op=id_ctrl['alu_op'], alu_src=id_ctrl['alu_src'], mem_read=id_ctrl['mem_read'],
            mem_write=id_ctrl['mem_write'], reg_write=id_ctrl['reg_write'],
            mem_to_reg=id_ctrl['mem_to_reg'], branch=id_ctrl['branch'])

        if ex_branch_taken: new_if_id = dict(pc=None, instruction=NOP)
        elif stall: new_if_id = dict(if_id)
        elif pc < program_end: new_if_id = dict(pc=pc, instruction=fetch(pc))
        else: new_if_id = dict(pc=None, instruction=NOP)   # past the real program: not a "real" fetch

        if ex_branch_taken: new_pc = ex_branch_target
        elif stall: new_pc = pc
        else: new_pc = (pc + 4) & MASK32

        pc, if_id, id_ex, ex_mem, mem_wb = new_pc, new_if_id, new_id_ex, new_ex_mem, new_mem_wb

    return regs, mem, last_retire_cycle, retired

# ---------------------------------------------------------------- programs
programs = {
    "test1_raw_hazard": [
        ("ADDI", 1, 0, 10), ("ADDI", 2, 0, 20), ("ADD", 3, 1, 2), ("SUB", 4, 3, 1),
    ],
    "test2_load_use": [
        ("ADDI", 1, 0, 99), ("SW", 1, 0, 0), ("LW", 2, 0, 0), ("ADD", 3, 2, 2),
    ],
    "test3_branch_taken": [
        ("ADDI", 1, 0, 7), ("ADDI", 2, 0, 7), ("BEQ", 1, 2, "SKIP"),
        ("ADDI", 3, 0, 111), ("ADDI", 4, 0, 4, "SKIP"),
    ],
    "test4_branch_not_taken": [
        ("ADDI", 1, 0, 7), ("ADDI", 2, 0, 3), ("BEQ", 1, 2, "SKIP"),
        ("ADDI", 3, 0, 111), ("ADDI", 4, 0, 4, "SKIP"),
    ],
    "test5_combined": [
        ("ADDI", 1, 0, 5), ("ADDI", 2, 0, 3), ("ADD", 3, 1, 2), ("SUB", 4, 1, 2),
        ("AND", 5, 1, 2), ("OR", 6, 1, 2), ("SW", 3, 0, 0), ("LW", 7, 0, 0),
        ("BEQ", 3, 7, "SKIP"), ("ADDI", 8, 0, 99), ("ADDI", 9, 0, 42, "SKIP"),
        ("BEQ", 1, 2, "NOTAKEN"), ("ADDI", 10, 0, 77), ("ADDI", 11, 0, 11, "NOTAKEN"),
    ],
}

if __name__ == "__main__":
    print(f"{'Test':<24}{'Fetched':>8}{'Retired':>8}{'Cycles':>8}{'CPI':>7}   Registers (nonzero)")
    print("-" * 98)
    results = {}
    for name, prog in programs.items():
        words, program_end = assemble(prog)
        num_instrs = len(prog)
        regs, mem, cycles, retired = run(words, program_end, num_instrs)
        cpi = cycles / retired
        nz = {i: regs[i] for i in range(32) if regs[i] != 0}
        results[name] = dict(words=words, program_end=program_end, regs=regs, mem=mem,
                              cycles=cycles, num_instrs=num_instrs, retired=retired, cpi=cpi)
        skipped = f"  ({num_instrs - retired} correctly skipped by a taken branch)" if retired < num_instrs else ""
        print(f"{name:<24}{num_instrs:>8}{retired:>8}{cycles:>8}{cpi:>7.2f}   {nz}{skipped}")
        with open(f"Direction/{name}.hex", "w") as f:
            for a in range(0, program_end, 4):
                f.write(f"{words.get(a, NOP):08x}\n")

    print("\nCPI here = cycles-to-drain / instructions-actually-retired (skipped")
    print("instructions from a taken branch are correctly excluded from both).")
    print("test1 has zero stalls/flushes -- closest thing to this design's 'ideal' CPI.")
