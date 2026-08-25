# ============================================================
#  primes.s — count & list primes below 50 (trial division)
#  Modulo done by repeated subtraction (RV32I, no DIV/REM).
#  0x100.. = prime list (words), 0x004(hi word alias) unused.
#  x9 (final) = count of primes -> also stored at 0x080-relative? no.
#  Store count at 0x0F0, primes from 0x100.
#  Exercises: nested loops, subroutine, blt/bge/beq, add/sub
# ============================================================
    .org 0x80
    j    _start
    j    trap_illegal
    j    trap_ecall
    j    trap_lsuerr

# is_prime(x10) -> x12 (1 if prime, else 0)
_start:
    li   x1, 0x100       # &out
    li   x20, 0          # count
    li   x21, 2          # n = 2
    li   x22, 50         # limit

scan:
    bge  x21, x22, finish
    add  x10, x0, x21
    jal  x5, is_prime    # ret addr in x5
    beq  x12, x0, next
    sw   x21, 0(x1)      # store prime
    addi x1, x1, 4
    addi x20, x20, 1
next:
    addi x21, x21, 1
    j    scan

finish:
    li   x23, 0x0F0
    sw   x20, 0(x23)     # store count
    li   x8, 0xC0DE0001
    sw   x8, 0(x0)
halt:
    j    halt

# ---- is_prime: n in x10, result in x12 ----
# trial divisor d = 2 .. n-1 ; if n % d == 0 -> not prime
is_prime:
    li   x12, 1          # assume prime
    li   x13, 2          # d = 2
ip_loop:
    bge  x13, x10, ip_done   # d >= n -> done, still prime
    # compute x10 % x13 via repeated subtraction into x14
    add  x14, x0, x10    # rem = n
mod_loop:
    blt  x14, x13, mod_done  # rem < d -> stop
    sub  x14, x14, x13
    j    mod_loop
mod_done:
    beq  x14, x0, not_prime  # rem == 0 -> divisible
    addi x13, x13, 1
    j    ip_loop
not_prime:
    li   x12, 0
ip_done:
    jalr x0, x5, 0       # return via x5

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
