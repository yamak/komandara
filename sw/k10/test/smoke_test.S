# Copyright 2025 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# ============================================================================
# K10 — Basic Arithmetic Smoke Test
# ============================================================================
# Simple test to verify the tracer and Spike-vs-K10 comparison flow.
# Uses only RV32I integer arithmetic.
#
# Termination:
#   - Spike: write 1 to 'tohost' symbol (standard HTIF convention)
#   - K10 TB: detects ECALL instruction in WB stage
# ============================================================================

.section .text.init
.globl _start

_start:
    # Basic arithmetic
    li   a0, 0x12345678       # Load immediate
    li   a1, 0xDEADBEEF       # Load immediate
    add  a2, a0, a1           # a2 = a0 + a1
    sub  a3, a0, a1           # a3 = a0 - a1
    and  a4, a0, a1           # a4 = a0 & a1
    or   a5, a0, a1           # a5 = a0 | a1
    xor  a6, a0, a1           # a6 = a0 ^ a1
    slli a7, a0, 4            # a7 = a0 << 4
    srli t0, a1, 8            # t0 = a1 >> 8   (logical)
    srai t1, a1, 8            # t1 = a1 >> 8   (arithmetic)

    # More operations
    addi t2, a0, -1           # t2 = a0 - 1
    slti t3, a0, 0            # t3 = (a0 < 0) ? 1 : 0
    slt  t4, a1, a0           # t4 = (a1 < a0) ? 1 : 0
    lui  t5, 0xABCDE          # t5 = 0xABCDE000
    auipc t6, 0               # t6 = current PC

    # ECALL to terminate K10 simulation (TB detects ECALL in WB stage)
    ecall

    # Write 1 to tohost to signal pass to Spike (never reached in K10 sim)
    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)

    # Infinite loop (should never reach here)
1:  j    1b

# ============================================================================
# tohost / fromhost — Spike HTIF interface
# ============================================================================
.section .tohost, "aw", @progbits
.globl tohost
.globl fromhost
.align 4
tohost:   .word 0
fromhost: .word 0
