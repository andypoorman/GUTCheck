extends GutTest

var _tokenizer: GUTCheckTokenizer
var _classifier: GUTCheckLineClassifier


func before_each():
	_tokenizer = GUTCheckTokenizer.new()
	_classifier = GUTCheckLineClassifier.new()


func _classify(source: String) -> GUTCheckScriptMap:
	var tokens = _tokenizer.tokenize(source)
	return _classifier.classify(tokens, "test.gd")


# ---------------------------------------------------------------------------
# Basic classification
# ---------------------------------------------------------------------------

func test_blank_line():
	var map = _classify("")
	assert_true(map.lines.has(1))
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_comment_line():
	var map = _classify("# a comment")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_var_declaration():
	var map = _classify("var x = 5")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_const_declaration():
	var map = _classify("const MAX = 100")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_const_with_preload():
	var map = _classify('const Foo = preload("res://foo.gd")')
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_class_name_declaration():
	var map = _classify("class_name Foo")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_extends_declaration():
	var map = _classify('extends "res://base.gd"')
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_signal_declaration():
	var map = _classify("signal health_changed(amount)")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_enum_declaration():
	var map = _classify("enum State { IDLE, RUNNING }")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_pass_is_executable():
	var map = _classify("pass")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_return_is_executable():
	var map = _classify("return 42")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_function_call():
	var map = _classify("print('hello')")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_assignment():
	var map = _classify("x = 5")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


# ---------------------------------------------------------------------------
# Branch classification
# ---------------------------------------------------------------------------

func test_if_branch():
	var map = _classify("if true:")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.BRANCH_IF)


func test_elif_branch():
	var source = "if true:\n\tpass\nelif false:"
	var map = _classify(source)
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.BRANCH_ELIF)


func test_else_branch():
	var source = "if true:\n\tpass\nelse:"
	var map = _classify(source)
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.BRANCH_ELSE)


func test_for_loop():
	var map = _classify("for i in range(10):")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.LOOP_FOR)


func test_while_loop():
	var map = _classify("while true:")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.LOOP_WHILE)


func test_match_statement():
	var map = _classify("match state:")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.BRANCH_MATCH)


# ---------------------------------------------------------------------------
# Function and class tracking
# ---------------------------------------------------------------------------

func test_func_def():
	var source = "func foo():\n\tpass"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.FUNC_DEF)
	assert_eq(map.functions.size(), 1)
	assert_eq(map.functions[0].name, "foo")
	assert_eq(map.functions[0].start_line, 1)


func test_class_def():
	var source = "class Inner:\n\tvar x = 1"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.CLASS_DEF)
	assert_eq(map.classes.size(), 1)
	assert_eq(map.classes[0].name, "Inner")


func test_static_func():
	var source = "static func bar():\n\tpass"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.FUNC_DEF)
	assert_eq(map.functions.size(), 1)
	assert_eq(map.functions[0].is_static, true)


func test_func_context_tracked():
	var source = "func foo():\n\tvar x = 1\n\treturn x"
	var map = _classify(source)
	assert_eq(map.lines[2].function_name, "foo")
	assert_eq(map.lines[3].function_name, "foo")


# ---------------------------------------------------------------------------
# Annotation handling
# ---------------------------------------------------------------------------

func test_annotation_only_line():
	var map = _classify("@export")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_annotation_with_var():
	var source = "@onready var x = $Node"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_export_annotation_alone():
	var source = "@export\nvar x = 5"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.EXECUTABLE)


# ---------------------------------------------------------------------------
# Multiline expressions
# ---------------------------------------------------------------------------

func test_multiline_array():
	var source = "var arr = [\n\t1,\n\t2,\n\t3,\n]"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)
	for line_num in [2, 3, 4, 5]:
		if map.lines.has(line_num):
			assert_eq(map.lines[line_num].type, GUTCheckScriptMap.LineType.CONTINUATION,
				"Line %d should be CONTINUATION" % line_num)


# ---------------------------------------------------------------------------
# Probe assignment
# ---------------------------------------------------------------------------

func test_probe_assignment():
	var source = "var x = 1\n# comment\nvar y = 2"
	var map = _classify(source)
	assert_gt(map.probe_count, 0, "Should assign at least one probe")
	assert_eq(map.probe_to_line.size(), map.probe_count)


func test_probes_only_on_executable_lines():
	var source = "class_name Foo\n\nvar x = 1\n# comment\nconst Y = 2"
	var map = _classify(source)
	for probe_id: int in map.probe_to_line:
		var line_num: int = map.probe_to_line[probe_id]
		assert_true(map.lines[line_num].is_executable(),
			"Probe %d on line %d should be on an executable line" % [probe_id, line_num])


# ---------------------------------------------------------------------------
# Sample script
# ---------------------------------------------------------------------------

func test_sample_script_classification():
	var file = FileAccess.open("res://test/resources/sample_script.gd", FileAccess.READ)
	if file == null:
		pending("Could not open sample_script.gd")
		return
	var source = file.get_as_text()
	file.close()

	var map = _classify(source)

	assert_gt(map.probe_count, 0, "Should have probes")
	assert_gt(map.functions.size(), 5, "Should find multiple functions")

	# extends Node -> NON_EXECUTABLE
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE, "extends should be non-executable")
	# class_name SampleScript -> NON_EXECUTABLE
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE, "class_name should be non-executable")


