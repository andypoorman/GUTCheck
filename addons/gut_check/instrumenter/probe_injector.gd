class_name GUTCheckProbeInjector
## Pure string-manipulation functions for injecting coverage probes into
## GDScript source lines. Every method is static — no instance state needed.


## Dispatch a single source line to the appropriate probe-injection wrapper.
static func instrument_line(line: String, line_type: GUTCheckScriptMap.LineType, sid: int, pid: int, stmt_count: int = 1, branch_probes: Array = []) -> String:
	var indent := get_indent(line)
	var content := line.substr(indent.length())

	match line_type:
		GUTCheckScriptMap.LineType.EXECUTABLE:
			if stmt_count > 1:
				return indent + instrument_semicolon_statements(content, sid, pid)
			return indent + "GUTCheckCollector.hit(%d,%d);%s" % [sid, pid, content]

		GUTCheckScriptMap.LineType.BRANCH_ELSE, \
		GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR:
			return line

		GUTCheckScriptMap.LineType.BRANCH_PATTERN:
			if branch_probes.size() > 0:
				return indent + inject_match_pattern_probe(content, sid, branch_probes[0].probe_id)
			return line

		GUTCheckScriptMap.LineType.BRANCH_IF:
			return indent + wrap_condition_br2(content, "if", sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.BRANCH_ELIF:
			return indent + wrap_condition_br2(content, "elif", sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.LOOP_WHILE:
			return indent + wrap_condition_br2(content, "while", sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.LOOP_FOR:
			return indent + wrap_for_br2(content, sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.BRANCH_MATCH:
			return indent + wrap_match(content, sid, pid)

		GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY:
			return indent + wrap_ternary(content, sid, pid, branch_probes)

		GUTCheckScriptMap.LineType.FUNC_DEF, \
		GUTCheckScriptMap.LineType.CLASS_DEF:
			return line

		_:
			return line


## Split content on semicolons (respecting strings and brackets) and
## inject a probe before each statement.
static func instrument_semicolon_statements(content: String, sid: int, first_pid: int) -> String:
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

	var parts: PackedStringArray = []
	for s_idx in range(statements.size()):
		var probe := "GUTCheckCollector.hit(%d,%d)" % [sid, first_pid + s_idx]
		parts.append("%s;%s" % [probe, statements[s_idx]])

	return "; ".join(parts)


## Wrap a condition with br2() for branch coverage.
static func wrap_condition_br2(content: String, keyword: String, sid: int, pid: int, branch_probes: Array) -> String:
	var kw_end := keyword.length()
	while kw_end < content.length() and content[kw_end] == " ":
		kw_end += 1

	var colon_pos := find_block_colon(content)
	if colon_pos == -1:
		return content

	var condition := content.substr(kw_end, colon_pos - kw_end).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	var true_pid := -1
	var false_pid := -1
	for bp in branch_probes:
		if bp.is_true_branch:
			true_pid = bp.probe_id
		else:
			false_pid = bp.probe_id

	if true_pid >= 0 and false_pid >= 0:
		return "%s GUTCheckCollector.hit_br2(%d,%d,%d,%d,%s):%s" % [keyword, sid, pid, true_pid, false_pid, condition, after_colon]

	return "%s GUTCheckCollector.br(%d,%d,%s):%s" % [keyword, sid, pid, condition, after_colon]


## Wrap a for-loop iterable with branch probes if available.
static func wrap_for_br2(content: String, sid: int, pid: int, branch_probes: Array) -> String:
	var in_pos := find_for_in(content)
	if in_pos == -1:
		return content

	var before_in := content.substr(0, in_pos)
	var after_in_start := in_pos + 4

	var colon_pos := find_block_colon(content)
	if colon_pos == -1:
		return content

	var iterable := content.substr(after_in_start, colon_pos - after_in_start).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	var true_pid := -1
	var false_pid := -1
	for bp in branch_probes:
		if bp.is_true_branch:
			true_pid = bp.probe_id
		else:
			false_pid = bp.probe_id

	if true_pid >= 0 and false_pid >= 0:
		return "%s in GUTCheckCollector.hit_br2rng(%d,%d,%d,%d,%s):%s" % [before_in, sid, pid, true_pid, false_pid, iterable, after_colon]

	return "%s in GUTCheckCollector.rng(%d,%d,%s):%s" % [before_in, sid, pid, iterable, after_colon]


## Wrap a match expression with br().
static func wrap_match(content: String, sid: int, pid: int) -> String:
	var kw_end := 5
	while kw_end < content.length() and content[kw_end] == " ":
		kw_end += 1

	var colon_pos := find_block_colon(content)
	if colon_pos == -1:
		return content

	var expr := content.substr(kw_end, colon_pos - kw_end).strip_edges()
	var after_colon := content.substr(colon_pos + 1)

	return "match GUTCheckCollector.br(%d,%d,%s):%s" % [sid, pid, expr, after_colon]


## Wrap ternary-if conditions with br2() for branch coverage.
## Input:  var x = "yes" if condition else "no"
## Output: GUTCheckCollector.hit(sid,pid);var x = "yes" if GUTCheckCollector.br2(sid,tpid,fpid,condition) else "no"
static func wrap_ternary(content: String, sid: int, pid: int, branch_probes: Array) -> String:
	# Find all ternary if/else pairs (positions in the content string)
	var ternary_ifs := find_ternary_if_positions(content)

	if ternary_ifs.size() == 0:
		# Fallback: no ternaries found at string level, treat as plain executable
		return "GUTCheckCollector.hit(%d,%d);%s" % [sid, pid, content]

	# Process ternaries right-to-left so earlier positions stay stable
	var result := content
	var bp_idx := (mini(ternary_ifs.size(), branch_probes.size() / 2) - 1) * 2

	for t_idx in range(ternary_ifs.size() - 1, -1, -1):
		if bp_idx < 0:
			break
		var if_pos: int = ternary_ifs[t_idx][0]
		var else_pos: int = ternary_ifs[t_idx][1]

		var true_pid := -1
		var false_pid := -1
		for bp in branch_probes:
			if bp.is_true_branch and bp.block_id == branch_probes[bp_idx].block_id:
				true_pid = bp.probe_id
			elif not bp.is_true_branch and bp.block_id == branch_probes[bp_idx].block_id:
				false_pid = bp.probe_id
		bp_idx -= 2

		if true_pid < 0 or false_pid < 0:
			continue

		# Extract the condition between " if " and " else "
		var cond_start := if_pos + 4  # len(" if ")
		var cond_end := else_pos
		var condition := result.substr(cond_start, cond_end - cond_start).strip_edges()

		# Replace: " if condition else " -> " if GUTCheckCollector.br2(sid,tpid,fpid,condition) else "
		var wrapped_condition := "GUTCheckCollector.br2(%d,%d,%d,%s)" % [sid, true_pid, false_pid, condition]
		result = result.substr(0, cond_start) + wrapped_condition + result.substr(cond_end)

	return "GUTCheckCollector.hit(%d,%d);%s" % [sid, pid, result]


## Find positions of ternary " if " and corresponding " else " in a source line.
## Returns array of [if_pos, else_pos] pairs, where each pos is the start of
## the " if " or " else " token (including leading space).
## Only finds ternary-ifs at bracket depth 0, outside strings.
static func find_ternary_if_positions(content: String) -> Array:
	var results: Array = []
	var pos := 0
	var length := content.length()
	var depth := 0
	var in_string := false
	var string_char := ""

	# First pass: find all " if " positions that are ternary (not at start of content)
	var if_positions: Array[int] = []

	while pos < length - 3:
		var c := content[pos]

		if in_string:
			if c == "\\" and pos + 1 < length:
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
			depth = maxi(0, depth - 1)
		elif depth == 0 and content.substr(pos, 4) == " if ":
			# Ternary if — must not be at the very start (that would be a statement-level if)
			if pos > 0:
				if_positions.append(pos)
				pos += 4
				continue

		pos += 1

	# Second pass: for each ternary if, find the matching else
	for if_pos in if_positions:
		var else_pos := _find_matching_else(content, if_pos + 4)
		if else_pos >= 0:
			results.append([if_pos, else_pos])

	return results


## Find the " else " that matches a ternary if, starting search from search_start.
## Handles nesting: if we encounter another " if " before " else ", we need to
## skip its corresponding " else " first.
static func _find_matching_else(content: String, search_start: int) -> int:
	var pos := search_start
	var length := content.length()
	var depth := 0
	var in_string := false
	var string_char := ""
	var nesting := 0  # ternary nesting depth

	while pos < length - 5:
		var c := content[pos]

		if in_string:
			if c == "\\" and pos + 1 < length:
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
			depth = maxi(0, depth - 1)
		elif depth == 0:
			if content.substr(pos, 4) == " if ":
				nesting += 1
				pos += 4
				continue
			if content.substr(pos, 6) == " else ":
				if nesting == 0:
					return pos
				nesting -= 1
				pos += 6
				continue

		pos += 1

	return -1


## No-op for match pattern probe injection.
static func inject_match_pattern_probe(content: String, _sid: int, _pid: int) -> String:
	return content


## Find the block-starting colon, respecting strings and nesting.
static func find_block_colon(content: String) -> int:
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


## Find the ` in ` keyword in a for-loop, respecting strings and nesting.
static func find_for_in(content: String) -> int:
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


## Extract leading whitespace from a line.
static func get_indent(line: String) -> String:
	var i := 0
	while i < line.length() and (line[i] == "\t" or line[i] == " "):
		i += 1
	return line.substr(0, i)
