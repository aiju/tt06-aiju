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

	reg [3:0] memory_state;
	localparam MEMORY_IDLE = 0;
	localparam MEMORY_ADDR_LOW = 1;
	localparam MEMORY_ADDR_HIGH = 2;
	localparam MEMORY_DATA = 3;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			memory_state <= MEMORY_IDLE;
			memory_rdata <= 8'bx;
			bus_handshake_req <= 1'b0;
			memory_done <= 1'b0;
		end else begin
			memory_done <= 1'b0;
			if(memory_state == MEMORY_IDLE && !memory_done && (memory_read || memory_write))
				memory_state <= MEMORY_ADDR_LOW;
			if(memory_state != MEMORY_IDLE && !bus_handshake_ack)
				bus_handshake_req <= 1'b1;
			if(bus_handshake_req && bus_handshake_ack) begin
				bus_handshake_req <= 1'b0;
				case(memory_state)
				MEMORY_ADDR_LOW:
					memory_state <= MEMORY_ADDR_HIGH;
				MEMORY_ADDR_HIGH:
					memory_state <= MEMORY_DATA;
				MEMORY_DATA: begin
					memory_state <= MEMORY_IDLE;
					memory_done <= 1'b1;
					if(memory_read)
						memory_rdata <= bus_data_in;
				end
				endcase
			end
		end
	end

	always @(*) begin
		bus_output_enable = 1'b0;
		bus_data_out = 8'bx;
		bus_state = 2'b00;
		case(memory_state)
		MEMORY_ADDR_LOW: begin
			bus_output_enable = 1'b1;
			bus_data_out = memory_addr[7:0];
			bus_state = 2'b00;
		end
		MEMORY_ADDR_HIGH: begin
			bus_output_enable = 1'b1;
			bus_data_out = memory_addr[15:8];
			bus_state = 2'b01;
		end
		MEMORY_DATA: begin
			bus_state = {1'b1, memory_write};
			if(memory_write) begin
				bus_output_enable = 1'b1;
				bus_data_out = memory_wdata;
			end
		end
		endcase
	end

endmodule
