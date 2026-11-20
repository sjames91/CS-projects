class_name UndoStack
extends RefCounted
## Linear history. One completed user action = one entry.

signal changed

const LIMIT := 400

var _undo: Array = []
var _redo: Array = []


func push(action_name: String, undo_fn: Callable, redo_fn: Callable) -> void:
	_undo.append({"name": action_name, "undo": undo_fn, "redo": redo_fn})
	if _undo.size() > LIMIT:
		_undo.pop_front()
	_redo.clear()
	changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_name() -> String:
	return _undo.back().name if can_undo() else ""


func redo_name() -> String:
	return _redo.back().name if can_redo() else ""


func undo() -> void:
	if not can_undo():
		return
	var e: Dictionary = _undo.pop_back()
	e.undo.call()
	_redo.append(e)
	changed.emit()


func redo() -> void:
	if not can_redo():
		return
	var e: Dictionary = _redo.pop_back()
	e.redo.call()
	_undo.append(e)
	changed.emit()


func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()
