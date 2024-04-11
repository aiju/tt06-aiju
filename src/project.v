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
	reg [7:0] rA;
	reg [7:0] rIR;
	reg [3:0] state, state_nxt;
	localparam CPU_FETCH = 0;
	localparam EXECUTE = 1;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			rPC <= 0;
			rIR <= 0;
			state <= CPU_FETCH;
			rA <= 0;
		end else begin
			state <= state_nxt;
			case(state)
			CPU_FETCH:
				if(memory_done) begin
					rIR <= memory_rdata;
					rPC <= rPC + 1;
					state <= EXECUTE;
				end
			EXECUTE: begin
				if(rIR == 0)
					rA <= 0;
				if(rIR == 1)
					rA <= rA + 1;
				if(rIR != 2 || memory_done)
					state <= CPU_FETCH;
			end
			endcase
		end
	end

	always @(*) begin
		memory_addr = 16'bx;
		memory_wdata = 8'bx;
		memory_read = 1'b0;
		memory_write = 1'b0;
		state_nxt = state;
		case(state)
		CPU_FETCH: begin
			memory_addr = rPC;
			memory_read = 1'b1;
		end
		EXECUTE: begin
			memory_addr = 16'hCAFE;
			memory_wdata = rA;
			memory_write = rIR == 2;
		end
		endcase
	end

endmodule
