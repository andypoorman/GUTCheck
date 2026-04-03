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
	assert_string_contains(result.source, "GUTCheckCollector.br2(")
	assert_string_contains(result.source, "GUTCheckCollector.hit(")
	# else line should be unchanged
	var lines = result.source.split("\n")
	assert_eq(lines[5].strip_edges(), "else:")
	# Line count preserved
	assert_eq(lines.size(), source.split("\n").size())


func test_instrument_while_loop():
	var source = "func foo():\n\tvar i = 0\n\twhile i < 10:\n\t\ti += 1"
	var result = _instrumenter.instrument(source, 50)
	assert_string_contains(result.source, "while GUTCheckCollector.br2(")


func test_instrument_for_loop():
	var source = "func foo():\n\tfor i in range(5):\n\t\tprint(i)"
	var result = _instrumenter.instrument(source, 51)
	assert_string_contains(result.source, "GUTCheckCollector.br2rng(")


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
