`timescale 1ns / 1ps

// Testbench de los puertos de debug del top (i_debug_reg_addr / o_debug_reg_data e i_debug_mem_addr / o_debug_mem_data).
// Es igual a top_monocycle_tb_from_file.sv, salvo que:
//   - el estado final se lee por los puertos de debug (y no por referencias jerarquicas) y se compara con ellas;
//   - durante la ejecucion las direcciones de debug cambian en cada ciclo, para comprobar que no alteran al procesador.
// Escribe rtl_state.txt con el mismo formato, asi que se compara con el modelo igual que siempre.
//
// Descripcion del testbench base:
// Testbench del top monociclo, version que LEE el programa desde un archivo.
// Lee las lineas  prog[n] = 32'h...;  de machine_code.txt (el que genera el ensamblador), lo carga
// por el puerto de escritura de la memoria de instrucciones, lo ejecuta hasta el HALT y escribe el
// estado final en un archivo, para compararlo con el modelo en python.
//
// Con un programa nuevo no hay que tocar este archivo:
//   1) python assembler.py                    -> machine_code.txt
//   2) en Vivado: Restart (no hace falta recompilar: el archivo se vuelve a leer al empezar)
//   3) python monocycle_model.py --rtl <RUTA_ESTADO>
//
// Solo hay que ajustar RUTA_PROGRAMA y RUTA_ESTADO una vez (rutas absolutas con barras normales /).
// Es la alternativa a top_monocycle_tb.sv, donde el programa se pega dentro del testbench.

module top_tb_debug;   // nombre distinto al de top_monocycle_tb.sv para que no choquen en el proyecto

localparam PROG_LEN   = 256;   // palabras que se cargan; lo que no se pega queda en HALT
localparam DMEM_DEPTH = 256;   // palabras de la memoria de datos (igual que el top)
localparam MAX_CYCLES = 500;   // igual que --max-ciclos de modelo.py

localparam RUTA_PROGRAMA = "F:/FACULTAD/5to/ArqDeComp/computer-architecture/RISC-V/scripts/machine_code.txt";
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

// Puertos de debug. Durante la ejecucion las direcciones cambian en cada ciclo (para comprobar que no
// alteran al procesador) y despues se recorren en orden para volcar el estado.
reg  [4:0]  dbg_reg_addr = 5'd0;
reg  [7:0]  dbg_mem_addr = 8'd0;
wire [31:0] dbg_reg_data, dbg_mem_data;
reg         scramble = 1'b1;
integer     dbg_diff = 0;
integer exec_cycles = 0;
reg imem_err_seen = 1'b0, dmem_err_seen = 1'b0;
reg [31:0] prog [0:PROG_LEN-1];

top dut (
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
    .o_dmem_addr_error(dmem_err),
    .i_debug_reg_addr(dbg_reg_addr),
    .o_debug_reg_data(dbg_reg_data),
    .i_debug_mem_addr(dbg_mem_addr),
    .o_debug_mem_data(dbg_mem_data)
);

always @(posedge clock) if (scramble) begin dbg_reg_addr <= $random; dbg_mem_addr <= $random; end

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
            for (i = 0; i < 32; i = i + 1) begin dbg_reg_addr = i; #1; $fdisplay(fd, "x%0d=%08h", i, dbg_reg_data); if (dbg_reg_data !== reg_val(i)) dbg_diff = dbg_diff + 1; end
            for (i = 0; i < DMEM_DEPTH; i = i + 1) begin
                dbg_mem_addr = i; #1; w = dbg_mem_data; if (w !== mem_word(i)) dbg_diff = dbg_diff + 1;
                if (w != 32'h0) $fdisplay(fd, "MEM[0x%08h]=%08h", i * 4, w);
            end
            $fclose(fd);
            $display("Lectura por puertos de debug: %0d diferencias contra las referencias jerarquicas", dbg_diff);
            $display("Estado final escrito en %0s", RUTA_ESTADO);
        end
    end
endtask

// Lee de RUTA_PROGRAMA las lineas  prog[n] = 32'hXXXXXXXX;  (las demas lineas, como los
// comentarios, se ignoran). Lo que no aparece en el archivo queda en HALT.
task cargar_programa;
    integer fd, r, n, idx, cargadas;
    reg [31:0]      palabra;
    reg [8*256-1:0] linea;
    begin
        cargadas = 0;
        fd = $fopen(RUTA_PROGRAMA, "r");
        if (fd == 0) begin
            $display("ERROR: no se pudo abrir %0s (revisa RUTA_PROGRAMA)", RUTA_PROGRAMA);
            $finish;
        end
        r = $fgets(linea, fd);
        while (r != 0) begin
            n = $sscanf(linea, "prog[%d] = 32'h%h;", idx, palabra);
            if (n == 2) begin
                if (idx >= 0 && idx < PROG_LEN) begin
                    prog[idx] = palabra;
                    cargadas = cargadas + 1;
                end else
                    $display("ATENCION: prog[%0d] esta fuera de la memoria de programa, se ignora", idx);
            end
            r = $fgets(linea, fd);
        end
        $fclose(fd);
        if (cargadas == 0) begin
            $display("ERROR: no hay ninguna linea  prog[n] = 32'h...;  en %0s", RUTA_PROGRAMA);
            $finish;
        end
        $display("Programa leido de %0s: %0d palabras", RUTA_PROGRAMA, cargadas);
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
    // ---------------- PROGRAMA (se lee de RUTA_PROGRAMA) ----------------
    for (k = 0; k < PROG_LEN; k = k + 1) prog[k] = 32'h0000000B;   // lo que no esta en el archivo queda en HALT
    cargar_programa;

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
    scramble = 1'b0;
    escribir_estado;
    $finish;
end

endmodule