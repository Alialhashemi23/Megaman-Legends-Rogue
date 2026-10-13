extends Node3D

const ITEMS = {
	"lens": {"name": "Sunken Lens", "desc": "+16% buster damage per stack.", "color": "ffca68", "unlock": 0},
	"spring": {"name": "Clockwork Spring", "desc": "+14% fire rate per stack.", "color": "7ee8dc", "unlock": 0},
	"heart": {"name": "Ceramic Heart", "desc": "+20 maximum health; restore 20 health.", "color": "f18780", "unlock": 0},
	"boots": {"name": "Gyro Soles", "desc": "+9% movement speed and a shorter dash cooldown.", "color": "a7c8f5", "unlock": 0},
	"shell": {"name": "Fossil Plating", "desc": "Damage reduction scales with each stack.", "color": "b8c7a4", "unlock": 0},
	"moss": {"name": "Copper Moss", "desc": "Every defeated machine restores 1.5 health per stack.", "color": "95d89d", "unlock": 0},
	"ember": {"name": "Ember Engine", "desc": "Buster hits burn enemies for 2 damage per tick per stack.", "color": "f99668", "unlock": 10},
	"coil": {"name": "Storm Coil", "desc": "18% chance per stack to chain lightning to nearby enemies.", "color": "9fb4ff", "unlock": 10},
	"prism": {"name": "Oracle Prism", "desc": "+8% critical chance per stack. Critical hits deal double damage.", "color": "dca4ec", "unlock": 25},
	"echo": {"name": "Echo Circuit", "desc": "12% chance per stack to fire a second bolt at 70% damage.", "color": "8edee8", "unlock": 25},
	"split": {"name": "Forked Antenna", "desc": "Add two side bolts. Stacks increase their damage.", "color": "edd998", "unlock": 50},
	"frost": {"name": "Winter Flywheel", "desc": "Dashing slows nearby machines. Stacks extend the slow.", "color": "b2e4ef", "unlock": 50},
	"clover": {"name": "Salvager's Charm", "desc": "+2.5 percentage points to relic drop chance per stack.", "color": "c1dc8e", "unlock": 50}
}
const WEAPONS = ["PULSE BUSTER", "NEEDLE BUSTER", "SIEGE BUSTER"]
const DEPTH_NAMES = ["THE TIDAL ARCHIVE", "GARDEN OF ENGINES", "HEART OF THE MACHINE"]
const BOSS_NAMES = ["ARCHIVE KEEPER", "VERDANT ENGINE", "CORE WARDEN"]
const ROOM_NAMES = ["PILLAR GALLERY", "RELAY CHAMBER", "SALVAGE ARCHIVE", "COOLANT WORKS", "BROKEN FOUNDRY"]
var mode = "title"
var world: Node3D
var player: DiverPlayer
var hud: Control
var sound: DiverSound
var rng = RandomNumberGenerator.new()
var rooms: Array = []
var enemies: Array = []
var interactables: Array = []
var pickups: Array = []
var particles: Array = []
var floaters: Array = []
var effects: Array = []
var obstacles: Array = []
var navigation = DiverNavigation.new()
var hit_confirm = 0.0
var kill_confirm = 0.0
var camera_effects = true
var depth = 1
var current_room = 0
var exit_room = 0
var scrap = 0
var kills = 0
var run_time = 0.0
var run_seed = 0
var total_damage = 0.0
var guardian_dead = false
var queue_level = false
var hurt_flash = 0.0
var message = ""
var message_detail = ""
var message_time = 0.0
var nearest: Dictionary = {}
var choice_items: Array = []
var choice_kind = ""
var outcome = false
var new_unlocks: Array = []
var selected_weapon = 0
var selected_character = 0
var title_clock = 0.0
var meta = {"kills": 0, "runs": 0, "wins": 0, "deepest": 0, "discovered": {}, "best_time": 0.0}
var screenshot_timer = -1.0
var smoke_test = false
var test_clock = 0.0
var test_stage = 0
var combat_test = false
var movement_test = false
var movement_origin = Vector3.ZERO
var test_enemy: DiverEnemy
const SAVE_PATH = "res://save/archive.json"
var save_path = SAVE_PATH

func _ready() -> void:
	load_meta()
	sound = DiverSound.new()
	add_child(sound)
	setup_environment()
	var canvas = CanvasLayer.new()
	add_child(canvas)
	hud = preload("res://scripts/hud.gd").new()
	hud.game = self
	canvas.add_child(hud)
	build_floor(false)
	position_title_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--smoke-test" in OS.get_cmdline_user_args():
		smoke_test = true
		start_run(49381)
	if "--capture" in OS.get_cmdline_user_args():
		start_run(49381)
		screenshot_timer = 2.0
	if "--capture-title" in OS.get_cmdline_user_args(): screenshot_timer = 2.0
	if "--capture-model" in OS.get_cmdline_user_args():
		mode = "model_preview"
		player.art.root.rotation.y = 0
		player.camera.position = player.position + Vector3(2.4, 1.9, -3.7)
		player.camera.look_at(player.position + Vector3(0, 1.2, 0))
		screenshot_timer = 1.0
	if "--capture-combat" in OS.get_cmdline_user_args(): preview_combat.call_deferred(3)
	if "--capture-bombard" in OS.get_cmdline_user_args(): preview_combat.call_deferred(2)
	if "--capture-rooms" in OS.get_cmdline_user_args(): preview_rooms.call_deferred()
	if "--capture-choice" in OS.get_cmdline_user_args():
		start_run(49381)
		open_relic_choice()
		screenshot_timer = 2.0
	if "--combat-test" in OS.get_cmdline_user_args():
		smoke_test = true
		combat_test = true
		start_run(49381)
		test_enemy = spawn_enemy(Vector3(0, 0, -5), 0, 0)
		player.lock_target = test_enemy
		player.shoot()
	if "--persistence-test" in OS.get_cmdline_user_args():
		validate_persistence.call_deferred()
	if "--movement-test" in OS.get_cmdline_user_args():
		smoke_test = true
		movement_test = true
		start_run(49381)
		movement_origin = player.position
		var key = InputEventKey.new()
		key.physical_keycode = KEY_W
		key.keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key)

