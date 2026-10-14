extends Node
class_name DiverSettings

# Player options and input bindings. Every gameplay and menu control is an
# InputMap action with one keyboard/mouse binding and one controller binding
# (Xbox layout names), both rebindable from the Options menu. Fixed extras:
# the left stick moves, the right stick looks, and D-pad / left stick / A / B
# also drive every menu.

const PATH = "res://save/settings.json"
const WEB_PATH = "user://settings.json"
const STICK_DEADZONE = 0.22

# Rebindable actions, in the order the Controls page lists them.
const ACTIONS = [
	{"id": "move_forward", "name": "Move forward", "kb": {"key": KEY_W}, "pad": {}},
	{"id": "move_back", "name": "Move back", "kb": {"key": KEY_S}, "pad": {}},
	{"id": "move_left", "name": "Move left", "kb": {"key": KEY_A}, "pad": {}},
	{"id": "move_right", "name": "Move right", "kb": {"key": KEY_D}, "pad": {}},
	{"id": "fire", "name": "Fire buster", "kb": {"mouse": MOUSE_BUTTON_LEFT}, "pad": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1}},
	{"id": "jump", "name": "Jump", "kb": {"key": KEY_SPACE}, "pad": {"button": JOY_BUTTON_A}},
	{"id": "dash", "name": "Dash", "kb": {"key": KEY_SHIFT}, "pad": {"button": JOY_BUTTON_B}},
	{"id": "lock_on", "name": "Lock on", "kb": {"key": KEY_Q}, "pad": {"axis": JOY_AXIS_TRIGGER_LEFT, "sign": 1}},
	{"id": "interact", "name": "Salvage / use", "kb": {"key": KEY_E}, "pad": {"button": JOY_BUTTON_X}},
	{"id": "ping", "name": "Ping (online)", "kb": {"key": KEY_G}, "pad": {"button": JOY_BUTTON_LEFT_SHOULDER}},
	{"id": "parts", "name": "Buster parts", "kb": {"key": KEY_TAB}, "pad": {"button": JOY_BUTTON_BACK}},
	{"id": "menu", "name": "Menu", "kb": {"key": KEY_ESCAPE}, "pad": {"button": JOY_BUTTON_START}},
	{"id": "chat", "name": "Chat (online)", "kb": {"key": KEY_T}, "pad": {}},
	{"id": "callout_1", "name": "Callout: Help!", "kb": {"key": KEY_1}, "pad": {"button": JOY_BUTTON_DPAD_UP}},
	{"id": "callout_2", "name": "Callout: Over here!", "kb": {"key": KEY_2}, "pad": {"button": JOY_BUTTON_DPAD_RIGHT}},
	{"id": "callout_3", "name": "Callout: Nice!", "kb": {"key": KEY_3}, "pad": {"button": JOY_BUTTON_DPAD_DOWN}},
	{"id": "callout_4", "name": "Callout: Wait up!", "kb": {"key": KEY_4}, "pad": {"button": JOY_BUTTON_DPAD_LEFT}},
]
# Movement on a controller always uses the left stick.
const STICK_MOVES = {"move_forward": [JOY_AXIS_LEFT_Y, -1], "move_back": [JOY_AXIS_LEFT_Y, 1], "move_left": [JOY_AXIS_LEFT_X, -1], "move_right": [JOY_AXIS_LEFT_X, 1]}
const PAD_NAMES = {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right"}

var path = PATH
var mouse_sensitivity = 1.0
var look_speed = 1.0
var invert_y = false
var vibration = true
var fullscreen = false
var camera_effects = true
var map_zoom = false
var fov = 67.0
var bindings: Dictionary = {}
var using_pad = false
var loaded = false

func _ready() -> void:
	if OS.has_feature("web"): path = WEB_PATH
	reset_bindings()
	load_settings()
	apply_bindings()
	apply_display()

func reset_bindings() -> void:
	bindings.clear()
	for a in ACTIONS: bindings[a.id] = {"kb": a.kb.duplicate(), "pad": a.pad.duplicate()}

func action_name(id: String) -> String:
	for a in ACTIONS:
		if a.id == id: return a.name
	return id

# Rebuild the InputMap from the current bindings plus the fixed extras.
func apply_bindings() -> void:
	for a in ACTIONS: set_action(a.id, binding_events(bindings[a.id]))
	for id in STICK_MOVES:
		var stick = InputEventJoypadMotion.new()
		stick.axis = STICK_MOVES[id][0]
		stick.axis_value = STICK_MOVES[id][1]
		InputMap.action_add_event(id, stick)
	# Right mouse button and middle mouse are permanent extras for lock-on and ping.
	InputMap.action_add_event("lock_on", mouse_event(MOUSE_BUTTON_RIGHT))
	InputMap.action_add_event("ping", mouse_event(MOUSE_BUTTON_MIDDLE))
	var look = {"look_left": [JOY_AXIS_RIGHT_X, -1], "look_right": [JOY_AXIS_RIGHT_X, 1], "look_up": [JOY_AXIS_RIGHT_Y, -1], "look_down": [JOY_AXIS_RIGHT_Y, 1]}
	for id in look:
		var stick = InputEventJoypadMotion.new()
		stick.axis = look[id][0]
		stick.axis_value = look[id][1]
		set_action(id, [stick])
	set_action("switch_digger", [key_event(KEY_C), pad_button(JOY_BUTTON_Y)])
	set_action("mute", [key_event(KEY_M)])
	set_action("choice_1", [key_event(KEY_1)])
	set_action("choice_2", [key_event(KEY_2)])
	set_action("choice_3", [key_event(KEY_3)])
	# Menus: arrows, D-pad and the left stick move; Enter/A confirm; Esc/B go back.
	var nav = {"nav_up": [KEY_UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1], "nav_down": [KEY_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1], "nav_left": [KEY_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1], "nav_right": [KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1]}
	for id in nav:
		var stick = InputEventJoypadMotion.new()
		stick.axis = nav[id][2]
		stick.axis_value = nav[id][3]
		set_action(id, [key_event(nav[id][0]), pad_button(nav[id][1]), stick], 0.5)
	set_action("nav_accept", [key_event(KEY_ENTER), key_event(KEY_KP_ENTER), pad_button(JOY_BUTTON_A)])
	set_action("nav_back", [key_event(KEY_ESCAPE), pad_button(JOY_BUTTON_B)])

func set_action(id: String, events: Array, deadzone: float = STICK_DEADZONE) -> void:
	if InputMap.has_action(id): InputMap.erase_action(id)
	InputMap.add_action(id, deadzone)
	for e in events: InputMap.action_add_event(id, e)

func binding_events(b: Dictionary) -> Array:
	var events = []
	var kb: Dictionary = b.get("kb", {})
	if kb.has("key"): events.append(key_event(int(kb.key)))
	elif kb.has("mouse"): events.append(mouse_event(int(kb.mouse)))
	var pad: Dictionary = b.get("pad", {})
	if pad.has("button"): events.append(pad_button(int(pad.button)))
	elif pad.has("axis"):
		var motion = InputEventJoypadMotion.new()
		motion.axis = int(pad.axis)
		motion.axis_value = float(pad.get("sign", 1))
		events.append(motion)
	return events

func key_event(code: int) -> InputEventKey:
	var e = InputEventKey.new()
	e.physical_keycode = code
	return e

func mouse_event(button: int) -> InputEventMouseButton:
	var e = InputEventMouseButton.new()
	e.button_index = button
	return e

func pad_button(button: int) -> InputEventJoypadButton:
	var e = InputEventJoypadButton.new()
	e.button_index = button
	return e

# Turn a pressed key/button into a binding for the given column ("kb" or "pad").
func binding_from_event(event: InputEvent, column: String) -> Dictionary:
	if column == "kb":
		if event is InputEventKey and event.pressed and not event.echo:
			var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			return {"key": code}
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			return {"mouse": event.button_index}
	else:
		if event is InputEventJoypadButton and event.pressed: return {"button": event.button_index}
		if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.6:
			return {"axis": event.axis, "sign": 1}
	return {}

# Assign a binding; an action that already used it takes over the old one (a swap).
func rebind(id: String, column: String, binding: Dictionary) -> void:
	if binding.is_empty() or not bindings.has(id): return
	var previous: Dictionary = bindings[id][column]
	for other in bindings:
		if other != id and bindings[other][column] == binding: bindings[other][column] = previous.duplicate()
	bindings[id][column] = binding
	apply_bindings()
	save_settings()

func binding_label(b: Dictionary) -> String:
	if b.has("key"):
		var name = OS.get_keycode_string(int(b.key))
		return {"Escape": "Esc", "Space": "Space", "Shift": "Shift"}.get(name, name)
	if b.has("mouse"): return {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB", MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5"}.get(int(b.mouse), "Mouse")
	if b.has("button"): return PAD_NAMES.get(int(b.button), "Button %d" % int(b.button))
	if b.has("axis"): return "LT" if int(b.axis) == JOY_AXIS_TRIGGER_LEFT else "RT"
	return "—"

# Button prompt for whichever device the player used last.
func prompt(id: String) -> String:
	if id == "move": return "L-Stick" if using_pad else "WASD"
	if id == "look": return "R-Stick" if using_pad else "Mouse"
	if not bindings.has(id): return ""
	var label = binding_label(bindings[id]["pad" if using_pad else "kb"])
	return label if label != "—" or not using_pad else binding_label(bindings[id].kb)

func _input(event: InputEvent) -> void:
	# Prompts follow the last device touched.
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5): using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 4): using_pad = false

