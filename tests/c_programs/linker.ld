/* Linker script for bare-metal RISC-V CPU */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 1M
}

SECTIONS
{
    /* Start at address 0 instead of 0x80000000 */
    . = 0x00000000;
    .text.init : { *(.text.init) } > RAM
    . = ALIGN(0x1000);
    .tohost : { *(.tohost) } > RAM
    . = ALIGN(0x1000);
    .text : { *(.text) } > RAM
    . = ALIGN(0x1000);
    .data : { *(.data) } > RAM
    .bss : { *(.bss) } > RAM
    _end = .;
}
