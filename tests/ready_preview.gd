extends SceneTree

# Native readiness gallery, entirely fixture state and isolated files.
var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://save/net02-captures"))
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = "res://save/net02-preview-archive.json"
	game.checkpoint_path = "res://save/net02-preview-checkpoint.dat"
	root.add_child(game)
	game.set_process(false)
	game.net.set_process(false)
	game.account.set_process(false)
	game.sound.muted = true
	var net = game.net
	net.slot = 1
	net.host_slot = 1
	net.lobby_code = "K7QX2"
	net.player_id = "fixture-1"
	net.player_name = "Mega"
	net.status = "online"
	net.server_ready = true
	net.command_transport = func(_message): return true
	for size in [Vector2i(1440, 900), Vector2i(960, 540)]:
		root.size = size
		for phase in ["idle", "all_ready", "countdown", "preparing"]:
			var players = []
			for i in 4:
				players.append({"slot": i + 1, "id": "fixture-%d" % (i + 1), "name": ["Mega", "Roll", "Tron", "Servbot"][i], "ready": phase != "idle" or i == 0, "selection": {"seq": 1, "character": 0, "weapon": 0, "spec": "", "buildRev": 1}})
			net.lobby = {"code": net.lobby_code, "name": "THE TIDAL ARCHIVE", "isPublic": true, "hostSlot": 1, "players": players, "state": "lobby", "readiness": {"v": 1, "setupRev": 2, "stateRev": 3, "phase": "idle" if phase == "all_ready" else phase, "attemptId": "fixture-attempt" if phase in ["countdown", "preparing"] else "", "deadlineMs": 0, "prepareDeadlineMs": 0, "waitingSlots": [2, 3, 4] if phase == "idle" else [4] if phase == "preparing" else [], "canStart": phase == "all_ready"}}
			net.sent_selection = players[0].selection.duplicate()
			net.selection_seq = 1
			net.selection_fingerprint = net.current_selection()
			net.countdown_seen = Time.get_ticks_msec()
			game.mode = "launch_preparing" if phase == "preparing" else "lobby"
			for i in 3:
				game.hud.queue_redraw()
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://save/net02-captures/%s-%dx%d.png" % [phase, size.x, size.y])
	print("READY_GALLERY_SAVED")
	quit()
