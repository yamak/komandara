# Copyright 2025 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# ============================================================================
# K10 — Self-Checking Performance Counter Test
# ============================================================================
# Verifies monotonic behavior of mcycle/minstret and a basic retired-instruction
# lower bound over a deterministic instruction window.
# ============================================================================

.section .text.init
.globl _start

_start:
    # Snapshot initial counters
    csrr t0, mcycle
    csrr t1, minstret

    # Deterministic integer instruction window
    li   a0, 0x11111111
    li   a1, 0x22222222
    add  a2, a0, a1
    xor  a3, a2, a0
    and  a4, a3, a1
    or   a5, a4, a0
    addi a6, a5, 7
    slli a7, a6, 3
    srli s0, a7, 2
    sub  s1, s0, a0
    addi s2, s1, -9

    # Snapshot counters again
    csrr s3, mcycle
    csrr s4, minstret

    # Deltas
    sub  s5, s3, t0
    sub  s6, s4, t1

    # Monotonic checks: both must increase
    beqz s5, fail
    beqz s6, fail

    # minstret must include at least this instruction window
    li   s7, 8
    blt  s6, s7, fail

    # mcycle delta must be >= minstret delta
    blt  s5, s6, fail

    ecall

    # Spike path (unreachable in K10 sim)
    la   t2, tohost
    li   t3, 1
    sw   t3, 0(t2)
1:  j    1b

fail:
    j    fail

.section .tohost, "aw", @progbits
.globl tohost
.globl fromhost
.align 4
tohost:   .word 0
fromhost: .word 0
