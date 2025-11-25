`timescale 1ns / 1ps
`include "dm_reg_addr.vh"

module top_with_ram_sim_gw #(
    parameter int        START_ADDR      = 32'h00000000,
    parameter int        MEM_SIZE        = 1024 * 1024,   // 1MB
    parameter int        ADDR_WIDTH      = 13,
    parameter int        DATA_WIDTH      = 32,
    parameter int        HART_ID         = 0,              // Hart ID for debug output
    parameter bit [31:0] TOHOST_ADDR     = 32'h80001000,   // tohost address for tests
    parameter bit [31:0] UART_BASE_ADDR  = 32'h00000100,   // UART base address in APB space
    parameter bit [31:0] UART_ADDR_MASK  = 32'h00000FF0,   // UART address mask (16-byte region)
    parameter string     IMEM_INIT_FILE  = ""            // Instruction memory initialization file
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
    output logic uart_event_o
  );

  // =================================================================
  //  Internal Memory - Gowin BRAM Implementation
  // =================================================================
  localparam IMEM_DEPTH = 4000;  // 16KB / 4 bytes
  localparam DMEM_DEPTH = 4000;  // 16KB / 4 bytes

  // IMEM signals for Gowin BRAM
  logic [31:0] imem_bram_dout;
  logic [11:0] imem_bram_addr;  // 12-bit for 4K words

  // DMEM signals for Gowin BRAM
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
  
  // UART signals - internal APB interface (New, for direct access)
  logic [ADDR_WIDTH-1:0] uart_paddr;
  logic                  uart_psel;
  logic                  uart_penable;
  logic                  uart_pwrite;
  logic [DATA_WIDTH-1:0] uart_pwdata;
  logic [DATA_WIDTH-1:0] uart_prdata;
  logic                  uart_pready;
  logic                  uart_pslverr;


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

  // New: UART Access detection
  logic        is_uart_access;
  logic        is_uart_write;
  logic        is_uart_read;

  // =================================================================
  //  Debug, CLINT, and UART Access Detection
  // =================================================================
  assign is_debug_rom_fetch = debug_mode &&
         (imem_addr >= DEBUG_AREA_START) &&
         (imem_addr <= DEBUG_AREA_END);

  assign is_debug_data_access = debug_mode &&
         (dmem_addr >= DEBUG_AREA_START) &&
         (dmem_addr <= DEBUG_AREA_END);

  assign is_dm_write = debug_mode && (cpu_dmem_wvalid != 2'b00) && is_debug_data_access;
  assign is_dm_read = debug_mode && cpu_dmem_rready && is_debug_data_access;

  assign is_clint_access = (dmem_addr >= CLINT_BASE) && (dmem_addr <= CLINT_END);
  assign is_clint_write = is_clint_access && (cpu_dmem_wvalid != 2'b00);
  assign is_clint_read = is_clint_access && cpu_dmem_rready;
  
  // New: UART detection - accessible in normal mode via dmem
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
  //  UART APB Slave Instantiation (New Direct Access Logic)
  // =================================================================
  // UART APB signals - combinational for simple memory-mapped access
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
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
      imem_rvalid_normal <= 1'b0;
    else
      imem_rvalid_normal <= cpu_imem_rready && !is_debug_rom_fetch;
  end

  assign imem_rvalid_debug = (imem_apb_state == IMEM_ACCESS && imem_apb_if.pready);
  assign cpu_imem_rvalid   = imem_rvalid_normal || imem_rvalid_debug;

  // DMEM read valid signals
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
      dmem_rvalid_normal <= 1'b0;
    else
      // dmem_rvalid_normal is valid if it's not a peripheral or debug access
      dmem_rvalid_normal <= cpu_dmem_rready && !is_debug_data_access && !is_clint_access && !is_uart_access;
  end

  assign dmem_rvalid_debug = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && !dmem_transaction_write);
  assign dmem_rvalid_clint = is_clint_read && clint_pready;
  assign dmem_rvalid_uart  = is_uart_read && uart_pready; // New
  
  assign cpu_dmem_rvalid = dmem_rvalid_normal || dmem_rvalid_debug || dmem_rvalid_clint || dmem_rvalid_uart;

  // DMEM write ready signals
  // dmem_wready_normal is ready if it's not a peripheral or debug module register access
  // Note: We allow writes in debug mode to normal memory (for progbuf execution)
  assign dmem_wready_normal = !is_debug_data_access && !is_clint_access && !is_uart_access; 
  
  assign dmem_wready_debug = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && dmem_transaction_write);
  assign dmem_wready_clint = is_clint_write && clint_pready;
  assign dmem_wready_uart  = is_uart_write && uart_pready; // New
  
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
  //  Gowin BRAM Instantiation for IMEM
  // =================================================================
  assign imem_bram_addr = imem_addr[13:2];  // Word address

  // imem_gowin_bram #(
  //                   .DEPTH     (IMEM_DEPTH),
  //                   .ADDR_WIDTH(12)
  //                 ) imem_bram_inst (
  //                   .clk    (clk),
  //                   .reset_n(reset_n),
  //                   .wr_en  (1'b0),
  //                   .wr_addr(12'b0),
  //                   .wr_data(32'b0),
  //                   .rd_en  (cpu_imem_rready && !is_debug_rom_fetch),
  //                   .rd_addr(imem_bram_addr),
  //                   .rd_data(imem_bram_dout)
  //                 );

  assign imem_rdata = is_debug_rom_fetch ? imem_apb_data : imem_bram_dout;

  // =================================================================
  //  Gowin BRAM Instantiation for DMEM
  // =================================================================
  assign dmem_bram_addr = dmem_addr[13:2];  // Word address
  // DMEM BRAM write enable logic
  // Write is enabled when:
  // 1. CPU issues a valid write (cpu_dmem_wvalid != 2'b00)
  // 2. Target is main memory (not CLINT or UART peripherals)
  // 3. Not accessing debug module registers (is_debug_data_access)
  // 4. Write ready is asserted (handshake complete)
  // Note: We allow writes in debug mode to normal memory (for progbuf execution)
  assign dmem_bram_we   = (cpu_dmem_wvalid != 2'b00) && !is_debug_data_access && !is_clint_access && !is_uart_access && dmem_wready_normal;

  // dmem_gowin_bram #(
  //                   .DEPTH     (DMEM_DEPTH),
  //                   .ADDR_WIDTH(12)
  //                 ) dmem_bram_inst (
  //                   .clk      (clk),
  //                   .reset_n  (reset_n),
  //                   .wr_en    (dmem_bram_we),
  //                   // DMEM BRAM read enable logic updated to exclude UART access
  //                   .rd_en    (cpu_dmem_rready && !is_debug_data_access && !is_clint_access && !is_uart_access), 
  //                   .addr     (dmem_bram_addr),
  //                   .wr_data  (dmem_wdata),
  //                   .rd_data  (dmem_bram_dout),
  //                   .init_wen (1'b0),
  //                   .init_addr(12'b0),
  //                   .init_data(32'b0)
  //                 );


  // --- 追加: 統合メモリインスタンス ---
  unified_gowin_bram #(
    .DEPTH     (IMEM_DEPTH), // DMEM_DEPTHと同じである前提
    .ADDR_WIDTH(12)
  ) main_ram_inst (
    .clk      (clk),
    .reset_n  (reset_n),
    
    // IMEM Interface (Port A)
    .imem_rd_en   (cpu_imem_rready && !is_debug_rom_fetch),
    .imem_addr    (imem_bram_addr),
    .imem_rd_data (imem_bram_dout),
    
    // DMEM Interface (Port B)
    .dmem_wr_en   (dmem_bram_we),
    .dmem_rd_en   (cpu_dmem_rready && !is_debug_data_access && !is_clint_access && !is_uart_access),
    .dmem_addr    (dmem_bram_addr),
    .dmem_wr_data (dmem_wdata),
    .dmem_rd_data (dmem_bram_dout)
  );
  // DMEM Read Data Muxing - Updated to include UART
  assign dmem_rdata = is_clint_access ? clint_prdata :
         (is_uart_access ? uart_prdata :
         (is_debug_data_access ? dmem_apb_data : dmem_bram_dout));

  // Monitor tohost for RISC-V test support
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

  // Debug: Monitor CPU reset signal for Hart 1
  // Register incoming reset request to break long combinational paths
  // and reduce fanout on the i_resetreq net.
  logic i_resetreq_sync;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      i_resetreq_sync <= 1'b0;
    end else begin
      i_resetreq_sync <= i_resetreq;
    end
  end

  logic cpu_reset_n;
  assign cpu_reset_n = reset_n & ~i_resetreq_sync;


  // =================================================================
  //  Core Instantiation
  // =================================================================
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

  // =================================================================
  //  Output Assignments
  // =================================================================
  assign debug_mode_o  = debug_mode;


  // Debug module interface
  assign o_hartreset   = i_resetreq_sync;
  assign o_nonexistent = 1'b0;  // Hart exists
  assign o_unavailable = 1'b0;  // Hart is always available

