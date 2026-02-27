export const tclTemplate = `# OpenOCD configuration for the Digilent Genesys 2 FPGA board
# Connecting to the K10 RISC-V softcore debug module via JTAG/BSCANE2

interface ftdi
transport select jtag

# FTDI layout for Digilent boards
ftdi_vid_pid 0x0403 0x6010
ftdi_channel 1

# Setup pin mappings
ftdi_layout_init 0x0088 0x008b
ftdi_layout_signal nTRST -ndata 0x0010

# Board Target Configuration
set CPU_NAME k10_core
set TAP_IDCODE 0x43651093

# Register the new TAP
jtag newtap $CPU_NAME cpu -irlen 6 -expected-id $TAP_IDCODE -ignore-version

# Define the target CPU
set TARGET_CPU $CPU_NAME.cpu
target create $TARGET_CPU riscv -chain-position $TARGET_CPU

# RISC-V debug module instruction register configurations
riscv set_ir idcode 0x09
riscv set_ir dtmcs 0x22
riscv set_ir dmi 0x23

# Adapter parameters
adapter speed 1000
reset_config none

# Hardware configuration
riscv set_prefer_sba on
gdb_breakpoint_override hard
gdb_report_data_abort enable
gdb_report_register_access_error enable

init
halt
`;

export const headerTemplate = `/* ============================================================================
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
    if (c == '\\n') {
#ifdef K10_REAL_HW
        while ((UART_STATUS & 0x1U) == 0U) {
        }
        UART_TXRX = (uint32_t)'\\r';
#else
        SIM_CHAR_OUT = (uint32_t)'\\r';
#endif
    }

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

static __attribute__((noinline)) void k10_put_dec(uint32_t val) {
    static char buf[11];
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
    k10_puts("[PASS]\\n");
#ifdef K10_REAL_HW
    while (1) {
        __asm__ volatile ("wfi");
    }
#else
    SIM_CTRL = 1;  // Triggers $finish with PASS
#endif
}

static inline void sim_fail(void) {
    k10_puts("[FAIL]\\n");
#ifdef K10_REAL_HW
    while (1) {
        __asm__ volatile ("wfi");
    }
#else
    SIM_CTRL = 0;  // Triggers $finish with FAIL
#endif
}

#define TEST_ASSERT(cond, msg) do { \\
    if (!(cond)) { \\
        k10_puts("ASSERT FAIL: "); \\
        k10_puts(msg); \\
        k10_putchar('\\n'); \\
        sim_fail(); \\
    } \\
} while (0)

#define TEST_START(name) k10_puts("  " name "... ")
#define TEST_OK()        k10_puts("OK\\n")

#endif // K10_H
`;

export const startupTemplate = `// ============================================================================
    // K10 Startup Code
    // ============================================================================
    // Entry point for K10 C applications. Sets up stack pointer, clears BSS,
    // installs trap vector, and calls main(). On return, terminates via ECALL.
    // ============================================================================

    .section .text.startup, "ax"
    .global _start
    .type _start, @function

_start:
    // ---- Disable linker relaxation for the entire startup function ----
    // This prevents the linker from shrinking instructions (e.g. call -> jal)
    // without updating the DWARF DW_AT_high_pc, which would cause _start's
    // debug range to overlap with main() and break GDB single-stepping.
    .option push
    .option norelax

    // ---- Set global pointer (linker relaxation) ----
    la      gp, __global_pointer$

    // ---- Set stack pointer ----
    la      sp, __stack_top

    // ---- Install trap vector ----
    la      t0, _trap_vector
    csrw    mtvec, t0

    // ---- Clear BSS section ----
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bge     t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:

    // ---- Enable global machine interrupts ----
    li      t0, 0x8           // MIE bit in mstatus
    csrs    mstatus, t0

    // ---- Call main() ----
    call    main

    // ---- Return value in a0; terminate via ECALL ----
    ecall

    // ---- Should not reach here ----
    j       .

    .option pop
    .size _start, . - _start

    // ============================================================================
    // Default Trap Vector  (direct mode)
    // ============================================================================
    // Traps context to the stack, discriminates between Exceptions and Async
    // Interrupts via mcause, and branches to C handlers.
    // ============================================================================

    .section .text, "ax"
    .global _trap_vector
    .type _trap_vector, @function
    .balign 4

_trap_vector:
    // Save only caller-saved registers (ABI requires ra, t0-t6, a0-a7)
    addi    sp, sp, -64
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a5, 36(sp)
    sw      a6, 40(sp)
    sw      a7, 44(sp)
    sw      t3, 48(sp)
    sw      t4, 52(sp)
    sw      t5, 56(sp)
    sw      t6, 60(sp)

    // Evaluate Exception vs Interrupt (MSB of mcause)
    csrr    a0, mcause
    bgez    a0, .L_handle_exception

.L_handle_interrupt:
    // Mask out the async bit just pass the reason
    slli    a0, a0, 1
    srli    a0, a0, 1
    call    interrupt_handler
    j       .L_restore_context

.L_handle_exception:
    // Simply trap on exceptions for the Template App
1:  j       1b

.L_restore_context:
    // Restore
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a5, 36(sp)
    lw      a6, 40(sp)
    lw      a7, 44(sp)
    lw      t3, 48(sp)
    lw      t4, 52(sp)
    lw      t5, 56(sp)
    lw      t6, 60(sp)
    addi    sp, sp, 64

    mret

    .size _trap_vector, . - _trap_vector
`;

