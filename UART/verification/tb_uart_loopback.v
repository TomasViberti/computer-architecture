`timescale 1ns/1ps

module tb_uart_loopback;

localparam CLK_FREQ   = 50_000_000;
localparam BAUD_RATE  = 9600;
localparam NB_DATA    = 8;

reg                   clock;
reg                   rst_n;
reg  [NB_DATA-1 : 0]  tx_data;
reg                   tx_start;

wire [NB_DATA-1 : 0]  rx_data;
wire                  rx_valid;
wire                  tx_busy;

initial clock = 0;
always #10 clock = ~clock;

top_uart #(
    .CLK_FREQ   (CLK_FREQ)  ,
    .BAUD_RATE  (BAUD_RATE) ,
    .NB_DATA    (NB_DATA)
) u_top_uart (
    .clock      (clock)    ,
    .i_rst_n    (rst_n)    ,
    .i_tx_data  (tx_data)  ,
    .i_tx_start (tx_start) ,
    .o_data     (rx_data)  ,
    .o_valid    (rx_valid) ,
    .o_tx_busy  (tx_busy)
);

integer errors     = 0;
integer sent_count = 0;
integer recv_count = 0;
integer i;
reg [7:0] sent_bytes [0:9];

task send_byte(input [7:0] data);
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


always @(posedge clock) begin
    if (rx_valid) begin
        if (rx_data !== sent_bytes[recv_count]) begin
            $display("FALLO: byte #%0d, se esperaba 0x%0h, se recibio 0x%0h", recv_count, sent_bytes[recv_count], rx_data);
            errors = errors + 1;
        end else begin
            $display("OK: byte #%0d (0x%0h) recibido correctamente via loopback", recv_count, rx_data);
        end
        recv_count = recv_count + 1;
    end
end

initial begin
    rst_n    = 0;
    tx_start = 0;
    tx_data  = 0;
    
    for(i = 0; i < 10; i = i + 1) begin
        sent_bytes[i] = 0;
    end

    #200;
    rst_n = 1;
    #200;

    send_byte(8'hA5);
    send_byte(8'h00);
    send_byte(8'hFF);
    send_byte(8'h3C);
    send_byte(8'b10100000); 
    send_byte(8'b10100101); 
    send_byte(8'h01);

    #50000;

    if (recv_count != sent_count) begin
        $display("FALLO: se enviaron %0d bytes pero solo se decodificaron %0d", sent_count, recv_count);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("TODOS LOS TESTS PASARON (%0d bytes en loopback)", sent_count);
    else
        $display("%0d TESTS FALLARON", errors);

    $finish;
end

endmodule