func setup_environment() -> void:
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("243d42")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d6d3be")
	e.ambient_light_energy = 0.68
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("384a46")
	e.fog_density = 0.009
	env.environment = e
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_color = Color("ffdfaa")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)

func position_title_camera() -> void:
	title_clock = 0
	player.camera.fov = 45
	player.camera.position = player.position + Vector3(2.8, 2.3, -5.3)
	player.camera.look_at(player.position + Vector3(1.2, 1.10, 0))
	player.art.root.rotation.y = -0.4

func show_title() -> void:
	mode = "title"
	position_title_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) % 1000000
	rng.seed = run_seed
	depth = 1
	scrap = 0
	kills = 0
	run_time = 0
	total_damage = 0
	queue_level = false
	new_unlocks.clear()
	build_floor(false)
	player.weapon = selected_weapon
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	notify("DESCENT 01 / " + DEPTH_NAMES[0], "Search the chambers. Defeat the guardian. Find the lift.")

func build_floor(keep_player: bool) -> void:
	var old_player = player
	if keep_player and is_instance_valid(old_player):
		world.remove_child(old_player)
	if is_instance_valid(world):
		if not keep_player and is_instance_valid(player) and is_instance_valid(player.camera): player.camera.queue_free()
		remove_child(world)
		world.queue_free()
	world = Node3D.new()
	world.name = "Dungeon"
	add_child(world)
	rooms.clear()
	enemies.clear()
	interactables.clear()
	pickups.clear()
	particles.clear()
	floaters.clear()
	effects.clear()
	obstacles.clear()
	hit_confirm = 0
	kill_confirm = 0
	guardian_dead = false
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while cells.size() < 8 + depth:
		var anchor: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var cell: Vector2i = anchor + directions[rng.randi_range(0, 3)]
		if not cells.has(cell): cells.append(cell)
	for i in cells.size():
		var center = Vector3(cells[i].x * 26, 0, cells[i].y * 26)
		rooms.append({"cell": cells[i], "center": center, "visited": i == 0, "cleared": i == 0, "distance": 999, "type": "chamber", "layout": (i + depth - 2) % 5})
	rooms[0].distance = 0
	var queue = [0]
	while not queue.is_empty():
		var idx = queue.pop_front()
		for d in directions:
			var neighbor = cells.find(cells[idx] + d)
			if neighbor >= 0 and rooms[neighbor].distance > rooms[idx].distance + 1:
				rooms[neighbor].distance = rooms[idx].distance + 1
				queue.append(neighbor)
	exit_room = 1
	for i in range(1, rooms.size()):
		if rooms[i].distance >= rooms[exit_room].distance: exit_room = i
	rooms[0].type = "landing"
	rooms[exit_room].type = "guardian"
	for i in rooms.size():
		build_room(i, cells, directions)
	navigation.build(rooms, obstacles)
	if keep_player:
		player = old_player
		world.add_child(player)
		player.lock_target = null
		player.heal(player.max_hp() * 0.25)
	else:
		player = DiverPlayer.new()
		player.game = self
		player.character = selected_character
		world.add_child(player)
	player.position = Vector3(0, 0.12, 3)
	player.velocity = Vector3.ZERO
	player.yaw = 0
	player.pitch = -0.20
	player.update_camera(1)
	current_room = 0
	create_interactable(Vector3(-3, 0, -3), "cache", "PART CACHE", 0, 0)
	create_interactable(rooms[exit_room].center + Vector3(0, 0, -5.8), "lift", "EXTRACTION" if depth == 3 else "DESCENT LIFT", 0, exit_room)
	for i in range(1, rooms.size()):
		if i == exit_room:
			spawn_enemy(rooms[i].center, 3, i)
			for n in depth: spawn_enemy(rooms[i].center + Vector3(-5 + n * 4, 0, -2), 1, i)
		else:
			var count = 2 + depth + rng.randi_range(0, 2)
			for n in count:
				var spawn = rooms[i].center
				for attempt in 64:
					spawn = rooms[i].center + Vector3(rng.randf_range(-6.5, 6.5), 0, rng.randf_range(-6.5, 6.5))
					if navigation.open_at(spawn): break
				spawn_enemy(spawn, rng.randi_range(0, mini(2, depth)), i)
			create_interactable(rooms[i].center + Vector3(4, 0, -3), "cache", "PART CACHE", 10 + depth * 3 + rng.randi_range(0, 5), i)
			if i % 3 == 1: create_interactable(rooms[i].center + Vector3(-4, 0, 3), "spring", "REPAIR WELL", 12 + depth * 2, i)
			for n in 2: create_interactable(rooms[i].center + Vector3(-7 + n * 14, 0, 6), "pot", "SALVAGE VESSEL", 0, i)

