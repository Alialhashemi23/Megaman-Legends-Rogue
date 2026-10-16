extends SceneTree

# One process in ready_e2e.mjs's serial, disposable relay sessions.
var game: Node3D
var index = 1
var party = 2
var scenario = "slow"
var session = ""
var folder = ""
var old_bytes: PackedByteArray
var old_world: Dictionary
var held_account = false
var account_released = false
var prepare_seen = 0
var staged_seen = false
var canceled = false
var aborts = 0
var previous_phase = "idle"
var forged = false
var run_requests: Array = []
var leases: Dictionary = {}
var failed_once = false
var elapsed = 0.0

func _initialize() -> void:
	run.call_deferred()

func fail(label: String) -> void:
	push_error("READY_SESSION_FAIL: " + label)
	quit(1)

func http(path: String, body: Variant, _method: int) -> Dictionary:
	if path == "/api/v1/lobby-ticket": return {"code": 200, "data": {"ticket": "isolated-ticket"}}
	if path.ends_with("/heartbeat"): return {"code": 200, "data": {"run": {"id": "run_fixture_" + str(index)}}}
	if path == "/api/v1/runs":
		run_requests.append(body.duplicate(true))
		if scenario == "failure" and not failed_once:
			failed_once = true
			return {"code": 503, "data": {}}
		if not leases.has(body.op_id): leases[body.op_id] = "run_fixture_" + str(index)
		return {"code": 201, "data": {"run": {"id": leases[body.op_id]}}}
	return {"code": 200, "data": {}}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ready-index="): index = int(arg.substr(14))
		if arg.begins_with("--ready-party="): party = int(arg.substr(14))
		if arg.begins_with("--ready-scenario="): scenario = arg.substr(17)
		if arg.begins_with("--ready-session="): session = arg.substr(16)
		if arg.begins_with("--ready-folder="): folder = arg.substr(15)
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = folder.path_join("p%d-archive.json" % index)
	game.checkpoint_path = folder.path_join("p%d-checkpoint.dat" % index)
	root.add_child(game)
	game.launch_prepared.connect(func(_attempt): staged_seen = true)
	game.net_test = "ready-driver"
	game.sound.muted = true
	game.solo_checkpoints = true
	game.start_run(124)
	game.run_time = 77
	game.player.add_item("lens")
	game.save_checkpoint()
	old_world = game.world_state()
	old_bytes = FileAccess.get_file_as_bytes(game.checkpoint_path)
	game.show_title()
	if index == party:
		game.guest_meta = game.meta.duplicate(true)
		game.meta = DiverProgression.fresh()
		game.profile_source = "account"
		game.account.identity = {"id": "acc_fixture_%d" % index, "name": "Isolated Account"}
		game.account.state = "signed_in"
		game.account.cache_root = folder.path_join("p%d-accounts" % index)
		game.account.transport = http
	game.net.player_name = "P%d" % index
	game.mode = "online"
	game.net.refresh_list()
	var entered = false
	var frame_clock = Time.get_ticks_msec()
	while elapsed < 35:
		await process_frame
		var now = Time.get_ticks_msec()
		elapsed += float(now - frame_clock) / 1000
		frame_clock = now
		var net = game.net
		if net.connected() and not entered:
			if index == 1:
				net.create_lobby(session, true)
				entered = true
			else:
				for info in net.public_lobbies:
					if info.name == session:
						net.join_lobby(str(info.code))
						entered = true
		var phase = net.ready_phase()
		if phase == "idle" and previous_phase in ["countdown", "preparing"]:
			aborts += 1
			if FileAccess.get_file_as_bytes(game.checkpoint_path) != old_bytes: fail("abort replaced prior checkpoint"); return
		previous_phase = phase
		if index == party and scenario in ["slow", "cancel"] and phase == "countdown" and not held_account:
			held_account = true
			game.account.busy = true
		if not game.launch_attempt.is_empty():
			if prepare_seen == 0: prepare_seen = now
			if game.world_running() or game.in_run(): fail("precommit gameplay became active"); return
			if game.launch_staged:
				staged_seen = true
				if game.run_time != 0: fail("staged clock advanced"); return
			if FileAccess.get_file_as_bytes(game.checkpoint_path) != old_bytes: fail("preparation replaced prior checkpoint"); return
			if not game.account.outbox.is_empty(): fail("preparation wrote account progress"); return
		if held_account and not account_released and prepare_seen > 0 and now - prepare_seen > 1200:
			account_released = true
			game.account.busy = false
			game.account.pump()
		if scenario == "failure" and index == party and failed_once and phase == "idle" and game.account.server_run == "" and not game.account_starting:
			game.account.retry_run()
		if net.active() and net.members().size() == party and phase == "idle" and net.selection_acknowledged():
			if not net.own_ready(): net.set_ready(true)
			if index == 1 and not forged:
				forged = true
				net.broadcast([DiverNet.M_START, 333, party, "forged-start"])
				net.broadcast([DiverNet.M_SYNC, old_world, {}])
			if index == 1 and net.can_start(): game.host_start_run()
		if scenario == "cancel" and index == 1 and phase == "preparing" and not canceled and game.launch_staged and party in net.readiness().get("waitingSlots", []):
			canceled = true
			net.cancel_launch()
		if game.in_run() and game.world_running() and game.run_time > 0.2:
			if game.run_id == "forged-start" or game.run_seed == 333: fail("legacy packets bypassed Ready"); return
			if game.party_size != party or game.player.character != 0 or not game.player.items.is_empty(): fail("fresh party/loadout mismatch"); return
			if not staged_seen: fail("commit had no staged world"); return
			if scenario in ["cancel", "failure"] and aborts == 0: fail("expected cancel/failure path was skipped"); return
			if index == party:
				if leases.size() != 1: fail("preparation allocated more than one unplayed lease"); return
				if scenario == "cancel" and run_requests.size() != 1: fail("cancel/retry did not reuse the late lease"); return
			print("READY_SESSION_PASS " + JSON.stringify({"index": index, "party": party, "scenario": scenario, "seed": game.run_seed, "runId": game.run_id, "aborts": aborts, "leases": leases.size(), "requests": run_requests.size()}))
			quit(0)
			return
	fail("timeout, phase=%s mode=%s error=%s ack=%s party=%s sent=%s" % [game.net.ready_phase(), game.mode, game.net.error_text, game.net.selection_acknowledged(), JSON.stringify(game.net.lobby), JSON.stringify(game.net.sent_selection)])
