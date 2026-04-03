extends GutTest
## Unit tests for GUTCheckCollector — covers hit methods, branch methods,
## range methods, and state management (lock/unlock/snapshot/reset/clear).

const SID := 99  # arbitrary script_id for test isolation
const PROBE_COUNT := 10  # enough probes for all test scenarios

var _snapshot: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()
	# Register a test script with enough probes for every test
	GUTCheckCollector.register_script(SID, "res://test_collector_fake.gd", PROBE_COUNT, null)


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _hits(probe_id: int) -> int:
	return GUTCheckCollector.get_hits()[SID][probe_id]


# ===========================================================================
# hit_br2()
# ===========================================================================

func test_hit_br2_returns_true_unchanged():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	assert_true(result, "hit_br2 should return true when condition is true")


func test_hit_br2_returns_false_unchanged():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.hit_br2(SID, 0, 1, 2, false)
	assert_false(result, "hit_br2 should return false when condition is false")


func test_hit_br2_fires_line_probe():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	assert_eq(_hits(0), 1, "Line probe should be incremented")


func test_hit_br2_fires_true_pid_when_true():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	assert_eq(_hits(1), 1, "True probe should be incremented when condition is true")


func test_hit_br2_fires_false_pid_when_false():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, false)
	assert_eq(_hits(2), 1, "False probe should be incremented when condition is false")


func test_hit_br2_does_not_fire_true_pid_when_false():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, false)
	assert_eq(_hits(1), 0, "True probe should NOT be incremented when condition is false")


func test_hit_br2_does_not_fire_false_pid_when_true():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	assert_eq(_hits(2), 0, "False probe should NOT be incremented when condition is true")


func test_hit_br2_disabled_returns_value_but_no_hits():
	# _enabled defaults to false after clear()
	var result = GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	assert_true(result, "Should still return condition value when disabled")
	assert_eq(_hits(0), 0, "Line probe should not increment when disabled")
	assert_eq(_hits(1), 0, "True probe should not increment when disabled")
	assert_eq(_hits(2), 0, "False probe should not increment when disabled")


func test_hit_br2_accumulates_hits():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, true)
	GUTCheckCollector.hit_br2(SID, 0, 1, 2, false)
	assert_eq(_hits(0), 3, "Line probe should accumulate across calls")
	assert_eq(_hits(1), 2, "True probe should accumulate across true calls")
	assert_eq(_hits(2), 1, "False probe should accumulate across false calls")


# ===========================================================================
# hit_br2rng()
# ===========================================================================

func test_hit_br2rng_returns_array_unchanged():
	GUTCheckCollector.enable()
	var input := [1, 2, 3]
	var result = GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, input)
	assert_eq(result, [1, 2, 3], "Should return original array")


func test_hit_br2rng_returns_dictionary_unchanged():
	GUTCheckCollector.enable()
	var input := {"a": 1}
	var result = GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, input)
	assert_eq(result, {"a": 1}, "Should return original dictionary")


func test_hit_br2rng_returns_string_unchanged():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, "hello")
	assert_eq(result, "hello", "Should return original string")


func test_hit_br2rng_returns_packed_string_array_unchanged():
	GUTCheckCollector.enable()
	var input := PackedStringArray(["a", "b"])
	var result = GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, input)
	assert_eq(result, PackedStringArray(["a", "b"]), "Should return original PackedStringArray")


func test_hit_br2rng_fires_line_probe():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, [1])
	assert_eq(_hits(0), 1, "Line probe should be incremented")


func test_hit_br2rng_fires_true_pid_for_non_empty_array():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, [1, 2])
	assert_eq(_hits(1), 1, "True probe should fire for non-empty array")
	assert_eq(_hits(2), 0, "False probe should not fire for non-empty array")


func test_hit_br2rng_fires_false_pid_for_empty_array():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, [])
	assert_eq(_hits(1), 0, "True probe should not fire for empty array")
	assert_eq(_hits(2), 1, "False probe should fire for empty array")


func test_hit_br2rng_fires_true_pid_for_non_empty_dict():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, {"k": "v"})
	assert_eq(_hits(1), 1, "True probe should fire for non-empty dictionary")


func test_hit_br2rng_fires_false_pid_for_empty_dict():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, {})
	assert_eq(_hits(2), 1, "False probe should fire for empty dictionary")


func test_hit_br2rng_fires_true_pid_for_non_empty_string():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, "abc")
	assert_eq(_hits(1), 1, "True probe should fire for non-empty string")


func test_hit_br2rng_fires_false_pid_for_empty_string():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, "")
	assert_eq(_hits(2), 1, "False probe should fire for empty string")


func test_hit_br2rng_unknown_type_treated_as_non_empty():
	# An integer is not Array/Dict/String — falls through to the else branch
	# which assumes non-empty (true_pid fires)
	GUTCheckCollector.enable()
	GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, 42)
	assert_eq(_hits(1), 1, "Unknown types should be treated as non-empty")
	assert_eq(_hits(2), 0)


