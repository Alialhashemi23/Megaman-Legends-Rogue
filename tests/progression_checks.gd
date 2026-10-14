extends SceneTree

var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PROGRESSION_CHECK_FAILED: " + message)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/progression-test.json"
	game.checkpoint_path = "res://save/progression-test.dat"
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	game.meta = DiverProgression.fresh()
	game.smoke_test = true
	await process_frame
	# Old profiles keep every previously earned part, without free currency.
	var old = {"kills": 57, "runs": 4, "wins": 1, "deepest": 3, "discovered": {"coil": true}, "best_time": 95.5}
	var migrated = DiverProgression.validate(old)
	verify(migrated.kills == 57 and migrated.zenny == 0 and migrated.discovered.coil, "Old records and discoveries migrate")
	verify(migrated.legacy_unlocks.size() == 7, "All formerly earned parts survive higher gates")
	game.meta = migrated
	verify(game.pool().size() == game.ITEMS.size(), "Legacy pool is preserved")
	game.meta = DiverProgression.fresh()
	verify(game.pool().size() == 6, "New profiles begin with six parts")
	verify(DiverProgression.reward(3, 3, 100) == 275, "Depth, guardians and scrap each contribute Zenny")
	# Every character has a unique attack, silhouette and affordable tree path.
	for character in 4:
		game.selected_character = character
		game.start_run(49381)
		var p = game.player
		p.set_physics_process(false)
		verify(p.weapon == character, "Signature weapon follows character %d" % character)
		verify(is_equal_approx(p.hp, p.max_hp()), "Fresh Life fits character %d" % character)
		var collision = p.get_child(0) as CollisionShape3D
		verify(is_equal_approx(collision.shape.height, 1.05 if character == 3 else 1.8), "Collision height matches model")
		verify(is_equal_approx(p.max_hp(), 65 if character == 3 else 100), "Servbot is fragile")
		var life_before = p.max_hp()
		p.base_health += 20
		verify(is_equal_approx(p.max_hp(), life_before + 20), "Run Life upgrades retain their full value")
		p.base_health -= 20
		verify(p.speed() > 7.0 if character == 3 else is_equal_approx(p.speed(), 6.2), "Servbot is fast")
		p.shoot()
		var bolts = game.world.find_children("*", "Node3D", false, false).filter(func(n): return n is DiverBolt)
		verify(bolts.size() == 1 and bolts[0].bomb == (character == 3), "Signature projectile type")
		if character == 3:
			var bomb = bolts[0]
			var before = bomb.flight_velocity.y
			bomb._physics_process(0.05)
			verify(bomb.flight_velocity.y < before, "Bomb follows gravity")
		game.mode = "workshop"
		game.meta.zenny = 2000
		verify(not game.buy_skill(character, "mastery"), "Mastery requires both branches")
		for entry in DiverProgression.NODES:
			var wallet = game.meta.zenny
			verify(game.buy_skill(character, entry.id), "Valid node is purchased")
			verify(game.meta.zenny == wallet - entry.cost, "Purchase charges exact price")
			verify(not game.buy_skill(character, entry.id), "Duplicate purchase refused")
		verify(game.item_unlocked(DiverProgression.RESEARCH[character]), "Research expands this digger's pool")
		game.start_run(777)
		p = game.player
		p.set_physics_process(false)
		verify(p.skills.size() == 5, "Purchased skills apply on next run")
		var build = game.build_state()
		p.skills.clear()
		game.apply_build(build)
		verify(p.skills.size() == 5 and p.weapon == character, "Skills restore through co-op build format")
		verify(not game.buy_skill(character, "frame"), "Purchases blocked during a dig")
	# Roll's support is decided on the downed player's client.
	game.player.downed = true
	game.player.revive = 0
	var helper = DiverPlayer.new()
	helper.character = 1
	helper.game = game
	helper.is_local = false
	helper.display_name = "Roll"
	root.add_child(helper)
	helper.position = game.player.position
	game.remote_players[4] = helper
	game.player.update_revive(1.0)
	verify(is_equal_approx(game.player.revive, 0.8), "Roll revives twice as fast")
	game.remote_players.clear()
	helper.free()
	# Real disk round trip: purchases and codes save immediately and atomically.
	game.mode = "workshop"
	game.smoke_test = false
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 500
	verify(game.buy_skill(0, "frame"), "Purchase writes real isolated profile")
	game.meta = DiverProgression.fresh()
	game.load_meta()
	verify(game.meta.zenny == 400 and "frame" in DiverProgression.owned(game.meta, 0), "Purchase survives reload")
	var code = DiverProgression.encode(game.meta)
	verify(DiverProgression.decode(code) == game.meta, "Save code round trip")
	verify(DiverProgression.decode(code + "x").is_empty(), "Damaged checksum refused")
	verify(DiverProgression.decode("RD2.@@@@.x").is_empty(), "Damaged payload refused")
	verify(DiverProgression.decode("x".repeat(32769)).is_empty(), "Oversized code refused")
	for key in ["zenny", "kills", "runs"]:
		var bad = game.meta.duplicate(true)
		bad[key] = -1
		verify(DiverProgression.validate(bad).is_empty(), "Negative counters refused")
		bad[key] = "100"
		verify(DiverProgression.validate(bad).is_empty(), "Wrong counter types refused")
	var bad = game.meta.duplicate(true)
	bad.trees = {"0": ["mastery"]}
	verify(DiverProgression.validate(bad).is_empty(), "Invalid prerequisites refused")
	var before = game.meta.duplicate(true)
	verify(not game.import_progress(bad) and game.meta == before, "Rejected import leaves profile intact")
	var imported = before.duplicate(true)
	imported.zenny = 1234
	verify(game.import_progress(imported), "Valid import saves")
	game.meta = DiverProgression.fresh()
	game.load_meta()
	verify(game.meta.zenny == 1234, "Imported progress survives reload")
	# A repeated end event cannot mint currency twice.
	game.smoke_test = true
	game.start_run(123)
	game.depth = 2
	game.guardian_dead = true
	game.scrap = 50
	game.finish_run(false)
	var balance = game.meta.zenny
	game.mode = "workshop"
	game.finish_run(false)
	verify(game.meta.zenny == balance and game.zenny_earned == 180, "Run reward is recorded once")
	# Verify the actual new menus with keyboard focus, not just drawing helpers.
	game.mode = "end"
	game.hud.activate("workshop")
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	verify(game.mode == "workshop" and game.hud.hits.size() == 12, "Workshop provides diggers, nodes and navigation")
	game.hud.activate("save_codes")
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	verify(game.hud.save_edit.visible, "Save field is visible")
	game.hud.save_edit.grab_focus()
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	verify(game.hud.save_edit.has_focus(), "Save field retains focus across redraws")
	game.hud.save_edit.text = code
	game.hud.activate("check_import")
	verify(not game.hud.pending_import.is_empty(), "Import previews progress before replacing it")
	verify(game.hud.back() and game.mode == "workshop", "Back returns to workshop")
	verify(game.hud.back() and game.mode == "end", "Workshop returns to results")
	for path in ["res://save/progression-test.json", "res://save/progression-test.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PROGRESSION_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
