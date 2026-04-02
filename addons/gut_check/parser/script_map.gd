class_name GUTCheckScriptMap
## Data structures for representing the coverage-relevant structure of a
## GDScript file. Produced by the LineClassifier.


enum LineType {
	EXECUTABLE,
	BRANCH_IF,
	BRANCH_ELIF,
	BRANCH_ELSE,
	LOOP_FOR,
	LOOP_WHILE,
	BRANCH_MATCH,
	BRANCH_PATTERN,   # Match arm pattern line (compound — has body)
	FUNC_DEF,
	CLASS_DEF,
	PROPERTY_ACCESSOR, # get: or set(...): lines
	NON_EXECUTABLE,
	CONTINUATION,
}


class LineInfo:
	var line_number: int
	var type: int  # LineType enum value
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


class FunctionInfo:
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


class ClassInfo:
	var name: String
	var start_line: int
	var end_line: int

	func _init(p_name: String, p_start: int):
		name = p_name
		start_line = p_start
		end_line = -1


## A branch point for BRDA coverage. Each condition (if/elif/while) produces
## two BranchInfo entries (true and false). Match patterns produce one each.
class BranchInfo:
	var line_number: int   # Source line of the branch
	var block_id: int      # Same block_id = same if/elif/else chain or match
	var branch_id: int     # Branch index within the block (0-based)
	var probe_id: int      # Which probe in the hits array tracks this branch
	## True for the false-path of a condition with no explicit else, or
	## an unmatched case in a match without a wildcard pattern.
	var is_true_branch: bool

	func _init(p_line: int, p_block: int, p_branch: int, p_probe: int, p_is_true: bool = true):
		line_number = p_line
		block_id = p_block
		branch_id = p_branch
		probe_id = p_probe
		is_true_branch = p_is_true


## Path of the source script (res:// path)
var path: String

## line_number -> LineInfo for every classified line
var lines: Dictionary = {}

## All functions found in the script
var functions: Array = []

## All inner classes found in the script
var classes: Array = []

## Branch points for BRDA coverage
var branches: Array = []  # Array of BranchInfo

## Probe ID -> line number mapping (for resolving hits back to source lines)
var probe_to_line: Dictionary = {}

## Total number of probes assigned (line + branch probes)
var probe_count: int = 0


func get_executable_lines_sorted() -> Array[int]:
	var result: Array[int] = []
	for line_num: int in lines:
		if lines[line_num].is_executable():
			result.append(line_num)
	result.sort()
	return result


## Get branch probes for a given line. Returns array of BranchInfo.
func get_branches_for_line(line_num: int) -> Array:
	var result: Array = []
	for b in branches:
		if b.line_number == line_num:
			result.append(b)
	return result


func get_function_for_line(line_num: int):
	for f in functions:
		if line_num >= f.start_line and (f.end_line == -1 or line_num <= f.end_line):
			return f
	return null


func assign_probes() -> void:
	probe_count = 0
	probe_to_line.clear()
	var sorted_lines := get_executable_lines_sorted()
	for line_num in sorted_lines:
		var info = lines[line_num]
		# Allocate one probe per statement on this line
		for _s in range(info.statement_count):
			probe_to_line[probe_count] = line_num
			probe_count += 1
	# Branch probes are allocated after line probes by assign_branch_probes()


## Allocate probe IDs for branch coverage. Must be called after assign_probes()
## so that branch probes don't collide with line probes. Each if/elif/while
## condition gets 2 probes (true/false). Match patterns get 1 probe each.
func assign_branch_probes() -> void:
	var next_block_id := 0
	var sorted_keys: Array[int] = []
	for k: int in lines:
		sorted_keys.append(k)
	sorted_keys.sort()

	# State for grouping if/elif/else chains into blocks
	var current_if_block := -1
	var current_if_branch := 0
	var current_match_block := -1
	var current_match_branch := 0

	for line_num in sorted_keys:
		var info: LineInfo = lines[line_num]

		match info.type:
			LineType.BRANCH_IF:
				# Start a new block for this if-chain
				current_if_block = next_block_id
				next_block_id += 1
				current_if_branch = 0
				# True branch probe
				var true_pid := probe_count
				branches.append(BranchInfo.new(line_num, current_if_block, current_if_branch, true_pid, true))
				probe_count += 1
				current_if_branch += 1
				# False branch probe
				var false_pid := probe_count
				branches.append(BranchInfo.new(line_num, current_if_block, current_if_branch, false_pid, false))
				probe_count += 1
				current_if_branch += 1

			LineType.BRANCH_ELIF:
				# Continue the current if-block
				if current_if_block == -1:
					current_if_block = next_block_id
					next_block_id += 1
					current_if_branch = 0
				# True branch
				var true_pid := probe_count
				branches.append(BranchInfo.new(line_num, current_if_block, current_if_branch, true_pid, true))
				probe_count += 1
				current_if_branch += 1
				# False branch
				var false_pid := probe_count
				branches.append(BranchInfo.new(line_num, current_if_block, current_if_branch, false_pid, false))
				probe_count += 1
				current_if_branch += 1

			LineType.BRANCH_ELSE:
				# else has no condition — it's entered whenever the last
				# elif/if false branch fires. We emit a single branch entry
				# to track that the else body was reached.
				if current_if_block == -1:
					current_if_block = next_block_id
					next_block_id += 1
					current_if_branch = 0
				var pid := probe_count
				branches.append(BranchInfo.new(line_num, current_if_block, current_if_branch, pid, true))
				probe_count += 1
				current_if_branch += 1

			LineType.LOOP_WHILE:
				# while gets its own block: 2 branches (entered / not entered)
				var block := next_block_id
				next_block_id += 1
				var true_pid := probe_count
				branches.append(BranchInfo.new(line_num, block, 0, true_pid, true))
				probe_count += 1
				var false_pid := probe_count
				branches.append(BranchInfo.new(line_num, block, 1, false_pid, false))
				probe_count += 1
				# Reset if-chain tracking
				current_if_block = -1

			LineType.LOOP_FOR:
				# for gets its own block: 2 branches (iterable non-empty / empty)
				var block := next_block_id
				next_block_id += 1
				var true_pid := probe_count
				branches.append(BranchInfo.new(line_num, block, 0, true_pid, true))
				probe_count += 1
				var false_pid := probe_count
				branches.append(BranchInfo.new(line_num, block, 1, false_pid, false))
				probe_count += 1
				# Reset if-chain tracking
				current_if_block = -1

			LineType.BRANCH_MATCH:
				# Start a new match block
				current_match_block = next_block_id
				next_block_id += 1
				current_match_branch = 0
				# The match expression itself gets a probe via br()
				# (already allocated as a line probe). Pattern arms below
				# get their own branch probes.
				# Reset if-chain tracking
				current_if_block = -1

			LineType.BRANCH_PATTERN:
				# Each match arm is a branch in the match block
				if current_match_block == -1:
					current_match_block = next_block_id
					next_block_id += 1
					current_match_branch = 0
				var pid := probe_count
				branches.append(BranchInfo.new(line_num, current_match_block, current_match_branch, pid, true))
				probe_count += 1
				current_match_branch += 1

			_:
				# Non-branch line — reset if-chain tracking if not continuation
				if info.type != LineType.CONTINUATION and info.type != LineType.NON_EXECUTABLE:
					current_if_block = -1
