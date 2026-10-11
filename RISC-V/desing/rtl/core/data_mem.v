/* Memoria de datos (RV32I)
Memoria de datos RV32I. Lectura combinacional, escritura sincronica.
Organizada en palabras de 32 bits, con escritura por byte (little-endian).
Sin reset, con valor inicial 0 (initial). Pensada para sintetizarse como LUTRAM.

Chequeo de rango: la memoria cubre 4*DEPTH bytes. Un acceso (lectura o escritura) a una
direccion fuera de ese rango NO se realiza: la escritura se ignora, la lectura devuelve 0,
y o_addr_error se activa. Asi no se repite la memoria en otras direcciones (aliasing).*/

module data_mem #(
    parameter DEPTH = 256                    // cantidad de palabras de 32 bits (256 = 1 KB)
)(
    input  wire        clock,
    input  wire [31:0] i_addr,               // direccion en bytes (sale de la ALU)
    input  wire [31:0] i_wdata,              // dato a escribir (rs2)
    input  wire        i_memread,
    input  wire        i_memwrite,
    input  wire [2:0]  i_funct3,             // [1:0] tamano, [2] 1 = sin signo (cargas)
    output reg  [31:0] o_rdata,
    output wire        o_addr_error             // 1 = acceso fuera de rango (lectura o escritura)
);

    localparam ADDR_BITS = $clog2(DEPTH);

    // Cuatro memorias de 1 byte: una por cada byte de la palabra (lane 0 = bits [7:0]).
    // Cada una tiene su propio write enable, lo que permite escribir sb/sh sin pisar los demas bytes. 
    // Esto permite guardar media palabra o incluso un byte sin arruinar un dato de cuatro bytes completos.
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

    // La direccion se parte: palabra y byte dentro de la palabra
    wire [ADDR_BITS-1:0] w_idx    = i_addr[ADDR_BITS+1:2];
    wire [1:0]           w_offset = i_addr[1:0];
    wire [1:0]           w_size   = i_funct3[1:0];   // 00 byte, 01 half, 10 word

    // ---------------- CHEQUEO DE RANGO ----------------
    // Los bits altos de la direccion deben ser 0: la memoria cubre 4*DEPTH bytes.
    wire w_in_range = (i_addr[31:ADDR_BITS+2] == 0);
    wire w_access   = i_memread | i_memwrite;
    assign o_addr_error = w_access & ~w_in_range;

    // ---------------- ESCRITURA ----------------

    // Dato replicado: cada lane toma el byte que le corresponde segun el tamano
    reg [31:0] r_wd;
    // Que bytes de la palabra se escriben
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

    // Palabra completa de la posicion pedida (lectura asincronica)
    wire [31:0] w_rword = {mem_b3[w_idx], mem_b2[w_idx], mem_b1[w_idx], mem_b0[w_idx]};

    // Byte y halfword que corresponden a la direccion
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