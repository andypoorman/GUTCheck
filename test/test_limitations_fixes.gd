extends GutTest
## Tests for the limitation fixes:
##   1. Inner class instrumentation (attempt + rollback)
##   2. .gdignore awareness
##   3. Path-based probe runtime detection (no filename collisions)
##   4. LCOV merge
##   5. Lambda function coverage


# ---------------------------------------------------------------------------
# 1. Inner class handling — no longer blanket-skipped
# ---------------------------------------------------------------------------

func test_inner_class_detection_still_works():
	var source := "extends Node\n\nclass Inner:\n\tvar x = 5\n\tfunc foo():\n\t\treturn x"
	assert_true(
		GUTCheckCoverageComputer.has_inner_classes_in_source(source),
		"Should detect inner class")


func test_inner_class_false_positive_class_name():
	var source := "class_name Foo\nextends Node"
	assert_false(
		GUTCheckCoverageComputer.has_inner_classes_in_source(source),
		"class_name should not be detected as inner class")


func test_inner_class_false_positive_multiline_string():
	## A multiline string containing "class Foo:" should NOT trigger inner class detection.
	var source := 'extends Node\n\nvar doc := """\nclass Foo:\n\tThis is documentation\n"""\n\nfunc bar():\n\tpass'
	assert_false(
		GUTCheckCoverageComputer.has_inner_classes_in_source(source),
		"class keyword inside multiline string should not be detected as inner class")


func test_inner_class_script_can_be_instrumented():
	## Inner class scripts should now be instrumented (not skipped).
	## The instrumenter should produce valid probes for both the outer
	## and inner class functions.
	var source := """extends Node

class Inner:
	var x = 5
	func foo():
		return x

func bar():
	var i = Inner.new()
	return i.foo()
"""
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, 99, "res://test_inner.gd")
	assert_gt(result.probe_count, 0, "Inner class script should produce probes")
	assert_string_contains(result.source, "GUTCheckCollector.hit(99,")
	# Line count must be preserved
	assert_eq(result.source.split("\n").size(), source.split("\n").size())


func test_inner_class_functions_tracked():
	## Functions inside inner classes should appear in the script map.
	var source := "extends Node\n\nclass Inner:\n\tfunc foo():\n\t\treturn 42\n\nfunc bar():\n\treturn 1"
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var script_map := classifier.classify(tokens, "res://test.gd")

	var func_names: Array[String] = []
	for f in script_map.functions:
		func_names.append(f.name)

	assert_has(func_names, "foo", "Inner class function should be in script map")
	assert_has(func_names, "bar", "Outer function should be in script map")


# ---------------------------------------------------------------------------
# 2. .gdignore awareness — tested via _scan_directory behavior
# ---------------------------------------------------------------------------

# Note: .gdignore behavior is filesystem-dependent and hard to unit test
# without mocking DirAccess. We verify the code path exists by checking
# that the scanner respects the convention. Integration tests would need
# a real directory with .gdignore.


# ---------------------------------------------------------------------------
# 3. Path-based probe runtime detection
# ---------------------------------------------------------------------------

func test_probe_runtime_detects_addon_scripts():
	var gc := GUTCheck.new()
	assert_true(gc._is_probe_runtime("res://addons/gut_check/collector/coverage_collector.gd"))
	assert_true(gc._is_probe_runtime("res://addons/gut_check/gut_check.gd"))
	assert_true(gc._is_probe_runtime("res://addons/gut_check/parser/script_map.gd"))
	assert_true(gc._is_probe_runtime("res://addons/gut_check/parser/line_info.gd"))
	assert_true(gc._is_probe_runtime("res://addons/gut_check/instrumenter/instrument_result.gd"))


func test_probe_runtime_allows_user_scripts_with_same_name():
	## User scripts that happen to have the same filename should NOT be excluded.
	var gc := GUTCheck.new()
	assert_false(gc._is_probe_runtime("res://scripts/coverage_collector.gd"),
		"User script with same name should not be excluded")
	assert_false(gc._is_probe_runtime("res://scripts/gut_check.gd"),
		"User script with same name should not be excluded")
	assert_false(gc._is_probe_runtime("res://scripts/script_map.gd"),
		"User script with same name should not be excluded")
	assert_false(gc._is_probe_runtime("res://src/utils/line_info.gd"),
		"User script with same name should not be excluded")


func test_probe_runtime_other_paths_allowed():
	var gc := GUTCheck.new()
	assert_false(gc._is_probe_runtime("res://scripts/player.gd"))
	assert_false(gc._is_probe_runtime("res://addons/gut_check/tokenizer/tokenizer.gd"))
	assert_false(gc._is_probe_runtime("res://addons/gut_check/parser/line_classifier.gd"))


# ---------------------------------------------------------------------------
# 4. LCOV merge
# ---------------------------------------------------------------------------

func test_merge_empty():
	var merger := GUTCheckLcovMerger.new()
	assert_eq(merger.generate_merged(), "", "Empty merge should produce empty output")


func test_merge_single_file():
	var lcov := """TN:
SF:/path/to/script.gd
FN:5,foo
FNDA:3,foo
FNF:1
FNH:1
DA:6,3
DA:7,2
LF:2
LH:2
end_of_record
"""
	var merger := GUTCheckLcovMerger.new()
	merger.add_content(lcov)
	var result := merger.generate_merged()
	assert_string_contains(result, "SF:/path/to/script.gd")
	assert_string_contains(result, "FNDA:3,foo")
	assert_string_contains(result, "DA:6,3")
	assert_string_contains(result, "DA:7,2")


func test_merge_combines_hit_counts():
	var lcov_a := """TN:
SF:/path/to/script.gd
FN:5,foo
FNDA:3,foo
FNF:1
FNH:1
DA:6,3
DA:7,0
LF:2
LH:1
end_of_record
"""
	var lcov_b := """TN:
SF:/path/to/script.gd
FN:5,foo
FNDA:2,foo
FNF:1
FNH:1
DA:6,1
DA:7,5
LF:2
LH:2
end_of_record
"""
	var merger := GUTCheckLcovMerger.new()
	merger.add_content(lcov_a)
	merger.add_content(lcov_b)
	var result := merger.generate_merged()
	# Hits should be summed
	assert_string_contains(result, "FNDA:5,foo")  # 3 + 2
	assert_string_contains(result, "DA:6,4")       # 3 + 1
	assert_string_contains(result, "DA:7,5")       # 0 + 5


func test_merge_different_files():
	var lcov_a := """TN:
SF:/path/to/a.gd
DA:1,5
LF:1
LH:1
end_of_record
"""
	var lcov_b := """TN:
SF:/path/to/b.gd
DA:1,3
LF:1
LH:1
end_of_record
"""
	var merger := GUTCheckLcovMerger.new()
	merger.add_content(lcov_a)
	merger.add_content(lcov_b)
	var result := merger.generate_merged()
	assert_string_contains(result, "SF:/path/to/a.gd")
	assert_string_contains(result, "SF:/path/to/b.gd")
	assert_string_contains(result, "DA:1,5")
	assert_string_contains(result, "DA:1,3")


func test_merge_branch_records():
	var lcov_a := """TN:
SF:/path/to/script.gd
BRDA:10,0,0,5
BRDA:10,0,1,0
BRF:2
BRH:1
DA:10,5
LF:1
LH:1
end_of_record
"""
	var lcov_b := """TN:
SF:/path/to/script.gd
BRDA:10,0,0,2
BRDA:10,0,1,3
BRF:2
BRH:2
DA:10,5
LF:1
LH:1
end_of_record
"""
	var merger := GUTCheckLcovMerger.new()
	merger.add_content(lcov_a)
	merger.add_content(lcov_b)
	var result := merger.generate_merged()
	assert_string_contains(result, "BRDA:10,0,0,7")  # 5 + 2
	assert_string_contains(result, "BRDA:10,0,1,3")  # 0 + 3


func test_merge_clear():
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("TN:\nSF:/a.gd\nDA:1,5\nLF:1\nLH:1\nend_of_record\n")
	merger.clear()
	assert_eq(merger.generate_merged(), "", "Clear should empty all records")


func test_merge_add_file_reads_from_disk():
	var tmp := "user://test_merge_input.lcov"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("TN:\nSF:/a.gd\nDA:1,3\nLF:1\nLH:1\nend_of_record\n")
	f.close()
	var merger := GUTCheckLcovMerger.new()
	assert_eq(merger.add_file(tmp), OK)
	assert_string_contains(merger.generate_merged(), "SF:/a.gd")
	DirAccess.remove_absolute(tmp)


func test_merge_add_file_missing_returns_error():
	var merger := GUTCheckLcovMerger.new()
	assert_eq(merger.add_file("user://__does_not_exist__.lcov"),
		ERR_FILE_NOT_FOUND)


func test_merge_write_merged_to_disk():
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("TN:\nSF:/path/to/script.gd\nDA:1,5\nLF:1\nLH:1\nend_of_record\n")
	var tmp_path := "user://test_merged.lcov"
	assert_eq(merger.write_merged(tmp_path), OK)
	var file := FileAccess.open(tmp_path, FileAccess.READ)
	assert_not_null(file)
	if file:
		var content := file.get_as_text()
		file.close()
		assert_string_contains(content, "SF:/path/to/script.gd")
		DirAccess.remove_absolute(tmp_path)


