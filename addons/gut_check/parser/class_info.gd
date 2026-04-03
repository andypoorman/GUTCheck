class_name GUTCheckClassInfo


var name: String
var start_line: int
var end_line: int
var indent: int  ## Indent level where this class was defined (for scope tracking)

func _init(p_name: String, p_start: int, p_indent: int = 0):
	name = p_name
	start_line = p_start
	end_line = -1
	indent = p_indent
