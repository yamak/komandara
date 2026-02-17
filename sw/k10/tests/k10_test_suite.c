/* ============================================================================
 * K10 Self-Test Suite
 * ============================================================================
 * Comprehensive self-test for the K10 core, exercising:
 *   1. Arithmetic (ADD/SUB/MUL/DIV/shifts)
 *   2. Unaligned memory access
 *   3. Timer interrupt (mtimecmp + mie + mstatus)
 *   4. Software interrupt (via sim_ctrl MSIP)
 *   5. ECALL
 *   6. EBREAK
 *
 * Results are printed via sim_ctrl CHAR_OUT.
 * Final pass/fail via sim_ctrl SIM_CTRL register.
 * ============================================================================ */

#include "k10.h"

// ============================================================================
// Trap state tracking
// ============================================================================

static volatile uint32_t trap_count    = 0;
static volatile uint32_t last_mcause   = 0;
static volatile int      timer_fired   = 0;
static volatile int      sw_irq_fired  = 0;
static volatile int      ecall_fired   = 0;
static volatile int      ebreak_fired  = 0;

// ============================================================================
// Trap Handler (called from startup.S _trap_vector)
// ============================================================================

uint32_t trap_handler(uint32_t mcause, uint32_t mepc) {
    trap_count++;
    last_mcause = mcause;

    if (mcause & 0x80000000U) {
        // Interrupt
        uint32_t cause_code = mcause & 0x7FFFFFFFU;

        if (cause_code == 7) {
            // Machine timer interrupt
            timer_fired = 1;
            // Disable timer interrupt to prevent re-entry
            clear_csr(mie, MIE_MTIE);
        } else if (cause_code == 3) {
            // Machine software interrupt
            sw_irq_fired = 1;
            // Clear MSIP via sim_ctrl
            SIM_MSIP = 0;
            // Disable software interrupt
            clear_csr(mie, MIE_MSIE);
        }
        return mepc;  // Return to interrupted instruction
    } else {
        // Exception
        if (mcause == 11) {
            // ECALL from M-mode
            ecall_fired = 1;
            return mepc + 4;  // Skip past ECALL
        } else if (mcause == 3) {
            // Breakpoint (EBREAK)
            ebreak_fired = 1;
            return mepc + 4;  // Skip past EBREAK (note: could be 2 if compressed)
        }
        // Unknown exception — advance past instruction
        return mepc + 4;
    }
}

// ============================================================================
// Test 1: Arithmetic
// ============================================================================

static int test_arithmetic(void) {
    TEST_START("Arithmetic");

    volatile int a = 42, b = 17;

    TEST_ASSERT(a + b == 59,  "ADD failed");
    TEST_ASSERT(a - b == 25,  "SUB failed");
    TEST_ASSERT(a * b == 714, "MUL failed");
    TEST_ASSERT(a / b == 2,   "DIV failed");
    TEST_ASSERT(a % b == 8,   "REM failed");

    // Shifts
    volatile uint32_t v = 0x12345678;
    TEST_ASSERT((v << 4) == 0x23456780, "SLL failed");
    TEST_ASSERT((v >> 4) == 0x01234567, "SRL failed");

    // Signed shift
    volatile int32_t sv = (int32_t)0xF0000000;
    TEST_ASSERT((sv >> 4) == (int32_t)0xFF000000, "SRA failed");

    TEST_OK();
    return 0;
}

// ============================================================================
// Test 2: Unaligned Memory Access
// ============================================================================

static int test_unaligned(void) {
    TEST_START("Unaligned access");

    // K10 supports unaligned accesses (hardware handles byte-lane steering)
    volatile uint8_t buf[8] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};

    // Unaligned 32-bit read at offset 1
    volatile uint32_t *p32 = (volatile uint32_t *)&buf[1];
    uint32_t val = *p32;
    TEST_ASSERT(val == 0x05040302, "Unaligned 32-bit read failed");

    // Unaligned 16-bit read at offset 1
    volatile uint16_t *p16 = (volatile uint16_t *)&buf[1];
    uint16_t val16 = *p16;
    TEST_ASSERT(val16 == 0x0302, "Unaligned 16-bit read failed");

    TEST_OK();
    return 0;
}

// ============================================================================
// Test 3: Timer Interrupt
// ============================================================================

static int test_timer_interrupt(void) {
    TEST_START("Timer IRQ");

    timer_fired = 0;

    // Read current mtime
    uint32_t mtime_lo = TIMER_MTIME_LO;

    // Set mtimecmp to current + 100 (fire soon)
    TIMER_MTIMECMP_HI = 0;
    TIMER_MTIMECMP_LO = mtime_lo + 100;

    // Enable timer interrupt
    set_csr(mie, MIE_MTIE);

    // Wait for interrupt (with timeout)
    for (volatile int i = 0; i < 10000 && !timer_fired; i++) {
        __asm__ volatile ("nop");
    }

    TEST_ASSERT(timer_fired, "Timer interrupt never fired");

    TEST_OK();
    return 0;
}

// ============================================================================
// Test 4: Software Interrupt
// ============================================================================

static int test_sw_interrupt(void) {
    TEST_START("SW IRQ");

    sw_irq_fired = 0;

    // Enable software interrupt
    set_csr(mie, MIE_MSIE);

    // Trigger software interrupt via sim_ctrl MSIP register
    SIM_MSIP = 1;

    // Wait for interrupt
    for (volatile int i = 0; i < 10000 && !sw_irq_fired; i++) {
        __asm__ volatile ("nop");
    }

    TEST_ASSERT(sw_irq_fired, "Software interrupt never fired");

    TEST_OK();
    return 0;
}

// ============================================================================
// Test 5: ECALL
// ============================================================================

static int test_ecall(void) {
    TEST_START("ECALL");

    ecall_fired = 0;

    // Trigger ECALL — trap handler will set ecall_fired and skip instruction
    __asm__ volatile ("ecall");

    TEST_ASSERT(ecall_fired, "ECALL trap not taken");

    TEST_OK();
    return 0;
}

// ============================================================================
// Test 6: EBREAK
// ============================================================================

static int test_ebreak(void) {
    TEST_START("EBREAK");

    ebreak_fired = 0;

    // Trigger EBREAK — trap handler will set ebreak_fired and skip instruction
    __asm__ volatile ("ebreak");

    TEST_ASSERT(ebreak_fired, "EBREAK trap not taken");

    TEST_OK();
    return 0;
}

// ============================================================================
// Main
// ============================================================================

int main(void) {
    k10_puts("=== K10 Self-Test Suite ===\n");

    int failures = 0;

    failures += test_arithmetic();
    failures += test_unaligned();
    failures += test_timer_interrupt();
    failures += test_sw_interrupt();
    failures += test_ecall();
    failures += test_ebreak();

    k10_puts("=== Tests complete: ");
    k10_put_dec(trap_count);
    k10_puts(" traps handled ===\n");

    if (failures == 0) {
        sim_pass();
    } else {
        k10_puts("FAILURES: ");
        k10_put_dec((uint32_t)failures);
        k10_putchar('\n');
        sim_fail();
    }

    return failures;
}
