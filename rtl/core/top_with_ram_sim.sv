// Top-level module for simulation that maintains rvcore_dm_connector interface
// This wraps the core with simple memory models for simulation testing

`timescale 1ns / 1ps

module top_with_ram_sim #(
    parameter int        START_ADDR     = 32'h00000000,  // CPU Reset Vector
    parameter int        MEM_SIZE       = 1024 * 1024,   // 1MB (Simulation default - unused for fixed RAM mapping)
    parameter int        ADDR_WIDTH     = 13,
    parameter int        DATA_WIDTH     = 32,
    // ★★★ 定義ファイル (DM_REG_ADDR_VH) に合わせる ★★★
    parameter bit [31:0] DEBUG_AREA_START = 32'h00000000, 
    parameter bit [31:0] DEBUG_AREA_END   = 32'h00001000,
    parameter int        HART_ID        = 0,             // Hart ID for debug output
    parameter bit [31:0] TOHOST_ADDR    = 32'h80001000,  // tohost address for tests
    parameter bit [31:0] UART_BASE_ADDR = 32'h00000100,  // UART base address in APB space
    parameter bit [31:0] UART_ADDR_MASK = 32'h00000FF0,  // UART address mask (16-byte region)
    parameter string     IMEM_INIT_FILE = "",            // IMEM initialization file (optional, for compatibility)
    parameter string     DMEM_INIT_FILE = ""             // DMEM initialization file (optional, for compatibility)
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
    input  logic i_dmactive,
    input  logic [1:0] i_ext_resume_trigger,
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
    output logic uart_event_o
  );

  // =================================================================
  //  Internal Memory - Gowin BRAM Implementation (Unified)
  // =================================================================
  // Use Gowin Block RAM primitives for synthesis
  // Memory is initialized from firmware.hex file via $readmemh in initial block
  // IMEM and DMEM share the same physical memory

  // Unified BRAM instantiation parameters
  localparam UNIFIED_MEM_DEPTH = 4096;  // 16KB (4096 words)
  
  // [FIXED] RAM Base Address hardcoded to 0x10000 as per request
  // This decouples the RAM location from the START_ADDR parameter.
  localparam bit [31:0] RAM_BASE_ADDR = 32'h00010000;
  localparam bit [31:0] RAM_END_ADDR  = RAM_BASE_ADDR + (UNIFIED_MEM_DEPTH * 4) - 1; // 0x13FFF

  // CLINT Address Definition (Default Standard RISC-V CLINT)
  localparam bit [31:0] CLINT_BASE = 32'h02000000;
  localparam bit [31:0] CLINT_END  = 32'h0200BFFF;

  // Unified memory signals
  logic [31:0] unified_bram_dout /*synthesis syn_keep=1*/;
  logic [11:0] unified_bram_addr;
  logic        unified_bram_we;
  logic        unified_bram_rd_en;
  logic [31:0] unified_bram_wr_data;

  // Separate read data for IMEM and DMEM paths
  logic [31:0] imem_bram_dout /*synthesis syn_keep=1*/;
  logic [11:0] imem_bram_addr;  // 12-bit for 4K words
  logic [31:0] dmem_bram_dout;
  logic [11:0] dmem_bram_addr;  // 12-bit for 4K words
  logic        dmem_bram_we;

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

  // Access Type Detection
  logic        is_debug_rom_fetch; // IMEM access to Debug ROM (via APB)
  logic        is_apb_dm_write;    // DMEM Write to APB (UART/Debug)
  logic        is_apb_dm_read;     // DMEM Read from APB (UART/Debug)
  
  logic        is_clint_access;
  logic        is_clint_write;
  logic        is_clint_read;

  // =================================================================
  //  Address Decoding Logic
  // =================================================================
  logic is_debug_area_imem;
  logic is_debug_area_dmem;
  logic is_uart_dmem;
  logic is_apb_dmem_access; // Combined Debug + UART (Any APB target)
  
  // 1. Debug Area Check (0x200 - 0xFFF)
  assign is_debug_area_imem = (imem_addr >= DEBUG_AREA_START) && (imem_addr <= DEBUG_AREA_END);
  assign is_debug_area_dmem = (dmem_addr >= DEBUG_AREA_START) && (dmem_addr <= DEBUG_AREA_END);
  
  // 2. UART Area Check (0x100 - 0x10F)
  assign is_uart_dmem = ((dmem_addr & UART_ADDR_MASK) == UART_BASE_ADDR);

  // 3. Combined APB Access (Debug OR UART)
  // This signal dictates "Route to APB Bus", regardless of CPU Mode (Normal/Debug)
  assign is_apb_dmem_access = is_debug_area_dmem || is_uart_dmem;

  // Route debug area IMEM fetch to APB
  assign is_debug_rom_fetch = is_debug_area_imem;

  // Trigger APB state machine for ANY APB access
  assign is_apb_dm_write = (cpu_dmem_wvalid != 2'b00) && is_apb_dmem_access;
  assign is_apb_dm_read  = cpu_dmem_rready && is_apb_dmem_access;

  // CLINT Access
  assign is_clint_access = (dmem_addr >= CLINT_BASE) && (dmem_addr <= CLINT_END);
  assign is_clint_write = is_clint_access && (cpu_dmem_wvalid != 2'b00);
  assign is_clint_read = is_clint_access && cpu_dmem_rready;

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
          .paddr              (clint_paddr),
          .psel               (clint_psel),
          .penable            (clint_penable),
          .pwrite             (clint_pwrite),
          .pwdata             (clint_pwdata),
          .pstrb              (4'hF),
          .prdata             (clint_prdata),
          .pready             (clint_pready),
          .pslverr            (clint_pslverr),
          .m_timer_interrupt_o(m_timer_interrupt)
        );

  always_comb
  begin
    clint_psel    = is_clint_access && (is_clint_write || is_clint_read);
    clint_penable = clint_psel;
    clint_pwrite  = is_clint_write;
    clint_paddr   = (dmem_addr - CLINT_BASE);
    clint_pwdata  = dmem_wdata;
  end

  // =================================================================
  //  APB Arbiter for Debug Module Access
  // =================================================================
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
  //  UART APB Slave
  // =================================================================
  logic        uart_psel;
  logic [31:0] uart_prdata;
  logic        uart_pready;
  logic        uart_pslverr;

  assign uart_psel = arbiter_out_if.psel &&
         ((arbiter_out_if.paddr & UART_ADDR_MASK[ADDR_WIDTH-1:0]) ==
          UART_BASE_ADDR[ADDR_WIDTH-1:0]);

  apb_uart_sv #(
                .APB_ADDR_WIDTH(ADDR_WIDTH)
              ) uart_inst (
                .CLK    (clk),
                .RSTN   (reset_n),
                .PADDR  (arbiter_out_if.paddr),
                .PWDATA (arbiter_out_if.pwdata),
                .PWRITE (arbiter_out_if.pwrite),
                .PSEL   (uart_psel),
                .PENABLE(arbiter_out_if.penable),
                .PRDATA (uart_prdata),
                .PREADY (uart_pready),
                .PSLVERR(uart_pslverr),
                .rx_i   (uart_rx_i),
                .tx_o   (uart_tx_o),
                .event_o(uart_event_o)
              );

  assign i_cpu_apb_paddr        = arbiter_out_if.paddr;
  assign i_cpu_apb_psel         = arbiter_out_if.psel && !uart_psel;
  assign i_cpu_apb_penable      = arbiter_out_if.penable;
  assign i_cpu_apb_pwrite       = arbiter_out_if.pwrite;
  assign i_cpu_apb_pwdata       = arbiter_out_if.pwdata;

  assign arbiter_out_if.pready  = uart_psel ? uart_pready : o_cpu_apb_pready;
  assign arbiter_out_if.prdata  = uart_psel ? uart_prdata : o_cpu_apb_prdata;
  assign arbiter_out_if.pslverr = uart_psel ? uart_pslverr : o_cpu_apb_pslverr;

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
  //  DMEM APB Master Logic (Debug Module & UART Access)
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
    else
    begin
      dmem_apb_state <= dmem_apb_next_state;
      if (dmem_apb_state == DMEM_IDLE && (is_apb_dm_write || is_apb_dm_read))
      begin
        dmem_apb_addr_reg      <= dmem_addr;
        dmem_apb_wdata_reg     <= dmem_wdata;
        dmem_apb_write_reg     <= is_apb_dm_write;
        dmem_transaction_addr  <= dmem_addr[ADDR_WIDTH-1:0];
        dmem_transaction_wdata <= dmem_wdata;
        dmem_transaction_write <= is_apb_dm_write;
      end
    end
  end

  always_comb
  begin
    dmem_apb_next_state = dmem_apb_state;
    case (dmem_apb_state)
      DMEM_IDLE:
        if (is_apb_dm_write || is_apb_dm_read)
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
          if (is_apb_dm_write || is_apb_dm_read)
          begin
            dmem_apb_if.psel   <= 1'b1;
            dmem_apb_if.paddr  <= dmem_addr[ADDR_WIDTH-1:0];
            dmem_apb_if.pwrite <= is_apb_dm_write;
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
  // Renamed signals to clarify they represent BUS targets, not CPU modes
  logic imem_rvalid_bram;
  logic imem_rvalid_apb;
  
  logic dmem_rvalid_bram; // Response from BRAM
  logic dmem_rvalid_apb;  // Response from APB (UART/Debug)
  logic dmem_rvalid_clint;// Response from CLINT
  
  logic dmem_wready_bram;
  logic dmem_wready_apb;
  logic dmem_wready_clint;

  // IMEM valid signals
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
      imem_rvalid_bram <= 1'b0;
    else
      // dmem_access_req is BRAM contention. APB access does NOT contend for BRAM.
      imem_rvalid_bram <= cpu_imem_rready && !is_debug_rom_fetch && !dmem_access_req;
  end

  assign imem_rvalid_apb = (imem_apb_state == IMEM_ACCESS && imem_apb_if.pready);
  assign cpu_imem_rvalid   = imem_rvalid_bram || imem_rvalid_apb;

  // DMEM read valid signals
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
      dmem_rvalid_bram <= 1'b0;
    else
      // is_apb_dmem_access includes UART and Debug
      dmem_rvalid_bram <= cpu_dmem_rready && !is_apb_dmem_access && !is_clint_access;
  end

  // APB Read Valid: Valid when APB state machine completes a READ transaction
  assign dmem_rvalid_apb = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && !dmem_transaction_write);
  assign dmem_rvalid_clint = is_clint_read && clint_pready;
  assign cpu_dmem_rvalid = dmem_rvalid_bram || dmem_rvalid_apb || dmem_rvalid_clint;

  // DMEM write ready signals
  // BRAM is always ready if we are NOT accessing APB or CLINT
  assign dmem_wready_bram = !is_apb_dm_write && !is_clint_access;
  
  // APB is ready when the state machine completes the WRITE transaction
  assign dmem_wready_apb = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && dmem_transaction_write);
  assign dmem_wready_clint = is_clint_write && clint_pready;
  
  assign cpu_dmem_wready = dmem_wready_bram || dmem_wready_apb || dmem_wready_clint;

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
  //  Unified Gowin BRAM Instantiation
  // =================================================================
  logic [31:0] imem_phys_addr;
  logic [31:0] dmem_phys_addr;
  logic        imem_in_program_area;
  logic        dmem_in_program_area;
  
  // [FIX] Define Program Area with Fixed Boundaries (RAM_BASE_ADDR - RAM_END_ADDR)
  assign imem_in_program_area = (imem_addr >= RAM_BASE_ADDR) && (imem_addr <= RAM_END_ADDR) && !is_debug_rom_fetch;
  
  // [FIX] Ensure UART and Debug areas are excluded from BRAM check, AND respect strict fixed upper bound
  assign dmem_in_program_area = (dmem_addr >= RAM_BASE_ADDR) && (dmem_addr <= RAM_END_ADDR) && !is_apb_dmem_access && !is_clint_access;
  
  // Physical Address Translation (Fixed Base)
  assign imem_phys_addr = imem_in_program_area ? (imem_addr - RAM_BASE_ADDR) : imem_addr;
  assign dmem_phys_addr = dmem_in_program_area ? (dmem_addr - RAM_BASE_ADDR) : dmem_addr;
  
  assign imem_bram_addr = imem_phys_addr[13:2];
  assign dmem_bram_addr = dmem_phys_addr[13:2];
  
  // Update write enable logic to respect expanded APB area
  assign dmem_bram_we   = (cpu_dmem_wvalid != 2'b00) && !is_apb_dm_write && !is_clint_access && cpu_dmem_wready;

  logic imem_access_req;
  logic dmem_access_req;
  logic dmem_bram_rd_en;
  
  logic imem_valid_bram_access;
  logic dmem_valid_bram_access;
  logic imem_valid_access;
  logic dmem_valid_access;
  
  assign imem_valid_access = imem_in_program_area || is_debug_area_imem;
  assign dmem_valid_access = dmem_in_program_area || is_apb_dmem_access || is_clint_access;
  
  assign imem_valid_bram_access = imem_in_program_area;
  assign dmem_valid_bram_access = dmem_in_program_area;
  
  assign imem_access_req = cpu_imem_rready && !is_debug_rom_fetch && imem_valid_bram_access;
  
  // Expanded exclusion for APB
  assign dmem_bram_rd_en = cpu_dmem_rready && !is_apb_dmem_access && !is_clint_access && dmem_valid_bram_access;
  assign dmem_access_req = dmem_bram_rd_en || (dmem_bram_we && dmem_valid_bram_access);

  assign unified_bram_we      = dmem_bram_we;
  assign unified_bram_rd_en   = dmem_access_req || imem_access_req;
  assign unified_bram_addr    = dmem_access_req ? dmem_bram_addr : imem_bram_addr;
  assign unified_bram_wr_data = dmem_wdata;

  // Track which port accessed the memory
  logic imem_was_last_access;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      imem_was_last_access <= 1'b0;
    else if (unified_bram_rd_en)
      imem_was_last_access <= imem_access_req && !dmem_access_req;
  end

  unified_gowin_bram #(
                       .DEPTH     (UNIFIED_MEM_DEPTH),
                       .ADDR_WIDTH(12),
                       .INIT_FILE (IMEM_INIT_FILE != "" ? IMEM_INIT_FILE : DMEM_INIT_FILE)
                     ) unified_bram_inst (
                       .clk    (clk),
                       .reset_n(reset_n),
                       .wr_en  (unified_bram_we),
                       .rd_en  (unified_bram_rd_en),
                       .addr   (unified_bram_addr),
                       .wr_data(unified_bram_wr_data),
                       .rd_data(unified_bram_dout)
                     );

  assign imem_bram_dout = unified_bram_dout;
  assign dmem_bram_dout = unified_bram_dout;

  // Return data mux logic
  assign imem_rdata = is_debug_rom_fetch ? imem_apb_data : 
                      (imem_valid_access ? imem_bram_dout : 32'h00000000);
  
  // dmem_rdata MUX: Route APB data if it was an APB access (regardless of CPU Mode)
  assign dmem_rdata = is_clint_access ? clint_prdata :
                      (is_apb_dmem_access ? dmem_apb_data : 
                       (dmem_valid_access ? dmem_bram_dout : 32'h00000000));

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (debug_mode && (cpu_dmem_wvalid != 2'b00)) begin
      $display("[DMEM_WRITE] Time=%t addr=0x%08h wdata=0x%08h", 
               $time, dmem_addr, dmem_wdata);
      $display("  phys_addr=0x%08h bram_addr=0x%03h in_program_area=%b", 
               dmem_phys_addr, dmem_bram_addr, dmem_in_program_area);
      $display("  is_apb=%b is_clint=%b is_uart=%b", is_apb_dmem_access, is_clint_access, is_uart_dmem);
    end
    if (cpu_dmem_rready) begin
      $display("[DMEM_READ] Time=%t addr=0x%08h phys=0x%08h bram_addr=0x%03h", 
               $time, dmem_addr, dmem_phys_addr, dmem_bram_addr);
      $display("  debug_mode=%b in_program_area=%b is_apb=%b is_clint=%b", 
               debug_mode, dmem_in_program_area, is_apb_dmem_access, is_clint_access);
    end
  end
`endif

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

  logic cpu_reset_n;
  assign cpu_reset_n = reset_n & ~i_resetreq;

  core #(
         .START_ADDR(START_ADDR),
         .HART_ID   (HART_ID)
       ) cpu (
         .clk    (clk),
         .reset_n(cpu_reset_n),
         .dmem_wready(cpu_dmem_wready),
         .dmem_wvalid(cpu_dmem_wvalid),
         .dmem_wdata (dmem_wdata),
         .dmem_addr  (dmem_addr),
         .dmem_rvalid(cpu_dmem_rvalid),
         .dmem_rready(cpu_dmem_rready),
         .dmem_rdata (dmem_rdata),
         .imem_rready(cpu_imem_rready),
         .imem_rvalid(cpu_imem_rvalid),
         .imem_rdata (imem_rdata),
         .imem_addr  (imem_addr),
         .exit(exit),
         .m_external_interrupt(1'b0),
         .m_timer_interrupt   (m_timer_interrupt),
         .m_software_interrupt(1'b0),
         .i_haltreq   (i_haltreq),
         .debug_mode_o(debug_mode),
         .i_external_trigger(i_external_trigger),
         .o_external_trigger(o_external_trigger),
         .gp                (gp)
       );

  assign debug_mode_o  = debug_mode;
  assign o_hartreset   = i_resetreq;
  assign o_nonexistent = 1'b0;
  assign o_unavailable = 1'b0;

endmodule

// =================================================================
//  Gowin BRAM Wrapper Module (Unified)
// =================================================================

/*
 * Unified Gowin BRAM - True Dual Port
 * Supports both read-only (IMEM) and read/write (DMEM) configurations
 * For IMEM: Set wr_en = 0
 * For DMEM: Set wr_en based on write conditions
 */
module unified_gowin_bram #(
    parameter        DEPTH      = 4096,
    parameter        ADDR_WIDTH = 12,
    parameter string INIT_FILE  = ""  // Optional initialization file
  ) (
    input  logic                  clk,
    input  logic                  reset_n,
    // Main data access
    input  logic                  wr_en,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [          31:0] wr_data,
    output logic [          31:0] rd_data /*synthesis syn_keep=1*/
  );

  // Inferred BRAM with proper attributes for Gowin
  logic [31:0] mem         [DEPTH-1:0] /*synthesis syn_ramstyle="block_ram"*/;
  logic [31:0] rd_data_reg /*synthesis syn_keep=1*/;

  // Initialize memory from file or firmware.hex
  // File should contain 32-bit words in hex format (one per line)
  // Use @address directive for non-contiguous sections
  initial
  begin
 
    `ifndef SYNTHESIS
            if (INIT_FILE != "")
            begin
              $display("[BRAM] Attempting to load %s...", INIT_FILE);
              $readmemh(INIT_FILE, mem);
              $display("[BRAM] Memory load complete from %s. First 4 words:", INIT_FILE);
            end
            else
            begin
              $display("[BRAM] Attempting to load firmware.hex...");
              $readmemh("firmware.hex", mem);
              $display("[BRAM] Memory load complete. First 4 words:");
            end
            $display("[BRAM]   mem[0] = 0x%08h", mem[0]);
    $display("[BRAM]   mem[1] = 0x%08h", mem[1]);
    $display("[BRAM]   mem[2] = 0x%08h", mem[2]);
    $display("[BRAM]   mem[3] = 0x%08h", mem[3]);
`endif
  end

  // Write-first behavior: write and read in same cycle
  // When wr_en and rd_en are both asserted, read returns the written data
  always_ff @(posedge clk)
  begin
    if (wr_en)
    begin
      mem[addr] <= wr_data;
      if (rd_en)
        rd_data_reg <= wr_data;  // Write-first: return written data
    end
    else if (rd_en)
    begin
      rd_data_reg <= mem[addr];  // Normal read
    end
  end

  assign rd_data = rd_data_reg;

  // Synthesis attributes for Gowin BRAM inference
  // synthesis syn_ramstyle = "block_ram"

endmodule
