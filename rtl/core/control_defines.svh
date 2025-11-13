`define EXE_FUN_LEN 5
// OP1
`define OP1_LEN 2
`define OP1_RS1 2'b00
`define OP1_PC 2'b01
`define OP1_X 2'b10
`define OP1_IMZ 2'b11

// OP2
`define OP2_LEN 3
`define OP2_X 3'b000
`define OP2_RS2 3'b001
`define OP2_IMI 3'b010
`define OP2_IMS 3'b011
`define OP2_IMJ 3'b100
`define OP2_IMU 3'b101

// MEN (memory enable / mode)
`define MEN_LEN 2
`define MEN_X 2'b00
`define MEN_S 2'b01
`define MEN_V 2'b10

// REN (register enable mode)
`define REN_LEN 2
`define REN_X 2'b00
`define REN_S 2'b01
`define REN_V 2'b10

// WB select (3-bit full encoding)
`define WB_SEL_LEN 3
`define WB_X 3'b000
`define WB_ALU 3'b000
`define WB_MEM 3'b001
`define WB_PC 3'b010
`define WB_CSR 3'b011
`define WB_MEM_V 3'b100
`define WB_ALU_V 3'b101
`define WB_VL 3'b110

// For legacy 1-bit wb_sel signals used in this core (0=ALU,1=MEM/CSR)
`define WB_SEL_ALU 1'b0
`define WB_SEL_MEM 1'b1

// Memory width (MW) 3-bit full encoding
`define MW_LEN 3
`define MW_X 3'b000
`define MW_W 3'b001
`define MW_H 3'b010
`define MW_B 3'b011
`define MW_HU 3'b100
`define MW_BU 3'b101

// Compatibility 2-bit MW encoding used by rvcore.sv: 00=none,01=byte,10=half,11=word
`define MW2_LEN 2
`define MW2_X 2'b00
`define MW2_B 2'b01
`define MW2_H 2'b10
`define MW2_W 2'b11

// CSR command encoding
`define CSR_LEN 3
`define CSR_X 3'b000
`define CSR_W 3'b001
`define CSR_S 3'b010
`define CSR_C 3'b011
`define CSR_E 3'b100
`define CSR_V 3'b101

// CSR addresses
`define CSR_ADDR_CYCLE 12'hc00
`define CSR_ADDR_CYCLEH 12'hc80
`define CSR_ADDR_MTVEC 12'h305
`define CSR_ADDR_MCAUSE 12'h342
`define CSR_ADDR_MEPC 12'h341
`define CSR_ADDR_MSTATUS 12'h300
`define CSR_ADDR_MIE 12'h304
`define CSR_ADDR_MIP 12'h344

// Debug CSR addresses
`define CSR_ADDR_DCSR 12'h7b0
`define CSR_ADDR_DPC 12'h7b1
`define CSR_ADDR_DSCRATCH0 12'h7b2
`define CSR_ADDR_DSCRATCH1 12'h7b3

// Trigger CSR addresses (Sdtrig extension)
`define CSR_ADDR_TSELECT 12'h7a0
`define CSR_ADDR_TDATA1 12'h7a1
`define CSR_ADDR_TDATA2 12'h7a2

// Debug cause codes (dcsr.cause)
`define DEBUG_CAUSE_EBREAK 3'h1
`define DEBUG_CAUSE_TRIGGER 3'h2
`define DEBUG_CAUSE_HALTREQ 3'h3
`define DEBUG_CAUSE_STEP 3'h4
`define DEBUG_CAUSE_RESETHALTREQ 3'h5

// Interrupt cause codes (mcause with bit 31 set)
`define INT_M_SOFTWARE 32'h8000_0003
`define INT_M_TIMER 32'h8000_0007
`define INT_M_EXTERNAL 32'h8000_000B

`define ALU_X 5'd0
`define ALU_ADD 5'd1
`define ALU_SUB 5'd2
`define ALU_AND 5'd3
`define ALU_OR 5'd4
`define ALU_XOR 5'd5
`define ALU_SLL 5'd6
`define ALU_SRL 5'd7
`define ALU_SRA 5'd8
`define ALU_SLT 5'd9
`define ALU_SLTU 5'd10
`define BR_BEQ 5'd11
`define BR_BNE 5'd12
`define BR_BLT 5'd13
`define BR_BGE 5'd14
`define BR_BLTU 5'd15
`define BR_BGEU 5'd16
`define ALU_JALR 5'd17
`define ALU_COPY1 5'd18
