`define TEST4

`ifdef TEST4
// Test 4: Se verifica el loopback con una rafaga larga de bytes.
initial begin : test_long_burst_loopback
    integer i;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Se envian mas bytes para estresar la continuidad de Tx y Rx.
    for (i = 0; i < 16; i = i + 1) begin
        send_byte(8'h3C + i);
    end

    // Se espera la recepcion completa de la rafaga.
    wait_for_all_bytes(16);

    // Si no hubo errores, el test paso.
    if (errors == 0 && recv_count == sent_count) begin
        $display("TEST4 PASSED");
    end else begin
        $display("TEST4 FAILED");
        $finish(2);
    end

    $finish;
end
`endif