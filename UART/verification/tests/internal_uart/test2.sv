`define TEST2

`ifdef TEST2
// Test 2: Verificacion del generador de baudrate.
// Comprueba el contador interno, la periodicidad del tick y su ancho de un ciclo.
initial begin : test_baud_rate_generator
    integer cycle;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // El contador debe comenzar en cero.
    check_count("TEST2_BAUD", "initial count", dut.u_baud_rate_gen.count, {NB_COUNT{1'b0}});
    check_bit("TEST2_BAUD", "initial tick", dut.u_baud_rate_gen.o_tick, 1'b0);

    // El contador debe incrementarse hasta COUNT_MAX-1 sin emitir tick.
    for (cycle = 1; cycle < COUNT_MAX; cycle = cycle + 1) begin
        @(posedge clock);
        #1;
        check_count("TEST2_BAUD", "count increment", dut.u_baud_rate_gen.count, cycle[NB_COUNT - 1 : 0]);
        check_bit("TEST2_BAUD", "tick low before terminal count", dut.u_baud_rate_gen.o_tick, 1'b0);
    end

    // En COUNT_MAX se genera un tick y el contador vuelve a cero.
    @(posedge clock);
    #1;
    check_count("TEST2_BAUD", "count reset on tick", dut.u_baud_rate_gen.count, {NB_COUNT{1'b0}});
    check_bit("TEST2_BAUD", "tick high on terminal count", dut.u_baud_rate_gen.o_tick, 1'b1);

    // El tick debe durar un solo ciclo de clock.
    @(posedge clock);
    #1;
    check_bit("TEST2_BAUD", "tick low after pulse", dut.u_baud_rate_gen.o_tick, 1'b0);
    check_count("TEST2_BAUD", "count restarted after tick", dut.u_baud_rate_gen.count, {{(NB_COUNT - 1){1'b0}}, 1'b1});

    $display("TEST2 PASSED");
    $finish;
end
`endif
