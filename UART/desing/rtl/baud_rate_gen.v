
module baud_rate_gen
#(
    parameter CLK_FREQ  = 50_000_000 ,
    parameter BAUD_RATE = 9600       ,
    parameter OVERSAMPLE = 16        ,
    parameter COUNT_MAX = CLK_FREQ / (BAUD_RATE * OVERSAMPLE)
)
(
    input  wire clock    ,
    input  wire i_rst_n  ,
    output reg  o_tick
);

localparam NB_COUNT = $clog2(COUNT_MAX);

reg [NB_COUNT - 1 : 0] count;

always @(posedge clock) begin
    if (!i_rst_n) begin
        count  <= {NB_COUNT{1'b0}};
        o_tick <= 1'b0;
    end else begin
        if (count == COUNT_MAX - 1) begin
            count  <= {NB_COUNT{1'b0}};
            o_tick <= 1'b1;
        end else begin
            count  <= count + 1'b1;
            o_tick <= 1'b0;
        end
    end
end

endmodule
