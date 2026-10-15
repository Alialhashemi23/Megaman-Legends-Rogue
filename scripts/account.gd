extends Node
class_name DiverAccount

# Account data never shares the guest archive. Windows tokens are memory-only;
# Android uses Keystore-backed encryption through a separate vault.
signal changed
signal message(text: String)
var game: Node
var transport: Callable
var cache_root = "user://accounts"
var state = "guest"
var status = "Offline"
var identity: Dictionary = {}
var profile: Dictionary = {}
var revision = 0
var last_sync = 0.0
var outbox: Array = []
var foreground_seconds = 0.0 # Foreground dig time not yet reported to /api/v1/activity.
var token = ""
var device: Dictionary = {}
var device_remaining = 0.0
var device_wait = 0.0
var device_interval = 5.0
var retry_wait = 0.0
var attempts = 0
var heartbeat_clock = 0.0
var server_run = ""
var last_result_run = ""
var start_intent: Dictionary = {}
var pending_run_callback: Callable
var takeover_needed = false
var migration: Dictionary = {}
var requests: Array = []
var busy = false
var generation = 0
var http: HTTPRequest
var vault: DiverAndroidVault
var backgrounded = false
var device_deadline = 0.0

func platform_id() -> String:
	return "android" if OS.has_feature("android") else ("web" if OS.has_feature("web") else "windows")

func restore_session() -> void:
	if not OS.has_feature("android"): return
	vault = DiverAndroidVault.new()
	resume_saved_session()

func resume_saved_session() -> void:
	token = vault.load_token(base_url())
	if token != "":
		state = "restoring"
		status = "Saving"
		refresh()
	elif FileAccess.file_exists(vault.file_for(base_url())):
		state = "needs_sign_in"
		status = "Sign-in needed"
		game.mode = "account"

func persist_pending() -> bool:
	if identity.is_empty(): return true
	if not write_file("outbox.json", outbox):
		message.emit("Could not store pending progress. Free device storage and retry.")
		return false
	return true

func _notification(what: int) -> void:
	if game == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		backgrounded = true
		report_activity()
		persist_pending()
		if game.in_run(): game.save_checkpoint()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		backgrounded = false
		if not game.in_run() and not game.net.active() and state in ["signed_in", "restoring"]: refresh()

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(completed)

static func uuid() -> String:
	if OS.has_feature("web"): return str(JavaScriptBridge.eval("window.crypto.randomUUID()", true))
	var bytes = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var s = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [s.substr(0, 8), s.substr(8, 4), s.substr(12, 4), s.substr(16, 4), s.substr(20)]

func base_url() -> String:
	if OS.has_feature("web"): return str(JavaScriptBridge.eval("location.origin", true))
	var url: String = game.net.server_url
	return url.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws").trim_suffix("/")

func signed_in() -> bool:
	return state == "signed_in"

func switch_allowed() -> bool:
	return not game.in_run() and not game.net.active()

func request(path: String, body: Variant, callback: Callable, method: int = HTTPClient.METHOD_POST) -> void:
	requests.append({"path": path, "url": base_url() + path, "body": body, "callback": callback, "method": method, "generation": generation})
	pump()

func pump() -> void:
	if busy or requests.is_empty(): return
	while not requests.is_empty() and requests[0].generation != generation and not requests[0].get("revoke", false): requests.pop_front()
	if requests.is_empty(): return
	busy = true
	var r: Dictionary = requests[0]
	if transport.is_valid():
		var response: Dictionary = transport.call(r.path, r.body, r.method)
		deliver.call_deferred(int(response.get("code", 0)), response.get("data", {}), response.get("headers", PackedStringArray()))
		return
	var headers = PackedStringArray(["Content-Type: application/json"])
	var credential = str(r.get("credential", token))
	if credential != "": headers.append("Authorization: Bearer " + credential)
	var error = http.request(r.url, headers, r.method, "" if r.body == null else JSON.stringify(r.body))
	if error != OK: deliver.call_deferred(0, {}, PackedStringArray())

func completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var parser = JSON.new()
	var data: Variant = {}
	if not body.is_empty() and parser.parse(body.get_string_from_utf8()) == OK: data = parser.data
	deliver(code if result == HTTPRequest.RESULT_SUCCESS else 0, data if data is Dictionary else {}, headers)

func deliver(code: int, data: Dictionary, headers: PackedStringArray = PackedStringArray()) -> void:
	if requests.is_empty(): return
	var r: Dictionary = requests.pop_front()
	busy = false
	if r.generation == generation: r.callback.call(code, data, headers)
	pump()

