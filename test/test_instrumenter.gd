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


func test_semicolons_inside_escaped_string_not_split():
	var source = 'func foo():\n\tprint("a\\\";b"); var x = 1'
	var result = _instrumenter.instrument(source, 0)
	assert_eq(result.probe_count, 2,
		"Escaped quotes inside strings should not confuse semicolon splitting")


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


# ---------------------------------------------------------------------------
# Instrumenter passthrough — lines without probes
# ---------------------------------------------------------------------------

func test_preserves_lines_without_probes():
	# Lines without instrumentation (top-level var, blank) must pass through
	# unchanged — covers the `line_to_first_probe.has` false branch and the
	# indent.length() == 0 branch.
	var source = "extends Node\n\nvar _field = 1\n\nfunc foo():\n\treturn 1"
	var result = _instrumenter.instrument(source, 0, "res://it.gd")
	var out_lines = result.source.split("\n")
	assert_eq(out_lines[0], "extends Node")  # line 1 passthrough
	assert_eq(out_lines[1], "")              # blank line passthrough
	assert_string_contains(out_lines[5], "GUTCheckCollector.hit(")  # probe injected


# ---------------------------------------------------------------------------
# Probe injector — static function edge cases
# ---------------------------------------------------------------------------

func test_probe_injector_ternary_without_probes_falls_back_to_hit():
	# Ternary line with zero branch probes — wrap_ternary must emit a plain
	# hit() call and skip br2 wrapping.
	var content = 'return "yes" if x else "no"'
	var result = GUTCheckProbeInjector.wrap_ternary(content, 0, 3, [])
	assert_string_contains(result, "GUTCheckCollector.hit(0,3);")
	assert_false(result.contains("br2("), "No branch probes means no br2 wrapping")


func test_probe_injector_find_for_in_with_string_containing_in_keyword():
	# Real ` in ` is found first; the " in " inside the string is never reached.
	var pos = GUTCheckProbeInjector.find_for_in('for c in "a in b": pass')
	assert_eq(pos, 5)


func test_probe_injector_find_for_in_with_escape_in_string():
	var pos = GUTCheckProbeInjector.find_for_in('for c in "a\\"b": pass')
	assert_eq(pos, 5)


func test_probe_injector_find_for_in_returns_minus_one_on_no_in():
	assert_eq(GUTCheckProbeInjector.find_for_in("for x:"), -1)


func test_probe_injector_for_in_with_no_in_returns_content_unchanged():
	# wrap_for_br2 returns content unchanged when find_for_in fails.
	var result = GUTCheckProbeInjector.wrap_for_br2("for x:", 0, 0, [])
	assert_eq(result, "for x:")


func test_probe_injector_find_block_colon_inside_string_ignored():
	# A colon inside a string literal must not be treated as block colon.
	var idx = GUTCheckProbeInjector.find_block_colon('"a:b":')
	assert_eq(idx, 5, "Block colon should be the one outside the string")


func test_probe_injector_find_ternary_if_positions_no_ternary():
	var positions = GUTCheckProbeInjector.find_ternary_if_positions("var x = 5")
	assert_eq(positions.size(), 0)


func test_probe_injector_get_indent_mixed_whitespace():
	assert_eq(GUTCheckProbeInjector.get_indent("\t  code"), "\t  ")
	assert_eq(GUTCheckProbeInjector.get_indent("code"), "")


func test_probe_injector_instrument_line_noop_for_non_executable_types():
	# FUNC_DEF / CLASS_DEF / default cases return the line unchanged.
	var line = "func foo():"
	var result = GUTCheckProbeInjector.instrument_line(
		line, GUTCheckScriptMap.LineType.FUNC_DEF, 0, 0)
	assert_eq(result, line)
	var line2 = "class Inner:"
	var result2 = GUTCheckProbeInjector.instrument_line(
		line2, GUTCheckScriptMap.LineType.CLASS_DEF, 0, 0)
	assert_eq(result2, line2)


func test_probe_injector_instrument_line_branch_else_returns_line():
	var line = "\telse:"
	var result = GUTCheckProbeInjector.instrument_line(
		line, GUTCheckScriptMap.LineType.BRANCH_ELSE, 0, 0)
	assert_eq(result, line)
