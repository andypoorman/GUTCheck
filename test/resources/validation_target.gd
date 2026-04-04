extends RefCounted
## Purpose-built validation target with KNOWN expected coverage.
## Each function is designed to exercise a specific coverage scenario
## so we can verify LCOV output is numerically correct.


var _value := 0


## Every line executes. Expected: 100% line coverage when called.
func fully_covered(x: int) -> int:
	var a := x + 1
	var b := a * 2
	var c := b - 3
	return c


## Only the true branch runs when called with true.
## Expected: ~60% line coverage (if-line + true body + return, but not else body).
func branching(cond: bool) -> String:
	if cond:
		return "yes"
	else:
		return "no"


## Never called. Expected: 0% line coverage for all lines inside.
func never_called() -> void:
	var x := 42
	var y := x + 1
	print(y)


## For-loop test: lines AFTER the for loop must be covered.
## This tests the scope fix -- the for loop should not "eat" subsequent lines.
func for_loop_then_more(n: int) -> int:
	var total := 0
	for i in range(n):
		total += i
	var result := total + 100
	return result


## Nested if inside a while -- deep nesting scope test.
func nested_blocks(limit: int) -> String:
	var out := ""
	var i := 0
	while i < limit:
		if i % 2 == 0:
			out += "e"
		else:
			out += "o"
		i += 1
	var done := true
	return out if done else ""


## Ternary expression -- should produce branch probes.
func ternary_expr(flag: bool) -> String:
	var result := "on" if flag else "off"
	return result


## Multiple nested blocks: for inside if inside while.
## The exact scenario our scope fix addresses -- lines after nested blocks
## must still be marked as covered.
func deeply_nested(n: int) -> int:
	var sum := 0
	var j := 0
	while j < 2:
		if j == 0:
			for k in range(n):
				sum += k
		else:
			sum += 10
		j += 1
	var final_result := sum + 1
	return final_result


## Property with get/set accessors.
var tracked: int:
	get:
		return _value
	set(v):
		_value = v


## Lambda defined inline.
func with_lambda() -> int:
	var fn = func(x): return x * 2
	return fn.call(5)


## Inner class with a method.
class Inner:
	var data := 0

	func compute(x: int) -> int:
		var r := x * 3
		return r
