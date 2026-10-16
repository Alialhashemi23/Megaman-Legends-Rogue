extends Node3D

const ITEMS = {
	"lens": {"name": "Sunken Lens", "desc": "+16% buster damage per stack.", "color": "ffca68", "unlock": 0},
	"spring": {"name": "Clockwork Spring", "desc": "+14% fire rate per stack.", "color": "7ee8dc", "unlock": 0},
	"heart": {"name": "Ceramic Heart", "desc": "+20 maximum health; restore 20 health.", "color": "f18780", "unlock": 0},
	"boots": {"name": "Gyro Soles", "desc": "+9% movement speed and a shorter dash cooldown.", "color": "a7c8f5", "unlock": 0},
	"shell": {"name": "Fossil Plating", "desc": "Damage reduction scales with each stack.", "color": "b8c7a4", "unlock": 0},
	"moss": {"name": "Copper Moss", "desc": "Every defeated machine restores 1.5 health per stack.", "color": "95d89d", "unlock": 0},
	"ember": {"name": "Ember Engine", "desc": "Buster hits burn enemies for 2 damage per tick per stack.", "color": "f99668", "unlock": 40},
	"coil": {"name": "Storm Coil", "desc": "18% chance per stack to chain lightning to nearby enemies.", "color": "9fb4ff", "unlock": 40},
	"prism": {"name": "Oracle Prism", "desc": "+8% critical chance per stack. Critical hits deal double damage.", "color": "dca4ec", "unlock": 100},
	"echo": {"name": "Echo Circuit", "desc": "12% chance per stack to fire a second bolt at 70% damage.", "color": "8edee8", "unlock": 100},
	"split": {"name": "Forked Antenna", "desc": "Add two side bolts. Stacks increase their damage.", "color": "edd998", "unlock": 220},
	"frost": {"name": "Winter Flywheel", "desc": "Dashing slows nearby machines. Stacks extend the slow.", "color": "b2e4ef", "unlock": 220},
	"clover": {"name": "Salvager's Charm", "desc": "+2.5 percentage points to relic drop chance per stack.", "color": "c1dc8e", "unlock": 220}
}
const WEAPONS = ["PULSE BUSTER", "NEEDLE BUSTER", "SIEGE BUSTER", "SALVAGE BOMBS"]
const DEPTH_NAMES = ["THE TIDAL ARCHIVE", "GARDEN OF ENGINES", "HEART OF THE MACHINE"]
const BOSS_NAMES = ["ARCHIVE KEEPER", "VERDANT ENGINE", "CORE WARDEN"]
const ROOM_NAMES = ["PILLAR GALLERY", "RELAY CHAMBER", "SALVAGE ARCHIVE", "COOLANT WORKS", "BROKEN FOUNDRY", "STEPPED VAULT", "TERRACE HALL", "GRAND CONCOURSE", "PASSAGE"]
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
# Corridors between rooms, raised stonework (for floor heights) and the parts of
# it robots may walk on. See scripts/ruins.gd.
var links: Array = []
var platforms: Array = []
var nav_open: Array = []
var ruins = DiverRuins.new()
var navigation = DiverNavigation.new()
var hit_confirm = 0.0
var kill_confirm = 0.0
var settings: DiverSettings
# Camera shake/recoil zoom lives in the player's settings.
var camera_effects: bool:
	get: return settings.camera_effects if settings else true
	set(value):
		if settings:
			settings.camera_effects = value
			settings.save_settings()
# Solo digs are short, so only online digs keep a checkpoint (for rejoining).
var solo_checkpoints = false
# Trigger and stick edges are polled so holding a trigger can't repeat a toggle.
var pad_held: Dictionary = {}
var nav_repeat = 0.0
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
var selected_weapon: int:
	get: return DiverPlayer.SIGNATURES[selected_character]
var selected_character = 0
var title_clock = 0.0
var meta = DiverProgression.fresh()
var profile_source = "guest"
var guest_meta: Dictionary = {}
var account: DiverAccount
var android_updates: DiverAndroidUpdates
var account_starting = false
var zenny_earned = 0
var run_recorded = false
var screenshot_timer = -1.0
var smoke_test = false
var test_clock = 0.0
var test_stage = 0
var combat_test = false
var movement_test = false
var movement_origin = Vector3.ZERO
var movement_heading = Vector3.FORWARD
var test_enemy: DiverEnemy
const SAVE_PATH = "res://save/archive.json"
const WEB_SAVE_PATH = "user://archive.json"
const OVERLAY_MODES = ["pause", "options", "controls", "inventory", "choice"]
var save_path = SAVE_PATH
# Online co-op state. Remote teammates are DiverPlayer proxies keyed by lobby slot.
var net: DiverNet
var remote_players: Dictionary = {}
var peers: Dictionary = {}
var party_size = 1
var pickup_seq = 0
var choice_queue: Array = []
# Part picks from caches a teammate opened, waiting until this digger is ready:
# {depth, cache, items}. Items are rolled when first opened so backing out
# and reopening can't reroll them. `choice_source` is the open pick's entry.
var pending_choices: Array = []
var choice_source: Dictionary = {}
const MAX_PENDING = 24
# Guardian milestones (polish P6): a major personal upgrade for the rest of the
# dig, offered when the first and second guardians fall. The final guardian
# ends the dig, so it keeps its part reward instead. Offers lean toward the
# parts a digger has fitted (`affinity`), but every milestone works without them.
const MILESTONE_DEPTHS = [1, 2]
const MILESTONES = {
	"arc": {"name": "Arc Conductor", "icon": "coil", "affinity": ["coil", "echo"], "desc": "+25% chance on every hit to chain lightning to nearby machines (stacks with Storm Coil)."},
	"wildfire": {"name": "Wildfire Core", "icon": "ember", "affinity": ["ember", "split"], "desc": "Hits set machines burning, and a burning machine that falls ignites everything within 4 m."},
	"glacier": {"name": "Glacier Drive", "icon": "frost", "affinity": ["frost", "boots"], "desc": "Every dash slows machines within 6 m for 3 s (longer with Winter Flywheels)."},
	"twin": {"name": "Twin Capacitor", "icon": "echo", "affinity": ["echo", "split", "spring"], "desc": "+35% chance for each shot to fire a second bolt at 70% damage (stacks with Echo Circuits)."},
	"fortune": {"name": "Fortune Prism", "icon": "prism", "affinity": ["prism", "clover", "lens"], "desc": "+15% critical chance, and critical hits deal triple damage instead of double."},
	"bulwark": {"name": "Bulwark Frame", "icon": "shell", "affinity": ["shell", "heart"], "desc": "Take 25% less damage while above half Life."},
	"scavenger": {"name": "Scavenger's Instinct", "icon": "moss", "affinity": ["moss", "clover"], "desc": "Each machine you defeat restores 3 Life and is 5 points likelier to drop a part."},
	"salvo": {"name": "Opening Salvo", "icon": "lens", "affinity": ["lens", "prism"], "desc": "+35% damage against machines above 75% health."},
	"second_wind": {"name": "Second Wind", "icon": "heart", "affinity": ["heart", "moss", "shell"], "desc": "Once per descent, a hit that would down you leaves you at 30% Life instead."},
	"kinetic": {"name": "Kinetic Loader", "icon": "spring", "affinity": ["boots", "spring"], "desc": "For 2.5 s after each dash, fire 30% faster."}
}
var net_clock = 0.0
var end_reason = ""
var net_test = ""
# Run persistence: every digger's build by identity, plus local/server checkpoints.
const CHECKPOINT_PATH = "res://save/run_checkpoint.dat"
const WEB_CHECKPOINT_PATH = "user://run_checkpoint.dat"
var checkpoint_path = CHECKPOINT_PATH
var roster: Dictionary = {}
var run_id = ""
var checkpoint_clock = 0.0
var checkpoint_dirty = false
var saved_dig: Dictionary = {}
var pending_restore: Dictionary = {}
var awaiting_checkpoint = 0.0
var malformed_messages = 0
# Co-op communication.
var chat_log: Array = []
var chat_open = false
var pings: Array = []
var spectate_index = 0
var leave_guard = false
var logged_checkpoint = ""

func _ready() -> void:
	# Keep paths a test assigned before adding the game, so checks never touch real saves.
	if save_path == SAVE_PATH: save_path = DiverPaths.pick(SAVE_PATH, WEB_SAVE_PATH)
	if checkpoint_path == CHECKPOINT_PATH: checkpoint_path = DiverPaths.pick(CHECKPOINT_PATH, WEB_CHECKPOINT_PATH)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-path="): checkpoint_path = arg.substr(18)
	load_meta()
	settings = DiverSettings.new()
	add_child(settings)
	sound = DiverSound.new()
	add_child(sound)
	net = DiverNet.new()
	net.game = self
	add_child(net)
	account = DiverAccount.new()
	account.game = self
	account.cache_root = DiverPaths.pick("res://save/accounts", "user://accounts")
	account.message.connect(func(text): notify("ACCOUNT", text))
	add_child(account)
	android_updates = DiverAndroidUpdates.new()
	android_updates.game = self
	add_child(android_updates)
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net-test="): net_test = arg.substr(11)
	if OS.has_feature("web"):
		var query = JavaScriptBridge.eval("new URLSearchParams(location.search).get('nettest') || ''", true)
		if query is String and query != "": net_test = query
	if net_test != "":
		var tester = load("res://tests/net_driver.gd").new() if ResourceLoader.exists("res://tests/net_driver.gd") else null
		if tester:
			tester.game = self
			tester.role = net_test
			add_child(tester)
	else:
		saved_dig = load_checkpoint()
		if not saved_dig.is_empty(): print("ONLINE: saved dig found run=%s online=%s" % [saved_dig.run_id, saved_dig.online])
		if OS.has_feature("web") and DisplayServer.get_name() != "headless": account.refresh()
		elif OS.has_feature("android"): account.restore_session()
		elif net.invited_code() != "":
			# Invite links open straight into the lobby (and rejoin a saved dig there).
			if saved_dig.get("online", false) and str(saved_dig.lobby_code) == net.invited_code(): continue_saved_dig()
			else:
				mode = "online"
				net.join_lobby(net.invited_code(), net.url_param("key"))
	if "--movement-test" in OS.get_cmdline_user_args():
		smoke_test = true
		movement_test = true
		start_run(49381)
		# Head for the landing's first door, whichever wall it is on.
		var door: Vector2i = DiverRuins.DIRECTIONS[ruins.doors_of(0)[0].side]
		movement_heading = Vector3(door.x, 0, door.y)
		player.position = Vector3(0, 0.12, 0)
		player.yaw = atan2(-door.x, -door.y)
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
	if account != null and profile_source == "account": account.refresh()
	chat_open = false
	# Teammates and pings from an online dig don't belong on the title screen.
	for member_slot in remote_players.keys(): remove_remote_player(member_slot)
	for ping in pings:
		if is_instance_valid(ping.node): ping.node.queue_free()
	pings.clear()
	position_title_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_run(seed_value: int = 0, party: int = 1, id: String = "") -> void:
	if account.state == "restoring" or (account.state == "needs_sign_in" and account.identity.is_empty()):
		mode = "account"
		notify("ACCOUNT", "Confirm your saved session online, or choose Play as Guest.")
		return
	if profile_source == "account" and account.server_run == "":
		if account_starting: return
		account_starting = true
		account.begin_run(func():
			start_run(seed_value, party, id)
		)
		return
	account_starting = false
	run_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) % 1000000
	run_id = id if id != "" else new_run_id(run_seed)
	if profile_source == "account": account.attach_world(run_id)
	retire_saved_dig(run_id)
	if not net.active(): roster.clear()
	rng.seed = run_seed
	party_size = clampi(party, 1, DiverNet.MAX_PLAYERS)
	depth = 1
	scrap = 0
	kills = 0
	run_time = 0
	total_damage = 0
	queue_level = false
	choice_queue.clear()
	pending_choices.clear()
	choice_source = {}
	end_reason = ""
	pickup_seq = 0
	new_unlocks.clear()
	run_recorded = false
	zenny_earned = 0
	build_floor(false)
	player.weapon = selected_weapon
	player.hp = player.max_hp()
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") and net.active() else Input.MOUSE_MODE_CAPTURED
	notify("DESCENT 01 / " + DEPTH_NAMES[0], "Search the chambers. Defeat the guardian. Find the lift." if party_size == 1 else "Dig together. Stand beside a downed teammate to revive them.")
	if net.active():
		print("ONLINE: dig started seed=%d party=%d slot=%d rooms=%d exit=%d robots=%d" % [run_seed, party_size, net.slot, rooms.size(), exit_room, enemies.size()])
		send_info()
		net.report_status("run", depth)
	save_checkpoint()

