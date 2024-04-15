/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_aiju_8080 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

	/*AUTOWIRE*/
	// Beginning of automatic wires (for undeclared instantiated-module outputs)
	wire [7:0]	bus_data_out;		// From bus_if_i of bus_if.v
	wire		bus_handshake_req;	// From bus_if_i of bus_if.v
	wire		bus_io;			// From bus_if_i of bus_if.v
	wire		bus_output_enable;	// From bus_if_i of bus_if.v
	wire [1:0]	bus_state;		// From bus_if_i of bus_if.v
	wire		cpu_fetch;		// From cpu_i of cpu.v
	wire		cpu_halted;		// From cpu_i of cpu.v
	wire		cpu_in_debug;		// From cpu_i of cpu.v
	wire		cpu_int_ack;		// From cpu_i of cpu.v
	wire [15:0]	memory_addr;		// From cpu_i of cpu.v
	wire		memory_done;		// From bus_if_i of bus_if.v
	wire		memory_io;		// From cpu_i of cpu.v
	wire [7:0]	memory_rdata;		// From bus_if_i of bus_if.v
	wire		memory_read;		// From cpu_i of cpu.v
	wire [7:0]	memory_wdata;		// From cpu_i of cpu.v
	wire		memory_write;		// From cpu_i of cpu.v
	// End of automatics

	assign uo_out[0] = bus_handshake_req;
	assign uo_out[1] = bus_state[0];
	assign uo_out[2] = bus_state[1];
	assign uo_out[3] = bus_io;
	assign uo_out[4] = cpu_fetch;
	assign uo_out[5] = cpu_in_debug;
	assign uo_out[6] = cpu_halted;
	assign uo_out[7] = cpu_int_ack;

	wire ext_bus_handshake_ack = ui_in[0];
	wire ext_debug_req = ui_in[1];
	wire ext_int_req = ui_in[2];

	wire bus_handshake_ack;
	(*keep_hierarchy*) sync bus_handshake_ack_sync(
		.clk(clk),
		.rst_n(rst_n),
		.in(ext_bus_handshake_ack),
		.out(bus_handshake_ack)
	);
	wire debug_req;
	(*keep_hierarchy*) sync debug_req_sync(
		.clk(clk),
		.rst_n(rst_n),
		.in(ext_debug_req),
		.out(debug_req)
	);
	wire int_req;
	(*keep_hierarchy*) sync int_req_sync(
		.clk(clk),
		.rst_n(rst_n),
		.in(ext_int_req),
		.out(int_req)
	);

	wire [7:0] bus_data_in = uio_in;
	assign uio_out = bus_data_out;
	assign uio_oe = {8{bus_output_enable}};

	bus_if bus_if_i(/*AUTOINST*/
			// Outputs
			.bus_handshake_req(bus_handshake_req),
			.bus_state	(bus_state[1:0]),
			.bus_data_out	(bus_data_out[7:0]),
			.bus_output_enable(bus_output_enable),
			.bus_io		(bus_io),
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
			.memory_io	(memory_io),
			.memory_wdata	(memory_wdata[7:0]));

	cpu cpu_i(/*AUTOINST*/
		  // Outputs
		  .memory_read		(memory_read),
		  .memory_write		(memory_write),
		  .memory_addr		(memory_addr[15:0]),
		  .memory_io		(memory_io),
		  .memory_wdata		(memory_wdata[7:0]),
		  .cpu_fetch		(cpu_fetch),
		  .cpu_halted		(cpu_halted),
		  .cpu_in_debug		(cpu_in_debug),
		  .cpu_int_ack		(cpu_int_ack),
		  // Inputs
		  .clk			(clk),
		  .rst_n		(rst_n),
		  .memory_rdata		(memory_rdata[7:0]),
		  .memory_done		(memory_done),
		  .debug_req		(debug_req),
		  .int_req		(int_req));

endmodule

module sync(
	input wire clk,
	input wire rst_n,
	input wire in,
	output wire out
);
	(* keep *) reg a;
	(* keep *) reg b;
	assign out = b;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			a <= 1'b0;
			b <= 1'b0;
		end else begin
			a <= in;
			b <= a;
		end
	end

endmodule
