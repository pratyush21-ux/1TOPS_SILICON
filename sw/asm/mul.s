# ============================================================
#  mul.s  — software multiply + power (RV32I has no MUL)
#  Computes 7 * 13 (=91) with shift-add, then 3^5 (=243)
#  by repeated software multiply.
#  Results: 0x100 = 91, 0x104 = 243
#  Exercises: andi, srli, slli, add, beq, addi, nested loops
# ============================================================
    .org 0x80
    j    _start
    j    trap_illegal
    j    trap_ecall
    j    trap_lsuerr

# ---- mul(x10, x11) -> x12 (unsigned shift-add) ----
# uses x13 (multiplicand copy), x14 (multiplier copy)
_start:
    # --- 7 * 13 ---
    li   x10, 7
    li   x11, 13
    jal  x1, mul
    li   x20, 0x100
    sw   x12, 0(x20)     # store 91

    # --- 3^5 = 3*3*3*3*3 ---
    li   x15, 3          # base
    li   x16, 5          # exponent
    li   x17, 1          # acc = 1
powloop:
    beq  x16, x0, powdone
    add  x10, x0, x17    # x10 = acc
    add  x11, x0, x15    # x11 = base
    jal  x1, mul
    add  x17, x0, x12    # acc = acc * base
    addi x16, x16, -1
    j    powloop
powdone:
    sw   x17, 4(x20)     # store 243

    li   x8, 0xC0DE0001
    sw   x8, 0(x0)
halt:
    j    halt

# ---- multiply routine: x12 = x10 * x11 ----
mul:
    add  x12, x0, x0     # product = 0
    add  x13, x0, x10    # md = x10
    add  x14, x0, x11    # mr = x11
mul_loop:
    beq  x14, x0, mul_ret
    andi x18, x14, 1
    beq  x18, x0, mul_skip
    add  x12, x12, x13   # if lsb set, add md
mul_skip:
    slli x13, x13, 1     # md <<= 1
    srli x14, x14, 1     # mr >>= 1
    j    mul_loop
mul_ret:
    jalr x0, x1, 0       # return

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
