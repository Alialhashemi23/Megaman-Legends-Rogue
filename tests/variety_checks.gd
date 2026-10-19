extends SceneTree

# BAL-02 balance, ENEMY-01 grenadier/mender, BOSS-01 vents and pillars, ROOM-01
# Power Relay, RELIC-01 parts, and the synced mid-fight spawns they rely on.
# Isolated saves; the game's own _process is driven by hand.

var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VARIETY_CHECK_FAILED: " + message)

func guardian() -> DiverEnemy:
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead and e.kind == 3: return e
	return null

func fresh_run(seed_value: int, at_depth: int) -> void:
	game.mode = "title"
	game.start_run(seed_value)
	if at_depth > 1:
		game.depth = at_depth
		game.rng.seed = game.floor_seed(at_depth)
		game.build_floor(true)
	for e in game.enemies: e.set_physics_process(false)
	game.player.set_physics_process(false)
	game.start_controls_blocked = false

func count_kind(kind: int) -> int:
	var n = 0
	for e in game.enemies:
		if is_instance_valid(e) and e.kind == kind: n += 1
	return n

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save"))
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/variety-test.json"
	game.checkpoint_path = "res://save/variety-test.dat"
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	game.meta = DiverProgression.fresh()
	game.meta.kills = 400
	await process_frame
	verify(DiverNet.NET_VERSION == 13, "Protocol separates build36 floor generation from build35")

	# --- Level-ups count like parts (BAL-02 C, half) --------------------------
	fresh_run(31337, 1)
	var p: DiverPlayer = game.player
	var plain = p.damage()
	p.power_picks = 1
	var picked = p.damage()
	p.power_picks = 0
	p.items = {"lens": 1}
	verify(is_equal_approx(picked, p.damage()) and picked > plain, "A power pick counts exactly like one Sunken Lens")
	p.items = {}
	var slow_fire = p.fire_delay()
	p.haste_picks = 2
	verify(is_equal_approx(p.fire_delay(), slow_fire / 1.28), "Haste picks add to the Spring pool")
	p.haste_picks = 0
	game.mode = "choice"
	game.choice_kind = "level"
	game.choice_items = game.LEVEL_CHOICES.duplicate()
	game.choose(0)
	verify(p.power_picks == 1 and is_equal_approx(p.base_damage, 12.0), "Choosing power adds a pick, not base damage")
	var old_build = game.build_state()
	old_build.erase("power_picks")
	old_build.erase("haste_picks")
	old_build.base_damage = 18.0
	old_build.fire_multiplier = 1.3
	game.apply_build(old_build)
	verify(p.power_picks == 2 and p.haste_picks == 2 and is_equal_approx(p.base_damage, 12.0) and is_equal_approx(p.fire_multiplier, 1.0), "Older builds convert their level picks")
	var saved = game.build_state()
	verify(saved.power_picks == 2 and saved.haste_picks == 2, "Builds carry level picks")

	# --- Guardian curve and party scaling (BAL-02 B) --------------------------
	for d in [1, 2, 3]:
		fresh_run(4242, d)
		verify(is_equal_approx(guardian().max_health, 1900.0 * [1.4, 3.5, 7.5][d - 1]), "B%d guardian Life follows the new curve" % d)
	game.party_size = 3
	var tough = game.spawn_enemy(Vector3(0, 0, -30), 3, game.exit_room)
	verify(is_equal_approx(tough.max_health, 1900.0 * 7.5 * 2.6), "Each extra digger adds 80% guardian Life")
	tough.queue_free()
	game.enemies.erase(tough)
	game.party_size = 1

	# --- Part effects (BAL-02 A, RELIC-01) -------------------------------------
	fresh_run(777, 1)
	p = game.player
	var foes = game.enemies.filter(func(e): return e.kind != 3)
	var a: DiverEnemy = foes[0]
	a.max_health = 100000
	a.health = 100000
	p.items = {"ember": 2}
	a.take_damage(100.0, true, p)
	verify(is_equal_approx(a.burn_pool, 24.0), "Ember stores 12% per stack of each hit as burn")
	var before = a.health
	a.burn_tick = 0
	a.active = true
	a._physics_process(0.016)
	verify(before - a.health >= 3.5, "A burn tick draws from the pool (%.1f)" % (before - a.health))
	a.burn_time = 0
	a.burn_pool = 0
	p.items = {"coil": 4}
	for e in game.enemies:
		if e != a and is_instance_valid(e): e.global_position = Vector3(500, 0, 500)
	var lone_before = a.health
	var grounded = false
	for n in 40:
		var h = a.health
		a.take_damage(10.0, true, p)
		if h - a.health > 10.5: grounded = true
	verify(grounded, "Storm Coil grounds into a lone target")
	p.items = {}
	a.slow = 2.0
	verify(is_equal_approx(a.chill(), 1.35), "Slowed machines wind up 35% slower")
	var h0 = a.health
	a.take_damage(100.0, false, p)
	verify(is_equal_approx(h0 - a.health, 110.0), "Slowed machines take 10% more")
	p.items = {"shatter": 2}
	h0 = a.health
	a.take_damage(100.0, false, p)
	verify(is_equal_approx(h0 - a.health, 143.0), "Shatter Core adds 15% per stack against slowed machines")
	a.slow = 0
	a.exposed = 2.0
	p.items = {"refractor": 1}
	h0 = a.health
	a.take_damage(100.0, false, p)
	verify(is_equal_approx(h0 - a.health, 168.0), "Refractor Crystal boosts damage to exposed machines")
	a.exposed = 0
	p.items = {"overclock": 2}
	p.last_hurt = -100000
	var quick = p.fire_delay()
	p.last_hurt = Time.get_ticks_msec()
	verify(quick < p.fire_delay() and is_equal_approx(p.fire_delay() / quick, 1.24), "Overclock Relay fires faster only while untouched")
	p.items = {}
	game.flare_patch(a.global_position, 100.0, 2, p)
	var patch_before = a.health
	game.flare_update(0.01)
	verify(game.flare_patches.size() == 1 and patch_before - a.health > 29.0, "A flare patch burns machines inside it")
	game.flare_update(3.5)
	verify(game.flare_patches.is_empty(), "Flare patches burn out")

	# --- Guardian vents and core hits (BOSS-01) ---------------------------------
	var g = guardian()
	g.position = g.home_position
	g.planned = "slam"
	g.resolve_attack()
	verify(g.vent_time > 2.0 and g.core.visible, "A slam opens the core vent")
	var bolt = DiverBolt.new()
	bolt.game = game
	bolt.source = p
	verify(is_equal_approx(bolt.core_bonus(g, g.core_point()), 2.5), "Core hits deal 2.5x while venting")
	verify(is_equal_approx(bolt.core_bonus(g, g.global_position + Vector3.UP * 2.5 + Vector3(0, 0, -1.0).rotated(Vector3.UP, g.rotation.y)), 1.0), "Front hits are ordinary")
	p.items = {"refractor": 1}
	verify(is_equal_approx(bolt.core_bonus(g, g.core_point()), 3.5), "Refractor Crystal sharpens core hits")
	p.items = {}
	g.vent_time = 0
	verify(is_equal_approx(bolt.core_bonus(g, g.core_point()), 1.0), "No core bonus once the vent closes")
	bolt.free()

	# --- Overdrive adds and synced spawns ----------------------------------------
	p.position = g.position + Vector3(4, 0, 0)
	var enemies_before = game.enemies.size()
	g.take_damage(g.health - g.max_health * 0.45, false, p)
	await process_frame
	verify(game.enemies.size() == enemies_before + 2 and game.spawned.size() == 2, "B1 Overdrive calls two helpers")
	var w = game.world_state()
	verify(w.spawned.size() == 2, "Spawned helpers are part of the world state")
	var kinds = w.spawned.map(func(r): return r[0])
	game.apply_world_state(w, true)
	verify(game.enemies.size() == enemies_before + 2 and game.enemies.slice(enemies_before).map(func(e): return e.kind) == kinds, "Restores rebuild helpers with the same ids")
	verify(game.well_formed([DiverNet.M_SPAWN, 1, 5, 2, Vector3.ZERO, 3]) and not game.well_formed([DiverNet.M_SPAWN, 1, 5, 2, 0, 3]), "Spawn messages are shape-checked")
	var count_before = game.enemies.size()
	game.remote_spawn([DiverNet.M_SPAWN, 1, count_before + 3, 1, Vector3.ZERO, 0])
	game.remote_spawn([DiverNet.M_SPAWN, 1, count_before, 3, Vector3.ZERO, 0])
	verify(game.enemies.size() == count_before, "Out-of-order or guardian spawns are refused")
	game.remote_spawn([DiverNet.M_SPAWN, 1, count_before, 4, Vector3(2, 0, 2), 0])
	verify(game.enemies.size() == count_before + 1 and game.enemies[-1].kind == 4, "A matching spawn is added")

	# --- Grenadiers, menders and pillars (ENEMY-01, BOSS-01) ---------------------
	var grenadiers = 0
	var menders = 0
	for seed_value in [11, 22, 33, 44]:
		fresh_run(seed_value, 3)
		grenadiers += count_kind(4)
		menders += count_kind(5)
	verify(grenadiers >= 4 and menders >= 2, "Deeper floors mix in grenadiers (%d) and menders (%d)" % [grenadiers, menders])
	fresh_run(11, 1)
	verify(count_kind(4) == 0 and count_kind(5) == 0, "B1 keeps the original robots")
	fresh_run(11, 3)
	var pillars = game.interactables.filter(func(o): return o.kind == "pillar")
	verify(pillars.size() >= 2, "The B3 arena has cover pillars (%d)" % pillars.size())
	var index = game.interactables.find(pillars[0])
	game.damage_pillar(index, 200)
	verify(pillars[0].used and not pillars[0].node.visible, "Pillars crumble after enough hits")
	var mender: DiverEnemy = null
	for e in game.enemies:
		if is_instance_valid(e) and e.kind == 5: mender = e
	if mender:
		var hurt: DiverEnemy = null
		for e in game.enemies:
			if is_instance_valid(e) and e.kind in [0, 1, 2, 4] and e != mender:
				hurt = e
				break
		hurt.global_position = mender.global_position + Vector3(2, 0, 0)
		hurt.health = hurt.max_health * 0.5
		var hurt_before = hurt.health
		mender.heal_clock = 0
		mender.mender_repair(0.016)
		verify(hurt.health > hurt_before, "A mender repairs a nearby machine")

	# --- Power Relay (ROOM-01) -----------------------------------------------------
	fresh_run(31336, 2)
	verify(not game.relay.is_empty() and game.relay.rings.size() == 2, "Seeded relay descent has two rings")
	var console = game.interactables[game.relay.console]
	verify(console.kind == "relay", "The relay has a console")
	game.mode = "play"
	game.perform_interact(console, game.player)
	verify(game.relay.active, "The console starts the charge")
	p = game.player
	p.items = {"lens": 5, "spring": 1}
	var stall = game.relay.charge
	p.position = Vector3(9999, 0, 9999)
	game.relay_update(5.0)
	verify(game.relay.charge == stall, "The relay only charges with a digger in the lit ring")
	var guard = 0
	while game.relay.active and guard < 200:
		var ring: Vector3 = game.relay.rings[game.relay.ring]
		p.position = Vector3(ring.x, 0.1, ring.z)
		game.relay_update(1.0)
		guard += 1
	verify(game.relay.done and game.spawned.size() > 0, "Holding the rings finishes the relay; waves arrived (%d)" % game.spawned.size())
	verify(guard == 24, "Relay completes in 24 occupied seconds")
	verify(game.mode == "choice" and str(game.choice_source.get("id", "")) == "relay:2", "Solo, the vault pick opens at once")
	verify(not "lens" in game.choice_items, "The vault skips your most-stacked part")
	game.choose(0)
	var relay_state = game.world_state().relay
	verify(relay_state[3] == true, "A finished relay is saved as done")
	game.remote_relay([DiverNet.M_RELAY, 2, 100.0, 2, 2])
	verify(game.pending_choices.is_empty(), "A repeated finish message grants nothing more")
	for seed_value in [11, 12, 13]:
		var offered = 0
		for d in [1, 2, 3]:
			fresh_run(seed_value, d)
			if not game.relay.is_empty():
				offered += 1
				verify(d == posmod(seed_value, 3) + 1, "Relay floor follows run seed")
		verify(offered == 1, "Exactly one relay offered per three-descent dig")

	game.floor_generation = 35
	game.rng.seed = game.floor_seed(game.depth)
	game.build_floor(true)
	var legacy = game.world_state()
	legacy.erase("floor_generation")
	var old_enemies = game.enemies.size()
	var old_objects = game.interactables.size()
	game.apply_world_state(legacy, true)
	verify(game.floor_generation == 35 and game.relay.rings.size() == 3 and game.enemies.size() == old_enemies and game.interactables.size() == old_objects, "Build35 checkpoint keeps old generation and object IDs")
	for path in ["res://save/variety-test.json", "res://save/variety-test.dat"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("VARIETY_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
