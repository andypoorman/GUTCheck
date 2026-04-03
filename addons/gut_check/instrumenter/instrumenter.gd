class_name GUTCheckInstrumenter
## Transforms GDScript source code by injecting coverage probes.
## Pure string manipulation is delegated to GUTCheckProbeInjector.


var _tokenizer = GUTCheckTokenizer.new()
var _classifier = GUTCheckLineClassifier.new()


## Instrument a GDScript source string. Returns a GUTCheckInstrumentResult
## with the modified source and metadata.
func instrument(source: String, script_id: int, script_path: String = "") -> GUTCheckInstrumentResult:
	var tokens = _tokenizer.tokenize(source)
	var script_map = _classifier.classify(tokens, script_path)

	var lines := source.split("\n")
	var result_lines: PackedStringArray = []
	result_lines.resize(lines.size())

	# Build reverse lookup: line_num -> first probe_id for that line
	var line_to_first_probe: Dictionary = {}
	for probe_id: int in script_map.probe_to_line:
		var ln: int = script_map.probe_to_line[probe_id]
		if not line_to_first_probe.has(ln) or probe_id < line_to_first_probe[ln]:
			line_to_first_probe[ln] = probe_id

	# Build branch probe lookup: line_num -> [BranchInfo, ...]
	var line_to_branches: Dictionary = {}
	for branch_info in script_map.branches:
		var ln: int = branch_info.line_number
		if not line_to_branches.has(ln):
			line_to_branches[ln] = []
		line_to_branches[ln].append(branch_info)

	for i in range(lines.size()):
		var line_num := i + 1
		var line := lines[i]

		if not line_to_first_probe.has(line_num):
			result_lines[i] = line
			continue

		var first_probe: int = line_to_first_probe[line_num]
		var line_info = script_map.lines.get(line_num)
		if line_info == null:
			result_lines[i] = line
			continue

		var indent = GUTCheckProbeInjector.get_indent(line)
		if indent.length() == 0:
			result_lines[i] = line
			continue
		if line_info.function_name.is_empty() and line_info.type == GUTCheckScriptMap.LineType.EXECUTABLE:
			result_lines[i] = line
			continue

		var branch_probes: Array = line_to_branches.get(line_num, [])
		result_lines[i] = GUTCheckProbeInjector.instrument_line(
			line, line_info.type, script_id, first_probe, line_info.statement_count, branch_probes)

	var result := GUTCheckInstrumentResult.new()
	result.source = "\n".join(result_lines)
	result.script_map = script_map
	result.probe_count = script_map.probe_count
	return result
