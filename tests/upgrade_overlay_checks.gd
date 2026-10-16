extends SceneTree

# UI-02 upgrade overlay: same view behind a dim, HUD context kept clear of the
# cards, solo pause, fresh presses between sequential picks, held buttons not
# leaking into play, and offers that never touch gameplay RNG. Isolated saves.

var game: Node3D
var failures = 0
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("OVERLAY_CHECK_FAILED: " + message)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func choice_hits() -> Array:
	return game.hud.hits.filter(func(h): return h.action in ["choice", "choice_later"])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save"))
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/overlay-test-archive.json"
	game.checkpoint_path = "res://save/overlay-test-run.dat"
	root.add_child(game)
	game.settings.path = "res://save/overlay-test-settings.json"
	game.account.cache_root = "res://save/overlay-test-accounts"
	game.sound.muted = true
	game.sound.settings_path = "res://save/overlay-test-audio.json"
	game.meta = DiverProgression.fresh()
	game.start_run(49381)
	await process_frame
	await process_frame
	var p: DiverPlayer = game.player

	# --- Same view, solo pause --------------------------------------------------
	var camera_before = p.camera.global_transform
	var position_before = p.global_position
	var time_before = game.run_time
	var rng_before = game.rng.state
	var cache = game.interactables.find(game.interactables.filter(func(o): return o.kind == "cache")[0])
	game.rooms[game.interactables[cache].room].cleared = true
	game.perform_interact(game.interactables[cache], p)
	verify(game.mode == "choice" and game.choice_kind == "relic", "A solo cache opens the overlay at once")
	for n in 6: await process_frame
	verify(game.run_time == time_before, "Solo time stands still behind the overlay")
	verify(p.camera.global_transform.is_equal_approx(camera_before) and p.global_position.is_equal_approx(position_before), "The camera and digger stay exactly where they were")
	var offer = game.choice_items.duplicate()
	verify(game.rng.state == rng_before, "Rolling the offer doesn't draw on gameplay RNG")
	verify(offer == game.relic_offer(game.choice_source), "The offer is reproducible from its event")
	verify(offer != game.relic_offer({"id": "cache:1:999"}) or offer != game.relic_offer({"id": "cache:2:998"}), "Different caches give different offers")
	game.close_choice()
	game.open_pending_choice()
	verify(game.choice_items == offer and game.rng.state == rng_before, "B and reopen keep the offer and RNG untouched")

	# --- Layout: cards in the clear band at every size --------------------------
	# Life column, team panels, map/scrap, boss bar, buster panel and dash meter.
	var reserved = [Rect2(26, 22, 96, 450), Rect2(28, 486, 268, 236), Rect2(1184, 28, 228, 372), Rect2(440, 120, 560, 118), Rect2(30, 738, 310, 104), Rect2(1230, 754, 178, 128), Rect2(1060, 560, 352, 176)]
	for size in [Vector2i(1440, 900), Vector2i(1280, 720), Vector2i(960, 600), Vector2i(960, 540), Vector2i(1920, 1080)]:
		root.size = size
		await refresh()
		var targets = choice_hits()
		verify(targets.filter(func(h): return h.action == "choice").size() == 4, "Three cards and an apply button at %s" % size)
		for hit in targets:
			verify(Rect2(Vector2.ZERO, game.hud.BASE).encloses(hit.rect), "Overlay targets stay on screen at %s" % size)
			for area in reserved: verify(not hit.rect.intersects(area), "Overlay target %s stays clear of HUD context %s" % [hit.rect, area])
		var cards = targets.filter(func(h): return h.action == "choice").slice(0, 3)
		verify(cards[0].rect.position.y == cards[1].rect.position.y and cards[1].rect.position.x > cards[0].rect.end.x, "Cards sit side by side")
	root.size = Vector2i(1440, 900)
	await refresh()

	# --- Fresh presses ------------------------------------------------------------
	game.choice_lock_until = 0
	Input.action_press("nav_accept")
	game.arm_choice()
	verify(game.choice_need_release and not game.choice_input_ready(), "A held confirm can't pick a newly shown offer")
	var parts_before = p.items.duplicate()
	game.hud.activate("choice", 0)
	verify(p.items == parts_before and game.mode == "choice", "...not even through the apply button")
	Input.action_release("nav_accept")
	await process_frame
	verify(not game.choice_need_release, "Releasing confirm re-arms the offer")
	await create_timer(0.2).timeout
	verify(game.choice_input_ready(), "A fresh press is accepted")

	# --- Held buttons don't leak into play after closing ---------------------------
	Input.action_press("dash")
	verify(game.hud.back() and game.mode == "play" and game.action_guard, "B closes the overlay and holds back gameplay buttons")
	for n in 4: await physics_frame
	verify(p.dash_time <= 0 and game.action_guard, "The B press that closed the overlay doesn't dash")
	Input.action_release("dash")
	await process_frame
	await physics_frame
	verify(not game.action_guard, "Releasing the button returns control")

	# --- Four picks in a row online (levels, parts, milestone) -------------------
	game.finish_run(false)
	game.net.slot = 2
	game.net.host_slot = 1
	game.net.lobby = {"players": [{"slot": 1, "name": "Host", "id": "h"}, {"slot": 2, "name": "Me", "id": "m"}]}
	game.start_run(4242, 2, "overlay-coop")
	await process_frame
	await process_frame
	p = game.player
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, 1, 1])
	p.gain_xp(p.xp_required)
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, 2, 2])
	game.grant_milestone(1)
	verify(game.mode == "play" and game.pending_choices.map(func(e): return e.kind) == ["relic", "level", "relic", "milestone"], "Four picks wait in the order earned")
	verify(game.pending_choices.map(func(e): return e.id) == ["cache:1:1", "level:2", "cache:1:2", "milestone:1"], "Each pick names its event")
	game.game_action("parts")
	var seen = []
	for n in 4:
		await refresh()
		seen.append(game.choice_kind)
		# After the B at pick 3, the reopened overlay counts the last two afresh.
		var expected = [[0, 4], [1, 4], [2, 4], [1, 2]][n]
		verify(game.choice_picks == expected[0] and game.choice_picks + 1 + game.pending_choices.size() == expected[1], "Pick %d is shown in the same overlay with the right count" % (n + 1))
		if n == 2:
			verify(game.hud.back() and game.pending_choices.size() == 2, "B exits mid-sequence and keeps the rest")
			game.game_action("parts")
			await refresh()
			verify(game.choice_picks == 0 and game.pending_choices.size() == 1, "Reopening continues with what's left")
		game.choose(0)
	verify(seen == ["relic", "level", "relic", "milestone"] and game.mode == "play" and game.pending_choices.is_empty(), "All four picks applied once each, then the overlay closes")
	verify(p.milestone_depths == [1] and p.level == 2, "Milestone and level counted once")
	game.grant_milestone(1)
	verify(game.pending_choices.is_empty(), "A taken milestone is never offered again")
	game.finish_run(false)
	verify(game.pending_choices.is_empty(), "Unpicked upgrades expire with the dig")

	game.net.slot = 0
	game.net.host_slot = 0
	game.net.lobby = {}
	for path in [game.save_path, game.checkpoint_path, game.checkpoint_path + ".tmp", "res://save/overlay-test-audio.json", "res://save/overlay-test-settings.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("OVERLAY_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
