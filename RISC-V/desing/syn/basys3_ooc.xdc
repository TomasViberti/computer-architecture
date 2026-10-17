## ---------------------------------------------------------------------
## Constraints para sintetizar modulo solo, sin el resto del procesador
##
## Uso: en Vivado, Settings > Synthesis > More Options, escribir:
##          -mode out_of_context
##      Top module: modulo_a_sintetizar
##      Part: xc7a35tcpg236-1 (Basys 3)
##
## ---------------------------------------------------------------------

create_clock -period 20.000 -name clk [get_ports clock]

set_input_delay  -clock clk 2.000 [get_ports -filter {DIRECTION == IN && NAME != "clock"}]
set_output_delay -clock clk 0.000 [get_ports -filter {DIRECTION == OUT}]
