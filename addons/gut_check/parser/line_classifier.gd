class_name GUTCheckLineClassifier
## Consumes a token stream and classifies each source line as executable,
## branch, loop, or non-executable. Produces a GUTCheckScriptMap.


func classify(tokens: Array, script_path: String = "") -> GUTCheckScriptMap:
	var map := GUTCheckScriptMap.new()
	map.path = script_path

	var current_line_tokens: Array = []
	var paren_depth: int = 0
	var first_token_line: int = -1

	# Scope tracking
	var func_stack: Array = []
	var class_stack: Array = []
	var indent_level: int = 0

	# Match scope tracking: stack of indent levels where match blocks start.
	# Lines at match_indent + 1 that look like patterns are BRANCH_PATTERN.
	var match_indent_stack: Array[int] = []

	# Property accessor tracking: stack of {indent: int, name: String} for
	# vars with a get/set block. The name is used to label accessor scopes.
	var property_indent_stack: Array = []

	var pending_static: bool = false

	for token in tokens:
		if token.type == GUTCheckToken.Type.INDENT:
			indent_level += 1
			continue
		if token.type == GUTCheckToken.Type.DEDENT:
			indent_level -= 1
			_close_scopes_at_indent(indent_level, func_stack, class_stack, token.line)
			# Pop match scopes that ended
			while match_indent_stack.size() > 0 and indent_level <= match_indent_stack.back():
				match_indent_stack.pop_back()
			# Pop property scopes that ended
			while property_indent_stack.size() > 0 and indent_level <= property_indent_stack.back().indent:
				property_indent_stack.pop_back()
			continue

		if token.type == GUTCheckToken.Type.NEWLINE:
			if current_line_tokens.size() > 0:
				var line_state := _finalize_current_line(
					map, current_line_tokens, first_token_line, token.line, paren_depth,
					pending_static, match_indent_stack, property_indent_stack,
					indent_level, func_stack, class_stack)
				pending_static = line_state.pending_static
				current_line_tokens = line_state.current_line_tokens
				first_token_line = line_state.first_token_line
			else:
				if not map.lines.has(token.line):
					map.lines[token.line] = GUTCheckLineInfo.new(
						token.line, GUTCheckScriptMap.LineType.NON_EXECUTABLE)
			continue

		if token.type == GUTCheckToken.Type.COMMENT:
			if current_line_tokens.size() == 0 and not map.lines.has(token.line):
				map.lines[token.line] = GUTCheckLineInfo.new(
					token.line, GUTCheckScriptMap.LineType.NON_EXECUTABLE)
			continue

		if token.type == GUTCheckToken.Type.EOF:
			continue

		if token.is_open_group():
			paren_depth += 1
		elif token.is_close_group():
			paren_depth = maxi(0, paren_depth - 1)

		if current_line_tokens.size() == 0:
			first_token_line = token.line
		current_line_tokens.append(token)

	var last_line: int = tokens.back().line if tokens.size() > 0 else 0
	_close_scopes_at_indent(-1, func_stack, class_stack, last_line)

	# Structure only: derive which lines are branches and how they group into
	# decision blocks. Probe IDs are NOT assigned here — that is the injector's
	# job (GUTCheckProbeAllocator), so a probe exists only because a collector
	# call was emitted for it.
	map.build_branches()
	return map


func _finalize_current_line(map: GUTCheckScriptMap, current_line_tokens: Array,
		first_token_line: int, newline_token_line: int, paren_depth: int,
		pending_static: bool, match_indent_stack: Array[int],
		property_indent_stack: Array, indent_level: int,
		func_stack: Array, class_stack: Array) -> Dictionary:
	var line_type = _classify_tokens(
		current_line_tokens, pending_static,
		match_indent_stack, property_indent_stack, indent_level)
	var scope_names := _get_scope_names(func_stack, class_stack)

	if paren_depth > 0:
		# Mid-statement newline (bracket continuation). Record a provisional
		# entry for the first line and mark this physical line as a
		# continuation. Scope entry is deferred until the statement completes
		# so multiline signatures don't register their function twice.
		if not map.lines.has(first_token_line):
			var partial = GUTCheckLineInfo.new(
				first_token_line, line_type, scope_names.func_name, scope_names.cls_name)
			partial.indent_level = indent_level
			map.lines[first_token_line] = partial
		map.lines[first_token_line].last_physical_line = newline_token_line
		if newline_token_line != first_token_line and not map.lines.has(newline_token_line):
			map.lines[newline_token_line] = GUTCheckLineInfo.new(
				newline_token_line, GUTCheckScriptMap.LineType.CONTINUATION,
				scope_names.func_name, scope_names.cls_name)
		return {
			"pending_static": pending_static,
			"current_line_tokens": current_line_tokens,
			"first_token_line": first_token_line,
		}

	# Class-body statements (member var declarations, including ternary
	# initializers) run outside any callable scope, where a statement probe
	# would be a syntax error. Exclude them from coverage instead of
	# reporting permanent zeros.
	if line_type == GUTCheckScriptMap.LineType.EXECUTABLE and scope_names.func_name == "":
		line_type = GUTCheckScriptMap.LineType.NON_EXECUTABLE

	var info = GUTCheckLineInfo.new(
		first_token_line, line_type, scope_names.func_name, scope_names.cls_name)
	info.indent_level = indent_level
	info.last_physical_line = newline_token_line
	info.statement_count = _count_statements(current_line_tokens)
	if line_type == GUTCheckScriptMap.LineType.EXECUTABLE:
		var ternary_count := _count_ternary_expressions(current_line_tokens)
		if ternary_count > 0:
			info.ternary_count = ternary_count
			info.type = GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY
			# wrap_ternary injects exactly one line probe, so keep the
			# allocation at one — extra per-statement probes would never
			# fire and pin the line at zero hits.
			info.statement_count = 1
	elif line_type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
			or line_type == GUTCheckScriptMap.LineType.BRANCH_PATTERN:
		info.has_inline_body = _has_tokens_after_block_colon(current_line_tokens)
	map.lines[first_token_line] = info
	_handle_scope_entry(current_line_tokens, first_token_line,
		indent_level, pending_static, func_stack, class_stack,
		match_indent_stack, property_indent_stack, map)

	return {
		"pending_static": _check_static(current_line_tokens),
		"current_line_tokens": [],
		"first_token_line": -1,
	}


func _get_scope_names(func_stack: Array, class_stack: Array) -> Dictionary:
	return {
		"func_name": func_stack.back().name if func_stack.size() > 0 else "",
		"cls_name": class_stack.back().name if class_stack.size() > 0 else "",
	}


