/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

module tt_um_aiju_8080 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output reg [7:0] uio_out,  // IOs: Output path
    output reg [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

	reg memory_read, memory_write;
	reg memory_done;
	reg [15:0] memory_addr;
	wire [7:0] memory_rdata;
	reg [7:0] memory_wdata;
	wire halted;

	// TODO: synchroniser
	wire handshake_in;
	reg handshake_out;
	assign handshake_in = ui_in[0];
	assign uo_out = {halted, memory_read, memory_write, handshake_out};
	reg handshake_valid, handshake_ready;
	reg handshake_state;
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			handshake_ready <= 1'b0;
			handshake_state <= 1'b0;
			handshake_out <= 1'b0;
		end else begin
			handshake_ready <= 1'b0;
			if(!handshake_state) begin
				if(!handshake_in) begin
					handshake_state <= 1'b1;
				end
			end else begin
				if(handshake_valid) begin
					handshake_out <= 1'b1;
				end
				if(handshake_in && handshake_out) begin
					handshake_ready <= 1'b1;
					handshake_out <= 1'b0;
					handshake_state <= 1'b0;
				end
			end
		end
	end

	reg [3:0] memory_state, memory_state_nxt;
	assign memory_rdata = uio_in;
	localparam MEMORY_IDLE = 0;
	localparam MEMORY_ADDR_LOW = 1;
	localparam MEMORY_ADDR_HIGH = 2;
	localparam MEMORY_DATA = 3;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			memory_state <= MEMORY_IDLE;
		end else begin
			memory_state <= memory_state_nxt;
		end
	end

	always @(*) begin
		memory_state_nxt = memory_state;
		uio_oe = 8'b0;
		uio_out = 8'bx;
		handshake_valid = 1'b0;
		memory_done = 1'b0;
		case(memory_state)
		MEMORY_IDLE: begin
			if(memory_read || memory_write) begin
				memory_state_nxt = MEMORY_ADDR_LOW;
			end
		end
		MEMORY_ADDR_LOW: begin
			handshake_valid = 1'b1;
			uio_oe = 8'hff;
			uio_out = memory_addr[7:0];
			if(handshake_ready) begin
				memory_state_nxt = MEMORY_ADDR_HIGH;
			end
		end
		MEMORY_ADDR_HIGH: begin
			handshake_valid = 1'b1;
			uio_oe = 8'hff;
			uio_out = memory_addr[15:8];
			if(handshake_ready) begin
				memory_state_nxt = MEMORY_DATA;
			end
		end
		MEMORY_DATA: begin
			handshake_valid = 1'b1;
			if(memory_write) begin
				uio_oe = 8'hff;
				uio_out = memory_wdata;
			end
			if(handshake_ready) begin
				memory_done = 1'b1;
				memory_state_nxt = MEMORY_IDLE;
			end
		end
		endcase
	end

	reg [15:0] AL;
	reg [15:0] rPC;
	reg [15:0] rSP;
	reg [7:0] rA, rB, rC, rD, rE, rH, rL;
	reg [7:0] rPSR;
	reg [7:0] rIR;
	reg [4:0] state;
	localparam CPU_FETCH = 0;
	localparam CPU_DECODE = 1;
	localparam CPU_MVI0 = 2;
	localparam CPU_MVI1 = 3;
	localparam CPU_ALU0 = 4;
	localparam CPU_ALU1 = 5;
	localparam CPU_MOV = 6;
	localparam CPU_JMP0 = 7;
	localparam CPU_JMP1 = 8;
	localparam CPU_PUSH0 = 9;
	localparam CPU_PUSH1 = 10;
	localparam CPU_PUSH2 = 11;
	localparam CPU_POP0 = 12;
	localparam CPU_POP1 = 13;
	localparam CPU_HALT = 14;
	localparam CPU_LXI0 = 15;
	localparam CPU_LXI1 = 16;
	localparam CPU_DIRECT0 = 17;
	localparam CPU_DIRECT1 = 18;
	localparam CPU_DIRECT2 = 19;
	localparam CPU_DIRECT3 = 20;
	localparam CPU_UNARY = 21;

	wire iMOV = rIR[7:6] == 1 && rIR != 8'b01110110;
	wire iALU = rIR[7:6] == 2;
	wire iALUI = (rIR & ~8'h38) == 8'b1100_0110;
	wire iMVI = rIR[7:6] == 0 && rIR[2:0] == 3'b110;
	wire iJMP = rIR == 8'b1100_0011;
	wire iPUSH = (rIR & ~8'h30) == 8'b1100_0101;
	wire iPOP = (rIR & ~8'h30) == 8'b1100_0001;
	wire iHALT = rIR == 8'h76;
	wire iLXI = (rIR & ~8'h30) == 8'b0000_0001;
	wire iLDA = rIR == 8'h3A;
	wire iSTA = rIR == 8'h32;
	wire iLHLD = rIR == 8'h2A;
	wire iSHLD = rIR == 8'h22;
	wire iUNARY = (rIR & ~8'h38) == 8'b0000_0111;
	wire memory_operand =
		iMOV && (rIR[5:3] == 3'b110 || rIR[2:0] == 3'b110)
		|| iALU && rIR[2:0] == 3'b110
		|| iMVI && rIR[5:3] == 3'b110;

	reg [4:0] decode_goto;
	always @(*) begin
		decode_goto = CPU_FETCH;
		case(1'b1)
		iMOV: decode_goto = CPU_MOV;
		iALU, iALUI: decode_goto = CPU_ALU0;
		iMVI: decode_goto = CPU_MVI0;
		iJMP: decode_goto = CPU_JMP0;
		iPUSH: decode_goto = CPU_PUSH0;
		iPOP: decode_goto = CPU_POP0;
		iHALT: decode_goto = CPU_HALT;
		iLXI: decode_goto = CPU_LXI0;
		iLDA, iSTA, iLHLD, iSHLD: decode_goto = CPU_DIRECT0;
		iUNARY: decode_goto = CPU_UNARY;
		endcase
	end

	reg [7:0] aluIn;
	reg [7:0] aluOut;
	reg alu_carry_out, alu_aux_carry_out;
	reg [4:0] alu_op;
	reg [7:0] set_flags;
	localparam ALU_ADD = 0;
	localparam ALU_ADC = 1;
	localparam ALU_SUB = 2;
	localparam ALU_SBB = 3;
	localparam ALU_AND = 4;
	localparam ALU_XOR = 5;
	localparam ALU_OR = 6;
	localparam ALU_CMP = 7;
	localparam ALU_RLC = 8;
	localparam ALU_RRC = 9;
	localparam ALU_RAL = 10;
	localparam ALU_RAR = 11;
	localparam ALU_DAA = 12;
	localparam ALU_CMA = 13;
	localparam ALU_STC = 14;
	localparam ALU_CMC = 15;
	localparam ALU_NOP = 31;

	always @(*) begin
		alu_carry_out = 1'b0;
		alu_aux_carry_out = 1'b0;
		aluOut = aluIn;
		case(alu_op)
		ALU_ADD, ALU_ADC: begin
			{alu_carry_out, aluOut} = rA + aluIn + (rPSR[0] & (alu_op == ALU_ADC));
			alu_aux_carry_out = (((rA & 15) + (aluIn & 15) + (rPSR[0] & (alu_op == ALU_ADC))) & 16) != 0;
		end
		ALU_SUB, ALU_SBB, ALU_CMP: begin
			{alu_carry_out, aluOut} = rA - aluIn - (rPSR[0] & (alu_op == ALU_SBB));
			alu_aux_carry_out = (((rA & 15) - (aluIn & 15) - (rPSR[0] & (alu_op == ALU_SBB))) & 16) != 0;
		end
		ALU_AND: begin
			aluOut = rA & aluIn;
			alu_aux_carry_out = rA[3] | aluIn[3];
		end
		ALU_OR:
			aluOut = rA | aluIn;
		ALU_XOR:
			aluOut = rA ^ aluIn;
		ALU_RLC: begin
			aluOut = {rA[6:0], rA[7]};
			alu_carry_out = rA[7];
		end
		ALU_RRC: begin
			aluOut = {rA[0], rA[7:1]};
			alu_carry_out = rA[0];
		end
		ALU_RAL: begin
			{alu_carry_out, aluOut} = {rA, rPSR[0]};
		end
		ALU_RAR: begin
			{aluOut, alu_carry_out} = {rPSR[0], rA};
		end
		ALU_CMA: aluOut = ~rA;
		ALU_CMC: begin
			aluOut = rA;
			alu_carry_out = ~rPSR[0];
		end
		ALU_STC: begin
			aluOut = rA;
			alu_carry_out = 1'b1;
		end
		ALU_DAA: begin : daa
			reg [7:0] a;

			if(rA[3:0] > 9 || rPSR[4]) begin
				a = rA + 6;
				alu_aux_carry_out = rA[3:0] > 9;
			end else begin
				a = rA;
				alu_aux_carry_out = 1'b0;
			end
			if(a[7:4] > 9 || rPSR[0]) begin
				aluOut = a + 8'h60;
				alu_carry_out = a[7:4] > 9;
			end else begin
				aluOut = a;
				alu_carry_out = 1'b0;
			end
		end
		endcase
	end
	wire alu_zero = aluOut == 0;
	wire alu_parity = ^aluOut;
	wire alu_sign = aluOut[7];
	wire [7:0] alu_flags = {alu_sign, alu_zero, 1'b0, alu_aux_carry_out, 1'b0, alu_parity, 1'b1, alu_carry_out};

	wire cycle_done = !memory_read && !memory_write || memory_done;
	wire pc_increment =
		state == CPU_FETCH || state == CPU_MVI0 || state == CPU_JMP0
		|| state == CPU_ALU0 && iALUI
		|| state == CPU_LXI0 || state == CPU_LXI1
		|| state == CPU_DIRECT0 || state == CPU_DIRECT1;
	wire al_increment = state == CPU_DIRECT2;
	wire sp_decrement = state == CPU_PUSH0 || state == CPU_PUSH1;
	wire sp_increment = state == CPU_POP0 || state == CPU_POP1;
	wire pc_jmp = state == CPU_JMP1;
	wire ir_load = state == CPU_FETCH;
	assign halted = state == CPU_HALT;
	reg [3:0] db_dst;
	reg [3:0] db_src;

	localparam DB_ALL = 4'b0010;
	localparam DB_ALH = 4'b0011;
	localparam DB_SPL = 4'b0100;
	localparam DB_SPH = 4'b0101;
	localparam DB_PSR = 4'b0110;
	localparam DB_ALU = 4'b0111;
	localparam DB_MEM = 4'b1110;
	localparam DB_H = 4'b1100;
	localparam DB_L = 4'b1101;
	localparam DB_A = 4'b1111;

	reg [7:0] DB;
	always @(*) begin
		DB = 8'bx;
		case(db_src)
		DB_PSR: DB = rPSR;
		DB_ALU: DB = aluOut;
		4'b1000: DB = rB;
		4'b1001: DB = rC;
		4'b1010: DB = rD;
		4'b1011: DB = rE;
		4'b1100: DB = rH;
		4'b1101: DB = rL;
		4'b1110: DB = memory_rdata;
		4'b1111: DB = rA;
		endcase
	end

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			rPC <= 0;
			rIR <= 0;
			rSP <= 0;
			AL <= 0;
		end else begin
			if(cycle_done) begin
				if(pc_increment)
					rPC <= rPC + 1;
				if(pc_jmp)
					rPC <= {memory_rdata, aluIn};
				if(ir_load)
					rIR <= memory_rdata;
				if(db_dst == DB_SPH)
					rSP[15:8] <= DB;
				if(db_dst == DB_SPL)
					rSP[7:0] <= DB;
				if(sp_increment)
					rSP <= rSP + 1;
				if(sp_decrement)
					rSP <= rSP - 1;
				if(db_dst == DB_ALH)
					AL[15:8] <= DB;
				if(db_dst == DB_ALL)
					AL[7:0] <= DB;
				if(al_increment)
					AL <= AL + 1;
			end
		end
	end

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			rPSR <= 2;
		end else begin
			if(cycle_done) begin
				if(db_dst == DB_PSR)
					rPSR <= DB & ~8'h28 | 2;
				else
					rPSR <= (rPSR & ~set_flags | alu_flags & set_flags) & ~8'h28 | 2;
			end
		end
	end

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			{rA, rB, rC, rD, rE, rH, rL} <= 0;
			aluIn <= 0;
		end else begin
			if(cycle_done) begin
				case(db_dst)
				DB_ALU: aluIn <= DB;
				4'b1000: rB <= DB;
				4'b1001: rC <= DB;
				4'b1010: rD <= DB;
				4'b1011: rE <= DB;
				4'b1100: rH <= DB;
				4'b1101: rL <= DB;
				4'b1111: rA <= DB;
				endcase
			end
		end
	end

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			state <= CPU_FETCH;
		end else begin
			if(cycle_done) begin
				case(state)
				CPU_FETCH:
					state <= CPU_DECODE;
				CPU_DECODE:
					state <= decode_goto;
				CPU_MVI0:
					state <= memory_operand ? CPU_MVI1 : CPU_FETCH;
				CPU_MVI1:
					state <= CPU_FETCH;
				CPU_MOV:
					state <= CPU_FETCH;
				CPU_ALU0:
					state <= CPU_ALU1;
				CPU_ALU1:
					state <= CPU_FETCH;
				CPU_JMP0:
					state <= CPU_JMP1;
				CPU_JMP1:
					state <= CPU_FETCH;
				CPU_PUSH0:
					state <= CPU_PUSH1;
				CPU_PUSH1:
					state <= CPU_PUSH2;
				CPU_PUSH2:
					state <= CPU_FETCH;
				CPU_POP0:
					state <= CPU_POP1;
				CPU_POP1:
					state <= CPU_FETCH;
				CPU_LXI0:
					state <= CPU_LXI1;
				CPU_LXI1:
					state <= CPU_FETCH;
				CPU_DIRECT0:
					state <= CPU_DIRECT1;
				CPU_DIRECT1:
					state <= CPU_DIRECT2;
				CPU_DIRECT2:
					if(iLHLD || iSHLD)
						state <= CPU_DIRECT3;
					else
						state <= CPU_FETCH;
				CPU_DIRECT3:
					state <= CPU_FETCH;
				CPU_UNARY:
					state <= CPU_FETCH;
				endcase
			end
		end
	end

	always @(*) begin
		memory_addr = 16'bx;
		memory_wdata = 8'bx;
		memory_read = 1'b0;
		memory_write = 1'b0;
		case(state)
		CPU_FETCH, CPU_MVI0, CPU_JMP0, CPU_JMP1, CPU_LXI0, CPU_LXI1, CPU_DIRECT0, CPU_DIRECT1: begin
			memory_addr = rPC;
			memory_read = 1'b1;
		end
		CPU_MVI1: begin
			memory_addr = {rH, rL};
			memory_wdata = DB;
			memory_write = 1'b1;
		end
		CPU_MOV: begin
			memory_addr = {rH, rL};
			if(rIR[5:3] == 6) begin
				memory_wdata = DB;
				memory_write = 1'b1;
			end else if(rIR[2:0] == 6)
				memory_read = 1'b1;
		end
		CPU_ALU0: begin
			if(iALUI) begin
				memory_addr = rPC;
				memory_read = 1'b1;
			end else if(memory_operand) begin
				memory_addr = {rH, rL};
				memory_read = 1'b1;
			end
		end
		CPU_PUSH1, CPU_PUSH2: begin
			memory_addr = rSP;
			memory_wdata = DB;
			memory_write = 1'b1;
		end
		CPU_POP0, CPU_POP1: begin
			memory_addr = rSP;
			memory_read = 1'b1;
		end
		CPU_DIRECT2, CPU_DIRECT3: begin
			memory_addr = AL;
			memory_read = iLDA || iLHLD;
			memory_write = iSTA || iSHLD;
			memory_wdata = DB;
		end
		endcase
	end

	always @(*) begin
		db_src = 4'b0000;
		db_dst = 4'b0000;
		alu_op = ALU_NOP;
		set_flags = 0;
		case(state)
		CPU_MOV: begin
			db_src = {1'b1, rIR[2:0]};
			db_dst = {1'b1, rIR[5:3]};
		end
		CPU_MVI0: begin
			db_src = DB_MEM;
			db_dst = memory_operand ? DB_ALU : {1'b1, rIR[5:3]};
		end
		CPU_MVI1: begin
			db_src = DB_ALU;
		end
		CPU_ALU0: begin
			db_src = iALUI ? DB_MEM : {1'b1, rIR[2:0]};
			db_dst = DB_ALU;
		end
		CPU_ALU1: begin
			db_src = DB_ALU;
			if(rIR[5:3] != 3'b111)
				db_dst = DB_A;
			alu_op = rIR[5:3];
			set_flags = 8'hff;
		end
		CPU_JMP0: begin
			db_src = DB_MEM;
			db_dst = DB_ALU;
		end
		CPU_PUSH1, CPU_PUSH2: begin
			if(rIR[5:4] == 3)
				db_src = state == CPU_PUSH1 ? DB_A : DB_PSR;
			else
				db_src = {1'b1, rIR[5:4], state == CPU_PUSH2};
		end
		CPU_POP0, CPU_POP1: begin
			db_src = DB_MEM;
			if(rIR[5:4] == 3)
				db_dst = state == CPU_POP1 ? DB_A : DB_PSR;
			else
				db_dst = {1'b1, rIR[5:4], state == CPU_POP0};
		end
		CPU_LXI0, CPU_LXI1: begin
			db_src = DB_MEM;
			if(rIR[5:4] == 3)
				db_dst = state == CPU_LXI1 ? DB_SPH : DB_SPL;
			else
				db_dst = {1'b1, rIR[5:4], state != CPU_LXI1};
		end
		CPU_DIRECT0, CPU_DIRECT1: begin
			db_src = DB_MEM;
			db_dst = state == CPU_DIRECT1 ? DB_ALH : DB_ALL;
		end
		CPU_DIRECT2: begin
			case(1'b1)
			iSTA:
				db_src = DB_A;
			iLDA: begin
				db_src = DB_MEM;
				db_dst = DB_A;
			end
			iSHLD:
				db_src = DB_L;
			iLHLD: begin
				db_src = DB_MEM;
				db_dst = DB_L;
			end
			endcase
		end
		CPU_DIRECT3: begin
			if(iSHLD)
				db_src = DB_H;
			else begin
				db_src = DB_MEM;
				db_dst = DB_H;
			end
		end
		CPU_UNARY: begin
			db_src = DB_ALU;
			db_dst = DB_A;
			alu_op = {1'b1, rIR[5:3]};
			case(rIR[5:3])
			4: set_flags = 8'hff;
			5: set_flags = 0;
			default: set_flags = 1;
			endcase
		end
		endcase
	end

endmodule
