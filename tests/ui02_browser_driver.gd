extends Node

# Test-export entry point only. Production presets exclude tests/*. The actual
# game, UI, input, account HTTP and relay code run unchanged below this node.
var game: Node3D
var bridge: JavaScriptObject
var clock = 0.0

func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)
	game.sound.muted = true
	bridge = JavaScriptBridge.create_callback(command)
	JavaScriptBridge.get_interface("window").ui02Command = bridge

func command(arguments: Array) -> void:
	var request = JSON.parse_string(str(arguments[0]))
	match str(request.op):
		"sign_in": game.account.sign_in_email(str(request.email), str(request.password))
		"create":
			game.mode = "online"
			game.net.create_lobby("UI02 disposable", false)
		"join":
			game.mode = "online"
			game.net.join_lobby(str(request.code))
		"ready": game.net.set_ready(true)
		"start": game.host_start_run()
		"solo": game.start_run(49381)
		"protect": game.player.invincible = 100000
		"cache":
			var caches = game.interactables.filter(func(o): return o.kind == "cache" and not o.used)
			var cache = caches[0]
			game.rooms[cache.room].cleared = true
			game.scrap = 1000
			game.perform_interact(cache, game.player)
		"xp": game.award_pickup({"kind": "xp", "value": game.player.xp_required}, game.player)
		"milestone": game.guardian_dead = true
		"save": game.save_checkpoint()
		"resume": game.continue_saved_dig()

func _process(dt: float) -> void:
	clock += dt
	if clock < 0.1 or not is_instance_valid(game.player): return
	clock = 0
	var p = game.player
	var position = p.global_position
	var camera = p.camera.global_position
	var peers = {}
	for id in game.roster:
		peers[id] = game.roster[id].get("pending", [])
	var buttons = []
	for hit in game.hud.hits:
		var point: Vector2 = (hit.rect.get_center() * game.hud.ui_scale + game.hud.ui_offset) / game.get_viewport().get_visible_rect().size
		buttons.append({"action": hit.action, "value": hit.get("value", 0), "x": point.x, "y": point.y})
	var state = {"mode": game.mode, "run": game.run_id, "seed": game.run_seed,
		"source": game.profile_source, "signed": game.account.signed_in(),
		"confirmed": game.net.account_confirmed, "account_state": game.account.state,
		"auth_note": game.account.auth.note, "account_run": game.account.server_run,
		"player_id": game.net.player_id, "code": game.net.lobby_code, "slot": game.net.slot,
		"host": game.net.is_host(), "ready": game.net.own_ready(), "can_start": game.net.can_start(), "acked": game.net.selection_acknowledged(),
		"net_status": game.net.status, "waiting_sync": game.net.awaiting_run_sync,
		"pending": game.build_state().pending, "peers": peers,
		"choice_kind": game.choice_kind, "choice_picks": game.choice_picks,
		"choice_ready": game.choice_input_ready(), "items": p.items, "damage": p.power_picks,
		"health": p.base_health, "fire_rate": p.fire_multiplier, "milestones": p.milestones,
		"shots": p.shot_count, "time": game.run_time, "guard": game.action_guard,
		"pos": [position.x, position.y, position.z], "camera": [camera.x, camera.y, camera.z], "buttons": buttons}
	JavaScriptBridge.eval("window.ui02State=" + JSON.stringify(state), true)
