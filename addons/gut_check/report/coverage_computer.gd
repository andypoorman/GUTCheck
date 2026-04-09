class_name GUTCheckCoverageComputer
## Pure computation utilities for coverage reports. Extracted from gut_check.gd
## so this logic can be instrumented for self-coverage.


## Compute line, branch, and function coverage for a single script.
static func compute_script_coverage(script_map, hits: PackedInt32Array) -> Dictionary:
	var context := build_script_context(script_map, hits)
	var line_probes: Dictionary = context.line_probes
	var branch_line_hits: Dictionary = context.branch_line_hits
	var exec_lines: Array[int] = context.exec_lines
	var lines_found := exec_lines.size()
	var lines_hit := 0
	var uncovered_lines: Array[int] = []

	for ln in exec_lines:
		var hit_count := get_line_hit_count(ln, line_probes, hits, branch_line_hits)
		if hit_count > 0:
			lines_hit += 1
		else:
			uncovered_lines.append(ln)

	# Branch coverage
	var branches_found: int = script_map.branches.size()
	var branches_hit := 0
	for b in script_map.branches:
		if get_branch_hit_count(b, script_map, hits, context) > 0:
			branches_hit += 1

	# Function coverage
	var funcs_found: int = script_map.functions.size()
	var funcs_hit := 0
	for func_info in script_map.functions:
		for ln in exec_lines:
			if ln >= func_info.start_line and (func_info.end_line == -1 or ln <= func_info.end_line):
				var fhc := get_line_hit_count(ln, line_probes, hits, branch_line_hits)
				if fhc > 0:
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


# -- Shared helpers (used by exporters too) --

static func build_script_context(script_map, hits: PackedInt32Array) -> Dictionary:
	var line_probes: Dictionary = build_line_probes(script_map)
	var exec_lines: Array[int] = script_map.get_executable_lines_sorted()
	var body_probe_ids: Dictionary = build_body_probe_ids(script_map, line_probes, exec_lines)
	return {
		"script_map": script_map,
		"line_probes": line_probes,
		"exec_lines": exec_lines,
		"body_probe_ids": body_probe_ids,
		"branch_line_hits": build_branch_line_hits(script_map, hits, body_probe_ids),
	}

## Build a mapping of line_number -> [probe_ids] for a script map.
static func build_line_probes(script_map) -> Dictionary:
	var line_probes: Dictionary = {}
	for probe_id: int in script_map.probe_to_line:
		var ln: int = script_map.probe_to_line[probe_id]
		if not line_probes.has(ln):
			line_probes[ln] = []
		line_probes[ln].append(probe_id)
	return line_probes


## Get the hit count for a line, falling back to branch probe hits.
static func get_line_hit_count(line_num: int, line_probes: Dictionary, hits: PackedInt32Array, branch_line_hits: Dictionary = {}) -> int:
	var hit_count := 0
	if line_probes.has(line_num):
		var probes: Array = line_probes[line_num]
		hit_count = hits[probes[0]] if probes[0] < hits.size() else 0
		for j in range(1, probes.size()):
			if probes[j] < hits.size():
				hit_count = mini(hit_count, hits[probes[j]])
	# Branch lines (if/elif/while/for) only fire branch probes, not line
	# probes.  Fall back to the sum of branch probe hits for such lines.
	if hit_count == 0 and branch_line_hits.has(line_num):
		hit_count = branch_line_hits[line_num]
	return hit_count


## Build a mapping of line_number -> total branch hits for that line.
## Used so branch lines (if/elif/while/for) count as covered even though
## the injector fires br2() instead of hit().
static func build_branch_line_hits(script_map, hits: PackedInt32Array, body_probe_ids: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for b in script_map.branches:
		var h := get_branch_hit_count(b, script_map, hits, {"body_probe_ids": body_probe_ids})
		if h > 0:
			result[b.line_number] = result.get(b.line_number, 0) + h
	return result


## Get the hit count for a branch probe, falling back to its body line
## for compound branches that cannot be instrumented directly.
static func get_branch_hit_count(branch_info, script_map, hits: PackedInt32Array, context: Dictionary = {}) -> int:
	var hit_count := 0
	if branch_info.probe_id < hits.size():
		hit_count = hits[branch_info.probe_id]
	if hit_count > 0:
		return hit_count

	var line_info = script_map.lines.get(branch_info.line_number)
	if line_info == null:
		return 0
	if line_info.type != GUTCheckScriptMap.LineType.BRANCH_ELSE \
			and line_info.type != GUTCheckScriptMap.LineType.BRANCH_PATTERN:
		return 0

	var body_probe_ids: Dictionary = context.get("body_probe_ids", {})
	return derive_body_hits(branch_info.line_number, script_map, hits, body_probe_ids)


## Derive hit count for a compound branch (else, match pattern) by looking
## at the first executable line in its body.
static func derive_body_hits(branch_line: int, _script_map, hits: PackedInt32Array, body_probe_ids: Dictionary) -> int:
	var pid: int = body_probe_ids.get(branch_line, -1)
	if pid >= 0 and pid < hits.size():
		return hits[pid]
	return 0


static func build_body_probe_ids(script_map, line_probes: Dictionary, exec_lines: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	var derivable_lines: Array[int] = []

	for branch_info in script_map.branches:
		var line_info = script_map.lines.get(branch_info.line_number)
		if line_info == null:
			continue
		if line_info.type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
				or line_info.type == GUTCheckScriptMap.LineType.BRANCH_PATTERN:
			if not result.has(branch_info.line_number):
				derivable_lines.append(branch_info.line_number)
				result[branch_info.line_number] = -1

	derivable_lines.sort()
	var exec_idx := 0
	for branch_line in derivable_lines:
		while exec_idx < exec_lines.size() and exec_lines[exec_idx] <= branch_line:
			exec_idx += 1
		if exec_idx >= exec_lines.size():
			break
		var body_line: int = exec_lines[exec_idx]
		if line_probes.has(body_line):
			result[branch_line] = line_probes[body_line][0]

	return result


static func _pct(hit: int, total: int, default_val: float = 0.0) -> float:
	if total <= 0:
		return default_val
	return float(hit) / float(total) * 100.0