func test_hit_br2rng_disabled_returns_value_no_hits():
	var result = GUTCheckCollector.hit_br2rng(SID, 0, 1, 2, [1, 2])
	assert_eq(result, [1, 2], "Should return iterable when disabled")
	assert_eq(_hits(0), 0, "Line probe should not increment when disabled")
	assert_eq(_hits(1), 0, "True probe should not increment when disabled")


# ===========================================================================
# br2() — same as hit_br2 but no line probe
# ===========================================================================

func test_br2_returns_true_unchanged():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.br2(SID, 1, 2, true)
	assert_true(result)


func test_br2_returns_false_unchanged():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.br2(SID, 1, 2, false)
	assert_false(result)


func test_br2_fires_true_pid_when_true():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2(SID, 1, 2, true)
	assert_eq(_hits(1), 1, "True probe should fire")
	assert_eq(_hits(2), 0, "False probe should not fire")


func test_br2_fires_false_pid_when_false():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2(SID, 1, 2, false)
	assert_eq(_hits(1), 0, "True probe should not fire")
	assert_eq(_hits(2), 1, "False probe should fire")


func test_br2_does_not_fire_line_probe():
	# br2 only has true_pid and false_pid — no line_pid parameter.
	# Verify probe 0 (which we are NOT passing) stays at zero.
	GUTCheckCollector.enable()
	GUTCheckCollector.br2(SID, 1, 2, true)
	GUTCheckCollector.br2(SID, 1, 2, false)
	assert_eq(_hits(0), 0, "br2 should not touch any line probe")


func test_br2_disabled_no_hits():
	GUTCheckCollector.br2(SID, 1, 2, true)
	assert_eq(_hits(1), 0)
	assert_eq(_hits(2), 0)


# ===========================================================================
# br2rng() — same as hit_br2rng but no line probe
# ===========================================================================

func test_br2rng_returns_array_unchanged():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.br2rng(SID, 1, 2, [10, 20])
	assert_eq(result, [10, 20])


func test_br2rng_fires_true_pid_for_non_empty():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2rng(SID, 1, 2, [1])
	assert_eq(_hits(1), 1)
	assert_eq(_hits(2), 0)


func test_br2rng_fires_false_pid_for_empty():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2rng(SID, 1, 2, [])
	assert_eq(_hits(1), 0)
	assert_eq(_hits(2), 1)


func test_br2rng_does_not_fire_line_probe():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2rng(SID, 1, 2, [1, 2])
	GUTCheckCollector.br2rng(SID, 1, 2, [])
	assert_eq(_hits(0), 0, "br2rng should not touch any line probe")


func test_br2rng_empty_dict():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2rng(SID, 1, 2, {})
	assert_eq(_hits(2), 1, "Empty dict should fire false_pid")


func test_br2rng_empty_string():
	GUTCheckCollector.enable()
	GUTCheckCollector.br2rng(SID, 1, 2, "")
	assert_eq(_hits(2), 1, "Empty string should fire false_pid")


func test_br2rng_disabled_returns_value():
	var result = GUTCheckCollector.br2rng(SID, 1, 2, ["x"])
	assert_eq(result, ["x"], "Should return iterable when disabled")
	assert_eq(_hits(1), 0)


# ===========================================================================
# State management
# ===========================================================================

func test_lock_prevents_clear_from_destroying_registrations():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	assert_eq(_hits(0), 1)
	GUTCheckCollector.lock()
	GUTCheckCollector.clear()
	# After locked clear, registration should still exist
	assert_true(GUTCheckCollector.get_hits().has(SID),
		"Locked clear should preserve registrations")


func test_unlock_allows_clear():
	GUTCheckCollector.lock()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()
	assert_false(GUTCheckCollector.get_hits().has(SID),
		"Unlocked clear should remove registrations")


func test_snapshot_restore_roundtrip():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	GUTCheckCollector.hit(SID, 0)
	GUTCheckCollector.hit(SID, 3)
	var snap = GUTCheckCollector.snapshot()

	# Mutate state
	GUTCheckCollector.hit(SID, 0)
	GUTCheckCollector.hit(SID, 5)
	assert_eq(_hits(0), 3, "Sanity check: hits should have changed")

	# Restore
	GUTCheckCollector.restore_snapshot(snap)
	assert_eq(_hits(0), 2, "Restored hit count should match snapshot")
	assert_eq(_hits(3), 1, "Restored hit count should match snapshot")
	assert_eq(_hits(5), 0, "Probe not hit before snapshot should be zero")


func test_reset_zeros_hits_without_removing_registrations():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	GUTCheckCollector.hit(SID, 1)
	assert_eq(_hits(0), 1)

	GUTCheckCollector.reset()

	assert_true(GUTCheckCollector.get_hits().has(SID),
		"Registration should survive reset")
	assert_eq(_hits(0), 0, "Hits should be zeroed after reset")
	assert_eq(_hits(1), 0, "Hits should be zeroed after reset")


