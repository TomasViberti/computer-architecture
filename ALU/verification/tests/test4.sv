`define TEST4

`ifdef TEST4
// Test 4: Se verifica el funcionamiento de la operación OR en la ALU.
initial begin : test_or
    integer i;
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] value_b;

    // Reset inicial antes de comenzar la verificación.
    apply_reset();

    // Se realizan 100 iteraciones aleatorias para cubrir distintos casos de entrada.
    for (i = 0; i < 100; i = i + 1) begin
        // Se inicializan las variables A y B con valores aleatorios.
        value_a = $urandom_range(0, 2**NB_DATA - 1);
        value_b = $urandom_range(0, 2**NB_DATA - 1);

        // Se ejecutan las tasks para verificar los resultados.
        prepare_and_execute(value_a, value_b, OR);
        check_transaction(value_a, value_b, OR, "TEST4_OR");
    end

    // Si las tasks no imprimen error, el test pasó.
    $display("TEST4 PASSED");
    $finish;
end
`endif