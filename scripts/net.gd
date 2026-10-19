extends Node
class_name DiverNet

# Online co-op transport. Every client connects to the lobby server over a
# WebSocket; the lobby host (any slot — hosting moves if the host leaves) runs
# the authoritative simulation and the server relays packets between members.
# Lobby commands are JSON text frames. Game traffic is one binary frame per
# frame: [target slot][var_to_bytes(Array of messages)]. Target 255 stores the
# host's run checkpoint on the server so a dig survives everyone dropping out.

enum {M_INFO, M_STATE, M_SHOT, M_START, M_SNAP, M_ATTACK, M_RESOLVE, M_DAMAGE, M_DIE, M_PICKUP, M_PICKUP_GONE, M_USED, M_HIT, M_INTERACT, M_FROST, M_HEAL, M_ITEM, M_XP, M_CHOICE, M_NOTIFY, M_FLOOR, M_END, M_SYNC, M_LIGHTNING, M_CLEARED, M_RESTORE, M_CHAT, M_PING, M_VISITED, M_SPAWN, M_RELAY}
# Bump when game messages change so mismatched builds can't share a lobby.
const NET_VERSION = 13
const READY_FEATURE = "ready_v1"
const CHECKPOINT_TARGET = 255
const DEFAULT_SERVER = "ws://127.0.0.1:8080/ws"
const PROFILE_PATH = "res://save/online.json"
const MAX_PLAYERS = 4
const RECONNECT_WINDOW = 90.0
const SLOT_COLORS = [Color("fff9df"), Color("ffdc68"), Color("7ad6ef"), Color("9cde70"), Color("ff9565")]
const ERRORS = {
	"not_found": "That lobby no longer exists.",
	"full": "That lobby is full (4 diggers).",
	"server_full": "The server is busy. Try again soon.",
	"version": "That lobby runs a different version of the game. Refresh the page to update.",
	"update_required": "Update Android from the game's /downloads/android/ page before joining online. Guest solo remains available.",
	"locked": "That lobby is locked by its host.",
	"password": "Wrong lobby password.",
	"banned": "You were removed from that lobby.",
	"ready_feature": "The game and lobby server need compatible readiness updates. Update both before starting online.",
}
const READY_ERRORS = {
	"ready_stale": "The party changed. Review the current loadout and Ready again.",
	"ready_selection_required": "Waiting for the server to confirm your loadout.",
	"ready_not_host": "Only the host can start or cancel the party countdown.",
	"ready_waiting": "Everyone must Ready before the host starts.",
	"ready_phase": "Wait for the current launch to finish or cancel it.",
	"ready_attempt": "That launch is no longer current.",
	"ready_invalid": "The server could not accept that readiness request.",
	"ready_feature": "Update the game and lobby server before starting online.",
}

var game: Node
var socket: WebSocketPeer
var status = "offline"  # offline, connecting, online, reconnecting
var server_url = ""
var player_name = ""
var player_id = ""
var slot = 0
var host_slot = 0
var lobby_code = ""
var lobby_password = ""
var lobby: Dictionary = {}
var public_lobbies: Array = []
var error_text = ""
var pending: Dictionary = {}
var outbox: Dictionary = {}
var profile_path = PROFILE_PATH
var list_clock = 0.0
var ping_clock = 0.0
var ping_ms = 0
var connected_once = false
var hello_pending = false
var account_confirmed = false
var guest_id = ""
var reconnect_clock = 0.0
var reconnect_wait = 0.0
var reconnect_attempts = 0
var command_transport: Callable # Isolated client checks; normal play uses the socket.
var server_ready = false
var connection_epoch = 0
var lobby_epoch = 0
var ready_state_rev = 0
var selection_seq = 0
var build_revision = 0
var sent_selection: Dictionary = {}
var selection_fingerprint: Dictionary = {}
var launch_payload: Dictionary = {}
var committed_attempt = ""
var recovery_expected = false
var awaiting_run_sync = false
var first_snapshot = true
var countdown_seen = 0
var countdown_attempt = ""

