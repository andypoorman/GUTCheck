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
	var inner_class_scripts: Array[String] = []
	for path in source_files:
		if _is_probe_runtime(path):
			continue
		if _has_inner_classes(path):
			inner_class_scripts.append(path)
			continue
		var entry: Dictionary = _prepare_file(path)
		if not entry.is_empty():
			pending.append(entry)

	# Phase 1b: attempt inner-class scripts. These are risky because reload()
	# creates new type identities for inner classes, which can break typed
	# references in scripts outside source_dirs. We attempt instrumentation
	# but roll back on compile failure.
	for path in inner_class_scripts:
		var entry: Dictionary = _prepare_file(path)
		if not entry.is_empty():
			entry["has_inner_classes"] = true
			pending.append(entry)

	# Free the instrumenter pipeline so no instances of GutCheck scripts
	# exist when we reload them. This is what allows self-instrumentation.
	_instrumenter = null
	_registry = null

	# Phase 2: reload all instrumented scripts now that no instances block it.
	# Inner-class scripts are reloaded last so that if they break typed refs,
	# the non-inner-class scripts are already successfully reloaded.
	var inner_class_entries: Array = []
	for entry in pending:
		if entry.get("has_inner_classes", false):
			inner_class_entries.append(entry)
		else:
			_reload_file(entry)
	for entry in inner_class_entries:
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

	var script_reports: Array = []
	for sid: int in script_paths:
		var path: String = script_paths[sid]
		var hits: PackedInt32Array = all_hits.get(sid, PackedInt32Array())
		var script_map = all_maps.get(sid)
		if script_map == null:
			continue
		var s: Dictionary = GUTCheckCoverageComputer.compute_script_coverage(script_map, hits)
		s["path"] = path
		script_reports.append(s)

	var totals: Dictionary = GUTCheckCoverageComputer.aggregate_coverage(script_reports)
	totals["scripts"] = script_reports
	return totals


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
	var project_path := ProjectSettings.globalize_path("res://")
	return GUTCheckCoverageComputer.parse_lcov_content(content, project_path)


## Format an array of line numbers into compact ranges like "5-8,12,15-20".
func _format_line_ranges(line_numbers: Array[int]) -> String:
	return GUTCheckCoverageComputer.format_line_ranges(line_numbers)


## Check whether coverage meets the configured target.
func is_coverage_passing() -> bool:
	var target: float = _config.get("coverage_target", 0.0)
	if target <= 0.0:
		return true
	var report := _build_coverage_report()
	return report.total_line_pct >= target


func _discover_source_files() -> Array[String]:
	var source_dirs: Array = _config.get("source_dirs", DEFAULT_CONFIG.source_dirs)
	var exclude_patterns: Array = _config.get("exclude_patterns", DEFAULT_CONFIG.exclude_patterns)
	var files: Array[String] = []
	var seen: Dictionary = {}

	for dir_path: String in source_dirs:
		_scan_directory(dir_path, files, exclude_patterns, seen)

	return files


func _scan_directory(dir_path: String, files: Array[String], exclude_patterns: Array, seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("GUTCheck: Could not open directory: %s" % dir_path)
		return

	# Respect .gdignore — Godot's convention for ignoring directories
	if dir.file_exists(".gdignore"):
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory(full_path, files, exclude_patterns, seen)
		elif file_name.ends_with(".gd"):
			if not _is_excluded(full_path, exclude_patterns) and not seen.has(full_path):
				seen[full_path] = true
				files.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


func _is_excluded(path: String, patterns: Array) -> bool:
	return GUTCheckCoverageComputer.is_excluded(path, patterns)


## Scripts that must be excluded from instrumentation:
## - coverage_collector.gd: called by every probe, would cause infinite recursion
## - gut_check.gd: the facade is executing instrument_scripts(), can't reload self
## - Data classes (line_info, function_info, class_info, branch_info, script_map,
##   instrument_result): live instances exist in the pending instrumentation queue
##   and in the collector's script maps, blocking Godot's reload()
##
## Uses path-based detection: files must be under the gut_check addon directory.
## Previous versions matched by filename alone, which could accidentally exclude
## user scripts with the same name (e.g., a user's "script_map.gd").
const _PROBE_RUNTIME_PATHS: Array[String] = [
	"gut_check/collector/coverage_collector.gd",
	"gut_check/gut_check.gd",
	"gut_check/parser/line_info.gd",
	"gut_check/parser/function_info.gd",
	"gut_check/parser/class_info.gd",
	"gut_check/parser/branch_info.gd",
	"gut_check/parser/script_map.gd",
	"gut_check/instrumenter/instrument_result.gd",
]

func _is_probe_runtime(path: String) -> bool:
	if "addons/gut_check/" not in path:
		return false
	for suffix in _PROBE_RUNTIME_PATHS:
		if path.ends_with(suffix):
			return true
	return false


## Check if a source file contains inner class definitions. Scripts with inner
## classes cannot be safely reloaded at runtime because Godot creates new type
## identities for the inner classes, breaking typed references in other scripts.
func _has_inner_classes(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var source := file.get_as_text()
	file.close()
	return GUTCheckCoverageComputer.has_inner_classes_in_source(source)


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
