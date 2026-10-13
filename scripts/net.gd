extends Node
class_name DiverNet

# Online co-op transport. Every client connects to the lobby server over a
# WebSocket; the lobby host (slot 1) runs the authoritative simulation and the
# server relays packets between members. Lobby commands are JSON text frames.
# Game traffic is one binary frame per frame: [target slot][var_to_bytes(Array of messages)].

enum {M_INFO, M_STATE, M_SHOT, M_START, M_SNAP, M_ATTACK, M_RESOLVE, M_DAMAGE, M_DIE, M_PICKUP, M_PICKUP_GONE, M_USED, M_HIT, M_INTERACT, M_FROST, M_HEAL, M_ITEM, M_XP, M_CHOICE, M_NOTIFY, M_FLOOR, M_END, M_SYNC, M_LIGHTNING, M_CLEARED, M_RESTORE, M_LOBBY}
const DEFAULT_SERVER = "ws://127.0.0.1:8080/ws"
const PROFILE_PATH = "res://save/online.json"
const MAX_PLAYERS = 4
const SLOT_COLORS = [Color("fff9df"), Color("ffdc68"), Color("7ad6ef"), Color("9cde70"), Color("ff9565")]

var game: Node
var socket: WebSocketPeer
var status = "offline"  # offline, connecting, online
var server_url = ""
var player_name = ""
var slot = 0
var lobby_code = ""
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

func _ready() -> void:
	if OS.has_feature("web"): profile_path = "user://online.json"
	load_profile()
	if player_name == "": player_name = "Digger %d" % (absi(hash([Time.get_unix_time_from_system(), Time.get_ticks_usec(), OS.get_unique_id()])) % 900 + 100)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): server_url = arg.substr(9)
		if arg.begins_with("--name="): player_name = arg.substr(7).left(16)
	if OS.has_feature("web"):
		var page = JavaScriptBridge.eval("(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'", true)
		if page is String and page.contains("/ws"): server_url = page
	if server_url == "": server_url = str(ProjectSettings.get_setting("relic_diver/online/default_server", DEFAULT_SERVER))

func active() -> bool:
	return slot > 0

func is_host() -> bool:
	return slot == 1

func is_guest() -> bool:
	return slot > 1

# Lobby code requested by the page URL (?lobby=CODE), if any.
func invited_code() -> String:
	if not OS.has_feature("web"): return ""
	var code = JavaScriptBridge.eval("new URLSearchParams(location.search).get('lobby') || ''", true)
	return str(code).strip_edges().to_upper().left(12) if code is String else ""

func invite_link() -> String:
	if lobby_code == "": return ""
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("location.origin", true)
		if origin is String: return "%s/?lobby=%s" % [origin, lobby_code]
	var base = server_url.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws")
	return "%s/?lobby=%s" % [base, lobby_code]

func set_page_lobby(code: String) -> void:
	if not OS.has_feature("web"): return
	var query = "?lobby=" + code if code != "" else ""
	JavaScriptBridge.eval("history.replaceState(null, '', location.pathname + %s)" % JSON.stringify(query), true)

func connect_server() -> void:
	if status != "offline": return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 21
	socket.outbound_buffer_size = 1 << 21
	socket.max_queued_packets = 4096
	error_text = ""
	if socket.connect_to_url(server_url) != OK:
		error_text = "Could not reach the dig server."
		socket = null
		return
	status = "connecting"

func disconnect_server() -> void:
	if socket: socket.close()
	socket = null
	status = "offline"
	reset_lobby()

func reset_lobby() -> void:
	slot = 0
	lobby_code = ""
	lobby = {}
	outbox.clear()
	set_page_lobby("")

func command(message: Dictionary) -> void:
	if status == "online" and socket: socket.send_text(JSON.stringify(message))
	else:
		pending = message
		connect_server()

func create_lobby(title: String, public_lobby: bool) -> void:
	command({"t": "create", "name": title, "public": public_lobby})

func join_lobby(code: String) -> void:
	error_text = ""
	command({"t": "join", "code": code.strip_edges().to_upper()})

func leave_lobby() -> void:
	if status == "online" and socket and active(): socket.send_text(JSON.stringify({"t": "leave"}))
	reset_lobby()

