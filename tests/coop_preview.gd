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
	game.checkpoint_path = "res://save/coop-preview-run.dat"
	await process_frame
	# The lobby browser with an open, a password and a locked lobby.
	game.net.status = "online"
	game.net.public_lobbies = [
		{"code": "K7QX2", "name": "Ali's Dig", "host": "Ali", "players": 3, "max": 4, "state": "run", "depth": 2, "locked": false, "password": false},
		{"code": "P4RTY", "name": "Friday Ruins", "host": "Maya", "players": 1, "max": 4, "state": "lobby", "depth": 1, "locked": false, "password": true},
		{"code": "LOCK3", "name": "Speedrun Practice", "host": "Rex", "players": 2, "max": 4, "state": "run", "depth": 3, "locked": true, "password": false}]
	game.mode = "online"
	await capture("browser")
	# Stage a lobby: we are the host, Roll and a second Mega joined.
	game.net.slot = 1
	game.net.host_slot = 1
	game.net.lobby_code = "K7QX2"
	game.net.lobby_password = "relic"
	game.net.player_name = "Ali"
	game.net.lobby = {"name": "Ali's Dig", "isPublic": true, "locked": true, "hostSlot": 1, "players": [{"slot": 1, "name": "Ali", "id": "a"}, {"slot": 2, "name": "Sam", "id": "s"}, {"slot": 3, "name": "Jordan", "id": "j"}]}
	game.add_chat(2, "Sam", "I'll take Roll this time", false)
	game.add_chat(3, "Jordan", "Siege buster ready. Let's go!", false)
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
	game.add_chat(3, "Jordan", "Cache is behind the pillar", false)
	game.add_chat(2, "Sam", "Help!", true)
	sam.speak("Help!")
	game.place_ping(3, Vector3(-3, 0, -3), "Cache!")
	await capture("dig")
	game.player.downed = true
	game.player.revive = 0.3
	game.message_time = 0
	sam.downed = false
	sam.speak("")
	game.player.update_camera(1)
	await capture("downed")
	game.player.downed = false
	game.net.status = "reconnecting"
	game.net.reconnect_attempts = 3
	game.player.update_camera(1)
	await capture("reconnect")
	game.net.status = "online"
	game.open_relic_choice()
	await capture("choice")
	game.save_checkpoint()
	var saved = game.load_checkpoint()
	game.finish_run(true)
	await capture("end")
	game.net.slot = 0
	game.saved_dig = saved
	game.show_title()
	await capture("title")
	for path in [game.save_path, game.sound.settings_path, game.checkpoint_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