func refresh() -> void:
	if state == "guest" and not OS.has_feature("web"): return
	request("/api/v1/profile", null, receive_profile, HTTPClient.METHOD_GET)

func receive_profile(code: int, data: Dictionary, _headers: PackedStringArray) -> void:
	if code == 200 and data.get("account") is Dictionary:
		var id = str(data.account.get("id", ""))
		if not id.begins_with("acc_") or not id.is_valid_filename(): return
		var switching = identity.get("id", "") != id
		if switching and not switch_allowed():
			message.emit("Leave the dig or lobby before switching accounts.")
			return
		if switching:
			generation += 1
			identity = data.account.duplicate(true)
			profile = {}
			revision = 0
			outbox = read_file("outbox.json", [])
			var active: Dictionary = read_file("active.json", {})
			server_run = ""
			start_intent = active.get("start", {})
		state = "signed_in"
		if not apply_profile(data):
			if switching and profile.is_empty():
				# Nothing confirmed yet: stay unconfirmed so digs, purchases and server changes wait.
				identity = {}
				outbox = []
				start_intent = {}
				state = "restoring"
				changed.emit()
			elif switching: game.activate_account()
			game.mode = "account"
			return
		if switching:
			game.activate_account()
			if game.mode in ["title", "account"]: game.mode = "account"
		flush()
	elif code == 401:
		var restoring = state in ["restoring", "needs_sign_in"]
		if vault != null: vault.erase(base_url())
		token = ""
		if restoring or not identity.is_empty(): state = "needs_sign_in"
		else: state = "guest"
		status = "Sign-in needed" if state == "needs_sign_in" else "Offline"
		changed.emit()
		if restoring: game.mode = "account"
		if game.net.invited_code() != "" and not game.net.active():
			# Accounts-enabled invite: choose sign-in before entering a lobby,
			# because identity changes are forbidden once the lobby is active.
			game.mode = "account"
	else:
		status = "Offline"
		if code == 403: message.emit("Verify your email in the sign-in page before syncing progress.")
		# A saved session restored while offline retries on its own once the server is reachable.
		if state == "restoring" and (code == 0 or code == 429 or code >= 500): retry_wait = 15
		changed.emit()
		if identity.is_empty() and game.net.invited_code() != "" and not game.net.active():
			game.mode = "online"
			game.net.join_lobby(game.net.invited_code(), game.net.url_param("key"))

func apply_profile(data: Dictionary) -> bool:
	var validated = DiverProgression.validate(data.get("profile"))
	if validated.is_empty():
		status = "Offline"
		message.emit("The server returned an invalid profile. Retry sync.")
		return false
	# Idempotent replays can return older snapshots. Never roll the wallet back.
	if int(data.get("revision", -1)) >= revision or profile.is_empty():
		profile = validated
		revision = int(data.revision)
		if game.profile_source == "account": game.meta = profile.duplicate(true)
	last_sync = Time.get_unix_time_from_system()
	status = "Synced" if outbox.is_empty() else "Saving"
	if not write_file("profile.json", {"profile": profile, "revision": revision, "last_sync": last_sync}):
		status = "Offline"
		message.emit("Could not cache confirmed progress. Free device storage and retry.")
		return false
	changed.emit()
	return true

func path_for(file: String) -> String:
	return cache_root.path_join(str(identity.id)).path_join(file)

func read_file(file: String, fallback: Variant) -> Variant:
	if OS.has_feature("web"):
		var mirror = JavaScriptBridge.eval("localStorage.getItem(%s) || ''" % JSON.stringify("relicAccount:" + str(identity.id) + ":" + file), true)
		if mirror is String and mirror != "":
			var value = JSON.parse_string(mirror)
			if typeof(value) == typeof(fallback): return value
	for suffix in ["", ".tmp"]:
		var path = path_for(file) + suffix
		if FileAccess.file_exists(path):
			var value = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(value) == typeof(fallback): return value
	return fallback.duplicate(true)

func write_file(file: String, value: Variant) -> bool:
	var path = path_for(file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(value))
	f.flush()
	var error = f.get_error()
	f.close()
	if error != OK: return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK: return false
	if OS.has_feature("web"):
		# Synchronous, account-scoped recovery for refresh during IndexedDB sync.
		var stored = JavaScriptBridge.eval("(() => { try { localStorage.setItem(%s, %s); return true; } catch(e) { return false; } })()" % [JSON.stringify("relicAccount:" + str(identity.id) + ":" + file), JSON.stringify(JSON.stringify(value))], true)
		JavaScriptBridge.force_fs_sync()
		if not bool(stored): return false
	return true