func _classify_tokens(tokens: Array, preceded_by_static: bool,
		match_indent_stack: Array[int], property_indent_stack: Array,
		indent_level: int) -> GUTCheckScriptMap.LineType:
	if tokens.size() == 0:
		return GUTCheckScriptMap.LineType.NON_EXECUTABLE

	var first = tokens[0]

	# Annotation-only line
	if first.type == GUTCheckToken.Type.ANNOTATION:
		if tokens.size() == 1:
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		if tokens[1].type == GUTCheckToken.Type.PAREN_OPEN:
			var depth := 0
			for i in range(1, tokens.size()):
				if tokens[i].is_open_group():
					depth += 1
				elif tokens[i].is_close_group():
					depth -= 1
					if depth == 0 and i == tokens.size() - 1:
						return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		var rest: Array = []
		rest.assign(tokens.slice(1))
		if tokens[1].type == GUTCheckToken.Type.PAREN_OPEN:
			var depth := 0
			var skip_to := 1
			for i in range(1, tokens.size()):
				if tokens[i].is_open_group():
					depth += 1
				elif tokens[i].is_close_group():
					depth -= 1
					if depth == 0:
						skip_to = i + 1
						break
			rest.assign(tokens.slice(skip_to))
		if rest.size() > 0:
			return _classify_tokens(rest, preceded_by_static,
				match_indent_stack, property_indent_stack, indent_level)
		return GUTCheckScriptMap.LineType.NON_EXECUTABLE

	# Check if we're inside a match block — lines at match_indent+1 that
	# end with colon are match patterns (branch points).
	if match_indent_stack.size() > 0:
		var match_indent: int = match_indent_stack.back()
		if indent_level == match_indent + 1:
			# This line is a direct child of the match block.
			# If it ends with a colon and isn't a keyword like if/for/while,
			# it's a match pattern.
			if _is_match_pattern(tokens):
				return GUTCheckScriptMap.LineType.BRANCH_PATTERN

	# Check if we're inside a property block — detect get:/set(value):
	if property_indent_stack.size() > 0:
		var prop_indent: int = property_indent_stack.back().indent
		if indent_level == prop_indent + 1:
			if _is_property_accessor(tokens):
				return GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR

	match first.type:
		GUTCheckToken.Type.KW_IF:
			return GUTCheckScriptMap.LineType.BRANCH_IF
		GUTCheckToken.Type.KW_ELIF:
			return GUTCheckScriptMap.LineType.BRANCH_ELIF
		GUTCheckToken.Type.KW_ELSE:
			return GUTCheckScriptMap.LineType.BRANCH_ELSE
		GUTCheckToken.Type.KW_FOR:
			return GUTCheckScriptMap.LineType.LOOP_FOR
		GUTCheckToken.Type.KW_WHILE:
			return GUTCheckScriptMap.LineType.LOOP_WHILE
		GUTCheckToken.Type.KW_MATCH:
			return GUTCheckScriptMap.LineType.BRANCH_MATCH
		GUTCheckToken.Type.KW_FUNC:
			return GUTCheckScriptMap.LineType.FUNC_DEF
		GUTCheckToken.Type.KW_CLASS:
			return GUTCheckScriptMap.LineType.CLASS_DEF
		GUTCheckToken.Type.KW_CLASS_NAME:
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		GUTCheckToken.Type.KW_EXTENDS:
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		GUTCheckToken.Type.KW_SIGNAL:
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		GUTCheckToken.Type.KW_ENUM:
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		GUTCheckToken.Type.KW_STATIC:
			if tokens.size() > 1:
				var rest: Array = []
				rest.assign(tokens.slice(1))
				return _classify_tokens(rest, true,
					match_indent_stack, property_indent_stack, indent_level)
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		GUTCheckToken.Type.KW_CONST:
			return GUTCheckScriptMap.LineType.NON_EXECUTABLE
		GUTCheckToken.Type.KW_VAR:
			# Check if this var has a trailing colon for get/set block:
			# var x: int:    (trailing colon after type, introduces property block)
			# We still classify as EXECUTABLE since the var declaration runs,
			# but we'll push a property scope in _handle_scope_entry.
			return GUTCheckScriptMap.LineType.EXECUTABLE
		GUTCheckToken.Type.KW_RETURN, GUTCheckToken.Type.KW_BREAK, \
		GUTCheckToken.Type.KW_CONTINUE, GUTCheckToken.Type.KW_PASS, \
		GUTCheckToken.Type.KW_AWAIT:
			return GUTCheckScriptMap.LineType.EXECUTABLE
		_:
			return GUTCheckScriptMap.LineType.EXECUTABLE


func _is_match_pattern(tokens: Array) -> bool:
	## Returns true if this line looks like a match arm pattern.
	## Match patterns end with : and don't start with control flow keywords.
	if tokens.size() == 0:
		return false

	var first = tokens[0]

	# Control flow keywords at this indent inside a match are not patterns.
	# KW_VAR is intentionally absent: `var v:` / `var v when v > 0:` are
	# binding patterns. This check only runs at match-pattern indent (the
	# caller gates on indent_level == match_indent + 1), so a `var` here can
	# only be a binding pattern, never an ordinary declaration.
	if first.type in [
		GUTCheckToken.Type.KW_IF, GUTCheckToken.Type.KW_FOR,
		GUTCheckToken.Type.KW_WHILE,
		GUTCheckToken.Type.KW_FUNC, GUTCheckToken.Type.KW_CLASS,
		GUTCheckToken.Type.KW_RETURN, GUTCheckToken.Type.KW_PASS,
		GUTCheckToken.Type.KW_BREAK, GUTCheckToken.Type.KW_CONTINUE,
	]:
		return false

	# Check if the line contains a colon at depth 0 — patterns always have one.
	# It may not be the last token if there's an inline body (e.g., "green": return val).
	var depth := 0
	for t in tokens:
		if t.is_open_group():
			depth += 1
		elif t.is_close_group():
			depth = maxi(0, depth - 1)
		elif t.type == GUTCheckToken.Type.COLON and depth == 0:
			return true

	# Also check for "when" guard: `pattern when condition:`
	for t in tokens:
		if t.type == GUTCheckToken.Type.KW_WHEN:
			return true

	return false


