class_name GUTCheckFunctionInfo


var name: String
var start_line: int
var end_line: int
var cls_name: String
var is_static: bool

func _init(p_name: String, p_start: int, p_class: String = "", p_static: bool = false):
	name = p_name
	start_line = p_start
	end_line = -1
	cls_name = p_class
	is_static = p_static
