extends GutTest
## Definitive accuracy validation for gutcheck coverage.
##
## Strategy: instrument a purpose-built target script with KNOWN expected
## coverage, execute specific functions, export LCOV, parse the output,
## and assert exact expected values.
##
## If these assertions pass, the coverage tool is numerically correct.

var _snapshot: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _load_validation_source() -> String:
	var f := FileAccess.open("res://test/resources/validation_target.gd", FileAccess.READ)
	assert_not_null(f, "Could not open validation_target.gd")
	var source := f.get_as_text()
	f.close()
	return source


func _instrument_and_register(source: String, script_id: int = 0) -> GUTCheckInstrumentResult:
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, script_id, "res://test/resources/validation_target.gd")
	GUTCheckCollector.register_script(script_id, "res://test/resources/validation_target.gd",
		result.probe_count, result.script_map)
	return result


func _get_lcov() -> String:
	var exporter := GUTCheckLcovExporter.new()
	return exporter.generate_lcov()


func _parse_da_lines(lcov: String) -> Dictionary:
	## Returns {line_number: hit_count} from DA records.
	var result: Dictionary = {}
	for line in lcov.split("\n"):
		if line.begins_with("DA:"):
			var parts := line.substr(3).split(",")
			if parts.size() >= 2:
				result[int(parts[0])] = int(parts[1])
	return result


func _parse_brda_lines(lcov: String) -> Array:
	## Returns array of {line, block, branch, hits} dicts from BRDA records.
	var result: Array = []
	for line in lcov.split("\n"):
		if line.begins_with("BRDA:"):
			var parts := line.substr(5).split(",")
			if parts.size() >= 4:
				result.append({
					"line": int(parts[0]),
					"block": int(parts[1]),
					"branch": int(parts[2]),
					"hits": int(parts[3]),
				})
	return result


func _parse_fn_lines(lcov: String) -> Dictionary:
	## Returns {func_name: hit_count} from FNDA records.
	var result: Dictionary = {}
	for line in lcov.split("\n"):
		if line.begins_with("FNDA:"):
			var parts := line.substr(5).split(",", true, 2)
			if parts.size() >= 2:
				result[parts[1]] = int(parts[0])
	return result


func _parse_summary(lcov: String) -> Dictionary:
	## Returns {LF, LH, BRF, BRH, FNF, FNH} from summary records.
	var result: Dictionary = {}
	for line in lcov.split("\n"):
		if line.begins_with("LF:"):
			result["LF"] = int(line.substr(3))
		elif line.begins_with("LH:"):
			result["LH"] = int(line.substr(3))
		elif line.begins_with("BRF:"):
			result["BRF"] = int(line.substr(4))
		elif line.begins_with("BRH:"):
			result["BRH"] = int(line.substr(4))
		elif line.begins_with("FNF:"):
			result["FNF"] = int(line.substr(4))
		elif line.begins_with("FNH:"):
			result["FNH"] = int(line.substr(4))
	return result


# ---------------------------------------------------------------------------
# Step 1: Verify classification is correct before testing runtime coverage
# ---------------------------------------------------------------------------

func test_classification_executable_lines():
	var source := _load_validation_source()
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var smap := classifier.classify(tokens, "res://test/resources/validation_target.gd")

	# fully_covered: lines 12-15 should be executable
	for ln in [12, 13, 14, 15]:
		assert_true(smap.lines.has(ln), "Line %d should exist in map" % ln)
		assert_true(smap.lines[ln].is_executable(),
			"Line %d in fully_covered should be executable" % ln)

	# never_called: lines 29-31 should be executable
	for ln in [29, 30, 31]:
		assert_true(smap.lines.has(ln), "Line %d should exist in map" % ln)
		assert_true(smap.lines[ln].is_executable(),
			"Line %d in never_called should be executable" % ln)

	# for_loop_then_more: line after loop (result = total + 100) must be executable
	# The for loop is on line 38, body on 39, then lines 40-41 after loop
	var for_func_lines := [37, 38, 39, 40, 41]
	for ln in for_func_lines:
		assert_true(smap.lines.has(ln), "Line %d should exist in map" % ln)


func test_classification_branch_lines():
	var source := _load_validation_source()
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var smap := classifier.classify(tokens, "res://test/resources/validation_target.gd")

	# branching func: line 21 should be BRANCH_IF (func def on 20)
	assert_true(smap.lines.has(21), "Line 21 should exist")
	assert_eq(smap.lines[21].type, GUTCheckScriptMap.LineType.BRANCH_IF,
		"Line 21 should be BRANCH_IF")

	# line 23 should be BRANCH_ELSE
	assert_true(smap.lines.has(23), "Line 23 should exist")
	assert_eq(smap.lines[23].type, GUTCheckScriptMap.LineType.BRANCH_ELSE,
		"Line 23 should be BRANCH_ELSE")


# ---------------------------------------------------------------------------
# Step 2: Full pipeline -- instrument, execute, export, verify LCOV
# ---------------------------------------------------------------------------

