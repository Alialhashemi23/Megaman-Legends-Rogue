extends SceneTree

# Run persistence: checkpoints restore the exact dig and build, survive
# corrupted or half-written files, retire cleanly, and malformed network
# messages are ignored without errors. Uses isolated test save paths.

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

func alive() -> int:
	var n = 0
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead: n += 1
	return n

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save"))
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/resume-test-archive.json"
	game.checkpoint_path = "res://save/resume-test-run.dat"
	root.add_child(game)
	game.sound.muted = true
	game.sound.settings_path = "res://save/resume-test-audio.json"
	game.save_path = "res://save/resume-test-archive.json"
	game.checkpoint_path = "res://save/resume-test-run.dat"
	# Solo digs aren't saved by default; the restore path is the one online rejoins use.
	game.solo_checkpoints = true
	game.clear_checkpoint()
	game.meta = DiverProgression.fresh()
	await process_frame

	# Play a little: parts, a level, damage, kills, salvage, a descent and an open choice.
	game.selected_character = 1
	game.start_run(49381)
	verify(FileAccess.file_exists(game.checkpoint_path), "Starting a dig writes a checkpoint")
	var p: DiverPlayer = game.player
	p.add_item("lens")
	p.add_item("lens")
	p.add_item("coil")
	p.base_damage += 3
	p.level = 3
	p.xp = 7
	p.xp_required = 28
	p.invincible = 0
	p.hurt(30)
	for i in 3: game.enemies[i + 2].take_damage(1000000, false)
	game.enemies[8].take_damage(5, false)
	game.scrap = 41
	game.guardian_dead = true
	game.descend()
	verify(game.depth == 2, "Descended for the test")
	game.enemies[1].take_damage(1000000, false)
	game.enemies[4].take_damage(7, false)
	game.interactables[2].used = true
	game.use_interactable(game.interactables[2])
	game.drop_pickup(Vector3(3, 0.5, 2), "scrap", 6)
	game.open_relic_choice()
	var offered = game.choice_items.duplicate()
	game.open_level_choice()
	verify(game.mode == "choice" and game.pending_choices.size() == 1 and game.pending_choices[0].kind == "level", "A level-up earned while choosing waits behind the open pick")
	await process_frame
	game.save_checkpoint()
	var before = {"depth": game.depth, "alive": alive(), "scrap": game.scrap, "kills": game.kills, "items": p.items.duplicate(), "level": p.level, "xp": p.xp, "hp": p.hp, "damage": p.damage(), "character": p.character, "seed": game.run_seed, "run_id": game.run_id, "used": game.interactables[2].used, "health4": game.enemies[4].health, "pickups": game.pickups.size(), "exit": game.exit_room}

	# A brand-new session: back to the title, then Continue Dig.
	game.mode = "title"
	game.build_floor(false)
	game.run_seed = 0
	game.saved_dig = game.load_checkpoint()
	verify(not game.saved_dig.is_empty() and not game.saved_dig.online, "Title finds the saved solo dig")
	game.continue_saved_dig()
	await process_frame
	p = game.player
	verify(game.depth == before.depth and game.run_seed == before.seed and game.run_id == before.run_id, "Same dig and descent restored")
	verify(game.exit_room == before.exit, "Same floor layout restored")
	verify(alive() == before.alive, "Defeated robots stay defeated (%d vs %d)" % [alive(), before.alive])
	verify(is_equal_approx(game.enemies[4].health, before.health4), "Damaged robots keep their damage")
	verify(game.scrap == before.scrap and game.kills == before.kills, "Scrap and machine count restored")
	verify(p.items == before.items, "Fitted parts restored")
	verify(p.level == before.level and p.xp == before.xp, "Level and experience restored")
	verify(is_equal_approx(p.hp, before.hp), "Life restored without free healing")
	verify(is_equal_approx(p.damage(), before.damage), "Buster upgrades restored")
	verify(p.character == before.character, "Selected digger restored")
	verify(game.interactables[2].used == before.used, "Used salvage stays used")
	verify(game.pickups.size() == before.pickups, "Dropped pickups restored")
	verify(game.mode == "play", "A restored dig never reopens the pick overlay by itself")
	verify(game.pending_choices.size() == 2 and game.pending_choices[0].kind == "relic" and game.pending_choices[0].items == offered, "The unfinished part pick waits first, with the same options")
	verify(game.pending_choices[1].kind == "level" and game.pending_choices[1].items == game.LEVEL_CHOICES, "The queued level-up survives as a level pick")
	verify(game.open_pending_choice() and game.choice_kind == "relic" and game.choice_items == offered, "Opening shows the restored part offer unchanged")
	game.choose(0)
	verify(game.mode == "choice" and game.choice_kind == "level", "The level pick follows in the same overlay")
	game.choose(0)
	verify(game.mode == "play" and game.pending_choices.is_empty(), "Both picks are spent once")

	# Checkpoints from the previous build: an open choice plus a queue of screens.
	var legacy = game.build_state()
	legacy.erase("pending")
	legacy.choice = {"kind": "relic", "items": ["lens", "coil", "echo"], "depth": 2, "cache": 5, "sourced": true}
	legacy.queue = ["level", "level"]
	legacy.pending = [{"depth": 2, "cache": 6, "items": []}, {"kind": "milestone", "depth": 1, "items": ["arc", "bulwark", "salvo"]}]
	game.apply_build(legacy)
	var kinds = game.pending_choices.map(func(e): return e.kind)
	verify(kinds == ["relic", "relic", "milestone", "level", "level"], "Older open/queued/waiting picks all load as queue entries (%s)" % str(kinds))
	verify(game.pending_choices[0].items == ["lens", "coil", "echo"] and game.choice_waiting(5), "The old open part pick keeps its cache and its offer")
	verify(game.pending_choices[3].id != game.pending_choices[4].id, "Two old queued level-ups stay two picks")
	game.pending_choices.clear()

	# Damaged files never break the title screen; a leftover temp file is used as backup.
	var f = FileAccess.open(game.checkpoint_path, FileAccess.WRITE)
	f.store_string("not a checkpoint")
	f.close()
	verify(game.load_checkpoint().is_empty(), "Corrupted checkpoint is ignored")
	game.save_checkpoint()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(game.checkpoint_path), ProjectSettings.globalize_path(game.checkpoint_path + ".tmp"))
	verify(not game.load_checkpoint().is_empty(), "Half-finished save falls back to the temp copy")

	# Ending a dig clears its checkpoint; abandoning one still counts its machines.
	game.finish_run(false)
	verify(not FileAccess.file_exists(game.checkpoint_path) and not FileAccess.file_exists(game.checkpoint_path + ".tmp"), "Finished digs leave no checkpoint")
	var kills_before = int(game.meta.kills)
	game.start_run(777)
	game.kills = 9
	game.save_checkpoint()
	game.mode = "title"
	game.start_run(778)
	verify(int(game.meta.kills) == kills_before + 9, "Replacing a saved dig still records its machines")
	game.finish_run(false)

	# Garbage from the network is ignored.
	game.net.slot = 2
	game.net.host_slot = 1
	game.net.lobby = {"players": [{"slot": 1, "name": "Host", "id": "h"}, {"slot": 2, "name": "Me", "id": "m"}]}
	game.start_run(4242, 2, "fuzz-run")
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var samples = [null, 3, "x", Vector3.ONE, PackedFloat32Array([1, 2]), {"a": 1}, [], true, -1, 1e9]
	for n in 400:
		var m = [rng.randi_range(-2, DiverNet.M_PING + 2)]
		for k in rng.randi_range(0, 9): m.append(samples[rng.randi_range(0, samples.size() - 1)])
		game.net_message(3, m)
	verify(game.malformed_messages > 300, "Malformed messages are rejected (%d)" % game.malformed_messages)
	verify(game.mode == "play" and game.depth == 1, "The dig carries on after garbage messages")
	game.net.slot = 0
	game.net.lobby = {}
	game.finish_run(false)

	for path in [game.save_path, game.checkpoint_path, game.checkpoint_path + ".tmp", "res://save/resume-test-audio.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESUME_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
