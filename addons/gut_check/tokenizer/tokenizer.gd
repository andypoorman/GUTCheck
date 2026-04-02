class_name GUTCheckTokenizer
## Line-oriented GDScript tokenizer.
##
## Converts GDScript source code into a stream of tokens. Handles indentation
## tracking, multiline strings, line continuations, and all GDScript syntax.

var _source: String
var _lines: PackedStringArray
var _tokens: Array

# Multiline state
var _in_multiline_string: bool = false
var _multiline_quote_char: String = ""
var _multiline_start_line: int = 0

# Indentation
var _indent_stack: Array[int] = [0]

# Line continuation
var _continuation: bool = false

# Bracket depth — suppress INDENT/DEDENT inside (), [], {}
var _bracket_depth: int = 0


func tokenize(source: String) -> Array:
	_source = source
	_lines = source.split("\n")
	_tokens = []
	_indent_stack = [0]
	_in_multiline_string = false
	_continuation = false
	_bracket_depth = 0

	for i in range(_lines.size()):
		_tokenize_line(i)

	# Emit remaining DEDENTs
	while _indent_stack.size() > 1:
		_indent_stack.pop_back()
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.DEDENT, "", _lines.size(), 0))

	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.EOF, "", _lines.size() + 1, 0))
	return _tokens


func _tokenize_line(line_idx: int) -> void:
	var line := _lines[line_idx]
	var line_num := line_idx + 1

	# If we're inside a multiline string, scan for the closing triple-quote
	if _in_multiline_string:
		_scan_multiline_string_continuation(line, line_num)
		return

	# Count leading whitespace for indentation
	var indent := _count_indent(line)
	var content_start := _count_indent_chars(line)
	var stripped := line.strip_edges()

	# Blank line
	if stripped.is_empty():
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NEWLINE, "", line_num, 0))
		return

	# Comment-only line (but still need to handle indentation)
	if stripped.begins_with("#"):
		if not _continuation and _bracket_depth == 0:
			_emit_indent_tokens(indent, line_num)
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.COMMENT, stripped, line_num, content_start))
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NEWLINE, "", line_num, 0))
		return

	# Emit indent/dedent tokens (not during line continuation or inside brackets)
	if not _continuation and _bracket_depth == 0:
		_emit_indent_tokens(indent, line_num)

	_continuation = false

	# Scan the line content character by character
	var pos := content_start
	var length := line.length()

	while pos < length:
		var c := line[pos]

		# Skip whitespace within line
		if c == " " or c == "\t":
			pos += 1
			continue

		# Comment - rest of line
		if c == "#":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.COMMENT, line.substr(pos), line_num, pos))
			break

		# Line continuation
		if c == "\\":
			_continuation = true
			pos += 1
			continue

		# Raw strings: r"..." or r'...'
		if c == "r" and pos + 1 < length and (line[pos + 1] == '"' or line[pos + 1] == "'"):
			pos = _scan_raw_string(line, pos, line_num)
			continue

		# String literals
		if c == '"' or c == "'":
			pos = _scan_string(line, pos, line_num)
			continue

		# StringName: &"..." or &'...'
		if c == "&" and pos + 1 < length and (line[pos + 1] == '"' or line[pos + 1] == "'"):
			pos = _scan_string_name(line, pos, line_num)
			continue

		# NodePath: ^"..."
		if c == "^" and pos + 1 < length and (line[pos + 1] == '"' or line[pos + 1] == "'"):
			pos = _scan_node_path_literal(line, pos, line_num)
			continue

		# NodePath shorthand: $NodePath or $"path"
		if c == "$":
			pos = _scan_dollar_path(line, pos, line_num)
			continue

		# Annotation: @word
		if c == "@":
			pos = _scan_annotation(line, pos, line_num)
			continue

		# Numbers
		if c.is_valid_int() or (c == "." and pos + 1 < length and line[pos + 1].is_valid_int()):
			pos = _scan_number(line, pos, line_num)
			continue

		# Identifiers and keywords
		if _is_identifier_start(c):
			pos = _scan_identifier(line, pos, line_num)
			continue

		# Multi-character operators (check longest match first)
		var op_result := _scan_operator(line, pos, line_num)
		if op_result > pos:
			pos = op_result
			continue

		# Unknown character - skip it
		pos += 1

	# End of line
	if not _continuation:
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NEWLINE, "", line_num, 0))


func _count_indent(line: String) -> int:
	## Returns the logical indent level (tabs count as 4 spaces).
	var count := 0
	for i in range(line.length()):
		if line[i] == "\t":
			count += 4  # Treat tabs as 4 spaces (Godot default)
		elif line[i] == " ":
			count += 1
		else:
			break
	return count


func _count_indent_chars(line: String) -> int:
	## Returns the number of actual whitespace characters at the start of line.
	var count := 0
	for i in range(line.length()):
		if line[i] == "\t" or line[i] == " ":
			count += 1
		else:
			break
	return count


func _emit_indent_tokens(indent: int, line_num: int) -> void:
	if indent > _indent_stack.back():
		_indent_stack.push_back(indent)
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.INDENT, "", line_num, 0))
	else:
		while indent < _indent_stack.back():
			_indent_stack.pop_back()
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.DEDENT, "", line_num, 0))


func _is_identifier_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


func _is_identifier_char(c: String) -> bool:
	return _is_identifier_start(c) or c.is_valid_int()


# ---------------------------------------------------------------------------
# String scanning
# ---------------------------------------------------------------------------

func _scan_string(line: String, pos: int, line_num: int, is_raw: bool = false) -> int:
	var quote := line[pos]
	var length := line.length()

	# Check for triple-quoted string
	if pos + 2 < length and line[pos + 1] == quote and line[pos + 2] == quote:
		return _scan_triple_quoted_string(line, pos, line_num, quote)

	# Regular single-line string
	var start := pos
	pos += 1  # skip opening quote

	while pos < length:
		var c := line[pos]
		if c == "\\" and not is_raw:
			pos += 2  # skip escape sequence
			continue
		if c == quote:
			pos += 1  # skip closing quote
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STRING, line.substr(start, pos - start), line_num, start))
			return pos
		pos += 1

	# Unterminated string on this line - emit what we have
	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STRING, line.substr(start), line_num, start))
	return length


func _scan_raw_string(line: String, pos: int, line_num: int) -> int:
	# r"..." or r'...' — backslash is not an escape character
	var start := pos
	pos += 1  # skip 'r'
	# Delegate to _scan_string with is_raw=true, but fix up the start position
	var inner_start := pos
	var result := _scan_string(line, pos, line_num, true)
	# Replace the token we just emitted to include the 'r' prefix
	if _tokens.size() > 0 and _tokens.back().line == line_num:
		var last_token = _tokens.back()
		_tokens[_tokens.size() - 1] = GUTCheckToken.new(
			last_token.type, "r" + last_token.value, line_num, start)
	return result


func _scan_triple_quoted_string(line: String, pos: int, line_num: int, quote: String) -> int:
	var triple := quote + quote + quote
	var start := pos
	pos += 3  # skip opening triple quote

	# Search for closing triple-quote on same line
	var close_pos := line.find(triple, pos)
	if close_pos != -1:
		pos = close_pos + 3
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STRING, line.substr(start, pos - start), line_num, start))
		return pos

	# Multiline string - store state and consume rest of line
	_in_multiline_string = true
	_multiline_quote_char = quote
	_multiline_start_line = line_num
	# Don't emit token yet - will emit when we find the closing triple-quote
	return line.length()


func _scan_multiline_string_continuation(line: String, line_num: int) -> void:
	var triple := _multiline_quote_char + _multiline_quote_char + _multiline_quote_char
	var close_pos := line.find(triple)

	if close_pos != -1:
		# Found the closing triple-quote
		_in_multiline_string = false
		var after_close := close_pos + 3
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STRING, triple, line_num, 0))

		# Continue scanning any code after the closing triple-quote on this line
		if after_close < line.length():
			var rest := line.substr(after_close)
			var rest_stripped := rest.strip_edges()
			if not rest_stripped.is_empty() and not rest_stripped.begins_with("#"):
				# There's code after the closing triple-quote — scan it
				var temp_pos := after_close
				while temp_pos < line.length():
					var c := line[temp_pos]
					if c == " " or c == "\t":
						temp_pos += 1
						continue
					if c == "#":
						_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.COMMENT, line.substr(temp_pos), line_num, temp_pos))
						break
					if _is_identifier_start(c):
						temp_pos = _scan_identifier(line, temp_pos, line_num)
						continue
					if c == "." or c == "(" or c == ")" or c == "[" or c == "]":
						var op_result := _scan_operator(line, temp_pos, line_num)
						if op_result > temp_pos:
							temp_pos = op_result
							continue
					temp_pos += 1

		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NEWLINE, "", line_num, 0))
	# else: still inside multiline string — don't emit tokens


func _scan_string_name(line: String, pos: int, line_num: int) -> int:
	var start := pos
	pos += 1  # skip &
	var quote := line[pos]
	pos += 1  # skip opening quote

	while pos < line.length():
		var c := line[pos]
		if c == "\\":
			pos += 2
			continue
		if c == quote:
			pos += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STRING_NAME, line.substr(start, pos - start), line_num, start))
			return pos
		pos += 1

	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STRING_NAME, line.substr(start), line_num, start))
	return line.length()


func _scan_node_path_literal(line: String, pos: int, line_num: int) -> int:
	var start := pos
	pos += 1  # skip ^
	var quote := line[pos]
	pos += 1  # skip opening quote

	while pos < line.length():
		var c := line[pos]
		if c == "\\":
			pos += 2
			continue
		if c == quote:
			pos += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NODE_PATH, line.substr(start, pos - start), line_num, start))
			return pos
		pos += 1

	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NODE_PATH, line.substr(start), line_num, start))
	return line.length()


func _scan_dollar_path(line: String, pos: int, line_num: int) -> int:
	var start := pos
	pos += 1  # skip $

	if pos < line.length() and (line[pos] == '"' or line[pos] == "'"):
		# $"quoted path"
		var quote := line[pos]
		pos += 1
		while pos < line.length():
			if line[pos] == "\\":
				pos += 2
				continue
			if line[pos] == quote:
				pos += 1
				break
			pos += 1
	else:
		# $UnquotedPath/Chain
		while pos < line.length() and (_is_identifier_char(line[pos]) or line[pos] == "/"):
			pos += 1

	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NODE_PATH, line.substr(start, pos - start), line_num, start))
	return pos


# ---------------------------------------------------------------------------
# Annotation scanning
# ---------------------------------------------------------------------------

func _scan_annotation(line: String, pos: int, line_num: int) -> int:
	var start := pos
	pos += 1  # skip @

	# Read the annotation name
	while pos < line.length() and _is_identifier_char(line[pos]):
		pos += 1

	var annotation_text := line.substr(start, pos - start)
	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.ANNOTATION, annotation_text, line_num, start))
	return pos


# ---------------------------------------------------------------------------
# Number scanning
# ---------------------------------------------------------------------------

func _scan_number(line: String, pos: int, line_num: int) -> int:
	var start := pos
	var length := line.length()
	var is_float := false

	# Check for hex, binary, octal prefix
	if line[pos] == "0" and pos + 1 < length:
		var next := line[pos + 1]
		if next == "x" or next == "X":
			pos += 2
			while pos < length and (_is_hex_char(line[pos]) or line[pos] == "_"):
				pos += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.INTEGER, line.substr(start, pos - start), line_num, start))
			return pos
		elif next == "b" or next == "B":
			pos += 2
			while pos < length and (line[pos] == "0" or line[pos] == "1" or line[pos] == "_"):
				pos += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.INTEGER, line.substr(start, pos - start), line_num, start))
			return pos
		elif next == "o" or next == "O":
			pos += 2
			while pos < length and ((line[pos] >= "0" and line[pos] <= "7") or line[pos] == "_"):
				pos += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.INTEGER, line.substr(start, pos - start), line_num, start))
			return pos

	# Regular decimal number
	while pos < length and (line[pos].is_valid_int() or line[pos] == "_"):
		pos += 1

	# Decimal point
	if pos < length and line[pos] == ".":
		# Check it's not the .. operator
		if pos + 1 < length and line[pos + 1] == ".":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.INTEGER, line.substr(start, pos - start), line_num, start))
			return pos
		is_float = true
		pos += 1
		while pos < length and (line[pos].is_valid_int() or line[pos] == "_"):
			pos += 1

	# Exponent
	if pos < length and (line[pos] == "e" or line[pos] == "E"):
		is_float = true
		pos += 1
		if pos < length and (line[pos] == "+" or line[pos] == "-"):
			pos += 1
		while pos < length and (line[pos].is_valid_int() or line[pos] == "_"):
			pos += 1

	var token_type := GUTCheckToken.Type.FLOAT if is_float else GUTCheckToken.Type.INTEGER
	_tokens.append(GUTCheckToken.new(token_type, line.substr(start, pos - start), line_num, start))
	return pos


func _is_hex_char(c: String) -> bool:
	return c.is_valid_int() or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")


# ---------------------------------------------------------------------------
# Identifier / keyword scanning
# ---------------------------------------------------------------------------

func _scan_identifier(line: String, pos: int, line_num: int) -> int:
	var start := pos
	while pos < line.length() and _is_identifier_char(line[pos]):
		pos += 1

	var word := line.substr(start, pos - start)

	# Check if it's a keyword
	if GUTCheckToken.KEYWORDS.has(word):
		_tokens.append(GUTCheckToken.new(GUTCheckToken.KEYWORDS[word], word, line_num, start))
	else:
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.IDENTIFIER, word, line_num, start))

	return pos


# ---------------------------------------------------------------------------
# Operator scanning
# ---------------------------------------------------------------------------

