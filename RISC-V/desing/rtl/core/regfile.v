/* Banco de registros (RV32I)
----------------------------------------------------------------------
32 registros de 32 bits (x0 a x31).

- 2 lecturas combinacionales: las salidas siguen a i_rs1 e i_rs2 sin
  esperar el clock.
- 1 escritura sincronica: el dato se guarda en el flanco de subida del
  clock, solo si i_reg_write vale 1.
- x0 vale siempre 0: escribirlo no tiene efecto y leerlo devuelve 0.
----------------------------------------------------------------------*/

module regfile
#(
    parameter NB_DATA = 32 ,
    parameter NB_ADDR = 5
)
(
    input  wire                     i_clk           ,
    input  wire                     i_reg_write     ,
    input  wire [NB_ADDR - 1 : 0]   i_rs1           ,
    input  wire [NB_ADDR - 1 : 0]   i_rs2           ,
    input  wire [NB_ADDR - 1 : 0]   i_rd            ,
    input  wire [NB_DATA - 1 : 0]   i_write_data    ,
    output wire [NB_DATA - 1 : 0]   o_read_data1    ,
    output wire [NB_DATA - 1 : 0]   o_read_data2
);

localparam NB_REGS = 2 ** NB_ADDR;

reg [NB_DATA - 1 : 0] regs [0 : NB_REGS - 1];

integer i;
initial begin
    for (i = 0; i < NB_REGS; i = i + 1)
        regs[i] = {NB_DATA{1'b0}};
end

// Escritura sincronica. Nunca se escribe x0.
always @(posedge i_clk) begin
    if (i_reg_write && (i_rd != {NB_ADDR{1'b0}}))
        regs[i_rd] <= i_write_data;
end

// Lecturas combinacionales. x0 siempre devuelve 0.
assign o_read_data1 = (i_rs1 == {NB_ADDR{1'b0}}) ? {NB_DATA{1'b0}} : regs[i_rs1];
assign o_read_data2 = (i_rs2 == {NB_ADDR{1'b0}}) ? {NB_DATA{1'b0}} : regs[i_rs2];

endmodule