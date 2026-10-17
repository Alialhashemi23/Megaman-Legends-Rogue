extends SceneTree

var game: Node3D
var checks = 0
var failures = 0
var folder = "res://save/reroll-" + DiverAccount.uuid()

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("REROLL_CHECK_FAILED: " + label)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func ready_offer() -> void:
	game.choice_need_release = false
	game.choice_lock_until = 0

func open(kind: String, id: String) -> void:
	game.mode = "play"
	var items = game.milestone_offer(game.depth, game.player) if kind == "milestone" else game.LEVEL_CHOICES if kind == "level" else []
	game.present_or_queue(game.choice_entry(kind, id, game.depth, -1, items))

func key(code: int, down: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	root.push_input(event, true)

func pad(down: bool) -> void:
	var event = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_Y
	event.pressed = down
	root.push_input(event, true)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game = load("res://main.tscn").instantiate()
	game.save_path = folder.path_join("guest.json")
	game.checkpoint_path = folder.path_join("run.dat")
	root.add_child(game)
	game.set_process(false)
	game.account.set_process(false)
	game.account.cache_root = folder.path_join("accounts")
	game.settings.path = folder.path_join("settings.json")
	game.sound.settings_path = folder.path_join("audio.json")
	game.sound.muted = true
	game.solo_checkpoints = true
	game.start_run(71421, 1, "reroll-unique-run")
	game.player.set_physics_process(false)
	await refresh()
	verify(game.build_state().rerolls_left == 1, "A new dig gets one reroll")
	var gameplay_rng = game.rng.state
	open("relic", "cache:1:10")
	await refresh()
	var original = game.choice_items.duplicate()
	verify(game.can_reroll_choice(), "Part offer is eligible")
	verify(not game.reroll_choice() and game.rerolls_left == 1, "Opening input cannot reroll during the arming interval")
	ready_offer()
	verify(game.reroll_choice(), "Fresh deliberate reroll succeeds")
	var rolled = game.choice_items.duplicate()
	verify(game.rerolls_left == 0 and game.choice_source.rerolls == 1, "Budget and one-offer flag are spent together")
	verify(rolled.size() == 3 and rolled[0] != rolled[1] and rolled[0] != rolled[2] and rolled[1] != rolled[2], "Three distinct part cards")
	verify(rolled == game.relic_offer(game.choice_source), "Rerolled cards use the event's deterministic seed")
	verify(game.rng.state == gameplay_rng, "Reroll never advances world RNG")
	ready_offer()
	verify(not game.reroll_choice(), "A second reroll is rejected")
	var snapshot = game.build_state()
	verify(snapshot.pending[0].items == rolled and snapshot.pending[0].rerolls == 1 and snapshot.rerolls_left == 0, "Recovery snapshot contains the new cards and spent budget")
	var cp = game.load_checkpoint()
	verify(not cp.is_empty() and cp.build.rerolls_left == 0 and cp.build.pending[0].items == rolled, "Immediate checkpoint records the spend")
	game.close_choice()
	verify(game.pending_choices[0].items == rolled and game.pending_choices[0].rerolls == 1, "Back preserves the new cards and flag")
	game.open_pending_choice()
	verify(game.choice_items == rolled and not game.can_reroll_choice(), "Reopen is neither a free reroll nor refund")
	game.apply_build(snapshot)
	verify(game.mode == "play" and game.pending_choices[0].items == rolled and game.rerolls_left == 0, "Rejoin restores the spent budget and defers the exact offer")
	game.open_pending_choice()
	ready_offer()
	verify(not game.reroll_choice(), "Rejoin cannot reroll again")
	game.close_choice()
	game.depth = 2
	verify(game.build_state().rerolls_left == 1 and game.rerolls_depth == 2, "Descending refills once")
	verify(game.build_state().rerolls_left == 1, "Repeated snapshots never accumulate tokens")
	game.open_pending_choice()
	ready_offer()
	verify(not game.reroll_choice() and game.rerolls_left == 1, "Previously rerolled offer stays capped on the next floor")
	game.close_choice()
	game.pending_choices.clear()
	open("level", "level:20")
	ready_offer()
	verify(not game.can_reroll_choice() and not game.reroll_choice(), "Level stat picks cannot be rerolled")
	verify(game.rerolls_left == 1, "Level attempts cost nothing")
	game.close_choice()
	game.pending_choices.clear()
	open("milestone", "milestone:2")
	ready_offer()
	verify(game.reroll_choice(), "Milestones can be rerolled")
	verify(game.choice_items == game.milestone_offer(2, game.player, 1), "Milestone reroll is reproducible and uses the same affinity weighting")
	verify(game.choice_items.all(func(id): return id in game.MILESTONES and id not in game.player.milestones), "Milestone cards are valid and unowned")
	game.close_choice()
	game.pending_choices.clear()
	game.depth = 3
	open("relic", "relay:3")
	await refresh()
	ready_offer()
	var relay = game.build_state()
	verify(relay.pending[0].id == "relay:3", "Relay ID survives pending cleaning and snapshots")
	game.apply_build(relay)
	verify(game.pending_choices[0].id == "relay:3", "Relay ID survives rejoin")
	game.open_pending_choice()
	ready_offer()
	verify(game.reroll_choice(), "Relay offers are rerollable")
	var relay_rolled = game.build_state()
	game.apply_build(relay_rolled)
	verify(game.pending_choices[0].items == relay_rolled.pending[0].items and game.pending_choices[0].rerolls == 1, "Relay reroll persists across restore")
	# An old build/offer gets the new bounded entitlement, no extra reward nodes.
	var old = relay_rolled.duplicate(true)
	old.erase("rerolls_left")
	old.erase("rerolls_depth")
	old.pending[0].erase("rerolls")
	game.apply_build(old)
	verify(game.rerolls_left == 1 and game.pending_choices[0].rerolls == 0, "Pre-feature saves migrate with one budget and zero rerolls")
	for value in ["bad", null, [], {}, NAN, INF, 0.5]:
		var bad = relay_rolled.duplicate(true)
		bad.rerolls_left = value
		bad.pending[0].rerolls = value
		game.apply_build(bad)
		verify(game.rerolls_left == 0 and game.pending_choices[0].rerolls == 1, "Malformed counters do not produce a free reroll")
	# Exercise the actual fixed Y and R menu path, with held-press suppression.
	game.pending_choices.clear()
	game.run_id = "fresh-input-run"
	game.depth = 1
	open("relic", "relic:keyboard")
	await refresh()
	ready_offer()
	key(KEY_R, true)
	await refresh()
	verify(game.rerolls_left == 0, "R rerolls the displayed part offer")
	var input_offer = game.choice_items.duplicate()
	key(KEY_R, true)
	await refresh()
	verify(game.choice_items == input_offer, "Held R cannot repeat")
	key(KEY_R, false)
	game.close_choice()
	game.pending_choices.clear()
	game.run_id = "fresh-pad-run"
	open("relic", "relic:pad")
	await refresh()
	ready_offer()
	pad(true)
	await refresh()
	verify(game.rerolls_left == 0 and game.hud.hits.all(func(h): return h.action != "reroll"), "Pad Y spends one token and reroll action becomes disabled")
	pad(true)
	await refresh()
	verify(game.rerolls_left == 0, "Held pad Y does not repeat")
	pad(false)
	# Every layout keeps all three action buttons within the overlay band.
	for handheld in [false, true]:
		game.settings.handheld_ui = handheld
		await refresh()
		for hit in game.hud.hits:
			verify(Rect2(Vector2.ZERO, game.hud.BASE).encloses(hit.rect), "Overlay hit targets remain inside the layout")
	print("REROLL_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
