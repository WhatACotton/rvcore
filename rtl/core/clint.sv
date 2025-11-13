`timescale 1ns / 1ps

module clint #(
    parameter int ADDR_WIDTH       = 13,
    parameter int DATA_WIDTH       = 32,
    parameter int CLINT_BASE_ADDR  = 32'h0200_0000
  ) (
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic [ADDR_WIDTH-1:0] paddr,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [DATA_WIDTH-1:0] pwdata,
    input  logic [           3:0] pstrb,
    output logic [DATA_WIDTH-1:0] prdata,
    output logic                  pready,
    output logic                  pslverr,

    output logic                  m_timer_interrupt_o
  );

  localparam logic [15:0] OFFSET_MTIMECMP = 16'h4000;
  localparam logic [15:0] OFFSET_MTIME    = 16'hBFF8;

  logic [63:0] mtime;
  logic [63:0] mtimecmp;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      mtime <= 64'd0;
    end
    else
    begin
      mtime <= mtime + 1;
    end
  end

  assign m_timer_interrupt_o = (mtime >= mtimecmp);



  logic [3:0] addr_offset;
  logic       is_mtimecmp_access;
  logic       is_mtime_access;
  logic       is_valid_access;

  assign addr_offset = paddr[3:0];


  // mtimecmp: 0x1000 - 0x1007
  // mtime:    0x1FF8 - 0x1FFF
  assign is_mtimecmp_access = (psel && (paddr[ADDR_WIDTH-1:3] == (OFFSET_MTIMECMP[ADDR_WIDTH-1:3])));
  assign is_mtime_access = (psel && (paddr[ADDR_WIDTH-1:3] == (OFFSET_MTIME[ADDR_WIDTH-1:3])));
  assign is_valid_access = is_mtimecmp_access || is_mtime_access;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
    end
    else if (is_mtimecmp_access && penable && pwrite)
    begin
      if (addr_offset[2] == 1'b0)
      begin
        mtimecmp[31:0] <= pwdata;
      end
      else
      begin
        mtimecmp[63:32] <= pwdata;
      end
    end
  end

  // APB Read (mtime / mtimecmp)
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      prdata <= 32'd0;
    end
    else if (psel && penable && !pwrite)
    begin
      if (is_mtimecmp_access)
      begin
        if (addr_offset[2] == 1'b0)
        begin
          prdata <= mtimecmp[31:0];
        end
        else
        begin
          prdata <= mtimecmp[63:32];
        end
      end
      else if (is_mtime_access)
      begin
        if (addr_offset[2] == 1'b0)
        begin
          prdata <= mtime[31:0];
        end
        else
        begin
          prdata <= mtime[63:32];
        end
      end
      else
      begin
        prdata <= 32'd0;
      end
    end
  end

  assign pready = 1'b1;

  assign pslverr = psel && penable && !is_valid_access;

endmodule :
clint
