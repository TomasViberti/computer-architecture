`define TEST1

`ifdef TEST1
// Test 1: Verificacion basica de uart.
// Valida el reset y el estado idle de los registros internos.
initial begin : test_reset_and_idle
    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // El contador del baud generator debe quedar en cero.
    check_count("TEST1_RESET", "baud counter", dut.u_baud_rate_gen.count, {NB_COUNT{1'b0}});
    check_bit("TEST1_RESET", "baud tick", dut.u_baud_rate_gen.o_tick, 1'b0);

    // El transmisor UART debe quedar en idle y con la linea en reposo.
    if (dut.u_uart_tx.state_reg !== TX_IDLE) begin
        $display("ERROR [TEST1_RESET] TX state expected=IDLE received=%0d", dut.u_uart_tx.state_reg);
        $finish(2);
    end
    check_bit("TEST1_RESET", "tx busy", dut.u_uart_tx.o_tx_busy, 1'b0);
    check_bit("TEST1_RESET", "tx line", dut.u_uart_tx.o_tx, 1'b1);
    check_bit("TEST1_RESET", "tx done", dut.u_uart_tx.done_reg, 1'b0);

    // El receptor UART debe quedar sincronizado e inactivo.
    if (dut.u_uart_rx.state_reg !== RX_IDLE) begin
        $display("ERROR [TEST1_RESET] RX state expected=IDLE received=%0d", dut.u_uart_rx.state_reg);
        $finish(2);
    end
    
    check_bit("TEST1_RESET", "rx valid", dut.u_uart_rx.valid_reg, 1'b0);
    check_bit("TEST1_RESET", "rx sync 0", dut.u_uart_rx.rx_sync_0, 1'b1);
    check_bit("TEST1_RESET", "rx sync 1", dut.u_uart_rx.rx_sync_1, 1'b1);
    check_bus("TEST1_RESET", "rx data", dut.u_uart_rx.data_reg, {NB_DATA{1'b0}});

    // Las salidas del top tambien deben quedar en su valor de reposo.
    check_bit("TEST1_RESET", "top valid", rx_valid, 1'b0);
    check_bit("TEST1_RESET", "top tx busy", tx_busy, 1'b0);
    check_bus("TEST1_RESET", "top rx data", rx_data, {NB_DATA{1'b0}});

    $display("TEST1 PASSED");
    $finish;
end
`endif
