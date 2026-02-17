# Copyright 2025 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

.section .text.init
.globl _start

_start:
    la   t0, trap_handler
    csrw mtvec, t0

    li   s0, 0

    # PMP0: NAPOT, locked, no R/W/X for an 8-byte region around pmp_data
    la   t1, pmp_data
    srli t1, t1, 2
    ori  t1, t1, 1
    csrw pmpaddr0, t1
    li   t2, 0x98
    csrw pmpcfg0, t2

    la   s1, pmp_data
    lw   t3, 0(s1)
    sw   t3, 4(s1)

    li   t4, 2
    bne  s0, t4, fail

    ecall

    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)
1:  j    1b

trap_handler:
    csrr t5, mcause
    li   t6, 5
    beq  t5, t6, trap_ok
    li   t6, 7
    beq  t5, t6, trap_ok
    j    fail

trap_ok:
    addi s0, s0, 1
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret

fail:
    ecall
2:  j    2b

.section .data
.balign 8
pmp_data:
    .word 0x11223344
    .word 0x55667788

.section .tohost, "aw", @progbits
.globl tohost
.globl fromhost
.align 4
tohost:   .word 0
fromhost: .word 0
