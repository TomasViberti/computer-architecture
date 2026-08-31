`define SIMULATION
`default_nettype none
`timescale 1ns / 1ps

module tb_top_alu;

    localparam NB_DATA   = 8;
    localparam NB_OPCODE = 6;
    localparam N_BOTONS  = 4;

    // Códigos de operación, deben matchear con los de la ALU.
    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;
    localparam AND = 6'b100100;
    localparam OR  = 6'b100101;
    localparam XOR = 6'b100110;
    localparam SRA = 6'b000011;
    localparam SRL = 6'b000010;
    localparam NOR = 6'b100111;

    // Códigos de botón. Tienen que matchear con top_alu.v.
    localparam LOAD_A    = 4'b1000;
    localparam LOAD_B    = 4'b0100;
    localparam LOAD_OP   = 4'b0010;
    localparam LOAD_ALU  = 4'b0001;
    localparam LOAD_NONE = 4'b0000;

    // Entradas del DUT.
    reg  [NB_DATA - 1 : 0]  i_switches = {NB_DATA{1'b0}};
    reg  [N_BOTONS - 1 : 0] i_btn_load = {N_BOTONS{1'b0}};
    reg                     i_rst_n    = 1'b0;
    reg                     clock      = 1'b0;

    // Salidas del DUT.
    wire [NB_DATA - 1 : 0]  o_leds;
    wire                    o_carry;

    // Instancia del DUT.
    top_alu #(
        .NB_DATA   (NB_DATA),
        .NB_OPCODE (NB_OPCODE),
        .N_BOTONS  (N_BOTONS)
    ) dut (
        .i_switches (i_switches),
        .i_btn_load (i_btn_load),
        .i_rst_n    (i_rst_n),
        .clock      (clock),
        .o_leds     (o_leds),
        .o_carry    (o_carry)
    );

    // Wire a registros internos para poder visualizar el comportamiento de cada test en el waveform de manera interna, es decir,
    // como cambian A, B y el resultado.
    wire [NB_DATA - 1 : 0]   probe_buf_a     = dut.buf_a;
    wire [NB_DATA - 1 : 0]   probe_buf_b     = dut.buf_b;
    wire [NB_OPCODE - 1 : 0] probe_buf_op    = dut.buf_op;

    wire [NB_DATA - 1 : 0]   probe_alu_in_a  = dut.alu_in_a;
    wire [NB_DATA - 1 : 0]   probe_alu_in_b  = dut.alu_in_b;
    wire [NB_OPCODE - 1 : 0] probe_alu_in_op = dut.alu_in_op;

    // Generación del clock de 10ns de período.
    always #5 clock = ~clock;

    // Función que retorna el resultado esperado de una operación
    function automatic [NB_DATA - 1 : 0] expected_result;
        input [NB_DATA - 1 : 0]   data_a;
        input [NB_DATA - 1 : 0]   data_b;
        input [NB_OPCODE - 1 : 0] op_code;
        reg   [NB_DATA : 0]       wide_result;
        begin
            case (op_code)
                ADD: begin
                    wide_result     = {1'b0, data_a} + {1'b0, data_b};
                    expected_result = wide_result[NB_DATA - 1 : 0];
                end
                SUB: begin
                    wide_result     = {1'b0, data_a} - {1'b0, data_b};
                    expected_result = wide_result[NB_DATA - 1 : 0];
                end
                AND: expected_result = data_a & data_b;
                OR : expected_result = data_a | data_b;
                XOR: expected_result = data_a ^ data_b;
                SRA: expected_result = $signed(data_a) >>> 1;
                SRL: expected_result = data_a >> 1;
                NOR: expected_result = ~(data_a | data_b);
                default: expected_result = {NB_DATA{1'b0}};
            endcase
        end
    endfunction

    // Función que retorna el carry esperado para las operaciones ADD y SUB, y para el resto cero.
    function automatic expected_carry;
        input [NB_DATA - 1 : 0]   data_a;
        input [NB_DATA - 1 : 0]   data_b;
        input [NB_OPCODE - 1 : 0] op_code;
        reg   [NB_DATA : 0]       wide_result;
        begin
            case (op_code)
                ADD: begin
                    wide_result    = {1'b0, data_a} + {1'b0, data_b};
                    expected_carry = wide_result[NB_DATA];
                end
                SUB: begin
                    wide_result    = {1'b0, data_a} - {1'b0, data_b};
                    expected_carry = wide_result[NB_DATA];
                end
                default: expected_carry = 1'b0;
            endcase
        end
    endfunction

    // Función que aplica un reset y deja listo el modulo para una ejecución.
    task automatic apply_reset;
        begin
            i_rst_n    = 1'b0;
            i_btn_load = LOAD_NONE;
            i_switches = {NB_DATA{1'b0}};
            repeat (2) @(posedge clock);
            #1;
            i_rst_n = 1'b1;
            @(posedge clock);
            #1;
        end
    endtask

    // Task para presionar un botón de los disponibles.
    task automatic press_button(input [N_BOTONS - 1 : 0] button);
        begin
            @(negedge clock);
            i_btn_load = button;
            @(negedge clock);
            i_btn_load = LOAD_NONE;
        end
    endtask

    // Task para cargar un valor en A.
    task automatic load_a(input [NB_DATA - 1 : 0] value);
        begin
            i_switches = value;
            press_button(LOAD_A);
        end
    endtask

    // Task para cargar un valor en B.
    task automatic load_b(input [NB_DATA - 1 : 0] value);
        begin
            i_switches = value;
            press_button(LOAD_B);
        end
    endtask

    // Task para cargar un valor en el registro de operación.
    task automatic load_opcode(input [NB_OPCODE - 1 : 0] value);
        begin
            i_switches = {{(NB_DATA - NB_OPCODE){1'b0}}, value};
            press_button(LOAD_OP);
        end
    endtask

    // Task para ejecutar la ALU, es decir, insertar los valores cargador en A, B y OPCODE
    // y actualizar la salida.
    task automatic execute_alu;
        begin
            press_button(LOAD_ALU);
            #1;
        end
    endtask

    // Task para ejecutar una operación completa en la ALU:
    // Cargar valores en A,B y OPCODE, y ejecutar la ALU.
    task automatic prepare_and_execute(
        input [NB_DATA - 1 : 0]   value_a,
        input [NB_DATA - 1 : 0]   value_b,
        input [NB_OPCODE - 1 : 0] op_code
    );
        begin
            load_a(value_a);
            load_b(value_b);
            load_opcode(op_code);
            execute_alu();
        end
    endtask

    // Task para verificar si el resultado obtenido despues de la ejecución
    // de la ALU es el correcto y esperado. Se utiliza en los tests para 
    // devolver TEST FAILED.
    task automatic check_result(
        input [NB_DATA - 1 : 0]   value_a,
        input [NB_DATA - 1 : 0]   value_b,
        input [NB_OPCODE - 1 : 0] op_code,
        input [NB_DATA - 1 : 0]   expected_leds,
        input                     expected_carry_value,
        input [8*64 - 1 : 0]      test_name
    );
        begin
            if (o_leds !== expected_leds || o_carry !== expected_carry_value) 
            begin
                $display("TEST FAILED: Error, [%0s] A=%0d B=%0d OP=%b -> leds=%0d carry=%b, expected leds=%0d carry=%b",
                         test_name, value_a, value_b, op_code, o_leds, o_carry, expected_leds, expected_carry_value);
                $finish(2);
            end
        end
    endtask

    // Task para obtener el resultado esperado de la operación cargada en la ALU.
    task automatic check_transaction(
        input [NB_DATA - 1 : 0]   value_a,
        input [NB_DATA - 1 : 0]   value_b,
        input [NB_OPCODE - 1 : 0] op_code,
        input [8*64 - 1 : 0]      test_name
    );
        reg [NB_DATA - 1 : 0] expected_leds;
        reg                   expected_carry_value;
        begin
            expected_leds        = expected_result(value_a, value_b, op_code);
            expected_carry_value = expected_carry(value_a, value_b, op_code);
            check_result(value_a, value_b, op_code, expected_leds, expected_carry_value, test_name);
        end
    endtask

    // Genera las señales para analizar en vivado
    initial begin
        $dumpfile("tb_top_alu.vcd");
        $dumpvars(0, tb_top_alu);
    end

    // Selección del test
    //`include "../tests/test1.sv"
    //`include "../tests/test2.sv"
    //`include "../tests/test3.sv"
    //`include "../tests/test4.sv"
    //`include "../tests/test5.sv"
    //`include "../tests/test6.sv"
    //`include "../tests/test7.sv"
    `include "../tests/test8.sv"

endmodule
