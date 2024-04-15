`default_nettype none
module cpu(
    input wire clk,
    input wire rst_n,

    output reg memory_read,
    output reg memory_write,
    output reg [15:0] memory_addr,
    output reg memory_io,
    output reg [7:0] memory_wdata,
    input wire [7:0] memory_rdata,
    input wire memory_done,

    input wire debug_req,
    input wire int_req,

    output wire cpu_fetch,
    output wire cpu_halted,
    output wire cpu_in_debug,
    output wire cpu_int_ack
);

	reg [15:0] AL;
	reg [15:0] rPC;
	reg [15:0] rSP;
	reg [7:0] rA, rB, rC, rD, rE, rH, rL;
	reg [7:0] rPSR;
	reg [7:0] rIR;
	reg [5:0] state;
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
	localparam CPU_CALL0 = 22;
	localparam CPU_CALL1 = 23;
	localparam CPU_CALL2 = 24;
	localparam CPU_CALL3 = 25;
	localparam CPU_RET0 = 26;
	localparam CPU_RET1 = 27;
	localparam CPU_PCHL0 = 28;
	localparam CPU_PCHL1 = 29;
	localparam CPU_PCHL2 = 30;
	localparam CPU_SPHL0 = 31;
	localparam CPU_SPHL1 = 32;
	localparam CPU_INRDCR0 = 33;
	localparam CPU_INRDCR1 = 34;
	localparam CPU_INXDCX0 = 35;
	localparam CPU_INXDCX1 = 36;
	localparam CPU_INXDCX2 = 37;
	localparam CPU_INXDCX3 = 38;
	localparam CPU_LDAXSTAX0 = 39;
	localparam CPU_LDAXSTAX1 = 40;
	localparam CPU_LDAXSTAX2 = 41;
    localparam CPU_XCHG0 = 42;
    localparam CPU_XCHG1 = 43;
    localparam CPU_XCHG2 = 44;
    localparam CPU_XCHG3 = 45;
    localparam CPU_XCHG4 = 46;
    localparam CPU_XCHG5 = 47;
    localparam CPU_DAD0 = 48;
    localparam CPU_DAD1 = 49;
    localparam CPU_DAD2 = 50;
    localparam CPU_DAD3 = 51;
    localparam CPU_DAD4 = 52;
    localparam CPU_DAD5 = 53;
    localparam CPU_DAD6 = 54;
    localparam CPU_DAD7 = 55;
    localparam CPU_IO0 = 56;
    localparam CPU_IO1 = 57;
    localparam CPU_EIDI = 58;
    localparam CPU_DEBUG0 = 62;
    localparam CPU_DEBUG1 = 63;

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
	wire iCALL = rIR == 8'hCD;
	wire iCALLcc = (rIR & ~8'h38) == 8'b1100_0100;
	wire iRST = (rIR & ~8'h38) == 8'b1100_0111;
	wire iRET = rIR == 8'hC9;
	wire iRETcc = (rIR & ~8'h38) == 8'b1100_0000;
	wire iJMPcc = (rIR & ~8'h38) == 8'b1100_0010;
	wire iPCHL = rIR == 8'hE9;
	wire iSPHL = rIR == 8'hF9;
	wire iINR = (rIR & ~8'h38) == 8'b0000_0100;
	wire iDCR = (rIR & ~8'h38) == 8'b0000_0101;
	wire iINX = (rIR & ~8'h30) == 8'b0000_0011;
	wire iDCX = (rIR & ~8'h30) == 8'b0000_1011;
	wire iINX_SP = rIR == 8'b0011_0011;
	wire iDCX_SP = rIR == 8'b0011_1011;
	wire iLDAX = (rIR & ~8'h10) == 8'b0000_1010;
	wire iSTAX = (rIR & ~8'h10) == 8'b0000_0010;
    wire iXCHG = rIR == 8'b1110_1011;
    wire iXTHL = rIR == 8'b1110_0011;
    wire iDAD = (rIR & ~8'h30) == 8'b0000_1001;
    wire iIN = rIR == 8'b1101_1011;
    wire iOUT = rIR == 8'b1101_0011;
    wire iNOP = rIR == 8'b0000_0000;
    wire iEI = rIR == 8'b1111_1011;
    wire iDI = rIR == 8'b1111_0011;
    wire undefined =
        (rIR & ~8'h38) == 8'b0000_0000 && !iNOP
        || rIR == 8'b1101_1001
        || (rIR & ~8'h30) == 8'b1100_1101 && !iCALL
        || rIR == 8'b1100_1011;
	wire memory_operand =
		iMOV && (rIR[5:3] == 3'b110 || rIR[2:0] == 3'b110)
		|| iALU && rIR[2:0] == 3'b110
		|| (iINR || iDCR || iMVI) && rIR[5:3] == 3'b110;

    wire dbgEXIT = rIR[6];
    wire dbgREAD = !rIR[7] && !dbgEXIT;
    wire dbgWRITE = rIR[7];

	reg condition;
	always @(*) begin
		case(rIR[5:3])
		3'b000: condition = !rPSR[6];
		3'b001: condition = rPSR[6];
		3'b010: condition = !rPSR[0];
		3'b011: condition = rPSR[0];
		3'b100: condition = !rPSR[2];
		3'b101: condition = rPSR[2];
		3'b110: condition = !rPSR[7];
		3'b111: condition = rPSR[7];
		endcase
	end

    reg int_enabled;
    reg int_latch;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            int_enabled <= 1'b0;
            int_latch <= 1'b0;
        end else begin
            if(state == CPU_EIDI) begin
                if(iEI)
                    int_enabled <= 1'b1;
                if(iDI)
                    int_enabled <= 1'b0;
            end
            if(cpu_int_ack)
                int_enabled <= 1'b0;
            if(cycle_done)
                int_latch <= int_req && int_enabled && !(state == CPU_EIDI && iDI || cpu_int_ack);
        end
    end
    assign cpu_int_ack = state == CPU_FETCH && int_latch;

	reg [5:0] decode_goto;
    reg missing_decoder_case;
	always @(*) begin
		decode_goto = CPU_FETCH;
        missing_decoder_case = 1'b0;
		case(1'b1)
		iMOV: decode_goto = CPU_MOV;
		iALU, iALUI: decode_goto = CPU_ALU0;
		iMVI: decode_goto = CPU_MVI0;
		iJMP, iJMPcc: decode_goto = CPU_JMP0;
		iPUSH: decode_goto = CPU_PUSH0;
		iPOP: decode_goto = CPU_POP0;
		iHALT: decode_goto = CPU_HALT;
		iLXI: decode_goto = CPU_LXI0;
		iLDA, iSTA, iLHLD, iSHLD: decode_goto = CPU_DIRECT0;
		iUNARY: decode_goto = CPU_UNARY;
		iCALL, iCALLcc, iRST: decode_goto = CPU_CALL0;
		iRET: decode_goto = CPU_RET0;
		iRETcc: decode_goto = condition ? CPU_RET0 : CPU_FETCH;
		iPCHL: decode_goto = CPU_PCHL0;
		iSPHL: decode_goto = CPU_SPHL0;
		iINR, iDCR: decode_goto = CPU_INRDCR0;
		iINX, iDCX: decode_goto = CPU_INXDCX0;
		iLDAX, iSTAX: decode_goto = CPU_LDAXSTAX0;
        iXCHG, iXTHL: decode_goto = CPU_XCHG0;
        iDAD: decode_goto = CPU_DAD0;
        iIN, iOUT: decode_goto = CPU_IO0;
        iNOP, undefined: decode_goto = CPU_FETCH;
        iEI, iDI: decode_goto = CPU_EIDI;
        default: missing_decoder_case = 1'b1;
		endcase
	end

    always @(posedge clk) begin
        if(state == CPU_DECODE && undefined)
            $display("undefined opcode %x", rIR);
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
	localparam ALU_INC = 16;
	localparam ALU_DEC = 17;
	localparam ALU_NOP = 31;

    reg [7:0] daa_operand;
    always @(*) begin
        daa_operand = 8'h00;
        if(rA[3:0] > 9 || rPSR[4])
            daa_operand[3:0] = 6;
        if(rA >= 8'h9a || rPSR[0])
            daa_operand[7:4] = 6;
    end

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
			alu_aux_carry_out = (((rA & 15) - (aluIn & 15) - (rPSR[0] & (alu_op == ALU_SBB))) & 16) == 0;
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
		ALU_DAA: begin
            {alu_carry_out, aluOut} = (rA + daa_operand) | (rPSR[0] ? 9'h100 : 9'h000);
            alu_aux_carry_out = (((rA & 15) + (daa_operand & 15)) & 16) != 0;
		end
		ALU_INC: begin
			{alu_carry_out, aluOut} = aluIn + 1;
			alu_aux_carry_out = (aluIn & 15) == 15;
		end
		ALU_DEC: begin
			{alu_carry_out, aluOut} = aluIn - 1;
			alu_aux_carry_out = (aluIn & 15) != 0;
		end
		endcase
	end
	wire alu_zero = aluOut == 0;
	wire alu_parity = ~^aluOut;
	wire alu_sign = aluOut[7];
	wire [7:0] alu_flags = {alu_sign, alu_zero, 1'b0, alu_aux_carry_out, 1'b0, alu_parity, 1'b1, alu_carry_out};

	wire cycle_done = !memory_read && !memory_write || memory_done;
	wire pc_increment =
		state == CPU_FETCH && !debug_req && !cpu_int_ack
        || state == CPU_MVI0 || state == CPU_JMP0 || state == CPU_JMP1 && iJMPcc && !condition
		|| state == CPU_ALU0 && iALUI
		|| state == CPU_LXI0 || state == CPU_LXI1
		|| state == CPU_DIRECT0 || state == CPU_DIRECT1
		|| (state == CPU_CALL0 || state == CPU_CALL1) && !iRST
        || state == CPU_IO0;
	wire al_increment = state == CPU_DIRECT2;
	wire sp_decrement =
		state == CPU_PUSH0 || state == CPU_PUSH1
		|| state == CPU_CALL1 && (!iCALLcc || condition)
		|| state == CPU_CALL2
		|| state == CPU_INXDCX0 && iDCX_SP
        || state == CPU_XCHG5 && iXTHL;
	wire sp_increment =
		state == CPU_POP0 || state == CPU_POP1
		|| state == CPU_RET0 || state == CPU_RET1
		|| state == CPU_INXDCX0 && iINX_SP
        || state == CPU_XCHG2 && iXTHL;
	wire pc_jmp =
		state == CPU_JMP1 && (!iJMPcc || condition)
		|| state == CPU_RET1;
	wire pc_jmp_al = state == CPU_CALL3 && !iRST || state == CPU_PCHL2;
	wire pc_rst_jmp = state == CPU_CALL3 && iRST;
	wire ir_load = state == CPU_FETCH || state == CPU_DEBUG0;
    assign cpu_fetch = state == CPU_FETCH;
	assign cpu_halted = state == CPU_HALT;
    assign cpu_in_debug = state == CPU_DEBUG0 || state == CPU_DEBUG1;
	reg [4:0] db_dst;
	reg [4:0] db_src;

	localparam DB_ALL = 5'b00010;
	localparam DB_ALH = 5'b00011;
	localparam DB_SPL = 5'b00100;
	localparam DB_SPH = 5'b00101;
	localparam DB_PSR = 5'b00110;
	localparam DB_ALU = 5'b00111;
	localparam DB_B = 5'b01000;
	localparam DB_C = 5'b01001;
	localparam DB_D = 5'b01010;
	localparam DB_E = 5'b01011;
	localparam DB_H = 5'b01100;
	localparam DB_L = 5'b01101;
	localparam DB_MEM = 5'b01110;
	localparam DB_A = 5'b01111;
	localparam DB_PCL = 5'b10000;
	localparam DB_PCH = 5'b10001;

	reg [7:0] DB;
	always @(*) begin
		DB = 8'bx;
		case(db_src)
		DB_PSR: DB = rPSR;
		DB_ALU: DB = aluOut;
		DB_B: DB = rB;
		DB_C: DB = rC;
		DB_D: DB = rD;
		DB_E: DB = rE;
		DB_H: DB = rH;
		DB_L: DB = rL;
		DB_MEM: DB = memory_rdata;
		DB_A: DB = rA;
        DB_SPL: DB = rSP[7:0];
        DB_SPH: DB = rSP[15:8];
		DB_PCL: DB = rPC[7:0];
		DB_PCH: DB = rPC[15:8];
        DB_ALL: DB = AL[7:0];
        DB_ALH: DB = AL[15:8];
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
				if(pc_jmp_al)
					rPC <= AL;
				if(pc_rst_jmp)
					rPC <= rIR & 8'h38;
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
				DB_B: rB <= DB;
				DB_C: rC <= DB;
				DB_D: rD <= DB;
				DB_E: rE <= DB;
				DB_H: rH <= DB;
				DB_L: rL <= DB;
				DB_A: rA <= DB;
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
                    if(debug_req)
                        state <= CPU_DEBUG0;
                    else
					    state <= CPU_DECODE;
				CPU_DECODE:
					state <= decode_goto;
                CPU_HALT:
                    if(debug_req)
                        state <= CPU_DEBUG0;
                    else if(int_latch)
                        state <= CPU_FETCH;
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
				CPU_CALL0:
					state <= CPU_CALL1;
				CPU_CALL1:
					if(!iCALLcc || condition)
						state <= CPU_CALL2;
					else
						state <= CPU_FETCH;
				CPU_CALL2:
					state <= CPU_CALL3;
				CPU_CALL3:
					state <= CPU_FETCH;
				CPU_RET0:
					state <= CPU_RET1;
				CPU_RET1:
					state <= CPU_FETCH;
				CPU_PCHL0:
					state <= CPU_PCHL1;
				CPU_PCHL1:
					state <= CPU_PCHL2;
				CPU_PCHL2:
					state <= CPU_FETCH;
				CPU_SPHL0:
					state <= CPU_SPHL1;
				CPU_SPHL1:
					state <= CPU_FETCH;
				CPU_INRDCR0:
					state <= CPU_INRDCR1;
				CPU_INRDCR1:
					state <= CPU_FETCH;
				CPU_INXDCX0:
					state <= iINX_SP || iDCX_SP ? CPU_FETCH : CPU_INXDCX1;
				CPU_INXDCX1:
					state <= alu_carry_out ? CPU_INXDCX2 : CPU_FETCH;
				CPU_INXDCX2:
					state <= CPU_INXDCX3;
				CPU_INXDCX3:
					state <= CPU_FETCH;
				CPU_LDAXSTAX0:
					state <= CPU_LDAXSTAX1;
				CPU_LDAXSTAX1:
					state <= CPU_LDAXSTAX2;
				CPU_LDAXSTAX2:
					state <= CPU_FETCH;
                CPU_DEBUG0:
                    state <= CPU_DEBUG1;
                CPU_DEBUG1:
                    if(dbgEXIT)
                        state <= CPU_FETCH;
                    else
                        state <= CPU_DEBUG0;
                CPU_XCHG0:
                    state <= CPU_XCHG1;
                CPU_XCHG1:
                    state <= CPU_XCHG2;
                CPU_XCHG2:
                    state <= CPU_XCHG3;
                CPU_XCHG3:
                    state <= CPU_XCHG4;
                CPU_XCHG4:
                    state <= CPU_XCHG5;
                CPU_XCHG5:
                    state <= CPU_FETCH;
                CPU_DAD0:
                    state <= CPU_DAD1;
                CPU_DAD1:
                    state <= CPU_DAD2;
                CPU_DAD2:
                    state <= CPU_DAD3;
                CPU_DAD3:
                    state <= CPU_DAD4;
                CPU_DAD4:
                    state <= CPU_DAD5;
                CPU_DAD5:
                    state <= CPU_DAD6;
                CPU_DAD6:
                    state <= CPU_DAD7;
                CPU_DAD7:
                    state <= CPU_FETCH;
                CPU_IO0:
                    state <= CPU_IO1;
                CPU_IO1:
                    state <= CPU_FETCH;
                CPU_EIDI:
                    state <= CPU_FETCH;
`ifndef SYNTHESIS
                default:
                    assert(0);
