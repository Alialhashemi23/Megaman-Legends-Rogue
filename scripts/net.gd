extends Node
class_name DiverNet

# Online co-op transport. Every client connects to the lobby server over a
# WebSocket; the lobby host (any slot — hosting moves if the host leaves) runs
# the authoritative simulation and the server relays packets between members.
# Lobby commands are JSON text frames. Game traffic is one binary frame per
# frame: [target slot][var_to_bytes(Array of messages)]. Target 255 stores the
# host's run checkpoint on the server so a dig survives everyone dropping out.

enum {M_INFO, M_STATE, M_SHOT, M_START, M_SNAP, M_ATTACK, M_RESOLVE, M_DAMAGE, M_DIE, M_PICKUP, M_PICKUP_GONE, M_USED, M_HIT, M_INTERACT, M_FROST, M_HEAL, M_ITEM, M_XP, M_CHOICE, M_NOTIFY, M_FLOOR, M_END, M_SYNC, M_LIGHTNING, M_CLEARED, M_RESTORE, M_CHAT, M_PING, M_VISITED}
# Bump when game messages change so mismatched builds can't share a lobby.
const NET_VERSION = 7
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
	slot = 0
	host_slot = 0
	lobby_code = ""
	lobby_password = ""
	lobby = {}
	outbox.clear()
	set_page_lobby("")

# Send a lobby command now if connected; returns false when there's no live socket.
func send_command(message: Dictionary) -> bool:
	if not connected() or socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	socket.send_text(JSON.stringify(message))
	return true

func command(message: Dictionary) -> void:
	if send_command(message): return
	else:
		pending = message
		connect_server()

func create_lobby(title: String, public_lobby: bool, password: String = "") -> void:
	error_text = ""
	command({"t": "create", "name": title, "public": public_lobby, "password": password.strip_edges().left(24)})

func join_lobby(code: String, password: String = "") -> void:
	error_text = ""
	command({"t": "join", "code": code.strip_edges().to_upper(), "password": password.strip_edges().left(24)})

# Rejoin a lobby, recreating it under the same code if the server forgot it.
func resume_lobby(code: String, title: String, public_lobby: bool, password: String) -> void:
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
				var hello = {"t": "hello", "name": player_name, "id": guest_id, "v": NET_VERSION}
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
			account_confirmed = bool(message.get("account", false))
			player_id = "acct:" + str(game.account.identity.id) if account_confirmed else guest_id
		"lobbies":
			if message.get("lobbies") is Array: public_lobbies = message.lobbies
		"joined":
			slot = int(message.get("slot", 0))
			host_slot = int(message.get("hostSlot", 1))
			lobby_code = str(message.get("code", ""))
			lobby_password = str(message.get("password", ""))
			error_text = ""
			reconnect_attempts = 0
			set_page_lobby(lobby_code)
			if is_instance_valid(game): game.lobby_entered(message)
		"lobby":
			if message.get("lobby") is Dictionary:
				lobby = message.lobby
				host_slot = int(lobby.get("hostSlot", host_slot))
			if is_instance_valid(game): game.lobby_updated()
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
			if status == "reconnecting" or (active() and code in ["banned", "version", "full", "locked"]):
				give_up(error_text)
			elif code in ["not_found", "full", "locked", "password", "banned", "version"]:
				set_page_lobby("")
			if is_instance_valid(game): game.join_failed(code)
		"pong":
			ping_ms = Time.get_ticks_msec() - int(message.get("time", 0))

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
