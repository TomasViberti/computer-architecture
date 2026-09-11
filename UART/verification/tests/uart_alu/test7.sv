`define TEST7

`ifdef TEST7
// Test 7: Se verifica el funcionamiento de la operacion SRL en la UART-ALU.
initial begin : test_srl
    integer i;
    reg [NB_DATA - 1 : 0] value_a;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Caso dirigido para validar el corrimiento logico a la derecha.
    value_a = 8'b1000_0001;
    run_alu_transaction(value_a, {NB_DATA{1'b0}}, SRL);
    check_transaction(value_a, {NB_DATA{1'b0}}, SRL, "TEST7_SRL_EDGE");

    // Se realizan iteraciones aleatorias para cubrir distintos casos de entrada.
    for (i = 0; i < 10; i = i + 1) begin
        // Se inicializa A con valores aleatorios.
        value_a = $urandom_range(0, 2**NB_DATA - 1);

        // Se ejecuta la transaccion completa y se verifica la respuesta.
        run_alu_transaction(value_a, {NB_DATA{1'b0}}, SRL);
        check_transaction(value_a, {NB_DATA{1'b0}}, SRL, "TEST7_SRL_RANDOM");
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