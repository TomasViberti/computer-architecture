`define TEST3

`ifdef TEST3
// Test 3: Se verifica el loopback con una secuencia aleatoria de bytes.
initial begin : test_random_stream_loopback
    integer i;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Se envian bytes aleatorios para cubrir distintos casos de entrada.
    for (i = 0; i < 10; i = i + 1) begin
        send_byte($urandom_range(0, 2**NB_DATA - 1));
    end

    // Se espera la recepcion completa de la secuencia.
    wait_for_all_bytes(10);

    // Si no hubo errores, el test paso.
    if (errors == 0 && recv_count == sent_count) begin
        $display("TEST3 PASSED");
    end else begin
        $display("TEST3 FAILED");
        $finish(2);
    end

    $finish;
end
`endif