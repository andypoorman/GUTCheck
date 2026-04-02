extends GutHookScript
## GUTCheck pre-run hook. Instruments source scripts before tests execute.
##
## Configure in .gutconfig.json:
##   "pre_run_script": "res://addons/gut_check/hooks/pre_run_hook.gd"


func run():
	var gut_check := GUTCheck.new()
	gut_check.load_config()
	gut_check.instrument_scripts()

	var instrumented := GUTCheckCollector.get_script_paths().size()
	var skipped := gut_check.get_skipped_scripts()
	if skipped.size() > 0:
		gut.logger.info("GUTCheck: Instrumented %d scripts, skipped %d" % [instrumented, skipped.size()])
		for path in skipped:
			gut.logger.warn("GUTCheck:   skipped: %s" % path)
	else:
		gut.logger.info("GUTCheck: Instrumented %d scripts" % instrumented)
