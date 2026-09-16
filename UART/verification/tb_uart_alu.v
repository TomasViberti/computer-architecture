`timescale 1ns/1ps
`default_nettype none

module tb_uart_alu;

localparam CLK_FREQ   = 50_000_000;
localparam BAUD_RATE  = 625_000;
localparam OVERSAMPLE = 16;
localparam NB_DATA    = 8;
localparam NB_OPCODE  = 6;
localparam BIT_TIME   = 1600;

// Opcode definitions. These values must match alu.v.
localparam ADD = 6'b100000;
localparam SUB = 6'b100010;
localparam AND = 6'b100100;
localparam OR  = 6'b100101;
localparam XOR = 6'b100110;
localparam SRA = 6'b000011;
localparam SRL = 6'b000010;
localparam NOR = 6'b100111;

reg  clock   = 1'b0;
reg  rst_n   = 1'b0;
reg  pc_tx_line = 1'b1;

wire fpga_tx_line;

// Top-level DUT instance.
top_uart_alu #(
    .CLK_FREQ  (CLK_FREQ)  ,
    .BAUD_RATE (BAUD_RATE) ,
    .NB_DATA   (NB_DATA)   ,
    .NB_OPCODE (NB_OPCODE)
) dut (
    .clock   (clock)       ,
    .i_rst_n (rst_n)       ,
    .i_rx    (pc_tx_line)  ,
    .o_tx    (fpga_tx_line)
);

// PC-side baud generator used to sample the FPGA response.
wire tick_pc;
wire [NB_DATA - 1 : 0] pc_rx_data;
wire                   pc_rx_valid;

baud_rate_gen #(
    .CLK_FREQ   (CLK_FREQ)  ,
    .BAUD_RATE  (BAUD_RATE) ,
    .OVERSAMPLE (OVERSAMPLE)
) u_baud_pc (
    .clock   (clock)   ,
    .i_rst_n (rst_n)   ,
    .o_tick  (tick_pc)
);

uart_rx #(
    .NB_DATA    (NB_DATA)   ,
    .OVERSAMPLE (OVERSAMPLE)
) u_pc_rx (
    .clock   (clock)       ,
    .i_rst_n (rst_n)       ,
    .i_tick  (tick_pc)     ,
    .i_rx    (fpga_tx_line),
    .o_data  (pc_rx_data)  ,
    .o_valid (pc_rx_valid)
);

// Clock generation: 50 MHz.
always #10 clock = ~clock;

// Captured response bytes from the FPGA.
reg [7:0] response_bytes [0:1];
integer   response_count = 0;
integer   errors = 0;