export const mainTemplate = `#include "k10.h"



volatile uint32_t timer_ticks = 0;
const uint32_t MTIMER_FREQ_HZ = 50000000; // 50 MHz core clock
const uint32_t TIMER_INTERVAL_MS = 1000;  // 1 second

void timer_init(void) {
    uint32_t ticks = (MTIMER_FREQ_HZ / 1000) * TIMER_INTERVAL_MS;
    uint32_t mtime_lo = TIMER_MTIME_LO;
    uint32_t mtime_hi = TIMER_MTIME_HI;

    // Add interval to current mtime
    uint32_t target_lo = mtime_lo + ticks;
    uint32_t target_hi = mtime_hi + (target_lo < mtime_lo ? 1 : 0);

    // Write mtimecmp (setting high word to max, then low, then actual high)
    TIMER_MTIMECMP_HI = 0xFFFFFFFF;
    TIMER_MTIMECMP_LO = target_lo;
    TIMER_MTIMECMP_HI = target_hi;

    // Enable Machine Timer Interrupt
    set_csr(mie, MIE_MTIE);
}

void interrupt_handler(uint32_t mcause_reason) {
    if (mcause_reason == 7) { // Machine Timer Interrupt
        timer_ticks++;
        k10_puts("[Timer ISR] System uptime: ");
        k10_put_dec(timer_ticks);
        k10_puts(" seconds\\n");

        // Re-arm timer
        timer_init();
    } else {
        k10_puts("Unknown Interrupt Reason: ");
        k10_put_dec(mcause_reason);
        k10_puts("\\n");
    }
}


int main(void) {
    k10_puts("\\n---------------------------------\\n");
    k10_puts(" Komandara CPU Alive!\\n");
    k10_puts(" Initiating Timer ISR sequence...\\n");
    k10_puts("---------------------------------\\n");

    timer_init();

    // Globally Enable Machine Interrupts
    set_csr(mstatus, MSTATUS_MIE);

    while (1) {
        // CPU sleeps waiting for interrupts. Debugger can still halt here.
        __asm__ volatile("wfi");
    }

    return 0;
}
`;

export const cmakeTemplate = `cmake_minimum_required(VERSION 3.15)
project(komandara_app C ASM)

# Toolchain file will set this to Generic / riscv32
# Ensure we cross compile
if (NOT CMAKE_SYSTEM_PROCESSOR MATCHES "riscv32")
    message(FATAL_ERROR "Please configure using the provided toolchain file: -DCMAKE_TOOLCHAIN_FILE=riscv32.cmake")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(LINKER_SCRIPT "\${CMAKE_CURRENT_LIST_DIR}/k10_link.ld")
set(COMMON_FLAGS
    -march=rv32imac_zicsr
    -mabi=ilp32
    -Os
    -g
    -nostdlib
    -ffreestanding
    -fno-builtin
    -Wall
    -Wextra
)

if (K10_REAL_HW)
    add_compile_definitions(K10_REAL_HW=1)
endif()

include_directories("\${CMAKE_CURRENT_LIST_DIR}/include")

add_executable(k10_app startup.S main.c)

target_compile_options(k10_app PRIVATE \${COMMON_FLAGS})
target_link_options(k10_app PRIVATE
    -T "\${LINKER_SCRIPT}"
    -nostartfiles
    -static
    -Wl,--gc-sections
)

# Generate .bin and .dis files automatically after build
add_custom_command(TARGET k10_app POST_BUILD
    COMMAND "\${CMAKE_OBJCOPY}" -O binary "$<TARGET_FILE:k10_app>" "\${CMAKE_CURRENT_BINARY_DIR}/k10_app.bin"
    COMMAND "\${CMAKE_OBJDUMP}" -d -S "$<TARGET_FILE:k10_app>" > "\${CMAKE_CURRENT_BINARY_DIR}/k10_app.dis"
    COMMENT "Generated k10_app.bin and k10_app.dis"
)
`;