func rumble(weak: float, strong: float, seconds: float) -> void:
	if not vibration or not using_pad: return
	for device in Input.get_connected_joypads(): Input.start_joy_vibration(device, weak, strong, seconds)

func apply_display() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()

func load_settings() -> void:
	if not FileAccess.file_exists(path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	mouse_sensitivity = clampf(float(data.get("mouse_sensitivity", 1.0)), 0.2, 3.0)
	look_speed = clampf(float(data.get("look_speed", 1.0)), 0.2, 3.0)
	invert_y = data.get("invert_y", false) == true
	vibration = data.get("vibration", true) == true
	fullscreen = data.get("fullscreen", false) == true
	map_zoom = data.get("map_zoom", false) == true
	camera_effects = data.get("camera_effects", true) == true
	fov = clampf(float(data.get("fov", 67.0)), 55.0, 85.0)
	var saved = data.get("bindings", {})
	if saved is Dictionary:
		for id in saved:
			if not bindings.has(id) or not saved[id] is Dictionary: continue
			for column in ["kb", "pad"]:
				var b = saved[id].get(column)
				if b is Dictionary and valid_binding(b, column): bindings[id][column] = to_ints(b)
	loaded = true

func valid_binding(b: Dictionary, column: String) -> bool:
	if b.is_empty(): return true
	if column == "kb": return b.has("key") or b.has("mouse")
	return b.has("button") or b.has("axis")

func to_ints(b: Dictionary) -> Dictionary:
	var out = {}
	for k in b: out[k] = int(b[k])
	return out

func save_settings() -> void:
	var game = get_parent()
	if game and game.get("smoke_test"): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"mouse_sensitivity": mouse_sensitivity, "look_speed": look_speed, "invert_y": invert_y, "vibration": vibration, "fullscreen": fullscreen, "camera_effects": camera_effects, "map_zoom": map_zoom, "fov": fov, "bindings": bindings}, "\t"))
