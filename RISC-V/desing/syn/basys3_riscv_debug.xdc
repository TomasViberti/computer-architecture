## ------------------------------------------------------------------
## Basys3 (xc7a35tcpg236-1) - Constraints para top_monocycle_debug
## ------------------------------------------------------------------

## Clock del sistema: 100 MHz (el Clocking Wizard lo baja a 50 MHz)
set_property PACKAGE_PIN W5 [get_ports clock]
set_property IOSTANDARD LVCMOS33 [get_ports clock]
create_clock -period 10.000 -name sys_clk_pin -waveform {0 5} -add [get_ports clock]

## ------------------------------------------------------------------
## Reset: usamos el SW15 (Activo en Bajo - Debe estar ARRIBA para operar)
## ------------------------------------------------------------------
set_property PACKAGE_PIN R2 [get_ports i_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports i_rst_n]

## ------------------------------------------------------------------
## Puertos UART (Conectados al puente USB de la placa Basys 3)
## ------------------------------------------------------------------
# i_uart_rx es el pin por donde la placa ESCUCHA a la PC
set_property PACKAGE_PIN B18 [get_ports i_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports i_uart_rx]

# o_uart_tx es el pin por donde la placa LE HABLA a la PC
set_property PACKAGE_PIN A18 [get_ports o_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]

## ------------------------------------------------------------------
## LEDs de estado:
##   o_led[0] = LD0 -> clock listo (locked del Clocking Wizard)
##   o_led[1] = LD1 -> sistema fuera de reset
##   o_led[2] = LD2 -> el procesador esta ejecutando
## ------------------------------------------------------------------
set_property PACKAGE_PIN U16 [get_ports {o_led[0]}]
set_property PACKAGE_PIN E19 [get_ports {o_led[1]}]
set_property PACKAGE_PIN U19 [get_ports {o_led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[*]}]

## ------------------------------------------------------------------
## Extras (opcionales: los XDC anteriores no los tenian)
## ------------------------------------------------------------------
## Configuracion de la placa
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Estos pines no tienen relacion de tiempo con el clock: no se analizan
set_false_path -from [get_ports i_rst_n]
set_false_path -from [get_ports i_uart_rx]
set_false_path -to   [get_ports o_uart_tx]
set_false_path -to   [get_ports {o_led[*]}]