func build_room(index: int, cells: Array[Vector2i], directions: Array) -> void:
	var room = rooms[index]
	var root = Node3D.new()
	world.add_child(root)
	root.position = room.center
	var palettes = [["b7c9c4", "ddd7bc", "667d78"], ["a5b6a4", "b8c5ac", "527f78"], ["a4aebb", "b7bfd1", "465f7b"]]
	var palette = palettes[depth - 1]
	var basefloor = DiverArt.box(root, Vector3(0, -0.35, 0), Vector3(20, 0.7, 20), Color(palette[0]), true)
	basefloor.material_override = DiverArt.painted("ruin_floor", Color(palette[0]), 0.5)
	DiverArt.box(root, Vector3(0, 4.95, 0), Vector3(20.4, 0.3, 20.4), Color("687776"), true)
	for beam_pos in [-5, 0, 5]:
		DiverArt.box(root, Vector3(beam_pos, 4.70, 0), Vector3(0.25, 0.20, 20), Color("435d5c"))
		DiverArt.box(root, Vector3(0, 4.70, beam_pos), Vector3(20, 0.20, 0.25), Color("435d5c"))
	for light_pos in [Vector3(-6, 3.2, -5), Vector3(6, 3.2, 5)]:
		var lamp = OmniLight3D.new()
		root.add_child(lamp)
		lamp.position = light_pos
		lamp.omni_range = 14
		lamp.light_color = Color("ffdfa6")
		lamp.light_energy = 0.85
		DiverArt.cylinder(root, light_pos + Vector3(0, 0.8, 0), 0.20, 0.20, DiverArt.INK)
		DiverArt.orb(root, light_pos + Vector3(0, 0.6, 0), 0.16, DiverArt.GOLD, 0.6)
	# Insets and a restrained tile grid give the room an authored archaeological feel.
	for x in range(-8, 10, 2):
		for z in range(-8, 10, 2):
			var col = Color(palette[0]).lightened(rng.randi_range(-1, 3) * 0.015)
			var tile = DiverArt.box(root, Vector3(x - 0.0, 0.005, z), Vector3(1.94, 0.018, 1.94), col)
			tile.material_override = DiverArt.stone_material(col)
	DiverArt.metal(root, Vector3(0, 0.03, 0), Vector3(6, 0.04, 6), Color(palette[1]))
	# Inlaid circuit paths guide the eye toward the exits.
	for sign_dir in [-1, 1]:
		DiverArt.box(root, Vector3(sign_dir * 3.3, 0.025, 0), Vector3(0.09, 0.025, 14), Color("638d83"))
		DiverArt.box(root, Vector3(0, 0.025, sign_dir * 3.3), Vector3(14, 0.025, 0.09), Color("638d83"))
	for d in directions:
		var connected = cells.has(room.cell + d)
		var wallpos = Vector3(d.x * 10, 2.4, d.y * 10)
		var horizontal = d.x == 0
		if connected:
			for sign_dir in [-1, 1]:
				var offset = Vector3(sign_dir * 6.3, 0, 0) if horizontal else Vector3(0, 0, sign_dir * 6.3)
				var size = Vector3(7.4, 4.8, 0.7) if horizontal else Vector3(0.7, 4.8, 7.4)
				DiverArt.wall(root, wallpos + offset, size, Color(palette[1]), true)
			for side in [-1, 1]:
				var p = Vector3(side * 2.9, 2.4, d.y * 9.8) if horizontal else Vector3(d.x * 9.8, 2.4, side * 2.9)
				DiverArt.metal(root, p, Vector3(0.5, 4.8, 0.5), Color(palette[1]))
				DiverArt.box(root, p + Vector3(0, -0.4, 0), Vector3(0.52, 0.65, 0.52), DiverArt.TEAL, false, 0.2)
			DiverArt.metal(root, Vector3(d.x * 10, 4.25, d.y * 10), Vector3(6.3, 1.1, 0.8) if horizontal else Vector3(0.8, 1.1, 6.3), Color(palette[1]))
			# Build each corridor once, but join both rooms without gaps.
			if d.x > 0 or d.y > 0:
				var p = Vector3(d.x * 13, -0.35, d.y * 13)
				var corridor = DiverArt.box(root, p, Vector3(6, 0.7, 6), Color(palette[0]), true)
				corridor.material_override = DiverArt.painted("ruin_floor", Color(palette[0]), 0.5)
				DiverArt.box(root, Vector3(d.x * 13, 4.95, d.y * 13), Vector3(6.2, 0.3, 6.2), Color("687776"), true)
				for side in [-1, 1]:
					var wp = Vector3(13, 2.4, side * 3.1) if not horizontal else Vector3(side * 3.1, 2.4, 13)
					DiverArt.wall(root, wp, Vector3(6, 4.8, 0.4) if not horizontal else Vector3(0.4, 4.8, 6), Color(palette[1]), true)
				DiverArt.box(root, Vector3(d.x * 13, 0.03, d.y * 13), Vector3(4.8, 0.04, 0.12) if horizontal else Vector3(0.12, 0.04, 4.8), DiverArt.TEAL, false, 0.6)
		else:
			DiverArt.wall(root, wallpos, Vector3(20.5, 4.8, 0.7) if horizontal else Vector3(0.7, 4.8, 20.5), Color(palette[1]), true)
			for offset in [-6, 0, 6]:
				var p = Vector3(offset, 1.8, d.y * 9.6) if horizontal else Vector3(d.x * 9.6, 1.8, offset)
				DiverArt.metal(root, p, Vector3(1.5, 1.2, 0.12) if horizontal else Vector3(0.12, 1.2, 1.5), Color(palette[1]))
				DiverArt.box(root, p + Vector3(0, 0.1, 0), Vector3(0.16, 0.8, 0.16), DiverArt.TEAL, false, 1)
	if index != 0 and index != exit_room: furnish_room(root, rooms[index].layout, palette)
	if index == 0:
		DiverArt.cylinder(root, Vector3(0, 0.08, 3), 2, 0.12, DiverArt.INK)
		DiverArt.label(root, Vector3(0, 3.1, -6), "ARCHIVE  /  %02d" % depth, DiverArt.TEAL, 50)
		for x in [-7, 7]:
			DiverArt.cylinder(root, Vector3(x, 1.2, -7), 0.7, 2.4, Color(palette[1]))
			DiverArt.orb(root, Vector3(x, 2.6, -7), 0.32, DiverArt.GOLD, 1)
	if index == exit_room:
		DiverArt.label(root, Vector3(0, 4.1, -6.5), BOSS_NAMES[depth - 1], DiverArt.GOLD, 42)
		for x in [-7, 7]:
			DiverArt.wall(root, Vector3(x, 2.4, -7), Vector3(2, 4.8, 2), Color(palette[1]), true)
			obstacles.append(Rect2(Vector2(root.position.x + x - 1, root.position.z - 8), Vector2(2, 2)))
			DiverArt.box(root, Vector3(x, 3, -5.9), Vector3(0.6, 3.2, 0.1), DiverArt.GOLD, false, 1)
	# A few low fragments and painted vegetation, kept off the main routes.
	for n in 5:
		var p = Vector3(rng.randf_range(-8.9, 8.9), 0.12, -8.5 if n % 2 == 0 else 8.5)
		DiverArt.box(root, p, Vector3(rng.randf_range(0.3, 0.8), 0.24, 0.5), Color(palette[1]))
		if depth == 2:
			DiverArt.box(root, p + Vector3.UP * 0.3, Vector3(0.10, 0.6, 0.4), Color("83b897"))

func cover(root: Node3D, pos: Vector3, size: Vector3, tint: Color, masonry: bool = false) -> void:
	var mesh = DiverArt.wall(root, pos, size, tint, true) if masonry else DiverArt.box(root, pos, size, tint, true)
	if not masonry: mesh.material_override = DiverArt.painted("ruin_metal", tint, 0.5)
	obstacles.append(Rect2(Vector2(root.position.x + pos.x - size.x / 2, root.position.z + pos.z - size.z / 2), Vector2(size.x, size.z)))

func furnish_room(root: Node3D, layout: int, palette: Array) -> void:
	var stone = Color(palette[1])
	var metal = Color("a8c6bd")
	match layout:
		0:
			for x in [-6.2, 6.2]:
				for z in [-6.2, 6.2]:
					cover(root, Vector3(x, 2.4, z), Vector3(1.5, 4.8, 1.5), stone, true)
					DiverArt.box(root, Vector3(x, 0.25, z), Vector3(2, 0.5, 2), Color(palette[2]))
					DiverArt.box(root, Vector3(x, 2.6, z), Vector3(1.55, 0.18, 1.55), DiverArt.GOLD, false, 0.15)
		1:
			cover(root, Vector3(0, 1.3, 0), Vector3(2.8, 2.6, 2.8), metal)
			DiverArt.cylinder(root, Vector3(0, 2.9, 0), 0.8, 0.45, DiverArt.INK)
			DiverArt.orb(root, Vector3(0, 3.45, 0), 0.48, DiverArt.TEAL, 0.55)
			for x in [-5.5, 5.5]:
				cover(root, Vector3(x, 0.8, 1.0), Vector3(2, 1.6, 2), metal)
				DiverArt.ring(root, Vector3(x, 1.61, 1), 0.65, DiverArt.GOLD, 0.06)
			for side in [-1, 1]: DiverArt.box(root, Vector3(side * 2.5, 0.04, 0), Vector3(1.7, 0.02, 0.12), DiverArt.TEAL, false, 0.2)
		2:
			for x in [-5.6, 5.6]:
				for z in [-5, 0, 5]:
					cover(root, Vector3(x, 0.95, z), Vector3(1.6, 1.9, 2.4), metal)
					for slot in [-0.7, 0, 0.7]:
						DiverArt.box(root, Vector3(x - signf(x) * 0.83, 1.3, z + slot), Vector3(0.04, 0.3, 0.35), DiverArt.GOLD, false, 0.10)
		3:
			for x in [-5.2, 5.2]:
				cover(root, Vector3(x, 1.2, 0), Vector3(2.8, 2.4, 2.8), metal)
				DiverArt.cylinder(root, Vector3(x, 2.55, 0), 1.42, 0.25, DiverArt.INK)
				DiverArt.cylinder(root, Vector3(x, 2.70, 0), 1.2, 0.08, Color("88d4b5"), 0.2)
				for z in [-1.3, 1.3]: DiverArt.box(root, Vector3(x, 1.25, z), Vector3(1.6, 0.22, 0.08), DiverArt.TEAL, false, 0.2)
			DiverArt.box(root, Vector3(0, 0.035, -5.2), Vector3(14, 0.03, 0.5), Color("73bca7"), false, 0.15)
			DiverArt.box(root, Vector3(0, 0.035, 5.2), Vector3(14, 0.03, 0.5), Color("73bca7"), false, 0.15)
		4:
			for side in [-1, 1]:
				cover(root, Vector3(side * 3.8, 0.65, side * 4.3), Vector3(2.6, 1.3, 2), metal)
				cover(root, Vector3(side * 6.8, 1.4, -side * 5), Vector3(1.6, 2.8, 1.6), stone, true)
				var pipe = DiverArt.cylinder(root, Vector3(side * 8.5, 1.3, 0), 0.42, 9, Color("8b9b83"))
				pipe.rotation.x = PI / 2
			DiverArt.box(root, Vector3(0, 0.045, 0), Vector3(5, 0.035, 3), Color("6e8077"))

func spawn_enemy(pos: Vector3, kind: int, room_id: int) -> DiverEnemy:
	var e = DiverEnemy.new()
	e.game = self
	e.kind = kind
	e.room_id = room_id
	world.add_child(e)
	e.position = pos + Vector3.UP * 0.1
	enemies.append(e)
	return e

func create_interactable(pos: Vector3, kind: String, title: String, cost: int, room_id: int) -> void:
	var root = Node3D.new()
	world.add_child(root)
	root.position = pos
	var color = DiverArt.GOLD
	match kind:
		"cache":
			DiverArt.box(root, Vector3(0, 0.4, 0), Vector3(1.3, 0.8, 0.95), DiverArt.INK)
			DiverArt.box(root, Vector3(0, 0.85, 0), Vector3(1.4, 0.2, 1.05), color)
			DiverArt.box(root, Vector3(0, 0.45, -0.5), Vector3(0.16, 0.4, 0.08), DiverArt.TEAL, false, 1)
		"spring":
			color = Color("8ee3a0")
			DiverArt.cylinder(root, Vector3(0, 0.25, 0), 0.9, 0.5, DiverArt.STONE)
			DiverArt.cylinder(root, Vector3(0, 0.53, 0), 0.65, 0.06, color, 1)
			DiverArt.orb(root, Vector3(0, 1.3, 0), 0.25, color, 1)
		"lift":
			color = DiverArt.TEAL
			DiverArt.cylinder(root, Vector3(0, 0.05, 0), 1.7, 0.1, DiverArt.INK)
			DiverArt.cylinder(root, Vector3(0, 0.12, 0), 1.4, 0.1, color, 1)
			for x in [-1.6, 1.6]: DiverArt.box(root, Vector3(x, 1.6, 0), Vector3(0.3, 3.2, 0.3), DiverArt.GOLD)
			DiverArt.box(root, Vector3(0, 3.2, 0), Vector3(3.5, 0.3, 0.3), DiverArt.GOLD)
		"pot":
			DiverArt.cylinder(root, Vector3(0, 0.45, 0), 0.40, 0.9, Color("bf9878"))
			DiverArt.cylinder(root, Vector3(0, 0.85, 0), 0.3, 0.18, DiverArt.INK)
	var caption: Label3D
	if kind != "pot":
		caption = DiverArt.label(root, Vector3(0, 2.1 if kind != "lift" else 3.8, 0), title, color, 24)
		caption.visible = false
	interactables.append({"node": root, "kind": kind, "title": title, "cost": cost, "used": false, "room": room_id, "caption": caption})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mode == "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look_mouse(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if mode == "play": mode = "pause"; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				elif mode == "pause": resume_game()
			KEY_E:
				if mode == "play": interact()
			KEY_Q:
				if mode == "play": player.toggle_lock()
			KEY_TAB:
				if mode == "play": mode = "inventory"; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				elif mode == "inventory": resume_game()
			KEY_M:
				sound.muted = not sound.muted
			KEY_1, KEY_2, KEY_3:
				if mode == "choice": choose(event.physical_keycode - KEY_1)
			KEY_ENTER:
				if mode == "title" or mode == "end": start_run()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and mode == "play": player.toggle_lock()

func resume_game() -> void:
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(dt: float) -> void:
	hurt_flash = maxf(0, hurt_flash - dt)
	message_time = maxf(0, message_time - dt)
	if mode == "play":
		hit_confirm = maxf(0, hit_confirm - dt)
		kill_confirm = maxf(0, kill_confirm - dt)
		run_time += dt
		update_world(dt)
		if queue_level:
			queue_level = false
			open_level_choice()
	elif mode == "title":
		title_clock += dt
		player.art.root.rotation.y = -0.4 + sin(title_clock * .45) * .26
		player.visual.preview(dt)
	elif mode == "end": player.visual.preview(dt, true, outcome)
	if screenshot_timer >= 0:
		screenshot_timer -= dt
		if screenshot_timer < 0: capture_image.call_deferred()
	if movement_test: run_movement_test(dt)
	elif combat_test: run_combat_test(dt)
	elif smoke_test: run_smoke(dt)
	hud.queue_redraw()

func update_world(dt: float) -> void:
	nearest = {}
	var best = 3.0
	for i in rooms.size():
		var delta = player.position - rooms[i].center
		if absf(delta.x) < 10 and absf(delta.z) < 10:
			if current_room != i:
				current_room = i
				if not rooms[i].visited:
					rooms[i].visited = true
					notify(BOSS_NAMES[depth - 1] if i == exit_room else ROOM_NAMES[rooms[i].layout], "Guardian signal detected." if i == exit_room else "Chamber %02d · Ancient machines are waking." % (i + 1))
			break
	var room_enemies = 0
	for e in enemies:
		if is_instance_valid(e) and not e.dead and e.room_id == current_room: room_enemies += 1
	if room_enemies == 0 and not rooms[current_room].cleared:
		rooms[current_room].cleared = true
		scrap += 5
		notify("CHAMBER SECURED", "+5 scrap · caches available")
	for obj in interactables:
		var dist = player.position.distance_to(obj.node.position)
		if is_instance_valid(obj.caption): obj.caption.visible = not obj.used and dist < 7.5
		if obj.used: continue
		if dist < best:
			best = dist
			nearest = obj
	for i in range(pickups.size() - 1, -1, -1):
		var p = pickups[i]
		if not is_instance_valid(p.node): pickups.remove_at(i); continue
		p.age += dt
		p.node.rotation.y += dt * 1.7
		var dist = player.position.distance_to(p.node.position)
		if dist < (2.8 if p.kind == "relic" else 5.5):
			p.node.position = p.node.position.move_toward(player.position + Vector3.UP * 0.7, dt * 10)
		else: p.node.position.y = p.base_y + sin(p.age * 3) * 0.10
		if dist < 1.2:
			match p.kind:
				"xp": player.gain_xp(int(p.value))
				"scrap": scrap += int(p.value); sound.play("scrap")
				"health": player.heal(p.value); sound.play("health")
				"relic": player.add_item(p.id)
			p.node.queue_free()
			pickups.remove_at(i)
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p.life -= dt
		if p.life <= 0:
			p.node.queue_free(); particles.remove_at(i)
		else:
			p.node.position += p.velocity * dt
			p.velocity.y -= dt * 10
			p.node.scale *= maxf(0.1, 1.0 - dt * 2)
	for i in range(floaters.size() - 1, -1, -1):
		var f = floaters[i]
		f.life -= dt
		f.node.position.y += dt * 1.1
		f.node.modulate.a = minf(1, f.life * 2)
		if f.life <= 0: f.node.queue_free(); floaters.remove_at(i)
	for i in range(effects.size() - 1, -1, -1):
		var effect = effects[i]
		effect.life -= dt
		if effect.life <= 0:
			effect.node.queue_free()
			effects.remove_at(i)
		else:
			var fraction = effect.life / effect.duration
			effect.node.scale = effect.base_scale * (1.0 + (1.0 - fraction) * effect.grow)
			effect.node.visible = fraction > 0.25 or int(fraction * 20) % 2 == 0

func interact() -> void:
	if nearest.is_empty(): return
	var obj = nearest
	if obj.kind == "lift":
		if not guardian_dead: notify("LIFT SEALED", "Defeat the Archive Keeper to restore power."); return
		if depth >= 3: finish_run(true); return
		depth += 1
		sound.play("door")
		build_floor(true)
		notify("DESCENT %02d / %s" % [depth, DEPTH_NAMES[depth - 1]], "Restored 25% health. The machinery grows stronger.")
		return
	if obj.kind == "cache" and not rooms[obj.room].cleared:
		notify("CACHE SEALED", "Secure this chamber before salvaging its relic."); return
	if scrap < obj.cost: notify("INSUFFICIENT SCRAP", "%d scrap required." % obj.cost); return
	scrap -= obj.cost
	obj.used = true
	match obj.kind:
		"cache":
			obj.node.scale.y = 0.55
			open_relic_choice()
		"spring":
			player.heal(player.max_hp() * 0.45)
			sound.play("loot")
			notify("SYSTEMS RESTORED", "Recovered 45% of maximum health.")
		"pot":
			burst(obj.node.position + Vector3.UP * 0.5, Color("bf9878"), 8)
			drop_pickup(obj.node.position + Vector3.UP * 0.5, "scrap", rng.randi_range(3, 7))
			if rng.randf() < 0.3: drop_pickup(obj.node.position + Vector3.UP, "health", 8)
			obj.node.visible = false
	nearest = {}

func pool() -> Array:
	var result = []
	for id in ITEMS:
		if int(meta.kills) >= ITEMS[id].unlock: result.append(id)
	return result

func open_relic_choice() -> void:
	choice_kind = "relic"
	choice_items.clear()
	var options = pool()
	for n in 3:
		var idx = rng.randi_range(0, options.size() - 1)
		choice_items.append(options[idx])
		options.remove_at(idx)
	mode = "choice"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sound.play("loot")

func open_level_choice() -> void:
	choice_kind = "level"
	choice_items = ["power", "vitality", "haste"]
	mode = "choice"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sound.play("level")

func choose(index: int) -> void:
	if index < 0 or index >= choice_items.size() or mode != "choice": return
	if choice_kind == "relic":
		player.add_item(choice_items[index])
	else:
		match choice_items[index]:
			"power": player.base_damage += 3; notify("BUSTER CALIBRATED", "+3 base damage")
			"vitality": player.base_health += 20; player.heal(35); notify("CORE EXPANDED", "+20 maximum health · restore 35 health")
			"haste": player.fire_multiplier += 0.15; notify("CAPACITOR TUNED", "+15% base fire rate")
	resume_game()

func drop_pickup(pos: Vector3, kind: String, value: float) -> void:
	var root = Node3D.new()
	world.add_child(root)
	root.position = pos
	var color = DiverArt.TEAL if kind == "xp" else DiverArt.GOLD if kind == "scrap" else Color("95d89d")
	DiverArt.orb(root, Vector3.ZERO, 0.14 if kind == "xp" else 0.19, color, 0.7)
	pickups.append({"node": root, "kind": kind, "value": value, "age": 0.0, "base_y": pos.y})

func drop_relic(pos: Vector3) -> void:
	var options = pool()
	var id = options[rng.randi_range(0, options.size() - 1)]
	var root = Node3D.new()
	world.add_child(root)
	root.position = pos
	DiverArt.box(root, Vector3.ZERO, Vector3(0.45, 0.45, 0.45), Color(ITEMS[id].color), false, 1)
	DiverArt.label(root, Vector3(0, 0.8, 0), ITEMS[id].name, Color(ITEMS[id].color), 25)
	pickups.append({"node": root, "kind": "relic", "id": id, "value": 0, "age": 0.0, "base_y": pos.y})

func spawn_bolt(pos: Vector3, dir: Vector3, amount: float, hostile: bool, heavy: bool, _unused: int) -> void:
	var bolt = DiverBolt.new()
	bolt.game = self
	bolt.direction = dir.normalized()
	bolt.amount = amount
	bolt.hostile = hostile
	bolt.heavy = heavy
	world.add_child(bolt)
	bolt.global_position = pos
	bolt.look_at(pos + dir)

func register_effect(node: Node3D, duration: float, grow: float = 0) -> void:
	if effects.size() > 120: node.queue_free(); return
	effects.append({"node": node, "life": duration, "duration": duration, "grow": grow, "base_scale": node.scale})

func muzzle_flash(pos: Vector3, color: Color, radius: float = 0.22) -> void:
	var mesh = DiverArt.orb(world, pos, radius, color, 1)
	register_effect(mesh, 0.06, 0.3)

func impact_ring(pos: Vector3, radius: float, color: Color, duration: float) -> void:
	var ring = DiverArt.ring(world, pos, radius, color, 0.08)
	register_effect(ring, duration, 0.35)

func beam_flash(from: Vector3, to: Vector3, width: float = 0.05, color: Color = Color("ffce87")) -> void:
	var mesh = DiverArt.box(world, (from + to) * 0.5, Vector3(width, 0.06 if width > 0.1 else width, maxf(0.1, from.distance_to(to))), color, false, 0.6)
	mesh.look_at(to)
	register_effect(mesh, 0.16 if width > 0.1 else 0.07)

func burst(pos: Vector3, color: Color, number: int) -> void:
	if particles.size() > 180: return
	for n in number:
		var p = DiverArt.box(world, pos, Vector3.ONE * rng.randf_range(0.05, 0.16), color, false, 0.3)
		particles.append({"node": p, "velocity": Vector3(rng.randf_range(-2, 2), rng.randf_range(1, 3), rng.randf_range(-2, 2)), "life": rng.randf_range(0.2, 0.5)})

func lightning(from: Vector3, to: Vector3) -> void:
	var length = from.distance_to(to)
	var p = DiverArt.box(world, (from + to) * 0.5, Vector3(0.06, 0.06, length), Color("a9bdff"), false, 2)
	p.look_at(to)
	particles.append({"node": p, "velocity": Vector3.ZERO, "life": 0.13})

func float_text(pos: Vector3, text: String, color: Color) -> void:
	if floaters.size() > 35: return
	var l = DiverArt.label(world, pos + Vector3(rng.randf_range(-0.2, 0.2), 0, 0), text, color, 34)
	floaters.append({"node": l, "life": 0.7})

func notify(title: String, detail: String = "") -> void:
	message = title
	message_detail = detail
	message_time = 4.5

func finish_run(won: bool) -> void:
	if mode == "end": return
	outcome = won
	var previous_kills = int(meta.kills)
	meta.kills = previous_kills + kills
	meta.runs = int(meta.runs) + 1
	meta.deepest = maxi(int(meta.deepest), depth)
	if won:
		meta.wins = int(meta.wins) + 1
		if float(meta.best_time) == 0 or run_time < float(meta.best_time): meta.best_time = run_time
	new_unlocks.clear()
	for id in ITEMS:
		if ITEMS[id].unlock > previous_kills and ITEMS[id].unlock <= int(meta.kills): new_unlocks.append(ITEMS[id].name)
	if previous_kills < 10 and int(meta.kills) >= 10: new_unlocks.append("Needle Buster")
	if previous_kills < 50 and int(meta.kills) >= 50: new_unlocks.append("Siege Buster")
	save_meta()
	mode = "end"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sound.play("win" if won else "hurt")

