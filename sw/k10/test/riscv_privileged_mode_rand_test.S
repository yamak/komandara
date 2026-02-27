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

    la   t1, user_entry
    csrw mepc, t1

    csrr t2, mstatus
    li   t3, ~(3 << 11)
    and  t2, t2, t3
    csrw mstatus, t2
    mret

user_entry:
    addi a0, a0, 1
    ecall

after_user:
    li   t0, 1
    bne  s0, t0, fail
    ecall

    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)
1:  j    1b

trap_handler:
    csrr t4, mcause
    li   t5, 8
    bne  t4, t5, fail

    li   s0, 1
    la   t6, after_user
    csrw mepc, t6

    csrr t2, mstatus
    li   t3, (3 << 11)
    or   t2, t2, t3
    csrw mstatus, t2
    mret

fail:
    ecall
2:  j    2b

.section .tohost, "aw", @progbits
.globl tohost
.globl fromhost
.align 4
tohost:   .word 0
fromhost: .word 0