# Every client generates the same floor from the run seed and descent.
func floor_seed(level: int) -> int:
	# Plain integer math keeps native and WebAssembly builds in agreement.
	return (run_seed * 7919 + level * 104729 + 1) & 0x7fffffff

# `arrive` applies the lift's healing; restores rebuild a floor without it.
func build_floor(keep_player: bool, arrive: bool = true) -> void:
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
	platforms.clear()
	nav_open.clear()
	ruins.game = self
	ruins.plan()
	ruins.build()
	navigation.build(rooms, obstacles, links, nav_open)
	if keep_player:
		player = old_player
		world.add_child(player)
		player.lock_target = null
		if not arrive: pass
		elif player.downed: player.revive_now(0.25)
		else: player.heal(player.max_hp() * 0.25)
	else:
		player = DiverPlayer.new()
		player.game = self
		player.character = selected_character
		player.skills = DiverProgression.owned(meta, selected_character)
		player.spec = equipped_spec(selected_character)
		world.add_child(player)
	player.slot = net.slot
	player.player_id = net.player_id if net.active() else ""
	player.display_name = net.player_name
	player.position = Vector3([0.0, 1.6, -1.6, 3.2][clampi(net.slot - 1, 0, 3)], 0.12, 3)
	player.velocity = Vector3.ZERO
	player.yaw = 0
	player.pitch = -0.20
	player.update_camera(1)
	current_room = 0
	create_interactable(Vector3(-4.5, 0, -4.5), "cache", "PART CACHE", 0, 0)
	create_interactable(rooms[exit_room].center + Vector3(0, 0, -9), "lift", "EXTRACTION" if depth == 3 else "DESCENT LIFT", 0, exit_room)
	for i in range(1, rooms.size()):
		var room: Dictionary = rooms[i]
		if i == exit_room:
			spawn_enemy(room.center, 3, i)
			for n in depth: spawn_enemy(room.center + Vector3(-5 + n * 4, 0, -2), 1, i)
		elif room.kind == "hall":
			# Dead-end passages hide a little salvage.
			for at in room.pots: create_interactable(at, "pot", "SALVAGE VESSEL", 0, i)
		else:
			var count = 3 + depth + rng.randi_range(0, 2) + (party_size - 1)
			if room.kind == "grand": count += 2 + depth
			for n in count:
				var spawn: Vector3 = room.center
				for attempt in 64:
					spawn = room.center + Vector3(rng.randf_range(-room.half.x + 4, room.half.x - 4), 0, rng.randf_range(-room.half.y + 4, room.half.y - 4))
					if navigation.open_at(spawn) and floor_height(spawn) == 0: break
				spawn_enemy(spawn, rng.randi_range(0, mini(2, depth)), i)
			create_interactable(room.cache_at, "cache", "PART CACHE", 10 + depth * 3 + rng.randi_range(0, 5), i)
			# The ledge above a jump puzzle holds a free part for whoever makes the climb.
			if room.bonus_at != null: create_interactable(room.bonus_at, "cache", "HIDDEN CACHE", 0, i)
			if i % 3 == 1: create_interactable(room.well_at, "spring", "REPAIR WELL", 12 + depth * 2, i)
			for at in room.pots: create_interactable(at, "pot", "SALVAGE VESSEL", 0, i)
	remote_players.clear()
	if net.active() and mode != "title": spawn_remote_players()
	warm_hit_effects()

# Draw the first hit's flash, sparks and damage number once, too small to see,
# so browsers compile those shaders while the floor loads rather than freezing
# on the first shot that lands.
func warm_hit_effects() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.camera): return
	var warm = Node3D.new()
	player.camera.add_child(warm)
	warm.position = Vector3(0, 0, -3)
	warm.scale = Vector3.ONE * 0.002
	var spark = DiverArt.box(warm, Vector3.ZERO, Vector3.ONE, Color("ffca68"), false, 0.3)
	spark.material_overlay = DiverArt.hit_flash()
	DiverArt.label(warm, Vector3.ZERO, "0123456789!", Color("c3f5ee"), 34)
	get_tree().create_timer(0.5).timeout.connect(warm.queue_free)

func cover(root: Node3D, pos: Vector3, size: Vector3, tint: Color, masonry: bool = false) -> void:
	var mesh = DiverArt.wall(root, pos, size, tint, true) if masonry else DiverArt.box(root, pos, size, tint, true)
	if not masonry: mesh.material_override = DiverArt.painted("ruin_metal", tint, 0.5)
	obstacles.append(Rect2(Vector2(root.position.x + pos.x - size.x / 2, root.position.z + pos.z - size.z / 2), Vector2(size.x, size.z)))

func spawn_enemy(pos: Vector3, kind: int, room_id: int) -> DiverEnemy:
	var e = DiverEnemy.new()
	e.game = self
	e.kind = kind
	e.room_id = room_id
	e.net_id = enemies.size()
	world.add_child(e)
	e.position = pos + Vector3.UP * 0.1
	e.net_pos = e.position
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
	if event is InputEventMouseButton and event.pressed:
		# Browsers only grant pointer lock on a click (e.g. after an online dig starts).
		if mode == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		# Downed diggers watch a teammate; clicking switches who.
		if event.button_index == MOUSE_BUTTON_LEFT and mode == "play" and player.downed: spectate_index += 1
	if event is InputEventJoypadMotion:
		pad_motion(event)
		return
	if not event.is_pressed() or event.is_echo(): return
	for id in ["chat", "ping", "callout_1", "callout_2", "callout_3", "callout_4", "menu", "interact", "lock_on", "parts", "mute", "choice_1", "choice_2", "choice_3", "nav_accept", "jump"]:
		if event.is_action_pressed(id) and game_action(id): get_viewport().set_input_as_handled()

# Gameplay actions from any device. Returns true when the action was used.
func game_action(id: String) -> bool:
	match id:
		"chat":
			if mode == "play" and net.active():
				chat_open = true
				return true
		"nav_accept":
			if mode == "play" and net.active() and not settings.using_pad:
				chat_open = true
				return true
			if mode == "title" or (mode == "end" and not net.active()):
				start_run()
				return true
		"ping":
			if mode == "play": ping_here(); return true
		"callout_1", "callout_2", "callout_3", "callout_4":
			if mode == "play" and net.active():
				say(QUICK_CHAT[int(id.right(1)) - 1], true)
				return true
		"menu":
			if mode == "play":
				mode = "pause"
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				return true
			if mode == "pause":
				resume_game()
				return true
		"interact":
			if mode == "play": interact(); return true
		"lock_on":
			if mode == "play": player.toggle_lock(); return true
		"parts":
			# The same button opens a waiting part pick first, otherwise the parts list.
			if mode == "play":
				if open_pending_choice(): return true
				mode = "inventory"
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				return true
			if mode == "inventory":
				resume_game()
				return true
			if mode == "choice" and can_defer_choice():
				defer_choice()
				return true
		"mute":
			sound.muted = not sound.muted
			return true
		"choice_1", "choice_2", "choice_3":
			if mode == "choice":
				choose(int(id.right(1)) - 1)
				return true
		"jump":
			# A downed digger cycles which teammate they watch.
			if mode == "play" and player.downed:
				spectate_index += 1
				return true
	return false

# Controller sticks and triggers: edge-detect so holds don't repeat toggles.
func pad_motion(event: InputEventJoypadMotion) -> void:
	for a in DiverSettings.ACTIONS:
		var pad: Dictionary = settings.bindings[a.id].pad
		if not pad.has("axis") or a.id == "fire" or int(pad.axis) != event.axis: continue
		var down = event.axis_value * float(pad.get("sign", 1)) > 0.6
		if down and not pad_held.get(a.id, false): game_action(a.id)
		pad_held[a.id] = down
	# The left stick steps through menus.
	if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] and mode != "play":
		var axis_key = "stick%d" % event.axis
		var dir = 0 if absf(event.axis_value) < 0.5 else (1 if event.axis_value > 0 else -1)
		if dir != pad_held.get(axis_key, 0):
			pad_held[axis_key] = dir
			if dir != 0:
				nav_repeat = 0.32
				hud.navigate(dir, event.axis == JOY_AXIS_LEFT_X)

# Holding the stick in a menu keeps scrolling.
func poll_pad(dt: float) -> void:
	if mode == "play": return
	for axis_index in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var dir = pad_held.get("stick%d" % axis_index, 0)
		if dir == 0: continue
		nav_repeat -= dt
		if nav_repeat <= 0:
			nav_repeat = 0.11
			hud.navigate(dir, axis_index == JOY_AXIS_LEFT_X)
		return

func resume_game() -> void:
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not choice_queue.is_empty():
		var next = choice_queue.pop_front()
		if next == "relic": open_relic_choice()
		else: open_level_choice()

# Solo menus pause the dig. Online, the ruins keep moving behind the menus,
# except while reconnecting, when everything waits for the resync.
func world_running() -> bool:
	if net.active() and not net.connected(): return false
	return mode == "play" or (net.active() and mode in OVERLAY_MODES)

func _process(dt: float) -> void:
	hurt_flash = maxf(0, hurt_flash - dt)
	message_time = maxf(0, message_time - dt)
	poll_pad(dt)
	if world_running():
		hit_confirm = maxf(0, hit_confirm - dt)
		kill_confirm = maxf(0, kill_confirm - dt)
		run_time += dt
		update_world(dt)
		if guardian_dead and depth in MILESTONE_DEPTHS and not milestone_owed_or_taken(depth): grant_milestone(depth)
		if net.active(): net_tick(dt)
		if queue_level:
			queue_level = false
			open_level_choice()
	elif mode == "title":
		title_clock += dt
		player.art.root.rotation.y = -0.4 + sin(title_clock * .45) * .26
		player.visual.preview(dt)
	elif mode == "end": player.visual.preview(dt, true, outcome)
	# Keep the dig saved: a few seconds of play at most can be lost to a crash.
	if in_run():
		checkpoint_clock += dt
		if checkpoint_clock > 5.0 or (checkpoint_dirty and checkpoint_clock > 0.5): save_checkpoint()
	if awaiting_checkpoint > 0:
		awaiting_checkpoint -= dt
		if awaiting_checkpoint <= 0: resolve_takeover({})
	if is_instance_valid(world): update_pings(dt)
	guard_page(in_run() or mode == "lobby")
	if screenshot_timer >= 0:
		screenshot_timer -= dt
		if screenshot_timer < 0: capture_image.call_deferred()
	if movement_test: run_movement_test(dt)
	elif combat_test: run_combat_test(dt)
	elif smoke_test and net_test == "": run_smoke(dt)
	hud.queue_redraw()

