# Copyright 2025 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# ============================================================================
# K10 — Self-Checking Unaligned Memory Access Test
# ============================================================================
# Tests that the LSU correctly handles unaligned loads and stores by
# splitting them into two consecutive aligned bus accesses.
#
# This test is SELF-CHECKING: it compares each result against an expected
# value and signals PASS (ECALL) or FAIL (EBREAK) directly to the K10 TB.
#
# NOTE: This test cannot be compared against Spike, because Spike traps
#       on misaligned accesses (no --misaligned support in our version).
#       Verification is done through self-checking assertions within the
#       assembly code itself.
#
# Memory layout (data_area starts at word-aligned address):
#   data_area + 0x00:  0xDEADBEEF
#   data_area + 0x04:  0xCAFEBABE
#   data_area + 0x08:  0x12345678
#   data_area + 0x0C:  0x9ABCDEF0
#   scratch_area:      64 bytes of scratch space for store tests
#
# Termination:
#   ECALL  → all tests passed
#   EBREAK → test failure (a0 = test number that failed)
# ============================================================================

.section .text.init
.globl _start

# ============================================================================
# Macro: CHECK — compare register against expected value, fail if mismatch
# ============================================================================
# Uses t0 as temporary. Sets a0 = test_num on failure and jumps to fail.
.macro CHECK reg, expected, test_num
    li      t0, \expected
    bne     \reg, t0, fail_\test_num
.endm

