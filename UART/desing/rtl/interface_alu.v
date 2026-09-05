/* ----------------------------------------------------------------------
   Protocolo:
     PC -> FPGA (3 bytes, en este orden):
         byte0 = data_a               (8 bits)
         byte1 = data_b               (8 bits)
         byte2 = { 2'b00, opcode }    (opcode en LSB, 6 bits)

     FPGA -> PC (2 bytes, en este orden):
         byte0 = alu_result           (8 bits)
         byte1 = { 7'b0, carry }      (8 bits, carry en LSB)

   Estados:
     WAIT_A         - espera byte0 (i_rx_valid) -> data_a_reg
     WAIT_B         - espera byte1 (i_rx_valid) -> data_b_reg
     WAIT_OP        - espera byte2 (i_rx_valid) -> opcode_reg,
     SEND_RESULT    - pulso de o_tx_start con o_tx_data = alu_result
     WAIT_RES_DONE  - espera a que uart_tx termine (i_tx_done)
     SEND_CARRY     - pulso de o_tx_start con o_tx_data = {7'b0,carry}
     WAIT_CARRY_DONE- espera a que uart_tx termine, vuelve a WAIT_A
----------------------------------------------------------------------*/

module interface_alu
#(
    parameter NB_DATA   = 8 ,
    parameter NB_OPCODE = 6
)
(
    input  wire                   clock         ,
    input  wire                   i_rst_n       ,
    input  wire [NB_DATA - 1 : 0] i_rx_data     ,
    input  wire                   i_rx_valid    ,
    input  wire                   i_tx_done     ,

    output reg  [NB_DATA - 1 : 0] o_tx_data     ,
    output reg                    o_tx_start    ,
    output wire [NB_DATA - 1 : 0] o_alu_result  ,
    output wire                   o_alu_carry
);

localparam WAIT_A          = 3'd0;
localparam WAIT_B          = 3'd1;
localparam WAIT_OP         = 3'd2;
localparam SEND_RESULT     = 3'd3;
localparam WAIT_RES_DONE   = 3'd4;
localparam SEND_CARRY      = 3'd5;
localparam WAIT_CARRY_DONE = 3'd6;

reg [2:0]                 state_reg    , state_next    ;
reg [NB_DATA - 1 : 0]     data_a_reg   , data_a_next   ;
reg [NB_DATA - 1 : 0]     data_b_reg   , data_b_next   ;
reg [NB_OPCODE - 1 : 0]   opcode_reg   , opcode_next   ;


always @(posedge clock) begin
    if (!i_rst_n) begin
        state_reg  <= WAIT_A;
        data_a_reg <= {NB_DATA{1'b0}};
        data_b_reg <= {NB_DATA{1'b0}};
        opcode_reg <= {NB_OPCODE{1'b0}};
    end else begin
        state_reg  <= state_next;
        data_a_reg <= data_a_next;
        data_b_reg <= data_b_next;
        opcode_reg <= opcode_next;
    end
end


always @(*) begin
    state_next  = state_reg;
    data_a_next = data_a_reg;
    data_b_next = data_b_reg;
    opcode_next = opcode_reg;
    o_tx_data   = {NB_DATA{1'b0}};
    o_tx_start  = 1'b0;

    case (state_reg)

        WAIT_A: begin
            if (i_rx_valid) begin
                data_a_next = i_rx_data;
                state_next  = WAIT_B;
            end
        end

        WAIT_B: begin
            if (i_rx_valid) begin
                data_b_next = i_rx_data;
                state_next  = WAIT_OP;
            end
        end

        WAIT_OP: begin
            if (i_rx_valid) begin
                opcode_next = i_rx_data[NB_OPCODE - 1 : 0];
                state_next  = SEND_RESULT;
            end
        end

        SEND_RESULT: begin
            o_tx_data  = o_alu_result;
            o_tx_start = 1'b1; 
            state_next = WAIT_RES_DONE;
        end

        WAIT_RES_DONE: begin
            if (i_tx_done) begin
                state_next = SEND_CARRY;
            end
        end

        SEND_CARRY: begin
            o_tx_data  = {{(NB_DATA-1){1'b0}}, o_alu_carry};
            o_tx_start = 1'b1;
            state_next = WAIT_CARRY_DONE;
        end

        WAIT_CARRY_DONE: begin
            if (i_tx_done) begin
                state_next = WAIT_A;
            end
        end

        default: begin
            state_next = WAIT_A;
        end

    endcase
end

// -------------------------------------------------------------
//                       ALU
// -------------------------------------------------------------
alu #(
    .NB_DATA   (NB_DATA)   ,
    .NB_OPCODE (NB_OPCODE)
) u_alu (
    .i_data_a     (data_a_reg)   ,
    .i_data_b     (data_b_reg)   ,
    .i_op_code    (opcode_reg)   ,
    .o_alu_result (o_alu_result) ,
    .o_carry      (o_alu_carry)
);

endmodule