# ============================================================
#  rv32i_compliance.s — Comprehensive RV32I instruction test
#
#  Systematically tests EVERY base RV32I instruction, including
#  edge cases (sign extension, boundary values, zero register).
#
#  Results stored at 0x100+, each word = 1 if sub-test passed.
#  Final count of passes stored at 0x0FC.
#  Done flag 0xC0DE0001 at 0x000 when finished.
#
#  Exercises: ALL R-type, I-type, Load, Store, Branch, Jump, Upper
# ============================================================
    .org 0x80
    j    _start
    j    trap_illegal
    j    trap_ecall
    j    trap_lsuerr

# ============================================================
# MACROS are expanded manually since the assembler is minimal.
# Convention: x30 = pass counter, x29 = scratch
# Result word at 0x100 + 4*test_index = 1 (pass) or 0 (fail)
# ============================================================

_start:
    addi x30, x0, 0          # pass counter = 0
    li   x28, 0x100           # result base address

# ============================================================
# TEST GROUP 1:  R-type ALU instructions
# ============================================================

# --- TEST 0: ADD ---
    li   x1, 7
    li   x2, 13
    add  x3, x1, x2          # 7 + 13 = 20
    li   x4, 20
    beq  x3, x4, t0_pass
    j    t0_fail
t0_pass:
    addi x29, x0, 1
    sw   x29, 0(x28)
    addi x30, x30, 1
    j    t1_start
t0_fail:
    sw   x0, 0(x28)

# --- TEST 1: ADD negative ---
t1_start:
    li   x1, 100
    li   x2, -30
    add  x3, x1, x2          # 100 + (-30) = 70
    li   x4, 70
    beq  x3, x4, t1_pass
    j    t1_fail
t1_pass:
    addi x29, x0, 1
    sw   x29, 4(x28)
    addi x30, x30, 1
    j    t2_start
t1_fail:
    sw   x0, 4(x28)

# --- TEST 2: SUB ---
t2_start:
    li   x1, 50
    li   x2, 18
    sub  x3, x1, x2          # 50 - 18 = 32
    li   x4, 32
    beq  x3, x4, t2_pass
    j    t2_fail
t2_pass:
    addi x29, x0, 1
    sw   x29, 8(x28)
    addi x30, x30, 1
    j    t3_start
t2_fail:
    sw   x0, 8(x28)

# --- TEST 3: SUB producing negative ---
t3_start:
    li   x1, 10
    li   x2, 25
    sub  x3, x1, x2          # 10 - 25 = -15
    li   x4, -15
    beq  x3, x4, t3_pass
    j    t3_fail
t3_pass:
    addi x29, x0, 1
    sw   x29, 12(x28)
    addi x30, x30, 1
    j    t4_start
t3_fail:
    sw   x0, 12(x28)

# --- TEST 4: AND ---
t4_start:
    li   x1, 0xFF
    li   x2, 0x0F
    and  x3, x1, x2          # 0xFF & 0x0F = 0x0F
    li   x4, 0x0F
    beq  x3, x4, t4_pass
    j    t4_fail
t4_pass:
    addi x29, x0, 1
    sw   x29, 16(x28)
    addi x30, x30, 1
    j    t5_start
t4_fail:
    sw   x0, 16(x28)

# --- TEST 5: OR ---
t5_start:
    li   x1, 0xA0
    li   x2, 0x0B
    or   x3, x1, x2          # 0xA0 | 0x0B = 0xAB
    li   x4, 0xAB
    beq  x3, x4, t5_pass
    j    t5_fail
t5_pass:
    addi x29, x0, 1
    sw   x29, 20(x28)
    addi x30, x30, 1
    j    t6_start
t5_fail:
    sw   x0, 20(x28)

# --- TEST 6: XOR ---
t6_start:
    li   x1, 0xFF
    li   x2, 0xAA
    xor  x3, x1, x2          # 0xFF ^ 0xAA = 0x55
    li   x4, 0x55
    beq  x3, x4, t6_pass
    j    t6_fail
t6_pass:
    addi x29, x0, 1
    sw   x29, 24(x28)
    addi x30, x30, 1
    j    t7_start
t6_fail:
    sw   x0, 24(x28)

