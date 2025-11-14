/* Linker script for bare-metal RISC-V CPU */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 1M
}

SECTIONS
{
    /* Start at address 0 */
    . = 0x00000000;
    
    .text.init : { *(.text.init) } > RAM
    
    . = ALIGN(4);
    .text : { *(.text) } > RAM
    
    . = ALIGN(4);
    .data : { *(.data) } > RAM
    .bss : { *(.bss) } > RAM
    
    /* Place tohost at a fixed address */
    . = 0x00001000;
    .tohost : { 
        tohost = .;
        . = . + 4;  /* Reserve 4 bytes for tohost */
    } > RAM
    
    _end = .;
}
