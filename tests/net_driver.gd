extends Node

# Scripted online co-op session used by tests/net_test.sh. Headless game
# instances meet through a real lobby server and put the dig through every
# mishap we could think of. The roles run in this order:
#   host, guest, late   — play together: hits, drops, choices, revive, lift, late join
#   guest → guest2      — the guest "refreshes" and comes back with their build
#   host  → host2       — the host crashes, hosting moves to guest2, the host returns
#   (everyone leaves)
#   host3               — rejoins the empty lobby and resumes from the server checkpoint
#   (server restarts)
#   host4               — resumes from its own local checkpoint, then ends the dig

var game: Node3D
var role = "host"
var lobby_name = "NETTEST"
var step = 0
var clock = 0.0
var total = 0.0
var waiting_for = ""
var marker = 0

func _ready() -> void:
	name = "NetDriver"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lobby-name="): lobby_name = arg.substr(13)
	game.smoke_test = true
	game.net.player_name = role.trim_suffix("2").trim_suffix("3").trim_suffix("4").capitalize()
	print("NET_ROLE %s server=%s id=%s" % [role, game.net.server_url, game.net.player_id])
	game.net.refresh_list()

func fail(reason: String) -> void:
	print("NET_FAIL %s step %d: %s" % [role, step, reason])
	get_tree().quit(1)

func finish() -> void:
	print("NET_PASS %s" % role)
	get_tree().quit(0)

func fingerprint() -> String:
	var health = 0.0
	for e in game.enemies:
		if is_instance_valid(e): health += e.max_health
	return "d=%d rooms=%d exit=%d enemies=%d health=%d interact=%d" % [game.depth, game.rooms.size(), game.exit_room, game.enemies.size(), int(health), game.interactables.size()]

func state_line() -> String:
	return "run=%s depth=%d alive=%d" % [game.run_id, game.depth, alive_count()]

func alive_count() -> int:
	var n = 0
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead: n += 1
	return n

func first_alive() -> DiverEnemy:
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead: return e
	return null

# Advance when the condition holds; fail if it takes too long.
func wait(condition: bool, label: String, timeout: float = 25.0) -> bool:
	if condition:
		step += 1
		clock = 0
		return true
	waiting_for = label
	if clock > timeout: fail("timed out waiting for " + label)
	return false

func proxy(slot: int) -> DiverPlayer:
	var p = game.remote_players.get(slot)
	return p if is_instance_valid(p) and p.net_seen else null

func lift() -> Vector3:
	return game.interactables[1].node.position

func _process(dt: float) -> void:
	clock += dt
	total += dt
	if total > 170: fail("overall timeout (%s)" % waiting_for)
	# Keep test diggers safe from robots unless a step downs one on purpose.
	if is_instance_valid(game.player) and game.in_run() and not game.player.downed and not (role == "guest" and step == 6): game.player.invincible = 999
	call(role + "_step")