// Returns the expected ALU result for the selected opcode.
function automatic [NB_DATA - 1 : 0] expected_result;
    input [NB_DATA - 1 : 0]   data_a;
    input [NB_DATA - 1 : 0]   data_b;
    input [NB_OPCODE - 1 : 0] opcode;
    reg   [NB_DATA : 0]       wide_result;
    begin
        case (opcode)
            ADD: begin
                wide_result     = {1'b0, data_a} + {1'b0, data_b};
                expected_result = wide_result[NB_DATA - 1 : 0];
            end
            SUB: begin
                wide_result     = {1'b0, data_a} - {1'b0, data_b};
                expected_result = wide_result[NB_DATA - 1 : 0];
            end
            AND: expected_result = data_a & data_b;
            OR : expected_result = data_a | data_b;
            XOR: expected_result = data_a ^ data_b;
            SRA: expected_result = $signed(data_a) >>> data_b;
            SRL: expected_result = data_a >> data_b;
            NOR: expected_result = ~(data_a | data_b);
            default: expected_result = {NB_DATA{1'b0}};
        endcase
    end
endfunction

// Returns the expected carry for ADD and SUB, or zero for the rest.
function automatic expected_carry;
    input [NB_DATA - 1 : 0]   data_a;
    input [NB_DATA - 1 : 0]   data_b;
    input [NB_OPCODE - 1 : 0] opcode;
    reg   [NB_DATA : 0]       wide_result;
    begin
        case (opcode)
            ADD: begin
                wide_result   = {1'b0, data_a} + {1'b0, data_b};
                expected_carry = wide_result[NB_DATA];
            end
            SUB: begin
                wide_result   = {1'b0, data_a} - {1'b0, data_b};
                expected_carry = wide_result[NB_DATA];
            end
            default: expected_carry = 1'b0;
        endcase
    end
endfunction

// Applies reset and leaves the design ready for the first transaction.
task automatic apply_reset;
    begin
        rst_n      = 1'b0;
        pc_tx_line = 1'b1;
        response_count = 0;
        repeat (2) @(posedge clock);
        #1;
        rst_n = 1'b1;
        @(posedge clock);
        #1;
    end
endtask

// Sends one byte from the emulated PC to the FPGA over the serial line.
task automatic pc_send_byte(input [7:0] data);
    integer i;
    begin
        pc_tx_line = 1'b0;
        #(BIT_TIME);
        for (i = 0; i < 8; i = i + 1) begin
            pc_tx_line = data[i];
            #(BIT_TIME);
        end
        pc_tx_line = 1'b1;
        #(BIT_TIME);
    end
endtask

// Sends a complete ALU transaction: A, B and opcode.
task automatic run_alu_transaction(
    input [7:0] data_a,
    input [7:0] data_b,
    input [5:0] opcode
);
    begin
        response_count = 0;
        response_bytes[0] = 8'h00;
        response_bytes[1] = 8'h00;

        pc_send_byte(data_a);
        pc_send_byte(data_b);
        pc_send_byte({2'b00, opcode});

        wait (response_count == 2);
        #(BIT_TIME);
    end
endtask

// Compares the captured response against the expected result and carry.
task automatic check_response(
    input [7:0]               data_a,
    input [7:0]               data_b,
    input [5:0]               opcode,
    input [NB_DATA - 1 : 0]   expected_data,
    input                     expected_carry_value,
    input [8*64 - 1 : 0]      test_name
);
    begin
        if (response_bytes[0] !== expected_data) begin
            $display("ERROR [%0s] result expected=0x%0h received=0x%0h (A=0x%0h B=0x%0h OP=%b)",
                     test_name, expected_data, response_bytes[0], data_a, data_b, opcode);
            errors = errors + 1;
        end else if (response_bytes[1][0] !== expected_carry_value || response_bytes[1][7:1] !== 7'b0) begin
            $display("ERROR [%0s] carry byte expected=0x%0h received=0x%0h", test_name, {7'b0, expected_carry_value}, response_bytes[1]);
            errors = errors + 1;
        end else begin
            $display("OK [%0s] A=0x%0h B=0x%0h -> result=0x%0h carry=%0b", test_name, data_a, data_b, response_bytes[0], response_bytes[1][0]);
        end
    end
endtask

// Builds the expected values for the active transaction and checks them.
task automatic check_transaction(
    input [7:0]               data_a,
    input [7:0]               data_b,
    input [5:0]               opcode,
    input [8*64 - 1 : 0]      test_name
);
    reg [NB_DATA - 1 : 0] expected_data;
    reg                   expected_carry_value;
    begin
        expected_data        = expected_result(data_a, data_b, opcode);
        expected_carry_value = expected_carry(data_a, data_b, opcode);
        check_response(data_a, data_b, opcode, expected_data, expected_carry_value, test_name);
    end
endtask

// Captures the response bytes as soon as the PC-side receiver validates them.
always @(posedge clock) begin
    if (pc_rx_valid) begin
        if (response_count < 2) begin
            response_bytes[response_count] = pc_rx_data;
            response_count = response_count + 1;
        end
    end
end

// Generates the waveform dump for simulation analysis.
initial begin
    $dumpfile("tb_uart_alu.vcd");
    $dumpvars(0, tb_uart_alu);
end

// Select the active test one by one.
//`include "tests/uart_alu/test1.sv"
//`include "tests/uart_alu/test2.sv"
//`include "tests/uart_alu/test3.sv"
//`include "tests/uart_alu/test4.sv"
//`include "tests/uart_alu/test5.sv"
//`include "tests/uart_alu/test6.sv"
//`include "tests/uart_alu/test7.sv"
//`include "tests/uart_alu/test8.sv"

endmodule