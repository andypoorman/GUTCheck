extends RefCounted


var flag := true
var value := 0


func simple_ternary(cond: bool) -> String:
	var x = "yes" if cond else "no"
	return x


func ternary_with_calls(cond: bool) -> int:
	var y = abs(-5) if cond else max(1, 2)
	return y


func nested_ternary(a: bool, b: bool) -> String:
	var z = "first" if a else "second" if b else "third"
	return z


func ternary_in_return(cond: bool) -> String:
	return "on" if cond else "off"


func ternary_in_assignment(cond: bool) -> void:
	value = 100 if cond else 0
