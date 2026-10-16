extends SceneTree

var game: Node3D
var failures = 0
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CHECK_FAILED: " + message)

func arena() -> void:
	game.depth = 1
	game.rng.seed = 49381
	game.build_floor(false)
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.mode = "play"
	game.auto_open_choice = false
	game.player.hp = 100
	game.player.invincible = 0
	await physics_frame
	await physics_frame

func pause_for(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.smoke_test = true
	game.set_process(false)
	# Generation must offer paths through every kind of chamber.
	var layouts = {}
	for seed_value in [49381, 8, 120, 8394, 5920, 8888]:
		game.rng.seed = seed_value
		game.depth = 1 + (seed_value % 3)
		game.build_floor(false)
		for room in game.rooms:
			if room.type == "chamber": layouts[room.layout] = true
			var path = game.navigation.route(Vector3.ZERO, room.center)
			verify(not path.is_empty(), "Every chamber remains reachable for seed %d" % seed_value)
			for point in path: verify(game.navigation.open_at(point), "Path never crosses a blocked grid point")
		for enemy in game.enemies:
			verify(game.navigation.open_at(enemy.position), "Enemy spawn avoids cover")
		await process_frame
	# Five cover arrangements plus the jump puzzle (5) and the terrace (6).
	for layout in 7: verify(layouts.has(layout), "Chamber layout %d appears" % layout)

	await arena()
	game.player.position = Vector3(0, 0, -0.4)
	var melee = game.spawn_enemy(Vector3(0, 0, -2), 0, 0)
	melee.attack = 100
	melee.begin_attack("melee", 0.46)
	verify(is_instance_valid(melee.marker), "Melee windup displays a warning")
	await pause_for(0.2)
	verify(game.player.hp == 100, "Melee windup does not damage the player early")
	game.player.position = Vector3(4, 0, -0.4)
	await pause_for(0.30)
	verify(game.player.hp == 100, "Leaving a melee warning avoids damage")
	game.player.position = melee.position + Vector3(0, 0, 1.2)
	melee.begin_attack("melee", 0.46)
	await pause_for(0.52)
	verify(game.player.hp < 100, "Remaining inside a melee warning takes damage")

	await arena()
	game.cover(game.world, Vector3(0, 0.8, -0.5), Vector3(4, 1.6, 1), Color.WHITE)
	game.player.position = Vector3(0, 0, 0.5)
	melee = game.spawn_enemy(Vector3(0, 0, -1.5), 0, 0)
	melee.attack = 100
	await physics_frame
	melee.begin_attack("melee", 0.46)
	await pause_for(0.52)
	verify(game.player.hp == 100, "Melee damage cannot pass through cover")

	await arena()
	game.player.position = Vector3(0, 0, 5)
	var sentry = game.spawn_enemy(Vector3.ZERO, 1, 0)
	sentry.attack = 100
	sentry.begin_attack("shot", 0.65)
	var first_aim = sentry.aim_point
	await pause_for(0.18)
	verify(sentry.aim_point == first_aim and not sentry.aim_locked, "Ranged aim holds through the windup")
	game.player.position = Vector3(3, 0, 5)
	await pause_for(0.16)
	verify(sentry.aim_locked and sentry.aim_point.x > 2.0, "Ranged aim locks onto the digger just before firing")
	game.player.position = Vector3(7, 0, 5)
	await pause_for(0.65)
	verify(game.player.hp == 100, "Moving after the lock dodges the shot")

	await arena()
	game.player.position = Vector3(0, 0, 5)
	var charger = game.spawn_enemy(Vector3.ZERO, 2, 0)
	charger.attack = 100
	charger.begin_attack("charge", 0.70)
	await pause_for(0.25)
	verify(game.player.hp == 100 and charger.position.z < 0.2, "Charge windup is stationary and harmless")
	game.player.position = Vector3(4, 0, 5)
	await pause_for(1.0)
	verify(game.player.hp == 100, "Sidestepping the committed charge lane avoids damage")
	verify(charger.position.z > 4.5, "Charge follows the marked direction")

	await arena()
	game.cover(game.world, Vector3(0, 1.0, 0), Vector3(4, 2, 1), Color.WHITE)
	game.player.position = Vector3(0, 0, 6)
	var shielded = game.spawn_enemy(Vector3(0, 0, -1.5), 0, 0)
	var exposed = game.spawn_enemy(Vector3(-1, 0, 1.3), 0, 0)
	shielded.set_physics_process(false)
	exposed.set_physics_process(false)
	await physics_frame
	game.spawn_bolt(Vector3(0, 1, 3), Vector3.FORWARD, 20, false, true, 0)
	await pause_for(0.25)
	verify(exposed.health < exposed.max_health, "Siege impact on a wall splashes exposed nearby enemies")
	verify(shielded.health == shielded.max_health, "Siege splash cannot pass through solid cover")

	await arena()
	game.player.position = Vector3(0, 0, 5)
	var boss = game.spawn_enemy(Vector3.ZERO, 3, 0)
	boss.attack = 100
	boss.begin_attack("bombard", 1.05)
	verify(boss.strike_points.size() == 3, "Bombardment marks three fixed impact locations")
	game.player.position = Vector3(-4, 0, -5)
	await pause_for(1.15)
	verify(game.player.hp == 100, "Leaving bombardment rings avoids the impacts")
	game.player.position = Vector3(0, 0, 5)
	boss.begin_attack("cross", 1.10)
	game.player.position = Vector3(4, 0, 4)
	await pause_for(1.2)
	verify(game.player.hp == 100, "Standing between cross-beam lanes is safe")
	game.player.position = Vector3(0, 0, 5)
	boss.begin_attack("cross", 1.10)
	await pause_for(1.2)
	verify(game.player.hp < 100, "Remaining in a cross-beam lane takes damage")
	boss.set_physics_process(false)
	game.player.position = Vector3(0, 0, 3)
	game.player.hp = 100
	game.player.invincible = 0
	await physics_frame
	var jump = InputEventKey.new()
	jump.physical_keycode = KEY_SPACE
	jump.keycode = KEY_SPACE
	jump.pressed = true
	Input.parse_input_event(jump)
	await pause_for(0.28)
	jump.pressed = false
	Input.parse_input_event(jump)
	verify(game.player.position.y > 0.70, "A normal Space-key jump reaches shockwave clearance")
	boss.blast(Vector3.ZERO, 4.7, 25)
	verify(game.player.hp == 100, "Jumping above a ground shockwave avoids damage")
	game.player.set_physics_process(false)
	game.player.position.y = 0
	game.player.invincible = 0.26
	boss.blast(Vector3.ZERO, 4.7, 25)
	verify(game.player.hp == 100, "Dash invulnerability avoids shockwave damage")
	game.player.invincible = 0
	boss.blast(Vector3.ZERO, 4.7, 25)
	verify(game.player.hp == 75, "Grounded players inside a shockwave take damage")
	boss.health = boss.max_health
	boss.begin_attack("fan", 0.8)
	boss.take_damage(boss.max_health * 0.55, false)
	verify(boss.overdrive_triggered and boss.state == "recover", "Overdrive cancels a pending attack for a recovery window")
	verify(boss.marker == null, "Cancelled attack warnings are removed")

	await arena()
	game.cover(game.world, Vector3(0, 1.3, 0), Vector3(2.8, 2.6, 2.8), Color.WHITE)
	game.navigation.build(game.rooms, game.obstacles, game.links, game.nav_open)
	game.player.position = Vector3(3.5, 0, 0)
	var chaser = game.spawn_enemy(Vector3(-3.5, 0, 0), 0, 0)
	chaser.attack = 100
	await pause_for(4.5)
	verify(chaser.position.x > 1.8, "A chasing robot routes around a central obstacle")
	verify(chaser.position.distance_to(game.player.position) < 3.0, "Routed robot reaches the player side of cover")

	game.mode = "pause"
	var frozen = chaser.state_time
	chaser.begin_attack("melee", 0.5)
	frozen = chaser.state_time
	await pause_for(0.15)
	verify(chaser.state_time == frozen, "Pausing freezes attack warning timers")
	print("COMBAT_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
