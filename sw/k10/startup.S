// ============================================================================
// K10 Startup Code
// ============================================================================
// Entry point for K10 C applications. Sets up stack pointer, clears BSS,
// installs trap vector, and calls main(). On return, terminates via ECALL.
// ============================================================================

    .section .text.startup, "ax"
    .global _start
    .type _start, @function

_start:
    // ---- Set global pointer (linker relaxation) ----
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

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

    .size _start, . - _start

// ============================================================================
// Default Trap Vector  (direct mode)
// ============================================================================
// Simple trap handler that saves context, calls trap_handler(), and restores.
// For self-test purposes. Delegates to C function if defined.
// ============================================================================

    .section .text, "ax"
    .global _trap_vector
    .type _trap_vector, @function
    .balign 4

_trap_vector:
    // Save caller-saved registers
    addi    sp, sp, -64
    sw      ra,   0(sp)
    sw      t0,   4(sp)
    sw      t1,   8(sp)
    sw      t2,  12(sp)
    sw      a0,  16(sp)
    sw      a1,  20(sp)
    sw      a2,  24(sp)
    sw      a3,  28(sp)
    sw      a4,  32(sp)
    sw      a5,  36(sp)
    sw      a6,  40(sp)
    sw      a7,  44(sp)
    sw      t3,  48(sp)
    sw      t4,  52(sp)
    sw      t5,  56(sp)
    sw      t6,  60(sp)

    // Call C handler: trap_handler(mcause, mepc)
    csrr    a0, mcause
    csrr    a1, mepc
    call    trap_handler

    // Update mepc from return value (handler may advance it)
    csrw    mepc, a0

    // Restore
    lw      ra,   0(sp)
    lw      t0,   4(sp)
    lw      t1,   8(sp)
    lw      t2,  12(sp)
    lw      a0,  16(sp)
    lw      a1,  20(sp)
    lw      a2,  24(sp)
    lw      a3,  28(sp)
    lw      a4,  32(sp)
    lw      a5,  36(sp)
    lw      a6,  40(sp)
    lw      a7,  44(sp)
    lw      t3,  48(sp)
    lw      t4,  52(sp)
    lw      t5,  56(sp)
    lw      t6,  60(sp)
    addi    sp, sp, 64

    mret

    .size _trap_vector, . - _trap_vector
