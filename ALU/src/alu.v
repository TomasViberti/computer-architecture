/* ALU Arithmetic and Logic Operations
----------------------------------------------------------------------
| Operation |   i_op_code    |   ALU Result 
----------------------------------------------------------------------
|  ADD      |   100000       |   o_alu_result = i_data_a + i_data_b;
----------------------------------------------------------------------
|  SUB      |   100010       |   o_alu_result = i_data_a - i_data_b;
----------------------------------------------------------------------
|  AND      |   100100       |   o_alu_result = i_data_a & i_data_b;
----------------------------------------------------------------------
|  OR       |   100101       |   o_alu_result = i_data_a | i_data_b;
----------------------------------------------------------------------
|  XOR      |   100110       |   o_alu_result = i_data_a ^ i_data_b;
----------------------------------------------------------------------
|  SRA       |   000011      |   o_alu_result = i_data_a >> 1;
----------------------------------------------------------------------
|  SRL       |   000010      |   o_alu_result = i_data_a << 1;
----------------------------------------------------------------------
|  NOR       |   100111      |   o_alu_result = ~(i_data_a | i_data_b);
----------------------------------------------------------------------*/

module alu
#(
    parameter NB_DATA   = 8       ,
    parameter NB_OPCODE = 6
)
(
    input  wire [NB_DATA - 1 : 0]   i_data_a            ,
    input  wire [NB_DATA - 1 : 0]   i_data_b            ,
    input  wire [NB_OPCODE - 1 : 0] i_op_code           ,
    output wire [NB_DATA - 1 : 0]   o_alu_result        ,
    output wire                     o_carry
);

reg [NB_DATA : 0]       result;
reg [NB_DATA - 1 : 0]   alu_result  ;
reg                     carry       ;

localparam ADD = 6'b100000;
localparam SUB = 6'b100010;
localparam AND = 6'b100100;
localparam OR  = 6'b100101;
localparam XOR = 6'b100110;
localparam SRA = 6'b000011;
localparam SRL = 6'b000010;
localparam NOR = 6'b100111;

always @(*) begin
    result     = {NB_DATA{1'b0}};
    alu_result = {NB_DATA{1'b0}};
    carry      = 1'b0;

    case (i_op_code)
        ADD: begin
            result          = {1'b0, i_data_a} + {1'b0, i_data_b};
            alu_result      = result[NB_DATA - 1 : 0];
            carry           = result[NB_DATA];
        end
        SUB: begin
            result          = {1'b0, i_data_a} - {1'b0, i_data_b};
            alu_result      = result[NB_DATA - 1 : 0];
            carry           = result[NB_DATA];
        end
        AND: begin
            alu_result = i_data_a & i_data_b;
        end
        OR : begin
            alu_result = i_data_a | i_data_b;
        end
        XOR: begin
            alu_result = i_data_a ^ i_data_b;
        end
        SRA: begin
            alu_result = $signed(i_data_a) >>> 1;
        end
        SRL: begin
            alu_result = i_data_a >> 1;
        end
        NOR: begin
            alu_result = ~(i_data_a | i_data_b);
        end
        default: begin
            alu_result     = {NB_DATA{1'b0}};
        end
    endcase
end

assign o_alu_result = alu_result;
assign o_carry      = carry;

endmodule