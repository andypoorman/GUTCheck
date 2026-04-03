class_name GUTCheck
## Main facade for GUTCheck code coverage.
##
## Usage from hook scripts:
##   var gc = GUTCheck.new()
##   gc.instrument_scripts()    # in pre-run hook
##   gc.export_coverage()       # in post-run hook

const DEFAULT_CONFIG_PATH := "res://.gutcheck.json"

const DEFAULT_CONFIG := {
	"source_dirs": ["res://"],
	"exclude_patterns": ["**/test_*.gd", "**/addons/**", "**/autoload/**"],
	"lcov_output": "res://coverage.lcov",
	"coverage_target": 0.0,
}

var _config: Dictionary = {}
var _registry: GUTCheckScriptRegistry
var _instrumenter: GUTCheckInstrumenter
var _skipped_scripts: Array[String] = []


func _init():
	_registry = GUTCheckScriptRegistry.new()
	_instrumenter = GUTCheckInstrumenter.new()


## Load configuration from .gutcheck.json, merging with defaults.
func load_config(path: String = DEFAULT_CONFIG_PATH) -> Dictionary:
	_config = DEFAULT_CONFIG.duplicate(true)

	if not FileAccess.file_exists(path):
		return _config

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GUTCheck: Could not open config file: %s" % path)
		return _config

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_warning("GUTCheck: Error parsing config: %s" % json.get_error_message())
		return _config

	var user_config: Dictionary = json.data
	_config.merge(user_config, true)
	return _config


## Discover and instrument all source scripts based on config.
## Uses a two-phase approach so that GutCheck's own scripts can be
## instrumented: phase 1 tokenizes/classifies/instruments while instances
## exist, phase 2 frees those instances then reloads the modified scripts.
func instrument_scripts() -> void:
	if _config.is_empty():
		load_config()

	GUTCheckCollector.clear()
	_skipped_scripts.clear()

	# Phase 1: tokenize, classify, instrument, register with collector.
	# The instrumenter/tokenizer/classifier instances are alive during this phase.
	var pending: Array = []  # Array of {path, source, script}
	var source_files := _discover_source_files()
	for path in source_files:
		if _is_probe_runtime(path):
			continue
		if _has_inner_classes(path):
			push_error("GUTCheck: '%s' contains inner classes. Godot reload() changes inner class type identity, which breaks typed references in other scripts. Refactor inner classes to separate files with class_name to enable coverage." % path)
			_skipped_scripts.append(path)
			continue
		var entry: Dictionary = _prepare_file(path)
		if not entry.is_empty():
			pending.append(entry)

	# Free the instrumenter pipeline so no instances of GutCheck scripts
	# exist when we reload them. This is what allows self-instrumentation.
	_instrumenter = null
	_registry = null

	# Phase 2: reload all instrumented scripts now that no instances block it.
	for entry in pending:
		_reload_file(entry)

	GUTCheckCollector.enable()


## Return scripts that were skipped during instrumentation.
func get_skipped_scripts() -> Array[String]:
	return _skipped_scripts


## Export coverage data to LCOV file.
func export_coverage() -> int:
	GUTCheckCollector.disable()

	var output_path: String = _config.get("lcov_output", DEFAULT_CONFIG.lcov_output)
	var exporter := GUTCheckLcovExporter.new()
	return exporter.export_lcov(output_path)


## Export coverage data to Cobertura XML file.
func export_cobertura() -> int:
	var output_path: String = _config.get("cobertura_output", "")
	if output_path.is_empty():
		return OK  # Not configured, skip silently
	var exporter := GUTCheckCoberturaExporter.new()
	return exporter.export_cobertura(output_path)


## Print a coverage summary. Pass a GUT logger for integration, or null for print().
## If previous_lcov_path is provided, shows delta from the previous run.
func print_summary(logger = null) -> void:
	var output_path: String = _config.get("lcov_output", DEFAULT_CONFIG.lcov_output)
	var previous := _parse_previous_lcov(output_path)
	var report := _build_coverage_report()

	# Coverage output always goes to print() so it's visible regardless of
	# GUT log level. The logger is only used for warnings.
	var log_fn := func(msg: String) -> void:
		print(msg)

	var warn_fn := func(msg: String) -> void:
		if logger != null and logger.has_method("warn"):
			logger.warn(msg)
		else:
			print(msg)

	# Header
	var delta_str := ""
	if not previous.is_empty():
		var prev_pct: float = previous.get("_total_percentage", 0.0)
		var diff: float = report.total_line_pct - prev_pct
		if abs(diff) >= 0.05:
			delta_str = " (%s%.1f%%)" % ["+" if diff > 0 else "", diff]
	log_fn.call("GUTCheck: %d/%d lines covered (%.1f%%)%s" % [
		report.total_lines_hit, report.total_lines_found, report.total_line_pct, delta_str])

	if report.total_branches_found > 0:
		log_fn.call("GUTCheck: %d/%d branches covered (%.1f%%)" % [
			report.total_branches_hit, report.total_branches_found, report.total_branch_pct])

	log_fn.call("GUTCheck: %d/%d functions covered (%.1f%%)" % [
		report.total_funcs_hit, report.total_funcs_found, report.total_func_pct])

	# Table header
	log_fn.call("")
	var header := "%-40s | %7s | %7s | %7s | %s" % ["File", "% Lines", "% Branch", "% Funcs", "Uncovered Lines"]
	log_fn.call(header)
	var sep := "%s-|-%s-|-%s-|-%s-|-%s" % [
		"-".repeat(40), "-".repeat(7), "-".repeat(8), "-".repeat(7), "-".repeat(20)]
	log_fn.call(sep)

	# Sort scripts by line coverage ascending (worst first)
	var sorted_scripts: Array = report.scripts.duplicate()
	sorted_scripts.sort_custom(func(a, b): return a.line_pct < b.line_pct)

	for s in sorted_scripts:
		var short_path: String = s.path
		if short_path.begins_with("res://"):
			short_path = short_path.substr(6)
		if short_path.length() > 40:
			short_path = "..." + short_path.right(37)

		var uncovered_str: String = _format_line_ranges(s.uncovered_lines)
		if uncovered_str.length() > 40:
			uncovered_str = uncovered_str.left(37) + "..."

		var branch_str := "   N/A " if s.branches_found == 0 else "%6.1f%%" % s.branch_pct

		var line_delta := ""
		if previous.has(s.path):
			var prev_pct: float = previous[s.path]
			var diff: float = s.line_pct - prev_pct
			if abs(diff) >= 0.05:
				line_delta = " %s%.1f" % ["+" if diff > 0 else "", diff]

		var line_str := "%5.1f%%%s" % [s.line_pct, line_delta]

		log_fn.call("%-40s | %7s | %8s | %6.1f%% | %s" % [
			short_path, line_str, branch_str, s.func_pct, uncovered_str])

	log_fn.call(sep)

	# Totals row
	var total_branch_str := "   N/A " if report.total_branches_found == 0 else "%6.1f%%" % report.total_branch_pct
	log_fn.call("%-40s | %6.1f%% | %8s | %6.1f%% |" % [
		"All files", report.total_line_pct, total_branch_str, report.total_func_pct])

	# Warn about top uncovered files
	if sorted_scripts.size() > 0 and sorted_scripts[0].line_pct < 50.0:
		warn_fn.call("")
		warn_fn.call("GUTCheck: Files with lowest coverage:")
		var count := 0
		for s in sorted_scripts:
			if count >= 5 or s.line_pct >= 50.0:
				break
			var short_path: String = s.path
			if short_path.begins_with("res://"):
				short_path = short_path.substr(6)
			warn_fn.call("  %5.1f%%  %s" % [s.line_pct, short_path])
			count += 1


