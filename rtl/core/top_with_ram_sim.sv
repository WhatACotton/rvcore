// Top-level module for simulation that maintains rvcore_dm_connector interface
// This wraps the core with simple memory models for simulation testing

`timescale 1ns / 1ps

module top_with_ram_sim #(
    parameter int START_ADDR = 32'h00000000,
    parameter int MEM_SIZE   = 1024 * 1024,   // 1MB
    parameter int ADDR_WIDTH = 13,
    parameter int DATA_WIDTH = 32,
    parameter int HART_ID    = 0,             // Hart ID for debug output
    parameter logic [31:0] TOHOST_ADDR = 32'h80001000  // tohost address for tests
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

    // Memory initialization interface
    input logic [31:0] init_addr,
    input logic [31:0] init_data,
    input logic        init_wen,

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
    input  logic                  o_cpu_apb_pslverr
  );

  // =================================================================
  //  Internal Memory - Gowin BRAM Implementation
  // =================================================================
  // Use Gowin Block RAM primitives for synthesis
  // Organized as dual-port RAM: Port A for init/write, Port B for read

  // Memory initialization tracking
  logic init_in_progress;
  logic init_wen_prev;

  // Detect when initialization is ongoing
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      init_wen_prev    <= 1'b0;
      init_in_progress <= 1'b0;
    end
    else
    begin
      init_wen_prev <= init_wen;
      // Start of initialization (rising edge of init_wen)
      if (init_wen && !init_wen_prev)
      begin
        init_in_progress <= 1'b1;
      end
      // End of initialization (falling edge of init_wen)
      else if (!init_wen && init_wen_prev)
      begin
        init_in_progress <= 1'b0;
      end
    end
  end

  // Gowin BRAM instantiation parameters
  localparam IMEM_DEPTH = 4096;  // 16KB / 4 bytes
  localparam DMEM_DEPTH = 4096;  // 16KB / 4 bytes

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

  // Core handshake signals
  logic cpu_imem_rready;
  logic cpu_dmem_rready;
  logic cpu_imem_rvalid;
  logic cpu_dmem_rvalid;
  logic cpu_dmem_wready;
  logic [1:0] cpu_dmem_wvalid;

  // Debug and CLINT access detection
  logic is_debug_rom_fetch;
  logic is_dm_write;
  logic is_dm_read;
  logic is_debug_data_access;
  logic is_clint_access;
  logic is_clint_write;
  logic is_clint_read;

  // =================================================================
  //  Debug and CLINT Access Detection
  // =================================================================
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
  assign is_clint_read  = is_clint_access && cpu_dmem_rready;

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
                .clk                     (clk),
                .rst_n                   (reset_n),
                .master0_if              (imem_apb_if.Slave),
                .master1_if              (dmem_apb_if.Slave),
                .slave_if                (arbiter_out_if.Master)
              );

  // Connect arbiter output to external APB interface
  assign i_cpu_apb_paddr        = arbiter_out_if.paddr;
  assign i_cpu_apb_psel         = arbiter_out_if.psel;
  assign i_cpu_apb_penable      = arbiter_out_if.penable;
  assign i_cpu_apb_pwrite       = arbiter_out_if.pwrite;
  assign i_cpu_apb_pwdata       = arbiter_out_if.pwdata;
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

  logic [31:0] imem_apb_addr_reg;
  logic [ADDR_WIDTH-1:0] imem_transaction_addr;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      imem_apb_state    <= IMEM_IDLE;
      imem_apb_addr_reg <= '0;
      imem_transaction_addr <= '0;
    end
    else
    begin
      imem_apb_state <= imem_apb_next_state;
      if (imem_apb_state == IMEM_IDLE && cpu_imem_rready && is_debug_rom_fetch)
      begin
        imem_apb_addr_reg <= imem_addr;
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

  logic [31:0] dmem_apb_addr_reg;
  logic [31:0] dmem_apb_wdata_reg;
  logic        dmem_apb_write_reg;
  logic [ADDR_WIDTH-1:0] dmem_transaction_addr;
  logic [31:0] dmem_transaction_wdata;
  logic        dmem_transaction_write;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      dmem_apb_state     <= DMEM_IDLE;
      dmem_apb_addr_reg  <= '0;
      dmem_apb_wdata_reg <= '0;
      dmem_apb_write_reg <= 1'b0;
      dmem_transaction_addr  <= '0;
      dmem_transaction_wdata <= '0;
      dmem_transaction_write <= 1'b0;
    end
    else
    begin
      dmem_apb_state <= dmem_apb_next_state;
      if (dmem_apb_state == DMEM_IDLE && (is_dm_write || is_dm_read))
      begin
        dmem_apb_addr_reg  <= dmem_addr;
        dmem_apb_wdata_reg <= dmem_wdata;
        dmem_apb_write_reg <= is_dm_write;
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
  logic dmem_wready_normal;
  logic dmem_wready_debug;
  logic dmem_wready_clint;

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
      dmem_rvalid_normal <= cpu_dmem_rready && !is_debug_data_access && !is_clint_access;
  end

  assign dmem_rvalid_debug = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && !dmem_transaction_write);
  assign dmem_rvalid_clint = is_clint_read && clint_pready;
  assign cpu_dmem_rvalid   = dmem_rvalid_normal || dmem_rvalid_debug || dmem_rvalid_clint;

  // DMEM write ready signals
  assign dmem_wready_normal = !is_dm_write && !is_clint_access;
  assign dmem_wready_debug = (dmem_apb_state == DMEM_ACCESS && dmem_apb_if.pready && dmem_transaction_write);
  assign dmem_wready_clint = is_clint_write && clint_pready;
  assign cpu_dmem_wready   = dmem_wready_normal || dmem_wready_debug || dmem_wready_clint;

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

  assign imem_apb_data = (imem_apb_state == IMEM_ACCESS) ? imem_apb_if.prdata : imem_apb_resp_reg;
  assign dmem_apb_data = (dmem_apb_state == DMEM_ACCESS) ? dmem_apb_if.prdata : dmem_apb_resp_reg;

  // =================================================================
  //  Gowin BRAM Instantiation for IMEM
  // =================================================================
  assign imem_bram_addr = imem_addr[13:2];  // Word address

  imem_gowin_bram #(
                    .DEPTH(IMEM_DEPTH),
                    .ADDR_WIDTH(12)
                  ) imem_bram_inst (
                    .clk        (clk),
                    .reset_n    (reset_n),
                    .wr_en      (init_wen && (init_addr[15:14] == 2'b00)),  // Map to lower 16KB
                    .wr_addr    (init_addr[13:2]),
                    .wr_data    (init_data),
                    .rd_en      (cpu_imem_rready && !is_debug_rom_fetch),
                    .rd_addr    (imem_bram_addr),
                    .rd_data    (imem_bram_dout)
                  );

  assign imem_rdata = is_debug_rom_fetch ? imem_apb_data : imem_bram_dout;

  // =================================================================
  //  Gowin BRAM Instantiation for DMEM
  // =================================================================
  assign dmem_bram_addr = dmem_addr[13:2];  // Word address
  assign dmem_bram_we   = (cpu_dmem_wvalid != 2'b00) && !is_dm_write && !is_clint_access && cpu_dmem_wready;

  dmem_gowin_bram #(
                    .DEPTH(DMEM_DEPTH),
                    .ADDR_WIDTH(12)
                  ) dmem_bram_inst (
                    .clk        (clk),
                    .reset_n    (reset_n),
                    .wr_en      (dmem_bram_we),
                    .rd_en      (cpu_dmem_rready && !is_debug_data_access && !is_clint_access),
                    .addr       (dmem_bram_addr),
                    .wr_data    (dmem_wdata),
                    .rd_data    (dmem_bram_dout),
                    .init_wen   (init_wen && (init_addr[15:14] == 2'b00)),
                    .init_addr  (init_addr[13:2]),
                    .init_data  (init_data)
                  );

  assign dmem_rdata = is_clint_access ? clint_prdata :
         (is_debug_data_access ? dmem_apb_data : dmem_bram_dout);

  // Monitor tohost for RISC-V test support
  // TOHOST_ADDR is now a module parameter (see module declaration)

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

  // =================================================================
  //  Core Instantiation
  // =================================================================
  core #(
         .START_ADDR(START_ADDR),
         .HART_ID(HART_ID)
       ) cpu (
         .clk          (clk),
         .reset_n      (reset_n & ~i_resetreq & ~init_in_progress),

         // DMEM Write Interface
         .dmem_wready  (cpu_dmem_wready),
         .dmem_wvalid  (cpu_dmem_wvalid),
         .dmem_wdata   (dmem_wdata),
         .dmem_addr    (dmem_addr),

         // DMEM Read Interface
         .dmem_rvalid  (cpu_dmem_rvalid),
         .dmem_rready  (cpu_dmem_rready),
         .dmem_rdata   (dmem_rdata),

         // IMEM Read Interface
         .imem_rready  (cpu_imem_rready),
         .imem_rvalid  (cpu_imem_rvalid),
         .imem_rdata   (imem_rdata),
         .imem_addr    (imem_addr),

         .exit         (exit),

         // Interrupt inputs
         .m_external_interrupt (1'b0),
         .m_timer_interrupt    (m_timer_interrupt),
         .m_software_interrupt (1'b0),

         // Debug interface
         .i_haltreq      (i_haltreq),
         .debug_mode_o   (debug_mode),

         // External triggers
         .i_external_trigger (i_external_trigger),
         .o_external_trigger (o_external_trigger)
       );

  // =================================================================
  //  Output Assignments
  // =================================================================
  assign debug_mode_o = debug_mode;

  // RISC-V test support - expose gp register (x3)
  assign gp = cpu.register_file[3];

  // Debug module interface
  assign o_hartreset   = i_resetreq;
  assign o_nonexistent = 1'b0;  // Hart exists
  assign o_unavailable = init_in_progress;

endmodule


// =================================================================
//  Gowin BRAM Wrapper Modules
// =================================================================

/*
 * IMEM Gowin BRAM - Simple Dual Port
 * Port A: Write (for initialization)
 * Port B: Read (for instruction fetch)
 */
module imem_gowin_bram #(
    parameter DEPTH = 4096,
    parameter ADDR_WIDTH = 12
  ) (
    input  logic clk,
    input  logic reset_n,
    // Write port (Port A)
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [31:0]           wr_data,
    // Read port (Port B)
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [31:0]           rd_data
  );

  // Inferred BRAM with proper attributes for Gowin
  logic [31:0] mem [DEPTH-1:0];
  logic [31:0] rd_data_reg;

  // Initialize to NOPs
  initial
  begin
    for (int i = 0; i < DEPTH; i++)
    begin
      mem[i] = 32'h00000013;  // NOP
    end
  end

  // Write port
  always_ff @(posedge clk)
  begin
    if (wr_en)
    begin
      mem[wr_addr] <= wr_data;
    end
  end

  // Read port with pipeline register
  always_ff @(posedge clk)
  begin
    if (rd_en)
    begin
      rd_data_reg <= mem[rd_addr];
    end
  end

  assign rd_data = rd_data_reg;

  // Synthesis attributes for Gowin BRAM inference
  // synthesis syn_ramstyle = "block_ram"

endmodule


/*
 * DMEM Gowin BRAM - True Dual Port
 * Port A: Read/Write (for data access)
 * Port B: Write only (for initialization)
 */
module dmem_gowin_bram #(
    parameter DEPTH = 4096,
    parameter ADDR_WIDTH = 12
  ) (
    input  logic clk,
    input  logic reset_n,
    // Port A: Main data access
    input  logic                  wr_en,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [31:0]           wr_data,
    output logic [31:0]           rd_data,
    // Port B: Initialization
    input  logic                  init_wen,
    input  logic [ADDR_WIDTH-1:0] init_addr,
    input  logic [31:0]           init_data
  );

  // Inferred BRAM with proper attributes for Gowin
  logic [31:0] mem [DEPTH-1:0];
  logic [31:0] rd_data_reg;

  // Initialize to NOPs
  initial
  begin
    for (int i = 0; i < DEPTH; i++)
    begin
      mem[i] = 32'h00000013;  // NOP
    end
  end

  // Port A: Read/Write
  always_ff @(posedge clk)
  begin
    if (wr_en)
    begin
      mem[addr] <= wr_data;
    end
  end

  always_ff @(posedge clk)
  begin
    if (rd_en)
    begin
      rd_data_reg <= mem[addr];
    end
  end

  // Port B: Initialization write
  always_ff @(posedge clk)
  begin
    if (init_wen)
    begin
      mem[init_addr] <= init_data;
    end
  end

  assign rd_data = rd_data_reg;

  // Synthesis attributes for Gowin BRAM inference
  // synthesis syn_ramstyle = "block_ram"

endmodule
