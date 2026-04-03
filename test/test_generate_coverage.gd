extends GutTest
## Generates a real coverage.lcov file for viewing with genhtml.


var _snapshot: Dictionary

func test_generate_coverage_report():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()

	var instrumenter = GUTCheckInstrumenter.new()

	var path = "res://test/resources/coverage_target.gd"
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	var source = file.get_as_text()
	file.close()

	var result = instrumenter.instrument(source, 0, path)
	GUTCheckCollector.register_script(0, path, result.probe_count, result.script_map)

	var dynamic_script = GDScript.new()
	dynamic_script.source_code = result.source
	dynamic_script.resource_path = "res://addons/gut_check/not_real/coverage_gen_0.gd"
	var err = dynamic_script.reload()
	assert_eq(err, OK, "Should compile")
	if err != OK:
		gut.p("COMPILE ERROR. First 30 lines:")
		var lines = result.source.split("\n")
		for i in range(mini(30, lines.size())):
			gut.p("  %3d: %s" % [i + 1, lines[i]])
		return

	GUTCheckCollector.enable()

	# Exercise the code — call some methods but not all
	var obj = dynamic_script.new()
	obj.take_damage(30)
	obj.take_damage(60)
	obj.take_damage(15)
	obj.heal(20)
	obj.get_health_percentage()
	obj.complex_logic(3, 2)
	obj.multiline_call()
	# NOTE: _on_death() is never called directly — it should show as uncovered

	GUTCheckCollector.disable()

	# Write LCOV
	var exporter = GUTCheckLcovExporter.new()
	var lcov_path = ProjectSettings.globalize_path("res://coverage.lcov")
	var write_err = exporter.export_lcov(lcov_path)
	assert_eq(write_err, OK, "Should write LCOV file")

	var summary = GUTCheckCollector.get_coverage_summary()
	gut.p("Coverage: %.1f%% (%d/%d lines)" % [
		summary.percentage, summary.hit_lines, summary.total_lines])
	gut.p("LCOV written to: %s" % lcov_path)

	GUTCheckCollector.restore_snapshot(_snapshot)
