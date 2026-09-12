`define TEST4

`ifdef TEST4
// Test 4: Verificacion white-box del receptor UART.
// Comprueba sincronizacion, estados, shift register y pulso de valid al recibir una trama completa.
initial begin : test_uart_rx_frame
    integer bit_index;
    integer tick_idx;
    reg [7:0] test_byte;
    reg [7:0] expected_rx_shift;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Byte de prueba con un patron que permite ver bien el corrimiento.
    test_byte = 8'h3C;
    expected_rx_shift = 8'h00;

    // Se inicia la trama desde la entrada emulada de la PC.
    start_tx_frame(test_byte);

    // El receptor debe ver la linea en bajo y pasar a START.
    wait_rx_state(RX_START);
    #1;
    check_bit("TEST4_RX", "sync flop 0", dut.u_uart_rx.rx_sync_0, 1'b0);
    check_bit("TEST4_RX", "sync flop 1", dut.u_uart_rx.rx_sync_1, 1'b0);

    // En lugar de contar ticks fijos que pueden desfasarse por los sincronizadores asíncronos,
    // esperamos dinámicamente a que la FSM valide el Start Bit y pase a la lectura de datos.
    wait_rx_state(RX_DATA);
    #1;
    check_bus("TEST4_RX", "data register at entry", dut.u_uart_rx.data_reg, expected_rx_shift);
    if (dut.u_uart_rx.bit_cnt_reg !== 0) begin
        $display("ERROR [TEST4_RX] bit counter expected=0 received=%0d at DATA entry", dut.u_uart_rx.bit_cnt_reg);
        $finish(2);
    end

    // Cada bit de datos dura exactamente OVERSAMPLE ticks a partir de este punto.
    for (bit_index = 0; bit_index < NB_DATA; bit_index = bit_index + 1) begin
        
        // Verificamos el estado durante los primeros 15 ticks del bit (antes del muestreo).
        for (tick_idx = 0; tick_idx < OVERSAMPLE - 1; tick_idx = tick_idx + 1) begin
            wait_for_next_baud_tick();
            #1;
            if (dut.u_uart_rx.state_reg !== RX_DATA) begin
                $display("ERROR [TEST4_RX] Expected DATA state during wait, received=%0d", dut.u_uart_rx.state_reg);
                $finish(2);
            end
            
            // Durante la espera, el contador de bits debe mantenerse en el índice actual.
            if (dut.u_uart_rx.bit_cnt_reg !== bit_index[2:0]) begin
                $display("ERROR [TEST4_RX] bit counter expected=%0d received=%0d during wait", bit_index, dut.u_uart_rx.bit_cnt_reg);
                $finish(2);
            end
        end

        // En el tick nro 16 (último tick de este bit) la UART hace el muestreo e inserta el bit.
        wait_for_next_baud_tick();
        expected_rx_shift = {test_byte[bit_index], expected_rx_shift[NB_DATA - 1 : 1]};
        #1;
        
        check_bus("TEST4_RX", "rx shift register", dut.u_uart_rx.data_reg, expected_rx_shift);
        
        // Si no es el último bit, la FSM se queda en DATA y el contador se incrementa preparándose para el próximo.
        if (bit_index < NB_DATA - 1) begin
            if (dut.u_uart_rx.state_reg !== RX_DATA) begin
                $display("ERROR [TEST4_RX] Expected DATA state after sample, received=%0d", dut.u_uart_rx.state_reg);
                $finish(2);
            end
            if (dut.u_uart_rx.bit_cnt_reg !== (bit_index[2:0] + 1'b1)) begin
                $display("ERROR [TEST4_RX] bit counter expected=%0d received=%0d after sample", bit_index + 1, dut.u_uart_rx.bit_cnt_reg);
                $finish(2);
            end
        end else begin
            // Si es el último bit: la FSM pasa a STOP.
            if (dut.u_uart_rx.state_reg !== RX_STOP) begin
                $display("ERROR [TEST4_RX] Expected STOP state after last data bit, received=%0d", dut.u_uart_rx.state_reg);
                $finish(2);
            end
        end
    end

    check_bit("TEST4_RX", "valid before stop completes", dut.u_uart_rx.valid_reg, 1'b0);

    // El stop bit debe mantenerse hasta completar el frame (faltan 15 ticks).
    for (tick_idx = 0; tick_idx < OVERSAMPLE - 1; tick_idx = tick_idx + 1) begin
        wait_for_next_baud_tick();
        #1;
        if (dut.u_uart_rx.state_reg !== RX_STOP) begin
            $display("ERROR [TEST4_RX] Expected STOP state during stop bit, received=%0d", dut.u_uart_rx.state_reg);
            $finish(2);
        end
    end

    // Al finalizar el stop bit (tick 16 del STOP) se levanta valid por un ciclo y la FSM vuelve a IDLE.
    wait_for_next_baud_tick();
    #1;
    if (dut.u_uart_rx.state_reg !== RX_IDLE) begin
        $display("ERROR [TEST4_RX] Expected IDLE state after frame, received=%0d", dut.u_uart_rx.state_reg);
        $finish(2);
    end
    check_bit("TEST4_RX", "rx valid pulse", dut.u_uart_rx.valid_reg, 1'b1);
    check_bus("TEST4_RX", "received byte", dut.u_uart_rx.o_data, test_byte);
    check_bus("TEST4_RX", "top rx byte", rx_data, test_byte);
    check_bit("TEST4_RX", "top rx valid", rx_valid, 1'b1);

    // Un ciclo despues, el pulso de valid debe desaparecer.
    @(posedge clock);
    #1;
    check_bit("TEST4_RX", "rx valid released", dut.u_uart_rx.valid_reg, 1'b0);

    $display("TEST4 PASSED");
    $finish;
end
`endif