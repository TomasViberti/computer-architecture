`define TEST7

`ifdef TEST7
// Test 7: Se verifica el funcionamiento de la operación SRL en la ALU.
initial begin : test_srl
    integer i;
    reg [NB_DATA - 1 : 0] value_a;

    // Reset inicial antes de comenzar la verificación.
    apply_reset();

    // Se prueba un caso dirigido para validar el corrimiento lógico a la derecha.
    value_a = 8'b1000_0001;
    prepare_and_execute(value_a, {NB_DATA{1'b0}}, SRL);
    check_transaction(value_a, {NB_DATA{1'b0}}, SRL, "TEST7_SRL_EDGE");

    // Se realizan 100 iteraciones aleatorias para cubrir distintos casos de entrada.
    for (i = 0; i < 100; i = i + 1) begin
        // Se inicializan las variables con valores aleatorios.
        value_a = $urandom_range(0, 2**NB_DATA - 1);

        // Se ejecutan las tasks para verificar los resultados.
        prepare_and_execute(value_a, {NB_DATA{1'b0}}, SRL);
        check_transaction(value_a, {NB_DATA{1'b0}}, SRL, "TEST7_SRL_RANDOM");
    end

    // Si las tasks no imprimen error, el test pasó.
    $display("TEST7 PASSED");
    $finish;
end
`endif