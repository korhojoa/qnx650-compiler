/* QNX 6.5 ARM: binutils' armnto emulation script predates ARM EHABI and has
   no .ARM.exidx/.ARM.extab rules, so -ffunction-sections code scatters
   per-function exidx orphan sections and PT_ARM_EXIDX covers almost nothing
   -- C++ exceptions then fail at runtime (the unwinder lives in QNX libc.so.3
   and reads PT_ARM_EXIDX). This INSERT script merges them into the canonical
   single sections (armelf.x rules). Passed on every link via LINK_SPEC. */
SECTIONS
{
  .ARM.extab : { *(.ARM.extab* .gnu.linkonce.armextab.*) }
  .ARM.exidx :
  {
    PROVIDE_HIDDEN (__exidx_start = .);
    *(.ARM.exidx* .gnu.linkonce.armexidx.*)
    PROVIDE_HIDDEN (__exidx_end = .);
  }
} INSERT AFTER .text;
