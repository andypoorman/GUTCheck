class_name GUTCheckCoberturaExporter
## Generates Cobertura XML from coverage data collected by GUTCheckCollector.
##
## Cobertura DTD: http://cobertura.sourceforge.net/xml/coverage-04.dtd
## Compatible with Codecov, GitHub Actions, and other CI tools.


## Export coverage data to a Cobertura XML file. Returns OK on success.
func export_cobertura(output_path: String, source_root: String = "") -> int:
	var content := generate_cobertura(source_root)
	return _write_file(output_path, content)


## Generate the Cobertura XML string without writing to disk.
func generate_cobertura(source_root: String = "") -> String:
	var script_paths := GUTCheckCollector.get_script_paths()
	var all_hits := GUTCheckCollector.get_hits()
	var all_maps := GUTCheckCollector.get_script_maps()

	var total_lines_valid := 0
	var total_lines_covered := 0
	var total_branches_valid := 0
	var total_branches_covered := 0

	# Group scripts by directory (package)
	var packages: Dictionary = {}  # dir_path -> Array of {sid, path, hits, map}
	for sid: int in script_paths:
		var path: String = script_paths[sid]
		var hits: PackedInt32Array = all_hits.get(sid, PackedInt32Array())
		var script_map = all_maps.get(sid)
		if script_map == null:
			continue
		var context := GUTCheckCoverageComputer.build_script_context(script_map, hits)
		var stats := _compute_script_stats(hits, context)

		var dir := path.get_base_dir()
		if not packages.has(dir):
			packages[dir] = []
		packages[dir].append({
			"sid": sid,
			"path": path,
			"hits": hits,
			"map": script_map,
			"context": context,
			"stats": stats,
		})

	# Build XML
	var xml := PackedStringArray()
	xml.append('<?xml version="1.0" ?>')
	xml.append('<!DOCTYPE coverage SYSTEM "http://cobertura.sourceforge.net/xml/coverage-04.dtd">')

	# First pass: compute totals
	for dir: String in packages:
		for entry in packages[dir]:
			var stats: Dictionary = entry.stats
			total_lines_valid += stats.lines_valid
			total_lines_covered += stats.lines_covered
			total_branches_valid += stats.branches_valid
			total_branches_covered += stats.branches_covered

	var line_rate := _rate(total_lines_covered, total_lines_valid)
	var branch_rate := _rate(total_branches_covered, total_branches_valid)
	var timestamp := int(Time.get_unix_time_from_system())

	xml.append('<coverage line-rate="%s" branch-rate="%s" lines-covered="%d" lines-valid="%d" branches-covered="%d" branches-valid="%d" complexity="0" version="1.0" timestamp="%d">' % [
		line_rate, branch_rate, total_lines_covered, total_lines_valid,
		total_branches_covered, total_branches_valid, timestamp])

	if source_root != "":
		xml.append('  <sources>')
		xml.append('    <source>%s</source>' % _escape_xml(source_root))
		xml.append('  </sources>')

	xml.append('  <packages>')

	# Emit packages
	var pkg_dirs := packages.keys()
	pkg_dirs.sort()
	for dir: String in pkg_dirs:
		var entries: Array = packages[dir]
		var pkg_lines_valid := 0
		var pkg_lines_covered := 0
		var pkg_branches_valid := 0
		var pkg_branches_covered := 0

		for entry in entries:
			var stats: Dictionary = entry.stats
			pkg_lines_valid += stats.lines_valid
			pkg_lines_covered += stats.lines_covered
			pkg_branches_valid += stats.branches_valid
			pkg_branches_covered += stats.branches_covered

		var pkg_name := dir.replace("res://", "").replace("/", ".")
		if pkg_name == "":
			pkg_name = "."

		xml.append('    <package name="%s" line-rate="%s" branch-rate="%s" complexity="0">' % [
			_escape_xml(pkg_name),
			_rate(pkg_lines_covered, pkg_lines_valid),
			_rate(pkg_branches_covered, pkg_branches_valid)])
		xml.append('      <classes>')

		for entry in entries:
			_emit_class(xml, entry.path, entry.map, entry.hits, entry.context, entry.stats)

		xml.append('      </classes>')
		xml.append('    </package>')

	xml.append('  </packages>')
	xml.append('</coverage>')

	return "\n".join(xml) + "\n"


func _emit_class(xml: PackedStringArray, path: String, script_map, hits: PackedInt32Array, context: Dictionary, stats: Dictionary) -> void:
	var class_name_str := path.get_file().get_basename()
	var filename := _to_relative_path(path)

	xml.append('        <class name="%s" filename="%s" line-rate="%s" branch-rate="%s" complexity="0">' % [
		_escape_xml(class_name_str), _escape_xml(filename),
		_rate(stats.lines_covered, stats.lines_valid),
		_rate(stats.branches_covered, stats.branches_valid)])

	# Methods
	xml.append('          <methods>')
	for func_info in script_map.functions:
		_emit_method(xml, func_info, script_map, hits, context)
	xml.append('          </methods>')

	# All lines
	xml.append('          <lines>')
	_emit_lines(xml, script_map, hits, context)
	xml.append('          </lines>')

	xml.append('        </class>')


