class_name GUTCheckCollector
## Static coverage data collector. Instrumented scripts call hit(), br(), and
## rng() on this class to record line execution. Uses PackedInt32Array for
## fast indexed access.
##
## This class is entirely static so that instrumented scripts can reference it
## by class_name without needing an instance or autoload.


## script_id -> PackedInt32Array of hit counts (indexed by probe_id)
static var _hits: Dictionary = {}

## script_id -> source file path (res:// path)
static var _script_paths: Dictionary = {}

## script_id -> GUTCheckScriptMap
static var _script_maps: Dictionary = {}

## Whether collection is active
static var _enabled: bool = false


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


## Record a hit and return the value unchanged. Used to wrap iterables:
##   for i in GUTCheckCollector.rng(sid, pid, range(10)):
static func rng(script_id: int, probe_id: int, value: Variant) -> Variant:
	if _enabled:
		_hits[script_id][probe_id] += 1
	return value


## Record a branch hit for a for-loop iterable. If the iterable has elements,
## records a hit on true_pid; if empty, records on false_pid. Returns the value.
##   for i in GUTCheckCollector.br2rng(sid, true_pid, false_pid, range(10)):
static func br2rng(script_id: int, true_pid: int, false_pid: int, value: Variant) -> Variant:
	if _enabled:
		# Check if the iterable is non-empty. For arrays, strings, dicts,
		# and other collections that support size/length checks.
		var non_empty := false
		if value is Array or value is PackedByteArray or value is PackedInt32Array \
				or value is PackedInt64Array or value is PackedFloat32Array \
				or value is PackedFloat64Array or value is PackedStringArray \
				or value is PackedVector2Array or value is PackedVector3Array \
				or value is PackedColorArray or value is PackedVector4Array:
			non_empty = value.size() > 0
		elif value is Dictionary:
			non_empty = value.size() > 0
		elif value is String:
			non_empty = value.length() > 0
		else:
			# For unknown iterables (generators, custom objects), assume non-empty
			# since Godot will just skip the loop body if empty.
			non_empty = true
		if non_empty:
			_hits[script_id][true_pid] += 1
		else:
			_hits[script_id][false_pid] += 1
	return value


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
	_hits.clear()
	_script_paths.clear()
	_script_maps.clear()
	_enabled = false


static func get_hits() -> Dictionary:
	return _hits


static func get_script_paths() -> Dictionary:
	return _script_paths


static func get_script_maps() -> Dictionary:
	return _script_maps


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
