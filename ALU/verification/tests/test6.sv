`define TEST6

`ifdef TEST6
// Test 6: Se verifica el funcionamiento de la operación SRA en la ALU.
initial begin : test_sra
    integer i;
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] shift_amount;

    // Reset inicial antes de comenzar la verificación.
    apply_reset();

    // Se prueba un caso dirigido con el bit de signo en 1 y shift distinto de cero.
    value_a = 8'b1000_0000;
    shift_amount = 8'd1;
    prepare_and_execute(value_a, shift_amount, SRA);
    check_transaction(value_a, shift_amount, SRA, "TEST6_SRA_EDGE");

    // Se realizan 100 iteraciones aleatorias para cubrir distintos casos de entrada.
    for (i = 0; i < 100; i = i + 1) begin
        // Se inicializan las variables con valores aleatorios.
        value_a = $urandom_range(0, 2**NB_DATA - 1);
        shift_amount = $urandom_range(0, 2**SHIFT_WIDTH - 1);

        // Se ejecutan las tasks para verificar los resultados.
        prepare_and_execute(value_a, shift_amount, SRA);
        check_transaction(value_a, shift_amount, SRA, "TEST6_SRA_RANDOM");
    end

    // Si las tasks no imprimen error, el test pasó.
    $display("TEST6 PASSED");
    $finish;
end
`endif