func _is_property_accessor(tokens: Array) -> bool:
	## Returns true if this line is a get: or set(...): property accessor.
	if tokens.size() == 0:
		return false

	var first = tokens[0]
	if first.type != GUTCheckToken.Type.IDENTIFIER:
		return false

	# get:
	if first.value == "get" and tokens.size() >= 2 and tokens[1].type == GUTCheckToken.Type.COLON:
		return true

	# set(value):
	if first.value == "set" and tokens.size() >= 2 and tokens[1].type == GUTCheckToken.Type.PAREN_OPEN:
		return true

	return false


func _count_ternary_expressions(tokens: Array) -> int:
	## Count inline ternary-if expressions (value if condition else other).
	## A ternary `if` is any KW_IF that is not the first keyword on the line
	## (i.e. not a statement-level if) and reaches its matching KW_ELSE with NO
	## block colon at the if's own group depth in between: a ternary is a pure
	## expression, whereas a block `if cond:` has a depth-0 colon after its
	## condition. This distinction matters because a bracket-continued statement
	## (e.g. a multiline lambda passed as a call argument) merges its whole body
	## into one logical line here — the lambda's block `if ... else:` would
	## otherwise be miscounted as a ternary, and wrap_ternary would emit
	## `br2(..., cond: body)`, a syntax error that fails the whole file's compile.
	var count := 0
	for i in range(1, tokens.size()):
		if tokens[i].type != GUTCheckToken.Type.KW_IF:
			continue
		# Scan toward the matching else, tracking group depth relative to this
		# if. A depth-0 colon means block control flow, not a ternary — abandon.
		var depth := 0
		for j in range(i + 1, tokens.size()):
			var t = tokens[j]
			if t.is_open_group():
				depth += 1
			elif t.is_close_group():
				depth = maxi(0, depth - 1)
			elif depth == 0 and t.type == GUTCheckToken.Type.COLON:
				break
			elif depth == 0 and t.type == GUTCheckToken.Type.KW_ELSE:
				# True ternaries always have both if and else. A nested ternary's
				# inner if/else lives inside this condition's brackets (depth > 0),
				# so the first depth-0 else is this if's own.
				count += 1
				break
	return count


func _count_statements(tokens: Array) -> int:
	## Count semicolon-separated statements on a line, ignoring empty
	## segments so a trailing semicolon (`do_thing();`) doesn't allocate a
	## probe the injector never places.
	## Only counts semicolons at depth 0 (not inside parens/brackets/braces).
	var count := 0
	var depth := 0
	var segment_has_tokens := false
	for t in tokens:
		if t.is_open_group():
			depth += 1
			segment_has_tokens = true
		elif t.is_close_group():
			depth = maxi(0, depth - 1)
			segment_has_tokens = true
		elif t.type == GUTCheckToken.Type.SEMICOLON and depth == 0:
			if segment_has_tokens:
				count += 1
			segment_has_tokens = false
		else:
			segment_has_tokens = true
	if segment_has_tokens:
		count += 1
	return maxi(count, 1)


func _check_static(tokens: Array) -> bool:
	return tokens.size() > 0 and tokens[0].type == GUTCheckToken.Type.KW_STATIC


func _has_trailing_colon_after_type(tokens: Array) -> bool:
	## Checks if a var declaration ends with a colon that introduces a get/set
	## property block. A trailing colon is the only thing that does this, in
	## every form:
	##   var name: Type:      (type hint + block — two colons)
	##   var name := v:        (inferred + block)
	##   var name = value:     (untyped + block — one colon)
	## NEWLINE/COMMENT tokens are never in this list, so the last token is the
	## last real token on the declaration.
	return tokens.size() > 0 \
		and tokens[tokens.size() - 1].type == GUTCheckToken.Type.COLON


func _is_lambda_assignment(tokens: Array) -> bool:
	## True if the line assigns a lambda (`... = func(...):`), so its trailing
	## colon is the lambda's block colon — not a get/set property accessor block.
	for i in range(tokens.size() - 1):
		if tokens[i].type == GUTCheckToken.Type.KW_FUNC \
				and tokens[i + 1].type == GUTCheckToken.Type.PAREN_OPEN:
			return true
	return false


func _handle_scope_entry(tokens: Array, line_num: int, indent: int,
		preceded_by_static: bool, func_stack: Array,
		class_stack: Array, match_indent_stack: Array[int],
		property_indent_stack: Array, map: GUTCheckScriptMap) -> void:
	if tokens.size() == 0:
		return

	var kw_idx := 0
	var has_static := preceded_by_static
	while kw_idx < tokens.size():
		if tokens[kw_idx].type == GUTCheckToken.Type.ANNOTATION:
			kw_idx += 1
			if kw_idx < tokens.size() and tokens[kw_idx].type == GUTCheckToken.Type.PAREN_OPEN:
				var depth := 1
				kw_idx += 1
				while kw_idx < tokens.size() and depth > 0:
					if tokens[kw_idx].is_open_group():
						depth += 1
					elif tokens[kw_idx].is_close_group():
						depth -= 1
					kw_idx += 1
			continue
		if tokens[kw_idx].type == GUTCheckToken.Type.KW_STATIC:
			has_static = true
			kw_idx += 1
			continue
		break

	if kw_idx >= tokens.size():
		return

	var kw = tokens[kw_idx]

	if kw.type == GUTCheckToken.Type.KW_FUNC:
		var fname := ""
		if kw_idx + 1 < tokens.size() and tokens[kw_idx + 1].type == GUTCheckToken.Type.IDENTIFIER:
			fname = tokens[kw_idx + 1].value
		var cls_name: String = class_stack.back().name if class_stack.size() > 0 else ""
		var info = GUTCheckFunctionInfo.new(fname, line_num, cls_name, has_static, indent)
		func_stack.append(info)
		map.functions.append(info)

	elif kw.type == GUTCheckToken.Type.KW_CLASS:
		var cname := ""
		if kw_idx + 1 < tokens.size() and tokens[kw_idx + 1].type == GUTCheckToken.Type.IDENTIFIER:
			cname = tokens[kw_idx + 1].value
		var info = GUTCheckClassInfo.new(cname, line_num, indent)
		class_stack.append(info)
		map.classes.append(info)

	elif kw.type == GUTCheckToken.Type.KW_MATCH:
		# Push the current indent level so we know pattern lines are at indent+1
		match_indent_stack.append(indent)

	elif kw.type == GUTCheckToken.Type.KW_VAR:
		# A trailing colon usually starts a get/set property block — but a block-
		# bodied lambda assignment (`var cb = func():`) also ends in a colon. Don't
		# open a property scope for it; the lambda is registered by
		# _detect_inline_lambdas below.
		if _has_trailing_colon_after_type(tokens) and not _is_lambda_assignment(tokens):
			var prop_name := ""
			if kw_idx + 1 < tokens.size() and tokens[kw_idx + 1].type == GUTCheckToken.Type.IDENTIFIER:
				prop_name = tokens[kw_idx + 1].value
			property_indent_stack.append({"indent": indent, "name": prop_name})

	elif kw.type == GUTCheckToken.Type.IDENTIFIER \
			and _is_block_property_accessor(tokens, indent, property_indent_stack):
		# get:/set(value): with a block body act like functions for coverage:
		# register a scope so body lines are attributed and instrumented.
		var prop: Dictionary = property_indent_stack.back()
		var fname: String = kw.value
		if not String(prop.name).is_empty():
			fname = "%s.%s" % [prop.name, kw.value]
		var accessor_cls: String = class_stack.back().name if class_stack.size() > 0 else ""
		var accessor_info = GUTCheckFunctionInfo.new(fname, line_num, accessor_cls, false, indent)
		func_stack.append(accessor_info)
		map.functions.append(accessor_info)

	# Detect inline lambdas on non-function lines (e.g. `var fn = func(x):`).
	# Named function declarations (kw == KW_FUNC) are already handled above,
	# so we only scan for lambdas when the line's leading keyword is something
	# else like var, return, etc.
	if kw.type != GUTCheckToken.Type.KW_FUNC:
		_detect_inline_lambdas(tokens, line_num, indent, func_stack, class_stack, map)


