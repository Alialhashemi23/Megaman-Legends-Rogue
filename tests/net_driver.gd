extends Node

# Scripted online co-op session used by tests/net_test.sh. Three headless game
# instances (host, guest and a late joiner) meet through a real lobby server and
# verify the shared dig: generation, robot hits, pickups, cache choices,
# downed/revive, gathering at the lift, late-join sync and the shared ending.

var game: Node3D
var role = "host"
var lobby_name = "NETTEST"
var step = 0
var clock = 0.0
var total = 0.0
var waiting_for = ""

func _ready() -> void:
	name = "NetDriver"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lobby-name="): lobby_name = arg.substr(13)
	game.smoke_test = true
	game.net.player_name = role.capitalize()
	print("NET_ROLE %s server=%s" % [role, game.net.server_url])
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

func alive_count() -> int:
	var n = 0
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead: n += 1
	return n

# Advance when the condition holds; fail if it takes too long.
func wait(condition: bool, label: String, timeout: float = 20.0) -> bool:
	if condition:
		step += 1
		clock = 0
		return true
	waiting_for = label
	if clock > timeout: fail("timed out waiting for " + label)
	return false

func guest_proxy(slot: int) -> DiverPlayer:
	var p = game.remote_players.get(slot)
	return p if is_instance_valid(p) and p.net_seen else null

func lift() -> Vector3:
	return game.interactables[1].node.position

func _process(dt: float) -> void:
	clock += dt
	total += dt
	if total > 150: fail("overall timeout (%s)" % waiting_for)
	# Keep test diggers safe from robots unless a step downs one on purpose.
	if is_instance_valid(game.player) and game.in_run() and not game.player.downed and step != 7: game.player.invincible = 999
	match role:
		"host": host_step()
		"guest": guest_step()
		"late": late_step()

func host_step() -> void:
	match step:
		0:
			if wait(game.net.status == "online", "server connection"): game.net.create_lobby(lobby_name, true)
		1: wait(game.mode == "lobby" and game.net.is_host(), "lobby creation")
		2:
			if wait(game.net.members().size() >= 2 and game.peers.has(2), "guest in lobby"):
				game.host_start_run()
				print("FINGERPRINT host " + fingerprint())
		3:
			var proxy = guest_proxy(2)
			if wait(proxy != null and proxy.global_position.distance_to(Vector3(4, 0.12, 2)) < 0.8, "guest movement replicated"):
				print("CHECK host sees guest at %s" % proxy.global_position)
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
			var proxy = guest_proxy(2)
			if wait(proxy != null and not proxy.items.is_empty() and game.peers[2].items.size() > 0, "guest part mirrored to host"):
				print("CHECK guest parts mirrored: %s" % proxy.items)
		7:
			var proxy = guest_proxy(2)
			if wait(proxy != null and proxy.downed, "guest downed"):
				print("CHECK host sees guest down")
		8:
			var proxy = guest_proxy(2)
			game.player.position = proxy.global_position + Vector3(0.9, 0, 0)
			if wait(not proxy.downed, "guest revived by host"):
				print("CHECK guest revived")
				game.guardian_dead = true
		9:
			game.player.position = lift() + Vector3(-1.5, 0.12, 1.5)
			var proxy = guest_proxy(2)
			if wait(proxy != null and proxy.global_position.distance_to(lift()) < 7, "guest at lift"):
				game.perform_interact(game.interactables[1], game.player)
				if game.depth != 2: fail("lift should descend once everyone is aboard")
				print("FINGERPRINT host " + fingerprint())
				print("CHECK host alive=%d" % alive_count())
		10:
			game.enemies[2].take_damage(1000000, false)
			game.interactables[2].used = true
			game.use_interactable(game.interactables[2])
			step += 1
		11:
			var late = guest_proxy(3)
			if wait(late != null, "late joiner state", 40): print("CHECK host sees late joiner, alive=%d" % alive_count())
		12:
			if wait(clock > 1.0, "settle"):
				game.end_run_all(false)
				print("CHECK host ended dig")
		13:
			if wait(clock > 1.0 and game.mode == "end", "end screen"): finish()

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
			var e = game.enemies[0]
			if wait(guest_proxy(1) != null, "host state on guest"):
				game.damage_enemy(e, 5, game.player)
				print("CHECK guest reported hit")
		4:
			game.player.position = Vector3(4, 0.12, 2)
			if wait(game.enemy_by_id(0) == null and not game.pickups.is_empty(), "host kill and drops replicated"):
				print("CHECK guest saw kill, pickups=%d" % game.pickups.size())
		5:
			if wait(game.mode == "choice" and game.choice_kind == "relic", "cache choice offered to guest"):
				game.choose(0)
				if game.player.items.is_empty(): fail("choice should fit a part")
		6:
			# Make sure the part reached the host before going down.
			if wait(clock > 0.6, "part sync"):
				game.player.invincible = 0
				game.player.hurt(99999)
				if not game.player.downed: fail("lethal damage should down an online digger")
		7:
			if wait(not game.player.downed and game.player.hp > 0, "revive"):
				print("CHECK guest revived hp=%d" % int(game.player.hp))
		8:
			if game.guardian_dead: game.player.position = game.interactables[1].node.position + Vector3(1.5, 0.12, 1.5)
			if wait(game.depth == 2, "descent", 30):
				print("FINGERPRINT guest " + fingerprint())
		9:
			if wait(game.mode == "end", "shared ending", 60): finish()

func late_step() -> void:
	match step:
		0:
			var found = ""
			for info in game.net.public_lobbies:
				if str(info.name) == lobby_name and str(info.state) == "run" and int(info.depth) == 2: found = str(info.code)
			if wait(found != "", "lobby in progress at B2", 60):
				# Give the host a moment to change the floor before syncing.
				game.net.join_lobby(found)
		1:
			if wait(game.mode == "play" and game.depth == 2, "late-join sync"):
				print("FINGERPRINT late " + fingerprint())
				print("CHECK late alive=%d used=%s" % [alive_count(), game.interactables[2].used])
				if not game.interactables[2].used: fail("used salvage should sync to late joiners")
		2:
			if wait(game.mode == "end", "shared ending", 60): finish()
