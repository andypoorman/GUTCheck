extends GutTest
## Tests for GUTCheckPathUtil — generic path and file-IO helpers.


func test_strip_res_prefix_removes_leading_res():
	assert_eq(GUTCheckPathUtil.strip_res_prefix("res://scripts/player.gd"), "scripts/player.gd")


func test_strip_res_prefix_only_prefix_returns_empty():
	assert_eq(GUTCheckPathUtil.strip_res_prefix("res://"), "")


func test_strip_res_prefix_leaves_non_res_path_unchanged():
	assert_eq(GUTCheckPathUtil.strip_res_prefix("/tmp/abs.gd"), "/tmp/abs.gd")
	assert_eq(GUTCheckPathUtil.strip_res_prefix("scripts/player.gd"), "scripts/player.gd")


func test_strip_res_prefix_empty_string():
	assert_eq(GUTCheckPathUtil.strip_res_prefix(""), "")


func test_write_file_writes_content_and_returns_ok():
	var path := "user://test_path_util_write.txt"
	assert_eq(GUTCheckPathUtil.write_file(path, "hello\nworld"), OK)
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f)
	if f:
		assert_eq(f.get_as_text(), "hello\nworld")
		f.close()
	DirAccess.remove_absolute(path)


func test_write_file_returns_error_for_unwritable_path():
	# FileAccess.open(WRITE) does not create missing parent dirs, so this fails.
	var result := GUTCheckPathUtil.write_file("user://__no_such_dir__/x.txt", "x")
	assert_ne(result, OK, "Writing under a nonexistent directory should return an error")
