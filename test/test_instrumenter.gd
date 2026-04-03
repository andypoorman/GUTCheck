extends GutTest

var _instrumenter: GUTCheckInstrumenter


func before_each():
	_instrumenter = GUTCheckInstrumenter.new()


# ---------------------------------------------------------------------------
# Basic instrumentation
# ---------------------------------------------------------------------------

func test_simple_executable_line():
	var source = "func foo():\n\tvar x = 5"
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "GUTCheckCollector.hit(0,")
	assert_string_contains(result.source, "var x = 5")


func test_non_executable_not_instrumented():
	var source = "class_name Foo"
	var result = _instrumenter.instrument(source, 0)
	assert_eq(result.source, source, "Non-executable lines should not be modified")


func test_comment_not_instrumented():
	var source = "# just a comment"
	var result = _instrumenter.instrument(source, 0)
	assert_eq(result.source, source)


func test_top_level_var_not_instrumented():
	var source = "var x = 5"
	var result = _instrumenter.instrument(source, 0)
	assert_eq(result.source, source, "Top-level var should not be instrumented")


func test_line_count_preserved():
	var source = "func foo():\n\tvar x = 1\n\tvar y = 2\n\t# comment\n\tvar z = 3"
	var result = _instrumenter.instrument(source, 0)
	var original_lines = source.split("\n").size()
	var result_lines = result.source.split("\n").size()
	assert_eq(result_lines, original_lines, "Line count must be preserved")


# ---------------------------------------------------------------------------
# Condition wrapping
# ---------------------------------------------------------------------------

func test_if_condition_wrapped():
	var source = "func foo():\n\tif x > 5:"
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "GUTCheckCollector.hit_br2(")
	assert_string_contains(result.source, "x > 5")
	assert_string_contains(result.source, "if GUTCheckCollector")


func test_elif_condition_wrapped():
	var source = "func foo():\n\tif true:\n\t\tpass\n\telif x < 3:"
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "elif GUTCheckCollector.hit_br2(")


func test_while_condition_wrapped():
	var source = "func foo():\n\twhile running:"
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "while GUTCheckCollector.hit_br2(")
	assert_string_contains(result.source, "running")


func test_for_iterable_wrapped():
	var source = "func foo():\n\tfor i in range(10):"
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "GUTCheckCollector.hit_br2rng(")
	assert_string_contains(result.source, "range(10)")


func test_match_wrapped():
	var source = "func foo():\n\tmatch state:"
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "match GUTCheckCollector.br(")
	assert_string_contains(result.source, "state")


# ---------------------------------------------------------------------------
# Else handling
# ---------------------------------------------------------------------------

func test_else_not_instrumented():
	var source = "func foo():\n\tif true:\n\t\tpass\n\telse:"
	var result = _instrumenter.instrument(source, 0)
	# else should NOT be instrumented (compound statement)
	var else_line = result.source.split("\n")[3]
	assert_eq(else_line, "\telse:", "else: should be unchanged")


# ---------------------------------------------------------------------------
# Indentation preservation
# ---------------------------------------------------------------------------

func test_indented_code_preserved():
	var source = "func foo():\n\tvar x = 5\n\tvar y = 10"
	var result = _instrumenter.instrument(source, 0)
	var lines = result.source.split("\n")
	assert_true(lines[1].begins_with("\t"), "Indentation should be preserved")
	assert_true(lines[2].begins_with("\t"), "Indentation should be preserved")


# ---------------------------------------------------------------------------
# Probe count
# ---------------------------------------------------------------------------

func test_probe_count_matches_executable_lines():
	var source = "func foo():\n\tvar x = 1\n\t# comment\n\tvar y = 2"
	var result = _instrumenter.instrument(source, 0)
	# Only var x and var y are executable (inside function)
	assert_eq(result.probe_count, 2,
		"Probe count should match number of executable lines")


# ---------------------------------------------------------------------------
# Complex script
# ---------------------------------------------------------------------------

