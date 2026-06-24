class_name GUTCheckCoverageComputer
## Pure computation utilities for coverage reports. Extracted from gut_check.gd
## so this logic can be instrumented for self-coverage.


## Compute line, branch, and function coverage for a single script.
static func compute_script_coverage(script_map, hits: PackedInt32Array) -> Dictionary:
	var context := build_script_context(script_map, hits)
	var line_probes: Dictionary = context.line_probes
	var branch_line_hits: Dictionary = context.branch_line_hits
	var exec_lines: Array[int] = context.exec_lines

	# Executable lines plus branch-only lines (else:, match arms), so the console
	# summary matches the LCOV/Cobertura output. See collect_da_lines.
	var all_da_lines: Array[int] = context.da_lines

	var lines_found := all_da_lines.size()
	var lines_hit := 0
	var uncovered_lines: Array[int] = []

	for ln in all_da_lines:
		var hit_count := get_line_hit_count(ln, line_probes, hits, branch_line_hits)
		if hit_count > 0:
			lines_hit += 1
		else:
			uncovered_lines.append(ln)

	# Branch coverage
	var branches_found: int = script_map.branches.size()
	var branches_hit := 0
	for b in script_map.branches:
		if get_branch_hit_count(b, hits) > 0:
			branches_hit += 1

	# Function coverage
	var funcs_found: int = script_map.functions.size()
	var funcs_hit := 0
	for func_info in script_map.functions:
		if function_hit_count(func_info, context, hits) > 0:
			funcs_hit += 1

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
## Uses the tokenizer to avoid false positives from "class " inside strings.
static func has_inner_classes_in_source(source: String) -> bool:
	var tokenizer := GUTCheckTokenizer.new()
	var tokens: Array = tokenizer.tokenize(source)
	for token in tokens:
		if token.type == GUTCheckToken.Type.KW_CLASS:
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
	var exec_lines: Array[int] = script_map.get_executable_lines_sorted()
	return {
		"script_map": script_map,
		"line_probes": build_line_probes(script_map),
		"exec_lines": exec_lines,
		"da_lines": collect_da_lines(script_map, exec_lines),
		"branch_line_hits": build_branch_line_hits(script_map, hits),
	}


## The lines that get a DA record: executable lines plus branch-only lines
## (else:, match arms) that carry a BRDA but are not themselves "executable".
## De-duplicated and sorted. Single source of truth for the line denominator,
## shared by compute_script_coverage and both exporters so LCOV, Cobertura and
## the console summary can never disagree on which lines count.
static func collect_da_lines(script_map, exec_lines: Array[int]) -> Array[int]:
	var seen: Dictionary = {}
	for ln in exec_lines:
		seen[ln] = true
	var da_lines: Array[int] = exec_lines.duplicate()
	for b in script_map.branches:
		if not seen.has(b.line_number):
			seen[b.line_number] = true
			da_lines.append(b.line_number)
	da_lines.sort()
	return da_lines

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
static func build_branch_line_hits(script_map, hits: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for b in script_map.branches:
		var h := get_branch_hit_count(b, hits)
		if h > 0:
			result[b.line_number] = result.get(b.line_number, 0) + h
	return result


## Hit count for a branch — just its probe's count. Every branch points at a
## real injected probe: if/elif/while/for/ternary and inline else/pattern fire
## their own; a block else:/pattern: has its probe_id bound to the first body
## line by the allocator (GUTCheckProbeAllocator.resolve_derived). So there is no
## report-time derivation — a branch is covered iff the probe proving it ran is.
static func get_branch_hit_count(branch_info, hits: PackedInt32Array) -> int:
	var pid: int = branch_info.probe_id
	if pid >= 0 and pid < hits.size():
		return hits[pid]
	return 0


## First line at which to measure a function's execution. For a block-bodied
## lambda the definition line is shared with the enclosing statement's probe
## (it fires when the lambda is DEFINED, not called), so measure from the
## first body line instead. Named functions/accessors start at their def line,
## which is non-executable anyway, so this is a no-op for them.
static func function_search_start(func_info) -> int:
	if String(func_info.name).begins_with("<lambda"):
		return func_info.start_line + 1
	return func_info.start_line


## Hit count for a function: the hit count of its first executable line within
## the function's range (see function_search_start). Shared by the report
## computer and the LCOV exporter so funcs_hit and FNDA agree.
static func function_hit_count(func_info, context: Dictionary, hits: PackedInt32Array) -> int:
	var search_start := function_search_start(func_info)
	for ln: int in context.exec_lines:
		if ln >= search_start and (func_info.end_line == -1 or ln <= func_info.end_line):
			return get_line_hit_count(ln, context.line_probes, hits, context.branch_line_hits)
	return 0


static func _pct(hit: int, total: int, default_val: float = 0.0) -> float:
	if total <= 0:
		return default_val
	return float(hit) / float(total) * 100.0
