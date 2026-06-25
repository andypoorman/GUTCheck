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
	GUTCheckProbeAllocator.assign_all(script_map)

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
	GUTCheckProbeAllocator.assign_all(script_map)

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 6
	GUTCheckCollector.hit(0, 1)  # line 7
	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	assert_string_contains(lcov, "FN:5,my_func")
	assert_string_contains(lcov, "FNDA:1,my_func")  # hit count = first exec line (line 6)
	assert_string_contains(lcov, "FNF:1")
	assert_string_contains(lcov, "FNH:1")


func test_branch_records_emitted_for_if():
	# Run only the true path by actually executing the instrumented script, so the
	# false branch stays uncovered and BRH < BRF. Firing every probe (as this test
	# used to) makes BRH == BRF and can never catch a missed branch.
	var instrumenter = GUTCheckInstrumenter.new()
	var source = "func foo(x):\n\tif x > 5:\n\t\treturn true\n\treturn false"
	var result = instrumenter.instrument(source, 0, "res://branch_test.gd")
	GUTCheckCollector.register_script(0, "res://branch_test.gd", result.probe_count, result.script_map)
	assert_gt(result.script_map.branches.size(), 0, "Should have branch info")

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented branch source should compile")
	if err != OK:
		return

	GUTCheckCollector.enable()
	script.new().foo(10)  # x > 5 -> only the true branch runs
	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	assert_string_contains(lcov, "BRF:2", "An if records a true and a false branch")
	assert_string_contains(lcov, "BRH:1", "Only the true branch was taken")


func test_no_branch_records_when_no_branches():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	GUTCheckProbeAllocator.assign_all(script_map)

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)
	GUTCheckCollector.disable()

	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()

	# No branches means no BRF/BRH records
	assert_false(lcov.contains("BRDA:"), "Should not have BRDA without branches")
	assert_false(lcov.contains("BRF:"), "Should not have BRF without branches")


func test_export_lcov_writes_file_to_disk():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/lcov_disk_test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	GUTCheckProbeAllocator.assign_all(script_map)

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
