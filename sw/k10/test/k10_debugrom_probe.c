#include "k10.h"

uint32_t trap_handler(uint32_t mcause, uint32_t mepc) {
    (void)mcause;
    return mepc + 4;
}

int main(void) {
    void (*debug_rom_entry)(void) = (void (*)(void))0x40003800u;

    debug_rom_entry();

    while (1) {
        __asm__ volatile ("wfi");
    }
}
