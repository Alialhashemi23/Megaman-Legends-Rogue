extends SceneTree

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture(filename: String) -> void:
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % filename)

func freeze() -> void:
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	for index in 2:
		game.selected_character = index
		game.start_run(49381)
		freeze()
		game.show_title()
		game.player.visual.preview(0)
		await capture("title-%s" % ["mega", "roll"][index])
		game.start_run(49381)
		freeze()
		game.player.position.y = 0
		game.message_time = 0
		game.player.visual.arm_weight = 1
		game.player.visual.animate(.18, Vector2(0,-1), true, 0, false, true, -.2, .3)
		game.player.update_camera(1)
		await capture("play-%s" % ["mega", "roll"][index])
	game.mode = "pause"
	await capture("pause-roll")
	print("CHARACTER_GAME_PREVIEW: Mega and Roll title/gameplay plus Roll pause menu")
	quit()
