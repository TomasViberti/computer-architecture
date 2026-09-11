`define TEST6
`ifdef TEST6
initial begin : test_sra
    integer i;
    reg [NB_DATA - 1 : 0] value_a;
    reg [NB_DATA - 1 : 0] value_b; // Nuevo registro de estímulo para B

    apply_reset();

    // Caso dirigido: Validar el bit de signo con una magnitud de B = 1
    value_a = 8'b1000_0000;
    value_b = 8'h01; 
    run_alu_transaction(value_a, value_b, SRA);
    check_transaction(value_a, value_b, SRA, "TEST6_SRA_EDGE");

    // Iteraciones aleatorias: Estresar A y el rango de desplazamiento B (0 a 7)
    for (i = 0; i < 10; i = i + 1) begin
        value_a = $urandom_range(0, 2**NB_DATA - 1);
        value_b = $urandom_range(0, 7); 

        run_alu_transaction(value_a, value_b, SRA);
        check_transaction(value_a, value_b, SRA, "TEST6_SRA_RANDOM");
    end

    if (errors == 0) $display("TEST6 PASSED");
    else begin $display("TEST6 FAILED"); $finish(2); end
    
    $finish;
end
`endif