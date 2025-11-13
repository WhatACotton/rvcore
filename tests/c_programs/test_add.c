// Simple C program example for RISC-V CPU
// Bare-metal, no standard library

// Volatile to prevent optimization
volatile int *const mem = (volatile int *)0;

// Exit function - sets x3 to 1 to signal completion
void exit_program(void)
{
    asm volatile(
        "addi x3, x0, 1\n" // Set x3 = 1 (exit signal)
        "1: j 1b\n"        // Infinite loop
        ::: "x3");
    __builtin_unreachable();
}

// Simple addition function
int add(int a, int b)
{
    return a + b;
}

// Main function
void main(void)
{
    volatile int x = 10;
    volatile int y = 20;
    volatile int result;

    result = add(x, y);

    // Store result to memory location 0
    mem[0] = result;

    // Exit with success
    exit_program();
}
