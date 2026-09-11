`define TEST2

`ifdef TEST2
// Test 2: Se verifica el loopback con una secuencia de bytes de borde.
initial begin : test_edge_bytes_loopback
    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Se envian bytes con patrones de borde y alternancia de bits.
    send_byte(8'h00);
    send_byte(8'hFF);
    send_byte(8'h55);
    send_byte(8'hAA);

    // Se espera la recepcion completa de la secuencia.
    wait_for_all_bytes(4);

    // Si no hubo errores, el test paso.
    if (errors == 0 && recv_count == sent_count) begin
        $display("TEST2 PASSED");
    end else begin
        $display("TEST2 FAILED");
        $finish(2);
    end

    $finish;
end
`endif