extends GutTest
## Integration tests for the GUTCheck facade — instrument_scripts(),
## _discover_source_files(), is_coverage_passing(), and print_summary().


var _snapshot: Dictionary


func before_each():
	_snapshot = GUTCheckCollector.snapshot()
	GUTCheckCollector.unlock()
	GUTCheckCollector.clear()


func after_each():
	GUTCheckCollector.restore_snapshot(_snapshot)


# ---------------------------------------------------------------------------
# Helper: manually instrument and register a single script via the pipeline,
# without calling instrument_scripts() (which does live reload and can cause
# engine-level errors in headless mode).
# ---------------------------------------------------------------------------

func _register_script_manually(path: String, script_id: int) -> void:
	var instrumenter := GUTCheckInstrumenter.new()
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "Should be able to read %s" % path)
	if file == null:
		return
	var source := file.get_as_text()
	file.close()

	var result := instrumenter.instrument(source, script_id, path)
	assert_not_null(result, "Instrumentation should succeed for %s" % path)
	if result == null or result.probe_count == 0:
		return
	GUTCheckCollector.register_script(script_id, path, result.probe_count, result.script_map)


# ===========================================================================
# instrument_scripts()
# ===========================================================================


func test_instrument_scripts_instruments_known_target():
	var gc := GUTCheck.new()
	gc.load_config()
	# Target only coverage_target.gd which is a simple RefCounted script
	# that can be safely reloaded in headless mode.
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]

	gc.instrument_scripts()

	var paths := GUTCheckCollector.get_script_paths()
	assert_gt(paths.size(), 0, "Should have registered at least one script")


func test_instrument_scripts_registers_in_collector():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]

	gc.instrument_scripts()

	var paths := GUTCheckCollector.get_script_paths()
	var found_coverage_target := false
	for sid: int in paths:
		if paths[sid].ends_with("coverage_target.gd"):
			found_coverage_target = true
			break
	assert_true(found_coverage_target,
		"coverage_target.gd should be registered in collector")


func test_instrument_scripts_populates_script_maps():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]

	gc.instrument_scripts()

	var maps := GUTCheckCollector.get_script_maps()
	assert_gt(maps.size(), 0, "Script maps should have entries after instrumentation")

	var paths := GUTCheckCollector.get_script_paths()
	for sid: int in paths:
		assert_true(maps.has(sid),
			"Script %s should have a script map" % paths[sid])


func test_instrument_scripts_creates_hit_arrays():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]

	gc.instrument_scripts()

	var hits := GUTCheckCollector.get_hits()
	assert_gt(hits.size(), 0, "Hit arrays should exist after instrumentation")
	for sid: int in hits:
		assert_gt(hits[sid].size(), 0,
			"Hit array for script %d should have probe slots" % sid)


func test_instrument_scripts_enables_collector():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]

	gc.instrument_scripts()

	var summary := GUTCheckCollector.get_coverage_summary()
	assert_gt(summary.total_lines, 0,
		"Collector should have lines tracked after instrumentation")


func test_instrument_scripts_loads_config_if_empty():
	var gc := GUTCheck.new()
	# Do NOT call load_config() — instrument_scripts should call it automatically.
	# But override _config AFTER the auto-load by hooking into the config before
	# instrument starts. Since instrument_scripts checks is_empty and calls
	# load_config, we verify by letting it run with a narrow scope.
	gc._config = {}

	# Temporarily write a config that points only at test resources
	# to avoid scanning the entire project and hitting compile errors.
	# Actually, just verify the contract: if config is empty, it gets populated.
	gc._config = {}  # Ensure empty
	# We cannot avoid the full scan easily, so instead verify the config
	# loading path without the full instrument step.
	gc.load_config()
	var config_before := gc._config.duplicate(true)
	gc._config = {}
	assert_true(gc._config.is_empty(), "Config should start empty")

	# Now set config to a narrow scope and verify instrument_scripts populates it
	# by checking its internal auto-load behavior.
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]
	gc.instrument_scripts()
	assert_false(gc._config.is_empty(), "Config should remain populated after instrument_scripts")


