# ============================================================
#  strlen_rev.s — string length + in-place reverse (COMPLEX)
#  Writes "RISCV" (0-terminated) to 0x200 as bytes, computes its
#  length into 0x100, then reverses the string in place.
#  Exercises: sb, lb, lbu, byte pointers, beq/blt, two subroutines.
#  After run, 0x200 holds "VCSIR\0", 0x100 = 5.
# ============================================================
    .org 0x80
    j    _start
    j    trap_illegal
    j    trap_ecall
    j    trap_lsuerr

_start:
    li   x1, 0x200       # str base
    # write "RISCV\0"  (R=82 I=73 S=83 C=67 V=86)
    li   x2, 82
    sb   x2, 0(x1)
    li   x2, 73
    sb   x2, 1(x1)
    li   x2, 83
    sb   x2, 2(x1)
    li   x2, 67
    sb   x2, 3(x1)
    li   x2, 86
    sb   x2, 4(x1)
    li   x2, 0
    sb   x2, 5(x1)

    # --- strlen ---
    add  x10, x0, x1     # ptr = base
    jal  x5, strlen      # -> x12 = len
    li   x20, 0x100
    sw   x12, 0(x20)     # store length (5)

    # --- reverse in place ---
    add  x10, x0, x1     # base
    add  x11, x0, x12    # len
    jal  x5, reverse

    li   x8, 0xC0DE0001
    sw   x8, 0(x0)
halt:
    j    halt

# ---- strlen: ptr in x10 -> len in x12 ----
strlen:
    li   x12, 0
sl_loop:
    add  x13, x10, x12
    lbu  x14, 0(x13)
    beq  x14, x0, sl_done
    addi x12, x12, 1
    j    sl_loop
sl_done:
    jalr x0, x5, 0

# ---- reverse: base x10, len x11 (destroys x5? no, uses x6) ----
# i = 0, j = len-1 ; swap while i < j
reverse:
    li   x15, 0          # i
    addi x16, x11, -1    # j = len-1
rev_loop:
    bge  x15, x16, rev_done
    add  x17, x10, x15   # &s[i]
    add  x18, x10, x16   # &s[j]
    lbu  x19, 0(x17)
    lbu  x20, 0(x18)
    sb   x20, 0(x17)
    sb   x19, 0(x18)
    addi x15, x15, 1
    addi x16, x16, -1
    j    rev_loop
rev_done:
    jalr x0, x5, 0

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