_start:
    # ====================================================================
    # Setup: initialize data area with known patterns
    # ====================================================================
    la      s0, data_area            # s0 = base address of data area

    li      t0, 0xDEADBEEF
    sw      t0, 0(s0)               # [base+0x00] = 0xDEADBEEF
    li      t0, 0xCAFEBABE
    sw      t0, 4(s0)               # [base+0x04] = 0xCAFEBABE
    li      t0, 0x12345678
    sw      t0, 8(s0)               # [base+0x08] = 0x12345678
    li      t0, 0x9ABCDEF0
    sw      t0, 12(s0)              # [base+0x0C] = 0x9ABCDEF0

    # ====================================================================
    # Test 1: Aligned LW (baseline — sanity check)
    # ====================================================================
    lw      a0, 0(s0)               # a0 = 0xDEADBEEF (aligned)
    CHECK   a0, 0xDEADBEEF, 1
    lw      a1, 4(s0)               # a1 = 0xCAFEBABE (aligned)
    CHECK   a1, 0xCAFEBABE, 2

    # ====================================================================
    # Test 3: Unaligned LW at offset +1 (crosses word boundary)
    # ====================================================================
    # Memory (LE bytes):
    #   addr+0: EF  addr+1: BE  addr+2: AD  addr+3: DE
    #   addr+4: BE  addr+5: BA  addr+6: FE  addr+7: CA
    # LW from addr+1: bytes at 1,2,3,4 = BE, AD, DE, BE → LE: 0xBEDEADBE
    addi    s1, s0, 1
    lw      a2, 0(s1)
    CHECK   a2, 0xBEDEADBE, 3

    # ====================================================================
    # Test 4: Unaligned LW at offset +2
    # ====================================================================
    # bytes at 2,3,4,5 = AD, DE, BE, BA → LE: 0xBABEDEAD
    addi    s1, s0, 2
    lw      a3, 0(s1)
    CHECK   a3, 0xBABEDEAD, 4

    # ====================================================================
    # Test 5: Unaligned LW at offset +3
    # ====================================================================
    # bytes at 3,4,5,6 = DE, BE, BA, FE → LE: 0xFEBABEDE
    addi    s1, s0, 3
    lw      a4, 0(s1)
    CHECK   a4, 0xFEBABEDE, 5

    # ====================================================================
    # Test 6: Unaligned LH at offset +3 (crosses word boundary)
    # ====================================================================
    # bytes at 3,4 = DE, BE → LE: 0xBEDE → sign-extend → 0xFFFFBEDE
    addi    s1, s0, 3
    lh      a5, 0(s1)
    CHECK   a5, 0xFFFFBEDE, 6

    # ====================================================================
    # Test 7: Unaligned LHU at offset +3 (crosses, zero-extend)
    # ====================================================================
    # bytes at 3,4 = DE, BE → LE: 0xBEDE → zero-extend → 0x0000BEDE
    lhu     a6, 0(s1)
    CHECK   a6, 0x0000BEDE, 7

    # ====================================================================
    # Test 8: LH at offset +1 (no crossing)
    # ====================================================================
    # bytes at 1,2 = BE, AD → LE: 0xADBE → sign-extend → 0xFFFFADBE
    addi    s1, s0, 1
    lh      a7, 0(s1)
    CHECK   a7, 0xFFFFADBE, 8

    # ====================================================================
    # Test 9: LHU at offset +1 (no crossing)
    # ====================================================================
    lhu     t1, 0(s1)
    CHECK   t1, 0x0000ADBE, 9

    # ====================================================================
    # Test 10: Byte loads at various offsets
    # ====================================================================
    lb      t1, 0(s0)               # byte 0: 0xEF → sign-extend → 0xFFFFFFEF
    CHECK   t1, 0xFFFFFFEF, 10
    lbu     t2, 1(s0)               # byte 1: 0xBE → zero-extend → 0x000000BE
    CHECK   t2, 0x000000BE, 11
    lb      t3, 2(s0)               # byte 2: 0xAD → sign-extend → 0xFFFFFFAD
    CHECK   t3, 0xFFFFFFAD, 12
    lbu     t4, 3(s0)               # byte 3: 0xDE → zero-extend → 0x000000DE
    CHECK   t4, 0x000000DE, 13

    # ====================================================================
    # Test 14: Unaligned SW at offset +1, verify round-trip
    # ====================================================================
    la      s2, scratch_area

    # Clear scratch area
    sw      zero, 0(s2)
    sw      zero, 4(s2)
    sw      zero, 8(s2)

    # Store 0xAABBCCDD at scratch+1 (unaligned)
    li      t5, 0xAABBCCDD
    addi    s3, s2, 1
    sw      t5, 0(s3)

    # Read back unaligned (should round-trip)
    lw      t6, 0(s3)
    CHECK   t6, 0xAABBCCDD, 14

    # ====================================================================
    # Test 15: Unaligned SW at offset +2, verify round-trip
    # ====================================================================
    sw      zero, 0(s2)
    sw      zero, 4(s2)

    li      t5, 0x11223344
    addi    s3, s2, 2
    sw      t5, 0(s3)

    lw      s4, 0(s3)
    CHECK   s4, 0x11223344, 15

    # ====================================================================
    # Test 16: Unaligned SW at offset +3, verify round-trip
    # ====================================================================
    sw      zero, 0(s2)
    sw      zero, 4(s2)
    sw      zero, 8(s2)

    li      t5, 0x55667788
    addi    s3, s2, 3
    sw      t5, 0(s3)

    lw      s5, 0(s3)
    CHECK   s5, 0x55667788, 16

    # ====================================================================
    # Test 17: Unaligned SH crossing boundary, verify round-trip
    # ====================================================================
    sw      zero, 0(s2)
    sw      zero, 4(s2)

    li      t5, 0xFFEE
    addi    s3, s2, 3
    sh      t5, 0(s3)

    lhu     s6, 0(s3)
    CHECK   s6, 0x0000FFEE, 17

    # ====================================================================
    # Test 18: Aligned store then unaligned load (pipeline stress)
    # ====================================================================
    li      t5, 0xA5A5A5A5
    sw      t5, 0(s2)
    li      t5, 0x5A5A5A5A
    sw      t5, 4(s2)

    addi    s3, s2, 1
    lw      s7, 0(s3)
    # bytes at scratch+1,+2,+3,+4: A5 A5 A5 5A → LE: 0x5AA5A5A5
    CHECK   s7, 0x5AA5A5A5, 18

    # ====================================================================
    # Test 19: Byte store to odd address, word load check
    # ====================================================================
    li      t5, 0x00000000
    sw      t5, 0(s2)                # Clear
    li      t5, 0xFF
    sb      t5, 1(s2)                # Store byte at scratch+1
    lw      s8, 0(s2)               # Read back word
    # After: byte0=00, byte1=FF, byte2=00, byte3=00 → 0x0000FF00
    CHECK   s8, 0x0000FF00, 19

    # ====================================================================
    # All tests passed!
    # ====================================================================
    li      a0, 0                    # Return code 0 = PASS
    ecall                            # Signal K10 TB to terminate

    # Spike path (unreachable in K10 sim)
    la      t0, tohost
    li      t1, 1
    sw      t1, 0(t0)
1:  j       1b

# ============================================================================
# Failure handlers — set a0 to the failing test number and use EBREAK
# ============================================================================
.altmacro
.macro FAIL_HANDLER num
fail_\num:
    li      a0, \num
    ebreak
.endm

FAIL_HANDLER 1
FAIL_HANDLER 2
FAIL_HANDLER 3
FAIL_HANDLER 4
FAIL_HANDLER 5
FAIL_HANDLER 6
FAIL_HANDLER 7
FAIL_HANDLER 8
FAIL_HANDLER 9
FAIL_HANDLER 10
FAIL_HANDLER 11
FAIL_HANDLER 12
FAIL_HANDLER 13
FAIL_HANDLER 14
FAIL_HANDLER 15
FAIL_HANDLER 16
FAIL_HANDLER 17
FAIL_HANDLER 18
FAIL_HANDLER 19

# ============================================================================
# Data section
# ============================================================================
.section .data
.balign 8
data_area:
    .word   0xDEADBEEF
    .word   0xCAFEBABE
    .word   0x12345678
    .word   0x9ABCDEF0
    .space  48

.balign 8
scratch_area:
    .space  64

# ============================================================================
# tohost / fromhost — Spike HTIF interface
# ============================================================================
.section .tohost, "aw", @progbits
.globl tohost
.globl fromhost
.align 4
tohost:   .word 0
fromhost: .word 0
