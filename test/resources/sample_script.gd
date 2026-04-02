extends Node

class_name SampleScript

var health := 100
var max_health := 100
const MAX_SPEED = 200

@onready var sprite = $Sprite2D

signal health_changed(new_health)

enum State {
	IDLE,
	RUNNING,
	JUMPING,
}

var state = State.IDLE


func _ready():
	health = max_health
	print("ready")


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		health = 0
		_die()
	elif health < 20:
		print("low health!")
	else:
		print("ouch")
	health_changed.emit(health)


func _die():
	print("dead")
	queue_free()


func heal(amount: int) -> void:
	health = mini(health + amount, max_health)


func get_health_percentage() -> float:
	return float(health) / float(max_health) * 100.0


func complex_logic(x: int, y: int) -> String:
	var result := ""
	for i in range(x):
		if i % 2 == 0:
			result += "even "
		else:
			result += "odd "

	while y > 0:
		result += str(y)
		y -= 1

	match state:
		State.IDLE:
			result += " idle"
		State.RUNNING:
			result += " running"
		State.JUMPING:
			result += " jumping"

	return result


func multiline_call():
	var arr = [
		1,
		2,
		3,
	]
	var dict = {
		"a": 1,
		"b": 2,
	}
	return arr.size() + dict.size()


func with_lambda():
	var fn = func(x):
		return x * 2
	return fn.call(5)


func string_edge_cases():
	var a = "hello # not a comment"
	var b = 'single quotes'
	var c = """
	triple quoted
	multiline string
	"""
	var d = &"string_name"
	return a + b + c + d


var _backing_value: int = 0
var tracked_value: int:
	get:
		return _backing_value
	set(value):
		_backing_value = value


func match_with_patterns(input) -> String:
	match input:
		1:
			return "one"
		2, 3:
			return "two or three"
		var x when x > 10:
			return "big: " + str(x)
		_:
			return "other"


func semicolons():
	var a = 1; var b = 2; var c = 3
	return a + b + c
