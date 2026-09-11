`define TEST1

`ifdef TEST1
// Test 1: Comportamiento basico del loopback UART.
// Valida reset, envio de un byte y recepcion del mismo byte.
initial begin : test_single_byte_loopback
    $display("TEST1 START: UART loopback verification");

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Caso dirigido con un byte clasico de prueba.
    send_byte(8'hA5);

    // Se espera la recepcion completa del mismo byte.
    wait_for_all_bytes(1);

    // Si no hubo errores, el test paso.
    if (errors == 0 && recv_count == sent_count) begin
        $display("TEST1 PASSED");
    end else begin
        $display("TEST1 FAILED");
        $finish(2);
    end

    $finish;
end
`endif