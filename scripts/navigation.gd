extends RefCounted
class_name DiverNavigation

var grid = AStarGrid2D.new()

func build(rooms: Array, obstacles: Array) -> void:
	var low = Vector2i(9999, 9999)
	var high = Vector2i(-9999, -9999)
	for room in rooms:
		var c = cell(room.center)
		low = Vector2i(mini(low.x, c.x - 12), mini(low.y, c.y - 12))
		high = Vector2i(maxi(high.x, c.x + 12), maxi(high.y, c.y + 12))
	grid.region = Rect2i(low, high - low + Vector2i.ONE)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	grid.fill_solid_region(grid.region, true)
	for room in rooms:
		var c = cell(room.center)
		grid.fill_solid_region(Rect2i(c - Vector2i(9, 9), Vector2i(19, 19)), false)
		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor = false
			for other in rooms:
				if other.cell == room.cell + direction: neighbor = true; break
			if not neighbor: continue
			for offset in range(10, 17):
				for side in range(-2, 3):
					var point = c + direction * offset + Vector2i(-direction.y, direction.x) * side
					if grid.is_in_boundsv(point): grid.set_point_solid(point, false)
	for obstacle in obstacles:
		var bounds: Rect2 = obstacle.grow(0.65)
		for x in range(int(floor(bounds.position.x)), int(ceil(bounds.end.x)) + 1):
			for z in range(int(floor(bounds.position.y)), int(ceil(bounds.end.y)) + 1):
				var p = Vector2i(x, z)
				if grid.is_in_boundsv(p) and bounds.has_point(Vector2(x, z)): grid.set_point_solid(p, true)

func cell(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.z))

func closest_open(p: Vector2i) -> Vector2i:
	if grid.is_in_boundsv(p) and not grid.is_point_solid(p): return p
	for radius in range(1, 5):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var candidate = p + Vector2i(x, y)
				if grid.is_in_boundsv(candidate) and not grid.is_point_solid(candidate): return candidate
	return p

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a = closest_open(cell(from))
	var b = closest_open(cell(to))
	var result = PackedVector3Array()
	if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b): return result
	if grid.is_point_solid(a) or grid.is_point_solid(b): return result
	for point in grid.get_id_path(a, b): result.append(Vector3(point.x, 0, point.y))
	return result

func open_at(pos: Vector3) -> bool:
	var p = cell(pos)
	return grid.is_in_boundsv(p) and not grid.is_point_solid(p)
