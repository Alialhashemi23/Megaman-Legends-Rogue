extends SceneTree

# Controller support, the Options menu, rebinding and leaving a dig.
# Simulates controller input through the real InputMap; uses isolated saves.

var game: Node3D
var failures = 0
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("OPTIONS_CHECK_FAILED: " + message)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func button(index: int, pressed: bool = true) -> void:
	var e = InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = pressed
	Input.parse_input_event(e)

func tap(index: int) -> void:
	button(index, true)
	await process_frame
	button(index, false)
	await process_frame

func axis(index: int, value: float) -> void:
	var e = InputEventJoypadMotion.new()
	e.axis = index
	e.axis_value = value
	Input.parse_input_event(e)

func key(code: int) -> void:
	for pressed in [true, false]:
		var e = InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save"))
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.save_path = "res://save/options-test-archive.json"
	game.checkpoint_path = "res://save/options-test-run.dat"
	game.sound.muted = true
	var s: DiverSettings = game.settings
	s.path = "res://save/options-test.json"
	await refresh()

	# Defaults and prompts.
	verify(InputMap.has_action("fire") and InputMap.has_action("look_left") and InputMap.has_action("nav_accept"), "Gameplay, look and menu actions exist")
	s.using_pad = false
	verify(s.prompt("interact") == "E" and s.prompt("fire") == "LMB", "Keyboard prompts by default")
	s.using_pad = true
	verify(s.prompt("interact") == "X" and s.prompt("fire") == "RT" and s.prompt("move") == "L-Stick", "Controller prompts use Xbox names")
	verify(s.prompt("chat") == "T", "Actions without a controller binding fall back to the keyboard prompt")

	# Menus with a controller: D-pad moves, A confirms, B backs out.
	game.mode = "title"
	await refresh()
	await tap(JOY_BUTTON_DPAD_DOWN)
	await refresh()
	verify(game.hud.focus_index == 1, "D-pad moves the title cursor")
	axis(JOY_AXIS_LEFT_Y, 1.0)
	await process_frame
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await refresh()
	verify(game.hud.focus_index == 2, "Left stick moves the title cursor too")
	await tap(JOY_BUTTON_DPAD_UP)
	await tap(JOY_BUTTON_DPAD_UP)
	await tap(JOY_BUTTON_Y)
	verify(game.selected_character == 1, "Y switches the digger on the title")
	await tap(JOY_BUTTON_Y)
	await refresh()
	await tap(JOY_BUTTON_A)
	await refresh()
	verify(game.mode == "play", "A starts the dig")
	verify(not game.persisting() and not FileAccess.file_exists(game.checkpoint_path), "Solo digs don't keep a mid-run save")

	# Playing with a controller.
	game.player.invincible = 999
	var start = game.player.position
	axis(JOY_AXIS_LEFT_Y, -1.0)
	for n in 30: await physics_frame
	axis(JOY_AXIS_LEFT_Y, 0.0)
	verify(game.player.position.z < start.z - 1.0, "Left stick walks forward")
	var yaw = game.player.yaw
	axis(JOY_AXIS_RIGHT_X, 1.0)
	for n in 10: await physics_frame
	axis(JOY_AXIS_RIGHT_X, 0.0)
	verify(game.player.yaw < yaw - 0.1, "Right stick turns the camera")
	s.invert_y = true
	var pitch = game.player.pitch
	axis(JOY_AXIS_RIGHT_Y, -1.0)
	for n in 6: await physics_frame
	axis(JOY_AXIS_RIGHT_Y, 0.0)
	verify(game.player.pitch < pitch, "Invert look flips the vertical stick")
	s.invert_y = false
	game.player.cooldown = 0
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	for n in 3: await physics_frame
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	verify(game.player.cooldown > 0, "Right trigger fires the buster")
	var enemy = game.spawn_enemy(game.player.position + Vector3(0, 0, -6), 0, 0)
	await physics_frame
	game.player.camera.look_at(enemy.global_position)
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await process_frame
	await process_frame
	verify(is_instance_valid(game.player.lock_target), "Left trigger locks on")
	for n in 5: await process_frame
	verify(is_instance_valid(game.player.lock_target), "Holding the trigger doesn't toggle lock-on off again")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await process_frame
	game.player.lock_target = null
	await tap(JOY_BUTTON_START)
	verify(game.mode == "pause", "Menu button pauses")
	await tap(JOY_BUTTON_B)
	verify(game.mode == "play", "B returns to the dig")
	await tap(JOY_BUTTON_BACK)
	verify(game.mode == "inventory", "View opens buster parts")
	await tap(JOY_BUTTON_B)
	verify(game.mode == "play", "B closes buster parts")

	# Options page.
	game.mode = "pause"
	game.hud.activate("options")
	await refresh()
	verify(game.mode == "options" and game.hud.options_return == "pause", "Options open from the pause menu")
	verify(game.hud.hits.size() == game.hud.OPTIONS.size(), "Every option is selectable")
	game.hud.focus_index = game.hud.OPTIONS.find("fov")
	var fov = s.fov
	await tap(JOY_BUTTON_DPAD_RIGHT)
	verify(s.fov == fov + 2, "D-pad right widens the field of view")
	game.hud.activate_option(game.hud.OPTIONS.find("invert"))
	verify(s.invert_y, "Invert look toggles")
	game.hud.activate_option(game.hud.OPTIONS.find("invert"))
	game.hud.focus_index = game.hud.OPTIONS.find("mouse")
	var sensitivity = s.mouse_sensitivity
	game.hud.navigate(1, true)
	verify(is_equal_approx(s.mouse_sensitivity, sensitivity + 0.1), "Mouse sensitivity adjusts")
	var camera = s.camera_effects
	game.hud.activate_option(game.hud.OPTIONS.find("camera"))
	verify(game.camera_effects != camera, "Camera motion toggle reaches the game")
	game.hud.activate_option(game.hud.OPTIONS.find("camera"))

	# Rebinding: keyboard and controller columns, swaps on conflict, persistence.
	game.hud.activate_option(game.hud.OPTIONS.find("controls"))
	await refresh()
	verify(game.mode == "controls", "Controls page opens from Options")
	verify(game.hud.hits.size() == DiverSettings.ACTIONS.size() * 2 + 2, "Every action has keyboard and controller cells")
	var jump = DiverSettings.ACTIONS.map(func(a): return a.id).find("jump")
	game.hud.activate("bind", jump * 2)
	key(KEY_J)
	await process_frame
	verify(s.bindings.jump.kb == {"key": KEY_J} and game.hud.listening.is_empty(), "A key press rebinds jump")
	game.hud.activate("bind", jump * 2)
	key(KEY_E)
	await process_frame
	verify(s.bindings.jump.kb == {"key": KEY_E} and s.bindings.interact.kb == {"key": KEY_J}, "Taking another action's key swaps them")
	game.hud.activate("bind", jump * 2 + 1)
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	verify(s.bindings.jump.pad == {"button": JOY_BUTTON_RIGHT_SHOULDER}, "A controller button rebinds jump")
	game.mode = "play"
	var e = InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_RIGHT_SHOULDER
	verify(e.is_action("jump"), "The new binding drives the action")
	s.save_settings()
	var loaded = DiverSettings.new()
	loaded.path = s.path
	loaded.reset_bindings()
	loaded.load_settings()
	verify(loaded.bindings.jump.kb == {"key": KEY_E} and loaded.bindings.jump.pad == {"button": JOY_BUTTON_RIGHT_SHOULDER}, "Bindings persist")
	loaded.free()
	game.mode = "controls"
	game.hud.activate("reset_controls")
	game.hud.activate("reset_controls")
	verify(s.bindings.jump.kb == {"key": KEY_SPACE} and s.bindings.interact.kb == {"key": KEY_E}, "Reset to defaults restores bindings")
	game.hud.back()
	verify(game.mode == "options", "B/Esc steps back from Controls to Options")
	game.hud.back()
	verify(game.mode == "pause", "…and from Options to where it was opened")

	# Leaving a dig: always available, needs a second press.
	await refresh()
	var leave = game.hud.hits.filter(func(h): return h.action == "leave_dig")
	verify(leave.size() == 1, "Pause menu offers Leave Dig")
	verify(game.hud.hits.filter(func(h): return h.action == "abandon").is_empty(), "Solo diggers don't see End Dig for Everyone")
	game.hud.activate("leave_dig")
	verify(game.mode == "pause", "First press only asks to confirm")
	game.hud.activate("leave_dig")
	verify(game.mode == "end" and game.end_reason == "You left the dig", "Second press leaves and records the dig")

	for path in [s.path, game.save_path, game.checkpoint_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("OPTIONS_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
