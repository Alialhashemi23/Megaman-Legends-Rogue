extends SceneTree

# Guardian milestones (polish P6): offers, the grant flow, rejoin and effects.
var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MILESTONE_CHECK_FAILED: " + message)

func tick() -> void:
	game._process(0.016)
	await process_frame

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/milestone-test.json"
	game.checkpoint_path = "res://save/milestone-test.dat"
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	game.meta = DiverProgression.fresh()
	await process_frame
	# Catalogue: every milestone has an icon and favours real parts.
	verify(game.MILESTONES.size() == 10, "Ten milestones")
	for id in game.MILESTONES:
		var entry = game.MILESTONES[id]
		verify(game.hud.ICONS.has(entry.icon), "%s has a painted icon" % id)
		for part in entry.affinity: verify(game.ITEMS.has(part), "%s favours a real part" % id)
	game.start_run(31337)
	var p = game.player
	p.set_physics_process(false)
	for e in game.enemies: e.set_physics_process(false)
	# Offers: three distinct, stable for a rejoin, never repeating a taken one.
	var offer = game.milestone_offer(1, p)
	verify(offer.size() == 3 and offer[0] != offer[1] and offer[1] != offer[2] and offer[0] != offer[2], "Three distinct milestones on offer")
	verify(offer == game.milestone_offer(1, p), "The same digger and descent always see the same offer")
	p.milestones = [offer[0]]
	verify(not offer[0] in game.milestone_offer(2, p), "Taken milestones are not offered again")
	p.milestones = []
	# Fitted parts steer the offer: six Storm Coils make Arc Conductor likely.
	p.items = {"coil": 6}
	var arc_seen = 0
	var plain_seen = 0
	for n in 60:
		game.run_id = "weights-%d" % n
		if "arc" in game.milestone_offer(1, p): arc_seen += 1
		p.items = {}
		if "arc" in game.milestone_offer(1, p): plain_seen += 1
		p.items = {"coil": 6}
	verify(arc_seen >= 50 and arc_seen > plain_seen + 15, "Fitted parts weight the offer (%d vs %d of 60)" % [arc_seen, plain_seen])
	p.items = {}
	game.run_id = "flow"
	# Grant flow: the first guardian opens a milestone choice once.
	game.mode = "play"
	game.depth = 1
	game.guardian_dead = true
	await tick()
	verify(game.mode == "choice" and game.choice_kind == "milestone" and game.choice_items.size() == 3, "A fallen guardian opens a milestone choice")
	game.hud.queue_redraw()
	await process_frame
	var picked = game.choice_items[1]
	game.choose(1)
	verify(p.milestones == [picked] and p.milestone_depths == [1] and game.mode == "play", "Choosing takes the milestone and resumes the dig")
	await tick()
	await tick()
	verify(game.mode == "play" and p.milestones.size() == 1, "The same guardian never grants a second milestone")
	game.depth = 3
	await tick()
	verify(game.mode == "play" and p.milestones.size() == 1, "The final guardian keeps its part reward instead")
	# Second guardian, chosen later (co-op deferral keeps the same offer).
	game.depth = 2
	game.mode = "pause"
	game.grant_milestone(2)
	var waiting = game.pending_choices.filter(func(e): return str(e.get("kind", "")) == "milestone")
	verify(waiting.size() == 1 and waiting[0].depth == 2 and waiting[0].items.size() == 3, "A milestone earned behind a menu waits as a pending pick")
	verify(game.milestone_owed_or_taken(2), "A waiting milestone is not granted twice")
	# Rejoin: builds carry milestones and waiting picks; forged ones are dropped.
	var build = game.build_state()
	verify(build.milestones == [picked] and build.milestone_depths == [1], "Builds carry milestones")
	p.milestones = []
	p.milestone_depths = []
	game.pending_choices.clear()
	game.apply_build(build)
	verify(p.milestones == [picked] and p.milestone_depths == [1], "Rejoining restores milestones")
	verify(game.pending_choices.size() == 1 and game.pending_choices[0].kind == "milestone" and game.pending_choices[0].items == waiting[0].items, "Rejoining keeps the waiting milestone offer")
	var forged = build.duplicate(true)
	forged.milestones = ["arc", "nope", "bulwark", "salvo"]
	forged.milestone_depths = [1, 2, 3, 9]
	game.apply_build(forged)
	verify(p.milestones == ["arc", "bulwark"] and p.milestone_depths == [1, 2], "Builds keep at most two known milestones from valid descents")
	verify(game.clean_pending([{"kind": "milestone", "depth": 2, "items": ["arc", "arc", "x"]}]).is_empty(), "Malformed milestone offers are dropped")
	# Effects.
	game.mode = "play"
	game.depth = 1
	p.milestones = ["bulwark", "second_wind"]
	p.second_wind_depth = 0
	p.hp = p.max_hp()
	p.invincible = 0
	p.hurt(20)
	verify(is_equal_approx(p.max_hp() - p.hp, 15.0), "Bulwark Frame softens hits above half Life")
	p.hp = 10
	p.invincible = 0
	p.hurt(50)
	verify(is_equal_approx(p.hp, p.max_hp() * 0.3) and not p.downed and p.second_wind_depth == 1, "Second Wind saves a digger once")
	p.hp = 10
	p.invincible = 0
	p.hurt(50)
	verify(p.hp <= 0, "Second Wind only works once per descent")
	p.hp = p.max_hp()
	p.downed = false
	game.mode = "play"
	p.milestones = ["kinetic"]
	var normal_delay = p.fire_delay()
	p.kinetic_time = 1.0
	verify(is_equal_approx(normal_delay / 1.3, p.fire_delay()), "Kinetic Loader fires faster after a dash")
	p.kinetic_time = 0
	var foes = game.enemies.filter(func(e): return e.kind != 3)
	var target: DiverEnemy = foes[0]
	target.max_health = 1000
	target.health = 1000
	p.milestones = ["salvo"]
	p.items = {}
	target.take_damage(10.0, true, p)
	verify(is_equal_approx(1000 - target.health, 13.5), "Opening Salvo hits healthy machines harder")
	target.health = 500
	target.take_damage(10.0, true, p)
	verify(is_equal_approx(500 - target.health, 10.0), "Opening Salvo fades on worn-down machines")
	p.milestones = ["wildfire"]
	target.burn_time = 0
	target.take_damage(1.0, true, p)
	verify(target.burn_time > 0, "Wildfire Core sets machines burning without Ember Engines")
	var neighbour: DiverEnemy = foes[1]
	neighbour.global_position = target.global_position + Vector3(2, 0, 0)
	neighbour.burn_time = 0
	target.last_source = p
	target.health = 1
	target.take_damage(5.0, true, p)
	verify(neighbour.burn_time > 0, "A burning machine that falls ignites its neighbours")
	p.milestones = ["scavenger"]
	p.hp = 50
	var survivor: DiverEnemy = foes[2]
	survivor.health = 1
	survivor.take_damage(5.0, true, p)
	verify(is_equal_approx(p.hp, 53.0), "Scavenger's Instinct repairs on each defeat")
	# Every dig starts without milestones.
	game.mode = "title"
	game.start_run(4242)
	verify(game.player.milestones.is_empty() and game.player.milestone_depths.is_empty(), "Milestones reset each dig")
	for path in ["res://save/milestone-test.json", "res://save/milestone-test.dat"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MILESTONE_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