func host_step() -> void:
	match step:
		0:
			if wait(game.net.connected(), "server connection"): game.net.create_lobby(lobby_name, true)
		1: wait(game.mode == "lobby" and game.net.is_host(), "lobby creation")
		2:
			if wait(game.net.members().size() >= 2 and game.peers.has(2), "guest in lobby"):
				game.host_start_run()
				print("FINGERPRINT host " + fingerprint())
		3:
			var p = proxy(2)
			if wait(p != null and p.global_position.distance_to(Vector3(4, 0.12, 2)) < 0.8, "guest movement replicated"):
				print("CHECK host sees guest at %s" % p.global_position)
		4:
			var e = game.enemies[0]
			if wait(is_instance_valid(e) and e.health < e.max_health, "guest hit applied on host"):
				print("CHECK host applied guest hit: %.1f / %.1f" % [e.health, e.max_health])
				e.take_damage(1000000, false)
		5:
			game.rooms[0].cleared = true
			game.perform_interact(game.interactables[0], game.player)
			if game.mode != "choice": fail("host should get a cache choice")
			if not game.world_running(): fail("online choices must not pause the world")
			game.choose(0)
			step += 1
		6:
			var p = proxy(2)
			if wait(p != null and not p.items.is_empty(), "guest part mirrored to host"):
				print("CHECK guest parts mirrored: %s" % p.items)
		7:
			var p = proxy(2)
			if wait(p != null and p.downed, "guest downed"): print("CHECK host sees guest down")
		8:
			var p = proxy(2)
			game.player.position = p.global_position + Vector3(0.9, 0, 0)
			if wait(not p.downed, "guest revived by host"):
				print("CHECK guest revived")
				game.guardian_dead = true
		9:
			game.player.position = lift() + Vector3(-1.5, 0.12, 1.5)
			var p = proxy(2)
			if wait(p != null and p.global_position.distance_to(lift()) < 7, "guest at lift"):
				game.perform_interact(game.interactables[1], game.player)
				if game.depth != 2: fail("lift should descend once everyone is aboard")
				if not game.milestone_owed_or_taken(1): fail("host should be offered a guardian milestone")
				print("CHECK host has a personal guardian milestone")
				print("FINGERPRINT host " + fingerprint())
		10:
			game.enemies[2].take_damage(1000000, false)
			game.interactables[2].used = true
			game.use_interactable(game.interactables[2])
			step += 1
		11:
			if wait(proxy(3) != null, "late joiner state", 40): print("CHECK host sees late joiner, alive=%d" % alive_count())
		12:
			if wait(not game.remote_players.has(2), "guest refresh (dropout)", 40): print("CHECK host saw guest drop out; dig continues in mode %s" % game.mode)
		13:
			var p = proxy(2)
			if wait(p != null and not p.items.is_empty(), "guest back with their parts", 60):
				print("CHECK guest returned with parts %s" % p.items)
		14:
			if wait(clock > 1.0, "settle"):
				# A part only the host has, to prove the host gets their own build back.
				game.player.add_item("clover")
		15:
			if wait(clock > 0.6, "part shared"):
				game.save_checkpoint()
				print("CHECK host crashing now, parts=%s" % game.player.items)
				finish()

func guest_step() -> void:
	match step:
		0:
			var found = ""
			for info in game.net.public_lobbies:
				if str(info.name) == lobby_name: found = str(info.code)
			if wait(found != "", "public lobby listed"): game.net.join_lobby(found)
		1: wait(game.mode == "lobby" and game.net.is_guest(), "joined lobby")
		2:
			if wait(game.mode == "play", "run start"): print("FINGERPRINT guest " + fingerprint())
		3:
			game.player.position = Vector3(4, 0.12, 2)
			if wait(proxy(1) != null, "host state on guest"):
				game.damage_enemy(game.enemies[0], 5, game.player)
				print("CHECK guest reported hit")
		4:
			game.player.position = Vector3(4, 0.12, 2)
			if wait(game.enemy_by_id(0) == null and not game.pickups.is_empty(), "host kill and drops replicated"):
				print("CHECK guest saw kill, pickups=%d" % game.pickups.size())
		5:
			# The host's cache leaves the guest a waiting pick instead of opening it.
			if wait(not game.pending_choices.is_empty(), "cache choice waiting for guest"):
				if game.mode != "play": fail("a teammate's cache should not open the choice screen")
				game.game_action("parts")
				if game.mode != "choice" or game.choice_kind != "relic": fail("parts button should open the waiting choice")
				game.choose(0)
				if game.player.items.is_empty(): fail("choice should fit a part")
		6:
			if wait(clock > 0.6, "part sync"):
				game.player.invincible = 0
				game.player.hurt(99999)
				if not game.player.downed: fail("lethal damage should down an online digger")
		7:
			if wait(not game.player.downed and game.player.hp > 0, "revive"): print("CHECK guest revived hp=%d" % int(game.player.hp))
		8:
			if game.guardian_dead: game.player.position = lift() + Vector3(1.5, 0.12, 1.5)
			if wait(game.depth == 2, "descent", 30):
				print("FINGERPRINT guest " + fingerprint())
				# Each digger earns their own guardian milestone (shown now or waiting).
				if not game.milestone_owed_or_taken(1): fail("guest should be offered a guardian milestone")
				print("CHECK guest has a personal guardian milestone")
		9:
			if wait(proxy(3) != null, "late joiner seen", 40):
				game.save_checkpoint()
				print("CHECK guest refreshing now with parts %s level %d" % [game.player.items, game.player.level])
				finish()

