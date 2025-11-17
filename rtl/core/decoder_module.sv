`include "instructions_defines.svh"
`include "control_defines.svh"

// Instruction Decoder Module
// With registered outputs to break critical paths
module decoder_module (
    input  logic        clk,
    input  logic        reset_n,

    // Instruction input (registered)
    input  logic [31:0] inst_r,

    // Decoded control outputs (registered)
    output logic [`EXE_FUN_LEN-1:0] exe_fun_o,
    output logic [    `OP1_LEN-1:0] op1_sel_o,
    output logic [    `OP2_LEN-1:0] op2_sel_o,
    output logic [    `MEN_LEN-1:0] mem_wen_o,
    output logic [    `REN_LEN-1:0] rf_wen_o,
    output logic [ `WB_SEL_LEN-1:0] wb_sel_o,
    output logic [    `CSR_LEN-1:0] csr_cmd_o,

    // Register addresses (registered)
    output logic [4:0] rs1_addr_o,
    output logic [4:0] rs2_addr_o,
    output logic [4:0] rd_addr_o,

    // Immediates (registered)
    output logic [31:0] imm_i_o,
    output logic [31:0] imm_s_o,
    output logic [31:0] imm_b_o,
    output logic [31:0] imm_j_o,
    output logic [31:0] imm_u_o,
    output logic [31:0] imm_z_o
  );

  // Combinational decode logic
  logic [`EXE_FUN_LEN-1:0] exe_fun_comb;
  logic [    `OP1_LEN-1:0] op1_sel_comb;
  logic [    `OP2_LEN-1:0] op2_sel_comb;
  logic [    `MEN_LEN-1:0] mem_wen_comb;
  logic [    `REN_LEN-1:0] rf_wen_comb;
  logic [ `WB_SEL_LEN-1:0] wb_sel_comb;
  logic [    `CSR_LEN-1:0] csr_cmd_comb;

  // Instruction fields
  logic [4:0] rs1_addr_comb, rs2_addr_comb, rd_addr_comb;
  logic [31:0] imm_i_comb, imm_s_comb, imm_b_comb, imm_j_comb, imm_u_comb, imm_z_comb;

  // Extract instruction fields
  assign rs1_addr_comb = inst_r[19:15];
  assign rs2_addr_comb = inst_r[24:20];
  assign rd_addr_comb  = inst_r[11:7];

  // Generate immediates
  assign imm_i_comb = {{20{inst_r[31]}}, inst_r[31:20]};
  assign imm_s_comb = {{20{inst_r[31]}}, inst_r[31:25], inst_r[11:7]};
  assign imm_b_comb = {{19{inst_r[31]}}, inst_r[31], inst_r[7], inst_r[30:25], inst_r[11:8], 1'b0};
  assign imm_j_comb = {{11{inst_r[31]}}, inst_r[31], inst_r[19:12], inst_r[20], inst_r[30:21], 1'b0};
  assign imm_u_comb = {inst_r[31:12], 12'd0};
  assign imm_z_comb = {27'd0, inst_r[19:15]};

  // Main decoder
  always_comb
  begin
    // Defaults
    exe_fun_comb = `ALU_X;
    op1_sel_comb = `OP1_RS1;
    op2_sel_comb = `OP2_RS2;
    mem_wen_comb = `MEN_X;
    rf_wen_comb  = `REN_X;
    wb_sel_comb  = `WB_X;
    csr_cmd_comb = `CSR_X;

    // Decode based on instruction
    casez (inst_r)
      // Loads
      32'b???????_?????_?????_010_?????_0000011:
      begin // LW
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_MEM;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_001_?????_0000011:
      begin // LH
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_MEM;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_101_?????_0000011:
      begin // LHU
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_MEM;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_000_?????_0000011:
      begin // LB
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_MEM;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_100_?????_0000011:
      begin // LBU
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_MEM;
        csr_cmd_comb = `CSR_X;
      end

      // Stores
      32'b???????_?????_?????_010_?????_0100011, // SW
      32'b???????_?????_?????_001_?????_0100011, // SH
      32'b???????_?????_?????_000_?????_0100011:
      begin // SB
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMS;
        mem_wen_comb = `MEN_S;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end

      // ALU R-type
      32'b0000000_?????_?????_000_?????_0110011:
      begin // ADD
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0100000_?????_?????_000_?????_0110011:
      begin // SUB
        exe_fun_comb = `ALU_SUB;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_111_?????_0110011:
      begin // AND
        exe_fun_comb = `ALU_AND;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_110_?????_0110011:
      begin // OR
        exe_fun_comb = `ALU_OR;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_100_?????_0110011:
      begin // XOR
        exe_fun_comb = `ALU_XOR;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_001_?????_0110011:
      begin // SLL
        exe_fun_comb = `ALU_SLL;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_101_?????_0110011:
      begin // SRL
        exe_fun_comb = `ALU_SRL;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0100000_?????_?????_101_?????_0110011:
      begin // SRA
        exe_fun_comb = `ALU_SRA;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_010_?????_0110011:
      begin // SLT
        exe_fun_comb = `ALU_SLT;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_011_?????_0110011:
      begin // SLTU
        exe_fun_comb = `ALU_SLTU;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end

      // ALU I-type
      32'b???????_?????_?????_000_?????_0010011:
      begin // ADDI
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_111_?????_0010011:
      begin // ANDI
        exe_fun_comb = `ALU_AND;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_110_?????_0010011:
      begin // ORI
        exe_fun_comb = `ALU_OR;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_100_?????_0010011:
      begin // XORI
        exe_fun_comb = `ALU_XOR;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_001_?????_0010011:
      begin // SLLI
        exe_fun_comb = `ALU_SLL;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_?????_?????_101_?????_0010011:
      begin // SRLI
        exe_fun_comb = `ALU_SRL;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b0100000_?????_?????_101_?????_0010011:
      begin // SRAI
        exe_fun_comb = `ALU_SRA;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_010_?????_0010011:
      begin // SLTI
        exe_fun_comb = `ALU_SLT;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_011_?????_0010011:
      begin // SLTIU
        exe_fun_comb = `ALU_SLTU;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end

      // Branches
      32'b???????_?????_?????_000_?????_1100011:
      begin // BEQ
        exe_fun_comb = `BR_BEQ;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_001_?????_1100011:
      begin // BNE
        exe_fun_comb = `BR_BNE;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_101_?????_1100011:
      begin // BGE
        exe_fun_comb = `BR_BGE;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_111_?????_1100011:
      begin // BGEU
        exe_fun_comb = `BR_BGEU;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_100_?????_1100011:
      begin // BLT
        exe_fun_comb = `BR_BLT;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_110_?????_1100011:
      begin // BLTU
        exe_fun_comb = `BR_BLTU;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end

      // Jumps
      32'b???????_?????_?????_???_?????_1101111:
      begin // JAL
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_PC;
        op2_sel_comb = `OP2_IMJ;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_PC;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_000_?????_1100111:
      begin // JALR
        exe_fun_comb = `ALU_JALR;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_IMI;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_PC;
        csr_cmd_comb = `CSR_X;
      end

      // Upper immediates
      32'b???????_?????_?????_???_?????_0110111:
      begin // LUI
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_X;
        op2_sel_comb = `OP2_IMU;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end
      32'b???????_?????_?????_???_?????_0010111:
      begin // AUIPC
        exe_fun_comb = `ALU_ADD;
        op1_sel_comb = `OP1_PC;
        op2_sel_comb = `OP2_IMU;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_ALU;
        csr_cmd_comb = `CSR_X;
      end

      // CSR instructions
      32'b???????_?????_?????_001_?????_1110011:
      begin // CSRRW
        exe_fun_comb = `ALU_COPY1;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_CSR;
        csr_cmd_comb = `CSR_W;
      end
      32'b???????_?????_?????_101_?????_1110011:
      begin // CSRRWI
        exe_fun_comb = `ALU_COPY1;
        op1_sel_comb = `OP1_IMZ;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_CSR;
        csr_cmd_comb = `CSR_W;
      end
      32'b???????_?????_?????_010_?????_1110011:
      begin // CSRRS
        exe_fun_comb = `ALU_COPY1;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_CSR;
        csr_cmd_comb = `CSR_S;
      end
      32'b???????_?????_?????_110_?????_1110011:
      begin // CSRRSI
        exe_fun_comb = `ALU_COPY1;
        op1_sel_comb = `OP1_IMZ;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_CSR;
        csr_cmd_comb = `CSR_S;
      end
      32'b???????_?????_?????_011_?????_1110011:
      begin // CSRRC
        exe_fun_comb = `ALU_COPY1;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_CSR;
        csr_cmd_comb = `CSR_C;
      end
      32'b???????_?????_?????_111_?????_1110011:
      begin // CSRRCI
        exe_fun_comb = `ALU_COPY1;
        op1_sel_comb = `OP1_IMZ;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_S;
        wb_sel_comb = `WB_CSR;
        csr_cmd_comb = `CSR_C;
      end

      // System instructions
      32'b0000000_00000_00000_000_00000_1110011:
      begin // ECALL
        exe_fun_comb = `ALU_X;
        op1_sel_comb = `OP1_X;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_E;
      end
      32'b0000000_00001_00000_000_00000_1110011:
      begin // EBREAK
        exe_fun_comb = `ALU_X;
        op1_sel_comb = `OP1_X;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b0011000_00010_00000_000_00000_1110011:
      begin // MRET
        exe_fun_comb = `ALU_X;
        op1_sel_comb = `OP1_X;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
      32'b0000000_00000_00000_000_00000_0001111:
      begin // FENCE.I
        exe_fun_comb = `ALU_X;
        op1_sel_comb = `OP1_X;
        op2_sel_comb = `OP2_X;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end

      default:
      begin
        exe_fun_comb = `ALU_X;
        op1_sel_comb = `OP1_RS1;
        op2_sel_comb = `OP2_RS2;
        mem_wen_comb = `MEN_X;
        rf_wen_comb = `REN_X;
        wb_sel_comb = `WB_X;
        csr_cmd_comb = `CSR_X;
      end
    endcase
  end

  // Register all outputs
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      exe_fun_o <= `ALU_X;
      op1_sel_o <= `OP1_RS1;
      op2_sel_o <= `OP2_RS2;
      mem_wen_o <= `MEN_X;
      rf_wen_o  <= `REN_X;
      wb_sel_o  <= `WB_X;
      csr_cmd_o <= `CSR_X;

      rs1_addr_o <= 5'd0;
      rs2_addr_o <= 5'd0;
      rd_addr_o  <= 5'd0;

      imm_i_o <= 32'd0;
      imm_s_o <= 32'd0;
      imm_b_o <= 32'd0;
      imm_j_o <= 32'd0;
      imm_u_o <= 32'd0;
      imm_z_o <= 32'd0;
    end
    else
    begin
      exe_fun_o <= exe_fun_comb;
      op1_sel_o <= op1_sel_comb;
      op2_sel_o <= op2_sel_comb;
      mem_wen_o <= mem_wen_comb;
      rf_wen_o  <= rf_wen_comb;
      wb_sel_o  <= wb_sel_comb;
      csr_cmd_o <= csr_cmd_comb;

      rs1_addr_o <= rs1_addr_comb;
      rs2_addr_o <= rs2_addr_comb;
      rd_addr_o  <= rd_addr_comb;

      imm_i_o <= imm_i_comb;
      imm_s_o <= imm_s_comb;
      imm_b_o <= imm_b_comb;
      imm_j_o <= imm_j_comb;
      imm_u_o <= imm_u_comb;
      imm_z_o <= imm_z_comb;
    end
  end

endmodule
