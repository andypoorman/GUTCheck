class_name GUTCheckInstrumenter
## Transforms GDScript source code by injecting coverage probes.
##
## Probes are injected in a way that preserves line numbers:
## - Simple executable lines: prepend GUTCheckCollector.hit(sid, pid); via semicolon
## - if/elif/while conditions: wrap with GUTCheckCollector.br(sid, pid, <cond>)
## - for iterables: wrap with GUTCheckCollector.rng(sid, pid, <iter>)
## - match expressions: wrap with GUTCheckCollector.br(sid, pid, <expr>)


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

	# Build a line_number -> probe_id lookup from the script map
	var line_to_probe: Dictionary = {}
	for probe_id: int in script_map.probe_to_line:
		var line_num: int = script_map.probe_to_line[probe_id]
		line_to_probe[line_num] = probe_id

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

		# Class-body declarations (var, const, signal) can't have executable
		# statements prepended — even in inner classes. Skip plain EXECUTABLE
		# lines at indent 0 (top-level class body) or that are outside any
		# function (inner class body). Branch/loop types are not skipped even
		# with empty function_name, as that can be a scope-tracking artifact.
		var indent = _get_indent(line)
		if indent.length() == 0:
			result_lines[i] = line
			continue
		if line_info.function_name.is_empty() and line_info.type == GUTCheckScriptMap.LineType.EXECUTABLE:
			result_lines[i] = line
			continue

		var branch_probes: Array = line_to_branches.get(line_num, [])
		result_lines[i] = _instrument_line(
			line, line_info.type, script_id, first_probe, line_info.statement_count, branch_probes)

	var result := GUTCheckInstrumentResult.new()
	result.source = "\n".join(result_lines)
	result.script_map = script_map
	result.probe_count = script_map.probe_count
	return result


