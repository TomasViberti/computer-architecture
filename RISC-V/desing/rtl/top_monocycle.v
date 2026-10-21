/* Top del procesador RISC-V (RV32I) monociclo
----------------------------------------------------------------------
Cada instruccion se ejecuta completa en un ciclo de clock:
    PC -> instr_mem -> control_unit / regfile / imm_gen -> ALU
       -> data_mem -> mux de write back -> regfile
y en el mismo flanco se actualiza el PC con el proximo valor.

Proximo PC:
----------------------------------------------------------------------
| Caso                        | next_pc
----------------------------------------------------------------------
| jal                         | PC + imm
| jalr                        | (rs1 + imm) & ~1     (sale de la ALU)
| branch tomado (beq / bne)   | PC + imm
| resto                       | PC + 4
----------------------------------------------------------------------
beq salta con Zero = 1 y bne con Zero = 0 (funct3[0] elige cual).

Write back (MemToReg): 00 = resultado ALU, 01 = dato de memoria,
10 = PC + 4 (direccion de retorno de jal / jalr).

Ejecucion:
- i_enable = 1 deja correr al procesador. Con i_enable = 0 (o despues
  de un HALT) el PC queda quieto y se bloquean las escrituras en el
  banco de registros y en la memoria de datos. Asi la instruccion
  actual no se "repite" mientras el procesador esta detenido.
- Para ejecutar paso a paso basta con dar i_enable = 1 durante un
  solo ciclo (lo hara la Debug Unit).
- La memoria de programa solo acepta escrituras con el procesador
  detenido (i_enable = 0 o en HALT).
----------------------------------------------------------------------*/

module top_monocycle
#(
    parameter IMEM_DEPTH     = 256                  ,   // palabras de programa
    parameter DMEM_DEPTH     = 256                  ,   // palabras de datos
    parameter DMEM_ADDR_BITS = $clog2(DMEM_DEPTH)   ,   // no modificar
    parameter IMEM_ADDR_BITS = $clog2(IMEM_DEPTH)       // no modificar
)
(
    input  wire                          clock               ,
    input  wire                          i_rst_n             ,   // activo en bajo: PC = 0
    input  wire                          i_enable            ,   // 1 = el procesador ejecuta

    // Carga de programa (Debug Unit)
    input  wire                          i_imem_write_enable ,
    input  wire [IMEM_ADDR_BITS - 1 : 0] i_imem_write_addr   ,   // indice de palabra
    input  wire [31 : 0]                 i_imem_write_data   ,

    // Estado para observar / depurar
    output wire [31 : 0]                 o_pc                ,
    output wire [31 : 0]                 o_instr             ,
    output wire                          o_halt              ,   // la instruccion actual es HALT
    output wire                          o_imem_addr_error   ,
    output wire                          o_dmem_addr_error   ,

    // Lectura de debug (Debug Unit)
    input  wire [4 : 0]                  i_debug_reg_addr    ,   // registro a leer (x0 a x31)
    output wire [31 : 0]                 o_debug_reg_data    ,
    input  wire [DMEM_ADDR_BITS - 1 : 0] i_debug_mem_addr    ,   // indice de palabra de la memoria de datos
    output wire [31 : 0]                 o_debug_mem_data
);

localparam JUMP_JAL  = 2'b01;
localparam JUMP_JALR = 2'b10;

localparam MTR_ALU = 2'b00;
localparam MTR_MEM = 2'b01;
localparam MTR_PC4 = 2'b10;

// ---------------- SEÑALES ----------------

// Fetch
wire [31 : 0] pc_current;
wire [31 : 0] pc_next;
wire [31 : 0] pc_plus4;
wire [31 : 0] instr;

// Campos de la instruccion
wire [6 : 0]  opcode   = instr[6 : 0];
wire [4 : 0]  rd       = instr[11 : 7];
wire [2 : 0]  funct3   = instr[14 : 12];
wire [4 : 0]  rs1      = instr[19 : 15];
wire [4 : 0]  rs2      = instr[24 : 20];
wire          funct7_5 = instr[30];

// Control
wire          reg_write;
wire          alu_src;
wire [2 : 0]  alu_op;
wire          mem_read;
wire          mem_write;
wire [1 : 0]  mem_to_reg;
wire          branch;
wire [1 : 0]  jump;
wire          halt;
wire [3 : 0]  alu_ctrl;

