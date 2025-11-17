`include "dm_reg_addr.vh"

// Simplified Trigger Module (combinational logic only, no pipeline registers)
// This module contains only the trigger matching logic to reduce main core complexity
module trigger_module_comb #(
    parameter int NUM_TRIGGERS = 4
  ) (
    // Trigger CSR inputs
    input  logic [1:0]              tselect,
    input  logic [NUM_TRIGGERS-1:0][31:0] tdata1,
    input  logic [NUM_TRIGGERS-1:0][31:0] tdata2,
    input  logic [NUM_TRIGGERS-1:0][31:0] tdata3,
    input  logic [31:0]             tcontrol,
    input  logic [31:0]             mcontext,

    // Execution state inputs
    input  logic [31:0] pc,
    input  logic [31:0] mem_access_addr,
    input  logic        mem_load_req,
    input  logic        mem_store_req,
    input  logic        instruction_retired,
    input  logic        trap_taken,
    input  logic        interrupt_trap,
    input  logic        debug_mode,

    // External trigger inputs
    input  logic [3:0]  i_external_trigger,

    // Instruction counter inputs
    input  logic [NUM_TRIGGERS-1:0][31:0] icount_counter,

    // Trigger outputs (combinational)
    output logic        trigger_fire,
    output logic        trigger_exception_req,
    output logic [1:0]  o_external_trigger
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

  logic tcontrol_mte;

  assign tcontrol_mte = tcontrol[3];

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
    mcontrol_trigger_enabled = tcontrol_mte && !debug_mode;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      mcontrol_is_type2[i] = (tdata1[i][31:28] == 4'd2);
      mcontrol_is_execute[i] = tdata1[i][2];
      mcontrol_is_store[i] = tdata1[i][1];
      mcontrol_is_load[i] = tdata1[i][0];

      trigger_mcontrol_match[i] = mcontrol_is_type2[i] && mcontrol_trigger_enabled && (
                              (mcontrol_is_execute[i] && (pc == tdata2[i])) ||
                              (mcontrol_is_load[i] && mem_load_req && (mem_access_addr == tdata2[i])) ||
                              (mcontrol_is_store[i] && mem_store_req && (mem_access_addr == tdata2[i]))
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
      icount_is_type3[i] = (tdata1[i][31:28] == 4'd3);
      icount_m_mode_match[i] = tdata1[i][9];
      icount_count_enabled[i] = tcontrol_mte && !debug_mode && icount_m_mode_match[i];

      trigger_icount_match[i] = icount_is_type3[i] && icount_count_enabled[i] &&
                          (icount_counter[i][13:0] == 14'd0) &&
                          instruction_retired;
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
    itrigger_trigger_enabled = tcontrol_mte && !debug_mode;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      itrigger_is_type4[i] = (tdata1[i][31:28] == 4'd4);
      itrigger_m_mode_match[i] = tdata1[i][9];

      trigger_itrigger_match[i] = itrigger_is_type4[i] && itrigger_trigger_enabled &&
                            itrigger_m_mode_match[i] && trap_taken &&
                            interrupt_trap;
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
    etrigger_trigger_enabled = tcontrol_mte && !debug_mode;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      etrigger_is_type5[i] = (tdata1[i][31:28] == 4'd5);
      etrigger_m_mode_match[i] = tdata1[i][9];

      trigger_etrigger_match[i] = etrigger_is_type5[i] && etrigger_trigger_enabled &&
                            etrigger_m_mode_match[i] && trap_taken &&
                            !interrupt_trap;
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
      mcontrol6_is_type6[i] = (tdata1[i][31:28] == 4'd6);
      mcontrol6_m_mode_match[i] = tdata1[i][2];
      mcontrol6_trigger_enabled[i] = tcontrol_mte && !debug_mode && mcontrol6_m_mode_match[i];

      mcontrol6_is_exec[i] = (tdata1[i][16:12] == 5'd0);
      mcontrol6_is_load[i] = (tdata1[i][16:12] == 5'd1);
      mcontrol6_is_store[i] = (tdata1[i][16:12] == 5'd2);

      trigger_mcontrol6_match[i] = mcontrol6_is_type6[i] && mcontrol6_trigger_enabled[i] && (
                               (mcontrol6_is_exec[i] && (pc == tdata2[i])) ||
                               (mcontrol6_is_load[i] && mem_load_req && (mem_access_addr == tdata2[i])) ||
                               (mcontrol6_is_store[i] && mem_store_req && (mem_access_addr == tdata2[i]))
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
    tmexttrigger_trigger_enabled = tcontrol_mte && !debug_mode;

    for (int i = 0; i < NUM_TRIGGERS; i++)
    begin
      tmexttrigger_is_type7[i] = (tdata1[i][31:28] == 4'd7);
      tmexttrigger_ext_select[i] = tdata1[i][19:16];

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

      trigger_type[i] = tdata1[i][31:28];

      case (trigger_type[i])
        4'd2:
          trigger_action[i] = {3'd0, tdata1[i][12]};
        4'd3:
          trigger_action[i] = {2'd0, tdata1[i][6:5]};
        4'd4:
          trigger_action[i] = {2'd0, tdata1[i][7:6]};
        4'd5:
          trigger_action[i] = {2'd0, tdata1[i][7:6]};
        4'd6:
          trigger_action[i] = {2'd0, tdata1[i][6:5]};
        4'd7:
          trigger_action[i] = tdata1[i][15:12];
        default:
          trigger_action[i] = 4'd0;
      endcase

      trigger_action_exception[i] = trigger_matched[i] && (trigger_action[i] == 4'd0);
      trigger_action_debug[i]     = trigger_matched[i] && (trigger_action[i] == 4'd1);
      trigger_action_ext0[i]      = trigger_matched[i] && (trigger_action[i] == 4'd8);
      trigger_action_ext1[i]      = trigger_matched[i] && (trigger_action[i] == 4'd9);
    end
  end

  // Combine trigger signals
  assign trigger_fire          = |trigger_action_debug;
  assign trigger_exception_req = |trigger_action_exception;
  assign o_external_trigger[0] = |trigger_action_ext0;
  assign o_external_trigger[1] = |trigger_action_ext1;

endmodule