# --- TEST 7: SLL (shift left logical) ---
t7_start:
    li   x1, 1
    li   x2, 4
    sll  x3, x1, x2          # 1 << 4 = 16
    li   x4, 16
    beq  x3, x4, t7_pass
    j    t7_fail
t7_pass:
    addi x29, x0, 1
    sw   x29, 28(x28)
    addi x30, x30, 1
    j    t8_start
t7_fail:
    sw   x0, 28(x28)

# --- TEST 8: SRL (shift right logical) ---
t8_start:
    li   x1, 256
    li   x2, 3
    srl  x3, x1, x2          # 256 >> 3 = 32
    li   x4, 32
    beq  x3, x4, t8_pass
    j    t8_fail
t8_pass:
    addi x29, x0, 1
    sw   x29, 32(x28)
    addi x30, x30, 1
    j    t9_start
t8_fail:
    sw   x0, 32(x28)

# --- TEST 9: SRA (shift right arithmetic, preserves sign) ---
t9_start:
    li   x1, -128
    li   x2, 2
    sra  x3, x1, x2          # -128 >> 2 = -32 (arithmetic)
    li   x4, -32
    beq  x3, x4, t9_pass
    j    t9_fail
t9_pass:
    addi x29, x0, 1
    sw   x29, 36(x28)
    addi x30, x30, 1
    j    t10_start
t9_fail:
    sw   x0, 36(x28)

# --- TEST 10: SLT (set less than, signed) ---
t10_start:
    li   x1, -5
    li   x2, 3
    slt  x3, x1, x2          # -5 < 3 → 1
    li   x4, 1
    beq  x3, x4, t10_pass
    j    t10_fail
t10_pass:
    addi x29, x0, 1
    sw   x29, 40(x28)
    addi x30, x30, 1
    j    t11_start
t10_fail:
    sw   x0, 40(x28)

# --- TEST 11: SLT (not less than) ---
t11_start:
    li   x1, 10
    li   x2, 5
    slt  x3, x1, x2          # 10 < 5 → 0
    beq  x3, x0, t11_pass
    j    t11_fail
t11_pass:
    addi x29, x0, 1
    sw   x29, 44(x28)
    addi x30, x30, 1
    j    t12_start
t11_fail:
    sw   x0, 44(x28)

# --- TEST 12: SLTU (unsigned comparison) ---
t12_start:
    li   x1, -1              # 0xFFFFFFFF unsigned
    li   x2, 1
    sltu x3, x2, x1          # 1 < 0xFFFFFFFF → 1 (unsigned)
    li   x4, 1
    beq  x3, x4, t12_pass
    j    t12_fail
t12_pass:
    addi x29, x0, 1
    sw   x29, 48(x28)
    addi x30, x30, 1
    j    t13_start
t12_fail:
    sw   x0, 48(x28)

# ============================================================
# TEST GROUP 2:  I-type ALU instructions
# ============================================================

# --- TEST 13: ADDI ---
t13_start:
    li   x1, 100
    addi x3, x1, -37         # 100 - 37 = 63
    li   x4, 63
    beq  x3, x4, t13_pass
    j    t13_fail
t13_pass:
    addi x29, x0, 1
    sw   x29, 52(x28)
    addi x30, x30, 1
    j    t14_start
t13_fail:
    sw   x0, 52(x28)

# --- TEST 14: ANDI ---
t14_start:
    li   x1, 0x7F
    andi x3, x1, 0x3C        # 0x7F & 0x3C = 0x3C
    li   x4, 0x3C
    beq  x3, x4, t14_pass
    j    t14_fail
t14_pass:
    addi x29, x0, 1
    sw   x29, 56(x28)
    addi x30, x30, 1
    j    t15_start
t14_fail:
    sw   x0, 56(x28)

# --- TEST 15: ORI ---
t15_start:
    li   x1, 0x30
    ori  x3, x1, 0x0C        # 0x30 | 0x0C = 0x3C
    li   x4, 0x3C
    beq  x3, x4, t15_pass
    j    t15_fail
t15_pass:
    addi x29, x0, 1
    sw   x29, 60(x28)
    addi x30, x30, 1
    j    t16_start
t15_fail:
    sw   x0, 60(x28)

