// UART sample without standard library
// Base address 0x100 (matches UART_BASE_ADDR in top module)

// Volatile access macros
#define UART_BASE 0x100

#define THR (*(volatile unsigned char *)(UART_BASE + 0x00))
#define RBR (*(volatile unsigned char *)(UART_BASE + 0x00))
#define IER (*(volatile unsigned char *)(UART_BASE + 0x01))
#define DLL (*(volatile unsigned char *)(UART_BASE + 0x00))
#define DLM (*(volatile unsigned char *)(UART_BASE + 0x01))
#define IIR (*(volatile unsigned char *)(UART_BASE + 0x02))
#define FCR (*(volatile unsigned char *)(UART_BASE + 0x02))
#define LCR (*(volatile unsigned char *)(UART_BASE + 0x03))
#define LSR (*(volatile unsigned char *)(UART_BASE + 0x05))

#define LCR_DLAB (0x80)
#define LCR_WLS_8 (0x03)
#define LSR_THRE (0x20)

// Simple exit helper used by other C tests that interact with testbench
void exit_program(void)
{
    asm volatile(
        "addi x3, x0, 1\n" // Signal success via x3
        "1: j 1b\n"
        :
        :
        : "x3");
    __builtin_unreachable();
}

void uart_init(unsigned int clk_freq, unsigned int baud_rate)
{
    // Avoid using division operator which will call libgcc helper in this
    // bare-metal build. Compute divisor with a simple subtraction loop.
    unsigned int divtmp = 0;
    unsigned int count = 0;
    unsigned int t = clk_freq;
    while (t >= baud_rate)
    {
        t -= baud_rate;
        count++;
    }
    unsigned short divisor = (unsigned short)(count - 1);

    LCR = LCR_DLAB;
    DLL = (unsigned char)(divisor & 0xFF);
    DLM = (unsigned char)((divisor >> 8) & 0xFF);
    LCR = LCR_WLS_8;       // 8-N-1
    FCR = (0x04) | (0x02); // clear FIFOs
}

void uart_putchar(char c)
{
    while ((LSR & LSR_THRE) == 0)
    {
        ;
    }
    THR = (unsigned char)c;
}

void uart_puts(const char *s)
{
    while (*s)
    {
        uart_putchar(*s++);
    }
}

void main(void)
{
    uart_init(50000000, 115200);
    uart_puts("Hello, UART!\n");

    // End of test: signal success to the testbench
    exit_program();
}
