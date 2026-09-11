`define TEST4

`ifdef TEST4
// Test 4: Se verifica el funcionamiento de la operacion OR en la UART-ALU.
initial begin : test_or
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
        run_alu_transaction(value_a, value_b, OR);
        check_transaction(value_a, value_b, OR, "TEST4_OR_RANDOM");
    end

    // Si no hubo errores, el test paso.
    if (errors == 0) begin
        $display("TEST4 PASSED");
    end else begin
        $display("TEST4 FAILED");
        $finish(2);
    end

    $finish;
end
`endif