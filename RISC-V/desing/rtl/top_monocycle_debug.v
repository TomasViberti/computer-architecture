/* ----------------------------------------------------------------------
   TOP MONOCYCLE DEBUG

   Clock
   -----
   La placa da 100 MHz. El Clocking Wizard (clk_wiz_0) los baja a los 50 MHz con los
   que trabaja todo el sistema (UART, Debug Unit y procesador).

   Reset
   -----
   Un switch de la placa (SW0) maneja el reset del sistema, con logica negada:
   switch en 1 = el sistema funciona, switch en 0 = el sistema esta en reset.
   El reset tambien se mantiene mientras el MMCM no este enganchado (locked = 0): el
   sistema solo arranca con el clock estable, aunque el switch este en 1 desde el inicio.
   Se activa sin esperar al clock y se suelta sincronizado con el clock de 50 MHz.
   Bajar y subir el switch es la forma de cortar un programa que no termina nunca.

   LEDs
   ----
   o_led[0]  clock listo (locked)
   o_led[1]  sistema fuera de reset
   o_led[2]  el procesador esta ejecutando (queda prendido si el programa no termina)
---------------------------------------------------------------------- */

module top_monocycle_debug
#(
    parameter CLK_FREQ   = 50_000_000   ,   // Hz, salida del Clocking Wizard
    parameter BAUD_RATE  = 115200       ,
    parameter IMEM_DEPTH = 256          ,   // palabras de programa
    parameter DMEM_DEPTH = 256          ,   // palabras de datos
    parameter TIMEOUT_MS = 100              
)
(
    input  wire         clock       ,   
    input  wire         i_rst_n     ,   
    input  wire         i_uart_rx   ,   
    output wire         o_uart_tx   ,   
    output wire [2 : 0] o_led
);

localparam IMEM_ADDR_BITS = $clog2(IMEM_DEPTH);
localparam DMEM_ADDR_BITS = $clog2(DMEM_DEPTH);

// ---------------- CLOCK 50 MHz ----------------

wire clock_50mhz;
wire locked;

clk_wiz_0 u_clk (
    .clk_in1  (clock        ),
    .clk_out1 (clock_50mhz  ),
    .locked   (locked       )
);

// ---------------- RST ----------------

wire rst_n_raw = locked & i_rst_n;

(* ASYNC_REG = "TRUE" *) reg [1 : 0] rst_sync;

always @(posedge clock_50mhz or negedge rst_n_raw) begin
    if (!rst_n_raw) rst_sync <= 2'b00;
    else            rst_sync <= {rst_sync[0], 1'b1};   
end       

wire rst_n = rst_sync[1];

// ---------------- UART ----------------

wire                tick;
wire [8 - 1 : 0]    rx_data;
wire                rx_valid;
wire [8 - 1 : 0]    tx_data;
wire                tx_start;
wire                tx_busy;

baud_rate_gen #(
    .CLK_FREQ  (CLK_FREQ ),
    .BAUD_RATE (BAUD_RATE)
) u_baud (
    .clock   (clock_50mhz   ),
    .i_rst_n (rst_n ),
    .o_tick  (tick  )
);

uart_rx u_rx (
    .clock   (clock_50mhz   ),
    .i_rst_n (rst_n         ),
    .i_tick  (tick          ),
    .i_rx    (i_uart_rx     ),
    .o_data  (rx_data       ),
    .o_valid (rx_valid      )
);

uart_tx u_tx (
    .clock      (clock_50mhz   ),
    .i_rst_n    (rst_n         ),
    .i_tick     (tick          ),
    .i_tx_start (tx_start      ),
    .i_data     (tx_data       ),
    .o_tx       (o_uart_tx     ),
    .o_tx_done  (              ),
    .o_tx_busy  (tx_busy       )
);

// ---------------- DEBUG UNIT ----------------

wire                        cpu_rst_n;
wire                        cpu_enable;
wire                        cpu_halt;
wire [31 : 0]               cpu_pc;
wire                        imem_err;
wire                        dmem_err;
wire                        imem_we;
wire [IMEM_ADDR_BITS-1 : 0] imem_waddr;
wire [31 : 0]               imem_wdata;
wire [4 : 0]                dbg_reg_addr;
wire [31 : 0]               dbg_reg_data;
wire [DMEM_ADDR_BITS-1 : 0] dbg_mem_addr;
wire [31 : 0]               dbg_mem_data;

debug_unit #(
    .IMEM_DEPTH (IMEM_DEPTH),
    .DMEM_DEPTH (DMEM_DEPTH),
    .CLK_FREQ   (CLK_FREQ  ),
    .TIMEOUT_MS (TIMEOUT_MS)
) u_debug (
    .clock          (clock_50mhz    ),
    .i_rst_n        (rst_n          ),
    // UART
    .i_rx_data      (rx_data        ),
    .i_rx_valid     (rx_valid       ),
    .i_tx_busy      (tx_busy        ),
    .o_tx_data      (tx_data        ),
    .o_tx_start     (tx_start       ),
    // procesador
    .o_cpu_rst_n    (cpu_rst_n      ),
    .o_cpu_enable   (cpu_enable     ),
    .i_cpu_halt     (cpu_halt       ),
    .i_cpu_pc       (cpu_pc         ),
    .i_imem_err     (imem_err       ),
    .i_dmem_err     (dmem_err       ),
    // carga de programa
    .o_imem_we      (imem_we        ),
    .o_imem_waddr   (imem_waddr     ),
    .o_imem_wdata   (imem_wdata     ),
    // lectura de debug
    .o_dbg_reg_addr (dbg_reg_addr   ),
    .i_dbg_reg_data (dbg_reg_data   ),
    .o_dbg_mem_addr (dbg_mem_addr   ),
    .i_dbg_mem_data (dbg_mem_data   )
);

// ---------------- PROCESADOR ----------------

top_monocycle #(
    .IMEM_DEPTH (IMEM_DEPTH),
    .DMEM_DEPTH (DMEM_DEPTH)
) u_cpu (
    .clock               (clock_50mhz  ),
    .i_rst_n             (cpu_rst_n    ),
    .i_enable            (cpu_enable   ),
    .i_imem_write_enable (imem_we      ),
    .i_imem_write_addr   (imem_waddr   ),
    .i_imem_write_data   (imem_wdata   ),
    .o_pc                (cpu_pc       ),
    .o_instr             (             ),
    .o_halt              (cpu_halt     ),
    .o_imem_addr_error   (imem_err     ),
    .o_dmem_addr_error   (dmem_err     ),
    .i_debug_reg_addr    (dbg_reg_addr ),
    .o_debug_reg_data    (dbg_reg_data ),
    .i_debug_mem_addr    (dbg_mem_addr ),
    .o_debug_mem_data    (dbg_mem_data )
);

// ---------------- LEDs ----------------

assign o_led[0] = locked;
assign o_led[1] = rst_n;
assign o_led[2] = cpu_enable;

endmodule