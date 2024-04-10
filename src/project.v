/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

module tt_um_aiju (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

	reg [7:0] rPC, rIP;
	reg [3:0] state;

	assign uio_oe = 8'b0;
	assign uio_out = {7'b0, state == 0};
	assign uo_out = rPC;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			rPC <= 0;
			rIP <= 0;
			state <= 0;
		end else begin
			case(state)
			0: begin
				state <= 1;
			end
			1: begin
				rIP <= ui_in;
				rPC <= rPC + 1;
				state <= 2;
			end
			2: begin
				if(rIP == 42)
					state <= 2;
				else
					state <= 0;
			end
			endcase
		end
	end

endmodule