func enqueue(path: String, body: Dictionary) -> bool:
	if identity.is_empty(): return false
	var op = {"path": path, "body": body.duplicate(true)}
	outbox.append(op)
	if not write_file("outbox.json", outbox):
		outbox.pop_back()
		status = "Offline"
		message.emit("Could not store pending progress. Free device storage and retry.")
		return false
	status = "Saving" if signed_in() else "Sign-in needed"
	changed.emit()
	flush()
	return true

func flush() -> void:
	if not signed_in() or outbox.is_empty() or retry_wait > 0: return
	# One ordered operation in flight; profile refresh and tickets share the queue.
	for r in requests:
		if r.get("outbox", false): return
	var op: Dictionary = outbox[0]
	if not write_file("outbox.json", outbox):
		status = "Offline"
		retry_wait = 10
		return
	requests.append({"path": op.path, "url": base_url() + op.path, "body": op.body.duplicate(true), "callback": operation_done, "method": HTTPClient.METHOD_POST, "generation": generation, "outbox": true})
	pump()

func operation_done(code: int, data: Dictionary, headers: PackedStringArray) -> void:
	var error = data.get("error", {})
	var reason = str(error.get("code", "")) if error is Dictionary else str(error)
	if code >= 200 and code < 300:
		if not apply_profile(data):
			retry_wait = 10
			return
		if outbox[0].path == "/api/v1/run-results" and str(outbox[0].body.run_id) == last_result_run and game.mode == "end":
			game.new_unlocks.clear()
			for id in data.get("result", {}).get("new_unlocks", []):
				if game.ITEMS.has(id): game.new_unlocks.append(game.ITEMS[id].name)
		outbox.pop_front()
		attempts = 0
	elif code == 401:
		state = "needs_sign_in"
		status = "Sign-in needed"
		changed.emit()
		return
	elif code >= 400 and code < 500 and code != 429:
		if reason == "revision_conflict": apply_profile(data)
		message.emit("Your progress changed on another device. Please retry the purchase." if reason == "revision_conflict" else "Progress operation refused: " + reason)
		outbox.pop_front()
	else:
		attempts += 1
		retry_wait = minf(120, pow(2, mini(attempts, 7)))
		for header in headers:
			if header.to_lower().begins_with("retry-after:"): retry_wait = maxf(retry_wait, float(header.substr(12).strip_edges()))
		status = "Offline"
		changed.emit()
		return
	if not write_file("outbox.json", outbox):
		status = "Offline"
		retry_wait = 10
		return
	status = "Synced" if outbox.is_empty() else "Saving"
	changed.emit()
	flush()

# Best effort and never queued in the outbox: a lost report only lowers an estimate.
func report_activity() -> void:
	var seconds = int(foreground_seconds)
	if not signed_in() or seconds < 1: return
	foreground_seconds -= seconds
	request("/api/v1/activity", {"seconds": mini(seconds, 3600), "platform": platform_id(), "game_version": DiverNet.NET_VERSION}, func(_code, _data, _headers): pass)

func retry() -> void:
	retry_wait = 0
	refresh()
	flush()

func pending_zenny() -> int:
	var total = 0
	for op in outbox:
		if op.path == "/api/v1/run-results" and not op.body.outcome.get("abandoned", false):
			var o: Dictionary = op.body.outcome
			total += DiverProgression.reward(int(o.depth), int(o.guardians), int(o.scrap))
	return total

func purchase(character: int, node: String) -> bool:
	if not signed_in() or status != "Synced" or not outbox.is_empty(): return false
	var operation_id = uuid()
	return enqueue("/api/v1/purchases", {"op_id": operation_id, "character": character, "node": node, "expected_revision": revision})

func discover(id: String) -> void:
	if profile.get("discovered", {}).get(id, false): return
	for op in outbox:
		if op.path == "/api/v1/discoveries" and id in op.body.parts: return
	enqueue("/api/v1/discoveries", {"op_id": uuid(), "parts": [id]})

