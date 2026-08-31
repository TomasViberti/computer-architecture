`define TEST2

`ifdef TEST2

// Test 2: Se verifica el funcionamiento de la operación SUB en la ALU.
initial begin : test_sub
    integer i;
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] value_b;

    // Reset inicial antes de comenzar la verificación.
    apply_reset();

    // Barrido aleatorio de SUB sobre operandos de ancho completo.
    for (i = 0; i < 100; i = i + 1) 
    begin
        // Se inicializan las variables A y B con valores aleatorios.
        value_a = $urandom_range(0, 2**NB_DATA - 1);
        value_b = $urandom_range(0, 2**NB_DATA - 1);

        // Se ejecutan las tasks para verificar los resultados.
        prepare_and_execute(value_a, value_b, SUB);
        check_transaction(value_a, value_b, SUB, "TEST2_SUB");
    end

    // Si las tasks no imprimen error, el test pasó
    $display("TEST2 PASSED");
    $finish;
end
`endif