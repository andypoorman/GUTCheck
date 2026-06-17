extends GutTest
## Regression tests for coverage-accuracy bugs found in review:
## - inline else:/match-arm bodies reported covered when they never ran
## - member var declarations reported permanently uncovered
## - multiline (paren/backslash) compound headers never instrumented
## - duplicate FN records for multiline function signatures
## - trailing semicolons pinning lines at zero hits
## - inner-class member ternary causing whole-file rollback
## - parenthesized/multiline ternaries with dead branch probes
## - property accessor bodies uninstrumentable
##
## Each test runs the full pipeline: instrument -> compile -> execute ->
## inspect collector/LCOV output.

var _snapshot: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _instrument(source: String, sid: int) -> GUTCheckInstrumentResult:
	var instrumenter := GUTCheckInstrumenter.new()
	var result := instrumenter.instrument(source, sid, "res://virtual_%d.gd" % sid)
	GUTCheckCollector.register_script(sid, "res://virtual_%d.gd" % sid,
		result.probe_count, result.script_map)
	return result


func _compile(result: GUTCheckInstrumentResult) -> GDScript:
	var script := GDScript.new()
	script.source_code = result.source
	var err := script.reload()
	assert_eq(err, OK, "Instrumented source should compile:\n%s" % result.source)
	if err != OK:
		return null
	return script


func _line_hit(result: GUTCheckInstrumentResult, sid: int, line: int) -> int:
	var hits: PackedInt32Array = GUTCheckCollector.get_hits()[sid]
	var ctx := GUTCheckCoverageComputer.build_script_context(result.script_map, hits)
	return GUTCheckCoverageComputer.get_line_hit_count(
		line, ctx.line_probes, hits, ctx.branch_line_hits)


func _branch_hits_for_line(result: GUTCheckInstrumentResult, sid: int, line: int) -> Array:
	var hits: PackedInt32Array = GUTCheckCollector.get_hits()[sid]
	var out: Array = []
	for b in result.script_map.branches:
		if b.line_number == line:
			out.append(GUTCheckCoverageComputer.get_branch_hit_count(b, hits))
	return out


func _da_lines(result: GUTCheckInstrumentResult, sid: int) -> Dictionary:
	## {line_number: hit_count} as the LCOV exporter would emit them.
	var hits: PackedInt32Array = GUTCheckCollector.get_hits()[sid]
	var report := GUTCheckCoverageComputer.compute_script_coverage(result.script_map, hits)
	var ctx := GUTCheckCoverageComputer.build_script_context(result.script_map, hits)
	var out: Dictionary = {}
	var exec_set: Dictionary = {}
	for ln in ctx.exec_lines:
		exec_set[ln] = true
	for b in result.script_map.branches:
		exec_set[b.line_number] = true
	for ln in exec_set:
		out[ln] = GUTCheckCoverageComputer.get_line_hit_count(
			ln, ctx.line_probes, hits, ctx.branch_line_hits)
	assert_eq(report.lines_found, exec_set.size(), "DA line sets should agree")
	return out


# ---------------------------------------------------------------------------
# Inline match arms / inline else must not inherit coverage from later code
# ---------------------------------------------------------------------------

func test_inline_match_arm_not_covered_when_not_taken():
	var source := """extends RefCounted

func pick(x: int) -> String:
	var r := ""
	match x:
		1: r = "one"
		2: r = "two"
	var after := r + "!"
	return after
"""
	var result := _instrument(source, 9101)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	script.new().pick(1)  # arm "2:" on line 7 never runs
	GUTCheckCollector.disable()

	assert_eq(_branch_hits_for_line(result, 9101, 6), [1], "Taken arm counts once")
	assert_eq(_branch_hits_for_line(result, 9101, 7), [0], "Untaken arm must be 0")
	assert_gt(_line_hit(result, 9101, 6), 0, "Taken arm line covered")
	assert_eq(_line_hit(result, 9101, 7), 0, "Untaken arm line must be uncovered")


