extends SceneTree

var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PLAYTEST_MENU_FAILED: " + label)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func key(code: int) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)

func pad(code: int) -> void:
	for down in [true, false]:
		var event = InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		root.push_input(event, true)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = "res://save/pt-menu-profile.json"
	game.checkpoint_path = "res://save/pt-menu-checkpoint.dat"
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	game.settings.path = "res://save/pt-menu-settings.json"
	game.account.cache_root = "res://save/pt-menu-accounts"
	var hud = game.hud
	game.mode = "end"
	await refresh()
	verify(hud.hits.map(func(h): return h.action) == ["workshop", "run_log", "title"], "PT03 end hit order follows left to right")
	hud.focus_action("workshop")
	pad(JOY_BUTTON_DPAD_RIGHT)
	verify(hud.focused_action() == "run_log", "PT03 pad right reaches middle Dig Log")
	pad(JOY_BUTTON_DPAD_RIGHT)
	verify(hud.focused_action() == "title", "PT03 pad right reaches rightmost action")
	key(KEY_LEFT)
	verify(hud.focused_action() == "run_log", "PT03 keyboard left reaches middle")
	key(KEY_ENTER)
	await refresh()
	verify(game.mode == "run_log", "PT03 Dig Log opens")
	pad(JOY_BUTTON_B)
	await refresh()
	verify(game.mode == "end" and hud.focused_action() == "run_log", "PT03 Log Back restores middle action")
	key(KEY_LEFT)
	verify(hud.focused_action() == "workshop", "PT03 keyboard left reaches leftmost")
	hud.activate("solo")
	await refresh()
	pad(JOY_BUTTON_A)
	verify(hud.focused_action() == "launch_solo", "PT04 accepting digger focuses Start")
	pad(JOY_BUTTON_B)
	verify(game.mode == "solo_prep" and hud.focused_action() == "solo_character", "PT04 first B returns to carousel")
	pad(JOY_BUTTON_B)
	await refresh()
	verify(game.mode == "title" and hud.focused_action() == "solo", "PT04 second B returns to title")
	hud.activate("solo")
	await refresh()
	hud.focus_action("title")
	key(KEY_ESCAPE)
	verify(game.mode == "solo_prep" and hud.focused_action() == "solo_character", "PT04 keyboard Back on footer returns to carousel")
	key(KEY_ESCAPE)
	await refresh()
	print("PLAYTEST_MENU_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
