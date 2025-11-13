// Fibonacci sequence calculator
// Computes F(n) where F(0)=0, F(1)=1, F(n)=F(n-1)+F(n-2)

volatile int *const mem = (volatile int *)0;

void exit_program(void)
{
    asm volatile(
        "addi x3, x0, 1\n"
        "1: j 1b\n" ::: "x3");
    __builtin_unreachable();
}

int fibonacci(int n)
{
    if (n <= 1)
        return n;

    int a = 0;
    int b = 1;
    int result;

    for (int i = 2; i <= n; i++)
    {
        result = a + b;
        a = b;
        b = result;
    }

    return result;
}

void main(void)
{
    // Calculate F(7) = 13
    int n = 7;
    int result = fibonacci(n);

    // Store to memory
    mem[0] = result; // Should be 13
    mem[1] = n;      // Store input

    exit_program();
}
