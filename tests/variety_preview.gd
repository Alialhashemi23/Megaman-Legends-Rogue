extends SceneTree

# Renders the new robots, a venting guardian, the B3 pillars and the Power Relay
# into res://save/variety-captures/ (ignored). Run windowed, not --headless.

var game: Node3D
const OUT = "res://save/variety-captures"

func _initialize() -> void:
	run.call_deferred()

func shot(filename: String) -> void:
	game.hud.queue_redraw()
	for n in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, filename])

func look(from: Vector3, at: Vector3) -> void:
	var p: DiverPlayer = game.player
	p.global_position = from
	var d = at - from
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = -0.15
	p.update_camera(1)

func freeze() -> void:
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/variety-preview.json"
	game.checkpoint_path = "res://save/variety-preview.dat"
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	game.meta.kills = 400
	root.size = Vector2i(1440, 900)
	game.start_run(31337)
	game.depth = 2
	game.rng.seed = game.floor_seed(2)
	game.build_floor(true)
	game.start_controls_blocked = false
	game.message_time = 0
	freeze()
	var p: DiverPlayer = game.player
	p.set_physics_process(false)
	# New robots side by side.
	var spot = p.global_position + Vector3(0, 0, -6)
	var grenadier = game.spawn_enemy(spot + Vector3(-1.6, 0, 0), 4, 0)
	var mender = game.spawn_enemy(spot + Vector3(1.6, 0, 0), 5, 0)
	var ally = game.spawn_enemy(spot + Vector3(3.2, 0, -1.5), 0, 0)
	for e in [grenadier, mender, ally]: e.set_physics_process(false)
	await process_frame
	look(spot + Vector3(0, 0, 5.5), spot)
	await shot("01-grenadier-mender")
	grenadier.show_attack("lob", 1.2, p.global_position + Vector3.UP)
	ally.health = ally.max_health * 0.4
	mender.heal_clock = 0
	mender.mender_repair(0.01)
	await shot("02-lob-rings-and-repair-beam")
	# The Power Relay chamber.
	var relay_room = game.rooms[game.relay.room]
	look(relay_room.center + Vector3(0, 0, 11), relay_room.center)
	await shot("03-power-relay-idle")
	game.relay.active = true
	game.relay.charge = 46.0
	game.relay.ring = 1
	game.current_room = game.relay.room
	game.relay_visuals()
	await shot("04-power-relay-charging")
	# A venting guardian, seen from behind.
	var g: DiverEnemy = null
	for e in game.enemies:
		if is_instance_valid(e) and e.kind == 3: g = e
	g.rotation.y = 0
	g.active = true
	g.open_vent()
	game.current_room = game.exit_room
	look(g.global_position + Vector3(2.5, 0, 9), g.global_position + Vector3.UP * 2)
	await shot("05-guardian-core-vent")
	# B3 arena pillars.
	game.depth = 3
	game.rng.seed = game.floor_seed(3)
	game.build_floor(true)
	freeze()
	var exit = game.rooms[game.exit_room]
	var pillar = game.interactables.filter(func(o): return o.kind == "pillar")[0]
	look(exit.center + Vector3(1.5, 0, 6.0), exit.center + Vector3.UP)
	await shot("06-b3-pillars")
	print("VARIETY_PREVIEW_SAVED")
	quit()
