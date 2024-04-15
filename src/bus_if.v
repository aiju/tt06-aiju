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
	output wire bus_io,

    input wire memory_read,
    input wire memory_write,
    input wire [15:0] memory_addr,
	input wire memory_io,
    input wire [7:0] memory_wdata,
    output reg [7:0] memory_rdata,
    output reg memory_done
);

	reg [1:0] memory_state;
	localparam MEMORY_IDLE = 0;
	localparam MEMORY_ADDR_LOW = 1;
	localparam MEMORY_ADDR_HIGH = 2;
	localparam MEMORY_DATA = 3;

	wire want_output_enable = memory_state != MEMORY_IDLE && (memory_state != MEMORY_DATA || memory_write);

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			memory_state <= MEMORY_IDLE;
			memory_rdata <= 8'bx;
			bus_handshake_req <= 1'b0;
			memory_done <= 1'b0;
			bus_output_enable <= 1'b0;
		end else begin
			memory_done <= 1'b0;
			if(memory_state == MEMORY_IDLE && !memory_done && (memory_read || memory_write))
				memory_state <= MEMORY_ADDR_LOW;
			if(memory_state != MEMORY_IDLE && !bus_handshake_ack)
				bus_output_enable <= want_output_enable;
			if(memory_state != MEMORY_IDLE && !bus_handshake_ack && want_output_enable == bus_output_enable)
				bus_handshake_req <= 1'b1;
			if(bus_handshake_req && bus_handshake_ack) begin
				bus_handshake_req <= 1'b0;
				case(memory_state)
				MEMORY_ADDR_LOW:
					memory_state <= MEMORY_ADDR_HIGH;
				MEMORY_ADDR_HIGH: begin
					memory_state <= MEMORY_DATA;
					if(memory_read)
						bus_output_enable <= 1'b0;
				end
				MEMORY_DATA: begin
					memory_state <= MEMORY_IDLE;
					bus_output_enable <= 1'b0;
					memory_done <= 1'b1;
					if(memory_read)
						memory_rdata <= bus_data_in;
				end
				endcase
			end
		end
	end

	assign bus_io = memory_io;

	always @(*) begin
		bus_data_out = 8'bx;
		bus_state = 2'b00;
		case(memory_state)
		MEMORY_ADDR_LOW: begin
			bus_data_out = memory_addr[7:0];
			bus_state = 2'b00;
		end
		MEMORY_ADDR_HIGH: begin
			bus_data_out = memory_addr[15:8];
			bus_state = 2'b01;
		end
		MEMORY_DATA: begin
			bus_state = {1'b1, memory_write};
			if(memory_write) begin
				bus_data_out = memory_wdata;
			end
		end
		endcase
	end

`ifdef FORMAL
	initial begin
		memory_state = MEMORY_IDLE;
		memory_done = 1'b0;
		bus_handshake_req = 1'b0;
		bus_output_enable = 1'b0;
	end

	default clocking
		@(posedge clk);
	endclocking
	default disable iff(!rst_n);

	assume property (!(memory_read && memory_write));
	assume property (memory_read && !memory_done |=> memory_read);
	assume property (memory_write && !memory_done |=> memory_write);
	assume property ($rose(bus_handshake_ack) |-> $past(bus_handshake_req));
	assume property ($fell(bus_handshake_ack) |-> $past(!bus_handshake_req));
	assume property ((memory_read && $past(memory_read)) || (memory_write && $past(memory_write)) |-> $stable(memory_addr) && $stable(memory_wdata));

	state_invariant: assert property (memory_state != MEMORY_IDLE |-> (memory_read || memory_write) && !memory_done);
	done_one_cycle: assert property (memory_done |=> !memory_done);
	done_only_if_active: assert property (memory_done |-> memory_read || memory_write);
	req_only_when_active: assert property (memory_state == MEMORY_IDLE |-> !bus_handshake_req);
	req_when_no_ack: assert property ($rose(bus_handshake_req) |-> !bus_handshake_ack);
	req_falls_when_ack: assert property (!$initstate && $fell(bus_handshake_req) |-> bus_handshake_ack);
	stable_bus_state: assert property (bus_handshake_req |-> $stable(bus_state));
	no_bus_contention: assert property (bus_handshake_req && bus_state == 2'b10 |-> !bus_output_enable && !$past(bus_output_enable));
	stable_bus_data_out: assert property (bus_handshake_req && bus_state != 2'b10 |-> bus_output_enable && $past(bus_output_enable) && $stable(bus_data_out));
	latch_bus_data: assert property (memory_done && memory_read |-> memory_rdata == $past(bus_data_in));

	stable_bus_output: assert property ((bus_handshake_req || bus_handshake_ack) && !bus_output_enable |=> !bus_output_enable);
	stable_bus_output2: assert property (bus_handshake_req && !bus_output_enable |-> !$past(bus_output_enable));

`ifdef LIVENESS
	assume property(bus_handshake_req |-> ##[1:5] bus_handshake_ack);
	assume property(!bus_handshake_req |-> ##[1:5] !bus_handshake_ack);
	liveness: assert property ((memory_read || memory_write) && !memory_done |-> ##[1:40] memory_done);
`endif
`endif

endmodule