func _detect_inline_lambdas(tokens: Array, line_num: int, indent: int, func_stack: Array,
		class_stack: Array, map: GUTCheckScriptMap) -> void:
	## Scan a token list for block-bodied inline lambda definitions (func(
	## without a name) and register them so they appear in function coverage.
	##
	## Inline-bodied lambdas (`func(x): return x`, including bracket-nested
	## `arr.map(func(x): ...)`) are intentionally NOT registered: their body
	## shares the definition line, which already carries the enclosing
	## statement's probe, so we cannot tell "invoked" from "merely defined".
	## Reporting them would count a never-called lambda as covered, so we omit
	## them rather than emit a false positive.
	var lambda_count := 0
	var depth := 0
	for i in range(tokens.size() - 1):
		var t = tokens[i]
		if t.is_open_group():
			depth += 1
		elif t.is_close_group():
			depth = maxi(0, depth - 1)
		if t.type != GUTCheckToken.Type.KW_FUNC:
			continue
		# Named function: func name( — skip, already handled
		if tokens[i + 1].type == GUTCheckToken.Type.IDENTIFIER:
			continue
		# Lambda: func( or func() — no name before paren
		if tokens[i + 1].type != GUTCheckToken.Type.PAREN_OPEN:
			continue
		if _lambda_body_is_inline(tokens, i, depth):
			continue  # unmeasurable — see method doc
		lambda_count += 1
		var lambda_name := "<lambda:%d:%d>" % [line_num, lambda_count]
		var cls_name: String = class_stack.back().name if class_stack.size() > 0 else ""
		var info := GUTCheckFunctionInfo.new(lambda_name, line_num, cls_name, false, indent)
		map.functions.append(info)
		# Block-bodied lambda: body lines follow at deeper indent and will be
		# attributed to this scope until the DEDENT closes it.
		func_stack.append(info)


func _lambda_body_is_inline(tokens: Array, func_idx: int, depth_at_func: int) -> bool:
	## A lambda's block colon is the first COLON at the same group depth as
	## its `func` token. If any token follows that colon, the body is inline.
	## Lambdas nested inside brackets are always treated as inline since
	## their body lines are bracket continuations that cannot take probes.
	if depth_at_func > 0:
		return true
	var depth := 0
	for j in range(func_idx + 1, tokens.size()):
		var t = tokens[j]
		if t.is_open_group():
			depth += 1
		elif t.is_close_group():
			depth = maxi(0, depth - 1)
		elif t.type == GUTCheckToken.Type.COLON and depth == 0:
			return j < tokens.size() - 1
	return false


func _has_tokens_after_block_colon(tokens: Array) -> bool:
	## True when a compound-statement line has code after its block colon
	## (e.g. `else: x()` or `"up": return v`). The block colon is the first
	## COLON at group depth 0; comments are never in the token list.
	var depth := 0
	for i in range(tokens.size()):
		var t = tokens[i]
		if t.is_open_group():
			depth += 1
		elif t.is_close_group():
			depth = maxi(0, depth - 1)
		elif t.type == GUTCheckToken.Type.COLON and depth == 0:
			return i < tokens.size() - 1
	return false


func _is_block_property_accessor(tokens: Array, indent: int, property_indent_stack: Array) -> bool:
	## True when this line is a get:/set(value): accessor with a block body
	## (no code after the colon). Inline accessors (`get: return x`) keep
	## their body on the accessor line and stay excluded from coverage.
	if property_indent_stack.size() == 0:
		return false
	if indent != int(property_indent_stack.back().indent) + 1:
		return false
	if not _is_property_accessor(tokens):
		return false
	return not _has_tokens_after_block_colon(tokens)


func _close_scopes_at_indent(indent: int, func_stack: Array,
		class_stack: Array, line_num: int) -> void:
	# Pop functions whose body we've exited. A function defined at indent N
	# has its body at indent N+1, so we close it when indent drops to N or below.
	while func_stack.size() > 0 and func_stack.back().end_line == -1:
		if indent <= func_stack.back().indent:
			func_stack.back().end_line = line_num - 1
			func_stack.pop_back()
		else:
			break

	# Pop classes whose body we've exited, same logic.
	while class_stack.size() > 0 and class_stack.back().end_line == -1:
		if indent <= class_stack.back().indent:
			class_stack.back().end_line = line_num - 1
			class_stack.pop_back()
		else:
			break
