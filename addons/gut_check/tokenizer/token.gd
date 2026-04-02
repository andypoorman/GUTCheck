class_name GUTCheckToken


enum Type {
	# Literals
	INTEGER,
	FLOAT,
	STRING,
	STRING_NAME,     # &"name"
	NODE_PATH,       # ^"path" or $Path
	TRUE,
	FALSE,
	NULL,

	# Identifier
	IDENTIFIER,

	# Keywords - control flow
	KW_IF,
	KW_ELIF,
	KW_ELSE,
	KW_FOR,
	KW_WHILE,
	KW_MATCH,
	KW_WHEN,
	KW_BREAK,
	KW_CONTINUE,
	KW_PASS,
	KW_RETURN,

	# Keywords - declarations
	KW_VAR,
	KW_CONST,
	KW_FUNC,
	KW_CLASS,
	KW_CLASS_NAME,
	KW_EXTENDS,
	KW_SIGNAL,
	KW_ENUM,
	KW_STATIC,

	# Keywords - expressions
	KW_AND,
	KW_OR,
	KW_NOT,
	KW_IN,
	KW_IS,
	KW_AS,
	KW_SELF,
	KW_SUPER,
	KW_AWAIT,
	KW_PRELOAD,

	# Operators - arithmetic
	PLUS,            # +
	MINUS,           # -
	STAR,            # *
	SLASH,           # /
	PERCENT,         # %
	STAR_STAR,       # **

	# Operators - comparison
	EQ,              # ==
	NE,              # !=
	LT,              # <
	GT,              # >
	LE,              # <=
	GE,              # >=

	# Operators - assignment
	ASSIGN,          # =
	PLUS_ASSIGN,     # +=
	MINUS_ASSIGN,    # -=
	STAR_ASSIGN,     # *=
	SLASH_ASSIGN,    # /=
	PERCENT_ASSIGN,  # %=
	STAR_STAR_ASSIGN,# **=
	AMPERSAND_ASSIGN,# &=
	PIPE_ASSIGN,     # |=
	CARET_ASSIGN,    # ^=
	LSHIFT_ASSIGN,   # <<=
	RSHIFT_ASSIGN,   # >>=

	# Operators - bitwise
	AMPERSAND,       # &
	PIPE,            # |
	CARET,           # ^
	TILDE,           # ~
	LSHIFT,          # <<
	RSHIFT,          # >>

	# Operators - misc
	ARROW,           # ->
	DOT_DOT,         # ..

	# Punctuation
	DOT,             # .
	COLON,           # :
	SEMICOLON,       # ;
	COMMA,           # ,
	AT,              # @
	DOLLAR,          # $
	BACKSLASH,       # \

	# Grouping
	PAREN_OPEN,      # (
	PAREN_CLOSE,     # )
	BRACKET_OPEN,    # [
	BRACKET_CLOSE,   # ]
	BRACE_OPEN,      # {
	BRACE_CLOSE,     # }

	# Structure
	NEWLINE,
	INDENT,
	DEDENT,
	COMMENT,
	ANNOTATION,      # @export, @onready, etc.
	EOF,
}


# Map of keyword strings to token types
const KEYWORDS := {
	"if": Type.KW_IF,
	"elif": Type.KW_ELIF,
	"else": Type.KW_ELSE,
	"for": Type.KW_FOR,
	"while": Type.KW_WHILE,
	"match": Type.KW_MATCH,
	"when": Type.KW_WHEN,
	"break": Type.KW_BREAK,
	"continue": Type.KW_CONTINUE,
	"pass": Type.KW_PASS,
	"return": Type.KW_RETURN,
	"var": Type.KW_VAR,
	"const": Type.KW_CONST,
	"func": Type.KW_FUNC,
	"class": Type.KW_CLASS,
	"class_name": Type.KW_CLASS_NAME,
	"extends": Type.KW_EXTENDS,
	"signal": Type.KW_SIGNAL,
	"enum": Type.KW_ENUM,
	"static": Type.KW_STATIC,
	"and": Type.KW_AND,
	"or": Type.KW_OR,
	"not": Type.KW_NOT,
	"in": Type.KW_IN,
	"is": Type.KW_IS,
	"as": Type.KW_AS,
	"self": Type.KW_SELF,
	"super": Type.KW_SUPER,
	"await": Type.KW_AWAIT,
	"preload": Type.KW_PRELOAD,
	"true": Type.TRUE,
	"false": Type.FALSE,
	"null": Type.NULL,
}


# Known annotations
const ANNOTATIONS := [
	"export", "export_category", "export_color_no_alpha",
	"export_custom", "export_dir", "export_enum",
	"export_exp_easing", "export_file", "export_flags",
	"export_flags_2d_navigation", "export_flags_2d_physics",
	"export_flags_2d_render", "export_flags_3d_navigation",
	"export_flags_3d_physics", "export_flags_3d_render",
	"export_flags_avoidance", "export_global_dir",
	"export_global_file", "export_group",
	"export_multiline", "export_node_path",
	"export_placeholder", "export_range",
	"export_storage", "export_subgroup",
	"export_tool_button",
	"icon",
	"onready",
	"tool",
	"warning_ignore",
	"static_unload",
]


var type: Type
var value: String
var line: int
var column: int


func _init(p_type: Type, p_value: String, p_line: int, p_column: int = 0):
	type = p_type
	value = p_value
	line = p_line
	column = p_column


func _to_string() -> String:
	return "Token(%s, %s, L%d)" % [Type.keys()[type], value.c_escape(), line]


func is_keyword() -> bool:
	return type >= Type.KW_IF and type <= Type.KW_PRELOAD


func is_assignment() -> bool:
	return type >= Type.ASSIGN and type <= Type.RSHIFT_ASSIGN


func is_open_group() -> bool:
	return type == Type.PAREN_OPEN or type == Type.BRACKET_OPEN or type == Type.BRACE_OPEN


func is_close_group() -> bool:
	return type == Type.PAREN_CLOSE or type == Type.BRACKET_CLOSE or type == Type.BRACE_CLOSE
