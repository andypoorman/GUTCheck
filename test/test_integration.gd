extends GutTest
## Integration tests that exercise the full tokenizer -> classifier -> instrumenter
## pipeline end-to-end WITHOUT touching collector state. Because these tests
## never call GUTCheckCollector.clear(), register_script(), enable(), or disable(),
## all code paths exercised here count toward self-coverage.


var _tokenizer: GUTCheckTokenizer
var _classifier: GUTCheckLineClassifier
var _instrumenter: GUTCheckInstrumenter


func before_each():
	_tokenizer = GUTCheckTokenizer.new()
	_classifier = GUTCheckLineClassifier.new()
	_instrumenter = GUTCheckInstrumenter.new()


# ---------------------------------------------------------------------------
# Helper: tokenize + classify
# ---------------------------------------------------------------------------

func _classify(source: String) -> GUTCheckScriptMap:
	var tokens = _tokenizer.tokenize(source)
	return _classifier.classify(tokens, "res://test_integration.gd")


func _strip_structure(tokens: Array) -> Array:
	var result: Array = []
	for t in tokens:
		if t.type != GUTCheckToken.Type.NEWLINE and t.type != GUTCheckToken.Type.INDENT \
				and t.type != GUTCheckToken.Type.DEDENT \
				and t.type != GUTCheckToken.Type.EOF and t.type != GUTCheckToken.Type.COMMENT:
			result.append(t)
	return result


# ===========================================================================
# TOKEN TYPES — cold paths not covered by existing test_tokenizer.gd
# ===========================================================================


# ---------------------------------------------------------------------------
# Raw strings
# ---------------------------------------------------------------------------

func test_raw_string_double_quote():
	var tokens = _tokenizer.tokenize('r"hello\\nworld"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_true(meaningful[0].value.begins_with("r"), "Raw string should keep r prefix")


func test_raw_string_single_quote():
	var tokens = _tokenizer.tokenize("r'raw\\tvalue'")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_true(meaningful[0].value.begins_with("r"))


# ---------------------------------------------------------------------------
# Octal numbers
# ---------------------------------------------------------------------------

func test_octal_literal():
	var tokens = _tokenizer.tokenize("0o777")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0o777")


func test_octal_literal_uppercase():
	var tokens = _tokenizer.tokenize("0O755")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0O755")


# ---------------------------------------------------------------------------
# Hex uppercase prefix
# ---------------------------------------------------------------------------

func test_hex_uppercase_prefix():
	var tokens = _tokenizer.tokenize("0XAB")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0XAB")


# ---------------------------------------------------------------------------
# Binary uppercase prefix
# ---------------------------------------------------------------------------

func test_binary_uppercase_prefix():
	var tokens = _tokenizer.tokenize("0B1100")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0B1100")


# ---------------------------------------------------------------------------
# Float starting with dot
# ---------------------------------------------------------------------------

func test_float_starting_with_dot():
	var tokens = _tokenizer.tokenize(".5")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, ".5")


# ---------------------------------------------------------------------------
# Exponent with sign
# ---------------------------------------------------------------------------

func test_exponent_with_plus_sign():
	var tokens = _tokenizer.tokenize("1e+5")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "1e+5")


func test_exponent_with_minus_sign():
	var tokens = _tokenizer.tokenize("2.5E-3")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "2.5E-3")


func test_integer_exponent():
	var tokens = _tokenizer.tokenize("5E10")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "5E10")


# ---------------------------------------------------------------------------
# Three-character operators
# ---------------------------------------------------------------------------

func test_star_star_assign():
	var tokens = _tokenizer.tokenize("x **= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.STAR_STAR_ASSIGN)
	assert_eq(meaningful[1].value, "**=")


func test_lshift_assign():
	var tokens = _tokenizer.tokenize("x <<= 3")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.LSHIFT_ASSIGN)
	assert_eq(meaningful[1].value, "<<=")


func test_rshift_assign():
	var tokens = _tokenizer.tokenize("x >>= 1")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.RSHIFT_ASSIGN)
	assert_eq(meaningful[1].value, ">>=")


# ---------------------------------------------------------------------------
# Two-character operators not yet covered
# ---------------------------------------------------------------------------

func test_percent_assign():
	var tokens = _tokenizer.tokenize("x %= 5")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PERCENT_ASSIGN)


func test_ampersand_assign():
	var tokens = _tokenizer.tokenize("x &= 0xFF")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.AMPERSAND_ASSIGN)


func test_pipe_assign():
	var tokens = _tokenizer.tokenize("x |= 0x0F")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PIPE_ASSIGN)


func test_caret_assign():
	var tokens = _tokenizer.tokenize("x ^= mask")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.CARET_ASSIGN)


func test_lshift_operator():
	var tokens = _tokenizer.tokenize("x << 4")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.LSHIFT)


func test_rshift_operator():
	var tokens = _tokenizer.tokenize("x >> 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.RSHIFT)


func test_bang_not_operator():
	var tokens = _tokenizer.tokenize("!x")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.KW_NOT)
	assert_eq(meaningful[0].value, "!")


# ---------------------------------------------------------------------------
# Single-character operators / punctuation
# ---------------------------------------------------------------------------

func test_tilde_operator():
	var tokens = _tokenizer.tokenize("~bits")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.TILDE)


