extends GutTest

var _snapshot: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)


func test_empty_coverage_produces_valid_xml():
	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()
	assert_string_contains(xml, '<?xml version="1.0" ?>')
	assert_string_contains(xml, '<coverage ')
	assert_string_contains(xml, '</coverage>')


func test_basic_cobertura_output():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/player.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/player.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 1 hit
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, 'filename="src/player.gd"')
	assert_string_contains(xml, '<line number="1" hits="1"')
	assert_string_contains(xml, '<line number="2" hits="0"')
	assert_string_contains(xml, 'line-rate=')
	assert_string_contains(xml, '<packages>')
	assert_string_contains(xml, '</packages>')


func test_function_records_in_cobertura():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://test.gd"

	var func_info = GUTCheckFunctionInfo.new("my_func", 5)
	func_info.end_line = 10
	script_map.functions.append(func_info)

	script_map.lines[5] = GUTCheckLineInfo.new(
		5, GUTCheckScriptMap.LineType.FUNC_DEF, "my_func")
	script_map.lines[6] = GUTCheckLineInfo.new(
		6, GUTCheckScriptMap.LineType.EXECUTABLE, "my_func")
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://test.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, '<method name="my_func"')
	assert_string_contains(xml, '<methods>')


func test_branch_coverage_in_cobertura():
	var instrumenter = GUTCheckInstrumenter.new()
	var source = "func foo(x):\n\tif x > 5:\n\t\treturn true\n\telse:\n\t\treturn false"
	var result = instrumenter.instrument(source, 0, "res://branch_test.gd")

	GUTCheckCollector.register_script(0, "res://branch_test.gd", result.probe_count, result.script_map)
	GUTCheckCollector.enable()
	# Fire all probes
	for pid in range(result.probe_count):
		GUTCheckCollector.hit(0, pid)
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, 'branch="true"')
	assert_string_contains(xml, 'condition-coverage=')
	assert_string_contains(xml, 'branch-rate=')


func test_xml_escaping():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = 'res://src/my&script.gd'
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, 'res://src/my&script.gd', script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, "my&amp;script")
	assert_false(xml.contains('my&script'), "Ampersand should be escaped")


func test_export_cobertura_writes_file_to_disk():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/disk_test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/disk_test.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var tmp_path := "user://test_cobertura_output.xml"
	var result := exporter.export_cobertura(tmp_path)
	assert_eq(result, OK, "export_cobertura should return OK")

	var file := FileAccess.open(tmp_path, FileAccess.READ)
	assert_not_null(file, "Output file should exist")
	if file:
		var content := file.get_as_text()
		file.close()
		assert_string_contains(content, '<?xml version="1.0" ?>')
		assert_string_contains(content, '</coverage>')
		DirAccess.remove_absolute(tmp_path)


func test_export_cobertura_with_bad_path_returns_error():
	var exporter = GUTCheckCoberturaExporter.new()
	var result := exporter.export_cobertura("/nonexistent/directory/file.xml")
	assert_ne(result, OK, "Should return error for invalid path")


func test_source_root_emits_sources_element():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/source_root_test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/source_root_test.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura("/my/project/root")

	assert_string_contains(xml, '<sources>')
	assert_string_contains(xml, '<source>/my/project/root</source>')
	assert_string_contains(xml, '</sources>')


func test_no_source_root_omits_sources_element():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/no_root_test.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/no_root_test.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_false(xml.contains('<sources>'), "No sources element without source_root")


func test_script_with_no_functions_emits_empty_methods():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/no_funcs.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/no_funcs.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, '<methods>')
	assert_string_contains(xml, '</methods>')
	# No <method> tags between them
	assert_false(xml.contains('<method name='), "No method elements for scripts without functions")


func test_script_with_no_branches_reports_zero_branch_rate():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/no_branches.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/no_branches.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, 'branch-rate="0"')
	assert_string_contains(xml, 'branches-valid="0"')
	assert_string_contains(xml, 'branches-covered="0"')


func test_function_with_inner_class_prefix():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/inner_cls.gd"

	var func_info = GUTCheckFunctionInfo.new("my_method", 10, "InnerClass")
	func_info.end_line = 15
	script_map.functions.append(func_info)

	script_map.lines[10] = GUTCheckLineInfo.new(
		10, GUTCheckScriptMap.LineType.FUNC_DEF, "my_method", "InnerClass")
	script_map.lines[11] = GUTCheckLineInfo.new(
		11, GUTCheckScriptMap.LineType.EXECUTABLE, "my_method", "InnerClass")
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/inner_cls.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, '<method name="InnerClass.my_method"')


