/* ----------------------------------------------------------------------
   Debug Unit

   Recibe comandos de la PC por UART, carga el programa en la memoria de
   instrucciones, ejecuta el procesador hasta el HALT y le manda a la PC el
   estado final (PC, ciclos, registros y memoria de datos).

   Protocolo
   ---------------------
   Reglas:
     1. Todo mensaje empieza con un byte que dice que es.
     2. Los numeros de varios bytes van con el byte MENOS significativo primero.
     3. Todo comando recibe una respuesta.

   PC -> FPGA:
     01 LOAD  seguido de N (2 bytes) y de N palabras de 4 bytes cada una.
              Carga desde la direccion 0. Valido: 1 <= N <= IMEM_DEPTH.
     02 RUN   Pone el procesador en PC = 0 y lo deja ejecutar hasta el HALT.
              Pone en cero el contador de ciclos y los errores capturados.
              No vacia los registros ni la memoria de datos.

   FPGA -> PC:
     00  OK
     01  comando desconocido
     02  parametro invalido (N = 0 o N mayor que IMEM_DEPTH)
     10  estado del procesador. Se manda solo, cuando el programa llega al
         HALT (despues del OK de RUN). Contenido, en este orden:
           1 byte    tipo (10)
           1 byte    banderas: bit 0 = termino por HALT (siempre 1)
                               bit 1 = ERROR_IMEM (el PC salio de la memoria de programa)
                               bit 2 = ERROR_DMEM (acceso a datos fuera de rango al ejecutar)
           4 bytes   PC final
           4 bytes   CICLOS: instrucciones ejecutadas, sin contar el HALT
           128 bytes registros x0 a x31, 4 bytes cada uno
           2 bytes   cantidad de palabras de memoria de datos que siguen (DMEM_DEPTH)
           4*DMEM_DEPTH bytes: la memoria de datos completa, palabra 0 primero

   Mientras el procesador ejecuta (entre el OK de RUN y el estado) la Debug
   Unit no atiende comandos: la PC tiene que esperar el estado. Si el programa
   no termina nunca, se corta con el boton de reset de la placa.

   Errores:
     Despues de un error la Debug Unit descarta todo lo que llegue hasta
     que la linea queda en silencio TIMEOUT_MS. Asi, los bytes de un
     comando que no se pudo aceptar no se interpretan como comandos nuevos.
     Si en medio de un LOAD dejan de llegar bytes durante TIMEOUT_MS, el
     comando se abandona (sin respuesta) y la Debug Unit vuelve a esperar
     un comando. Este silencio no corre mientras el procesador ejecuta.

   Estados:
     IDLE        - espera el byte de comando
     LOAD_NLO    - LOAD: espera el byte bajo de N
     LOAD_NHI    - LOAD: espera el byte alto de N y valida N
     LOAD_BYTE   - LOAD: espera un byte de la palabra (4 por palabra)
     LOAD_WRITE  - LOAD: un ciclo, escribe la palabra en la memoria de instrucciones
     REPLY       - manda el byte de respuesta (espera a que la UART este libre)
     DRAIN       - descarta bytes hasta que haya silencio
     RUN_START   - un ciclo: libera el reset del procesador y pone en cero contadores y errores
     RUN_EXEC    - el procesador ejecuta; cuenta ciclos y captura errores hasta que sube o_halt
     DUMP_LOAD   - toma el proximo valor del estado (campo e indice)
     DUMP_SEND   - manda ese valor, byte a byte, byte menos significativo primero
---------------------------------------------------------------------- */

module debug_unit
#(
    parameter IMEM_DEPTH     = 256                  ,   // palabras de programa
    parameter DMEM_DEPTH     = 256                  ,   // palabras de datos
    parameter CLK_FREQ       = 50_000_000           ,   // Hz
    parameter TIMEOUT_MS     = 100                  ,   // silencio maximo dentro de un comando
    parameter IMEM_ADDR_BITS = $clog2(IMEM_DEPTH)   ,   // no modificar
    parameter DMEM_ADDR_BITS = $clog2(DMEM_DEPTH)       // no modificar
)
(
    input  wire                          clock          ,
    input  wire                          i_rst_n        ,

    // UART
    input  wire [7 : 0]                  i_rx_data      ,
    input  wire                          i_rx_valid     ,
    input  wire                          i_tx_busy      ,
    output reg  [7 : 0]                  o_tx_data      ,
    output reg                           o_tx_start     ,

    // Procesador
    output wire                          o_cpu_rst_n    ,   // reset del procesador (activo en bajo)
    output wire                          o_cpu_enable   ,   // 1 = el procesador ejecuta
    input  wire                          i_cpu_halt     ,
    input  wire [31 : 0]                 i_cpu_pc       ,
    input  wire                          i_imem_err     ,
    input  wire                          i_dmem_err     ,

    // Carga de programa
    output reg                           o_imem_we      ,
    output wire [IMEM_ADDR_BITS - 1 : 0] o_imem_waddr   ,
    output wire [31 : 0]                 o_imem_wdata   ,

    // Lectura de debug
    output wire [4 : 0]                  o_dbg_reg_addr ,
    input  wire [31 : 0]                 i_dbg_reg_data ,
    output wire [DMEM_ADDR_BITS - 1 : 0] o_dbg_mem_addr ,
    input  wire [31 : 0]                 i_dbg_mem_data
);

