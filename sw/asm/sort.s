# ============================================================
#  Bubble sort — RV32I test program for the rv32i core
#
#  Exercises: lui, addi, slli, add, lw, sw, beq, bge, jal
#             (no RV32M — the core is RV32I only)
#
#  Data memory map
#    0x000   status word, 0xC0DE0001 once the sort finishes
#    0x004   trap marker, non-zero only if an exception fired
#    0x100   the 12-word signed array, sorted ascending in place
#
#  The core resets to boot_addr + 0x80, so the program is placed there
#  and the three exception vectors that follow are given real handlers
#  so a trap shows up as a marker instead of silently corrupting results.
# ============================================================

    .org 0x80

    j    _start          # 0x80  reset vector
    j    trap_illegal    # 0x84  illegal instruction
    j    trap_ecall      # 0x88  ecall
    j    trap_lsuerr     # 0x8c  load/store error

# ------------------------------------------------------------
# Seed the array from immediates, so the test needs no preloaded
# data memory: whatever the sort reads, this program wrote.
# ------------------------------------------------------------
_start:
    li   x1, 0x100       # x1 = &a[0]

    li   x2, 42
    sw   x2, 0(x1)
    li   x2, -7
    sw   x2, 4(x1)
    li   x2, 19
    sw   x2, 8(x1)
    li   x2, 0
    sw   x2, 12(x1)
    li   x2, 255
    sw   x2, 16(x1)
    li   x2, -128
    sw   x2, 20(x1)
    li   x2, 3
    sw   x2, 24(x1)
    li   x2, 77
    sw   x2, 28(x1)
    li   x2, -1
    sw   x2, 32(x1)
    li   x2, 1000
    sw   x2, 36(x1)
    li   x2, 5
    sw   x2, 40(x1)
    li   x2, -999
    sw   x2, 44(x1)

# ------------------------------------------------------------
# for (n = 12; --n != 0; )
#     for (i = 0; i < n; i++)
#         if (a[i+1] < a[i]) swap(a[i], a[i+1]);
# ------------------------------------------------------------
    li   x3, 12          # x3 = n

outer:
    addi x3, x3, -1      # n = n - 1
    beq  x3, x0, done    # no pairs left to compare
    addi x4, x0, 0       # i = 0

inner:
    bge  x4, x3, outer   # i >= n -> start the next pass
    slli x5, x4, 2
    add  x5, x5, x1      # x5 = &a[i]
    lw   x6, 0(x5)       # x6 = a[i]
    lw   x7, 4(x5)       # x7 = a[i+1]
    bge  x7, x6, noswap  # already in order (signed compare)
    sw   x7, 0(x5)
    sw   x6, 4(x5)
noswap:
    addi x4, x4, 1
    j    inner

done:
    li   x8, 0xC0DE0001
    sw   x8, 0(x0)       # publish the done flag
halt:
    j    halt            # park here for the debug unit

# ------------------------------------------------------------
# Exception handlers — record which one fired, then park.
# ------------------------------------------------------------
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
