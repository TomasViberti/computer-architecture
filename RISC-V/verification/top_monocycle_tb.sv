`timescale 1ns / 1ps

// Testbench del top monociclo.
// Carga un programa por el puerto de escritura de la memoria de instrucciones
// lo ejecuta hasta el HALT y escribe el estado final en un archivo, 
// para compararlo con el modelo en python.
//
// Con un programa nuevo:
//   1) python ensamblador.py                  -> programa_maquina.txt
//   2) pegar su contenido entre los marcadores PEGAR AQUI / FIN DEL PROGRAMA
//   3) poner en RUTA_ESTADO una ruta absoluta con barras normales (/)
//   4) simular y correr:  python modelo.py --rtl <RUTA_ESTADO>

module top_monocycle_tb;

localparam PROG_LEN   = 256;   // palabras que se cargan; lo que no se pega queda en HALT
localparam DMEM_DEPTH = 256;   // palabras de la memoria de datos (igual que el top)
localparam MAX_CYCLES = 500;   // igual que --max-ciclos de modelo.py

localparam RUTA_ESTADO = "F:/FACULTAD/5to/ArqDeComp/computer-architecture/RISC-V/scripts/rtl_state.txt";

reg         clock = 1'b0;
always #5 clock = ~clock;

reg         rst_n = 1'b0, enable = 1'b0;
reg         we = 1'b0;
reg  [7:0]  waddr = 0;
reg  [31:0] wdata = 0;

wire [31:0] pc, instr;
wire        halt, imem_err, dmem_err;

integer k, cycles;
integer exec_cycles = 0;
reg imem_err_seen = 1'b0, dmem_err_seen = 1'b0;
reg [31:0] prog [0:PROG_LEN-1];

top_monocycle dut (
    .clock(clock), 
    .i_rst_n(rst_n), 
    .i_enable(enable),
    .i_imem_write_enable(we), 
    .i_imem_write_addr(waddr), 
    .i_imem_write_data(wdata),
    .o_pc(pc), 
    .o_instr(instr), 
    .o_halt(halt),
    .o_imem_addr_error(imem_err), 
    .o_dmem_addr_error(dmem_err)
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

// Escribe el estado final en RUTA_ESTADO (mismo formato que estado_modelo.txt)
task escribir_estado;
    integer fd, i;
    reg [31:0] w;
    begin
        fd = $fopen(RUTA_ESTADO, "w");
        if (fd == 0) $display("ERROR: no se pudo abrir %0s para escribir el estado", RUTA_ESTADO);
        else begin
            $fdisplay(fd, "PC=%08h", pc);
            $fdisplay(fd, "CICLOS=%0d", exec_cycles);
            $fdisplay(fd, "HALT=%0d", halt);
            $fdisplay(fd, "ERROR_IMEM=%0d", imem_err_seen);
            $fdisplay(fd, "ERROR_DMEM=%0d", dmem_err_seen);
            for (i = 0; i < 32; i = i + 1) $fdisplay(fd, "x%0d=%08h", i, reg_val(i));
            for (i = 0; i < DMEM_DEPTH; i = i + 1) begin
                w = mem_word(i);
                if (w != 32'h0) $fdisplay(fd, "MEM[0x%08h]=%08h", i * 4, w);
            end
            $fclose(fd);
            $display("Estado final escrito en %0s", RUTA_ESTADO);
        end
    end
endtask

// Monitor: una linea por instruccion ejecutada
always @(posedge clock)
    if (rst_n && enable && !halt)
        $display("  [ciclo] PC = %h  instr = %h", pc, instr);

// Cuenta las instrucciones ejecutadas y recuerda si alguna señal de error se activo
// (las señales de error son combinacionales)
always @(posedge clock) begin
    if (rst_n && enable && !halt) exec_cycles <= exec_cycles + 1;
    if (imem_err)                 imem_err_seen <= 1'b1;
    if (enable && dmem_err)       dmem_err_seen <= 1'b1;
end

initial begin
    // ---------------- PROGRAMA ----------------
    for (k = 0; k < PROG_LEN; k = k + 1) prog[k] = 32'h0000000B;   // lo no pegado queda en HALT

    // >>>>>>>>>> PEGAR AQUI EL PROGRAMA >>>>>>>>>>

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

    // <<<<<<<<<< FIN DEL PROGRAMA <<<<<<<<<<

    // ---------------- CARGA (procesador detenido) ----------------
    #50;
    for (k = 0; k < PROG_LEN; k = k + 1) write_word(k[7:0], prog[k]);

    // ---------------- EJECUCION ----------------
    @(negedge clock); rst_n = 1'b1;
    @(negedge clock); enable = 1'b1;
    cycles = 0;
    while (!halt && cycles < MAX_CYCLES) begin
        @(posedge clock); #1;
        cycles = cycles + 1;
    end

    // Dos ciclos mas detenido (para que se registren las señales de error) y se escribe el estado
    @(negedge clock); enable = 1'b0;
    repeat (2) @(posedge clock);
    #1;
    if (halt) $display("HALT alcanzado en %0d ciclos (PC = %h)", exec_cycles, pc);
    else      $display("ATENCION: no llego al HALT en %0d ciclos", MAX_CYCLES);
    escribir_estado;
    $finish;
end

endmodule