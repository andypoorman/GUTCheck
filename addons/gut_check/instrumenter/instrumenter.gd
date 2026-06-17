class_name GUTCheckInstrumenter
## Transforms GDScript source code by injecting coverage probes.
## Pure string manipulation is delegated to GUTCheckProbeInjector.


var _tokenizer = GUTCheckTokenizer.new()
var _classifier = GUTCheckLineClassifier.new()


## Instrument a GDScript source string. Returns a GUTCheckInstrumentResult
## with the modified source and metadata.
##
## conservative=true skips wrapping `for` loop iterables. Wrapping an iterable
## routes it through a collector call that returns Variant, which widens the
## loop variable's type — so a body like `for x in typed: var y := x.foo()`
## fails to compile (`:=` can't infer from Variant). GDScript can't preserve
## the element type through any wrapper, so when the normal pass fails to
## compile we re-run conservatively: the for-loop headers go uninstrumented
## (and are excluded by the injection check) while everything else is kept,
## rather than losing the whole file to a rollback.
func instrument(source: String, script_id: int, script_path: String = "", conservative: bool = false) -> GUTCheckInstrumentResult:
	var tokens: Array = _tokenizer.tokenize(source)
	# classify() returns STRUCTURE only (no probe IDs). The branch infos carry
	# block_id / true-false role; their probe_id is assigned below at injection.
	var script_map: GUTCheckScriptMap = _classifier.classify(tokens, script_path)

	var lines: PackedStringArray = source.split("\n")
	var result_lines: PackedStringArray = []
	result_lines.resize(lines.size())
	for i in range(lines.size()):
		result_lines[i] = lines[i]

	# Branch structure per line: line_num -> [BranchInfo, ...]. The wrappers
	# stamp freshly-allocated ids onto these infos as they inject.
	var line_to_branches: Dictionary = {}
	for branch_info in script_map.branches:
		var ln: int = branch_info.line_number
		if not line_to_branches.has(ln):
			line_to_branches[ln] = []
		line_to_branches[ln].append(branch_info)
	var structural_branch_count := script_map.branches.size()

	# The sole probe-ID authority. Every collector call emitted below pulls its
	# id from here at the moment of emission, so allocation == injection by
	# construction — a declined wrapper allocates nothing and leaves no orphan.
	var allocator := GUTCheckProbeAllocator.new()

	var sorted_line_numbers: Array[int] = []
	for ln: int in script_map.lines:
		sorted_line_numbers.append(ln)
	sorted_line_numbers.sort()

	for line_num in sorted_line_numbers:
		var i: int = line_num - 1
		if i < 0 or i >= lines.size():
			continue
		var line_info: GUTCheckLineInfo = script_map.lines[line_num]
		if not _is_injectable_line_type(line_info.type):
			continue

		# Conservative pass: leave `for` headers raw so the loop var keeps its
		# type. Their probes are simply never allocated.
		if conservative and line_info.type == GUTCheckScriptMap.LineType.LOOP_FOR:
			continue

		var indent: String = GUTCheckProbeInjector.get_indent(lines[i])
		if indent.length() == 0:
			continue
		# Class-body statements can't take probes (the classifier already
		# excludes them; this is a safety net against classifier gaps).
		if line_info.function_name.is_empty() \
				and (line_info.type == GUTCheckScriptMap.LineType.EXECUTABLE \
					or line_info.type == GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY):
			continue

		var branch_probes: Array = line_to_branches.get(line_num, [])
		var span: int = mini(line_info.last_physical_line, lines.size()) - line_num + 1
		# Attribute this line's line-probe allocations to line_num.
		allocator.begin_line(line_num)

		if span <= 1 or not _spans_are_instrumentable(line_info.type):
			# Single-line statements, and multiline statements whose wrapper
			# only touches the first physical line (plain executables get a
			# probe prepended; the rest of the statement is unchanged).
			result_lines[i] = GUTCheckProbeInjector.instrument_line(
				lines[i], line_info.type, script_id, allocator,
				line_info.statement_count, branch_probes, line_info.has_inline_body)
			continue

		# Compound statements spanning physical lines (parenthesized or
		# backslash-continued headers): join the span, instrument the whole
		# logical statement, and split back. Wrappers only insert text, so the
		# physical line count must survive the round trip — if it doesn't,
		# abandon the statement AND roll back the ids the wrapper just allocated,
		# so the discarded text leaves no orphaned probe behind.
		var sp := allocator.savepoint()
		var joined := "\n".join(lines.slice(i, i + span))
		var instrumented := GUTCheckProbeInjector.instrument_line(
			joined, line_info.type, script_id, allocator,
			line_info.statement_count, branch_probes, line_info.has_inline_body)
		var parts: PackedStringArray = instrumented.split("\n")
		if parts.size() != span:
			allocator.rollback_to(sp)
			continue
		for k in range(span):
			result_lines[i + k] = parts[k]

	var instrumented_source := "\n".join(result_lines)

	# Point each block else/pattern branch at its body's first line probe now
	# that every line probe is known (see resolve_derived). After this, every
	# surviving branch reads a real injected probe — no derivation at report time.
	allocator.resolve_derived(script_map.lines)

	# The injector is the sole probe-ID authority: every id in these structures
	# was handed out at an emit site, so there is nothing allocated-but-
	# uninjected to reconcile. This is what the old post-hoc scan/exclude pass
	# became — correctness by construction rather than after the fact.
	script_map.probe_to_line = allocator.probe_to_line
	script_map.branches = allocator.branches
	script_map.probe_count = allocator.probe_count
	script_map._mark_caches_dirty()

	# Surface anything GUTCheck classified as coverable but the wrappers could
	# not instrument (no block colon, a multiline round-trip mismatch, a dense
	# form, or the conservative for-loop skip). Such lines/branches are simply
	# absent from coverage rather than reported as a false zero.
	var declined := _count_declined(script_map, structural_branch_count)
	if declined.lines > 0 or declined.branches > 0:
		push_warning(
			"GUTCheck: %s — %d line(s) and %d branch(es) could not be instrumented and were excluded from coverage" \
			% [script_path, declined.lines, declined.branches])

	var result := GUTCheckInstrumentResult.new()
	result.source = instrumented_source
	result.script_map = script_map
	result.probe_count = script_map.probe_count
	return result


## Line types the injection loop processes. Everything else (non-executable,
## continuation, func/class def, property accessor) is skipped — and crucially,
## continuation lines are skipped so a multiline statement's already-written
## physical lines are not clobbered by re-processing.
static func _is_injectable_line_type(line_type: GUTCheckScriptMap.LineType) -> bool:
	return line_type == GUTCheckScriptMap.LineType.EXECUTABLE \
		or line_type == GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_IF \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_ELIF \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
		or line_type == GUTCheckScriptMap.LineType.LOOP_WHILE \
		or line_type == GUTCheckScriptMap.LineType.LOOP_FOR \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_MATCH \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_PATTERN


## Count coverable-but-uninstrumented lines/branches for the diagnostic warning.
## A declined line is an executable line that received no line probe; a declined
## branch is one the structure expected but the injector never allocated.
func _count_declined(script_map, structural_branch_count: int) -> Dictionary:
	var instrumented_lines: Dictionary = {}
	for pid: int in script_map.probe_to_line:
		instrumented_lines[script_map.probe_to_line[pid]] = true
	var declined_lines := 0
	for ln in script_map.get_executable_lines_sorted():
		if not instrumented_lines.has(ln):
			declined_lines += 1
	return {
		"lines": declined_lines,
		"branches": structural_branch_count - script_map.branches.size(),
	}


## Statement types whose probe wrapper needs the full logical statement
## (condition/iterable/expression wrapping). Plain EXECUTABLE statements are
## excluded: their probe is prepended to the first physical line, which is
## already line-count safe.
static func _spans_are_instrumentable(line_type: GUTCheckScriptMap.LineType) -> bool:
	return line_type == GUTCheckScriptMap.LineType.BRANCH_IF \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_ELIF \
		or line_type == GUTCheckScriptMap.LineType.LOOP_WHILE \
		or line_type == GUTCheckScriptMap.LineType.LOOP_FOR \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_MATCH \
		or line_type == GUTCheckScriptMap.LineType.EXECUTABLE_TERNARY \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
		or line_type == GUTCheckScriptMap.LineType.BRANCH_PATTERN
