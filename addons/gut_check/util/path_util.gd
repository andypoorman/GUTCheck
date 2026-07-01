class_name GUTCheckPathUtil
## Small generic path and file-IO helpers shared across the exporters, the LCOV
## merger, and the report formatter. Dependency-free so any layer can call them.


## Write content to a file, truncating any existing contents. Returns OK, or the
## FileAccess open error code on failure.
static func write_file(path: String, content: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK


## Strip a leading "res://" from a path. Returns the path unchanged when the
## prefix is absent (so absolute or already-relative paths pass through).
static func strip_res_prefix(path: String) -> String:
	if path.begins_with("res://"):
		return path.substr(6)
	return path
