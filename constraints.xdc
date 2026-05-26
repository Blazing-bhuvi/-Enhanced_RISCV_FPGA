################ CLOCK ################
set_property PACKAGE_PIN E3 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]
create_clock -period 10.000 [get_ports clk_100mhz]

################ SWITCHES ################
# SW0 (Manual/Auto Mode)
set_property PACKAGE_PIN J15 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]
# SW1 (Unused currently, but mapped safely)
set_property PACKAGE_PIN L16 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]
## Switches
# ... sw[0] and sw[1] are already there ...
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]; # Switch 2

################ BUTTONS ################
# Center Button (Reset)
set_property PACKAGE_PIN N17 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]
# Up Button (Manual Clock Step)
set_property PACKAGE_PIN M18 [get_ports btnU]
set_property IOSTANDARD LVCMOS33 [get_ports btnU]

################ LEDS #################
# LEDs LD0-LD15
set_property PACKAGE_PIN H17 [get_ports {led[0]}]
set_property PACKAGE_PIN K15 [get_ports {led[1]}]
set_property PACKAGE_PIN J13 [get_ports {led[2]}]
set_property PACKAGE_PIN N14 [get_ports {led[3]}]
set_property PACKAGE_PIN R18 [get_ports {led[4]}]
set_property PACKAGE_PIN V17 [get_ports {led[5]}]
set_property PACKAGE_PIN U17 [get_ports {led[6]}]
set_property PACKAGE_PIN U16 [get_ports {led[7]}]
set_property PACKAGE_PIN V16 [get_ports {led[8]}]
set_property PACKAGE_PIN T15 [get_ports {led[9]}]
set_property PACKAGE_PIN U14 [get_ports {led[10]}]
set_property PACKAGE_PIN T16 [get_ports {led[11]}]
set_property PACKAGE_PIN V15 [get_ports {led[12]}]
set_property PACKAGE_PIN V14 [get_ports {led[13]}]
set_property PACKAGE_PIN V12 [get_ports {led[14]}]
set_property PACKAGE_PIN V11 [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

################ 7-SEGMENT CATHODES ################
# Segments CA to CG
set_property PACKAGE_PIN T10 [get_ports {seg[0]}]
set_property PACKAGE_PIN R10 [get_ports {seg[1]}]
set_property PACKAGE_PIN K16 [get_ports {seg[2]}]
set_property PACKAGE_PIN K13 [get_ports {seg[3]}]
set_property PACKAGE_PIN P15 [get_ports {seg[4]}]
set_property PACKAGE_PIN T11 [get_ports {seg[5]}]
set_property PACKAGE_PIN L18 [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

################ 7-SEGMENT ANODES ################
# Anodes AN0 to AN7
set_property PACKAGE_PIN J17 [get_ports {an[0]}]
set_property PACKAGE_PIN J18 [get_ports {an[1]}]
set_property PACKAGE_PIN T9  [get_ports {an[2]}]
set_property PACKAGE_PIN J14 [get_ports {an[3]}]
set_property PACKAGE_PIN P14 [get_ports {an[4]}]
set_property PACKAGE_PIN T14 [get_ports {an[5]}]
set_property PACKAGE_PIN K2  [get_ports {an[6]}]
set_property PACKAGE_PIN U13 [get_ports {an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]


############### RGB LIGHTS ##############
set_property -dict { PACKAGE_PIN R12  IOSTANDARD LVCMOS33 } [get_ports { led16_b }]; 
set_property -dict { PACKAGE_PIN M16  IOSTANDARD LVCMOS33 } [get_ports { led16_g }]; 
set_property -dict { PACKAGE_PIN N15  IOSTANDARD LVCMOS33 } [get_ports { led16_r }];

############ UART BRIDGE ################
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }]; #IO_L7P_T1_AD6P_35 Sch=uart_txd_in
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }]; #IO_L11N_T1_SRCC_35 Sch=uart_rxd_out