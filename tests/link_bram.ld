/* Linker script for RISC-V tests on single-port BRAM at 0x10000 */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 16K
}

SECTIONS
{
  . = 0x00010000;
  
  .text.init : { 
    *(.text.init) 
  } > RAM
  
  . = ALIGN(0x100);
  .tohost : { 
    *(.tohost) 
  } > RAM
  
  . = ALIGN(0x100);
  .text : { 
    *(.text) 
  } > RAM
  
  . = ALIGN(0x100);
  .data : { 
    *(.data)
    *(.data.*)
  } > RAM
  
  .rodata : {
    *(.rodata)
    *(.rodata.*)
  } > RAM
  
  .bss : { 
    *(.bss)
    *(.bss.*)
    *(COMMON)
  } > RAM
  
  _end = .;
  
  /* Discard unnecessary sections */
  /DISCARD/ : {
    *(.eh_frame)
    *(.comment)
  }
}
