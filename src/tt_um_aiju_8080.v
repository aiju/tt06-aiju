/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

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

	/*AUTOWIRE*/
	// Beginning of automatic wires (for undeclared instantiated-module outputs)
	wire [7:0]	bus_data_out;		// From bus_if_i of bus_if.v
	wire		bus_handshake_req;	// From bus_if_i of bus_if.v
	wire		bus_output_enable;	// From bus_if_i of bus_if.v
	wire [1:0]	bus_state;		// From bus_if_i of bus_if.v
	wire		cpu_halted;		// From cpu_i of cpu.v
	wire [15:0]	memory_addr;		// From cpu_i of cpu.v
	wire		memory_done;		// From bus_if_i of bus_if.v
	wire [7:0]	memory_rdata;		// From bus_if_i of bus_if.v
	wire		memory_read;		// From cpu_i of cpu.v
	wire [7:0]	memory_wdata;		// From cpu_i of cpu.v
	wire		memory_write;		// From cpu_i of cpu.v
	// End of automatics

	assign uo_out[0] = bus_handshake_req;
	assign uo_out[1] = bus_state[0];
	assign uo_out[2] = bus_state[1];
	assign uo_out[3] = cpu_halted;
	assign uo_out[4] = 1'b0;
	assign uo_out[5] = 1'b0;
	assign uo_out[6] = 1'b0;
	assign uo_out[7] = 1'b0;

	wire bus_handshake_ack = ui_in[0];

	wire [7:0] bus_data_in = uio_in;
	assign uio_out = bus_data_out;
	assign uio_oe = {8{bus_output_enable}};

	bus_if bus_if_i(/*AUTOINST*/
			// Outputs
			.bus_handshake_req(bus_handshake_req),
			.bus_state	(bus_state[1:0]),
			.bus_data_out	(bus_data_out[7:0]),
			.bus_output_enable(bus_output_enable),
			.memory_rdata	(memory_rdata[7:0]),
			.memory_done	(memory_done),
			// Inputs
			.clk		(clk),
			.rst_n		(rst_n),
			.bus_handshake_ack(bus_handshake_ack),
			.bus_data_in	(bus_data_in[7:0]),
			.memory_read	(memory_read),
			.memory_write	(memory_write),
			.memory_addr	(memory_addr[15:0]),
			.memory_wdata	(memory_wdata[7:0]));

	cpu cpu_i(/*AUTOINST*/
		  // Outputs
		  .memory_read		(memory_read),
		  .memory_write		(memory_write),
		  .memory_addr		(memory_addr[15:0]),
		  .memory_wdata		(memory_wdata[7:0]),
		  .cpu_halted		(cpu_halted),
		  // Inputs
		  .clk			(clk),
		  .rst_n		(rst_n),
		  .memory_rdata		(memory_rdata[7:0]),
		  .memory_done		(memory_done));

endmodule
