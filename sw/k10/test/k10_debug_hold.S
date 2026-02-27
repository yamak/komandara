.section .text.init
.globl _start

_start:
1:
    wfi
    j 1b
