/* ----------------------------------------------------------------------
   Recibe un frame: 1 start bit (0), NB_DATA bits de
   datos (LSB primero), 1 stop bit (1).

   Estados:
     IDLE  - espera i_rx en 0 (posible start bit)
     START - espera OVERSAMPLE/2 ticks y re-chequea que i_rx siga en 0
     DATA  - cada OVERSAMPLE ticks, mete 1 bit nuevo por la izquierda
             del shift register y descarta el mas viejo por la derecha.
             Como el primer bit que llega es el LSB, al terminar de
             desplazar NB_DATA veces el dato queda ordenado correcto.
     STOP  - espera OVERSAMPLE ticks mas (deberia estar en 1) y levanta
             o_valid por 1 ciclo de clock.
---------------------------------------------------------------------- */

module uart_rx
#(
    parameter NB_DATA    = 8  ,
    parameter OVERSAMPLE = 16
)
(
    input  wire                   clock         ,
    input  wire                   i_rst_n       ,
    input  wire                   i_tick        , 
    input  wire                   i_rx          , 

    output wire [NB_DATA - 1 : 0] o_data        ,
    output wire                   o_valid   
);

localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;

localparam NB_TICK_CNT = $clog2(OVERSAMPLE);
localparam NB_BIT_CNT  = $clog2(NB_DATA);

// i_rx viene de un pin externo, generada por otro dispositivo 
// (una PC, un módulo USB-serial, otro microcontrolador), 
// es asincrona respecto a "clock", y puede cambiar justo en el  
// flanco de muestreo, generando metaestabilidadm en rx_sync_0. 
// Un segundo flip-flop (rx_sync_1) le da un ciclo extra
// para que ese valor se resuelva antes de usarlo en la FSM.

// registros de sincronizacion
reg rx_sync_0, rx_sync_1;

always @(posedge clock) begin
    if (!i_rst_n) begin
        rx_sync_0 <= 1'b1;
        rx_sync_1 <= 1'b1;
    end else begin
        rx_sync_0 <= i_rx;
        rx_sync_1 <= rx_sync_0;
    end
end

reg [1:0]                 state_reg     , state_next    ;
reg [NB_BIT_CNT - 1 : 0]  bit_cnt_reg   , bit_cnt_next  ;
reg [NB_TICK_CNT - 1 : 0] tick_cnt_reg  , tick_cnt_next ;
reg [NB_DATA - 1 : 0]     data_reg      , data_next     ;
reg                       valid_reg     , valid_next    ;

always @(posedge clock) begin
    if (!i_rst_n) begin
        state_reg    <= IDLE;
        bit_cnt_reg  <= {NB_BIT_CNT{1'b0}};
        tick_cnt_reg <= {NB_TICK_CNT{1'b0}};
        data_reg     <= {NB_DATA{1'b0}};
        valid_reg    <= 1'b0;
    end else begin
        state_reg    <= state_next;
        bit_cnt_reg  <= bit_cnt_next;
        tick_cnt_reg <= tick_cnt_next;
        data_reg     <= data_next;
        valid_reg    <= valid_next;
    end
end


always @(*) begin

    state_next    = state_reg;
    bit_cnt_next  = bit_cnt_reg;
    tick_cnt_next = tick_cnt_reg;
    data_next     = data_reg;
    valid_next    = 1'b0;

    case (state_reg)

        IDLE: begin
            if (rx_sync_1 == 1'b0) begin 
                state_next    = START;
                tick_cnt_next = {NB_TICK_CNT{1'b0}};
            end
        end

        START: begin
            if (i_tick) begin
                if (tick_cnt_reg == (OVERSAMPLE/2 - 1)) begin
                    if (rx_sync_1 == 1'b0) begin
                        tick_cnt_next = {NB_TICK_CNT{1'b0}};
                        bit_cnt_next  = {NB_BIT_CNT{1'b0}};
                        state_next    = DATA;
                    end else begin
                        state_next = IDLE; // era ruido
                    end
                end else begin
                    tick_cnt_next = tick_cnt_reg + 1'b1;
                end
            end
        end

        DATA: begin
            if (i_tick) begin
                if (tick_cnt_reg == OVERSAMPLE - 1) begin
                    tick_cnt_next = {NB_TICK_CNT{1'b0}};
                    data_next     = {rx_sync_1, data_reg[NB_DATA - 1 : 1]};

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
            if (i_tick) begin
                if (tick_cnt_reg == OVERSAMPLE - 1) begin
                    tick_cnt_next = {NB_TICK_CNT{1'b0}};
                    valid_next    = 1'b1; 
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

assign o_data  = data_reg;
assign o_valid = valid_reg;

endmodule