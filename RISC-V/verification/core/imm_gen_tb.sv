`timescale 1ns/1ps

module imm_gen_tb;

    logic [31:0] i_inst;
    logic [31:0] o_imm;

    int errors = 0;
    int total  = 0;

    imm_gen dut (
        .i_inst(i_inst),
        .o_imm (o_imm)
    );

    logic [6:0] op_s;
    integer     k;
    string      nm;

    // 1 si el opcode es uno de los 7 que genera inmediato
    function logic is_supported(input logic [6:0] op);
        case (op)
            7'b0000011, 7'b0010011, 7'b1100111, 7'b0100011,
            7'b1100011, 7'b0110111, 7'b1101111: is_supported = 1'b1;
            default:                            is_supported = 1'b0;
        endcase
    endfunction

    // Aplica una instruccion y compara el inmediato contra el esperado
    task check_imm
        (
        input logic [31:0] i,
        input logic [31:0] expected,
        input string      name
        );

        begin
            i_inst = i;
            #1;
            total = total + 1;
            if (o_imm === expected)
                $display("[PASS] %-22s i_inst=%h o_imm=%h", name, i, o_imm);
            else begin
                errors = errors + 1;
                $display("[FAIL] %-22s i_inst=%h o_imm=%h (esperado %h)", name, i, o_imm, expected);
            end
        end
    endtask

    initial begin
        i_inst = 32'b0;
        #1;

        // ---------- Tipo I - loads ----------
        check_imm(32'h00810283, 32'h00000008, "lb imm=8");
        check_imm(32'hFFC10283, 32'hFFFFFFFC, "lb imm=-4");
        check_imm(32'h7FF10283, 32'h000007FF, "lb imm=2047");
        check_imm(32'h80010283, 32'hFFFFF800, "lb imm=-2048");
        check_imm(32'h00811283, 32'h00000008, "lh imm=8");
        check_imm(32'hFFC11283, 32'hFFFFFFFC, "lh imm=-4");
        check_imm(32'h7FF11283, 32'h000007FF, "lh imm=2047");
        check_imm(32'h80011283, 32'hFFFFF800, "lh imm=-2048");
        check_imm(32'h00812283, 32'h00000008, "lw imm=8");
        check_imm(32'hFFC12283, 32'hFFFFFFFC, "lw imm=-4");
        check_imm(32'h7FF12283, 32'h000007FF, "lw imm=2047");
        check_imm(32'h80012283, 32'hFFFFF800, "lw imm=-2048");
        check_imm(32'h00814283, 32'h00000008, "lbu imm=8");
        check_imm(32'hFFC14283, 32'hFFFFFFFC, "lbu imm=-4");
        check_imm(32'h7FF14283, 32'h000007FF, "lbu imm=2047");
        check_imm(32'h80014283, 32'hFFFFF800, "lbu imm=-2048");
        check_imm(32'h00815283, 32'h00000008, "lhu imm=8");
        check_imm(32'hFFC15283, 32'hFFFFFFFC, "lhu imm=-4");
        check_imm(32'h7FF15283, 32'h000007FF, "lhu imm=2047");
        check_imm(32'h80015283, 32'hFFFFF800, "lhu imm=-2048");

        // ---------- Tipo I - aritmetico/logico con inmediato ----------
        check_imm(32'h00110093, 32'h00000001, "addi imm=1");
        check_imm(32'hFFF10093, 32'hFFFFFFFF, "addi imm=-1");
        check_imm(32'h7FF10093, 32'h000007FF, "addi imm=2047");
        check_imm(32'h80010093, 32'hFFFFF800, "addi imm=-2048");
        check_imm(32'h00117093, 32'h00000001, "andi imm=1");
        check_imm(32'hFFF17093, 32'hFFFFFFFF, "andi imm=-1");
        check_imm(32'h7FF17093, 32'h000007FF, "andi imm=2047");
        check_imm(32'h80017093, 32'hFFFFF800, "andi imm=-2048");
        check_imm(32'h00116093, 32'h00000001, "ori imm=1");
        check_imm(32'hFFF16093, 32'hFFFFFFFF, "ori imm=-1");
        check_imm(32'h7FF16093, 32'h000007FF, "ori imm=2047");
        check_imm(32'h80016093, 32'hFFFFF800, "ori imm=-2048");
        check_imm(32'h00114093, 32'h00000001, "xori imm=1");
        check_imm(32'hFFF14093, 32'hFFFFFFFF, "xori imm=-1");
        check_imm(32'h7FF14093, 32'h000007FF, "xori imm=2047");
        check_imm(32'h80014093, 32'hFFFFF800, "xori imm=-2048");
        check_imm(32'h00112093, 32'h00000001, "slti imm=1");
        check_imm(32'hFFF12093, 32'hFFFFFFFF, "slti imm=-1");
        check_imm(32'h7FF12093, 32'h000007FF, "slti imm=2047");
        check_imm(32'h80012093, 32'hFFFFF800, "slti imm=-2048");
        check_imm(32'h00113093, 32'h00000001, "sltiu imm=1");
        check_imm(32'hFFF13093, 32'hFFFFFFFF, "sltiu imm=-1");
        check_imm(32'h7FF13093, 32'h000007FF, "sltiu imm=2047");
        check_imm(32'h80013093, 32'hFFFFF800, "sltiu imm=-2048");

        // ---------- Tipo I - shifts (el campo [31:20] incluye funct7 + shamt) ----------
        // El ImmGen entrega el campo completo; la ALU usa solo los 5 bits bajos (shamt)
        check_imm(32'h00111093, 32'h00000001, "slli shamt=1");
        check_imm(32'h01F11093, 32'h0000001F, "slli shamt=31");
        check_imm(32'h00115093, 32'h00000001, "srli shamt=1");
        check_imm(32'h01F15093, 32'h0000001F, "srli shamt=31");
        check_imm(32'h40115093, 32'h00000401, "srai shamt=1");
        check_imm(32'h41F15093, 32'h0000041F, "srai shamt=31");

        // ---------- Tipo I - jalr ----------
        check_imm(32'h004100E7, 32'h00000004, "jalr imm=4");
        check_imm(32'hFFC100E7, 32'hFFFFFFFC, "jalr imm=-4");
        check_imm(32'h7FF100E7, 32'h000007FF, "jalr imm=2047");
        check_imm(32'h800100E7, 32'hFFFFF800, "jalr imm=-2048");

        // ---------- Tipo S - stores ----------
        check_imm(32'h00510423, 32'h00000008, "sb imm=8");
        check_imm(32'hFE510E23, 32'hFFFFFFFC, "sb imm=-4");
        check_imm(32'h7E510FA3, 32'h000007FF, "sb imm=2047");
        check_imm(32'h80510023, 32'hFFFFF800, "sb imm=-2048");
        check_imm(32'h025100A3, 32'h00000021, "sb imm=33");
        check_imm(32'h00511423, 32'h00000008, "sh imm=8");
        check_imm(32'hFE511E23, 32'hFFFFFFFC, "sh imm=-4");
        check_imm(32'h7E511FA3, 32'h000007FF, "sh imm=2047");
        check_imm(32'h80511023, 32'hFFFFF800, "sh imm=-2048");
        check_imm(32'h025110A3, 32'h00000021, "sh imm=33");
        check_imm(32'h00512423, 32'h00000008, "sw imm=8");
        check_imm(32'hFE512E23, 32'hFFFFFFFC, "sw imm=-4");
        check_imm(32'h7E512FA3, 32'h000007FF, "sw imm=2047");
        check_imm(32'h80512023, 32'hFFFFF800, "sw imm=-2048");
        check_imm(32'h025120A3, 32'h00000021, "sw imm=33");

        // ---------- Tipo B - branches (bit 0 siempre 0) ----------
        check_imm(32'h00208863, 32'h00000010, "beq off=16");
        check_imm(32'hFE208CE3, 32'hFFFFFFF8, "beq off=-8");
        check_imm(32'h7E208FE3, 32'h00000FFE, "beq off=4094");
        check_imm(32'h80208063, 32'hFFFFF000, "beq off=-4096");
        check_imm(32'h00208163, 32'h00000002, "beq off=2");
        check_imm(32'hFE208FE3, 32'hFFFFFFFE, "beq off=-2");
        check_imm(32'h002080E3, 32'h00000800, "beq off=2048");
        check_imm(32'h00209863, 32'h00000010, "bne off=16");
        check_imm(32'hFE209CE3, 32'hFFFFFFF8, "bne off=-8");
        check_imm(32'h7E209FE3, 32'h00000FFE, "bne off=4094");
        check_imm(32'h80209063, 32'hFFFFF000, "bne off=-4096");
        check_imm(32'h00209163, 32'h00000002, "bne off=2");
        check_imm(32'hFE209FE3, 32'hFFFFFFFE, "bne off=-2");
        check_imm(32'h002090E3, 32'h00000800, "bne off=2048");

        // ---------- Tipo U - lui (sin extension de signo) ----------
        check_imm(32'h123452B7, 32'h12345000, "lui imm20=0x12345");
        check_imm(32'hFFFFF2B7, 32'hFFFFF000, "lui imm20=0xFFFFF");
        check_imm(32'h800002B7, 32'h80000000, "lui imm20=0x80000");
        check_imm(32'h000012B7, 32'h00001000, "lui imm20=0x00001");
        check_imm(32'h000002B7, 32'h00000000, "lui imm20=0x00000");

        // ---------- Tipo J - jal (bit 0 siempre 0) ----------
        check_imm(32'h010000EF, 32'h00000010, "jal off=16");
        check_imm(32'hFF1FF0EF, 32'hFFFFFFF0, "jal off=-16");
        check_imm(32'h7FFFF0EF, 32'h000FFFFE, "jal off=1048574");
        check_imm(32'h800000EF, 32'hFFF00000, "jal off=-1048576");
        check_imm(32'h002000EF, 32'h00000002, "jal off=2");
        check_imm(32'hFFFFF0EF, 32'hFFFFFFFE, "jal off=-2");
        check_imm(32'h001000EF, 32'h00000800, "jal off=2048");
        check_imm(32'h7FF7F0EF, 32'h0007FFFE, "jal off=524286");

        // ---------- Tipo R: opcode 0110011 -> default (o_imm = 0) ----------
        check_imm(32'h003100B3, 32'h00000000, "add  (R)");
        check_imm(32'h403100B3, 32'h00000000, "sub  (R)");
        check_imm(32'h003110B3, 32'h00000000, "sll  (R)");
        check_imm(32'h003150B3, 32'h00000000, "srl  (R)");
        check_imm(32'h403150B3, 32'h00000000, "sra  (R)");
        check_imm(32'h003170B3, 32'h00000000, "and  (R)");
        check_imm(32'h003160B3, 32'h00000000, "or   (R)");
        check_imm(32'h003140B3, 32'h00000000, "xor  (R)");
        check_imm(32'h003120B3, 32'h00000000, "slt  (R)");
        check_imm(32'h003130B3, 32'h00000000, "sltu (R)");
        check_imm(32'hFFFFFFB3, 32'h00000000, "R con campos en 1");

        // ---------- Opcodes desconocidos -> default (o_imm = 0) ----------
        check_imm(32'h00000000, 32'h00000000, "todo ceros");
        check_imm(32'hFFFFFFFF, 32'h00000000, "todo unos");
        check_imm(32'hFFFFF017, 32'h00000000, "auipc (no soportada)");
        check_imm(32'hFFFFF073, 32'h00000000, "system (no soportada)");
        check_imm(32'hFFFFF00F, 32'h00000000, "fence (no soportada)");

        // ---------- Barrido: todo opcode NO soportado debe dar 0 ----------
        // (campos con basura fija; se recorren los 128 opcodes posibles)
        for (k = 0; k < 128; k = k + 1) begin
            op_s = k;                                  // se trunca a 7 bits
            if (!is_supported(op_s)) begin
                nm = $sformatf("barrido opcode=%b", op_s);
                check_imm({25'h1A5A5A5, op_s}, 32'h0, nm);
            end
        end

        $display("--------------------------------------------");
        if (errors == 0)
            $display("TODOS LOS TESTS PASARON (%0d/%0d)", total, total);
        else
            $display("FALLARON %0d de %0d tests", errors, total);
        $display("--------------------------------------------");
        $finish;
    end

endmodule