func late_step() -> void:
	match step:
		0:
			var found = ""
			for info in game.net.public_lobbies:
				if str(info.name) == lobby_name and str(info.state) == "run" and int(info.depth) == 2: found = str(info.code)
			if wait(found != "", "lobby in progress at B2", 60): game.net.join_lobby(found)
		1:
			if wait(game.mode == "play" and game.depth == 2, "late-join sync"):
				print("FINGERPRINT late " + fingerprint())
				if not game.interactables[2].used: fail("used salvage should sync to late joiners")
				game.player.add_item("echo")
		2:
			# Simulate a Wi-Fi blip: the socket dies but the game keeps running.
			if wait(clock > 0.8, "part shared before the blip"):
				game.net.socket.close()
		3:
			if wait(game.net.reconnecting() and not game.world_running(), "dig frozen while reconnecting", 10): print("CHECK late lost its connection; dig frozen")
		4:
			if wait(game.net.connected() and game.net.active() and game.world_running() and proxy(1) != null, "automatic reconnect", 30):
				if not game.player.items.has("echo") or game.depth != 2: fail("reconnecting must keep the live build and floor")
				print("CHECK late reconnected by itself with parts %s" % game.player.items)
		5:
			if wait(game.net.host_slot == 2 and game.net.connected(), "hosting moved to the returned guest", 90):
				marker = alive_count()
				print("CHECK late sees new host slot %d" % game.net.host_slot)
		6:
			if wait(alive_count() < marker, "new host simulating robots"): print("CHECK late saw the new host defeat a robot")
		7:
			var p = proxy(1)
			if wait(p != null and p.items.has("clover"), "old host back with parts", 60):
				print("CHECK late sees the old host back with parts %s" % p.items)
		8:
			if wait(clock > 1.0, "settle"): finish()

func guest2_step() -> void:
	match step:
		0:
			if wait(game.net.player_id != "", "identity"):
				game.continue_saved_dig()
				if game.net.pending.is_empty() and not game.net.connected(): fail("rejoin should start connecting")
		1:
			if wait(game.mode in ["play", "choice"] and game.depth == 2 and not game.player.items.is_empty(), "build restored after refresh"):
				print("CHECK guest2 restored parts %s level %d" % [game.player.items, game.player.level])
		2:
			if wait(game.net.is_host(), "hosting handed over after the host crash", 60):
				print("CHECK guest2 is now hosting")
		3:
			var e = first_alive()
			if e: e.take_damage(1000000, false)
			step += 1
		4:
			var p = proxy(1)
			if wait(p != null and p.items.has("clover"), "old host back with parts", 60): print("CHECK guest2 sees old host back")
		5:
			if wait(clock > 1.5, "settle"):
				game.save_checkpoint()
				print("STATE guest2 " + state_line())
				finish()

func host2_step() -> void:
	match step:
		0:
			if wait(game.net.player_id != "", "identity"): game.continue_saved_dig()
		1:
			if wait(game.mode in ["play", "choice"] and game.depth == 2 and game.player.items.has("clover") and not game.net.is_host(), "host rejoined as a guest with their own parts", 40):
				print("CHECK host2 restored parts %s" % game.player.items)
		2:
			if wait(clock > 3.0, "settle"): finish()

func host3_step() -> void:
	match step:
		0:
			if wait(game.net.player_id != "", "identity"): game.continue_saved_dig()
		1:
			if wait(game.mode in ["play", "choice"] and game.net.is_host() and game.depth == 2 and game.player.items.has("clover"), "empty lobby taken over from the server checkpoint", 40):
				print("STATE host3 " + state_line())
				print("CHECK host3 resumed from the server, parts %s" % game.player.items)
				game.save_checkpoint()
		2:
			if wait(clock > 1.0, "settle"): finish()

func host4_step() -> void:
	match step:
		0:
			if wait(game.net.player_id != "", "identity"): game.continue_saved_dig()
		1:
			if wait(game.mode in ["play", "choice"] and game.net.is_host() and game.depth == 2 and game.player.items.has("clover"), "dig recreated from the local checkpoint after a server restart", 40):
				print("STATE host4 " + state_line())
				print("CHECK host4 recreated lobby %s from its own save" % game.net.lobby_code)
				game.end_run_all(false)
		2:
			if wait(game.mode == "end", "end screen"):
				if FileAccess.file_exists(game.checkpoint_path): fail("ending the dig should clear the checkpoint")
				finish()
