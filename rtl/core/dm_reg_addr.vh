`ifndef DM_REG_ADDR_VH
`define DM_REG_ADDR_VH
`define DEBUG_ENTRY_POINT 32'h00000600

localparam int DEBUG_ENTRY_POINT = 32'h00000600;
localparam int DEBUG_AREA_START = 32'h00000200; 
localparam int DEBUG_AREA_END   = 32'h00000FFF; 
localparam int CLINT_BASE = 32'h02000000;
localparam int CLINT_END  = 32'h02001FFF; 

`endif