func test_standalone_ampersand():
	var tokens = _tokenizer.tokenize("a & b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.AMPERSAND)


func test_standalone_pipe():
	var tokens = _tokenizer.tokenize("a | b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PIPE)


func test_standalone_caret():
	# Caret that is NOT followed by quote (so not a NodePath literal)
	var tokens = _tokenizer.tokenize("a ^ b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.CARET)


func test_brace_open_close():
	var tokens = _tokenizer.tokenize("{}")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.BRACE_OPEN)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.BRACE_CLOSE)


func test_semicolon_token():
	var tokens = _tokenizer.tokenize("a; b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.SEMICOLON)


func test_comma_token():
	var tokens = _tokenizer.tokenize("a, b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.COMMA)


func test_standalone_star():
	var tokens = _tokenizer.tokenize("a * b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.STAR)


func test_standalone_slash():
	var tokens = _tokenizer.tokenize("a / b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.SLASH)


func test_standalone_percent():
	var tokens = _tokenizer.tokenize("a % b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PERCENT)


func test_standalone_plus():
	var tokens = _tokenizer.tokenize("a + b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PLUS)


func test_standalone_minus():
	var tokens = _tokenizer.tokenize("a - b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.MINUS)


func test_standalone_assign():
	var tokens = _tokenizer.tokenize("x = 1")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.ASSIGN)


func test_standalone_lt():
	var tokens = _tokenizer.tokenize("a < b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.LT)


func test_standalone_gt():
	var tokens = _tokenizer.tokenize("a > b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.GT)


func test_dot_token():
	var tokens = _tokenizer.tokenize("a.b")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.DOT)


func test_colon_token():
	var tokens = _tokenizer.tokenize("x: int")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.COLON)


func test_bracket_open_close():
	var tokens = _tokenizer.tokenize("[]")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.BRACKET_OPEN)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.BRACKET_CLOSE)


func test_paren_open_close():
	var tokens = _tokenizer.tokenize("()")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.PAREN_OPEN)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PAREN_CLOSE)


# ---------------------------------------------------------------------------
# Keywords — expression keywords not covered by existing tests
# ---------------------------------------------------------------------------

func test_expression_keywords():
	var source = "and or not in is as self super await preload when"
	var tokens = _tokenizer.tokenize(source)
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.KW_AND)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.KW_OR)
	assert_eq(meaningful[2].type, GUTCheckToken.Type.KW_NOT)
	assert_eq(meaningful[3].type, GUTCheckToken.Type.KW_IN)
	assert_eq(meaningful[4].type, GUTCheckToken.Type.KW_IS)
	assert_eq(meaningful[5].type, GUTCheckToken.Type.KW_AS)
	assert_eq(meaningful[6].type, GUTCheckToken.Type.KW_SELF)
	assert_eq(meaningful[7].type, GUTCheckToken.Type.KW_SUPER)
	assert_eq(meaningful[8].type, GUTCheckToken.Type.KW_AWAIT)
	assert_eq(meaningful[9].type, GUTCheckToken.Type.KW_PRELOAD)
	assert_eq(meaningful[10].type, GUTCheckToken.Type.KW_WHEN)


# ---------------------------------------------------------------------------
# Dollar-quoted path
# ---------------------------------------------------------------------------

func test_dollar_quoted_path():
	var tokens = _tokenizer.tokenize('$"Some/Path"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_eq(meaningful[0].value, '$"Some/Path"')


# ---------------------------------------------------------------------------
# Percent-quoted node
# ---------------------------------------------------------------------------

func test_percent_quoted_node():
	var tokens = _tokenizer.tokenize('%"MyNode"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_true(meaningful[0].value.begins_with('%"'))


# ---------------------------------------------------------------------------
# Unterminated strings
# ---------------------------------------------------------------------------

func test_unterminated_string():
	var tokens = _tokenizer.tokenize('"hello')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)


func test_unterminated_string_name():
	var tokens = _tokenizer.tokenize('&"hello')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)


func test_unterminated_node_path_literal():
	var tokens = _tokenizer.tokenize('^"hello')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


# ---------------------------------------------------------------------------
# String with escape in string_name
# ---------------------------------------------------------------------------

func test_string_name_with_escape():
	var tokens = _tokenizer.tokenize('&"he\\nllo"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)


func test_node_path_with_escape():
	var tokens = _tokenizer.tokenize('^"path\\/sub"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


# ---------------------------------------------------------------------------
# Multiline triple-quoted string with code after closing
# ---------------------------------------------------------------------------

func test_triple_quote_multiline_with_code_after():
	var source = '"""\nhello\n""".strip_edges()'
	var tokens = _tokenizer.tokenize(source)
	var has_string = false
	var has_identifier = false
	for t in tokens:
		if t.type == GUTCheckToken.Type.STRING:
			has_string = true
		if t.type == GUTCheckToken.Type.IDENTIFIER and t.value == "strip_edges":
			has_identifier = true
	assert_true(has_string, "Should have STRING token")
	assert_true(has_identifier, "Should find strip_edges after closing triple-quote")


func test_triple_quote_multiline_with_comment_after():
	# The multiline string continuation scanner checks for code/comments after
	# closing triple-quote. A comment after the close should be recognized.
	var source = '"""\ntext\n""" # a comment'
	var tokens = _tokenizer.tokenize(source)
	# The continuation scanner handles comments specially — it only scans for
	# identifiers and operators after close, not comments preceded by space.
	# This tests that the code path runs without error.
	assert_gt(tokens.size(), 0, "Should produce tokens")


# ---------------------------------------------------------------------------
# Indentation — spaces
# ---------------------------------------------------------------------------

func test_indent_with_spaces():
	var source = "if true:\n    pass"
	var tokens = _tokenizer.tokenize(source)
	var types = tokens.map(func(t): return t.type)
	assert_true(GUTCheckToken.Type.INDENT in types, "Should emit INDENT for spaces")


# ---------------------------------------------------------------------------
# Comment-only line with continuation active — bracket depth suppression
# ---------------------------------------------------------------------------

func test_comment_inside_brackets():
	var source = "var x = [\n\t# a comment\n\t1,\n]"
	var tokens = _tokenizer.tokenize(source)
	var comments = tokens.filter(func(t): return t.type == GUTCheckToken.Type.COMMENT)
	assert_eq(comments.size(), 1, "Should find the comment inside brackets")


# ===========================================================================
# TOKEN HELPER METHODS — is_keyword, is_assignment, is_open_group, etc.
# ===========================================================================

func test_token_is_keyword():
	var t = GUTCheckToken.new(GUTCheckToken.Type.KW_IF, "if", 1)
	assert_true(t.is_keyword())
	var t2 = GUTCheckToken.new(GUTCheckToken.Type.KW_PRELOAD, "preload", 1)
	assert_true(t2.is_keyword())
	var t3 = GUTCheckToken.new(GUTCheckToken.Type.IDENTIFIER, "foo", 1)
	assert_false(t3.is_keyword())


func test_token_is_assignment():
	var t = GUTCheckToken.new(GUTCheckToken.Type.ASSIGN, "=", 1)
	assert_true(t.is_assignment())
	var t2 = GUTCheckToken.new(GUTCheckToken.Type.RSHIFT_ASSIGN, ">>=", 1)
	assert_true(t2.is_assignment())
	var t3 = GUTCheckToken.new(GUTCheckToken.Type.PLUS, "+", 1)
	assert_false(t3.is_assignment())


func test_token_is_open_group():
	var t1 = GUTCheckToken.new(GUTCheckToken.Type.PAREN_OPEN, "(", 1)
	var t2 = GUTCheckToken.new(GUTCheckToken.Type.BRACKET_OPEN, "[", 1)
	var t3 = GUTCheckToken.new(GUTCheckToken.Type.BRACE_OPEN, "{", 1)
	assert_true(t1.is_open_group())
	assert_true(t2.is_open_group())
	assert_true(t3.is_open_group())
	var t4 = GUTCheckToken.new(GUTCheckToken.Type.PAREN_CLOSE, ")", 1)
	assert_false(t4.is_open_group())


func test_token_is_close_group():
	var t1 = GUTCheckToken.new(GUTCheckToken.Type.PAREN_CLOSE, ")", 1)
	var t2 = GUTCheckToken.new(GUTCheckToken.Type.BRACKET_CLOSE, "]", 1)
	var t3 = GUTCheckToken.new(GUTCheckToken.Type.BRACE_CLOSE, "}", 1)
	assert_true(t1.is_close_group())
	assert_true(t2.is_close_group())
	assert_true(t3.is_close_group())
	var t4 = GUTCheckToken.new(GUTCheckToken.Type.PAREN_OPEN, "(", 1)
	assert_false(t4.is_close_group())


func test_token_to_string():
	var t = GUTCheckToken.new(GUTCheckToken.Type.KW_IF, "if", 5)
	var s = t._to_string()
	assert_true(s.contains("KW_IF"), "Should contain type name")
	assert_true(s.contains("L5"), "Should contain line number")


# ===========================================================================
# CLASSIFIER — edge cases
# ===========================================================================


# ---------------------------------------------------------------------------
# static func
# ---------------------------------------------------------------------------

func test_static_func_classification():
	var source = "static func bar():\n\tpass"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.FUNC_DEF)
	assert_eq(map.functions[0].is_static, true)
	assert_eq(map.functions[0].name, "bar")


# ---------------------------------------------------------------------------
# Nested match inside function
# ---------------------------------------------------------------------------

func test_nested_match_classification():
	var source = "func foo():\n\tmatch state:\n\t\t0:\n\t\t\tprint('zero')\n\t\t_:\n\t\t\tprint('other')"
	var map = _classify(source)
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.BRANCH_MATCH)
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN)
	assert_eq(map.lines[5].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN)


# ---------------------------------------------------------------------------
# Property accessors with complex types
# ---------------------------------------------------------------------------

func test_property_accessor_with_typed_var():
	var source = "var _val: int = 0\nvar prop: int:\n\tget:\n\t\treturn _val\n\tset(value):\n\t\t_val = value"
	var map = _classify(source)
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR)
	assert_eq(map.lines[5].type, GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR)
	assert_eq(map.lines[4].type, GUTCheckScriptMap.LineType.EXECUTABLE)
	assert_eq(map.lines[6].type, GUTCheckScriptMap.LineType.EXECUTABLE)


# ---------------------------------------------------------------------------
# Inner class with function
# ---------------------------------------------------------------------------

func test_inner_class_classification():
	var source = "class Inner:\n\tvar x = 1\n\tfunc foo():\n\t\tpass"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.CLASS_DEF)
	assert_eq(map.classes.size(), 1)
	assert_eq(map.classes[0].name, "Inner")
	assert_eq(map.functions.size(), 1)
	assert_eq(map.functions[0].name, "foo")


# ---------------------------------------------------------------------------
# Annotation with parentheses (e.g. @export_range(0, 100))
# ---------------------------------------------------------------------------

func test_annotation_with_parens_only():
	var source = "@export_range(0, 100)"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_annotation_with_parens_then_var():
	var source = "@export_range(0, 100) var health: int = 50"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


# ---------------------------------------------------------------------------
# await keyword
# ---------------------------------------------------------------------------

func test_await_is_executable():
	var map = _classify("await get_tree().process_frame")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


# ---------------------------------------------------------------------------
# break / continue
# ---------------------------------------------------------------------------

func test_break_is_executable():
	var map = _classify("break")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


func test_continue_is_executable():
	var map = _classify("continue")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)


# ---------------------------------------------------------------------------
# Semicolons: statement count
# ---------------------------------------------------------------------------

func test_semicolons_statement_count():
	var source = "func foo():\n\tvar a = 1; var b = 2; var c = 3"
	var map = _classify(source)
	assert_eq(map.lines[2].statement_count, 3)


# ---------------------------------------------------------------------------
# Multiline expression with brackets (continuation)
# ---------------------------------------------------------------------------

func test_multiline_dict_continuation():
	var source = "var d = {\n\t\"a\": 1,\n\t\"b\": 2,\n}"
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.EXECUTABLE)
	for ln in [2, 3, 4]:
		if map.lines.has(ln):
			assert_eq(map.lines[ln].type, GUTCheckScriptMap.LineType.CONTINUATION,
				"Line %d should be CONTINUATION" % ln)


# ---------------------------------------------------------------------------
# Static keyword alone (edge case)
# ---------------------------------------------------------------------------

func test_static_alone_non_executable():
	# "static" by itself on a line (unusual but valid parse)
	var tokens = _tokenizer.tokenize("static")
	var map = _classifier.classify(tokens, "test.gd")
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


