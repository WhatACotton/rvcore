// CSR (Control and Status Register) test program
// Tests CSRRW, CSRRS, CSRRC instructions

volatile int *const mem = (volatile int *)0;

void exit_program(void)
{
    asm volatile(
        "addi x3, x0, 1\n"
        "1: j 1b\n" ::: "x3");
    __builtin_unreachable();
}

// CSR addresses (standard RISC-V CSRs)
#define CSR_MSTATUS 0x300
#define CSR_MISA 0x301
#define CSR_MIE 0x304
#define CSR_MTVEC 0x305
#define CSR_MSCRATCH 0x340
#define CSR_MEPC 0x341
#define CSR_MCAUSE 0x342
#define CSR_MTVAL 0x343
#define CSR_MIP 0x344

// CSR test functions using inline assembly
unsigned int csr_read_mscratch(void)
{
    unsigned int value;
    asm volatile("csrr %0, 0x340" : "=r"(value));
    return value;
}

void csr_write_mscratch(unsigned int value)
{
    asm volatile("csrw 0x340, %0" ::"r"(value));
}

unsigned int csr_swap_mscratch(unsigned int value)
{
    unsigned int old_value;
    asm volatile("csrrw %0, 0x340, %1" : "=r"(old_value) : "r"(value));
    return old_value;
}

unsigned int csr_set_mscratch(unsigned int mask)
{
    unsigned int old_value;
    asm volatile("csrrs %0, 0x340, %1" : "=r"(old_value) : "r"(mask));
    return old_value;
}

unsigned int csr_clear_mscratch(unsigned int mask)
{
    unsigned int old_value;
    asm volatile("csrrc %0, 0x340, %1" : "=r"(old_value) : "r"(mask));
    return old_value;
}

unsigned int csr_read_mepc(void)
{
    unsigned int value;
    asm volatile("csrr %0, 0x341" : "=r"(value));
    return value;
}

void csr_write_mepc(unsigned int value)
{
    asm volatile("csrw 0x341, %0" ::"r"(value));
}

unsigned int csr_read_mcause(void)
{
    unsigned int value;
    asm volatile("csrr %0, 0x342" : "=r"(value));
    return value;
}

void csr_write_mcause(unsigned int value)
{
    asm volatile("csrw 0x342, %0" ::"r"(value));
}

void main(void)
{
    unsigned int value;

    // Test 1: Write and read MSCRATCH (scratch register for machine mode)
    csr_write_mscratch(0x12345678);
    value = csr_read_mscratch();
    mem[0] = value; // Should be 0x12345678

    // Test 2: CSRRW - atomic read/write
    value = csr_swap_mscratch(0xABCDEF00);
    mem[1] = value; // Should be 0x12345678 (old value)
    value = csr_read_mscratch();
    mem[2] = value; // Should be 0xABCDEF00 (new value)

    // Test 3: CSRRS - atomic read and set bits
    csr_write_mscratch(0x00FF00FF);
    value = csr_set_mscratch(0xFF00FF00); // Set these bits
    mem[3] = value;                       // Should be 0x00FF00FF (old value)
    value = csr_read_mscratch();
    mem[4] = value; // Should be 0xFFFFFFFF (all bits set)

    // Test 4: CSRRC - atomic read and clear bits
    csr_write_mscratch(0xFFFFFFFF);
    value = csr_clear_mscratch(0x0F0F0F0F); // Clear these bits
    mem[5] = value;                         // Should be 0xFFFFFFFF (old value)
    value = csr_read_mscratch();
    mem[6] = value; // Should be 0xF0F0F0F0 (cleared bits)

    // Test 5: Test MEPC (exception program counter)
    csr_write_mepc(0x1000);
    value = csr_read_mepc();
    mem[7] = value; // Should be 0x1000

    // Test 6: Test MCAUSE (machine cause)
    csr_write_mcause(0x8000000B); // Interrupt bit + cause
    value = csr_read_mcause();
    mem[8] = value; // Should be 0x8000000B

    // Success marker
    mem[9] = 0xC5C5C5C5; // CSR test complete marker

    exit_program();
}
