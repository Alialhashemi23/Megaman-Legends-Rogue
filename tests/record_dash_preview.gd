extends SceneTree

# Record every digger running, jumping and dashing in each direction through the
# real game camera.
# Run with --write-movie <file.avi> --fixed-fps 60; user saves untouched.
const SEGMENT = 8.0
var game: Node3D
var elapsed = 0.0
var keys: Dictionary = {}
var segment = -1
var recording = false

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://tools/runtime/dash-preview-records.json"
	root.add_child(game)
	game.meta = {"kills": 0, "runs": 0, "wins": 0, "deepest": 0, "discovered": {}, "best_time": 0.0}
	game.sound.settings_path = "res://tools/runtime/dash-preview-audio.json"
	game.sound.muted = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	recording = true
	print("DASH_VIDEO_STARTED")

func key(code: int, down: bool) -> void:
	if bool(keys.get(code, false)) == down: return
	keys[code] = down
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func release_all() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE]: key(code, false)

func begin(character: int) -> void:
	release_all()
	game.selected_character = character
	game.start_run(49381)
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.player.pitch = -.13
	game.message_time = 0
	game.player.update_camera(1)

func _physics_process(dt: float) -> bool:
	if not recording: return false
	elapsed += dt
	var index = int(elapsed / SEGMENT)
	if index >= DiverCharacter.COUNT:
		release_all()
		recording = false
		print("DASH_VIDEO_COMPLETE")
		quit()
		return false
	if index != segment:
		segment = index
		begin(index)
	var t = fmod(elapsed, SEGMENT)
	# Run then dash forward; a standing dash; right, left and back dashes;
	# a standing jump and landing; then a run with a jump.
	key(KEY_W, (t > .6 and t < 1.3) or (t > 7.0 and t < 7.9))
	key(KEY_SPACE, (t > 6.2 and t < 6.3) or (t > 7.3 and t < 7.4))
	key(KEY_D, t > 3.0 and t < 3.4)
	key(KEY_A, t > 4.2 and t < 4.6)
	key(KEY_S, t > 5.4 and t < 5.8)
	key(KEY_SHIFT, (t > 1.0 and t < 1.08) or (t > 2.0 and t < 2.08) or (t > 3.05 and t < 3.13) or (t > 4.25 and t < 4.33) or (t > 5.45 and t < 5.53))
	return false
