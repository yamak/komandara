/* ============================================================================
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
    BRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS
{
    .text : ALIGN(4)
    {
        *(.text.startup)
        *(.text*)
        . = ALIGN(4);
    } > BRAM

    .rodata : ALIGN(4)
    {
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > BRAM

    .data : ALIGN(4)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;  /* GP for linker relaxation */
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        __data_end = .;
    } > BRAM

    .bss : ALIGN(4)
    {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > BRAM

    /* Stack at top of BRAM */
    __stack_top = ORIGIN(BRAM) + LENGTH(BRAM);

    /DISCARD/ :
    {
        *(.eh_frame*)
        *(.comment)
    }
}