func begin_run(callback: Callable, takeover: bool = false) -> void:
	pending_run_callback = callback
	if not signed_in():
		game.account_starting = false
		message.emit("Sign in again, or leave the lobby and choose Play as Guest.")
		return
	if start_intent.is_empty() or bool(start_intent.takeover) != takeover:
		start_intent = {"op_id": uuid(), "platform": platform_id(), "game_version": DiverNet.NET_VERSION, "takeover": takeover}
	if not write_file("active.json", {"start": start_intent}):
		game.account_starting = false
		message.emit("Could not store account dig. Free device storage before starting.")
		return
	request("/api/v1/runs", start_intent.duplicate(true), func(code, data, _headers):
		game.account_starting = false
		if code == 201:
			server_run = str(data.run.id)
			if not write_file("active.json", {"run_id": server_run}):
				message.emit("Could not store account dig. Retry before playing.")
				server_run = ""
				return
			start_intent = {}
			takeover_needed = false
			heartbeat_clock = 0
			status = "Synced" if outbox.is_empty() else "Saving"
			pending_run_callback = Callable()
			callback.call()
		else:
			status = "Offline"
			if code == 401:
				state = "needs_sign_in"
				status = "Sign-in needed"
			takeover_needed = code == 409 and data.get("error", {}).get("code") == "active_run"
			if takeover_needed: start_intent = {}
			var detail = "Another device has an active dig. Choose Take over to start here." if takeover_needed else "Account dig could not start. Retry, or leave the lobby and choose Play as Guest."
			message.emit(detail)
			if game.net.active(): game.net.error_text = detail
			if not game.net.active(): game.mode = "account"
	)

func retry_run(takeover: bool = false) -> void:
	if pending_run_callback.is_valid(): begin_run(pending_run_callback, takeover)

func result(outcome: Dictionary) -> bool:
	if server_run == "": return false
	last_result_run = server_run
	var ok = enqueue("/api/v1/run-results", {"run_id": server_run, "outcome": outcome})
	if ok:
		server_run = ""
		write_file("active.json", {})
	return ok

func attach_world(world_id: String) -> void:
	if server_run != "": write_file("active.json", {"run_id": server_run, "world_run": world_id})

func resume_world(world_id: String) -> bool:
	var active: Dictionary = read_file("active.json", {})
	if str(active.get("world_run", "")) == world_id:
		server_run = str(active.get("run_id", ""))
	else:
		var cp: Dictionary = game.load_checkpoint()
		if str(cp.get("run_id", "")) == world_id and str(cp.get("account_id", "")) == str(identity.get("id", "")):
			server_run = str(cp.get("account_run", ""))
	return server_run != ""

func ticket(callback: Callable) -> void:
	if not signed_in():
		callback.call("")
		return
	request("/api/v1/lobby-ticket", {}, func(code, data, _headers):
		if code != 200: message.emit("Account lobby sign-in unavailable. Connecting to the relay as a guest.")
		callback.call(str(data.get("ticket", "")) if code == 200 else "")
	)

func sign_in() -> void:
	if not switch_allowed(): return
	if vault != null and state == "guest" and FileAccess.file_exists(vault.file_for(base_url())):
		# A session kept by play_guest() is tried before asking for a new approval.
		resume_saved_session()
		if state == "restoring": return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.assign('/account?return=' + encodeURIComponent(location.pathname + location.search))", true)
		return
	state = "signing_in"
	request("/api/auth/device/code", {"client_id": "relic-" + platform_id()}, func(code, data, _headers):
		if code != 200:
			state = "needs_sign_in" if not identity.is_empty() else "guest"
			message.emit("Sign-in is unavailable. You can still play as Guest.")
			return
		device = data
		device_remaining = float(data.expires_in)
		device_deadline = Time.get_unix_time_from_system() + device_remaining
		device_interval = float(data.interval)
		device_wait = device_interval
		open_device_page()
	)

func open_device_page() -> void:
	if device.has("verification_uri_complete"):
		if not persist_pending(): return
		var url = str(device.verification_uri_complete)
		OS.shell_open(base_url() + url if url.begins_with("/") else url)

func cancel_sign_in() -> void:
	device = {}
	state = "needs_sign_in" if not identity.is_empty() else "guest"
	generation += 1

# Choosing Guest while a saved Android session is still unconfirmed (usually offline)
# keeps the encrypted session for the next launch or Sign In instead of revoking it.
func play_guest() -> void:
	if state != "restoring" or vault == null:
		sign_out()
		return
	generation += 1
	requests = requests.slice(0, 1) if busy else []
	token = ""
	retry_wait = 0
	state = "guest"
	status = "Offline"
	game.activate_guest()
	changed.emit()
	message.emit("Playing as Guest. Your saved sign-in is kept; choose Sign In to restore it.")

func sign_out() -> void:
	if not switch_allowed(): return
	if vault != null and not vault.erase(base_url()):
		message.emit("Could not remove the saved session. Free device storage and retry sign-out.")
		return
	generation += 1
	requests = requests.slice(0, 1) if busy else []
	requests.append({"path": "/api/auth/sign-out", "url": base_url() + "/api/auth/sign-out", "body": {}, "callback": func(code, _data, _headers):
		if code != 200: message.emit("Signed out locally. Server session revocation failed; retry sign-out in your browser account page.")
	, "method": HTTPClient.METHOD_POST, "generation": generation, "credential": token, "revoke": true})
	token = ""
	identity = {}
	profile = {}
	revision = 0
	last_sync = 0
	outbox = []
	device = {}
	migration = {}
	server_run = ""
	start_intent = {}
	last_result_run = ""
	pending_run_callback = Callable()
	takeover_needed = false
	foreground_seconds = 0
	state = "guest"
	status = "Offline"
	game.activate_guest()
	changed.emit()
	pump()

func clear_local_session() -> void:
	if not switch_allowed() or identity.is_empty(): return
	if not outbox.is_empty():
		message.emit("Sync pending progress before clearing this device's account cache.")
		return
	for file in ["profile.json", "active.json", "outbox.json"]:
		var path = ProjectSettings.globalize_path(path_for(file))
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("localStorage.removeItem(%s)" % JSON.stringify("relicAccount:" + str(identity.id) + ":" + file), true)
	if OS.has_feature("web"): JavaScriptBridge.force_fs_sync()
	sign_out()

func empty_account() -> bool:
	return not profile.is_empty() and int(profile.runs) == 0 and int(profile.kills) == 0 and int(profile.zenny) == 0 and profile.trees.is_empty()

func preview_migration(source: Dictionary) -> void:
	if not switch_allowed() or not signed_in() or not empty_account(): return
	var value = source.duplicate(true)
	value.erase("revision")
	request("/api/v1/migrate-guest", {"profile": value}, func(code, data, _headers):
		if code == 200:
			migration = {"profile": value, "confirm": data.confirm, "preview": data.preview}
			game.mode = "account"
		else: message.emit("Guest adoption refused. Your local save is unchanged.")
	)

func confirm_migration() -> void:
	if not switch_allowed() or migration.is_empty(): return
	enqueue("/api/v1/migrate-guest", {"op_id": uuid(), "profile": migration.profile, "confirm": migration.confirm})
	migration = {}

func _process(dt: float) -> void:
	if game == null: return
	if backgrounded: return
	if game.in_run() and DisplayServer.window_is_focused() and signed_in() and game.profile_source == "account": foreground_seconds += dt
	# Play-time estimate for the owner dashboard: every two minutes in a dig, and when it ends.
	if foreground_seconds >= 120 or (foreground_seconds >= 1 and not game.in_run()): report_activity()
	if retry_wait > 0:
		retry_wait -= dt
		if retry_wait <= 0:
			if state == "restoring": refresh()
			else: flush()
	if signed_in() and server_run != "" and game.in_run():
		heartbeat_clock += dt
		if heartbeat_clock >= 120:
			heartbeat_clock = 0
			request("/api/v1/runs/" + server_run + "/heartbeat", null, func(code, _data, _headers):
				if code == 409: message.emit("This account's dig was taken over elsewhere. Your result will still sync.")
			)
	if state != "signing_in" or device.is_empty(): return
	device_remaining -= dt
	if device_deadline > 0: device_remaining = minf(device_remaining, device_deadline - Time.get_unix_time_from_system())
	device_wait -= dt
	if device_remaining <= 0:
		cancel_sign_in()
		message.emit("Sign-in code expired. Please sign in again.")
		return
	if device_wait > 0: return
	for r in requests:
		if r.path == "/api/auth/device/token": return
	device_wait = device_interval
	request("/api/auth/device/token", {"grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": device.device_code, "client_id": "relic-" + platform_id()}, func(code, data, _headers):
		if code == 200:
			token = str(data.access_token)
			if OS.has_feature("android"):
				if vault == null: vault = DiverAndroidVault.new()
				if not vault.save_token(base_url(), token):
					vault.erase(base_url())
					message.emit("Secure session storage unavailable. Sign in again after restarting.")
			device = {}
			refresh()
		elif data.get("error") == "slow_down":
			device_interval += 5
			device_wait = maxf(device_wait, device_interval)
		elif data.get("error") in ["access_denied", "expired_token", "invalid_grant"]:
			cancel_sign_in()
			message.emit("Sign-in ended. You can try again.")
	)
