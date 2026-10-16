extends RefCounted
class_name DiverRuins

# Plans and builds a floor: chambers of several kinds, passages that fork or
# dead-end, and the corridors joining them. Every machine builds the same floor
# from the same seed, so all gameplay random choices come from game.rng in a
# fixed order. Painted decoration uses no random draws and changes no collisions.

const CELL = 40.0
const ROOM_HALF = 15.0
const HALL_HALF = 4.0
const DOOR_WIDTH = 5.2
# Wall sides in order: north, east, south, west.
const DIRECTIONS = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const INWARD = [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
const PALETTES = [["d2cbb5", "f0e1c3", "657e89"], ["bcc9b1", "d8e0bf", "5d8172"], ["bbc2d3", "cbd4e6", "607598"]]
# Warm archive stone / copper garden machinery / indigo inner mechanisms.
# Color is painted into the surfaces; keep lighting simple and matte.
const THEMES = [
	{"panel": "ruin_archive_panel", "trim": "b9d4d3", "fixture": "93afb8", "ceiling": "89968e", "lamp": "ffe0ae"},
	{"panel": "ruin_garden_panel", "trim": "d8c59a", "fixture": "b8aa83", "ceiling": "849b82", "lamp": "f2e6bd"},
	{"panel": "ruin_core_panel", "trim": "b6c5e2", "fixture": "8fa5cb", "ceiling": "78849d", "lamp": "d6e6ff"}
]
# Layouts 0-4 are the cover arrangements; these are the special chambers.
const CLIMB = 5
const TERRACE = 6
const GRAND = 7
const HALL = 8

var game: Node3D
var palette: Array = PALETTES[0]
var theme: Dictionary = THEMES[0]

# --- Planning ---------------------------------------------------------------

func plan() -> void:
	var rng: RandomNumberGenerator = game.rng
	game.rooms.clear()
	game.links.clear()
	var owner = {}
	var cells: Array[Vector2i] = []
	claim(add_room([Vector2i.ZERO], "landing"), owner, cells)
	var order = ["grand"]
	for n in 5 + game.depth: order.append("chamber")
	for n in 2 + game.depth: order.append("hall")
	shuffle(order)
	for kind in order:
		for attempt in 400:
			var anchor: Vector2i = pick_anchor(owner, cells)
			var d: Vector2i = DIRECTIONS[rng.randi_range(0, 3)]
			var cell = anchor + d
			var from: int = owner[anchor]
			if owner.has(cell) or link_count(from) >= door_limit(from): continue
			var taken = [cell]
			if kind == "grand":
				var e: Vector2i = [d, Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)][rng.randi_range(0, 2)]
				if owner.has(cell + e): continue
				taken.append(cell + e)
			claim(add_room(taken, kind), owner, cells)
			add_link(from, game.rooms.size() - 1, anchor, d)
			break
	# A few extra corridors turn the tree into loops, so there is more than one way round.
	for cell in cells:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not owner.has(cell + d): continue
			var a: int = owner[cell]
			var b: int = owner[cell + d]
			if a == b or linked(a, b) or link_count(a) >= door_limit(a) or link_count(b) >= door_limit(b): continue
			if rng.randi_range(0, 99) < 22: add_link(a, b, cell, d)
	game.rooms[0].distance = 0
	var queue = [0]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for link in game.links:
			if link.a != index and link.b != index: continue
			var other: int = link.b if link.a == index else link.a
			if game.rooms[other].distance > game.rooms[index].distance + 1:
				game.rooms[other].distance = game.rooms[index].distance + 1
				queue.append(other)
	# The guardian waits in the chamber furthest from the landing.
	game.exit_room = -1
	for i in game.rooms.size():
		if game.rooms[i].kind != "chamber": continue
		if game.exit_room < 0 or game.rooms[i].distance >= game.rooms[game.exit_room].distance: game.exit_room = i
	game.rooms[game.exit_room].kind = "guardian"
	game.rooms[game.exit_room].type = "guardian"
	var covers = [0, 1, 2, 3, 4]
	shuffle(covers)
	var chambers = []
	for i in game.rooms.size():
		var room: Dictionary = game.rooms[i]
		if room.kind == "hall": room.dead_end = link_count(i) == 1
		if room.kind == "chamber": chambers.append(i)
	var deck = [CLIMB, TERRACE]
	for n in maxi(0, chambers.size() - 2): deck.append(covers[n % 5])
	shuffle(deck)
	for n in chambers.size():
		var room: Dictionary = game.rooms[chambers[n]]
		room.layout = deck[n]
		# Ledges and terraces are built against a wall without a door.
		if room.layout >= CLIMB and free_side(chambers[n]) < 0: room.layout = covers[n % 5]

func shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j = game.rng.randi_range(0, i)
		var kept = list[i]
		list[i] = list[j]
		list[j] = kept

func add_room(cells: Array, kind: String) -> int:
	var low = Vector2(cells[0])
	var high = low
	for c in cells:
		low = low.min(Vector2(c))
		high = high.max(Vector2(c))
	var middle = (low + high) * 0.5 * CELL
	var half = (high - low) * 0.5 * CELL + Vector2.ONE * (HALL_HALF if kind == "hall" else ROOM_HALF)
	var first = game.rooms.is_empty()
	game.rooms.append({"cell": cells[0], "cells": cells, "center": Vector3(middle.x, 0, middle.y), "half": half, "kind": kind, "type": kind,
		"layout": GRAND if kind == "grand" else HALL if kind == "hall" else 0, "height": 4.8 if kind == "hall" else 8.0 if kind == "grand" else 6.4,
		"visited": first, "entered": first, "cleared": first or kind == "hall", "distance": 999, "dead_end": false,
		"cache_at": null, "well_at": null, "bonus_at": null, "pots": []})
	return game.rooms.size() - 1

func claim(index: int, owner: Dictionary, cells: Array[Vector2i]) -> void:
	for c in game.rooms[index].cells:
		owner[c] = index
		cells.append(c)

# Passages that can still branch are favoured, so hallways fork.
func pick_anchor(owner: Dictionary, cells: Array[Vector2i]) -> Vector2i:
	var rng: RandomNumberGenerator = game.rng
	var forks = []
	for c in cells:
		if game.rooms[owner[c]].kind == "hall" and link_count(owner[c]) < 3: forks.append(c)
	if not forks.is_empty() and rng.randi_range(0, 99) < 45: return forks[rng.randi_range(0, forks.size() - 1)]
	return cells[rng.randi_range(0, cells.size() - 1)]

func add_link(a: int, b: int, cell: Vector2i, d: Vector2i) -> void:
	var from = Vector2(cell) * CELL + Vector2(d) * cell_half(a)
	var to = Vector2(cell + d) * CELL - Vector2(d) * cell_half(b)
	game.links.append({"a": a, "b": b, "cell": cell, "dir": d, "from": from, "to": to})

func cell_half(index: int) -> float:
	return HALL_HALF if game.rooms[index].kind == "hall" else ROOM_HALF

func link_count(index: int) -> int:
	var count = 0
	for link in game.links:
		if link.a == index or link.b == index: count += 1
	return count

func linked(a: int, b: int) -> bool:
	for link in game.links:
		if (link.a == a and link.b == b) or (link.a == b and link.b == a): return true
	return false

func door_limit(index: int) -> int:
	var kind: String = game.rooms[index].kind
	return 4 if kind == "hall" else 5 if kind == "grand" else 3

# Doors of a room: the wall side and the position along that wall.
func doors_of(index: int) -> Array:
	var room: Dictionary = game.rooms[index]
	var result = []
	for link in game.links:
		if link.a != index and link.b != index: continue
		var cell: Vector2i = link.cell if link.a == index else link.cell + link.dir
		var d: Vector2i = link.dir if link.a == index else -link.dir
		var local = Vector2(cell) * CELL - Vector2(room.center.x, room.center.z)
		result.append({"side": DIRECTIONS.find(d), "along": local.x if d.x == 0 else local.y})
	return result

func free_side(index: int) -> int:
	var doors = doors_of(index)
	for side in 4:
		var used = false
		for door in doors:
			if door.side == side: used = true
		if not used: return side
	return -1

# --- Construction -----------------------------------------------------------

func build() -> void:
	palette = PALETTES[game.depth - 1]
	theme = THEMES[game.depth - 1]
	for i in game.rooms.size(): build_room(i)
	for link in game.links: build_corridor(link)

# A point `inset` metres in from a wall and `along` it, in room coordinates.
func wall_point(room: Dictionary, side: int, along: float, inset: float, y: float = 0.0) -> Vector3:
	match side:
		0: return Vector3(along, y, -room.half.y + inset)
		1: return Vector3(room.half.x - inset, y, along)
		2: return Vector3(-along, y, room.half.y - inset)
	return Vector3(-room.half.x + inset, y, -along)

func wall_size(side: int, along: float, height: float, depth: float) -> Vector3:
	return Vector3(along, height, depth) if side % 2 == 0 else Vector3(depth, height, along)

func room_crest_index(room: Dictionary) -> int:
	match room.kind:
		"landing": return 0
		"guardian": return 9
		"grand": return 8
		"hall": return 11 if room.dead_end else 10
	return clampi(int(room.layout) + 1, 1, 7)

func wall_face(faces: Array, room: Dictionary, side: int, along: float, y: float, size: Vector2, inset: float = 0.365) -> void:
	# QuadMesh faces +Z; clockwise walls face inward. Existing walls are 0.7 m
	# thick, so the paint lies just inside their surface, never across an opening.
	# Scale in the face's local axes before rotating (east/west walls included).
	var basis = Basis(Vector3.UP, -side * PI / 2) * Basis.from_scale(Vector3(size.x, size.y, 1))
	faces.append(Transform3D(basis, wall_point(room, side, along, inset, y)))

func finish_wall_details(root: Node3D, room: Dictionary, details: Dictionary) -> void:
	DiverArt.panels(root, details.panels, DiverArt.painted(str(theme.panel)))
	DiverArt.panels(root, details.bands, DiverArt.painted("ruin_border", Color(theme.trim)))
	DiverArt.panels(root, details.crests, DiverArt.room_crest(room_crest_index(room)))

func fixture_faces(faces: Array, center: Vector3, size: Vector3) -> void:
	# Paint the existing solid machines instead of adding non-solid prop clutter.
	for side in 4:
		var width = minf(1.6, (size.x if side % 2 == 0 else size.z) - 0.30)
		var height = minf(1.6, size.y - 0.30)
		var reach = (size.z if side % 2 == 0 else size.x) * 0.5 + 0.012
		var basis = Basis(Vector3.UP, -side * PI / 2) * Basis.from_scale(Vector3(width, height, 1))
		faces.append(Transform3D(basis, center + INWARD[side] * reach))

