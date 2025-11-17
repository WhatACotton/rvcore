`include "control_defines.svh"

// ALU and Branch Unit
// Separated module with registered outputs for better timing
module alu_module (
    input  logic        clk,
    input  logic        reset_n,

    // Control signals (registered input)
    input  logic [`EXE_FUN_LEN-1:0] exe_fun_r,

    // Operands (registered input)
    input  logic [31:0] op1_data_r,
    input  logic [31:0] op2_data_r,

    // Outputs (registered)
    output logic [31:0] alu_out_o,
    output logic        br_flg_o
  );

  logic [31:0] alu_out_comb;
  logic        br_flg_comb;

  // Combinational ALU
  always_comb
  begin
    case (exe_fun_r)
      `ALU_ADD:
        alu_out_comb = op1_data_r + op2_data_r;
      `ALU_SUB:
        alu_out_comb = op1_data_r - op2_data_r;
      `ALU_AND:
        alu_out_comb = op1_data_r & op2_data_r;
      `ALU_OR:
        alu_out_comb = op1_data_r | op2_data_r;
      `ALU_XOR:
        alu_out_comb = op1_data_r ^ op2_data_r;
      `ALU_SLL:
        alu_out_comb = op1_data_r << op2_data_r[4:0];
      `ALU_SRL:
        alu_out_comb = op1_data_r >> op2_data_r[4:0];
      `ALU_SRA:
        alu_out_comb = $signed(op1_data_r) >>> op2_data_r[4:0];
      `ALU_SLT:
        alu_out_comb = ($signed(op1_data_r) < $signed(op2_data_r)) ? 32'd1 : 32'd0;
      `ALU_SLTU:
        alu_out_comb = (op1_data_r < op2_data_r) ? 32'd1 : 32'd0;
      `ALU_JALR:
        alu_out_comb = (op1_data_r + op2_data_r) & ~32'd1;
      `ALU_COPY1:
        alu_out_comb = op1_data_r;
      default:
        alu_out_comb = 32'd0;
    endcase
  end

  // Combinational Branch Unit
  always_comb
  begin
    case (exe_fun_r)
      `BR_BEQ:
        br_flg_comb = (op1_data_r == op2_data_r);
      `BR_BNE:
        br_flg_comb = (op1_data_r != op2_data_r);
      `BR_BLT:
        br_flg_comb = ($signed(op1_data_r) < $signed(op2_data_r));
      `BR_BGE:
        br_flg_comb = ($signed(op1_data_r) >= $signed(op2_data_r));
      `BR_BLTU:
        br_flg_comb = (op1_data_r < op2_data_r);
      `BR_BGEU:
        br_flg_comb = (op1_data_r >= op2_data_r);
      default:
        br_flg_comb = 1'b0;
    endcase
  end

  // Register outputs
  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      alu_out_o <= 32'd0;
      br_flg_o  <= 1'b0;
    end
    else
    begin
      alu_out_o <= alu_out_comb;
      br_flg_o  <= br_flg_comb;
    end
  end

endmodule
