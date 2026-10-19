extends SceneTree

var game: Node3D
var index = 1
var scenario = "win"
var folder = ""

func _initialize() -> void:
	run.call_deferred()

func fail(label: String) -> void:
	push_error("PT08_FAIL: " + label)
	quit(1)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--index="): index = int(arg.substr(8))
		if arg.begins_with("--scenario="): scenario = arg.substr(11)
		if arg.begins_with("--folder="): folder = arg.substr(9)
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = folder.path_join("p%d-profile.json" % index)
	game.checkpoint_path = folder.path_join("p%d-checkpoint.dat" % index)
	root.add_child(game)
	game.net_test = "pt08-driver"
	game.net.profile_path = folder.path_join("p%d-online.json" % index)
	game.settings.path = folder.path_join("p%d-settings.json" % index)
	game.sound.settings_path = folder.path_join("p%d-audio.json" % index)
	game.account.cache_root = folder.path_join("p%d-accounts" % index)
	game.sound.muted = true
	game.mode = "online"
	game.net.refresh_list()
	var joined = false
	var code = ""
	var first_run = ""
	var stage = 0
	var run_seen = 0
	var ended = false
	var saw_remote_fire = false
	var deadline = Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var net = game.net
		if net.connected() and not joined:
			if index == 1:
				net.create_lobby("PT08-" + scenario, true)
				joined = true
			else:
				for info in net.public_lobbies:
					if info.name == "PT08-" + scenario:
						net.join_lobby(str(info.code))
						joined = true
		if net.active() and code == "": code = net.lobby_code
		if stage == 0 and net.active() and net.members().size() == 2 and net.ready_phase() == "idle" and net.selection_acknowledged():
			if not net.own_ready(): net.set_ready(true)
			if index == 1 and net.can_start(): game.host_start_run()
		if stage == 0 and game.in_run() and game.world_running():
			first_run = game.run_id
			stage = 1
			run_seen = Time.get_ticks_msec()
			for enemy in game.enemies: enemy.set_physics_process(false)
			game.flare_patch(game.enemies[0].position, 12, 1, game.player)
		if stage == 1:
			for patch in game.flare_patches:
				if not patch.local: saw_remote_fire = true
		if stage == 1 and Time.get_ticks_msec() - run_seen > 600 and not ended:
			ended = true
			if scenario == "down":
				game.player.hp = 0
				game.player.downed = true
			elif index == 1: game.end_run_all(scenario in ["win", "guest_leave"])
		if stage == 1 and game.mode == "end" and game.hud.previous_mode == "end":
			if not saw_remote_fire: fail("PT09 teammate ignition was not replicated"); return
			if not net.active() or net.lobby_code != code: fail("results lost lobby"); return
			if not game.hud.hits.any(func(h): return h.action == "lobby_room"): fail("no Return to Lobby action"); return
			game.hud.activate("lobby_room")
			stage = 2
		if stage == 2 and net.lobby.get("state", "") == "lobby" and net.ready_phase() == "idle":
			if net.own_ready(): fail("Ready retained after results"); return
			if game.mode != "lobby" or net.lobby_code != code: fail("did not return to same lobby"); return
			var file = FileAccess.open(folder.path_join("p%d-returned" % index), FileAccess.WRITE)
			file.store_string(code)
			file.close()
			stage = 3
		if stage == 3 and FileAccess.file_exists(folder.path_join("p1-returned")) and FileAccess.file_exists(folder.path_join("p2-returned")):
			if scenario == "guest_leave" and index == 2:
				game.leave_online()
				print("PT08_PASS " + JSON.stringify({"index": index, "scenario": scenario, "code": code, "left": true}))
				quit(); return
			var expected = 1 if scenario == "guest_leave" else 2
			if net.members().size() != expected: continue
			if net.selection_acknowledged():
				if not net.own_ready(): net.set_ready(true)
				if index == 1 and net.can_start(): game.host_start_run()
		if stage == 3 and game.in_run() and game.world_running():
			if game.run_id == first_run or net.lobby_code != code: fail("new dig failed or code changed"); return
			print("PT08_PASS " + JSON.stringify({"index": index, "scenario": scenario, "code": code, "restarted": true}))
			quit(); return
	fail("timeout at stage %d mode %s" % [stage, game.mode])