func build_room(index: int) -> void:
	var room: Dictionary = game.rooms[index]
	var rng: RandomNumberGenerator = game.rng
	var root = Node3D.new()
	game.world.add_child(root)
	root.position = room.center
	var hx: float = room.half.x
	var hz: float = room.half.y
	var top: float = room.height
	var stone = Color(palette[0])
	var floor_mesh = DiverArt.box(root, Vector3(0, -0.35, 0), Vector3(hx * 2, 0.7, hz * 2), stone, true)
	floor_mesh.material_override = DiverArt.painted("ruin_floor", stone, 0.5)
	DiverArt.box(root, Vector3(0, top + 0.15, 0), Vector3(hx * 2 + 0.4, 0.3, hz * 2 + 0.4), Color(theme.ceiling), true)
	var tile_positions = []
	var tile_tints = []
	for x in range(-int(hx) + 1, int(hx), 2):
		for z in range(-int(hz) + 1, int(hz), 2):
			tile_tints.append(stone.lightened(rng.randi_range(-1, 3) * 0.015))
			tile_positions.append(Vector3(x, 0.005, z))
	DiverArt.tiles(root, tile_positions, tile_tints, Vector3(1.94, 0.018, 1.94))
	var doors = doors_of(index)
	var landmark_side = free_side(index)
	if landmark_side < 0: landmark_side = index % 4
	var details = {"panels": [], "bands": [], "crests": [], "landmark_side": landmark_side}
	for side in 4:
		var offsets = []
		for door in doors:
			if door.side == side: offsets.append(door.along)
		build_wall(root, room, side, offsets, details)
	finish_wall_details(root, room, details)
	if room.kind == "hall":
		build_hall(root, room, doors.size())
		return
	for beam in range(-int(hx) + 5, int(hx), 10): DiverArt.box(root, Vector3(beam, top - 0.10, 0), Vector3(0.25, 0.20, hz * 2), Color("435d5c"))
	for beam in range(-int(hz) + 5, int(hz), 10): DiverArt.box(root, Vector3(0, top - 0.10, beam), Vector3(hx * 2, 0.20, 0.25), Color("435d5c"))
	var lamps = [Vector3(-9, 0, -7.5), Vector3(9, 0, 7.5)]
	if room.kind == "grand": lamps = [Vector3(-hx + 13, 0, -hz + 9), Vector3(hx - 13, 0, hz - 9), Vector3(-hx + 13, 0, hz - 9), Vector3(hx - 13, 0, -hz + 9)]
	for at in lamps: lamp(root, at + Vector3(0, top - 1.7, 0), 22, 0.95)
	# Inlaid circuit paths guide the eye toward the exits.
	if room.kind != "grand":
		var seal = Transform3D(Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(8, 8, 1)), Vector3(0, 0.03, 0))
		DiverArt.panels(root, [seal], DiverArt.painted("ruin_floor_seal", Color(palette[0])))
	for sign_dir in [-1, 1]:
		DiverArt.box(root, Vector3(sign_dir * 5.0, 0.025, 0), Vector3(0.09, 0.025, hz * 2 - 9), Color("638d83"))
		DiverArt.box(root, Vector3(0, 0.025, sign_dir * 5.0), Vector3(hx * 2 - 9, 0.025, 0.09), Color("638d83"))
	room.cache_at = room.center + Vector3(6, 0, -4.5)
	room.well_at = room.center + Vector3(-6, 0, 4.5)
	room.pots = [room.center + Vector3(-10.5, 0, 9), room.center + Vector3(10.5, 0, 9)]
	match room.kind:
		"landing":
			DiverArt.cylinder(root, Vector3(0, 0.08, 3), 2, 0.12, DiverArt.INK)
			DiverArt.label(root, Vector3(0, 4.2, -9), "ARCHIVE  /  %02d" % game.depth, DiverArt.TEAL, 50)
			for x in [-10.5, 10.5]:
				DiverArt.cylinder(root, Vector3(x, 1.2, -10.5), 0.7, 2.4, Color(palette[1]))
				DiverArt.orb(root, Vector3(x, 2.6, -10.5), 0.32, DiverArt.GOLD, 1)
		"guardian":
			DiverArt.label(root, Vector3(0, 5.2, -10), game.BOSS_NAMES[game.depth - 1], DiverArt.GOLD, 42)
			for x in [-10.5, 10.5]:
				game.cover(root, Vector3(x, top / 2, -10.5), Vector3(2, top, 2), Color(palette[1]), true)
				DiverArt.box(root, Vector3(x, 3, -9.4), Vector3(0.6, 3.2, 0.1), DiverArt.GOLD, false, 1)
		"grand": build_grand(root, room)
		_:
			match int(room.layout):
				CLIMB: build_climb(root, room, free_side(index))
				TERRACE: build_terrace(root, room, free_side(index))
				_: furnish(root, int(room.layout))
	# A few low fragments and painted vegetation, kept off the main routes.
	for n in 8 if room.kind != "grand" else 14:
		var p = Vector3(rng.randf_range(-hx + 1.1, hx - 1.1), 0.12, -hz + 1.5 if n % 2 == 0 else hz - 1.5)
		DiverArt.box(root, p, Vector3(rng.randf_range(0.3, 0.8), 0.24, 0.5), Color(palette[1]))
		if game.depth == 2: DiverArt.box(root, p + Vector3.UP * 0.3, Vector3(0.10, 0.6, 0.4), Color("83b897"))

func lamp(root: Node3D, at: Vector3, reach: float, energy: float) -> void:
	var light = OmniLight3D.new()
	root.add_child(light)
	light.position = at
	light.omni_range = reach
	light.light_color = Color(theme.lamp)
	light.light_energy = energy
	DiverArt.cylinder(root, at + Vector3(0, 0.8, 0), 0.20, 0.20, DiverArt.INK)
	DiverArt.orb(root, at + Vector3(0, 0.6, 0), 0.16, DiverArt.GOLD, 0.6)

# One wall of a room, with an opening, posts and a lintel for each door on it.
func build_wall(root: Node3D, room: Dictionary, side: int, door_offsets: Array, details: Dictionary) -> void:
	var length: float = (room.half.x if side % 2 == 0 else room.half.y) * 2 + 0.5
	var top: float = room.height
	door_offsets.sort()
	var spans = []
	var cursor = -length / 2
	for offset in door_offsets:
		spans.append([cursor, offset - DOOR_WIDTH / 2])
		cursor = offset + DOOR_WIDTH / 2
	spans.append([cursor, length / 2])
	# wall_point measures along the wall clockwise, so mirror the south and west sides back.
	var flip = -1.0 if side >= 2 else 1.0
	var widest = 0.0
	var landmark_at = 0.0
	for span in spans:
		var size: float = span[1] - span[0]
		if size < 0.05: continue
		var middle: float = (span[0] + span[1]) / 2
		DiverArt.wall(root, wall_point(room, side, middle * flip, 0, top / 2), wall_size(side, size, top, 0.7), Color(palette[1]), true)
		if size > widest:
			widest = size
			landmark_at = middle * flip
		# Repeated painted ceramic bands give large walls a human-sized rhythm.
		# Batch the little faces rather than adding dozens of nodes per chamber.
		var band_count = maxi(1, ceili(size / 5.5))
		var band_width = size / band_count
		for n in band_count:
			var at = (span[0] + (n + 0.5) * band_width) * flip
			wall_face(details.bands, room, side, at, 0.75, Vector2(band_width, 0.38))
			wall_face(details.bands, room, side, at, top - 0.45, Vector2(band_width, 0.30))
		var panels = mini(4, int(size / 8.0)) if room.kind != "hall" else mini(1, int(size / 4.0))
		for n in panels:
			var at = (middle + (n - (panels - 1) * 0.5) * 7.0) * flip
			wall_face(details.panels, room, side, at, 2.0 if room.kind == "hall" else 2.25, Vector2(1.9, 2.0) if room.kind == "hall" else Vector2(2.3, 2.5))
	if side == int(details.landmark_side) and widest >= 3.8:
		wall_face(details.crests, room, side, landmark_at, 3.7 if room.kind == "hall" else top - 1.55, Vector2(1.4, 1.2) if room.kind == "hall" else Vector2(2.5, 1.9), 0.375)
	for offset in door_offsets:
		for edge in [-1, 1]:
			var at = (offset + edge * 2.9) * flip
			DiverArt.metal(root, wall_point(room, side, at, 0.2, top / 2), Vector3(0.5, top, 0.5), Color(palette[1]))
			DiverArt.box(root, wall_point(room, side, at, 0.2, 2.0), Vector3(0.52, 0.65, 0.52), Color(theme.trim))
		DiverArt.metal(root, wall_point(room, side, offset * flip, 0, (top + 3.7) / 2), wall_size(side, 6.3, top - 3.7, 0.8), Color(palette[1]))
		wall_face(details.crests, room, side, offset * flip, 4.15, Vector2(0.70, 0.70), 0.415)

# A passage junction: forks get a floor ring, dead ends hide salvage.
func build_hall(root: Node3D, room: Dictionary, door_count: int) -> void:
	lamp(root, Vector3(0, room.height - 1.5, 0), 13, 0.8)
	DiverArt.metal(root, Vector3(0, 0.03, 0), Vector3(3.4, 0.04, 3.4), Color(palette[1]))
	if door_count >= 3: DiverArt.ring(root, Vector3(0, 0.07, 0), 1.4, DiverArt.GOLD, 0.10)
	if room.dead_end:
		room.pots = [room.center + Vector3(-2.3, 0, -2.3), room.center + Vector3(2.3, 0, 2.3), room.center + Vector3(-2.3, 0, 2.3)]
		DiverArt.box(root, Vector3(0, 0.035, 0), Vector3(1.2, 0.03, 1.2), DiverArt.TEAL, false, 0.6)

func build_corridor(link: Dictionary) -> void:
	var from: Vector2 = link.from
	var to: Vector2 = link.to
	var middle = (from + to) * 0.5
	var length = from.distance_to(to)
	var along_x = link.dir.x != 0
	var stone = Color(palette[0])
	var root = Node3D.new()
	game.world.add_child(root)
	root.position = Vector3(middle.x, 0, middle.y)
	var floor_mesh = DiverArt.box(root, Vector3(0, -0.35, 0), Vector3(length, 0.7, 6) if along_x else Vector3(6, 0.7, length), stone, true)
	floor_mesh.material_override = DiverArt.painted("ruin_floor", stone, 0.5)
	DiverArt.box(root, Vector3(0, 4.95, 0), Vector3(length, 0.3, 6.2) if along_x else Vector3(6.2, 0.3, length), Color(theme.ceiling), true)
	var panels: Array = []
	var bands: Array = []
	for edge in [-1, 1]:
		DiverArt.wall(root, Vector3(0, 2.4, edge * 3.1) if along_x else Vector3(edge * 3.1, 2.4, 0), Vector3(length, 4.8, 0.4) if along_x else Vector3(0.4, 4.8, length), Color(palette[1]), true)
		var angle = (PI if edge > 0 else 0.0) if along_x else (-PI / 2 if edge > 0 else PI / 2)
		var basis = Basis(Vector3.UP, angle)
		if length >= 3:
			var pos = Vector3(0, 2.3, edge * 2.885) if along_x else Vector3(edge * 2.885, 2.3, 0)
			panels.append(Transform3D(basis * Basis.from_scale(Vector3(1.7, 2.1, 1)), pos))
		var count = maxi(1, ceili(length / 5.5))
		var width = length / count
		for n in count:
			var at = -length / 2 + (n + 0.5) * width
			var pos = Vector3(at, 0.75, edge * 2.885) if along_x else Vector3(edge * 2.885, 0.75, at)
			bands.append(Transform3D(basis * Basis.from_scale(Vector3(width, 0.38, 1)), pos))
	DiverArt.panels(root, panels, DiverArt.painted(str(theme.panel)))
	DiverArt.panels(root, bands, DiverArt.painted("ruin_border", Color(theme.trim)))
	# Painted cross-bands mark the way without competing with attack telegraphs.
	var sills = maxi(1, int(length / 9.0))
	for n in sills:
		var at = (n - (sills - 1) * 0.5) * 9.0
		DiverArt.box(root, Vector3(at, 0.03, 0) if along_x else Vector3(0, 0.03, at), Vector3(0.12, 0.04, 4.8) if along_x else Vector3(4.8, 0.04, 0.12), Color(theme.trim))

