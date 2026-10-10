`timescale 1ns / 1ps

module alu_tb;

localparam NB_DATA    = 32;
localparam NB_ALUCTRL = 4;

localparam ADD    = 4'b0000;
localparam SLL    = 4'b0001;
localparam SLT    = 4'b0010;
localparam SLTU   = 4'b0011;
localparam XOR    = 4'b0100;
localparam SRL    = 4'b0101;
localparam OR     = 4'b0110;
localparam AND    = 4'b0111;
localparam SUB    = 4'b1000;
localparam SRA    = 4'b1101;
localparam PASS_B = 4'b1111;

reg  [NB_DATA - 1 : 0]    a;
reg  [NB_DATA - 1 : 0]    b;
reg  [NB_ALUCTRL - 1 : 0] ctrl;
wire [NB_DATA - 1 : 0]    result;
wire                      zero;

integer errors = 0;
integer tests  = 0;

alu #(.NB_DATA(NB_DATA), .NB_ALUCTRL(NB_ALUCTRL)) dut (
    .i_data_a     (a),
    .i_data_b     (b),
    .i_alu_ctrl   (ctrl),
    .o_alu_result (result),
    .o_zero       (zero)
);

task check;
    input [NB_ALUCTRL - 1 : 0] t_ctrl;
    input [NB_DATA - 1 : 0]    t_a;
    input [NB_DATA - 1 : 0]    t_b;
    input [NB_DATA - 1 : 0]    t_expected;
    input [255:0]              t_name;
    begin
        ctrl = t_ctrl; a = t_a; b = t_b;
        #1;
        tests = tests + 1;
        if (result !== t_expected || zero !== (t_expected == 0)) begin
            errors = errors + 1;
            $display("FAIL %0s: a=%h b=%h -> %h (esperado %h), zero=%b",
                     t_name, t_a, t_b, result, t_expected, zero);
        end else begin
            $display("ok   %0s", t_name);
        end
    end
endtask

initial begin
    check(ADD,    32'd5,        32'd7,        32'd12,       "add basico");
    check(ADD,    32'hFFFFFFFF, 32'd1,        32'd0,        "add overflow ignorado, zero=1");
    check(SUB,    32'd5,        32'd7,        32'hFFFFFFFE, "sub negativo");
    check(SUB,    32'd7,        32'd7,        32'd0,        "sub igual, zero=1");
    check(AND,    32'hF0F0F0F0, 32'hFF00FF00, 32'hF000F000, "and");
    check(OR,     32'hF0F0F0F0, 32'h0F0F0F0F, 32'hFFFFFFFF, "or");
    check(XOR,    32'hFFFF0000, 32'hFF00FF00, 32'h00FFFF00, "xor");
    check(SLL,    32'd1,        32'd4,        32'd16,       "sll");
    check(SLL,    32'd1,        32'd33,       32'd2,        "sll usa solo b[4:0]");
    check(SRL,    32'h80000000, 32'd4,        32'h08000000, "srl rellena con 0");
    check(SRA,    32'h80000000, 32'd4,        32'hF8000000, "sra replica el signo");
    check(SRA,    32'h40000000, 32'd4,        32'h04000000, "sra con positivo");
    check(SLT,    32'hFFFFFFFF, 32'd1,        32'd1,        "slt: -1 < 1");
    check(SLT,    32'd1,        32'hFFFFFFFF, 32'd0,        "slt: 1 < -1 es falso");
    check(SLTU,   32'hFFFFFFFF, 32'd1,        32'd0,        "sltu: 0xFFFFFFFF < 1 es falso");
    check(SLTU,   32'd1,        32'hFFFFFFFF, 32'd1,        "sltu: 1 < 0xFFFFFFFF");
    check(PASS_B, 32'hDEADBEEF, 32'h12345000, 32'h12345000, "pass_b (lui)");
    check(4'b1001, 32'd5,       32'd7,        32'd0,        "codigo no usado -> 0");

    $display("----------------------------------------");
    $display("%0d pruebas, %0d errores", tests, errors);
    if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
    $finish;
end

endmodule