func test_branch_condition_elements_emitted():
	# Build a script with an if/else via manual construction
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/branch_cond.gd"

	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.BRANCH_IF)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[3] = GUTCheckLineInfo.new(
		3, GUTCheckScriptMap.LineType.BRANCH_ELSE)
	script_map.lines[4] = GUTCheckLineInfo.new(
		4, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()
	# Probe layout: 0=line1 exec, 1=line2 exec, 2=line4 exec,
	#               3=if-true, 4=if-false, 5=else

	GUTCheckCollector.register_script(0, "res://src/branch_cond.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 1 exec (if line)
	GUTCheckCollector.hit(0, 1)  # line 2 exec (if body)
	GUTCheckCollector.hit(0, 2)  # line 4 exec (else body)
	GUTCheckCollector.hit(0, 3)  # if-true branch probe
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, 'branch="true"')
	assert_string_contains(xml, '<conditions>')
	assert_string_contains(xml, '</conditions>')
	assert_string_contains(xml, '<condition number=')
	assert_string_contains(xml, 'type="jump"')
	assert_string_contains(xml, 'condition-coverage=')


func test_multiple_packages_sorted_by_directory():
	var map_a = GUTCheckScriptMap.new()
	map_a.path = "res://z_dir/z_script.gd"
	map_a.lines[1] = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.EXECUTABLE)
	map_a.assign_probes()
	map_a.assign_branch_probes()

	var map_b = GUTCheckScriptMap.new()
	map_b.path = "res://a_dir/a_script.gd"
	map_b.lines[1] = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.EXECUTABLE)
	map_b.assign_probes()
	map_b.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://z_dir/z_script.gd", map_a.probe_count, map_a)
	GUTCheckCollector.register_script(1, "res://a_dir/a_script.gd", map_b.probe_count, map_b)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	var a_pos := xml.find('name="a_dir"')
	var z_pos := xml.find('name="z_dir"')
	assert_gt(a_pos, -1, "a_dir package should be present")
	assert_gt(z_pos, -1, "z_dir package should be present")
	assert_lt(a_pos, z_pos, "a_dir should come before z_dir (sorted)")


func test_root_level_script_uses_dot_package_name():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://root_script.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://root_script.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, 'name="."')


func test_partial_branch_coverage_percentage():
	# Build if with true/false branches, only hit true
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/partial_branch.gd"

	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.BRANCH_IF)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()
	# Probe layout: 0=line1 exec, 1=line2 exec, 2=if-true branch, 3=if-false branch

	GUTCheckCollector.register_script(0, "res://src/partial_branch.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 1 exec (if line)
	GUTCheckCollector.hit(0, 1)  # line 2 exec (body)
	GUTCheckCollector.hit(0, 2)  # if-true branch probe
	# Don't hit probe 3 (if-false branch)
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	# Should have 50% (1/2) condition-coverage
	assert_string_contains(xml, 'condition-coverage="50% (1/2)"')


func test_branch_line_uses_branch_hits_for_line_coverage():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/branch_line_hits.gd"

	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.BRANCH_IF)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/branch_line_hits.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 1)  # body line
	GUTCheckCollector.hit(0, 2)  # if-true branch
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, '<line number="1" hits="1" branch="true"')


func test_function_with_open_ended_end_line():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/open_func.gd"

	var func_info = GUTCheckFunctionInfo.new("open_func", 5)
	# end_line stays -1 (open-ended)
	script_map.functions.append(func_info)

	script_map.lines[5] = GUTCheckLineInfo.new(
		5, GUTCheckScriptMap.LineType.FUNC_DEF, "open_func")
	script_map.lines[6] = GUTCheckLineInfo.new(
		6, GUTCheckScriptMap.LineType.EXECUTABLE, "open_func")
	script_map.lines[7] = GUTCheckLineInfo.new(
		7, GUTCheckScriptMap.LineType.EXECUTABLE, "open_func")
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/open_func.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)  # line 6
	GUTCheckCollector.hit(0, 1)  # line 7
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, '<method name="open_func"')
	# Both lines should appear inside the method's lines
	assert_string_contains(xml, '<line number="6"')
	assert_string_contains(xml, '<line number="7"')


func test_export_cobertura_with_source_root_writes_to_disk():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/disk_src.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/disk_src.gd", script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var tmp_path := "user://test_cobertura_src_root.xml"
	var result := exporter.export_cobertura(tmp_path, "/my/root")
	assert_eq(result, OK)

	var file := FileAccess.open(tmp_path, FileAccess.READ)
	assert_not_null(file, "Output file should exist")
	if file:
		var content := file.get_as_text()
		file.close()
		assert_string_contains(content, '<source>/my/root</source>')
		DirAccess.remove_absolute(tmp_path)


func test_else_branch_derives_hits_from_body():
	# Test the derive_body_hits path in _get_branch_data_for_line
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/else_derive.gd"

	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.BRANCH_IF)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[3] = GUTCheckLineInfo.new(
		3, GUTCheckScriptMap.LineType.BRANCH_ELSE)
	script_map.lines[4] = GUTCheckLineInfo.new(
		4, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()
	# Probe layout: 0=line1 exec, 1=line2 exec, 2=line4 exec,
	#               3=if-true, 4=if-false, 5=else

	GUTCheckCollector.register_script(0, "res://src/else_derive.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	# Hit exec lines but NOT the else branch probe (5) directly
	GUTCheckCollector.hit(0, 0)  # line 1 exec (if line)
	GUTCheckCollector.hit(0, 1)  # line 2 exec (if body)
	GUTCheckCollector.hit(0, 2)  # line 4 exec (else body -- used for derivation)
	# Don't hit probe 5 (else branch probe) -- let it derive from body
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	# The else branch should be detected as covered via body derivation
	# This tests _get_branch_data_for_line's BRANCH_ELSE derive path
	assert_string_contains(xml, 'branch="true"')
	assert_string_contains(xml, 'condition-coverage=')


func test_all_lines_covered_produces_rate_one():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/full_cov.gd"
	script_map.lines[1] = GUTCheckLineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[2] = GUTCheckLineInfo.new(
		2, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, "res://src/full_cov.gd", script_map.probe_count, script_map)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(0, 0)
	GUTCheckCollector.hit(0, 1)
	GUTCheckCollector.disable()

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, 'line-rate="1.0000"')