# ---------------------------------------------------------------------------
# Classifier: func context tracking across lines
# ---------------------------------------------------------------------------

func test_function_context_on_body_lines():
	var source = "func foo():\n\tvar x = 1\n\tvar y = 2\n\treturn x + y"
	var map = _classify(source)
	assert_eq(map.lines[2].function_name, "foo")
	assert_eq(map.lines[3].function_name, "foo")
	assert_eq(map.lines[4].function_name, "foo")


# ---------------------------------------------------------------------------
# Match with when guard
# ---------------------------------------------------------------------------

func test_match_when_guard():
	var source = "func foo():\n\tmatch val:\n\t\tx when x > 0:\n\t\t\tprint(x)"
	var map = _classify(source)
	assert_eq(map.lines[3].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN)


# ===========================================================================
# INSTRUMENTER — full pipeline
# ===========================================================================


func test_instrument_if_elif_else():
	var source = "func foo(x):\n\tif x > 5:\n\t\treturn 1\n\telif x > 0:\n\t\treturn 0\n\telse:\n\t\treturn -1"
	var result = _instrumenter.instrument(source, 99, "res://test_integ.gd")
	assert_gt(result.probe_count, 0)
	assert_string_contains(result.source, "GUTCheckCollector.hit_br2(")
	assert_string_contains(result.source, "GUTCheckCollector.hit(")
	# else line should be unchanged
	var lines = result.source.split("\n")
	assert_eq(lines[5].strip_edges(), "else:")
	# Line count preserved
	assert_eq(lines.size(), source.split("\n").size())


func test_instrument_while_loop():
	var source = "func foo():\n\tvar i = 0\n\twhile i < 10:\n\t\ti += 1"
	var result = _instrumenter.instrument(source, 50)
	assert_string_contains(result.source, "while GUTCheckCollector.hit_br2(")


func test_instrument_for_loop():
	var source = "func foo():\n\tfor i in range(5):\n\t\tprint(i)"
	var result = _instrumenter.instrument(source, 51)
	assert_string_contains(result.source, "GUTCheckCollector.hit_br2rng(")


func test_instrument_match():
	var source = "func foo():\n\tmatch state:\n\t\t0:\n\t\t\tprint('zero')\n\t\t_:\n\t\t\tprint('other')"
	var result = _instrumenter.instrument(source, 52)
	assert_string_contains(result.source, "match GUTCheckCollector.br(")
	assert_gt(result.script_map.branches.size(), 0)


func test_instrument_semicolons():
	var source = "func foo():\n\tvar a = 1; var b = 2; var c = 3"
	var result = _instrumenter.instrument(source, 53)
	var line2 = result.source.split("\n")[1]
	var hit_count = line2.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 3, "Each semicolon-separated statement should get its own probe")


func test_instrument_property_accessor_untouched():
	var source = "var _val: int = 0\nvar prop: int:\n\tget:\n\t\treturn _val\n\tset(value):\n\t\t_val = value"
	var result = _instrumenter.instrument(source, 54)
	var lines = result.source.split("\n")
	# get: and set: lines should not be modified
	assert_eq(lines[2].strip_edges(), "get:")
	assert_eq(lines[4].strip_edges(), "set(value):")


func test_instrument_top_level_var_not_instrumented():
	var source = "var x = 5\nfunc foo():\n\tvar y = 10"
	var result = _instrumenter.instrument(source, 55)
	var lines = result.source.split("\n")
	assert_false(lines[0].contains("GUTCheckCollector"), "Top-level var should not be instrumented")
	assert_true(lines[2].contains("GUTCheckCollector"), "Function body var should be instrumented")


func test_instrument_line_count_complex():
	var source = "extends Node\nclass_name Foo\n\nvar x = 5\n\nfunc foo():\n\tvar a = 1\n\tif a > 0:\n\t\treturn a\n\telse:\n\t\treturn 0\n\nfunc bar():\n\tfor i in range(3):\n\t\tprint(i)\n\twhile true:\n\t\tbreak"
	var result = _instrumenter.instrument(source, 56)
	assert_eq(
		result.source.split("\n").size(),
		source.split("\n").size(),
		"Instrumented source must preserve line count")


func test_instrument_class_def_untouched():
	var source = "class Inner:\n\tvar x = 1\n\tfunc foo():\n\t\tpass"
	var result = _instrumenter.instrument(source, 57)
	var lines = result.source.split("\n")
	assert_false(lines[0].contains("GUTCheckCollector"), "class line should not be instrumented")


# ===========================================================================
# SCRIPT MAP — methods
# ===========================================================================

func test_script_map_get_executable_lines_sorted():
	var source = "func foo():\n\tvar x = 1\n\t# comment\n\tvar y = 2"
	var map = _classify(source)
	var exec = map.get_executable_lines_sorted()
	assert_gt(exec.size(), 0)
	# Should be sorted
	for i in range(exec.size() - 1):
		assert_true(exec[i] < exec[i + 1], "Lines should be sorted ascending")


func test_script_map_get_branches_for_line():
	var source = "func foo():\n\tif x > 0:\n\t\tpass"
	var map = _classify(source)
	var branches = map.get_branches_for_line(2)
	assert_gt(branches.size(), 0, "if line should have branch info")
	# Non-branch line
	var no_branches = map.get_branches_for_line(3)
	assert_eq(no_branches.size(), 0)


func test_script_map_get_function_for_line():
	var source = "func foo():\n\tvar x = 1\n\treturn x"
	var map = _classify(source)
	var func_info = map.get_function_for_line(2)
	assert_not_null(func_info)
	assert_eq(func_info.name, "foo")
	# Line outside functions
	var none = map.get_function_for_line(99)
	assert_null(none)


func test_script_map_assign_branch_probes_if_elif_else():
	var source = "func foo():\n\tif true:\n\t\tpass\n\telif false:\n\t\tpass\n\telse:\n\t\tpass"
	var map = _classify(source)
	# Should have branches for if (2), elif (2), else (1) = 5 total
	assert_eq(map.branches.size(), 5, "if(2) + elif(2) + else(1) = 5 branch probes")
	# Verify branch probes exist for the expected lines
	var branch_lines = {}
	for b in map.branches:
		branch_lines[b.line_number] = true
	assert_true(branch_lines.has(2), "if line should have branch")
	assert_true(branch_lines.has(4), "elif line should have branch")
	assert_true(branch_lines.has(6), "else line should have branch")


func test_script_map_assign_branch_probes_while():
	var source = "func foo():\n\twhile running:\n\t\tpass"
	var map = _classify(source)
	var while_branches = map.get_branches_for_line(2)
	assert_eq(while_branches.size(), 2, "while should have true/false branches")


func test_script_map_assign_branch_probes_for():
	var source = "func foo():\n\tfor i in items:\n\t\tpass"
	var map = _classify(source)
	var for_branches = map.get_branches_for_line(2)
	assert_eq(for_branches.size(), 2, "for should have true/false branches")


func test_script_map_assign_branch_probes_match():
	var source = "func foo():\n\tmatch x:\n\t\t1:\n\t\t\tpass\n\t\t2:\n\t\t\tpass\n\t\t_:\n\t\t\tpass"
	var map = _classify(source)
	# Match patterns should have branch probes
	var pattern_branches = []
	for b in map.branches:
		if b.line_number in [3, 5, 7]:
			pattern_branches.append(b)
	assert_eq(pattern_branches.size(), 3, "Each match arm should get a branch probe")


# ===========================================================================
# EXPORTER — generate without clearing collector
# ===========================================================================
# The exporters read from GUTCheckCollector's current static state. We call
# generate_lcov() and generate_cobertura() on whatever state exists. Since
# the CI run has instrumented scripts registered, these calls exercise real
# exporter code paths and count toward self-coverage.

func test_lcov_exporter_generate():
	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov()
	# In CI self-coverage mode, there WILL be registered scripts.
	# In a bare run, this might be empty — either way the code path is hit.
	assert_true(lcov is String, "generate_lcov should return a String")
	if lcov.length() > 0:
		assert_string_contains(lcov, "SF:")
		assert_string_contains(lcov, "end_of_record")


func test_lcov_exporter_generate_with_test_name():
	var exporter = GUTCheckLcovExporter.new()
	var lcov = exporter.generate_lcov("integration_test")
	assert_true(lcov is String)
	if lcov.length() > 0:
		assert_string_contains(lcov, "TN:integration_test")


func test_cobertura_exporter_generate():
	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()
	assert_true(xml is String, "generate_cobertura should return a String")
	assert_string_contains(xml, '<?xml version="1.0" ?>')
	assert_string_contains(xml, '</coverage>')


func test_cobertura_exporter_generate_with_source_root():
	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura("/home/user/project")
	assert_true(xml is String)
	assert_string_contains(xml, '<sources>')
	assert_string_contains(xml, '/home/user/project')


