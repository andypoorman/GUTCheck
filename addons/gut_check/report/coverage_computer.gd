class_name GUTCheckCoverageComputer
## Pure computation utilities for coverage reports. Extracted from gut_check.gd
## so this logic can be instrumented for self-coverage.


## Compute line, branch, and function coverage for a single script.
static func compute_script_coverage(script_map, hits: PackedInt32Array) -> Dictionary:
	# Line coverage
	var line_probes: Dictionary = _build_line_probes(script_map)
	var exec_lines: Array[int] = script_map.get_executable_lines_sorted()
	var lines_found := exec_lines.size()
	var lines_hit := 0
	var uncovered_lines: Array[int] = []

	for ln in exec_lines:
		var hit_count := _get_line_hit_count(ln, line_probes, hits)
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
		if h == 0:
			var line_info = script_map.lines.get(b.line_number)
			if line_info != null and (line_info.type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
					or line_info.type == GUTCheckScriptMap.LineType.BRANCH_PATTERN):
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

	return {
		"lines_found": lines_found,
		"lines_hit": lines_hit,
		"line_pct": _pct(lines_hit, lines_found, 100.0),
		"branches_found": branches_found,
		"branches_hit": branches_hit,
		"branch_pct": _pct(branches_hit, branches_found, 100.0),
		"funcs_found": funcs_found,
		"funcs_hit": funcs_hit,
		"func_pct": _pct(funcs_hit, funcs_found, 100.0),
		"uncovered_lines": uncovered_lines,
	}


## Aggregate multiple per-script coverage reports into totals.
static func aggregate_coverage(script_reports: Array) -> Dictionary:
	var total_lines_found := 0
	var total_lines_hit := 0
	var total_branches_found := 0
	var total_branches_hit := 0
	var total_funcs_found := 0
	var total_funcs_hit := 0

	for s in script_reports:
		total_lines_found += s.lines_found
		total_lines_hit += s.lines_hit
		total_branches_found += s.branches_found
		total_branches_hit += s.branches_hit
		total_funcs_found += s.funcs_found
		total_funcs_hit += s.funcs_hit

	return {
		"total_lines_found": total_lines_found,
		"total_lines_hit": total_lines_hit,
		"total_line_pct": _pct(total_lines_hit, total_lines_found),
		"total_branches_found": total_branches_found,
		"total_branches_hit": total_branches_hit,
		"total_branch_pct": _pct(total_branches_hit, total_branches_found),
		"total_funcs_found": total_funcs_found,
		"total_funcs_hit": total_funcs_hit,
		"total_func_pct": _pct(total_funcs_hit, total_funcs_found),
	}


## Parse LCOV content string and extract per-file line coverage percentages.
## project_path is the result of ProjectSettings.globalize_path("res://").
## Returns {path: percentage, "_total_percentage": float}.
static func parse_lcov_content(content: String, project_path: String = "") -> Dictionary:
	var result: Dictionary = {}
	var current_path := ""
	var lf := 0
	var lh := 0
	var total_lf := 0
	var total_lh := 0

	for line in content.split("\n"):
		if line.begins_with("SF:"):
			current_path = line.substr(3)
			if project_path != "" and current_path.begins_with(project_path):
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
static func format_line_ranges(line_numbers: Array[int]) -> String:
	if line_numbers.is_empty():
		return ""

	var ranges: PackedStringArray = []
	var start: int = line_numbers[0]
	var end_num: int = line_numbers[0]

	for i in range(1, line_numbers.size()):
		if line_numbers[i] == end_num + 1:
			end_num = line_numbers[i]
		else:
			if start == end_num:
				ranges.append(str(start))
			else:
				ranges.append("%d-%d" % [start, end_num])
			start = line_numbers[i]
			end_num = line_numbers[i]

	if start == end_num:
		ranges.append(str(start))
	else:
		ranges.append("%d-%d" % [start, end_num])

	return ",".join(ranges)


## Check if source text contains inner class definitions.
static func has_inner_classes_in_source(source: String) -> bool:
	for line in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("class ") and not stripped.begins_with("class_name"):
			return true
	return false


## Check if a path matches any exclusion pattern.
static func is_excluded(path: String, patterns: Array) -> bool:
	for pattern: String in patterns:
		if path.match(pattern):
			return true
	return false


# -- Private helpers --

static func _build_line_probes(script_map) -> Dictionary:
	var line_probes: Dictionary = {}
	for probe_id: int in script_map.probe_to_line:
		var ln: int = script_map.probe_to_line[probe_id]
		if not line_probes.has(ln):
			line_probes[ln] = []
		line_probes[ln].append(probe_id)
	return line_probes


static func _get_line_hit_count(line_num: int, line_probes: Dictionary, hits: PackedInt32Array) -> int:
	if not line_probes.has(line_num):
		return 0
	var probes: Array = line_probes[line_num]
	var hit_count: int = hits[probes[0]] if probes[0] < hits.size() else 0
	for j in range(1, probes.size()):
		if probes[j] < hits.size():
			hit_count = mini(hit_count, hits[probes[j]])
	return hit_count


static func _pct(hit: int, total: int, default_val: float = 0.0) -> float:
	if total <= 0:
		return default_val
	return float(hit) / float(total) * 100.0
