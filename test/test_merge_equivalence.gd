extends GutTest
## End-to-end equivalence proof for merge_inputs.
##
## Simulates sharded coverage collection in-process: shard A runs part of the
## sample code and exports a tracefile; shard B runs the rest and exports
## through export_coverage() with merge_inputs pointing at shard A's file —
## exactly the flow a sharded CI uses. The merged report must be identical to
## the report of a single run that executed everything both shards did.
##
## Unlike the merger unit tests (hand-written LCOV snippets), this feeds the
## merge real exporter output, so it also guards against the exporter's format
## drifting away from what the merger understands.

const SID := 7
const VIRTUAL_PATH := "res://merge_eq_virtual_sample.gd"
const A_PATH := "user://merge_eq_shard_a.lcov"
const MERGED_PATH := "user://merge_eq_merged.lcov"
const REFERENCE_PATH := "user://merge_eq_reference.lcov"

const SAMPLE := """extends RefCounted


func alpha(flag: bool) -> int:
	if flag:
		return 1
	return 2


func beta() -> int:
	var total := 0
	for i in 3:
		total += i
	return total
"""

var _snapshot: Dictionary
var _a: Dictionary
var _merged: Dictionary
var _reference: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()

	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(SAMPLE, SID, VIRTUAL_PATH)
	GUTCheckCollector.register_script(SID, VIRTUAL_PATH, result.probe_count, result.script_map)

	var script := GDScript.new()
	script.source_code = result.source
	script.resource_path = "res://addons/gut_check/not_real/merge_eq_sample.gd"
	assert_eq(script.reload(), OK, "Instrumented sample should compile")

	GUTCheckCollector.enable()
	var obj = script.new()
	# Zero-hit state with the sample registered and the collector enabled —
	# restoring this is the in-process equivalent of a fresh shard process.
	var clean := GUTCheckCollector.snapshot()

	# Shard A: exercise only alpha's true branch, export its tracefile.
	# Collection stops before each export — the exporter itself is instrumented
	# when the suite runs with self-coverage, and its probes must not fire into
	# the cleared collector (the production hooks disable before exporting too).
	obj.alpha(true)
	GUTCheckCollector.disable()
	var exporter := GUTCheckLcovExporter.new()
	assert_eq(exporter.export_lcov(A_PATH), OK, "Shard A export should succeed")

	# Shard B: fresh state, run the rest, then export through the real
	# merge_inputs path — live shard B coverage + shard A's file.
	GUTCheckCollector.restore_snapshot(clean)
	obj.alpha(false)
	obj.beta()
	var gc := GUTCheck.new()
	gc._config = {"lcov_output": MERGED_PATH, "merge_inputs": [A_PATH]}
	assert_eq(gc.export_coverage(), OK, "Merged export should succeed")

	# Reference: one run that executes everything both shards did.
	GUTCheckCollector.restore_snapshot(clean)
	obj.alpha(true)
	obj.alpha(false)
	obj.beta()
	GUTCheckCollector.disable()
	assert_eq(exporter.export_lcov(REFERENCE_PATH), OK, "Reference export should succeed")

	_a = _parse_lcov(A_PATH)
	_merged = _parse_lcov(MERGED_PATH)
	_reference = _parse_lcov(REFERENCE_PATH)


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)
	DirAccess.remove_absolute(A_PATH)
	DirAccess.remove_absolute(MERGED_PATH)
	DirAccess.remove_absolute(REFERENCE_PATH)


# ---------------------------------------------------------------------------
# The shards are genuinely partial — the merge has real work to do
# ---------------------------------------------------------------------------

func test_shard_a_is_partial():
	var rec := _single_record(_a)
	assert_eq(rec.fnda.get("beta", -1), 0, "Shard A never calls beta")
	var missing := _covered(_single_record(_reference)).filter(
		func(ln): return not _covered(rec).has(ln))
	assert_gt(missing.size(), 0,
		"Shard A must leave some reference-covered lines uncovered")


func test_merged_covers_what_shard_a_missed():
	assert_gt(_single_record(_merged).fnda.get("beta", 0), 0,
		"Live shard B's beta() coverage must survive the merge")
	assert_gt(_single_record(_merged).da.values().count(1), 0,
		"Merged file should carry shard A's single-hit lines too")


# ---------------------------------------------------------------------------
# Merged report == single combined run, record for record
# ---------------------------------------------------------------------------

func test_merged_has_same_source_files_as_reference():
	assert_eq(_merged.keys(), _reference.keys(),
		"Merged and reference must report the same source files")
	assert_eq(_merged.size(), 1, "Sample run should produce exactly one SF record")


func test_merged_line_records_equal_reference():
	assert_eq(_single_record(_merged).da, _single_record(_reference).da,
		"Per-line hit counts must match the combined run exactly")


func test_merged_branch_records_equal_reference():
	assert_eq(_single_record(_merged).brda, _single_record(_reference).brda,
		"Branch records must match the combined run exactly")


func test_merged_function_records_equal_reference():
	assert_eq(_single_record(_merged).fnda, _single_record(_reference).fnda,
		"Function hit counts must match the combined run exactly")


func test_merged_summary_counters_equal_reference_and_are_consistent():
	var m := _single_record(_merged)
	var r := _single_record(_reference)
	assert_eq(m.summary, r.summary,
		"LF/LH/BRF/BRH/FNF/FNH must match the combined run")
	assert_eq(m.summary["LF"], m.da.size(), "LF must equal the DA record count")
	assert_eq(m.summary["LH"], _covered(m).size(), "LH must equal covered DA count")
	var taken := 0
	for hits: int in m.brda.values():
		if hits > 0:
			taken += 1
	assert_eq(m.summary["BRH"], taken, "BRH must equal taken BRDA count")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _parse_lcov(path: String) -> Dictionary:
	## Parse an LCOV file into {sf_path: {da, brda, fnda, summary}}.
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "Tracefile should exist: %s" % path)
	if file == null:
		return {}
	var records: Dictionary = {}
	var cur: Dictionary = {}
	for line in file.get_as_text().split("\n"):
		line = line.strip_edges()
		if line.begins_with("SF:"):
			cur = {"da": {}, "brda": {}, "fnda": {}, "summary": {}}
			records[line.substr(3)] = cur
		elif cur.is_empty():
			continue
		elif line.begins_with("DA:"):
			var parts := line.substr(3).split(",")
			cur.da[parts[0].to_int()] = parts[1].to_int()
		elif line.begins_with("BRDA:"):
			var parts := line.substr(5).split(",")
			cur.brda["%s,%s,%s" % [parts[0], parts[1], parts[2]]] = parts[3].to_int()
		elif line.begins_with("FNDA:"):
			var parts := line.substr(5).split(",", true, 2)
			cur.fnda[parts[1]] = parts[0].to_int()
		else:
			for key in ["LF", "LH", "BRF", "BRH", "FNF", "FNH"]:
				if line.begins_with(key + ":"):
					cur.summary[key] = line.substr(key.length() + 1).to_int()
	file.close()
	return records


func _single_record(parsed: Dictionary) -> Dictionary:
	assert_eq(parsed.size(), 1, "Expected exactly one SF record")
	return parsed.values()[0]


func _covered(record: Dictionary) -> Array:
	return record.da.keys().filter(func(ln): return record.da[ln] > 0)