func test_cobertura_exporter_export_to_disk():
	var exporter = GUTCheckCoberturaExporter.new()
	var tmp_path := "user://test_integration_cobertura.xml"
	var result := exporter.export_cobertura(tmp_path)
	assert_eq(result, OK, "export_cobertura should return OK")
	var file := FileAccess.open(tmp_path, FileAccess.READ)
	assert_not_null(file, "Cobertura XML file should exist on disk")
	if file:
		var content := file.get_as_text()
		file.close()
		assert_string_contains(content, '<?xml version="1.0" ?>')
		assert_string_contains(content, '</coverage>')
		DirAccess.remove_absolute(tmp_path)


func test_cobertura_exporter_export_to_disk_with_source_root():
	var exporter = GUTCheckCoberturaExporter.new()
	var tmp_path := "user://test_integration_cobertura_src.xml"
	var result := exporter.export_cobertura(tmp_path, "/my/project")
	assert_eq(result, OK)
	var file := FileAccess.open(tmp_path, FileAccess.READ)
	assert_not_null(file)
	if file:
		var content := file.get_as_text()
		file.close()
		assert_string_contains(content, '<source>/my/project</source>')
		DirAccess.remove_absolute(tmp_path)


func test_cobertura_exporter_export_bad_path():
	var exporter = GUTCheckCoberturaExporter.new()
	var result := exporter.export_cobertura("/nonexistent/dir/file.xml")
	assert_ne(result, OK, "Bad path should return error")


func test_cobertura_xml_contains_package_and_class_structure():
	# Exercise the full XML generation path including packages, classes,
	# methods, and lines -- all counting toward self-coverage.
	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()
	assert_string_contains(xml, '</coverage>')
	# In self-coverage mode, there will be real registered scripts
	if xml.contains('<package '):
		assert_string_contains(xml, '<classes>')
		assert_string_contains(xml, '</classes>')
		assert_string_contains(xml, '<methods>')
		assert_string_contains(xml, '</methods>')
		assert_string_contains(xml, '<lines>')
		assert_string_contains(xml, '</lines>')
		assert_string_contains(xml, '<line number=')
		assert_string_contains(xml, 'line-rate=')
		assert_string_contains(xml, 'branch-rate=')
		assert_string_contains(xml, 'timestamp=')


func test_cobertura_xml_branch_elements_present():
	# In self-coverage mode, instrumented scripts have branches (if/elif/else).
	# This exercises _emit_line_element's branch path and _get_branch_data_for_line.
	var exporter = GUTCheckCoberturaExporter.new()
	var xml = exporter.generate_cobertura()
	assert_string_contains(xml, '</coverage>')
	if xml.contains('branch="true"'):
		assert_string_contains(xml, 'condition-coverage=')
		assert_string_contains(xml, '<conditions>')
		assert_string_contains(xml, '<condition number=')
		assert_string_contains(xml, 'type="jump"')


# ===========================================================================
# SCRIPT REGISTRY — pure unit tests
# ===========================================================================

func test_script_registry_register_and_lookup():
	var reg = GUTCheckScriptRegistry.new()
	var id1 = reg.register("res://foo.gd")
	var id2 = reg.register("res://bar.gd")
	assert_ne(id1, id2, "Different scripts should get different IDs")
	assert_eq(reg.get_id("res://foo.gd"), id1)
	assert_eq(reg.get_id("res://bar.gd"), id2)
	assert_eq(reg.get_path(id1), "res://foo.gd")
	assert_eq(reg.get_path(id2), "res://bar.gd")


func test_script_registry_duplicate_returns_same_id():
	var reg = GUTCheckScriptRegistry.new()
	var id1 = reg.register("res://foo.gd")
	var id2 = reg.register("res://foo.gd")
	assert_eq(id1, id2, "Re-registering same path should return same ID")


func test_script_registry_unknown_path():
	var reg = GUTCheckScriptRegistry.new()
	assert_eq(reg.get_id("res://unknown.gd"), -1)


func test_script_registry_unknown_id():
	var reg = GUTCheckScriptRegistry.new()
	assert_eq(reg.get_path(999), "")


func test_script_registry_get_all_paths():
	var reg = GUTCheckScriptRegistry.new()
	reg.register("res://a.gd")
	reg.register("res://b.gd")
	reg.register("res://c.gd")
	var paths = reg.get_all_paths()
	assert_eq(paths.size(), 3)
	assert_true("res://a.gd" in paths)
	assert_true("res://b.gd" in paths)
	assert_true("res://c.gd" in paths)


func test_script_registry_get_script_count():
	var reg = GUTCheckScriptRegistry.new()
	assert_eq(reg.get_script_count(), 0)
	reg.register("res://a.gd")
	assert_eq(reg.get_script_count(), 1)
	reg.register("res://b.gd")
	assert_eq(reg.get_script_count(), 2)
	reg.register("res://a.gd")  # duplicate
	assert_eq(reg.get_script_count(), 2)


func test_script_registry_clear():
	var reg = GUTCheckScriptRegistry.new()
	reg.register("res://a.gd")
	reg.register("res://b.gd")
	reg.clear()
	assert_eq(reg.get_script_count(), 0)
	assert_eq(reg.get_all_paths().size(), 0)
	assert_eq(reg.get_id("res://a.gd"), -1)


# ===========================================================================
# COMPLEX PIPELINE — large script through full pipeline
# ===========================================================================

func test_complex_script_full_pipeline():
	var source = """extends Node
class_name ComplexTest

signal health_changed(amount)
enum State { IDLE, RUNNING, DEAD }

const MAX_HP = 100

var hp: int = MAX_HP
var _items: Array = []

@export var speed: float = 5.0
@onready var sprite = $Sprite2D

static func utility() -> int:
	return 42

func _ready():
	var x = 1; var y = 2; var z = 3
	hp = MAX_HP

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	elif amount >= hp:
		hp = 0
		_on_death()
	else:
		hp -= amount
	health_changed.emit(-amount)

func _on_death():
	match State.DEAD:
		State.IDLE:
			pass
		State.RUNNING:
			pass
		State.DEAD:
			print("dead")
		_:
			pass

func process_items():
	for item in _items:
		if item == null:
			continue
		print(item)
	while _items.size() > 10:
		_items.pop_back()

class Inner:
	var value: int = 0
	func get_value():
		return value
"""
	var result = _instrumenter.instrument(source, 77, "res://complex_test.gd")
	assert_eq(
		result.source.split("\n").size(),
		source.split("\n").size(),
		"Line count must be preserved for complex script")
	assert_gt(result.probe_count, 0)
	assert_gt(result.script_map.functions.size(), 3)
	assert_gt(result.script_map.branches.size(), 0)
	assert_gt(result.script_map.classes.size(), 0)

	# Verify non-executable lines are not instrumented
	var lines = result.source.split("\n")
	# "extends Node" — line 0
	assert_false(lines[0].contains("GUTCheckCollector"))
	# "class_name ComplexTest" — line 1
	assert_false(lines[1].contains("GUTCheckCollector"))
	# "signal health_changed" — line 3
	assert_false(lines[3].contains("GUTCheckCollector"))
	# "enum State" — line 4
	assert_false(lines[4].contains("GUTCheckCollector"))
	# "const MAX_HP" — line 6
	assert_false(lines[6].contains("GUTCheckCollector"))


# ===========================================================================
# EDGE CASES — ensures cold paths in _classify_tokens are hit
# ===========================================================================

func test_preload_call_classification():
	var source = 'const Foo = preload("res://foo.gd")'
	var map = _classify(source)
	assert_eq(map.lines[1].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_empty_line_is_non_executable():
	var source = "func foo():\n\n\tpass"
	var map = _classify(source)
	assert_eq(map.lines[2].type, GUTCheckScriptMap.LineType.NON_EXECUTABLE)


func test_multiple_dedents_at_end():
	var source = "func foo():\n\tif true:\n\t\tif false:\n\t\t\tpass"
	var map = _classify(source)
	assert_eq(map.functions.size(), 1)
	assert_gt(map.probe_count, 0)


# ---------------------------------------------------------------------------
# LineInfo is_executable
# ---------------------------------------------------------------------------

func test_line_info_is_executable():
	var exec = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.EXECUTABLE)
	assert_true(exec.is_executable())

	var non_exec = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.NON_EXECUTABLE)
	assert_false(non_exec.is_executable())

	var cont = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.CONTINUATION)
	assert_false(cont.is_executable())

	var func_def = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.FUNC_DEF)
	assert_false(func_def.is_executable())

	var class_def = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.CLASS_DEF)
	assert_false(class_def.is_executable())

	var branch_else = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.BRANCH_ELSE)
	assert_false(branch_else.is_executable())

	var pattern = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.BRANCH_PATTERN)
	assert_false(pattern.is_executable())

	var prop = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR)
	assert_false(prop.is_executable())

	var branch_if = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.BRANCH_IF)
	assert_true(branch_if.is_executable())

	var loop_for = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.LOOP_FOR)
	assert_true(loop_for.is_executable())

	var loop_while = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.LOOP_WHILE)
	assert_true(loop_while.is_executable())

	var match_br = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.BRANCH_MATCH)
	assert_true(match_br.is_executable())