func test_inline_match_arm_covered_when_taken():
	var source := """extends RefCounted

func pick(x: int) -> String:
	match x:
		1: return "one"
		2: return "two"
	return "none"
"""
	var result := _instrument(source, 9102)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.pick(2), "two", "Instrumented inline arm must still return its value")
	GUTCheckCollector.disable()

	assert_eq(_branch_hits_for_line(result, 9102, 5), [0])
	assert_eq(_branch_hits_for_line(result, 9102, 6), [1])


func test_inline_else_not_covered_when_not_taken():
	var source := """extends RefCounted

var calls := []

func act(a: bool) -> void:
	if a:
		calls.append("then")
	else: calls.append("else")
	calls.append("after")
"""
	var result := _instrument(source, 9103)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	inst.act(true)  # inline else body never runs
	GUTCheckCollector.disable()

	assert_eq(_branch_hits_for_line(result, 9103, 8), [0], "Untaken inline else must be 0")
	assert_eq(_line_hit(result, 9103, 8), 0, "Inline else line must be uncovered")

	GUTCheckCollector.enable()
	inst.act(false)
	GUTCheckCollector.disable()
	assert_eq(_branch_hits_for_line(result, 9103, 8), [1], "Inline else counts when taken")
	assert_gt(_line_hit(result, 9103, 8), 0)


func test_block_else_still_derives_from_body():
	var source := """extends RefCounted

func act(a: bool) -> String:
	if a:
		return "then"
	else:
		return "else"
"""
	var result := _instrument(source, 9104)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	inst.act(true)
	GUTCheckCollector.disable()
	assert_eq(_branch_hits_for_line(result, 9104, 6), [0], "Block else not taken yet")

	GUTCheckCollector.enable()
	inst.act(false)
	GUTCheckCollector.disable()
	assert_eq(_branch_hits_for_line(result, 9104, 6), [1], "Block else derived from body")


func test_inline_else_pass_compiles():
	var source := """extends RefCounted

func act(a: bool) -> int:
	if a:
		return 1
	else: pass
	return 0
"""
	var result := _instrument(source, 9105)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.act(false), 0)
	GUTCheckCollector.disable()
	assert_eq(_branch_hits_for_line(result, 9105, 6), [1], "else: pass counts when taken")


# ---------------------------------------------------------------------------
# Member var declarations are excluded, not permanently uncovered
# ---------------------------------------------------------------------------

func test_member_vars_excluded_from_coverage():
	var source := """extends RefCounted

var counter := 0
var label := "hi"

func bump() -> void:
	counter += 1
"""
	var result := _instrument(source, 9106)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	script.new().bump()
	GUTCheckCollector.disable()

	var da := _da_lines(result, 9106)
	assert_false(da.has(3), "Member var line must not get a DA record")
	assert_false(da.has(4), "Member var line must not get a DA record")
	assert_gt(da.get(7, 0), 0, "Function body still covered")


func test_inner_class_member_ternary_compiles_and_tracks():
	var source := """extends RefCounted

class Inner:
	var mode := "a" if true else "b"

	func get_mode() -> String:
		return mode
"""
	var result := _instrument(source, 9107)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inner = script.new().Inner.new()
	assert_eq(inner.get_mode(), "a")
	GUTCheckCollector.disable()

	var da := _da_lines(result, 9107)
	assert_false(da.has(4), "Inner-class member ternary excluded, not instrumented")
	assert_gt(da.get(7, 0), 0, "Inner-class method body covered")


# ---------------------------------------------------------------------------
# Multiline compound headers (paren + backslash continuations)
# ---------------------------------------------------------------------------

func test_multiline_paren_condition_instrumented():
	var source := """extends RefCounted

func check(a: bool, b: bool) -> int:
	if (a
			and b):
		return 1
	return 0
"""
	var result := _instrument(source, 9108)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.check(true, true), 1)
	assert_eq(inst.check(true, false), 0)
	GUTCheckCollector.disable()

	assert_gt(_line_hit(result, 9108, 4), 0, "Multiline if header line covered")
	var branches := _branch_hits_for_line(result, 9108, 4)
	assert_eq(branches.size(), 2)
	assert_eq(branches[0], 1, "True branch taken once")
	assert_eq(branches[1], 1, "False branch taken once")


