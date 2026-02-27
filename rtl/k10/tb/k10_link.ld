/* ============================================================================
 * K10 — Linker Script (Spike-compatible)
 * ============================================================================
 * Places code/data at 0x80000000 — compatible with Spike's default layout.
 * K10 TB maps BRAM at the same address via MEM_BASE parameter.
 * Includes .tohost section for Spike HTIF termination.
 * Stack grows down from the top of BRAM (64 KB).
 * ============================================================================ */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

_bram_start = 0x80000000;
_bram_size  = 64K;

SECTIONS
{
  . = _bram_start;
  .text.init : { *(.text.init) }
  .text      : { *(.text .text.*) }
  . = ALIGN(16);
  .rodata    : { *(.rodata .rodata.*) }
  . = ALIGN(0x1000);
  .tohost    : { *(.tohost) }
  . = ALIGN(16);
  .data      : { *(.data .data.*) }
  .bss       : { *(.bss .bss.* COMMON) }
  . = ALIGN(16);
  _end = .;

  /* Stack at top of BRAM */
  . = _bram_start + _bram_size - 4;
  _stack_top = .;
}
