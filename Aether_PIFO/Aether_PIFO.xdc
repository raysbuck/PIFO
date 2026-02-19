# Aether_PIFO Vivado Constraints
# Target Frequency: 250MHz (Period = 4.0ns)
# This design is optimized for 200MHz+ stable operation.

create_clock -period 4.000 -name clk [get_ports i_clk]

# Optional: Add jitter and uncertainty for more robust timing
set_clock_uncertainty 0.100 [get_clocks clk]

# Input/Output Delays (Assuming 2ns for generic interface)
# Exclude the clock port from all_inputs to avoid warnings on the clock itself
set_input_delay -clock clk 2.000 [remove_from_collection [all_inputs] [get_ports i_clk]]
set_output_delay -clock clk 2.000 [all_outputs]

# Explicitly ensure i_arst_n is covered if all_inputs has issues in some versions
set_input_delay -clock clk 2.000 [get_ports i_arst_n]

# Optimization Properties for Vivado 2023.2
# Enable register retiming to balance logic levels across node boundaries
set_property -name {STEPS.SYNTH_DESIGN.ARGS.RETIMING} -value {true} -objects [get_runs synth_1]

# Post-route physical optimization to fix long wires in large trees
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
