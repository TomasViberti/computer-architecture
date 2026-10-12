`timescale 1ns/1ps

module pc_tb;

    reg         clk;
    reg         reset;
    reg         enable;
    reg  [31:0] next_pc;
    wire [31:0] current_pc;

    pc dut (
        .i_clk(clk),
        .i_reset(reset),
        .i_enable(enable),
        .i_next_pc(next_pc),
        .o_current_pc(current_pc)
    );

    integer tests  = 0;
    integer errors = 0;
    integer i;
    reg [31:0] exp_pc;

    always #5 clk = ~clk;

    task check(input [31:0] t_got, input [31:0] t_expected, input [511:0] t_name);
        begin
            tests = tests + 1;
            if (t_got !== t_expected) begin
                errors = errors + 1;
                $display("ERROR %0s: obtenido %h, esperado %h", t_name, t_got, t_expected);
            end
        end
    endtask

    // Cambia las entradas en el flanco de bajada, deja pasar un flanco de subida y espera 1 ns
    task step(input [31:0] t_next, input t_en, input t_rst);
        begin
            @(negedge clk);
            next_pc = t_next;
            enable  = t_en;
            reset   = t_rst;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0; reset = 1; enable = 0; next_pc = 32'hFFFF_FFFF;

        // 1) Valor inicial: el PC arranca en 0 aun sin reset
        #1;
        check(current_pc, 32'h0, "valor inicial");

        // 2) Reset: lleva el PC a 0 aunque enable valga 1 y next_pc sea distinto de 0
        step(32'h1234_5678, 1, 1);
        check(current_pc, 32'h1234_5678, "carga antes del reset");
        step(32'hAAAA_AAAA, 1, 0);
        check(current_pc, 32'h0, "reset con enable=1");

        // 3) El reset tiene prioridad sobre el enable y se mantiene mientras vale 0
        step(32'hAAAA_AAAA, 0, 0);
        check(current_pc, 32'h0, "reset con enable=0");
        step(32'hAAAA_AAAA, 1, 0);
        check(current_pc, 32'h0, "reset mantenido");

        // 4) Carga normal con distintos valores de 32 bits
        for (i = 1; i <= 8; i = i + 1) begin
            exp_pc = 32'h9E37_79B9 * i;
            step(exp_pc, 1, 1);
            check(current_pc, exp_pc, "carga de next_pc");
        end

        // 5) Enable en 0: mantiene el valor aunque next_pc cambie
        step(32'h0000_0040, 1, 1);
        check(current_pc, 32'h0000_0040, "carga previa a mantener");
        step(32'h0000_0080, 0, 1);
        check(current_pc, 32'h0000_0040, "enable=0 mantiene");
        step(32'h0000_00C0, 0, 1);
        check(current_pc, 32'h0000_0040, "enable=0 sigue manteniendo");
        step(32'h0000_00C0, 1, 1);
        check(current_pc, 32'h0000_00C0, "enable=1 vuelve a cargar");

        // 6) Reset sincronico: no actua hasta el flanco de subida
        step(32'h0000_0100, 1, 1);
        check(current_pc, 32'h0000_0100, "valor antes del reset");
        @(negedge clk);
        reset = 0;
        #1;
        check(current_pc, 32'h0000_0100, "reset sincronico: sin flanco no cambia");
        @(posedge clk);
        #1;
        check(current_pc, 32'h0, "reset sincronico: con flanco vale 0");

        // 7) Secuencia como en el datapath: next_pc = PC + 4
        step(32'h0, 1, 0);
        for (i = 1; i <= 10; i = i + 1) begin
            step(current_pc + 4, 1, 1);
            check(current_pc, 32'd4 * i, "secuencia PC+4");
        end

        // 8) Desborde: 0xFFFFFFFC + 4 vuelve a 0
        step(32'hFFFF_FFFC, 1, 1);
        check(current_pc, 32'hFFFF_FFFC, "PC maximo alineado");
        step(current_pc + 4, 1, 1);
        check(current_pc, 32'h0, "desborde de 32 bits");

        $display("%0d pruebas, %0d errores", tests, errors);
        if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
        else             $display("HAY PRUEBAS FALLIDAS");
        $finish;
    end

endmodule