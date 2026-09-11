`define TEST1

`ifdef TEST1
// Test 1: Comportamiento basico de la UART-ALU.
// Valida reset, envio de operandos, ejecucion de ADD y recepcion de la respuesta.
initial begin : test_reset_and_add
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] value_b;

    $display("TEST1 START: UART-ALU black-box verification");

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Caso dirigido para verificar una suma simple.
    value_a = 8'd10;
    value_b = 8'd20;

    // Se envian los 3 bytes del comando y se chequea la respuesta.
    run_alu_transaction(value_a, value_b, ADD);
    check_transaction(value_a, value_b, ADD, "TEST1_ADD_BASIC");

    // Caso dirigido para forzar carry en la suma.
    value_a = 8'd200;
    value_b = 8'd100;

    // Se repite la transaccion para validar el byte de carry.
    run_alu_transaction(value_a, value_b, ADD);
    check_transaction(value_a, value_b, ADD, "TEST1_ADD_CARRY");

    // Si no hubo errores, el test pasó.
    if (errors == 0) begin
        $display("TEST1 PASSED");
    end else begin
        $display("TEST1 FAILED");
        $finish(2);
    end

    $finish;
end
`endif