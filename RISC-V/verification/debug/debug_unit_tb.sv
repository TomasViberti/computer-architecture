`timescale 1ns / 1ps

// Testbench de la Debug Unit con el procesador real (top).
// Un modelo de la PC hace lo que va a hacer la herramienta de Python:
//   1. lee el programa de machine_code.txt y lo manda con LOAD,
//   2. manda RUN,
//   3. recibe el paquete de estado que la Debug Unit manda sola al llegar al HALT,
//   4. escribe RUTA_ESTADO con el mismo formato que rtl_state.txt.
// Despues se compara con el modelo en Python (monocycle_model.py) igual que siempre.
// Una simulacion = un programa (el procesador no vacia registros ni memoria entre programas).
//
// Archivos necesarios en el proyecto de Vivado: baud_rate_gen.v, uart_rx.v, uart_tx.v, debug_unit.v
// y los del procesador (top_monocycle.v y los modulos que instancia).
// Poner en RUTA_PROGRAMA y RUTA_ESTADO rutas absolutas con barras normales (/).
module debug_unit_top_tb;

localparam CLK_FREQ   = 50_000_000;
localparam BAUD       = 115200;
localparam real BIT_NS = 1.0e9 / BAUD;
localparam IMEM_DEPTH = 256;
localparam DMEM_DEPTH = 256;
localparam PKT_BYTES  = 1 + 1 + 4 + 4 + 128 + 2 + 4 * DMEM_DEPTH;

localparam RUTA_PROGRAMA = "F:/FACULTAD/5to/ArqDeComp/computer-architecture/RISC-V/scripts/machine_code.txt";
localparam RUTA_ESTADO = "F:/FACULTAD/5to/ArqDeComp/computer-architecture/RISC-V/scripts/rtl_state.txt";

reg clock = 1'b0;
always #10 clock = ~clock;                   // 50 MHz

reg rst_n = 1'b0;
initial begin repeat (10) @(posedge clock); rst_n = 1'b1; end

reg  rx_line = 1'b1;                         // PC -> FPGA
wire tx_line;                                // FPGA -> PC

wire        tick, rx_valid, tx_start, tx_busy;
wire [7:0]  rx_data, tx_data;
wire        cpu_rst_n, cpu_enable, cpu_halt, imem_err, dmem_err;
wire [31:0] cpu_pc;
wire        imem_we;
wire [7:0]  imem_waddr;
wire [31:0] imem_wdata;
wire [4:0]  dbg_reg_addr;
wire [7:0]  dbg_mem_addr;
wire [31:0] dbg_reg_data, dbg_mem_data;

baud_rate_gen #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD)) u_baud (.clock(clock), .i_rst_n(rst_n), .o_tick(tick));
uart_rx u_rx (.clock(clock), .i_rst_n(rst_n), .i_tick(tick), .i_rx(rx_line), .o_data(rx_data), .o_valid(rx_valid));
uart_tx u_tx (.clock(clock), .i_rst_n(rst_n), .i_tick(tick), .i_tx_start(tx_start), .i_data(tx_data),
              .o_tx(tx_line), .o_tx_done(), .o_tx_busy(tx_busy));

debug_unit #(.IMEM_DEPTH(IMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .CLK_FREQ(CLK_FREQ)) u_du (
    .clock(clock), .i_rst_n(rst_n),
    .i_rx_data(rx_data), .i_rx_valid(rx_valid), .i_tx_busy(tx_busy),
    .o_tx_data(tx_data), .o_tx_start(tx_start),
    .o_cpu_rst_n(cpu_rst_n), .o_cpu_enable(cpu_enable),
    .i_cpu_halt(cpu_halt), .i_cpu_pc(cpu_pc), .i_imem_err(imem_err), .i_dmem_err(dmem_err),
    .o_imem_we(imem_we), .o_imem_waddr(imem_waddr), .o_imem_wdata(imem_wdata),
    .o_dbg_reg_addr(dbg_reg_addr), .i_dbg_reg_data(dbg_reg_data),
    .o_dbg_mem_addr(dbg_mem_addr), .i_dbg_mem_data(dbg_mem_data));

top u_cpu (
    .clock(clock), .i_rst_n(cpu_rst_n), .i_enable(cpu_enable),
    .i_imem_write_enable(imem_we), .i_imem_write_addr(imem_waddr), .i_imem_write_data(imem_wdata),
    .o_pc(cpu_pc), .o_instr(), .o_halt(cpu_halt),
    .o_imem_addr_error(imem_err), .o_dmem_addr_error(dmem_err),
    .i_debug_reg_addr(dbg_reg_addr), .o_debug_reg_data(dbg_reg_data),
    .i_debug_mem_addr(dbg_mem_addr), .o_debug_mem_data(dbg_mem_data));

// ---------------- modelo de la PC ----------------
integer errors = 0;

task send_byte(input [7:0] b);
    integer i;
    begin
        rx_line = 1'b0; #(BIT_NS);
        for (i = 0; i < 8; i = i + 1) begin rx_line = b[i]; #(BIT_NS); end
        rx_line = 1'b1; #(BIT_NS);
    end
endtask

reg [7:0] rxq [0:4095];
integer   q_wr = 0, q_rd = 0;
reg [7:0] rcv;
integer   ri;
always @(negedge tx_line) begin : pc_rx
    #(BIT_NS * 1.5);
    for (ri = 0; ri < 8; ri = ri + 1) begin rcv[ri] = tx_line; #(BIT_NS); end
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

task expect_ok(input [8*30-1:0] msg);
    reg [7:0] b; reg ok;
    begin
        recv_byte(b, ok, 20000);
        if (!ok || b !== 8'h00) begin errors = errors + 1; $display("ERROR: %0s: respuesta %h (ok=%0d), se esperaba 00", msg, b, ok); end
    end
endtask

// ---------------- programa (de machine_code.txt) ----------------
reg [31:0] prog [0:IMEM_DEPTH-1];
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
            if (n == 2 && idx >= 0 && idx < IMEM_DEPTH) begin
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

function [31:0] w32(input integer off);       // 4 bytes del paquete, el menos significativo primero
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

initial begin
    wait (rst_n);
    repeat (20) @(posedge clock);
    leer_programa;

    // 1. LOAD
    send_byte(8'h01); send_byte(n_words[7:0]); send_byte(n_words[15:8]);
    for (k = 0; k < n_words; k = k + 1) send_word(prog[k]);
    expect_ok("OK de LOAD");

    // 2. RUN
    send_byte(8'h02);
    expect_ok("OK de RUN");

    // 3. El estado llega solo, cuando el programa termina
    for (k = 0; k < PKT_BYTES; k = k + 1) begin
        recv_byte(b, ok, 200000);
        if (!ok) begin errors = errors + 1; $display("ERROR: el paquete se corto en el byte %0d de %0d", k, PKT_BYTES); k = PKT_BYTES; end
        else pkt[k] = b;
    end

    if (errors == 0) begin
        if (pkt[0] !== 8'h10)                 begin errors = errors + 1; $display("ERROR: el tipo del paquete es %h, se esperaba 10", pkt[0]); end
        if ({pkt[139], pkt[138]} !== DMEM_DEPTH) begin errors = errors + 1; $display("ERROR: cantidad de palabras de memoria = %0d, se esperaba %0d", {pkt[139], pkt[138]}, DMEM_DEPTH); end
        if (errors == 0) begin
            escribir_estado;
            $display("Paquete de %0d bytes recibido. PC final = %h, CICLOS = %0d", PKT_BYTES, w32(2), w32(6));
        end
    end
    #(300_000.0);
    if (q_rd != q_wr) begin errors = errors + 1; $display("ERROR: la FPGA mando bytes de mas despues del paquete"); end
    $display(errors == 0 ? "OK: LOAD, RUN y estado completados" : "HUBO ERRORES");
    $finish;
end

initial begin #3_000_000_000; $display("TIMEOUT GLOBAL DEL TESTBENCH"); $finish; end

endmodule