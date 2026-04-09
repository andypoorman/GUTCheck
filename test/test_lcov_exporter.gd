extends GutTest

var _snapshot: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)


func test_empty_coverage_produces_empty_lcov():
	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()
	assert_eq(lcov, "", "No registered scripts should produce empty LCOV")


func test_basic_lcov_output():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)

	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 1 hit once
	GUTCheckCollector.hit(0, 0)  # line 1 hit twice
	# line 2 not hit
	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	assert_string_contains(lcov, "TN:")
	assert_string_contains(lcov, "SF:")
	assert_string_contains(lcov, "DA:1,2")   # line 1, hit 2 times
	assert_string_contains(lcov, "DA:2,0")   # line 2, hit 0 times
	assert_string_contains(lcov, "LF:2")     # 2 lines found
	assert_string_contains(lcov, "LH:1")     # 1 line hit
	assert_string_contains(lcov, "end_of_record")


func test_function_records():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://test.gd"

	var func_info = GUTCheckFunctionInfo.new("my_func", 5)
	func_info.end_line = 10
	script_map.functions.append(func_info)

	# FUNC_DEF is not executable, so only line 6 and 7 get probes
	script_map.lines[5] = GUTCheckLineInfo.new(
		5, GUTCheckScriptMap.LineType.FUNC_DEF, "my_func")
	script_map.lines[6] = GUTCheckLineInfo.new(
		6, GUTCheckScriptMap.LineType.EXECUTABLE, "my_func")
	script_map.lines[7] = GUTCheckLineInfo.new(
		7, GUTCheckScriptMap.LineType.EXECUTABLE, "my_func")
	script_map.assign_probes()

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 6
	GUTCheckCollector.hit(0, 1)  # line 7
	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	assert_string_contains(lcov, "FN:5,my_func")
	assert_string_contains(lcov, "FNDA:")
	assert_string_contains(lcov, "FNF:1")
	assert_string_contains(lcov, "FNH:1")


func test_branch_records_emitted_for_if():
	# Instrument a script with an if/else to verify BRDA records
	var instrumenter = GUTCheckInstrumenter.new()
	var source = "func foo(x):\n\tif x > 5:\n\t\treturn true\n\telse:\n\t\treturn false"
	var result = instrumenter.instrument(source, 0, "res://branch_test.gd")

	GUTCheckCollector.register_script(0, "res://branch_test.gd", result.probe_count, result.script_map)
	GUTCheckCollector.enable()

	# Simulate: condition true twice, false once
	# The br2() is used, so true_pid and false_pid get separate hits
	# We need to find the branch probe IDs
	var branches = result.script_map.branches
	assert_gt(branches.size(), 0, "Should have branch info")

	# Fire some line probes to simulate execution
	for pid in range(result.probe_count):
		GUTCheckCollector.hit(0, pid)

	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	assert_string_contains(lcov, "BRDA:")
	assert_string_contains(lcov, "BRF:")
	assert_string_contains(lcov, "BRH:")


func test_no_branch_records_when_no_branches():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)
	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	# No branches means no BRF/BRH records
	assert_false(lcov.contains("BRDA:"), "Should not have BRDA without branches")
	assert_false(lcov.contains("BRF:"), "Should not have BRF without branches")


func test_coverage_collector_summary():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[3] = GUTCheckLineInfo.new(
		3, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)
	GUTCheckCollector.hit(0, 1)
	GUTCheckCollector.disable()

	var summary = GUTCheckCollector.get_coverage_summary()
	assert_eq(summary.total_lines, 3)
	assert_eq(summary.hit_lines, 2)
	assert_almost_eq(summary.percentage, 66.666, 0.01)


func test_export_lcov_writes_file_to_disk():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/lcov_disk_test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/lcov_disk_test.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckLcovExporter.new()
	var tmp_path := "user://test_lcov_output.info"
	var result := exporter.export_lcov(tmp_path)
	assert_eq(result, OK, "export_lcov should return OK")

	var file := FileAccess.open(tmp_path, FileAccess.READ)
	assert_not_null(file, "Output file should exist")
	if file:
		var content := file.get_as_text()
		file.close()
		assert_string_contains(content, "TN:")
		assert_string_contains(content, "end_of_record")
		DirAccess.remove_absolute(tmp_path)


func test_export_lcov_with_bad_path_returns_error():
	var exporter = GUTCheckLcovExporter.new()
	var result := exporter.export_lcov("/nonexistent/directory/file.info")
	assert_ne(result, OK, "Should return error for invalid path")


func test_to_absolute_path_passthrough_for_non_res_path():
	var exporter = GUTCheckLcovExporter.new()
	assert_eq(exporter._to_absolute_path("/tmp/example.gd"), "/tmp/example.gd")
