# ============================================================
#  fib.s  — iterative Fibonacci (EASY)
#  Compute fib(0..11), store the 12 values at 0x100.
#  Exercises: li, add, sw, addi, blt, j
#  status @0x000 = 0xC0DE0001 when finished.
# ============================================================
    .org 0x80
    j    _start
    j    trap_illegal
    j    trap_ecall
    j    trap_lsuerr

_start:
    li   x1, 0x100       # &out[0]
    li   x2, 0           # a = fib(0)
    li   x3, 1           # b = fib(1)
    li   x4, 0           # i = 0
    li   x5, 12          # count

loop:
    bge  x4, x5, done
    sw   x2, 0(x1)       # out[i] = a
    add  x6, x2, x3      # next = a + b
    add  x2, x0, x3      # a = b
    add  x3, x0, x6      # b = next
    addi x1, x1, 4
    addi x4, x4, 1
    j    loop

done:
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
