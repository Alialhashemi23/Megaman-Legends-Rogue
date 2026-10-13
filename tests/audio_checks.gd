extends SceneTree

var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func press(key: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	root.push_input(event, true)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.set_process(false)
	await process_frame
	for cue in game.sound.MUSIC_NAMES:
		var stream: AudioStreamOggVorbis = game.sound.tracks[cue]
		verify(stream != null and stream.get_length() > 5, "Music cue loads: " + cue)
		verify(stream.loop == (cue not in ["clear", "lost"]), "Loop policy: " + cue)
	for kind in game.sound.EFFECT_NAMES:
		var stream: AudioStreamWAV = game.sound.streams[kind]
		verify(stream != null and stream.get_length() > 0.025 and stream.data.size() > 0, "Effect loads: " + kind)
	for bus in ["Master", "Music", "Effects", "Ambience", "Menu"]:
		verify(AudioServer.get_bus_index(bus) >= 0, "Audio bus exists: " + bus)
	game.mode = "title"
	verify(game.sound.desired_cue() == "title", "Title selects its own composition")
	game.mode = "play"
	for depth in range(1, 4):
		game.depth = depth
		verify(game.sound.desired_cue() == ["tidal", "garden", "core"][depth - 1], "Descent selects its theme")
	var boss = game.enemies.filter(func(e): return e.kind == 3)[0]
	boss.active = true
	game.current_room = boss.room_id
	verify(game.sound.desired_cue() == "guardian", "Awakened guardian changes the score")
	game.sound.change_music("guardian")
	game.mode = "pause"
	verify(game.sound.desired_cue() == "guardian", "Pause retains the battle cue")
	game.mode = "play"
	game.guardian_dead = true
	verify(game.sound.desired_cue() == "core", "Defeated guardian restores descent music")
	game.mode = "end"
	game.outcome = true
	verify(game.sound.desired_cue() == "clear", "Extraction selects clear cue")
	game.outcome = false
	verify(game.sound.desired_cue() == "lost", "Defeat selects loss cue")
	game.mode = "pause"
	game.hud.activate("options")
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	verify(game.hud.hits.size() == 14, "Options expose sound, display and control settings")
	var music_level = game.sound.volumes.Music
	press(KEY_DOWN)
	press(KEY_LEFT)
	verify(is_equal_approx(game.sound.volumes.Music, music_level - .05), "Left lowers selected music level")
	press(KEY_RIGHT)
	verify(is_equal_approx(game.sound.volumes.Music, music_level), "Right restores selected music level")
	game.sound.volumes.Effects = 1.0
	game.hud.activate("volume", 2)
	verify(game.sound.volumes.Effects == 0, "Volume wraps to silent")
	verify(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "Zero effects mutes bus")
	verify(AudioServer.is_bus_mute(AudioServer.get_bus_index("Menu")), "Effects control also covers menu sounds")
	game.sound.muted = true
	verify(AudioServer.is_bus_mute(0), "Mute all mutes master")
	game.sound.muted = false
	verify(not AudioServer.is_bus_mute(0), "Unmute restores master")
	press(KEY_ESCAPE)
	verify(game.mode == "pause", "Escape returns to paused menu")
	print("AUDIO_CHECKS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