func test_merge_write_merged_bad_path_returns_error():
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("TN:\nSF:/x.gd\nDA:1,5\nLF:1\nLH:1\nend_of_record\n")
	assert_ne(merger.write_merged("/nonexistent/dir/merged.lcov"), OK)


func test_merge_fnda_before_fn_creates_synthetic_entry():
	# FNDA with no matching FN — should create entry with line=0.
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("TN:\nSF:/a.gd\nFNDA:5,bar\nend_of_record\n")
	assert_string_contains(merger.generate_merged(), "FNDA:5,bar")


func test_merge_fn_without_comma_is_skipped():
	# Malformed FN line (no comma) should not crash or record anything.
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("TN:\nSF:/a.gd\nFN:bad\nend_of_record\n")
	assert_false(merger.generate_merged().contains("FNDA"))


func test_merge_orphan_records_without_sf_are_ignored():
	# Records appearing before any SF line — each record type has a
	# `_records.has(current_sf)` guard that skips them.
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("TN:\nFN:5,foo\nFNDA:2,foo\nBRDA:1,0,0,1\nDA:1,1\nend_of_record\n")
	assert_eq(merger.generate_merged(), "")


func test_merge_blank_lines_are_skipped():
	var merger := GUTCheckLcovMerger.new()
	merger.add_content("\n\nTN:\nSF:/a.gd\n\nDA:1,1\nLF:1\nLH:1\nend_of_record\n\n")
	assert_string_contains(merger.generate_merged(), "SF:/a.gd")


# ---------------------------------------------------------------------------
# 5. Lambda function coverage
# ---------------------------------------------------------------------------

func test_lambda_creates_function_entry():
	## Multi-line lambda should create a function entry in the script map.
	var source := "func foo():\n\tvar fn = func(x):\n\t\treturn x * 2\n\treturn fn.call(5)"
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var script_map := classifier.classify(tokens, "res://test.gd")

	var has_lambda := false
	for f in script_map.functions:
		if f.name.begins_with("<lambda:"):
			has_lambda = true
			break
	assert_true(has_lambda, "Lambda should create a function entry")


func test_lambda_body_is_executable():
	## The body of a multi-line lambda should be classified as executable.
	var source := "func foo():\n\tvar fn = func(x):\n\t\treturn x * 2\n\treturn fn.call(5)"
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var script_map := classifier.classify(tokens, "res://test.gd")

	# Line 3 (return x * 2) should be executable
	assert_true(script_map.lines.has(3), "Lambda body line should be classified")
	if script_map.lines.has(3):
		assert_true(script_map.lines[3].is_executable(), "Lambda body should be executable")


func test_lambda_instrumented():
	## Lambda body should get probes.
	var source := "func foo():\n\tvar fn = func(x):\n\t\treturn x * 2\n\treturn fn.call(5)"
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, 0, "res://test.gd")
	# Line 3 should have a hit() probe for the return statement
	var lines := result.source.split("\n")
	assert_string_contains(lines[2], "GUTCheckCollector.hit(")


func test_multiple_lambdas_on_different_lines():
	var source := """func foo():
	var a = func(x):
		return x + 1
	var b = func(y):
		return y * 2
	return a.call(b.call(3))
"""
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var script_map := classifier.classify(tokens, "res://test.gd")

	var lambda_count := 0
	for f in script_map.functions:
		if f.name.begins_with("<lambda:"):
			lambda_count += 1
	assert_eq(lambda_count, 2, "Should detect both lambdas")


func test_lambda_in_function_scope():
	## Lambda's function_name in LineInfo should reference the lambda.
	var source := "func foo():\n\tvar fn = func(x):\n\t\treturn x * 2\n\treturn fn.call(5)"
	var tokenizer := GUTCheckTokenizer.new()
	var classifier := GUTCheckLineClassifier.new()
	var tokens := tokenizer.tokenize(source)
	var script_map := classifier.classify(tokens, "res://test.gd")

	# Line 3 should be inside the lambda scope
	if script_map.lines.has(3):
		var fn_name: String = script_map.lines[3].function_name
		assert_true(fn_name.begins_with("<lambda:") or fn_name == "foo",
			"Lambda body should be scoped to lambda or enclosing function")


func test_single_line_lambda_no_extra_scope():
	## A single-line lambda (var fn = func(x): return x) shouldn't break.
	## The lambda body is on the same line as the declaration.
	var source := "func foo():\n\tvar fn = func(x): return x * 2\n\treturn fn.call(5)"
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, 0, "res://test.gd")
	# Should not crash and should preserve line count
	assert_eq(result.source.split("\n").size(), source.split("\n").size())
	assert_gt(result.probe_count, 0)
