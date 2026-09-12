`define TEST7

`ifdef TEST7
// Test 7: Se verifica el funcionamiento de la operacion SRL en la UART-ALU.
initial begin : test_srl
    integer i;
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] value_b; // NUEVO: Registro para el desplazamiento

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Caso dirigido para validar el corrimiento logico a la derecha.
    // Desplazamos 1 posicion para verificar que el bit MSB se rellene con 0.
    value_a = 8'b1000_0001;
    value_b = 8'h01; 
    run_alu_transaction(value_a, value_b, SRL);
    check_transaction(value_a, value_b, SRL, "TEST7_SRL_EDGE");

    // Se realizan iteraciones aleatorias para cubrir distintos casos de entrada.
    for (i = 0; i < 10; i = i + 1) begin
        // Se inicializa A con valores aleatorios y B con desplazamientos validos (0 a 7).
        value_a = $urandom_range(0, 2**NB_DATA - 1);
        value_b = $urandom_range(0, 7);

        // Se ejecuta la transaccion completa y se verifica la respuesta.
        run_alu_transaction(value_a, value_b, SRL);
        check_transaction(value_a, value_b, SRL, "TEST7_SRL_RANDOM");
    end

    // Si no hubo errores, el test paso.
    if (errors == 0) begin
        $display("TEST7 PASSED");
    end else begin
        $display("TEST7 FAILED");
        $finish(2);
    end

    $finish;
end
`endif