// Program Counter RV32I. Registro de 32 bits que guarda la direccion de la
// instruccion actual. Tiene como entrada el próximo PC.
// Reset sincronico activo en bajo y habilitacion a traves de enable.

module pc (
    input  wire        clock,
    input  wire        i_rst_n,          // activo en bajo: 0 lleva el PC a 0
    input  wire        i_enable,         // 1 = carga i_next_pc, 0 = mantiene el valor
    input  wire [31:0] i_next_pc,        // proximo PC (sale del mux PC+4 / destino de salto)
    output reg  [31:0] o_current_pc      // PC actual (va a la memoria de instrucciones y al sumador)
);

always @(posedge clock or negedge i_rst_n) begin
    if (!i_rst_n)
        o_current_pc <= 32'b0;
    else if (i_enable)
        o_current_pc <= i_next_pc;
end

endmodule