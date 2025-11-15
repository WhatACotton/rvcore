`timescale 1ns / 1ps

module apb_arbiter #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int NUM_MASTERS = 2
  ) (
    input logic clk,
    input logic rst_n,

    // Master interfaces (2 inputs)
    APB.Slave master0_if,
    APB.Slave master1_if,

    // Slave interface (1 output)
    APB.Master slave_if
  );

  // Internal signals for arbitration
  logic [1:0] grant;
  logic [1:0] grant_q;
  // Registered grant to maintain during transaction
  logic       last_grant;

  // APB state tracking - follow dm_reg.sv pattern
  typedef enum logic [1:0] {
            IDLE   = 2'b00,
            SETUP  = 2'b01,
            UPDATE = 2'b10
          } apb_state_t;

  apb_state_t current_state, next_state;

  logic apb_valid_0, apb_valid_1;

  assign apb_valid_0 = master0_if.psel;
  assign apb_valid_1 = master1_if.psel;

  logic request_0, request_1;
  assign request_0 = apb_valid_0;
  assign request_1 = apb_valid_1;

  // State machine and arbiter logic - follow dm_reg.sv pattern
  always_ff @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      current_state <= IDLE;
      grant_q       <= 2'b00;
      last_grant    <= 1'b0;
    end
    else
    begin
      current_state <= next_state;
      // Register the grant decision when transitioning to SETUP state
      if (current_state == IDLE && next_state == SETUP)
      begin
        grant_q <= grant;
        // Update last_grant for round-robin - track which master was granted
        if (grant[0])
        begin
          last_grant <= 1'b0;  // Master 0 was granted
        end
        else if (grant[1])
        begin
          last_grant <= 1'b1;  // Master 1 was granted
        end
      end
    end
  end

  always_comb
  begin
    next_state = current_state;
    case (current_state)
      IDLE:
      begin
        if (request_0 || request_1)
        begin
          next_state = SETUP;
        end
      end

      SETUP:
      begin
        next_state = UPDATE;
      end

      UPDATE:
      begin
        if (slave_if.pready)
        begin
          next_state = IDLE;
        end
      end

      default:
      begin
        next_state = IDLE;
      end
    endcase
  end

  always_comb
  begin
    grant = 2'b00;
    if (current_state == IDLE && (request_0 || request_1))
    begin
      if (request_0 && request_1)
      begin
        // Both requesting - use last_grant for round-robin
        // last_grant indicates which master was granted last time
        // If master 0 was last granted, give priority to master 1
        if (last_grant == 1'b0)
        begin
          grant[1] = 1'b1;  // Grant master 1 next
        end
        else
        begin
          grant[0] = 1'b1;  // Grant master 0 next
        end
      end
      else if (request_0)
      begin
        grant[0] = 1'b1;
      end
      else if (request_1)
      begin
        grant[1] = 1'b1;
      end
    end
  end

  always_comb
  begin
    slave_if.paddr   = '0;
    slave_if.pprot   = '0;
    slave_if.psel    = 1'b0;
    slave_if.penable = 1'b0;
    slave_if.pwrite  = 1'b0;
    slave_if.pwdata  = '0;
    slave_if.pstrb   = '0;

    if (grant_q[0])
    begin
      slave_if.paddr  = master0_if.paddr;
      slave_if.pprot  = master0_if.pprot;
      slave_if.pwrite = master0_if.pwrite;
      slave_if.pwdata = master0_if.pwdata;
      slave_if.pstrb  = master0_if.pstrb;
    end
    else if (grant_q[1])
    begin
      slave_if.paddr  = master1_if.paddr;
      slave_if.pprot  = master1_if.pprot;
      slave_if.pwrite = master1_if.pwrite;
      slave_if.pwdata = master1_if.pwdata;
      slave_if.pstrb  = master1_if.pstrb;
    end
    else if (grant[0])
    begin
      slave_if.paddr  = master0_if.paddr;
      slave_if.pprot  = master0_if.pprot;
      slave_if.pwrite = master0_if.pwrite;
      slave_if.pwdata = master0_if.pwdata;
      slave_if.pstrb  = master0_if.pstrb;
    end
    else if (grant[1])
    begin
      slave_if.paddr  = master1_if.paddr;
      slave_if.pprot  = master1_if.pprot;
      slave_if.pwrite = master1_if.pwrite;
      slave_if.pwdata = master1_if.pwdata;
      slave_if.pstrb  = master1_if.pstrb;
    end

    case (current_state)
      IDLE:
      begin
        if (grant[0] || grant[1])
        begin
          slave_if.psel    = 1'b1;
          slave_if.penable = 1'b0;
        end
        else
        begin
          slave_if.psel    = 1'b0;
          slave_if.penable = 1'b0;
        end
      end

      SETUP:
      begin
        slave_if.psel    = 1'b1;
        slave_if.penable = 1'b1;
      end

      UPDATE:
      begin
        slave_if.psel    = 1'b1;
        slave_if.penable = 1'b1;
      end

      default:
      begin
        slave_if.psel    = 1'b0;
        slave_if.penable = 1'b0;
      end
    endcase
  end

  always_comb
  begin
    master0_if.pready  = 1'b0;
    master0_if.prdata  = '0;
    master0_if.pslverr = 1'b0;

    master1_if.pready  = 1'b0;
    master1_if.prdata  = '0;
    master1_if.pslverr = 1'b0;

    if (grant_q[0])
    begin
      master0_if.pready  = slave_if.pready;
      master0_if.prdata  = slave_if.prdata;
      master0_if.pslverr = slave_if.pslverr;
    end
    else if (grant_q[1])
    begin
      master1_if.pready  = slave_if.pready;
      master1_if.prdata  = slave_if.prdata;
      master1_if.pslverr = slave_if.pslverr;
    end
  end

endmodule
