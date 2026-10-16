extends SceneTree

# Co-op feedback (roadmap phase 1, UI-02): the party shares one map, every
# online pick (cache, level, milestone) waits until the digger opens it with the
# parts button, picks run in sequence in one overlay, B puts them back without
# rerolling, and everything survives a rejoin. Uses isolated test save paths.

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

func caches() -> Array:
	var result = []
	for i in game.interactables.size():
		if game.interactables[i].kind == "cache": result.append(i)
	return result

func draw_frames() -> void:
	for n in 3:
		game.hud.queue_redraw()
		await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save"))
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/coop-test-archive.json"
	game.checkpoint_path = "res://save/coop-test-run.dat"
	root.add_child(game)
	game.sound.muted = true
	game.sound.settings_path = "res://save/coop-test-audio.json"
	game.save_path = "res://save/coop-test-archive.json"
	game.checkpoint_path = "res://save/coop-test-run.dat"
	game.meta = DiverProgression.fresh()
	await process_frame

	# Join as a guest (slot 2) in a lobby hosted by slot 1, with a teammate in slot 3.
	game.net.slot = 2
	game.net.host_slot = 1
	game.net.lobby = {"players": [{"slot": 1, "name": "Host", "id": "h"}, {"slot": 2, "name": "Me", "id": "m"}, {"slot": 3, "name": "Mate", "id": "t"}]}
	game.start_run(4242, 3, "coop-feedback")
	await process_frame
	verify(game.mode == "play", "Guest is in the dig")

	# --- Shared map -------------------------------------------------------------
	var far = -1
	for i in game.rooms.size():
		if not game.rooms[i].visited and game.rooms[i].kind != "hall" and i != game.exit_room:
			far = i
			break
	verify(far > 0, "Found an unexplored room")
	game.net_message(3, [DiverNet.M_VISITED, game.depth + 1, far])
	verify(not game.rooms[far].visited, "A reveal for another descent is ignored")
	game.net_message(3, [DiverNet.M_VISITED, game.depth, 999])
	game.net_message(3, [DiverNet.M_VISITED, game.depth, -4])
	verify(game.mode == "play", "Out-of-range reveals are ignored")
	game.net_message(3, [DiverNet.M_VISITED, game.depth, far])
	verify(game.rooms[far].visited, "A teammate's explored room appears on this map")
	verify(not game.rooms[far].entered, "...but its arrival banner still waits for this digger")
	game.message = ""
	game.player.position = game.rooms[far].center
	game.update_world(0.016)
	verify(game.current_room == far and game.rooms[far].entered, "Walking in marks the room as entered")
	verify(game.message != "", "The chamber still announces itself on first arrival")
	var revealed = game.world_state().visited
	verify(far in revealed, "Shared reveals are part of the world state late joiners receive")
	game.net_message(1, [DiverNet.M_CLEARED, game.depth, far])
	verify(game.rooms[far].cleared, "Cleared rooms still come from the host")

	# --- Waiting picks (UI-02: every online pick waits until opened) -----------
	var list = caches()
	verify(list.size() >= 2, "Floor has at least two caches (%d)" % list.size())
	var mate_cache: int = list[0]
	var own_cache: int = list[1]
	var before_malformed = game.malformed_messages
	game.net_message(1, [DiverNet.M_CHOICE])
	verify(game.malformed_messages == before_malformed + 1 and game.pending_choices.is_empty(), "An old-format cache message is rejected")
	game.net_message(3, [DiverNet.M_CHOICE, game.depth, mate_cache, 3])
	verify(game.pending_choices.is_empty(), "Only the host can hand out cache picks")
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, mate_cache, 3])
	verify(game.mode == "play", "A teammate's cache doesn't open the choice screen")
	verify(game.pending_choices.size() == 1 and game.choice_waiting(mate_cache), "...it leaves a pick waiting from that cache")
	verify(game.message == "PART CHOICE WAITING", "...and says so")
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, mate_cache, 3])
	verify(game.pending_choices.size() == 1, "A repeated cache message never queues a second pick")
	await draw_frames()

	# Opening your own cache queues too: nothing takes over the screen online.
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, own_cache, 2])
	verify(game.mode == "play" and game.pending_choices.size() == 2 and game.choice_waiting(own_cache), "The digger who opened a cache gets a waiting pick")
	verify(game.pending_choices.all(func(e): return e.kind == "relic" and e.items.is_empty()), "Waiting part picks aren't rolled until they're shown")

	# The parts button opens the overlay; the dig keeps running behind it.
	verify(game.game_action("parts") and game.mode == "choice", "The parts button opens the waiting picks")
	# The harness has no socket; with a live connection the dig keeps running.
	game.net.status = "online"
	verify(game.world_running(), "Online picks don't pause the dig")
	game.net.status = "offline"
	verify(int(game.choice_source.cache) == mate_cache and game.choice_picks == 0, "The oldest pick comes first")
	verify(not game.choice_input_ready(), "A just-opened offer ignores input for a moment")
	var offered = game.choice_items.duplicate()
	await draw_frames()
	verify(game.hud.hits.filter(func(h): return h.action == "choice").size() >= 3, "Three cards are clickable")
	verify(game.hud.back() and game.mode == "play" and game.pending_choices.size() == 2, "B closes the overlay and keeps every pick waiting")
	verify(game.action_guard, "Buttons held while closing can't fire or dash until released")
	verify(game.pending_choices[0].items == offered, "...with the same three parts")
	verify(game.game_action("parts") and game.choice_items == offered, "Reopening doesn't reroll the offer")
	verify(game.game_action("parts") and game.mode == "play", "The parts button closes it again too")

	# Damage lands while choosing and never closes the overlay.
	game.game_action("parts")
	var hp_before = game.player.hp
	game.player.invincible = 0
	game.net.status = "online"
	game.player.hurt(10)
	game.net.status = "offline"
	verify(game.player.hp < hp_before and game.mode == "choice", "A hit while choosing hurts but leaves the overlay open")

	# Sequential picks in one overlay, each needing a fresh press.
	await create_timer(0.2).timeout
	verify(game.choice_input_ready(), "The offer accepts a press once settled")
	var items_before = game.player.items.duplicate()
	game.hud.activate("choice", 0)
	verify(game.player.count(offered[0]) == int(items_before.get(offered[0], 0)) + 1, "Choosing fits the part")
	verify(game.mode == "choice" and game.choice_picks == 1 and int(game.choice_source.cache) == own_cache, "The next waiting pick follows in the same overlay")
	var parts_count = game.player.items.values().reduce(func(a, b): return a + b, 0)
	game.hud.activate("choice", 0)
	verify(game.player.items.values().reduce(func(a, b): return a + b, 0) == parts_count, "A second press right away doesn't pick again")
	verify(not game.choice_waiting(mate_cache) and game.choice_waiting(own_cache), "Choosing settles that cache's pick only")
	await draw_frames()

	# --- Rejoin restores the exact picks without reopening ---------------------
	var own_offer = game.choice_items.duplicate()
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, mate_cache + 100, 3])
	verify(game.mode == "choice" and game.pending_choices.size() == 1, "A new teammate cache while choosing waits too")
	var build = game.build_state()
	game.pending_choices.clear()
	game.choice_source = {}
	game.apply_build(build)
	verify(game.mode == "play", "A rejoin doesn't force the overlay open")
	verify(game.pending_choices.size() == 2 and game.pending_choices[0].items == own_offer and int(game.pending_choices[0].cache) == own_cache, "The open pick comes back first with the same offer")
	verify(game.choice_waiting(mate_cache + 100), "Waiting picks come back after a rejoin")
	var dirty = build.duplicate(true)
	dirty.pending = [5, "x", {"depth": "nope"}, {"depth": 2, "cache": 3, "items": ["lens", "bogus", "coil"]}, {"depth": 1, "cache": 4, "items": ["lens", "coil", "echo"]}, {"depth": 1, "cache": 4, "items": ["spring", "coil", "echo"]}, {"kind": "level", "items": ["lens", "coil", "echo"]}, {"kind": "bogus", "items": []}]
	game.apply_build(dirty)
	verify(game.pending_choices.size() == 4, "Malformed or duplicate waiting picks are dropped (%d kept)" % game.pending_choices.size())
	verify(game.pending_choices[1].items.is_empty() and game.pending_choices[2].items == ["lens", "coil", "echo"], "Invalid offers are rerolled; valid ones are kept")
	verify(game.pending_choices[3].kind == "level" and game.pending_choices[3].items == game.LEVEL_CHOICES, "A level pick is never read as a part offer")
	game.pending_choices.clear()
	for n in 70: game.net_message(1, [DiverNet.M_CHOICE, game.depth, 200 + n, 3])
	verify(game.pending_choices.size() == game.MAX_PENDING and game.message == "UPGRADES FULL", "A full queue is capped and announced, never silent")
	game.pending_choices.clear()

	# Levels queue online with a short cue instead of a screen.
	var level_before = game.player.level
	game.player.gain_xp(game.player.xp_required)
	verify(game.mode == "play" and game.player.level == level_before + 1, "An online level-up doesn't open a screen")
	verify(game.pending_choices.size() == 1 and game.pending_choices[0].kind == "level" and game.message == "LEVEL UP!", "...it waits as a level pick and says so")

	# Going down closes the overlay; the pick waits for the revive.
	game.game_action("parts")
	game.player.hp = 1
	game.player.invincible = 0
	game.net.status = "online"
	game.player.hurt(50)
	game.net.status = "offline"
	verify(game.player.downed and game.mode == "play" and game.pending_choices.size() == 1, "Downed closes the overlay and keeps the pick")
	verify(not game.open_pending_choice(), "Picks can't be opened while down")
	game.player.revive_now(0.5)
	verify(game.mode == "play" and game.open_pending_choice() and game.choice_kind == "level", "After a revive the pick waits until opened")
	var health_before = game.player.base_health
	game.choose(1)
	verify(game.player.base_health == health_before + 20 and game.mode == "play", "The level pick applies once")

	# --- Host side: every digger's pick waits, the host's too ------------------
	game.finish_run(false)
	game.net.slot = 1
	game.net.host_slot = 1
	game.start_run(5151, 2, "coop-host")
	await process_frame
	var mate = game.create_remote_player(3)
	list = caches()
	var cache_a: Dictionary = game.interactables[list[0]]
	var cache_b: Dictionary = game.interactables[list[1]]
	game.rooms[cache_a.room].cleared = true
	game.rooms[cache_b.room].cleared = true
	game.scrap = 500
	game.perform_interact(cache_a, mate)
	verify(cache_a.used and game.mode == "play" and game.choice_waiting(list[0]), "Host waits when a guest opens a cache")
	game.perform_interact(cache_b, game.player)
	verify(game.mode == "play" and game.choice_waiting(list[1]), "The host's own cache pick waits too")
	verify(game.open_pending_choice() and int(game.choice_source.cache) == list[0], "Picks open in the order they were earned")
	game.choose(1)
	game.choose(1)
	verify(game.mode == "play" and game.pending_choices.is_empty(), "Both host picks spent in one overlay")
	await draw_frames()

	# --- Solo: a pick opens at once and pauses; B still steps out ---------------
	game.finish_run(false)
	game.net.slot = 0
	game.net.host_slot = 0
	game.net.lobby = {}
	game.start_run(6262)
	await process_frame
	list = caches()
	game.rooms[game.interactables[list[0]].room].cleared = true
	game.scrap = 500
	game.perform_interact(game.interactables[list[0]], game.player)
	verify(game.mode == "choice" and not game.world_running(), "Solo cache picks open immediately and pause the dig")
	var solo_offer = game.choice_items.duplicate()
	verify(game.hud.back() and game.mode == "play" and game.world_running(), "B leaves a solo pick for later and the dig resumes")
	verify(game.pending_choices.size() == 1 and game.pending_choices[0].items == solo_offer, "...the same offer waits")
	verify(game.game_action("parts") and game.choice_items == solo_offer, "The parts button reopens it")
	game.choose(0)
	verify(game.game_action("parts") and game.mode == "inventory", "With nothing waiting the button opens Buster parts")
	game.resume_game()
	game.player.gain_xp(game.player.xp_required)
	verify(game.mode == "play" and game.auto_open_choice, "A solo level-up opens on the next frame")
	await process_frame
	await process_frame
	verify(game.mode == "choice" and game.choice_kind == "level" and not game.world_running(), "...as a paused level pick")
	game.choose(2)
	game.finish_run(false)

	for path in [game.save_path, game.checkpoint_path, game.checkpoint_path + ".tmp", "res://save/coop-test-audio.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COOP_FEEDBACK_CHECKS %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
