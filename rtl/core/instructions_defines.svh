// Auto-generated instruction defines based on Scala BitPat patterns
// Converted to SystemVerilog `define macros for opcode, funct3, funct7
// and helper IS_* macros that test an instruction word `instr`.

// Opcodes (instr[6:0])
`define OPC_LOAD 7'b0000011
`define OPC_STORE 7'b0100011
`define OPC_OP_IMM 7'b0010011
`define OPC_OP 7'b0110011
`define OPC_LUI 7'b0110111
`define OPC_AUIPC 7'b0010111
`define OPC_JAL 7'b1101111
`define OPC_JALR 7'b1100111
`define OPC_BRANCH 7'b1100011
`define OPC_SYSTEM 7'b1110011
`define OPC_VECTOR 7'b1010111
`define OPC_LOAD_FP 7'b0000111 // used by VLE pattern
`define OPC_STORE_FP 7'b0100111 // used by VSE pattern

// funct3 fields (instr[14:12])
// Loads
`define F3_LB 3'b000
`define F3_LH 3'b001
`define F3_LW 3'b010
`define F3_LBU 3'b100
`define F3_LHU 3'b101

// Stores
`define F3_SB 3'b000
`define F3_SH 3'b001
`define F3_SW 3'b010
`define F3_SBU 3'b100 // non-standard name present in source
`define F3_SHU 3'b101 // non-standard name present in source

// Integer ALU / IMM
`define F3_ADD_SUB 3'b000
`define F3_SLL 3'b001
`define F3_SLT 3'b010
`define F3_SLTU 3'b011
`define F3_XOR 3'b100
`define F3_SRL_SRA 3'b101
`define F3_OR 3'b110
`define F3_AND 3'b111

// Branches
`define F3_BEQ 3'b000
`define F3_BNE 3'b001
`define F3_BLT 3'b100
`define F3_BGE 3'b101
`define F3_BLTU 3'b110
`define F3_BGEU 3'b111

// CSR funct3 encodings
`define F3_CSRRW 3'b001
`define F3_CSRRS 3'b010
`define F3_CSRRC 3'b011
`define F3_CSRRWI 3'b101
`define F3_CSRRSI 3'b110
`define F3_CSRRCI 3'b111

// funct7 fields (instr[31:25])
`define F7_ADD 7'b0000000
`define F7_SUB 7'b0100000
`define F7_SRA 7'b0100000
`define F7_SRL 7'b0000000
`define F7_SLL 7'b0000000

// Specific instruction immediate encodings
`define ECALL_ENCODING 32'h00000073
`define EBREAK_ENCODING 32'h00100073
`define MRET_ENCODING  32'h30200073
`define DRET_ENCODING  32'h7b200073
`define FENCE_I_ENCODING 32'h0000100f

// Helper macros: expect a 32-bit wire/reg named `instr` in scope
`define IS_OPCODE(opc) ((instr[6:0]) == (opc))
`define IS_F3(f3) ((instr[14:12]) == (f3))
`define IS_F7(f7) ((instr[31:25]) == (f7))

