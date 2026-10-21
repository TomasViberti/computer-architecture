/*
 * Memoria de datos RV32I
 *
 * Memoria de datos de 32 bits con lectura combinacional y escritura
 * sincronica, organizada en palabras y con soporte para escritura por
 * byte (little-endian).
 *
 * Inicializacion:
 *   - Sin reset.
 *   - Contenido inicializado en cero mediante initial.
 *   - Pensada para implementarse como LUTRAM.
 *
 * Chequeo de rango:
 *   La memoria abarca DEPTH palabras (4 * DEPTH bytes). Los accesos
 *   fuera de este rango se consideran invalidos:
 *   - Escritura: se ignora.
 *   - Lectura: devuelve cero.
 *   - o_addr_error: se activa.
 *
 *   De esta manera, se evita el aliasing de direcciones fuera del
 *   rango implementado.
 *
 * Puerto de debug:
 *   o_debug_data devuelve la palabra completa correspondiente a
 *   i_debug_addr, interpretada como indice de palabra. Esta lectura
 *   es combinacional e independiente del puerto utilizado por el
 *   procesador (Debug Unit), sin chequeo de rango, tamano ni signo.
 */

module data_mem #(
    parameter DEPTH     = 256              ,    // cantidad de palabras de 32 bits (256 = 1 KB)
    parameter ADDR_BITS = $clog2(DEPTH)         // no modificar
)(
    input  wire                 clock,
    input  wire [31:0]          i_addr,         // direccion en bytes (sale de la ALU)
    input  wire [31:0]          i_wdata,        // dato a escribir (rs2)
    input  wire                 i_memread,
    input  wire                 i_memwrite,
    input  wire [2:0]           i_funct3,  
    input  wire [ADDR_BITS-1:0] i_debug_addr,           
    output reg  [31:0]          o_rdata,
    output wire                 o_addr_error,  
    output wire [31:0]          o_debug_data         
);

    (* ram_style = "distributed" *) reg [7:0] mem_b0 [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] mem_b1 [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] mem_b2 [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] mem_b3 [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem_b0[i] = 8'b0;
            mem_b1[i] = 8'b0;
            mem_b2[i] = 8'b0;
            mem_b3[i] = 8'b0;
        end
    end

    wire [ADDR_BITS-1:0] w_idx    = i_addr[ADDR_BITS+1:2];
    wire [1:0]           w_offset = i_addr[1:0];
    wire [1:0]           w_size   = i_funct3[1:0];   // 00 byte, 01 half, 10 word

    // ---------------- CHEQUEO DE RANGO ----------------

    wire w_in_range = (i_addr[31:ADDR_BITS+2] == 0);
    wire w_access   = i_memread | i_memwrite;
    assign o_addr_error = w_access & ~w_in_range;

    // ---------------- ESCRITURA ----------------

    reg [31:0] r_wd;
    reg [3:0]  r_we;

    always @(*) begin
        r_wd = i_wdata;
        r_we = 4'b0000;
        if (i_memwrite && w_in_range) begin
            case (w_size)
                2'b00: begin                          // sb: 1 byte, el que indica addr[1:0]
                    r_wd = {4{i_wdata[7:0]}};
                    r_we = 4'b0001 << w_offset;
                end
                2'b01: begin                          // sh: 2 bytes, la mitad que indica addr[1]
                    r_wd = {2{i_wdata[15:0]}};
                    r_we = w_offset[1] ? 4'b1100 : 4'b0011;
                end
                2'b10: begin                          // sw: los 4 bytes
                    r_wd = i_wdata;
                    r_we = 4'b1111;
                end
                default: r_we = 4'b0000;
            endcase
        end
    end

    always @(posedge clock) begin
        if (r_we[0]) mem_b0[w_idx] <= r_wd[7:0];
        if (r_we[1]) mem_b1[w_idx] <= r_wd[15:8];
        if (r_we[2]) mem_b2[w_idx] <= r_wd[23:16];
        if (r_we[3]) mem_b3[w_idx] <= r_wd[31:24];
    end

    // ---------------- LECTURA ----------------

    wire [31:0] w_rword = {mem_b3[w_idx], mem_b2[w_idx], mem_b1[w_idx], mem_b0[w_idx]};

    assign o_debug_data = {mem_b3[i_debug_addr], mem_b2[i_debug_addr], mem_b1[i_debug_addr], mem_b0[i_debug_addr]};

    reg [7:0]  r_byte;
    reg [15:0] r_half;

    always @(*) begin
        case (w_offset)
            2'b00:   r_byte = w_rword[7:0];
            2'b01:   r_byte = w_rword[15:8];
            2'b10:   r_byte = w_rword[23:16];
            default: r_byte = w_rword[31:24];
        endcase
        r_half = w_offset[1] ? w_rword[31:16] : w_rword[15:0];
    end

    always @(*) begin
        if (i_memread && w_in_range) begin
            case (i_funct3)
                3'b000:  o_rdata = {{24{r_byte[7]}}, r_byte};    // lb : byte con signo
                3'b001:  o_rdata = {{16{r_half[15]}}, r_half};   // lh : halfword con signo
                3'b010:  o_rdata = w_rword;                      // lw : palabra completa
                3'b100:  o_rdata = {24'b0, r_byte};              // lbu: byte con ceros
                3'b101:  o_rdata = {16'b0, r_half};              // lhu: halfword con ceros
                default: o_rdata = 32'b0;
            endcase
        end else begin
            o_rdata = 32'b0;
        end
    end

endmodule