# Ask before closing or reloading the browser tab mid-dig.
func guard_page(on: bool) -> void:
	if on == leave_guard or not OS.has_feature("web"): return
	leave_guard = on
	JavaScriptBridge.eval("window.onbeforeunload = %s" % ("function (e) { e.preventDefault(); e.returnValue = ''; return ''; }" if on else "null"), true)

func update_world(dt: float) -> void:
	nearest = {}
	var best = 3.0
	var here = room_index_at(player.position)
	if here >= 0 and current_room != here:
		current_room = here
		# The whole party shares the map; the banner is for whoever walks in.
		if not rooms[here].visited:
			rooms[here].visited = true
			net.broadcast([DiverNet.M_VISITED, depth, here])
		if not rooms[here].entered:
			rooms[here].entered = true
			# Passages are quiet; chambers announce themselves.
			if rooms[here].kind != "hall":
				var hint = {5: "Climb the blocks to reach the hidden cache.", 6: "Take the ramps for the high ground.", 7: "A vast hall. Many machines are waking."}.get(int(rooms[here].layout), "Chamber %02d · Ancient machines are waking." % (here + 1))
				notify(BOSS_NAMES[depth - 1] if here == exit_room else ROOM_NAMES[rooms[here].layout], "Guardian signal detected." if here == exit_room else hint)
	# The host decides when any occupied chamber is secured.
	if not net.is_guest():
		for room_index in occupied_rooms():
			if rooms[room_index].cleared: continue
			var room_enemies = 0
			for e in enemies:
				if is_instance_valid(e) and not e.dead and e.room_id == room_index: room_enemies += 1
			if room_enemies == 0:
				rooms[room_index].cleared = true
				scrap += 5
				if room_index == current_room: notify("CHAMBER SECURED", "+5 scrap · caches available")
				net.broadcast([DiverNet.M_CLEARED, depth, room_index])
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
		# Pickups drift toward the closest digger who may take them; the host awards them.
		var collector: DiverPlayer = null
		var dist = 999.0
		for candidate in all_players():
			if candidate.downed or not may_collect(p, candidate): continue
			if net.is_guest() and candidate != player: continue
			var d = candidate.position.distance_to(p.node.position)
			if d < dist:
				dist = d
				collector = candidate
		var reach = 2.8 if p.kind == "relic" else 5.5
		if collector and "magnet" in collector.skills: reach *= DiverProgression.BONUS.magnet
		if collector and dist < reach:
			p.node.position = p.node.position.move_toward(collector.position + Vector3.UP * 0.7, dt * 10)
		else: p.node.position.y = p.base_y + sin(p.age * 3) * 0.10
		if collector and dist < 1.2 and not net.is_guest():
			award_pickup(p, collector)
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
	if net.is_guest():
		net.to_host([DiverNet.M_INTERACT, depth, interactables.find(obj)])
		nearest = {}
		return
	perform_interact(obj, player)

# Runs on the host (or solo) for whoever pressed E.
func perform_interact(obj: Dictionary, who: DiverPlayer) -> void:
	if obj.used: return
	if obj.kind == "lift":
		if not guardian_dead: tell(who, "LIFT SEALED", "Defeat the Archive Keeper to restore power."); return
		var ready = 0
		var standing = 0
		for p in all_players():
			if p.downed: continue
			standing += 1
			if p.position.distance_to(obj.node.position) < 8: ready += 1
		if all_players().size() > 1 and ready < standing: tell(who, "GATHER AT THE LIFT", "%d of %d diggers are aboard. The lift waits for everyone standing." % [ready, standing]); return
		if depth >= 3: end_run_all(true); return
		descend()
		return
	if obj.kind == "cache" and not rooms[obj.room].cleared:
		tell(who, "CACHE SEALED", "Secure this chamber before salvaging its relic."); return
	if scrap < obj.cost: tell(who, "INSUFFICIENT SCRAP", "%d scrap required." % obj.cost); return
	scrap -= obj.cost
	obj.used = true
	use_interactable(obj)
	net.broadcast([DiverNet.M_USED, depth, interactables.find(obj)])
	match obj.kind:
		"cache":
			# Online, every digger gets their own pick from the cache. The opener
			# chooses now; teammates are told and choose when they're ready.
			var cache = interactables.find(obj)
			var opener = net.slot if who == player else who.slot
			net.broadcast([DiverNet.M_CHOICE, depth, cache, opener])
			if who == player: open_relic_choice({"depth": depth, "cache": cache, "items": []})
			else: add_pending_choice(cache)
		"spring":
			net.broadcast([DiverNet.M_RESTORE, 0.45])
			restore_life(0.45)
		"pot":
			drop_pickup(obj.node.position + Vector3.UP * 0.5, "scrap", rng.randi_range(3, 7))
			if rng.randf() < 0.3: drop_pickup(obj.node.position + Vector3.UP, "health", 8)
	nearest = {}

func use_interactable(obj: Dictionary) -> void:
	obj.used = true
	match obj.kind:
		"cache": obj.node.scale.y = 0.55
		"pot":
			burst(obj.node.position + Vector3.UP * 0.5, Color("bf9878"), 8)
			obj.node.visible = false
	if nearest == obj: nearest = {}

func restore_life(fraction: float) -> void:
	player.heal(player.max_hp() * fraction)
	sound.play("loot")
	notify("SYSTEMS RESTORED", "Recovered %d%% of maximum health." % int(fraction * 100))

func descend() -> void:
	depth += 1
	rng.seed = floor_seed(depth)
	net.broadcast([DiverNet.M_FLOOR, depth, party_size])
	enter_floor()

func enter_floor() -> void:
	sound.play("door")
	build_floor(true)
	notify("DESCENT %02d / %s" % [depth, DEPTH_NAMES[depth - 1]], "Restored 25% health. The machinery grows stronger.")
	net.report_status("run", depth)
	build_changed()
	save_checkpoint()

func pool() -> Array:
	var result = []
	for id in ITEMS:
		if item_unlocked(id): result.append(id)
	return result

# True once this digger has taken, deferred or been shown this descent's milestone.
func milestone_owed_or_taken(at_depth: int) -> bool:
	if not is_instance_valid(player) or at_depth in player.milestone_depths: return true
	if mode == "choice" and choice_kind == "milestone" and int(choice_source.get("depth", 0)) == at_depth: return true
	for entry in pending_choices:
		if str(entry.get("kind", "")) == "milestone" and int(entry.depth) == at_depth: return true
	return false

# Three distinct milestones, weighted by fitted parts. Seeded by the dig, the
# descent and the digger, so a rejoin or reload sees the same offer.
func milestone_offer(at_depth: int, who: DiverPlayer) -> Array:
	var picker = RandomNumberGenerator.new()
	picker.seed = hash("%s/%d/%s/%d" % [run_id, at_depth, who.player_id, who.character])
	var options = []
	var weights = []
	for id in MILESTONES:
		if id in who.milestones: continue
		var weight = 1.0
		for part in MILESTONES[id].affinity: weight += 2.0 * who.count(part)
		options.append(id)
		weights.append(weight)
	var result = []
	while result.size() < 3 and not options.is_empty():
		var index = picker.rand_weighted(PackedFloat32Array(weights))
		result.append(options[index])
		options.remove_at(index)
		weights.remove_at(index)
	return result

func grant_milestone(at_depth: int) -> void:
	var entry = {"kind": "milestone", "depth": at_depth, "cache": -1, "items": milestone_offer(at_depth, player)}
	if mode == "play": open_relic_choice(entry)
	else:
		pending_choices.push_front(entry)
		notify("MILESTONE READY", "Press %s to choose your guardian milestone." % settings.prompt("parts"))
	build_changed()

func open_relic_choice(source: Dictionary = {}) -> void:
	if str(source.get("kind", "")) == "milestone" and mode != "choice":
		choice_kind = "milestone"
		choice_source = source
		choice_items = (source.items as Array).duplicate()
		mode = "choice"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		sound.play("level")
		checkpoint_dirty = true
		return
	if mode == "choice":
		if source.is_empty(): choice_queue.append("relic")
		else: pending_choices.push_front(source)
		return
	choice_kind = "relic"
	choice_source = source
	choice_items.clear()
	if (source.get("items", []) as Array).size() == 3:
		choice_items = (source.items as Array).duplicate()
	else:
		var options = pool()
		for n in 3:
			var idx = rng.randi_range(0, options.size() - 1)
			choice_items.append(options[idx])
			options.remove_at(idx)
		if not source.is_empty(): source.items = choice_items.duplicate()
	mode = "choice"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sound.play("loot")
	checkpoint_dirty = true

func open_level_choice() -> void:
	if mode == "choice":
		choice_queue.append("level")
		return
	choice_kind = "level"
	choice_items = ["power", "vitality", "haste"]
	mode = "choice"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	checkpoint_dirty = true
	sound.play("level")

# A teammate opened a cache: this digger's pick waits until they open it.
func add_pending_choice(cache: int) -> void:
	if pending_choices.size() >= MAX_PENDING: return
	pending_choices.append({"depth": depth, "cache": cache, "items": []})
	notify("PART CHOICE WAITING", "A teammate opened a cache. Press %s to pick your part." % settings.prompt("parts"))
	sound.play("loot")
	build_changed()

func open_pending_choice() -> bool:
	if pending_choices.is_empty() or mode != "play": return false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	open_relic_choice(pending_choices.pop_front())
	build_changed()
	return true

# Online the dig keeps going behind menus, so a cache pick can be put back
# for later (the same three parts stay on offer).
func can_defer_choice() -> bool:
	return mode == "choice" and choice_kind in ["relic", "milestone"] and net.active()

func defer_choice() -> void:
	if not can_defer_choice(): return
	var entry = choice_source.duplicate()
	entry.merge({"depth": depth, "cache": -1}, false)
	entry.items = choice_items.duplicate()
	pending_choices.push_front(entry)
	choice_source = {}
	build_changed()
	resume_game()

# Whether this digger still has a pick waiting from a given cache on this floor.
func choice_waiting(cache: int) -> bool:
	if mode == "choice" and int(choice_source.get("depth", 0)) == depth and int(choice_source.get("cache", -1)) == cache: return true
	for entry in pending_choices:
		if str(entry.get("kind", "")) != "milestone" and int(entry.depth) == depth and int(entry.cache) == cache: return true
	return false

