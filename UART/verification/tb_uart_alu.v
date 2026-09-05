`timescale 1ns/1ps

module tb_top_uart_alu;

localparam CLK_FREQ  = 50_000_000;
localparam BAUD_RATE = 9600;
localparam NB_DATA   = 8;
localparam NB_OPCODE = 6;

reg  clock;
reg  rst_n;
reg  pc_tx_line; 

wire fpga_tx_line;

top_uart_alu #(
    .CLK_FREQ  (CLK_FREQ)  ,
    .BAUD_RATE (BAUD_RATE) ,
    .NB_DATA   (NB_DATA)   ,
    .NB_OPCODE (NB_OPCODE)
) dut (
    .clock   (clock)        ,
    .i_rst_n (rst_n)        ,
    .i_rx    (pc_tx_line)   ,
    .o_tx    (fpga_tx_line)
);

// ---------------------------------------------------------------
// Decodificador de la respuesta hacia la "PC" un uart_rx escuchando o_tx
// ---------------------------------------------------------------
wire tick_pc;
wire [NB_DATA-1:0] pc_rx_data;
wire pc_rx_valid;

baud_rate_gen #(
    .CLK_FREQ  (CLK_FREQ)  ,
    .BAUD_RATE (BAUD_RATE)
) u_baud_pc (
    .clock   (clock)   ,
    .i_rst_n (rst_n)   ,
    .o_tick  (tick_pc)
);

uart_rx #(
    .NB_DATA (NB_DATA)
) u_pc_rx (
    .clock   (clock)        ,
    .i_rst_n (rst_n)        ,
    .i_tick  (tick_pc)      ,
    .i_rx    (fpga_tx_line) ,
    .o_data  (pc_rx_data)   ,
    .o_valid (pc_rx_valid)
);

initial clock = 0;
always #10 clock = ~clock; // 50MHz

localparam BIT_TIME = 104167; // ~ 1/9600 s en ns

// manda un byte por la linea serie emulando una UART externa (la "PC")
task pc_send_byte(input [7:0] data);
    integer i;
    begin
        pc_tx_line = 1'b0; // start bit
        #(BIT_TIME);
        for (i = 0; i < 8; i = i + 1) begin
            pc_tx_line = data[i];
            #(BIT_TIME);
        end
        pc_tx_line = 1'b1; // stop bit
        #(BIT_TIME);
    end
endtask

// captura los 2 bytes de respuesta (resultado + carry)
reg [7:0] resp_bytes [0:1];
integer   resp_count = 0;

always @(posedge clock) begin
    if (pc_rx_valid) begin
        resp_bytes[resp_count] = pc_rx_data;
        resp_count = resp_count + 1;
    end
end

integer errors = 0;

// manda un comando ALU completo (3 bytes) y verifica los 2 bytes de respuesta
task run_alu_op(
    input [7:0] data_a,
    input [7:0] data_b,
    input [5:0] opcode,
    input [7:0] expected_result,
    input       expected_carry,
    input [8*20-1:0] op_name
);
    begin
        resp_count = 0;

        pc_send_byte(data_a);
        pc_send_byte(data_b);
        pc_send_byte({2'b00, opcode});

        // esperamos los 2 bytes de respuesta (con margen de tiempo)
        wait (resp_count == 2);
        #(BIT_TIME);

        if (resp_bytes[0] !== expected_result) begin
            $display("FALLO [%0s]: alu_result esperado 0x%0h, recibido 0x%0h", op_name, expected_result, resp_bytes[0]);
            errors = errors + 1;
        end else if (resp_bytes[1][0] !== expected_carry) begin
            $display("FALLO [%0s]: carry esperado %0b, recibido %0b", op_name, expected_carry, resp_bytes[1][0]);
            errors = errors + 1;
        end else begin
            $display("OK [%0s]: data_a=0x%0h data_b=0x%0h -> result=0x%0h carry=%0b",op_name, data_a, data_b, resp_bytes[0], resp_bytes[1][0]);
        end
    end
endtask

initial begin
    rst_n      = 0;
    pc_tx_line = 1'b1; // idle
    #200;
    rst_n = 1;
    #200;

    run_alu_op(8'd10, 8'd20, 6'b100000, 8'd30,  1'b0, "ADD");
    run_alu_op(8'd5,  8'd10, 6'b100010, 8'hFB,  1'b1, "SUB (resta con signo, carry=1)");
    run_alu_op(8'hFF, 8'h0F, 6'b100100, 8'h0F,  1'b0, "AND");
    run_alu_op(8'hF0, 8'h0F, 6'b100101, 8'hFF,  1'b0, "OR");
    run_alu_op(8'hFF, 8'h0F, 6'b100110, 8'hF0,  1'b0, "XOR");
    run_alu_op(8'hFF, 8'h0F, 6'b100111, 8'h00,  1'b0, "NOR");

    #(BIT_TIME * 2);

    if (errors == 0)
        $display("TODOS LOS TESTS DE INTEGRACION PASARON");
    else
        $display("%0d TESTS FALLARON", errors);

    $finish;
end

endmodule