extends SceneTree

# Co-op feedback (roadmap phase 1): the party shares one map, a teammate's
# cache leaves a waiting part pick instead of taking over the screen, the parts
# button opens that pick, picks can be put aside online without rerolling, and
# everything survives a rejoin. Uses isolated test save paths.

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

	# --- Waiting part picks -----------------------------------------------------
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
	await draw_frames()

	# Opening your own cache still goes straight to the choice.
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, own_cache, 2])
	verify(game.mode == "choice" and game.choice_kind == "relic", "The digger who opened a cache chooses right away")
	verify(int(game.choice_source.cache) == own_cache and game.choice_waiting(own_cache), "The open pick remembers its cache")
	await draw_frames()
	var offered = game.choice_items.duplicate()
	verify(game.can_defer_choice(), "Online cache picks can be put aside")
	verify(game.game_action("parts"), "The parts button puts the open pick aside")
	verify(game.mode == "play" and game.pending_choices.size() == 2, "Put-aside pick joins the waiting list")
	verify(game.pending_choices[0].items == offered, "...with the same three parts")

	# The parts button now opens waiting picks first.
	verify(game.game_action("parts") and game.mode == "choice", "The parts button opens a waiting pick")
	verify(game.choice_items == offered, "Reopening doesn't reroll the offer")
	verify(game.hud.back() and game.mode == "play", "Back also puts a pick aside online")
	game.game_action("parts")
	var items_before = game.player.items.duplicate()
	game.choose(0)
	verify(game.player.count(offered[0]) == int(items_before.get(offered[0], 0)) + 1, "Choosing fits the part")
	verify(game.pending_choices.size() == 1 and not game.choice_waiting(own_cache), "Choosing settles that cache's pick")
	verify(game.choice_waiting(mate_cache), "The other waiting pick is untouched")
	await draw_frames()

	# --- Rejoin restores the exact picks ---------------------------------------
	game.game_action("parts")
	var mate_offer = game.choice_items.duplicate()
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, own_cache, 3])
	verify(game.mode == "choice" and game.pending_choices.size() == 1, "A new teammate cache while choosing waits too")
	var build = game.build_state()
	game.pending_choices.clear()
	game.choice_source = {}
	game.mode = "play"
	game.apply_build(build)
	verify(game.mode == "choice" and game.choice_items == mate_offer, "An open pick comes back after a rejoin")
	verify(int(game.choice_source.get("cache", -1)) == mate_cache, "...still tied to its cache")
	verify(game.pending_choices.size() == 1 and game.choice_waiting(own_cache), "Waiting picks come back after a rejoin")
	var dirty = build.duplicate(true)
	dirty.choice = {}
	dirty.pending = [5, "x", {"depth": "nope"}, {"depth": 2, "cache": 3, "items": ["lens", "bogus", "coil"]}, {"depth": 1, "cache": 4, "items": ["lens", "coil", "echo"]}]
	game.mode = "play"
	game.apply_build(dirty)
	verify(game.pending_choices.size() == 3, "Malformed waiting picks are dropped (%d kept)" % game.pending_choices.size())
	verify(game.pending_choices[1].items.is_empty() and game.pending_choices[2].items == ["lens", "coil", "echo"], "Invalid offers are rerolled; valid ones are kept")
	for n in 40: game.net_message(1, [DiverNet.M_CHOICE, game.depth, mate_cache, 3])
	verify(game.pending_choices.size() == game.MAX_PENDING, "The waiting list is capped")

	# --- Host side: whoever presses E chooses now; everyone else waits ----------
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
	verify(game.mode == "choice" and int(game.choice_source.cache) == list[1], "Host chooses at once from their own cache")
	game.choose(1)
	await draw_frames()

	# --- Solo keeps the immediate choice; the button is plain Buster parts -------
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
	verify(game.mode == "choice" and not game.can_defer_choice(), "Solo cache picks open immediately and can't be put aside")
	verify(not game.hud.back() and game.mode == "choice", "Back doesn't skip a solo pick")
	game.choose(0)
	verify(game.game_action("parts") and game.mode == "inventory", "With nothing waiting the button opens Buster parts")
	game.resume_game()
	game.finish_run(false)

	for path in [game.save_path, game.checkpoint_path, game.checkpoint_path + ".tmp", "res://save/coop-test-audio.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COOP_FEEDBACK_CHECKS %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
