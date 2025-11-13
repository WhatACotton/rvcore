// Test M-Mode CSRs and interrupt handling
// Tests mtvec, mcause, mepc, and interrupt processing

// CSR addresses
#define CSR_MTVEC 0x305
#define CSR_MCAUSE 0x342
#define CSR_MEPC 0x341

// CSR access macros
#define read_csr(reg) ({ unsigned long __tmp; \
  asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
  __tmp; })

#define write_csr(reg, val) ({ asm volatile("csrw " #reg ", %0" ::"r"(val)); })

#define swap_csr(reg, val) ({ unsigned long __tmp; \
  asm volatile ("csrrw %0, " #reg ", %1" : "=r"(__tmp) : "r"(val)); \
  __tmp; })

// Trap handler flag
volatile int trap_count = 0;
volatile int trap_cause = 0;
volatile int trap_epc = 0;

// Trap handler (must be aligned)
void __attribute__((aligned(4))) trap_handler(void)
{
    // Read trap information
    unsigned int cause, epc;

    asm volatile("csrr %0, 0x342" : "=r"(cause)); // mcause
    asm volatile("csrr %0, 0x341" : "=r"(epc));   // mepc

    trap_count++;
    trap_cause = cause;
    trap_epc = epc;

    // Return from trap
    asm volatile("mret");
}

int main(void)
{
    unsigned int val;

    // Test 1: Write and read mtvec
    unsigned int handler_addr = (unsigned int)&trap_handler;
    write_csr(0x305, handler_addr); // mtvec
    val = read_csr(0x305);

    if (val != handler_addr)
    {
        // Test failed
        asm volatile("li x3, 2"); // Error code 2
        asm volatile("ecall");
    }

    // Test 2: Test ECALL (should jump to trap handler)
    trap_count = 0;
    asm volatile("ecall");

    // After ECALL and MRET, we should be back here
    if (trap_count != 1)
    {
        asm volatile("li x3, 3"); // Error code 3
        asm volatile("ecall");
    }

    // Test 3: Verify mcause was set correctly (11 for ECALL from M-mode)
    if (trap_cause != 11)
    {
        asm volatile("li x3, 4"); // Error code 4
        asm volatile("ecall");
    }

    // Test 4: Read/write mepc
    write_csr(0x341, 0x12345678); // mepc
    val = read_csr(0x341);

    if (val != 0x12345678)
    {
        asm volatile("li x3, 5"); // Error code 5
        asm volatile("ecall");
    }

    // Test 5: Read/write mcause
    write_csr(0x342, 0xABCDEF00); // mcause
    val = read_csr(0x342);

    if (val != 0xABCDEF00)
    {
        asm volatile("li x3, 6"); // Error code 6
        asm volatile("ecall");
    }

    // All tests passed
    asm volatile("li x3, 1"); // Success code

    // Infinite loop to stop execution
    while (1)
    {
        asm volatile("nop");
    }

    return 0;
}