func test_multiline_backslash_condition_instrumented():
	var source := "extends RefCounted\n\nfunc check(a: bool, b: bool) -> int:\n\tif a \\\n\t\t\tand b:\n\t\treturn 1\n\treturn 0\n"
	var result := _instrument(source, 9109)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.check(true, true), 1)
	GUTCheckCollector.disable()

	assert_gt(_line_hit(result, 9109, 4), 0, "Backslash-continued if header covered")
	var branches := _branch_hits_for_line(result, 9109, 4)
	assert_eq(branches, [1, 0], "True branch hit, false branch not")


func test_multiline_while_and_for_instrumented():
	var source := """extends RefCounted

func count(n: int) -> int:
	var total := 0
	var i := 0
	while (i <
			n):
		i += 1
	for x in (
			range(n)):
		total += x
	return total
"""
	var result := _instrument(source, 9110)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.count(3), 3)
	GUTCheckCollector.disable()

	assert_gt(_line_hit(result, 9110, 6), 0, "Multiline while header covered")
	assert_gt(_line_hit(result, 9110, 9), 0, "Multiline for header covered")


func test_multiline_statement_line_count_preserved():
	var source := """extends RefCounted

func check(a: bool, b: bool) -> int:
	if (a
			and b):
		return 1
	return 0
"""
	var result := _instrument(source, 9111)
	assert_eq(result.source.split("\n").size(), source.split("\n").size(),
		"Instrumentation must never change the physical line count")


# ---------------------------------------------------------------------------
# Ternaries: parenthesized and multiline
# ---------------------------------------------------------------------------

func test_parenthesized_ternary_branches_tracked():
	var source := """extends RefCounted

func pick(c: bool) -> String:
	var r = ("yes" if c else "no")
	return r
"""
	var result := _instrument(source, 9112)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.pick(true), "yes")
	GUTCheckCollector.disable()

	var branches := _branch_hits_for_line(result, 9112, 4)
	assert_eq(branches, [1, 0], "Parenthesized ternary branches must be live probes")


func test_multiline_ternary_branches_tracked():
	var source := """extends RefCounted

func pick(c: bool) -> String:
	var r = ("yes" if c
			else "no")
	return r
"""
	var result := _instrument(source, 9113)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var inst = script.new()
	assert_eq(inst.pick(false), "no")
	GUTCheckCollector.disable()

	var branches := _branch_hits_for_line(result, 9113, 4)
	assert_eq(branches, [0, 1], "Multiline ternary false branch must count")


# ---------------------------------------------------------------------------
# Trailing semicolons
# ---------------------------------------------------------------------------

func test_trailing_semicolon_line_covered():
	var source := """extends RefCounted

func go() -> int:
	var a := 1;
	return a
"""
	var result := _instrument(source, 9114)
	assert_eq(result.script_map.lines[4].statement_count, 1,
		"Trailing semicolon must not create a phantom statement")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	script.new().go()
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9114, 4), 0, "Line with trailing semicolon covered")


# ---------------------------------------------------------------------------
# Multiline signatures: exactly one function record
# ---------------------------------------------------------------------------

func test_multiline_signature_single_function_record():
	var source := """extends RefCounted

func foo(a: int,
		b: int) -> int:
	return a + b
"""
	var result := _instrument(source, 9115)
	var names: Array = []
	for f in result.script_map.functions:
		names.append(f.name)
	assert_eq(names, ["foo"], "Multiline signature must register exactly one function")

	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().foo(1, 2), 3)
	GUTCheckCollector.disable()

	var exporter := GUTCheckLcovExporter.new()
	var lcov := exporter.generate_lcov()
	var fn_count := 0
	for line in lcov.split("\n"):
		if line.begins_with("FN:") and line.ends_with(",foo"):
			fn_count += 1
	assert_eq(fn_count, 1, "LCOV must contain exactly one FN record for foo")
	assert_string_contains(lcov, "FNF:1")


# ---------------------------------------------------------------------------
# Property accessors with block bodies are tracked and instrumented
# ---------------------------------------------------------------------------

