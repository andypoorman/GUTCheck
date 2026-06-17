class_name GUTCheckProbeAllocator
## The single authority for probe identity. A probe ID exists only because this
## allocator handed it out — and the injector only asks for one at the moment it
## emits (or, for a derived block else/pattern, commits to) a collector call. So
## "a probe is an injected counter" holds by construction: a wrapper that
## declines simply never calls in here, so that ID is never born and cannot
## become an orphan.
##
## Two ways to drive it:
##   * Incrementally (the instrumenter): line()/branch() as calls are emitted,
##     with savepoint()/rollback_to() to undo a multiline statement that is
##     wrapped but then abandoned because it failed its round-trip.
##   * In batch (assign_all): number a fully-structured map that is NOT being
##     injected — a hand-built map in a test, where "assume every probe is
##     injectable" is exactly right and there is no source to scan.


var probe_count: int = 0
## probe_id -> line_number (line probes only)
var probe_to_line: Dictionary = {}
## GUTCheckBranchInfo, in allocation order
var branches: Array = []

## Block else/pattern branch infos awaiting binding by resolve_derived(). They
## fire no probe of their own — their hit is read from the first body line.
var _derived: Array = []

## Source line that line() probes are currently attributed to. The instrumenter
## sets this with begin_line() before instrumenting each line, so the wrappers
## can call line() without threading a line number through every signature.
var _current_line: int = 0

# Passthrough (test) mode: see passthrough(). When set, the allocator does not
# allocate — line() counts up from a fixed seed and branch() echoes the id the
# caller already put on the info — so the string wrappers can be unit-tested
# with pinned ids. Production never uses this.
var _passthrough: bool = false
var _next_line: int = 0


## A non-allocating allocator for unit-testing the string wrappers with fixed
## ids: line() returns `line_seed`, `line_seed + 1`, … and branch() echoes the
## probe_id already on each branch info. It records nothing, so the wrapper's
## emitted string is fully determined by the caller. Production code always uses
## the plain constructor and lets line()/branch() allocate.
static func passthrough(line_seed: int) -> GUTCheckProbeAllocator:
	var a := GUTCheckProbeAllocator.new()
	a._passthrough = true
	a._next_line = line_seed
	return a


## Attribute subsequent line() allocations to this source line.
func begin_line(line_number: int) -> void:
	_current_line = line_number


## Allocate a line probe (for the current begin_line()) and return its id.
func line() -> int:
	if _passthrough:
		var seeded := _next_line
		_next_line += 1
		return seeded
	var pid := probe_count
	probe_count += 1
	probe_to_line[pid] = _current_line
	return pid


## Allocate a probe for an INJECTED branch — one whose collector call carries
## this id (if/elif/while/for true-false, ternary, inline else/pattern). Stamps
## the id onto the pre-structured branch info and keeps it.
func branch(info) -> int:
	if _passthrough:
		return info.probe_id
	info.probe_id = probe_count
	probe_count += 1
	branches.append(info)
	return info.probe_id


## Register a DERIVED branch — a block else:/pattern: whose body is on the
## following lines, so it can't hold its own counter. It fires no probe; instead
## resolve_derived() will point its probe_id at the first body line's probe, so a
## branch's hit is always just hits[probe_id] with no special derivation step.
func derive_branch(info) -> void:
	if _passthrough:
		return
	info.probe_id = -1
	branches.append(info)
	_derived.append(info)


## Bind every derived branch to the first injected line probe inside its block
## (the body's first measurable line), then drop any branch that still has no
## probe — an else/pattern whose body could not be instrumented is honestly
## absent rather than reported as a false zero. Call once after the injection
## walk, when all line probes are known. `lines` is the script map's lines.
func resolve_derived(lines: Dictionary) -> void:
	if _derived.is_empty():
		return
	var line_to_probes: Dictionary = {}
	for pid: int in probe_to_line:
		var ln: int = probe_to_line[pid]
		if not line_to_probes.has(ln):
			line_to_probes[ln] = []
		line_to_probes[ln].append(pid)
	var probed_lines: Array = line_to_probes.keys()
	probed_lines.sort()
	for info in _derived:
		info.probe_id = _first_body_probe(lines, info, line_to_probes, probed_lines)
	var kept: Array = []
	for b in branches:
		if b.probe_id >= 0:
			kept.append(b)
	branches = kept


## The probe of the first measurable line that belongs to a derived branch's
## block — the first probed line after it that is indented deeper. Returns -1 if
## the immediately-following probed line is not inside the block (an empty or
## uninstrumentable body), so the branch is dropped rather than borrowing a hit
## from code outside its block.
func _first_body_probe(lines: Dictionary, info, line_to_probes: Dictionary, probed_lines: Array) -> int:
	var branch_li = lines.get(info.line_number)
	if branch_li == null:
		return -1
	for ln: int in probed_lines:
		if ln <= info.line_number:
			continue
		var body_li = lines.get(ln)
		if body_li == null:
			continue
		if body_li.indent_level <= branch_li.indent_level:
			return -1
		return line_to_probes[ln][0]
	return -1


## True if a branch is derived (block else:/pattern: with its body on following
## lines). Used by assign_all to decide between branch() and derive_branch().
static func _is_derived_branch(map, info) -> bool:
	var li = map.lines.get(info.line_number)
	if li == null:
		return false
	return not li.has_inline_body \
		and (li.type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
			or li.type == GUTCheckScriptMap.LineType.BRANCH_PATTERN)


## Mark a point to roll back to. See rollback_to().
func savepoint() -> int:
	return probe_count


## Undo every allocation made since `sp`. The instrumenter calls this when a
## multiline statement is wrapped, fails the physical-line-count round trip, and
## is abandoned — without it the ids embedded in the discarded string would
## survive in the map as orphans, the very thing inject-time allocation prevents.
func rollback_to(sp: int) -> void:
	if probe_count <= sp:
		return
	for pid in range(sp, probe_count):
		probe_to_line.erase(pid)
	var kept: Array = []
	for b in branches:
		if b.probe_id < sp:
			kept.append(b)
	branches = kept
	probe_count = sp


## Batch numbering for a fully-structured map that is NOT being injected (a
## hand-built map in a test, or any "assume everything is injectable" case).
## Numbers line probes in the canonical line-sorted layout, then injected branch
## probes, then binds derived block else/pattern branches to their body line —
## the same probe model the live injector produces.
static func assign_all(map) -> void:
	map.build_branches()
	var a := GUTCheckProbeAllocator.new()
	for line_num in map.get_executable_lines_sorted():
		a.begin_line(line_num)
		var info = map.lines[line_num]
		for _s in range(info.statement_count):
			a.line()
	for b in map.branches:
		if _is_derived_branch(map, b):
			a.derive_branch(b)
		else:
			a.branch(b)
	a.resolve_derived(map.lines)
	map.probe_to_line = a.probe_to_line
	map.branches = a.branches
	map.probe_count = a.probe_count
