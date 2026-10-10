/* Decodificador de la ALU
----------------------------------------------------------------------
Recibe ALUop junto con funct3 y el bit 30 de la instruccion (funct7[5]), 
y genera el codigo i_alu_ctrl que entiende la ALU.
----------------------------------------------------------------------
| i_alu_op | Instrucciones             | o_alu_ctrl
----------------------------------------------------------------------
|   000    | cargas, stores, jalr      | 0000 (ADD, calcula direccion)
|   001    | beq, bne                  | 1000 (SUB, compara con Zero)
|   010    | tipo R                    | {funct7[5], funct3}
|   011    | tipo I aritmetico         | funct3 == 101 ? {funct7[5], funct3} : {0, funct3}
|   100    | lui                       | 1111 (PASS_B)
----------------------------------------------------------------------
*/

module alu_control
#(
    parameter NB_ALUOP   = 3 ,
    parameter NB_ALUCTRL = 4
)
(
    input  wire [NB_ALUOP - 1 : 0]   i_alu_op   ,
    input  wire [2 : 0]              i_funct3   ,
    input  wire                      i_funct7_5 ,
    output wire [NB_ALUCTRL - 1 : 0] o_alu_ctrl
);

localparam OP_ADD    = 3'b000;
localparam OP_SUB    = 3'b001;
localparam OP_R      = 3'b010;
localparam OP_I      = 3'b011;
localparam OP_PASS_B = 3'b100;

localparam CTRL_ADD    = 4'b0000;
localparam CTRL_SUB    = 4'b1000;
localparam CTRL_PASS_B = 4'b1111;

localparam F3_SR = 3'b101;

reg [NB_ALUCTRL - 1 : 0] alu_ctrl;

always @(*) begin
    case (i_alu_op)
        OP_ADD:    alu_ctrl = CTRL_ADD;
        OP_SUB:    alu_ctrl = CTRL_SUB;
        OP_R:      alu_ctrl = {i_funct7_5, i_funct3};
        OP_I:      alu_ctrl = (i_funct3 == F3_SR) ? {i_funct7_5, i_funct3} : {1'b0, i_funct3};
        OP_PASS_B: alu_ctrl = CTRL_PASS_B;
        default:   alu_ctrl = CTRL_ADD;
    endcase
end

assign o_alu_ctrl = alu_ctrl;

endmodule