func test_property_accessor_bodies_covered():
	var source := """extends RefCounted

var _value := 0

var tracked: int:
	get:
		return _value
	set(v):
		_value = v

func poke() -> int:
	tracked = 5
	return tracked
"""
	var result := _instrument(source, 9116)
	var fn_names: Array = []
	for f in result.script_map.functions:
		fn_names.append(f.name)
	assert_has(fn_names, "tracked.get", "Block get accessor registered as function")
	assert_has(fn_names, "tracked.set", "Block set accessor registered as function")

	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().poke(), 5)
	GUTCheckCollector.disable()

	assert_gt(_line_hit(result, 9116, 7), 0, "get body covered after read")
	assert_gt(_line_hit(result, 9116, 9), 0, "set body covered after write")


# ---------------------------------------------------------------------------
# Comment containing a colon after a block colon must not corrupt wrapping
# ---------------------------------------------------------------------------

func test_comment_with_colon_after_if_compiles():
	var source := """extends RefCounted

func check(x: int) -> int:
	if x > 0:  # note: positive path
		return 1
	return 0
"""
	var result := _instrument(source, 9117)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().check(1), 1)
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9117, 4), 0, "Header with colon-in-comment covered")


# ---------------------------------------------------------------------------
# Config: documented keys must not warn
# ---------------------------------------------------------------------------

func test_cobertura_output_is_known_config_key():
	assert_true(GUTCheck.DEFAULT_CONFIG.has("cobertura_output"),
		"cobertura_output is documented and must be a known config key")


# ===========================================================================
# Round 2 — regressions found by the max-effort code review.
# Each test below fails on the pre-fix code and passes after.
# ===========================================================================

# --- R1: nested / parenthesized ternaries must not corrupt the wrap ---------

func test_nested_ternary_compiles_and_tracks_both_blocks():
	# Pre-fix: the right-to-left splice used a stale else_pos for the outer
	# ternary → garbled source → parse error → whole-file rollback.
	var source := """extends RefCounted

func pick(c: bool) -> int:
	var x = 1 if (2 if c else 3) else 4
	return x
"""
	var result := _instrument(source, 9201)
	assert_eq(result.script_map.lines[4].ternary_count, 2, "two ternaries on the line")
	var script := _compile(result)  # asserts the instrumented source compiles
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().pick(true), 1, "nested ternary keeps its value after wrapping")
	GUTCheckCollector.disable()

	var branches := _branch_hits_for_line(result, 9201, 4)
	assert_eq(branches.size(), 4, "two ternary blocks → four branch probes")
	var hit := 0
	for h in branches:
		if h > 0:
			hit += 1
	assert_eq(hit, 2, "pick(true) takes one branch of each ternary")


func test_nested_ternary_other_path():
	var source := """extends RefCounted

func pick(c: bool) -> int:
	return 1 if (2 if c else 0) else 4
"""
	var result := _instrument(source, 9208)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	# c=false → inner 0 (falsy) → outer false → 4
	assert_eq(script.new().pick(false), 4, "nested ternary false path keeps value")
	GUTCheckCollector.disable()


# --- R2: semicolon splitter must emit exactly statement_count probes --------

func test_trailing_comment_semicolon_no_phantom_probe():
	# Pre-fix: the comment-only trailing segment got its own probe, overrunning
	# into the next line's probe id → false coverage (or OOB on the last line).
	var source := """extends RefCounted

func run() -> int:
	var a = 1; var b = 2; # trailing note
	return a + b
"""
	var result := _instrument(source, 9202)
	assert_eq(result.script_map.lines[4].statement_count, 2, "two real statements")
	var line4: String = result.source.split("\n")[3]
	assert_eq(line4.count("GUTCheckCollector.hit("), 2,
		"exactly two probes — the comment segment gets none")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().run(), 3)
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9202, 4), 0, "the multi-statement line is covered")


