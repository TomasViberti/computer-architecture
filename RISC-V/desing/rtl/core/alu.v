/* ALU RISC-V (RV32I)
----------------------------------------------------------------------
| Operacion |  i_alu_ctrl  |  Resultado
----------------------------------------------------------------------
|  ADD      |    0000      |  a + b
|  SLL      |    0001      |  a << b[4:0]
|  SLT      |    0010      |  (a < b) con signo ? 1 : 0
|  SLTU     |    0011      |  (a < b) sin signo ? 1 : 0
|  XOR      |    0100      |  a ^ b
|  SRL      |    0101      |  a >> b[4:0]            (logico)
|  OR       |    0110      |  a | b
|  AND      |    0111      |  a & b
|  SUB      |    1000      |  a - b
|  SRA      |    1101      |  a >>> b[4:0]           (aritmetico)
|  PASS_B   |    1111      |  b                      (usado por lui)
----------------------------------------------------------------------
*/

module alu
#(
    parameter NB_DATA    = 32 ,
    parameter NB_ALUCTRL = 4
)
(
    input  wire [NB_DATA - 1 : 0]    i_data_a       ,
    input  wire [NB_DATA - 1 : 0]    i_data_b       ,
    input  wire [NB_ALUCTRL - 1 : 0] i_alu_ctrl     ,
    output wire [NB_DATA - 1 : 0]    o_alu_result   ,
    output wire                      o_zero
);

localparam SHIFT_WIDTH = $clog2(NB_DATA);

localparam ADD    = 4'b0000;
localparam SLL    = 4'b0001;
localparam SLT    = 4'b0010;
localparam SLTU   = 4'b0011;
localparam XOR    = 4'b0100;
localparam SRL    = 4'b0101;
localparam OR     = 4'b0110;
localparam AND    = 4'b0111;
localparam SUB    = 4'b1000;
localparam SRA    = 4'b1101;
localparam PASS_B = 4'b1111;

reg  [NB_DATA - 1 : 0] alu_result;

wire signed [NB_DATA - 1 : 0] data_a_signed = i_data_a;
wire signed [NB_DATA - 1 : 0] data_b_signed = i_data_b;
wire        [SHIFT_WIDTH - 1 : 0] shamt     = i_data_b[SHIFT_WIDTH - 1 : 0];

always @(*) begin
    case (i_alu_ctrl)
        ADD:    alu_result = i_data_a + i_data_b;
        SUB:    alu_result = i_data_a - i_data_b;
        AND:    alu_result = i_data_a & i_data_b;
        OR:     alu_result = i_data_a | i_data_b;
        XOR:    alu_result = i_data_a ^ i_data_b;
        SLL:    alu_result = i_data_a << shamt;
        SRL:    alu_result = i_data_a >> shamt;
        SRA:    alu_result = data_a_signed >>> shamt;
        SLT:    alu_result = {{(NB_DATA - 1){1'b0}}, (data_a_signed < data_b_signed)};
        SLTU:   alu_result = {{(NB_DATA - 1){1'b0}}, (i_data_a < i_data_b)};
        PASS_B: alu_result = i_data_b;
        default: alu_result = {NB_DATA{1'b0}};
    endcase
end

assign o_alu_result = alu_result;
assign o_zero       = (alu_result == {NB_DATA{1'b0}});

endmodule