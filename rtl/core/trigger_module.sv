`include "dm_reg_addr.vh"

// Trigger Module (Sdtrig - Debug Spec v1.0)
// Separated module for better synthesis performance
module trigger_module #(
    parameter int NUM_TRIGGERS = 4
  ) (
    input  logic        clk,
    input  logic        reset_n,

    // Trigger CSR interface
    input  logic [1:0]              csr_tselect,
    input  logic [NUM_TRIGGERS-1:0][31:0] csr_tdata1,
    input  logic [NUM_TRIGGERS-1:0][31:0] csr_tdata2,
    input  logic [NUM_TRIGGERS-1:0][31:0] csr_tdata3,
    input  logic [31:0]             csr_tcontrol,
    input  logic [31:0]             csr_mcontext,

    // Execution state inputs (registered)
    input  logic [31:0] pc_r,
    input  logic [31:0] mem_access_addr_r,
    input  logic        mem_load_req_r,
    input  logic        mem_store_req_r,
    input  logic        instruction_retired_r,
    input  logic        trap_taken_r,
    input  logic        interrupt_trap_r,
    input  logic        debug_mode_r,

    // External trigger inputs
    input  logic [3:0]  i_external_trigger,

    // Trigger outputs (registered)
    output logic        trigger_fire_o,
    output logic        trigger_exception_req_o,
    output logic [1:0]  o_external_trigger,

    // Counter interface
    output logic [NUM_TRIGGERS-1:0][31:0] icount_counter_o,
    input  logic        csr_tdata1_write,
    input  logic [31:0] csr_tdata1_wdata
  );

  // Internal signals
  logic [NUM_TRIGGERS-1:0] trigger_mcontrol_match;
  logic [NUM_TRIGGERS-1:0] trigger_icount_match;
  logic [NUM_TRIGGERS-1:0] trigger_itrigger_match;
  logic [NUM_TRIGGERS-1:0] trigger_etrigger_match;
  logic [NUM_TRIGGERS-1:0] trigger_mcontrol6_match;
  logic [NUM_TRIGGERS-1:0] trigger_tmexttrigger_match;

  logic [NUM_TRIGGERS-1:0] trigger_action_exception;
  logic [NUM_TRIGGERS-1:0] trigger_action_debug;
  logic [NUM_TRIGGERS-1:0] trigger_action_ext0;
  logic [NUM_TRIGGERS-1:0] trigger_action_ext1;

  logic [NUM_TRIGGERS-1:0][31:0] icount_counter;
  logic [NUM_TRIGGERS-1:0] icount_pending;

  logic tcontrol_mte;

  assign tcontrol_mte = csr_tcontrol[3];

  // ========================================================================
  // Type 2: mcontrol
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] mcontrol_is_type2;
  logic [NUM_TRIGGERS-1:0] mcontrol_is_execute;
  logic [NUM_TRIGGERS-1:0] mcontrol_is_load;
  logic [NUM_TRIGGERS-1:0] mcontrol_is_store;
  logic mcontrol_trigger_enabled;

  always_comb
  begin
    mcontrol_trigger_enabled = tcontrol_mte && !debug_mode_r;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      mcontrol_is_type2[i] = (csr_tdata1[i][31:28] == 4'd2);
      mcontrol_is_execute[i] = csr_tdata1[i][2];
      mcontrol_is_store[i] = csr_tdata1[i][1];
      mcontrol_is_load[i] = csr_tdata1[i][0];

      trigger_mcontrol_match[i] = mcontrol_is_type2[i] && mcontrol_trigger_enabled && (
                              (mcontrol_is_execute[i] && (pc_r == csr_tdata2[i])) ||
                              (mcontrol_is_load[i] && mem_load_req_r && (mem_access_addr_r == csr_tdata2[i])) ||
                              (mcontrol_is_store[i] && mem_store_req_r && (mem_access_addr_r == csr_tdata2[i]))
                            );
    end
  end

  // ========================================================================
  // Type 3: icount
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] icount_is_type3;
  logic [NUM_TRIGGERS-1:0] icount_m_mode_match;
  logic [NUM_TRIGGERS-1:0] icount_count_enabled;

  always_comb
  begin
    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      icount_is_type3[i] = (csr_tdata1[i][31:28] == 4'd3);
      icount_m_mode_match[i] = csr_tdata1[i][9];
      icount_count_enabled[i] = tcontrol_mte && !debug_mode_r && icount_m_mode_match[i];

      trigger_icount_match[i] = icount_is_type3[i] && icount_count_enabled[i] &&
                          (icount_counter[i][13:0] == 14'd0) &&
                          instruction_retired_r;
    end
  end

  // ========================================================================
  // Type 4: itrigger
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] itrigger_is_type4;
  logic [NUM_TRIGGERS-1:0] itrigger_m_mode_match;
  logic itrigger_trigger_enabled;

  always_comb
  begin
    itrigger_trigger_enabled = tcontrol_mte && !debug_mode_r;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      itrigger_is_type4[i] = (csr_tdata1[i][31:28] == 4'd4);
      itrigger_m_mode_match[i] = csr_tdata1[i][9];

      trigger_itrigger_match[i] = itrigger_is_type4[i] && itrigger_trigger_enabled &&
                            itrigger_m_mode_match[i] && trap_taken_r &&
                            interrupt_trap_r;
    end
  end

  // ========================================================================
  // Type 5: etrigger
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] etrigger_is_type5;
  logic [NUM_TRIGGERS-1:0] etrigger_m_mode_match;
  logic etrigger_trigger_enabled;

  always_comb
  begin
    etrigger_trigger_enabled = tcontrol_mte && !debug_mode_r;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      etrigger_is_type5[i] = (csr_tdata1[i][31:28] == 4'd5);
      etrigger_m_mode_match[i] = csr_tdata1[i][9];

      trigger_etrigger_match[i] = etrigger_is_type5[i] && etrigger_trigger_enabled &&
                            etrigger_m_mode_match[i] && trap_taken_r &&
                            !interrupt_trap_r;
    end
  end

  // ========================================================================
  // Type 6: mcontrol6
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] mcontrol6_is_type6;
  logic [NUM_TRIGGERS-1:0] mcontrol6_is_exec;
  logic [NUM_TRIGGERS-1:0] mcontrol6_is_load;
  logic [NUM_TRIGGERS-1:0] mcontrol6_is_store;
  logic [NUM_TRIGGERS-1:0] mcontrol6_m_mode_match;
  logic [NUM_TRIGGERS-1:0] mcontrol6_trigger_enabled;

  always_comb
  begin
    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      mcontrol6_is_type6[i] = (csr_tdata1[i][31:28] == 4'd6);
      mcontrol6_m_mode_match[i] = csr_tdata1[i][2];
      mcontrol6_trigger_enabled[i] = tcontrol_mte && !debug_mode_r && mcontrol6_m_mode_match[i];

      mcontrol6_is_exec[i] = (csr_tdata1[i][16:12] == 5'd0);
      mcontrol6_is_load[i] = (csr_tdata1[i][16:12] == 5'd1);
      mcontrol6_is_store[i] = (csr_tdata1[i][16:12] == 5'd2);

      trigger_mcontrol6_match[i] = mcontrol6_is_type6[i] && mcontrol6_trigger_enabled[i] && (
                               (mcontrol6_is_exec[i] && (pc_r == csr_tdata2[i])) ||
                               (mcontrol6_is_load[i] && mem_load_req_r && (mem_access_addr_r == csr_tdata2[i])) ||
                               (mcontrol6_is_store[i] && mem_store_req_r && (mem_access_addr_r == csr_tdata2[i]))
                             );
    end
  end

  // ========================================================================
  // Type 7: tmexttrigger
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] tmexttrigger_is_type7;
  logic [NUM_TRIGGERS-1:0][3:0] tmexttrigger_ext_select;
  logic tmexttrigger_trigger_enabled;

  always_comb
  begin
    tmexttrigger_trigger_enabled = tcontrol_mte && !debug_mode_r;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      tmexttrigger_is_type7[i] = (csr_tdata1[i][31:28] == 4'd7);
      tmexttrigger_ext_select[i] = csr_tdata1[i][19:16];

      trigger_tmexttrigger_match[i] = tmexttrigger_is_type7[i] && tmexttrigger_trigger_enabled &&
                                (tmexttrigger_ext_select[i] < 4) &&
                                i_external_trigger[tmexttrigger_ext_select[i]];
    end
  end

  // ========================================================================
  // Trigger Action Decoding
  // ========================================================================
  logic [NUM_TRIGGERS-1:0] trigger_matched;
  logic [NUM_TRIGGERS-1:0][3:0] trigger_action;
  logic [NUM_TRIGGERS-1:0][3:0] trigger_type;

  always_comb
  begin
    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      trigger_matched[i] = trigger_mcontrol_match[i] |
                     trigger_icount_match[i] |
                     trigger_itrigger_match[i] |
                     trigger_etrigger_match[i] |
                     trigger_mcontrol6_match[i] |
                     trigger_tmexttrigger_match[i];

      trigger_type[i] = csr_tdata1[i][31:28];

      case (trigger_type[i])
        4'd2:
          trigger_action[i] = {3'd0, csr_tdata1[i][12]};
        4'd3:
          trigger_action[i] = {2'd0, csr_tdata1[i][6:5]};
        4'd4:
          trigger_action[i] = {2'd0, csr_tdata1[i][7:6]};
        4'd5:
          trigger_action[i] = {2'd0, csr_tdata1[i][7:6]};
        4'd6:
          trigger_action[i] = {2'd0, csr_tdata1[i][6:5]};
        4'd7:
          trigger_action[i] = csr_tdata1[i][15:12];
        default:
          trigger_action[i] = 4'd0;
      endcase

      trigger_action_exception[i] = trigger_matched[i] && (trigger_action[i] == 4'd0);
      trigger_action_debug[i]     = trigger_matched[i] && (trigger_action[i] == 4'd1);
      trigger_action_ext0[i]      = trigger_matched[i] && (trigger_action[i] == 4'd8);
      trigger_action_ext1[i]      = trigger_matched[i] && (trigger_action[i] == 4'd9);
    end
  end

  // ========================================================================
  // Registered outputs
  // ========================================================================
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      trigger_fire_o <= 1'b0;
      trigger_exception_req_o <= 1'b0;
      o_external_trigger <= 2'b00;
    end
    else
    begin
      trigger_fire_o <= |trigger_action_debug;
      trigger_exception_req_o <= |trigger_action_exception;
      o_external_trigger[0] <= |trigger_action_ext0;
      o_external_trigger[1] <= |trigger_action_ext1;
    end
  end

  // ========================================================================
  // Instruction counter
  // ========================================================================
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      for (int k = 0; k < NUM_TRIGGERS; k++)
      begin
        icount_counter[k] <= 32'd0;
        icount_pending[k] <= 1'b0;
      end
    end
    else
    begin
      for (int k = 0; k < NUM_TRIGGERS; k++)
      begin
        if (csr_tdata1[k][31:28] == 4'd3)
        begin
          if (instruction_retired_r && !debug_mode_r)
          begin
            if (icount_counter[k][13:0] > 14'd0)
            begin
              icount_counter[k][13:0] <= icount_counter[k][13:0] - 14'd1;
            end
            else
            begin
              icount_pending[k] <= 1'b1;
            end
          end
          if (csr_tdata1_write && csr_tselect == k[1:0])
          begin
            icount_counter[k][13:0] <= csr_tdata1_wdata[23:10];
            icount_pending[k] <= csr_tdata1_wdata[0];
          end
        end
      end
    end
  end

  assign icount_counter_o = icount_counter;

endmodule