func load_meta() -> void:
	if not FileAccess.file_exists(save_path): return
	var f = FileAccess.open(save_path, FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for key in meta:
			if data.has(key) and typeof(data[key]) == typeof(meta[key]): meta[key] = data[key]
		# JSON numbers decode as floats.
		for key in ["kills", "runs", "wins", "deepest"]:
			if data.get(key) is float or data.get(key) is int: meta[key] = maxi(0, int(data[key]))

func save_meta() -> void:
	if smoke_test: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save"))
	var f = FileAccess.open(save_path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(meta, "\t"))

func time_string() -> String:
	return "%02d:%02d" % [int(run_time) / 60, int(run_time) % 60]

func capture_image() -> void:
	await RenderingServer.frame_post_draw
	var filename = "title" if mode == "title" else "choices" if mode == "choice" else "model" if mode == "model_preview" else "combat" if mode == "combat_preview" else "gameplay"
	get_viewport().get_texture().get_image().save_png("res://build/%s.png" % filename)
	print("CAPTURE_SAVED")
	get_tree().quit()

func preview_combat(tier: int) -> void:
	mode = "combat_preview"
	rng.seed = 49381
	run_seed = 49381
	depth = tier
	build_floor(false)
	current_room = exit_room
	rooms[exit_room].visited = true
	player.position = rooms[exit_room].center + Vector3(0, 0, 4)
	player.pitch = -0.26
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.update_camera(1)
	for enemy in enemies:
		if enemy.kind == 3:
			enemy.active = true
			enemy.rotation.y = PI
			enemy.begin_attack("cross" if tier == 3 else "bombard", 1.1)
	message_time = 0
	screenshot_timer = 1.0

func preview_rooms() -> void:
	mode = "model_preview"
	rng.seed = 49381
	depth = 1
	build_floor(false)
	await get_tree().physics_frame
	for layout in 5:
		for room in rooms:
			if room.type == "chamber" and room.layout == layout:
				player.camera.position = room.center + Vector3(7.9, 3.8, 7.9)
				player.camera.look_at(room.center + Vector3(0, 1.0, 0))
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://screenshots/room-%d.png" % layout)
				break
	print("ROOM_GALLERY_SAVED")
	get_tree().quit()

func run_smoke(dt: float) -> void:
	test_clock += dt
	if test_clock < 0.3: return
	test_clock = 0
	match test_stage:
		0:
			assert(rooms.size() == 9)
			for r in rooms: assert(r.distance < 999)
			assert(exit_room > 0)
			player.add_item("lens")
			player.add_item("lens")
			assert(player.count("lens") == 2)
			assert(is_equal_approx(player.damage(), 15.84))
			nearest = interactables[0]
			interact()
			assert(mode == "choice" and choice_items.size() == 3)
			choose(0)
			assert(mode == "play")
		1:
			var enemy = enemies[0]
			var hp_before = enemy.health
			enemy.take_damage(10)
			assert(enemy.health < hp_before)
			player.invincible = 0
			player.hurt(10)
			assert(player.hp < player.max_hp())
			player.gain_xp(12)
			assert(player.level == 2)
		2:
			assert(mode == "choice")
			choose(1)
			var e = enemies[0]
			e.take_damage(100000, false)
			assert(kills == 1)
			guardian_dead = true
			nearest = interactables[1]
			interact()
			assert(depth == 2 and player.level == 2 and player.count("lens") >= 2)
		3:
			assert(rooms.size() == 10)
			guardian_dead = true
			nearest = interactables[1]
			interact()
			assert(depth == 3)
		4:
			guardian_dead = true
			nearest = interactables[1]
			interact()
			assert(mode == "end" and outcome)
			print("SMOKE_PASS: connected generation, stacking, choices, damage, XP, descent, extraction")
			get_tree().quit()
	test_stage += 1

func run_combat_test(dt: float) -> void:
	test_clock += dt
	if test_stage == 0 and test_clock > 0.8:
		assert(test_enemy.health < test_enemy.max_health, "Buster projectile must collide with a moving enemy")
		player.add_item("ember")
		player.add_item("coil")
		player.add_item("moss")
		player.add_item("split")
		player.add_item("echo")
		player.add_item("prism")
		player.shoot()
		test_stage = 1
	if test_stage == 1 and test_clock > 2.5:
		assert(kills > 0 or test_enemy.health < 15, "Combat should apply sustained damage")
		player.lock_target = null
		player.invincible = 0
		player.hp = 100
		spawn_bolt(player.position + Vector3(0, 1, -2), Vector3.BACK, 10, true, false, 0)
		test_stage = 2
	if test_stage == 2 and test_clock > 3.1:
		assert(player.hp < 100, "Hostile projectile must hit the player capsule")
		print("COMBAT_PASS: moving target projectile collision, relic procs, hostile damage")
		get_tree().quit()

func validate_persistence() -> void:
	save_path = "res://save/validation.json"
	meta.kills = 57
	meta.runs = 4
	meta.wins = 1
	meta.discovered = {"coil": true}
	save_meta()
	meta.kills = 0
	meta.runs = 0
	meta.wins = 0
	meta.discovered = {}
	load_meta()
	assert(meta.kills == 57 and meta.runs == 4 and meta.wins == 1)
	assert(meta.discovered.has("coil"))
	assert(pool().size() == ITEMS.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("PERSISTENCE_PASS: saved stats, discoveries, unlock pool reloaded from disk")
	get_tree().quit()

func run_movement_test(dt: float) -> void:
	test_clock += dt
	if test_clock > 3.7:
		assert(player.position.z < -17, "Player should pass through the doorway into the corridor")
		assert(player.position.y > -0.1, "The connected floors must support the player")
		var key = InputEventKey.new()
		key.physical_keycode = KEY_W
		key.keycode = KEY_W
		key.pressed = false
		Input.parse_input_event(key)
		print("MOVEMENT_PASS: keyboard input, grounded movement, doorway and corridor traversal")
		get_tree().quit()
