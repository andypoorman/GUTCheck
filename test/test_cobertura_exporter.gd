extends GutTest


func before_each():
	GUTCheckCollector.clear()


func after_each():
	GUTCheckCollector.clear()


func test_empty_coverage_produces_valid_xml():
	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()
	assert_string_contains(xml, '<?xml version="1.0" ?>')
	assert_string_contains(xml, '<coverage ')
	assert_string_contains(xml, '</coverage>')


func test_basic_cobertura_output():
	var script_map = GUTCheckScriptMap.new()
	script_map.path = "res://src/player.gd"
	script_map.lines[1] = GUTCheckScriptMap.LineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.lines[2] = GUTCheckScriptMap.LineInfo.new(
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

	var func_info = GUTCheckScriptMap.FunctionInfo.new("my_func", 5)
	func_info.end_line = 10
	script_map.functions.append(func_info)

	script_map.lines[5] = GUTCheckScriptMap.LineInfo.new(
		5, GUTCheckScriptMap.LineType.FUNC_DEF, "my_func")
	script_map.lines[6] = GUTCheckScriptMap.LineInfo.new(
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
	script_map.lines[1] = GUTCheckScriptMap.LineInfo.new(
		1, GUTCheckScriptMap.LineType.EXECUTABLE)
	script_map.assign_probes()
	script_map.assign_branch_probes()

	GUTCheckCollector.register_script(0, 'res://src/my&script.gd', script_map.probe_count, script_map)

	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()

	assert_string_contains(xml, "my&amp;script")
	assert_false(xml.contains('my&script'), "Ampersand should be escaped")
