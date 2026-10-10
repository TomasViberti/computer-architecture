/* Unidad de control principal
----------------------------------------------------------------------
Circuito combinacional: a partir del opcode de la instruccion genera
las señales de control del datapath.

Las señales que "no importan" (X) en una instruccion se fijan en 0.
Un opcode que no corresponde a ninguna instruccion deja todas las
señales en 0: la instruccion no escribe registros ni memoria y no salta
(se comporta como un nop).
----------------------------------------------------------------------
| Instruccion | RegW | ALUsrc | ALUop | MemR | MemW | MemToReg | Branch | Jump
| tipo R      |  1   |   0    |  010  |  0   |  0   |   00     |   0    |  00
| tipo I arit |  1   |   1    |  011  |  0   |  0   |   00     |   0    |  00
| cargas      |  1   |   1    |  000  |  1   |  0   |   01     |   0    |  00
| stores      |  0   |   1    |  000  |  0   |  1   |   00     |   0    |  00
| branches    |  0   |   0    |  001  |  0   |  0   |   00     |   1    |  00
| lui         |  1   |   1    |  100  |  0   |  0   |   00     |   0    |  00
| jal         |  1   |   0    |  000  |  0   |  0   |   10     |   0    |  01
| jalr        |  1   |   1    |  000  |  0   |  0   |   10     |   0    |  10
----------------------------------------------------------------------*/

module control_unit
(
    input  wire [6 : 0] i_opcode        ,
    output wire         o_reg_write     ,
    output wire         o_alu_src       ,
    output wire [2 : 0] o_alu_op        ,
    output wire         o_mem_read      ,
    output wire         o_mem_write     ,
    output wire [1 : 0] o_mem_to_reg    ,
    output wire         o_branch        ,
    output wire [1 : 0] o_jump
);

// Opcodes
localparam OPCODE_R      = 7'b0110011;
localparam OPCODE_I_ARIT = 7'b0010011;
localparam OPCODE_LOAD   = 7'b0000011;
localparam OPCODE_STORE  = 7'b0100011;
localparam OPCODE_BRANCH = 7'b1100011;
localparam OPCODE_LUI    = 7'b0110111;
localparam OPCODE_JAL    = 7'b1101111;
localparam OPCODE_JALR   = 7'b1100111;

// ALUop
localparam ALUOP_ADD    = 3'b000;
localparam ALUOP_SUB    = 3'b001;
localparam ALUOP_R      = 3'b010;
localparam ALUOP_I      = 3'b011;
localparam ALUOP_PASS_B = 3'b100;

// Jump
localparam JUMP_NONE = 2'b00;
localparam JUMP_JAL  = 2'b01;
localparam JUMP_JALR = 2'b10;

// MemToReg
localparam MTR_ALU = 2'b00;
localparam MTR_MEM = 2'b01;
localparam MTR_PC4 = 2'b10;

reg         reg_write;
reg         alu_src;
reg [2 : 0] alu_op;
reg         mem_read;
reg         mem_write;
reg [1 : 0] mem_to_reg;
reg         branch;
reg [1 : 0] jump;

always @(*) begin
    reg_write  = 1'b0;
    alu_src    = 1'b0;
    alu_op     = ALUOP_ADD;
    mem_read   = 1'b0;
    mem_write  = 1'b0;
    mem_to_reg = MTR_ALU;
    branch     = 1'b0;
    jump       = JUMP_NONE;

    case (i_opcode)
        OPCODE_R: begin
            reg_write = 1'b1;
            alu_op    = ALUOP_R;
        end
        OPCODE_I_ARIT: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            alu_op    = ALUOP_I;
        end
        OPCODE_LOAD: begin
            reg_write  = 1'b1;
            alu_src    = 1'b1;
            mem_read   = 1'b1;
            mem_to_reg = MTR_MEM;
        end
        OPCODE_STORE: begin
            alu_src   = 1'b1;
            mem_write = 1'b1;
        end
        OPCODE_BRANCH: begin
            alu_op  = ALUOP_SUB;
            branch  = 1'b1;
        end
        OPCODE_LUI: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            alu_op    = ALUOP_PASS_B;
        end
        OPCODE_JAL: begin
            reg_write  = 1'b1;
            mem_to_reg = MTR_PC4;
            jump       = JUMP_JAL;
        end
        OPCODE_JALR: begin
            reg_write  = 1'b1;
            alu_src    = 1'b1;
            mem_to_reg = MTR_PC4;
            jump       = JUMP_JALR;
        end
        default: begin
            // se mantienen los valores por defecto
        end
    endcase
end

assign o_reg_write  = reg_write;
assign o_alu_src    = alu_src;
assign o_alu_op     = alu_op;
assign o_mem_read   = mem_read;
assign o_mem_write  = mem_write;
assign o_mem_to_reg = mem_to_reg;
assign o_branch     = branch;
assign o_jump       = jump;

endmodule