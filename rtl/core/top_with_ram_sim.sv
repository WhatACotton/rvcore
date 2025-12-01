// Top-level module for simulation that maintains rvcore_dm_connector interface
// This wraps the core with unified memory model for simulation testing

`timescale 1ns / 1ps

`include "dm_reg_addr.vh"

module top_with_ram_sim #(
    parameter int        START_ADDR     = 32'h00010000,  // Core entry point (default: RAM base address)
    parameter int        MEM_SIZE       = 1024 * 1024,   // 1MB (for compatibility, unused)
    parameter int        ADDR_WIDTH     = 13,
    parameter int        DATA_WIDTH     = 32,
    parameter int        HART_ID        = 0,             // Hart ID for debug output
    parameter bit [31:0] TOHOST_ADDR    = 32'h80001000,  // tohost address for tests
    parameter bit [31:0] UART_BASE_ADDR = 32'h00000100,  // UART base address in APB space
    parameter bit [31:0] UART_ADDR_MASK = 32'h00000FF0,  // UART address mask (16-byte region)
    parameter string     IMEM_INIT_FILE = "",            // IMEM initialization file (optional)
    parameter string     DMEM_INIT_FILE = ""             // DMEM initialization file (optional)
  ) (
    input logic clk,
    input logic reset_n,

    // Control/status
    output logic exit,

    // Debug mode status
    output logic debug_mode_o,

    // External trigger inputs/outputs
    input  logic [3:0] i_external_trigger,
    output logic [1:0] o_external_trigger,

    // RISC-V test support - tohost register
    output logic [31:0] tohost,

    // RISC-V test support - gp register (x3)
    output logic [31:0] gp,

    // Debug module interface
    output logic o_nonexistent,
    input  logic i_haltreq,
    input  logic i_resetreq,
    output logic o_hartreset,
    output logic o_unavailable,

    // CPU I/F - APB master interface to Debug Module
    output logic [ADDR_WIDTH-1:0] i_cpu_apb_paddr,
    output logic                  i_cpu_apb_psel,
    output logic                  i_cpu_apb_penable,
    output logic                  i_cpu_apb_pwrite,
    output logic [DATA_WIDTH-1:0] i_cpu_apb_pwdata,
    input  logic                  o_cpu_apb_pready,
    input  logic [DATA_WIDTH-1:0] o_cpu_apb_prdata,
    input  logic                  o_cpu_apb_pslverr,

    // UART interface
    input  logic uart_rx_i,
    output logic uart_tx_o,
    output logic uart_event_o,

    input  logic i_dmactive,
    input logic i_ext_resume_trigger


  );

  // =================================================================
  //  Internal Memory Parameters and Address Mapping
  // =================================================================
  localparam IMEM_DEPTH = 4096; // 16KB / 4 bytes
  localparam DMEM_DEPTH = 4096; // 16KB / 4 bytes
  
  // RAM Base Address - Fixed at 0x10000 (separate from Debug ROM area 0x200-0xFFF)
  // This ensures Debug ROM and RAM do not overlap in the address space
  localparam bit [31:0] RAM_BASE_ADDR = 32'h00010000;
  localparam bit [31:0] RAM_END_ADDR  = RAM_BASE_ADDR + (IMEM_DEPTH * 4) - 1; // 0x13FFF

  // Memory signals
  logic [31:0] imem_bram_dout;
  logic [11:0] imem_bram_addr;  // 12-bit for 4K words

  logic [31:0] dmem_bram_dout;
  logic [11:0] dmem_bram_addr;  // 12-bit for 4K words
  logic        dmem_bram_we;
  
  // Address range detection
  logic        imem_in_ram_area;
  logic        dmem_in_ram_area;

  // =================================================================
  //  Internal Signals for Core Interface
  // =================================================================
  logic [31:0] imem_addr;
  logic        imem_rready;
  logic [31:0] imem_rdata;
  logic        imem_rvalid;

  logic [31:0] dmem_addr;
  logic [ 1:0] dmem_wvalid;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_wstrb;
  logic        dmem_wready;
  logic [31:0] dmem_rdata;
  logic        dmem_rready;
  logic        dmem_rvalid;
  logic        debug_mode;
  logic        m_timer_interrupt;

  // CLINT signals - internal APB interface
  logic [12:0] clint_paddr;
  logic        clint_psel;
  logic        clint_penable;
  logic        clint_pwrite;
  logic [31:0] clint_pwdata;
  logic [31:0] clint_prdata;
  logic        clint_pready;
  logic        clint_pslverr;

  // Core handshake signals
  logic        cpu_imem_rready;
  logic        cpu_dmem_rready;
  logic        cpu_imem_rvalid;
  logic        cpu_dmem_rvalid;
  logic        cpu_dmem_wready;
  logic [ 1:0] cpu_dmem_wvalid;

  // Debug and CLINT Access detection
  logic        is_debug_rom_fetch;
  logic        is_dm_write;
  logic        is_dm_read;
  logic        is_debug_data_access;
  logic        is_clint_access;
  logic        is_clint_write;
  logic        is_clint_read;
  
  // UART Access detection
  logic        is_uart_access;
  logic        is_uart_write;
  logic        is_uart_read;

  // =================================================================
  //  Address Range Detection
  // =================================================================
  // Memory Map:
  // - 0x200-0xFFF: Debug Module area (Progbuf, Debug ROM, FLAG) via APB
  //   - 0x200-0x3FF: Debug ROM / Progbuf
  //   - 0x400-0x7FF: FLAG area (Hart communication with Debug Module)
  // - 0x10000-0x13FFF: Program RAM via BRAM
  //
  // In debug mode, all accesses to 0x200-0xFFF go through APB to Debug Module
  // This includes FLAG area which is used for resume/halt signaling between harts
  
  // Address masking: use only lower 14 bits (16KB) to handle wrap-around
  // This allows addresses like 0xffffff10 to map to RAM area
  logic [13:0] imem_masked_addr;
  logic [13:0] dmem_masked_addr;
  assign imem_masked_addr = imem_addr[13:0];
  assign dmem_masked_addr = dmem_addr[13:0];
  
  // RAM area only includes 0x10000-0x13FFF, NOT FLAG area (0x400-0x7FF)
  // FLAG area must go through APB to Debug Module for resume/halt communication
  assign imem_in_ram_area = ((imem_addr >= RAM_BASE_ADDR) && (imem_addr <= RAM_END_ADDR)) ||
                             (imem_addr[31:14] == 18'h3FFFF); // Handle 0xFFFFxxxx range
  assign dmem_in_ram_area = ((dmem_addr >= RAM_BASE_ADDR) && (dmem_addr <= RAM_END_ADDR)) ||
                             (dmem_addr[31:14] == 18'h3FFFF); // Handle 0xFFFFxxxx range

  // =================================================================
  //  Debug, CLINT, and UART Access Detection
  // =================================================================
  // Debug ROM access detection: 
  // - In debug mode, addresses 0x200-0xFFF go to Debug Module (Progbuf, Debug ROM)
  // - This takes priority over RAM access
  assign is_debug_rom_fetch = debug_mode &&
         (imem_addr >= DEBUG_AREA_START) &&
         (imem_addr <= DEBUG_AREA_END);

  assign is_dm_write = debug_mode && (cpu_dmem_wvalid != 2'b00) &&
         (dmem_addr >= DEBUG_AREA_START) && (dmem_addr <= DEBUG_AREA_END);

  assign is_debug_data_access = debug_mode &&
         (dmem_addr >= DEBUG_AREA_START) &&
         (dmem_addr <= DEBUG_AREA_END);

  assign is_dm_read = debug_mode && cpu_dmem_rready && is_debug_data_access;

  assign is_clint_access = (dmem_addr >= CLINT_BASE) && (dmem_addr <= CLINT_END);
  assign is_clint_write = is_clint_access && (cpu_dmem_wvalid != 2'b00);
  assign is_clint_read = is_clint_access && cpu_dmem_rready;
  
  // UART detection - accessible in normal mode via dmem
  assign is_uart_access = (dmem_addr >= UART_BASE_ADDR) && (dmem_addr <= UART_BASE_ADDR + 32'h0000000F);
  assign is_uart_write = is_uart_access && (cpu_dmem_wvalid != 2'b00);
  assign is_uart_read  = is_uart_access && cpu_dmem_rready;

  // =================================================================
  //  CLINT (Core-Local Interruptor) Instantiation
  // =================================================================
  clint #(
          .ADDR_WIDTH     (13),
          .DATA_WIDTH     (32),
          .CLINT_BASE_ADDR(CLINT_BASE)
        ) clint_inst (
          .clk                (clk),
          .reset_n            (reset_n),
          // APB Slave Interface
          .paddr              (clint_paddr),
          .psel               (clint_psel),
          .penable            (clint_penable),
          .pwrite             (clint_pwrite),
          .pwdata             (clint_pwdata),
          .pstrb              (4'hF),
          .prdata             (clint_prdata),
          .pready             (clint_pready),
          .pslverr            (clint_pslverr),
          // Timer Interrupt Output
          .m_timer_interrupt_o(m_timer_interrupt)
        );

  // CLINT APB signals - combinational for simple memory-mapped access
  always_comb
  begin
    clint_psel    = is_clint_access && (is_clint_write || is_clint_read);
    clint_penable = clint_psel;  // Assert both in same cycle for 1-cycle response
    clint_pwrite  = is_clint_write;
    clint_paddr   = (dmem_addr - CLINT_BASE);  // Convert to relative address
    clint_pwdata  = dmem_wdata;
  end

  // =================================================================
  //  APB Arbiter for Debug Module Access
  // =================================================================
  // Internal APB interfaces
  APB #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
      ) imem_apb_if ();

  APB #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
      ) dmem_apb_if ();

  APB #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
      ) arbiter_out_if ();

  // Instantiate APB arbiter
  apb_arbiter #(
                .ADDR_WIDTH (ADDR_WIDTH),
                .DATA_WIDTH (DATA_WIDTH),
                .NUM_MASTERS(2)
              ) arbiter_inst (
                .clk       (clk),
                .rst_n     (reset_n),
                .master0_if(imem_apb_if.Slave),
                .master1_if(dmem_apb_if.Slave),
                .slave_if  (arbiter_out_if.Master)
              );
              
  // =================================================================
  //  UART APB Slave Instantiation (New Direct Access Logic)
  // =================================================================
  // UART APB signals - combinational for simple memory-mapped access
  logic [ADDR_WIDTH-1:0] uart_paddr;
  logic                  uart_psel;
  logic                  uart_penable;
  logic                  uart_pwrite;
  logic [DATA_WIDTH-1:0] uart_pwdata;
  logic [DATA_WIDTH-1:0] uart_prdata;
  logic                  uart_pready;
  logic                  uart_pslverr;

  always_comb
  begin
    // UART APB Slave interface signals driven by core access
    uart_psel    = is_uart_access && (is_uart_write || is_uart_read);
    uart_penable = uart_psel; 
    uart_pwrite  = is_uart_write;
    // PADDR should be the full address for the APB UART module to decode internally
    uart_paddr   = dmem_addr[ADDR_WIDTH-1:0]; 
    uart_pwdata  = dmem_wdata;
  end

  // Instantiate UART
  apb_uart_sv #(
                .APB_ADDR_WIDTH(ADDR_WIDTH)
              ) uart_inst (
                .CLK    (clk),
                .RSTN   (reset_n),
                .PADDR  (uart_paddr),  // Driven by new logic
                .PWDATA (uart_pwdata), // Driven by new logic
                .PWRITE (uart_pwrite), // Driven by new logic
                .PSEL   (uart_psel),   // Driven by new logic
                .PENABLE(uart_penable), // Driven by new logic
                .PRDATA (uart_prdata),
                .PREADY (uart_pready),
                .PSLVERR(uart_pslverr),
                .rx_i   (uart_rx_i),
                .tx_o   (uart_tx_o),
                .event_o(uart_event_o)
              );

  // Connect arbiter output directly to external Debug Module APB interface
  assign i_cpu_apb_paddr        = arbiter_out_if.paddr;
  assign i_cpu_apb_psel         = arbiter_out_if.psel;
  assign i_cpu_apb_penable      = arbiter_out_if.penable;
  assign i_cpu_apb_pwrite       = arbiter_out_if.pwrite;
  assign i_cpu_apb_pwdata       = arbiter_out_if.pwdata;

  // Connect external APB response back to arbiter
  assign arbiter_out_if.pready  = o_cpu_apb_pready;
  assign arbiter_out_if.prdata  = o_cpu_apb_prdata;
  assign arbiter_out_if.pslverr = o_cpu_apb_pslverr;

  // =================================================================
  //  IMEM APB Master Logic (Debug ROM Access)
  // =================================================================
  typedef enum logic [1:0] {
            IMEM_IDLE,
            IMEM_SETUP,
            IMEM_ACCESS
          } imem_apb_state_t;
  imem_apb_state_t imem_apb_state, imem_apb_next_state;

  logic [          31:0] imem_apb_addr_reg;
  logic [ADDR_WIDTH-1:0] imem_transaction_addr;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      imem_apb_state        <= IMEM_IDLE;
      imem_apb_addr_reg     <= '0;
      imem_transaction_addr <= '0;
    end
    else if (!i_dmactive)
    begin
      // Reset state machine when debug module is deactivated (OpenOCD disconnect)
      imem_apb_state        <= IMEM_IDLE;
    end
    else
    begin
      imem_apb_state <= imem_apb_next_state;
      if (imem_apb_state == IMEM_IDLE && cpu_imem_rready && is_debug_rom_fetch)
      begin
        imem_apb_addr_reg     <= imem_addr;
        imem_transaction_addr <= imem_addr[ADDR_WIDTH-1:0];
      end
    end
  end

  always_comb
  begin
    imem_apb_next_state = imem_apb_state;
    case (imem_apb_state)
      IMEM_IDLE:
        if (cpu_imem_rready && is_debug_rom_fetch)
          imem_apb_next_state = IMEM_SETUP;
      IMEM_SETUP:
        imem_apb_next_state = IMEM_ACCESS;
      IMEM_ACCESS:
        if (imem_apb_if.pready)
          imem_apb_next_state = IMEM_IDLE;
      default:
        imem_apb_next_state = IMEM_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      imem_apb_if.paddr   <= '0;
      imem_apb_if.psel    <= 1'b0;
      imem_apb_if.penable <= 1'b0;
      imem_apb_if.pwrite  <= 1'b0;
      imem_apb_if.pwdata  <= '0;
      imem_apb_if.pstrb   <= '0;
      imem_apb_if.pprot   <= '0;
    end
    else
    begin
      case (imem_apb_state)
        IMEM_IDLE:
        begin
          imem_apb_if.psel    <= 1'b0;
          imem_apb_if.penable <= 1'b0;
          if (cpu_imem_rready && is_debug_rom_fetch)
          begin
            imem_apb_if.psel   <= 1'b1;
            imem_apb_if.paddr  <= imem_addr[ADDR_WIDTH-1:0];
            imem_apb_if.pwrite <= 1'b0;
          end
        end
        IMEM_SETUP:
        begin
          imem_apb_if.paddr   <= imem_transaction_addr;
          imem_apb_if.psel    <= 1'b1;
          imem_apb_if.penable <= 1'b1;
        end
        IMEM_ACCESS:
        begin
          imem_apb_if.paddr   <= imem_transaction_addr;
          imem_apb_if.psel    <= 1'b1;
          imem_apb_if.penable <= 1'b1;
          if (imem_apb_if.pready)
          begin
            imem_apb_if.psel    <= 1'b0;
            imem_apb_if.penable <= 1'b0;
          end
        end
        default:
        begin
          imem_apb_if.psel    <= 1'b0;
          imem_apb_if.penable <= 1'b0;
        end
      endcase
    end
  end

  // =================================================================
  //  DMEM APB Master Logic (Debug Module Access)
  // =================================================================
  typedef enum logic [1:0] {
            DMEM_IDLE,
            DMEM_SETUP,
            DMEM_ACCESS
          } dmem_apb_state_t;
  dmem_apb_state_t dmem_apb_state, dmem_apb_next_state;

  logic [          31:0] dmem_apb_addr_reg;
  logic [          31:0] dmem_apb_wdata_reg;
  logic                  dmem_apb_write_reg;
  logic [ADDR_WIDTH-1:0] dmem_transaction_addr;
  logic [          31:0] dmem_transaction_wdata;
  logic                  dmem_transaction_write;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      dmem_apb_state         <= DMEM_IDLE;
      dmem_apb_addr_reg      <= '0;
      dmem_apb_wdata_reg     <= '0;
      dmem_apb_write_reg     <= 1'b0;
      dmem_transaction_addr  <= '0;
      dmem_transaction_wdata <= '0;
      dmem_transaction_write <= 1'b0;
    end
    else if (!i_dmactive)
    begin
      // Reset state machine when debug module is deactivated (OpenOCD disconnect)
      dmem_apb_state         <= DMEM_IDLE;
    end
    else
    begin
      dmem_apb_state <= dmem_apb_next_state;
      if (dmem_apb_state == DMEM_IDLE && (is_dm_write || is_dm_read))
      begin
        dmem_apb_addr_reg      <= dmem_addr;
        dmem_apb_wdata_reg     <= dmem_wdata;
        dmem_apb_write_reg     <= is_dm_write;
        dmem_transaction_addr  <= dmem_addr[ADDR_WIDTH-1:0];
        dmem_transaction_wdata <= dmem_wdata;
        dmem_transaction_write <= is_dm_write;
      end
    end
  end

  always_comb
  begin
    dmem_apb_next_state = dmem_apb_state;
    case (dmem_apb_state)
      DMEM_IDLE:
        if (is_dm_write || is_dm_read)
          dmem_apb_next_state = DMEM_SETUP;
      DMEM_SETUP:
        dmem_apb_next_state = DMEM_ACCESS;
      DMEM_ACCESS:
        if (dmem_apb_if.pready)
          dmem_apb_next_state = DMEM_IDLE;
      default:
        dmem_apb_next_state = DMEM_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      dmem_apb_if.paddr   <= '0;
      dmem_apb_if.psel    <= 1'b0;
      dmem_apb_if.penable <= 1'b0;
      dmem_apb_if.pwrite  <= 1'b0;
      dmem_apb_if.pwdata  <= '0;
      dmem_apb_if.pstrb   <= 4'hF;
      dmem_apb_if.pprot   <= '0;
    end
    else
    begin
      case (dmem_apb_state)
        DMEM_IDLE:
        begin
          dmem_apb_if.psel    <= 1'b0;
          dmem_apb_if.penable <= 1'b0;
          if (is_dm_write || is_dm_read)
          begin
            dmem_apb_if.psel   <= 1'b1;
            dmem_apb_if.paddr  <= dmem_addr[ADDR_WIDTH-1:0];
            dmem_apb_if.pwrite <= is_dm_write;
            dmem_apb_if.pwdata <= dmem_wdata;
          end
        end
        DMEM_SETUP:
        begin
          dmem_apb_if.paddr   <= dmem_transaction_addr;
          dmem_apb_if.pwrite  <= dmem_transaction_write;
          dmem_apb_if.pwdata  <= dmem_transaction_wdata;
          dmem_apb_if.psel    <= 1'b1;
          dmem_apb_if.penable <= 1'b1;
        end
        DMEM_ACCESS:
        begin
          dmem_apb_if.paddr   <= dmem_transaction_addr;
          dmem_apb_if.pwrite  <= dmem_transaction_write;
          dmem_apb_if.pwdata  <= dmem_transaction_wdata;
          dmem_apb_if.psel    <= 1'b1;
          dmem_apb_if.penable <= 1'b1;
          if (dmem_apb_if.pready)
          begin
            dmem_apb_if.psel    <= 1'b0;
            dmem_apb_if.penable <= 1'b0;
          end
        end
        default:
        begin
          dmem_apb_if.psel    <= 1'b0;
          dmem_apb_if.penable <= 1'b0;
        end
      endcase
    end
  end

  // =================================================================
  //  Core Handshake Logic
  // =================================================================
  logic imem_rvalid_normal;
  logic imem_rvalid_debug;
  logic dmem_rvalid_normal;
  logic dmem_rvalid_debug;
  logic dmem_rvalid_clint;
  logic dmem_rvalid_uart; // New
  
  logic dmem_wready_normal;
  logic dmem_wready_debug;
  logic dmem_wready_clint;
  logic dmem_wready_uart; // New

  // IMEM valid signals
  // For single-port BRAM: use the valid signal from arbiter
  assign imem_rvalid_normal = bram_imem_valid;

  assign imem_rvalid_debug = (imem_apb_state == IMEM_ACCESS && imem_apb_if.pready);
  assign cpu_imem_rvalid   = imem_rvalid_normal || imem_rvalid_debug;

  // DMEM read valid signals
  // For single-port BRAM: use the valid signal from arbiter
  assign dmem_rvalid_normal = bram_dmem_valid && !dmem_bram_we;  // Valid for reads only

  assign dmem_rvalid_debug = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && !dmem_transaction_write);
  assign dmem_rvalid_clint = is_clint_read && clint_pready;
  assign dmem_rvalid_uart  = is_uart_read && uart_pready;
  
  assign cpu_dmem_rvalid = dmem_rvalid_normal || dmem_rvalid_debug || dmem_rvalid_clint || dmem_rvalid_uart;

  // DMEM write ready signals
  // For single-port BRAM: writes are always accepted immediately
  // (no arbitration conflict for writes - they always win)
  assign dmem_wready_normal = dmem_in_ram_area && !is_debug_data_access && !is_clint_access && !is_uart_access; 
  
  assign dmem_wready_debug = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && dmem_transaction_write);
  assign dmem_wready_clint = is_clint_write && clint_pready;
  assign dmem_wready_uart  = is_uart_write && uart_pready;
  
  assign cpu_dmem_wready = dmem_wready_normal || dmem_wready_debug || dmem_wready_clint || dmem_wready_uart;

  // =================================================================
  //  APB Response Capture and Memory Data Muxing
  // =================================================================
  logic [31:0] imem_apb_resp_reg;
  logic [31:0] dmem_apb_resp_reg;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      imem_apb_resp_reg <= 32'h0;
      dmem_apb_resp_reg <= 32'h0;
    end
    else
    begin
      if (imem_apb_state == IMEM_ACCESS && imem_apb_if.pready)
        imem_apb_resp_reg <= imem_apb_if.prdata;
      if (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && !dmem_transaction_write)
        dmem_apb_resp_reg <= dmem_apb_if.prdata;
    end
  end

  logic [31:0] imem_apb_data;
  logic [31:0] dmem_apb_data;

  assign imem_apb_data  = (imem_apb_state == IMEM_ACCESS) ? imem_apb_if.prdata : imem_apb_resp_reg;
  assign dmem_apb_data  = (dmem_apb_state == DMEM_ACCESS) ? dmem_apb_if.prdata : dmem_apb_resp_reg;

  // =================================================================
  //  UNIFIED Memory Instantiation with Address Translation
  //  RAM is mapped at 0x10000 - 0x13FFF
  //  Physical BRAM address = Virtual address - 0x10000
  // =================================================================
  
  // Address translation: Virtual (0x10000-0x13FFF) -> Physical (0x0000-0x3FFF)
  // For 0xFFFFxxxx addresses, use lower 14 bits directly (wrap-around behavior)
  logic [31:0] imem_phys_addr;
  logic [31:0] dmem_phys_addr;
  
  assign imem_phys_addr = (imem_addr[31:14] == 18'h3FFFF) ? {18'h0, imem_addr[13:0]} : 
                          (imem_addr - RAM_BASE_ADDR);
  assign dmem_phys_addr = (dmem_addr[31:14] == 18'h3FFFF) ? {18'h0, dmem_addr[13:0]} : 
                          (dmem_addr - RAM_BASE_ADDR);
  
  // Word address mapping - lower 14 bits give us 16KB address space
  assign imem_bram_addr = imem_phys_addr[13:2];
  assign dmem_bram_addr = dmem_phys_addr[13:2];
  
  // Write enable logic
  // DMEM write is enabled when:
  // 1. CPU issues a valid write (cpu_dmem_wvalid != 2'b00)
  // 2. Target is RAM area (dmem_in_ram_area)
  // 3. Not accessing debug module registers (is_debug_data_access)
  // 4. Not accessing peripherals (CLINT, UART)
  // Note: We allow writes in debug mode to normal memory (for progbuf execution)
  assign dmem_bram_we = (cpu_dmem_wvalid != 2'b00) && dmem_in_ram_area && 
                        !is_debug_data_access && !is_clint_access && !is_uart_access;

  // Single-port BRAM with arbiter - outputs valid signals
  logic bram_imem_valid;
  logic bram_dmem_valid;
  
  unified_gowin_bram #(
    .DEPTH     (IMEM_DEPTH), 
    .ADDR_WIDTH(12),
    .INIT_FILE (IMEM_INIT_FILE != "" ? IMEM_INIT_FILE : DMEM_INIT_FILE)
  ) main_ram_inst (
    .clk      (clk),
    .reset_n  (reset_n),
    
    // Port A: IMEM (Read Only)
    .imem_rd_en      (cpu_imem_rready && imem_in_ram_area && !is_debug_rom_fetch),
    .imem_addr       (imem_bram_addr),
    .imem_rd_data    (imem_bram_dout),
    .imem_rd_valid   (bram_imem_valid),  // NEW: indicates when IMEM data is valid
    
    // Port B: DMEM (Read/Write)
    .dmem_wr_en        (dmem_bram_we),
    .dmem_rd_en        (cpu_dmem_rready && dmem_in_ram_area && !is_debug_data_access && !is_clint_access && !is_uart_access),
    .dmem_addr         (dmem_bram_addr),
    .dmem_wr_data      (dmem_wdata),
    .dmem_rd_data      (dmem_bram_dout),
    .dmem_access_valid (bram_dmem_valid)  // NEW: indicates when DMEM data/write is valid
  );

  // Read Data Muxing
  // Priority: Debug ROM > CLINT > UART > RAM > Default (0x00000000)
  assign imem_rdata = is_debug_rom_fetch ? imem_apb_data : 
                      (imem_in_ram_area ? imem_bram_dout : 32'h00000000);
  
  assign dmem_rdata = is_clint_access ? clint_prdata :
                      (is_uart_access ? uart_prdata :
                      (is_debug_data_access ? dmem_apb_data : 
                      (dmem_in_ram_area ? dmem_bram_dout : 32'h00000000)));

`ifndef SYNTHESIS
  // Debug monitoring for routing verification
  always_ff @(posedge clk) begin
    // Monitor Debug ROM routing (CRITICAL for halt/resume)
    if (cpu_imem_rready && is_debug_rom_fetch) begin
      $display("[DEBUG_ROM] Time=%t HART=%0d addr=0x%08h -> APB (Progbuf/Debug ROM)", 
               $time, HART_ID, imem_addr);
    end
    
    // Monitor RAM access
    if (cpu_imem_rready && imem_in_ram_area) begin
      $display("[IMEM_RAM] Time=%t HART=%0d virt=0x%08h phys=0x%08h bram_addr=0x%03h", 
               $time, HART_ID, imem_addr, imem_phys_addr, imem_bram_addr);
    end
    
    // Monitor debug data access
    if ((cpu_dmem_wvalid != 2'b00 || cpu_dmem_rready) && is_debug_data_access) begin
      $display("[DEBUG_DATA] Time=%t HART=%0d addr=0x%08h wr=%b rd=%b -> APB", 
               $time, HART_ID, dmem_addr, (cpu_dmem_wvalid != 2'b00), cpu_dmem_rready);
    end
    
    // Monitor RAM writes
    if (cpu_dmem_wvalid != 2'b00 && dmem_in_ram_area) begin
      $display("[DMEM_WR_RAM] Time=%t HART=%0d virt=0x%08h phys=0x%08h data=0x%08h bram_addr=0x%03h", 
               $time, HART_ID, dmem_addr, dmem_phys_addr, dmem_wdata, dmem_bram_addr);
    end
    
    // Monitor RAM reads
    if (cpu_dmem_rready && dmem_in_ram_area) begin
      $display("[DMEM_RD_RAM] Time=%t HART=%0d virt=0x%08h phys=0x%08h bram_addr=0x%03h", 
               $time, HART_ID, dmem_addr, dmem_phys_addr, dmem_bram_addr);
    end
    
    // Debug: Monitor DMEM read request conditions
    if (cpu_dmem_rready && !dmem_in_ram_area) begin
      $display("[DMEM_RD_DEBUG] Time=%t HART=%0d RREADY but NOT in RAM area! addr=0x%08h debug=%b clint=%b uart=%b", 
               $time, HART_ID, dmem_addr, is_debug_data_access, is_clint_access, is_uart_access);
    end
    
    // Debug: Monitor dmem_rvalid generation
    if (cpu_dmem_rvalid) begin
      $display("[DMEM_RVALID] Time=%t HART=%0d rvalid=1 data=0x%08h (normal=%b debug=%b clint=%b uart=%b)", 
               $time, HART_ID, dmem_rdata, dmem_rvalid_normal, dmem_rvalid_debug, dmem_rvalid_clint, dmem_rvalid_uart);
    end
    
    // Monitor when address is out of range (potential bug)
    if (cpu_imem_rready && !imem_in_ram_area && !is_debug_rom_fetch) begin
      $display("[WARNING] IMEM access to unmapped region: 0x%08h", imem_addr);
    end
  end
`endif

  // =================================================================
  //  RISC-V Test Support (Tohost)
  // =================================================================
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      tohost <= 32'h0;
    end
    else if ((cpu_dmem_wvalid != 2'b00) && (dmem_addr == TOHOST_ADDR))
    begin
      tohost <= dmem_wdata;
    end
  end

  // Debug: Monitor CPU reset signal
  logic cpu_reset_n;
  assign cpu_reset_n = reset_n & ~i_resetreq;

  // =================================================================
  //  Core Instantiation
  // =================================================================
  core #(
         .START_ADDR(START_ADDR),
         .HART_ID   (HART_ID)
       ) cpu (
         .clk    (clk),
         .reset_n(cpu_reset_n),

         // DMEM Write Interface
         .dmem_wready(cpu_dmem_wready),
         .dmem_wvalid(cpu_dmem_wvalid),
         .dmem_wdata (dmem_wdata),
         .dmem_addr  (dmem_addr),

         // DMEM Read Interface
         .dmem_rvalid(cpu_dmem_rvalid),
         .dmem_rready(cpu_dmem_rready),
         .dmem_rdata (dmem_rdata),

         // IMEM Read Interface
         .imem_rready(cpu_imem_rready),
         .imem_rvalid(cpu_imem_rvalid),
         .imem_rdata (imem_rdata),
         .imem_addr  (imem_addr),

         .exit(exit),

         // Interrupt inputs
         .m_external_interrupt(1'b0),
         .m_timer_interrupt   (m_timer_interrupt),
         .m_software_interrupt(1'b0),

         // Debug interface
         .i_haltreq   (i_haltreq),
         .debug_mode_o(debug_mode),

         // External triggers
         .i_external_trigger(i_external_trigger),
         .o_external_trigger(o_external_trigger),
         .gp                (gp)
       );

  // Output Assignments
  assign debug_mode_o  = debug_mode;
  assign o_hartreset   = i_resetreq;
  assign o_nonexistent = 1'b0;
  assign o_unavailable = 1'b0;

endmodule

// =================================================================
//  Unified Gowin BRAM Wrapper - Single Port with Arbiter
//  True single-port RAM: only one access per cycle
//  DMEM has priority over IMEM
//  Suitable for both simulation and Gowin synthesis
// =================================================================
module unified_gowin_bram #(
    parameter        DEPTH      = 4096,
    parameter        ADDR_WIDTH = 12,
    parameter string INIT_FILE  = ""  // Optional initialization file
  ) (
    input  logic                     clk,
    input  logic                     reset_n,
    
    // Port A: IMEM Access (Read Only)
    input  logic                     imem_rd_en,
    input  logic [ADDR_WIDTH-1:0]    imem_addr,
    output logic [31:0]              imem_rd_data,
    output logic                     imem_rd_valid,  // NEW: indicates data is valid
    
    // Port B: DMEM Access (Read/Write)
    input  logic                     dmem_wr_en,
    input  logic                     dmem_rd_en,
    input  logic [ADDR_WIDTH-1:0]    dmem_addr,
    input  logic [31:0]              dmem_wr_data,
    output logic [31:0]              dmem_rd_data,
    output logic                     dmem_access_valid  // NEW: indicates data/write is valid
  );

  // Single-port BRAM
  logic [31:0] mem [DEPTH-1:0] /*synthesis syn_ramstyle="block_ram"*/;
  
  // Internal registers
  logic [31:0] rd_data_reg;
  logic [31:0] imem_rd_data_reg;
  logic [31:0] dmem_rd_data_reg;
  
  // Arbiter state - determines who accessed BRAM in previous cycle
  typedef enum logic [1:0] {
    ARB_IDLE,
    ARB_DMEM_WR,
    ARB_DMEM_RD,
    ARB_IMEM_RD
  } arb_state_t;
  
  arb_state_t arb_granted;
  logic dmem_rd_in_progress;  // Track if DMEM read is in progress
  logic imem_rd_in_progress;  // Track if IMEM read is in progress
  
  // Arbiter logic: DMEM has priority over IMEM
  logic                  bram_wr_en;
  logic                  bram_rd_en;
  logic [ADDR_WIDTH-1:0] bram_addr;
  logic [31:0]           bram_wr_data;
  arb_state_t            current_grant;
  
  always_comb begin
    bram_wr_en = 1'b0;
    bram_rd_en = 1'b0;
    bram_addr = '0;
    bram_wr_data = '0;
    current_grant = ARB_IDLE;
    
    // DMEM write has highest priority
    if (dmem_wr_en) begin
      current_grant = ARB_DMEM_WR;
      bram_addr = dmem_addr;
      bram_wr_data = dmem_wr_data;
      bram_wr_en = 1'b1;
      // Write-first: also read if dmem_rd_en is asserted
      bram_rd_en = dmem_rd_en && !dmem_rd_in_progress;  // Only start new read if not in progress
    end
    // DMEM read has second priority (but don't start new read if one is in progress)
    else if (dmem_rd_en && !dmem_rd_in_progress) begin
      current_grant = ARB_DMEM_RD;
      bram_addr = dmem_addr;
      bram_rd_en = 1'b1;
    end
    // IMEM read has lowest priority (but don't start new read if one is in progress)
    else if (imem_rd_en && !imem_rd_in_progress) begin
      current_grant = ARB_IMEM_RD;
      bram_addr = imem_addr;
      bram_rd_en = 1'b1;
    end
  end

  // BRAM access
  always_ff @(posedge clk) begin
    if (bram_wr_en) begin
      mem[bram_addr] <= bram_wr_data;
      // Write-first behavior
      if (bram_rd_en)
        rd_data_reg <= bram_wr_data;
    end else if (bram_rd_en) begin
      rd_data_reg <= mem[bram_addr];
    end
  end
  
  // Register grant for next cycle
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      arb_granted <= ARB_IDLE;
      dmem_rd_in_progress <= 1'b0;
      imem_rd_in_progress <= 1'b0;
    end else begin
      arb_granted <= current_grant;
      
      // Track read in progress
      // Set when read starts (bram_rd_en asserted)
      // Clear when the read completes (arb_granted shows the read was serviced)
      if (bram_rd_en && current_grant == ARB_DMEM_RD)
        dmem_rd_in_progress <= 1'b1;
      else if (arb_granted == ARB_DMEM_RD || arb_granted == ARB_DMEM_WR)
        dmem_rd_in_progress <= 1'b0;
      
      if (bram_rd_en && current_grant == ARB_IMEM_RD)
        imem_rd_in_progress <= 1'b1;
      else if (arb_granted == ARB_IMEM_RD)
        imem_rd_in_progress <= 1'b0;
    end
  end
  
  // Route data to appropriate port based on who was granted access
  // Data from BRAM is available in rd_data_reg one cycle after bram_rd_en
  // arb_granted tells us which port initiated the read
  always_ff @(posedge clk) begin
    if (!reset_n) begin
      imem_rd_data_reg <= '0;
      dmem_rd_data_reg <= '0;
      imem_rd_valid <= 1'b0;
      dmem_access_valid <= 1'b0;
    end else begin
      // Default: no valid data
      imem_rd_valid <= 1'b0;
      dmem_access_valid <= 1'b0;
      
      // Latch data and assert valid based on arb_granted from previous cycle
      // arb_granted indicates who initiated access in previous cycle
      // rd_data_reg contains the data read in previous cycle
      case (arb_granted)
        ARB_IMEM_RD: begin
          imem_rd_data_reg <= rd_data_reg;
          imem_rd_valid <= 1'b1;
        end
        ARB_DMEM_RD, ARB_DMEM_WR: begin
          dmem_rd_data_reg <= rd_data_reg;
          dmem_access_valid <= 1'b1;
        end
      endcase
    end
  end
  
  assign imem_rd_data = imem_rd_data_reg;
  assign dmem_rd_data = dmem_rd_data_reg;

  // Initialize memory from file
  initial begin
    if (INIT_FILE != "") begin
      $display("[BRAM] Loading %s...", INIT_FILE);
      $readmemh(INIT_FILE, mem);
      $display("[BRAM] Memory loaded. First 4 words:");
      $display("[BRAM]   mem[0] = 0x%08h", mem[0]);
      $display("[BRAM]   mem[1] = 0x%08h", mem[1]);
      $display("[BRAM]   mem[2] = 0x%08h", mem[2]);
      $display("[BRAM]   mem[3] = 0x%08h", mem[3]);
    end else begin
      $display("[BRAM] Loading firmware.hex...");
      $readmemh("firmware.hex", mem);
      $display("[BRAM] Memory loaded. First 4 words:");
      $display("[BRAM]   mem[0] = 0x%08h", mem[0]);
      $display("[BRAM]   mem[1] = 0x%08h", mem[1]);
      $display("[BRAM]   mem[2] = 0x%08h", mem[2]);
      $display("[BRAM]   mem[3] = 0x%08h", mem[3]);
    end
  end

endmodule