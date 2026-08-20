# The ring oscillator feedback loops are intentional - tell Vivado not to
# optimize them away or treat them as a design error.
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w1*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w2*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w3*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w4*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w5*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w6*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w7*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *wop*}]

# PYNQ-Z2 system clock is 125 MHz = 8 ns period.
create_clock -period 8.000 -name sys_clk_pin -waveform {0.000 4.000} [get_ports clk]

# ============================================================
# PYNQ-Z2 I/O constraints
# ============================================================

# 125 MHz system clock
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} \
    [get_ports {clk}]
# ============================================================
# Control signals
# ============================================================

# SW0 -> reset_n
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} \
    [get_ports {reset_n}]

# BTN0 -> start
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} \
    [get_ports {start}]

# LED0 -> done
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} \
    [get_ports {done}]


# ============================================================
# challenge[7:0] -> PMOD A
# ============================================================

set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[0]}]

set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[1]}]

set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[2]}]

set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[3]}]

set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[4]}]

set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[5]}]

set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[6]}]

set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} \
    [get_ports {challenge[7]}]


# ============================================================
# response[7:0] -> PMOD B
# ============================================================

set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} \
    [get_ports {response[0]}]

set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} \
    [get_ports {response[1]}]

set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} \
    [get_ports {response[2]}]

set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} \
    [get_ports {response[3]}]

set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} \
    [get_ports {response[4]}]

set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} \
    [get_ports {response[5]}]

set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} \
    [get_ports {response[6]}]

set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} \
    [get_ports {response[7]}]