func _ready() -> void:
	profile_path = DiverPaths.pick(PROFILE_PATH, "user://online.json")
	load_profile()
	if player_name == "": player_name = "Digger %d" % (absi(hash([Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()])) % 900 + 100)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): server_url = arg.substr(9)
		if arg.begins_with("--name="): player_name = arg.substr(7).left(16)
		if arg.begins_with("--player-id="): player_id = arg.substr(12).left(40)
	# A stable identity lets the dig recognise a digger who refreshes or reconnects.
	if player_id == "":
		player_id = "%08x%08x" % [randi(), absi(hash([Time.get_ticks_usec(), Time.get_unix_time_from_system()])) & 0xffffffff]
		if DisplayServer.get_name() != "headless": save_profile()
	if OS.has_feature("web"):
		var page = JavaScriptBridge.eval("(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'", true)
		if page is String and page.contains("/ws"): server_url = page
	if server_url == "": server_url = str(ProjectSettings.get_setting("relic_diver/online/default_server", DEFAULT_SERVER))
	guest_id = player_id

# In a lobby (possibly reconnecting to it).
func active() -> bool:
	return slot > 0

func connected() -> bool:
	return status == "online"

func reconnecting() -> bool:
	return status == "reconnecting"

func is_host() -> bool:
	return slot > 0 and slot == host_slot

func is_guest() -> bool:
	return slot > 0 and slot != host_slot

func url_param(name: String) -> String:
	if not OS.has_feature("web"): return ""
	var value = JavaScriptBridge.eval("new URLSearchParams(location.search).get(%s) || ''" % JSON.stringify(name), true)
	return str(value).strip_edges().left(24) if value is String else ""

# Lobby code requested by the page URL (?lobby=CODE&key=PASSWORD), if any.
func invited_code() -> String:
	return url_param("lobby").to_upper().left(12)

func invite_link() -> String:
	if lobby_code == "": return ""
	var base = server_url.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws")
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("location.origin", true)
		if origin is String: base = origin
	var link = "%s/?lobby=%s" % [base, lobby_code]
	if lobby_password != "": link += "&key=" + lobby_password.uri_encode()
	return link

func set_page_lobby(code: String) -> void:
	if not OS.has_feature("web"): return
	var query = ""
	if code != "":
		query = "?lobby=" + code
		if lobby_password != "": query += "&key=" + lobby_password.uri_encode()
	JavaScriptBridge.eval("history.replaceState(null, '', location.pathname + %s)" % JSON.stringify(query), true)

func connect_server() -> void:
	if socket != null: return
	if OS.has_feature("android") and game.android_updates.blocks_online():
		error_text = "Update Android from " + game.account.base_url() + "/downloads/android/ before joining online. Guest solo remains available."
		return
	connection_epoch += 1
	server_ready = false
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 21
	socket.outbound_buffer_size = 1 << 21
	socket.max_queued_packets = 4096
	if socket.connect_to_url(server_url) != OK:
		socket = null
		if not active(): error_text = "Could not reach the dig server."
		return
	if status != "reconnecting": status = "connecting"

func disconnect_server() -> void:
	if socket: socket.close()
	socket = null
	hello_pending = false
	account_confirmed = false
	player_id = guest_id
	status = "offline"
	reset_lobby()

func reset_lobby() -> void:
	clear_readiness()
	slot = 0
	host_slot = 0
	lobby_code = ""
	lobby_password = ""
	lobby = {}
	outbox.clear()
	set_page_lobby("")

# Send a lobby command now if connected; returns false when there's no live socket.
func send_command(message: Dictionary) -> bool:
	if command_transport.is_valid(): return bool(command_transport.call(message))
	if not connected() or socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	socket.send_text(JSON.stringify(message))
	return true

