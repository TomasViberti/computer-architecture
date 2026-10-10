// Generador de inmediatos RV32I. Logica combinacional.
// Entrada: instruccion de 32 bits. Salida: inmediato de 32 bits.

module imm_gen (
    input  wire [31:0] i_inst,
    output reg  [31:0] o_imm
);

    // Opcodes (i_inst[6:0]). Para las operaciones tipo R, opcode = 0110011, no hay inmediatos y se entrega 0.
    localparam OP_LOAD   = 7'b0000011;  // lb, lh, lw, lbu, lhu
    localparam OP_OPIMM  = 7'b0010011;  // addi, andi, ori, xori, slti, sltiu, slli, srli, srai
    localparam OP_JALR   = 7'b1100111;  // jalr
    localparam OP_STORE  = 7'b0100011;  // sb, sh, sw
    localparam OP_BRANCH = 7'b1100011;  // beq, bne
    localparam OP_LUI    = 7'b0110111;  // lui
    localparam OP_JAL    = 7'b1101111;  // jal

    wire [6:0] opcode = i_inst[6:0];

    always @(*) begin
        case (opcode)
            // Formato I: 12 bits en i_inst[31:20], extendidos con signo
            OP_LOAD, OP_OPIMM, OP_JALR:
                o_imm = {{20{i_inst[31]}}, i_inst[31:20]};

            // Formato S: 12 bits partidos, extendidos con signo
            OP_STORE:
                o_imm = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};

            // Formato B: 12 bits partidos, extendidos con signo, bit 0 = 0
            OP_BRANCH:
                o_imm = {{19{i_inst[31]}}, i_inst[31], i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};

            // Formato U: 20 bits arriba, 12 ceros abajo (sin extension de signo)
            OP_LUI:
                o_imm = {i_inst[31:12], 12'b0};

            // Formato J: 20 bits partidos, extendidos con signo, bit 0 = 0
            OP_JAL:
                o_imm = {{11{i_inst[31]}}, i_inst[31], i_inst[19:12], i_inst[20], i_inst[30:21], 1'b0};

            // Tipo R y cualquier otro: sin inmediato
            default:
                o_imm = 32'b0;
        endcase
    end

endmodule