# Checkpoint/roster data comes from other machines: keep only well-formed picks.
func clean_pending(value: Variant) -> Array:
	var result = []
	if not value is Array: return result
	for entry in value:
		if result.size() >= MAX_PENDING: break
		if not entry is Dictionary: continue
		var milestone = str(entry.get("kind", "")) == "milestone"
		var catalogue = MILESTONES if milestone else ITEMS
		var items = []
		if entry.get("items") is Array and (entry.items as Array).size() == 3:
			for id in entry.items:
				if id is String and catalogue.has(id) and id not in items: items.append(id)
		if milestone:
			if items.size() == 3: result.append({"kind": "milestone", "depth": clampi(int(entry.get("depth", 1)), 1, 3), "cache": -1, "items": items})
			continue
		result.append({"depth": clampi(int(entry.get("depth", 1)), 1, 3), "cache": int(entry.get("cache", -1)), "items": items if items.size() == 3 else []})
	return result

func choose(index: int) -> void:
	if index < 0 or index >= choice_items.size() or mode != "choice": return
	if choice_kind == "milestone":
		var id: String = choice_items[index]
		var at_depth = int(choice_source.get("depth", depth))
		choice_source = {}
		if id not in player.milestones and at_depth not in player.milestone_depths:
			player.milestones.append(id)
			player.milestone_depths.append(at_depth)
			sound.play("win")
			notify("MILESTONE / " + MILESTONES[id].name.to_upper(), MILESTONES[id].desc)
	elif choice_kind == "relic":
		choice_source = {}
		player.add_item(choice_items[index])
	else:
		match choice_items[index]:
			"power": player.base_damage += 3; notify("BUSTER CALIBRATED", "+3 base damage")
			"vitality": player.base_health += 20; player.heal(35); notify("CORE EXPANDED", "+20 maximum health · restore 35 health")
			"haste": player.fire_multiplier += 0.15; notify("CAPACITOR TUNED", "+15% base fire rate")
	build_changed()
	resume_game()

func drop_pickup(pos: Vector3, kind: String, value: float) -> void:
	if net.is_guest(): return
	pickup_seq += 1
	make_pickup(pickup_seq, pos, kind, value, "", "")
	net.broadcast([DiverNet.M_PICKUP, depth, pickup_seq, pos, kind, value, "", ""])

# `owner` (a digger's id) reserves a part for them (each teammate gets a guardian core).
func drop_relic(pos: Vector3, owner: String = "") -> void:
	if net.is_guest(): return
	var options = pool()
	var id = options[rng.randi_range(0, options.size() - 1)]
	pickup_seq += 1
	make_pickup(pickup_seq, pos, "relic", 0, id, owner)
	net.broadcast([DiverNet.M_PICKUP, depth, pickup_seq, pos, "relic", 0.0, id, owner])

func make_pickup(id: int, pos: Vector3, kind: String, value: float, item_id: String, owner: String) -> void:
	var root = Node3D.new()
	world.add_child(root)
	root.position = pos
	if kind == "relic":
		DiverArt.box(root, Vector3.ZERO, Vector3(0.45, 0.45, 0.45), Color(ITEMS[item_id].color), false, 1)
		var title: String = ITEMS[item_id].name
		if owner != "" and party_size > 1: title = "%s · %s" % [str(roster.get(owner, {}).get("name", "Teammate")) if owner != net.player_id else net.player_name, title]
		DiverArt.label(root, Vector3(0, 0.8, 0), title, Color(ITEMS[item_id].color), 25)
	else:
		var color = DiverArt.TEAL if kind == "xp" else DiverArt.GOLD if kind == "scrap" else Color("95d89d")
		DiverArt.orb(root, Vector3.ZERO, 0.14 if kind == "xp" else 0.19, color, 0.7)
	pickups.append({"node": root, "kind": kind, "id": item_id, "value": value, "age": 0.0, "base_y": pos.y, "net_id": id, "owner": owner})

# Host/solo: hand a collected pickup to the digger who reached it.
func award_pickup(p: Dictionary, who: DiverPlayer) -> void:
	match p.kind:
		"xp":
			player.gain_xp(int(p.value))
			net.broadcast([DiverNet.M_XP, int(p.value)])
		"scrap":
			scrap += int(p.value)
			if who == player: sound.play("scrap")
		"health":
			heal_player(who, p.value)
			if who == player: sound.play("health")
		"relic":
			if who == player: player.add_item(p.id)
			else: net.send(who.slot, [DiverNet.M_ITEM, p.id])
	net.broadcast([DiverNet.M_PICKUP_GONE, depth, p.net_id, who.slot, p.kind])

func spawn_bolt(pos: Vector3, dir: Vector3, amount: float, hostile: bool, heavy: bool, projectile_kind: int = 0, source: Node3D = null, cosmetic: bool = false) -> DiverBolt:
	var bolt = DiverBolt.new()
	bolt.game = self
	bolt.direction = dir if projectile_kind == 1 else dir.normalized()
	bolt.bomb = projectile_kind == 1
	bolt.amount = amount
	bolt.hostile = hostile
	bolt.heavy = heavy
	bolt.source = source
	bolt.cosmetic = cosmetic
	world.add_child(bolt)
	bolt.global_position = pos
	bolt.look_at(pos + dir)
	if source == player and not cosmetic and net.active(): net.broadcast([DiverNet.M_SHOT, depth, pos, dir, heavy, projectile_kind])
	return bolt

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
	if net.is_host(): net.broadcast([DiverNet.M_LIGHTNING, depth, from, to])
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
	if run_recorded: return
	if profile_source == "account":
		if not account.result(run_outcome(won)):
			notify("PROGRESS NOT STORED", "Free device storage, then retry finishing this dig.")
			return
		finish_account_run(won)
		return
	run_recorded = true
	outcome = won
	zenny_earned = DiverProgression.reward(depth, depth - 1 + int(guardian_dead), scrap)
	meta.zenny = int(meta.zenny) + zenny_earned
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
	save_meta()
	mode = "end"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sound.play("win" if won else "hurt")
	choice_queue.clear()
	pending_choices.clear()
	choice_source = {}
	chat_open = false
	clear_checkpoint()
	if net.is_host(): net.report_status("lobby", depth)

func activate_account() -> void:
	if profile_source == "guest": guest_meta = meta.duplicate(true)
	profile_source = "account"
	meta = account.profile.duplicate(true)

func activate_guest() -> void:
	if profile_source == "account" and not guest_meta.is_empty(): meta = guest_meta.duplicate(true)
	profile_source = "guest"
	guest_meta = {}
	net.disconnect_server()

# The account rule: once an account is active, this device's Guest progress has
# either moved into it or been overruled by it, so Guest starts fresh (including
# a saved Guest dig). Account caches and checkpoints are untouched.
func discard_guest_progress() -> void:
	var active = meta
	var source = profile_source
	meta = DiverProgression.fresh()
	profile_source = "guest"
	save_meta()
	guest_meta = meta
	meta = active
	profile_source = source
	var cp = load_checkpoint()
	if cp.is_empty() or str(cp.get("account_id", "")) != "": return
	saved_dig = {}
	for path in [checkpoint_path, checkpoint_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func record_discovery(id: String) -> void:
	if profile_source == "account": account.discover(id)
	else:
		meta.discovered[id] = true
		save_meta()

func run_outcome(won: bool, abandoned: bool = false) -> Dictionary:
	return {"won": won, "depth": depth, "guardians": depth - 1 + int(guardian_dead), "scrap": scrap, "kills": kills, "run_time": run_time, "character": selected_character, "abandoned": abandoned}

func finish_account_run(won: bool) -> void:
	run_recorded = true
	outcome = won
	zenny_earned = DiverProgression.reward(depth, depth - 1 + int(guardian_dead), scrap)
	mode = "end"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sound.play("win" if won else "hurt")
	choice_queue.clear()
	pending_choices.clear()
	choice_source = {}
	chat_open = false
	clear_checkpoint()
	if net.is_host(): net.report_status("lobby", depth)

func load_meta() -> void:
	if FileAccess.file_exists(save_path):
		var f = FileAccess.open(save_path, FileAccess.READ)
		if f != null:
			var validated = DiverProgression.validate(JSON.parse_string(f.get_as_text()))
			if not validated.is_empty(): meta = validated
	# A synchronous browser mirror covers refreshes during an IndexedDB commit.
	if OS.has_feature("web"):
		var code = JavaScriptBridge.eval("(() => { try { return localStorage.getItem('relicDiverProgressV2') || ''; } catch(e) { return ''; } })()", true)
		if code is String and code != "":
			var recovery = DiverProgression.decode(code)
			if not recovery.is_empty() and int(recovery.revision) >= int(meta.revision): meta = recovery

func save_meta() -> bool:
	if profile_source == "account": return false
	if smoke_test: return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	var f = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if f == null: return false
	var previous_revision = int(meta.revision)
	meta.revision = mini(100000000, previous_revision + 1)
	f.store_string(JSON.stringify(meta, "\t"))
	f.flush()
	var error = f.get_error()
	f.close()
	if error != OK:
		meta.revision = previous_revision
		return false
	var renamed = DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) == OK
	# FileAccess closed the temporary path; also sync the subsequent rename on web.
	if renamed and OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('relicDiverProgressV2', %s); } catch(e) {}" % JSON.stringify(DiverProgression.encode(meta)), true)
		JavaScriptBridge.force_fs_sync()
	if not renamed: meta.revision = previous_revision
	return renamed

func item_unlocked(id: String) -> bool:
	return int(meta.kills) >= ITEMS[id].unlock or id in meta.legacy_unlocks or ("salvage" in DiverProgression.owned(meta, selected_character) and id == DiverProgression.RESEARCH[selected_character])

func buy_skill(character: int, id: String) -> bool:
	if in_run() or not DiverProgression.can_buy(meta, character, id): return false
	if profile_source == "account": return account.purchase(character, id)
	var before = meta.duplicate(true)
	var skills = DiverProgression.owned(meta, character)
	skills.append(id)
	meta.trees[str(character)] = skills
	meta.zenny -= DiverProgression.node(id).cost
	if not save_meta():
		meta = before
		return false
	return true

func import_progress(data: Dictionary) -> bool:
	if in_run() or net.active() or not saved_dig.is_empty(): return false
	if profile_source == "account":
		if account.empty_account(): account.preview_migration(data)
		return false
	var validated = DiverProgression.validate(data)
	if validated.is_empty(): return false
	var before = meta
	meta = validated
	if not save_meta():
		meta = before
		return false
	return true

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
	# The deepest floor has enough chambers to show every arrangement.
	depth = 3
	build_floor(false)
	await get_tree().physics_frame
	for layout in 9:
		for room in rooms:
			if room.kind in ["chamber", "grand", "hall"] and room.layout == layout:
				player.camera.fov = 80
				player.camera.position = room.center + Vector3(room.half.x - 1.5, room.height - 1.2, room.half.y - 1.5)
				player.camera.look_at(room.center + Vector3(0, 0.5, 0))
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://screenshots/room-%d.png" % layout)
				break
	print("ROOM_GALLERY_SAVED")
	get_tree().quit()

# Rooms that aren't passages: the landing, chambers, the big hall and the guardian.
func chamber_count() -> int:
	var count = 0
	for room in rooms:
		if room.kind != "hall": count += 1
	return count

func run_smoke(dt: float) -> void:
	test_clock += dt
	if test_clock < 0.3: return
	test_clock = 0
	match test_stage:
		0:
			assert(chamber_count() == 8)
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
			assert(chamber_count() == 9)
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
		assert(kills > 0 or test_enemy.health < test_enemy.max_health * 0.45, "Combat should apply sustained damage")
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
	meta.kills = 257
	meta.runs = 4
	meta.wins = 1
	meta.discovered = {"coil": true}
	save_meta()
	meta.kills = 0
	meta.runs = 0
	meta.wins = 0
	meta.discovered = {}
	load_meta()
	assert(meta.kills == 257 and meta.runs == 4 and meta.wins == 1)
	assert(meta.discovered.has("coil"))
	assert(pool().size() == ITEMS.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("PERSISTENCE_PASS: saved stats, discoveries, unlock pool reloaded from disk")
	get_tree().quit()

func run_movement_test(dt: float) -> void:
	test_clock += dt
	if test_clock > 3.7:
		assert((player.position - movement_origin).dot(movement_heading) > 17, "Player should pass through the doorway into the corridor")
		assert(player.position.y > -0.1, "The connected floors must support the player")
		var key = InputEventKey.new()
		key.physical_keycode = KEY_W
		key.keycode = KEY_W
		key.pressed = false
		Input.parse_input_event(key)
		print("MOVEMENT_PASS: keyboard input, grounded movement, doorway and corridor traversal")
		get_tree().quit()

# ---------------------------------------------------------------------------
# Online co-op. The lobby host owns robots, pickups, scrap and doors; every
# digger owns their own movement, Life and fitted parts. Damage to a digger is
# decided on that digger's machine, damage to robots by the shooter.
#
# Runs are built to survive mishaps: hosting moves to another digger if the
# host leaves, dropped connections reconnect and resync, every digger's build
# is mirrored by identity (refresh = same build back), and each machine keeps
# a local checkpoint while the host also stores one on the server.

const QUICK_CHAT = ["Help!", "Over here!", "Nice!", "Wait up!"]
const CHECKPOINT_VERSION = 3

func all_players() -> Array:
	var result = [player] if is_instance_valid(player) else []
	for proxy in remote_players.values():
		if is_instance_valid(proxy): result.append(proxy)
	return result

func room_index_at(pos: Vector3) -> int:
	for i in rooms.size():
		var delta = pos - rooms[i].center
		if absf(delta.x) < rooms[i].half.x and absf(delta.z) < rooms[i].half.y: return i
	return -1

# Height of the raised stonework under a point (0 on the open floor and ramps).
func floor_height(pos: Vector3) -> float:
	var height = 0.0
	for platform in platforms:
		if platform.rect.has_point(Vector2(pos.x, pos.z)): height = maxf(height, platform.y)
	return height

func occupied_rooms() -> Array:
	var result = []
	for p in all_players():
		var index = current_room if p == player else room_index_at(p.position)
		if index >= 0 and not result.has(index): result.append(index)
	return result

func room_has_player(room_id: int, from: Vector3) -> bool:
	for p in all_players():
		var index = current_room if p == player else room_index_at(p.position)
		if index == room_id and p.global_position.distance_to(from) < 40: return true
	return false

# Robots chase the closest standing digger who isn't busy choosing a part.
func target_for(enemy: Node3D) -> DiverPlayer:
	var best: DiverPlayer = null
	var best_distance = INF
	for p in all_players():
		if p.downed: continue
		var d = p.global_position.distance_to(enemy.global_position)
		if p.net_flags & DiverPlayer.FLAG_CHOOSING or (p == player and mode == "choice"): d += 30
		if d < best_distance:
			best_distance = d
			best = p
	return best

# A reserved part can be taken by its owner, or by anyone while the owner is away.
func may_collect(p: Dictionary, who: DiverPlayer) -> bool:
	if p.owner == "" or who.player_id == p.owner: return true
	for other in all_players():
		if other.player_id == p.owner: return false
	return true

func tell(who: DiverPlayer, title: String, detail: String) -> void:
	if who == player: notify(title, detail)
	else: net.send(who.slot, [DiverNet.M_NOTIFY, title, detail])

func announce(title: String, detail: String) -> void:
	notify(title, detail)
	net.broadcast([DiverNet.M_NOTIFY, title, detail])

func heal_player(who: DiverPlayer, amount: float) -> void:
	if amount <= 0 or not is_instance_valid(who): return
	if who == player: player.heal(amount)
	else: net.send(who.slot, [DiverNet.M_HEAL, amount])

func frost_burst(pos: Vector3, amount: float, radius: float = 6.0) -> void:
	if net.is_guest():
		net.to_host([DiverNet.M_FROST, depth, pos, amount, radius])
		return
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_to(pos) < radius:
			enemy.slow = amount

# Guests report their hits to the host, who applies damage and part effects.
func damage_enemy(enemy: DiverEnemy, amount: float, source: Node3D, effects: bool = true) -> void:
	if not net.is_guest():
		enemy.take_damage(amount, effects, source)
		return
	if source != player: return
	net.to_host([DiverNet.M_HIT, depth, enemy.net_id, amount])
	hit_confirm = 0.14
	enemy.flash = 0.1
	enemy.my_last_hit = Time.get_ticks_msec()
	sound.play("hit", 1.0, enemy.global_position)

func local_player_down() -> void:
	if all_players().size() <= 1 and not net.active():
		finish_run(false)
		return
	player.downed = true
	player.revive = 0
	player.lock_target = null
	player.visual.current_clip = ""
	notify("YOU'RE DOWN!", "Hang on. A teammate can revive you by standing close. Click to watch a teammate.")
	send_state()
	build_changed()

# --- builds and world snapshots --------------------------------------------

# Everything needed to hand a digger back their exact build.
func clean_milestones(value: Variant) -> Array:
	var result = []
	if value is Array:
		for id in value:
			if id is String and MILESTONES.has(id) and id not in result and result.size() < MILESTONE_DEPTHS.size(): result.append(id)
	return result

func clean_spec(value: Variant, skills: Array) -> String:
	return value if value is String and value in DiverProgression.SPEC_NODES and value in skills else ""

# This device's equipped specialization for a digger, if still owned.
func equipped_spec(character: int) -> String:
	return DiverProgression.usable_spec(meta, character, str(settings.specs.get(str(character), "")))

# Free to change between digs; a dig keeps the one it started with.
func equip_spec(character: int, id: String) -> bool:
	if in_run() or (id != "" and DiverProgression.usable_spec(meta, character, id) == ""): return false
	if id == "": settings.specs.erase(str(character))
	else: settings.specs[str(character)] = id
	if not smoke_test: settings.save_settings()
	send_info()
	return true

func clean_skills(value: Variant) -> Array:
	var result = []
	if value is Array:
		for id in value:
			if id is String and not DiverProgression.node(id).is_empty() and id not in result: result.append(id)
	return result

func build_state() -> Dictionary:
	var p = player
	var queue = choice_queue.duplicate()
	if queue_level: queue.append("level")
	return {"id": net.player_id, "name": net.player_name, "character": p.character, "weapon": p.weapon, "skills": p.skills.duplicate(), "spec": p.spec, "milestones": p.milestones.duplicate(), "milestone_depths": p.milestone_depths.duplicate(), "second_wind_depth": p.second_wind_depth, "shot_count": p.shot_count, "repair_cooldown": p.repair_cooldown, "items": p.items.duplicate(), "level": p.level, "xp": p.xp, "xp_required": p.xp_required, "base_health": p.base_health, "base_damage": p.base_damage, "fire_multiplier": p.fire_multiplier, "hp": p.hp, "downed": p.downed, "choice": {"kind": choice_kind, "items": choice_items.duplicate(), "depth": int(choice_source.get("depth", depth)), "cache": int(choice_source.get("cache", -1)), "sourced": not choice_source.is_empty()} if mode == "choice" else {}, "queue": queue, "pending": pending_choices.duplicate(true)}

func apply_build(b: Dictionary) -> void:
	var p = player
	if int(b.get("character", p.character)) != p.character: p.set_character(int(b.character))
	selected_character = p.character
	p.weapon = DiverPlayer.SIGNATURES[p.character]
	p.skills = clean_skills(b.get("skills", []))
	p.spec = clean_spec(b.get("spec", ""), p.skills)
	p.milestones = clean_milestones(b.get("milestones", []))
	p.milestone_depths = []
	if b.get("milestone_depths") is Array:
		for d in b.milestone_depths:
			if (d is int or d is float) and int(d) in MILESTONE_DEPTHS and int(d) not in p.milestone_depths: p.milestone_depths.append(int(d))
	p.second_wind_depth = int(b.get("second_wind_depth", 0))
	p.shot_count = maxi(0, int(b.get("shot_count", 0)))
	p.repair_cooldown = clampf(float(b.get("repair_cooldown", 0)), 0, DiverProgression.BONUS.repair_delay)
	p.items = (b.get("items", {}) as Dictionary).duplicate() if b.get("items") is Dictionary else {}
	p.level = int(b.get("level", 1))
	p.xp = int(b.get("xp", 0))
	p.xp_required = int(b.get("xp_required", 12))
	p.base_health = float(b.get("base_health", 100.0))
	p.base_damage = float(b.get("base_damage", 12.0))
	p.fire_multiplier = float(b.get("fire_multiplier", 1.0))
	p.hp = clampf(float(b.get("hp", p.max_hp())), 0, p.max_hp())
	p.downed = bool(b.get("downed", false)) or p.hp <= 0
	if p.downed: p.hp = 0
	p.visual.current_clip = ""
	choice_queue = (b.get("queue", []) as Array).duplicate() if b.get("queue") is Array else []
	pending_choices = clean_pending(b.get("pending", []))
	choice_source = {}
	var choice = b.get("choice", {})
	if choice is Dictionary and choice.get("items") is Array and (choice.items as Array).size() == 3:
		choice_kind = str(choice.kind)
		choice_items = (choice.items as Array).duplicate()
		if choice_kind == "relic" and bool(choice.get("sourced", false)):
			choice_source = {"depth": clampi(int(choice.get("depth", depth)), 1, 3), "cache": int(choice.get("cache", -1)), "items": choice_items.duplicate()}
		if choice_kind == "milestone":
			var offer = clean_pending([{"kind": "milestone", "depth": choice.get("depth", depth), "items": choice_items}])
			if offer.is_empty():
				choice_kind = "level"
				choice_items = ["power", "vitality", "haste"]
			else: choice_source = offer[0]
		mode = "choice"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not choice_queue.is_empty():
		resume_game()

func world_state() -> Dictionary:
	var alive = PackedFloat32Array()
	for e in enemies:
		if is_instance_valid(e) and not e.dead: alive.append_array([e.net_id, e.health, e.global_position.x, e.global_position.y, e.global_position.z, 1.0 if e.active else 0.0])
	var used = PackedInt32Array()
	for i in interactables.size():
		if interactables[i].used: used.append(i)
	var cleared = PackedInt32Array()
	var visited = PackedInt32Array()
	for i in rooms.size():
		if rooms[i].cleared: cleared.append(i)
		if rooms[i].visited: visited.append(i)
	var items = []
	for p in pickups:
		if is_instance_valid(p.node): items.append([p.net_id, p.node.position, p.kind, float(p.value), p.id, p.owner])
	return {"run_id": run_id, "seed": run_seed, "depth": depth, "party": party_size, "floor_seed": run_seed if depth == 1 else floor_seed(depth), "scrap": scrap, "kills": kills, "run_time": run_time, "total_damage": total_damage, "guardian_dead": guardian_dead, "alive": alive, "used": used, "cleared": cleared, "visited": visited, "pickups": items, "pickup_seq": pickup_seq}

# Rebuild the floor from its seed, then apply everything that has happened on it.
func apply_world_state(w: Dictionary, keep_player: bool) -> void:
	if run_id != str(w.get("run_id", "")): run_recorded = false
	run_id = str(w.get("run_id", ""))
	run_seed = int(w.get("seed", 1))
	party_size = clampi(int(w.get("party", 1)), 1, DiverNet.MAX_PLAYERS)
	depth = clampi(int(w.get("depth", 1)), 1, 3)
	queue_level = false
	new_unlocks.clear()
	end_reason = ""
	if not keep_player:
		choice_queue.clear()
		pending_choices.clear()
		choice_source = {}
	rng.seed = int(w.get("floor_seed", run_seed))
	build_floor(keep_player and is_instance_valid(player), false)
	scrap = int(w.get("scrap", 0))
	kills = int(w.get("kills", 0))
	run_time = float(w.get("run_time", 0.0))
	total_damage = float(w.get("total_damage", 0.0))
	guardian_dead = bool(w.get("guardian_dead", false))
	var alive: PackedFloat32Array = w.get("alive", PackedFloat32Array()) if w.get("alive") is PackedFloat32Array else PackedFloat32Array()
	var living = {}
	for i in range(0, alive.size() - 5, 6):
		var id = int(alive[i])
		if id < 0 or id >= enemies.size() or not is_instance_valid(enemies[id]): continue
		living[id] = true
		var e: DiverEnemy = enemies[id]
		e.health = clampf(alive[i + 1], 1, e.max_health)
		if alive[i + 5] > 0.5:
			e.active = true
			e.global_position = Vector3(alive[i + 2], alive[i + 3], alive[i + 4])
			e.net_pos = e.global_position
	for id in enemies.size():
		if not living.has(id) and is_instance_valid(enemies[id]):
			enemies[id].dead = true
			enemies[id].queue_free()
	for index in w.get("used", []):
		if index >= 0 and index < interactables.size(): use_interactable(interactables[index])
	for index in w.get("cleared", []):
		if index >= 0 and index < rooms.size(): rooms[index].cleared = true
	for index in w.get("visited", []):
		if index >= 0 and index < rooms.size(): rooms[index].visited = true
	for item in w.get("pickups", []):
		if item is Array and item.size() >= 6 and item[1] is Vector3 and (item[2] != "relic" or ITEMS.has(str(item[4]))):
			make_pickup(int(item[0]), item[1], str(item[2]), float(item[3]), str(item[4]), str(item[5]))
	pickup_seq = int(w.get("pickup_seq", 0))
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else Input.MOUSE_MODE_CAPTURED

# --- checkpoints ---------------------------------------------------------------

func checkpoint_data() -> Dictionary:
	if net.active(): roster[net.player_id] = build_state()
	return {"v": CHECKPOINT_VERSION, "account_id": str(account.identity.get("id", "")) if profile_source == "account" else "", "account_run": account.server_run if profile_source == "account" else "", "online": net.active(), "lobby_code": net.lobby_code, "lobby_name": str(net.lobby.get("name", "")), "public": bool(net.lobby.get("isPublic", true)), "password": net.lobby_password, "run_id": run_id, "saved": Time.get_unix_time_from_system(), "world": world_state(), "build": build_state(), "roster": roster.duplicate(true), "selected": [selected_character, selected_weapon]}

func persisting() -> bool:
	return (not smoke_test or net_test != "") and (net.active() or solo_checkpoints)

func save_checkpoint() -> void:
	checkpoint_clock = 0.0
	checkpoint_dirty = false
	if not in_run() or not persisting() or net.reconnecting(): return
	var data = checkpoint_data()
	# Write beside the old file first, so a crash mid-write never loses the dig.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(checkpoint_path.get_base_dir()))
	var temp = checkpoint_path + ".tmp"
	var f = FileAccess.open(temp, FileAccess.WRITE)
	if f == null: return
	f.store_var(data)
	f.close()
	if FileAccess.file_exists(checkpoint_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(checkpoint_path))
	var moved = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(checkpoint_path))
	if logged_checkpoint != run_id:
		logged_checkpoint = run_id
		print("ONLINE: checkpoint saved run=%s (%s)" % [run_id, error_string(moved)])
	if net.is_host(): net.store_checkpoint(var_to_bytes(data))

