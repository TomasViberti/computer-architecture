// Program Counter RV32I. Registro de 32 bits que guarda la direccion de la
// instruccion actual. Tiene como entrada el próximo PC.
// Reset sincronico activo en bajo y habilitacion a traves de enable.

module pc (
    input  wire        i_clk,
    input  wire        i_reset,          // activo en bajo: 0 lleva el PC a 0
    input  wire        i_enable,         // 1 = carga i_next_pc, 0 = mantiene el valor
    input  wire [31:0] i_next_pc,        // proximo PC (sale del mux PC+4 / destino de salto)
    output reg  [31:0] o_current_pc      // PC actual (va a la memoria de instrucciones y al sumador)
);

    initial o_current_pc = 32'b0;

    always @(posedge i_clk) begin
        if (!i_reset)
            o_current_pc <= 32'b0;
        else if (i_enable)
            o_current_pc <= i_next_pc;
    end

endmodule