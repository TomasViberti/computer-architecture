`define TEST3

`ifdef TEST3
// Test 3: Verificacion del transmisor UART.
// Comprueba estados, linea serial, shift register y señal de busy durante una trama completa.
initial begin : test_uart_tx_frame
    integer bit_index;
    integer tick_index;
    reg [NB_DATA - 1 : 0] expected_shift;
    reg [7:0] test_byte;

    // Reset inicial antes de comenzar la verificacion.
    apply_reset();

    // Byte de prueba con mezcla de unos y ceros.
    test_byte = 8'hA5;
    expected_shift = test_byte;

    // Se inicia la trama sin esperar a que termine.
    start_tx_frame(test_byte);

    // El transmisor debe entrar en START con la linea en 0 y busy activo.
    wait_tx_state(TX_START);
    #1;
    if (dut.u_uart_tx.o_tx !== 1'b0) begin
        $display("ERROR [TEST3_TX] Start bit expected=0 received=%0b", dut.u_uart_tx.o_tx);
        $finish(2);
    end
    check_bit("TEST3_TX", "tx busy", dut.u_uart_tx.o_tx_busy, 1'b1);
    check_bus("TEST3_TX", "tx shift register", dut.u_uart_tx.data_reg, expected_shift);

    // Durante la fase START la linea debe mantenerse en cero por OVERSAMPLE ticks.
    for (tick_index = 0; tick_index < OVERSAMPLE - 1; tick_index = tick_index + 1) begin
        wait_for_next_baud_tick();
        #1;
        if (dut.u_uart_tx.state_reg !== TX_START) begin
            $display("ERROR [TEST3_TX] Expected START state during start bit, received=%0d", dut.u_uart_tx.state_reg);
            $finish(2);
        end
        check_bit("TEST3_TX", "start bit level", dut.u_uart_tx.o_tx, 1'b0);
    end

    // En el siguiente tick termina el START y comienza DATA con el bit 0 primero.
    // Como el RTL fuerza tx_next = data_reg[0] al entrar al estado, NO hay retardo.
    wait_for_next_baud_tick();
    #1;
    if (dut.u_uart_tx.state_reg !== TX_DATA) begin
        $display("ERROR [TEST3_TX] Expected DATA state after start bit, received=%0d", dut.u_uart_tx.state_reg);
        $finish(2);
    end
    check_bit("TEST3_TX", "first data bit", dut.u_uart_tx.o_tx, expected_shift[0]);
    check_bus("TEST3_TX", "shift register at data entry", dut.u_uart_tx.data_reg, expected_shift);
    if (dut.u_uart_tx.bit_cnt_reg !== 0) begin
        $display("ERROR [TEST3_TX] bit counter expected=0 received=%0d", dut.u_uart_tx.bit_cnt_reg);
        $finish(2);
    end

    // Cada bit-time completo avanza al siguiente bit transmitido y desplaza el registro interno.
    // Cubre las transiciones bit0->bit1 ... bit(NB_DATA-2)->bit(NB_DATA-1).
    for (bit_index = 1; bit_index < NB_DATA; bit_index = bit_index + 1) begin
        
        // Mantiene el bit actual durante el resto del bit-time (OVERSAMPLE-1 ticks).
        for (tick_index = 0; tick_index < OVERSAMPLE - 1; tick_index = tick_index + 1) begin
            wait_for_next_baud_tick();
            #1;
            if (dut.u_uart_tx.state_reg !== TX_DATA) begin
                $display("ERROR [TEST3_TX] Expected DATA state during bit hold, received=%0d", dut.u_uart_tx.state_reg);
                $finish(2);
            end
            check_bit("TEST3_TX", "data bit held", dut.u_uart_tx.o_tx, expected_shift[0]);
        end

        // El ultimo tick del bit-time desplaza el shift register.
        wait_for_next_baud_tick();
        expected_shift = {1'b0, expected_shift[NB_DATA - 1 : 1]};
        #1;
        if (dut.u_uart_tx.state_reg !== TX_DATA) begin
            $display("ERROR [TEST3_TX] Expected DATA state, received=%0d", dut.u_uart_tx.state_reg);
            $finish(2);
        end
        
        // --- COMPENSACIÓN DEL HARDWARE ---
        // Como eliminamos el "look-ahead" en el RTL, el registro de transmisión (tx_reg) 
        // toma 1 ciclo de reloj extra en actualizarse con el bit recién desplazado.
        // Avanzamos 1 ciclo exacto en el simulador para que el pin o_tx refleje la realidad.
        @(posedge clock);
        #1;
        
        check_bit("TEST3_TX", "data bit level", dut.u_uart_tx.o_tx, expected_shift[0]);
        check_bus("TEST3_TX", "shift register during data", dut.u_uart_tx.data_reg, expected_shift);
        if (dut.u_uart_tx.bit_cnt_reg !== bit_index[2:0]) begin
            $display("ERROR [TEST3_TX] bit counter expected=%0d received=%0d", bit_index, dut.u_uart_tx.bit_cnt_reg);
            $finish(2);
        end
    end

    // El ultimo bit de datos (bit_cnt_reg == NB_DATA-1) tambien debe sostenerse
    // durante OVERSAMPLE-1 ticks antes de que el ultimo tick dispare la transicion a STOP.
    for (tick_index = 0; tick_index < OVERSAMPLE - 1; tick_index = tick_index + 1) begin
        wait_for_next_baud_tick();
        #1;
        if (dut.u_uart_tx.state_reg !== TX_DATA) begin
            $display("ERROR [TEST3_TX] Expected DATA state during last bit hold, received=%0d", dut.u_uart_tx.state_reg);
            $finish(2);
        end
        check_bit("TEST3_TX", "last data bit held", dut.u_uart_tx.o_tx, expected_shift[0]);
    end

    // El ultimo tick de DATA lleva a STOP y la linea vuelve a 1.
    wait_for_next_baud_tick();
    #1;
    if (dut.u_uart_tx.state_reg !== TX_STOP) begin
        $display("ERROR [TEST3_TX] Expected STOP state, received=%0d", dut.u_uart_tx.state_reg);
        $finish(2);
    end
    
    // Al entrar a STOP, el RTL sí fuerza explícitamente tx_next = 1'b1 en el mismo tick, 
    // por lo que el pin o_tx sube al instante (no requiere el delay de 1 clock).
    check_bit("TEST3_TX", "stop bit level", dut.u_uart_tx.o_tx, 1'b1);
    check_bit("TEST3_TX", "tx busy in stop", dut.u_uart_tx.o_tx_busy, 1'b1);

    // La fase STOP dura otro bit completo y luego emite done y vuelve a IDLE.
    for (tick_index = 0; tick_index < OVERSAMPLE - 1; tick_index = tick_index + 1) begin
        wait_for_next_baud_tick();
        #1;
        if (dut.u_uart_tx.state_reg !== TX_STOP) begin
            $display("ERROR [TEST3_TX] Expected STOP state during stop bit, received=%0d", dut.u_uart_tx.state_reg);
            $finish(2);
        end
        check_bit("TEST3_TX", "stop bit held high", dut.u_uart_tx.o_tx, 1'b1);
    end

    wait_for_next_baud_tick();
    #1;
    if (dut.u_uart_tx.state_reg !== TX_IDLE) begin
        $display("ERROR [TEST3_TX] Expected IDLE state at end of frame, received=%0d", dut.u_uart_tx.state_reg);
        $finish(2);
    end
    check_bit("TEST3_TX", "tx done pulse", dut.u_uart_tx.done_reg, 1'b1);
    check_bit("TEST3_TX", "tx busy after frame", dut.u_uart_tx.o_tx_busy, 1'b0);
    check_bit("TEST3_TX", "tx line idle", dut.u_uart_tx.o_tx, 1'b1);

    // Un ciclo despues, el pulso de done debe desaparecer.
    @(posedge clock);
    #1;
    check_bit("TEST3_TX", "tx done released", dut.u_uart_tx.done_reg, 1'b0);

    $display("TEST3 PASSED");
    $finish;
end
`endif