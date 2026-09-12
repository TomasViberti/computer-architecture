## ------------------------------------------------------------------
## Basys3 (xc7a35tcpg236-1) - Constraints para top_uart_alu
## ------------------------------------------------------------------

## Clock del sistema: 100 MHz
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
# i_rx es el pin por donde la placa ESCUCHA a la PC
set_property PACKAGE_PIN B18 [get_ports i_rx]
set_property IOSTANDARD LVCMOS33 [get_ports i_rx]

# o_tx es el pin por donde la placa LE HABLA a la PC
set_property PACKAGE_PIN A18 [get_ports o_tx]
set_property IOSTANDARD LVCMOS33 [get_ports o_tx]

## ------------------------------------------------------------------
## LEDs: LD0-LD7 -> o_leds[7:0] (Resultado), LD8 -> o_carry (Carry)
## ------------------------------------------------------------------
set_property PACKAGE_PIN U16 [get_ports {o_leds[0]}]
set_property PACKAGE_PIN E19 [get_ports {o_leds[1]}]
set_property PACKAGE_PIN U19 [get_ports {o_leds[2]}]
set_property PACKAGE_PIN V19 [get_ports {o_leds[3]}]
set_property PACKAGE_PIN W18 [get_ports {o_leds[4]}]
set_property PACKAGE_PIN U15 [get_ports {o_leds[5]}]
set_property PACKAGE_PIN U14 [get_ports {o_leds[6]}]
set_property PACKAGE_PIN V14 [get_ports {o_leds[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_leds[*]}]

set_property PACKAGE_PIN V13 [get_ports o_carry]
set_property IOSTANDARD LVCMOS33 [get_ports o_carry]