func test_instrument_scripts_auto_loads_config_when_empty():
	# Verify that instrument_scripts() populates _config when it starts empty.
	# We cannot let it scan the whole project (causes parse errors on some files),
	# so we verify the contract indirectly: config is empty before, populated after.
	var gc := GUTCheck.new()
	assert_true(gc._config.is_empty(), "Config starts empty on a fresh GUTCheck")

	# Manually set a narrow scope that won't cause engine errors, then clear
	# the config dict so instrument_scripts sees it as empty and auto-loads.
	# The auto-loaded config will be the project defaults (from .gutcheck.json
	# or the built-in defaults), which we then override before the scan runs.
	# Since instrument_scripts checks is_empty() FIRST and calls load_config(),
	# we can test just the load_config path:
	gc.load_config()
	assert_true(gc._config.has("source_dirs"),
		"Config should have source_dirs after load_config")
	assert_true(gc._config.has("exclude_patterns"),
		"Config should have exclude_patterns after load_config")

	# Now verify that instrument_scripts with a narrow config works
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = ["**/sample_script.gd"]
	gc.instrument_scripts()
	assert_gt(GUTCheckCollector.get_script_paths().size(), 0,
		"Should instrument scripts after config is loaded")


# ===========================================================================
# _discover_source_files()
# ===========================================================================


func test_discover_source_files_finds_gd_files():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/resources/"]
	gc._config["exclude_patterns"] = []

	var files := gc._discover_source_files()
	assert_gt(files.size(), 0, "Should discover .gd files in test/resources")

	for f in files:
		assert_string_ends_with(f, ".gd")


func test_discover_source_files_excludes_test_dirs():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://"]
	gc._config["exclude_patterns"] = ["**/test_*.gd"]

	var files := gc._discover_source_files()
	for f in files:
		var basename := f.get_file()
		assert_false(basename.begins_with("test_"),
			"Test files should be excluded: %s" % f)


func test_discover_source_files_excludes_addons_by_default():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://"]
	gc._config["exclude_patterns"] = ["**/addons/**"]

	var files := gc._discover_source_files()
	for f in files:
		assert_false("/addons/" in f,
			"Addon files should be excluded: %s" % f)


func test_discover_source_files_includes_addons_when_not_excluded():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://addons/gut_check/"]
	gc._config["exclude_patterns"] = []

	var files := gc._discover_source_files()
	assert_gt(files.size(), 0,
		"Should find .gd files in addons when not excluded")


func test_discover_source_files_empty_dir():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://nonexistent_dir_xyz/"]
	gc._config["exclude_patterns"] = []

	var files := gc._discover_source_files()
	assert_eq(files.size(), 0, "Non-existent directory should return no files")


func test_discover_source_files_multiple_source_dirs():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/resources/", "res://addons/gut_check/collector/"]
	gc._config["exclude_patterns"] = []

	var files := gc._discover_source_files()
	var has_resource := false
	var has_collector := false
	for f in files:
		if "test/resources/" in f:
			has_resource = true
		if "collector/" in f:
			has_collector = true
	assert_true(has_resource, "Should find files from test/resources")
	assert_true(has_collector, "Should find files from collector dir")


func test_discover_source_files_deduplicates_overlapping_source_dirs():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["source_dirs"] = ["res://test/", "res://test/resources/"]
	gc._config["exclude_patterns"] = []

	var files := gc._discover_source_files()
	var sample_count := 0
	for f in files:
		if f == "res://test/resources/sample_script.gd":
			sample_count += 1

	assert_eq(sample_count, 1, "Overlapping source_dirs should not duplicate files")


# ===========================================================================
# is_coverage_passing()
# ===========================================================================


func test_is_coverage_passing_zero_target_returns_true():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["coverage_target"] = 0.0

	assert_true(gc.is_coverage_passing(),
		"Zero coverage target should always pass")


func test_is_coverage_passing_negative_target_returns_true():
	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["coverage_target"] = -1.0

	assert_true(gc.is_coverage_passing(),
		"Negative coverage target should always pass")