# ===========================================================================
# PROBE INJECTOR — static utility tests
# ===========================================================================


# ---------------------------------------------------------------------------
# get_indent
# ---------------------------------------------------------------------------

func test_probe_injector_get_indent_tabs():
	assert_eq(GUTCheckProbeInjector.get_indent("\t\tvar x = 1"), "\t\t")

func test_probe_injector_get_indent_spaces():
	assert_eq(GUTCheckProbeInjector.get_indent("    var x = 1"), "    ")

func test_probe_injector_get_indent_mixed():
	assert_eq(GUTCheckProbeInjector.get_indent("\t  code"), "\t  ")

func test_probe_injector_get_indent_empty():
	assert_eq(GUTCheckProbeInjector.get_indent(""), "")

func test_probe_injector_get_indent_no_indent():
	assert_eq(GUTCheckProbeInjector.get_indent("var x"), "")


# ---------------------------------------------------------------------------
# find_block_colon
# ---------------------------------------------------------------------------

func test_find_block_colon_simple():
	var pos = GUTCheckProbeInjector.find_block_colon("if x > 0:")
	assert_eq(pos, 8)

func test_find_block_colon_in_string():
	# The colon inside the string should be ignored; only the trailing one counts
	var pos = GUTCheckProbeInjector.find_block_colon('if s == "a:b":')
	assert_eq(pos, 13)

func test_find_block_colon_nested_parens():
	var pos = GUTCheckProbeInjector.find_block_colon("if foo(a, b):")
	assert_eq(pos, 12)

func test_find_block_colon_no_colon():
	var pos = GUTCheckProbeInjector.find_block_colon("var x = 1")
	assert_eq(pos, -1)

func test_find_block_colon_nested_brackets():
	var pos = GUTCheckProbeInjector.find_block_colon("if d[k]:")
	assert_eq(pos, 7)


# ---------------------------------------------------------------------------
# find_for_in
# ---------------------------------------------------------------------------

func test_find_for_in_simple():
	var pos = GUTCheckProbeInjector.find_for_in("for i in range(5):")
	assert_gt(pos, 0)
	assert_eq("for i in range(5):".substr(pos, 4), " in ")

func test_find_for_in_complex_var():
	var pos = GUTCheckProbeInjector.find_for_in("for item in items:")
	assert_gt(pos, 0)

func test_find_for_in_no_in():
	var pos = GUTCheckProbeInjector.find_for_in("for_something:")
	assert_eq(pos, -1)

func test_find_for_in_string_containing_in():
	# " in " inside a string should be skipped
	var pos = GUTCheckProbeInjector.find_for_in('for x in ["in value"]:')
	assert_gt(pos, 0)
	# The first real " in " is before the brackets
	assert_true(pos < 10, "Should find the real 'in', not the one in the string")


# ---------------------------------------------------------------------------
# instrument_semicolon_statements
# ---------------------------------------------------------------------------

func test_instrument_semicolon_two_stmts():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("a = 1; b = 2", 0, 10)
	assert_string_contains(result, "GUTCheckCollector.hit(0,10)")
	assert_string_contains(result, "GUTCheckCollector.hit(0,11)")
	assert_string_contains(result, "a = 1")
	assert_string_contains(result, "b = 2")

func test_instrument_semicolon_single_stmt():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("x = 1", 0, 5)
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")
	assert_string_contains(result, "x = 1")

func test_instrument_semicolon_string_with_semicolon():
	# Semicolons inside strings should not split
	var result = GUTCheckProbeInjector.instrument_semicolon_statements('var s = "a;b"', 0, 0)
	# Should be treated as a single statement
	assert_eq(result.count("GUTCheckCollector.hit("), 1)


# ---------------------------------------------------------------------------
# wrap_condition_br2 — with and without branch probes
# ---------------------------------------------------------------------------

func _make_branch_probes(true_pid: int, false_pid: int) -> Array:
	return [
		GUTCheckBranchInfo.new(1, 0, 0, true_pid, true),
		GUTCheckBranchInfo.new(1, 0, 1, false_pid, false),
	]