func test_unregister_script_removes_probes():
	assert_true(GUTCheckCollector.get_hits().has(SID))
	GUTCheckCollector.unregister_script(SID)
	assert_false(GUTCheckCollector.get_hits().has(SID),
		"Hits should be removed after unregister")
	assert_false(GUTCheckCollector.get_script_paths().has(SID),
		"Path should be removed after unregister")
	assert_false(GUTCheckCollector.get_script_maps().has(SID),
		"Script map should be removed after unregister")


func test_register_script_creates_zeroed_hit_array():
	var sid2 := 200
	GUTCheckCollector.register_script(sid2, "res://other.gd", 5, null)
	var hits: PackedInt32Array = GUTCheckCollector.get_hits()[sid2]
	assert_eq(hits.size(), 5, "Hit array should match requested probe count")
	for i in range(5):
		assert_eq(hits[i], 0, "All probes should start at zero")


func test_multiple_register_scripts_are_independent():
	var sid_a := 300
	var sid_b := 301
	GUTCheckCollector.register_script(sid_a, "res://a.gd", 3, null)
	GUTCheckCollector.register_script(sid_b, "res://b.gd", 4, null)

	GUTCheckCollector.enable()
	GUTCheckCollector.hit(sid_a, 0)
	GUTCheckCollector.hit(sid_b, 0)
	GUTCheckCollector.hit(sid_b, 0)

	assert_eq(GUTCheckCollector.get_hits()[sid_a][0], 1,
		"Script A probe 0 should have 1 hit")
	assert_eq(GUTCheckCollector.get_hits()[sid_b][0], 2,
		"Script B probe 0 should have 2 hits")
	assert_eq(GUTCheckCollector.get_hits()[sid_a].size(), 3)
	assert_eq(GUTCheckCollector.get_hits()[sid_b].size(), 4)


func test_register_stores_path_and_map():
	var sid2 := 400
	var fake_map := {"fake": true}
	GUTCheckCollector.register_script(sid2, "res://stored.gd", 2, fake_map)
	assert_eq(GUTCheckCollector.get_script_paths()[sid2], "res://stored.gd")
	assert_eq(GUTCheckCollector.get_script_maps()[sid2], fake_map)


# ===========================================================================
# hit() and br() basics (sanity coverage)
# ===========================================================================

func test_hit_increments_probe():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	GUTCheckCollector.hit(SID, 0)
	assert_eq(_hits(0), 2)


func test_hit_disabled_no_increment():
	GUTCheckCollector.hit(SID, 0)
	assert_eq(_hits(0), 0)


func test_br_returns_value_and_increments():
	GUTCheckCollector.enable()
	var result = GUTCheckCollector.br(SID, 0, 42)
	assert_eq(result, 42, "br should return value unchanged")
	assert_eq(_hits(0), 1)


func test_br_disabled_returns_value_no_hit():
	var result = GUTCheckCollector.br(SID, 0, "hello")
	assert_eq(result, "hello")
	assert_eq(_hits(0), 0)


func test_rng_returns_value_and_increments():
	GUTCheckCollector.enable()
	var input := [10, 20, 30]
	var result = GUTCheckCollector.rng(SID, 0, input)
	assert_eq(result, [10, 20, 30])
	assert_eq(_hits(0), 1)


func test_rng_disabled_returns_value_no_hit():
	var result = GUTCheckCollector.rng(SID, 0, [1])
	assert_eq(result, [1])
	assert_eq(_hits(0), 0)


# ===========================================================================
# enable / disable
# ===========================================================================

func test_enable_disable_toggle():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	assert_eq(_hits(0), 1)

	GUTCheckCollector.disable()
	GUTCheckCollector.hit(SID, 0)
	assert_eq(_hits(0), 1, "Should not increment after disable")

	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	assert_eq(_hits(0), 2, "Should increment again after re-enable")


# ===========================================================================
# get_coverage_summary()
# ===========================================================================

func test_coverage_summary_with_no_hits():
	var summary = GUTCheckCollector.get_coverage_summary()
	assert_eq(summary.total_lines, PROBE_COUNT)
	assert_eq(summary.hit_lines, 0)
	assert_eq(summary.percentage, 0.0)


func test_coverage_summary_with_partial_hits():
	GUTCheckCollector.enable()
	GUTCheckCollector.hit(SID, 0)
	GUTCheckCollector.hit(SID, 3)
	GUTCheckCollector.hit(SID, 7)
	GUTCheckCollector.disable()

	var summary = GUTCheckCollector.get_coverage_summary()
	assert_eq(summary.hit_lines, 3)
	assert_eq(summary.total_lines, PROBE_COUNT)
	assert_almost_eq(summary.percentage, 30.0, 0.01)
