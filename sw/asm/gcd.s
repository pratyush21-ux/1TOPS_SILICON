# ============================================================
#  gcd.s  — greatest common divisor (subtraction method)
#  gcd(1071, 462) = 21. Result stored at 0x100.
#  Exercises: li, beq, blt, sub, sw, j
# ============================================================
    .org 0x80
    j    _start
    j    trap_illegal
    j    trap_ecall
    j    trap_lsuerr

_start:
    li   x1, 1071        # a
    li   x2, 462         # b

gcd:
    beq  x1, x2, done    # a == b -> gcd
    blt  x1, x2, b_big   # a < b
    sub  x1, x1, x2      # a > b: a = a - b
    j    gcd
b_big:
    sub  x2, x2, x1      # b = b - a
    j    gcd

done:
    li   x3, 0x100
    sw   x1, 0(x3)       # store gcd
    li   x8, 0xC0DE0001
    sw   x8, 0(x0)
halt:
    j    halt

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
