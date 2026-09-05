
module top_uart_alu
#(
    parameter CLK_FREQ   = 50_000_000 ,
    parameter BAUD_RATE  = 9600       ,
    parameter OVERSAMPLE = 16         ,
    parameter NB_DATA    = 8          ,
    parameter NB_OPCODE  = 6
)
(
    input  wire clock    ,
    input  wire i_rst_n  ,
    input  wire i_rx     , 
    output wire o_tx      
);

wire tick;

wire [NB_DATA - 1 : 0] rx_data;
wire                   rx_valid;

wire [NB_DATA - 1 : 0] tx_data;
wire                   tx_start;
wire                   tx_done;
wire                   tx_busy;

baud_rate_gen #(
    .CLK_FREQ   (CLK_FREQ)   ,
    .BAUD_RATE  (BAUD_RATE)  ,
    .OVERSAMPLE (OVERSAMPLE)
) u_baud_rate_gen (
    .clock   (clock) ,
    .i_rst_n (i_rst_n) ,
    .o_tick  (tick)
);

uart_rx #(
    .NB_DATA    (NB_DATA)   ,
    .OVERSAMPLE (OVERSAMPLE)
) u_uart_rx (
    .clock   (clock)    ,
    .i_rst_n (i_rst_n)  ,
    .i_tick  (tick)     ,
    .i_rx    (i_rx)     ,
    .o_data  (rx_data)  ,
    .o_valid (rx_valid)
);

interface_alu #(
    .NB_DATA   (NB_DATA)  ,
    .NB_OPCODE (NB_OPCODE)
) u_interface_alu (
    .clock        (clock)    ,
    .i_rst_n      (i_rst_n)  ,
    .i_rx_data    (rx_data)  ,
    .i_rx_valid   (rx_valid) ,
    .o_tx_data    (tx_data)  ,
    .o_tx_start   (tx_start) ,
    .i_tx_done    (tx_done)  ,
    .o_alu_result ()         , 
    .o_alu_carry  ()
);

uart_tx #(
    .NB_DATA    (NB_DATA)   ,
    .OVERSAMPLE (OVERSAMPLE)
) u_uart_tx (
    .clock      (clock)    ,
    .i_rst_n    (i_rst_n)  ,
    .i_tick     (tick)     ,
    .i_tx_start (tx_start) ,
    .i_data     (tx_data)  ,
    .o_tx       (o_tx)     ,
    .o_tx_done  (tx_done)  ,
    .o_tx_busy  (tx_busy)
);

endmodule