## Build a detailed coverage report from collector data.
func _build_coverage_report() -> Dictionary:
	var script_paths := GUTCheckCollector.get_script_paths()
	var all_hits := GUTCheckCollector.get_hits()
	var all_maps := GUTCheckCollector.get_script_maps()

	var total_lines_found := 0
	var total_lines_hit := 0
	var total_branches_found := 0
	var total_branches_hit := 0
	var total_funcs_found := 0
	var total_funcs_hit := 0
	var scripts: Array = []

	for sid: int in script_paths:
		var path: String = script_paths[sid]
		var hits: PackedInt32Array = all_hits.get(sid, PackedInt32Array())
		var script_map = all_maps.get(sid)
		if script_map == null:
			continue

		# Line coverage
		var line_probes: Dictionary = {}
		for probe_id: int in script_map.probe_to_line:
			var ln: int = script_map.probe_to_line[probe_id]
			if not line_probes.has(ln):
				line_probes[ln] = []
			line_probes[ln].append(probe_id)

		var exec_lines: Array[int] = script_map.get_executable_lines_sorted()
		var lines_found := exec_lines.size()
		var lines_hit := 0
		var uncovered_lines: Array[int] = []

		for ln in exec_lines:
			var hit_count := 0
			if line_probes.has(ln):
				var probes: Array = line_probes[ln]
				hit_count = hits[probes[0]] if probes[0] < hits.size() else 0
				for j in range(1, probes.size()):
					if probes[j] < hits.size():
						hit_count = mini(hit_count, hits[probes[j]])
			if hit_count > 0:
				lines_hit += 1
			else:
				uncovered_lines.append(ln)

		# Branch coverage
		var branches_found: int = script_map.branches.size()
		var branches_hit := 0
		for b in script_map.branches:
			var h := 0
			if b.probe_id < hits.size():
				h = hits[b.probe_id]
			# Derive hits for compound branches (else, match patterns)
			if h == 0:
				var line_info = script_map.lines.get(b.line_number)
				if line_info != null and (line_info.type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
						or line_info.type == GUTCheckScriptMap.LineType.BRANCH_PATTERN):
					# Check first body line
					for body_ln in exec_lines:
						if body_ln > b.line_number:
							if line_probes.has(body_ln):
								var pid: int = line_probes[body_ln][0]
								if pid < hits.size():
									h = hits[pid]
							break
			if h > 0:
				branches_hit += 1

		# Function coverage
		var funcs_found: int = script_map.functions.size()
		var funcs_hit := 0
		for func_info in script_map.functions:
			for ln in exec_lines:
				if ln >= func_info.start_line and (func_info.end_line == -1 or ln <= func_info.end_line):
					if line_probes.has(ln):
						var pid: int = line_probes[ln][0]
						if pid < hits.size() and hits[pid] > 0:
							funcs_hit += 1
					break

		total_lines_found += lines_found
		total_lines_hit += lines_hit
		total_branches_found += branches_found
		total_branches_hit += branches_hit
		total_funcs_found += funcs_found
		total_funcs_hit += funcs_hit

		scripts.append({
			"path": path,
			"lines_found": lines_found,
			"lines_hit": lines_hit,
			"line_pct": (float(lines_hit) / float(lines_found) * 100.0) if lines_found > 0 else 100.0,
			"branches_found": branches_found,
			"branches_hit": branches_hit,
			"branch_pct": (float(branches_hit) / float(branches_found) * 100.0) if branches_found > 0 else 100.0,
			"funcs_found": funcs_found,
			"funcs_hit": funcs_hit,
			"func_pct": (float(funcs_hit) / float(funcs_found) * 100.0) if funcs_found > 0 else 100.0,
			"uncovered_lines": uncovered_lines,
		})

	return {
		"total_lines_found": total_lines_found,
		"total_lines_hit": total_lines_hit,
		"total_line_pct": (float(total_lines_hit) / float(total_lines_found) * 100.0) if total_lines_found > 0 else 0.0,
		"total_branches_found": total_branches_found,
		"total_branches_hit": total_branches_hit,
		"total_branch_pct": (float(total_branches_hit) / float(total_branches_found) * 100.0) if total_branches_found > 0 else 0.0,
		"total_funcs_found": total_funcs_found,
		"total_funcs_hit": total_funcs_hit,
		"total_func_pct": (float(total_funcs_hit) / float(total_funcs_found) * 100.0) if total_funcs_found > 0 else 0.0,
		"scripts": scripts,
	}


## Parse a previous LCOV file to extract per-file line coverage percentages.
## Returns {path: percentage, "_total_percentage": float} or empty dict if unavailable.
func _parse_previous_lcov(lcov_path: String) -> Dictionary:
	if not FileAccess.file_exists(lcov_path):
		return {}

	var file := FileAccess.open(lcov_path, FileAccess.READ)
	if file == null:
		return {}

	var content := file.get_as_text()
	file.close()

	var result: Dictionary = {}
	var current_path := ""
	var lf := 0
	var lh := 0
	var total_lf := 0
	var total_lh := 0

	for line in content.split("\n"):
		if line.begins_with("SF:"):
			current_path = line.substr(3)
			# Convert absolute path back to res:// if possible
			var project_path := ProjectSettings.globalize_path("res://")
			if current_path.begins_with(project_path):
				current_path = "res://" + current_path.substr(project_path.length())
		elif line.begins_with("LF:"):
			lf = int(line.substr(3))
		elif line.begins_with("LH:"):
			lh = int(line.substr(3))
		elif line == "end_of_record":
			if current_path != "" and lf > 0:
				result[current_path] = float(lh) / float(lf) * 100.0
			total_lf += lf
			total_lh += lh
			current_path = ""
			lf = 0
			lh = 0

	if total_lf > 0:
		result["_total_percentage"] = float(total_lh) / float(total_lf) * 100.0

	return result