func command(message: Dictionary) -> void:
	if send_command(message): return
	else:
		pending = message
		connect_server()

func create_lobby(title: String, public_lobby: bool, password: String = "") -> void:
	recovery_expected = false
	error_text = ""
	command({"t": "create", "name": title, "public": public_lobby, "password": password.strip_edges().left(24)})

func join_lobby(code: String, password: String = "") -> void:
	recovery_expected = false
	error_text = ""
	command({"t": "join", "code": code.strip_edges().to_upper(), "password": password.strip_edges().left(24)})

# Rejoin a lobby, recreating it under the same code if the server forgot it.
func resume_lobby(code: String, title: String, public_lobby: bool, password: String) -> void:
	recovery_expected = true
	error_text = ""
	command(resume_message(code, title, public_lobby, password))

func resume_message(code: String, title: String, public_lobby: bool, password: String) -> Dictionary:
	return {"t": "resume", "code": code, "name": title, "public": public_lobby, "password": password}

func leave_lobby() -> void:
	if active(): send_command({"t": "leave"})
	if status == "reconnecting":
		if socket: socket.close()
		socket = null
		status = "offline"
	reset_lobby()

func refresh_list() -> void:
	list_clock = 0.0
	if connected(): command({"t": "list"})
	else: connect_server()

func rename(value: String) -> void:
	player_name = value.strip_edges().left(16)
	save_profile()
	send_command({"t": "name", "name": player_name})

func report_status(state: String, depth: int) -> void:
	if is_host(): send_command({"t": "status", "state": state, "depth": depth})

func kick(member_slot: int) -> void:
	if is_host(): send_command({"t": "kick", "slot": member_slot})

func set_locked(value: bool) -> void:
	if is_host(): send_command({"t": "lock", "locked": value})

func store_checkpoint(data: PackedByteArray) -> void:
	if not is_host() or not connected() or socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	var payload = PackedByteArray([CHECKPOINT_TARGET])
	payload.append_array(data)
	socket.put_packet(payload)

# Queue a game message for one slot (0 = everyone else in the lobby).
func send(target: int, message: Array) -> void:
	if not active() or not connected(): return
	if not outbox.has(target): outbox[target] = []
	outbox[target].append(message)

func broadcast(message: Array) -> void:
	send(0, message)

func to_host(message: Array) -> void:
	if host_slot > 0: send(host_slot, message)

func members() -> Array:
	return lobby.get("players", [])

func member_name(member_slot: int) -> String:
	for p in members():
		if int(p.slot) == member_slot: return str(p.name)
	return "Digger"

func member_id(member_slot: int) -> String:
	for p in members():
		if int(p.slot) == member_slot: return str(p.get("id", ""))
	return ""

func _process(dt: float) -> void:
	if status == "reconnecting" and socket == null:
		reconnect_clock += dt
		reconnect_wait -= dt
		if reconnect_clock > RECONNECT_WINDOW:
			give_up("Couldn't reconnect to the dig server.")
			return
		if reconnect_wait <= 0:
			reconnect_attempts += 1
			reconnect_wait = minf(5.0, 0.5 * pow(2, mini(reconnect_attempts, 4)))
			connect_server()
	if socket == null: return
	socket.poll()
	var state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if status != "online" and not hello_pending:
			var rejoining = status == "reconnecting"
			hello_pending = true
			var current_socket = socket
			game.account.ticket(func(ticket):
				if socket != current_socket or socket == null: return
				hello_pending = false
				status = "online"
				connected_once = true
				var hello = {"t": "hello", "name": player_name, "id": guest_id, "v": NET_VERSION, "features": [READY_FEATURE]}
				if OS.has_feature("android"):
					hello.platform = "android"
					hello.androidVersionCode = game.android_updates.installed_code
				if ticket != "": hello.ticket = ticket
				socket.send_text(JSON.stringify(hello))
				socket.send_text(JSON.stringify({"t": "list"}))
				if rejoining and lobby_code != "":
					socket.send_text(JSON.stringify(resume_message(lobby_code, str(lobby.get("name", "")), bool(lobby.get("isPublic", true)), lobby_password)))
				elif not pending.is_empty(): socket.send_text(JSON.stringify(pending))
				pending = {}
			)
		while socket != null and socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			if socket.was_string_packet(): handle_command(JSON.parse_string(packet.get_string_from_utf8()))
			elif packet.size() > 1:
				var data = bytes_to_var(packet.slice(1))
				if packet[0] == CHECKPOINT_TARGET:
					if data is Dictionary and is_instance_valid(game): game.server_checkpoint(data)
				elif data is Array:
					for message in data:
						if message is Array and not message.is_empty() and is_instance_valid(game): game.net_message(packet[0], message)
		flush()
		ping_clock += dt
		if ping_clock > 5.0 and socket:
			ping_clock = 0.0
			socket.send_text(JSON.stringify({"t": "ping", "time": Time.get_ticks_msec()}))
		if not active() and is_instance_valid(game) and game.mode == "online":
			list_clock += dt
			if list_clock > 4.0: refresh_list()
	elif state == WebSocketPeer.STATE_CLOSED:
		awaiting_run_sync = game.in_run()
		recovery_expected = game.in_run() or recovery_expected
		clear_readiness(false)
		connection_epoch += 1
		server_ready = false
		hello_pending = false
		socket = null
		outbox.clear()
		pending = {}
		if active():
			# Stay in the lobby and keep trying; the dig is frozen until we're back.
			if status != "reconnecting":
				status = "reconnecting"
				reconnect_clock = 0.0
				reconnect_wait = 0.5
				reconnect_attempts = 0
				if is_instance_valid(game): game.connection_lost()
			return
		status = "offline"
		error_text = "Connection to the dig server was lost." if connected_once else "Could not reach the dig server."
		connected_once = false

func give_up(reason: String) -> void:
	if socket: socket.close()
	socket = null
	status = "offline"
	error_text = reason
	reset_lobby()
	if is_instance_valid(game): game.connection_failed(reason)

func flush() -> void:
	if socket == null or not connected(): return
	for target in outbox:
		if outbox[target].is_empty(): continue
		var payload = PackedByteArray([target])
		payload.append_array(var_to_bytes(outbox[target]))
		socket.put_packet(payload)
	outbox.clear()