func _emit_method(xml: PackedStringArray, func_info, script_map, hits: PackedInt32Array, context: Dictionary) -> void:
	var name: String = func_info.name
	if func_info.cls_name != "":
		name = "%s.%s" % [func_info.cls_name, func_info.name]

	var exec_lines: Array[int] = context.exec_lines
	var line_probes: Dictionary = context.line_probes
	var branch_line_hits: Dictionary = context.branch_line_hits

	xml.append('            <method name="%s" signature="" line-rate="0" branch-rate="0" complexity="0">' % _escape_xml(name))
	xml.append('              <lines>')

	for line_num in exec_lines:
		if line_num >= func_info.start_line and (func_info.end_line == -1 or line_num <= func_info.end_line):
			var hit_count := GUTCheckCoverageComputer.get_line_hit_count(
				line_num, line_probes, hits, branch_line_hits)
			var branch_data := _get_branch_data_for_line(line_num, script_map, hits, context)
			_emit_line_element(xml, line_num, hit_count, branch_data, "                ")

	xml.append('              </lines>')
	xml.append('            </method>')


func _emit_lines(xml: PackedStringArray, script_map, hits: PackedInt32Array, context: Dictionary) -> void:
	var line_probes: Dictionary = context.line_probes
	var branch_line_hits: Dictionary = context.branch_line_hits
	var exec_lines: Array[int] = context.exec_lines

	for line_num in exec_lines:
		var hit_count := GUTCheckCoverageComputer.get_line_hit_count(
			line_num, line_probes, hits, branch_line_hits)
		var branch_data := _get_branch_data_for_line(line_num, script_map, hits, context)
		_emit_line_element(xml, line_num, hit_count, branch_data, "            ")


func _emit_line_element(xml: PackedStringArray, line_num: int, hit_count: int, branch_data: Dictionary, indent: String) -> void:
	if branch_data.is_empty():
		xml.append('%s<line number="%d" hits="%d" branch="false"/>' % [indent, line_num, hit_count])
	else:
		var covered: int = branch_data.covered
		var total: int = branch_data.total
		var pct := int(float(covered) / float(total) * 100.0) if total > 0 else 0
		xml.append('%s<line number="%d" hits="%d" branch="true" condition-coverage="%d%% (%d/%d)">' % [
			indent, line_num, hit_count, pct, covered, total])
		xml.append('%s  <conditions>' % indent)
		for i in range(branch_data.conditions.size()):
			var cond: Dictionary = branch_data.conditions[i]
			xml.append('%s    <condition number="%d" type="jump" coverage="%d%%"/>' % [
				indent, i, cond.coverage_pct])
		xml.append('%s  </conditions>' % indent)
		xml.append('%s</line>' % indent)


func _get_branch_data_for_line(line_num: int, script_map, hits: PackedInt32Array, context: Dictionary) -> Dictionary:
	var line_branches: Array = script_map.get_branches_for_line(line_num)
	if line_branches.size() == 0:
		return {}

	var total := line_branches.size()
	var covered := 0
	var conditions: Array = []

	for b in line_branches:
		var h := GUTCheckCoverageComputer.get_branch_hit_count(
			b, script_map, hits, context)

		if h > 0:
			covered += 1
		conditions.append({"coverage_pct": 100 if h > 0 else 0})

	return {"total": total, "covered": covered, "conditions": conditions}


func _compute_script_stats(hits: PackedInt32Array, context: Dictionary) -> Dictionary:
	var line_probes: Dictionary = context.line_probes
	var branch_line_hits: Dictionary = context.branch_line_hits
	var exec_lines: Array[int] = context.exec_lines
	var lines_valid: int = exec_lines.size()
	var lines_covered := 0
	for ln in exec_lines:
		if GUTCheckCoverageComputer.get_line_hit_count(ln, line_probes, hits, branch_line_hits) > 0:
			lines_covered += 1

	var script_map = context.get("script_map")
	var branches_valid: int = script_map.branches.size()
	var branches_covered := 0
	for b in script_map.branches:
		if GUTCheckCoverageComputer.get_branch_hit_count(b, script_map, hits, context) > 0:
			branches_covered += 1

	return {
		"lines_valid": lines_valid,
		"lines_covered": lines_covered,
		"branches_valid": branches_valid,
		"branches_covered": branches_covered,
	}


func _rate(covered: int, total: int) -> String:
	if total == 0:
		return "0"
	return "%.4f" % (float(covered) / float(total))


func _to_relative_path(res_path: String) -> String:
	if res_path.begins_with("res://"):
		return res_path.substr(6)
	return res_path


func _escape_xml(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")


func _write_file(path: String, content: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK
