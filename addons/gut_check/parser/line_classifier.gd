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

	# Property accessor tracking: indent level of a var with get/set block
	var property_indent_stack: Array[int] = []

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
			while property_indent_stack.size() > 0 and indent_level <= property_indent_stack.back():
				property_indent_stack.pop_back()
			continue

		if token.type == GUTCheckToken.Type.NEWLINE:
			if current_line_tokens.size() > 0:
				if paren_depth > 0:
					if not map.lines.has(first_token_line):
						var line_type = _classify_tokens(
							current_line_tokens, pending_static,
							match_indent_stack, property_indent_stack, indent_level)
						var func_name: String = func_stack.back().name if func_stack.size() > 0 else ""
						var cls_name: String = class_stack.back().name if class_stack.size() > 0 else ""
						map.lines[first_token_line] = GUTCheckLineInfo.new(
							first_token_line, line_type, func_name, cls_name)
						_handle_scope_entry(current_line_tokens, first_token_line,
							indent_level, pending_static, func_stack, class_stack,
							match_indent_stack, property_indent_stack, map)
						pending_static = _check_static(current_line_tokens)
					if token.line != first_token_line and not map.lines.has(token.line):
						var func_name: String = func_stack.back().name if func_stack.size() > 0 else ""
						var cls_name: String = class_stack.back().name if class_stack.size() > 0 else ""
						map.lines[token.line] = GUTCheckLineInfo.new(
							token.line, GUTCheckScriptMap.LineType.CONTINUATION, func_name, cls_name)
				else:
					var line_type = _classify_tokens(
						current_line_tokens, pending_static,
						match_indent_stack, property_indent_stack, indent_level)
					var func_name: String = func_stack.back().name if func_stack.size() > 0 else ""
					var cls_name: String = class_stack.back().name if class_stack.size() > 0 else ""
					var info = GUTCheckLineInfo.new(
						first_token_line, line_type, func_name, cls_name)
					info.statement_count = _count_statements(current_line_tokens)
					map.lines[first_token_line] = info
					_handle_scope_entry(current_line_tokens, first_token_line,
						indent_level, pending_static, func_stack, class_stack,
						match_indent_stack, property_indent_stack, map)
					pending_static = _check_static(current_line_tokens)

					current_line_tokens.clear()
					first_token_line = -1
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

	map.assign_probes()
	map.assign_branch_probes()
	return map


func _classify_tokens(tokens: Array, preceded_by_static: bool,
		match_indent_stack: Array[int], property_indent_stack: Array[int],
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
		var prop_indent: int = property_indent_stack.back()
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

	# Control flow keywords at this indent inside a match are not patterns
	if first.type in [
		GUTCheckToken.Type.KW_IF, GUTCheckToken.Type.KW_FOR,
		GUTCheckToken.Type.KW_WHILE, GUTCheckToken.Type.KW_VAR,
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


func _count_statements(tokens: Array) -> int:
	## Count semicolon-separated statements on a line.
	## Only counts semicolons at depth 0 (not inside parens/brackets/braces).
	var count := 1
	var depth := 0
	for t in tokens:
		if t.is_open_group():
			depth += 1
		elif t.is_close_group():
			depth = maxi(0, depth - 1)
		elif t.type == GUTCheckToken.Type.SEMICOLON and depth == 0:
			count += 1
	return count


func _check_static(tokens: Array) -> bool:
	return tokens.size() > 0 and tokens[0].type == GUTCheckToken.Type.KW_STATIC


func _tokens_contain_call(tokens: Array) -> bool:
	for i in range(tokens.size() - 1):
		if tokens[i].type == GUTCheckToken.Type.IDENTIFIER or tokens[i].type == GUTCheckToken.Type.KW_PRELOAD:
			if tokens[i + 1].type == GUTCheckToken.Type.PAREN_OPEN:
				return true
	return false


func _has_trailing_colon_after_type(tokens: Array) -> bool:
	## Checks if a var declaration has a trailing colon that introduces a
	## get/set property block. Pattern: var name: Type:  (two colons)
	## or: var name = value:  (unusual but valid)
	var colon_count := 0
	for t in tokens:
		if t.type == GUTCheckToken.Type.COLON:
			colon_count += 1
	# A var with get/set has at least 2 colons: one for the type hint, one for the block
	# Or if no type hint, just one trailing colon after the value/declaration
	if colon_count >= 2:
		var last = tokens[tokens.size() - 1]
		return last.type == GUTCheckToken.Type.COLON
	return false


func _handle_scope_entry(tokens: Array, line_num: int, indent: int,
		preceded_by_static: bool, func_stack: Array,
		class_stack: Array, match_indent_stack: Array[int],
		property_indent_stack: Array[int], map: GUTCheckScriptMap) -> void:
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
		var info = GUTCheckFunctionInfo.new(fname, line_num, cls_name, has_static)
		func_stack.append(info)
		map.functions.append(info)

	elif kw.type == GUTCheckToken.Type.KW_CLASS:
		var cname := ""
		if kw_idx + 1 < tokens.size() and tokens[kw_idx + 1].type == GUTCheckToken.Type.IDENTIFIER:
			cname = tokens[kw_idx + 1].value
		var info = GUTCheckClassInfo.new(cname, line_num)
		class_stack.append(info)
		map.classes.append(info)

	elif kw.type == GUTCheckToken.Type.KW_MATCH:
		# Push the current indent level so we know pattern lines are at indent+1
		match_indent_stack.append(indent)

	elif kw.type == GUTCheckToken.Type.KW_VAR:
		# Check if this var introduces a property block (trailing colon for get/set)
		if _has_trailing_colon_after_type(tokens):
			property_indent_stack.append(indent)


func _close_scopes_at_indent(indent: int, func_stack: Array,
		class_stack: Array, line_num: int) -> void:
	while func_stack.size() > 0 and func_stack.back().end_line == -1:
		func_stack.back().end_line = line_num - 1
		func_stack.pop_back()
		break

	if func_stack.size() == 0:
		while class_stack.size() > 0 and class_stack.back().end_line == -1:
			class_stack.back().end_line = line_num - 1
			class_stack.pop_back()
			break
