/* Startup code for bare-metal RISC-V */

    .section .text.start
    .globl _start
    .type _start, @function

_start:
    /* Initialize stack pointer from linker-provided symbol */
    la sp, __stack_top

    /* Zero out other caller-saved registers (x1 was set by la above) */
    addi x3, x0, 0
    addi x4, x0, 0
    addi x5, x0, 0
    addi x6, x0, 0
    addi x7, x0, 0
    addi x8, x0, 0
    addi x9, x0, 0
    addi x10, x0, 0
    
    /* Call main function */
    call main
    
    /* If main returns, exit */
    addi x3, x0, 1      # Set exit code
1:  j 1b                # Infinite loop
