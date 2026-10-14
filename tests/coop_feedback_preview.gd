extends SceneTree

# Renders the co-op feedback states without a server: a teammate's waiting part
# pick with cache icons on the shared map, and the pick screen showing the
# fitted build. Saves screenshots/coop-pending*.png and coop-pick.png.
#   godot --path . --script tests/coop_feedback_preview.gd

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture(name: String) -> void:
	for n in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/coop-%s.png" % name)
	print("saved coop-%s" % name)

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.save_path = "res://save/coop-feedback-preview.json"
	game.sound.settings_path = "res://save/coop-feedback-preview-audio.json"
	game.sound.muted = true
	game.checkpoint_path = "res://save/coop-feedback-preview-run.dat"
	await process_frame
	game.net.status = "online"
	game.net.slot = 2
	game.net.host_slot = 1
	game.net.player_name = "Sam"
	game.net.lobby = {"name": "Ali's Dig", "isPublic": true, "hostSlot": 1, "players": [{"slot": 1, "name": "Ali", "id": "a"}, {"slot": 2, "name": "Sam", "id": "s"}, {"slot": 3, "name": "Jordan", "id": "j"}]}
	game.start_run(49381, 3)
	for proxy in game.remote_players.values(): proxy.set_physics_process(false)
	# Teammates have explored most of the floor; two caches are claimed or waiting.
	for i in game.rooms.size():
		if i != game.exit_room and i % 4 != 3:
			game.rooms[i].visited = true
			game.rooms[i].cleared = i % 3 != 2
	var caches = []
	for i in game.interactables.size():
		if game.interactables[i].kind == "cache" and game.rooms[game.interactables[i].room].visited: caches.append(i)
	game.player.items = {"lens": 2, "coil": 1, "spring": 1, "moss": 1}
	game.interactables[caches[0]].used = true
	game.use_interactable(game.interactables[caches[0]])
	if caches.size() > 2:
		game.interactables[caches[2]].used = true
		game.use_interactable(game.interactables[caches[2]])
		game.rooms[game.interactables[caches[2]].room].cleared = true
		game.net_message(1, [DiverNet.M_CHOICE, game.depth, caches[2], 3])
	game.player.position = Vector3(0, 0.12, 1)
	game.player.pitch = -0.2
	for n in 20:
		await physics_frame
		game.player.update_camera(1)
	game.net_message(1, [DiverNet.M_CHOICE, game.depth, caches[0], 3])
	await capture("pending")
	game.settings.map_zoom = true
	game.message_time = 0
	await capture("pending-zoomed")
	game.settings.map_zoom = false
	game.game_action("parts")
	await capture("pick")
	for path in [game.save_path, game.sound.settings_path, game.checkpoint_path, game.checkpoint_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