# ---------------------------------------------------------------------------
# Match pattern classification
# ---------------------------------------------------------------------------

func test_match_patterns_classified():
	var source = "func foo():\n\tmatch x:\n\t\t1:\n\t\t\tprint('one')\n\t\t2:\n\t\t\tprint('two')"
	var map = _classify(source)
	# Line 2: match x: -> BRANCH_MATCH
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.BRANCH_MATCH)
	# Line 3: 1: -> BRANCH_PATTERN
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN,
		"Match arm '1:' should be BRANCH_PATTERN")
	# Line 4: print('one') -> EXECUTABLE
	assert_eq(map.lines[4].type, GUTCheckScriptMap.LineType.EXECUTABLE)
	# Line 5: 2: -> BRANCH_PATTERN
	assert_eq(map.lines[5].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN,
		"Match arm '2:' should be BRANCH_PATTERN")


func test_match_wildcard_pattern():
	var source = "func foo():\n\tmatch x:\n\t\t_:\n\t\t\tpass"
	var map = _classify(source)
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN,
		"Wildcard '_:' should be BRANCH_PATTERN")


func test_match_pattern_not_assigned_probe():
	var source = "func foo():\n\tmatch x:\n\t\t1:\n\t\t\tprint('one')"
	var map = _classify(source)
	# BRANCH_PATTERN should NOT get a probe (compound statement, can't instrument)
	for probe_id: int in map.probe_to_line:
		var line_num: int = map.probe_to_line[probe_id]
		assert_ne(map.lines[line_num].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN,
			"Probe should not be on a BRANCH_PATTERN line")


# ---------------------------------------------------------------------------
# Property accessor (get/set) classification
# ---------------------------------------------------------------------------

func test_property_get_set():
	var source = "var _val: int = 0\nvar prop: int:\n\tget:\n\t\treturn _val\n\tset(value):\n\t\t_val = value"
	var map = _classify(source)
	# Line 3: get: -> PROPERTY_ACCESSOR
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR,
		"get: should be PROPERTY_ACCESSOR")
	# Line 4: return _val -> EXECUTABLE
	assert_eq(map.lines[4].type, GUTCheckScriptMap.LineType.EXECUTABLE)
	# Line 5: set(value): -> PROPERTY_ACCESSOR
	assert_eq(map.lines[5].type, GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR,
		"set(value): should be PROPERTY_ACCESSOR")
	# Line 6: _val = value -> EXECUTABLE
	assert_eq(map.lines[6].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_property_accessor_not_assigned_probe():
	var source = "var prop: int:\n\tget:\n\t\treturn 0\n\tset(v):\n\t\tpass"
	var map = _classify(source)
	for probe_id: int in map.probe_to_line:
		var line_num: int = map.probe_to_line[probe_id]
		assert_ne(map.lines[line_num].type, GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR,
			"Probe should not be on a PROPERTY_ACCESSOR line")


# ---------------------------------------------------------------------------
# Ternary-if classification
# ---------------------------------------------------------------------------

func test_simple_ternary_classified():
	var source = 'func foo():\n\tvar x = "yes" if true else "no"'
	var map = _classify(source)
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY,
		"Line with ternary-if should be EXECUTABLE_TERNARY")
	assert_eq(map.lines[2].ternary_count, 1,
		"Should have exactly 1 ternary expression")


func test_nested_ternary_classified():
	var source = 'func foo():\n\tvar z = "a" if x else "b" if y else "c"'
	var map = _classify(source)
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY,
		"Line with nested ternary should be EXECUTABLE_TERNARY")
	assert_eq(map.lines[2].ternary_count, 2,
		"Nested ternary should count as 2 ternary expressions")


func test_ternary_branch_probes_assigned():
	var source = 'func foo():\n\tvar x = "yes" if true else "no"'
	var map = _classify(source)
	var branches_on_line := map.get_branches_for_line(2)
	assert_eq(branches_on_line.size(), 2,
		"Ternary should have 2 branch probes (true + false)")
	var has_true := false
	var has_false := false
	for b in branches_on_line:
		if b.is_true_branch:
			has_true = true
		else:
			has_false = true
	assert_true(has_true, "Should have true branch probe")
	assert_true(has_false, "Should have false branch probe")


func test_nested_ternary_branch_probes():
	var source = 'func foo():\n\tvar z = "a" if x else "b" if y else "c"'
	var map = _classify(source)
	var branches_on_line := map.get_branches_for_line(2)
	assert_eq(branches_on_line.size(), 4,
		"Nested ternary should have 4 branch probes (2 per ternary)")


func test_statement_if_not_ternary():
	var source = "func foo():\n\tif true:"
	var map = _classify(source)
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.BRANCH_IF,
		"Statement-level if should still be BRANCH_IF, not EXECUTABLE_TERNARY")
