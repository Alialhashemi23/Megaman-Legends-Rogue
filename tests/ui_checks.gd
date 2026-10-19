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
	game.smoke_test = true
	game.save_path = "res://save/ui-test-archive.json"
	game.checkpoint_path = "res://save/ui-test-run.dat"
	root.add_child(game)
	game.set_process(false)
	game.settings.path = "res://save/ui-test-settings.json"
	game.account.cache_root = "res://save/ui-test-accounts"
	game.sound.muted = true
	game.meta.kills = 0
	await refresh()
	var hud = game.hud
	var main_actions = ["solo", "online", "workshop", "options", "account", "credits", "archive", "quit"]
	verify(hud.hits.map(func(h): return h.action) == main_actions, "Main actions form one list including Account")
	press(KEY_UP)
	verify(hud.focused_action() == "quit", "Simple title navigation wraps upward")
	press(KEY_DOWN)
	for i in hud.hits.size():
		verify(hud.hits[i].rect.position.x == 64, "Every title action belongs to the same vertical group")
	click(hud.hits[0])
	await refresh()
	verify(game.mode == "solo_prep" and hud.focused_action() == "solo_character", "Mouse Solo opens preparation on the character region")
	verify(game.sound.desired_cue() == "title" and not game.world_running(), "Preparation keeps title music and inactive gameplay")
	press(KEY_LEFT)
	verify(game.selected_character == DiverCharacter.COUNT - 1, "Character carousel wraps left")
	press(KEY_RIGHT)
	press(KEY_RIGHT)
	verify(game.selected_character == 1, "Right selects the displayed Roll without launching")
	click(hud.hits.filter(func(h): return h.action == "solo_cycle" and h.value == 1)[0])
	verify(game.selected_character == 2 and hud.focused_action() == "solo_character", "Mouse arrow cycles the digger and retains the selection region")
	press(KEY_LEFT)
	var held = InputEventKey.new()
	held.keycode = KEY_ENTER
	held.physical_keycode = KEY_ENTER
	held.pressed = true
	root.push_input(held, true)
	await refresh()
	verify(game.mode == "solo_prep" and hud.focused_action() == "launch_solo", "Accepting the digger focuses Start without launching")
	root.push_input(held, true)
	await refresh()
	verify(game.mode == "solo_prep", "A duplicate held confirm cannot start the dig")
	held.echo = true
	root.push_input(held, true)
	held.echo = false
	verify(game.mode == "solo_prep", "Keyboard auto-repeat cannot start the dig")
	held.pressed = false
	root.push_input(held, true)
	press(KEY_LEFT)
	verify(game.selected_character == 1, "Left on Start does not change the chosen digger")
	press(KEY_DOWN)
	verify(hud.focused_action() == "title", "Down from Start focuses Back")
	press(KEY_DOWN)
	verify(hud.focused_action() == "solo_character", "Prep regions wrap back to selection")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "title" and hud.focused_action() == "solo", "Back from prep restores Solo on the title")
	# A held press cannot cross the title/preparation boundary either.
	held.pressed = true
	root.push_input(held, true)
	root.push_input(held, true)
	await refresh()
	root.push_input(held, true)
	verify(game.mode == "solo_prep" and hud.focused_action() == "solo_character", "Holding confirm on Solo cannot accept or launch the new page")
	held.pressed = false
	root.push_input(held, true)
	press(KEY_ESCAPE)
	await refresh()
	# Idle motion (including resize-generated events) cannot steal keyboard/pad focus.
	var idle = InputEventMouseMotion.new()
	idle.position = hud.ui_offset + hud.hits[0].rect.get_center() * hud.ui_scale
	hud.navigate(1, false)
	root.push_input(idle, true)
	await refresh()
	verify(hud.focused_action() == "online", "Stationary mouse does not steal menu focus")
	idle.relative = Vector2(20, 0)
	root.push_input(idle, true)
	verify(hud.focused_action() == "solo", "Deliberate pointer movement can select a menu action")
	hud.navigate(1, false)
	idle.relative = Vector2(1, 0)
	for i in 4: root.push_input(idle, true)
	verify(hud.focused_action() == "online", "Tiny pointer jitter does not take controller focus")
	root.push_input(idle, true)
	verify(hud.focused_action() == "solo", "Accumulated slow pointer movement can still take control")
	for action in ["options", "account", "credits", "archive"]:
		hud.focus_action(action)
		hud.confirm()
		await refresh()
		if action == "options":
			hud.focus_action("option", hud.OPTIONS.find("controls"))
			hud.confirm()
			await refresh()
			press(KEY_ESCAPE)
			await refresh()
			verify(game.mode == "options" and hud.focus_index == hud.OPTIONS.find("controls"), "Controls Back restores the Controls option")
		if action == "account":
			verify(hud.auth_email_edit.visible and hud.auth_password_edit.visible, "Account still opens the in-game sign-in modal")
			hud.auth_email_edit.grab_focus()
			press(KEY_ESCAPE)
			await refresh()
			verify(game.mode == "account" and not hud.editing(), "Back leaves text entry before closing the account layer")
		press(KEY_ESCAPE)
		await refresh()
		verify(game.mode == "title" and hud.focused_action() == action, "Back restores the originating title action: " + action)
	# Preserve the Workshop's spatial graph and node focus through its child page.
	hud.focus_action("workshop")
	hud.confirm()
	await refresh()
	verify(hud.focused_action() == "grid_node", "Workshop enters on a useful circuit")
	hud.focus_action("grid_node", 0)
	press(KEY_RIGHT)
	verify(DiverProgression.NODES[hud.hits[hud.focus_index].value].id == "salvage", "Workshop Right follows the spatial link")
	press(KEY_LEFT)
	press(KEY_LEFT)
	verify(DiverProgression.NODES[hud.hits[hud.focus_index].value].id == "mobility", "Workshop Left follows the spatial link")
	var node_focus = hud.focus_index
	hud.activate("save_codes")
	await refresh()
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "workshop" and hud.focus_index == node_focus, "Save Codes Back restores the selected circuit")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "workshop" and hud.focused_action() == "tree_character", "Workshop Back first reaches digger header")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "title" and hud.focused_action() == "workshop", "Workshop Back restores its title action")
	# Saved-dig priority may insert/remove a row without moving focus to another action.
	hud.focus_action("account")
	game.saved_dig = {"online": true, "lobby_code": "TEST", "world": {"depth": 2, "run_time": 61}}
	await refresh()
	verify(hud.hits[0].action == "continue" and hud.focused_action() == "account", "Rejoin has priority while Account keeps semantic focus")
	var saved = game.saved_dig.duplicate(true)
	hud.activate("solo")
	await refresh()
	hud.confirm()
	hud.confirm()
	verify(game.mode == "solo_prep" and game.saved_dig == saved, "New-dig review preserves the saved dig before confirmation")
	press(KEY_ESCAPE)
	await refresh()
	game.saved_dig = {}
	await refresh()
	for state in ["guest", "restoring", "needs_sign_in"]:
		game.account.state = state
		hud.focus_action("account")
		hud.confirm()
		await refresh()
		verify(game.mode == "account", "Account entry stays available in " + state)
		press(KEY_ESCAPE)
		await refresh()
		verify(hud.focused_action() == "account" and game.profile_source == "guest", "Account Back preserves Guest and focus in " + state)
	# The update prompt keeps its download/later path and title focus.
	game.android_updates.set_process(false)
	game.android_updates.metadata = {"versionCode": 99, "minimumOnlineVersionCode": 1, "gameProtocol": DiverNet.NET_VERSION, "versionName": "fixture", "notes": "Fixture update", "bytes": 100}
	game.mode = "android_update"
	await refresh()
	verify(hud.hits.map(func(h): return h.action) == ["android_download", "android_later"], "Update actions are preserved")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "title" and hud.focused_action() == "account" and game.android_updates.dismissed, "Update Back restores the title's prior action")
	game.android_updates.metadata = {}
	game.account.state = "guest"
	hud.activate("solo")
	await refresh()
	press(KEY_ENTER)
	press(KEY_ENTER)
	await refresh()
	verify(game.mode == "play" and game.player.character == 1, "Separate keyboard accept and Start launch the displayed Roll")
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
	verify(game.hud.ICONS.size() == 36, "UI has a full set of distinct equipment and status icons")
	print("UI_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