# The five cover arrangements, spread out for the larger chambers.
func furnish(root: Node3D, layout: int) -> void:
	var stone = Color(palette[1])
	var metal = Color(theme.fixture)
	var mechanism_faces: Array = []
	match layout:
		0:
			for x in [-9.3, 9.3]:
				for z in [-9.3, 9.3]:
					game.cover(root, Vector3(x, 3.2, z), Vector3(1.8, 6.4, 1.8), stone, true)
					DiverArt.box(root, Vector3(x, 0.25, z), Vector3(2.4, 0.5, 2.4), Color(palette[2]))
					DiverArt.box(root, Vector3(x, 2.6, z), Vector3(1.85, 0.18, 1.85), DiverArt.GOLD, false, 0.15)
		1:
			game.cover(root, Vector3(0, 1.3, 0), Vector3(2.8, 2.6, 2.8), metal)
			fixture_faces(mechanism_faces, Vector3(0, 1.3, 0), Vector3(2.8, 2.6, 2.8))
			DiverArt.cylinder(root, Vector3(0, 2.9, 0), 0.8, 0.45, DiverArt.INK)
			DiverArt.orb(root, Vector3(0, 3.45, 0), 0.48, DiverArt.TEAL, 0.55)
			for x in [-8.25, 8.25]:
				game.cover(root, Vector3(x, 0.8, 1.5), Vector3(2, 1.6, 2), metal)
				DiverArt.ring(root, Vector3(x, 1.61, 1.5), 0.65, DiverArt.GOLD, 0.06)
			for side in [-1, 1]: DiverArt.box(root, Vector3(side * 3.6, 0.04, 0), Vector3(2.6, 0.02, 0.12), DiverArt.TEAL, false, 0.2)
		2:
			for x in [-8.4, 8.4]:
				for z in [-7.5, 0, 7.5]:
					game.cover(root, Vector3(x, 0.95, z), Vector3(1.6, 1.9, 2.4), metal)
					fixture_faces(mechanism_faces, Vector3(x, 0.95, z), Vector3(1.6, 1.9, 2.4))
					for slot in [-0.7, 0, 0.7]:
						DiverArt.box(root, Vector3(x - signf(x) * 0.83, 1.3, z + slot), Vector3(0.04, 0.3, 0.35), DiverArt.GOLD, false, 0.10)
		3:
			for x in [-7.8, 7.8]:
				game.cover(root, Vector3(x, 1.2, 0), Vector3(2.8, 2.4, 2.8), metal)
				fixture_faces(mechanism_faces, Vector3(x, 1.2, 0), Vector3(2.8, 2.4, 2.8))
				DiverArt.cylinder(root, Vector3(x, 2.55, 0), 1.42, 0.25, DiverArt.INK)
				DiverArt.cylinder(root, Vector3(x, 2.70, 0), 1.2, 0.08, Color("88d4b5"), 0.2)
				for z in [-1.3, 1.3]: DiverArt.box(root, Vector3(x, 1.25, z), Vector3(1.6, 0.22, 0.08), DiverArt.TEAL, false, 0.2)
			for z in [-7.8, 7.8]: DiverArt.box(root, Vector3(0, 0.035, z), Vector3(21, 0.03, 0.5), Color("73bca7"), false, 0.15)
		4:
			for side in [-1, 1]:
				game.cover(root, Vector3(side * 5.7, 0.65, side * 6.5), Vector3(2.6, 1.3, 2), metal)
				fixture_faces(mechanism_faces, Vector3(side * 5.7, 0.65, side * 6.5), Vector3(2.6, 1.3, 2))
				game.cover(root, Vector3(side * 10.2, 1.4, -side * 7.5), Vector3(1.6, 2.8, 1.6), stone, true)
				# Overhead conduit, run above the door lintels so it never crosses a doorway.
				var pipe = DiverArt.cylinder(root, Vector3(side * 14.0, 5.0, 0), 0.42, 24, Color("8b9b83"))
				pipe.rotation.x = PI / 2
				for z in [-9.0, 0.0, 9.0]: DiverArt.box(root, Vector3(side * 14.35, 5.0, z), Vector3(0.7, 0.9, 0.3), DiverArt.INK)
			DiverArt.box(root, Vector3(0, 0.045, 0), Vector3(7.5, 0.035, 4.5), Color("6e8077"))
	DiverArt.panels(root, mechanism_faces, DiverArt.room_crest(layout + 1))

# Raised stonework diggers can stand on. Robots path around it unless it is
# `walkable`, in which case they reach the top by its ramps.
func raise_block(root: Node3D, at: Vector3, size: Vector3, tint: Color, walkable: bool = false) -> void:
	var block = DiverArt.box(root, Vector3(at.x, size.y / 2, at.z), size, tint, true)
	block.material_override = DiverArt.painted("ruin_wall" if walkable or size.y > 3 else "ruin_metal", tint, 0.5)
	var cap = DiverArt.box(root, Vector3(at.x, size.y + 0.01, at.z), Vector3(size.x - 0.12, 0.02, size.z - 0.12), Color(palette[0]))
	cap.material_override = DiverArt.painted("ruin_floor", Color(palette[0]), 0.5)
	var area = Rect2(root.position.x + at.x - size.x / 2, root.position.z + at.z - size.z / 2, size.x, size.z)
	game.platforms.append({"rect": area, "y": size.y})
	game.obstacles.append(area)
	if walkable: game.nav_open.append(area.grow(-1.2))

# A solid wedge from `top` (the middle of its high edge) down to the floor.
func ramp(root: Node3D, top: Vector3, run: Vector3, length: float, width: float, tint: Color) -> void:
	var across = run.cross(Vector3.UP) * width * 0.5
	var high_a = top + across
	var high_b = top - across
	var low_a = Vector3(high_a.x, 0, high_a.z) + run * length
	var low_b = Vector3(high_b.x, 0, high_b.z) + run * length
	var base_a = Vector3(high_a.x, 0, high_a.z)
	var base_b = Vector3(high_b.x, 0, high_b.z)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope_normal = (Vector3.UP * length + run * top.y).normalized()
	for v in [high_a, high_b, low_b, high_a, low_b, low_a]: st.set_normal(slope_normal); st.add_vertex(v)
	for v in [high_a, low_a, base_a]: st.set_normal(across.normalized()); st.add_vertex(v)
	for v in [high_b, base_b, low_b]: st.set_normal(-across.normalized()); st.add_vertex(v)
	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat = DiverArt.painted("ruin_floor", tint, 0.5).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	root.add_child(mesh)
	var body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([high_a, high_b, low_a, low_b, base_a, base_b])
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	var origin = Vector2(root.position.x, root.position.z)
	var a = origin + Vector2(base_a.x, base_a.z)
	var b = origin + Vector2(low_b.x, low_b.z)
	game.obstacles.append(Rect2(a.min(b), (a - b).abs()))
	# Robots climb along the middle of the ramp, from just past its foot to the platform.
	var foot = origin + Vector2(top.x, top.z) + Vector2(run.x, run.z) * (length + 1.6)
	var head = origin + Vector2(top.x, top.z) - Vector2(run.x, run.z) * 1.6
	game.nav_open.append(Rect2(foot.min(head), (foot - head).abs()).grow(0.6))

