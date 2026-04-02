extends RefCounted

var health := 100
var max_health := 100

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		health = 0
		_on_death()
	elif health < 20:
		print("low health!")
	else:
		print("ouch")


func _on_death():
	print("dead")


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