func _scan_operator(line: String, pos: int, line_num: int) -> int:
	var length := line.length()
	var c := line[pos]
	var next := line[pos + 1] if pos + 1 < length else ""
	var next2 := line[pos + 2] if pos + 2 < length else ""

	# Three-character operators
	if c == "*" and next == "*" and next2 == "=":
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STAR_STAR_ASSIGN, "**=", line_num, pos))
		return pos + 3
	if c == "<" and next == "<" and next2 == "=":
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.LSHIFT_ASSIGN, "<<=", line_num, pos))
		return pos + 3
	if c == ">" and next == ">" and next2 == "=":
		_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.RSHIFT_ASSIGN, ">>=", line_num, pos))
		return pos + 3

	# Two-character operators
	match c:
		"*":
			if next == "*":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STAR_STAR, "**", line_num, pos))
				return pos + 2
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STAR_ASSIGN, "*=", line_num, pos))
				return pos + 2
		"=":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.EQ, "==", line_num, pos))
				return pos + 2
		"!":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NE, "!=", line_num, pos))
				return pos + 2
			# Standalone ! (negation, same as not)
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.KW_NOT, "!", line_num, pos))
			return pos + 1
		"<":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.LE, "<=", line_num, pos))
				return pos + 2
			if next == "<":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.LSHIFT, "<<", line_num, pos))
				return pos + 2
		">":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.GE, ">=", line_num, pos))
				return pos + 2
			if next == ">":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.RSHIFT, ">>", line_num, pos))
				return pos + 2
		"+":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PLUS_ASSIGN, "+=", line_num, pos))
				return pos + 2
		"-":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.MINUS_ASSIGN, "-=", line_num, pos))
				return pos + 2
			if next == ">":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.ARROW, "->", line_num, pos))
				return pos + 2
		"/":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.SLASH_ASSIGN, "/=", line_num, pos))
				return pos + 2
		"%":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PERCENT_ASSIGN, "%=", line_num, pos))
				return pos + 2
			# % as unique node reference: %NodeName
			if _is_identifier_start(next) or next == '"' or next == "'":
				return _scan_percent_node(line, pos, line_num)
		"&":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.AMPERSAND_ASSIGN, "&=", line_num, pos))
				return pos + 2
		"|":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PIPE_ASSIGN, "|=", line_num, pos))
				return pos + 2
		"^":
			if next == "=":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.CARET_ASSIGN, "^=", line_num, pos))
				return pos + 2
		".":
			if next == ".":
				_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.DOT_DOT, "..", line_num, pos))
				return pos + 2

	# Single-character operators — track bracket depth
	match c:
		"+":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PLUS, "+", line_num, pos))
		"-":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.MINUS, "-", line_num, pos))
		"*":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.STAR, "*", line_num, pos))
		"/":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.SLASH, "/", line_num, pos))
		"%":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PERCENT, "%", line_num, pos))
		"=":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.ASSIGN, "=", line_num, pos))
		"<":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.LT, "<", line_num, pos))
		">":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.GT, ">", line_num, pos))
		"&":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.AMPERSAND, "&", line_num, pos))
		"|":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PIPE, "|", line_num, pos))
		"^":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.CARET, "^", line_num, pos))
		"~":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.TILDE, "~", line_num, pos))
		".":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.DOT, ".", line_num, pos))
		":":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.COLON, ":", line_num, pos))
		";":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.SEMICOLON, ";", line_num, pos))
		",":
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.COMMA, ",", line_num, pos))
		"(":
			_bracket_depth += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PAREN_OPEN, "(", line_num, pos))
		")":
			_bracket_depth = maxi(0, _bracket_depth - 1)
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.PAREN_CLOSE, ")", line_num, pos))
		"[":
			_bracket_depth += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.BRACKET_OPEN, "[", line_num, pos))
		"]":
			_bracket_depth = maxi(0, _bracket_depth - 1)
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.BRACKET_CLOSE, "]", line_num, pos))
		"{":
			_bracket_depth += 1
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.BRACE_OPEN, "{", line_num, pos))
		"}":
			_bracket_depth = maxi(0, _bracket_depth - 1)
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.BRACE_CLOSE, "}", line_num, pos))
		"\\": # standalone backslash not at end of line
			_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.BACKSLASH, "\\", line_num, pos))
		_:
			# Unknown single character - skip
			pass

	return pos + 1


func _scan_percent_node(line: String, pos: int, line_num: int) -> int:
	var start := pos
	pos += 1  # skip %

	if pos < line.length() and (line[pos] == '"' or line[pos] == "'"):
		# %"quoted name"
		var quote := line[pos]
		pos += 1
		while pos < line.length():
			if line[pos] == "\\":
				pos += 2
				continue
			if line[pos] == quote:
				pos += 1
				break
			pos += 1
	else:
		# %UnquotedName
		while pos < line.length() and _is_identifier_char(line[pos]):
			pos += 1

	_tokens.append(GUTCheckToken.new(GUTCheckToken.Type.NODE_PATH, line.substr(start, pos - start), line_num, start))
	return pos
