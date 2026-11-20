class_name TilingRegistry
extends RefCounted
## Every available tiling registers a factory here. Tools and UI only ever ask
## the registry for "a tiling with this id"; adding a tiling never touches
## tool code. Custom Shape Editor tilings register at runtime the same way.

static var _factories: Dictionary = {}
static var _order: Array[String] = []


static func _ensure_builtins() -> void:
	if not _factories.is_empty():
		return
	register("square", func(): return SquareTiling.new())
	register("hex", func(): return HexTiling.new())
	register("triangle", func(): return TriangleTiling.new())
	register("diamond", func(): return DiamondTiling.new())
	register("voronoi", func(): return VoronoiTiling.new())


static func register(tiling_id: String, factory: Callable) -> void:
	if not _factories.has(tiling_id):
		_order.append(tiling_id)
	_factories[tiling_id] = factory


static func ids() -> Array[String]:
	_ensure_builtins()
	return _order.duplicate()


static func has(tiling_id: String) -> bool:
	_ensure_builtins()
	return _factories.has(tiling_id)


static func create(tiling_id: String, cell_size: float, canvas_px: Vector2, params: Dictionary) -> Tiling:
	_ensure_builtins()
	var f: Callable = _factories.get(tiling_id, _factories["square"])
	var t: Tiling = f.call()
	return t.setup(cell_size, canvas_px, params)


static func display_name(tiling_id: String) -> String:
	_ensure_builtins()
	if not _factories.has(tiling_id):
		return tiling_id
	return (_factories[tiling_id].call() as Tiling).display_name()


static func default_params(tiling_id: String) -> Dictionary:
	_ensure_builtins()
	var out := {}
	if _factories.has(tiling_id):
		for d in (_factories[tiling_id].call() as Tiling).param_defs():
			out[d.key] = d.default
	return out