func handle_command(message) -> void:
	if not message is Dictionary: return
	match str(message.get("t", "")):
		"welcome":
			server_ready = message.get("features") is Array and READY_FEATURE in message.features
			if not server_ready: error_text = ERRORS.ready_feature
			account_confirmed = bool(message.get("account", false))
			player_id = "acct:" + str(game.account.identity.id) if account_confirmed else guest_id
		"lobbies":
			if message.get("lobbies") is Array: public_lobbies = message.lobbies
		"joined":
			var recovering = recovery_expected or game.in_run()
			clear_readiness(false)
			recovery_expected = recovering or bool(message.get("checkpoint", false))
			slot = int(message.get("slot", 0))
			host_slot = int(message.get("hostSlot", 1))
			lobby_code = str(message.get("code", ""))
			lobby_password = str(message.get("password", ""))
			error_text = ""
			reconnect_attempts = 0
			set_page_lobby(lobby_code)
			if is_instance_valid(game): game.lobby_entered(message)
		"lobby":
			accept_lobby(message.get("lobby"))
		"ready_error":
			if not active() or not integer(message.get("setupRev"), 0): return
			if message.has("attemptId") and message.attemptId != readiness().get("attemptId", ""): return
			error_text = READY_ERRORS.get(str(message.get("code", "")), "Readiness request was refused.")
		"launch_prepare", "launch_commit":
			accept_launch(message)
		"launch_aborted":
			if message.get("code") != lobby_code or not message.get("attemptId") is String: return
			if message.attemptId != launch_payload.get("attemptId", readiness().get("attemptId", "")): return
			game.abort_launch(str(message.get("reason", "cancel")))
			launch_payload = {}
		"host":
			host_slot = int(message.get("slot", host_slot))
			if is_instance_valid(game): game.host_changed()
		"entered":
			if is_instance_valid(game): game.peer_entered(int(message.get("slot", 0)), str(message.get("id", "")))
		"left":
			if is_instance_valid(game): game.peer_left(int(message.get("slot", 0)))
		"kicked":
			reset_lobby()
			if is_instance_valid(game): game.kicked()
		"replaced":
			# This lobby seat moved to a newer tab or window; stop without reconnecting.
			if socket: socket.close()
			socket = null
			status = "offline"
			reset_lobby()
			if is_instance_valid(game): game.connection_failed("Your dig continued in another tab or window.")
		"error":
			var code = str(message.get("code", ""))
			if code == "bad_ticket":
				account_confirmed = false
				player_id = guest_id
				game.notify("ACCOUNT", "Lobby sign-in unavailable. Connected as a guest.")
				return
			error_text = ERRORS.get(code, "Server error: " + code)
			if code == "update_required":
				if active(): give_up(error_text)
				else: disconnect_server()
				game.notify("UPDATE ANDROID", error_text)
				return
			if status == "reconnecting" or (active() and code in ["banned", "version", "full", "locked", "ready_feature"]):
				give_up(error_text)
			elif code in ["not_found", "full", "locked", "password", "banned", "version", "ready_feature"]:
				set_page_lobby("")
			if is_instance_valid(game): game.join_failed(code)
		"pong":
			ping_ms = Time.get_ticks_msec() - int(message.get("time", 0))

# Readiness is connection/lobby state, never checkpoint/profile data.
func clear_readiness(clear_recovery: bool = true) -> void:
	if is_instance_valid(game): game.abort_launch("")
	lobby_epoch += 1
	ready_state_rev = 0
	selection_seq = 0
	sent_selection = {}
	selection_fingerprint = {}
	launch_payload = {}
	committed_attempt = ""
	countdown_attempt = ""
	first_snapshot = true
	if clear_recovery:
		recovery_expected = false
		awaiting_run_sync = false
	# Keep the old lobby summary for reconnect, but discard its expired consent.
	lobby.erase("readiness")

func context() -> Array:
	return [connection_epoch, lobby_epoch, lobby_code, socket]

func current_context(value: Array) -> bool:
	return active() and connected() and value == context()

static func integer(value: Variant, minimum: int, maximum: int = 9007199254740991) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

func readiness() -> Dictionary:
	return lobby.get("readiness", {})

func ready_phase() -> String:
	return str(readiness().get("phase", "idle"))

func loadout_locked() -> bool:
	return active() and ready_phase() in ["countdown", "preparing"]

func own_member() -> Dictionary:
	for member in members():
		if int(member.slot) == slot: return member
	return {}

func own_ready() -> bool:
	return bool(own_member().get("ready", false))

func current_selection() -> Dictionary:
	return {"character": game.selected_character, "weapon": game.selected_weapon, "spec": game.equipped_spec(game.selected_character), "skills": DiverProgression.owned(game.meta, game.selected_character).duplicate()}

func publish_selection() -> void:
	if not active() or not connected() or not server_ready or readiness().is_empty() or loadout_locked(): return
	var fingerprint = current_selection()
	if fingerprint == selection_fingerprint and selection_seq > 0: return
	var revision = build_revision + 1
	var next = {"t": "selection", "seq": selection_seq + 1, "character": fingerprint.character, "weapon": fingerprint.weapon, "spec": fingerprint.spec, "buildRev": revision}
	if not send_command(next): return
	build_revision = revision
	selection_seq += 1
	selection_fingerprint = fingerprint
	sent_selection = next.duplicate()
	sent_selection.erase("t")

