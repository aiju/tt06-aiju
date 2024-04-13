`default_nettype none

module bus_if(
    input wire clk,
    input wire rst_n,

    input wire bus_handshake_ack,
    output reg bus_handshake_req,
	output reg [1:0] bus_state,
	input wire [7:0] bus_data_in,
	output reg [7:0] bus_data_out,
	output reg bus_output_enable,

    input wire memory_read,
    input wire memory_write,
    input wire [15:0] memory_addr,
    input wire [7:0] memory_wdata,
    output reg [7:0] memory_rdata,
    output reg memory_done
);

	reg handshake_valid, handshake_ready;
	reg handshake_state;
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			handshake_ready <= 1'b0;
			handshake_state <= 1'b0;
			bus_handshake_req <= 1'b0;
		end else begin
			handshake_ready <= 1'b0;
			if(!handshake_state) begin
				if(!bus_handshake_ack) begin
					handshake_state <= 1'b1;
				end
			end else begin
				if(handshake_valid) begin
					bus_handshake_req <= 1'b1;
				end
				if(bus_handshake_req && bus_handshake_ack) begin
					handshake_ready <= 1'b1;
					bus_handshake_req <= 1'b0;
					handshake_state <= 1'b0;
				end
			end
		end
	end

	reg [3:0] memory_state, memory_state_nxt;
	localparam MEMORY_IDLE = 0;
	localparam MEMORY_ADDR_LOW = 1;
	localparam MEMORY_ADDR_HIGH = 2;
	localparam MEMORY_DATA = 3;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			memory_state <= MEMORY_IDLE;
			memory_rdata <= 8'bx;
		end else begin
			memory_state <= memory_state_nxt;
			if(bus_handshake_req && bus_handshake_ack && memory_state == MEMORY_DATA && memory_read) begin
				memory_rdata <= bus_data_in;
			end
		end
	end

	always @(*) begin
		memory_state_nxt = memory_state;
		bus_output_enable = 1'b0;
		bus_data_out= 8'bx;
		handshake_valid = 1'b0;
		memory_done = 1'b0;
		bus_state = 2'b00;
		case(memory_state)
		MEMORY_IDLE: begin
			if(memory_read || memory_write) begin
				memory_state_nxt = MEMORY_ADDR_LOW;
			end
		end
		MEMORY_ADDR_LOW: begin
			handshake_valid = 1'b1;
			bus_output_enable = 1'b1;
			bus_data_out = memory_addr[7:0];
			bus_state = 2'b00;
			if(handshake_ready) begin
				memory_state_nxt = MEMORY_ADDR_HIGH;
			end
		end
		MEMORY_ADDR_HIGH: begin
			handshake_valid = 1'b1;
			bus_output_enable = 1'b1;
			bus_data_out = memory_addr[15:8];
			bus_state = 2'b01;
			if(handshake_ready) begin
				memory_state_nxt = MEMORY_DATA;
			end
		end
		MEMORY_DATA: begin
			handshake_valid = 1'b1;
			bus_state = {1'b1, memory_write};
			if(memory_write) begin
				bus_output_enable = 1'b1;
				bus_data_out = memory_wdata;
			end
			if(handshake_ready) begin
				memory_done = 1'b1;
				memory_state_nxt = MEMORY_IDLE;
			end
		end
		endcase
	end

endmodule
