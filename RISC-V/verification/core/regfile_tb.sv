`timescale 1ns / 1ps

module regfile_tb;

localparam NB_DATA = 32;
localparam NB_ADDR = 5;

reg                   clk;
reg                   reg_write;
reg  [NB_ADDR - 1:0]  rs1;
reg  [NB_ADDR - 1:0]  rs2;
reg  [NB_ADDR - 1:0]  rd;
reg  [NB_DATA - 1:0]  write_data;
wire [NB_DATA - 1:0]  read_data1;
wire [NB_DATA - 1:0]  read_data2;

integer errors = 0;
integer tests  = 0;
integer k;

regfile #(.NB_DATA(NB_DATA), .NB_ADDR(NB_ADDR)) dut (
    .i_clk        (clk),
    .i_reg_write  (reg_write),
    .i_rs1        (rs1),
    .i_rs2        (rs2),
    .i_rd         (rd),
    .i_write_data (write_data),
    .o_read_data1 (read_data1),
    .o_read_data2 (read_data2)
);

initial clk = 1'b0;
always #5 clk = ~clk;

task check;
    input [NB_DATA - 1:0] t_got;
    input [NB_DATA - 1:0] t_expected;
    input [511:0]         t_name;
    begin
        tests = tests + 1;
        if (t_got !== t_expected) begin
            errors = errors + 1;
            $display("FAIL %0s: obtenido %h, esperado %h", t_name, t_got, t_expected);
        end else begin
            $display("ok   %0s", t_name);
        end
    end
endtask

// Escribe un registro: las entradas cambian en el flanco de bajada y el dato
// se guarda en el siguiente flanco de subida.
task write_reg;
    input [NB_ADDR - 1:0] t_rd;
    input [NB_DATA - 1:0] t_data;
    input                 t_we;
    begin
        @(negedge clk);
        rd = t_rd; write_data = t_data; reg_write = t_we;
        @(posedge clk);
        #1;
        reg_write = 1'b0;
    end
endtask

initial begin
    reg_write = 0; rs1 = 0; rs2 = 0; rd = 0; write_data = 0;
    #12;

    // 1) Estado inicial: todo en 0
    rs1 = 5'd5; rs2 = 5'd31; #1;
    check(read_data1, 32'h0, "x5 arranca en 0");
    check(read_data2, 32'h0, "x31 arranca en 0");

    // 2) Escritura normal, y la lectura sigue al dato guardado
    write_reg(5'd5, 32'hDEADBEEF, 1'b1);
    rs1 = 5'd5; #1;
    check(read_data1, 32'hDEADBEEF, "escribe x5 y lee x5");

    // 3) Con RegWrite = 0 no se guarda nada
    write_reg(5'd6, 32'h12345678, 1'b0);
    rs1 = 5'd6; #1;
    check(read_data1, 32'h0, "RegWrite=0: x6 no cambia");

    // 4) x0 no se puede escribir y siempre lee 0
    write_reg(5'd0, 32'hFFFFFFFF, 1'b1);
    rs1 = 5'd0; rs2 = 5'd0; #1;
    check(read_data1, 32'h0, "x0 leido por el puerto 1 es 0");
    check(read_data2, 32'h0, "x0 leido por el puerto 2 es 0");

    // 5) Dos lecturas a la vez, de registros distintos y del mismo
    write_reg(5'd6, 32'hCAFE0006, 1'b1);
    rs1 = 5'd5; rs2 = 5'd6; #1;
    check(read_data1, 32'hDEADBEEF, "dos lecturas: puerto 1 = x5");
    check(read_data2, 32'hCAFE0006, "dos lecturas: puerto 2 = x6");
    rs1 = 5'd6; rs2 = 5'd6; #1;
    check(read_data1, 32'hCAFE0006, "mismo registro en ambos puertos (1)");
    check(read_data2, 32'hCAFE0006, "mismo registro en ambos puertos (2)");

    // 6) La lectura es combinacional: cambia sin esperar el clock
    rs1 = 5'd5; #1;
    check(read_data1, 32'hDEADBEEF, "lectura combinacional: x5");
    rs1 = 5'd6; #1;
    check(read_data1, 32'hCAFE0006, "lectura combinacional: x6 sin clock");

    // 7) Lectura y escritura del mismo registro en el mismo ciclo:
    //    antes del flanco se lee el valor viejo, despues el nuevo
    @(negedge clk);
    rd = 5'd7; write_data = 32'hAAAA0007; reg_write = 1'b1; rs1 = 5'd7;
    #1;
    check(read_data1, 32'h0, "mismo ciclo: antes del flanco lee el valor viejo");
    @(posedge clk); #1; reg_write = 1'b0;
    check(read_data1, 32'hAAAA0007, "mismo ciclo: despues del flanco lee el nuevo");

    // 8) Los 31 registros son independientes: se escribe un valor distinto
    //    en cada uno y se lee todo de nuevo
    for (k = 1; k < 32; k = k + 1)
        write_reg(k[4:0], 32'h1000_0000 + k, 1'b1);
    for (k = 1; k < 32; k = k + 1) begin
        rs1 = k[4:0]; rs2 = k[4:0]; #1;
        check(read_data1, 32'h1000_0000 + k, "x1..x31 puerto 1");
        check(read_data2, 32'h1000_0000 + k, "x1..x31 puerto 2");
    end
    rs1 = 5'd0; #1;
    check(read_data1, 32'h0, "x0 sigue en 0 al final");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule