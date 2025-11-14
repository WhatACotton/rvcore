/*
 * Sdtrig (Debug Trigger Module) Test Program
 * Tests trigger configuration and external trigger functionality
 */

// CSR addresses
#define CSR_TSELECT 0x7A0
#define CSR_TDATA1 0x7A1
#define CSR_TDATA2 0x7A2

// Trigger types
#define TRIGGER_TYPE_MCONTROL 2
#define TRIGGER_TYPE_ICOUNT 3

// Test result reporting - tohost at fixed address
#define TOHOST ((volatile unsigned int *)0x00001000)

void write_tohost(unsigned int value)
{
    *TOHOST = value;
}

void test_pass()
{
    write_tohost(1); // Pass
    while (1)
        ;
}

void test_fail(unsigned int error_code)
{
    write_tohost(error_code); // Fail with error code
    while (1)
        ;
}

// CSR access macros (need to be compile-time constants)
#define READ_CSR(reg, csr) \
    asm volatile("csrr %0, " #csr : "=r"(reg))

#define WRITE_CSR(csr, val) \
    asm volatile("csrw " #csr ", %0" : : "r"(val))

#define read_tselect() ({ unsigned int __v; READ_CSR(__v, 0x7a0); __v; })
#define write_tselect(v) WRITE_CSR(0x7a0, v)
#define read_tdata1() ({ unsigned int __v; READ_CSR(__v, 0x7a1); __v; })
#define write_tdata1(v) WRITE_CSR(0x7a1, v)
#define read_tdata2() ({ unsigned int __v; READ_CSR(__v, 0x7a2); __v; })
#define write_tdata2(v) WRITE_CSR(0x7a2, v)

void main()
{
    unsigned int tselect_val, tdata1_val, tdata2_val;

    // Test 1: Basic CSR access - Write and read back tselect
    write_tselect(0);
    tselect_val = read_tselect();
    if (tselect_val != 0)
    {
        test_fail(0x101); // Failed to write tselect
    }

    // Test 2: Configure trigger 0 as mcontrol (execute trigger)
    write_tselect(0);

    // tdata1: type=2 (mcontrol), dmode=0, execute=1
    // [31:28]=type(2), [27]=dmode(0), [2]=execute(1)
    tdata1_val = (2 << 28) | (1 << 2);
    write_tdata1(tdata1_val);

    // Set trigger address to 0x100
    write_tdata2(0x100);

    // Read back and verify
    tdata1_val = read_tdata1();
    if ((tdata1_val >> 28) != 2)
    {
        test_fail(0x102); // Failed to set trigger type
    }

    tdata2_val = read_tdata2();
    if (tdata2_val != 0x100)
    {
        test_fail(0x103); // Failed to set trigger address
    }

    // Test 3: Configure trigger 1 as mcontrol (load trigger)
    write_tselect(1);

    // tdata1: type=2, load=1
    tdata1_val = (2 << 28) | (1 << 0);
    write_tdata1(tdata1_val);
    write_tdata2(0x200);

    // Verify
    tdata1_val = read_tdata1();
    if ((tdata1_val & 0x1) != 1)
    {
        test_fail(0x104); // Failed to set load bit
    }

    // Test 4: Configure trigger 2 as icount (external trigger)
    write_tselect(2);

    // tdata1: type=3 (icount), enable=1
    tdata1_val = (3 << 28) | (1 << 0);
    write_tdata1(tdata1_val);

    // Read back and verify type
    tdata1_val = read_tdata1();
    if ((tdata1_val >> 28) != 3)
    {
        test_fail(0x105); // Failed to set icount type
    }
    if ((tdata1_val & 0x1) != 1)
    {
        test_fail(0x106); // Failed to set enable bit
    }

    // Test 5: Configure trigger 3 as mcontrol (store trigger)
    write_tselect(3);

    // tdata1: type=2, store=1
    tdata1_val = (2 << 28) | (1 << 1);
    write_tdata1(tdata1_val);
    write_tdata2(0x300);

    // Verify
    tdata1_val = read_tdata1();
    if ((tdata1_val & 0x2) != 2)
    {
        test_fail(0x107); // Failed to set store bit
    }

    // Test 6: Verify trigger selection works
    write_tselect(0);
    tdata2_val = read_tdata2();
    if (tdata2_val != 0x100)
    {
        test_fail(0x108); // Trigger 0 address mismatch
    }

    write_tselect(1);
    tdata2_val = read_tdata2();
    if (tdata2_val != 0x200)
    {
        test_fail(0x109); // Trigger 1 address mismatch
    }

    write_tselect(3);
    tdata2_val = read_tdata2();
    if (tdata2_val != 0x300)
    {
        test_fail(0x10A); // Trigger 3 address mismatch
    }

    // All tests passed!
    test_pass();
}
