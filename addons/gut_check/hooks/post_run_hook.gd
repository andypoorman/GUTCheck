extends GutHookScript
## GUTCheck post-run hook. Exports coverage data and prints summary.
##
## Configure in .gutconfig.json:
##   "post_run_script": "res://addons/gut_check/hooks/post_run_hook.gd"


func run():
	var gut_check := GUTCheck.new()
	gut_check.load_config()

	# Disable collection, then print summary before exporting — print_summary
	# reads the previous LCOV file for delta comparison, so it must run
	# before we overwrite it.
	GUTCheckCollector.disable()
	gut_check.print_summary(gut.logger)

	var err := gut_check.export_coverage()
	if err != OK:
		gut.logger.error("GUTCheck: Failed to export coverage (error %d)" % err)

	var cobertura_err := gut_check.export_cobertura()
	if cobertura_err != OK:
		gut.logger.error("GUTCheck: Failed to export Cobertura XML (error %d)" % cobertura_err)

	if not gut_check.is_coverage_passing():
		gut.logger.warn("GUTCheck: Coverage below target")
		set_exit_code(1)
