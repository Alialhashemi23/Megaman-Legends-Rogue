extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = "res://save/pt12-native.json"
	root.add_child(game)
	game.set_process(false)
	game.settings.path = "res://save/pt12-native-settings.json"
	game.sound.muted = true
	game.mode = "options"
	game.settings.set_fullscreen(true)
	await create_timer(0.5).timeout
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		push_error("PT12 native fullscreen failed")
		quit(1)
		return
	game.settings.set_fullscreen(false)
	await create_timer(0.5).timeout
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		push_error("PT12 native windowed failed")
		quit(1)
		return
	print("PT12_NATIVE_DISPLAY_PASS: actual Windows fullscreen and windowed modes")
	quit()
