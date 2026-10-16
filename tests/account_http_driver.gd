extends SceneTree

# Called by account_e2e.mjs with a disposable backend and an in-memory token.
var game: Node
var account: DiverAccount
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("ACCOUNT_HTTP_FAILED: " + label)

func until(predicate: Callable) -> void:
	var deadline = Time.get_ticks_msec() + 25000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	verify(predicate.call(), "Request completed within deadline")

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	root.add_child(game)
	game.sound.muted = true
	game.set_process(false)
	game.save_path = "user://account-http-test/guest.json"
	game.checkpoint_path = "user://account-http-test/checkpoint.dat"
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 999
	game.net.server_url = OS.get_environment("ACCOUNT_TEST_ORIGIN").replace("http://", "ws://") + "/ws"
	account = game.account
	account.cache_root = OS.get_environment("ACCOUNT_TEST_CACHE")
	if OS.get_environment("ACCOUNT_TEST_EMAIL") != "":
		# The in-game sign-in over real HTTP, with an authenticator code when given.
		account.sign_in_email(OS.get_environment("ACCOUNT_TEST_EMAIL"), OS.get_environment("ACCOUNT_TEST_PASSWORD"))
		var totp = OS.get_environment("ACCOUNT_TEST_TOTP")
		if totp != "":
			await until(func(): return account.auth.view == "two_factor" and not account.auth.busy)
			verify(account.auth.cookie.contains("two_factor="), "Native sign-in keeps the authenticator cookie")
			account.verify_code(totp, false)
	else:
		account.token = OS.get_environment("ACCOUNT_TEST_TOKEN")
		account.state = "signing_in"
		account.refresh()
	await until(func(): return account.signed_in())
	verify(account.token != "" and not account.auth.bad, "Native sign-in holds a bearer session")
	verify(not DiverAccount.has_progress(game.guest_meta), "An account with progress discards this device's Guest progress")
	if OS.get_environment("ACCOUNT_TEST_MODE") == "write":
		verify(game.meta.zenny == 200, "Native receives initial cloud migration")
		var began = [false]
		account.begin_run(func(): began[0] = true)
		await until(func(): return began[0])
		verify(account.result({"won": false, "depth": 2, "guardians": 1, "scrap": 37, "kills": 41, "run_time": 655.2, "character": 1, "abandoned": false}), "Result queued durably")
		await until(func(): return account.status == "Offline")
		verify(account.pending_zenny() == 117 and game.meta.zenny == 200, "Committed but lost response stays pending")
		# Simulate a process reload: discard the in-memory queue and recover disk.
		account.outbox = account.read_file("outbox.json", [])
		account.retry()
		await until(func(): return account.outbox.is_empty() and account.status == "Synced")
		verify(game.meta.zenny == 317 and game.meta.runs == 1, "Result replay rewards once")
		verify(account.purchase(0, "frame"), "Purchase queued against authoritative revision")
		await until(func(): return account.status == "Offline")
		account.retry()
		await until(func(): return account.outbox.is_empty() and account.status == "Synced")
		verify(game.meta.zenny == 217 and "frame" in DiverProgression.owned(game.meta, 0), "Lost purchase response spends once")
		account.discover("lens")
		await until(func(): return account.outbox.is_empty())
	else:
		var expected = int(OS.get_environment("ACCOUNT_TEST_ZENNY")) if OS.get_environment("ACCOUNT_TEST_ZENNY") != "" else 217
		verify(game.meta.zenny == expected and game.meta.runs == 1 and game.meta.kills == 41, "Second native process sees confirmed wallet and records")
		verify("frame" in DiverProgression.owned(game.meta, 0) and game.meta.discovered.get("lens", false), "Second process sees purchases and discoveries")
	verify(not game.import_progress(DiverProgression.fresh()), "Cloud wallet rejects save-code replacement")
	# Exercise the real ticket -> hello -> welcome -> acct: identity path.
	game.mode = "online"
	game.net.create_lobby("Account HTTP check", false)
	await until(func(): return game.net.active())
	verify(game.net.account_confirmed and game.net.player_id.begins_with("acct:"), "Godot co-op ticket confirms account identity")
	game.net.leave_lobby()
	print("ACCOUNT_HTTP: %d failures" % failures)
	quit(1 if failures else 0)