func refresh_list() -> void:
	list_clock = 0.0
	if status == "online": command({"t": "list"})
	else: connect_server()

func rename(value: String) -> void:
	player_name = value.strip_edges().left(16)
	save_profile()
	if status == "online": socket.send_text(JSON.stringify({"t": "name", "name": player_name}))

func report_status(state: String, depth: int) -> void:
	if is_host() and status == "online": socket.send_text(JSON.stringify({"t": "status", "state": state, "depth": depth}))

# Queue a game message for one slot (0 = everyone else in the lobby).
func send(target: int, message: Array) -> void:
	if not active(): return
	if not outbox.has(target): outbox[target] = []
	outbox[target].append(message)

func broadcast(message: Array) -> void:
	send(0, message)

func to_host(message: Array) -> void:
	send(1, message)

func members() -> Array:
	return lobby.get("players", [])

func member_name(member_slot: int) -> String:
	for p in members():
		if int(p.slot) == member_slot: return str(p.name)
	return "Digger"

func _process(dt: float) -> void:
	if socket == null: return
	socket.poll()
	var state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if status == "connecting":
			status = "online"
			connected_once = true
			socket.send_text(JSON.stringify({"t": "hello", "name": player_name}))
			socket.send_text(JSON.stringify({"t": "list"}))
			if not pending.is_empty():
				socket.send_text(JSON.stringify(pending))
				pending = {}
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			if socket.was_string_packet(): handle_command(JSON.parse_string(packet.get_string_from_utf8()))
			elif packet.size() > 1:
				var batch = bytes_to_var(packet.slice(1))
				if batch is Array:
					for message in batch:
						if message is Array and not message.is_empty() and is_instance_valid(game): game.net_message(packet[0], message)
		flush()
		ping_clock += dt
		if ping_clock > 5.0:
			ping_clock = 0.0
			socket.send_text(JSON.stringify({"t": "ping", "time": Time.get_ticks_msec()}))
		if not active() and is_instance_valid(game) and game.mode == "online":
			list_clock += dt
			if list_clock > 4.0: refresh_list()
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_active = active()
		socket = null
		status = "offline"
		if not connected_once: error_text = "Could not reach the dig server."
		else: error_text = "Connection to the dig server was lost."
		connected_once = false
		pending = {}
		if was_active:
			reset_lobby()
			if is_instance_valid(game): game.lobby_closed("Connection lost")

func flush() -> void:
	if socket == null or status != "online": return
	for target in outbox:
		if outbox[target].is_empty(): continue
		var payload = PackedByteArray([target])
		payload.append_array(var_to_bytes(outbox[target]))
		socket.put_packet(payload)
	outbox.clear()

func handle_command(message) -> void:
	if not message is Dictionary: return
	match str(message.get("t", "")):
		"lobbies":
			public_lobbies = message.get("lobbies", [])
		"joined":
			slot = int(message.slot)
			lobby_code = str(message.code)
			error_text = ""
			set_page_lobby(lobby_code)
			if is_instance_valid(game): game.lobby_entered()
		"lobby":
			lobby = message.get("lobby", {})
			if is_instance_valid(game): game.lobby_updated()
		"entered":
			if is_instance_valid(game): game.peer_entered(int(message.slot))
		"left":
			if is_instance_valid(game): game.peer_left(int(message.slot))
		"closed":
			reset_lobby()
			if is_instance_valid(game): game.lobby_closed("The host closed the lobby")
		"error":
			var code = str(message.get("code", ""))
			error_text = {"not_found": "That lobby no longer exists.", "full": "That lobby is full (4 diggers).", "server_full": "The server is busy. Try again soon."}.get(code, "Server error: " + code)
			if code in ["not_found", "full"]: set_page_lobby("")
		"pong":
			ping_ms = Time.get_ticks_msec() - int(message.get("time", 0))

func load_profile() -> void:
	if not FileAccess.file_exists(profile_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if data is Dictionary:
		player_name = str(data.get("name", "")).left(16)
		if not OS.has_feature("web"): server_url = str(data.get("server", ""))

func save_profile() -> void:
	if is_instance_valid(game) and game.smoke_test: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_path.get_base_dir()))
	var f = FileAccess.open(profile_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"name": player_name, "server": server_url}, "\t"))
