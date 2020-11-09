`include "bus.vh"
`include "control.vh"
`include "opcode.vh"
`include "aluop.vh"

module controlunit(opcode, control, aluop);

	input wire [`OPCODESIZE-1:0] opcode;
	output wire [`CONTROLSIZE-1:0] control;
	output wire [`ALUOPSIZE-1:0] aluop;

	/* wires to set the source from the */
	wire regsrc_alu;
	wire regsrc_mem;
	wire regsrc_mov;
	wire regsrc_pc;

	/* wires to set the alu operation */
	wire [`ALUOPSIZE-1:0] aluop_r;
	wire alu_inva;          /* whether to invert ALU's operand A */
	wire alu_invb;          /* whether to invert ALU's operand B */
	wire alu_shift;         /* whether to shift ALU's result */
	wire alu_shdir;         /* direction to shift ALU's result */
	wire [1:0] alu_op;      /* operation ALU should perform */
	wire [1:0] alu_op_ri;   /* operation ALU should perform */
	wire [2:0] ri_upper;
	wire [2:0] ri_lower;

	/*
	 * control the mux that decides whether the first address input
	 * of the register file comes from Rn or is X31
	 */
	assign control[`REG1LOC] =  (opcode & `CB_MASK) == `CB_BITSET
	                         || (opcode & `SHIFT_MASK) == `SHIFT_BITSET
	                         || (opcode & `BFLAG_MASK) == `BFLAG_BITSET;

	/*
	 * control the mux that decides whether the second address input
	 * of the register file comes from Rm or Rt
	 */
	assign control[`REG2LOC] =  (opcode & `CB_MASK) == `CB_BITSET
	                         || (opcode & `LDUR_MASK) == `LDUR_BITSET
	                         || (opcode & `STUR_MASK) == `STUR_BITSET
	                         || (opcode & `MOV_MASK) == `MOV_BITSET;

	/* control whether to read from data memory */
	assign control[`MEMREAD] = (opcode & `LDUR_MASK) == `LDUR_BITSET;

	/* control whether to write into data memory */
	assign control[`MEMWRITE] = (opcode & `STUR_MASK) == `STUR_BITSET;

	/* whether to set flags */
	assign control[`SETFLAGS] = ((opcode & `R_MASK) == `R_BITSET
	                          || (opcode & `I_MASK) == `I_BITSET)
	                          && ((ri_upper == 'b111 && ri_lower == 'b000)    /* AND(I)S */
	                          ||  (ri_upper == 'b101 && ri_lower == 'b100)    /* ADD(I)S */
	                          ||  (ri_upper == 'b111 && ri_lower == 'b100));  /* SUB(I)S */

	/*
	 * control the mux that decides whether the second operand of
	 * the ALU is the second data read from the registers file or
	 * the data coming out of the sign-extend
	 */
	assign control[`ALUSRC] =  (opcode & `LDUR_MASK) == `LDUR_BITSET
	                        || (opcode & `STUR_MASK) == `STUR_BITSET
	                        || (opcode & `I_MASK) == `I_BITSET;

	/* control whether writing into the registers file is enabled */
	assign control[`REGWRITE] = regsrc_mem | regsrc_mov | regsrc_alu | regsrc_pc;

	/*
	 * control the mux that decides where the data to be written
	 * into the register file comes from (only make senses when
	 * control[`REGWRITE] is asserted.  The possibles values are:
	 * `REGSRC_PC   data comes from the pc module (for BL instructions)
	 * `REGSRC_MOV  data comes from the mov module
	 * `REGSRC_MEM  data comes from the memory module
	 * `REGSRC_ALU  data comes from the alu module
	 */
	assign regsrc_pc = (opcode & `B_MASK) == `B_BITSET && opcode[`OPCODESIZE-1];
	assign regsrc_mov = (opcode & `MOV_MASK) == `MOV_BITSET;
	assign regsrc_mem = (opcode & `LDUR_MASK) == `LDUR_BITSET;
	assign regsrc_alu =  (opcode & `SHIFT_MASK) == `SHIFT_BITSET
	                  || (opcode & `R_MASK) == `R_BITSET
	                  || (opcode & `I_MASK) == `I_BITSET;
	assign control[`REGSRC1:`REGSRC0] = regsrc_pc ? `REGSRC_PC
	                                  : regsrc_mov ? `REGSRC_MOV
	                                  : regsrc_mem ? `REGSRC_MEM
	                                  : `REGSRC_ALU;

	/*
	 * upper 3 bits for R- and I- format opcodes
	 * and lower 3:1 bits for R- and I- format opcodes
	 */
	assign ri_upper = opcode[`OPCODESIZE-1:`OPCODESIZE-3];
	assign ri_lower = opcode[3:1];

	/*
	 * compose aluop from its elements
	 */
	assign aluop = {alu_inva, alu_invb, alu_shift, alu_shdir, alu_op};

	/*
	 * no instruction in LEGv8 requires the operand A to be inverted
	 */
	assign alu_inva = 1'b0;

	/*
	 * invert operand B in arithmetic operations that requires it
	 * (that is, subtraction instructions)
	 */
	assign alu_invb = ((opcode & `R_MASK) == `R_BITSET
	                || (opcode & `I_MASK) == `I_BITSET)
	                && (ri_upper[2:1] == 2'b11 && ri_lower == 4'b100);

	/*
	 * shift ALU's result if the opcode is of a shift instruction
	 */
	assign alu_shift = (opcode & `SHIFT_MASK) == `SHIFT_BITSET;

	/*
	 * shift ALU's result to the left if the opcode is of a shift
	 * instruction to the left
	 */
	assign alu_shdir = (opcode & `SHIFT_MASK) == `SHIFT_BITSET
	                 && opcode[0] == 1'b1;                  /* LSL */

	/*
	 * the two LSB of the ALU operation for R- and I-format instructions
	 */
	assign alu_op_ri = (ri_upper == 'b100 && ri_lower == 'b100) ? `ALUOP_ADD /* ADD(I) */
	                 : (ri_upper == 'b110 && ri_lower == 'b100) ? `ALUOP_ADD /* SUB(I) */
	                 : (ri_upper == 'b100 && ri_lower == 'b000) ? `ALUOP_AND /* AND(I) */
	                 : (ri_upper == 'b101 && ri_lower == 'b000) ? `ALUOP_ORR /* ORR(I) */
	                 : (ri_upper == 'b110 && ri_lower == 'b000) ? `ALUOP_EOR /* EOR(I) */
	                 : (ri_upper == 'b111 && ri_lower == 'b000) ? `ALUOP_AND /* AND(I)S */
	                 : (ri_upper == 'b101 && ri_lower == 'b100) ? `ALUOP_ADD /* ADD(I)S */
	                 : (ri_upper == 'b111 && ri_lower == 'b100) ? `ALUOP_ADD /* SUB(I)S */
	                 : `ALUOP_ADD;

	/*
	 * the two LSB of the ALU operation
	 */
	assign alu_op = ((opcode & `CB_MASK) == `CB_BITSET
	              || (opcode & `SHIFT_MASK) == `SHIFT_BITSET
	              || (opcode & `BFLAG_MASK) == `BFLAG_BITSET) ? `ALUOP_ORR
	              : ((opcode & `R_MASK) == `R_BITSET
	              || (opcode & `I_MASK) == `I_BITSET) ? alu_op_ri
	              : `ALUOP_ADD;
endmodule