func load_checkpoint() -> Dictionary:
	for path in [checkpoint_path, checkpoint_path + ".tmp"]:
		if not FileAccess.file_exists(path): continue
		var f = FileAccess.open(path, FileAccess.READ)
		if f == null: continue
		var data = f.get_var()
		if valid_checkpoint(data): return data
	return {}

func valid_checkpoint(data) -> bool:
	return data is Dictionary and int(data.get("v", 0)) == CHECKPOINT_VERSION and data.get("world") is Dictionary and data.get("build") is Dictionary and str(data.get("run_id", "")) != ""

func clear_checkpoint() -> void:
	saved_dig = {}
	if not persisting(): return
	for path in [checkpoint_path, checkpoint_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# Mark the build as changed: teammates hear about it and the checkpoint is refreshed soon.
func build_changed() -> void:
	checkpoint_dirty = true
	send_info()

# An abandoned saved dig still counts its machines toward unlocks.
func retire_saved_dig(new_run_id: String) -> void:
	var cp = load_checkpoint()
	if cp.is_empty() or str(cp.run_id) == new_run_id: return
	var owner_id = str(cp.get("account_id", ""))
	if owner_id != "":
		if profile_source != "account" or owner_id != str(account.identity.id): return
		var w: Dictionary = cp.world
		if not account.enqueue("/api/v1/run-results", {"run_id": str(cp.get("account_run", "")), "outcome": {"won": false, "depth": int(w.get("depth", 1)), "guardians": int(w.get("depth", 1)) - 1 + int(w.get("guardian_dead", false)), "scrap": int(w.get("scrap", 0)), "kills": int(w.get("kills", 0)), "run_time": float(w.get("run_time", 0)), "character": int(cp.build.get("character", 0)), "abandoned": true}}): return
		clear_checkpoint()
		return
	if profile_source == "account":
		var cloud = meta
		meta = guest_meta
		profile_source = "guest"
		meta.kills += int(cp.world.get("kills", 0))
		meta.runs += 1
		meta.deepest = maxi(int(meta.deepest), int(cp.world.get("depth", 1)))
		save_meta()
		guest_meta = meta
		meta = cloud
		profile_source = "account"
		clear_checkpoint()
		return
	meta.kills = int(meta.kills) + int(cp.world.get("kills", 0))
	meta.runs = int(meta.runs) + 1
	meta.deepest = maxi(int(meta.deepest), int(cp.world.get("depth", 1)))
	save_meta()
	clear_checkpoint()

# Restore a whole dig: the floor, then this digger's build and everyone else's.
func restore_checkpoint(cp: Dictionary) -> void:
	if profile_source == "account" and account.server_run == "" and not account.resume_world(str(cp.run_id)):
		account.begin_run(func(): restore_checkpoint(cp))
		return
	if profile_source == "account": account.attach_world(str(cp.run_id))
	if cp.get("roster") is Dictionary: roster = (cp.roster as Dictionary).duplicate(true)
	var selected = cp.get("selected", [selected_character, selected_weapon])
	if selected is Array and selected.size() == 2:
		selected_character = clampi(int(selected[0]), 0, DiverCharacter.COUNT - 1)
	apply_world_state(cp.world, false)
	var mine = roster.get(net.player_id, cp.build if not cp.online or str(cp.build.get("id", "")) == net.player_id else {})
	if mine is Dictionary and not mine.is_empty(): apply_build(mine)
	else: player.weapon = selected_weapon
	notify("DIG RESUMED", "B%d · %s. Your build is back." % [depth, DEPTH_NAMES[depth - 1]])
	print("ONLINE: dig restored run=%s depth=%d parts=%d" % [run_id, depth, player.items.size()])
	if net.active():
		net.report_status("run", depth)
		send_info()
	save_checkpoint()

# Title → Continue Dig / Rejoin Dig.
func continue_saved_dig() -> void:
	var cp = load_checkpoint()
	if cp.is_empty(): return
	var owner_id = str(cp.get("account_id", ""))
	if owner_id != (str(account.identity.get("id", "")) if profile_source == "account" else ""):
		notify("SAVED DIG", "Switch to the account or Guest profile that started this dig.")
		return
	if not cp.online:
		restore_checkpoint(cp)
		return
	pending_restore = cp
	mode = "online"
	net.resume_lobby(str(cp.lobby_code), str(cp.lobby_name), bool(cp.public), str(cp.password))

func discard_saved_dig() -> void:
	retire_saved_dig("")

# --- connection, hosting and lobby events ---------------------------------------

func send_info() -> void:
	if not is_instance_valid(player): return
	var build = build_state()
	if mode in ["lobby", "online", "title"]:
		build.character = selected_character
		build.weapon = selected_weapon
		build.skills = DiverProgression.owned(meta, selected_character)
		build.spec = equipped_spec(selected_character)
	if net.active():
		roster[net.player_id] = build
		net.broadcast([DiverNet.M_INFO, build])

func send_state() -> void:
	var p = player
	net.broadcast([DiverNet.M_STATE, depth, p.global_position, p.velocity, p.yaw, p.pitch, p.move_input, p.state_flags(), p.hp, p.max_hp(), p.revive])

func spawn_remote_players() -> void:
	for member in net.members():
		var member_slot = int(member.slot)
		if member_slot == net.slot: continue
		create_remote_player(member_slot)

func create_remote_player(member_slot: int) -> DiverPlayer:
	if remote_players.has(member_slot) and is_instance_valid(remote_players[member_slot]): return remote_players[member_slot]
	var info: Dictionary = peers.get(member_slot, roster.get(net.member_id(member_slot), {}))
	var proxy = DiverPlayer.new()
	proxy.game = self
	proxy.is_local = false
	proxy.slot = member_slot
	proxy.player_id = net.member_id(member_slot)
	proxy.display_name = net.member_name(member_slot)
	proxy.character = clampi(int(info.get("character", 0)), 0, DiverCharacter.COUNT - 1)
	proxy.weapon = DiverPlayer.SIGNATURES[proxy.character]
	proxy.skills = clean_skills(info.get("skills", []))
	proxy.spec = clean_spec(info.get("spec", ""), proxy.skills)
	proxy.milestones = clean_milestones(info.get("milestones", []))
	proxy.items = (info.get("items", {}) as Dictionary).duplicate() if info.get("items") is Dictionary else {}
	proxy.level = int(info.get("level", 1))
	world.add_child(proxy)
	proxy.position = Vector3([0.0, 1.6, -1.6, 3.2][clampi(member_slot - 1, 0, 3)], 0.12, 3)
	proxy.net_pos = proxy.position
	remote_players[member_slot] = proxy
	print("ONLINE: teammate %s (slot %d) is in the dig" % [proxy.display_name, member_slot])
	return proxy

func remove_remote_player(member_slot: int) -> void:
	if remote_players.has(member_slot):
		if is_instance_valid(remote_players[member_slot]): remote_players[member_slot].queue_free()
		remote_players.erase(member_slot)

func in_run() -> bool:
	return mode == "play" or mode in OVERLAY_MODES

# Called every frame while the dig runs online.
func net_tick(dt: float) -> void:
	net_clock += dt
	if net_clock < 0.05: return
	net_clock = 0.0
	send_state()
	if not net.is_host(): return
	var data = PackedFloat32Array()
	for e in enemies:
		if not is_instance_valid(e) or e.dead or not e.active: continue
		data.append_array([e.net_id, e.global_position.x, e.global_position.y, e.global_position.z, e.rotation.y, e.health])
	net.broadcast([DiverNet.M_SNAP, depth, scrap, kills, guardian_dead, run_time, data])
	# The dig ends only when every digger is down.
	var standing = 0
	for p in all_players():
		if not p.downed: standing += 1
	if standing == 0: end_run_all(false)

func end_run_all(won: bool) -> void:
	net.broadcast([DiverNet.M_END, won])
	finish_run(won)

func new_run_id(seed_value: int) -> String:
	return "%d-%d-%d" % [seed_value, int(Time.get_unix_time_from_system()), randi() % 100000]

func host_start_run() -> void:
	if not net.is_host(): return
	if profile_source == "account" and account.server_run == "":
		if account_starting: return
		account_starting = true
		account.begin_run(host_start_run)
		return
	var seed_value = randi() % 1000000 + 1
	var party = maxi(1, net.members().size())
	var id = new_run_id(seed_value)
	net.broadcast([DiverNet.M_START, seed_value, party, id])
	start_run(seed_value, party, id)

func enter_lobby_room() -> void:
	mode = "lobby"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	position_title_camera()
	send_info()

func leave_online() -> void:
	net.leave_lobby()
	peers.clear()
	pending_restore = {}
	for member_slot in remote_players.keys(): remove_remote_player(member_slot)
	if in_run(): finish_run(false)
	else: show_title()

func lobby_entered(info: Dictionary) -> void:
	print("ONLINE: joined lobby %s as slot %d (host slot %d)" % [net.lobby_code, net.slot, net.host_slot])
	peers.clear()
	if net_test == "": net.save_profile()
	var takeover = bool(info.get("takeover", false)) or bool(info.get("recreated", false))
	if takeover and in_run():
		# Back from a dropout as the only digger: carry on with the live dig.
		become_host("BACK ONLINE", "You're hosting the dig again.")
		return
	if takeover:
		if bool(info.get("checkpoint", false)):
			awaiting_checkpoint = 3.0
			return
		resolve_takeover({})
		return
	if in_run(): return  # Rejoined a live dig; the host will resync us.
	if mode in ["title", "online", "end", "archive"]: enter_lobby_room()

# The server handed us the last host's checkpoint (or it never came).
func server_checkpoint(data: Dictionary) -> void:
	if awaiting_checkpoint <= 0 or not valid_checkpoint(data): return
	resolve_takeover(data)

func resolve_takeover(server_copy: Dictionary) -> void:
	awaiting_checkpoint = 0.0
	var best = server_copy
	var mine = pending_restore if not pending_restore.is_empty() else load_checkpoint()
	pending_restore = {}
	if not mine.is_empty() and str(mine.get("lobby_code", "")) == net.lobby_code and mine.get("online", false):
		var same_run = not best.is_empty() and str(mine.run_id) == str(best.run_id)
		if best.is_empty() or (same_run and float(mine.world.get("run_time", 0)) > float(best.world.get("run_time", 0))):
			best = mine
	if best.is_empty():
		enter_lobby_room()
		return
	restore_checkpoint(best)

func become_host(title: String, detail: String) -> void:
	# Robots and loot now run here, starting from the positions we last saw.
	var top = pickup_seq
	for p in pickups: top = maxi(top, int(p.net_id))
	pickup_seq = top + 1000
	for e in enemies:
		if is_instance_valid(e) and not e.dead and e.net_seen:
			e.global_position = e.net_pos
			e.rotation.y = e.net_rot
	notify(title, detail)
	print("ONLINE: now hosting run=%s" % run_id)
	net.report_status("run", depth)
	send_info()
	save_checkpoint()

func host_changed() -> void:
	if in_run() and net.is_host(): become_host("YOU'RE HOSTING NOW", "The host left, so the dig moved to you. Keep going!")

func lobby_updated() -> void:
	var present = []
	for member in net.members(): present.append(int(member.slot))
	for member_slot in peers.keys():
		if not present.has(member_slot): peers.erase(member_slot)
	for member_slot in remote_players.keys():
		if not present.has(member_slot): remove_remote_player(member_slot)
		elif is_instance_valid(remote_players[member_slot]):
			remote_players[member_slot].display_name = net.member_name(member_slot)
			remote_players[member_slot].player_id = net.member_id(member_slot)

func peer_entered(member_slot: int, id: String) -> void:
	send_info()
	# The newcomer may be a returning digger: hand back their build with the world.
	if net.is_host() and in_run(): net.send(member_slot, [DiverNet.M_SYNC, world_state(), roster.get(id, {})])

func peer_left(member_slot: int) -> void:
	var who = net.member_name(member_slot)
	peers.erase(member_slot)
	remove_remote_player(member_slot)
	if in_run(): notify("%s DROPPED OUT" % who.to_upper(), "Their build is saved if they rejoin. The dig continues.")

func kicked() -> void:
	peers.clear()
	pending_restore = {}
	for member_slot in remote_players.keys(): remove_remote_player(member_slot)
	if in_run():
		end_reason = "The host removed you from the lobby"
		finish_run(false)
	else:
		mode = "online"
		net.error_text = "The host removed you from the lobby."

func connection_lost() -> void:
	print("ONLINE: connection lost, reconnecting")
	save_checkpoint_offline()

func connection_failed(reason: String) -> void:
	peers.clear()
	pending_restore = {}
	awaiting_checkpoint = 0.0
	for member_slot in remote_players.keys(): remove_remote_player(member_slot)
	if in_run():
		# The dig stays saved; Rejoin Dig on the title screen picks it back up.
		show_title()
		notify("DIG SAVED", reason + " Choose Rejoin Dig to continue.")
		saved_dig = load_checkpoint()
	elif mode == "lobby":
		mode = "online"

func join_failed(code: String) -> void:
	if not pending_restore.is_empty() and code in ["banned", "version", "locked", "password", "full"]:
		pending_restore = {}

# Reconnecting blocks the normal save (state is frozen), so write it explicitly once.
func save_checkpoint_offline() -> void:
	if not in_run() or not persisting(): return
	var f = FileAccess.open(checkpoint_path + ".tmp", FileAccess.WRITE)
	if f == null: return
	f.store_var(checkpoint_data())
	f.close()
	if FileAccess.file_exists(checkpoint_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(checkpoint_path))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(checkpoint_path + ".tmp"), ProjectSettings.globalize_path(checkpoint_path))

func apply_sync(m: Array) -> void:
	if profile_source == "account" and account.server_run == "": account.resume_world(str(m[1].get("run_id", "")))
	if profile_source == "account" and account.server_run == "":
		if account_starting: return
		account_starting = true
		account.begin_run(func(): apply_sync(m))
		return
	var w: Dictionary = m[1]
	var build: Dictionary = m[2]
	var same_run = in_run() and str(w.get("run_id", "")) == run_id
	if not same_run: retire_saved_dig(str(w.get("run_id", "")))
	apply_world_state(w, same_run)
	if profile_source == "account": account.attach_world(run_id)
	if same_run: pass  # Our live build is the freshest copy.
	elif not build.is_empty():
		apply_build(build)
		notify("WELCOME BACK", "Your build was saved. B%d · %s." % [depth, DEPTH_NAMES[depth - 1]])
	else:
		player.weapon = selected_weapon
		notify("JOINED THE DIG", "B%d · %s. Catch up with your team!" % [depth, DEPTH_NAMES[depth - 1]])
	print("ONLINE: synced into dig run=%s depth=%d parts=%d" % [run_id, depth, player.items.size()])
	build_changed()
	save_checkpoint()

func enemy_by_id(id: int) -> DiverEnemy:
	if id < 0 or id >= enemies.size(): return null
	var e = enemies[id]
	return e if is_instance_valid(e) and not e.dead else null

func sender(from_slot: int) -> DiverPlayer:
	var proxy = remote_players.get(from_slot)
	return proxy if is_instance_valid(proxy) else null

# --- chat, pings and spectating ---------------------------------------------------

func say(text: String, quick: bool = false) -> void:
	text = text.strip_edges().left(120)
	if text == "" or not net.active(): return
	add_chat(net.slot, net.player_name, text, quick)
	net.broadcast([DiverNet.M_CHAT, text, quick])
	if quick and is_instance_valid(player): player.speak(text)

func add_chat(from_slot: int, who: String, text: String, quick: bool) -> void:
	chat_log.append({"slot": from_slot, "name": who, "text": text, "quick": quick, "time": Time.get_ticks_msec()})
	while chat_log.size() > 30: chat_log.pop_front()
	sound.play("menu_move")

# Mark a spot (or a robot, cache or lift) for the team.
func ping_here() -> void:
	if not net.active() or not is_instance_valid(player) or not is_instance_valid(player.camera): return
	var center = get_viewport().get_visible_rect().size * 0.5
	var from = player.camera.project_ray_origin(center)
	var query = PhysicsRayQueryParameters3D.create(from, from + player.camera.project_ray_normal(center) * 60, 5)
	var hit = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var label = "Here!"
	var at: Vector3 = hit.position
	if hit.collider is DiverEnemy:
		label = "Robot!"
		at = hit.collider.global_position
	else:
		for obj in interactables:
			if not obj.used and obj.node.position.distance_to(at) < 2.5:
				label = {"cache": "Cache!", "spring": "Repair well!", "lift": "Lift!", "pot": "Salvage!"}.get(obj.kind, "Here!")
				at = obj.node.position
	place_ping(net.slot, at, label)
	net.broadcast([DiverNet.M_PING, depth, at, label])

func place_ping(from_slot: int, at: Vector3, label: String) -> void:
	var color: Color = DiverNet.SLOT_COLORS[clampi(from_slot, 0, 4)]
	var root = Node3D.new()
	world.add_child(root)
	root.position = Vector3(at.x, maxf(0.06, at.y - 0.9) if label == "Robot!" else at.y + 0.06, at.z)
	DiverArt.ring(root, Vector3.ZERO, 0.9, color, 0.12)
	DiverArt.box(root, Vector3(0, 1.6, 0), Vector3(0.06, 3.2, 0.06), color, false, 1.5)
	var tag = DiverArt.label(root, Vector3(0, 3.6, 0), "%s: %s" % [net.player_name if from_slot == net.slot else net.member_name(from_slot), label], color, 40)
	tag.no_depth_test = true
	pings.append({"node": root, "life": 5.0})
	while pings.size() > 8:
		var old = pings.pop_front()
		if is_instance_valid(old.node): old.node.queue_free()
	sound.play("lock", 1.2, at)

