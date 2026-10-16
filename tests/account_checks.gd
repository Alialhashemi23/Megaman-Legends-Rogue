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
	verify(game.guest_meta.zenny == 0 and not DiverAccount.has_progress(game.guest_meta), "An account with progress wins: Guest progress is discarded")
	verify(not sent.any(func(r): return r.path == "/api/v1/migrate-guest"), "Guest progress is never offered to an account that has progress")
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
	verify(game.profile_source == "guest" and not DiverAccount.has_progress(game.meta), "Sign-out leaves a fresh Guest, not the discarded progress")
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
	# A save-code adoption previews first; if the account gained progress meanwhile, the account wins.
	game.guest_meta = guest.duplicate(true)
	responses.append({"code": 200, "data": {"preview": {"runs": 0, "zenny": 777, "kills": 0, "trees": 0}, "confirm": "mig_test"}})
	account.preview_migration(guest)
	await settle()
	verify(not account.migration.is_empty() and not sent.back().body.has("op_id"), "Guest migration preview cannot mutate wallet")
	responses.append({"code": 409, "data": {"error": {"code": "not_empty"}}})
	account.confirm_migration()
	await settle()
	verify(not DiverAccount.has_progress(game.guest_meta) and account.outbox.is_empty(), "Adoption refused because the account has progress discards Guest")
	account.sign_out()
	await settle()
	# A new, empty account adopts this device's Guest progress automatically, once.
	game.mode = "title"
	game.meta = guest.duplicate(true)
	var adopted = DiverProgression.fresh()
	adopted.zenny = 777
	responses.append({"code": 200, "data": {"preview": {"runs": 0, "zenny": 777, "kills": 0, "trees": 0}, "confirm": "mig_auto"}})
	responses.append({"code": 200, "data": {"account": {"id": "acc_test_new", "name": "New", "role": "player"}, "profile": adopted, "revision": 1}})
	await login("acc_test_new", 0, 0)
	await settle()
	var migrations = sent.filter(func(r): return r.path == "/api/v1/migrate-guest")
	verify(migrations.size() >= 2 and migrations[-2].body.profile.zenny == 777 and migrations[-1].body.confirm == "mig_auto" and migrations[-1].body.has("op_id"), "Empty account previews then confirms Guest adoption by itself")
	verify(game.meta.zenny == 777 and not DiverAccount.has_progress(game.guest_meta), "Adopted progress continues in the account and leaves Guest fresh")
	account.sign_out()
	await settle()
	# An account with progress also clears a saved Guest dig.
	game.meta = guest.duplicate(true)
	var guest_dig = {"v": game.CHECKPOINT_VERSION, "run_id": "guest-dig", "account_id": "", "online": false, "world": {"depth": 1}, "build": {}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(game.checkpoint_path.get_base_dir()))
	var checkpoint = FileAccess.open(game.checkpoint_path, FileAccess.WRITE)
	checkpoint.store_var(guest_dig)
	checkpoint.close()
	game.saved_dig = guest_dig
	verify(not game.load_checkpoint().is_empty(), "Fixture: a saved Guest dig exists")
	await login("acc_test_a", 12, 6)
	verify(game.load_checkpoint().is_empty() and game.saved_dig.is_empty(), "Signing in to an account with progress discards a saved Guest dig")
	account.sign_out()
	await settle()
	await login("acc_test_c")
	# Actual menu supports all navigation paths and never claims pending is saved.
	game.mode = "account"
	game.hud.queue_redraw()
	await settle()
	verify(game.hud.hits.any(func(hit): return hit.action == "account_retry"), "Account menu exposes keyboard/controller Retry target")
	verify(game.hud.back() and game.mode == "title", "Account menu supports Back")
	verify(not FileAccess.get_file_as_string(account.path_for("profile.json")).contains("access_token"), "Cache contains no credentials")
	# In-game sign-in: errors stay in the panel; a session token and then the profile follow success.
	account.sign_out()
	await settle()
	game.mode = "account"
	account.open_auth("sign_in")
	responses.append({"code": 401, "data": {"code": "INVALID_EMAIL_OR_PASSWORD", "message": "Invalid email or password"}})
	account.sign_in_email("digger@example.test", "wrong password")
	await settle()
	verify(sent.back().path == "/api/auth/sign-in/email" and sent.back().body.email == "digger@example.test", "Sign-in posts email and password to Better Auth")
	verify(account.auth.bad and account.auth.note.contains("don't match") and account.state == "guest" and not account.auth.busy, "Wrong password explains itself and stays Guest")
	responses.append({"code": 403, "data": {"code": "EMAIL_NOT_VERIFIED"}})
	account.sign_in_email("digger@example.test", "right password")
	await settle()
	verify(account.auth.note.contains("Confirm your email"), "Unverified email asks for confirmation")
	responses.append({"code": 200, "data": {"twoFactorRedirect": true}, "headers": PackedStringArray(["Set-Cookie: __Secure-better-auth.two_factor=abc.def%3D; Max-Age=600; Path=/; HttpOnly; Secure"])})
	account.sign_in_email("digger@example.test", "right password")
	await settle()
	verify(account.auth.view == "two_factor" and account.auth.cookie == "__Secure-better-auth.two_factor=abc.def%3D", "Authenticator accounts get the code step and keep its cookie")
	var code_headers = account.request_headers({"auth": true, "credential": "", "cookie": account.auth.cookie})
	verify(OS.has_feature("web") or ("Cookie: " + account.auth.cookie in code_headers and "Origin: " + account.base_url() in code_headers and not Array(code_headers).any(func(h): return h.begins_with("Authorization"))), "Native code check sends the cookie and the game server's origin, never a bearer")
	responses.append({"code": 401, "data": {"code": "INVALID_CODE"}})
	account.verify_code("123 456", false)
	await settle()
	verify(sent.back().path == "/api/auth/two-factor/verify-totp" and sent.back().body.code == "123456" and account.auth.view == "two_factor" and account.auth.bad, "A wrong code stays on the code step")
	responses.append({"code": 200, "data": {"token": "raw"}, "headers": PackedStringArray(["set-auth-token: signed.token-value"])})
	responses.append({"code": 200, "data": document("acc_test_a", 12, 6)})
	account.verify_code("654321", false)
	await settle()
	verify(OS.has_feature("web") or account.token == "signed.token-value", "Native keeps the bearer token Better Auth issued")
	verify(account.signed_in() and account.identity.id == "acc_test_a" and game.profile_source == "account" and game.mode == "title", "A completed sign-in loads the account and closes the panel")
	verify(account.auth.cookie == "" and not account.auth.busy, "Sign-in leaves no authenticator cookie behind")
	account.sign_out()
	await settle()
	responses.append({"code": 200, "data": {"user": {"id": "u"}}})
	game.mode = "account"
	account.open_auth("create")
	account.create_account("Digger", "new@example.test", "long enough password")
	await settle()
	verify(sent.back().path == "/api/auth/sign-up/email" and sent.back().body.name == "Digger" and account.auth.view == "check_email", "Creating an account asks to confirm the email")
	responses.append({"code": 200, "data": {"status": true}})
	account.open_auth("forgot")
	account.send_reset("new@example.test")
	await settle()
	verify(sent.back().path == "/api/auth/request-password-reset" and not account.auth.bad and account.auth.note.contains("reset link"), "Forgot password sends the reset email")
	# The panel is a modal over the title, with focusable fields and Back steps.
	account.open_auth("create")
	game.hud.queue_redraw()
	await settle()
	verify(game.hud.hits.filter(func(hit): return hit.action == "auth_field").size() == 3 and game.hud.hits.any(func(hit): return hit.action == "auth_submit"), "Create form exposes three fields and a submit target")
	verify(not game.hud.hits.any(func(hit): return hit.action == "start"), "Title buttons under the modal can't be used")
	game.hud.activate("auth_field", 1)
	verify(game.hud.auth_email_edit.has_focus(), "Controller confirm focuses a text field")
	game.hud.auth_email_edit.text_submitted.emit("x")
	verify(game.hud.auth_password_edit.has_focus(), "Enter moves to the next field")
	game.hud.get_viewport().gui_release_focus()
	verify(game.hud.back() and account.auth.view == "sign_in" and game.mode == "account", "Back from Create returns to Sign in")
	verify(game.hud.back() and game.mode == "title", "Back from Sign in closes the panel")
	await login("acc_test_a", 12, 6)
	account.state = "signed_in"
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
