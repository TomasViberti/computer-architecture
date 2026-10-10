`timescale 1ns / 1ps

module control_unit_tb;

reg  [6:0] opcode;
wire       reg_write;
wire       alu_src;
wire [2:0] alu_op;
wire       mem_read;
wire       mem_write;
wire [1:0] mem_to_reg;
wire       branch;
wire [1:0] jump;
wire       halt;

integer errors = 0;
integer tests  = 0;

control_unit dut (
    .i_opcode     (opcode),
    .o_reg_write  (reg_write),
    .o_alu_src    (alu_src),
    .o_alu_op     (alu_op),
    .o_mem_read   (mem_read),
    .o_mem_write  (mem_write),
    .o_mem_to_reg (mem_to_reg),
    .o_branch     (branch),
    .o_jump       (jump),
    .o_halt       (halt)
);

task check;
    input [6:0]   t_opcode;
    input         e_reg_write;
    input         e_alu_src;
    input [2:0]   e_alu_op;
    input         e_mem_read;
    input         e_mem_write;
    input [1:0]   e_mem_to_reg;
    input         e_branch;
    input [1:0]   e_jump;
    input         e_halt;
    input [255:0] t_name;
    begin
        opcode = t_opcode;
        #1;
        tests = tests + 1;
        if ({reg_write, alu_src, alu_op, mem_read, mem_write, mem_to_reg, branch, jump, halt} !==
            {e_reg_write, e_alu_src, e_alu_op, e_mem_read, e_mem_write, e_mem_to_reg, e_branch, e_jump, e_halt}) begin
            errors = errors + 1;
            $display("FAIL %0s: obtenido RW=%b AS=%b AOP=%b MR=%b MW=%b M2R=%b BR=%b J=%b H=%b",
                     t_name, reg_write, alu_src, alu_op, mem_read, mem_write, mem_to_reg, branch, jump, halt);
            $display("     esperado RW=%b AS=%b AOP=%b MR=%b MW=%b M2R=%b BR=%b J=%b H=%b",
                     e_reg_write, e_alu_src, e_alu_op, e_mem_read, e_mem_write, e_mem_to_reg, e_branch, e_jump, e_halt);
        end else begin
            $display("ok   %0s", t_name);
        end
    end
endtask

initial begin
    //     opcode     RW   AS   ALUop  MR   MW   M2R   BR   J     H
    check(7'b0110011, 1'b1, 1'b0, 3'b010, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b0, "tipo R");
    check(7'b0010011, 1'b1, 1'b1, 3'b011, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b0, "tipo I aritmetico");
    check(7'b0000011, 1'b1, 1'b1, 3'b000, 1'b1, 1'b0, 2'b01, 1'b0, 2'b00, 1'b0, "cargas");
    check(7'b0100011, 1'b0, 1'b1, 3'b000, 1'b0, 1'b1, 2'b00, 1'b0, 2'b00, 1'b0, "stores");
    check(7'b1100011, 1'b0, 1'b0, 3'b001, 1'b0, 1'b0, 2'b00, 1'b1, 2'b00, 1'b0, "branches");
    check(7'b0110111, 1'b1, 1'b1, 3'b100, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b0, "lui");
    check(7'b1101111, 1'b1, 1'b0, 3'b000, 1'b0, 1'b0, 2'b10, 1'b0, 2'b01, 1'b0, "jal");
    check(7'b1100111, 1'b1, 1'b1, 3'b000, 1'b0, 1'b0, 2'b10, 1'b0, 2'b10, 1'b0, "jalr");

    // HALT: opcode custom-0, no escribe registros ni memoria y no salta
    check(7'b0001011, 1'b0, 1'b0, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b1, "halt (custom-0)");

    // opcodes invalidos: no escriben registros ni memoria y no saltan
    check(7'b0000000, 1'b0, 1'b0, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b0, "opcode invalido 0000000");
    check(7'b1111111, 1'b0, 1'b0, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b0, "opcode invalido 1111111");
    check(7'b0001111, 1'b0, 1'b0, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 2'b00, 1'b0, "opcode invalido 0001111");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule