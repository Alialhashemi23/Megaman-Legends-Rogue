extends SceneTree

# Exercise actual playback and capture a short title > ruin > boss > menu mix.
var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	game.sound.settings_path = "res://tools/runtime/audio-preview-settings.json"
	game.sound.muted = false
	game.sound.volumes = {"Master": .85, "Music": .65, "Effects": .85, "Ambience": .6}
	game.sound.apply_volumes()
	var recording = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, recording)
	recording.set_recording_active(true)
	await create_timer(2.0).timeout
	game.mode = "play"
	for i in 9:
		game.sound.play(["shot", "needle", "siege"][i % 3])
		game.sound.play("hit", 1.0, game.player.position + Vector3(2, 1, -3))
		await create_timer(.23).timeout
	game.current_room = game.exit_room
	var boss = game.enemies.filter(func(e): return e.kind == 3)[0]
	boss.active = true
	await create_timer(2.0).timeout
	game.sound.play("warning")
	await create_timer(.6).timeout
	game.sound.play("slam", 1.0, game.player.position + Vector3(3, 0, -2))
	await create_timer(1.0).timeout
	game.mode = "audio"
	game.hud.queue_redraw()
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/ui-audio.png")
	game.sound.play("menu_confirm")
	await create_timer(.4).timeout
	recording.set_recording_active(false)
	var result = recording.get_recording()
	if result == null or result.data.size() == 0:
		push_error("Audio capture is empty")
		quit(1)
		return
	result.save_to_wav("res://tools/audio/in-game-mix.wav")
	print("AUDIO_PREVIEW: %s seconds captured, title/ruin/guardian transitions, world effects and settings rendered" % result.get_length())
	game.smoke_test = true
	quit()
