/* ============================================================================
 * K10 Hardware Abstraction Header
 * ============================================================================
 * Peripheral register map, CSR helpers, and utility functions for K10 tests.
 * ============================================================================ */

#ifndef K10_H
#define K10_H

#include <stdint.h>

// ============================================================================
// Peripheral Base Addresses
// ============================================================================

#define K10_TIMER_BASE     0x40000000U
#define K10_SIM_CTRL_BASE  0x40001000U
#define K10_UART_BASE      0x40002000U

// ============================================================================
// Timer Registers (k10_timer)
// ============================================================================

#define TIMER_MTIME_LO     (*(volatile uint32_t *)(K10_TIMER_BASE + 0x00))
#define TIMER_MTIME_HI     (*(volatile uint32_t *)(K10_TIMER_BASE + 0x04))
#define TIMER_MTIMECMP_LO  (*(volatile uint32_t *)(K10_TIMER_BASE + 0x08))
#define TIMER_MTIMECMP_HI  (*(volatile uint32_t *)(K10_TIMER_BASE + 0x0C))

// ============================================================================
// Sim Controller Registers (k10_sim_ctrl)
// ============================================================================

#define SIM_CTRL           (*(volatile uint32_t *)(K10_SIM_CTRL_BASE + 0x00))
#define SIM_CHAR_OUT       (*(volatile uint32_t *)(K10_SIM_CTRL_BASE + 0x04))
#define SIM_MSIP           (*(volatile uint32_t *)(K10_SIM_CTRL_BASE + 0x08))
#define SIM_STATUS         (*(volatile uint32_t *)(K10_SIM_CTRL_BASE + 0x0C))

// ============================================================================
// UART Registers (k10_uart)
// ============================================================================

#define UART_TXRX          (*(volatile uint32_t *)(K10_UART_BASE + 0x00))
#define UART_STATUS        (*(volatile uint32_t *)(K10_UART_BASE + 0x04))
#define UART_CTRL          (*(volatile uint32_t *)(K10_UART_BASE + 0x08))
#define UART_BAUD_DIV      (*(volatile uint32_t *)(K10_UART_BASE + 0x0C))
#define UART_IRQ_CLR       (*(volatile uint32_t *)(K10_UART_BASE + 0x10))

// ============================================================================
// CSR Helpers
// ============================================================================

#define read_csr(csr)       ({ unsigned long __v; \
    __asm__ volatile ("csrr %0, " #csr : "=r"(__v)); __v; })

#define write_csr(csr, val) ({ unsigned long __v = (unsigned long)(val); \
    __asm__ volatile ("csrw " #csr ", %0" :: "rK"(__v)); })

#define set_csr(csr, val)   ({ unsigned long __v = (unsigned long)(val); \
    __asm__ volatile ("csrs " #csr ", %0" :: "rK"(__v)); })

#define clear_csr(csr, val) ({ unsigned long __v = (unsigned long)(val); \
    __asm__ volatile ("csrc " #csr ", %0" :: "rK"(__v)); })

// ============================================================================
// Interrupt Constants
// ============================================================================

#define MIE_MSIE    (1U << 3)    // Software interrupt enable
#define MIE_MTIE    (1U << 7)    // Timer interrupt enable
#define MIE_MEIE    (1U << 11)   // External interrupt enable

#define MSTATUS_MIE (1U << 3)    // Global interrupt enable

// ============================================================================
// Console Output (via sim_ctrl)
// ============================================================================

static inline void k10_putchar(char c) {
#ifdef K10_REAL_HW
    while ((UART_STATUS & 0x1U) == 0U) {
    }
    UART_TXRX = (uint32_t)c;
#else
    SIM_CHAR_OUT = (uint32_t)c;
#endif
}

static inline void k10_puts(const char *s) {
    while (*s) {
        k10_putchar(*s++);
    }
}

static inline void k10_put_hex(uint32_t val) {
    const char hex[] = "0123456789abcdef";
    k10_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        k10_putchar(hex[(val >> i) & 0xF]);
    }
}

static inline void k10_put_dec(uint32_t val) {
    char buf[11];
    int i = 0;
    if (val == 0) { k10_putchar('0'); return; }
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    while (i > 0) k10_putchar(buf[--i]);
}

// ============================================================================
// Test Helpers
// ============================================================================

static inline void sim_pass(void) {
    k10_puts("[PASS]\n");
#ifdef K10_REAL_HW
    while (1) {
        __asm__ volatile ("wfi");
    }
#else
    SIM_CTRL = 1;  // Triggers $finish with PASS
#endif
}

static inline void sim_fail(void) {
    k10_puts("[FAIL]\n");
#ifdef K10_REAL_HW
    while (1) {
        __asm__ volatile ("wfi");
    }
#else
    SIM_CTRL = 0;  // Triggers $finish with FAIL
#endif
}

#define TEST_ASSERT(cond, msg) do { \
    if (!(cond)) { \
        k10_puts("ASSERT FAIL: "); \
        k10_puts(msg); \
        k10_putchar('\n'); \
        sim_fail(); \
    } \
} while (0)

#define TEST_START(name) k10_puts("  " name "... ")
#define TEST_OK()        k10_puts("OK\n")

#endif // K10_H
