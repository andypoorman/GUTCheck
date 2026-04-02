class_name GUTCheckScriptRegistry
## Tracks the mapping between script IDs and their file paths. Each source
## script gets a unique integer ID used by the instrumenter and collector.


var _next_id: int = 0
var _path_to_id: Dictionary = {}
var _id_to_path: Dictionary = {}


func register(path: String) -> int:
	if _path_to_id.has(path):
		return _path_to_id[path]

	var id := _next_id
	_next_id += 1
	_path_to_id[path] = id
	_id_to_path[id] = path
	return id


func get_id(path: String) -> int:
	return _path_to_id.get(path, -1)


func get_path(id: int) -> String:
	return _id_to_path.get(id, "")


func get_all_paths() -> Array:
	return _path_to_id.keys()


func get_script_count() -> int:
	return _next_id


func clear() -> void:
	_next_id = 0
	_path_to_id.clear()
	_id_to_path.clear()