export const toolchainTemplate = `# CMake toolchain file for riscv32-unknown-elf-gcc
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv32)

set(TOOLS_DIR "$KOMANDARA_ROOT/tools")
set(TOOLCHAIN_PREFIX "\${TOOLS_DIR}/riscv-toolchain/bin/riscv32-unknown-elf-")

set(CMAKE_C_COMPILER   \${TOOLCHAIN_PREFIX}gcc)
set(CMAKE_CXX_COMPILER \${TOOLCHAIN_PREFIX}g++)
set(CMAKE_ASM_COMPILER \${TOOLCHAIN_PREFIX}gcc)
set(CMAKE_OBJCOPY      \${TOOLCHAIN_PREFIX}objcopy)
set(CMAKE_OBJDUMP      \${TOOLCHAIN_PREFIX}objdump)
set(CMAKE_SIZE         \${TOOLCHAIN_PREFIX}size)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
`;

export const linkerTemplate = `/* ============================================================================
 * K10 Linker Script
 * ============================================================================
 * Memory map:
 *   BRAM: 0x8000_0000 — 0x8000_FFFF  (64 KB)
 *   Peripheral: 0x4000_0000 — 0x4FFF_FFFF
 *
 * Text and data are placed in BRAM. Stack grows downward from top of BRAM.
 * ============================================================================ */

MEMORY
{
    BRAM(rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.text.startup))
        *(.text .text.*)
        . = ALIGN(4);
    } > BRAM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
    } > BRAM

    .data : ALIGN(4)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;  /* GP for linker relaxation */
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > BRAM

    .bss : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > BRAM

    /* Stack at top of BRAM */
    __stack_top = ORIGIN(BRAM) + LENGTH(BRAM);

    /DISCARD/ :
    {
        *(.eh_frame .eh_frame.*)
        *(.comment)
    }
}
`;


export const settingsJsonTemplate = `{
    "cmake.configureArgs": [
        "-DCMAKE_TOOLCHAIN_FILE=riscv32.cmake"
    ],
    "cmake.buildDirectory": "\${workspaceFolder}/build/\${buildType}",
    "cmake.generator": "Unix Makefiles",
    "cortex-debug.gdbPath.linux": "$KOMANDARA_ROOT/tools/riscv-toolchain/bin/riscv32-unknown-elf-gdb"
}`;

export const settingsJsonGenesys2Template = `{
    "cmake.configureArgs": [
        "-DCMAKE_TOOLCHAIN_FILE=riscv32.cmake",
        "-DK10_REAL_HW=ON"
    ],
    "cmake.buildDirectory": "\${workspaceFolder}/build/\${buildType}",
    "cmake.generator": "Unix Makefiles",
    "cortex-debug.gdbPath.linux": "$KOMANDARA_ROOT/tools/riscv-toolchain/bin/riscv32-unknown-elf-gdb"
}`;


export const launchJsonGenesys2 = `{
    "version": "0.2.0",
        "configurations": [
            {
                "name": "K10 Hardware Attach",
                "type": "cortex-debug",
                "request": "launch",
                "servertype": "openocd",
                "cwd": "\${workspaceFolder}",
                "executable": "\${command:cmake.launchTargetPath}",
                "configFiles": [
                    "openocd/board-openocd-cfg.tcl"
                ],
                "overrideAttachCommands": [
                    "set remotetimeout 25",
                    "monitor halt",
                    "monitor reset init",
                    "load"
                ],
                "runToEntryPoint": "main",
                "showDevDebugOutput": "raw"
            }
        ]
} `;

export const launchJsonSim = `{
    "version": "0.2.0",
        "configurations": [
            {
                "name": "K10 Verilator Target",
                "type": "cortex-debug",
                "request": "launch",
                "servertype": "openocd",
                "cwd": "\${workspaceFolder}",
                "executable": "\${command:cmake.launchTargetPath}",
                "serverArgs": [
                    "-c",
                    "adapter driver remote_bitbang",
                    "-c",
                    "remote_bitbang port 9824",
                    "-c",
                    "remote_bitbang host localhost",
                    "-c",
                    "set _CHIPNAME riscv",
                    "-c",
                    "jtag newtap \\\\$_CHIPNAME cpu -irlen 5"
                ],
                "overrideAttachCommands": [
                    "set remotetimeout 25",
                    "monitor halt",
                    "load"
                ],
                "runToEntryPoint": "main"
            }
        ]
} `;

export const cmakeKitsJsonTemplate = `[
    {
        "name": "Komandara RISC-V Toolchain",
        "toolchainFile": "\${workspaceFolder}/riscv32.cmake"
    }
]`;

export const tasksJsonTemplate = `{
    "version": "2.0.0",
        "tasks": [
            {
                "label": "Build Project",
                "type": "cmake",
                "command": "build",
                "group": {
                    "kind": "build",
                    "isDefault": true
                },
                "problemMatcher": "$gcc"
            },
            {
                "label": "Clean Project",
                "type": "cmake",
                "command": "clean",
                "problemMatcher": []
            }
        ]
} `;
