/* ---------------------------------------------------------------------
   Arma un frame: 1 start bit (0), NB_DATA bits de
   datos (LSB primero), 1 stop bit (1), y lo va sacando por o_tx
   bit a bit, sincronizado con i_tick.

   Estados:
     IDLE  - o_tx en reposo (1). Espera i_tx_start.
             Al llegar, carga i_data en el shift register y arranca
             el start bit (o_tx <= 0) en el mismo ciclo.
     START - mantiene o_tx en 0 durante 1 bit-time completo.
     DATA  - saca data_reg[0] por o_tx, y cada bit-time desplaza el
             shift register a la derecha (data_reg >>= 1) para sacar
             el siguiente bit. Se repite NB_DATA veces.
     STOP  - pone o_tx en 1 durante 1 bit-time y levanta o_tx_done
             por 1 ciclo de clock al terminar.
---------------------------------------------------------------------- */

module uart_tx
#(
    parameter NB_DATA    = 8  ,
    parameter OVERSAMPLE = 16
)
(
    input  wire                   clock         ,
    input  wire                   i_rst_n       ,
    input  wire                   i_tick        , 
    input  wire                   i_tx_start    ,
    input  wire [NB_DATA - 1 : 0] i_data        ,

    output wire                   o_tx          , 
    output wire                   o_tx_done     , // pulso de 1 ciclo al terminar el frame
    output wire                   o_tx_busy       // 1 mientras esta transmitiendo
);

localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;

localparam NB_TICK_CNT = $clog2(OVERSAMPLE);
localparam NB_BIT_CNT  = $clog2(NB_DATA);

reg [1:0]                 state_reg    , state_next    ;
reg [NB_BIT_CNT - 1 : 0]  bit_cnt_reg  , bit_cnt_next  ;
reg [NB_TICK_CNT - 1 : 0] tick_cnt_reg , tick_cnt_next ;
reg [NB_DATA - 1 : 0]     data_reg     , data_next     ;
reg                       tx_reg       , tx_next       ;
reg                       done_reg     , done_next     ;


always @(posedge clock) begin
    if (!i_rst_n) begin
        state_reg    <= IDLE;
        bit_cnt_reg  <= {NB_BIT_CNT{1'b0}};
        tick_cnt_reg <= {NB_TICK_CNT{1'b0}};
        data_reg     <= {NB_DATA{1'b0}};
        tx_reg       <= 1'b1; 
        done_reg     <= 1'b0;
    end else begin
        state_reg    <= state_next;
        bit_cnt_reg  <= bit_cnt_next;
        tick_cnt_reg <= tick_cnt_next;
        data_reg     <= data_next;
        tx_reg       <= tx_next;
        done_reg     <= done_next;
    end
end


always @(*) begin
    state_next    = state_reg;
    bit_cnt_next  = bit_cnt_reg;
    tick_cnt_next = tick_cnt_reg;
    data_next     = data_reg;
    tx_next       = tx_reg;
    done_next     = 1'b0;

    case (state_reg)

        IDLE: begin
            tx_next = 1'b1;
            if (i_tx_start) begin
                data_next     = i_data;
                tick_cnt_next = {NB_TICK_CNT{1'b0}};
                tx_next       = 1'b0; 
                state_next    = START;
            end
        end

        START: begin
            tx_next = 1'b0;
            if (i_tick) begin
                if (tick_cnt_reg == OVERSAMPLE - 1) begin
                    tick_cnt_next = {NB_TICK_CNT{1'b0}};
                    bit_cnt_next  = {NB_BIT_CNT{1'b0}};
                    state_next    = DATA;
                end else begin
                    tick_cnt_next = tick_cnt_reg + 1'b1;
                end
            end
        end

        DATA: begin
            tx_next = data_reg[0];
            if (i_tick) begin
                if (tick_cnt_reg == OVERSAMPLE - 1) begin
                    tick_cnt_next = {NB_TICK_CNT{1'b0}};
                    data_next     = {1'b0, data_reg[NB_DATA - 1 : 1]}; 

                    if (bit_cnt_reg == NB_DATA - 1) begin
                        state_next = STOP;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1'b1;
                    end
                end else begin
                    tick_cnt_next = tick_cnt_reg + 1'b1;
                end
            end
        end

        STOP: begin
            tx_next = 1'b1;
            if (i_tick) begin
                if (tick_cnt_reg == OVERSAMPLE - 1) begin
                    tick_cnt_next = {NB_TICK_CNT{1'b0}};
                    done_next     = 1'b1;
                    state_next    = IDLE;
                end else begin
                    tick_cnt_next = tick_cnt_reg + 1'b1;
                end
            end
        end

        default: begin
            state_next = IDLE;
        end

    endcase
end

assign o_tx      = tx_reg;
assign o_tx_done = done_reg;
assign o_tx_busy = (state_reg != IDLE);

endmodule