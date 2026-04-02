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