func test_double_semicolon_no_phantom_probe():
	var source := """extends RefCounted

func run() -> int:
	var a = 1;; var b = 2
	return a + b
"""
	var result := _instrument(source, 9203)
	assert_eq(result.script_map.lines[4].statement_count, 2, "empty segment is not a statement")
	var line4: String = result.source.split("\n")[3]
	assert_eq(line4.count("GUTCheckCollector.hit("), 2,
		"the empty `;;` segment gets no probe")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().run(), 3)
	GUTCheckCollector.disable()


func test_trailing_comment_semicolon_last_line_no_overrun():
	# When the multi-statement line is the last allocation, the phantom probe id
	# equalled probe_count → out-of-bounds write on every execution. Exactly
	# statement_count probes keeps every id in range.
	var source := """extends RefCounted

func run() -> void:
	var a = 1; prints(a); # done
"""
	var result := _instrument(source, 9204)
	var line4: String = result.source.split("\n")[3]
	assert_eq(line4.count("GUTCheckCollector.hit("), 2)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	script.new().run()  # must not OOB-write
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9204, 4), 0)


# --- R3: single-colon property accessors must be tracked & instrumented -----

func test_single_colon_property_bodies_covered():
	# Pre-fix: `var prop = 0:` (one colon) pushed no property scope, so the
	# get/set bodies became class-level NON_EXECUTABLE and vanished.
	var source := """extends RefCounted

var _x := 0

var prop = 0:
	get:
		return _x
	set(v):
		_x = v

func poke() -> int:
	prop = 7
	return prop
"""
	var result := _instrument(source, 9205)
	var fn_names: Array = []
	for f in result.script_map.functions:
		fn_names.append(f.name)
	assert_has(fn_names, "prop.get", "single-colon get accessor registered as a function")
	assert_has(fn_names, "prop.set", "single-colon set accessor registered as a function")

	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().poke(), 7)
	GUTCheckCollector.disable()

	assert_gt(_line_hit(result, 9205, 7), 0, "get body (return _x) covered after read")
	assert_gt(_line_hit(result, 9205, 9), 0, "set body (_x = v) covered after write")


# --- P2: match binding-pattern arms must classify as patterns ---------------

func test_match_var_binding_pattern_covered():
	# Pre-fix: `var v:` stayed EXECUTABLE → probe prepended → parse error →
	# whole-file rollback.
	var source := """extends RefCounted

func classify(x: int) -> String:
	match x:
		0:
			return "zero"
		var v:
			return "got %d" % v
"""
	var result := _instrument(source, 9207)
	assert_eq(result.script_map.lines[7].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN,
		"`var v:` is a binding pattern, not an executable statement")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().classify(5), "got 5", "binding pattern arm runs after wrapping")
	GUTCheckCollector.disable()
	# the binding-pattern arm body executed
	assert_gt(_line_hit(result, 9207, 8), 0, "binding-pattern arm body covered")


func test_match_var_binding_pattern_with_when_guard():
	var source := """extends RefCounted

func classify(x: int) -> String:
	match x:
		var v when v > 10:
			return "big"
		_:
			return "small"
"""
	var result := _instrument(source, 9209)
	assert_eq(result.script_map.lines[5].type, GUTCheckScriptMap.LineType.BRANCH_PATTERN,
		"guarded binding pattern is a pattern")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().classify(50), "big")
	GUTCheckCollector.disable()


# --- P3: compound header with an inline typed-var body must compile ---------

func test_inline_typed_var_body_compiles():
	# Pre-fix: find_block_colon returned the LAST depth-0 colon (the type
	# colon), so the wrap captured `c: var y` → parse error → rollback.
	var source := """extends RefCounted

func run(c: bool) -> int:
	if c: var y: int = 1
	return 0
"""
	var result := _instrument(source, 9206)
	var line4: String = result.source.split("\n")[3]
	assert_string_contains(line4, "GUTCheckCollector.hit_br2(")
	assert_string_contains(line4, ",c): var y: int = 1")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().run(true), 0)
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9206, 4), 0, "inline-typed-body header is covered")


func test_typed_for_loop_still_wraps():
	# The first-colon change must not break typed loop vars, whose colon is
	# BEFORE the iterable — the block colon is still found after `in`.
	var source := """extends RefCounted

func total(n: int) -> int:
	var sum := 0
	for i: int in range(n):
		sum += i
	return sum
"""
	var result := _instrument(source, 9210)
	var line5: String = result.source.split("\n")[4]
	assert_string_contains(line5, "GUTCheckCollector.hit_br2rng(")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().total(4), 6)
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9210, 5), 0, "typed for header covered")


# --- R4: declaration-only scripts are registered, not skipped ---------------

func test_declaration_only_script_registers_zero_probes():
	# Pre-fix: a 0-probe script was treated as a failure — warned, added to
	# skipped, and omitted from all coverage output. It should register with
	# no coverable lines instead.
	var path := "user://gutcheck_decl_only.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends RefCounted\n\nconst MAX := 100\nvar health := 100\nsignal died\nenum State { IDLE, RUN }\n")
	f.close()

	var gc := GUTCheck.new()
	var entry := gc._prepare_file(path)

	assert_true(entry.is_empty(), "0-probe file produces no reload entry")
	assert_false(gc.get_skipped_scripts().has(path),
		"declaration-only file must NOT be marked skipped")
	assert_true(GUTCheckCollector.get_script_paths().values().has(path),
		"declaration-only file must be registered so it appears in coverage output")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# Option A — injection verification: allocated-but-not-injected probes are
# excluded (not reported as a false zero), and a durable invariant proves
# allocation == injection going forward.
# ===========================================================================

## Every probe still in the map after instrumentation must actually appear in
## the emitted source (line probes), or be a derivable block else/pattern
## branch. This is the guard that any future wrapper change which orphans a
## probe trips immediately — and the harness that will de-risk Option B.
## Test-only scan of instrumented source for the probe ids actually emitted, so
## the invariant below can independently prove every surviving probe id is really
## present. Production no longer scans — inject-time allocation makes that
## unnecessary — but this stays as a safety net that re-derives the truth from
## the emitted source rather than trusting the allocator.
func _scan_injected_probe_ids(source: String) -> Dictionary:
	var injected: Dictionary = {}
	var re := RegEx.new()
	# Longest method names first so the alternation matches them whole.
	re.compile("GUTCheckCollector\\.(hit_br2rng|hit_br2|hit|br2|br|rng)\\((\\d+(?:,\\d+)*)")
	for m in re.search_all(source):
		var method: String = m.get_string(1)
		var nums: PackedStringArray = m.get_string(2).split(",")  # nums[0] is the script id
		var pid_count := 0
		match method:
			"hit", "br", "rng":
				pid_count = 1
			"br2":
				pid_count = 2
			"hit_br2", "hit_br2rng":
				pid_count = 3
		for i in range(1, mini(1 + pid_count, nums.size())):
			injected[int(nums[i])] = true
	return injected


func _assert_probe_invariant(result: GUTCheckInstrumentResult, ctx_msg: String) -> void:
	var injected := _scan_injected_probe_ids(result.source)
	for pid: int in result.script_map.probe_to_line:
		assert_true(injected.has(pid),
			"%s: surviving line probe %d must appear in instrumented source" % [ctx_msg, pid])
	for b in result.script_map.branches:
		var li = result.script_map.lines.get(b.line_number)
		var derivable: bool = li != null and not li.has_inline_body \
			and (li.type == GUTCheckScriptMap.LineType.BRANCH_ELSE \
				or li.type == GUTCheckScriptMap.LineType.BRANCH_PATTERN)
		assert_true(injected.has(b.probe_id) or derivable,
			"%s: surviving branch probe %d (line %d) must be injected or derivable" % [
				ctx_msg, b.probe_id, b.line_number])


func test_probe_invariant_holds_over_resource_corpus():
	var files := [
		"res://test/resources/validation_target.gd",
		"res://test/resources/ternary_target.gd",
		"res://test/resources/sample_script.gd",
		"res://test/resources/coverage_target.gd",
	]
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "could not open %s" % path)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		var result := GUTCheckInstrumenter.new().instrument(src, 9310, path)
		_assert_probe_invariant(result, path)


