extends GutTest

var _tokenizer: GUTCheckTokenizer


func before_each():
	_tokenizer = GUTCheckTokenizer.new()


# ---------------------------------------------------------------------------
# Basic token types
# ---------------------------------------------------------------------------

func test_empty_source():
	var tokens = _tokenizer.tokenize("")
	assert_eq(tokens.back().type, GUTCheckToken.Type.EOF)


func test_single_identifier():
	var tokens = _tokenizer.tokenize("foo")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.IDENTIFIER)
	assert_eq(meaningful[0].value, "foo")


func test_keywords():
	var source = "if elif else for while match return break continue pass var const func class extends signal enum static"
	var tokens = _tokenizer.tokenize(source)
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.KW_IF)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.KW_ELIF)
	assert_eq(meaningful[2].type, GUTCheckToken.Type.KW_ELSE)
	assert_eq(meaningful[3].type, GUTCheckToken.Type.KW_FOR)
	assert_eq(meaningful[4].type, GUTCheckToken.Type.KW_WHILE)
	assert_eq(meaningful[5].type, GUTCheckToken.Type.KW_MATCH)
	assert_eq(meaningful[6].type, GUTCheckToken.Type.KW_RETURN)
	assert_eq(meaningful[7].type, GUTCheckToken.Type.KW_BREAK)
	assert_eq(meaningful[8].type, GUTCheckToken.Type.KW_CONTINUE)
	assert_eq(meaningful[9].type, GUTCheckToken.Type.KW_PASS)
	assert_eq(meaningful[10].type, GUTCheckToken.Type.KW_VAR)
	assert_eq(meaningful[11].type, GUTCheckToken.Type.KW_CONST)
	assert_eq(meaningful[12].type, GUTCheckToken.Type.KW_FUNC)
	assert_eq(meaningful[13].type, GUTCheckToken.Type.KW_CLASS)
	assert_eq(meaningful[14].type, GUTCheckToken.Type.KW_EXTENDS)
	assert_eq(meaningful[15].type, GUTCheckToken.Type.KW_SIGNAL)
	assert_eq(meaningful[16].type, GUTCheckToken.Type.KW_ENUM)
	assert_eq(meaningful[17].type, GUTCheckToken.Type.KW_STATIC)


func test_class_name_keyword():
	var tokens = _tokenizer.tokenize("class_name Foo")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.KW_CLASS_NAME)
	assert_eq(meaningful[0].value, "class_name")
	assert_eq(meaningful[1].type, GUTCheckToken.Type.IDENTIFIER)
	assert_eq(meaningful[1].value, "Foo")


func test_boolean_and_null():
	var tokens = _tokenizer.tokenize("true false null")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.TRUE)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.FALSE)
	assert_eq(meaningful[2].type, GUTCheckToken.Type.NULL)


# ---------------------------------------------------------------------------
# Numbers
# ---------------------------------------------------------------------------

func test_integer_literal():
	var tokens = _tokenizer.tokenize("42")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "42")


func test_float_literal():
	var tokens = _tokenizer.tokenize("3.14")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "3.14")


func test_hex_literal():
	var tokens = _tokenizer.tokenize("0xFF")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0xFF")


func test_binary_literal():
	var tokens = _tokenizer.tokenize("0b1010")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0b1010")


func test_scientific_notation():
	var tokens = _tokenizer.tokenize("1.5e10")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "1.5e10")


func test_underscore_in_number():
	var tokens = _tokenizer.tokenize("1_000_000")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "1_000_000")


# ---------------------------------------------------------------------------
# Strings
# ---------------------------------------------------------------------------

