`include "instructions_defines.svh"
`include "control_defines.svh"
`include "dm_reg_addr.vh"

module core #(
    parameter int START_ADDR = 32'h0000_0000,
    parameter int HART_ID    = 0               // Hart ID for mhartid CSR (0xF14)
  ) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        dmem_wready,
    output logic [ 1:0] dmem_wvalid,
    input  logic        dmem_rvalid,
    output logic        dmem_rready,
    output logic [31:0] dmem_wdata,
    input        [31:0] dmem_rdata,
    output logic [31:0] dmem_addr,
    output logic        imem_rready,
    input  logic        imem_rvalid,
    input        [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic        exit,
    // Interrupt inputs
    input  logic        m_external_interrupt,
    input  logic        m_timer_interrupt,
    input  logic        m_software_interrupt,
    // Debug Module interface
    input  logic        i_haltreq,             // Debug halt request from DM
    output logic        debug_mode_o,          // Debug mode status output
    // External trigger inputs (for Sdtrig extension - Type 7)
    // Spec allows up to 16 inputs, using 4 for simplicity
    input  logic [ 3:0] i_external_trigger,    // External trigger inputs [0:3]
    // External trigger outputs (for actions 8/9)
    // Action 8: chain 0 output, Action 9: chain 1 output
    output logic [ 1:0] o_external_trigger,    // [0]=action8/chain0, [1]=action9/chain1
    output logic        gp
  );

  // PC register
  logic [31:0] pc;
  // Current instruction
  logic [31:0] inst;
  // Saved PC for current instruction (to break timing path)
  logic [31:0] inst_pc;
  enum logic [2:0] {
         PROC,
         IMEM_READ,
         IMEM_DONE,
         DMEM_READ,
         DMEM_WRITE,
         DMEM_DONE
       }
       proc_state, next_proc_state;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      proc_state <= PROC;
      mem_inst       <= 32'd0;  // Initialize saved memory instruction
      mem_addr_saved <= 32'd0;
    end
    else
    begin
      proc_state <= next_proc_state;
      
      // Debug: Log PC changes when debug_mode changes
      if (i_haltreq && !debug_mode) begin
        $display("[RVCORE_PC] Time=%d HART=%0d: Next cycle will set debug_mode=1, pc=0x%08x, proc_state=%0d->%0d", 
                 $time, HART_ID, `DEBUG_ENTRY_POINT, proc_state, next_proc_state);
      end
      
      // Debug: Log state transitions after halt
      if (debug_mode && (proc_state != next_proc_state)) begin
        $display("[RVCORE_STATE] Time=%d HART=%0d: debug_mode=1 proc_state=%0d->%0d pc=0x%08x imem_rready=%b", 
                 $time, HART_ID, proc_state, next_proc_state, pc, (next_proc_state == IMEM_READ));
      end

      // Save instruction and address for any memory operation
      // (both loads and stores, including SB/SH that need RMW)
      if (proc_state == IMEM_DONE && (wb_sel == `WB_MEM || mem_wen != `MEN_X))
      begin
        mem_inst       <= inst;
        mem_addr_saved <= alu_out;
      end
    end
  end

  // Detect PC-changing events that require proc_state reset
  logic pc_jump_event;
  // Memory boundary check - auto-halt if PC goes out of valid RAM range
  // Valid RAM: 0x10000 - 0x13FFF (16KB)
  // Auto-halt prevents executing undefined memory when program is not loaded
  logic mem_boundary_violation;
  assign mem_boundary_violation = (pc >= 32'h00014000) && !debug_mode;
  
  // CRITICAL: haltreq must wait for instruction_retired to ensure halt at instruction boundary
  // This prevents halting in the middle of multi-cycle instructions (loads/stores)
  assign pc_jump_event = (i_haltreq && !debug_mode && instruction_retired) ||
                         (trigger_fire && !debug_mode) ||
                         (trigger_exception_req && !debug_mode && instruction_retired) ||
                         (`IS_DRET(inst) && debug_mode && instruction_retired) ||
                         (`IS_ECALL(inst) && !debug_mode && instruction_retired) ||
                         (`IS_EBREAK(inst) && !debug_mode && instruction_retired) ||  // Software breakpoint
                         (`IS_EBREAK(inst) && debug_mode && instruction_retired) ||   // EBREAK in debug mode
                         (`IS_MRET(inst) && !debug_mode && instruction_retired) ||
                         (dcsr_step && !debug_mode && instruction_retired) ||  // Single-step mode
                         (mem_boundary_violation && instruction_retired);

  always_comb
  begin
    next_proc_state = proc_state;

    // If PC jump event occurs (halt, trap, return), reset to PROC state
    if (pc_jump_event)
    begin
      next_proc_state = PROC;
    end
    // If exit flag is set, halt the core by staying in current state
    else if (exit_flag)
    begin
      next_proc_state = proc_state;  // Halt - no state transitions
    end
    else
    begin
      case (proc_state)
        PROC:
        begin
          next_proc_state = IMEM_READ;
        end
        IMEM_READ:
        begin
          if (imem_rvalid && imem_rready)
          begin
            next_proc_state = IMEM_DONE;
          end
        end
        IMEM_DONE:
        begin
          if (mem_wen != `MEN_X)
          begin
            // For SB/SH, need Read-Modify-Write: Read first
            if (`IS_SB(inst) || `IS_SH(inst))
            begin
              next_proc_state = DMEM_READ;
            end
            else
            begin
              // SW: Direct write
              next_proc_state = DMEM_WRITE;
            end
          end
          else if (mem_wen == `MEN_X && wb_sel == `WB_MEM)
          begin
            next_proc_state = DMEM_READ;
          end
          else
          begin
            next_proc_state = PROC;
          end
        end
        DMEM_WRITE:
        begin
          if (dmem_wready)
          begin
            // Write completed, always go to DMEM_DONE
            next_proc_state = DMEM_DONE;
          end
        end
        DMEM_READ:
        begin
          if (dmem_rvalid && dmem_rready)
          begin
            // After RMW read for SB/SH, go to write
            if (mem_wen != `MEN_X && (`IS_SB(mem_inst) || `IS_SH(mem_inst)))
            begin
              next_proc_state = DMEM_WRITE;
            end
            else
            begin
              next_proc_state = DMEM_DONE;
            end
          end
        end
        // Duplicate DMEM_READ case removed (handled above)
        DMEM_DONE:
        begin
          next_proc_state = PROC;
        end
        default:
        begin
          next_proc_state = PROC;
        end
      endcase
    end
  end
  assign imem_rready = (proc_state == IMEM_READ);

  // Signal to indicate instruction retirement for PC stalling
  logic instruction_retired;

  // Exit flag to halt the core when test completes
  logic exit_flag;

  always_comb
  begin
    instruction_retired = 1'b0;

    case (proc_state)
      IMEM_DONE:
      begin
        // ALU, CSR, or Branch instructions complete here
        if (mem_wen == `MEN_X && wb_sel != `WB_MEM)
        begin
          instruction_retired = 1'b1;
        end
      end
      DMEM_WRITE:
      begin
        // Store instruction completes when memory handshake is done
        if (dmem_wvalid && dmem_wready && wb_sel != `WB_MEM)
        begin
          instruction_retired = 1'b1;
        end
      end
      DMEM_DONE:
      begin
        // Load instruction completes here
        instruction_retired = 1'b1;
      end
      default:
        instruction_retired = 1'b0;
    endcase
  end

  // Register file and CSR
  logic [  31:0][31:0] register_file;

  // Individual CSR registers (no large CSR file array for better synthesis)
  // M-Mode CSR registers
  logic [  31:0]       mtvec;
  // Machine trap-handler base address
  logic [  31:0]       mcause;
  // Machine trap cause
  logic [  31:0]       mepc;
  // Machine exception program counter
  logic [  31:0]       mstatus;
  // Machine status register
  logic [  31:0]       mscratch;
  logic [  31:0]       misa;

  // mstatus bit fields
  logic                mstatus_mie;
  // bit 3: Machine Interrupt Enable
  logic                mstatus_mpie;
  // bit 7: Previous MIE (before trap)
  logic [   1:0]       mstatus_mpp;
  // bits 12:11: Previous privilege mode

  // Construct mstatus register from bit fields
  assign mstatus = {19'd0, mstatus_mpp, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0};

  // Debug registers
  logic [31:0] dcsr;  // Debug Control and Status Register
  logic [31:0] dpc;
  // Debug Pro  logic [31:0] dpc_prev;  // Previous DPC value for debugging
  logic        dpc_protected;  // Protect DPC from CSR writes when entering debug mode
  logic        debug_mode;
  // CPU is in debug mode

  // dcsr bit fields (simplified - key fields only)
  logic [ 2:0] dcsr_cause;
  // bits 8:6 - debug entry cause
  logic        dcsr_step;
  // bit 2 - single step mode
  logic [ 1:0] dcsr_prv;
  // bits 1:0 - privilege level before debug

  // Construct dcsr register
  // [31:28]=xdebugver(4), [27:16]=0, [15]=ebreakm, [14:12]=0,
  // [11]=stepie, [10]=stopcount, [9]=stoptime, [8:6]=cause,
  // [5:4]=0, [3]=mprven, [2]=step, [1:0]=prv
  assign dcsr = {
           4'h4, 12'h0, 1'b0, 3'h0, 1'b0, 1'b0, 1'b0, dcsr_cause, 2'h0, 1'b0, dcsr_step, dcsr_prv
         };

  // Output debug mode status
  assign debug_mode_o = debug_mode;

  // Debug scratch registers (individual registers instead of CSR file)
  logic [31:0] dscratch0;
  logic [31:0] dscratch1;

  // Hart ID - Use parameter directly as constant (not a register)
  // This ensures each hart instance has the correct, unchangeable ID

  // ==========================================================================
  // Trigger Module (Sdtrig - Separated for better synthesis)
  // ==========================================================================
  parameter int NUM_TRIGGERS = 4;  // 4 hardware triggers

  // Trigger CSR registers
  logic [             1:0]       tselect;
  logic [NUM_TRIGGERS-1:0][31:0] tdata1;
  logic [NUM_TRIGGERS-1:0][31:0] tdata2;
  logic [NUM_TRIGGERS-1:0][31:0] tdata3;
  logic [            31:0]       tinfo;
  logic [            31:0]       tcontrol;
  logic [            31:0]       mcontext;

  // Trigger outputs
  logic                          trigger_fire;
  logic                          trigger_exception_req;

  // Instruction counter for icount trigger (type 3)
  logic [NUM_TRIGGERS-1:0][31:0] icount_counter;
  logic [NUM_TRIGGERS-1:0]       icount_pending;

  // Memory access tracking for triggers
  logic                          mem_load_req;
  logic                          mem_store_req;
  logic [            31:0]       mem_access_addr;

  // Trap/interrupt tracking for triggers
  logic                          trap_taken;
  logic                          interrupt_trap;
  logic [            31:0]       trap_cause;

  // Misaligned access detection
  logic                          misaligned_load;
  logic                          misaligned_store;
  logic                          misaligned_exception;

  // tinfo: report which trigger types are supported
  assign tinfo = 32'b0000_0000_0000_0000_0000_0001_1111_1100;

  // Instantiate trigger module (combinational logic only, no added latency)
  trigger_module_comb #(
                        .NUM_TRIGGERS(NUM_TRIGGERS)
                      ) u_trigger_module (
                        .tselect(tselect),
                        .tdata1(tdata1),
                        .tdata2(tdata2),
                        .tdata3(tdata3),
                        .tcontrol(tcontrol),
                        .mcontext(mcontext),
                        .pc(inst_pc),
                        .mem_access_addr(mem_access_addr),
                        .mem_load_req(mem_load_req),
                        .mem_store_req(mem_store_req),
                        .instruction_retired(instruction_retired),
                        .trap_taken(trap_taken),
                        .interrupt_trap(interrupt_trap),
                        .debug_mode(debug_mode),
                        .i_external_trigger(i_external_trigger),
                        .icount_counter(icount_counter),
                        .trigger_fire(trigger_fire),
                        .trigger_exception_req(trigger_exception_req),
                        .o_external_trigger(o_external_trigger)
                      );

  // ============================================================================

  // Saved instruction and address for memory operations (used in writeback)
  logic [31:0] mem_inst;
  logic [31:0] mem_addr_saved;
  // Read-Modify-Write buffer for SB/SH operations
  logic [31:0] rmw_read_data;

  // Instruction fields
  logic [4:0] rs1_addr, rs2_addr, rd_addr;
  logic [31:0] rs1_data, rs2_data;
  logic [31:0] imm_i, imm_s, imm_b, imm_j, imm_u, imm_z;

  // Control signals
  logic [`EXE_FUN_LEN-1:0] exe_fun;
  logic [    `OP1_LEN-1:0] op1_sel;
  logic [    `OP2_LEN-1:0] op2_sel;
  logic [    `MEN_LEN-1:0] mem_wen;
  logic [    `REN_LEN-1:0] rf_wen;
  logic [ `WB_SEL_LEN-1:0] wb_sel;
  logic [    `CSR_LEN-1:0] csr_cmd;

  // ALU operands and result
  logic [31:0] op1_data, op2_data;
  logic [31:0] alu_out;
  logic        br_flg;

  // CSR signals
  logic [11:0] csr_addr;
  logic [31:0] csr_rdata, csr_wdata;

  // Writeback data
  logic [31:0] wb_data;

  // PC assignment
  assign imem_addr = pc;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      inst    <= 32'd0;
      inst_pc <= 32'd0;
    end
    else
    begin
      if (proc_state == IMEM_READ && imem_rready && imem_rvalid)
      begin
        inst    <= imem_rdata;
        inst_pc <= pc;  // Save PC along with instruction to break timing path
      end
    end
  end

  // Instruction decode
  assign rs1_addr = inst[19:15];
  assign rs2_addr = inst[24:20];
  assign rd_addr  = inst[11:7];

  // Register read
  assign rs1_data = (rs1_addr != 5'd0) ? register_file[rs1_addr] : 32'd0;
  assign rs2_data = (rs2_addr != 5'd0) ? register_file[rs2_addr] : 32'd0;

  // Immediate generation
  assign imm_i    = {{20{inst[31]}}, inst[31:20]};
  assign imm_s    = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  assign imm_b    = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  assign imm_j    = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
  assign imm_u    = {inst[31:12], 12'd0};
  assign imm_z    = {27'd0, inst[19:15]};

  // Instruction decoder
  always_comb
  begin
    exe_fun = `ALU_X;
    op1_sel = `OP1_RS1;
    op2_sel = `OP2_RS2;
    mem_wen = `MEN_X;
    rf_wen  = `REN_X;
    wb_sel  = `WB_X;
    csr_cmd = `CSR_X;
    if (`IS_LW(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_MEM;
      csr_cmd = `CSR_X;
    end
    else if (`IS_LH(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_MEM;
      csr_cmd = `CSR_X;
    end
    else if (`IS_LHU(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_MEM;
      csr_cmd = `CSR_X;
    end
    else if (`IS_LB(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_MEM;
      csr_cmd = `CSR_X;
    end
    else if (`IS_LBU(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_MEM;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SW(inst) || `IS_SH(inst) || `IS_SB(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMS;
      mem_wen = `MEN_S;  // Will be adjusted based on size
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_ADD(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_ADDI(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SUB(inst))
    begin
      exe_fun = `ALU_SUB;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_AND(inst))
    begin
      exe_fun = `ALU_AND;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_OR(inst))
    begin
      exe_fun = `ALU_OR;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_XOR(inst))
    begin
      exe_fun = `ALU_XOR;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_ANDI(inst))
    begin
      exe_fun = `ALU_AND;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_ORI(inst))
    begin
      exe_fun = `ALU_OR;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_XORI(inst))
    begin
      exe_fun = `ALU_XOR;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SLL(inst))
    begin
      exe_fun = `ALU_SLL;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SRL(inst))
    begin
      exe_fun = `ALU_SRL;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SRA(inst))
    begin
      exe_fun = `ALU_SRA;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SLLI(inst))
    begin
      exe_fun = `ALU_SLL;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SRLI(inst))
    begin
      exe_fun = `ALU_SRL;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SRAI(inst))
    begin
      exe_fun = `ALU_SRA;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SLT(inst))
    begin
      exe_fun = `ALU_SLT;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SLTU(inst))
    begin
      exe_fun = `ALU_SLTU;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SLTI(inst))
    begin
      exe_fun = `ALU_SLT;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_SLTIU(inst))
    begin
      exe_fun = `ALU_SLTU;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_BEQ(inst))
    begin
      exe_fun = `BR_BEQ;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_BNE(inst))
    begin
      exe_fun = `BR_BNE;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_BGE(inst))
    begin
      exe_fun = `BR_BGE;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_BGEU(inst))
    begin
      exe_fun = `BR_BGEU;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_BLT(inst))
    begin
      exe_fun = `BR_BLT;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_BLTU(inst))
    begin
      exe_fun = `BR_BLTU;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_RS2;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_JAL(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_PC;
      op2_sel = `OP2_IMJ;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_PC;
      csr_cmd = `CSR_X;
    end
    else if (`IS_JALR(inst))
    begin
      exe_fun = `ALU_JALR;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_IMI;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_PC;
      csr_cmd = `CSR_X;
    end
    else if (`IS_LUI(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_X;
      op2_sel = `OP2_IMU;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_AUIPC(inst))
    begin
      exe_fun = `ALU_ADD;
      op1_sel = `OP1_PC;
      op2_sel = `OP2_IMU;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_ALU;
      csr_cmd = `CSR_X;
    end
    else if (`IS_CSRRW(inst))
    begin
      exe_fun = `ALU_COPY1;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_CSR;
      csr_cmd = `CSR_W;
    end
    else if (`IS_CSRRWI(inst))
    begin
      exe_fun = `ALU_COPY1;
      op1_sel = `OP1_IMZ;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_CSR;
      csr_cmd = `CSR_W;
    end
    else if (`IS_CSRRS(inst))
    begin
      exe_fun = `ALU_COPY1;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_CSR;
      csr_cmd = `CSR_S;
    end
    else if (`IS_CSRRSI(inst))
    begin
      exe_fun = `ALU_COPY1;
      op1_sel = `OP1_IMZ;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_CSR;
      csr_cmd = `CSR_S;
    end
    else if (`IS_CSRRC(inst))
    begin
      exe_fun = `ALU_COPY1;
      op1_sel = `OP1_RS1;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_CSR;
      csr_cmd = `CSR_C;
    end
    else if (`IS_CSRRCI(inst))
    begin
      exe_fun = `ALU_COPY1;
      op1_sel = `OP1_IMZ;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_S;
      wb_sel  = `WB_CSR;
      csr_cmd = `CSR_C;
    end
    else if (`IS_ECALL(inst))
    begin
      exe_fun = `ALU_X;
      op1_sel = `OP1_X;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_E;
    end
    else if (`IS_EBREAK(inst))
    begin
      exe_fun = `ALU_X;
      op1_sel = `OP1_X;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_MRET(inst))
    begin
      exe_fun = `ALU_X;
      op1_sel = `OP1_X;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
    else if (`IS_FENCE_I(inst))
    begin
      // FENCE.I: Instruction fence - NOP for this implementation
      // (no instruction cache, Von Neumann architecture)
      exe_fun = `ALU_X;
      op1_sel = `OP1_X;
      op2_sel = `OP2_X;
      mem_wen = `MEN_X;
      rf_wen  = `REN_X;
      wb_sel  = `WB_X;
      csr_cmd = `CSR_X;
    end
  end

  // Operand selection
  always_comb
  begin
    case (op1_sel)
      `OP1_RS1:
        op1_data = rs1_data;
      `OP1_PC:
        op1_data = inst_pc;
      `OP1_IMZ:
        op1_data = imm_z;
      default:
        op1_data = 32'd0;
    endcase

    case (op2_sel)
      `OP2_RS2:
        op2_data = rs2_data;
      `OP2_IMI:
        op2_data = imm_i;
      `OP2_IMS:
        op2_data = imm_s;
      `OP2_IMJ:
        op2_data = imm_j;
      `OP2_IMU:
        op2_data = imm_u;
      default:
        op2_data = 32'd0;
    endcase
  end

  // ALU
  always_comb
  begin
    case (exe_fun)
      `ALU_ADD:
        alu_out = op1_data + op2_data;
      `ALU_SUB:
        alu_out = op1_data - op2_data;
      `ALU_AND:
        alu_out = op1_data & op2_data;
      `ALU_OR:
        alu_out = op1_data | op2_data;
      `ALU_XOR:
        alu_out = op1_data ^ op2_data;
      `ALU_SLL:
        alu_out = op1_data << op2_data[4:0];
      `ALU_SRL:
        alu_out = op1_data >> op2_data[4:0];
      `ALU_SRA:
        alu_out = $signed(op1_data) >>> op2_data[4:0];
      `ALU_SLT:
        alu_out = ($signed(op1_data) < $signed(op2_data)) ? 32'd1 : 32'd0;
      `ALU_SLTU:
        alu_out = (op1_data < op2_data) ? 32'd1 : 32'd0;
      `ALU_JALR:
        alu_out = (op1_data + op2_data) & ~32'd1;
      `ALU_COPY1:
        alu_out = op1_data;
      default:
        alu_out = 32'd0;
    endcase

    case (exe_fun)
      `BR_BEQ:
        br_flg = (op1_data == op2_data);
      `BR_BNE:
        br_flg = (op1_data != op2_data);
      `BR_BLT:
        br_flg = ($signed(op1_data) < $signed(op2_data));
      `BR_BGE:
        br_flg = ($signed(op1_data) >= $signed(op2_data));
      `BR_BLTU:
        br_flg = (op1_data < op2_data);
      `BR_BGEU:
        br_flg = (op1_data >= op2_data);
      default:
        br_flg = 1'b0;
    endcase
  end

  // Misaligned access detection (DISABLED - not supported)
  // Non-aligned memory access is not supported, no exception generated
  always_comb
  begin
    misaligned_load      = 1'b0;
    misaligned_store     = 1'b0;
    misaligned_exception = 1'b0;

    // Note: Misaligned access support is implementation-defined in RISC-V.
    // This core does not support misaligned access exception handling.
    // Tests requiring this feature (e.g., rv32ui-p-ma_data) are not supported.
  end

  // CSR address
  assign csr_addr = (csr_cmd == `CSR_E) ? `CSR_ADDR_MCAUSE : inst[31:20];

  // CSR read data (only debug CSRs accessible in debug mode)
  always_comb
  begin
    case (csr_addr)
      `CSR_ADDR_MTVEC:
        csr_rdata = mtvec;
      `CSR_ADDR_MISA:
        csr_rdata = misa;
      `CSR_ADDR_MCAUSE:
        csr_rdata = mcause;
      `CSR_ADDR_MEPC:
        csr_rdata = mepc;
      `CSR_ADDR_MSTATUS:
        csr_rdata = mstatus;
      `CSR_ADDR_MSCRATCH:
        csr_rdata = mscratch;
      `CSR_ADDR_DCSR:
        csr_rdata = debug_mode ? dcsr : 32'd0;
      `CSR_ADDR_DPC:
      begin
        csr_rdata = debug_mode ? dpc : 32'd0;
        if (debug_mode)
        begin
          $display("[CSR_READ_DPC] Time=%d HART_ID=%0d: Reading DPC, value=0x%08x debug_mode=%b", 
                   $time, HART_ID, dpc, debug_mode);
        end
      end
      `CSR_ADDR_DSCRATCH0:
        csr_rdata = debug_mode ? dscratch0 : 32'd0;
      `CSR_ADDR_DSCRATCH1:
        csr_rdata = debug_mode ? dscratch1 : 32'd0;
      `CSR_ADDR_TSELECT:
        csr_rdata = {30'd0, tselect};
      `CSR_ADDR_TDATA1:
        csr_rdata = tdata1[tselect];
      `CSR_ADDR_TDATA2:
        csr_rdata = tdata2[tselect];
      `CSR_ADDR_TDATA3:
        csr_rdata = tdata3[tselect];
      `CSR_ADDR_TINFO:
        csr_rdata = tinfo;
      `CSR_ADDR_TCONTROL:
        csr_rdata = tcontrol;
      `CSR_ADDR_MCONTEXT:
        csr_rdata = mcontext;
      12'hF14:
        csr_rdata = HART_ID;  // mhartid - use parameter directly
      default:
        csr_rdata = 32'd0;  // Unsupported CSRs return 0
    endcase
  end

  // CSR write data
  always_comb
  begin
    case (csr_cmd)
      `CSR_W:
        csr_wdata = op1_data;
      `CSR_S:
        csr_wdata = csr_rdata | op1_data;
      `CSR_C:
        csr_wdata = csr_rdata & ~op1_data;
      `CSR_E:
        csr_wdata = 32'd11;
      // Environment call from M-mode
      default:
        csr_wdata = 32'd0;
    endcase
  end

  // This logic is correct for driving the dmem ports
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      dmem_addr   <= 32'd0;
      dmem_wdata  <= 32'd0;
      dmem_wvalid <= 2'b00;
      exit_flag         <= 1'b0;
    end
    else
    begin
      if (proc_state == IMEM_DONE)
      begin
        dmem_addr <= alu_out;

        // For SW, prepare data and wvalid immediately
        if (`IS_SW(inst))
        begin
          dmem_wdata <= rs2_data;
          dmem_wvalid <= 2'b11;  // Assert wvalid for SW
        end
        else
        begin
          dmem_wvalid <= 2'b00;
        end
        // For SB/SH, data will be prepared after RMW read
        // mem_inst and mem_addr_saved are saved in state transition logic
      end
      else if (proc_state == DMEM_READ && dmem_rvalid && (mem_wen != `MEN_X) && (
                 `IS_SB(mem_inst)
                 ||
                 `IS_SH(mem_inst)
               ))
      begin
        // Read-Modify-Write: Merge new data with read data
        if (`IS_SB(mem_inst))
        begin
          // Store Byte: Replace one byte
          case (mem_addr_saved[1:0])
            2'b00:
              dmem_wdata <= {dmem_rdata[31:8], rs2_data[7:0]};
            2'b01:
              dmem_wdata <= {dmem_rdata[31:16], rs2_data[7:0], dmem_rdata[7:0]};
            2'b10:
              dmem_wdata <= {dmem_rdata[31:24], rs2_data[7:0], dmem_rdata[15:0]};
            2'b11:
              dmem_wdata <= {rs2_data[7:0], dmem_rdata[23:0]};
          endcase
        end
        else if (`IS_SH(mem_inst))
        begin
          // Store Halfword: Replace halfword
          case (mem_addr_saved[1])
            1'b0:
              dmem_wdata <= {dmem_rdata[31:16], rs2_data[15:0]};
            1'b1:
              dmem_wdata <= {rs2_data[15:0], dmem_rdata[15:0]};
          endcase
        end
        // Assert wvalid after preparing RMW data
        dmem_wvalid <= 2'b11;
      end
      else if (proc_state == DMEM_WRITE)
      begin
        // Maintain wvalid during write, wait for wready
        if (!dmem_wready)
        begin
          dmem_wvalid <= 2'b11;  // Keep wvalid asserted
        end
        else
        begin
          dmem_wvalid <= 2'b00;  // Deassert after write completes
        end

        // Check for tohost write (RISC-V test completion)
        if (dmem_addr == 32'h80001000 && dmem_wready)
        begin
          exit_flag <= 1'b1;  // Test completed
        end
      end
      else
      begin
        dmem_wvalid <= 2'b00;
      end
    end
  end

  // This logic is correct for driving dmem_rready
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      dmem_rready   <= 1'b0;
      rmw_read_data <= 32'd0;
    end
    else
    begin
      if (proc_state == DMEM_READ)
      begin
        dmem_rready <= 1'b1;
        // Capture read data for Read-Modify-Write (SB/SH)
        if (dmem_rvalid)
        begin
          rmw_read_data <= dmem_rdata;
        end
      end
      else
      begin
        dmem_rready <= 1'b0;
      end
    end
  end

  // ============================================================================
  // Memory Access Tracking for Triggers
  // ============================================================================
  // Track memory operations for load/store trigger matching
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      mem_load_req    <= 1'b0;
      mem_store_req   <= 1'b0;
      mem_access_addr <= 32'h0;
    end
    else
    begin
      // Capture memory access information when operations occur
      if (proc_state == DMEM_READ && dmem_rready)
      begin
        mem_load_req    <= 1'b1;
        mem_access_addr <= dmem_addr;
      end
      else
      begin
        mem_load_req <= 1'b0;
      end

      if (proc_state == DMEM_WRITE && (dmem_wvalid != 2'b00))
      begin
        mem_store_req   <= 1'b1;
        mem_access_addr <= dmem_addr;
      end
      else
      begin
        mem_store_req <= 1'b0;
      end
    end
  end

  // Writeback data selection
  always_comb
  begin
    case (wb_sel)
      `WB_MEM:
      begin
        // Handle narrower loads with sign/zero extension
        // Select correct byte/halfword based on address alignment
        // Use saved mem_inst and mem_addr_saved
        if (`IS_LB(mem_inst))
        begin
          case (mem_addr_saved[1:0])
            2'b00:
              wb_data = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
            2'b01:
              wb_data = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
            2'b10:
              wb_data = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
            2'b11:
              wb_data = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
          endcase
        end
        else if (`IS_LBU(mem_inst))
        begin
          case (mem_addr_saved[1:0])
            2'b00:
              wb_data = {24'd0, dmem_rdata[7:0]};
            2'b01:
              wb_data = {24'd0, dmem_rdata[15:8]};
            2'b10:
              wb_data = {24'd0, dmem_rdata[23:16]};
            2'b11:
              wb_data = {24'd0, dmem_rdata[31:24]};
          endcase
        end
        else if (`IS_LH(mem_inst))
        begin
          case (mem_addr_saved[1])
            1'b0:
              wb_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
            1'b1:
              wb_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
          endcase
        end
        else if (`IS_LHU(mem_inst))
        begin
          case (mem_addr_saved[1])
            1'b0:
              wb_data = {16'd0, dmem_rdata[15:0]};
            1'b1:
              wb_data = {16'd0, dmem_rdata[31:16]};
          endcase
        end
        else
        begin
          // Default to full word load
          wb_data = dmem_rdata;
        end
      end
      `WB_PC:
        wb_data = inst_pc + 32'd4;
      `WB_CSR:
        wb_data = csr_rdata;
      `WB_ALU:
        wb_data = alu_out;
      default:
        wb_data = 32'd0;
    endcase
  end

  // PC update and register write
  integer i, j;
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      pc             <= START_ADDR;

      for (i = 0; i < 32; i = i + 1)
      begin
        register_file[i] <= 32'd0;
      end

      // Initialize M-Mode CSRs
      misa         <= 32'h40001100;  // RV32I
      mtvec        <= 32'd0;
      mcause       <= 32'd0;
      mepc         <= 32'd0;
      mscratch      <= 32'd0;
      mstatus_mie  <= 1'b0;  // Interrupts disabled at reset
      mstatus_mpie <= 1'b0;
      mstatus_mpp  <= 2'b11;  // Previous privilege = M-mode

      // Initialize Debug CSRs
      dcsr_cause   <= 3'd0;
      dcsr_step    <= 1'b0;
      dcsr_prv     <= 2'b11;  // M-mode
      debug_mode   <= 1'b0;   // Always start in normal mode
      dpc          <= START_ADDR;  // Initialize DPC to START_ADDR for proper resumption
      dpc_protected <= 1'b0;
      dscratch0    <= 32'd0;
      dscratch1    <= 32'd0;

      // Hart ID is now a compile-time constant (HART_ID parameter)
      // No initialization needed

      // Initialize Trigger CSRs
      tselect      <= 2'd0;
      tcontrol     <= 32'h00000008;  // mte=1 (bit 3): M-mode triggers enabled
      mcontext     <= 32'd0;
      for (int k = 0; k < NUM_TRIGGERS; k++)
      begin
        tdata1[k]         <= 32'd0;
        tdata2[k]         <= 32'd0;
        tdata3[k]         <= 32'd0;
        icount_counter[k] <= 32'd0;
        icount_pending[k] <= 1'b0;
      end

      trap_taken        <= 1'b0;
      interrupt_trap    <= 1'b0;
      trap_cause        <= 32'd0;
    end
    else  // Normal operation
    begin
      // Track DPC changes for debugging - check at the END of the cycle
      // to see what actually got written
      
      // Clear DPC protection flag after one cycle
      dpc_protected <= 1'b0;
      
      // ========================================================================
      // Register File and CSR Writes - Execute every cycle (not gated by stall)
      // This ensures instructions complete their writeback even during APB waits
      // ========================================================================

      // Write to register file (allow writes in debug mode for debug ROM execution)
      if (proc_state == DMEM_DONE || (proc_state == IMEM_DONE && wb_sel != `WB_MEM))
      begin
        if (rf_wen == `REN_S && rd_addr != 5'd0)
        begin
          register_file[rd_addr] <= wb_data;
          // Note: exit_flag is controlled by tohost writes in memory write logic
        end
      end


      // Write to CSR (including M-Mode and Debug registers)
      // For CSRRS/CSRRC, don't write CSR if rs1=x0 (read-only operation)
      // This logic should also only execute when the instruction is ready
      if (proc_state == IMEM_DONE)
      begin
        if (csr_cmd == `CSR_W ||
            ((csr_cmd == `CSR_S || csr_cmd == `CSR_C) && rs1_addr != 5'd0) ||
            csr_cmd == `CSR_E)
        begin
          case (csr_addr)
            `CSR_ADDR_MTVEC:
              mtvec <= csr_wdata;
            `CSR_ADDR_MCAUSE:
              mcause <= csr_wdata;
            `CSR_ADDR_MEPC:
              mepc <= csr_wdata;
            `CSR_ADDR_MSTATUS:
            begin
              // Only update specific writable fields of mstatus
              mstatus_mie  <= csr_wdata[3];
              mstatus_mpie <= csr_wdata[7];
              mstatus_mpp  <= csr_wdata[12:11];
            end
            `CSR_ADDR_DCSR:
            begin
              // Only update writable fields of dcsr (debug mode only)
              if (debug_mode)
              begin
                // Update individual bit fields instead of full register
                dcsr_step <= csr_wdata[2];
                dcsr_prv  <= csr_wdata[1:0];
                // Note: cause is read-only, set by hardware
                // Note: other fields like ebreakm, stepie, etc. can be added if needed
              end
            end
            `CSR_ADDR_DPC:
              if (debug_mode && !dpc_protected)
              begin
                $display("[DPC_WRITE_CSR] Time=%d HART_ID=%0d: CSR write to DPC, old=0x%08x new=0x%08x csr_cmd=%b inst=0x%08x pc=0x%08x", 
                         $time, HART_ID, dpc, csr_wdata, csr_cmd, inst, pc);
                dpc <= csr_wdata;
              end
              else if (debug_mode && dpc_protected)
              begin
                $display("[DPC_WRITE_BLOCKED] Time=%d HART_ID=%0d: CSR write BLOCKED (protected), keeping dpc=0x%08x (would write 0x%08x)", 
                         $time, HART_ID, dpc, csr_wdata);
              end
            `CSR_ADDR_DSCRATCH0:
              if (debug_mode)
                dscratch0 <= csr_wdata;
            `CSR_ADDR_DSCRATCH1:
              if (debug_mode)
                dscratch1 <= csr_wdata;
            `CSR_ADDR_TSELECT:
              tselect <= csr_wdata[1:0];  // Only 2 bits for 4 triggers
            `CSR_ADDR_TDATA1:
              tdata1[tselect] <= csr_wdata;
            `CSR_ADDR_TDATA2:
              tdata2[tselect] <= csr_wdata;
            `CSR_ADDR_TDATA3:
              tdata3[tselect] <= csr_wdata;
            `CSR_ADDR_TCONTROL:
              tcontrol <= csr_wdata;
            `CSR_ADDR_MCONTEXT:
              mcontext <= csr_wdata;
            default:
              ;  // Unsupported CSRs - no operation
          endcase
        end
      end

      // ======================================================================
      // Instruction Count Trigger (Type 3) Counter Update
      // ======================================================================
      for (int k = 0; k < NUM_TRIGGERS; k++)
      begin
        if (tdata1[k][31:28] == 4'd3)
        begin  // Type 3 = icount
          if (instruction_retired && !debug_mode)
          begin
            if (icount_counter[k][13:0] > 14'd0)
            begin
              icount_counter[k][13:0] <= icount_counter[k][13:0] - 14'd1;
            end
            else
            begin
              // Counter reached 0, set pending
              icount_pending[k] <= 1'b1;
            end
          end
          // Reload counter when tdata1 is written
          if (proc_state == IMEM_DONE && csr_cmd != `CSR_X &&
              csr_addr == `CSR_ADDR_TDATA1 && tselect == k[1:0])
          begin
            icount_counter[k][13:0] <= csr_wdata[23:10];
            icount_pending[k]       <= csr_wdata[0];  // Pending bit
          end
        end
      end

      // ======================================================================
      // Trap Detection (for itrigger and etrigger)
      // ======================================================================
      trap_taken     <= 1'b0;  // Default: no trap
      interrupt_trap <= 1'b0;

      // Detect ECALL (exception trap)
      if (`IS_ECALL(inst) && !debug_mode && instruction_retired)
      begin
        trap_taken     <= 1'b1;
        interrupt_trap <= 1'b0;
        trap_cause     <= 32'd11;  // M-mode ECALL
      end

      // ======================================================================
      // PC UPDATE LOGIC
      // This is the single, authoritative block for the PC
      // ======================================================================

      // Memory boundary violation has highest priority (safety mechanism)
      if (mem_boundary_violation && !debug_mode && instruction_retired)
      begin
        // Enter debug mode due to memory boundary violation
        // This prevents executing undefined memory when program is not properly loaded
        debug_mode <= 1'b1;
        dcsr_cause <= `DEBUG_CAUSE_HALTREQ;  // cause = 3 (treat as halt request)
        dcsr_prv   <= 2'b11;  // M-mode
        // Save PC that violated the boundary
        $display("[DPC_WRITE_MEM_BOUNDARY] Time=%d HART_ID=%0d: Setting dpc=0x%08x (boundary violation)", 
                 $time, HART_ID, pc);
        dpc        <= pc;
        // Jump to Debug ROM entry point
        pc         <= `DEBUG_ENTRY_POINT;
        $display("[RVCORE_MEM_BOUNDARY] Time=%d HART_ID=%0d: Memory boundary violation at PC=0x%08x! Auto-halting to debug mode.", 
                 $time, HART_ID, pc);
      end  // Trigger exception has second priority (action=0)
      else if (trigger_exception_req && !debug_mode && instruction_retired)
      begin
        // Trigger exception (breakpoint exception)
        pc           <= mtvec;
        mepc         <= inst_pc;
        mcause       <= 32'd3;  // Breakpoint exception (cause=3)
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
        mstatus_mpp  <= 2'b11;
      end  // Trigger debug mode entry has third priority (action=1)
      else if (trigger_fire && !debug_mode)
      begin
        // Enter debug mode due to trigger
        debug_mode <= 1'b1;
        dcsr_cause <= `DEBUG_CAUSE_TRIGGER;  // cause = 2 (trigger)
        dcsr_prv   <= 2'b11;  // M-mode
        // Save PC of triggering instruction
        $display("[DPC_WRITE_TRIGGER] Time=%d HART_ID=%0d: Setting dpc=0x%08x (trigger fire)", 
                 $time, HART_ID, inst_pc);
        dpc        <= inst_pc;
        // Jump to Debug ROM entry point
        pc         <= `DEBUG_ENTRY_POINT;
      end  // Debug halt request has fourth priority
      else if (i_haltreq && !debug_mode && instruction_retired)
      begin
        // Enter debug mode due to halt request (at instruction boundary)
        // CRITICAL: Must wait for instruction_retired to ensure halt at instruction boundary
        // per RISC-V Debug Spec 3.2: halt at next instruction boundary
        debug_mode <= 1'b1;
        dcsr_cause <= `DEBUG_CAUSE_HALTREQ;  // cause = 3 (halt request)
        dcsr_prv   <= 2'b11;
        // M-mode
        // Save PC for resumption - use pc (next instruction) not inst_pc (current)
        // When instruction_retired=1, current instruction is done, pc points to next
        $display("[DPC_WRITE_HALTREQ] Time=%d HART_ID=%0d: Setting dpc=0x%08x (haltreq, inst_pc=0x%08x)", 
                 $time, HART_ID, pc, inst_pc);
        dpc        <= pc;
        // Jump to Debug ROM entry point
        pc         <= `DEBUG_ENTRY_POINT;
        // Debug ROM entry address
        $display("[RVCORE_HALT] Time=%d HART_ID=%0d: Entering debug mode due to haltreq! inst_pc=0x%08x pc(next)=0x%08x dpc=0x%08x -> DEBUG_ENTRY=0x%08x", 
                 $time, HART_ID, inst_pc, pc, pc, `DEBUG_ENTRY_POINT);
      end  // Single-step: Auto-halt after one instruction when dcsr.step=1
      else if (!debug_mode && dcsr_step && instruction_retired)
      begin
        // Re-enter debug mode after executing single instruction in step mode
        // per RISC-V Debug Spec 4.8.3: dcsr.step causes hart to enter debug mode
        // immediately after executing one instruction
        debug_mode <= 1'b1;
        dcsr_cause <= `DEBUG_CAUSE_STEP;  // cause = 4 (single step)
        dcsr_prv   <= 2'b11;  // M-mode
        // Save PC for resumption - dpc should point to the next instruction to execute
        // inst_pc is the PC of the instruction that just retired
        // For most instructions, next PC is inst_pc + 4 (will be corrected for branches by hardware)
        $display("[DPC_WRITE_STEP] Time=%d HART_ID=%0d: Setting dpc=0x%08x (single-step, inst_pc=0x%08x, OLD_dpc=0x%08x)", 
                 $time, HART_ID, (inst_pc + 32'd4), inst_pc, dpc);
        dpc        <= inst_pc + 32'd4;
        dpc_protected <= 1'b1;  // Protect DPC from CSR writes this cycle
        // Jump to Debug ROM entry point
        pc         <= `DEBUG_ENTRY_POINT;
        $display("[RVCORE_STEP] Time=%d HART_ID=%0d: Re-entering debug mode after single-step! inst_pc=0x%08x pc(current)=0x%08x dpc(saved)=0x%08x -> DEBUG_ENTRY=0x%08x dcsr_step=%b PROTECTED=1", 
                 $time, HART_ID, inst_pc, pc, (inst_pc + 32'd4), `DEBUG_ENTRY_POINT, dcsr_step);
      end
      else if (!debug_mode && dcsr_step)
      begin
        // Debug: dcsr.step is set but instruction not retired
        $display("[RVCORE_STEP_WAIT] Time=%d HART_ID=%0d: dcsr_step=1 but instruction_retired=0, pc=0x%08x inst_pc=0x%08x proc_state=%d", 
                 $time, HART_ID, pc, inst_pc, proc_state);
      end  // DRET: Exit debug mode
      else if (
        `IS_DRET(inst)
        && debug_mode && instruction_retired)
      begin  // Must be retired
        debug_mode <= 1'b0;
        // Restore PC from DPC
        pc         <= dpc;
      end  // ECALL: Machine mode trap
      else if (
        `IS_ECALL(inst)
        && !debug_mode && instruction_retired)
      begin  // Must be retired
        // ECALL: Jump to trap handler (mtvec) and save return address
        pc           <= mtvec;
        mepc         <= inst_pc + 32'd4;
        // Save PC of next instruction, not current
        mcause       <= 32'd11;
        // Environment call from M-mode (cause code 11)
        // Update mstatus: save MIE to MPIE, clear MIE, set MPP to M-mode
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;  // Disable interrupts in trap handler
        mstatus_mpp  <= 2'b11;
        // Previous privilege = M-mode
      end  // EBREAK: Software breakpoint (execution mode) -> Enter debug mode
      else if (`IS_EBREAK(inst) && !debug_mode && instruction_retired)
      begin
        // Enter debug mode due to EBREAK (software breakpoint)
        debug_mode <= 1'b1;
        dcsr_cause <= `DEBUG_CAUSE_EBREAK;  // cause = 1 (ebreak)
        dcsr_prv   <= 2'b11;  // M-mode
        // Save PC of EBREAK instruction for GDB to identify breakpoint location
        $display("[DPC_WRITE_EBREAK] Time=%d HART_ID=%0d: Setting dpc=0x%08x (software breakpoint)",
                 $time, HART_ID, inst_pc);
        dpc        <= inst_pc;
        // Jump to Debug ROM entry point
        pc         <= `DEBUG_ENTRY_POINT;
        $display("[RVCORE_SWBP] Time=%d HART_ID=%0d: Software breakpoint (EBREAK) at PC=0x%08x! Entering debug mode.",
                 $time, HART_ID, inst_pc);
      end  // EBREAK: In debug mode, jump to debug exception entry (DPC + 4)
      else if (`IS_EBREAK(inst) && debug_mode && instruction_retired)
      begin  // Must be retired
        pc         <= `DEBUG_ENTRY_POINT + 32'd4;
      end
      else if (`IS_MRET(inst) && !debug_mode && instruction_retired)
      begin
        pc           <= mepc;
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
      end
      else if (instruction_retired)
      begin
        if (br_flg)
        begin
          pc <= inst_pc + imm_b;
        end
        else if (wb_sel == `WB_PC)
        begin
          pc <= alu_out;
        end
        else
        begin
          pc <= inst_pc + 32'd4;
        end
      end

    end  // End of normal operation
  end

  // Exit signal
  assign exit = exit_flag;
  assign gp   = register_file[3];  // x3 is gp


endmodule
