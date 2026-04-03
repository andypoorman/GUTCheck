class_name GUTCheckLineInfo


var line_number: int
var type: int  # GUTCheckScriptMap.LineType enum value
var function_name: String
var cls_name: String
## Number of semicolon-separated statements on this line.
## 1 means a normal single-statement line.
var statement_count: int = 1

func _init(p_line: int, p_type: int, p_func: String = "", p_class: String = ""):
	line_number = p_line
	type = p_type
	function_name = p_func
	cls_name = p_class

func is_executable() -> bool:
	return type != GUTCheckScriptMap.LineType.NON_EXECUTABLE \
		and type != GUTCheckScriptMap.LineType.CONTINUATION \
		and type != GUTCheckScriptMap.LineType.FUNC_DEF \
		and type != GUTCheckScriptMap.LineType.CLASS_DEF \
		and type != GUTCheckScriptMap.LineType.BRANCH_ELSE \
		and type != GUTCheckScriptMap.LineType.BRANCH_PATTERN \
		and type != GUTCheckScriptMap.LineType.PROPERTY_ACCESSOR