func test_double_quoted_string():
	var tokens = _tokenizer.tokenize('"hello world"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_eq(meaningful[0].value, '"hello world"')


func test_single_quoted_string():
	var tokens = _tokenizer.tokenize("'hello'")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_eq(meaningful[0].value, "'hello'")


func test_string_with_escape():
	var tokens = _tokenizer.tokenize('"hello\\nworld"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)


func test_string_with_hash():
	var tokens = _tokenizer.tokenize('"hello # not a comment"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_eq(meaningful.size(), 1, "Hash inside string should not create a comment token")


func test_string_name():
	var tokens = _tokenizer.tokenize('&"my_name"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)


func test_node_path_caret():
	var tokens = _tokenizer.tokenize('^"some/path"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


func test_triple_quoted_string_single_line():
	var tokens = _tokenizer.tokenize('"""hello"""')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)


func test_triple_quoted_string_multiline():
	var source = '"""\nhello\nworld\n"""'
	var tokens = _tokenizer.tokenize(source)
	var identifiers = tokens.filter(func(t): return t.type == GUTCheckToken.Type.IDENTIFIER)
	assert_eq(identifiers.size(), 0, "Content inside triple-quoted strings should not be tokenized as identifiers")


# ---------------------------------------------------------------------------
# Operators
# ---------------------------------------------------------------------------

func test_comparison_operators():
	var tokens = _tokenizer.tokenize("== != <= >= < >")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.EQ)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.NE)
	assert_eq(meaningful[2].type, GUTCheckToken.Type.LE)
	assert_eq(meaningful[3].type, GUTCheckToken.Type.GE)
	assert_eq(meaningful[4].type, GUTCheckToken.Type.LT)
	assert_eq(meaningful[5].type, GUTCheckToken.Type.GT)


func test_assignment_operators():
	var tokens = _tokenizer.tokenize("+= -= *= /=")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.PLUS_ASSIGN)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.MINUS_ASSIGN)
	assert_eq(meaningful[2].type, GUTCheckToken.Type.STAR_ASSIGN)
	assert_eq(meaningful[3].type, GUTCheckToken.Type.SLASH_ASSIGN)


func test_arrow_operator():
	var tokens = _tokenizer.tokenize("->")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.ARROW)


func test_power_operator():
	var tokens = _tokenizer.tokenize("**")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STAR_STAR)


func test_dotdot_operator():
	var tokens = _tokenizer.tokenize("0..10")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.DOT_DOT)
	assert_eq(meaningful[2].type, GUTCheckToken.Type.INTEGER)


# ---------------------------------------------------------------------------
# Indentation
# ---------------------------------------------------------------------------

func test_indent_dedent():
	var source = "if true:\n\tpass"
	var tokens = _tokenizer.tokenize(source)
	var types = tokens.map(func(t): return t.type)
	assert_true(GUTCheckToken.Type.INDENT in types, "Should emit INDENT token")


func test_nested_indent_dedent():
	var source = "if true:\n\tif false:\n\t\tpass\nvar x = 1"
	var tokens = _tokenizer.tokenize(source)
	var indents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.INDENT)
	var dedents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.DEDENT)
	assert_eq(indents.size(), 2, "Should have 2 INDENT tokens")
	assert_eq(dedents.size(), 2, "Should have 2 DEDENT tokens")


# ---------------------------------------------------------------------------
# Comments
# ---------------------------------------------------------------------------

func test_comment_only_line():
	var tokens = _tokenizer.tokenize("# this is a comment")
	var comments = tokens.filter(func(t): return t.type == GUTCheckToken.Type.COMMENT)
	assert_eq(comments.size(), 1)


func test_inline_comment():
	var source = "var x = 5 # inline comment"
	var tokens = _tokenizer.tokenize(source)
	var comments = tokens.filter(func(t): return t.type == GUTCheckToken.Type.COMMENT)
	var vars_found = tokens.filter(func(t): return t.type == GUTCheckToken.Type.KW_VAR)
	assert_eq(comments.size(), 1)
	assert_eq(vars_found.size(), 1)


# ---------------------------------------------------------------------------
# Annotations
# ---------------------------------------------------------------------------

func test_annotation():
	var tokens = _tokenizer.tokenize("@export")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.ANNOTATION)
	assert_eq(meaningful[0].value, "@export")


func test_onready_annotation():
	var tokens = _tokenizer.tokenize("@onready var x = $Node")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.ANNOTATION)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.KW_VAR)


# ---------------------------------------------------------------------------
# Complex constructs
# ---------------------------------------------------------------------------

func test_dollar_node_path():
	var tokens = _tokenizer.tokenize("$Sprite2D")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_eq(meaningful[0].value, "$Sprite2D")


func test_percent_unique_node():
	var tokens = _tokenizer.tokenize("%MyNode")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


func test_function_declaration():
	var source = "func foo(x: int, y: float) -> String:"
	var tokens = _tokenizer.tokenize(source)
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.KW_FUNC)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.IDENTIFIER)
	assert_eq(meaningful[1].value, "foo")


func test_line_continuation():
	var source = "var x = 1 + \\\n\t2 + 3"
	var tokens = _tokenizer.tokenize(source)
	var meaningful = _strip_structure(tokens)
	var ints = meaningful.filter(func(t): return t.type == GUTCheckToken.Type.INTEGER)
	assert_eq(ints.size(), 3, "All three numbers should be tokenized")


func test_sample_script():
	var file = FileAccess.open("res://test/resources/sample_script.gd", FileAccess.READ)
	if file == null:
		pending("Could not open sample_script.gd")
		return
	var source = file.get_as_text()
	file.close()

	var tokens = _tokenizer.tokenize(source)
	assert_gt(tokens.size(), 10, "Should produce many tokens from a real script")
	assert_eq(tokens.back().type, GUTCheckToken.Type.EOF, "Should end with EOF")

	var funcs = tokens.filter(func(t): return t.type == GUTCheckToken.Type.KW_FUNC)
	assert_gt(funcs.size(), 5, "Should find multiple func keywords in sample script")


# ---------------------------------------------------------------------------
# Raw strings
# ---------------------------------------------------------------------------

func test_raw_string_double_quote():
	var tokens = _tokenizer.tokenize('r"hello\\nworld"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_eq(meaningful[0].value, 'r"hello\\nworld"')


func test_raw_string_single_quote():
	var tokens = _tokenizer.tokenize("r'hello\\nworld'")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)
	assert_eq(meaningful[0].value, "r'hello\\nworld'")


# ---------------------------------------------------------------------------
# Triple-quoted / multiline strings
# ---------------------------------------------------------------------------

func test_triple_quoted_multiline_emits_string_token():
	var source = '"""\nline one\nline two\n"""'
	var tokens = _tokenizer.tokenize(source)
	var strings = tokens.filter(func(t): return t.type == GUTCheckToken.Type.STRING)
	assert_gt(strings.size(), 0, "Should emit at least one STRING token for multiline")


func test_triple_quoted_single_quote_multiline():
	var source = "'''\nline one\nline two\n'''"
	var tokens = _tokenizer.tokenize(source)
	var strings = tokens.filter(func(t): return t.type == GUTCheckToken.Type.STRING)
	assert_gt(strings.size(), 0, "Should handle single-quote triple-quoted strings")


func test_triple_quoted_with_code_after_close():
	# Code after closing triple-quote on the same line
	var source = '"""\nhello\n""".strip_edges()'
	var tokens = _tokenizer.tokenize(source)
	var strings = tokens.filter(func(t): return t.type == GUTCheckToken.Type.STRING)
	var identifiers = tokens.filter(func(t): return t.type == GUTCheckToken.Type.IDENTIFIER)
	assert_gt(strings.size(), 0, "Should emit STRING token")
	assert_true(identifiers.any(func(t): return t.value == "strip_edges"),
		"Should tokenize identifier after closing triple-quote")


func test_triple_quoted_with_operator_after_close():
	# Operator (like dot or paren) after closing triple-quote on same line
	var source = '"""\nhello\n"""[0]'
	var tokens = _tokenizer.tokenize(source)
	var brackets = tokens.filter(func(t): return t.type == GUTCheckToken.Type.BRACKET_OPEN)
	assert_gt(brackets.size(), 0, "Should tokenize operator after closing triple-quote")


# ---------------------------------------------------------------------------
# StringName literals
# ---------------------------------------------------------------------------

func test_string_name_value():
	var tokens = _tokenizer.tokenize('&"my_signal"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)
	assert_eq(meaningful[0].value, '&"my_signal"')


func test_string_name_single_quote():
	var tokens = _tokenizer.tokenize("&'my_signal'")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful.size(), 1)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)
	assert_eq(meaningful[0].value, "&'my_signal'")


func test_string_name_with_escape():
	var tokens = _tokenizer.tokenize('&"na\\tme"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)


func test_string_name_unterminated():
	var tokens = _tokenizer.tokenize('&"unterminated')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING_NAME)


# ---------------------------------------------------------------------------
# NodePath literals
# ---------------------------------------------------------------------------

func test_node_path_caret_value():
	var tokens = _tokenizer.tokenize('^"some/path"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_eq(meaningful[0].value, '^"some/path"')


func test_node_path_caret_single_quote():
	var tokens = _tokenizer.tokenize("^'some/path'")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


func test_node_path_caret_with_escape():
	var tokens = _tokenizer.tokenize('^"path\\nname"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


func test_node_path_caret_unterminated():
	var tokens = _tokenizer.tokenize('^"unterminated')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


func test_dollar_quoted_path():
	var tokens = _tokenizer.tokenize('$"Some/Quoted Path"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_eq(meaningful[0].value, '$"Some/Quoted Path"')


func test_dollar_chain_path():
	var tokens = _tokenizer.tokenize("$Parent/Child/GrandChild")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_eq(meaningful[0].value, "$Parent/Child/GrandChild")


func test_dollar_quoted_with_escape():
	var tokens = _tokenizer.tokenize('$"path\\nname"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


# ---------------------------------------------------------------------------
# Line continuation and bracket depth
# ---------------------------------------------------------------------------

func test_line_continuation_suppresses_newline():
	var source = "var x = 1 + \\\n\t2"
	var tokens = _tokenizer.tokenize(source)
	# The continued line should not produce INDENT between the two lines
	var indents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.INDENT)
	assert_eq(indents.size(), 0, "Line continuation should suppress INDENT")


func test_bracket_depth_suppresses_indent():
	var source = "foo(\n\t1,\n\t2\n)"
	var tokens = _tokenizer.tokenize(source)
	var indents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.INDENT)
	assert_eq(indents.size(), 0, "Inside brackets, INDENT should be suppressed")


func test_bracket_depth_square_brackets():
	var source = "var a = [\n\t1,\n\t2\n]"
	var tokens = _tokenizer.tokenize(source)
	var indents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.INDENT)
	assert_eq(indents.size(), 0, "Inside square brackets, INDENT should be suppressed")


func test_bracket_depth_curly_braces():
	var source = "var d = {\n\t\"key\": 1\n}"
	var tokens = _tokenizer.tokenize(source)
	var indents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.INDENT)
	assert_eq(indents.size(), 0, "Inside curly braces, INDENT should be suppressed")


# ---------------------------------------------------------------------------
# Trailing DEDENT and EOF emission
# ---------------------------------------------------------------------------

func test_trailing_dedent_at_eof():
	# Code that ends while still indented -- should emit DEDENT before EOF
	var source = "if true:\n\tpass"
	var tokens = _tokenizer.tokenize(source)
	var dedents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.DEDENT)
	assert_gt(dedents.size(), 0, "Should emit trailing DEDENT at EOF")
	assert_eq(tokens.back().type, GUTCheckToken.Type.EOF)


func test_deeply_nested_trailing_dedent():
	var source = "if true:\n\tif false:\n\t\tpass"
	var tokens = _tokenizer.tokenize(source)
	var dedents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.DEDENT)
	assert_eq(dedents.size(), 2, "Should emit 2 trailing DEDENTs for 2-deep nesting at EOF")


# ---------------------------------------------------------------------------
# Number edge cases
# ---------------------------------------------------------------------------

func test_octal_literal():
	var tokens = _tokenizer.tokenize("0o77")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0o77")


func test_scientific_notation_with_positive_exponent():
	var tokens = _tokenizer.tokenize("1e+10")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "1e+10")


func test_scientific_notation_with_negative_exponent():
	var tokens = _tokenizer.tokenize("2.5e-3")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, "2.5e-3")


func test_float_starting_with_dot():
	var tokens = _tokenizer.tokenize(".5")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.FLOAT)
	assert_eq(meaningful[0].value, ".5")


func test_integer_before_dotdot():
	# 5..10 — the 5 should be INTEGER, not FLOAT
	var tokens = _tokenizer.tokenize("5..10")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "5")
	assert_eq(meaningful[1].type, GUTCheckToken.Type.DOT_DOT)


func test_hex_with_underscore():
	var tokens = _tokenizer.tokenize("0xFF_00")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0xFF_00")


func test_binary_with_underscore():
	var tokens = _tokenizer.tokenize("0b1010_0101")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.INTEGER)
	assert_eq(meaningful[0].value, "0b1010_0101")


# ---------------------------------------------------------------------------
# Operator edge cases
# ---------------------------------------------------------------------------

func test_power_assign_operator():
	var tokens = _tokenizer.tokenize("x **= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.STAR_STAR_ASSIGN)
	assert_eq(meaningful[1].value, "**=")


func test_lshift_assign_operator():
	var tokens = _tokenizer.tokenize("x <<= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.LSHIFT_ASSIGN)


func test_rshift_assign_operator():
	var tokens = _tokenizer.tokenize("x >>= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.RSHIFT_ASSIGN)


func test_percent_assign_operator():
	var tokens = _tokenizer.tokenize("x %= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PERCENT_ASSIGN)


func test_ampersand_assign_operator():
	var tokens = _tokenizer.tokenize("x &= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.AMPERSAND_ASSIGN)


func test_pipe_assign_operator():
	var tokens = _tokenizer.tokenize("x |= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PIPE_ASSIGN)


func test_caret_assign_operator():
	var tokens = _tokenizer.tokenize("x ^= 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.CARET_ASSIGN)


func test_lshift_operator():
	var tokens = _tokenizer.tokenize("x << 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.LSHIFT)


func test_rshift_operator():
	var tokens = _tokenizer.tokenize("x >> 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.RSHIFT)


func test_tilde_operator():
	var tokens = _tokenizer.tokenize("~x")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.TILDE)


func test_semicolon():
	var tokens = _tokenizer.tokenize("x = 1; y = 2")
	var meaningful = _strip_structure(tokens)
	var semis = meaningful.filter(func(t): return t.type == GUTCheckToken.Type.SEMICOLON)
	assert_eq(semis.size(), 1)


func test_bang_as_not():
	var tokens = _tokenizer.tokenize("!x")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.KW_NOT)
	assert_eq(meaningful[0].value, "!")


func test_standalone_ampersand():
	var tokens = _tokenizer.tokenize("x & y")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.AMPERSAND)


func test_standalone_pipe():
	var tokens = _tokenizer.tokenize("x | y")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PIPE)


func test_standalone_caret():
	var tokens = _tokenizer.tokenize("x ^ y")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.CARET)


# ---------------------------------------------------------------------------
# Percent node references
# ---------------------------------------------------------------------------

func test_percent_quoted_node():
	var tokens = _tokenizer.tokenize('%"My Node"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)
	assert_eq(meaningful[0].value, '%"My Node"')


func test_percent_quoted_with_escape():
	var tokens = _tokenizer.tokenize('%"na\\tme"')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.NODE_PATH)


# ---------------------------------------------------------------------------
# Expression keywords
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
# Tab indentation
# ---------------------------------------------------------------------------

func test_tab_indentation():
	var source = "func foo():\n\tvar x = 1\n\t\tvar y = 2\n\tvar z = 3"
	var tokens = _tokenizer.tokenize(source)
	var indents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.INDENT)
	var dedents = tokens.filter(func(t): return t.type == GUTCheckToken.Type.DEDENT)
	assert_eq(indents.size(), 2, "Should detect 2 indent levels with tabs")


# ---------------------------------------------------------------------------
# Blank lines
# ---------------------------------------------------------------------------

func test_blank_line_emits_newline():
	var source = "var x = 1\n\nvar y = 2"
	var tokens = _tokenizer.tokenize(source)
	var newlines = tokens.filter(func(t): return t.type == GUTCheckToken.Type.NEWLINE)
	assert_gte(newlines.size(), 3, "Blank line should emit NEWLINE token")


# ---------------------------------------------------------------------------
# Comment during continuation / inside brackets
# ---------------------------------------------------------------------------

func test_comment_inside_brackets():
	var source = "foo(\n\t# comment\n\t1\n)"
	var tokens = _tokenizer.tokenize(source)
	var comments = tokens.filter(func(t): return t.type == GUTCheckToken.Type.COMMENT)
	assert_gt(comments.size(), 0, "Comments inside brackets should still be tokenized")


func test_comment_on_continued_line():
	# Comment on a line that is being continued should have no INDENT emitted
	var source = "# comment\nvar x = 1 + \\\n\t2"
	var tokens = _tokenizer.tokenize(source)
	var comments = tokens.filter(func(t): return t.type == GUTCheckToken.Type.COMMENT)
	assert_gt(comments.size(), 0)


# ---------------------------------------------------------------------------
# Unterminated strings
# ---------------------------------------------------------------------------

func test_unterminated_double_string():
	var tokens = _tokenizer.tokenize('"unterminated')
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)


func test_unterminated_single_string():
	var tokens = _tokenizer.tokenize("'unterminated")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[0].type, GUTCheckToken.Type.STRING)


# ---------------------------------------------------------------------------
# Token helper methods
# ---------------------------------------------------------------------------

func test_token_to_string():
	var t = GUTCheckToken.new(GUTCheckToken.Type.IDENTIFIER, "foo", 1, 0)
	var s = t._to_string()
	assert_true(s.contains("IDENTIFIER"), "to_string should contain type name")
	assert_true(s.contains("foo"), "to_string should contain value")


func test_token_is_keyword():
	var kw = GUTCheckToken.new(GUTCheckToken.Type.KW_IF, "if", 1, 0)
	var id = GUTCheckToken.new(GUTCheckToken.Type.IDENTIFIER, "foo", 1, 0)
	assert_true(kw.is_keyword(), "KW_IF should be a keyword")
	assert_false(id.is_keyword(), "IDENTIFIER should not be a keyword")


func test_token_is_assignment():
	var assign = GUTCheckToken.new(GUTCheckToken.Type.PLUS_ASSIGN, "+=", 1, 0)
	var plus = GUTCheckToken.new(GUTCheckToken.Type.PLUS, "+", 1, 0)
	assert_true(assign.is_assignment(), "+= should be assignment")
	assert_false(plus.is_assignment(), "+ should not be assignment")


func test_token_is_open_group():
	var paren = GUTCheckToken.new(GUTCheckToken.Type.PAREN_OPEN, "(", 1, 0)
	var bracket = GUTCheckToken.new(GUTCheckToken.Type.BRACKET_OPEN, "[", 1, 0)
	var brace = GUTCheckToken.new(GUTCheckToken.Type.BRACE_OPEN, "{", 1, 0)
	var close = GUTCheckToken.new(GUTCheckToken.Type.PAREN_CLOSE, ")", 1, 0)
	assert_true(paren.is_open_group())
	assert_true(bracket.is_open_group())
	assert_true(brace.is_open_group())
	assert_false(close.is_open_group())


func test_token_is_close_group():
	var paren = GUTCheckToken.new(GUTCheckToken.Type.PAREN_CLOSE, ")", 1, 0)
	var bracket = GUTCheckToken.new(GUTCheckToken.Type.BRACKET_CLOSE, "]", 1, 0)
	var brace = GUTCheckToken.new(GUTCheckToken.Type.BRACE_CLOSE, "}", 1, 0)
	var open = GUTCheckToken.new(GUTCheckToken.Type.PAREN_OPEN, "(", 1, 0)
	assert_true(paren.is_close_group())
	assert_true(bracket.is_close_group())
	assert_true(brace.is_close_group())
	assert_false(open.is_close_group())


# ---------------------------------------------------------------------------
# Miscellaneous punctuation
# ---------------------------------------------------------------------------

func test_colon_token():
	var tokens = _tokenizer.tokenize("var x: int")
	var meaningful = _strip_structure(tokens)
	var colons = meaningful.filter(func(t): return t.type == GUTCheckToken.Type.COLON)
	assert_eq(colons.size(), 1)


func test_dot_token():
	var tokens = _tokenizer.tokenize("obj.method")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.DOT)


func test_comma_token():
	var tokens = _tokenizer.tokenize("a, b, c")
	var meaningful = _strip_structure(tokens)
	var commas = meaningful.filter(func(t): return t.type == GUTCheckToken.Type.COMMA)
	assert_eq(commas.size(), 2)


func test_single_char_arithmetic():
	var tokens = _tokenizer.tokenize("a + b - c * d / e")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PLUS)
	assert_eq(meaningful[3].type, GUTCheckToken.Type.MINUS)
	assert_eq(meaningful[5].type, GUTCheckToken.Type.STAR)
	assert_eq(meaningful[7].type, GUTCheckToken.Type.SLASH)


func test_percent_as_modulo():
	# Standalone % when not followed by identifier or quote
	var tokens = _tokenizer.tokenize("x % 2")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.PERCENT)


func test_assign_token():
	var tokens = _tokenizer.tokenize("x = 1")
	var meaningful = _strip_structure(tokens)
	assert_eq(meaningful[1].type, GUTCheckToken.Type.ASSIGN)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _strip_structure(tokens: Array) -> Array:
	var result: Array = []
	for t in tokens:
		if t.type != GUTCheckToken.Type.NEWLINE and t.type != GUTCheckToken.Type.INDENT \
				and t.type != GUTCheckToken.Type.DEDENT \
				and t.type != GUTCheckToken.Type.EOF and t.type != GUTCheckToken.Type.COMMENT:
			result.append(t)
	return result
