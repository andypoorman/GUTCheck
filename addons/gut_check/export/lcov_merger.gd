class_name GUTCheckLcovMerger
## Merges multiple LCOV tracefiles into a single combined tracefile.
##
## Useful for combining coverage from parallel test runs (e.g., unit +
## integration suites run separately). Equivalent to `lcov --add-tracefile`
## but implemented in pure GDScript so no external tools are needed.
##
## Usage:
##   var merger = GUTCheckLcovMerger.new()
##   merger.add_file("res://coverage_unit.lcov")
##   merger.add_file("res://coverage_integration.lcov")
##   merger.write_merged("res://coverage.lcov")


## Parsed records per source file. Key: absolute SF path.
## Value: { "functions": {name: {line, hits}}, "branches": [{line,block,branch,hits}],
##          "lines": {line_num: hits} }
var _records: Dictionary = {}


## Add an LCOV tracefile to the merge set.
func add_file(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GUTCheckLcovMerger: Could not open: %s" % path)
		return ERR_FILE_NOT_FOUND
	var content := file.get_as_text()
	file.close()
	add_content(content)
	return OK


## Add raw LCOV content string to the merge set.
func add_content(content: String) -> void:
	var current_sf: String = ""
	for line in content.split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("SF:"):
			current_sf = line.substr(3)
			if not _records.has(current_sf):
				_records[current_sf] = {
					"functions": {},  # name -> {line, hits}
					"branches": {},   # "line,block,branch" -> hits
					"lines": {},      # line_num -> hits
				}

		elif line.begins_with("FN:"):
			# FN:<line>,<name>
			var parts: PackedStringArray = line.substr(3).split(",", true, 2)
			if parts.size() >= 2 and _records.has(current_sf):
				var fn_name: String = parts[1]
				if not _records[current_sf].functions.has(fn_name):
					_records[current_sf].functions[fn_name] = {
						"line": parts[0].to_int(),
						"hits": 0,
					}

		elif line.begins_with("FNDA:"):
			# FNDA:<hits>,<name>
			var parts: PackedStringArray = line.substr(5).split(",", true, 2)
			if parts.size() >= 2 and _records.has(current_sf):
				var fn_name: String = parts[1]
				var hits: int = parts[0].to_int()
				if _records[current_sf].functions.has(fn_name):
					_records[current_sf].functions[fn_name].hits += hits
				else:
					_records[current_sf].functions[fn_name] = {
						"line": 0,
						"hits": hits,
					}

		elif line.begins_with("BRDA:"):
			# BRDA:<line>,<block>,<branch>,<hits>
			var parts: PackedStringArray = line.substr(5).split(",")
			if parts.size() >= 4 and _records.has(current_sf):
				var key := "%s,%s,%s" % [parts[0], parts[1], parts[2]]
				var hits: int = parts[3].to_int()
				if _records[current_sf].branches.has(key):
					_records[current_sf].branches[key] += hits
				else:
					_records[current_sf].branches[key] = hits

		elif line.begins_with("DA:"):
			# DA:<line>,<hits>
			var parts: PackedStringArray = line.substr(3).split(",")
			if parts.size() >= 2 and _records.has(current_sf):
				var ln: int = parts[0].to_int()
				var hits: int = parts[1].to_int()
				if _records[current_sf].lines.has(ln):
					_records[current_sf].lines[ln] += hits
				else:
					_records[current_sf].lines[ln] = hits

		# TN, FNF, FNH, BRF, BRH, LF, LH, end_of_record — skip (recomputed)


## Generate merged LCOV content string.
func generate_merged() -> String:
	var output: PackedStringArray = []

	# Sort source files for deterministic output
	var sorted_sfs: Array = _records.keys()
	sorted_sfs.sort()

	for sf: String in sorted_sfs:
		var rec: Dictionary = _records[sf]
		output.append("TN:")
		output.append("SF:%s" % sf)

		# Function records
		var fn_found := 0
		var fn_hit := 0
		var fn_names: Array = rec.functions.keys()
		fn_names.sort()
		for fn_name: String in fn_names:
			var fn: Dictionary = rec.functions[fn_name]
			if fn.line > 0:
				output.append("FN:%d,%s" % [fn.line, fn_name])
		for fn_name: String in fn_names:
			var fn: Dictionary = rec.functions[fn_name]
			output.append("FNDA:%d,%s" % [fn.hits, fn_name])
			fn_found += 1
			if fn.hits > 0:
				fn_hit += 1
		output.append("FNF:%d" % fn_found)
		output.append("FNH:%d" % fn_hit)

		# Branch records
		var br_found := 0
		var br_hit := 0
		var br_keys: Array = rec.branches.keys()
		br_keys.sort()
		for key: String in br_keys:
			var hits: int = rec.branches[key]
			output.append("BRDA:%s,%d" % [key, hits])
			br_found += 1
			if hits > 0:
				br_hit += 1
		if br_found > 0:
			output.append("BRF:%d" % br_found)
			output.append("BRH:%d" % br_hit)

		# Line records
		var ln_found := 0
		var ln_hit := 0
		var sorted_lines: Array = rec.lines.keys()
		sorted_lines.sort()
		for ln: int in sorted_lines:
			var hits: int = rec.lines[ln]
			output.append("DA:%d,%d" % [ln, hits])
			ln_found += 1
			if hits > 0:
				ln_hit += 1
		output.append("LF:%d" % ln_found)
		output.append("LH:%d" % ln_hit)

		output.append("end_of_record")

	return "\n".join(output) + "\n" if output.size() > 0 else ""


## Write merged coverage to a file. Returns OK on success.
func write_merged(output_path: String) -> int:
	var content := generate_merged()
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK


## Clear all parsed records.
func clear() -> void:
	_records.clear()