// ---------------- comandos y respuestas ----------------
localparam [7 : 0] CMD_LOAD        = 8'h01;
localparam [7 : 0] CMD_RUN         = 8'h02;
localparam [7 : 0] REPLY_OK        = 8'h00;
localparam [7 : 0] REPLY_ERR_CMD   = 8'h01;
localparam [7 : 0] REPLY_ERR_PARAM = 8'h02;
localparam [7 : 0] PKT_STATE       = 8'h10;

// ---------------- estados ----------------
localparam [3 : 0] IDLE       = 4'd0;
localparam [3 : 0] LOAD_NLO   = 4'd1;
localparam [3 : 0] LOAD_NHI   = 4'd2;
localparam [3 : 0] LOAD_BYTE  = 4'd3;
localparam [3 : 0] LOAD_WRITE = 4'd4;
localparam [3 : 0] REPLY      = 4'd5;
localparam [3 : 0] DRAIN      = 4'd6;
localparam [3 : 0] RUN_START  = 4'd7;
localparam [3 : 0] RUN_EXEC   = 4'd8;
localparam [3 : 0] DUMP_LOAD  = 4'd9;
localparam [3 : 0] DUMP_SEND  = 4'd10;

// Que hacer despues de mandar la respuesta
localparam [1 : 0] AFTER_IDLE  = 2'd0;
localparam [1 : 0] AFTER_DRAIN = 2'd1;
localparam [1 : 0] AFTER_RUN   = 2'd2;

// Campos del paquete de estado, en el orden en que se mandan
localparam [2 : 0] F_TYPE  = 3'd0;
localparam [2 : 0] F_FLAGS = 3'd1;
localparam [2 : 0] F_PC    = 3'd2;
localparam [2 : 0] F_CYC   = 3'd3;
localparam [2 : 0] F_REG   = 3'd4;
localparam [2 : 0] F_NW    = 3'd5;
localparam [2 : 0] F_MEM   = 3'd6;

localparam [15 : 0] NWORDS = DMEM_DEPTH;

localparam TIMEOUT_CYCLES = (CLK_FREQ / 1000) * TIMEOUT_MS;
localparam NB_TMO         = $clog2(TIMEOUT_CYCLES + 1);

reg [3 : 0]          state_reg   , state_next   ;
reg [15 : 0]         count_reg   , count_next   ;   // LOAD: palabras a cargar (N)
reg [15 : 0]         widx_reg    , widx_next    ;   // LOAD: palabra que se esta cargando
reg [1 : 0]          bidx_reg    , bidx_next    ;   // LOAD: byte dentro de la palabra
reg [31 : 0]         word_reg    , word_next    ;   // LOAD: palabra que se esta armando
reg [7 : 0]          reply_reg   , reply_next   ;
reg [1 : 0]          after_reg   , after_next   ;   // que hacer despues de responder
reg [NB_TMO - 1 : 0] tmo_reg     , tmo_next     ;   // ciclos sin recibir bytes
reg                  cpu_rst_reg , cpu_rst_next ;   // 1 = procesador fuera de reset
reg                  enable_reg  , enable_next  ;
reg [31 : 0]         cyc_reg     , cyc_next     ;   // CICLOS
reg                  eimem_reg   , eimem_next   ;   // ERROR_IMEM capturado
reg                  edmem_reg   , edmem_next   ;   // ERROR_DMEM capturado
reg [31 : 0]         pc_reg      , pc_next      ;   // PC al llegar al HALT
reg [2 : 0]          field_reg   , field_next   ;   // DUMP: campo que se esta mandando
reg [15 : 0]         didx_reg    , didx_next    ;   // DUMP: indice dentro del campo (registro o palabra)
reg [31 : 0]         out_reg     , out_next     ;   // DUMP: valor que se esta mandando
reg [2 : 0]          nb_reg      , nb_next      ;   // DUMP: bytes que faltan de ese valor

// N completo, cuando llega su byte alto
wire [15 : 0] n_new = {i_rx_data, count_reg[7 : 0]};

