// Test program for debugging verification
// Tests CSR operations, register file, and control flow

// CSR addresses
#define CSR_MSTATUS 0x300
#define CSR_MTVEC 0x305
#define CSR_MCAUSE 0x342
#define CSR_MEPC 0x341

// CSR access macros
#define read_csr(reg) ({ unsigned long __tmp; \
  asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
  __tmp; })

#define write_csr(reg, val) ({ asm volatile("csrw " #reg ", %0" ::"r"(val)); })

// Test variables
volatile int test_var1 = 0xAAAA5555;
volatile int test_var2 = 0x12345678;
volatile int result = 0;

// Simple function for testing call/return
int add_function(int a, int b)
{
    return a + b;
}

// Shift and add function (avoid multiplication)
int shift_add_function(int a, int b)
{
    volatile int result = 0;
    volatile int count = b;
    // Add 'a' to result 'b' times using a loop
    while (count > 0)
    {
        result = result + a;
        count = count - 1;
    }
    return result;
}

int main(void)
{
    int temp;

    // Test 1: Basic arithmetic
    int a = 10;
    int b = 20;
    int sum = a + b;

    if (sum != 30)
    {
        asm volatile("li x3, 2"); // Error code 2
        while (1)
            ;
    }

    // Test 2: Function call
    result = add_function(5, 7);

    if (result != 12)
    {
        asm volatile("li x3, 3"); // Error code 3
        while (1)
            ;
    }

    // Test 3: Loop and shift-add
    result = shift_add_function(3, 4);

    if (result != 12)
    {
        asm volatile("li x3, 4"); // Error code 4
        while (1)
            ;
    }

    // Test 4: CSR operations
    write_csr(0x305, 0x1000); // Write mtvec
    temp = read_csr(0x305);   // Read back

    if (temp != 0x1000)
    {
        asm volatile("li x3, 5"); // Error code 5
        while (1)
            ;
    }

    // Test 5: Read/modify/write mstatus
    unsigned int mstatus_val = read_csr(0x300);
    write_csr(0x300, mstatus_val | 0x1808); // Set MIE and MPP
    temp = read_csr(0x300);

    if ((temp & 0x1808) != 0x1808)
    {
        asm volatile("li x3, 6"); // Error code 6
        while (1)
            ;
    }

    // Test 6: Memory access
    volatile int *ptr = &test_var1;
    *ptr = 0xDEADBEEF;

    if (test_var1 != 0xDEADBEEF)
    {
        asm volatile("li x3, 7"); // Error code 7
        while (1)
            ;
    }

    // Test 7: Array operations
    int array[5] = {1, 2, 3, 4, 5};
    int array_sum = 0;

    for (int i = 0; i < 5; i++)
    {
        array_sum += array[i];
    }

    if (array_sum != 15)
    {
        asm volatile("li x3, 8"); // Error code 8
        while (1)
            ;
    }

    // Test 8: Conditional branches
    int cond_result = 0;

    if (a < b)
    {
        cond_result = 1;
    }
    else
    {
        cond_result = 0;
    }

    if (cond_result != 1)
    {
        asm volatile("li x3, 9"); // Error code 9
        while (1)
            ;
    }

    // All tests passed
    asm volatile("li x3, 1"); // Success code

    while (1)
        ;

    return 0;
}
