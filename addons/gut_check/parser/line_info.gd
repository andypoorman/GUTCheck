class_name GUTCheckLineInfo


var line_number: int
var type: int  # GUTCheckScriptMap.LineType enum value
var function_name: String
var cls_name: String
## Number of semicolon-separated statements on this line.
## 1 means a normal single-statement line.
var statement_count: int = 1
## Number of ternary-if expressions on this line (for branch coverage).
var ternary_count: int = 0
## True for else:/match-pattern lines whose body is on the same line
## (e.g. `else: x()` or `"up": return v`). Inline bodies get a probe injected
## after the block colon, so their hits must never be derived from
## following lines.
var has_inline_body: bool = false
## Indent level (in INDENT/DEDENT steps, not columns). Used to bound
## body-hit derivation for compound branches to lines inside their block.
var indent_level: int = 0
## Last physical line of this logical statement (== line_number for
## single-line statements; greater when the statement spans lines via
## parentheses or backslash continuations).
var last_physical_line: int = 0

func _init(p_line: int, p_type: int, p_func: String = "", p_class: String = ""):
	line_number = p_line
	type = p_type
	function_name = p_func
	cls_name = p_class
	last_physical_line = p_line

func is_executable() -> bool:
	return type != GUTCheckScriptMap.LineType.NON_EXECUTABLE \
		and type != GUTCheckScriptMap.LineType.CONTINUATION \
		and type != GUTCheckScriptMap.LineType.FUNC_DEF \
		and type != GUTCheckScriptMap.LineType.CLASS_DEF \
		and type != GUTCheckScriptMap.LineType.BRANCH_ELSE \
		and type != GUTCheckScriptMap.LineType.BRANCH_PATTERN \
		and type != GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR
