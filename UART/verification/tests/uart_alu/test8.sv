`define TEST8

`ifdef TEST8
// Test 8: Se verifica el funcionamiento de la operacion NOR en la UART-ALU.
initial begin : test_nor
    integer i;
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] value_b;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Se realizan iteraciones aleatorias para cubrir distintos casos de entrada.
    for (i = 0; i < 10; i = i + 1) begin
        // Se inicializan las variables A y B con valores aleatorios.
        value_a = $urandom_range(0, 2**NB_DATA - 1);
        value_b = $urandom_range(0, 2**NB_DATA - 1);

        // Se ejecuta la transaccion completa y se verifica la respuesta.
        run_alu_transaction(value_a, value_b, NOR);
        check_transaction(value_a, value_b, NOR, "TEST8_NOR_RANDOM");
    end

    // Si no hubo errores, el test paso.
    if (errors == 0) begin
        $display("TEST8 PASSED");
    end else begin
        $display("TEST8 FAILED");
        $finish(2);
    end

    $finish;
end
`endif