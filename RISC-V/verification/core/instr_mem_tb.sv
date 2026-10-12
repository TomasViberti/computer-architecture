`timescale 1ns / 1ps

module instr_mem_tb;

localparam DEPTH = 256;                       // 0x000 a 0x3FF
localparam [31:0] HALT = 32'h0000000B;

reg         clock = 1'b0;
always #5 clock = ~clock;

reg         halted = 1'b1, we = 1'b0;
reg  [7:0]  waddr = 0;
reg  [31:0] wdata = 0, pc = 0;
wire [31:0] instr;
wire        err;

reg  [31:0] pc2 = 0;
wire [31:0] instr2;
wire        err2;

integer errors = 0, tests = 0, k;

instr_mem #(.DEPTH(DEPTH)) dut (
    .clock(clock), .i_halted(halted), .i_write_enable(we), .i_write_addr(waddr), .i_write_data(wdata),
    .i_pc(pc), .o_instr(instr), .o_addr_error(err)
);

// Segunda instancia: otro tamaño y otro valor inicial (parametros)
instr_mem #(.DEPTH(16), .INIT_WORD(32'h0)) dut2 (
    .clock(clock), .i_halted(1'b0), .i_write_enable(1'b0), .i_write_addr(4'd0), .i_write_data(32'd0),
    .i_pc(pc2), .o_instr(instr2), .o_addr_error(err2)
);

task check;
    input [31:0]  got;
    input [31:0]  exp;
    input [511:0] name;
    begin
        tests = tests + 1;
        if (got !== exp) begin
            errors = errors + 1;
            $display("FAIL %0s: obtenido %h, esperado %h", name, got, exp);
        end else $display("ok   %0s", name);
    end
endtask

task write_word;
    input [7:0]  a;
    input [31:0] d;
    input        h;
    begin
        @(negedge clock);
        waddr = a; wdata = d; halted = h; we = 1'b1;
        @(posedge clock);
        #1 we = 1'b0;
    end
endtask

initial begin
    #12;

    // 1) Arranque: todo en HALT
    pc = 32'h0;            #1; check(instr, HALT, "arranca en HALT (palabra 0)");
    pc = 4*(DEPTH-1);      #1; check(instr, HALT, "arranca en HALT (ultima palabra)");
    check({31'b0, err}, 32'd0, "direccion valida: sin error");

    // 2) Escritura con el procesador detenido
    write_word(8'd3, 32'h002081B3, 1'b1);
    pc = 32'd12; #1;  check(instr, 32'h002081B3, "escribe la palabra 3 y la lee en PC = 0xC");
    pc = 32'd8;  #1;  check(instr, HALT, "la palabra anterior no cambia");
    pc = 32'd16; #1;  check(instr, HALT, "la palabra siguiente no cambia");

    // 3) Con el procesador en marcha la escritura se ignora
    write_word(8'd5, 32'hDEADBEEF, 1'b0);
    pc = 32'd20; #1;  check(instr, HALT, "escritura con i_halted = 0: se ignora");

    // 4) La lectura es combinacional
    pc = 32'd12; #1;  check(instr, 32'h002081B3, "lectura combinacional A");
    pc = 32'd8;  #1;  check(instr, HALT, "lectura combinacional B (sin clock)");

    // 5) La escritura es sincronica: antes del flanco se lee el valor viejo
    @(negedge clock);
    waddr = 8'd7; wdata = 32'hCAFE0007; halted = 1'b1; we = 1'b1; pc = 32'd28;
    #1; check(instr, HALT, "antes del flanco: valor viejo");
    @(posedge clock); #1 we = 1'b0;
    check(instr, 32'hCAFE0007, "despues del flanco: valor nuevo");

    // 6) Rango: la memoria cubre 0x000 a 0x3FF
    pc = 32'h3FC; #1; check({31'b0, err}, 32'd0, "0x3FC esta en rango");
    pc = 32'h400; #1; check(instr, HALT, "0x400 (justo fuera): devuelve HALT");
    check({31'b0, err}, 32'd1, "0x400: error activo");
    pc = 32'h8000_0000; #1; check(instr, HALT, "0x80000000: devuelve HALT");
    check({31'b0, err}, 32'd1, "0x80000000: error activo");
    pc = 32'hFFFF_FFFC; #1; check({31'b0, err}, 32'd1, "0xFFFFFFFC: error activo");
    write_word(8'd0, 32'h00000013, 1'b1);
    pc = 32'h400; #1; check(instr, HALT, "0x400 NO repite la palabra 0 (sin aliasing)");
    pc = 32'h0;   #1; check(instr, 32'h00000013, "la palabra 0 si vale nop");

    // 7) PC desalineado: se trata como alineado hacia abajo
    pc = 32'd13; #1; check(instr, 32'h002081B3, "PC = 13 lee la palabra 3");
    check({31'b0, err}, 32'd0, "PC desalineado dentro del rango: sin error");

    // 8) Parametros DEPTH e INIT_WORD (segunda instancia: 16 palabras, 0x00 a 0x3F)
    pc2 = 32'h0;  #1; check(instr2, 32'h0, "INIT_WORD = 0: arranca en ceros");
    pc2 = 32'h3C; #1; check({31'b0, err2}, 32'd0, "DEPTH = 16: 0x3C esta en rango");
    pc2 = 32'h40; #1; check(instr2, HALT, "DEPTH = 16: 0x40 devuelve HALT");
    check({31'b0, err2}, 32'd1, "DEPTH = 16: 0x40 activa el error");

    // 9) Las 256 palabras se escriben y se leen sin interferirse
    for (k = 0; k < DEPTH; k = k + 1) write_word(k[7:0], 32'hA000_0000 + k, 1'b1);
    for (k = 0; k < DEPTH; k = k + 1) begin
        pc = k * 4; #1; tests = tests + 1;
        if (instr !== 32'hA000_0000 + k || err !== 1'b0) begin
            errors = errors + 1; $display("FAIL palabra %0d", k);
        end
    end
    $display("ok   las 256 palabras se escriben y se leen sin interferirse");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule