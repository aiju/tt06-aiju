/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

module tt_um_aiju (
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

	// TODO: synchroniser
	wire handshake_in;
	reg handshake_out;
	assign handshake_in = ui_in[0];
	assign uo_out = {memory_read, memory_write, handshake_out};
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

	reg [15:0] rPC;
	reg [7:0] rA, rB, rC, rD, rE, rH, rL;
	reg [7:0] rIR;
	reg [3:0] state;
	localparam CPU_FETCH = 0;
	localparam CPU_DECODE = 1;
	localparam CPU_MVI0 = 2;
	localparam CPU_MVI1 = 3;
	localparam CPU_ALU0 = 4;
	localparam CPU_ALU1 = 5;
	localparam CPU_MOV = 6;

	wire iMOV = rIR[7:6] == 1 && rIR != 8'b01110110;
	wire iALU = rIR[7:6] == 2;
	wire iMVI = rIR[7:6] == 0 && rIR[2:0] == 3'b110;
	wire memory_operand =
		iMOV && (rIR[5:3] == 3'b110 || rIR[2:0] == 3'b110)
		|| iALU && rIR[2:0] == 3'b110
		|| iMVI && rIR[5:3] == 3'b110;

	reg [3:0] decode_goto;
	always @(*) begin
		decode_goto = CPU_FETCH;
		case(1'b1)
		iMOV: decode_goto = CPU_MOV;
		iALU: decode_goto = CPU_ALU0;
		iMVI: decode_goto = CPU_MVI0;
		endcase
	end

	reg [7:0] aluIn;
	wire [7:0] aluOut;
	assign aluOut = state == CPU_MVI1 ? aluIn : rA + aluIn;

	wire pc_increment = (state == CPU_FETCH || state == CPU_MVI0) && memory_done;
	wire ir_load = state == CPU_FETCH && memory_done;
	reg [3:0] db_dst;
	reg [3:0] db_src;

	reg [7:0] DB;
	always @(*) begin
		DB = 8'bx;
		case(db_src)
		4'b0111: DB = aluOut;
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
		end else begin
			if(pc_increment)
				rPC <= rPC + 1;
			if(ir_load)
				rIR <= memory_rdata;
		end
	end

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			{rA, rB, rC, rD, rE, rH, rL} <= 0;
			aluIn <= 0;
		end else begin
			case(db_dst)
			4'b0111: aluIn <= DB;
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

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			state <= CPU_FETCH;
		end else begin
			case(state)
			CPU_FETCH:
				if(memory_done)
					state <= CPU_DECODE;
			CPU_DECODE:
				state <= decode_goto;
			CPU_MVI0:
				if(memory_done)
					state <= memory_operand ? CPU_MVI1 : CPU_FETCH;
			CPU_MVI1:
				if(memory_done)
					state <= CPU_FETCH;
			CPU_MOV:
				if(!memory_operand || memory_done)
					state <= CPU_FETCH;
			CPU_ALU0:
				if(!memory_operand || memory_done)
					state <= CPU_ALU1;
			CPU_ALU1:
				state <= CPU_FETCH;
			endcase
		end
	end

	always @(*) begin
		memory_addr = 16'bx;
		memory_wdata = 8'bx;
		memory_read = 1'b0;
		memory_write = 1'b0;
		case(state)
		CPU_FETCH, CPU_MVI0: begin
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
			if(memory_operand) begin
				memory_addr = {rH, rL};
				memory_read = 1'b1;
			end
		end
		endcase
	end

	always @(*) begin
		db_src = 4'b0000;
		db_dst = 4'b0000;
		case(state)
		CPU_MOV: begin
			db_src = {1'b1, rIR[2:0]};
			db_dst = {1'b1, rIR[5:3]};
		end
		CPU_MVI0: begin
			db_src = 4'b1110;
			db_dst = memory_operand ? 4'b0111 : {1'b1, rIR[5:3]};
		end
		CPU_MVI1: begin
			db_src = 4'b0111;
		end
		CPU_ALU0: begin
			db_src = {1'b1, rIR[2:0]};
			db_dst = 4'b0111;
		end
		CPU_ALU1: begin
			db_src = 4'b0111;
			db_dst = 4'b1111;
		end
		endcase
	end

endmodule
