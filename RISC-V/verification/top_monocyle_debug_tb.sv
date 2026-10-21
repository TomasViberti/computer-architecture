`timescale 1ns / 1ps

// Testbench del top de la FPGA, visto desde los pines de la placa.
// El modelo de la PC maneja el clock de 100 MHz, el switch de reset (1 = funciona, 0 = reset) y la linea serie, y hace:
//   1. El switch arranca en 1: el sistema solo puede salir de reset cuando el clock engancha (locked).
//      Se informa en que momento engancha y se comprueba, durante toda la simulacion, que el sistema
//      nunca sale de reset con el clock sin enganchar.
//   2. Carga un programa que nunca termina (jal x0, 0), lo ejecuta y comprueba que no llega
//      ninguna respuesta. Despues baja el switch (el sistema tiene que quedar en reset) y lo sube,
//      y comprueba que el procesador se detiene. Ese programa no escribe registros ni memoria,
//      asi que no ensucia el estado.
//   3. Carga el programa de RUTA_PROGRAMA, lo ejecuta, recibe el estado por UART y escribe
//      RUTA_ESTADO con el mismo formato que rtl_state.txt, para compararlo con el modelo.
//      El estado se escribe aunque antes haya habido otros errores.
// Al final se imprime un resumen con todos los errores.
//
// En Vivado el Clocking Wizard (clk_wiz_0) tiene que estar en el proyecto. Poner en
// RUTA_PROGRAMA y RUTA_ESTADO rutas absolutas con barras normales (/).
// La simulacion completa son unos 125 ms: en xsim puede tardar varios minutos.
module top_monocycle_debug_tb;

localparam BAUD       = 115200;
localparam real BIT_NS = 1.0e9 / BAUD;
localparam DMEM_DEPTH = 256;
localparam PKT_BYTES  = 1 + 1 + 4 + 4 + 128 + 2 + 4 * DMEM_DEPTH;

localparam RUTA_PROGRAMA = "F:/FACULTAD/5to/ArqDeComp/computer-architecture/RISC-V/scripts/machine_code.txt";
localparam RUTA_ESTADO   = "F:/FACULTAD/5to/ArqDeComp/computer-architecture/RISC-V/scripts/rtl_state.txt";

reg         i_clk = 1'b0;
reg         i_rst_n = 1'b1;             // el switch arranca en 1: el sistema espera solo al clock
reg         i_uart_rx = 1'b1;           // PC -> FPGA
wire        o_uart_tx;                  // FPGA -> PC
wire [2:0]  o_led;

always #5 i_clk = ~i_clk;               // 100 MHz

top_monocycle_debug dut (
    .clock     (i_clk     ),
    .i_rst_n   (i_rst_n   ),
    .i_uart_rx (i_uart_rx ),
    .o_uart_tx (o_uart_tx ),
    .o_led     (o_led     )
);

// ---------------- registro de errores ----------------
// Cada error se imprime en el momento y ademas queda guardado para el resumen final.
integer errors = 0;
reg [8*160-1:0] errlog [0:31];
reg [8*160-1:0] tmp;

task registrar(input [8*160-1:0] msg);
    begin
        if (errors < 32) errlog[errors] = msg;
        errors = errors + 1;
        $display("ERROR %0d (t = %0t): %0s", errors, $time, msg);
    end
endtask

task check(input cond, input [8*160-1:0] msg);
    begin if (!cond) registrar(msg); end
endtask

// ---------------- modelo de la PC ----------------
task send_byte(input [7:0] b);
    integer i;
    begin
        i_uart_rx = 1'b0; #(BIT_NS);
        for (i = 0; i < 8; i = i + 1) begin i_uart_rx = b[i]; #(BIT_NS); end
        i_uart_rx = 1'b1; #(BIT_NS);
    end
endtask

reg [7:0] rxq [0:4095];
integer   q_wr = 0, q_rd = 0;
reg [7:0] rcv;
integer   ri;
always @(negedge o_uart_tx) begin : pc_rx
    #(BIT_NS * 1.5);
    for (ri = 0; ri < 8; ri = ri + 1) begin rcv[ri] = o_uart_tx; #(BIT_NS); end
    rxq[q_wr % 4096] = rcv;
    q_wr = q_wr + 1;
end

task recv_byte(output [7:0] b, output ok, input integer timeout_us);
    integer t;
    begin
        t = 0;
        while (q_rd == q_wr && t < timeout_us * 5) begin #200; t = t + 1; end
        if (q_rd != q_wr) begin b = rxq[q_rd % 4096]; q_rd = q_rd + 1; ok = 1'b1; end
        else              begin b = 8'h00; ok = 1'b0; end
    end
endtask

task send_word(input [31:0] w);
    begin send_byte(w[7:0]); send_byte(w[15:8]); send_byte(w[23:16]); send_byte(w[31:24]); end
endtask

task expect_ok(input [8*60-1:0] msg);
    reg [7:0] b; reg ok;
    begin
        recv_byte(b, ok, 20000);
        if (!ok || b !== 8'h00) begin
            $sformat(tmp, "%0s: respuesta %h (hubo respuesta = %0d), se esperaba 00", msg, b, ok);
            registrar(tmp);
        end
    end
endtask

// Espera (hasta 1 ms) a que el sistema salga de reset; si no sale, lo informa.
// El tiempo que tarda el MMCM en enganchar depende del modelo: no se supone ninguno.
task esperar_fuera_de_reset(input [8*60-1:0] msg);
    integer t;
    begin
        t = 0;
        while (o_led[1] !== 1'b1 && t < 1000) begin #1000; t = t + 1; end
        if (o_led[1] !== 1'b1) begin
            $sformat(tmp, "%0s: el sistema no sale de reset (led = %b)", msg, o_led);
            registrar(tmp);
        end
    end
endtask

// ---------------- reglas que se vigilan siempre ----------------
// 1. El sistema nunca sale de reset con el clock sin enganchar (led[1] implica led[0]).
// 2. El procesador recibe el reset y el enable de la Debug Unit.
integer lock_err = 0, wiring_err = 0;
always @(posedge i_clk) begin
    if (o_led[1] === 1'b1 && o_led[0] !== 1'b1) lock_err = lock_err + 1;
    if (dut.u_cpu.i_rst_n !== dut.u_debug.o_cpu_rst_n || dut.u_cpu.i_enable !== dut.u_debug.o_cpu_enable) wiring_err = wiring_err + 1;
end

// Informa cuando cambia locked (para saber cuando engancha el MMCM)
always @(o_led[0]) $display("[%0t] locked = %b", $time, o_led[0]);

// ---------------- programa (de machine_code.txt) ----------------
reg [31:0] prog [0:255];
integer    n_words;

task leer_programa;
    integer fd, r, n, idx;
    reg [31:0]      palabra;
    reg [8*256-1:0] linea;
    begin
        n_words = 0;
        fd = $fopen(RUTA_PROGRAMA, "r");
        if (fd == 0) begin $display("ERROR: no se pudo abrir %0s", RUTA_PROGRAMA); $finish; end
        r = $fgets(linea, fd);
        while (r != 0) begin
            n = $sscanf(linea, "prog[%d] = 32'h%h;", idx, palabra);
            if (n == 2 && idx >= 0 && idx < 256) begin
                prog[idx] = palabra;
                if (idx + 1 > n_words) n_words = idx + 1;
            end
            r = $fgets(linea, fd);
        end
        $fclose(fd);
        if (n_words == 0) begin $display("ERROR: no hay ninguna linea prog[n] = 32'h...; en %0s", RUTA_PROGRAMA); $finish; end
        $display("Programa leido de %0s: %0d palabras", RUTA_PROGRAMA, n_words);
    end
endtask

// ---------------- paquete de estado ----------------
reg [7:0] pkt [0:PKT_BYTES-1];

function [31:0] w32(input integer off);
    w32 = {pkt[off + 3], pkt[off + 2], pkt[off + 1], pkt[off]};
endfunction

task escribir_estado;
    integer fd, i, nw;
    reg [31:0] w;
    begin
        fd = $fopen(RUTA_ESTADO, "w");
        if (fd == 0) begin $display("ERROR: no se pudo abrir %0s para escribir", RUTA_ESTADO); $finish; end
        $fdisplay(fd, "PC=%08h", w32(2));
        $fdisplay(fd, "CICLOS=%0d", w32(6));
        $fdisplay(fd, "HALT=%0d", pkt[1][0]);
        $fdisplay(fd, "ERROR_IMEM=%0d", pkt[1][1]);
        $fdisplay(fd, "ERROR_DMEM=%0d", pkt[1][2]);
        for (i = 0; i < 32; i = i + 1) $fdisplay(fd, "x%0d=%08h", i, w32(10 + 4 * i));
        nw = {pkt[139], pkt[138]};
        for (i = 0; i < nw; i = i + 1) begin
            w = w32(140 + 4 * i);
            if (w != 32'h0) $fdisplay(fd, "MEM[0x%08h]=%08h", i * 4, w);
        end
        $fclose(fd);
        $display("Estado recibido por UART escrito en %0s", RUTA_ESTADO);
    end
endtask

integer k;
reg [7:0] b; reg ok;
reg paquete_ok;

initial begin
    $timeformat(-6, 3, " us", 0);

    // ---- arranque: el switch esta en 1, el sistema espera solo al clock ----
    esperar_fuera_de_reset("al arrancar");
    check(o_led[0] === 1'b1, "el sistema salio de reset sin que el clock este enganchado");
    #(1000.0);
    check(o_uart_tx === 1'b1, "tx tiene que estar en reposo (1)");
    leer_programa;

    // ---- programa que no termina + reset por switch ----
    send_byte(8'h01); send_byte(8'h01); send_byte(8'h00); send_word(32'h0000_006F);   // LOAD de 1 palabra: jal x0, 0
    expect_ok("OK de LOAD (bucle)");
    send_byte(8'h02);
    expect_ok("OK de RUN (bucle)");
    #(3_000_000.0);                                  // 3 ms
    check(o_led[2] === 1'b1, "el procesador tendria que seguir ejecutando el bucle");
    check(q_rd == q_wr,      "no tendria que llegar nada: el programa no termina");
    i_rst_n = 1'b0; #(1000.0);                       // se baja el switch
    check(o_led[1] === 1'b0, "con el switch en 0 el sistema tiene que estar en reset (aunque el clock este enganchado)");
    check(o_led[0] === 1'b1, "el switch no tiene que tocar al clock: locked tiene que seguir en 1");
    i_rst_n = 1'b1;                                  // se sube el switch
    esperar_fuera_de_reset("despues del reset por switch");
    #(500.0);
    check(o_led[2] === 1'b0, "despues del reset el procesador tiene que estar detenido");
    $display("Reset por switch: el programa que no termina se corto");

    $display("\n----- Flujo completo con el programa de prueba -----");
    send_byte(8'h01); send_byte(n_words[7:0]); send_byte(n_words[15:8]);
    for (k = 0; k < n_words; k = k + 1) send_word(prog[k]);
    expect_ok("OK de LOAD");
    send_byte(8'h02);
    expect_ok("OK de RUN");
    paquete_ok = 1'b1;
    for (k = 0; k < PKT_BYTES; k = k + 1) begin
        recv_byte(b, ok, 200000);
        if (!ok) begin
            $sformat(tmp, "el paquete de estado se corto en el byte %0d de %0d", k, PKT_BYTES);
            registrar(tmp);
            paquete_ok = 1'b0;
            k = PKT_BYTES;
        end else pkt[k] = b;
    end
    // El estado se procesa aunque antes haya habido otros errores
    if (paquete_ok) begin
        if (pkt[0] !== 8'h10) begin
            $sformat(tmp, "el tipo del paquete es %h, se esperaba 10", pkt[0]);
            registrar(tmp);
            paquete_ok = 1'b0;
        end
        if ({pkt[139], pkt[138]} !== DMEM_DEPTH) begin
            $sformat(tmp, "cantidad de palabras de memoria = %0d, se esperaba %0d", {pkt[139], pkt[138]}, DMEM_DEPTH);
            registrar(tmp);
            paquete_ok = 1'b0;
        end
        if (paquete_ok) begin
            escribir_estado;
            $display("Paquete de %0d bytes recibido. PC final = %h, CICLOS = %0d", PKT_BYTES, w32(2), w32(6));
        end
    end
    #(300_000.0);
    check(q_rd == q_wr,       "la FPGA mando bytes de mas despues del paquete");
    check(o_led[2] === 1'b0,  "al terminar, el procesador tiene que quedar detenido");
    check(lock_err == 0,      "el sistema salio de reset con el clock sin enganchar");
    check(wiring_err == 0,    "el reset y el enable del procesador no vienen de la Debug Unit");

    // ---- resumen ----
    $display("\n========== RESUMEN ==========");
    if (errors == 0) $display("OK: top completo (0 errores)");
    else begin
        $display("HUBO %0d ERRORES:", errors);
        for (k = 0; k < errors && k < 32; k = k + 1) $display("  %0d) %0s", k + 1, errlog[k]);
    end
    $finish;
end

// Seguro contra cuelgues: 1 s simulado (el retardo tiene que entrar en 32 bits con signo)
initial begin #1_000_000_000; $display("TIMEOUT GLOBAL DEL TESTBENCH"); $finish; end

endmodule