func test_wrap_condition_br2_with_branch_probes():
	var bps = _make_branch_probes(10, 11)
	var result = GUTCheckProbeInjector.wrap_condition_br2("if x > 0:", "if", 1, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2(1,5,10,11,")
	assert_string_contains(result, "x > 0")

func test_wrap_condition_br2_without_branch_probes():
	var result = GUTCheckProbeInjector.wrap_condition_br2("if x > 0:", "if", 1, 5, [])
	assert_string_contains(result, "GUTCheckCollector.br(1,5,")

func test_wrap_condition_br2_elif():
	var bps = _make_branch_probes(20, 21)
	var result = GUTCheckProbeInjector.wrap_condition_br2("elif y < 3:", "elif", 2, 8, bps)
	assert_string_contains(result, "elif GUTCheckCollector.hit_br2(2,8,20,21,")

func test_wrap_condition_br2_while():
	var bps = _make_branch_probes(30, 31)
	var result = GUTCheckProbeInjector.wrap_condition_br2("while active:", "while", 3, 9, bps)
	assert_string_contains(result, "while GUTCheckCollector.hit_br2(3,9,30,31,")

func test_wrap_condition_br2_no_colon():
	var result = GUTCheckProbeInjector.wrap_condition_br2("if something", "if", 0, 0, [])
	assert_eq(result, "if something")


# ---------------------------------------------------------------------------
# wrap_for_br2 — with and without branch probes
# ---------------------------------------------------------------------------

func test_wrap_for_br2_with_branch_probes():
	var bps = _make_branch_probes(40, 41)
	var result = GUTCheckProbeInjector.wrap_for_br2("for i in range(5):", 1, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2rng(1,5,40,41,")
	assert_string_contains(result, "range(5)")

func test_wrap_for_br2_without_branch_probes():
	var result = GUTCheckProbeInjector.wrap_for_br2("for i in range(5):", 1, 5, [])
	assert_string_contains(result, "GUTCheckCollector.rng(1,5,")

func test_wrap_for_br2_no_in():
	var result = GUTCheckProbeInjector.wrap_for_br2("for_thing:", 1, 5, [])
	assert_eq(result, "for_thing:")


# ---------------------------------------------------------------------------
# wrap_match
# ---------------------------------------------------------------------------

func test_wrap_match_simple():
	var result = GUTCheckProbeInjector.wrap_match("match state:", 3, 15)
	assert_string_contains(result, "match GUTCheckCollector.br(3,15,state):")

func test_wrap_match_complex_expr():
	var result = GUTCheckProbeInjector.wrap_match("match foo.bar():", 1, 2)
	assert_string_contains(result, "match GUTCheckCollector.br(1,2,foo.bar()):")

func test_wrap_match_no_colon():
	var result = GUTCheckProbeInjector.wrap_match("match something", 0, 0)
	assert_eq(result, "match something")


# ---------------------------------------------------------------------------
# inject_match_pattern_probe — currently a no-op
# ---------------------------------------------------------------------------

func test_inject_match_pattern_probe_returns_content():
	var result = GUTCheckProbeInjector.inject_match_pattern_probe("0:", 1, 5)
	assert_eq(result, "0:", "inject_match_pattern_probe should return content unchanged")


# ---------------------------------------------------------------------------
# instrument_line — dispatch by LineType
# ---------------------------------------------------------------------------

func test_instrument_line_executable():
	var result = GUTCheckProbeInjector.instrument_line("\tvar x = 1", GUTCheckScriptMap.LineType.EXECUTABLE, 0, 5)
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")
	assert_true(result.begins_with("\t"), "Should preserve indent")

func test_instrument_line_executable_multi_stmt():
	var result = GUTCheckProbeInjector.instrument_line("\ta = 1; b = 2", GUTCheckScriptMap.LineType.EXECUTABLE, 0, 5, 2)
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")
	assert_string_contains(result, "GUTCheckCollector.hit(0,6)")

func test_instrument_line_branch_else():
	var result = GUTCheckProbeInjector.instrument_line("\telse:", GUTCheckScriptMap.LineType.BRANCH_ELSE, 0, 0)
	assert_eq(result, "\telse:", "BRANCH_ELSE should be returned unchanged")

func test_instrument_line_property_accessor():
	var result = GUTCheckProbeInjector.instrument_line("\tget:", GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR, 0, 0)
	assert_eq(result, "\tget:", "PROPERTY_ACCESSOR should be returned unchanged")

func test_instrument_line_branch_if():
	var bps = _make_branch_probes(10, 11)
	var result = GUTCheckProbeInjector.instrument_line("\tif x > 0:", GUTCheckScriptMap.LineType.BRANCH_IF, 1, 5, 1, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2(")

func test_instrument_line_branch_elif():
	var bps = _make_branch_probes(20, 21)
	var result = GUTCheckProbeInjector.instrument_line("\telif y:", GUTCheckScriptMap.LineType.BRANCH_ELIF, 1, 5, 1, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2(")

func test_instrument_line_loop_while():
	var bps = _make_branch_probes(30, 31)
	var result = GUTCheckProbeInjector.instrument_line("\twhile active:", GUTCheckScriptMap.LineType.LOOP_WHILE, 1, 5, 1, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2(")

func test_instrument_line_loop_for():
	var bps = _make_branch_probes(40, 41)
	var result = GUTCheckProbeInjector.instrument_line("\tfor i in items:", GUTCheckScriptMap.LineType.LOOP_FOR, 1, 5, 1, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2rng(")

func test_instrument_line_branch_match():
	var result = GUTCheckProbeInjector.instrument_line("\tmatch val:", GUTCheckScriptMap.LineType.BRANCH_MATCH, 1, 5)
	assert_string_contains(result, "match GUTCheckCollector.br(")

func test_instrument_line_branch_pattern_with_probe():
	var bp = GUTCheckBranchInfo.new(1, 0, 0, 99, true)
	var result = GUTCheckProbeInjector.instrument_line("\t0:", GUTCheckScriptMap.LineType.BRANCH_PATTERN, 1, 5, 1, [bp])
	# inject_match_pattern_probe is a no-op, so content is returned unchanged
	assert_eq(result.strip_edges(), "0:")

func test_instrument_line_branch_pattern_no_probe():
	var result = GUTCheckProbeInjector.instrument_line("\t0:", GUTCheckScriptMap.LineType.BRANCH_PATTERN, 1, 5, 1, [])
	assert_eq(result, "\t0:", "BRANCH_PATTERN without probes should be unchanged")

func test_instrument_line_func_def():
	var result = GUTCheckProbeInjector.instrument_line("func foo():", GUTCheckScriptMap.LineType.FUNC_DEF, 0, 0)
	assert_eq(result, "func foo():", "FUNC_DEF should be returned unchanged")

func test_instrument_line_class_def():
	var result = GUTCheckProbeInjector.instrument_line("class Inner:", GUTCheckScriptMap.LineType.CLASS_DEF, 0, 0)
	assert_eq(result, "class Inner:", "CLASS_DEF should be returned unchanged")

func test_instrument_line_non_executable():
	var result = GUTCheckProbeInjector.instrument_line("# comment", GUTCheckScriptMap.LineType.NON_EXECUTABLE, 0, 0)
	assert_eq(result, "# comment", "NON_EXECUTABLE should be returned unchanged")

func test_instrument_line_continuation():
	var result = GUTCheckProbeInjector.instrument_line("\t\"key\": val,", GUTCheckScriptMap.LineType.CONTINUATION, 0, 0)
	assert_eq(result, "\t\"key\": val,", "CONTINUATION should be returned unchanged")

func test_instrument_line_ternary():
	var bps = [
		GUTCheckBranchInfo.new(1, 0, 0, 10, true),
		GUTCheckBranchInfo.new(1, 0, 1, 11, false),
	]
	var result = GUTCheckProbeInjector.instrument_line('\tvar x = "a" if c else "b"', GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY, 1, 5, 1, bps)
	assert_string_contains(result, "GUTCheckCollector.hit(1,5)")
	assert_string_contains(result, "GUTCheckCollector.br2(")


# ---------------------------------------------------------------------------
# instrument_semicolon_statements — string, bracket, and escape edge cases
# ---------------------------------------------------------------------------

func test_semicolon_stmts_with_quoted_string():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements('var s = "a;b"; var t = 1', 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Semicolon inside string should not create extra probe")

func test_semicolon_stmts_with_single_quoted_string():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("var s = 'a;b'; var t = 1", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Semicolon inside single-quoted string should not split")

func test_semicolon_stmts_with_brackets():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("foo(a, b); bar([1, 2])", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Should handle brackets correctly")

func test_semicolon_stmts_with_nested_brackets():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("foo({a: [1]}); bar()", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Should handle nested brackets correctly")

func test_semicolon_stmts_semicolon_in_parens():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("foo(a; b)", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 1, "Semicolon inside parens should not split")

func test_semicolon_stmts_closing_brackets():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("foo(a); bar(b)", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Closing brackets should allow semicolons at depth 0 to split")

func test_semicolon_stmts_empty_trailing():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("a = 1;", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 1, "Trailing semicolon should not create empty statement")

func test_semicolon_stmts_string_close_and_reopen():
	# Test that ending a string and starting a new one works
	var result = GUTCheckProbeInjector.instrument_semicolon_statements('var s = "ab" + "cd"; var t = 1', 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Should handle string close and reopen")

func test_semicolon_stmts_escaped_quote_inside_string():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements('var s = "a\\";b"; var t = 1', 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 2, "Escaped quote inside string should not break semicolon splitting")

func test_semicolon_stmts_regular_chars():
	var result = GUTCheckProbeInjector.instrument_semicolon_statements("abc = xyz", 0, 10)
	var hit_count = result.count("GUTCheckCollector.hit(")
	assert_eq(hit_count, 1, "Regular chars handled by else branch")
	assert_string_contains(result, "abc = xyz")


# ---------------------------------------------------------------------------
# wrap_ternary — edge cases
# ---------------------------------------------------------------------------

func test_wrap_ternary_no_ternary_found():
	var result = GUTCheckProbeInjector.wrap_ternary("var x = 1", 0, 5, [])
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")
	assert_string_contains(result, "var x = 1")

func test_wrap_ternary_with_branch_probes():
	var bps = [
		GUTCheckBranchInfo.new(1, 0, 0, 10, true),
		GUTCheckBranchInfo.new(1, 0, 1, 11, false),
	]
	var result = GUTCheckProbeInjector.wrap_ternary('var x = "yes" if cond else "no"', 0, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.br2(")
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")

func test_wrap_ternary_missing_branch_probes():
	var result = GUTCheckProbeInjector.wrap_ternary('var x = "yes" if cond else "no"', 0, 5, [])
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")

func test_wrap_ternary_multiple_ternaries():
	var bps = [
		GUTCheckBranchInfo.new(1, 0, 0, 10, true),
		GUTCheckBranchInfo.new(1, 0, 1, 11, false),
		GUTCheckBranchInfo.new(1, 1, 0, 12, true),
		GUTCheckBranchInfo.new(1, 1, 1, 13, false),
	]
	var result = GUTCheckProbeInjector.wrap_ternary('"a" if x else "b" if y else "c"', 0, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.hit(0,5)")
	var br2_count = result.count("GUTCheckCollector.br2(")
	assert_eq(br2_count, 2, "Should wrap both ternary conditions")

func test_wrap_ternary_condition_extraction():
	var bps = [
		GUTCheckBranchInfo.new(1, 0, 0, 10, true),
		GUTCheckBranchInfo.new(1, 0, 1, 11, false),
	]
	var result = GUTCheckProbeInjector.wrap_ternary('var x = "yes" if a > b else "no"', 0, 5, bps)
	assert_string_contains(result, "a > b)")
	assert_string_contains(result, " else ")


# ---------------------------------------------------------------------------
# find_ternary_if_positions — string and bracket handling
# ---------------------------------------------------------------------------

func test_find_ternary_positions_simple():
	var result = GUTCheckProbeInjector.find_ternary_if_positions('var x = "yes" if cond else "no"')
	assert_eq(result.size(), 1, "Should find one ternary")

func test_find_ternary_positions_none():
	var result = GUTCheckProbeInjector.find_ternary_if_positions("var x = 1")
	assert_eq(result.size(), 0, "Should find no ternary in simple assignment")

func test_find_ternary_positions_if_in_string():
	var result = GUTCheckProbeInjector.find_ternary_if_positions('var x = "check if true"')
	assert_eq(result.size(), 0, "if inside string should not match")

func test_find_ternary_positions_if_in_brackets():
	var result = GUTCheckProbeInjector.find_ternary_if_positions("var x = foo( a if b else c )")
	assert_eq(result.size(), 0, "if inside brackets should not match at depth>0")

func test_find_ternary_positions_escaped_string():
	var result = GUTCheckProbeInjector.find_ternary_if_positions('var x = "a\\"b" if cond else "c"')
	assert_eq(result.size(), 1, "Should handle escaped quotes in strings")

func test_find_ternary_positions_nested():
	var result = GUTCheckProbeInjector.find_ternary_if_positions('"a" if x else "b" if y else "c"')
	assert_eq(result.size(), 2, "Should find two ternary-ifs in nested expression")

func test_find_ternary_positions_single_quoted_string():
	var result = GUTCheckProbeInjector.find_ternary_if_positions("var x = 'check if true'")
	assert_eq(result.size(), 0, "if inside single-quoted string should not match")

func test_find_ternary_positions_bracket_depth():
	var result = GUTCheckProbeInjector.find_ternary_if_positions("var x = [a if b else c]")
	assert_eq(result.size(), 0, "Ternary inside square brackets should not match")

func test_find_ternary_positions_curly_brackets():
	var result = GUTCheckProbeInjector.find_ternary_if_positions("var x = {a if b else c}")
	assert_eq(result.size(), 0, "Ternary inside curly brackets should not match")

func test_find_ternary_positions_closing_brackets():
	var result = GUTCheckProbeInjector.find_ternary_if_positions("foo(a) if cond else bar(b)")
	assert_eq(result.size(), 1, "Ternary after closing bracket should be detected")


# ---------------------------------------------------------------------------
# _find_matching_else — string and nesting edge cases
# ---------------------------------------------------------------------------

func test_find_matching_else_simple():
	var content = '"yes" if cond else "no"'
	var result = GUTCheckProbeInjector._find_matching_else(content, 10)
	assert_gt(result, 0, "Should find else position")

func test_find_matching_else_nested():
	var content = '"a" if x else "b" if y else "c"'
	var if_pos = content.find(" if ")
	var result = GUTCheckProbeInjector._find_matching_else(content, if_pos + 4)
	assert_gt(result, 0, "Should find matching else")

func test_find_matching_else_string_content():
	var content = 'x if "has else in it" else y'
	var if_pos = content.find(" if ")
	var result = GUTCheckProbeInjector._find_matching_else(content, if_pos + 4)
	assert_gt(result, 0, "Should skip else inside string and find real else")

func test_find_matching_else_brackets():
	var content = 'foo if bar(else_thing) else baz'
	var if_pos = content.find(" if ")
	var result = GUTCheckProbeInjector._find_matching_else(content, if_pos + 4)
	assert_gt(result, 0, "Should skip else inside brackets")

func test_find_matching_else_not_found():
	var content = 'x if cond'
	var result = GUTCheckProbeInjector._find_matching_else(content, 6)
	assert_eq(result, -1, "Should return -1 when no else found")

func test_find_matching_else_escaped_string():
	var content = 'x if "a\\"else" else y'
	var if_pos = content.find(" if ")
	var result = GUTCheckProbeInjector._find_matching_else(content, if_pos + 4)
	assert_gt(result, 0, "Should handle escaped quotes and find real else")

func test_find_matching_else_single_quoted():
	var content = "x if 'has else' else y"
	var if_pos = content.find(" if ")
	var result = GUTCheckProbeInjector._find_matching_else(content, if_pos + 4)
	assert_gt(result, 0, "Should skip else inside single-quoted string")

func test_find_matching_else_nested_ternary_skip():
	var content = 'a if b if c else d else e'
	var result = GUTCheckProbeInjector._find_matching_else(content, 4)
	assert_gt(result, 0, "Should handle nested ternary else skipping")


# ---------------------------------------------------------------------------
# inject_match_pattern_probe — direct call coverage
# ---------------------------------------------------------------------------

func test_inject_match_pattern_probe_direct():
	var result = GUTCheckProbeInjector.inject_match_pattern_probe("42:", 5, 20)
	assert_eq(result, "42:", "Should return content unchanged (no-op)")

func test_inject_match_pattern_probe_string_pattern():
	var result = GUTCheckProbeInjector.inject_match_pattern_probe('"hello":', 3, 15)
	assert_eq(result, '"hello":', "Should return string pattern unchanged")


# ---------------------------------------------------------------------------
# find_block_colon — string and bracket edge cases
# ---------------------------------------------------------------------------

func test_find_block_colon_single_quoted_string():
	var pos = GUTCheckProbeInjector.find_block_colon("if s == 'a:b':")
	assert_eq(pos, 13, "Should handle single-quoted strings")

func test_find_block_colon_string_with_backslash():
	# String contains a backslash — triggers the escape continue path
	var pos = GUTCheckProbeInjector.find_block_colon('if s == "a\\nb"  :')
	assert_gt(pos, -1, "Should handle backslash in strings")

func test_find_block_colon_nested_curly_brackets():
	var pos = GUTCheckProbeInjector.find_block_colon("if foo({a: 1}):")
	assert_eq(pos, 14, "Should skip colons inside nested brackets")

func test_find_block_colon_closing_brackets():
	var pos = GUTCheckProbeInjector.find_block_colon("if (a) and (b):")
	assert_eq(pos, 14, "Should handle closing brackets correctly")


# ---------------------------------------------------------------------------
# find_for_in — string and bracket edge cases
# ---------------------------------------------------------------------------

func test_find_for_in_with_brackets():
	var pos = GUTCheckProbeInjector.find_for_in("for k in foo(bar):")
	assert_eq(pos, 5, "Should find 'in' with bracket expressions")

func test_find_for_in_single_quoted_string():
	var pos = GUTCheckProbeInjector.find_for_in("for x in ['in']:")
	assert_eq(pos, 5, "Should handle single-quoted strings")

func test_find_for_in_nested_brackets():
	var pos = GUTCheckProbeInjector.find_for_in("for x in {a: [1]}:")
	assert_eq(pos, 5, "Should handle nested brackets after 'in'")

func test_find_for_in_escaped_string():
	var pos = GUTCheckProbeInjector.find_for_in('for x in ["a\\"in"]:')
	assert_eq(pos, 5, "Should handle escaped quotes in strings")

func test_find_for_in_closing_brackets():
	var pos = GUTCheckProbeInjector.find_for_in("for (k) in items:")
	assert_gt(pos, 4, "Should handle opening and closing brackets before 'in'")


# ---------------------------------------------------------------------------
# wrap_for_br2 — no-colon edge case
# ---------------------------------------------------------------------------

func test_wrap_for_br2_no_colon_with_in():
	var result = GUTCheckProbeInjector.wrap_for_br2("for i in range(5)", 1, 5, [])
	assert_eq(result, "for i in range(5)", "No colon should return unchanged")


# ---------------------------------------------------------------------------
# wrap_condition_br2 — after_colon and mixed probe scenarios
# ---------------------------------------------------------------------------

func test_wrap_condition_br2_with_after_colon_content():
	var bps = _make_branch_probes(10, 11)
	var result = GUTCheckProbeInjector.wrap_condition_br2("if x > 0: pass", "if", 1, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2(1,5,10,11,")
	assert_string_contains(result, " pass")

func test_wrap_condition_br2_only_true_probe():
	var bps = [GUTCheckBranchInfo.new(1, 0, 0, 10, true)]
	var result = GUTCheckProbeInjector.wrap_condition_br2("if x:", "if", 1, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.br(1,5,")

func test_wrap_condition_br2_extra_spaces():
	var bps = _make_branch_probes(10, 11)
	var result = GUTCheckProbeInjector.wrap_condition_br2("if   x > 0:", "if", 1, 5, bps)
	assert_string_contains(result, "GUTCheckCollector.hit_br2(")
	assert_string_contains(result, "x > 0")


# ===========================================================================
# COVERAGE COMPUTER — static utility tests
# ===========================================================================


# ---------------------------------------------------------------------------
# format_line_ranges
# ---------------------------------------------------------------------------

func test_format_line_ranges_consecutive():
	var lines: Array[int] = [1, 2, 3, 4, 5]
	assert_eq(GUTCheckCoverageComputer.format_line_ranges(lines), "1-5")

func test_format_line_ranges_gaps():
	var lines: Array[int] = [1, 2, 5, 6, 7, 10]
	assert_eq(GUTCheckCoverageComputer.format_line_ranges(lines), "1-2,5-7,10")

func test_format_line_ranges_single_lines():
	var lines: Array[int] = [3, 7, 12]
	assert_eq(GUTCheckCoverageComputer.format_line_ranges(lines), "3,7,12")

func test_format_line_ranges_empty():
	var lines: Array[int] = []
	assert_eq(GUTCheckCoverageComputer.format_line_ranges(lines), "")

func test_format_line_ranges_single_element():
	var lines: Array[int] = [42]
	assert_eq(GUTCheckCoverageComputer.format_line_ranges(lines), "42")

func test_format_line_ranges_mixed():
	var lines: Array[int] = [1, 3, 4, 5, 9]
	assert_eq(GUTCheckCoverageComputer.format_line_ranges(lines), "1,3-5,9")


# ---------------------------------------------------------------------------
# has_inner_classes_in_source
# ---------------------------------------------------------------------------

func test_has_inner_classes_positive():
	var source = "extends Node\n\nclass Inner:\n\tvar x = 1\n"
	assert_true(GUTCheckCoverageComputer.has_inner_classes_in_source(source))

func test_has_inner_classes_negative():
	var source = "extends Node\nvar x = 1\nfunc foo():\n\tpass\n"
	assert_false(GUTCheckCoverageComputer.has_inner_classes_in_source(source))

func test_has_inner_classes_class_name_not_counted():
	var source = "class_name MyScript\nvar x = 1\n"
	assert_false(GUTCheckCoverageComputer.has_inner_classes_in_source(source))

func test_has_inner_classes_indented():
	var source = "func foo():\n\tclass Local:\n\t\tpass\n"
	assert_true(GUTCheckCoverageComputer.has_inner_classes_in_source(source))


# ---------------------------------------------------------------------------
# is_excluded
# ---------------------------------------------------------------------------

func test_is_excluded_match():
	assert_true(GUTCheckCoverageComputer.is_excluded("res://addons/gut/test.gd", ["res://addons/*"]))

func test_is_excluded_no_match():
	assert_false(GUTCheckCoverageComputer.is_excluded("res://src/game.gd", ["res://addons/*"]))

func test_is_excluded_multiple_patterns():
	assert_true(GUTCheckCoverageComputer.is_excluded("res://test/foo.gd", ["res://addons/*", "res://test/*"]))

func test_is_excluded_empty_patterns():
	assert_false(GUTCheckCoverageComputer.is_excluded("res://anything.gd", []))

func test_is_excluded_exact_match():
	assert_true(GUTCheckCoverageComputer.is_excluded("res://specific.gd", ["res://specific.gd"]))


# ---------------------------------------------------------------------------
# parse_lcov_content
# ---------------------------------------------------------------------------

func test_parse_lcov_simple():
	var lcov = "SF:/project/src/a.gd\nLF:10\nLH:8\nend_of_record\n"
	var result = GUTCheckCoverageComputer.parse_lcov_content(lcov)
	assert_true(result.has("/project/src/a.gd"))
	assert_almost_eq(result["/project/src/a.gd"], 80.0, 0.01)
	assert_true(result.has("_total_percentage"))
	assert_almost_eq(result["_total_percentage"], 80.0, 0.01)

func test_parse_lcov_multiple_records():
	var lcov = "SF:/p/a.gd\nLF:10\nLH:5\nend_of_record\nSF:/p/b.gd\nLF:10\nLH:10\nend_of_record\n"
	var result = GUTCheckCoverageComputer.parse_lcov_content(lcov)
	assert_almost_eq(result["/p/a.gd"], 50.0, 0.01)
	assert_almost_eq(result["/p/b.gd"], 100.0, 0.01)
	assert_almost_eq(result["_total_percentage"], 75.0, 0.01)

func test_parse_lcov_with_project_path():
	var lcov = "SF:/home/user/project/src/a.gd\nLF:4\nLH:4\nend_of_record\n"
	var result = GUTCheckCoverageComputer.parse_lcov_content(lcov, "/home/user/project/")
	assert_true(result.has("res://src/a.gd"))
	assert_almost_eq(result["res://src/a.gd"], 100.0, 0.01)

func test_parse_lcov_empty():
	var result = GUTCheckCoverageComputer.parse_lcov_content("")
	assert_false(result.has("_total_percentage"))

func test_parse_lcov_zero_lines():
	var lcov = "SF:/p/empty.gd\nLF:0\nLH:0\nend_of_record\n"
	var result = GUTCheckCoverageComputer.parse_lcov_content(lcov)
	# LF:0 means the file should not get a percentage entry
	assert_false(result.has("/p/empty.gd"))


# ---------------------------------------------------------------------------
# compute_script_coverage — build a ScriptMap with known probes
# ---------------------------------------------------------------------------

func _build_test_script_map() -> GUTCheckScriptMap:
	# Build a minimal script map with 3 executable lines in a function,
	# plus one branch (if) with true/false probes.
	var sm = GUTCheckScriptMap.new()
	sm.path = "res://test_coverage.gd"

	# func foo():       line 1 (FUNC_DEF)
	# \tvar a = 1       line 2 (EXECUTABLE)
	# \tif a > 0:       line 3 (BRANCH_IF)
	# \t\treturn a      line 4 (EXECUTABLE)
	# \tvar b = 2       line 5 (EXECUTABLE)

	sm.lines[1] = GUTCheckLineInfo.new(1, GUTCheckScriptMap.LineType.FUNC_DEF, "foo")
	sm.lines[2] = GUTCheckLineInfo.new(2, GUTCheckScriptMap.LineType.EXECUTABLE, "foo")
	sm.lines[3] = GUTCheckLineInfo.new(3, GUTCheckScriptMap.LineType.BRANCH_IF, "foo")
	sm.lines[4] = GUTCheckLineInfo.new(4, GUTCheckScriptMap.LineType.EXECUTABLE, "foo")
	sm.lines[5] = GUTCheckLineInfo.new(5, GUTCheckScriptMap.LineType.EXECUTABLE, "foo")

	# Function info
	var func_info = GUTCheckFunctionInfo.new("foo", 1)
	func_info.end_line = 5
	sm.functions.append(func_info)

	# Assign line probes: lines 2,3,4,5 are executable -> probe IDs 0,1,2,3
	sm.probe_to_line[0] = 2
	sm.probe_to_line[1] = 3
	sm.probe_to_line[2] = 4
	sm.probe_to_line[3] = 5
	sm.probe_count = 4

	# Branch probes for the if on line 3: true=pid4, false=pid5
	sm.branches.append(GUTCheckBranchInfo.new(3, 0, 0, 4, true))
	sm.branches.append(GUTCheckBranchInfo.new(3, 0, 1, 5, false))
	sm.probe_count = 6

	return sm


func test_compute_script_coverage_all_hit():
	var sm = _build_test_script_map()
	# All line probes hit, both branch probes hit
	var hits := PackedInt32Array([1, 1, 1, 1, 1, 1])
	var result = GUTCheckCoverageComputer.compute_script_coverage(sm, hits)

	assert_eq(result.lines_found, 4, "4 executable lines")
	assert_eq(result.lines_hit, 4)
	assert_almost_eq(result.line_pct, 100.0, 0.01)
	assert_eq(result.branches_found, 2)
	assert_eq(result.branches_hit, 2)
	assert_almost_eq(result.branch_pct, 100.0, 0.01)
	assert_eq(result.funcs_found, 1)
	assert_eq(result.funcs_hit, 1)
	assert_eq(result.uncovered_lines.size(), 0)


func test_compute_script_coverage_partial():
	var sm = _build_test_script_map()
	# Line probes: lines 2,3 hit; lines 4,5 not hit. Branch: true hit, false not.
	var hits := PackedInt32Array([1, 1, 0, 0, 1, 0])
	var result = GUTCheckCoverageComputer.compute_script_coverage(sm, hits)

	assert_eq(result.lines_hit, 2)
	assert_eq(result.lines_found, 4)
	assert_almost_eq(result.line_pct, 50.0, 0.01)
	assert_eq(result.branches_hit, 1)
	assert_eq(result.branches_found, 2)
	assert_true(result.uncovered_lines.size() > 0)


func test_compute_script_coverage_none_hit():
	var sm = _build_test_script_map()
	var hits := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var result = GUTCheckCoverageComputer.compute_script_coverage(sm, hits)

	assert_eq(result.lines_hit, 0)
	assert_almost_eq(result.line_pct, 0.0, 0.01)
	assert_eq(result.branches_hit, 0)
	assert_eq(result.funcs_hit, 0)
	assert_eq(result.uncovered_lines.size(), 4)


# ---------------------------------------------------------------------------
# aggregate_coverage
# ---------------------------------------------------------------------------

func test_aggregate_coverage_multiple_scripts():
	var reports = [
		{
			"lines_found": 10, "lines_hit": 8,
			"branches_found": 4, "branches_hit": 2,
			"funcs_found": 3, "funcs_hit": 3,
		},
		{
			"lines_found": 20, "lines_hit": 10,
			"branches_found": 6, "branches_hit": 6,
			"funcs_found": 5, "funcs_hit": 4,
		},
	]
	var agg = GUTCheckCoverageComputer.aggregate_coverage(reports)
	assert_eq(agg.total_lines_found, 30)
	assert_eq(agg.total_lines_hit, 18)
	assert_almost_eq(agg.total_line_pct, 60.0, 0.01)
	assert_eq(agg.total_branches_found, 10)
	assert_eq(agg.total_branches_hit, 8)
	assert_almost_eq(agg.total_branch_pct, 80.0, 0.01)
	assert_eq(agg.total_funcs_found, 8)
	assert_eq(agg.total_funcs_hit, 7)

func test_aggregate_coverage_empty():
	var agg = GUTCheckCoverageComputer.aggregate_coverage([])
	assert_eq(agg.total_lines_found, 0)
	assert_eq(agg.total_lines_hit, 0)
	assert_almost_eq(agg.total_line_pct, 0.0, 0.01)

func test_aggregate_coverage_single():
	var reports = [{
		"lines_found": 5, "lines_hit": 5,
		"branches_found": 0, "branches_hit": 0,
		"funcs_found": 1, "funcs_hit": 1,
	}]
	var agg = GUTCheckCoverageComputer.aggregate_coverage(reports)
	assert_eq(agg.total_lines_found, 5)
	assert_almost_eq(agg.total_line_pct, 100.0, 0.01)
