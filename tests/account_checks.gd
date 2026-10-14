extends SceneTree

var game: Node
var account: DiverAccount
var responses: Array = []
var sent: Array = []
var failures = 0
var checks = 0
var cache = "user://account-checks-" + DiverAccount.uuid()

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACCOUNT_CHECK_FAILED: " + label)

func fake(path: String, body: Variant, _method: int) -> Dictionary:
	sent.append({"path": path, "body": body.duplicate(true) if body is Dictionary else body})
	return responses.pop_front() if not responses.is_empty() else {"code": 503, "data": {"error": {"code": "unavailable"}}}

func settle() -> void:
	for i in 8: await process_frame

func document(id: String, zenny: int, rev: int) -> Dictionary:
	var p = DiverProgression.fresh()
	p.zenny = zenny
	return {"account": {"id": id, "name": id, "role": "player"}, "profile": p, "revision": rev}

func login(id: String, zenny: int = 0, rev: int = 0) -> void:
	account.receive_profile(200, document(id, zenny, rev), PackedStringArray())
	await settle()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	game.save_path = cache.path_join("guest.json")
	game.checkpoint_path = cache.path_join("checkpoint.dat")
	account = game.account
	account.set_process(false)
	account.cache_root = cache
	account.transport = fake
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 777
	var guest = game.meta.duplicate(true)
	await login("acc_test_a", 100, 2)
	verify(game.profile_source == "account" and game.meta.zenny == 100, "Cloud wallet replaces active view")
	verify(game.guest_meta == guest, "Guest view remains separate")
	verify(not game.save_meta() and not FileAccess.file_exists(game.save_path), "Cloud cannot write guest archive")
	verify(account.status == "Synced", "Confirmed profile reports sync")
	# A lost response leaves an immutable body on disk, and no spendable reward.
	account.server_run = "run_test"
	var outcome = {"won": false, "depth": 2, "guardians": 1, "scrap": 37, "kills": 41, "run_time": 655.2, "character": 1, "abandoned": false}
	verify(account.result(outcome), "Result stored before send")
	await settle()
	verify(account.outbox.size() == 1 and account.status == "Offline", "503 retains result and reports offline")
	verify(account.pending_zenny() == 117 and game.meta.zenny == 100, "Pending reward is not spendable")
	verify(not account.purchase(0, "frame"), "Offline purchase is blocked")
	var original: Dictionary = sent.back().duplicate(true)
	var disk: Array = account.read_file("outbox.json", [])
	verify(disk.size() == 1 and disk[0].body.run_id == "run_test" and disk[0].body.outcome.kills == 41, "Outbox is durable")
	responses.append({"code": 200, "data": document("acc_test_a", 217, 3)})
	account.retry_wait = 0
	account.flush()
	await settle()
	verify(sent.back() == original, "Retry uses exactly the original run id and body")
	verify(account.outbox.is_empty() and account.pending_zenny() == 0 and game.meta.zenny == 217, "Confirmation clears pending balance")
	# Recreate the client node to exercise actual startup recovery, not just RAM.
	responses.append({"code": 503, "data": {}})
	account.discover("coil")
	await settle()
	var pending_body = sent.back().body.duplicate(true)
	account.queue_free()
	await process_frame
	account = DiverAccount.new()
	account.game = game
	account.cache_root = cache
	account.transport = fake
	game.account = account
	game.add_child(account)
	account.set_process(false)
	responses.append({"code": 200, "data": document("acc_test_a", 217, 3)})
	await login("acc_test_a", 217, 3)
	verify(account.outbox.is_empty() and sent.back().body.op_id == pending_body.op_id, "A recreated client replays the durable operation once")
	# Revision conflict adopts cloud state and requires a new explicit purchase.
	responses.append({"code": 409, "data": {"error": {"code": "revision_conflict"}, "revision": 4, "profile": document("acc_test_a", 12, 4).profile}})
	verify(account.purchase(0, "frame"), "Online purchase enqueues")
	await settle()
	verify(account.outbox.is_empty() and game.meta.zenny == 12 and account.revision == 4, "Conflict replaces wallet without retrying stale purchase")
	# Auth expiry holds operations; account B can neither see nor send A's work.
	responses.append({"code": 401, "data": {"error": {"code": "unauthorized"}}})
	account.discover("lens")
	await settle()
	verify(account.state == "needs_sign_in" and account.outbox.size() == 1 and account.status == "Sign-in needed", "401 retains outbox and asks for sign-in")
	var a_pending = account.outbox.duplicate(true)
	await login("acc_test_b", 8, 0)
	verify(account.outbox.is_empty() and game.meta.zenny == 8, "Switching accounts resets wallet, revision and outbox")
	verify(account.read_file("outbox.json", []).is_empty(), "B has no A operations")
	responses.append({"code": 200, "data": document("acc_test_a", 12, 5)})
	await login("acc_test_a", 12, 4)
	verify(account.outbox.is_empty() and sent.back().body == a_pending[0].body, "Returning to A replays A's exact operation")
	# An older idempotent response cannot undo a newer authoritative GET.
	account.apply_profile(document("acc_test_a", 3, 1))
	verify(game.meta.zenny == 12 and account.revision == 5, "Old operation snapshot cannot roll back profile")
	verify(not game.import_progress(guest), "Save code cannot overwrite established cloud wallet")
	game.mode = "play"
	account.sign_out()
	verify(game.profile_source == "account", "Sign-out blocked during dig")
	game.mode = "account"
	responses.append({"code": 200, "data": {}})
	account.sign_out()
	await settle()
	verify(game.profile_source == "guest" and game.meta == guest, "Sign-out restores original guest profile")
	# New account run retries reuse their durable start intent after lost response.
	await login("acc_test_c")
	var began = [false]
	account.begin_run(func(): began[0] = true)
	await settle()
	var first = sent.back().duplicate(true)
	verify(not began[0] and account.server_run == "", "No offline account run starts")
	responses.append({"code": 201, "data": {"run": {"id": "run_real"}, "revision": 0}})
	account.begin_run(func(): began[0] = true)
	await settle()
	verify(began[0] and sent.back() == first and account.server_run == "run_real", "Lost start response retries the same operation")
	account.attach_world("coop-world")
	account.server_run = ""
	verify(account.resume_world("coop-world") and account.server_run == "run_real", "Local account run follows checkpoint without using host run id")
	# Migration always previews first, and rejected adoption preserves guest.
	responses.append({"code": 200, "data": {"preview": {"runs": 0, "zenny": 777, "kills": 0, "trees": 0}, "confirm": "mig_test"}})
	account.preview_migration(guest)
	await settle()
	verify(not account.migration.is_empty() and not sent.back().body.has("op_id"), "Guest migration preview cannot mutate wallet")
	responses.append({"code": 409, "data": {"error": {"code": "not_empty"}}})
	account.confirm_migration()
	await settle()
	verify(game.guest_meta == guest and account.outbox.is_empty(), "Rejected migration never changes guest")
	# Actual menu supports all navigation paths and never claims pending is saved.
	game.mode = "account"
	game.hud.queue_redraw()
	await settle()
	verify(game.hud.hits.any(func(hit): return hit.action == "account_retry"), "Account menu exposes keyboard/controller Retry target")
	verify(game.hud.back() and game.mode == "title", "Account menu supports Back")
	verify(not FileAccess.get_file_as_string(account.path_for("profile.json")).contains("access_token"), "Cache contains no credentials")
	# Device polling recognizes Better Auth's string errors and cancellation.
	game.mode = "account"
	account.state = "signing_in"
	account.device = {"device_code": "test-device"}
	account.device_remaining = 600
	account.device_wait = 0
	account.device_interval = 5
	responses.append({"code": 400, "data": {"error": "slow_down"}})
	account._process(0.1)
	await settle()
	verify(account.device_interval == 10, "Device slow_down adds five seconds")
	account.device_wait = 0
	responses.append({"code": 400, "data": {"error": "access_denied"}})
	account._process(0.1)
	await settle()
	verify(account.device.is_empty() and account.state == "needs_sign_in", "Device denial stops polling without clearing pending account data")
	account.state = "signing_in"
	account.device = {"device_code": "expired"}
	account.device_remaining = 0.01
	var sent_count = sent.size()
	account._process(1)
	await settle()
	verify(account.device.is_empty() and sent.size() == sent_count, "Expired code cannot poll again")
	# Cleanup refuses to erase any durable pending operation.
	account.state = "signed_in"
	account.discover("ember")
	await settle()
	account.clear_local_session()
	verify(game.profile_source == "account" and not account.outbox.is_empty(), "Local cleanup preserves unsynced operations")
	# Dashboard play time: reported best effort outside the outbox, whole seconds only.
	var outbox_before = account.outbox.size()
	account.foreground_seconds = 130.4
	account._process(0)
	await settle()
	var reports = sent.filter(func(s): return s.path == "/api/v1/activity")
	verify(reports.size() == 1 and reports[0].body.seconds == 130 and reports[0].body.platform == account.platform_id() and account.foreground_seconds < 1, "Play time reports whole foreground seconds once")
	verify(account.outbox.size() == outbox_before, "Play-time reports never enter the progress outbox")
	account.state = "needs_sign_in"
	account.foreground_seconds = 50
	account._process(0)
	await settle()
	verify(sent.filter(func(s): return s.path == "/api/v1/activity").size() == 1, "No play-time report without a confirmed sign-in")
	account.state = "signed_in"
	account.foreground_seconds = 0
	print("ACCOUNT_CHECKS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
