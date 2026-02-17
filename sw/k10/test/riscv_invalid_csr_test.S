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

    la   t1, user_entry
    csrw mepc, t1

    csrr t2, mstatus
    li   t3, ~(3 << 11)
    and  t2, t2, t3
    csrw mstatus, t2
    mret

user_entry:
    csrw mstatus, zero
    j    fail

trap_handler:
    csrr t4, mcause
    li   t5, 2
    bne  t4, t5, fail

    csrr t6, mepc
    la   s0, user_entry
    bne  t6, s0, fail

    ecall

fail:
    j    fail
