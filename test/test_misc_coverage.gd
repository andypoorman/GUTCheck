extends GutTest


func test_script_registry_accessors_and_clear():
	var registry := GUTCheckScriptRegistry.new()
	var id_a := registry.register("res://a.gd")
	var id_b := registry.register("res://b.gd")

	assert_eq(id_a, 0)
	assert_eq(id_b, 1)
	assert_eq(registry.get_id("res://a.gd"), id_a)
	assert_eq(registry.get_id("res://missing.gd"), -1)
	assert_eq(registry.get_path(id_b), "res://b.gd")
	assert_eq(registry.get_path(999), "")
	assert_eq(registry.get_script_count(), 2)

	var paths := registry.get_all_paths()
	assert_true(paths.has("res://a.gd"))
	assert_true(paths.has("res://b.gd"))

	registry.clear()
	assert_eq(registry.get_script_count(), 0)
	assert_eq(registry.get_id("res://a.gd"), -1)
	assert_eq(registry.get_all_paths().size(), 0)


func test_get_branch_hit_count_returns_zero_when_line_info_missing():
	var script_map := GUTCheckScriptMap.new()
	var branch := GUTCheckBranchInfo.new(10, 0, 0, 0, true)
	script_map.branches.append(branch)
	var hits := PackedInt32Array([0])

	var hit_count := GUTCheckCoverageComputer.get_branch_hit_count(branch, script_map, hits)
	assert_eq(hit_count, 0)


func test_get_branch_hit_count_returns_zero_for_non_derivable_branch_type():
	var script_map := GUTCheckScriptMap.new()
	script_map.lines[10] = GUTCheckLineInfo.new(10, GUTCheckScriptMap.LineType.BRANCH_IF)
	var branch := GUTCheckBranchInfo.new(10, 0, 0, 0, true)
	script_map.branches.append(branch)
	var hits := PackedInt32Array([0])

	var hit_count := GUTCheckCoverageComputer.get_branch_hit_count(branch, script_map, hits)
	assert_eq(hit_count, 0)


func test_derive_body_hits_returns_zero_for_missing_probe_mapping():
	var hits := PackedInt32Array([3])
	var body_probe_ids := {}

	var hit_count := GUTCheckCoverageComputer.derive_body_hits(20, null, hits, body_probe_ids)
	assert_eq(hit_count, 0)


func test_derive_body_hits_returns_zero_for_out_of_range_probe_id():
	var hits := PackedInt32Array([1])
	var body_probe_ids := {20: 5}

	var hit_count := GUTCheckCoverageComputer.derive_body_hits(20, null, hits, body_probe_ids)
	assert_eq(hit_count, 0)


func test_build_body_probe_ids_without_body_line_keeps_default_value():
	var script_map := GUTCheckScriptMap.new()
	script_map.lines[5] = GUTCheckLineInfo.new(5, GUTCheckScriptMap.LineType.BRANCH_ELSE)
	var branch := GUTCheckBranchInfo.new(5, 0, 0, 0, true)
	script_map.branches.append(branch)

	var body_probe_ids := GUTCheckCoverageComputer.build_body_probe_ids(
		script_map, {}, [])
	assert_true(body_probe_ids.has(5))
	assert_eq(body_probe_ids[5], -1)
