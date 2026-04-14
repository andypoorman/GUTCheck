class_name GUTCheckCollector
## Static coverage data collector. Instrumented scripts call hit(), br(), and
## rng() on this class to record line execution. Uses PackedInt32Array for
## fast indexed access.
##
## This class is entirely static so that instrumented scripts can reference it
## by class_name without needing an instance or autoload.
##
## NOT thread-safe. All instrumented code must run on the main thread.
## Loading instrumented scripts on background threads (e.g., ResourceLoader)
## may corrupt coverage data.


## script_id -> PackedInt32Array of hit counts (indexed by probe_id)
static var _hits: Dictionary = {}

## script_id -> source file path (res:// path)
static var _script_paths: Dictionary = {}

## script_id -> GUTCheckScriptMap
static var _script_maps: Dictionary = {}

## Whether collection is active
static var _enabled: bool = false

## When locked, clear() preserves instrumentation registrations and keeps
## collection enabled. Used for self-coverage so test cleanup doesn't
## destroy production instrumentation state.
static var _locked: bool = false


## Register a script for coverage tracking. Must be called before any hits
## are recorded for this script_id.
static func register_script(script_id: int, path: String, probe_count: int, script_map) -> void:
	var hits := PackedInt32Array()
	hits.resize(probe_count)
	_hits[script_id] = hits
	_script_paths[script_id] = path
	_script_maps[script_id] = script_map


## Record a hit on an executable line. Called by instrumented code via:
##   GUTCheckCollector.hit(sid, pid);original_statement
static func hit(script_id: int, probe_id: int) -> void:
	if _enabled:
		_hits[script_id][probe_id] += 1


## Record a hit and return the value unchanged. Used to wrap conditions:
##   if GUTCheckCollector.br(sid, pid, original_condition):
static func br(script_id: int, probe_id: int, value: Variant) -> Variant:
	if _enabled:
		_hits[script_id][probe_id] += 1
	return value


## Record a branch hit into one of two probes depending on truthiness.
## Used for if/elif/while to track both true and false branches:
##   if GUTCheckCollector.br2(sid, true_pid, false_pid, condition):
static func br2(script_id: int, true_pid: int, false_pid: int, value: Variant) -> Variant:
	if _enabled:
		if value:
			_hits[script_id][true_pid] += 1
		else:
			_hits[script_id][false_pid] += 1
	return value


## Record a line hit AND a branch hit. Fires the line probe (pid) plus
## the appropriate branch probe (true_pid or false_pid) in one call.
##   if GUTCheckCollector.hit_br2(sid, pid, true_pid, false_pid, condition):
static func hit_br2(script_id: int, line_pid: int, true_pid: int, false_pid: int, value: Variant) -> Variant:
	if _enabled:
		_hits[script_id][line_pid] += 1
		if value:
			_hits[script_id][true_pid] += 1
		else:
			_hits[script_id][false_pid] += 1
	return value


## Record a hit and return the value unchanged. Used to wrap iterables:
##   for i in GUTCheckCollector.rng(sid, pid, range(10)):
static func rng(script_id: int, probe_id: int, value: Variant) -> Variant:
	if _enabled:
		_hits[script_id][probe_id] += 1
	return value


## Record a line hit AND a branch hit for a for-loop iterable.
## Fires line probe plus true_pid (non-empty) or false_pid (empty).
##   for i in GUTCheckCollector.hit_br2rng(sid, pid, true_pid, false_pid, range(10)):
static func hit_br2rng(script_id: int, line_pid: int, true_pid: int, false_pid: int, value: Variant) -> Variant:
	if _enabled:
		_hits[script_id][line_pid] += 1
		if _is_non_empty_iterable(value):
			_hits[script_id][true_pid] += 1
		else:
			_hits[script_id][false_pid] += 1
	return value


## Record a branch hit for a for-loop iterable. If the iterable has elements,
## records a hit on true_pid; if empty, records on false_pid. Returns the value.
##   for i in GUTCheckCollector.br2rng(sid, true_pid, false_pid, range(10)):
static func br2rng(script_id: int, true_pid: int, false_pid: int, value: Variant) -> Variant:
	if _enabled:
		if _is_non_empty_iterable(value):
			_hits[script_id][true_pid] += 1
		else:
			_hits[script_id][false_pid] += 1
	return value


static func _is_non_empty_iterable(value: Variant) -> bool:
	if value is Array or value is PackedByteArray or value is PackedInt32Array \
			or value is PackedInt64Array or value is PackedFloat32Array \
			or value is PackedFloat64Array or value is PackedStringArray \
			or value is PackedVector2Array or value is PackedVector3Array \
			or value is PackedColorArray or value is PackedVector4Array:
		return value.size() > 0
	if value is Dictionary:
		return value.size() > 0
	if value is String:
		return value.length() > 0
	# For unknown iterables (generators, custom objects), assume non-empty
	# since Godot will just skip the loop body if empty.
	return true


static func enable() -> void:
	_enabled = true


static func disable() -> void:
	_enabled = false


static func reset() -> void:
	for sid: int in _hits:
		_hits[sid].fill(0)


## Remove a single script from tracking. Used to roll back failed instrumentation.
static func unregister_script(script_id: int) -> void:
	_hits.erase(script_id)
	_script_paths.erase(script_id)
	_script_maps.erase(script_id)


static func clear() -> void:
	if _locked:
		# When locked, clear() is a no-op. This preserves real
		# instrumentation data for self-coverage while tests run.
		return
	_hits.clear()
	_script_paths.clear()
	_script_maps.clear()
	_enabled = false


## Lock the collector so clear() only resets hit counters instead of
## removing registrations. Used for self-coverage.
static func lock() -> void:
	_locked = true


static func unlock() -> void:
	_locked = false


## Snapshot the full collector state. Returns an opaque dictionary that
## can be passed to restore_snapshot() to bring everything back.
static func snapshot() -> Dictionary:
	return {
		"hits": _hits.duplicate(true),
		"paths": _script_paths.duplicate(true),
		"maps": _script_maps.duplicate(true),
		"enabled": _enabled,
		"locked": _locked,
	}


## Restore a previously taken snapshot.
static func restore_snapshot(snap: Dictionary) -> void:
	_hits = snap.hits.duplicate(true)
	_script_paths = snap.paths.duplicate(true)
	_script_maps = snap.maps.duplicate(true)
	_enabled = snap.enabled
	_locked = snap.locked


static func get_hits() -> Dictionary:
	return _hits


static func get_script_paths() -> Dictionary:
	return _script_paths


static func get_script_maps() -> Dictionary:
	return _script_maps


## Returns probe-based coverage counts (hit probes / total probes), NOT line-based.
## For canonical line-coverage metrics, use GUTCheck._build_coverage_report().total_line_pct.
static func get_coverage_summary() -> Dictionary:
	var total_lines := 0
	var hit_lines := 0
	var per_script: Dictionary = {}

	for sid: int in _hits:
		var hits: PackedInt32Array = _hits[sid]
		var path: String = _script_paths.get(sid, "unknown")
		var script_total := hits.size()
		var script_hit := 0

		for h in hits:
			if h > 0:
				script_hit += 1

		total_lines += script_total
		hit_lines += script_hit

		per_script[path] = {
			"lines_found": script_total,
			"lines_hit": script_hit,
			"percentage": (float(script_hit) / float(script_total) * 100.0) if script_total > 0 else 0.0,
		}

	return {
		"total_lines": total_lines,
		"hit_lines": hit_lines,
		"percentage": (float(hit_lines) / float(total_lines) * 100.0) if total_lines > 0 else 0.0,
		"scripts": per_script,
	}