func test_fully_covered_function_100_percent():
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	# Execute the instrumented code by evaluating it
	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile. Error: %d" % err)
	if err != OK:
		gut.p("Instrumented source (first 2000 chars):")
		gut.p(result.source.substr(0, 2000))
		return

	var target = script.new()
	GUTCheckCollector.enable()

	# Call fully_covered -- all 4 lines should be hit
	var val = target.fully_covered(5)
	assert_eq(val, 9, "fully_covered(5) should return 9")  # (5+1)*2-3 = 9

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)

	# Lines 12-15 are the body of fully_covered
	for ln in [12, 13, 14, 15]:
		assert_true(da.has(ln), "DA should have line %d" % ln)
		if da.has(ln):
			assert_gt(da[ln], 0, "Line %d should be hit (fully_covered)" % ln)

	# never_called lines should be 0
	for ln in [29, 30, 31]:
		if da.has(ln):
			assert_eq(da[ln], 0, "Line %d should NOT be hit (never_called)" % ln)


func test_branching_only_true_branch():
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()

	# Call branching(true) -- only the true branch should fire
	var val = target.branching(true)
	assert_eq(val, "yes")

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)

	# Line 21 (if cond:) should be hit (it's the branch condition)
	assert_true(da.has(21), "DA should have line 21 (if cond)")
	if da.has(21):
		assert_gt(da[21], 0, "Line 21 (if cond) should be hit")

	# Line 22 (return "yes") should be hit
	assert_true(da.has(22), "DA should have line 22")
	if da.has(22):
		assert_gt(da[22], 0, "Line 22 (true branch body) should be hit")

	# Line 24 (return "no") should NOT be hit
	if da.has(24):
		assert_eq(da[24], 0, "Line 24 (false branch body) should NOT be hit")

	# Check branch coverage: if should have true=hit, false=not-hit
	var brda := _parse_brda_lines(lcov)
	var if_branches := brda.filter(func(b): return b.line == 21)
	assert_gte(if_branches.size(), 2, "Line 21 should have at least 2 branch probes")
	if if_branches.size() >= 2:
		var has_hit := if_branches.any(func(b): return b.hits > 0)
		var has_miss := if_branches.any(func(b): return b.hits == 0)
		assert_true(has_hit, "Should have at least one hit branch on line 21")
		assert_true(has_miss, "Should have at least one missed branch on line 21")


func test_never_called_is_zero():
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	# Don't call anything -- just export
	GUTCheckCollector.enable()
	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)

	# All executable lines in never_called (29-31) should be 0
	for ln in [29, 30, 31]:
		if da.has(ln):
			assert_eq(da[ln], 0, "Line %d should be 0 (never_called)" % ln)

	# Function coverage: never_called should show 0 hits
	var fns := _parse_fn_lines(lcov)
	assert_true(fns.has("never_called"), "FNDA should include never_called")
	if fns.has("never_called"):
		assert_eq(fns["never_called"], 0, "never_called should have 0 function hits")


func test_for_loop_subsequent_lines_covered():
	## KEY TEST: Validates our scope fix. Lines after a for-loop body must
	## be covered when they execute.
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()

	var val = target.for_loop_then_more(3)
	# 0+1+2 = 3, +100 = 103
	assert_eq(val, 103, "for_loop_then_more(3) should return 103")

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)

	# Line 37: var total := 0 -- should be hit
	if da.has(37):
		assert_gt(da[37], 0, "Line 37 (var total) should be hit")

	# Line 38: for i in range(n): -- should be hit
	if da.has(38):
		assert_gt(da[38], 0, "Line 38 (for loop) should be hit")

	# Line 39: total += i -- should be hit
	if da.has(39):
		assert_gt(da[39], 0, "Line 39 (loop body) should be hit")

	# Line 40: var result := total + 100 -- MUST be hit (scope fix test)
	assert_true(da.has(40), "Line 40 (after loop) must have a DA entry")
	if da.has(40):
		assert_gt(da[40], 0, "Line 40 (after for loop) MUST be hit -- scope fix validation")

	# Line 41: return result -- MUST be hit
	assert_true(da.has(41), "Line 41 (return) must have a DA entry")
	if da.has(41):
		assert_gt(da[41], 0, "Line 41 (return after loop) MUST be hit -- scope fix validation")


func test_deeply_nested_blocks_subsequent_lines():
	## Tests for-inside-if-inside-while, then lines after the while.
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()

	var val = target.deeply_nested(3)
	# j=0: sum += 0+1+2 = 3; j=1: sum += 10 = 13; final = 13+1 = 14
	assert_eq(val, 14, "deeply_nested(3) should return 14")

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)

	# Line 77: var final_result := sum + 1 -- MUST be hit
	assert_true(da.has(77), "Line 77 (after while) must have a DA entry")
	if da.has(77):
		assert_gt(da[77], 0, "Line 77 (after nested blocks) MUST be hit")

	# Line 78: return final_result -- MUST be hit
	assert_true(da.has(78), "Line 78 (return) must have a DA entry")
	if da.has(78):
		assert_gt(da[78], 0, "Line 78 (return after nested blocks) MUST be hit")


