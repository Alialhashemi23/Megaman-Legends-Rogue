extends SceneTree

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture(mode: String, name: String) -> void:
	game.mode = mode
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/next-%s.png" % name)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/preview-only.json"
	game.checkpoint_path = "res://save/preview-only.dat"
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 780
	game.meta.trees = {"0": ["frame", "mobility", "salvage"], "1": ["frame", "salvage", "ability"]}
	await capture("title", "title")
	game.hud.workshop_return = "title"
	await capture("workshop", "mega-tree")
	game.hud.workshop_character = 1
	await capture("workshop", "roll-tree")
	game.hud.activate("save_codes")
	game.hud.save_edit.text = DiverProgression.encode(game.meta)
	await capture("save_codes", "backup")
	for character in 4:
		game.selected_character = character
		game.start_run(49381)
		game.player.set_physics_process(false)
		game.message_time = 0
		game.player.update_camera(1)
		await capture("play", "digger-%d" % character)
		await capture("pause", "pause-%d" % character)
	game.settings.map_zoom = true
	for room in game.rooms: room.visited = true
	await capture("play", "zoomed-map")
	game.finish_run(true)
	await capture("end", "results")
	game.hud.activate("options")
	await capture("options", "options")
	root.size = Vector2i(960, 600)
	await capture("workshop", "tree-960")
	print("NEXT_FEATURES_GALLERY_SAVED")
	quit()
