/* ----------------------------------------------------------------------
   Top UART loopback Tx to Rx
---------------------------------------------------------------------- */

module top_uart_loopback
#(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD_RATE  = 9600,
    parameter OVERSAMPLE = 16,
    parameter NB_DATA    = 8
)
(
    input  wire                     clock,
    input  wire                     i_rst_n,
    input  wire [NB_DATA - 1 : 0]   i_tx_data,
    input  wire                     i_tx_start,

    output wire [NB_DATA - 1 : 0]   o_data,
    output wire                     o_valid,
    output wire                     o_tx_busy
);

wire i_tick ;
wire i_rx   ;

/* ---------------------------------------------------------------
   Baud rate generator
   --------------------------------------------------------------- */
baud_rate_gen
#(
    .CLK_FREQ   (CLK_FREQ),
    .BAUD_RATE  (BAUD_RATE),
    .OVERSAMPLE (OVERSAMPLE)
)
u_baud_rate_gen
(
    .clock  (clock),
    .i_rst_n(i_rst_n),
    .o_tick (i_tick)
);

/* ----------------------------------------------------------------
   UART transmitter
   --------------------------------------------------------------- */
uart_tx
#(
    .NB_DATA    (NB_DATA),
    .OVERSAMPLE (OVERSAMPLE)
)
u_uart_tx
(
    .clock      (clock),
    .i_rst_n    (i_rst_n),
    .i_tick     (i_tick),
    .i_tx_start (i_tx_start),
    .i_data     (i_tx_data),
    .o_tx       (i_rx),
    .o_tx_done  (),
    .o_tx_busy  (o_tx_busy)
);

/* ---------------------------------------------------------------
   UART receiver
--------------------------------------------------------------- */
uart_rx
#(
    .NB_DATA    (NB_DATA),
    .OVERSAMPLE (OVERSAMPLE)
)
u_uart_rx
(
    .clock  (clock),
    .i_rst_n(i_rst_n),
    .i_tick (i_tick),
    .i_rx   (i_rx),
    .o_data (o_data),
    .o_valid(o_valid)
);

endmodule