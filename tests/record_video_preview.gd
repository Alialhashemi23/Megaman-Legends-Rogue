extends SceneTree

# Record the actual renderer and mixer with scripted input; user saves untouched.
var game: Node3D
var elapsed = 0.0
var fired: Dictionary = {}
var keys: Dictionary = {}
var mouse_down = false
var part_choice_time = -1.0
var recording = false

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://tools/runtime/video-preview-records.json"
	root.add_child(game)
	game.meta = {"kills": 0, "runs": 0, "wins": 0, "deepest": 0, "discovered": {}, "best_time": 0.0}
	game.sound.settings_path = "res://tools/runtime/video-preview-audio.json"
	game.sound.muted = false
	game.sound.volumes = {"Master": .85, "Music": .80, "Effects": .85, "Ambience": .60}
	game.sound.apply_volumes()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	recording = true
	print("VIDEO_PREVIEW_STARTED")

func once(time: float, id: String) -> bool:
	if elapsed < time or fired.has(id): return false
	fired[id] = true
	return true

func key(code: int, down: bool) -> void:
	if bool(keys.get(code, false)) == down: return
	keys[code] = down
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func mouse(down: bool) -> void:
	if mouse_down == down: return
	mouse_down = down
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = Vector2(640, 400)
	Input.parse_input_event(event)

func release_all() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE]: key(code, false)
	mouse(false)

func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func skirmish(character: int) -> void:
	release_all()
	game.selected_character = character
	game.start_run(49381)
	clear_enemies()
	game.player.pitch = -.13
	game.spawn_enemy(Vector3(-2.5, 0, -4), 0, 0)
	game.spawn_enemy(Vector3(3, 0, -7), 1, 0)
	game.spawn_enemy(Vector3(0, 0, -11), 2, 0)
	game.message_time = 0
	game.player.update_camera(1)

func aim_target() -> void:
	if is_instance_valid(game.player.lock_target) and not game.player.lock_target.dead: return
	game.player.lock_target = null
	var nearest = 999.0
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead: continue
		var distance = enemy.position.distance_to(game.player.position)
		if distance < nearest:
			nearest = distance
			game.player.lock_target = enemy

func guardian() -> void:
	release_all()
	game.depth = 3
	game.build_floor(true)
	for enemy in game.enemies.duplicate():
		if enemy.kind != 3:
			enemy.queue_free()
			game.enemies.erase(enemy)
	var boss = game.enemies[0]
	game.player.position = game.rooms[game.exit_room].center + Vector3(0, .1, 4.4)
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0
	game.player.visual.rotation.y = 0
	game.player.lock_target = boss
	game.current_room = game.exit_room
	game.rooms[game.exit_room].visited = true
	boss.active = true
	game.message_time = 0
	game.player.update_camera(1)

func _physics_process(dt: float) -> bool:
	if not recording: return false
	elapsed += dt
	if once(3, "mega"): skirmish(0)
	if once(12.5, "parts"):
		release_all()
		game.open_relic_choice()
	if once(14, "choice_focus"): game.hud.choice_preview = 1
	if once(15.5, "fit_part"):
		game.hud.activate("choice", 1)
	if once(16, "roll_title"):
		release_all()
		game.show_title()
		game.hud.select_character(1)
		game.player.visual.preview(0)
	if once(19, "roll"): skirmish(1)
	if once(29, "guardian"): guardian()
	if once(40, "end_title"):
		release_all()
		game.player.lock_target = null
		game.show_title()
	if elapsed >= 43:
		release_all()
		recording = false
		print("VIDEO_PREVIEW_COMPLETE")
		quit()
		return false
	if game.mode == "play":
		aim_target()
		var t = elapsed - (3 if elapsed < 16 else 19 if elapsed < 29 else 29)
		if elapsed < 29:
			key(KEY_D, t > 1.5 and t < 2.2)
			key(KEY_A, t > 5.2 and t < 5.8)
			key(KEY_W, t > 6.5 and t < 7.6)
			key(KEY_SPACE, t > 3.5 and t < 3.62)
			key(KEY_SHIFT, t > 5.25 and t < 5.36)
			mouse((t > .65 and t < 2.7) or (t > 4.1 and t < 4.9) or (t > 6.7 and t < 8.7))
		else:
			key(KEY_D, (t > 1 and t < 1.4) or (t > 6 and t < 6.4))
			key(KEY_A, t > 3.8 and t < 4.25)
			key(KEY_S, false)
			key(KEY_SPACE, t > 2.75 and t < 2.88)
			key(KEY_SHIFT, t > 4 and t < 4.12)
			mouse((t > .7 and t < 2.5) or (t > 4.5 and t < 5.5) or (t > 7.2 and t < 9.6))
	elif game.mode == "choice" and elapsed < 12.5 or game.mode == "choice" and elapsed > 19:
		# Let natural level-up choices stay visible before confirming one.
		release_all()
		if part_choice_time < 0: part_choice_time = elapsed
		if elapsed - part_choice_time > 1.2:
			game.hud.activate("choice", 0)
			part_choice_time = -1
	return false
