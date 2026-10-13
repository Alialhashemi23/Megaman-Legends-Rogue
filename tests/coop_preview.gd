extends SceneTree

# Renders the online co-op HUD states without a server: a staged three-digger
# party with one teammate down. Saves screenshots/coop-*.png.
#   xvfb-run godot --path . --script tests/coop_preview.gd

var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture(name: String) -> void:
	for n in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/coop-%s.png" % name)
	print("saved coop-%s" % name)

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.save_path = "res://save/coop-preview.json"
	game.sound.settings_path = "res://save/coop-preview-audio.json"
	game.sound.muted = true
	await process_frame
	# Stage a lobby: we are the host, Roll and a second Mega joined.
	game.net.slot = 1
	game.net.lobby_code = "K7QX2"
	game.net.player_name = "Ali"
	game.net.lobby = {"name": "Ali's Dig", "isPublic": true, "players": [{"slot": 1, "name": "Ali"}, {"slot": 2, "name": "Sam"}, {"slot": 3, "name": "Jordan"}]}
	game.peers = {2: {"character": 1, "weapon": 0, "items": {"lens": 2}, "level": 3, "name": "Sam"}, 3: {"character": 0, "weapon": 2, "items": {}, "level": 2, "name": "Jordan"}}
	game.mode = "lobby"
	await capture("lobby")
	game.start_run(49381, 3)
	game.message_time = 0
	for slot in game.remote_players:
		var proxy: DiverPlayer = game.remote_players[slot]
		proxy.set_physics_process(false)
	var sam: DiverPlayer = game.remote_players[2]
	var jordan: DiverPlayer = game.remote_players[3]
	game.player.position = Vector3(0, 0.12, 1)
	game.player.yaw = 0.35
	game.player.pitch = -0.28
	sam.apply_state(Vector3(-1.4, 0.12, -1.0), Vector3.ZERO, 0.4, 0, Vector2.ZERO, DiverPlayer.FLAG_FLOOR | DiverPlayer.FLAG_DOWN, 0, 120, 0.45)
	sam.global_position = sam.net_pos
	jordan.apply_state(Vector3(2.6, 0.12, -3.5), Vector3.ZERO, -0.3, 0, Vector2.ZERO, DiverPlayer.FLAG_FLOOR | DiverPlayer.FLAG_AIM, 64, 100, 0)
	jordan.global_position = jordan.net_pos
	for proxy in [sam, jordan]:
		proxy.remote_process(0.5)
		proxy.set_physics_process(false)
	for n in 30:
		await physics_frame
		sam.visual.preview(1.0 / 30, true, false)
		jordan.visual.animate(1.0 / 30, Vector2.ZERO, true, 0, false, true, -0.1, 0)
		game.player.update_camera(1)
	game.notify("CHAMBER SECURED", "")
	await capture("dig")
	game.player.downed = true
	game.player.revive = 0.3
	game.message_time = 0
	await capture("downed")
	game.player.downed = false
	game.open_relic_choice()
	await capture("choice")
	game.finish_run(true)
	await capture("end")
	for path in [game.save_path, game.sound.settings_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
