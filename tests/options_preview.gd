extends SceneTree

# Renders the Options, Controls and pause menus plus controller prompts.
#   xvfb-run godot --path . --script tests/options_preview.gd   → screenshots/options-*.png

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture(name: String) -> void:
	for n in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/options-%s.png" % name)
	print("saved options-%s" % name)

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.save_path = "res://save/options-preview.json"
	game.settings.path = "res://save/options-preview-settings.json"
	game.sound.settings_path = "res://save/options-preview-audio.json"
	game.sound.muted = true
	await process_frame
	game.settings.using_pad = true
	await capture("title-controller")
	game.start_run(49381)
	game.message_time = 0
	game.player.position = Vector3(-3, 0.12, -1.2)
	game.player.yaw = 0
	for n in 10: await physics_frame
	await capture("hud-controller")
	game.settings.using_pad = false
	game.mode = "pause"
	await capture("pause")
	game.hud.activate("options")
	game.hud.focus_index = 7
	await capture("options")
	game.hud.activate_option(game.hud.OPTIONS.find("controls"))
	game.hud.focus_index = 10
	game.hud.listening = {"id": "dash", "column": "pad", "time": 6.0}
	await capture("controls")
	for path in [game.save_path, game.settings.path, game.sound.settings_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