// Load/Store
`define IS_LB(instr) ((instr[6:0] == `OPC_LOAD) && (instr[14:12] == `F3_LB))
`define IS_LH(instr) ((instr[6:0] == `OPC_LOAD) && (instr[14:12] == `F3_LH))
`define IS_LW(instr) ((instr[6:0] == `OPC_LOAD) && (instr[14:12] == `F3_LW))
`define IS_LBU(instr) ((instr[6:0] == `OPC_LOAD) && (instr[14:12] == `F3_LBU))
`define IS_LHU(instr) ((instr[6:0] == `OPC_LOAD) && (instr[14:12] == `F3_LHU))

`define IS_SB(instr) ((instr[6:0] == `OPC_STORE) && (instr[14:12] == `F3_SB))
`define IS_SH(instr) ((instr[6:0] == `OPC_STORE) && (instr[14:12] == `F3_SH))
`define IS_SW(instr) ((instr[6:0] == `OPC_STORE) && (instr[14:12] == `F3_SW))

// Add / Sub
`define IS_ADD(
instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_ADD_SUB) && (instr[31:25] == `F7_ADD))
`define IS_SUB(
instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_ADD_SUB) && (instr[31:25] == `F7_SUB))
`define IS_ADDI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_ADD_SUB))

// Logical
`define IS_AND(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_AND))
`define IS_OR(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_OR))
`define IS_XOR(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_XOR))
`define IS_ANDI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_AND))
`define IS_ORI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_OR))
`define IS_XORI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_XOR))

// Shifts
`define IS_SLL(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_SLL) && (instr[31:25] == `F7_SLL))
`define IS_SRL(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_SRL_SRA) && (instr[31:25] == `F7_SRL))
`define IS_SRA(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_SRL_SRA) && (instr[31:25] == `F7_SRA))
`define IS_SLLI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_SLL) && (instr[31:25] == `F7_SLL))
`define IS_SRLI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_SRL_SRA) && (instr[31:25] == `F7_SRL))
`define IS_SRAI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_SRL_SRA) && (instr[31:25] == `F7_SRA))

// Compare
`define IS_SLT(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_SLT))
`define IS_SLTU(instr) ((instr[6:0] == `OPC_OP) && (instr[14:12] == `F3_SLTU))
`define IS_SLTI(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_SLT))
`define IS_SLTIU(instr) ((instr[6:0] == `OPC_OP_IMM) && (instr[14:12] == `F3_SLTU))

// Branches
`define IS_BEQ(instr) ((instr[6:0] == `OPC_BRANCH) && (instr[14:12] == `F3_BEQ))
`define IS_BNE(instr) ((instr[6:0] == `OPC_BRANCH) && (instr[14:12] == `F3_BNE))
`define IS_BLT(instr) ((instr[6:0] == `OPC_BRANCH) && (instr[14:12] == `F3_BLT))
`define IS_BGE(instr) ((instr[6:0] == `OPC_BRANCH) && (instr[14:12] == `F3_BGE))
`define IS_BLTU(instr) ((instr[6:0] == `OPC_BRANCH) && (instr[14:12] == `F3_BLTU))
`define IS_BGEU(instr) ((instr[6:0] == `OPC_BRANCH) && (instr[14:12] == `F3_BGEU))

// Jumps
`define IS_JAL(instr) ((instr[6:0] == `OPC_JAL))
`define IS_JALR(instr) ((instr[6:0] == `OPC_JALR) && (instr[14:12] == 3'b000))

// LUI / AUIPC
`define IS_LUI(instr) ((instr[6:0] == `OPC_LUI))
`define IS_AUIPC(instr) ((instr[6:0] == `OPC_AUIPC))

// CSR
`define IS_CSRRW(instr) ((instr[6:0] == `OPC_SYSTEM) && (instr[14:12] == `F3_CSRRW))
`define IS_CSRRWI(instr) ((instr[6:0] == `OPC_SYSTEM) && (instr[14:12] == `F3_CSRRWI))
`define IS_CSRRS(instr) ((instr[6:0] == `OPC_SYSTEM) && (instr[14:12] == `F3_CSRRS))
`define IS_CSRRSI(instr) ((instr[6:0] == `OPC_SYSTEM) && (instr[14:12] == `F3_CSRRSI))
`define IS_CSRRC(instr) ((instr[6:0] == `OPC_SYSTEM) && (instr[14:12] == `F3_CSRRC))
`define IS_CSRRCI(instr) ((instr[6:0] == `OPC_SYSTEM) && (instr[14:12] == `F3_CSRRCI))

// ECALL
`define IS_ECALL(instr) ((instr) == `ECALL_ENCODING)

// EBREAK
`define IS_EBREAK(instr) ((instr) == `EBREAK_ENCODING)

// MRET
`define IS_MRET(instr) ((instr) == `MRET_ENCODING)

// DRET (Debug Return)
`define IS_DRET(instr) ((instr) == `DRET_ENCODING)

// FENCE.I (Instruction Fence)
`define IS_FENCE_I(instr) ((instr) == `FENCE_I_ENCODING)

// Vector (basic matches from BitPat)
`define IS_VSETVLI(instr) ((instr[6:0] == `OPC_VECTOR) && (instr[14:12] == 3'b111))
`define IS_VLE(instr) ((instr[6:0] == `OPC_LOAD_FP) && (instr[31:25] == 7'b0000001))
`define IS_VSE(instr) ((instr[6:0] == `OPC_STORE_FP) && (instr[31:25] == 7'b0000001))
`define IS_VADDVV(instr) ((instr[6:0] == `OPC_VECTOR) && (instr[31:25] == 7'b0000001) && (instr[14:12] == 3'b000))

// Custom instruction(s)
`define IS_PCNT(instr) ((instr[6:0] == 7'b0001011) && (instr[31:12] == 20'b00000000000000000000))

// Note: consumers should include this file and use macros like:
//    `IS_ADD(instr)    or  (`OPC_LOAD)
// The macros assume a 32-bit scalar/vector 'instr' in scope.