func selection_acknowledged() -> bool:
	return selection_seq > 0 and own_member().get("selection", {}) == sent_selection and current_selection() == selection_fingerprint

func set_ready(value: bool) -> void:
	if not active() or not connected() or not server_ready or readiness().is_empty(): return
	if value and (ready_phase() != "idle" or not selection_acknowledged() or not game.account_ready_to_prepare()): return
	send_command({"t": "ready", "setupRev": int(readiness().setupRev), "ready": value})

func can_start() -> bool:
	return server_ready and connected() and is_host() and selection_acknowledged() and bool(readiness().get("canStart", false)) and ready_phase() == "idle"

func cancel_launch() -> void:
	if not loadout_locked(): return
	if is_host(): send_command({"t": "start_cancel", "attemptId": str(readiness().get("attemptId", ""))})
	else: set_ready(false)

func waiting_names() -> String:
	var names: Array[String] = []
	for member_slot in readiness().get("waitingSlots", []): names.append(member_name(int(member_slot)))
	return ", ".join(names)

func countdown_left() -> int:
	# Approximate presentation only: the relay's prepare/commit authorizes launch.
	return maxi(0, 3 - int((Time.get_ticks_msec() - countdown_seen) / 1000))

func valid_ready_lobby(value: Dictionary) -> bool:
	var r: Variant = value.get("readiness")
	if not r is Dictionary or r.get("v") != 1 or not value.get("players") is Array: return false
	if not integer(r.get("setupRev"), 1) or not integer(r.get("stateRev"), 1): return false
	if not r.get("phase") in ["idle", "countdown", "preparing", "running"] or not r.get("attemptId") is String or not r.get("canStart") is bool: return false
	if not integer(r.get("deadlineMs"), 0) or not integer(r.get("prepareDeadlineMs"), 0) or not r.get("waitingSlots") is Array: return false
	if (r.phase in ["countdown", "preparing"]) != (r.attemptId.length() > 0 and r.attemptId.length() <= 64): return false
	var slots = []
	if value.players.is_empty() or value.players.size() > MAX_PLAYERS: return false
	for member in value.players:
		if not member is Dictionary or not integer(member.get("slot"), 1, MAX_PLAYERS) or int(member.slot) in slots: return false
		if not member.get("id") is String or not member.get("name") is String or not member.get("ready") is bool: return false
		slots.append(int(member.slot))
		if member.has("selection"):
			var s: Variant = member.selection
			if not s is Dictionary or not integer(s.get("seq"), 1) or not integer(s.get("character"), 0, 3) or not integer(s.get("weapon"), 0, 3) or not integer(s.get("buildRev"), 0) or not s.get("spec") in ["", "spec_a", "spec_b"]: return false
		elif member.ready: return false
	if not integer(value.get("hostSlot"), 1, MAX_PLAYERS) or not int(value.hostSlot) in slots or not slot in slots: return false
	for member_slot in r.waitingSlots:
		if not integer(member_slot, 1, MAX_PLAYERS) or not int(member_slot) in slots: return false
	return value.get("state") in ["lobby", "run"]

