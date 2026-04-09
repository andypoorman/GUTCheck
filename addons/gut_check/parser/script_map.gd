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
	EXECUTABLE_TERNARY, # Executable line containing inline ternary (if/else expression)
	NON_EXECUTABLE,
	CONTINUATION,
}


## Path of the source script (res:// path)
var path: String

## line_number -> GUTCheckLineInfo for every classified line
var lines: Dictionary = {}

## All functions found in the script
var functions: Array = []

## All inner classes found in the script
var classes: Array = []

## Branch points for BRDA coverage
var branches: Array = []  # Array of GUTCheckBranchInfo

## Probe ID -> line number mapping (for resolving hits back to source lines)
var probe_to_line: Dictionary = {}

## Total number of probes assigned (line + branch probes)
var probe_count: int = 0

var _cached_executable_lines: Array[int] = []
var _cached_branches_by_line: Dictionary = {}
var _cached_functions_by_line: Dictionary = {}
var _caches_dirty: bool = true


func get_executable_lines_sorted() -> Array[int]:
	_refresh_caches()
	return _cached_executable_lines.duplicate()


## Get branch probes for a given line. Returns array of GUTCheckBranchInfo.
func get_branches_for_line(line_num: int) -> Array:
	_refresh_caches()
	return _cached_branches_by_line.get(line_num, []).duplicate()


func get_function_for_line(line_num: int):
	_refresh_caches()
	return _cached_functions_by_line.get(line_num, null)


func assign_probes() -> void:
	probe_count = 0
	probe_to_line.clear()
	_mark_caches_dirty()
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
	_mark_caches_dirty()
	branches.clear()
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
		var info: GUTCheckLineInfo = lines[line_num]

		match info.type:
			LineType.BRANCH_IF:
				# Start a new block for this if-chain
				current_if_block = next_block_id
				next_block_id += 1
				current_if_branch = 0
				# True branch probe
				var true_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, current_if_block, current_if_branch, true_pid, true))
				probe_count += 1
				current_if_branch += 1
				# False branch probe
				var false_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, current_if_block, current_if_branch, false_pid, false))
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
				branches.append(GUTCheckBranchInfo.new(line_num, current_if_block, current_if_branch, true_pid, true))
				probe_count += 1
				current_if_branch += 1
				# False branch
				var false_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, current_if_block, current_if_branch, false_pid, false))
				probe_count += 1
				current_if_branch += 1

			LineType.BRANCH_ELSE:
				if current_if_block == -1:
					current_if_block = next_block_id
					next_block_id += 1
					current_if_branch = 0
				var pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, current_if_block, current_if_branch, pid, true))
				probe_count += 1
				current_if_branch += 1

			LineType.LOOP_WHILE:
				var block := next_block_id
				next_block_id += 1
				var true_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, block, 0, true_pid, true))
				probe_count += 1
				var false_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, block, 1, false_pid, false))
				probe_count += 1
				current_if_block = -1

			LineType.LOOP_FOR:
				var block := next_block_id
				next_block_id += 1
				var true_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, block, 0, true_pid, true))
				probe_count += 1
				var false_pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, block, 1, false_pid, false))
				probe_count += 1
				current_if_block = -1

			LineType.BRANCH_MATCH:
				current_match_block = next_block_id
				next_block_id += 1
				current_match_branch = 0
				current_if_block = -1

			LineType.BRANCH_PATTERN:
				if current_match_block == -1:
					current_match_block = next_block_id
					next_block_id += 1
					current_match_branch = 0
				var pid := probe_count
				branches.append(GUTCheckBranchInfo.new(line_num, current_match_block, current_match_branch, pid, true))
				probe_count += 1
				current_match_branch += 1

			LineType.EXECUTABLE_TERNARY:
				# Each ternary-if on the line gets its own block with true/false probes
				for _t in range(info.ternary_count):
					var block := next_block_id
					next_block_id += 1
					var true_pid := probe_count
					branches.append(GUTCheckBranchInfo.new(line_num, block, 0, true_pid, true))
					probe_count += 1
					var false_pid := probe_count
					branches.append(GUTCheckBranchInfo.new(line_num, block, 1, false_pid, false))
					probe_count += 1
				current_if_block = -1

			_:
				if info.type != LineType.CONTINUATION and info.type != LineType.NON_EXECUTABLE:
					current_if_block = -1
	_mark_caches_dirty()


func _refresh_caches() -> void:
	if not _caches_dirty:
		return

	_cached_executable_lines.clear()
	_cached_branches_by_line.clear()
	_cached_functions_by_line.clear()

	for line_num: int in lines:
		if lines[line_num].is_executable():
			_cached_executable_lines.append(line_num)
	_cached_executable_lines.sort()

	for branch_info in branches:
		var line_branches: Array = _cached_branches_by_line.get(branch_info.line_number, [])
		line_branches.append(branch_info)
		_cached_branches_by_line[branch_info.line_number] = line_branches

	for func_info in functions:
		var end_line: int = func_info.end_line
		if end_line == -1:
			end_line = lines.keys().max() if lines.size() > 0 else func_info.start_line
		for line_num in range(func_info.start_line, end_line + 1):
			if not _cached_functions_by_line.has(line_num):
				_cached_functions_by_line[line_num] = func_info

	_caches_dirty = false


func _mark_caches_dirty() -> void:
	_caches_dirty = true
