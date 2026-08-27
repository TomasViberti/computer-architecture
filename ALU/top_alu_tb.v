`timescale 1ns / 1ps

module tb_top_alu;

    localparam NB_DATA   = 8;
    localparam NB_OPCODE = 6;
    localparam N_BOTONS  = 4;

    // Códigos de operación (deben coincidir con los de alu.v)
    localparam ADD = 6'b100000;

    // Códigos de botón (deben coincidir con los de top_alu.v)
    localparam LOAD_A   = 4'b1000;
    localparam LOAD_B   = 4'b0100;
    localparam LOAD_OP  = 4'b0010;
    localparam LOAD_ALU = 4'b0001;
    localparam LOAD_NONE= 4'b0000;

    // Señales conectadas al DUT (Device Under Test)
    reg  [NB_DATA - 1 : 0]  i_switches;
    reg  [N_BOTONS - 1 : 0] i_btn_load;
    reg                     i_rst_n;
    reg                     clock;

    wire [NB_DATA - 1 : 0]  o_leds;
    wire                    o_carry;

    // Instancia del top
    top_alu #(
        .NB_DATA   (NB_DATA)  ,
        .NB_OPCODE (NB_OPCODE),
        .N_BOTONS  (N_BOTONS)
    ) dut (
        .i_switches (i_switches),
        .i_btn_load (i_btn_load),
        .i_rst_n    (i_rst_n)   ,
        .clock      (clock)     ,
        .o_leds     (o_leds)    ,
        .o_carry    (o_carry)
    );

    // Generación de clock: periodo de 10ns (100MHz)
    always #5 clock = ~clock;

    // Tarea auxiliar: simula "apretar" un botón durante 1 ciclo de clock
    task pulsar_boton(input [N_BOTONS-1:0] boton);
        begin
            @(negedge clock);
            i_btn_load = boton;
            @(negedge clock);
            i_btn_load = LOAD_NONE;
        end
    endtask

    initial begin
        // Dump para ver las formas de onda en Vivado
        $dumpfile("tb_top_alu.vcd");
        $dumpvars(0, tb_top_alu);

        // Estado inicial
        clock      = 0;
        i_rst_n    = 0;
        i_btn_load = LOAD_NONE;
        i_switches = 0;

        // Reset
        #20;
        i_rst_n = 1;

        // ---------------------------------------------------------
        // Test: ADD de 5 + 3 = 8
        // ---------------------------------------------------------

        // Cargar Dato A = 5
        i_switches = 8'd5;
        pulsar_boton(LOAD_A);

        // Cargar Dato B = 3
        i_switches = 8'd3;
        pulsar_boton(LOAD_B);

        // Cargar Op = ADD
        i_switches = {2'b00, ADD}; // los bits bajos son el opcode
        pulsar_boton(LOAD_OP);

        // Cargar los registros de la ALU y ejecutar
        pulsar_boton(LOAD_ALU);

        #20;
        $display("o_leds = %d (esperado 8), o_carry = %b (esperado 0)", o_leds, o_carry);

        #50;
        $finish;
    end

endmodule