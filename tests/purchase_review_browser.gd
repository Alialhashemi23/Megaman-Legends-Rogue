extends Node

# Test-only exported entry point; production excludes tests/*. Real Workshop
# controls/rendering and account outbox run below; only HTTP replies are mocked.
var game: Node3D
var bridge: JavaScriptObject
var clock = 0.0
var reply = "offline"
var remote: Dictionary
var operations: Dictionary = {}
var sent: Array = []

func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)
	game.sound.muted = true
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 500
	game.mode = "workshop"
	game.account.transport = fake
	bridge = JavaScriptBridge.create_callback(command)
	JavaScriptBridge.get_interface("window").ui03Command = bridge

func document(wallet: int, revision: int) -> Dictionary:
	var profile = DiverProgression.fresh()
	profile.zenny = wallet
	return {"account": {"id": "acc_ui03_preview", "name": "Workshop Test", "role": "player"}, "profile": profile, "revision": revision}

func fake(path: String, body: Variant, _method: int) -> Dictionary:
	if path == "/api/v1/profile": return {"code": 200, "data": remote.duplicate(true)} if not remote.is_empty() else {"code": 404, "data": {}}
	if path != "/api/v1/purchases": return {"code": 503, "data": {}}
	sent.append(str(body.op_id))
	if reply == "offline": return {"code": 503, "data": {}}
	if reply == "conflict":
		remote = document(270, 8)
		remote.profile.trees["0"] = ["frame"]
		return {"code": 409, "data": {"error": {"code": "revision_conflict"}, "profile": remote.profile, "revision": remote.revision}}
	if not operations.has(body.op_id):
		var key = str(int(body.character))
		var tree: Array = remote.profile.trees.get(key, []).duplicate()
		tree.append(str(body.node))
		remote.profile.trees[key] = tree
		remote.profile.zenny -= DiverProgression.node(str(body.node)).cost
		remote.revision += 1
		operations[body.op_id] = remote.duplicate(true)
	return {"code": 200, "data": operations[body.op_id].duplicate(true)}

func command(arguments: Array) -> void:
	var request: Dictionary = JSON.parse_string(str(arguments[0]))
	match str(request.op):
		"cloud":
			remote = document(500, 7)
			game.account.receive_profile(200, remote.duplicate(true), PackedStringArray())
		"reply": reply = str(request.value)
		"wallet": game.meta.zenny = int(request.value)
		"specialization":
			game.meta = DiverProgression.fresh()
			game.meta.zenny = 900
			game.meta.trees["2"] = ["frame", "mobility", "magnet", "loader"]
			game.hud.select_workshop_character(2)
			game.hud.workshop_focus_pending = false
			game.hud.grid_reveal(12)
			game.hud.focus_action("grid_node", 12)
		"block_save":
			var file = FileAccess.open("user://ui03-blocked", FileAccess.WRITE)
			file.store_string("intentional storage failure")
			file.close()
			game.save_path = "user://ui03-blocked/guest.json"

func _process(dt: float) -> void:
	clock += dt
	if clock < 0.1: return
	clock = 0
	var buttons = []
	for hit in game.hud.hits:
		var point: Vector2 = (hit.rect.get_center() * game.hud.ui_scale + game.hud.ui_offset) / game.get_viewport().get_visible_rect().size
		buttons.append({"action": hit.action, "value": hit.get("value", 0), "x": point.x, "y": point.y})
	var state = {"mode": game.mode, "wallet": game.meta.zenny, "trees": game.meta.trees,
		"review": game.hud.purchase_review, "focus": game.hud.focused_action(),
		"source": game.profile_source, "status": game.account.status, "sent": sent,
		"pending": game.account.outbox.size(), "requests": game.account.requests.size(), "ready": game.hud.purchase_input_ready(), "buttons": buttons}
	JavaScriptBridge.eval("window.ui03State=" + JSON.stringify(state), true)
