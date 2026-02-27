#include "k10.h"

uint32_t trap_handler(uint32_t mcause, uint32_t mepc) {
    (void)mcause;
    return mepc + 4;
}

int main(void) {
    uint32_t dcsr = (1u << 15);
    __asm__ volatile ("csrw 0x7b0, %0" :: "r"(dcsr));
    __asm__ volatile (".word 0x00100073");

    while (1) {
        __asm__ volatile ("wfi");
    }
}
