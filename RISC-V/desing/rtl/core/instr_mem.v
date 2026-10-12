/* Memoria de programa (instrucciones de 32 bits)
----------------------------------------------------------------------
- Lectura combinacional: o_instr sigue a i_pc sin esperar el clock.

- Escritura sincronica de una palabra de 32 bits por vez, para que la
  Debug Unit cargue el programa por UART sin resintetizar.

- i_pc es una direccion en bytes; la palabra se elige con i_pc[N+1:2].

- Direccion fuera de rango: devuelve HALT y activa o_addr_error.

- Un PC desalineado (bits [1:0] distintos de 0) se trata como alineado
  hacia abajo, igual que en data_mem.
----------------------------------------------------------------------*/

module instr_mem
#(
    parameter DEPTH     = 256               ,   // palabras de 32 bits
    parameter INIT_WORD = 32'h0000000B      ,   // contenido inicial (HALT)
    parameter ADDR_BITS = $clog2(DEPTH)         
)
(
    input  wire                     clock           ,
    input  wire                     i_halted        ,   // 1 = procesador detenido
    input  wire                     i_write_enable  ,   // escritura de la Debug Unit
    input  wire [ADDR_BITS - 1 : 0] i_write_addr    ,   // indice de palabra a escribir
    input  wire [31 : 0]            i_write_data    ,   // palabra completa
    input  wire [31 : 0]            i_pc            ,   // direccion en bytes
    output wire [31 : 0]            o_instr         ,
    output wire                     o_addr_error        // 1 = i_pc fuera de rango
);

localparam [31 : 0] HALT_WORD = 32'h0000000B;

(* ram_style = "distributed" *) reg [31 : 0] mem [0 : DEPTH - 1];

integer i;
initial begin
    for (i = 0; i < DEPTH; i = i + 1)
        mem[i] = INIT_WORD;
end

// Rango: los bits altos del PC deben ser 0
wire                     in_range = (i_pc[31 : ADDR_BITS + 2] == 0);
wire [ADDR_BITS - 1 : 0] rindex   = i_pc[ADDR_BITS + 1 : 2];

// Lectura combinacional
assign o_instr      = in_range ? mem[rindex] : HALT_WORD;
assign o_addr_error = ~in_range;

// Escritura sincronica, solo con el procesador detenido
always @(posedge clock) begin
    if (i_write_enable && i_halted)
        mem[i_write_addr] <= i_write_data;
end

endmodule