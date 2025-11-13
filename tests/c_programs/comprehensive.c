// Comprehensive test for RISC-V CPU (RV32I only - no multiplication)

volatile int *const mem = (volatile int *)0;

void exit_program(void)
{
    asm volatile(
        "addi x3, x0, 1\n"
        "1: j 1b\n" ::: "x3");
    __builtin_unreachable();
}

// Test 1: Arithmetic operations (add/sub only)
int test_arithmetic(void)
{
    int a = 10;
    int b = 3;

    int sum = a + b;         // 13
    int diff = a - b;        // 7
    int result = sum + diff; // 20

    return result;
}

// Test 2: Logical operations
int test_logic(void)
{
    int x = 10; // 0b1010
    int y = 12; // 0b1100

    int and_result = x & y; // 8
    int or_result = x | y;  // 14
    int xor_result = x ^ y; // 6

    return and_result + or_result + xor_result; // 28
}

// Test 3: Shifts (instead of multiplication)
int test_shifts(void)
{
    int x = 5;

    int left = x << 2;     // 5 * 4 = 20
    int right = left >> 1; // 20 / 2 = 10

    return left + right; // 30
}

// Test 4: Comparison and branching
int test_compare(void)
{
    int result = 0;

    if (5 > 3)
        result += 10;
    if (2 < 8)
        result += 20;
    if (7 == 7)
        result += 30;
    if (4 != 9)
        result += 40;

    return result; // 100
}

// Test 5: Loops
int test_loops(void)
{
    int sum = 0;

    // Sum numbers 1 to 10
    for (int i = 1; i <= 10; i++)
    {
        sum += i;
    }

    return sum; // 55
}

// Test 6: Array operations
int test_array(void)
{
    int arr[5];

    // Initialize: 0, 2, 4, 6, 8
    arr[0] = 0;
    arr[1] = 2;
    arr[2] = 4;
    arr[3] = 6;
    arr[4] = 8;

    // Find max
    int max = arr[0];
    for (int i = 1; i < 5; i++)
    {
        if (arr[i] > max)
        {
            max = arr[i];
        }
    }

    return max; // 8
}

// Test 7: Fibonacci (iterative, no multiplication)
int fibonacci(int n)
{
    if (n <= 1)
        return n;

    int a = 0;
    int b = 1;
    int result = 0;

    for (int i = 2; i <= n; i++)
    {
        result = a + b;
        a = b;
        b = result;
    }

    return result;
}

int test_fibonacci(void)
{
    return fibonacci(10); // F(10) = 55
}

// Main function - run all tests
void main(void)
{
    // Run all tests and store results
    mem[0] = test_arithmetic(); // 20
    mem[1] = test_logic();      // 28
    mem[2] = test_shifts();     // 30
    mem[3] = test_compare();    // 100
    mem[4] = test_loops();      // 55
    mem[5] = test_array();      // 8
    mem[6] = test_fibonacci();  // 55

    // Calculate total
    int total = 0;
    for (int i = 0; i < 7; i++)
    {
        total += mem[i];
    }
    mem[7] = total; // 20+28+30+100+55+8+55 = 296

    // Success indicator
    mem[8] = 0xCAFE; // Magic number to verify completion

    exit_program();
}
