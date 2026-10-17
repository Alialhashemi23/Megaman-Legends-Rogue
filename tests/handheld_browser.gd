extends Node

# Test-only browser fixture. Production exports exclude tests/* and these hooks.
var game: Node3D
var bridge: JavaScriptObject
var clock = 0.0

func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)
	game.sound.muted = true
	game.net.set_process(false)
	game.account.set_process(false)
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 500
	bridge = JavaScriptBridge.create_callback(command)
	JavaScriptBridge.get_interface("window").ui04Command = bridge

func command(arguments: Array) -> void:
	var request: Dictionary = JSON.parse_string(str(arguments[0]))
	match str(request.op):
		"preset":
			game.settings.handheld_ui = bool(request.value)
			game.settings.large_minimap = bool(request.value)
			game.settings.save_settings()
		"screen":
			game.net.slot = 0
			game.net.status = "offline"
			var screen = str(request.value)
			if screen in ["play", "choice"]:
				if not is_instance_valid(game.player): game.start_run(40404)
				game.message_time = 0
				game.player.set_physics_process(false)
				game.player.lock_target = null
				for enemy in game.enemies:
					if is_instance_valid(enemy): enemy.set_physics_process(false)
				game.settings.close_camera = bool(request.get("close", false))
				game.player.update_camera(1.0)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if screen == "lobby":
				game.net.slot = 1
				game.net.host_slot = 1
				game.net.status = "online"
				game.net.lobby_code = "UI04"
				game.net.server_ready = true
				game.net.selection_seq = 1
				game.net.sent_selection = game.net.current_selection()
				game.net.selection_fingerprint = game.net.current_selection()
				var members = []
				for i in 4:
					members.append({"slot": i + 1, "id": "preview-%d" % i, "name": ["Mega Test", "Roll Test", "Tron Test", "Servbot Test"][i], "ready": true, "selection": game.net.current_selection() if i == 0 else {"character": i, "weapon": i, "spec": "", "skills": []}})
				game.net.lobby = {"name": "Handheld Preview", "players": members, "readiness": {"phase": "idle", "canStart": true, "setupRev": 1}}
			if screen == "choice":
				game.choice_kind = "relic"
				game.choice_items = ["lens", "spring", "ember"]
				game.choice_opened_at = Time.get_ticks_msec() - 1000
				game.arm_choice()
			if screen == "solo_prep": game.show_solo_prep()
			game.mode = screen
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		"auth":
			game.account.auth.view = str(request.value)
			game.mode = "account"
		"choice_kind":
			game.choice_kind = str(request.value)
			game.choice_items = game.LEVEL_CHOICES.slice(0, 3) if game.choice_kind == "level" else game.MILESTONES.keys().slice(0, 3)
			game.choice_opened_at = Time.get_ticks_msec() - 1000
			game.mode = "choice"
		"review": game.hud.buy_grid_node(0)
		"lock":
			var target = game.spawn_enemy(game.player.position + Vector3(0, 0, -8), 0, 0)
			target.set_physics_process(false)
			game.player.lock_target = target
			game.player.update_camera(1.0)

func _process(dt: float) -> void:
	clock += dt
	if clock < 0.1: return
	clock = 0
	var buttons = []
	for hit in game.hud.hits:
		var point: Vector2 = (hit.rect.get_center() * game.hud.ui_scale + game.hud.ui_offset) / game.get_viewport().get_visible_rect().size
		buttons.append({"action": hit.action, "value": hit.get("value", 0), "x": point.x, "y": point.y, "valid": Rect2(Vector2.ZERO, game.hud.BASE).encloses(hit.rect) if hit.rect.has_area() else true})
	JavaScriptBridge.eval("window.ui04State=" + JSON.stringify({"mode": game.mode, "handheld": game.settings.handheld_ui, "large_map": game.settings.large_minimap, "close": game.settings.close_camera, "focus": game.hud.focused_action(), "buttons": buttons}), true)
