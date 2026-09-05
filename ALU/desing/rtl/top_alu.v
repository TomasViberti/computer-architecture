`include "alu.v"

/* ---------------------------------------------------------------------
   alu_top
    ---------------------------------------------------------------------
   Arquitectura:

   SWITCHES ----+--> --botón1--> [buf_a]    +--> [alu_in_a]--+
                |                           |                |
                +--> --botón2--> [buf_b]    |--> [alu_in_b] -+--> ALU --> LEDS
                |                           |                |
                +--> --botón3--> [buf_op]   +--> [alu_in_op]-+
                                            ^
                                            |
                                        botón4 (load_alu) carga los 3 registros juntos

------------------------------------------------------------------------------------------*/

module top_alu
#(
    parameter NB_DATA   = 8                         ,
    parameter NB_OPCODE = 6                         ,
    parameter N_BOTONS  = 4 
)
(
    // Entradas
    input  wire [NB_DATA - 1 : 0]   i_switches      ,
    input  wire [N_BOTONS - 1 : 0]  i_btn_load      , 
    input  wire                     i_rst_n         , // reset activo en bajo
    input  wire                     clock           ,
    
    // Salidas
    output wire [NB_DATA - 1 : 0]   o_leds          ,
    output wire                     o_carry
);

localparam LOAD_A   = 4'b1000;
localparam LOAD_B   = 4'b0100;
localparam LOAD_OP  = 4'b0010;
localparam LOAD_ALU = 4'b0001;

reg [NB_DATA - 1 : 0]   buf_a;
reg [NB_DATA - 1 : 0]   buf_b;
reg [NB_OPCODE - 1 : 0] buf_op;

reg [NB_DATA - 1 : 0]   alu_in_a;
reg [NB_DATA - 1 : 0]   alu_in_b;
reg [NB_OPCODE - 1 : 0] alu_in_op;

always @(posedge clock) begin
    if (!i_rst_n) begin
        buf_a   <= {NB_DATA{1'b0}};
        buf_b   <= {NB_DATA{1'b0}};
        buf_op  <= {NB_OPCODE{1'b0}};

        alu_in_a  <= {NB_DATA{1'b0}};
        alu_in_b  <= {NB_DATA{1'b0}};
        alu_in_op <= {NB_OPCODE{1'b0}};
    end else begin
        case(i_btn_load)
            LOAD_A: begin
                buf_a <= i_switches;
            end

            LOAD_B: begin
                buf_b <= i_switches;
            end

            LOAD_OP: begin
                buf_op <= i_switches[NB_OPCODE - 1 : 0];
            end

            LOAD_ALU: begin
                alu_in_a  <= buf_a;
                alu_in_b  <= buf_b;
                alu_in_op <= buf_op;
            end
        endcase
    end
end


// -------------------------------------------------------------
//                          ALU
// -------------------------------------------------------------

wire [NB_DATA - 1 : 0] alu_result;
wire                   alu_carry;

alu #(
    .NB_DATA   (NB_DATA)   ,
    .NB_OPCODE (NB_OPCODE)
) u_alu (
    .i_data_a     (alu_in_a)   ,
    .i_data_b     (alu_in_b)   ,
    .i_op_code    (alu_in_op)  ,
    .o_alu_result (alu_result) ,
    .o_carry      (alu_carry)
);

assign o_leds  = alu_result;
assign o_carry = alu_carry;

endmodule