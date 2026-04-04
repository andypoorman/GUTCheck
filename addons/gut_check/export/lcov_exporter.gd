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
	var line_probes: Dictionary = GUTCheckCoverageComputer.build_line_probes(script_map)

	for branch_info in script_map.branches:
		var hit_count := GUTCheckCoverageComputer.get_branch_hit_count(
			branch_info, script_map, hits, line_probes)

		lines.append("BRDA:%d,%d,%d,%d" % [
			branch_info.line_number, branch_info.block_id,
			branch_info.branch_id, hit_count])
		branches_found += 1
		if hit_count > 0:
			branches_hit += 1

	lines.append("BRF:%d" % branches_found)
	lines.append("BRH:%d" % branches_hit)


func _emit_line_records(lines: PackedStringArray, script_map, hits: PackedInt32Array) -> void:
	var lines_found := 0
	var lines_hit := 0
	var line_probes: Dictionary = GUTCheckCoverageComputer.build_line_probes(script_map)
	var branch_line_hits: Dictionary = GUTCheckCoverageComputer.build_branch_line_hits(script_map, hits)

	var executable_lines = script_map.get_executable_lines_sorted()
	for line_num in executable_lines:
		var hit_count := GUTCheckCoverageComputer.get_line_hit_count(
			line_num, line_probes, hits, branch_line_hits)
		lines.append("DA:%d,%d" % [line_num, hit_count])
		lines_found += 1
		if hit_count > 0:
			lines_hit += 1

	lines.append("LF:%d" % lines_found)
	lines.append("LH:%d" % lines_hit)


func _get_function_hit_count(func_info, script_map, hits: PackedInt32Array) -> int:
	# A function's hit count is the hit count of its first executable line.
	var line_probes: Dictionary = GUTCheckCoverageComputer.build_line_probes(script_map)
	var branch_line_hits: Dictionary = GUTCheckCoverageComputer.build_branch_line_hits(script_map, hits)
	var exec_lines = script_map.get_executable_lines_sorted()
	for line_num in exec_lines:
		if line_num >= func_info.start_line and (func_info.end_line == -1 or line_num <= func_info.end_line):
			return GUTCheckCoverageComputer.get_line_hit_count(
				line_num, line_probes, hits, branch_line_hits)
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
