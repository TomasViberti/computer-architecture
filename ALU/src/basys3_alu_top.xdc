## ------------------------------------------------------------------
## Basys3 (xc7a35tcpg236-1) - Constraints para alu_top
## ------------------------------------------------------------------

## Clock del sistema: 100 MHz
set_property PACKAGE_PIN W5 [get_ports clock]
set_property IOSTANDARD LVCMOS33 [get_ports clock]
create_clock -period 10.000 -name sys_clk_pin -waveform {0 5} -add [get_ports clock]

## ------------------------------------------------------------------
## Reset: usamos el (SW15)
## ------------------------------------------------------------------
set_property PACKAGE_PIN R2 [get_ports i_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports i_rst_n]

## ------------------------------------------------------------------
## Switches de datos: SW0-SW7 -> i_switches[7:0]
## ------------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports {i_switches[0]}]
set_property PACKAGE_PIN V16 [get_ports {i_switches[1]}]
set_property PACKAGE_PIN W16 [get_ports {i_switches[2]}]
set_property PACKAGE_PIN W17 [get_ports {i_switches[3]}]
set_property PACKAGE_PIN W15 [get_ports {i_switches[4]}]
set_property PACKAGE_PIN V15 [get_ports {i_switches[5]}]
set_property PACKAGE_PIN W14 [get_ports {i_switches[6]}]
set_property PACKAGE_PIN W13 [get_ports {i_switches[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {i_switches[*]}]

## ------------------------------------------------------------------
## Botones: cada bit del bus i_btn_load va a un botón distinto.
##   i_btn_load[3] = BTNU -> carga Dato A
##   i_btn_load[2] = BTNL -> carga Dato B
##   i_btn_load[1] = BTNR -> carga Op
##   i_btn_load[0] = BTND -> carga en la ALU
## ------------------------------------------------------------------
set_property PACKAGE_PIN T18 [get_ports {i_btn_load[3]}]
set_property PACKAGE_PIN W19 [get_ports {i_btn_load[2]}]
set_property PACKAGE_PIN T17 [get_ports {i_btn_load[1]}]
set_property PACKAGE_PIN U17 [get_ports {i_btn_load[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {i_btn_load[*]}]

## ------------------------------------------------------------------
## LEDs: LD0-LD7 -> o_leds[7:0], LD8 -> o_carry
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
