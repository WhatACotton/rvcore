/*
 * clint_timer_test.c
 *
 * CLINT (Core-Local Interruptor) timer test program for FreeRTOS integration.
 *
 * This program tests the CLINT timer functionality by:
 * 1. Reading the mtime register
 * 2. Setting mtimecmp to trigger an interrupt
 * 3. Waiting for the timer interrupt
 * 4. Handling the timer interrupt in the trap handler
 */

#define CLINT_BASE 0x02000000
#define MTIMECMP_ADDR (CLINT_BASE + 0x4000) // 0x02004000
#define MTIME_ADDR (CLINT_BASE + 0xBFF8)    // 0x0200BFF8

#define MIE_MTIE (1 << 7)    // Machine timer interrupt enable
#define MIP_MTIP (1 << 7)    // Machine timer interrupt pending
#define MSTATUS_MIE (1 << 3) // Machine interrupt enable

// Volatile pointers to CLINT registers
volatile unsigned long long *mtime_ptr = (volatile unsigned long long *)MTIME_ADDR;
volatile unsigned long long *mtimecmp_ptr = (volatile unsigned long long *)MTIMECMP_ADDR;

// Flag to indicate timer interrupt occurred
volatile int timer_interrupt_count = 0;

// Read lower 32 bits of mtime
static inline unsigned int read_mtime_lo(void)
{
    volatile unsigned int *mtime_lo = (volatile unsigned int *)MTIME_ADDR;
    return *mtime_lo;
}

// Read upper 32 bits of mtime
static inline unsigned int read_mtime_hi(void)
{
    volatile unsigned int *mtime_hi = (volatile unsigned int *)(MTIME_ADDR + 4);
    return *mtime_hi;
}

// Read full 64-bit mtime (careful about overflow)
static inline unsigned long long read_mtime(void)
{
    unsigned int hi, lo;
    do
    {
        hi = read_mtime_hi();
        lo = read_mtime_lo();
    } while (hi != read_mtime_hi()); // Retry if overflow occurred
    return ((unsigned long long)hi << 32) | lo;
}

// Write lower 32 bits of mtimecmp
static inline void write_mtimecmp_lo(unsigned int value)
{
    volatile unsigned int *mtimecmp_lo = (volatile unsigned int *)MTIMECMP_ADDR;
    *mtimecmp_lo = value;
}

// Write upper 32 bits of mtimecmp
static inline void write_mtimecmp_hi(unsigned int value)
{
    volatile unsigned int *mtimecmp_hi = (volatile unsigned int *)(MTIMECMP_ADDR + 4);
    *mtimecmp_hi = value;
}

// Write full 64-bit mtimecmp
static inline void write_mtimecmp(unsigned long long value)
{
    // Write upper half first to prevent spurious interrupts
    write_mtimecmp_hi(0xFFFFFFFF); // Set to max first
    write_mtimecmp_lo((unsigned int)value);
    write_mtimecmp_hi((unsigned int)(value >> 32));
}

// Enable machine timer interrupts
static inline void enable_timer_interrupt(void)
{
    unsigned int mie;
    __asm__ volatile("csrr %0, mie" : "=r"(mie));
    mie |= MIE_MTIE;
    __asm__ volatile("csrw mie, %0" ::"r"(mie));

    // Enable global interrupts
    unsigned int mstatus;
    __asm__ volatile("csrr %0, mstatus" : "=r"(mstatus));
    mstatus |= MSTATUS_MIE;
    __asm__ volatile("csrw mstatus, %0" ::"r"(mstatus));
}

// Disable machine timer interrupts
static inline void disable_timer_interrupt(void)
{
    unsigned int mie;
    __asm__ volatile("csrr %0, mie" : "=r"(mie));
    mie &= ~MIE_MTIE;
    __asm__ volatile("csrw mie, %0" ::"r"(mie));
}

// Trap handler (called on timer interrupt)
void trap_handler(void) __attribute__((interrupt));
void trap_handler(void)
{
    unsigned int mcause;
    __asm__ volatile("csrr %0, mcause" : "=r"(mcause));

    // Check if it's a timer interrupt (bit 31 set, exception code 7)
    if ((mcause & 0x80000000) && ((mcause & 0x7FFFFFFF) == 7))
    {
        timer_interrupt_count++;

        // Clear interrupt by setting mtimecmp to max value
        write_mtimecmp(0xFFFFFFFFFFFFFFFFULL);
    }
}

int main(void)
{
    // Set up trap vector (startup.S is the entry point)
    extern void trap_handler(void);
    __asm__ volatile("csrw mtvec, %0" : : "r"((unsigned int)trap_handler));

    // Test 1: Read mtime
    unsigned long long current_time = read_mtime();

    // Test 2: Set mtimecmp to trigger interrupt after 1000 cycles
    unsigned long long target_time = current_time + 1000;
    write_mtimecmp(target_time);

    // Test 3: Enable timer interrupts
    enable_timer_interrupt();

    // Test 4: Wait for interrupt (busy loop)
    int timeout = 10000;
    while (timer_interrupt_count == 0 && timeout > 0)
    {
        __asm__ volatile("nop");
        timeout--;
    }

    // Test 5: Disable interrupts
    disable_timer_interrupt();

    // Check results
    if (timer_interrupt_count > 0)
    {
        // Success: Timer interrupt occurred
        // Store result in register x20 for verification
        __asm__ volatile("li x20, 0x12345678"); // Success code
    }
    else
    {
        // Failure: No interrupt
        __asm__ volatile("li x20, 0xDEADBEEF"); // Failure code
    }

    // Infinite loop
    while (1)
    {
        __asm__ volatile("nop");
    }

    return 0;
}

/* Removed local `_start` to avoid duplicate symbol with `startup.S`.
   `startup.S` provides the real `_start` entrypoint and calls `main`.
   Trap vector is initialized above in `main` before interrupts are enabled. */
