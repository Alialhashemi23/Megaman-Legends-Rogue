extends RefCounted
class_name DiverNavigation

var grid = AStarGrid2D.new()

# Rooms and corridors are open floor; obstacles (cover and raised stonework)
# are solid, except the `open_areas` robots may walk on: platform tops and ramps.
func build(rooms: Array, obstacles: Array, links: Array = [], open_areas: Array = []) -> void:
	var low = Vector2i(9999, 9999)
	var high = Vector2i(-9999, -9999)
	for room in rooms:
		var c = cell(room.center)
		var reach = Vector2i(int(room.half.x) + 2, int(room.half.y) + 2)
		low = Vector2i(mini(low.x, c.x - reach.x), mini(low.y, c.y - reach.y))
		high = Vector2i(maxi(high.x, c.x + reach.x), maxi(high.y, c.y + reach.y))
	grid.region = Rect2i(low, high - low + Vector2i.ONE)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	grid.fill_solid_region(grid.region, true)
	for room in rooms:
		var inner = Vector2i(int(room.half.x) - 1, int(room.half.y) - 1)
		grid.fill_solid_region(Rect2i(cell(room.center) - inner, inner * 2 + Vector2i.ONE), false)
	# Corridors, reaching a little way into the rooms they join.
	for link in links:
		var d: Vector2i = link.dir
		var start = Vector2i(roundi(link.from.x), roundi(link.from.y)) - d * 2
		var steps = roundi(link.from.distance_to(link.to)) + 4
		for offset in range(0, steps + 1):
			for side in range(-2, 3):
				var point = start + d * offset + Vector2i(-d.y, d.x) * side
				if grid.is_in_boundsv(point): grid.set_point_solid(point, false)
	for obstacle in obstacles:
		mark(obstacle.grow(0.65), true)
	for area in open_areas:
		mark(area, false)

func mark(bounds: Rect2, solid: bool) -> void:
	for x in range(int(floor(bounds.position.x)), int(ceil(bounds.end.x)) + 1):
		for z in range(int(floor(bounds.position.y)), int(ceil(bounds.end.y)) + 1):
			var p = Vector2i(x, z)
			if grid.is_in_boundsv(p) and bounds.grow(0.001).has_point(Vector2(x, z)): grid.set_point_solid(p, solid)

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