func _instrument_line(line: String, line_type: GUTCheckScriptMap.LineType, sid: int, pid: int, stmt_count: int = 1, branch_probes: Array = []) -> String:
	var indent := _get_indent(line)
	var content := line.substr(indent.length())

	match line_type:
		GUTCheckScriptMap.LineType.EXECUTABLE:
			if stmt_count > 1:
				return indent + _instrument_semicolon_statements(content, sid, pid)
			return indent + "GUTCheckCollector.hit(%d,%d);%s" % [sid, pid, content]

		GUTCheckScriptMap.LineType.BRANCH_ELSE, \
		GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR:
			# Compound statements — can't prepend with semicolons.
			# Their body lines will be instrumented instead.
			# For else: branch probe is recorded via hit() on the first body line.
			return line

		GUTCheckScriptMap.LineType.BRANCH_PATTERN:
			# Match patterns can't have code prepended. We inject a hit()
			# call for the branch probe if we have one assigned.
			if branch_probes.size() > 0:
				return indent + _inject_match_pattern_probe(content, sid, branch_probes[0].probe_id)
			return line

		GUTCheckScriptMap.LineType.BRANCH_IF:
			return indent + _wrap_condition_br2(content, "if", sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.BRANCH_ELIF:
			return indent + _wrap_condition_br2(content, "elif", sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.LOOP_WHILE:
			return indent + _wrap_condition_br2(content, "while", sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.LOOP_FOR:
			return indent + _wrap_for_br2(content, sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.BRANCH_MATCH:
			return indent + _wrap_match(content, sid, pid)

		GUTCheckScriptMap.LineType.FUNC_DEF, \
		GUTCheckScriptMap.LineType.CLASS_DEF:
			# func and class are compound statements — can't prepend with semicolons.
			# Coverage is tracked via the first executable line in the body.
			return line

		_:
			return line


func _instrument_semicolon_statements(content: String, sid: int, first_pid: int) -> String:
	## Split content on semicolons (respecting strings and brackets) and
	## inject a probe before each statement.
	var statements: Array[String] = []
	var current := ""
	var depth := 0
	var in_string := false
	var string_char := ""

	for i in range(content.length()):
		var c := content[i]

		if in_string:
			current += c
			if c == "\\" and not in_string:
				if i + 1 < content.length():
					current += content[i + 1]
				continue
			if c == string_char:
				in_string = false
			continue

		if c == '"' or c == "'":
			in_string = true
			string_char = c
			current += c
			continue

		if c == "(" or c == "[" or c == "{":
			depth += 1
			current += c
		elif c == ")" or c == "]" or c == "}":
			depth = maxi(0, depth - 1)
			current += c
		elif c == ";" and depth == 0:
			statements.append(current.strip_edges())
			current = ""
		else:
			current += c

	if not current.strip_edges().is_empty():
		statements.append(current.strip_edges())

	# Inject a probe before each statement
	var parts: PackedStringArray = []
	for s_idx in range(statements.size()):
		var probe := "GUTCheckCollector.hit(%d,%d)" % [sid, first_pid + s_idx]
		parts.append("%s;%s" % [probe, statements[s_idx]])

	return "; ".join(parts)


func _wrap_condition(content: String, keyword: String, sid: int, pid: int) -> String:
	var kw_end := keyword.length()
	while kw_end < content.length() and content[kw_end] == " ":
		kw_end += 1

	var colon_pos := _find_block_colon(content)
	if colon_pos == -1:
		return content

	var condition := content.substr(kw_end, colon_pos - kw_end).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	return "%s GUTCheckCollector.br(%d,%d,%s):%s" % [keyword, sid, pid, condition, after_colon]


## Wrap a condition with br2() for branch coverage. Falls back to br() if
## no branch probes are available.
func _wrap_condition_br2(content: String, keyword: String, sid: int, pid: int, branch_probes: Array) -> String:
	var kw_end := keyword.length()
	while kw_end < content.length() and content[kw_end] == " ":
		kw_end += 1

	var colon_pos := _find_block_colon(content)
	if colon_pos == -1:
		return content

	var condition := content.substr(kw_end, colon_pos - kw_end).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	# Find true/false branch probes for this line
	var true_pid := -1
	var false_pid := -1
	for bp in branch_probes:
		if bp.is_true_branch:
			true_pid = bp.probe_id
		else:
			false_pid = bp.probe_id

	if true_pid >= 0 and false_pid >= 0:
		return "%s GUTCheckCollector.br2(%d,%d,%d,%s):%s" % [keyword, sid, true_pid, false_pid, condition, after_colon]

	# Fallback to regular br() if branch probes aren't available
	return "%s GUTCheckCollector.br(%d,%d,%s):%s" % [keyword, sid, pid, condition, after_colon]


## Wrap a for-loop iterable with rng() and also record branch probes if available.
func _wrap_for_br2(content: String, sid: int, pid: int, branch_probes: Array) -> String:
	var in_pos := _find_for_in(content)
	if in_pos == -1:
		return content

	var before_in := content.substr(0, in_pos)
	var after_in_start := in_pos + 4

	var colon_pos := _find_block_colon(content)
	if colon_pos == -1:
		return content

	var iterable := content.substr(after_in_start, colon_pos - after_in_start).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	# Find true/false branch probes for this line
	var true_pid := -1
	var false_pid := -1
	for bp in branch_probes:
		if bp.is_true_branch:
			true_pid = bp.probe_id
		else:
			false_pid = bp.probe_id

	if true_pid >= 0 and false_pid >= 0:
		# Use br2rng which records true/false based on whether iterable is non-empty
		return "%s in GUTCheckCollector.br2rng(%d,%d,%d,%s):%s" % [before_in, sid, true_pid, false_pid, iterable, after_colon]

	# Fallback to regular rng()
	return "%s in GUTCheckCollector.rng(%d,%d,%s):%s" % [before_in, sid, pid, iterable, after_colon]


## Inject a hit() probe into a match pattern line. Match patterns look like:
##   1:       ->  1: (can't inject before colon)
## So we inject after the colon: "1: GUTCheckCollector.hit(sid,pid);" (inline body trick)
## Actually, match patterns with body blocks can't have inline code injected
## safely. Instead, we leave patterns uninstrumented and track their body lines.
## However, for branch tracking we need to know which arm was entered.
## We prepend a hit after the pattern colon if there's an inline expression,
## or accept that body-line probes serve as the branch-hit signal.
func _inject_match_pattern_probe(_content: String, _sid: int, _pid: int) -> String:
	# Match patterns have their bodies on subsequent indented lines.
	# We can't safely inject code into the pattern line itself because
	# "1:" is a syntactic construct, not an expression. The branch probe
	# is instead tracked by checking whether any body line was hit.
	# Return unchanged — the LCOV exporter will derive hits from body lines.
	return _content


func _wrap_for(content: String, sid: int, pid: int) -> String:
	var in_pos := _find_for_in(content)
	if in_pos == -1:
		return content

	var before_in := content.substr(0, in_pos)
	var after_in_start := in_pos + 4

	var colon_pos := _find_block_colon(content)
	if colon_pos == -1:
		return content

	var iterable := content.substr(after_in_start, colon_pos - after_in_start).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	return "%s in GUTCheckCollector.rng(%d,%d,%s):%s" % [before_in, sid, pid, iterable, after_colon]


func _wrap_match(content: String, sid: int, pid: int) -> String:
	var kw_end := 5
	while kw_end < content.length() and content[kw_end] == " ":
		kw_end += 1

	var colon_pos := _find_block_colon(content)
	if colon_pos == -1:
		return content

	var expr := content.substr(kw_end, colon_pos - kw_end).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	return "match GUTCheckCollector.br(%d,%d,%s):%s" % [sid, pid, expr, after_colon]


func _find_block_colon(content: String) -> int:
	var depth := 0
	var in_string := false
	var string_char := ""
	var last_colon := -1

	for i in range(content.length()):
		var c := content[i]

		if in_string:
			if c == "\\" and i + 1 < content.length():
				continue
			if c == string_char:
				in_string = false
			continue

		if c == '"' or c == "'":
			in_string = true
			string_char = c
			continue

		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif c == ":" and depth == 0:
			last_colon = i

	return last_colon


func _find_for_in(content: String) -> int:
	var pos := 4
	var depth := 0
	var in_string := false
	var string_char := ""

	while pos < content.length() - 3:
		var c := content[pos]

		if in_string:
			if c == "\\" and pos + 1 < content.length():
				pos += 2
				continue
			if c == string_char:
				in_string = false
			pos += 1
			continue

		if c == '"' or c == "'":
			in_string = true
			string_char = c
			pos += 1
			continue

		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif depth == 0 and content.substr(pos, 4) == " in ":
			return pos

		pos += 1

	return -1


func _get_indent(line: String) -> String:
	var i := 0
	while i < line.length() and (line[i] == "\t" or line[i] == " "):
		i += 1
	return line.substr(0, i)
