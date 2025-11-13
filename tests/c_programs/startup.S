/* Startup code for bare-metal RISC-V */

    .section .text.start
    .globl _start
    .type _start, @function

_start:
    /* Initialize stack pointer (if needed) */
    /* For our simple CPU, we may not use stack */
    
    /* Zero out x0-x31 registers (x0 is hardwired to 0) */
    addi x1, x0, 0
    addi x2, x0, 0
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
