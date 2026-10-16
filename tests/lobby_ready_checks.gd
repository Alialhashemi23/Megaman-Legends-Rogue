extends SceneTree

# Client readiness journeys with isolated disk state and controlled relay/HTTP replies.
var game: Node3D
var commands: Array = []
var requests: Array = []
var checks = 0
var failures = 0
var root_path = "res://save/ready-checks-" + DiverAccount.uuid()
var old_checkpoint: Dictionary = {}
var old_bytes = PackedByteArray()

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("READY_CHECK_FAILED: " + label)

func settle() -> void:
	for i in 4: await process_frame

func fresh(label: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await settle()
	commands.clear()
	requests.clear()
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = root_path.path_join(label + "-archive.json")
	game.checkpoint_path = root_path.path_join(label + "-checkpoint.dat")
	root.add_child(game)
	game.set_process(false)
	game.net_test = "ready-checks"
	game.net.set_process(false)
	game.account.set_process(false)
	game.account.cache_root = root_path.path_join(label + "-accounts")
	game.sound.muted = true
	game.solo_checkpoints = true
	game.start_run(42)
	game.run_time = 77
	game.player.add_item("lens")
	game.save_checkpoint()
	old_checkpoint = game.load_checkpoint()
	old_bytes = FileAccess.get_file_as_bytes(game.checkpoint_path)
	game.show_title()
	game.net.slot = 1
	game.net.host_slot = 1
	game.net.lobby_code = "K7QX2"
	game.net.player_id = "self"
	game.net.status = "online"
	game.net.server_ready = true
	game.net.command_transport = func(value): commands.append(value.duplicate(true)); return true
	game.mode = "lobby"
	game.net.accept_lobby(snapshot("idle", 1, false))
	game.net.accept_lobby(snapshot("idle", 2, false))
	await settle()

func snapshot(phase: String, state_rev: int, ready: bool, attempt: String = "") -> Dictionary:
	var own = {"slot": 1, "id": "self", "name": "Mega", "ready": ready}
	if not game.net.sent_selection.is_empty(): own.selection = game.net.sent_selection.duplicate()
	return {"code": "K7QX2", "name": "Ready checks", "hostSlot": 1, "state": "run" if phase == "running" else "lobby", "players": [own, {"slot": 2, "id": "friend", "name": "Roll", "ready": ready, "selection": {"seq": 1, "character": 1, "weapon": 1, "spec": "", "buildRev": 1}}], "readiness": {"v": 1, "setupRev": 2, "stateRev": state_rev, "phase": phase, "attemptId": attempt, "deadlineMs": 1000 if phase == "countdown" else 0, "prepareDeadlineMs": 61000 if phase == "preparing" else 0, "waitingSlots": [1, 2] if phase == "idle" and not ready else [2] if phase == "preparing" else [], "canStart": phase == "idle" and ready}}

func prepare(attempt: String, rev: int = 10) -> Dictionary:
	game.net.accept_lobby(snapshot("countdown", rev, true, attempt))
	var payload = {"t": "launch_prepare", "code": "K7QX2", "attemptId": attempt, "setupRev": 2, "hostSlot": 1, "slots": [1, 2], "seed": 734, "party": 2, "runId": "world-" + attempt, "timeoutMs": 60000}
	game.net.handle_command(payload)
	return payload

func abort(attempt: String, rev: int) -> void:
	game.net.handle_command({"t": "launch_aborted", "code": "K7QX2", "attemptId": attempt, "reason": "cancel"})
	game.net.accept_lobby(snapshot("idle", rev, false))

func checkpoint_unchanged() -> bool:
	return FileAccess.get_file_as_bytes(game.checkpoint_path) == old_bytes

func lease(path: String, body: Variant, _method: int) -> Dictionary:
	requests.append({"path": path, "body": body.duplicate(true) if body is Dictionary else body})
	if path.ends_with("/heartbeat"): return {"code": 200, "data": {"run": {"id": "run_unplayed_fixture"}}}
	return {"code": 201, "data": {"run": {"id": "run_unplayed_fixture"}}}

func run() -> void:
	await fresh("guest")
	var net = game.net
	net.accept_lobby(JSON.parse_string(JSON.stringify(snapshot("idle", 3, false))))
	verify(net.selection_acknowledged(), "Own published selection must be acknowledged")
	for state in ["restoring", "needs_sign_in"]:
		game.account.state = state
		var before = commands.size()
		net.set_ready(true)
		verify(commands.size() == before and not game.account_ready_to_prepare(), "Unconfirmed account state requires explicit account/Guest choice: " + state)
	game.account.state = "guest"
	var n = commands.size()
	game.host_start_run()
	verify(commands.size() == n and not game.in_run(), "Host cannot Start before all Ready")
	net.set_ready(true)
	verify(commands.back().t == "ready" and commands.back().setupRev == 2, "Ready sends current setup consent")
	net.accept_lobby(snapshot("idle", 3, true))
	game.host_start_run()
	verify(commands.back().t == "start_request" and game.mode == "lobby", "Host Start requests the relay without starting locally")
	verify(net.outbox.values().all(func(batch): return batch.all(func(m): return m[0] != DiverNet.M_START)), "Host never broadcasts legacy binary Start")
	net.accept_lobby(snapshot("idle", 2, false))
	verify(net.own_ready(), "Older snapshots cannot unready a current member")
	var malformed = snapshot("idle", 4, false)
	malformed.players[0].slot = 1.5
	net.accept_lobby(malformed)
	verify(net.own_ready(), "Malformed numeric slots do not replace the party snapshot")
	game.net_message(1, [DiverNet.M_START, 999, 2, "forged-start"])
	game.net_message(1, [DiverNet.M_SYNC, old_checkpoint.world, {}])
	verify(game.mode == "lobby" and checkpoint_unchanged(), "Old Start and idle Sync cannot bypass readiness or retire a checkpoint")
	var payload = prepare("first")
	verify(game.launch_staged and game.mode == "launch_preparing" and not game.in_run(), "Preparation builds an inactive world")
	verify(not game.world_running() and game.run_time == 0 and checkpoint_unchanged(), "No preparation simulation, clock or save replacement")
	var player = game.player
	var hp = player.hp
	game._process(0.5)
	verify(game.player == player and game.player.hp == hp and game.run_time == 0, "A staged world remains frozen while another player loads")
	var prepared_count = commands.filter(func(c): return c.t == "launch_prepared").size()
	net.handle_command(payload)
	verify(game.player == player and commands.filter(func(c): return c.t == "launch_prepared").size() == prepared_count, "Duplicate preparation does not rebuild or acknowledge twice")
	game.hud.select_character(2)
	verify(game.selected_character == 0 and not game.equip_spec(0, ""), "Loadout changes are locked during preparation")
	var commit = payload.duplicate()
	commit.t = "launch_commit"
	commit.attemptId = "old-attempt"
	net.handle_command(commit)
	verify(not game.in_run(), "Stale commit cannot promote a staged world")
	commit.attemptId = "first"
	Input.action_press("nav_accept")
	net.handle_command(commit)
	verify(game.mode == "play" and game.player == player and game.run_id == "world-first", "Commit promotes the exact prepared world once")
	verify(not game.world_running(), "Held confirm remains blocked after commit")
	game._process(0.5)
	verify(game.run_time == 0, "Held controls cannot advance simulation after commit")
	Input.action_release("nav_accept")
	game._process(0)
	verify(game.world_running(), "Controls release activates gameplay")
	var records = game.meta.runs
	net.handle_command(commit)
	verify(game.player == player and game.meta.runs == records, "Duplicate commit does not retire another save or rebuild")

	await fresh("abort")
	net = game.net
	prepare("cancel")
	abort("cancel", 11)
	verify(game.mode == "lobby" and game.launch_attempt.is_empty() and checkpoint_unchanged(), "Cancel discards only preparation and preserves the prior checkpoint")
	verify(game.meta.runs == 0 and game.meta.zenny == 0, "Cancel records no run or reward")
	prepare("disconnect", 12)
	net.clear_readiness(false)
	verify(game.launch_attempt.is_empty() and checkpoint_unchanged(), "Connection reset discards staged preparation without touching saves")
	net.handle_command(commit)
	verify(not game.in_run(), "A commit from a previous lobby context cannot start")

	await fresh("account")
	net = game.net
	game.profile_source = "account"
	game.account.state = "signed_in"
	game.account.identity = {"id": "acc_ready_fixture", "name": "Account fixture"}
	game.account.transport = lease
	game.account.busy = true
	prepare("slow")
	verify(not game.launch_staged and game.account_starting and checkpoint_unchanged(), "A slow account request holds preparation without retiring the old dig")
	abort("slow", 11)
	game.account.busy = false
	game.account.pump()
	await settle()
	verify(game.account.server_run == "run_unplayed_fixture" and game.mode == "lobby" and not game.launch_staged, "Late account success retains an unplayed lease without restarting canceled preparation")
	verify(checkpoint_unchanged() and not game.account.read_file("active.json", {}).has("world_run"), "Canceled lease has no world attachment and the previous checkpoint remains intact")
	var allocated = requests.filter(func(r): return r.path == "/api/v1/runs").size()
	prepare("retry", 12)
	await settle()
	verify(game.launch_staged and requests.filter(func(r): return r.path == "/api/v1/runs").size() == allocated, "A new deliberate attempt confirms and reuses the unplayed account lease")
	abort("retry", 13)
	verify(game.account.outbox.is_empty() and checkpoint_unchanged(), "Repeated cancel awards no result and preserves account/Guest progress")
	game.account.server_run = ""
	game.account.transport = func(path, body, _method): requests.append({"path": path, "body": body.duplicate(true)}); return {"code": 503, "data": {}}
	prepare("failure", 14)
	await settle()
	verify(commands.any(func(c): return c.t == "launch_failed" and c.code == "account"), "Account failure explicitly aborts the relay attempt")
	verify(game.profile_source == "account" and game.account.pending_run_callback.is_valid(), "Account failure retains explicit Retry without switching to Guest")
	var intent = game.account.start_intent.duplicate(true)
	abort("failure", 15)
	game.account.transport = lease
	game.account.retry_run()
	await settle()
	verify(requests.back().body.op_id == intent.op_id and game.account.server_run != "", "Account Retry reuses the same operation identity")
	verify(game.mode == "lobby" and checkpoint_unchanged(), "Account Retry alone does not launch or retire a save")
	allocated = requests.filter(func(r): return r.path == "/api/v1/runs").size()
	game.account.transport = func(_path, _body, _method): return {"code": 503, "data": {}}
	prepare("lease-offline", 16)
	await settle()
	verify(not game.launch_staged and game.account.server_run != "" and game.account.lease_retry.is_valid(), "An offline lease check preserves the issued lease and offers renewal Retry")
	abort("lease-offline", 17)
	game.account.transport = lease
	game.account.retry_run()
	await settle()
	verify(requests.back().path.ends_with("/heartbeat") and requests.filter(func(r): return r.path == "/api/v1/runs").size() == allocated, "Lease Retry renews the existing lease without allocating a second dig")
	verify(game.mode == "lobby" and checkpoint_unchanged(), "A late lease retry cannot revive its aborted launch")
	game.account.transport = func(_path, _body, _method): return {"code": 409, "data": {"error": {"code": "active_run"}}}
	prepare("lease-revoked", 18)
	await settle()
	verify(game.account.server_run == "" and game.account.takeover_needed and not game.launch_staged, "A revoked lease requires explicit Take over rather than starting silently")
	verify(game.profile_source == "account" and checkpoint_unchanged(), "Lease rejection never falls back to Guest or retires the old save")
	abort("lease-revoked", 19)
	game.account.transport = lease
	game.account.retry_run(true)
	await settle()
	verify(requests.back().body.takeover and game.account.server_run != "" and game.mode == "lobby", "Explicit Take over obtains a lease without starting the canceled attempt")
	var cache_root = game.account.cache_root
	var blocked = root_path.path_join("blocked-cache")
	var file = FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("fixture")
	file.close()
	game.account.cache_root = blocked
	game.account.server_run = ""
	prepare("storage", 20)
	verify(commands.back().t == "launch_failed" and commands.back().code == "storage" and checkpoint_unchanged(), "Failed account storage aborts before world preparation or save retirement")
	abort("storage", 21)
	game.account.cache_root = cache_root

	await fresh("loadout")
	net = game.net
	net.accept_lobby(snapshot("idle", 3, true))
	game.request_loadout_change()
	verify(game.mode == "lobby" and commands.back().t == "ready" and not commands.back().ready, "Change loadout first requests Unready")
	net.accept_lobby(snapshot("idle", 4, false))
	verify(game.mode == "workshop", "Loadout editing waits for the confirmed idle/unready snapshot")
	var revision = net.build_revision
	game.meta.zenny = 500
	verify(game.buy_skill(0, "frame"), "An unready lobby member can use the existing Workshop purchase")
	verify(net.build_revision > revision and not net.selection_acknowledged(), "A passive purchase publishes a new build revision before Ready")
	var sent = commands.size()
	net.set_ready(true)
	verify(commands.size() == sent, "An unacknowledged purchased build cannot Ready")
	net.accept_lobby(snapshot("idle", 5, false))
	net.set_ready(true)
	verify(commands.back().t == "ready", "Ready becomes available after the purchased build is acknowledged")
	game.mode = "lobby"
	prepare("invalid-shape", 6)
	abort("invalid-shape", 7)
	var invalid = prepare("shape", 8)
	abort("shape", 9)
	net.accept_lobby(snapshot("countdown", 10, true, "shape"))
	invalid.party = 3
	net.handle_command(invalid)
	verify(game.launch_attempt.is_empty(), "A mismatched frozen roster cannot prepare")

	await fresh("idle-takeover")
	net = game.net
	var saved = old_checkpoint.duplicate(true)
	saved.online = true
	saved.lobby_code = net.lobby_code
	saved.build.id = "self"
	saved.roster["self"] = saved.build.duplicate(true)
	file = FileAccess.open(game.checkpoint_path, FileAccess.WRITE)
	file.store_var(saved)
	file.close()
	old_bytes = FileAccess.get_file_as_bytes(game.checkpoint_path)
	game.lobby_entered({"takeover": true, "recreated": true, "checkpoint": false})
	verify(game.mode == "lobby" and checkpoint_unchanged(), "An idle-lobby reconnect cannot silently resume an older personal dig")
	net.recovery_expected = true
	game.pending_restore = saved
	game.lobby_entered({"takeover": true, "recreated": true, "checkpoint": false})
	verify(game.in_run() and game.player.count("lens") == 1, "Explicit checkpoint resume still works after the server forgets its lobby")

	await fresh("recovery")
	net = game.net
	net.accept_lobby(snapshot("running", 4, false))
	verify(not net.can_recover_sync(old_checkpoint.world), "Run status arriving after an idle snapshot cannot authorize recovery")
	net.first_snapshot = true
	net.accept_lobby(snapshot("running", 5, false))
	verify(net.can_recover_sync(old_checkpoint.world), "Joining an already running lobby enables its active-run sync path")
	game.net_message(1, [DiverNet.M_SYNC, old_checkpoint.world, old_checkpoint.build])
	verify(game.in_run() and game.player.count("lens") == 1 and game.run_time == 77, "Legitimate active-run Sync restores the existing build and clock without Ready")
	var world = old_checkpoint.world.duplicate()
	world.run_id = "another-dig"
	game.net_message(1, [DiverNet.M_SYNC, world, {}])
	verify(game.run_id == old_checkpoint.run_id, "Active-run Sync cannot silently change run identity")
	net.handle_command({"t": "welcome", "features": []})
	sent = commands.size()
	game.host_start_run()
	net.set_ready(true)
	verify(commands.size() == sent and not net.can_start(), "A server without ready_v1 never gets an ungated fresh launch")
	await fresh("sign-out")
	game.guest_meta = game.meta.duplicate(true)
	game.profile_source = "account"
	game.account.state = "signed_in"
	game.account.identity = {"id": "acc_cancel_signout", "name": "Fixture"}
	game.account.transport = lease
	game.account.busy = true
	prepare("sign-out")
	verify(game.account_starting, "Held account allocation is in flight before leaving")
	game.leave_online()
	game.account.sign_out()
	verify(not game.account_starting and not game.account.lease_retry.is_valid(), "Sign-out clears canceled account-start gates instead of blocking a later sign-in")
	print("READY_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
