extends SceneTree

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func show_screen(mode: String, filename: String) -> void:
	game.mode = mode
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/ui-%s.png" % filename)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	game.start_run(49381)
	game.meta.kills = 57
	game.meta.runs = 4
	game.meta.wins = 1
	game.player.items.clear()
	for id in game.ITEMS:
		game.player.items[id] = 2 if id == "lens" else 12 if id == "spring" else 1
		game.meta.discovered[id] = true
	game.player.hp = 73
	game.player.level = 5
	game.player.xp = 13
	game.player.xp_required = 40
	game.scrap = 2387
	game.run_time = 873
	game.message_time = 0
	await show_screen("inventory", "inventory")
	game.hud.selected_item = 12
	await show_screen("inventory", "inventory-scrolled")
	await show_screen("pause", "pause")
	game.choice_kind = "relic"
	game.choice_items = ["coil", "lens", "echo"]
	await show_screen("choice", "choice")
	game.choice_kind = "level"
	game.choice_items = ["power", "vitality", "haste"]
	await show_screen("choice", "level")
	game.outcome = true
	game.kills = 38
	game.depth = 3
	game.new_unlocks = ["Storm Coil", "Needle Buster", "Forked Antenna"]
	await show_screen("end", "results")
	game.depth = 1
	await show_screen("play", "hud")
	root.size = Vector2i(1920, 1080)
	await show_screen("inventory", "inventory-1920")
	root.size = Vector2i(960, 600)
	await show_screen("pause", "pause-960")
	print("UI_GALLERY_SAVED")
	quit()