# --- TEST 16: XORI ---
t16_start:
    li   x1, 0xFF
    xori x3, x1, 0x55        # 0xFF ^ 0x55 = 0xAA
    li   x4, 0xAA
    beq  x3, x4, t16_pass
    j    t16_fail
t16_pass:
    addi x29, x0, 1
    sw   x29, 64(x28)
    addi x30, x30, 1
    j    t17_start
t16_fail:
    sw   x0, 64(x28)

# --- TEST 17: SLTI ---
t17_start:
    li   x1, -10
    slti x3, x1, 0           # -10 < 0 → 1
    li   x4, 1
    beq  x3, x4, t17_pass
    j    t17_fail
t17_pass:
    addi x29, x0, 1
    sw   x29, 68(x28)
    addi x30, x30, 1
    j    t18_start
t17_fail:
    sw   x0, 68(x28)

# --- TEST 18: SLTIU ---
t18_start:
    li   x1, 5
    sltiu x3, x1, 10         # 5 < 10 → 1 (unsigned)
    li   x4, 1
    beq  x3, x4, t18_pass
    j    t18_fail
t18_pass:
    addi x29, x0, 1
    sw   x29, 72(x28)
    addi x30, x30, 1
    j    t19_start
t18_fail:
    sw   x0, 72(x28)

# --- TEST 19: SLLI ---
t19_start:
    li   x1, 3
    slli x3, x1, 5           # 3 << 5 = 96
    li   x4, 96
    beq  x3, x4, t19_pass
    j    t19_fail
t19_pass:
    addi x29, x0, 1
    sw   x29, 76(x28)
    addi x30, x30, 1
    j    t20_start
t19_fail:
    sw   x0, 76(x28)

# --- TEST 20: SRLI ---
t20_start:
    li   x1, 1024
    srli x3, x1, 4           # 1024 >> 4 = 64
    li   x4, 64
    beq  x3, x4, t20_pass
    j    t20_fail
t20_pass:
    addi x29, x0, 1
    sw   x29, 80(x28)
    addi x30, x30, 1
    j    t21_start
t20_fail:
    sw   x0, 80(x28)

# --- TEST 21: SRAI ---
t21_start:
    li   x1, -64
    srai x3, x1, 3           # -64 >> 3 = -8 (arithmetic)
    li   x4, -8
    beq  x3, x4, t21_pass
    j    t21_fail
t21_pass:
    addi x29, x0, 1
    sw   x29, 84(x28)
    addi x30, x30, 1
    j    t22_start
t21_fail:
    sw   x0, 84(x28)

# ============================================================
# TEST GROUP 3:  Load/Store all widths
# ============================================================
# Use address 0x200 as scratch for load/store tests

# --- TEST 22: SW + LW ---
t22_start:
    li   x1, 0x200
    li   x2, 0xDEADBEEF
    sw   x2, 0(x1)
    lw   x3, 0(x1)
    beq  x3, x2, t22_pass
    j    t22_fail
t22_pass:
    addi x29, x0, 1
    sw   x29, 88(x28)
    addi x30, x30, 1
    j    t23_start
t22_fail:
    sw   x0, 88(x28)

# --- TEST 23: SB + LBU (store byte, load byte unsigned) ---
t23_start:
    li   x1, 0x210
    sw   x0, 0(x1)           # clear word first
    li   x2, 0xAB
    sb   x2, 0(x1)           # store byte
    lbu  x3, 0(x1)           # load byte unsigned
    li   x4, 0xAB
    beq  x3, x4, t23_pass
    j    t23_fail
t23_pass:
    addi x29, x0, 1
    sw   x29, 92(x28)
    addi x30, x30, 1
    j    t24_start
t23_fail:
    sw   x0, 92(x28)

# --- TEST 24: LB sign extension ---
t24_start:
    li   x1, 0x220
    li   x2, 0x80            # byte value 0x80 = -128 signed
    sb   x2, 0(x1)
    lb   x3, 0(x1)           # should sign-extend to 0xFFFFFF80 = -128
    li   x4, -128
    beq  x3, x4, t24_pass
    j    t24_fail
t24_pass:
    addi x29, x0, 1
    sw   x29, 96(x28)
    addi x30, x30, 1
    j    t25_start