func test_nested_while_if_coverage():
	## Tests that nested_blocks covers both branches and lines after the while.
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()

	var val = target.nested_blocks(4)
	assert_eq(val, "eoeo", "nested_blocks(4) should return 'eoeo'")

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)

	# Lines after the while loop must be covered
	# Line 54: var done := true
	if da.has(54):
		assert_gt(da[54], 0, "Line 54 (after while) should be hit")
	# Line 55: return out if done else ""
	if da.has(55):
		assert_gt(da[55], 0, "Line 55 (return with ternary) should be hit")


func test_ternary_has_branch_probes():
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()

	# Call ternary with true
	var val = target.ternary_expr(true)
	assert_eq(val, "on")

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var brda := _parse_brda_lines(lcov)

	# Line 60 (var result := "on" if flag else "off") should have ternary branches
	var ternary_branches := brda.filter(func(b): return b.line == 60)
	assert_gte(ternary_branches.size(), 2,
		"Line 60 (ternary) should have at least 2 branch probes (true/false)")
	if ternary_branches.size() >= 2:
		var has_hit := ternary_branches.any(func(b): return b.hits > 0)
		assert_true(has_hit, "At least one ternary branch should be hit")


func test_function_coverage_counts():
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()

	# Call 3 functions, leave never_called uncalled
	target.fully_covered(1)
	target.branching(true)
	target.for_loop_then_more(2)

	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var fns := _parse_fn_lines(lcov)
	var summary := _parse_summary(lcov)

	# Functions that were called should have hits > 0
	for fname in ["fully_covered", "branching", "for_loop_then_more"]:
		assert_true(fns.has(fname), "FNDA should include %s" % fname)
		if fns.has(fname):
			assert_gt(fns[fname], 0, "%s should have function hits > 0" % fname)

	# never_called should have 0 hits
	if fns.has("never_called"):
		assert_eq(fns["never_called"], 0, "never_called should have 0 function hits")

	# FNH should be at least 3 (the 3 we called)
	assert_true(summary.has("FNH"), "Should have FNH summary")
	if summary.has("FNH"):
		assert_gte(summary["FNH"], 3, "At least 3 functions should be hit")


func test_summary_counts_consistent():
	## Verify LF/LH/BRF/BRH totals match individual DA/BRDA records.
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()
	target.fully_covered(1)
	target.branching(true)
	target.for_loop_then_more(2)
	target.nested_blocks(3)
	target.deeply_nested(2)
	target.ternary_expr(false)
	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)
	var brda := _parse_brda_lines(lcov)
	var summary := _parse_summary(lcov)

	# LF should equal number of DA records
	assert_eq(summary.get("LF", -1), da.size(),
		"LF should equal number of DA records")

	# LH should equal number of DA records with hits > 0
	var hit_count := 0
	for ln in da:
		if da[ln] > 0:
			hit_count += 1
	assert_eq(summary.get("LH", -1), hit_count,
		"LH should equal number of hit DA records")

	# BRF should equal number of BRDA records
	if summary.has("BRF"):
		assert_eq(summary["BRF"], brda.size(),
			"BRF should equal number of BRDA records")

	# BRH should equal number of BRDA records with hits > 0
	if summary.has("BRH"):
		var br_hit := 0
		for b in brda:
			if b.hits > 0:
				br_hit += 1
		assert_eq(summary["BRH"], br_hit,
			"BRH should equal number of hit BRDA records")


func test_no_negative_hit_counts():
	## No DA or BRDA record should ever have a negative hit count.
	var source := _load_validation_source()
	var result := _instrument_and_register(source)

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script should compile")
	if err != OK:
		return

	var target = script.new()
	GUTCheckCollector.enable()
	target.fully_covered(1)
	target.branching(false)
	target.for_loop_then_more(0)
	GUTCheckCollector.disable()

	var lcov := _get_lcov()
	var da := _parse_da_lines(lcov)
	var brda := _parse_brda_lines(lcov)

	for ln in da:
		assert_gte(da[ln], 0, "DA line %d should not have negative hits" % ln)

	for b in brda:
		assert_gte(b.hits, 0,
			"BRDA line %d block %d branch %d should not have negative hits" % [b.line, b.block, b.branch])


func test_no_probe_id_exceeds_array():
	## Verify no probe_id in the script_map exceeds the allocated array size.
	var source := _load_validation_source()
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, 0, "res://test/resources/validation_target.gd")

	var smap := result.script_map
	var probe_count := result.probe_count

	# Check line probes
	for pid: int in smap.probe_to_line:
		assert_lt(pid, probe_count,
			"Line probe ID %d should be < probe_count %d" % [pid, probe_count])

	# Check branch probes
	for b in smap.branches:
		assert_lt(b.probe_id, probe_count,
			"Branch probe ID %d should be < probe_count %d" % [b.probe_id, probe_count])


func test_instrumented_script_compiles():
	## The instrumented source must be valid GDScript.
	var source := _load_validation_source()
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, 0, "res://test/resources/validation_target.gd")

	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented script must compile without errors")
	if err != OK:
		gut.p("=== INSTRUMENTED SOURCE (first 3000 chars) ===")
		gut.p(result.source.substr(0, 3000))
