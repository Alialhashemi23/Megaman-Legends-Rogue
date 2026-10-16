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

func dpad(button: int) -> void:
	for pressed in [true, false]:
		var event = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
	game.hud.queue_redraw()
	await process_frame
	await process_frame

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
		game.meta.zenny = 5000
		verify(not game.buy_skill(character, "mastery"), "Unlinked nodes cannot be bought")
		for entry in DiverProgression.NODES:
			var wallet = game.meta.zenny
			verify(game.buy_skill(character, entry.id), "Valid node is purchased")
			verify(game.meta.zenny == wallet - entry.cost, "Purchase charges exact price")
			verify(not game.buy_skill(character, entry.id), "Duplicate purchase refused")
		verify(game.item_unlocked(DiverProgression.RESEARCH[character]), "Research expands this digger's pool")
		game.start_run(777)
		p = game.player
		p.set_physics_process(false)
		verify(p.skills.size() == DiverProgression.NODES.size(), "The full grid applies on next run")
		var bonus = DiverProgression.BONUS
		verify(is_equal_approx(p.life_bonus(), bonus.frame * bonus.cell), "Frame and Reserve Cell both raise Life")
		verify(is_equal_approx(p.damage(), p.base_damage * bonus.barrel), "Tuned Barrel raises damage")
		verify(is_equal_approx(p.fire_delay(), [0.25, 0.13, 0.65, 0.75][p.weapon] / (p.fire_multiplier * bonus.mastery * bonus.loader)), "Mastery and Quick Loader both raise attack speed")
		var build = game.build_state()
		p.skills.clear()
		game.apply_build(build)
		verify(p.skills.size() == DiverProgression.NODES.size() and p.weapon == character, "Skills restore through co-op build format")
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
	# Specializations: unlocked on the grid, one equipped per dig, only it applies.
	var spec_keys = []
	for pair in DiverProgression.SPECS:
		verify(pair.size() == 2, "Two specializations per digger")
		for special in pair: spec_keys.append(special.key)
	var unique_keys = {}
	for key in spec_keys: unique_keys[key] = true
	verify(spec_keys.size() == 8 and unique_keys.size() == 8, "Eight distinct specialization effects")
	game.selected_character = 0
	game.mode = "title"
	verify(game.equip_spec(0, "spec_a"), "An owned specialization can be equipped")
	game.start_run(4242)
	var mega = game.player
	mega.set_physics_process(false)
	for e in game.enemies: e.set_physics_process(false)
	verify(mega.spec == "spec_a" and mega.specialization() == "focus", "A dig brings the equipped specialization")
	verify(not game.equip_spec(0, "spec_b"), "Specializations cannot change during a dig")
	var foes = game.enemies.filter(func(e): return e.kind != 3)
	var target: DiverEnemy = foes[0]
	target.max_health = 100000
	target.health = 100000
	var dealt = []
	for k in 7:
		var before_hp = target.health
		target.take_damage(10.0, true, mega)
		dealt.append(before_hp - target.health)
	verify(is_equal_approx(dealt[0], 10.0) and is_equal_approx(dealt[5], 14.0) and is_equal_approx(dealt[6], 14.0), "Focus Lens ramps to +40% on one machine")
	var saved_build = game.build_state()
	verify(saved_build.spec == "spec_a", "Builds carry the specialization for co-op and rejoin")
	mega.spec = ""
	verify(mega.specialization() == "", "Owning both specializations applies neither unless one is equipped")
	game.apply_build(saved_build)
	verify(game.player.spec == "spec_a", "Rejoining restores the exact specialization")
	var forged = saved_build.duplicate(true)
	forged.spec = "spec_b"
	forged.skills = ["frame"]
	game.apply_build(forged)
	verify(game.player.spec == "", "Builds cannot claim an unowned specialization")
	game.apply_build(saved_build)
	# Needle Storm exposes machines for everyone; Field Medic repairs nearby allies.
	var roll = DiverPlayer.new()
	roll.character = 1
	roll.game = game
	roll.is_local = false
	roll.skills = ["frame", "spec_a", "spec_b"]
	roll.spec = "spec_b"
	root.add_child(roll)
	roll.global_position = mega.global_position
	for k in 6: target.take_damage(10.0, true, roll)
	verify(target.exposed > 0, "Every sixth Needle Storm hit exposes a machine")
	var exposed_before = target.health
	target.take_damage(10.0, false, mega)
	verify(is_equal_approx(exposed_before - target.health, 12.0), "Exposed machines take +20% from everyone")
	roll.storm_heat = 0.3
	var storm_delay = roll.fire_delay()
	roll.storm_heat = 0.0
	verify(is_equal_approx(storm_delay * 1.3, roll.fire_delay()), "Needle Storm heat raises attack speed by up to 30%")
	game.remote_players[5] = roll
	verify(not mega.medic_nearby(), "Needle Storm Roll does not repair")
	roll.spec = "spec_a"
	verify(mega.medic_nearby(), "A nearby Field Medic Roll repairs teammates")
	roll.global_position = mega.global_position + Vector3(9, 0, 0)
	verify(not mega.medic_nearby(), "Field Medic only reaches teammates within 6 m")
	game.remote_players.erase(5)
	# Ricochet Coil bounces a hit to the nearest other machine in sight.
	mega.spec = "spec_b"
	var second: DiverEnemy = foes[1]
	target.global_position = mega.global_position + Vector3(0, 0, -3)
	second.global_position = mega.global_position + Vector3(2.5, 0, -3)
	var shot = DiverBolt.new()
	shot.game = game
	shot.source = mega
	shot.amount = 10.0
	game.world.add_child(shot)
	shot.global_position = target.global_position + Vector3.UP
	var bolts_before = game.world.get_children().filter(func(n): return n is DiverBolt).size()
	shot.ricochet(target, target.global_position + Vector3.UP)
	var bounces = game.world.get_children().filter(func(n): return n is DiverBolt and n.bounced)
	verify(bounces.size() == 1 and is_equal_approx(bounces[0].amount, 6.0) and game.world.get_children().filter(func(n): return n is DiverBolt).size() == bolts_before + 1, "Ricochet Coil bounces once for 60% damage")
	# Tron's and Servbot's specializations change their blasts.
	var tron = DiverPlayer.new()
	tron.character = 2
	tron.skills = ["frame", "salvage", "ability", "spec_a", "spec_b"]
	tron.spec = "spec_b"
	var blast = DiverBolt.new()
	blast.source = tron
	verify(is_equal_approx(blast.splash_radius(), DiverProgression.BONUS.splash_radius + 1.5), "Wide Barrage widens Tron's blasts")
	tron.spec = "spec_a"
	verify(is_equal_approx(blast.splash_radius(), DiverProgression.BONUS.splash_radius) and blast.spec() == "breaker", "Siege Breaker keeps the normal radius")
	var servbot = DiverPlayer.new()
	servbot.character = 3
	servbot.skills = ["frame", "spec_a"]
	servbot.spec = "spec_a"
	var guardian = DiverEnemy.new()
	guardian.kind = 3
	blast.source = servbot
	verify(is_equal_approx(blast.guardian_bonus(guardian), 1.25) and is_equal_approx(blast.guardian_bonus(target), 1.0), "Demolition Charge hits guardians harder")
	for node in [roll, shot]: node.queue_free()
	for node in [tron, blast, servbot, guardian]: node.free()
	game.mode = "title"
	verify(game.equip_spec(0, ""), "Unequipping restores the default loadout between digs")
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
	# Profile 2 trees keep every purchase under the grid rules (no refunds, no losses).
	var old_profile = {"version": 2, "zenny": 55, "trees": {"0": ["frame", "mobility", "salvage", "ability", "mastery"], "1": ["frame", "salvage"]}}
	var migrated_grid = DiverProgression.validate(old_profile)
	verify(migrated_grid.version == DiverProgression.VERSION and migrated_grid.zenny == 55 and migrated_grid.trees == old_profile.trees, "Old Workshop purchases carry into the grid unchanged")
	verify(DiverProgression.validate({"version": 3, "trees": {"0": ["frame", "barrel"]}}).is_empty(), "Grid trees must stay connected")
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
	var tabs = DiverCharacter.COUNT
	var grid_count = DiverProgression.NODES.size()
	verify(game.mode == "workshop" and game.hud.hits.size() == tabs + grid_count + 3 + 3, "Workshop provides diggers, grid nodes, view controls and navigation")
	var first = game.hud.workshop_first_node()
	verify(game.hud.focus_index == tabs + first, "Workshop entry focuses the first useful node")
	verify(DiverProgression.can_buy(game.meta, game.hud.workshop_character, DiverProgression.NODES[first].id), "Focused node is affordable when one is")
	var start_character = game.hud.workshop_character
	var shoulder = InputEventJoypadButton.new()
	shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER
	shoulder.pressed = true
	root.push_input(shoulder, true)
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	verify(game.hud.workshop_character == wrapi(start_character - 1, 0, tabs), "LB switches Workshop digger")
	verify(game.hud.focus_index == tabs + game.hud.workshop_first_node(), "Switching digger refocuses its grid")
	game.hud.select_workshop_character(start_character)
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	# Directional moves follow the grid layout from the start node.
	var index_of = func(id: String) -> int:
		for i in grid_count:
			if DiverProgression.NODES[i].id == id: return i
		return -1
	var focused = func() -> String:
		var hit = game.hud.hits[game.hud.focus_index]
		return DiverProgression.NODES[hit.value].id if hit.action == "grid_node" else hit.action
	game.hud.focus_index = tabs + index_of.call("frame")
	var route = [[JOY_BUTTON_DPAD_RIGHT, "salvage"], [JOY_BUTTON_DPAD_LEFT, "frame"], [JOY_BUTTON_DPAD_LEFT, "mobility"], [JOY_BUTTON_DPAD_UP, "servos"], [JOY_BUTTON_DPAD_UP, "tree_character"], [JOY_BUTTON_DPAD_DOWN, "grid_node"]]
	for step in route:
		await dpad(step[0])
		verify(focused.call() == step[1] or (step[1] == "grid_node" and game.hud.hits[game.hud.focus_index].action == "grid_node"), "D-pad reaches %s (got %s)" % [step[1], focused.call()])
	game.hud.focus_index = tabs + index_of.call("frame")
	for step in [[JOY_BUTTON_DPAD_DOWN, "mastery"], [JOY_BUTTON_DPAD_DOWN, "cell"], [JOY_BUTTON_DPAD_DOWN, "spec_a"], [JOY_BUTTON_DPAD_DOWN, "start"], [JOY_BUTTON_DPAD_LEFT, "save_codes"], [JOY_BUTTON_DPAD_UP, "spec_a"], [JOY_BUTTON_DPAD_RIGHT, "spec_b"]]:
		await dpad(step[0])
		verify(focused.call() == step[1], "D-pad reaches %s (got %s)" % [step[1], focused.call()])
	verify(game.hud.workshop_character == start_character, "Moving around the grid never switches digger")
	# Zoom keeps the focused node on screen; recenter restores the overview.
	await dpad(JOY_BUTTON_X)
	verify(game.hud.grid_zoom_step == 2 and game.hud.GRID_RECT.has_point(game.hud.grid_point(game.hud.focus_index - tabs)), "Zooming in keeps the focused node visible")
	game.hud.activate("grid_center")
	verify(game.hud.grid_zoom_step == 1 and game.hud.grid_center == Vector2(0, 2.4), "Recenter restores the overview")
	# Accepting a node buys it only when it is linked and affordable.
	var wallet = game.meta.zenny
	var probe = 3 - start_character if start_character != 3 else 0
	game.hud.select_workshop_character(probe)
	game.meta.trees.erase(str(probe))
	game.meta.zenny = 1000
	game.hud.activate("grid_node", index_of.call("mobility"))
	verify(not "mobility" in DiverProgression.owned(game.meta, probe) and game.hud.workshop_message.begins_with("Buy a linked"), "Unlinked node explains the missing link")
	game.hud.activate("grid_node", index_of.call("frame"))
	game.hud.activate("grid_node", index_of.call("mobility"))
	verify(DiverProgression.owned(game.meta, probe) == ["frame", "mobility"] and game.meta.zenny == 760, "Linked nodes are bought from the grid")
	game.meta.zenny = 0
	game.hud.select_workshop_character(start_character)
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	var fitted = DiverProgression.owned(game.meta, start_character)
	var shown = game.hud.focus_index - tabs
	verify(shown >= 0 and shown < grid_count and (not DiverProgression.NODES[shown].id in fitted or fitted.size() == grid_count), "Unaffordable grid focuses the next unfitted node")
	game.meta.zenny = wallet
	# Title account copy ignores stale profile requests from an old generation.
	var account = game.account
	var saved_requests = account.requests
	account.requests = [{"path": "/api/v1/profile", "generation": account.generation - 1}]
	verify(game.hud.title_account_copy().label.begins_with("Guest") or account.state != "guest", "Stale request does not show an account check")
	account.requests = [{"path": "/api/v1/profile", "generation": account.generation}]
	verify(game.hud.title_account_copy().label == "Checking account…" or account.state != "guest", "Current profile request shows an account check")
	account.requests = saved_requests
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
