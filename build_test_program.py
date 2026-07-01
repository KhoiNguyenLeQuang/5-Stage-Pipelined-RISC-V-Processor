#!/usr/bin/env python3
"""
Builds program.hex for the single-cycle RV32I-subset datapath, and
independently computes the "golden" expected final register/memory state
by simulating the same 8 instructions in Python.

This exists so the expected values handed to the user are computed, not
hand-traced -- removing a whole class of arithmetic mistakes.
"""

MASK32 = 0xFFFFFFFF


def to_s32(x):
    x &= MASK32
    return x - (1 << 32) if x & 0x8000_0000 else x


# ---------------------------------------------------------------- encoders
def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm12 &= 0xFFF
    hi, lo = (imm12 >> 5) & 0x7F, imm12 & 0x1F
    return (hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (lo << 7) | opcode


def enc_b(imm13, rs2, rs1, funct3, opcode):
    assert imm13 % 2 == 0, "branch offsets must be even"
    imm = imm13 & 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


OPC_R, OPC_I, OPC_LOAD, OPC_STORE, OPC_BRANCH = 0b0110011, 0b0010011, 0b0000011, 0b0100011, 0b1100011

def ADD(rd, rs1, rs2):  return enc_r(0b0000000, rs2, rs1, 0b000, rd, OPC_R)
def SUB(rd, rs1, rs2):  return enc_r(0b0100000, rs2, rs1, 0b000, rd, OPC_R)
def AND(rd, rs1, rs2):  return enc_r(0b0000000, rs2, rs1, 0b111, rd, OPC_R)
def OR(rd, rs1, rs2):   return enc_r(0b0000000, rs2, rs1, 0b110, rd, OPC_R)
def ADDI(rd, rs1, imm): return enc_i(imm, rs1, 0b000, rd, OPC_I)
def LW(rd, rs1, imm):   return enc_i(imm, rs1, 0b010, rd, OPC_LOAD)
def SW(rs2, rs1, imm):  return enc_s(imm, rs2, rs1, 0b010, OPC_STORE)
def BEQ(rs1, rs2, imm): return enc_b(imm, rs2, rs1, 0b000, OPC_BRANCH)

NOP = ADDI(0, 0, 0)


# ------------------------------------------------------------- the program
# Addresses are fixed up below once labels are known.
prog = [
    ("ADDI", 1, 0, 5),     # x1 = 5
    ("ADDI", 2, 0, 3),     # x2 = 3
    ("ADD",  3, 1, 2),     # x3 = x1 + x2 = 8
    ("SUB",  4, 1, 2),     # x4 = x1 - x2 = 2
    ("AND",  5, 1, 2),     # x5 = x1 & x2 = 1
    ("OR",   6, 1, 2),     # x6 = x1 | x2 = 7
    ("SW",   3, 0, 0),     # Mem[x0+0] = x3   -> Mem[0] = 8
    ("LW",   7, 0, 0),     # x7 = Mem[x0+0]   -> x7 = 8
    ("BEQ",  3, 7, "SKIP"),    # x3 == x7 (8==8)  -> taken
    ("ADDI", 8, 0, 99),    # must be SKIPPED
    ("ADDI", 9, 0, 42, "SKIP"),
    ("BEQ",  1, 2, "NOTAKEN"), # x1 != x2 (5!=3) -> not taken
    ("ADDI", 10, 0, 77),   # must EXECUTE (branch not taken)
    ("ADDI", 11, 0, 11, "NOTAKEN"),
]

# first pass: assign addresses + collect label positions
addr = 0
labels = {}
addressed = []
for entry in prog:
    *fields, = entry
    label = None
    if isinstance(fields[-1], str) and fields[0] != "BEQ":
        label = fields[-1]
        fields = fields[:-1]
    elif fields[0] == "BEQ":
        pass
    if label:
        labels[label] = addr
    addressed.append((addr, entry))
    addr += 4
program_end = addr  # one past the last instruction -- captured BEFORE the
                     # loop below reuses the name `addr` as its loop variable

words = []
trace = []
for addr, entry in addressed:
    op = entry[0]
    if op == "ADDI":
        rd, rs1, imm = entry[1], entry[2], entry[3]
        words.append(ADDI(rd, rs1, imm))
        trace.append((addr, f"ADDI x{rd}, x{rs1}, {imm}"))
    elif op == "ADD":
        rd, rs1, rs2 = entry[1], entry[2], entry[3]
        words.append(ADD(rd, rs1, rs2))
        trace.append((addr, f"ADD  x{rd}, x{rs1}, x{rs2}"))
    elif op == "SUB":
        rd, rs1, rs2 = entry[1], entry[2], entry[3]
        words.append(SUB(rd, rs1, rs2))
        trace.append((addr, f"SUB  x{rd}, x{rs1}, x{rs2}"))
    elif op == "AND":
        rd, rs1, rs2 = entry[1], entry[2], entry[3]
        words.append(AND(rd, rs1, rs2))
        trace.append((addr, f"AND  x{rd}, x{rs1}, x{rs2}"))
    elif op == "OR":
        rd, rs1, rs2 = entry[1], entry[2], entry[3]
        words.append(OR(rd, rs1, rs2))
        trace.append((addr, f"OR   x{rd}, x{rs1}, x{rs2}"))
    elif op == "SW":
        rs2, rs1, imm = entry[1], entry[2], entry[3]
        words.append(SW(rs2, rs1, imm))
        trace.append((addr, f"SW   x{rs2}, {imm}(x{rs1})"))
    elif op == "LW":
        rd, rs1, imm = entry[1], entry[2], entry[3]
        words.append(LW(rd, rs1, imm))
        trace.append((addr, f"LW   x{rd}, {imm}(x{rs1})"))
    elif op == "BEQ":
        rs1, rs2, target_label = entry[1], entry[2], entry[3]
        offset = labels[target_label] - addr
        words.append(BEQ(rs1, rs2, offset))
        trace.append((addr, f"BEQ  x{rs1}, x{rs2}, {target_label}  (offset={offset})"))

print("=== Assembled program ===")
for (a, _), w, (_, mnem) in zip(addressed, words, trace):
    print(f"0x{a:02X}: 0x{w:08X}   {mnem}")

# ------------------------------------------------------- reference simulator
regs = [0] * 32
mem = {0: 0}
pc = 0

def get_reg(i):
    return 0 if i == 0 else regs[i]

def set_reg(i, v):
    if i != 0:
        regs[i] = to_s32(v) & MASK32

steps = 0
while pc < program_end:
    word = words[pc // 4]
    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7_5 = (word >> 30) & 0x1

    next_pc = pc + 4

    if opcode == OPC_R:
        a, b = get_reg(rs1), get_reg(rs2)
        if funct3 == 0b000:
            result = (a - b) if funct7_5 else (a + b)
        elif funct3 == 0b111:
            result = a & b
        elif funct3 == 0b110:
            result = a | b
        set_reg(rd, result)
    elif opcode == OPC_I:
        imm = to_s32((word >> 20) << 20) >> 20
        set_reg(rd, get_reg(rs1) + imm)
    elif opcode == OPC_LOAD:
        imm = to_s32((word >> 20) << 20) >> 20
        addr_eff = (get_reg(rs1) + imm) & MASK32
        set_reg(rd, mem.get(addr_eff, 0))
    elif opcode == OPC_STORE:
        imm_hi = (word >> 25) & 0x7F
        imm_lo = (word >> 7) & 0x1F
        imm = to_s32(((imm_hi << 5) | imm_lo) << 20) >> 20
        addr_eff = (get_reg(rs1) + imm) & MASK32
        mem[addr_eff] = get_reg(rs2) & MASK32
    elif opcode == OPC_BRANCH:
        b12 = (word >> 31) & 1
        b11 = (word >> 7) & 1
        b10_5 = (word >> 25) & 0x3F
        b4_1 = (word >> 8) & 0xF
        imm = (b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1)
        imm = to_s32(imm << 19) >> 19
        if get_reg(rs1) == get_reg(rs2):
            next_pc = pc + imm

    pc = next_pc
    steps += 1
    if steps > 100:
        raise RuntimeError("runaway simulation -- infinite loop?")

print(f"\n=== Reference simulation: {steps} instructions executed ===")
print("\n=== Expected final register values ===")
for i in range(12):
    v = get_reg(i)
    print(f"x{i:<2} = {v:<6} (0x{v & MASK32:08X})")
print("\n=== Expected final memory ===")
for a, v in sorted(mem.items()):
    print(f"Mem[0x{a:02X}] = {v} (0x{v:08X})")

# ------------------------------------------------------------ write program.hex
PAD_WORDS = 32
with open("Direction/program.hex", "w") as f:
    for w in words:
        f.write(f"{w:08x}\n")

print(f"\nprogram.hex written: {len(words)} instructions")

# ------------------------------------------------------ independent self-check
# Decode every encoded word back into its NUMERIC fields using separate
# logic from the encoders above, and compare against the originally
# intended numeric values from `prog`. This is a second, independent code
# path checking the first one -- numeric comparison, not string matching.
def decode_b_imm(word):
    b12 = (word >> 31) & 1
    b11 = (word >> 7) & 1
    b10_5 = (word >> 25) & 0x3F
    b4_1 = (word >> 8) & 0xF
    imm = (b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1)
    return to_s32(imm << 19) >> 19

def decode_i_imm(word):
    return to_s32((word >> 20) << 20) >> 20

def decode_s_imm(word):
    hi = (word >> 25) & 0x7F
    lo = (word >> 7) & 0x1F
    return to_s32(((hi << 5) | lo) << 20) >> 20

print("\n=== Self-check: decoding every instruction back, comparing to intent ===")
all_ok = True
for (a, entry), w in zip(addressed, words):
    opcode = w & 0x7F
    rd = (w >> 7) & 0x1F
    funct3 = (w >> 12) & 0x7
    rs1f = (w >> 15) & 0x1F
    rs2f = (w >> 20) & 0x1F
    funct7_5 = (w >> 30) & 1
    op = entry[0]

    checks = []
    if op in ("ADD", "SUB", "AND", "OR"):
        exp_rd, exp_rs1, exp_rs2 = entry[1], entry[2], entry[3]
        checks = [("rd", rd, exp_rd), ("rs1", rs1f, exp_rs1), ("rs2", rs2f, exp_rs2)]
        exp_f3f7 = {"ADD": (0, 0), "SUB": (0, 1), "AND": (7, 0), "OR": (6, 0)}[op]
        checks += [("funct3", funct3, exp_f3f7[0]), ("funct7_5", funct7_5, exp_f3f7[1])]
    elif op == "ADDI":
        exp_rd, exp_rs1, exp_imm = entry[1], entry[2], entry[3]
        checks = [("rd", rd, exp_rd), ("rs1", rs1f, exp_rs1), ("imm", decode_i_imm(w), exp_imm)]
    elif op == "LW":
        exp_rd, exp_rs1, exp_imm = entry[1], entry[2], entry[3]
        checks = [("rd", rd, exp_rd), ("rs1", rs1f, exp_rs1), ("imm", decode_i_imm(w), exp_imm)]
    elif op == "SW":
        exp_rs2, exp_rs1, exp_imm = entry[1], entry[2], entry[3]
        checks = [("rs2", rs2f, exp_rs2), ("rs1", rs1f, exp_rs1), ("imm", decode_s_imm(w), exp_imm)]
    elif op == "BEQ":
        exp_rs1, exp_rs2, target_label = entry[1], entry[2], entry[3]
        exp_offset = labels[target_label] - a
        checks = [("rs1", rs1f, exp_rs1), ("rs2", rs2f, exp_rs2), ("offset", decode_b_imm(w), exp_offset)]

    passed = all(actual == expected for _, actual, expected in checks)
    all_ok = all_ok and passed
    detail = ", ".join(f"{name}={actual}(want {expected})" for name, actual, expected in checks)
    print(f"0x{a:02X} {op:<4} {'PASS' if passed else 'FAIL'}  [{detail}]")

print(f"\n{'ALL CHECKS PASSED' if all_ok else 'SOME CHECKS FAILED -- DO NOT USE program.hex'}")
