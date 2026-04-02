class_name GUTCheckLcovExporter
## Generates LCOV tracefiles from coverage data collected by GUTCheckCollector.
##
## LCOV format reference: https://ltp.sourceforge.net/coverage/lcov/geninfo.1.php
##
## Records emitted:
##   TN:<test name>
##   SF:<absolute source path>
##   FN:<line>,<function name>
##   FNDA:<hit count>,<function name>
##   FNF:<functions found>
##   FNH:<functions hit>
##   BRDA:<line>,<block>,<branch>,<hits>
##   BRF:<branches found>
##   BRH:<branches hit>
##   DA:<line>,<hit count>
##   LF:<lines found>
##   LH:<lines hit>
##   end_of_record


## Export coverage data to an LCOV tracefile. Returns OK on success.
func export_lcov(output_path: String, test_name: String = "") -> int:
	var content := _generate_lcov(test_name)
	return _write_file(output_path, content)


## Generate the LCOV content string without writing to disk.
func generate_lcov(test_name: String = "") -> String:
	return _generate_lcov(test_name)


func _generate_lcov(test_name: String) -> String:
	var lines: PackedStringArray = []
	var script_paths := GUTCheckCollector.get_script_paths()
	var all_hits := GUTCheckCollector.get_hits()
	var all_maps := GUTCheckCollector.get_script_maps()

	for sid: int in script_paths:
		var path: String = script_paths[sid]
		var hits: PackedInt32Array = all_hits.get(sid, PackedInt32Array())
		var script_map = all_maps.get(sid)
		if script_map == null:
			continue

		lines.append("TN:%s" % test_name)
		lines.append("SF:%s" % _to_absolute_path(path))

		# Function records
		_emit_function_records(lines, script_map, hits)

		# Branch records
		_emit_branch_records(lines, script_map, hits)

		# Line records
		_emit_line_records(lines, script_map, hits)

		lines.append("end_of_record")

	return "\n".join(lines) + "\n" if lines.size() > 0 else ""


func _emit_function_records(lines: PackedStringArray, script_map, hits: PackedInt32Array) -> void:
	var functions_found := 0
	var functions_hit := 0

	for func_info in script_map.functions:
		# Emit FN record
		lines.append("FN:%d,%s" % [func_info.start_line, _qualified_func_name(func_info)])

		# Calculate function hit count: a function is "hit" if any
		# executable line within it was executed
		var func_hit_count := _get_function_hit_count(func_info, script_map, hits)
		lines.append("FNDA:%d,%s" % [func_hit_count, _qualified_func_name(func_info)])

		functions_found += 1
		if func_hit_count > 0:
			functions_hit += 1

	lines.append("FNF:%d" % functions_found)
	lines.append("FNH:%d" % functions_hit)


func _emit_branch_records(lines: PackedStringArray, script_map, hits: PackedInt32Array) -> void:
	if script_map.branches.size() == 0:
		# No branch data — omit BRF/BRH entirely for backward compatibility
		return

	var branches_found := 0
	var branches_hit := 0

	# Build line_probes for match pattern hit derivation
	var line_probes: Dictionary = {}
	for probe_id: int in script_map.probe_to_line:
		var ln: int = script_map.probe_to_line[probe_id]
		if not line_probes.has(ln):
			line_probes[ln] = []
		line_probes[ln].append(probe_id)

	for branch_info in script_map.branches:
		var hit_count := 0
		if branch_info.probe_id < hits.size():
			hit_count = hits[branch_info.probe_id]

		# For match patterns and else branches, the probe is allocated but
		# not directly recorded (compound statements can't have code injected).
		# Derive hits from the first executable body line after the branch.
		var line_info = script_map.lines.get(branch_info.line_number)
		if line_info != null and hit_count == 0:
			if line_info.type == GUTCheckScriptMap.LineType.BRANCH_PATTERN \
					or line_info.type == GUTCheckScriptMap.LineType.BRANCH_ELSE:
				hit_count = _derive_body_hits(branch_info.line_number, script_map, hits, line_probes)

		lines.append("BRDA:%d,%d,%d,%d" % [
			branch_info.line_number, branch_info.block_id,
			branch_info.branch_id, hit_count])
		branches_found += 1
		if hit_count > 0:
			branches_hit += 1

	lines.append("BRF:%d" % branches_found)
	lines.append("BRH:%d" % branches_hit)


## Derive hit count for a compound branch (else, match pattern) by looking
## at the first executable line in its body.
func _derive_body_hits(branch_line: int, script_map, hits: PackedInt32Array, line_probes: Dictionary) -> int:
	var pattern_line := branch_line
	var exec_lines: Array[int] = script_map.get_executable_lines_sorted()
	for ln in exec_lines:
		if ln > pattern_line:
			if line_probes.has(ln):
				var pid: int = line_probes[ln][0]
				if pid < hits.size():
					return hits[pid]
			break
	return 0


func _emit_line_records(lines: PackedStringArray, script_map, hits: PackedInt32Array) -> void:
	var lines_found := 0
	var lines_hit := 0

	# Build line_num -> [probe_ids] mapping for multi-statement lines
	var line_probes: Dictionary = {}  # line_num -> Array[int]
	for probe_id: int in script_map.probe_to_line:
		var line_num: int = script_map.probe_to_line[probe_id]
		if not line_probes.has(line_num):
			line_probes[line_num] = []
		line_probes[line_num].append(probe_id)

	var executable_lines = script_map.get_executable_lines_sorted()
	for line_num in executable_lines:
		# For multi-statement lines, use the minimum hit count across all
		# probes (conservative: all statements must be hit for full coverage)
		var hit_count := 0
		if line_probes.has(line_num):
			var probes: Array = line_probes[line_num]
			hit_count = hits[probes[0]] if probes[0] < hits.size() else 0
			for j in range(1, probes.size()):
				if probes[j] < hits.size():
					hit_count = mini(hit_count, hits[probes[j]])

		lines.append("DA:%d,%d" % [line_num, hit_count])
		lines_found += 1
		if hit_count > 0:
			lines_hit += 1

	lines.append("LF:%d" % lines_found)
	lines.append("LH:%d" % lines_hit)


func _get_function_hit_count(func_info, script_map, hits: PackedInt32Array) -> int:
	# A function's hit count is the hit count of its first executable line's first probe
	var exec_lines = script_map.get_executable_lines_sorted()
	for line_num in exec_lines:
		if line_num >= func_info.start_line and (func_info.end_line == -1 or line_num <= func_info.end_line):
			for probe_id: int in script_map.probe_to_line:
				if script_map.probe_to_line[probe_id] == line_num:
					if probe_id < hits.size():
						return hits[probe_id]
					return 0
			break
	return 0


func _qualified_func_name(func_info) -> String:
	if func_info.cls_name != "":
		return "%s.%s" % [func_info.cls_name, func_info.name]
	return func_info.name


func _to_absolute_path(res_path: String) -> String:
	if Engine.is_editor_hint() or not res_path.begins_with("res://"):
		return res_path
	return ProjectSettings.globalize_path(res_path)


func _write_file(path: String, content: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK
