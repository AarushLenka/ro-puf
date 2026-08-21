#==============================================================================
# ro-puf : sample constraints  (PYNQ-Z2, xc7z020clg400-1)
#
# HOW TO USE
#   Add as a constraints file in constrs_1. Leave "used in synthesis" AND
#   "used in implementation" both ticked.
#
# READ THIS FIRST
#   Nearly every section below is COMMENTED OUT ON PURPOSE. If you wire the PUF
#   to the PS clock and reset inside the block design (recommended -- see
#   Section 1), this project needs *no active constraints at all*, and the file
#   stays as documentation.
#
#   The previous project's XDC actively caused two problems:
#     1. create_clock on a PS-derived clock produced a duplicate 125 MHz clock
#        on hardware that actually runs at 50 MHz.
#     2. All 8 ALLOW_COMBINATORIAL_LOOPS lines matched zero nets at synthesis
#        ("WARNING: [Vivado 12-1023] No nets matched"), because puf_top was a
#        black box at the time. They were silently deferred to implementation.
#   Both are addressed below by NOT doing them here.
#==============================================================================


#------------------------------------------------------------------------------
# 1. CLOCK AND RESET  -- prefer the block design over this file
#------------------------------------------------------------------------------
# Recommended: in the BD, connect
#     puf_top/clk      <- processing_system7_0/FCLK_CLK0
#     puf_top/reset_n  <- rst_ps7_0_50M/peripheral_aresetn
#
# Then puf_top has no external clk/reset ports, and:
#   - DRC UCIO-1 / NSTD-1 cannot occur (the ports do not exist)
#   - FCLK_CLK0 is constrained automatically by the PS7 IP
#   - the PUF shares a clock domain with the AXI GPIO that drives it
#
# Do NOT add create_clock for FCLK_CLK0. The PS7 IP already defines it. A second
# create_clock on the same source is what produced the 50 vs 125 MHz split.
#
# Verify after synthesis -- expect exactly ONE clock, clk_fpga_0 at 20.000 ns:
#     report_clocks
#
# ONLY if you deliberately drive the PUF from an external pin instead, uncomment
# this block. The PYNQ-Z2 125 MHz oscillator is on H16 / LVCMOS33.
#
# create_clock -period 8.000 -name sys_clk -waveform {0.000 4.000} [get_ports clk]
# set_property PACKAGE_PIN H16  [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]
#
# set_property PACKAGE_PIN D19  [get_ports reset_n]   ;# BTN0
# set_property IOSTANDARD LVCMOS33 [get_ports reset_n]
#
# Confirm H16/D19 against the PYNQ-Z2 master XDC for your board revision before
# programming. A wrong PACKAGE_PIN can drive a pin against an external source.


#------------------------------------------------------------------------------
# 2. RING OSCILLATOR COMBINATIONAL LOOPS  -- handled in RTL, not here
#------------------------------------------------------------------------------
# The inverter ring in ring_osc.v is an intentional combinational loop. Vivado
# must be told to allow it, but an XDC is the wrong place: during top-level
# synthesis puf_top is an unresolved black box, so its internal nets w1..wop do
# not exist yet and every get_nets returns empty.
#
# Put the attribute in the RTL instead, where it travels with the module
# regardless of synthesis order. In verilog/ring_osc.v:
#
#     (* DONT_TOUCH = "TRUE", ALLOW_COMBINATORIAL_LOOPS = "TRUE" *)
#     wire w1, w2, w3, w4, w5, w6, w7, wop;
#
# If you want a post-synthesis safety net as well, uncomment below. Note this
# runs only in implementation, after synthesis has already made its decisions,
# so it is a backstop and not a substitute for the RTL attribute.
#
# Anchored to the exact net names (w1..w7, wop) rather than a bare wildcard:
# the old file used {NAME =~ *w1*}, which also matches w10-w19 and any net whose
# name merely contains "w1".
#
# set_property ALLOW_COMBINATORIAL_LOOPS TRUE \
#     [get_nets -hierarchical -filter {NAME =~ "*/ro/w[1-7]" || NAME =~ "*/ro/wop"}]


#------------------------------------------------------------------------------
# 3. OSCILLATOR RETENTION  -- RTL attributes, verified by a post-synth check
#------------------------------------------------------------------------------
# The PUF depends entirely on 256 physically distinct oscillators. If synthesis
# merges them (they are structurally identical), the design still builds and
# still returns responses -- they are just no longer chip-unique. There is no
# error message for this failure mode.
#
# KEEP is not sufficient: it preserves nets from deletion but does not stop
# instance merging. ring_osc.v now carries module-level DONT_TOUCH plus an
# INSTANCE_ID tied into a net, which is the part that actually prevents it.
#
# MANDATORY CHECK after the first synthesis run -- must return 256:
#     open_run synth_1
#     llength [get_cells -hier -filter {REF_NAME =~ ring_osc*}]
#
# And confirm puf_top holds real logic (expect ~2000+ LUTs, not ~50):
#     report_utilization -hierarchical -file util_hier.rpt
#
# For reference, the earlier build implemented the ENTIRE design in 1452 LUTs
# while puf_top alone synthesized out-of-context to 2518 -- a strong sign the
# oscillators were being stripped during integration.


#------------------------------------------------------------------------------
# 4. TIMING EXCEPTIONS FOR THE OSCILLATOR DOMAINS
#------------------------------------------------------------------------------
# The oscillator outputs (via clock_div_2) clock the measurement counters. They
# are free-running, unconstrained, and deliberately unpredictable in frequency --
# that variation IS the PUF. Vivado will report them as unconstrained clocks.
#
# The counters are resynchronised into the clk domain by a 2-flop synchroniser
# in puf_cell.v before being compared, so the crossing is already safe in RTL.
# These exceptions only quiet the analyser; they are not load-bearing.
#
# Uncomment if unconstrained-clock warnings are noisy enough to hide real ones.
# Keep them narrow: a blanket set_false_path would also mask genuine violations.
#
# set_property CLOCK_DEDICATED_ROUTE FALSE \
#     [get_nets -hierarchical -filter {NAME =~ "*/div/q"}]
#
# set_false_path -from [get_clocks -include_generated_clocks -of_objects \
#     [get_nets -hierarchical -filter {NAME =~ "*/div/q"}]] \
#     -to [get_clocks clk_fpga_0]


#------------------------------------------------------------------------------
# 5. OPTIONAL: PHYSICAL ISOLATION OF THE PUF ARRAY
#------------------------------------------------------------------------------
# Not required to build. Relevant to PUF quality: pinning the array to a fixed
# region makes results reproducible across builds, since re-placement changes
# routing delays and therefore changes responses on the same physical chip.
#
# Uncomment and size the range to your utilisation if you need build-to-build
# stability, e.g. when comparing the raw array against puf_array_xor.
#
# create_pblock pblock_puf
# add_cells_to_pblock [get_pblocks pblock_puf] \
#     [get_cells -hier -filter {NAME =~ "*puf_top*array*"}]
# resize_pblock [get_pblocks pblock_puf] -add {SLICE_X0Y0:SLICE_X47Y49}


#------------------------------------------------------------------------------
# 6. DO NOT ADD THESE  (recorded so the mistakes are not repeated)
#------------------------------------------------------------------------------
# set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
# set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
#     Downgrading these forces a bitstream out of a design with unplaced I/O.
#     It hides the problem rather than fixing it, and Xilinx warns it can damage
#     the device or attached components. Fix the connection (Section 1) instead.
#
# create_clock ... [get_ports clk]   when clk comes from FCLK_CLK0
#     Duplicate clock definition. This is the 50-vs-125 MHz bug.
#
# set_false_path across the whole design to clear CDC warnings
#     The real crossings are handled by synchronisers in puf_driver.v and
#     puf_cell.v. A blanket exception would also hide the next real one.
#==============================================================================
