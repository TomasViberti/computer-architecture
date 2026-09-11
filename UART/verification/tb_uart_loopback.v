`timescale 1ns/1ps
`default_nettype none

module tb_uart_loopback;

localparam CLK_FREQ   = 50_000_000;
localparam BAUD_RATE  = 625_000;
localparam OVERSAMPLE = 16;
localparam NB_DATA    = 8;
localparam BIT_TIME   = 1600;

reg                   clock   = 1'b0;
reg                   rst_n   = 1'b0;
reg  [NB_DATA - 1 : 0] tx_data = {NB_DATA{1'b0}};
reg                   tx_start = 1'b0;

wire [NB_DATA - 1 : 0] rx_data;
wire                  rx_valid;
wire                  tx_busy;

// Top-level DUT instance.
top_uart_loopback #(
    .CLK_FREQ   (CLK_FREQ)  ,
    .BAUD_RATE  (BAUD_RATE) ,
    .OVERSAMPLE (OVERSAMPLE),
    .NB_DATA    (NB_DATA)
) u_top_uart_loopback (
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

integer errors     = 0;
integer sent_count  = 0;
integer recv_count  = 0;
integer i;
reg [7:0] sent_bytes [0:31];

// Applies reset and clears the verification counters.
task automatic apply_reset;
    integer j;
    begin
        rst_n    = 1'b0;
        tx_start = 1'b0;
        tx_data  = {NB_DATA{1'b0}};
        sent_count = 0;
        recv_count = 0;
        for (j = 0; j < 32; j = j + 1) begin
            sent_bytes[j] = 8'h00;
        end
        repeat (2) @(posedge clock);
        #1;
        rst_n = 1'b1;
        @(posedge clock);
        #1;
    end
endtask

// Starts a UART transmission from the loopback input side.
task automatic send_byte(input [7:0] data);
    begin
        sent_bytes[sent_count] = data;
        sent_count = sent_count + 1;

        @(posedge clock); #1;
        tx_data  = data;
        tx_start = 1'b1;
        @(posedge clock); #1;
        tx_start = 1'b0;

        wait (tx_busy == 1'b0);
        @(posedge clock); #1;
    end
endtask

// Checks each received byte against the transmitted reference stream.
always @(posedge clock) begin
    if (rx_valid) begin
        if (rx_data !== sent_bytes[recv_count]) begin
            $display("ERROR: byte #%0d expected=0x%0h received=0x%0h", recv_count, sent_bytes[recv_count], rx_data);
            errors = errors + 1;
        end else begin
            $display("OK: byte #%0d (0x%0h) received correctly via loopback", recv_count, rx_data);
        end
        recv_count = recv_count + 1;
    end
end

// Waits until all transmitted bytes have been received by the UART receiver.
task automatic wait_for_all_bytes(input integer expected_count);
    begin
        wait (recv_count == expected_count);
        #(BIT_TIME);
    end
endtask

// Generates the waveform dump for simulation analysis.
initial begin
    $dumpfile("tb_uart_loopback.vcd");
    $dumpvars(0, tb_uart_loopback);
end

// Select the active test one by one.
//`include "tests/uart_loopback/test1.sv"
//`include "tests/uart_loopback/test2.sv"
//`include "tests/uart_loopback/test3.sv"
//`include "tests/uart_loopback/test4.sv"

endmodule