`endif
				endcase
			end
		end
	end

	always @(*) begin
		memory_addr = 16'bx;
		memory_wdata = 8'bx;
		memory_read = 1'b0;
		memory_write = 1'b0;
        memory_io = 1'b0;
		case(state)
		CPU_FETCH, CPU_MVI0, CPU_JMP0, CPU_JMP1, CPU_LXI0, CPU_LXI1, CPU_DIRECT0, CPU_DIRECT1, CPU_IO0: begin
			memory_addr = rPC;
			memory_read = 1'b1;
		end
		CPU_CALL0, CPU_CALL1: begin
			memory_addr = rPC;
			memory_read = !iRST;
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
		CPU_POP0, CPU_POP1, CPU_RET0, CPU_RET1: begin
			memory_addr = rSP;
			memory_read = 1'b1;
		end
		CPU_DIRECT2, CPU_DIRECT3: begin
			memory_addr = AL;
			memory_read = iLDA || iLHLD;
			memory_write = iSTA || iSHLD;
			memory_wdata = DB;
		end
		CPU_CALL2, CPU_CALL3: begin
			memory_addr = rSP;
			memory_wdata = DB;
			memory_write = 1'b1;
		end
		CPU_INRDCR0, CPU_INRDCR1: begin
			if(memory_operand) begin
				memory_addr = {rH, rL};
				memory_wdata = DB;
				memory_read = state == CPU_INRDCR0;
				memory_write = state == CPU_INRDCR1;
			end
		end
		CPU_LDAXSTAX2: begin
			memory_addr = AL;
			memory_read = iLDAX;
			memory_write = iSTAX;
			memory_wdata = DB;
		end
        CPU_XCHG1, CPU_XCHG4: begin
            if(iXTHL) begin
                memory_read = 1'b1;
                memory_addr = rSP;
            end
        end
        CPU_XCHG2, CPU_XCHG5: begin
            if(iXTHL) begin
                memory_write = 1'b1;
                memory_wdata = DB;
                memory_addr = rSP;
            end
        end
        CPU_IO1: begin
            memory_addr = {8'b0, AL[7:0]};
            memory_wdata = DB;
            memory_read = iIN;
            memory_write = iOUT;
            memory_io = 1'b1;
        end
        CPU_DEBUG0: begin
            memory_addr = 16'hCAFE;
            memory_read = 1'b1;
            memory_io = 1'b1;
        end
        CPU_DEBUG1: begin
            memory_io = 1'b1;
            if(dbgREAD) begin
                memory_addr = 16'hCAFF;
                memory_write = 1'b1;
                memory_wdata = DB;
            end
            if(dbgWRITE) begin
                memory_addr = 16'hCAFF;
                memory_read = 1'b1;
            end
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
		CPU_JMP0, CPU_RET0: begin
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
		CPU_CALL0: begin
			db_src = DB_MEM;
			db_dst = DB_ALL;
		end
		CPU_CALL1: begin
			db_src = DB_MEM;
			db_dst = DB_ALH;
		end
		CPU_CALL2:
			db_src = DB_PCH;
		CPU_CALL3:
			db_src = DB_PCL;
		CPU_PCHL0: begin
			db_src = DB_L;
			db_dst = DB_ALL;
		end
		CPU_PCHL1: begin
			db_src = DB_H;
			db_dst = DB_ALH;
		end
		CPU_SPHL0: begin
			db_src = DB_L;
			db_dst = DB_SPL;
		end
		CPU_SPHL1: begin
			db_src = DB_H;
			db_dst = DB_SPH;
		end
		CPU_INRDCR0: begin
			db_src = {1'b1, rIR[5:3]};
			db_dst = DB_ALU;
		end
		CPU_INRDCR1: begin
			db_src = DB_ALU;
			db_dst = {1'b1, rIR[5:3]};
			alu_op = iDCR ? ALU_DEC : ALU_INC;
			set_flags = 8'hfe;
		end
		CPU_INXDCX0, CPU_INXDCX2: begin
			db_src = {1'b1, rIR[5:4], state == CPU_INXDCX0};
			db_dst = DB_ALU;
		end
		CPU_INXDCX1, CPU_INXDCX3: begin
			db_src = DB_ALU;
			db_dst = {1'b1, rIR[5:4], state == CPU_INXDCX1};
			alu_op = iDCX ? ALU_DEC : ALU_INC;
		end
		CPU_LDAXSTAX0, CPU_LDAXSTAX1: begin
			db_src = {1'b1, 1'b0, rIR[4], state == CPU_LDAXSTAX0};
			db_dst = state == CPU_LDAXSTAX1 ? DB_ALH : DB_ALL;
		end
		CPU_LDAXSTAX2: begin
			if(iLDAX) begin
				db_src = DB_MEM;
				db_dst = DB_A;
			end else
				db_src = DB_A;
		end
        CPU_DEBUG1: begin
            if(dbgREAD) begin
                db_src = rIR[4:0];
            end
            if(dbgWRITE) begin
                db_src = DB_MEM;
                db_dst = rIR[4:0];
            end
        end
        CPU_XCHG0: begin
            db_src = DB_L;
            db_dst = DB_ALL;
        end
        CPU_XCHG1: begin
            db_src = iXTHL ? DB_MEM : DB_E;
            db_dst = DB_L;
        end
        CPU_XCHG2: begin
            db_src = DB_ALL;
            if(iXCHG)
                db_dst = DB_E;
        end
        CPU_XCHG3: begin
            db_src = DB_H;
            db_dst = DB_ALL;
        end
        CPU_XCHG4: begin
            db_src = iXTHL ? DB_MEM : DB_D;
            db_dst = DB_H;
        end
        CPU_XCHG5: begin
            db_src = DB_ALL;
            if(iXCHG)
                db_dst = DB_D;
        end
        CPU_DAD0: begin
            db_src = DB_A;
            db_dst = DB_ALL;
        end
        CPU_DAD1: begin
            db_src = DB_L;
            db_dst = DB_A;
        end
        CPU_DAD2: begin
            db_src = rIR[5:4] == 3 ? DB_SPL : {1'b1, rIR[5:4], 1'b1};
            db_dst = DB_ALU;
        end
        CPU_DAD3: begin
            alu_op = ALU_ADD;
            db_src = DB_ALU;
            db_dst = DB_L;
            set_flags = 8'h01;
        end
        CPU_DAD4: begin
            db_src = DB_H;
            db_dst = DB_A;
        end
        CPU_DAD5: begin
            db_src = rIR[5:4] == 3 ? DB_SPH : {1'b1, rIR[5:4], 1'b0};
            db_dst = DB_ALU;
        end
        CPU_DAD6: begin
            alu_op = ALU_ADC;
            db_src = DB_ALU;
            db_dst = DB_H;
            set_flags = 8'h01;
        end
        CPU_DAD7: begin
            db_src = DB_ALL;
            db_dst = DB_A;
        end
        CPU_IO0: begin
            db_src = DB_MEM;
            db_dst = DB_ALL;
        end
        CPU_IO1: begin
            if(iIN) begin
                db_src = DB_MEM;
                db_dst = DB_A;
            end
            if(iOUT)
                db_src = DB_A;
        end
		endcase
	end

`ifdef FORMAL
    initial state = CPU_FETCH;

	default clocking
		@(posedge clk);
	endclocking
	default disable iff(!rst_n);

    assume property (memory_done |=> !memory_done);
    assume property (debug_req && !cpu_in_debug |=> debug_req);

    read_until_done: assert property (memory_read && !memory_done |=> memory_read);
    write_until_done: assert property (memory_write && !memory_done |=> memory_write);
    not_read_and_write: assert property (!memory_read || !memory_write);
    stable_memory_addr: assert property (!$initstate && (memory_read && $past(memory_read) || memory_write && $past(memory_write)) && !$past(memory_done) |-> $stable(memory_addr) && $stable(memory_io));
    stable_memory_wdata: assert property (!$initstate && memory_write && $past(memory_write) && !$past(memory_done) && state != CPU_DEBUG1 |-> $stable(memory_wdata));

    assert property (state == CPU_ALU0 || state == CPU_ALU1 |-> iALU || iALUI);
    assert property (state == CPU_HALT |-> iHALT);
    assert property (state == CPU_POP0 || state == CPU_POP1 |-> iPOP);
    assert property (state == CPU_PUSH0 || state == CPU_PUSH1 || state == CPU_PUSH2 |-> iPUSH);
    assert property (state == CPU_PCHL0 || state == CPU_PCHL1 || state == CPU_PCHL2 |-> iPCHL);
    assert property (state == CPU_RET0 || state == CPU_RET1 |-> iRET || iRETcc);
    assert property (state == CPU_UNARY |-> iUNARY);
    assert property (state == CPU_INRDCR0 || state == CPU_INRDCR1 |-> iINR || iDCR);
    assert property (state == CPU_DAD0 || state == CPU_DAD1 || state == CPU_DAD2 || state == CPU_DAD3 || state == CPU_DAD4 || state == CPU_DAD5 || state == CPU_DAD6 || state == CPU_DAD7 |-> iDAD);
    assert property (state == CPU_JMP0 || state == CPU_JMP1 |-> iJMP || iJMPcc);
    assert property (state == CPU_INXDCX0 || state == CPU_INXDCX1 || state == CPU_INXDCX2 || state == CPU_INXDCX3 |-> iINX || iDCX);
    assert property (state == CPU_MOV |-> iMOV);
    assert property (state == CPU_DIRECT0 || state == CPU_DIRECT1 || state == CPU_DIRECT2 |-> iLDA || iSTA || iLHLD || iSHLD);
    assert property (state == CPU_DIRECT3 |-> iLHLD || iSHLD);
    assert property (state == CPU_MVI0 || state == CPU_MVI1 |-> iMVI);
    assert property (state == CPU_LXI0 || state == CPU_LXI1 |-> iLXI);
    assert property (state == CPU_LDAXSTAX0 || state == CPU_LDAXSTAX1 || state == CPU_LDAXSTAX2 |-> iLDAX || iSTAX);
    assert property (state == CPU_SPHL0 || state == CPU_SPHL1 |-> iSPHL);
    assert property (state == CPU_IO0 || state == CPU_IO1 |-> iIN || iOUT);
    assert property (state == CPU_CALL0 || state == CPU_CALL1 || state == CPU_CALL2 || state == CPU_CALL3 |-> iCALL || iCALLcc || iRST);
    assert property (state == CPU_XCHG0 || state == CPU_XCHG1 || state == CPU_XCHG2 || state == CPU_XCHG3 || state == CPU_XCHG4 || state == CPU_XCHG5 |-> iXCHG || iXTHL);
    assert property (state == CPU_EIDI |-> iEI || iDI);

    exactly_one_decode: assert property ($onehot({
        iMOV, iALU, iALUI, iMVI, iJMP, iPUSH, iPOP, iHALT, iLXI, iLDA, iSTA, iLHLD, iSHLD,
        iUNARY, iCALL, iCALLcc, iRST, iRET, iRETcc, iJMPcc, iPCHL, iSPHL, iINR, iDCR,
        iINX, iDCX, iLDAX, iSTAX, iXCHG, iXTHL, iDAD, iIN, iOUT, iNOP, iEI, iDI,
        undefined}));
    inx_sp_dcx_sp: assert property ((!iINX_SP || iINX) && (!iDCX_SP || iDCX));
    no_missing_cases: assert property (!missing_decoder_case);


`ifdef LIVENESS
    assume property (memory_read |-> ##[1:3] memory_done);
    assume property (memory_write |-> ##[1:3] memory_done);
    assert property (state != CPU_FETCH |-> ##[1:40] state == CPU_FETCH || state == CPU_HALT || state == CPU_DEBUG0 || state == CPU_DEBUG1);
    assert property (debug_req && !cpu_in_debug |-> ##[1:40] cpu_in_debug);
`endif
`endif
endmodule
