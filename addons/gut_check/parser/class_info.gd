class_name GUTCheckClassInfo


var name: String
var start_line: int
var end_line: int

func _init(p_name: String, p_start: int):
	name = p_name
	start_line = p_start
	end_line = -1