t24_fail:
    sw   x0, 96(x28)

# --- TEST 25: SH + LHU (half-word unsigned) ---
t25_start:
    li   x1, 0x230
    sw   x0, 0(x1)           # clear
    li   x2, 0x1234
    sh   x2, 0(x1)           # store half
    lhu  x3, 0(x1)           # load half unsigned
    li   x4, 0x1234
    beq  x3, x4, t25_pass
    j    t25_fail
t25_pass:
    addi x29, x0, 1
    sw   x29, 100(x28)
    addi x30, x30, 1
    j    t26_start
t25_fail:
    sw   x0, 100(x28)

# --- TEST 26: LH sign extension ---
t26_start:
    li   x1, 0x240
    li   x2, 0x8000           # half = 0x8000 = -32768 signed
    sh   x2, 0(x1)
    lh   x3, 0(x1)           # should sign-extend to 0xFFFF8000
    li   x4, -32768
    beq  x3, x4, t26_pass
    j    t26_fail
t26_pass:
    addi x29, x0, 1
    sw   x29, 104(x28)
    addi x30, x30, 1
    j    t27_start
t26_fail:
    sw   x0, 104(x28)

# ============================================================
# TEST GROUP 4:  All branch types
# ============================================================

# --- TEST 27: BEQ (taken) ---
t27_start:
    li   x1, 42
    li   x2, 42
    beq  x1, x2, t27_pass
    j    t27_fail
t27_pass:
    addi x29, x0, 1
    sw   x29, 108(x28)
    addi x30, x30, 1
    j    t28_start
t27_fail:
    sw   x0, 108(x28)
    j    t28_start

# --- TEST 28: BEQ (not taken) ---
t28_start:
    li   x1, 1
    li   x2, 2
    beq  x1, x2, t28_fail
    j    t28_pass
t28_fail:
    sw   x0, 112(x28)
    j    t29_start
t28_pass:
    addi x29, x0, 1
    sw   x29, 112(x28)
    addi x30, x30, 1

# --- TEST 29: BNE ---
t29_start:
    li   x1, 10
    li   x2, 20
    bne  x1, x2, t29_pass
    j    t29_fail
t29_pass:
    addi x29, x0, 1
    sw   x29, 116(x28)
    addi x30, x30, 1
    j    t30_start
t29_fail:
    sw   x0, 116(x28)

# --- TEST 30: BLT (signed) ---
t30_start:
    li   x1, -5
    li   x2, 5
    blt  x1, x2, t30_pass    # -5 < 5 → taken
    j    t30_fail
t30_pass:
    addi x29, x0, 1
    sw   x29, 120(x28)
    addi x30, x30, 1
    j    t31_start
t30_fail:
    sw   x0, 120(x28)

# --- TEST 31: BGE (signed) ---
t31_start:
    li   x1, 10
    li   x2, 10
    bge  x1, x2, t31_pass    # 10 >= 10 → taken
    j    t31_fail
t31_pass:
    addi x29, x0, 1
    sw   x29, 124(x28)
    addi x30, x30, 1
    j    t32_start
t31_fail:
    sw   x0, 124(x28)

# --- TEST 32: BLTU (unsigned) ---
t32_start:
    li   x1, 5
    li   x2, -1              # 0xFFFFFFFF = huge unsigned
    bltu x1, x2, t32_pass    # 5 < 0xFFFFFFFF → taken
    j    t32_fail
t32_pass:
    addi x29, x0, 1
    sw   x29, 128(x28)
    addi x30, x30, 1
    j    t33_start
t32_fail:
    sw   x0, 128(x28)

# --- TEST 33: BGEU (unsigned) ---
t33_start:
    li   x1, -1              # 0xFFFFFFFF
    li   x2, 100
    bgeu x1, x2, t33_pass    # 0xFFFFFFFF >= 100 → taken
    j    t33_fail
t33_pass:
    addi x29, x0, 1
    sw   x29, 132(x28)
    addi x30, x30, 1
    j    t34_start
t33_fail:
    sw   x0, 132(x28)

# ============================================================
# TEST GROUP 5:  LUI, AUIPC, JAL, JALR
# ============================================================

# --- TEST 34: LUI ---
t34_start:
    lui  x3, 0xABCDE         # x3 = 0xABCDE000
    li   x4, 0xABCDE000
    beq  x3, x4, t34_pass
    j    t34_fail
t34_pass:
    addi x29, x0, 1
    sw   x29, 136(x28)
    addi x30, x30, 1
    j    t35_start
t34_fail:
    sw   x0, 136(x28)

# --- TEST 35: AUIPC ---
t35_start:
    auipc x3, 0              # x3 = PC of this instruction
    addi x4, x3, 8           # expected: PC + 8 = address of the beq below
    auipc x5, 0              # x5 = PC of this instruction = t35_start + 8
    beq  x4, x5, t35_pass
    j    t35_fail
t35_pass:
    addi x29, x0, 1
    sw   x29, 140(x28)
    addi x30, x30, 1
    j    t36_start
t35_fail:
    sw   x0, 140(x28)

# --- TEST 36: JAL (link address) ---
t36_start:
    jal  x1, t36_target      # x1 = return address (PC + 4)
t36_ret:
    beq  x3, x1, t36_pass    # x3 (set by target) should == x1
    j    t36_fail
t36_target:
    add  x3, x1, x0          # save link addr
    j    t36_ret
t36_pass:
    addi x29, x0, 1
    sw   x29, 144(x28)
    addi x30, x30, 1
    j    t37_start
t36_fail:
    sw   x0, 144(x28)

# --- TEST 37: JALR (indirect jump + link) ---
t37_start:
    jal  x1, t37_func        # call function
    # on return, x3 should be 99
    li   x4, 99
    beq  x3, x4, t37_pass
    j    t37_fail
t37_func:
    li   x3, 99
    jalr x0, 0(x1)           # return to caller (x1 = return addr)
t37_pass:
    addi x29, x0, 1
    sw   x29, 148(x28)
    addi x30, x30, 1
    j    t38_start
t37_fail:
    sw   x0, 148(x28)

# ============================================================
# TEST GROUP 6:  Edge cases
# ============================================================

# --- TEST 38: Write to x0 does nothing ---
t38_start:
    addi x0, x0, 42          # x0 must stay 0
    beq  x0, x0, t38_check   # always taken
    j    t38_fail
t38_check:
    li   x4, 0
    beq  x0, x4, t38_pass
    j    t38_fail
t38_pass:
    addi x29, x0, 1
    sw   x29, 152(x28)
    addi x30, x30, 1
    j    t39_start
t38_fail:
    sw   x0, 152(x28)

# --- TEST 39: ADD overflow wraps (unsigned) ---
t39_start:
    li   x1, 0x7FFFFFFF      # max positive
    li   x2, 1
    add  x3, x1, x2          # should wrap to 0x80000000 = -2147483648
    li   x4, 0x80000000
    beq  x3, x4, t39_pass
    j    t39_fail
t39_pass:
    addi x29, x0, 1
    sw   x29, 156(x28)
    addi x30, x30, 1
    j    t40_start
t39_fail:
    sw   x0, 156(x28)

# --- TEST 40: SRL on negative value (zero-fills) ---
t40_start:
    li   x1, -1              # 0xFFFFFFFF
    srli x3, x1, 16          # 0x0000FFFF = 65535
    li   x4, 0xFFFF
    beq  x3, x4, t40_pass
    j    t40_fail
t40_pass:
    addi x29, x0, 1
    sw   x29, 160(x28)
    addi x30, x30, 1
    j    done
t40_fail:
    sw   x0, 160(x28)

# ============================================================
# Done — store pass count and done flag
# ============================================================
done:
    li   x1, 0xFC
    sw   x30, 0(x1)          # pass count at 0x0FC
    li   x8, 0xC0DE0001
    sw   x8, 0(x0)           # done flag at 0x000
halt:
    j    halt

# ============================================================
# Exception handlers
# ============================================================
trap_illegal:
    li   x9, 0xBAD00001
    j    trap_store
trap_ecall:
    li   x9, 0xBAD00002
    j    trap_store
trap_lsuerr:
    li   x9, 0xBAD00003
trap_store:
    sw   x9, 4(x0)
trap_halt:
    j    trap_halt
