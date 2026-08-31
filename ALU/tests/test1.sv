`define TEST1

`ifdef TEST1

// Test 1: Comportamiento básico de la ALU.
// Valida reset, carga de operandos, ejecución de ADD y retención de la salida.

initial begin : test_reset_load_and_add
	reg [NB_DATA - 1 : 0] value_a;
	reg [NB_DATA - 1 : 0] value_b;

	// Verificación del reset: la salida debe quedar en cero.
	apply_reset();

	if (o_leds !== {NB_DATA{1'b0}} || o_carry !== 1'b0) 
    begin
		$display("ERROR [TEST1_RESET] Output did not remain at zero after reset: leds=%0d carry=%b", o_leds, o_carry);
		$finish(2);
	end

	// Carga aleatoria de A y B dentro del ancho completo del bus.
	value_a = $urandom_range(0, 2**NB_DATA - 1);
	value_b = $urandom_range(0, 2**NB_DATA - 1);

	// Secuencia de carga y ejecución de ADD.
	prepare_and_execute(value_a, value_b, ADD);
	check_transaction(value_a, value_b, ADD, "TEST1_ADD_BASIC");

	// Caso arbitrario para forzar carry en la suma.
	value_a = 8'd200;
	value_b = 8'd100;

	// Se repite la ejecución para validar el carry de salida.
	prepare_and_execute(value_a, value_b, ADD);
	check_transaction(value_a, value_b, ADD, "TEST1_ADD_CARRY");

	// El botón LOAD_NONE no debe alterar la salida.
	press_button(LOAD_NONE);
	#1;

	// Chequeo de retención de salida.
	if (o_leds !== expected_result(value_a, value_b, ADD)) 
    begin
		$display("ERROR [TEST1_HOLD] Output changed without LOAD_ALU.");
		$finish(2);
	end

	// Fin del test.
	$display("TEST1 PASSED");
	$finish;
end
`endif