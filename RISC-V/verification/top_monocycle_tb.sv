`timescale 1ns / 1ps

// Testbench del top monociclo: carga un programa por el puerto de escritura
// de la memoria de instrucciones, lo ejecuta hasta el HALT y revisa el estado
// final de los registros y de la memoria de datos (por referencia jerarquica).

module top_tb;

localparam PROG_LEN  = 40;
localparam MAX_CYCLES = 500;

reg         clock = 1'b0;
always #5 clock = ~clock;

reg         rst_n = 1'b0, enable = 1'b0;
reg         we = 1'b0;
reg  [7:0]  waddr = 0;
reg  [31:0] wdata = 0;

wire [31:0] pc, instr;
wire        halt, imem_err, dmem_err;

integer errors = 0, tests = 0, k, cycles;
reg [31:0] prog [0:PROG_LEN-1];

top dut (
    .clock(clock), .i_rst_n(rst_n), .i_enable(enable),
    .i_imem_write_enable(we), .i_imem_write_addr(waddr), .i_imem_write_data(wdata),
    .o_pc(pc), .o_instr(instr), .o_halt(halt),
    .o_imem_addr_error(imem_err), .o_dmem_addr_error(dmem_err)
);

// Lectura de registros y memoria de datos desde adentro del top
function [31:0] reg_val;
    input [4:0] r;
    reg_val = (r == 0) ? 32'b0 : dut.u_regfile.regs[r];
endfunction

function [31:0] mem_word;
    input integer idx;
    mem_word = {dut.u_data_mem.mem_b3[idx], dut.u_data_mem.mem_b2[idx],
                dut.u_data_mem.mem_b1[idx], dut.u_data_mem.mem_b0[idx]};
endfunction

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
    begin
        @(negedge clock);
        waddr = a; wdata = d; we = 1'b1;
        @(posedge clock);
        #1 we = 1'b0;
    end
endtask

// Monitor: una linea por instruccion ejecutada
always @(posedge clock)
    if (rst_n && enable && !halt)
        $display("  [ciclo] PC = %h  instr = %h", pc, instr);

initial begin
    // ---------------- PROGRAMA ----------------
    prog[ 0] = 32'h00500093;   // 0x00  addi x1, x0, 5
    prog[ 1] = 32'h00700113;   // 0x04  addi x2, x0, 7
    prog[ 2] = 32'h002081B3;   // 0x08  add  x3, x1, x2
    prog[ 3] = 32'h40110233;   // 0x0C  sub  x4, x2, x1
    prog[ 4] = 32'h0020F2B3;   // 0x10  and  x5, x1, x2
    prog[ 5] = 32'h0020E333;   // 0x14  or   x6, x1, x2
    prog[ 6] = 32'h0020C3B3;   // 0x18  xor  x7, x1, x2
    prog[ 7] = 32'h00309413;   // 0x1C  slli x8, x1, 3
    prog[ 8] = 32'hFF000493;   // 0x20  addi x9, x0, -16
    prog[ 9] = 32'h4024D513;   // 0x24  srai x10, x9, 2
    prog[10] = 32'h01C4D593;   // 0x28  srli x11, x9, 28
    prog[11] = 32'h0014A633;   // 0x2C  slt  x12, x9, x1
    prog[12] = 32'h0014B6B3;   // 0x30  sltu x13, x9, x1
    prog[13] = 32'h12345737;   // 0x34  lui  x14, 0x12345
    prog[14] = 32'h00302023;   // 0x38  sw   x3, 0(x0)
    prog[15] = 32'h00902223;   // 0x3C  sw   x9, 4(x0)
    prog[16] = 32'h001004A3;   // 0x40  sb   x1, 9(x0)
    prog[17] = 32'h00002783;   // 0x44  lw   x15, 0(x0)
    prog[18] = 32'h00400803;   // 0x48  lb   x16, 4(x0)
    prog[19] = 32'h00404883;   // 0x4C  lbu  x17, 4(x0)
    prog[20] = 32'h00401903;   // 0x50  lh   x18, 4(x0)
    prog[21] = 32'h00802983;   // 0x54  lw   x19, 8(x0)
    prog[22] = 32'h00000A13;   // 0x58  addi x20, x0, 0
    prog[23] = 32'h00500A93;   // 0x5C  addi x21, x0, 5
    prog[24] = 32'h015A0A33;   // 0x60  loop: add x20, x20, x21
    prog[25] = 32'hFFFA8A93;   // 0x64  addi x21, x21, -1
    prog[26] = 32'hFE0A9CE3;   // 0x68  bne  x21, x0, loop
    prog[27] = 32'h00000463;   // 0x6C  beq  x0, x0, +8
    prog[28] = 32'h06300B13;   // 0x70  addi x22, x0, 99   (no se ejecuta)
    prog[29] = 32'h00C00BEF;   // 0x74  jal  x23, +12
    prog[30] = 32'h06300C13;   // 0x78  addi x24, x0, 99   (no se ejecuta)
    prog[31] = 32'h06200C13;   // 0x7C  addi x24, x0, 98   (no se ejecuta)
    prog[32] = 32'h09500C93;   // 0x80  addi x25, x0, 0x95
    prog[33] = 32'h000C8D67;   // 0x84  jalr x26, 0(x25)  -> salta a 0x94 (bit 0 en 0)
    prog[34] = 32'h06100C13;   // 0x88  addi x24, x0, 97   (no se ejecuta)
    prog[35] = 32'h06000C13;   // 0x8C  addi x24, x0, 96   (no se ejecuta)
    prog[36] = 32'h05F00C13;   // 0x90  addi x24, x0, 95   (no se ejecuta)
    prog[37] = 32'h00100013;   // 0x94  addi x0, x0, 1     (x0 no cambia)
    prog[38] = 32'h00100D93;   // 0x98  addi x27, x0, 1
    prog[39] = 32'h0000000B;   // 0x9C  halt

    // ---------------- CARGA (procesador detenido) ----------------
    #12;
    for (k = 0; k < PROG_LEN; k = k + 1) write_word(k[7:0], prog[k]);

    @(negedge clock); rst_n = 1'b1;
    #1; check(pc, 32'h0, "despues del reset PC = 0");
    check(instr, prog[0], "la instruccion 0 quedo cargada");

    // Con enable = 0 el procesador no avanza ni escribe
    repeat (3) @(posedge clock);
    #1; check(pc, 32'h0, "enable = 0: el PC no avanza");
    check(reg_val(1), 32'h0, "enable = 0: no se escribe x1");

    // ---------------- EJECUCION ----------------
    @(negedge clock); enable = 1'b1;
    cycles = 0;
    while (!halt && cycles < MAX_CYCLES) begin
        @(posedge clock); #1;
        cycles = cycles + 1;
    end
    $display("HALT alcanzado en %0d ciclos (PC = %h)", cycles, pc);

    check({31'b0, halt}, 32'd1, "se llega al HALT");
    check(pc, 32'h9C, "PC final = 0x9C");
    // 24 instrucciones hasta el loop + 3*5 del loop + beq, jal, addi, jalr, addi x0, addi x27
    check(cycles, 32'd45, "cantidad de ciclos hasta el HALT");

    // ---------------- RESULTADOS ----------------
    check(reg_val(0),  32'h0000_0000, "x0  = 0 (no se escribe)");
    check(reg_val(1),  32'h0000_0005, "x1  addi");
    check(reg_val(2),  32'h0000_0007, "x2  addi");
    check(reg_val(3),  32'h0000_000C, "x3  add");
    check(reg_val(4),  32'h0000_0002, "x4  sub");
    check(reg_val(5),  32'h0000_0005, "x5  and");
    check(reg_val(6),  32'h0000_0007, "x6  or");
    check(reg_val(7),  32'h0000_0002, "x7  xor");
    check(reg_val(8),  32'h0000_0028, "x8  slli");
    check(reg_val(9),  32'hFFFF_FFF0, "x9  addi negativo");
    check(reg_val(10), 32'hFFFF_FFFC, "x10 srai");
    check(reg_val(11), 32'h0000_000F, "x11 srli");
    check(reg_val(12), 32'h0000_0001, "x12 slt");
    check(reg_val(13), 32'h0000_0000, "x13 sltu");
    check(reg_val(14), 32'h1234_5000, "x14 lui");
    check(reg_val(15), 32'h0000_000C, "x15 lw");
    check(reg_val(16), 32'hFFFF_FFF0, "x16 lb (con signo)");
    check(reg_val(17), 32'h0000_00F0, "x17 lbu");
    check(reg_val(18), 32'hFFFF_FFF0, "x18 lh");
    check(reg_val(19), 32'h0000_0500, "x19 lw despues de sb");
    check(reg_val(20), 32'h0000_000F, "x20 loop con bne (5+4+3+2+1)");
    check(reg_val(21), 32'h0000_0000, "x21 contador del loop");
    check(reg_val(22), 32'h0000_0000, "x22 beq salto la instruccion");
    check(reg_val(23), 32'h0000_0078, "x23 jal guarda PC + 4");
    check(reg_val(24), 32'h0000_0000, "x24 jal / jalr saltaron las instrucciones");
    check(reg_val(25), 32'h0000_0095, "x25 direccion de jalr");
    check(reg_val(26), 32'h0000_0088, "x26 jalr guarda PC + 4");
    check(reg_val(27), 32'h0000_0001, "x27 se ejecuta el destino de jalr");

    check(mem_word(0), 32'h0000_000C, "mem[0x0] sw");
    check(mem_word(1), 32'hFFFF_FFF0, "mem[0x4] sw");
    check(mem_word(2), 32'h0000_0500, "mem[0x8] sb en el byte 1");
    check({31'b0, dmem_err}, 32'd0, "sin errores de direccion en datos");

    // ---------------- HALT ----------------
    repeat (5) @(posedge clock);
    #1; check(pc, 32'h9C, "en HALT el PC queda quieto");
    check(reg_val(27), 32'h0000_0001, "en HALT no cambian los registros");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule
