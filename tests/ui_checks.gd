extends SceneTree

var game: Node3D
var failures = 0
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI_CHECK_FAILED: " + message)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func press(key: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	root.push_input(event, true)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	root.push_input(event, true)

func click(hit: Dictionary) -> void:
	var point: Vector2 = game.hud.ui_offset + hit.rect.get_center() * game.hud.ui_scale
	var move = InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = false
	root.push_input(event, true)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	game.meta.kills = 0
	await refresh()
	verify(game.hud.hits.size() == 8, "Title has five menu actions, one unlocked buster and two diggers")
	verify(game.hud.hits[0].action == "start", "Default keyboard selection starts a dig")
	verify(game.hud.hits[1].action == "online", "Play Online sits directly under Start Dig")
	click(game.hud.hits[0])
	await refresh()
	verify(game.mode == "play", "Mouse click starts the dig")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "pause", "Escape opens the new pause menu")
	press(KEY_DOWN)
	press(KEY_ENTER)
	await refresh()
	verify(game.mode == "inventory", "Keyboard navigation opens Buster Parts")
	verify(game.hud.hits.size() == 1, "Empty inventory offers a return action")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "play", "Escape returns from Buster Parts")
	game.player.items.clear()
	for id in game.ITEMS: game.player.items[id] = 12
	game.mode = "inventory"
	await refresh()
	for i in 12: press(KEY_DOWN)
	await refresh()
	verify(game.hud.selected_item == 12, "All thirteen parts are reachable with keyboard navigation")
	verify(game.hud.list_scroll == 6, "The list scrolls to reveal the last part")
	verify(game.hud.hits[0].value == 6, "Visible rows track the scrolled inventory")
	for size in [Vector2i(960, 600), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		await refresh()
		verify(game.hud.ui_scale > 0, "UI scale remains valid after resizing")
		var first = game.hud.hits[0]
		click(first)
		await refresh()
		verify(game.hud.selected_item == first.value, "Scaled mouse clicks select the visible inventory row")
		for hit in game.hud.hits:
			verify(Rect2(Vector2.ZERO, Vector2(1440, 900)).encloses(hit.rect), "Click targets stay inside the safe area")
	game.mode = "choice"
	game.choice_kind = "relic"
	game.choice_items = ["lens", "spring", "heart"]
	await refresh()
	press(KEY_DOWN)
	verify(game.hud.choice_preview == 1, "Keyboard navigation previews another part")
	var previous = game.player.count("spring")
	press(KEY_ENTER)
	await refresh()
	verify(game.mode == "play" and game.player.count("spring") == previous + 1, "Confirm fits the previewed part exactly once")
	game.mode = "choice"
	game.choice_kind = "level"
	game.choice_items = ["power", "vitality", "haste"]
	await refresh()
	var previous_health = game.player.base_health
	press(KEY_2)
	await refresh()
	verify(game.player.base_health == previous_health + 20, "Number shortcuts still apply level upgrades")
	game.mode = "archive"
	await refresh()
	for i in 12: press(KEY_DOWN)
	await refresh()
	verify(game.hud.selected_item == 12, "Locked collection entries remain inspectable")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "title", "Collection returns to title with Escape")
	verify(game.hud.ICONS.size() == 32, "UI has a full set of distinct equipment and status icons")
	print("UI_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
