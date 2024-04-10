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

	reg [7:0] ctr;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n)
			ctr <= 0;
		else
			ctr <= ctr + 1;
	end

	assign uo_out = ctr;

	assign uio_out = 8'b0;
	assign uio_oe = 8'b0;

endmodule
