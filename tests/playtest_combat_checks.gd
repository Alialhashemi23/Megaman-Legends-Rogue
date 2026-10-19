extends SceneTree

var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PLAYTEST_COMBAT_FAILED: " + label)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = "res://save/pt-combat.json"
	game.checkpoint_path = "res://save/pt-combat.dat"
	root.add_child(game)
	game.set_process(false)
	game.start_run(82828)
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	var g: DiverEnemy = game.enemies.filter(func(e): return e.kind == 3)[0]
	var p = game.player
	var room = game.rooms[g.room_id]
	var outside = room.center + Vector3(room.half.x + 2, 0, 0)
	p.position = outside
	verify(game.target_for(g) == null, "PT05 guardian ignores hallway digger")
	var health = g.health
	g.take_damage(100, true, p)
	verify(g.health == health and not g.active, "PT05 hallway hit neither damages nor activates")
	var robot = game.enemies.filter(func(e): return e.kind != 3)[0]
	verify(game.target_for(robot) == p, "PT05 ordinary robots still target across rooms")
	var remote = game.create_remote_player(2)
	remote.position = room.center + Vector3(3, 0, 0)
	verify(game.target_for(g) == remote, "PT05 guardian selects remote digger inside arena")
	g.take_damage(10, false, remote)
	verify(g.health == health - 10, "PT05 host accepts inside guest damage")
	remote.downed = true
	verify(game.target_for(g) == null, "PT05 downed digger does not hold aggro")
	g.position = outside
	g.active = true
	g.planned = "fan"
	g.state = "windup"
	g._physics_process(0.1)
	verify(game.room_index_at(g.position) == g.room_id and not g.active and g.state == "approach", "PT05 leaving cancels attack and leashes inside")
	for n in 100: g._physics_process(0.1)
	verify(g.position.distance_to(g.home_position) < 0.01, "PT05 returns to original spot without healing")
	verify(g.health == health - 10, "PT05 leash preserves guardian Life")
	p.position = room.center + Vector3(5, 0, 0)
	g.take_damage(10, false, p)
	verify(g.health == health - 20, "PT05 arena damage still works")
	g.open_vent()
	verify(g.vent_time > 0, "PT05 vents still open")
	g.aim_point = p.position + Vector3.UP
	g.fire_at_point(5)
	verify(game.world.get_children().filter(func(n): return n is DiverBolt and n.guardian_room == g.room_id).size() == 5, "PT05 guardian projectiles carry arena damage boundary")
	for node in game.world.get_children():
		if node is DiverBolt: node.queue_free()
	for d in [1, 2, 3]:
		game.depth = d
		verify(is_equal_approx(g.fan_spacing(), 0.24 if d == 1 else 0.14), "PT01 B%d fan spacing" % d)
	game.depth = 1
	p.set_character(2)
	p.weapon = 2
	p.items = {}
	verify(is_equal_approx(g.max_health, 2660), "PT01 B1 guardian Life unchanged with Tron/Siege")
	# Real hostile projectiles cross Tron's collision plane. The wider halfway
	# lane must be safe, while the centre lane still punishes standing still.
	for angle in [0.12, 0.0]:
		p.position = g.position + Vector3(sin(angle), 0, -cos(angle)) * 10
		p.hp = p.max_hp()
		p.invincible = 0
		p.dash_guard = 0
		g.aim_point = g.position + Vector3(0, 1.0, -10)
		g.fire_at_point(5)
		var hp = p.hp
		await create_timer(0.7).timeout
		verify(p.hp == hp if angle > 0 else p.hp < hp, "PT01 Tron safe between lanes; centre lane still hits (%.2f)" % angle)
		for node in game.world.get_children():
			if node is DiverBolt: node.queue_free()
	p.position = g.position + Vector3(0, 0, -8)
	var boss_before = g.health
	g.shield = 0
	game.damage_enemy(g, p.damage() * 2.4, p)
	verify(g.health < boss_before, "PT01 Tron's Siege damage works inside B1 arena")
	print("PLAYTEST_COMBAT_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