// Datapath
wire [31 : 0] read_data1;
wire [31 : 0] read_data2;
wire [31 : 0] imm;
wire [31 : 0] alu_b;
wire [31 : 0] alu_result;
wire          alu_zero;
wire [31 : 0] mem_rdata;
reg  [31 : 0] write_back;

// El procesador avanza solo si esta habilitado y la instruccion no es HALT
wire          cpu_run = i_enable & ~halt;

// ---------------- FETCH ----------------

pc u_pc (
    .clock          (clock      ),
    .i_rst_n        (i_rst_n    ),
    .i_enable       (cpu_run    ),
    .i_next_pc      (pc_next    ),
    .o_current_pc   (pc_current )
);

instr_mem #(
    .DEPTH          (IMEM_DEPTH )
) u_instr_mem (
    .clock          (clock               ),
    .i_halted       (~cpu_run            ),
    .i_write_enable (i_imem_write_enable ),
    .i_write_addr   (i_imem_write_addr   ),
    .i_write_data   (i_imem_write_data   ),
    .i_pc           (pc_current          ),
    .o_instr        (instr               ),
    .o_addr_error   (o_imem_addr_error   )
);

// ---------------- DECODE ----------------

control_unit u_control_unit (
    .i_opcode       (opcode     ),
    .o_reg_write    (reg_write  ),
    .o_alu_src      (alu_src    ),
    .o_alu_op       (alu_op     ),
    .o_mem_read     (mem_read   ),
    .o_mem_write    (mem_write  ),
    .o_mem_to_reg   (mem_to_reg ),
    .o_branch       (branch     ),
    .o_jump         (jump       ),
    .o_halt         (halt       )
);

regfile u_regfile (
    .clock          (clock                 ),
    .i_reg_write    (reg_write & cpu_run   ),
    .i_debug_addr   (i_debug_reg_addr      ),
    .i_rs1          (rs1                   ),
    .i_rs2          (rs2                   ),
    .i_rd           (rd                    ),
    .i_write_data   (write_back            ),
    .o_read_data1   (read_data1            ),
    .o_read_data2   (read_data2            ),
    .o_debug_data   (o_debug_reg_data      )
);

imm_gen u_imm_gen (
    .i_inst         (instr ),
    .o_imm          (imm   )
);

// ---------------- EXECUTE ----------------

alu_control u_alu_control (
    .i_alu_op       (alu_op   ),
    .i_funct3       (funct3   ),
    .i_funct7_5     (funct7_5 ),
    .o_alu_ctrl     (alu_ctrl )
);

assign alu_b = alu_src ? imm : read_data2;

alu u_alu (
    .i_data_a       (read_data1 ),
    .i_data_b       (alu_b      ),
    .i_alu_ctrl     (alu_ctrl   ),
    .o_alu_result   (alu_result ),
    .o_zero         (alu_zero   )
);

// ---------------- MEMORY ----------------

data_mem #(
    .DEPTH          (DMEM_DEPTH )
) u_data_mem (
    .clock          (clock               ),
    .i_addr         (alu_result          ),
    .i_debug_addr   (i_debug_mem_addr    ),
    .i_wdata        (read_data2          ),
    .i_memread      (mem_read            ),
    .i_memwrite     (mem_write & cpu_run ),
    .i_funct3       (funct3              ),
    .o_rdata        (mem_rdata           ),
    .o_addr_error   (o_dmem_addr_error   ),
    .o_debug_data   (o_debug_mem_data    )
);

// ---------------- WRITE BACK ----------------

always @(*) begin
    case (mem_to_reg)
        MTR_ALU: write_back = alu_result;
        MTR_MEM: write_back = mem_rdata;
        MTR_PC4: write_back = pc_plus4;
        default: write_back = alu_result;
    endcase
end

// ---------------- PROXIMO PC ----------------

assign pc_plus4 = pc_current + 32'd4;

wire [31 : 0] pc_target   = pc_current + imm;                   // branches y jal
wire [31 : 0] jalr_target = {alu_result[31 : 1], 1'b0};         // rs1 + imm, bit 0 en 0
wire          branch_take = branch & (funct3[0] ? ~alu_zero : alu_zero);

assign pc_next = (jump == JUMP_JAL ) ? pc_target   :
                 (jump == JUMP_JALR) ? jalr_target :
                 branch_take         ? pc_target   :
                                       pc_plus4;

// ---------------- SALIDAS ----------------

assign o_pc    = pc_current;
assign o_instr = instr;
assign o_halt  = halt;

endmodule
