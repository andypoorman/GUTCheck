class_name GUTCheckProbeInjector
## Pure string-manipulation functions for injecting coverage probes into
## GDScript source lines. Every method is static — no instance state needed.


## Dispatch a source statement (single line, or a newline-joined multiline
## statement) to the appropriate probe-injection wrapper. Probe IDs are pulled
## from `allocator` at the moment a call is emitted, so a wrapper that declines
## allocates nothing and that probe is never born (see GUTCheckProbeAllocator).
## `branch_probes` carries the branch STRUCTURE (block_id / true-false role) for
## this line; the wrappers stamp freshly-allocated ids onto those infos.
static func instrument_line(line: String, line_type: GUTCheckScriptMap.LineType, sid: int, allocator: GUTCheckProbeAllocator, stmt_count: int = 1, branch_probes: Array = [], has_inline_body: bool = false) -> String:
	var indent := get_indent(line)
	var content := line.substr(indent.length())

	match line_type:
		GUTCheckScriptMap.LineType.EXECUTABLE:
			if stmt_count > 1:
				return indent + instrument_semicolon_statements(content, sid, allocator)
			return indent + "GUTCheckCollector.hit(%d,%d);%s" % [sid, allocator.line(), content]

		GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR:
			return line

		GUTCheckScriptMap.LineType.BRANCH_ELSE, \
		GUTCheckScriptMap.LineType.BRANCH_PATTERN:
			# Inline bodies get the branch probe injected after the block colon.
			# Block bodies can't hold their own counter, so they register a derived
			# branch — no call is emitted; the allocator later points its probe at
			# the first body line (see GUTCheckProbeAllocator.resolve_derived).
			if has_inline_body and branch_probes.size() > 0:
				return indent + inject_inline_body_probe(content, sid, allocator, branch_probes[0])
			if branch_probes.size() > 0:
				allocator.derive_branch(branch_probes[0])
			return line

		GUTCheckScriptMap.LineType.BRANCH_IF:
			return indent + wrap_condition_br2(content, "if", sid, allocator, branch_probes)

		GUTCheckScriptMap.LineType.BRANCH_ELIF:
			return indent + wrap_condition_br2(content, "elif", sid, allocator, branch_probes)

		GUTCheckScriptMap.LineType.LOOP_WHILE:
			return indent + wrap_condition_br2(content, "while", sid, allocator, branch_probes)

		GUTCheckScriptMap.LineType.LOOP_FOR:
			return indent + wrap_for_br2(content, sid, allocator, branch_probes)

		GUTCheckScriptMap.LineType.BRANCH_MATCH:
			return indent + wrap_match(content, sid, allocator)

		GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY:
			return indent + wrap_ternary(content, sid, allocator, branch_probes)

		GUTCheckScriptMap.LineType.FUNC_DEF, \
		GUTCheckScriptMap.LineType.CLASS_DEF:
			return line

		_:
			return line


## Split content on semicolons (respecting strings and brackets) and inject a
## probe before each real statement. Empty segments (e.g. `a();;b()`) and a
## trailing comment-only segment (`a(); b(); # note`) carry no statement, so
## they get NO probe — the probe count here must match the classifier's
## statement_count, or probe ids overrun into the next line's allocation.
static func instrument_semicolon_statements(content: String, sid: int, allocator: GUTCheckProbeAllocator) -> String:
	var segments: Array[String] = []
	var current := ""
	var scan_state := _new_scan_state()

	for i in range(content.length()):
		var c: String = content[i]
		if _scan_char(c, scan_state, i, content.length()):
			current += c
			continue

		if c == ";" and scan_state.depth == 0:
			segments.append(current)
			current = ""
		else:
			current += c
	segments.append(current)

	var parts: PackedStringArray = []
	var trailing_comment := ""
	for seg in segments:
		# Explicit type (not `:=`): when GUTCheck instruments its own source,
		# the wrapped `for` iterable returns Variant, and `:=` on a Variant
		# method result fails to infer. An annotated local sidesteps that.
		var s: String = seg.strip_edges()
		if s.is_empty():
			continue  # empty `;;` segment — no statement, no probe
		if s.begins_with("#"):
			trailing_comment = s  # comment-only segment — preserve it, but no probe
			continue
		# Allocate one line probe per real statement, on this same line.
		parts.append("GUTCheckCollector.hit(%d,%d);%s" % [sid, allocator.line(), s])

	var result := "; ".join(parts)
	if not trailing_comment.is_empty():
		result += "  " + trailing_comment
	return result


## Wrap a condition with br2() for branch coverage. Allocates the line probe and
## the two branch probes only on the success path; a missing block colon declines
## and allocates nothing.
static func wrap_condition_br2(content: String, keyword: String, sid: int, allocator: GUTCheckProbeAllocator, branch_probes: Array) -> String:
	var block_parts := _split_block_content(content, keyword.length())
	if block_parts.is_empty():
		return content

	var condition: String = block_parts.condition
	var after_colon: String = block_parts.after_colon
	var true_info = _find_branch(branch_probes, true)
	var false_info = _find_branch(branch_probes, false)
	var line_pid := allocator.line()

	if true_info != null and false_info != null:
		var true_pid := allocator.branch(true_info)
		var false_pid := allocator.branch(false_info)
		return "%s GUTCheckCollector.hit_br2(%d,%d,%d,%d,%s):%s" % [keyword, sid, line_pid, true_pid, false_pid, condition, after_colon]

	return "%s GUTCheckCollector.br(%d,%d,%s):%s" % [keyword, sid, line_pid, condition, after_colon]


## Wrap a for-loop iterable with branch probes if available. Declines (no probe)
## when there is no `in` or no block colon.
static func wrap_for_br2(content: String, sid: int, allocator: GUTCheckProbeAllocator, branch_probes: Array) -> String:
	var in_pos := find_for_in(content)
	if in_pos == -1:
		return content

	var before_in := content.substr(0, in_pos)
	# find_for_in returns the index just before "in"; the iterable starts right
	# after the 2-char keyword (in_pos + 3). _split_block_content skips any
	# leading space, so this handles both `in range` and the dense `in(arr)`
	# (where no space follows "in").
	var block_parts := _split_block_content(content, in_pos + 3)
	if block_parts.is_empty():
		return content

	var iterable: String = block_parts.condition
	var after_colon: String = block_parts.after_colon
	var true_info = _find_branch(branch_probes, true)
	var false_info = _find_branch(branch_probes, false)
	var line_pid := allocator.line()

	if true_info != null and false_info != null:
		var true_pid := allocator.branch(true_info)
		var false_pid := allocator.branch(false_info)
		return "%s in GUTCheckCollector.hit_br2rng(%d,%d,%d,%d,%s):%s" % [before_in, sid, line_pid, true_pid, false_pid, iterable, after_colon]

	return "%s in GUTCheckCollector.rng(%d,%d,%s):%s" % [before_in, sid, line_pid, iterable, after_colon]


## Wrap a match expression with br(). Declines when there is no block colon.
static func wrap_match(content: String, sid: int, allocator: GUTCheckProbeAllocator) -> String:
	var block_parts := _split_block_content(content, 5)
	if block_parts.is_empty():
		return content

	var expr: String = block_parts.condition
	var after_colon: String = block_parts.after_colon

	return "match GUTCheckCollector.br(%d,%d,%s):%s" % [sid, allocator.line(), expr, after_colon]


## Wrap ternary-if conditions with br2() for branch coverage.
## Input:  var x = "yes" if condition else "no"
## Output: GUTCheckCollector.hit(sid,pid);var x = "yes" if GUTCheckCollector.br2(sid,tpid,fpid,condition) else "no"
## The line probe is always allocated (every ternary line gets one); each
## wrapped ternary block additionally allocates its two branch probes. If no
## ternary is found at string level, only the line probe is allocated and the
## line's branch structure is declined.
static func wrap_ternary(content: String, sid: int, allocator: GUTCheckProbeAllocator, branch_probes: Array) -> String:
	# Find all ternary if/else pairs (positions in the content string)
	var ternary_ifs := find_ternary_if_positions(content)
	var line_pid := allocator.line()

	if ternary_ifs.size() == 0:
		# Fallback: no ternaries found at string level, treat as plain executable
		return "GUTCheckCollector.hit(%d,%d);%s" % [sid, line_pid, content]

	# Process ternaries right-to-left so earlier positions stay stable.
	# A nested ternary lives inside its enclosing ternary's condition, so
	# wrapping the inner one (processed first, larger position) inserts text
	# before the outer one's recorded else_pos. We track the byte delta of
	# every applied edit and shift a later pair's else_pos by the deltas of
	# any edit that landed inside its condition — keeping all positions valid
	# without dropping the inner ternary's probes.
	var result := content
	var edits: Array = []  # each entry: [edit_if_pos, byte_delta]
	var bp_idx := (mini(ternary_ifs.size(), branch_probes.size() / 2) - 1) * 2

	for t_idx in range(ternary_ifs.size() - 1, -1, -1):
		if bp_idx < 0:
			break
		var if_pos: int = ternary_ifs[t_idx][0]
		var else_pos: int = ternary_ifs[t_idx][1]
		var block_id: int = branch_probes[bp_idx].block_id
		var true_info = _find_block_branch(branch_probes, block_id, true)
		var false_info = _find_block_branch(branch_probes, block_id, false)
		bp_idx -= 2

		if true_info == null or false_info == null:
			continue
		var true_pid := allocator.branch(true_info)
		var false_pid := allocator.branch(false_info)

		# Shift else_pos past any earlier edit that fell inside this condition
		# (i.e. a nested ternary we already wrapped). cond_start never shifts:
		# this pair's "if" is left of every edit processed so far.
		var extra := 0
		for e in edits:
			if e[0] < else_pos:
				extra += e[1]
		var adj_else := else_pos + extra

		# Extract the condition between the "if" and "else" words. Kept raw
		# (not stripped) so newlines in multiline statements are preserved
		# inside the wrapper call and the physical line count stays intact.
		var cond_start := if_pos + 2  # after the "if" word
		var condition := result.substr(cond_start, adj_else - cond_start)

		var wrapped_condition := "GUTCheckCollector.br2(%d,%d,%d,%s)" % [sid, true_pid, false_pid, condition]
		result = result.substr(0, cond_start) + " " + wrapped_condition + " " + result.substr(adj_else)
		edits.append([if_pos, wrapped_condition.length() + 2 - condition.length()])

	return "GUTCheckCollector.hit(%d,%d);%s" % [sid, line_pid, result]


static func _is_word_boundary_char(c: String) -> bool:
	# A keyword boundary is anything that can't continue an identifier —
	# whitespace, parens, operators, brackets. This recognises dense but valid
	# forms like `1 if(c)else 2` and `for x in(arr):`, while still rejecting
	# `if` inside `notify` or `in` inside `index`.
	return not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
		or (c >= "0" and c <= "9") or c == "_")


## True if the word w starts at pos, delimited by whitespace on both sides.
static func _word_at(content: String, pos: int, w: String) -> bool:
	var w_len := w.length()
	if pos == 0 or pos + w_len >= content.length():
		return false
	if content.substr(pos, w_len) != w:
		return false
	if not _is_word_boundary_char(content[pos - 1]):
		return false
	return _is_word_boundary_char(content[pos + w_len])


## Find positions of ternary "if" words and their matching "else" words.
## Returns array of [if_pos, else_pos] pairs (start of each keyword).
## Ternaries are found at any bracket depth (parenthesized ternaries are
## still expressions and safe to wrap), outside strings and comments.
## Whitespace boundaries include newlines so multiline statements work.
static func find_ternary_if_positions(content: String) -> Array:
	var results: Array = []
	var pos := 0
	var length := content.length()
	var scan_state := _new_scan_state()

	# First pass: find all ternary "if" positions (never at content start —
	# that would be a statement-level if).
	var if_positions: Array[int] = []

	while pos < length:
		var c: String = content[pos]
		if _scan_char(c, scan_state, pos, length):
			pos += 1
			continue
		if _word_at(content, pos, "if"):
			if_positions.append(pos)
			pos += 2
			continue
		pos += 1

	# Second pass: for each ternary if, find the matching else. The matcher
	# tracks depth relative to the if's position, so nested subexpressions
	# (and their own ternaries) are skipped correctly at any absolute depth.
	for if_pos in if_positions:
		var else_pos := _find_matching_else(content, if_pos + 2)
		if else_pos >= 0:
			results.append([if_pos, else_pos])

	return results


## Find the "else" word that matches a ternary if, starting from search_start.
## Handles nesting: if we encounter another "if" before "else", we need to
## skip its corresponding "else" first.
static func _find_matching_else(content: String, search_start: int) -> int:
	var pos := search_start
	var length := content.length()
	var scan_state := _new_scan_state()
	var nesting := 0  # ternary nesting depth

	while pos < length:
		var c: String = content[pos]
		if _scan_char(c, scan_state, pos, length):
			pos += 1
			continue
		if scan_state.depth == 0:
			if _word_at(content, pos, "if"):
				nesting += 1
				pos += 2
				continue
			if _word_at(content, pos, "else"):
				if nesting == 0:
					return pos
				nesting -= 1
				pos += 4
				continue
		pos += 1

	return -1


## Find the FIRST depth-0 colon at or after min_pos, respecting strings and
## comments. This is the block colon for compound headers — searching from the
## start of the condition/iterable (min_pos) skips a typed loop var's colon
## (`for i: int in ...`, which is before the iterable) and stops at the block
## colon before any inline body (`if c: var y: int = 1`, whose type colon is
## after the block colon). The scan always starts at 0 so bracket/string depth
## is tracked correctly; min_pos only gates which colon is returned.
static func find_first_block_colon(content: String, min_pos: int = 0) -> int:
	var scan_state := _new_scan_state()
	for i in range(content.length()):
		var c: String = content[i]
		if _scan_char(c, scan_state, i, content.length()):
			continue
		if c == ":" and scan_state.depth == 0 and i >= min_pos:
			return i
	return -1


## Inject a probe into the inline body of an else:/match-pattern line:
##   else: x()      ->  else: GUTCheckCollector.hit(sid,pid);x()
##   "up": return v ->  "up": GUTCheckCollector.hit(sid,pid);return v
## The branch probe is allocated only once a real inline body is confirmed (not a
## bare colon / empty / comment-only body); the same probe carries both the
## branch hit and the line hit, straight from real execution of the body.
static func inject_inline_body_probe(content: String, sid: int, allocator: GUTCheckProbeAllocator, branch_info) -> String:
	var colon_pos := find_first_block_colon(content)
	if colon_pos == -1 or colon_pos + 1 >= content.length():
		return content
	var body := content.substr(colon_pos + 1)
	var body_stripped := body.strip_edges()
	if body_stripped.is_empty() or body_stripped.begins_with("#"):
		return content
	return "%s GUTCheckCollector.hit(%d,%d);%s" % [
		content.substr(0, colon_pos + 1), sid, allocator.branch(branch_info), body_stripped]


static func _split_block_content(content: String, start_pos: int) -> Dictionary:
	var expr_start := start_pos
	while expr_start < content.length() and content[expr_start] == " ":
		expr_start += 1

	# The block colon is the first depth-0 colon at/after the condition start.
	# Searching from expr_start (not the whole line) ignores both a typed loop
	# var's colon (before the iterable) and an inline body's type colon (after
	# the block colon), so an inline-bodied header isn't mis-split.
	var colon_pos := find_first_block_colon(content, expr_start)
	if colon_pos == -1:
		return {}

	return {
		"condition": content.substr(expr_start, colon_pos - expr_start).strip_edges(),
		"after_colon": content.substr(colon_pos + 1),
	}


## Find the true- or false-branch GUTCheckBranchInfo on a line (one of each for
## if/elif/while/for), or null. The wrapper allocates a probe for it only when
## both are present, so an incomplete pair declines cleanly.
static func _find_branch(branch_probes: Array, want_true: bool):
	for bp in branch_probes:
		if bp.is_true_branch == want_true:
			return bp
	return null


## Find the true- or false-branch GUTCheckBranchInfo for one ternary block, or
## null. A ternary line carries 2 branch infos per block (block_id distinguishes
## the ternaries on the line).
static func _find_block_branch(branch_probes: Array, block_id: int, want_true: bool):
	for bp in branch_probes:
		if bp.block_id == block_id and bp.is_true_branch == want_true:
			return bp
	return null


static func _new_scan_state() -> Dictionary:
	return {
		"depth": 0,
		"in_string": false,
		"string_char": "",
		"escape_next": false,
		"in_comment": false,
	}


static func _scan_char(c: String, state: Dictionary, pos: int, length: int) -> bool:
	if state.in_comment:
		# Comments end at the physical line break (multiline scans pass
		# newline-joined content through this scanner).
		if c == "\n":
			state.in_comment = false
		return true

	if state.in_string:
		if state.escape_next:
			state.escape_next = false
			return true
		if c == "\\" and pos + 1 < length:
			state.escape_next = true
			return true
		if c == state.string_char:
			state.in_string = false
		return true

	if c == '"' or c == "'":
		state.in_string = true
		state.string_char = c
		state.escape_next = false
		return true

	if c == "#":
		state.in_comment = true
		return true

	if c == "(" or c == "[" or c == "{":
		state.depth += 1
		return false
	if c == ")" or c == "]" or c == "}":
		state.depth = maxi(0, state.depth - 1)
		return false
	return false


## Find the position of the `in` keyword in a for-loop, respecting strings,
## comments, and nesting. Returns the index of the whitespace character
## immediately before the `in` word.
static func find_for_in(content: String) -> int:
	var pos := 4  # skip "for "
	var length := content.length()
	var scan_state := _new_scan_state()

	while pos < length:
		var c := content[pos]
		if _scan_char(c, scan_state, pos, length):
			pos += 1
			continue
		if scan_state.depth == 0 and _word_at(content, pos, "in"):
			return pos - 1
		pos += 1

	return -1


## Extract leading whitespace from a line.
static func get_indent(line: String) -> String:
	var i := 0
	while i < line.length() and (line[i] == "\t" or line[i] == " "):
		i += 1
	return line.substr(0, i)