endmodule
/*
 * Unified Gowin BRAM - True Dual Port
 * Port A: IMEM (Instruction Fetch - Read Only)
 * Port B: DMEM (Data Access - Read/Write)
 */
module unified_gowin_bram #(
    parameter DEPTH      = 4096,
    parameter ADDR_WIDTH = 12
  ) (
    input  logic                     clk,
    input  logic                     reset_n,
    
    // Port A: IMEM Access
    input  logic                     imem_rd_en,
    input  logic [ADDR_WIDTH-1:0]    imem_addr,
    output logic [31:0]              imem_rd_data,
    
    // Port B: DMEM Access
    input  logic                     dmem_wr_en,
    input  logic                     dmem_rd_en,
    input  logic [ADDR_WIDTH-1:0]    dmem_addr,
    input  logic [31:0]              dmem_wr_data,
    output logic [31:0]              dmem_rd_data
  );

  logic active_reset;
  assign active_reset = ~reset_n;

  // Gowin_DPB IPコア (True Dual Port Mode)
  Gowin_DPB u_bram (
    // Port A: IMEM (Read Only)
    .clka   (clk),
    .reseta (active_reset),
    .cea    (imem_rd_en),
    .ocea   (imem_rd_en),
    .wrea   (1'b0),          // Write Disabled
    .ada    (imem_addr),
    .dina   (32'b0),
    .douta  (imem_rd_data),

    // Port B: DMEM (Read/Write)
    .clkb   (clk),
    .resetb (active_reset),
    .ceb    (dmem_wr_en || dmem_rd_en),
    .oceb   (dmem_rd_en),
    .wreb   (dmem_wr_en),
    .adb    (dmem_addr),
    .dinb   (dmem_wr_data),
    .doutb  (dmem_rd_data)
  );

endmodule