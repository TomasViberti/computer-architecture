`timescale 1ns/1ps
`default_nettype none

module tb_internal_uart;

localparam CLK_FREQ   = 50_000_000;
localparam BAUD_RATE  = 625_000;
localparam OVERSAMPLE = 16;
localparam NB_DATA    = 8;
localparam BIT_TIME   = 1600;
localparam COUNT_MAX  = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
localparam NB_COUNT    = $clog2(COUNT_MAX);

localparam TX_IDLE  = 2'b00;
localparam TX_START = 2'b01;
localparam TX_DATA  = 2'b10;
localparam TX_STOP  = 2'b11;

localparam RX_IDLE  = 2'b00;
localparam RX_START = 2'b01;
localparam RX_DATA  = 2'b10;
localparam RX_STOP  = 2'b11;

reg                   clock   = 1'b0;
reg                   rst_n   = 1'b0;
reg  [NB_DATA - 1 : 0] tx_data = {NB_DATA{1'b0}};
reg                   tx_start = 1'b0;

wire [NB_DATA - 1 : 0] rx_data;
wire                   rx_valid;
wire                   tx_busy;

// Top-level DUT instance.
top_uart_loopback #(
    .CLK_FREQ   (CLK_FREQ)  ,
    .BAUD_RATE  (BAUD_RATE) ,
    .OVERSAMPLE (OVERSAMPLE),
    .NB_DATA    (NB_DATA)
) dut (
    .clock      (clock)    ,
    .i_rst_n    (rst_n)    ,
    .i_tx_data  (tx_data)  ,
    .i_tx_start (tx_start) ,
    .o_data     (rx_data)  ,
    .o_valid    (rx_valid) ,
    .o_tx_busy  (tx_busy)
);

// Clock generation: 50 MHz.
always #10 clock = ~clock;

integer errors = 0;
integer i;
integer j;
integer tick_count;
reg [7:0] tx_reference;
reg [7:0] rx_expected_shift;



// Applies reset and clears the stimulus and counters.
task automatic apply_reset;
    integer k;
    begin
        rst_n    = 1'b0;
        tx_start = 1'b0;
        tx_data  = {NB_DATA{1'b0}};
        errors   = 0;
        tx_reference = 8'h00;
        rx_expected_shift = 8'h00;
        for (k = 0; k < 32; k = k + 1) begin
            // No scoreboards persist between tests.
        end
        repeat (2) @(posedge clock);
        #1;
        rst_n = 1'b1;
        #1;
    end
endtask

// Checks one condition and stops the simulation if it fails.
task automatic check_condition(
    input [8*64 - 1 : 0] test_name,
    input [8*64 - 1 : 0] message,
    input                condition
);
    begin
        if (!condition) begin
            $display("ERROR [%0s] %0s", test_name, message);
            errors = errors + 1;
            $finish(2);
        end
    end
endtask

// Checks a bus against an expected value.
task automatic check_bus(
    input [8*64 - 1 : 0] test_name,
    input [8*64 - 1 : 0] label,
    input [NB_DATA - 1 : 0] actual,
    input [NB_DATA - 1 : 0] expected
);
    begin
        if (actual !== expected) begin
            $display("ERROR [%0s] %0s expected=0x%0h received=0x%0h", test_name, label, expected, actual);
            errors = errors + 1;
            $finish(2);
        end
    end
endtask

// Checks a single bit against an expected value.
task automatic check_bit(
    input [8*64 - 1 : 0] test_name,
    input [8*64 - 1 : 0] label,
    input                actual,
    input                expected
);
    begin
        if (actual !== expected) begin
            $display("ERROR [%0s] %0s expected=%0b received=%0b", test_name, label, expected, actual);
            errors = errors + 1;
            $finish(2);
        end
    end
endtask

// Checks the baud generator counter against an expected value.
task automatic check_count(
    input [8*64 - 1 : 0] test_name,
    input [8*64 - 1 : 0] label,
    input [NB_COUNT - 1 : 0] actual,
    input [NB_COUNT - 1 : 0] expected
);
    begin
        if (actual !== expected) begin
            $display("ERROR [%0s] %0s expected=%0d received=%0d", test_name, label, expected, actual);
            errors = errors + 1;
            $finish(2);
        end
    end
endtask

// Waits for the next baud generator tick pulse.
task automatic wait_for_next_baud_tick;
    begin
        @(posedge dut.u_baud_rate_gen.o_tick);
        @(posedge clock);
        #1;
    end
endtask

// Waits until the UART TX FSM reaches the requested state.
task automatic wait_tx_state(input [1:0] target_state);
    begin
        while (dut.u_uart_tx.state_reg !== target_state) begin
            @(posedge clock);
            #1;
        end
    end
endtask

// Waits until the UART RX FSM reaches the requested state.
task automatic wait_rx_state(input [1:0] target_state);
    begin
        while (dut.u_uart_rx.state_reg !== target_state) begin
            @(posedge clock);
            #1;
        end
    end
endtask

// Starts a transmission from the loopback input side without waiting for completion.
task automatic start_tx_frame(input [7:0] data);
    begin
        @(posedge clock);
        #1;
        tx_data  = data;
        tx_start = 1'b1;
        @(posedge clock);
        #1;
        tx_start = 1'b0;
    end
endtask

// Waits for the TX frame to complete.
task automatic wait_tx_complete;
    begin
        wait (tx_busy == 1'b0);
        @(posedge clock);
        #1;
    end
endtask

// Generates the waveform dump for simulation analysis.
initial begin
    $dumpfile("tb_internal_uart.vcd");
    $dumpvars(0, tb_internal_uart);
end

// Select the active test one by one.
//`include "tests/internal_uart/test1.sv"
//`include "tests/internal_uart/test2.sv"
`include "tests/internal_uart/test3.sv"
//`include "tests/internal_uart/test4.sv"

endmodule
