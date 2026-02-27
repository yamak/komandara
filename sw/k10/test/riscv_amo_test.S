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
    la   s9, trap_handler
    csrw mtvec, s9

    la   t0, amo_word
    li   t1, 1
    sw   t1, 0(t0)

    lr.w t2, (t0)
    addi t2, t2, 4
    sc.w t3, t2, (t0)
    bnez t3, fail

    lw   t4, 0(t0)
    li   t5, 5
    bne  t4, t5, fail

    amoadd.w t6, t1, (t0)
    bne  t6, t5, fail
    lw   s0, 0(t0)
    li   s1, 6
    bne  s0, s1, fail

    amoswap.w s2, t1, (t0)
    bne  s2, s1, fail
    lw   s3, 0(t0)
    bne  s3, t1, fail

    ecall

    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)
1:  j    1b

trap_handler:
    j    fail

fail:
    ecall
2:  j    2b

.section .data
.balign 8
amo_word:
    .word 0

.section .tohost, "aw", @progbits
.globl tohost
.globl fromhost
.align 4
tohost:   .word 0
fromhost: .word 0