# ===========================================================================
# Round 3 — the four orthogonal bugs A/B didn't cover.
# ===========================================================================

# --- Bug 1: multiline triple-quoted string must not be corrupted ------------

func test_multiline_string_value_not_corrupted():
	# Pre-fix: the string's (indented) closing line was classified executable
	# and got a probe prepended INSIDE the literal → corrupted value + a probe
	# that never fires. The whole literal must be one logical statement.
	var source := "extends RefCounted\n\nfunc make() -> String:\n\tvar s = \"\"\"hello\n\tworld\"\"\"\n\treturn s\n"
	var result := _instrument(source, 9410)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	var got: String = script.new().make()
	GUTCheckCollector.disable()
	assert_eq(got, "hello\n\tworld", "multiline string value intact (no probe injected inside it)")
	assert_gt(_line_hit(result, 9410, 4), 0, "the string's opening line is covered")
	assert_false(result.script_map.lines.has(5) and result.script_map.lines[5].is_executable(),
		"the string's closing line is not a separate executable line")


# --- Bug 2: dense keyword forms are now instrumented ------------------------

func test_dense_ternary_now_instrumented():
	# `1 if(c)else 2` (no spaces around the keywords) is valid GDScript; the
	# relaxed boundary check now wraps it instead of leaving it un-instrumented.
	var source := """extends RefCounted

func pick(c: bool) -> int:
	var x = 1 if(c)else 2
	return x
"""
	var result := _instrument(source, 9301)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().pick(true), 1, "dense ternary still returns correctly")
	GUTCheckCollector.disable()

	var branches := _branch_hits_for_line(result, 9301, 4)
	assert_eq(branches.size(), 2, "dense ternary now has its two branch probes")
	assert_eq(branches, [1, 0], "true branch taken (c=true), false not")
	assert_gt(_line_hit(result, 9301, 4), 0, "line covered")
	_assert_probe_invariant(result, "dense ternary")


func test_dense_for_in_now_instrumented():
	var source := "extends RefCounted\n\nfunc total(arr: Array) -> int:\n\tvar s := 0\n\tfor x in(arr):\n\t\ts += x\n\treturn s\n"
	var result := _instrument(source, 9420)
	var line5: String = result.source.split("\n")[4]
	assert_string_contains(line5, "GUTCheckCollector.hit_br2rng(")
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	assert_eq(script.new().total([1, 2, 3]), 6)
	GUTCheckCollector.disable()
	assert_gt(_line_hit(result, 9420, 5), 0, "dense for header covered")
	assert_eq(_branch_hits_for_line(result, 9420, 5).size(), 2, "dense for has its branch probes")


# --- Bug 3: lambda function coverage measures invocation, not definition ----

func test_inline_lambda_not_falsely_covered():
	# A bracket-nested inline lambda that's never invoked (empty array) must not
	# be reported as a covered function — so it isn't registered at all.
	var source := "extends RefCounted\n\nfunc run(items: Array) -> Array:\n\treturn items.map(func(x): return x * 2)\n"
	var result := _instrument(source, 9430)
	var lambda_count := 0
	for f in result.script_map.functions:
		if String(f.name).begins_with("<lambda"):
			lambda_count += 1
	assert_eq(lambda_count, 0, "inline lambda is not registered as a measurable function")

	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	script.new().run([])  # empty → the lambda is never called
	GUTCheckCollector.disable()
	var hits: PackedInt32Array = GUTCheckCollector.get_hits()[9430]
	var report := GUTCheckCoverageComputer.compute_script_coverage(result.script_map, hits)
	assert_eq(report.funcs_found, 1, "only run() is counted, not the inline lambda")
	assert_eq(report.funcs_hit, 1, "run() is covered")


