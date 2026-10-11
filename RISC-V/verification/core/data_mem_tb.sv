`timescale 1ns/1ps

module data_mem_tb;

localparam DEPTH = 256;                 // palabras de 32 bits

reg         clk;
reg  [31:0] addr;
reg  [31:0] wdata;
reg         memread;
reg         memwrite;
reg  [2:0]  funct3;
wire [31:0] rdata;
wire        addr_error;

integer errors = 0;
integer tests  = 0;
integer j, k;
reg [31:0] w;
reg [7:0]  b;
reg [15:0] h;
reg [31:0] exp;

data_mem #(.DEPTH(DEPTH)) dut (
    .clock      (clk),
    .i_addr     (addr),
    .i_wdata    (wdata),
    .i_memread  (memread),
    .i_memwrite (memwrite),
    .i_funct3   (funct3),
    .o_rdata    (rdata),
    .o_addr_error (addr_error)
);

initial clk = 1'b0;
always #5 clk = ~clk;

task check;
    input [31:0]  t_got;
    input [31:0]  t_expected;
    input [511:0] t_name;
    begin
        tests = tests + 1;
        if (t_got !== t_expected) begin
            errors = errors + 1;
            $display("FAIL %0s (addr=%h): obtenido %h, esperado %h", t_name, addr, t_got, t_expected);
        end else begin
            $display("ok   %0s", t_name);
        end
    end
endtask

// Escribe: las entradas cambian en el flanco de bajada y el dato se guarda
// en el siguiente flanco de subida.
task store;
    input [31:0] t_addr;
    input [31:0] t_data;
    input [2:0]  t_f3;
    input        t_we;
    begin
        @(negedge clk);
        addr = t_addr; wdata = t_data; funct3 = t_f3; memwrite = t_we; memread = 1'b0;
        @(posedge clk);
        #1;
        memwrite = 1'b0;
    end
endtask

// Lee (MemRead = 1) y compara
task load;
    input [31:0]  t_addr;
    input [2:0]   t_f3;
    input [31:0]  t_expected;
    input [511:0] t_name;
    begin
        addr = t_addr; funct3 = t_f3; memread = 1'b1; memwrite = 1'b0;
        #1;
        check(rdata, t_expected, t_name);
    end
endtask

initial begin
    memwrite = 0; memread = 0; addr = 0; wdata = 0; funct3 = 0;
    #12;

    // 1) Estado inicial: toda la memoria en 0
    load(32'h0,            3'b010, 32'h0, "lw @0 arranca en 0");
    load((DEPTH - 1) * 4,  3'b010, 32'h0, "lw ultima palabra arranca en 0");

    // 2) sw y lw
    store(32'h10, 32'hDEADBEEF, 3'b010, 1'b1);
    load (32'h10, 3'b010, 32'hDEADBEEF, "sw y lw");

    // 3) Orden de bytes y extension. Una palabra con bytes negativos (DEADBEEF)
    //    y otra con bytes positivos (7F6E5D4C): lb/lbu byte a byte y lh/lhu por mitades
    store(32'h14, 32'h7F6E5D4C, 3'b010, 1'b1);
    for (j = 0; j < 2; j = j + 1) begin
        w = (j == 0) ? 32'hDEADBEEF : 32'h7F6E5D4C;
        for (k = 0; k < 4; k = k + 1) begin
            b = w >> (8 * k);
            load(32'h10 + 4*j + k, 3'b100, {24'b0, b},        "lbu: cada byte, con ceros");
            load(32'h10 + 4*j + k, 3'b000, {{24{b[7]}}, b},   "lb: cada byte, con signo");
        end
        for (k = 0; k < 2; k = k + 1) begin
            h = w >> (16 * k);
            load(32'h10 + 4*j + 2*k, 3'b101, {16'b0, h},       "lhu: cada mitad, con ceros");
            load(32'h10 + 4*j + 2*k, 3'b001, {{16{h[15]}}, h}, "lh: cada mitad, con signo");
        end
    end

    // 4) sb escribe 1 byte y no toca los otros tres (se prueba en cada posicion)
    for (k = 0; k < 4; k = k + 1) begin
        store(32'h40, 32'hFFFFFFFF, 3'b010, 1'b1);
        store(32'h40 + k, 32'h12345678, 3'b000, 1'b1);       // solo debe entrar el 78
        exp = (32'hFFFFFFFF & ~(32'hFF << (8 * k))) | (32'h78 << (8 * k));
        load(32'h40, 3'b010, exp, "sb: escribe 1 byte, el resto no cambia");
    end

    // 5) sh escribe 2 bytes y no toca los otros dos (en las dos mitades)
    for (k = 0; k < 2; k = k + 1) begin
        store(32'h50, 32'hFFFFFFFF, 3'b010, 1'b1);
        store(32'h50 + 2*k, 32'h12345678, 3'b001, 1'b1);     // solo debe entrar el 5678
        exp = (32'hFFFFFFFF & ~(32'hFFFF << (16 * k))) | (32'h5678 << (16 * k));
        load(32'h50, 3'b010, exp, "sh: escribe 2 bytes, el resto no cambia");
    end

    // 6) sw no pisa las palabras vecinas
    store(32'h5C, 32'h11111111, 3'b010, 1'b1);
    store(32'h60, 32'h22222222, 3'b010, 1'b1);
    store(32'h64, 32'h33333333, 3'b010, 1'b1);
    load (32'h5C, 3'b010, 32'h11111111, "vecina anterior intacta");
    load (32'h60, 3'b010, 32'h22222222, "palabra del medio");
    load (32'h64, 3'b010, 32'h33333333, "vecina siguiente intacta");

    // 7) Con MemRead = 0 la salida es 0 aunque haya datos en esa direccion
    addr = 32'h10; funct3 = 3'b010; memread = 1'b0; #1;
    check(rdata, 32'h0, "MemRead=0: la salida es 0");

    // 8) Con MemWrite = 0 no se guarda nada
    store(32'h10, 32'h12345678, 3'b010, 1'b0);
    load (32'h10, 3'b010, 32'hDEADBEEF, "MemWrite=0: no escribe");

    // 9) Limites del rango: la memoria cubre DEPTH*4 bytes (0x000 a 0x3FF)
    load((DEPTH - 1) * 4,     3'b010, 32'h0, "ultima palabra esta en rango");
    check({31'b0, addr_error}, 32'd0, "ultima palabra: sin error");
    load(DEPTH * 4 - 1,       3'b100, 32'h0, "ultimo byte esta en rango");
    check({31'b0, addr_error}, 32'd0, "ultimo byte: sin error");

    // 10) Lectura fuera de rango: devuelve 0 y levanta el error (sin aliasing)
    load(DEPTH * 4,           3'b010, 32'h0, "lectura justo fuera del rango: 0");
    check({31'b0, addr_error}, 32'd1, "lectura justo fuera del rango: error");
    load(DEPTH * 4 + 32'h10,  3'b010, 32'h0, "lectura en alias de 0x10: 0, no DEADBEEF");
    check({31'b0, addr_error}, 32'd1, "lectura en alias de 0x10: error");
    load(32'h8000_0000,       3'b010, 32'h0, "lectura en 0x80000000: 0");
    check({31'b0, addr_error}, 32'd1, "lectura en 0x80000000: error");
    load(32'hFFFF_FFFC,       3'b000, 32'h0, "lectura en 0xFFFFFFFC: 0");
    check({31'b0, addr_error}, 32'd1, "lectura en 0xFFFFFFFC: error");

    // 11) Escritura fuera de rango: no se guarda y levanta el error
    @(negedge clk);
    addr = DEPTH * 4 + 32'h10; wdata = 32'hDEAD0000; funct3 = 3'b010; memwrite = 1'b1; memread = 1'b0;
    #1;
    check({31'b0, addr_error}, 32'd1, "escritura fuera de rango: error");
    @(posedge clk); #1 memwrite = 1'b0;
    load(32'h10, 3'b010, 32'hDEADBEEF, "escritura fuera de rango NO pisa 0x10");
    check({31'b0, addr_error}, 32'd0, "direccion valida: sin error");

    @(negedge clk);
    addr = DEPTH * 4; wdata = 32'hCAFEBABE; funct3 = 3'b000; memwrite = 1'b1; memread = 1'b0;
    #1;
    check({31'b0, addr_error}, 32'd1, "sb fuera de rango: error");
    @(posedge clk); #1 memwrite = 1'b0;
    load(32'h0, 3'b010, 32'h0, "sb fuera de rango NO pisa 0x0");

    // 12) Sin lectura ni escritura no hay error, aunque la direccion sea invalida
    addr = 32'hFFFF_FFFF; memread = 1'b0; memwrite = 1'b0; #1;
    check({31'b0, addr_error}, 32'd0, "sin acceso: sin error");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule