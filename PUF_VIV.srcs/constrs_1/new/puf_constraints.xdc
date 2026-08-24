# puf_constraints.xdc
# set ro_loop_nets [get_nets -hierarchical -quiet \
   #   -filter {NAME =~ "*/ro/w1"}]

 # if {[llength $ro_loop_nets] > 0} {
 #     set_property ALLOW_COMBINATORIAL_LOOPS TRUE $ro_loop_nets
 # }
  
set_property ALLOW_COMBINATORIAL_LOOPS TRUE \
    [get_nets -hierarchical -quiet -filter {NAME =~ "*/ro/w1"}]
 
 