func test_multiline_lambda_uncovered_when_only_defined():
	# A block-bodied lambda that's defined but never called must show 0 — its
	# FNDA derives from the body line, not the definition line.
	var source := "extends RefCounted\n\nfunc setup() -> Callable:\n\tvar cb = func():\n\t\treturn 42\n\treturn cb\n"
	var result := _instrument(source, 9431)
	var script := _compile(result)
	if script == null:
		return
	GUTCheckCollector.enable()
	script.new().setup()  # defines the lambda but never invokes it
	GUTCheckCollector.disable()
	var hits: PackedInt32Array = GUTCheckCollector.get_hits()[9431]
	var report := GUTCheckCoverageComputer.compute_script_coverage(result.script_map, hits)
	assert_eq(report.funcs_found, 2, "setup() and the multiline lambda are both counted")
	assert_eq(report.funcs_hit, 1, "only setup() ran; the lambda body never executed")


# --- Bug 4: typed-for `:=` widening degrades instead of rolling back --------

func test_typed_for_conservative_compiles_and_covers_body():
	var bad := "extends RefCounted\n\nfunc sum_x(items: Array[Vector2]) -> float:\n\tvar total := 0.0\n\tfor it in items:\n\t\tvar x := it.x\n\t\ttotal += x\n\treturn total\n"
	# Normal instrumentation wraps the iterable → `it` becomes Variant →
	# `var x := it.x` can't infer → won't compile.
	var normal := GUTCheckInstrumenter.new().instrument(bad, 9440, "res://typed_for.gd")
	var s1 := GDScript.new()
	s1.source_code = normal.source
	gut.error_tracker.disabled = true  # the next reload fails on purpose
	var r1 := s1.reload()
	gut.error_tracker.disabled = false
	assert_ne(r1, OK, "normal instrumentation fails to compile (Variant widening)")

	# Conservative skips the for-wrapping → `it` keeps its type → compiles.
	var cons := GUTCheckInstrumenter.new().instrument(bad, 9441, "res://typed_for.gd", true)
	var s2 := GDScript.new()
	s2.source_code = cons.source
	assert_eq(s2.reload(), OK, "conservative instrumentation compiles")
	GUTCheckCollector.register_script(9441, "res://typed_for.gd", cons.probe_count, cons.script_map)
	GUTCheckCollector.enable()
	var arr: Array[Vector2] = [Vector2(1, 2), Vector2(3, 4)]
	var r: float = s2.new().sum_x(arr)
	GUTCheckCollector.disable()
	assert_eq(r, 4.0, "conservative-instrumented code runs correctly")
	assert_gt(_line_hit(cons, 9441, 6), 0, "for-body line still covered under conservative mode")


func test_reload_file_retries_conservatively_on_failure():
	var bad := "extends RefCounted\n\nfunc sum_x(items: Array[Vector2]) -> float:\n\tvar total := 0.0\n\tfor it in items:\n\t\tvar x := it.x\n\t\ttotal += x\n\treturn total\n"
	var script := GDScript.new()
	script.source_code = bad
	assert_eq(script.reload(), OK, "original source compiles")

	var normal := GUTCheckInstrumenter.new().instrument(bad, 9442, "res://typed_for2.gd")
	var entry := {
		"path": "res://typed_for2.gd",
		"source": normal.source,
		"script": script,
		"script_id": 9442,
		"probe_count": normal.probe_count,
		"script_map": normal.script_map,
	}
	var gc := GUTCheck.new()
	gut.error_tracker.disabled = true  # the first (normal) reload fails on purpose
	gc._reload_file(entry)
	gut.error_tracker.disabled = false

	assert_false(gc.get_skipped_scripts().has("res://typed_for2.gd"),
		"retry avoids skipping the file")
	assert_true(GUTCheckCollector.get_script_paths().values().has("res://typed_for2.gd"),
		"file registered via the conservative retry")


func test_clean_file_excludes_nothing():
	var source := """extends RefCounted

func f(a: bool, b) -> int:
	if a:
		return 1
	for x in b:
		print(x)
	return 0
"""
	var result := _instrument(source, 9302)
	var injected := _scan_injected_probe_ids(result.source)
	# Nothing is pruned: every line probe in the map is present in the source.
	for pid: int in result.script_map.probe_to_line:
		assert_true(injected.has(pid), "clean file: line probe %d injected" % pid)
	_assert_probe_invariant(result, "clean file")
	assert_not_null(_compile(result), "clean file compiles")