# Jump puzzle: stepping blocks climb to a high ledge holding a free part cache.
func build_climb(root: Node3D, room: Dictionary, side: int) -> void:
	var metal = Color(theme.fixture)
	raise_block(root, wall_point(room, side, 0, 2.3), wall_size(side, 22, 3.2, 3.9), Color(palette[1]))
	for mirror in [-1.0, 1.0]:
		var steps = [[3.5, 11.0, 0.8], [7.7, 11.0, 1.6], [7.7, 6.9, 2.4]]
		for step in steps:
			var at = wall_point(room, side, mirror * step[0], step[1])
			raise_block(root, at, Vector3(2.6, step[2], 2.6), metal)
			DiverArt.box(root, Vector3(at.x, step[2] + 0.03, at.z), Vector3(1.5, 0.03, 1.5), DiverArt.GOLD, false, 0.3)
		game.cover(root, wall_point(room, side, mirror * 8.5, 21, 0.8), wall_size(side, 2.6, 1.6, 2), metal)
	DiverArt.box(root, wall_point(room, side, 0, 4.1, 3.23), wall_size(side, 21, 0.04, 0.14), DiverArt.GOLD, false, 0.4)
	room.bonus_at = room.center + wall_point(room, side, 0, 2.2, 3.2)
	room.pots = [room.center + wall_point(room, side, -8, 2.2, 3.2), room.center + wall_point(room, side, 8, 2.2, 3.2)]
	room.cache_at = room.center + wall_point(room, side, 0, 19)
	room.well_at = room.center + wall_point(room, side, 0, 25)

# Elevation change: a raised terrace along one wall with a ramp at each end.
func build_terrace(root: Node3D, room: Dictionary, side: int) -> void:
	var metal = Color(theme.fixture)
	raise_block(root, wall_point(room, side, 0, 4.2), wall_size(side, 29.2, 1.6, 7.6), Color(palette[1]), true)
	for along in [-9.0, 9.0]:
		ramp(root, wall_point(room, side, along, 8.0, 1.6), INWARD[side], 6.0, 4.0, Color(palette[0]))
		game.cover(root, wall_point(room, side, along * 0.7, 20, 0.8), wall_size(side, 2.6, 1.6, 2), metal)
	DiverArt.wall(root, wall_point(room, side, 0, 7.6, 2.05), wall_size(side, 8, 0.9, 0.5), Color(palette[1]), true)
	DiverArt.box(root, wall_point(room, side, 0, 7.95, 1.63), wall_size(side, 29, 0.04, 0.14), DiverArt.GOLD, false, 0.4)
	room.cache_at = room.center + wall_point(room, side, 0, 3.6, 1.6)
	room.pots = [room.center + wall_point(room, side, -12.5, 2.5, 1.6), room.center + wall_point(room, side, 12.5, 2.5, 1.6)]
	room.well_at = room.center + wall_point(room, side, 0, 24)

# Big room: a two-cell concourse with a colonnade and a raised dais in the middle.
func build_grand(root: Node3D, room: Dictionary) -> void:
	var long_x: bool = room.half.x > room.half.y
	var top: float = room.height
	var metal = Color(theme.fixture)
	var place = func(along: float, across: float, y: float = 0.0) -> Vector3: return Vector3(along, y, across) if long_x else Vector3(across, y, along)
	var sized = func(along: float, height: float, across: float) -> Vector3: return Vector3(along, height, across) if long_x else Vector3(across, height, along)
	for along in [-27.0, -9.0, 9.0, 27.0]:
		for across in [-8.0, 8.0]:
			game.cover(root, place.call(along, across, top / 2), Vector3(1.8, top, 1.8), Color(palette[1]), true)
			DiverArt.box(root, place.call(along, across, 0.3), Vector3(2.5, 0.6, 2.5), Color(palette[2]))
			DiverArt.box(root, place.call(along, across, 3.0), Vector3(1.85, 0.18, 1.85), DiverArt.GOLD, false, 0.15)
	raise_block(root, place.call(0, 0), sized.call(10, 1.2, 8), Color(palette[1]), true)
	for mirror in [-1.0, 1.0]:
		ramp(root, place.call(mirror * 5.0, 0, 1.2), place.call(mirror, 0), 4.5, 4.0, Color(palette[0]))
		game.cover(root, place.call(mirror * 18.0, -mirror * 4.5, 0.8), sized.call(2, 1.6, 2.6), metal)
	room.cache_at = room.center + place.call(0, 0, 1.2)
	room.well_at = room.center + place.call(-18.0, -4.5)
	room.pots = [room.center + place.call(-32.0, -12.0), room.center + place.call(32.0, 12.0), room.center + place.call(-32.0, 12.0), room.center + place.call(32.0, -12.0)]