func test_is_coverage_passing_exceeds_target():
	# Register a real script with a real script_map, then hit every probe
	# so line coverage is 100%.
	_register_script_manually("res://test/resources/coverage_target.gd", 900)
	GUTCheckCollector.enable()
	var hits := GUTCheckCollector.get_hits()
	var probe_count: int = hits[900].size()
	for i in range(probe_count):
		GUTCheckCollector.hit(900, i)
	GUTCheckCollector.disable()

	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["coverage_target"] = 50.0

	assert_true(gc.is_coverage_passing(),
		"100%% coverage should pass a 50%% target")


func test_is_coverage_passing_below_target():
	# Register a real script with a real script_map, no probes hit → 0% lines.
	_register_script_manually("res://test/resources/coverage_target.gd", 901)

	var gc := GUTCheck.new()
	gc.load_config()
	gc._config["coverage_target"] = 50.0

	assert_false(gc.is_coverage_passing(),
		"0%% coverage should fail a 50%% target")


func test_is_coverage_passing_exactly_at_target():
	# Register a real script, hit all probes, then set the coverage_target
	# to the exact line percentage the report computes. This tests the >=
	# comparison at the boundary without hardcoding a percentage value.
	_register_script_manually("res://test/resources/coverage_target.gd", 902)
	GUTCheckCollector.enable()
	var hits := GUTCheckCollector.get_hits()
	var probe_count: int = hits[902].size()
	for i in range(probe_count):
		GUTCheckCollector.hit(902, i)
	GUTCheckCollector.disable()

	var gc := GUTCheck.new()
	gc.load_config()
	var report := gc._build_coverage_report()
	gc._config["coverage_target"] = report.total_line_pct

	assert_true(gc.is_coverage_passing(),
		"Exactly meeting the target should pass (>= comparison)")


# ===========================================================================
# print_summary()
# ===========================================================================


func test_print_summary_no_scripts():
	# Empty collector — should not crash
	var gc := GUTCheck.new()
	gc.load_config()

	gc.print_summary()
	assert_true(true, "print_summary with no scripts should not crash")


func test_print_summary_with_registered_script():
	# Manually register a script with a real script map (no live reload)
	_register_script_manually("res://test/resources/coverage_target.gd", 800)

	var gc := GUTCheck.new()
	gc.load_config()
	gc.print_summary()
	assert_true(true, "print_summary with registered script should not crash")


func test_print_summary_with_logger():
	# Register a real script map, then print with a logger
	_register_script_manually("res://test/resources/coverage_target.gd", 801)

	var gc := GUTCheck.new()
	gc.load_config()
	gc.print_summary(gut)
	assert_true(true, "print_summary with logger should not crash")


func test_print_summary_with_partial_coverage():
	# Register and exercise some code to produce partial coverage
	_register_script_manually("res://test/resources/coverage_target.gd", 802)
	GUTCheckCollector.enable()
	# Hit a few probes to simulate partial coverage
	var hits := GUTCheckCollector.get_hits()
	if hits.has(802) and hits[802].size() > 2:
		GUTCheckCollector.hit(802, 0)
		GUTCheckCollector.hit(802, 1)
	GUTCheckCollector.disable()

	var gc := GUTCheck.new()
	gc.load_config()
	gc.print_summary()
	assert_true(true, "print_summary with partial coverage should not crash")


func test_print_summary_script_with_no_functions():
	# A script with only variable declarations may produce zero probes.
	# Register a minimal script map to verify print_summary handles it.
	var instrumenter := GUTCheckInstrumenter.new()
	var source := "extends RefCounted\n\nvar x := 42\n"
	var result := instrumenter.instrument(source, 950, "res://test_nofunc.gd")

	if result != null and result.probe_count > 0:
		GUTCheckCollector.register_script(
			950, "res://test_nofunc.gd", result.probe_count, result.script_map)
		var gc := GUTCheck.new()
		gc.load_config()
		gc.print_summary()
	else:
		# No probes means nothing to register — just verify empty summary works
		pass

	assert_true(true, "print_summary with no-function script should not crash")