func accept_lobby(value: Variant) -> void:
	if not active() or not value is Dictionary or value.get("code") != lobby_code: return
	if not server_ready or not valid_ready_lobby(value):
		error_text = ERRORS.ready_feature
		return
	var r: Dictionary = value.readiness
	if int(r.stateRev) < ready_state_rev: return
	if first_snapshot and value.state == "run" and r.phase == "running": recovery_expected = true
	first_snapshot = false
	ready_state_rev = int(r.stateRev)
	lobby = value.duplicate(true)
	# JSON numbers arrive as floats. Canonicalize after validating their shape;
	# dictionary equality otherwise rejects an acknowledged integer loadout.
	for key in ["setupRev", "stateRev", "deadlineMs", "prepareDeadlineMs"]: lobby.readiness[key] = int(lobby.readiness[key])
	lobby.readiness.waitingSlots = lobby.readiness.waitingSlots.map(func(member_slot): return int(member_slot))
	for member in lobby.players:
		member.slot = int(member.slot)
		if member.has("selection"):
			for key in ["seq", "character", "weapon", "buildRev"]: member.selection[key] = int(member.selection[key])
	host_slot = int(lobby.hostSlot)
	if r.phase == "countdown" and r.attemptId != countdown_attempt:
		countdown_attempt = r.attemptId
		countdown_seen = Time.get_ticks_msec()
	if not launch_payload.is_empty() and (r.phase == "idle" or int(r.setupRev) != int(launch_payload.setupRev)):
		game.abort_launch("")
		launch_payload = {}
	game.lobby_updated()
	if not game.in_run(): publish_selection()

func valid_launch(value: Dictionary) -> bool:
	if not server_ready or not active() or not connected() or value.get("code") != lobby_code: return false
	if not value.get("attemptId") is String or value.attemptId.is_empty() or value.attemptId.length() > 64: return false
	if not integer(value.get("setupRev"), 1) or int(value.setupRev) != int(readiness().get("setupRev", 0)): return false
	if not integer(value.get("seed"), 1, 1000000) or not integer(value.get("party"), 1, MAX_PLAYERS) or not integer(value.get("hostSlot"), 1, MAX_PLAYERS) or int(value.hostSlot) != host_slot: return false
	if not value.get("runId") is String or value.runId.is_empty() or value.runId.length() > 96: return false
	for c in value.runId:
		if c.unicode_at(0) < 32 or c.unicode_at(0) > 126: return false
	if not value.get("slots") is Array or value.slots.size() != int(value.party) or value.slots.size() != members().size(): return false
	var expected = []
	for member in members(): expected.append(int(member.slot))
	expected.sort()
	var received = []
	for member_slot in value.slots:
		if not integer(member_slot, 1, MAX_PLAYERS): return false
		received.append(int(member_slot))
	return received == expected and slot in received

func accept_launch(value: Dictionary) -> void:
	if not valid_launch(value): return
	if value.attemptId == committed_attempt: return
	if value.t == "launch_prepare":
		if not integer(value.get("timeoutMs"), 1, 300000) or game.in_run(): return
		if value.attemptId != readiness().get("attemptId") or not ready_phase() in ["countdown", "preparing"] or not selection_acknowledged(): return
		if not launch_payload.is_empty(): return
		launch_payload = value.duplicate(true)
		game.prepare_launch(launch_payload, context())
	else:
		if launch_payload.is_empty() or game.in_run(): return
		for key in ["code", "attemptId", "setupRev", "hostSlot", "slots", "seed", "party", "runId"]:
			if value[key] != launch_payload[key]: return
		if game.commit_launch(value):
			committed_attempt = value.attemptId
			launch_payload = {}
			recovery_expected = false

func can_recover_sync(world: Dictionary) -> bool:
	if not launch_payload.is_empty() or loadout_locked(): return false
	if game.in_run(): return str(world.get("run_id", "")) == game.run_id
	return recovery_expected and (ready_phase() == "running" or not game.pending_restore.is_empty())

func load_profile() -> void:
	if not FileAccess.file_exists(profile_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if data is Dictionary:
		player_name = str(data.get("name", "")).left(16)
		player_id = str(data.get("id", "")).left(40)
		if not OS.has_feature("web"): server_url = str(data.get("server", ""))

func save_profile() -> void:
	if is_instance_valid(game) and game.smoke_test: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_path.get_base_dir()))
	var f = FileAccess.open(profile_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"name": player_name, "id": guest_id if guest_id != "" else player_id, "server": server_url}, "\t"))
