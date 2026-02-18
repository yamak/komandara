set xpr [lindex $argv 0]
set rpt_dir [lindex $argv 1]

open_project $xpr
open_run impl_1

file mkdir $rpt_dir

report_timing_summary -max_paths 20 -report_unconstrained -warn_on_violation -file "$rpt_dir/timing_summary.rpt"
report_clock_interaction -file "$rpt_dir/clock_interaction.rpt"
report_cdc -details -file "$rpt_dir/cdc.rpt"
report_drc -file "$rpt_dir/drc.rpt"
report_methodology -file "$rpt_dir/methodology.rpt"

exit
