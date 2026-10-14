extends SceneTree

var failures = 0
var checks = 0
var game: Node
var opened: Array = []

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ANDROID_CHECK_FAILED: " + label)

func run() -> void:
	var base = "https://game.example"
	var release = {"versionCode": 10, "versionName": "0.18.0", "gameProtocol": 7, "minimumOnlineVersionCode": 2, "downloadUrl": base + "/downloads/android/", "bytes": 50000000, "sha256": "a".repeat(64), "signingFingerprint": "b".repeat(64), "notes": "New build"}
	verify(DiverAndroidUpdates.valid(release, base), "Valid release metadata")
	for field in ["versionCode", "gameProtocol", "minimumOnlineVersionCode", "bytes"]:
		for value in [0, -1, 1.5, "10", 2147483648]:
			var bad = release.duplicate(true)
			bad[field] = value
			verify(not DiverAndroidUpdates.valid(bad, base), "Reject non-integer/out-of-range " + field)
	for url in ["http://game.example/downloads/android/", "https://evil.example/downloads/android/", base + "/downloads/android/../x", base + "/downloads/android/%2e%2e/x", base + "/downloads/android/?token=x"]:
		var bad = release.duplicate(true)
		bad.downloadUrl = url
		verify(not DiverAndroidUpdates.valid(bad, base), "Reject untrusted download URL")
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	game.save_path = "user://android-checks/guest.json"
	game.checkpoint_path = "user://android-checks/checkpoint.dat"
	game.account.cache_root = "user://android-checks/accounts"
	var update = game.android_updates
	update.set_process(false)
	update.opener = func(url): opened.append(url)
	update.installed_code = 10
	update.metadata = release.duplicate(true)
	verify(not update.available() and not update.blocks_online(), "No update at same integer code")
	update.installed_code = 2
	verify(update.available() and not update.blocks_online(), "Optional update permits online")
	game.mode = "title"
	update._process(0)
	verify(game.mode == "android_update", "Boot update prompt at title")
	update.later()
	update._process(0)
	verify(game.mode == "title" and opened.is_empty(), "Later neither opens browser nor repeats prompt")
	update.metadata.minimumOnlineVersionCode = 3
	verify(update.blocks_online(), "Minimum supported build blocks only online")
	game.mode = "play"
	update.download()
	verify(opened.is_empty(), "No download during dig")
	game.mode = "title"
	update.download()
	verify(opened == [release.downloadUrl], "Explicit download opens system-browser URL once")
	update.metadata = {}
	verify(not update.available() and not update.blocks_online(), "Metadata outage permits guest solo and server decides online")
	game.account.state = "restoring"
	game.start_run()
	verify(game.mode == "account" and not game.in_run(), "Saved account never silently becomes an offline guest dig")
	game.account.receive_profile(401, {}, PackedStringArray())
	verify(game.account.state == "needs_sign_in", "Expired restored session asks for sign-in rather than becoming Guest")
	game.start_run()
	verify(game.mode == "account" and not game.in_run(), "Expired saved session requires explicit Guest choice")
	var vault = DiverAndroidVault.new()
	vault.directory = "user://android-checks/vault"
	verify(not vault.save_token(base, "disposable-test-token"), "Non-Android vault refuses plaintext fallback")
	verify(not FileAccess.file_exists(vault.file_for(base)), "Failed secure storage writes no token file")
	game.hud.activate("credits")
	verify(game.mode == "credits" and game.hud.credits_lines.size() > 13, "In-game engine and asset notices are packaged and paginated")
	game.hud.activate("credits_page", 100000)
	verify(game.hud.credits_page == (game.hud.credits_lines.size() - 1) / 13, "Full notices remain reachable through the last page")
	game.account.identity = {"id": "acc_android_lifecycle_test"}
	game.account.outbox = [{"path": "/api/v1/discoveries", "body": {"op_id": DiverAccount.uuid(), "id": "lens"}}]
	game.account.state = "guest"
	game.mode = "title"
	game.account._notification(NOTIFICATION_APPLICATION_PAUSED)
	verify(game.account.backgrounded and game.account.read_file("outbox.json", []) == game.account.outbox, "Suspension persists pending operations before leaving the app")
	game.account._notification(NOTIFICATION_APPLICATION_RESUMED)
	verify(not game.account.backgrounded, "Resume restores foreground processing")
	game.account.state = "signing_in"
	game.account.device = {"device_code": "disposable-expired-code"}
	game.account.device_remaining = 600
	game.account.device_deadline = Time.get_unix_time_from_system() - 1
	game.account._process(0)
	verify(game.account.device.is_empty() and game.account.state != "signing_in", "Time spent in external browser counts against device-code expiry")
	print("ANDROID_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