func update_pings(dt: float) -> void:
	for i in range(pings.size() - 1, -1, -1):
		pings[i].life -= dt
		var node: Node3D = pings[i].node
		if not is_instance_valid(node) or pings[i].life <= 0:
			if is_instance_valid(node): node.queue_free()
			pings.remove_at(i)
		else:
			node.rotation.y += dt * 2
			node.visible = pings[i].life > 1.0 or int(pings[i].life * 8) % 2 == 0

func spectate_target() -> DiverPlayer:
	var standing = []
	for p in remote_players.values():
		if is_instance_valid(p) and not p.downed: standing.append(p)
	if standing.is_empty(): return null
	return standing[wrapi(spectate_index, 0, standing.size())]

# --- game messages -------------------------------------------------------------

# Expected shapes of incoming messages: anything else is ignored, never crashes the dig.
const NUM = -1
const SHAPES = {
	DiverNet.M_INFO: [TYPE_DICTIONARY],
	DiverNet.M_STATE: [NUM, TYPE_VECTOR3, TYPE_VECTOR3, NUM, NUM, TYPE_VECTOR2, NUM, NUM, NUM, NUM],
	DiverNet.M_SHOT: [NUM, TYPE_VECTOR3, TYPE_VECTOR3, TYPE_BOOL, NUM],
	DiverNet.M_START: [NUM, NUM, TYPE_STRING],
	DiverNet.M_SNAP: [NUM, NUM, NUM, TYPE_BOOL, NUM, TYPE_PACKED_FLOAT32_ARRAY],
	DiverNet.M_ATTACK: [NUM, NUM, TYPE_STRING, NUM, TYPE_VECTOR3],
	DiverNet.M_RESOLVE: [NUM, NUM, TYPE_VECTOR3],
	DiverNet.M_DAMAGE: [NUM, NUM, NUM, TYPE_BOOL, NUM],
	DiverNet.M_DIE: [NUM, NUM],
	DiverNet.M_PICKUP: [NUM, NUM, TYPE_VECTOR3, TYPE_STRING, NUM, TYPE_STRING, TYPE_STRING],
	DiverNet.M_PICKUP_GONE: [NUM, NUM, NUM, TYPE_STRING],
	DiverNet.M_USED: [NUM, NUM],
	DiverNet.M_HIT: [NUM, NUM, NUM],
	DiverNet.M_INTERACT: [NUM, NUM],
	DiverNet.M_FROST: [NUM, TYPE_VECTOR3, NUM, NUM],
	DiverNet.M_HEAL: [NUM],
	DiverNet.M_ITEM: [TYPE_STRING],
	DiverNet.M_XP: [NUM],
	DiverNet.M_CHOICE: [NUM, NUM, NUM],
	DiverNet.M_NOTIFY: [TYPE_STRING, TYPE_STRING],
	DiverNet.M_FLOOR: [NUM, NUM],
	DiverNet.M_END: [TYPE_BOOL],
	DiverNet.M_SYNC: [TYPE_DICTIONARY, TYPE_DICTIONARY],
	DiverNet.M_LIGHTNING: [NUM, TYPE_VECTOR3, TYPE_VECTOR3],
	DiverNet.M_CLEARED: [NUM, NUM],
	DiverNet.M_RESTORE: [NUM],
	DiverNet.M_CHAT: [TYPE_STRING, TYPE_BOOL],
	DiverNet.M_PING: [NUM, TYPE_VECTOR3, TYPE_STRING],
	DiverNet.M_VISITED: [NUM, NUM],
}
# Messages tied to the current floor carry its descent number first.
const FLOOR_MESSAGES = [DiverNet.M_STATE, DiverNet.M_SHOT, DiverNet.M_SNAP, DiverNet.M_ATTACK, DiverNet.M_RESOLVE, DiverNet.M_DAMAGE, DiverNet.M_DIE, DiverNet.M_PICKUP, DiverNet.M_PICKUP_GONE, DiverNet.M_USED, DiverNet.M_HIT, DiverNet.M_INTERACT, DiverNet.M_FROST, DiverNet.M_LIGHTNING, DiverNet.M_CLEARED, DiverNet.M_PING, DiverNet.M_CHOICE, DiverNet.M_VISITED]

func well_formed(m: Array) -> bool:
	if typeof(m[0]) != TYPE_INT or not SHAPES.has(m[0]): return false
	var shape: Array = SHAPES[m[0]]
	if m.size() < shape.size() + 1: return false
	for i in shape.size():
		var kind = typeof(m[i + 1])
		if shape[i] == NUM:
			if kind != TYPE_INT and kind != TYPE_FLOAT: return false
		elif kind != shape[i]: return false
	return true

func net_message(from_slot: int, m: Array) -> void:
	if not well_formed(m):
		malformed_messages += 1
		return
	var kind = int(m[0])
	if kind in FLOOR_MESSAGES and (not in_run() or int(m[1]) != depth): return
	var from_host = from_slot == net.host_slot
	match kind:
		DiverNet.M_INFO:
			var b: Dictionary = m[1]
			if not b.get("items") is Dictionary: return
			peers[from_slot] = b
			var id = str(b.get("id", net.member_id(from_slot)))
			if id != "": roster[id] = b
			var proxy = sender(from_slot)
			if proxy:
				if proxy.character != int(b.get("character", 0)): proxy.set_character(int(b.get("character", 0)))
				proxy.weapon = DiverPlayer.SIGNATURES[proxy.character]
				proxy.skills = clean_skills(b.get("skills", []))
				proxy.spec = clean_spec(b.get("spec", ""), proxy.skills)
				proxy.milestones = clean_milestones(b.get("milestones", []))
				proxy.items = (b.items as Dictionary).duplicate()
				proxy.level = int(b.get("level", 1))
		DiverNet.M_STATE:
			var proxy = sender(from_slot)
			if proxy == null: proxy = create_remote_player(from_slot)
			proxy.apply_state(m[2], m[3], m[4], m[5], m[6], int(m[7]), m[8], m[9], m[10])
			var id = net.member_id(from_slot)
			if roster.has(id):
				roster[id].hp = float(m[8])
				roster[id].downed = int(m[7]) & DiverPlayer.FLAG_DOWN != 0
		DiverNet.M_SHOT:
			spawn_bolt(m[2], m[3], 0, false, m[4], clampi(int(m[5]), 0, 1), sender(from_slot), true)
			if sender(from_slot): sender(from_slot).remote_shot(m[2])
		DiverNet.M_START:
			if from_host:
				retire_saved_dig(str(m[3]))
				start_run(int(m[1]), int(m[2]), str(m[3]))
		DiverNet.M_SYNC:
			if from_host: apply_sync(m)
		DiverNet.M_FLOOR:
			if from_host and in_run():
				depth = clampi(int(m[1]), 1, 3)
				party_size = clampi(int(m[2]), 1, DiverNet.MAX_PLAYERS)
				rng.seed = floor_seed(depth)
				enter_floor()
		DiverNet.M_END:
			if from_host and in_run(): finish_run(bool(m[1]))
		DiverNet.M_SNAP:
			if not from_host: return
			scrap = int(m[2])
			kills = int(m[3])
			guardian_dead = bool(m[4])
			run_time = float(m[5])
			var data: PackedFloat32Array = m[6]
			for i in range(0, data.size() - 5, 6):
				var e = enemy_by_id(int(data[i]))
				if e: e.apply_snapshot(Vector3(data[i + 1], data[i + 2], data[i + 3]), data[i + 4], data[i + 5])
		DiverNet.M_ATTACK:
			var e = enemy_by_id(int(m[2]))
			if from_host and e: e.show_attack(str(m[3]), float(m[4]), m[5])
		DiverNet.M_RESOLVE:
			var e = enemy_by_id(int(m[2]))
			if from_host and e:
				e.global_position = m[3]
				e.resolve_attack()
		DiverNet.M_DAMAGE:
			var e = enemy_by_id(int(m[2]))
			if from_host and e: e.show_damage(float(m[3]), bool(m[4]), int(m[5]) != net.slot)
		DiverNet.M_DIE:
			var e = enemy_by_id(int(m[2]))
			if from_host and e: e.remote_die()
		DiverNet.M_LIGHTNING:
			if from_host:
				var p = DiverArt.box(world, (m[2] + m[3]) * 0.5, Vector3(0.06, 0.06, maxf(0.1, m[2].distance_to(m[3]))), Color("a9bdff"), false, 2)
				p.look_at(m[3])
				particles.append({"node": p, "velocity": Vector3.ZERO, "life": 0.13})
		DiverNet.M_PICKUP:
			if from_host and (m[4] != "relic" or ITEMS.has(m[6])): make_pickup(int(m[2]), m[3], m[4], float(m[5]), m[6], m[7])
		DiverNet.M_PICKUP_GONE:
			if not from_host: return
			for i in range(pickups.size() - 1, -1, -1):
				if pickups[i].net_id == int(m[2]):
					if is_instance_valid(pickups[i].node): pickups[i].node.queue_free()
					pickups.remove_at(i)
			if int(m[3]) == net.slot and m[4] in ["scrap", "health"]: sound.play(m[4])
		DiverNet.M_XP:
			if from_host and in_run(): player.gain_xp(int(m[1]))
		DiverNet.M_ITEM:
			if from_host and in_run() and ITEMS.has(m[1]): player.add_item(m[1])
		DiverNet.M_HEAL:
			if from_host and in_run(): player.heal(float(m[1]))
		DiverNet.M_RESTORE:
			if from_host and in_run(): restore_life(float(m[1]))
		DiverNet.M_CHOICE:
			if from_host and in_run():
				if int(m[3]) == net.slot: open_relic_choice({"depth": depth, "cache": int(m[2]), "items": []})
				else: add_pending_choice(int(m[2]))
		DiverNet.M_NOTIFY:
			if from_host and in_run(): notify(m[1].left(60), m[2].left(160))
		DiverNet.M_USED:
			if from_host and int(m[2]) >= 0 and int(m[2]) < interactables.size(): use_interactable(interactables[int(m[2])])
		DiverNet.M_VISITED:
			if int(m[2]) >= 0 and int(m[2]) < rooms.size(): rooms[int(m[2])].visited = true
		DiverNet.M_CLEARED:
			if from_host and int(m[2]) >= 0 and int(m[2]) < rooms.size() and not rooms[int(m[2])].cleared:
				rooms[int(m[2])].cleared = true
				if int(m[2]) == current_room: notify("CHAMBER SECURED", "+5 scrap · caches available")
		DiverNet.M_HIT:
			var e = enemy_by_id(int(m[2]))
			if net.is_host() and e and sender(from_slot): e.take_damage(clampf(float(m[3]), 0, 5000), true, sender(from_slot))
		DiverNet.M_INTERACT:
			var index = int(m[2])
			if net.is_host() and sender(from_slot) and index >= 0 and index < interactables.size(): perform_interact(interactables[index], sender(from_slot))
		DiverNet.M_FROST:
			if net.is_host(): frost_burst(m[2], clampf(float(m[3]), 0, 20), clampf(float(m[4]), 0, 8))
		DiverNet.M_CHAT:
			add_chat(from_slot, net.member_name(from_slot), m[1].strip_edges().left(120), m[2])
			if m[2] and sender(from_slot): sender(from_slot).speak(m[1].left(40))
		DiverNet.M_PING:
			place_ping(from_slot, m[2], m[3].left(16))