func test_sample_script_instrumentation():
	var file = FileAccess.open("res://test/resources/sample_script.gd", FileAccess.READ)
	if file == null:
		pending("Could not open sample_script.gd")
		return
	var source = file.get_as_text()
	file.close()

	var result = _instrumenter.instrument(source, 0, "res://test/resources/sample_script.gd")

	assert_eq(
		result.source.split("\n").size(),
		source.split("\n").size(),
		"Instrumented source must have same line count")

	assert_gt(result.probe_count, 0, "Should have coverage probes")
	assert_string_contains(result.source, "GUTCheckCollector.hit(")
	assert_string_contains(result.source, "GUTCheckCollector.hit_br2(")
	assert_string_contains(result.source, "GUTCheckCollector.hit_br2rng(")


# ---------------------------------------------------------------------------
# Semicolon-separated statements
# ---------------------------------------------------------------------------

func test_semicolons_get_multiple_probes():
	var source = "func foo():\n\tvar a = 1; var b = 2; var c = 3"
	var result = _instrumenter.instrument(source, 0)
	# Should have 3 probes for the 3 statements on line 2
	assert_eq(result.probe_count, 3,
		"Three semicolon-separated statements should get 3 probes")


func test_semicolons_each_instrumented():
	var source = "func foo():\n\tvar a = 1; var b = 2"
	var result = _instrumenter.instrument(source, 0)
	var line2 = result.source.split("\n")[1]
	# Should contain two hit() calls
	var hit_count = line2.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Each semicolon-separated statement should get its own probe")


func test_semicolons_inside_parens_not_split():
	# Semicolons inside function call arguments should NOT be treated as statement separators
	var source = "func foo():\n\tprint(a; b)"
	var result = _instrumenter.instrument(source, 0)
	# Should have only 1 probe (the whole line is one statement)
	assert_eq(result.probe_count, 1,
		"Semicolons inside parens should not create extra probes")


# ---------------------------------------------------------------------------
# Ternary-if instrumentation
# ---------------------------------------------------------------------------

func test_ternary_gets_br2_probe():
	var source = 'func foo():\n\tvar x = "yes" if cond else "no"'
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "GUTCheckCollector.br2(")
	assert_string_contains(result.source, "GUTCheckCollector.hit(")


func test_ternary_preserves_structure():
	var source = 'func foo():\n\tvar x = "yes" if cond else "no"'
	var result = _instrumenter.instrument(source, 0)
	var lines = result.source.split("\n")
	assert_eq(lines.size(), source.split("\n").size(),
		"Ternary instrumentation should preserve line count")
	# The instrumented line should still contain the ternary keywords
	assert_string_contains(lines[1], " if ")
	assert_string_contains(lines[1], " else ")


func test_ternary_has_branch_probes():
	var source = 'func foo():\n\tvar x = "yes" if cond else "no"'
	var result = _instrumenter.instrument(source, 0)
	# 1 line probe + 2 branch probes = 3 total probes
	assert_eq(result.probe_count, 3,
		"Ternary should have 1 line probe + 2 branch probes")


func test_nested_ternary_instrumented():
	var source = 'func foo():\n\tvar z = "a" if x else "b" if y else "c"'
	var result = _instrumenter.instrument(source, 0)
	# Should have 2 br2() calls, one per ternary
	var line2 = result.source.split("\n")[1]
	var br2_count = line2.count("GUTCheckCollector.br2(")
	assert_eq(br2_count, 2,
		"Nested ternary should produce 2 br2() probes")


func test_ternary_return_instrumented():
	var source = 'func foo():\n\treturn "on" if cond else "off"'
	var result = _instrumenter.instrument(source, 0)
	assert_string_contains(result.source, "GUTCheckCollector.br2(")
	assert_string_contains(result.source, 'return "on" if')


func test_ternary_condition_wrapped_correctly():
	var source = 'func foo():\n\tvar x = "yes" if cond else "no"'
	var result = _instrumenter.instrument(source, 0)
	var line2 = result.source.split("\n")[1]
	# The condition "cond" should be inside br2(), not outside
	assert_string_contains(line2, "br2(0,")
	assert_string_contains(line2, ",cond)")
	# The else keyword should still be present after the wrapped condition
	assert_string_contains(line2, ') else "no"')