// Estados en los que la Debug Unit espera bytes de la PC (ahi corre el contador de silencio)
wire waiting = (state_reg == LOAD_NLO)  || (state_reg == LOAD_NHI) ||
               (state_reg == LOAD_BYTE) || (state_reg == LOAD_WRITE) ||
               (state_reg == DRAIN);

wire timeout_hit = waiting && (tmo_reg == TIMEOUT_CYCLES - 1) && !i_rx_valid;

// Ultima palabra del paquete de estado
wire last_word = (field_reg == F_MEM) && (didx_reg == DMEM_DEPTH - 1);

always @(posedge clock) begin
    if (!i_rst_n) begin
        state_reg   <= IDLE;
        count_reg   <= 16'd0;
        widx_reg    <= 16'd0;
        bidx_reg    <= 2'd0;
        word_reg    <= 32'd0;
        reply_reg   <= REPLY_OK;
        after_reg   <= AFTER_IDLE;
        tmo_reg     <= {NB_TMO{1'b0}};
        cpu_rst_reg <= 1'b0;
        enable_reg  <= 1'b0;
        cyc_reg     <= 32'd0;
        eimem_reg   <= 1'b0;
        edmem_reg   <= 1'b0;
        pc_reg      <= 32'd0;
        field_reg   <= F_TYPE;
        didx_reg    <= 16'd0;
        out_reg     <= 32'd0;
        nb_reg      <= 3'd0;
    end else begin
        state_reg   <= state_next;
        count_reg   <= count_next;
        widx_reg    <= widx_next;
        bidx_reg    <= bidx_next;
        word_reg    <= word_next;
        reply_reg   <= reply_next;
        after_reg   <= after_next;
        tmo_reg     <= tmo_next;
        cpu_rst_reg <= cpu_rst_next;
        enable_reg  <= enable_next;
        cyc_reg     <= cyc_next;
        eimem_reg   <= eimem_next;
        edmem_reg   <= edmem_next;
        pc_reg      <= pc_next;
        field_reg   <= field_next;
        didx_reg    <= didx_next;
        out_reg     <= out_next;
        nb_reg      <= nb_next;
    end
end

always @(*) begin
    state_next   = state_reg;
    count_next   = count_reg;
    widx_next    = widx_reg;
    bidx_next    = bidx_reg;
    word_next    = word_reg;
    reply_next   = reply_reg;
    after_next   = after_reg;
    tmo_next     = tmo_reg;
    cpu_rst_next = cpu_rst_reg;
    enable_next  = enable_reg;
    cyc_next     = cyc_reg;
    eimem_next   = eimem_reg;
    edmem_next   = edmem_reg;
    pc_next      = pc_reg;
    field_next   = field_reg;
    didx_next    = didx_reg;
    out_next     = out_reg;
    nb_next      = nb_reg;
    o_tx_data    = (state_reg == DUMP_SEND) ? out_reg[7 : 0] : reply_reg;
    o_tx_start   = 1'b0;
    o_imem_we    = 1'b0;

    // Contador de silencio: vuelve a cero con cada byte recibido y
    // solo corre mientras se esperan bytes de la PC.
    if (i_rx_valid || !waiting)
        tmo_next = {NB_TMO{1'b0}};
    else if (tmo_reg != TIMEOUT_CYCLES - 1)
        tmo_next = tmo_reg + 1'b1;

    case (state_reg)
        // ------------------------------------------------ comandos
        IDLE: begin
            if (i_rx_valid) begin
                case (i_rx_data)
                    CMD_LOAD: begin
                        state_next = LOAD_NLO;
                    end
                    CMD_RUN: begin
                        reply_next = REPLY_OK;
                        after_next = AFTER_RUN;
                        state_next = REPLY;
                    end
                    default: begin
                        reply_next = REPLY_ERR_CMD;
                        after_next = AFTER_DRAIN;
                        state_next = REPLY;
                    end
                endcase
            end
        end

        // ------------------------------------------------ LOAD
        LOAD_NLO: begin
            if (i_rx_valid) begin
                count_next[7 : 0] = i_rx_data;
                state_next        = LOAD_NHI;
            end
        end

        LOAD_NHI: begin
            if (i_rx_valid) begin
                count_next[15 : 8] = i_rx_data;
                if (n_new == 16'd0 || n_new > IMEM_DEPTH) begin
                    reply_next = REPLY_ERR_PARAM;
                    after_next = AFTER_DRAIN;
                    state_next = REPLY;
                end else begin
                    widx_next  = 16'd0;
                    bidx_next  = 2'd0;
                    state_next = LOAD_BYTE;
                end
            end
        end

        LOAD_BYTE: begin
            if (i_rx_valid) begin
                // El primer byte es el menos significativo: entra por la izquierda
                // y, tras 4 bytes, queda en los bits [7:0].
                word_next = {i_rx_data, word_reg[31 : 8]};
                if (bidx_reg == 2'd3) begin
                    bidx_next  = 2'd0;
                    state_next = LOAD_WRITE;
                end else begin
                    bidx_next = bidx_reg + 1'b1;
                end
            end
        end

        LOAD_WRITE: begin
            o_imem_we = 1'b1;
            widx_next = widx_reg + 1'b1;
            if (widx_reg == count_reg - 1'b1) begin
                reply_next = REPLY_OK;
                after_next = AFTER_IDLE;
                state_next = REPLY;
            end else begin
                state_next = LOAD_BYTE;
            end
        end

        // ------------------------------------------------ respuesta
        REPLY: begin
            if (!i_tx_busy) begin
                o_tx_start = 1'b1;
                case (after_reg)
                    AFTER_DRAIN: state_next = DRAIN;
                    AFTER_RUN:   state_next = RUN_START;
                    default:     state_next = IDLE;
                endcase
            end
        end

        DRAIN: begin
            // No hace nada: descarta los bytes. El silencio lo detecta timeout_hit.
        end

        // ------------------------------------------------ RUN
        RUN_START: begin
            cpu_rst_next = 1'b1;            // suelta el reset: el PC queda en 0
            enable_next  = 1'b0;
            cyc_next     = 32'd0;
            eimem_next   = 1'b0;
            edmem_next   = 1'b0;
            state_next   = RUN_EXEC;
        end

        RUN_EXEC: begin
            enable_next = 1'b1;
            if (i_imem_err)                   eimem_next = 1'b1;
            if (enable_reg && i_dmem_err)     edmem_next = 1'b1;
            if (enable_reg && !i_cpu_halt)    cyc_next   = cyc_reg + 1'b1;
            if (i_cpu_halt) begin
                // El programa termino: se guarda el PC, se detiene el procesador
                // (queda en reset) y se empieza a mandar el estado.
                pc_next      = i_cpu_pc;
                enable_next  = 1'b0;
                cpu_rst_next = 1'b0;
                field_next   = F_TYPE;
                didx_next    = 16'd0;
                state_next   = DUMP_LOAD;
            end
        end

        // ------------------------------------------------ estado hacia la PC
        DUMP_LOAD: begin
            case (field_reg)
                F_TYPE:  begin out_next = {24'd0, PKT_STATE};                    nb_next = 3'd1; end
                F_FLAGS: begin out_next = {29'd0, edmem_reg, eimem_reg, 1'b1};   nb_next = 3'd1; end
                F_PC:    begin out_next = pc_reg;                                nb_next = 3'd4; end
                F_CYC:   begin out_next = cyc_reg;                               nb_next = 3'd4; end
                F_REG:   begin out_next = i_dbg_reg_data;                        nb_next = 3'd4; end
                F_NW:    begin out_next = {16'd0, NWORDS};                       nb_next = 3'd2; end
                default: begin out_next = i_dbg_mem_data;                        nb_next = 3'd4; end
            endcase
            state_next = DUMP_SEND;
        end

        DUMP_SEND: begin
            if (!i_tx_busy) begin
                o_tx_start = 1'b1;                          // manda out_reg[7:0]
                out_next   = {8'd0, out_reg[31 : 8]};
                if (nb_reg != 3'd1) begin
                    nb_next = nb_reg - 1'b1;
                end else begin
                    // Termino este valor: pasa al siguiente campo o indice
                    state_next = last_word ? IDLE : DUMP_LOAD;
                    case (field_reg)
                        F_TYPE:  field_next = F_FLAGS;
                        F_FLAGS: field_next = F_PC;
                        F_PC:    field_next = F_CYC;
                        F_CYC:   begin field_next = F_REG; didx_next = 16'd0; end
                        F_REG: begin
                            if (didx_reg == 16'd31) begin field_next = F_NW; didx_next = 16'd0; end
                            else didx_next = didx_reg + 1'b1;
                        end
                        F_NW:    begin field_next = F_MEM; didx_next = 16'd0; end
                        default: didx_next = didx_reg + 1'b1;
                    endcase
                end
            end
        end

        default: state_next = IDLE;
    endcase

    // Silencio demasiado largo en medio de un comando (o despues de un error)
    if (timeout_hit) begin
        state_next = IDLE;
        after_next = AFTER_IDLE;
    end
end

assign o_imem_waddr   = widx_reg[IMEM_ADDR_BITS - 1 : 0];
assign o_imem_wdata   = word_reg;
assign o_cpu_rst_n    = cpu_rst_reg;
assign o_cpu_enable   = enable_reg;
assign o_dbg_reg_addr = didx_reg[4 : 0];
assign o_dbg_mem_addr = didx_reg[DMEM_ADDR_BITS - 1 : 0];

endmodule