## Format an array of line numbers into compact ranges like "5-8,12,15-20".
func _format_line_ranges(line_numbers: Array[int]) -> String:
	if line_numbers.is_empty():
		return ""

	var ranges: PackedStringArray = []
	var start: int = line_numbers[0]
	var end: int = line_numbers[0]

	for i in range(1, line_numbers.size()):
		if line_numbers[i] == end + 1:
			end = line_numbers[i]
		else:
			if start == end:
				ranges.append(str(start))
			else:
				ranges.append("%d-%d" % [start, end])
			start = line_numbers[i]
			end = line_numbers[i]

	if start == end:
		ranges.append(str(start))
	else:
		ranges.append("%d-%d" % [start, end])

	return ",".join(ranges)


## Check whether coverage meets the configured target.
func is_coverage_passing() -> bool:
	var target: float = _config.get("coverage_target", 0.0)
	if target <= 0.0:
		return true
	var summary := GUTCheckCollector.get_coverage_summary()
	return summary.percentage >= target


func _discover_source_files() -> Array[String]:
	var source_dirs: Array = _config.get("source_dirs", DEFAULT_CONFIG.source_dirs)
	var exclude_patterns: Array = _config.get("exclude_patterns", DEFAULT_CONFIG.exclude_patterns)
	var files: Array[String] = []

	for dir_path: String in source_dirs:
		_scan_directory(dir_path, files, exclude_patterns)

	return files


func _scan_directory(dir_path: String, files: Array[String], exclude_patterns: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("GUTCheck: Could not open directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory(full_path, files, exclude_patterns)
		elif file_name.ends_with(".gd"):
			if not _is_excluded(full_path, exclude_patterns):
				files.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


func _is_excluded(path: String, patterns: Array) -> bool:
	for pattern: String in patterns:
		if path.match(pattern):
			return true
	return false


## Scripts that must be excluded from instrumentation:
## - coverage_collector.gd: called by every probe, would cause infinite recursion
## - gut_check.gd: the facade is executing instrument_scripts(), can't reload self
## - Data classes (line_info, function_info, class_info, branch_info, script_map,
##   instrument_result): live instances exist in the pending instrumentation queue
##   and in the collector's script maps, blocking Godot's reload()
func _is_probe_runtime(path: String) -> bool:
	var filename := path.get_file()
	return filename in [
		"coverage_collector.gd",
		"gut_check.gd",
		"line_info.gd",
		"function_info.gd",
		"class_info.gd",
		"branch_info.gd",
		"script_map.gd",
		"instrument_result.gd",
	]


## Check if a source file contains inner class definitions. Scripts with inner
## classes cannot be safely reloaded at runtime because Godot creates new type
## identities for the inner classes, breaking typed references in other scripts.
func _has_inner_classes(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var source := file.get_as_text()
	file.close()
	# Look for top-level "class Foo" declarations (not "class_name")
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("class ") and not stripped.begins_with("class_name"):
			return true
	return false


## Phase 1: tokenize, classify, instrument a file. Returns a dict with
## {path, source, script} on success, or empty dict on failure.
func _prepare_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GUTCheck: Could not read file: %s" % path)
		_skipped_scripts.append(path)
		return {}

	var source := file.get_as_text()
	file.close()

	var script_id := _registry.register(path)

	var result: GUTCheckInstrumentResult
	result = _instrumenter.instrument(source, script_id, path)
	if result == null or result.probe_count == 0:
		push_warning("GUTCheck: Instrumentation produced no probes for: %s (skipping)" % path)
		_skipped_scripts.append(path)
		return {}

	# Get the cached GDScript object — don't reload yet.
	var script = load(path) as GDScript
	if script == null:
		push_warning("GUTCheck: Could not load script for instrumentation: %s (skipping)" % path)
		_skipped_scripts.append(path)
		return {}

	return {
		"path": path,
		"source": result.source,
		"script": script,
		"script_id": script_id,
		"probe_count": result.probe_count,
		"script_map": result.script_map,
	}


## Phase 2: reload a previously instrumented script and register with collector.
func _reload_file(entry: Dictionary) -> void:
	var path: String = entry.path
	var script: GDScript = entry.script
	var original_source: String = script.source_code
	script.source_code = entry.source
	var reload_result: int = script.reload()
	if reload_result != OK:
		push_warning("GUTCheck: Failed to compile instrumented script: %s (error %d, skipping)" % [path, reload_result])
		script.source_code = original_source
		script.reload()
		_skipped_scripts.append(path)
		return

	# Register with collector only after successful reload
	GUTCheckCollector.register_script(
		entry.script_id, path, entry.probe_count, entry.script_map)
