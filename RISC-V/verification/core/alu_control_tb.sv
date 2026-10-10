`timescale 1ns / 1ps

module alu_control_tb;

localparam OP_ADD    = 3'b000;
localparam OP_SUB    = 3'b001;
localparam OP_R      = 3'b010;
localparam OP_I      = 3'b011;
localparam OP_PASS_B = 3'b100;

reg  [2:0] alu_op;
reg  [2:0] funct3;
reg        funct7_5;
wire [3:0] alu_ctrl;

integer errors = 0;
integer tests  = 0;

alu_control dut (
    .i_alu_op   (alu_op),
    .i_funct3   (funct3),
    .i_funct7_5 (funct7_5),
    .o_alu_ctrl (alu_ctrl)
);

task check;
    input [2:0]   t_op;
    input [2:0]   t_f3;
    input         t_f7;
    input [3:0]   t_expected;
    input [255:0] t_name;
    begin
        alu_op = t_op; funct3 = t_f3; funct7_5 = t_f7;
        #1;
        tests = tests + 1;
        if (alu_ctrl !== t_expected) begin
            errors = errors + 1;
            $display("FAIL %0s: esperado %b, obtenido %b", t_name, t_expected, alu_ctrl);
        end else begin
            $display("ok   %0s -> %b", t_name, alu_ctrl);
        end
    end
endtask

initial begin
    // ALUop = suma forzada (cargas, stores, jalr): ignora funct3 y bit 30
    check(OP_ADD, 3'b000, 1'b0, 4'b0000, "lw/sw/jalr");
    check(OP_ADD, 3'b111, 1'b1, 4'b0000, "suma forzada ignora funct");

    // ALUop = resta forzada (branches)
    check(OP_SUB, 3'b000, 1'b0, 4'b1000, "beq");
    check(OP_SUB, 3'b001, 1'b0, 4'b1000, "bne");

    // Tipo R: {funct7[5], funct3}
    check(OP_R, 3'b000, 1'b0, 4'b0000, "add");
    check(OP_R, 3'b000, 1'b1, 4'b1000, "sub");
    check(OP_R, 3'b001, 1'b0, 4'b0001, "sll");
    check(OP_R, 3'b010, 1'b0, 4'b0010, "slt");
    check(OP_R, 3'b011, 1'b0, 4'b0011, "sltu");
    check(OP_R, 3'b100, 1'b0, 4'b0100, "xor");
    check(OP_R, 3'b101, 1'b0, 4'b0101, "srl");
    check(OP_R, 3'b101, 1'b1, 4'b1101, "sra");
    check(OP_R, 3'b110, 1'b0, 4'b0110, "or");
    check(OP_R, 3'b111, 1'b0, 4'b0111, "and");

    // Tipo I aritmetico: el bit 30 solo cuenta en srli/srai
    check(OP_I, 3'b000, 1'b0, 4'b0000, "addi imm positivo");
    check(OP_I, 3'b000, 1'b1, 4'b0000, "addi imm negativo (bit 30 = 1) NO es sub");
    check(OP_I, 3'b010, 1'b1, 4'b0010, "slti con bit 30 = 1");
    check(OP_I, 3'b011, 1'b1, 4'b0011, "sltiu con bit 30 = 1");
    check(OP_I, 3'b100, 1'b1, 4'b0100, "xori con bit 30 = 1");
    check(OP_I, 3'b110, 1'b1, 4'b0110, "ori con bit 30 = 1");
    check(OP_I, 3'b111, 1'b1, 4'b0111, "andi con bit 30 = 1");
    check(OP_I, 3'b001, 1'b0, 4'b0001, "slli");
    check(OP_I, 3'b101, 1'b0, 4'b0101, "srli");
    check(OP_I, 3'b101, 1'b1, 4'b1101, "srai");

    // lui
    check(OP_PASS_B, 3'b000, 1'b0, 4'b1111, "lui");
    check(OP_PASS_B, 3'b101, 1'b1, 4'b1111, "lui ignora funct");

    // ALUop no definido -> suma
    check(3'b101, 3'b111, 1'b1, 4'b0000, "ALUop invalido -> ADD");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule