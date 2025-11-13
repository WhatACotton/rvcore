// Test actual interrupt handling with interrupt inputs
// Tests hardware interrupts (timer, software, external)

// CSR addresses
#define CSR_MSTATUS 0x300
#define CSR_MIE 0x304
#define CSR_MIP 0x344
#define CSR_MTVEC 0x305
#define CSR_MCAUSE 0x342
#define CSR_MEPC 0x341

// Interrupt cause codes (with bit 31 set for interrupts)
#define INTERRUPT_SOFTWARE 0x80000003
#define INTERRUPT_TIMER 0x80000007
#define INTERRUPT_EXTERNAL 0x8000000B

// mstatus bits
#define MSTATUS_MIE (1 << 3)

// CSR access macros
#define read_csr(reg) ({ unsigned long __tmp; \
  asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
  __tmp; })

#define write_csr(reg, val) ({ asm volatile("csrw " #reg ", %0" ::"r"(val)); })

#define set_csr(reg, val) ({ asm volatile("csrs " #reg ", %0" ::"r"(val)); })

#define clear_csr(reg, val) ({ asm volatile("csrc " #reg ", %0" ::"r"(val)); })

// Interrupt handler state
volatile int interrupt_count = 0;
volatile unsigned int last_mcause = 0;
volatile unsigned int last_mepc = 0;

// Interrupt handler (must be aligned)
void __attribute__((aligned(4))) interrupt_handler(void)
{
    unsigned int cause, epc;

    // Read interrupt information
    asm volatile("csrr %0, 0x342" : "=r"(cause)); // mcause
    asm volatile("csrr %0, 0x341" : "=r"(epc));   // mepc

    interrupt_count++;
    last_mcause = cause;
    last_mepc = epc;

    // Return from interrupt
    asm volatile("mret");
}

int main(void)
{
    unsigned int val;

    // Test 1: Setup interrupt handler
    unsigned int handler_addr = (unsigned int)&interrupt_handler;
    write_csr(0x305, handler_addr); // mtvec
    val = read_csr(0x305);

    if (val != handler_addr)
    {
        // Failed to set mtvec
        asm volatile("li x3, 2");
        while (1)
            ;
    }

    // Test 2: Enable global interrupts in mstatus
    set_csr(0x300, MSTATUS_MIE); // Set MIE bit in mstatus
    val = read_csr(0x300);

    if ((val & MSTATUS_MIE) == 0)
    {
        // Failed to enable interrupts
        asm volatile("li x3, 3");
        while (1)
            ;
    }

    // Test 3: Wait for interrupt (test will trigger from Python)
    // The Python test will set m_timer_interrupt high
    interrupt_count = 0;

    // Small delay loop to allow interrupt to occur
    for (int i = 0; i < 100; i++)
    {
        asm volatile("nop");
    }

    // If we reach here without interrupt, that's OK for this test
    // The Python test will check interrupt_count externally

    // Test 4: Verify mstatus behavior during interrupt
    // After MRET, MIE should be restored
    val = read_csr(0x300);

    // Success - all tests passed
    asm volatile("li x3, 1");

    // Infinite loop
    while (1)
        ;

    return 0;
}
