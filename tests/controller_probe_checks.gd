extends SceneTree
var game: Node3D
var checks = 0
var failures = 0
var folder = "res://save/controller-" + DiverAccount.uuid()
func _initialize() -> void: run.call_deferred()
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CONTROLLER_CHECK_FAILED: " + label)
func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
func button(index: int, down: bool) -> void:
	var event = InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = down
	root.push_input(event, true)
func run() -> void:
	var raw = DiverControllerProbe.clean_browser([{"index":2,"id":"Example pad","mapping":"standard","axes":[-2,0.25,2,"bad",NAN],"buttons":[0,0.5,1,2,null]}])
	verify(raw.size()==1 and raw[0].index==2 and raw[0].mapping=="standard", "Browser slot/name/mapping preserved")
	verify(raw[0].axes==[-1.0,0.25,1.0,0.0,0.0], "Raw axes are finite and bounded")
	verify(raw[0].buttons==[0.0,0.5,1.0,1.0,0.0], "Raw analog trigger/button values retained")
	verify(DiverControllerProbe.clean_browser(null).is_empty(), "Absent browser data safe")
	verify(DiverControllerProbe.clean_browser([null,{},[],{"index":[],"axes":[],"buttons":[]}]).is_empty(), "Malformed browser data ignored")
	var many = []
	for i in 100: many.append(0.25)
	var limited = DiverControllerProbe.clean_browser([{"axes":many,"buttons":many}])[0]
	verify(limited.axes.size()==32 and limited.buttons.size()==64, "Diagnostics have bounded raw arrays")
	var missing = DiverControllerProbe.sample(-1)
	verify(not missing.connected and missing.axes.is_empty() and missing.buttons.is_empty(), "Disconnected pad does not report stale axes")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game=load("res://main.tscn").instantiate()
	game.save_path=folder.path_join("guest.json")
	game.checkpoint_path=folder.path_join("run.dat")
	root.add_child(game)
	game.set_process(false)
	game.net.set_process(false)
	game.account.set_process(false)
	game.account.cache_root=folder.path_join("accounts")
	game.sound.settings_path=folder.path_join("audio.json")
	game.sound.muted=true
	game.settings.path=folder.path_join("settings.json")
	game.settings.save_settings()
	var before=FileAccess.get_file_as_string(game.settings.path)
	var bindings=game.settings.bindings.duplicate(true)
	var deadzone=InputMap.action_get_deadzone("move_left")
	var h=game.hud
	game.mode="title"
	h.activate("options")
	await refresh()
	verify(h.OPTIONS.has("controller_test") and h.hits.size()==19, "Diagnostics reachable through Options")
	h.activate_option(h.OPTIONS.find("controller_test"))
	await refresh()
	verify(game.mode=="controller_test", "Option opens diagnostic page")
	verify(h.listening.is_empty(), "Diagnostics never enter binding capture")
	button(JOY_BUTTON_A,true)
	await refresh()
	verify(game.mode=="controller_test" and h.controller_last_button.contains("pressed"), "A registers without activating Back")
	button(JOY_BUTTON_A,false)
	button(JOY_BUTTON_Y,true)
	button(JOY_BUTTON_Y,false)
	await refresh()
	verify(game.mode=="controller_test", "Y is diagnostic, not a character change/reroll")
	var motion=InputEventJoypadMotion.new()
	motion.axis=JOY_AXIS_LEFT_Y
	motion.axis_value=0.9
	root.push_input(motion,true)
	verify(game.pad_held.is_empty(), "Stick motion does not start menu auto-repeat")
	button(JOY_BUTTON_B,true)
	await refresh()
	verify(game.mode=="options" and h.focused_action()=="option" and h.hits[h.focus_index].value==h.OPTIONS.find("controller_test"), "B returns one layer and restores Controller test focus")
	button(JOY_BUTTON_B,false)
	verify(before==FileAccess.get_file_as_string(game.settings.path) and bindings==game.settings.bindings and deadzone==InputMap.action_get_deadzone("move_left"), "Probe does not change saved settings, bindings or deadzones")
	for handheld in [false,true]:
		game.settings.handheld_ui=handheld
		game.mode="options"
		await refresh()
		for hit in h.hits: verify(Rect2(Vector2.ZERO,h.BASE).encloses(hit.rect), "Every option stays within the layout")
		h.activate_option(h.OPTIONS.find("controller_test"))
		await refresh()
		for hit in h.hits: verify(Rect2(Vector2.ZERO,h.BASE).encloses(hit.rect), "Diagnostic actions stay within the layout")
	game.mode="pause"
	h.activate("options")
	await refresh()
	h.activate_option(h.OPTIONS.find("controller_test"))
	await refresh()
	verify(game.in_run() and not game.world_running(), "Solo stays paused during diagnostics")
	game.net.slot=1
	game.net.status="online"
	verify(game.world_running(), "Co-op keeps simulating during diagnostics")
	game.net.slot=0
	game.net.status="offline"
	h.back()
	await refresh()
	h.back()
	verify(game.mode=="pause", "Diagnostics preserve the original Options return layer")
	print("CONTROLLER_CHECKS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
