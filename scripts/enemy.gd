extends CharacterBody3D
class_name DiverEnemy

var game: Node3D
var kind = 0
var room_id = 0
var health = 30.0
var max_health = 30.0
var dead = false
var active = false
var slow = 0.0
# Needle Storm: every sixth needle exposes a machine to extra damage.
var exposed = 0.0
var needle_hits = 0
var burn_time = 0.0
var burn_tick = 0.0
var burn_damage = 0.0
# Ember Engine (BAL-02): a share of each hit keeps burning after it lands.
var burn_pool = 0.0
# Guardians vent an exposed core for a moment after their big attacks (BOSS-01).
var vent_time = 0.0
var core: Node3D
# Mender: repair pulses and the cosmetic beam on guests.
var heal_clock = 0.0
var attack = 1.0
var flash = 0.0
var phase = 0.0
var art: Dictionary
var health_bar: MeshInstance3D
var ai_time = 0.0
var strafe_sign = 1.0
var state = "approach"
var state_time = 0.0
var windup_duration = 0.5
var planned = ""
var aim_point = Vector3.ZERO
var aim_direction = Vector3.FORWARD
var marker: Node3D
var strike_points: Array[Vector3] = []
var attack_cycle = 0
var charge_hit = false
var knockback = Vector3.ZERO
var path = PackedVector3Array()
var path_index = 0
var route_cooldown = 0.0
var hit_overlay: StandardMaterial3D
var meshes: Array[MeshInstance3D] = []
var overdrive_triggered = false
var aim_locked = false
# A guardian shrugs off damage for a moment as it enters overdrive.
var shield = 0.0
var guard_shown = -100000
# Online: the host simulates robots; guests show proxies that follow snapshots.
var net_id = -1
var net_pos = Vector3.ZERO
var net_rot = 0.0
var net_seen = false
var target: Node3D
var last_source: Node3D
var my_last_hit = -100000
const GUARDIAN_DEPTH = [1.4, 3.5, 7.5]
const VENT_SECONDS = 2.5
const CORE_OFFSET = Vector3(0, 3.1, 0.85)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	# Kinds: 0 melee, 1 sentry, 2 charger, 3 guardian, 4 grenadier, 5 mender.
	max_health = [55.0, 44.0, 110.0, 1900.0, 50.0, 36.0][kind]
	# Guardians grow faster with depth than robots do (BAL-02), so deep fights last.
	max_health *= GUARDIAN_DEPTH[game.depth - 1] if kind == 3 else 1 + (game.depth - 1) * 0.65
	# Bigger parties face sturdier machines (guardians scale the most).
	max_health *= 1.0 + (game.party_size - 1) * (0.80 if kind == 3 else 0.35)
	health = max_health
	var col = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 1.0 if kind == 3 else 0.45
	shape.height = 3.8 if kind == 3 else 1.6
	col.position.y = shape.height / 2
	col.shape = shape
	add_child(col)
	art = DiverArt.robot(self, kind, game.depth)
	for node in art.root.find_children("*", "MeshInstance3D", true, false): meshes.append(node)
	hit_overlay = DiverArt.hit_flash()
	phase = game.rng.randf() * TAU
	attack = game.rng.randf_range(0.7, 2) * 0.5
	strafe_sign = -1 if game.rng.randf() < 0.5 else 1
	health_bar = DiverArt.box(self, Vector3(0, 4.7 if kind == 3 else 2.2, 0), Vector3(1.1, 0.07, 0.08), Color("ed8d68"), false, 0.4)
	health_bar.visible = false
	if kind == 3: core = make_core()
	add_to_group("enemies")

# Difficulty: every attack keeps its warning, but deeper floors hit harder
# (`base + per_floor` for each descent) and wind up and recover sooner.
func hit(base: float, per_floor: float) -> float:
	return base + per_floor * game.depth

func pace() -> float:
	var value = 0.75 - 0.075 * (game.depth - 1)
	return value * 0.85 if kind == 3 and overdrive_triggered else value

# Sentries and guardians lock their aim just before firing, leading a moving digger.
func lock_aim() -> void:
	aim_locked = true
	var who: DiverPlayer = null
	var best = 6.0
	for p in game.all_players():
		var d = p.global_position.distance_to(aim_point - Vector3.UP)
		if not p.downed and d < best:
			best = d
			who = p
	if who == null: return
	var from = global_position + Vector3.UP * (2.6 if kind == 3 else 1.5)
	var moving: Vector3 = who.velocity if who.is_local else who.net_vel
	moving.y = 0
	var flight = from.distance_to(who.global_position) / (17.0 + game.depth * 2)
	aim_point = who.global_position + Vector3.UP + moving * flight * (0.55 + 0.15 * game.depth)
	aim_direction = aim_point - global_position - Vector3.UP
	aim_direction.y = 0
	aim_direction = aim_direction.normalized()
	if is_instance_valid(marker):
		for child in marker.get_children(): child.queue_free()
		var origin = global_position
		origin.y += 0.075
		warning_line(origin, Vector3(aim_point.x, game.floor_height(aim_point) + 0.075, aim_point.z), 0.14, Color("fa775e"))
		DiverArt.ring(marker, origin, 0.7 if kind == 1 else 1.8, Color("fa775e"), 0.12)

func _physics_process(dt: float) -> void:
	if dead or not game.world_running() or not is_instance_valid(game.player): return
	if game.net.is_guest():
		proxy_process(dt)
		return
	target = game.target_for(self)
	if target == null:
		velocity = Vector3(0, velocity.y - dt * 25, 0)
		move_and_slide()
		return
	var distance = global_position.distance_to(target.global_position)
	active = active or game.room_has_player(room_id, global_position) or health < max_health
	if not active: return
	slow -= dt
	exposed -= dt
	vent_time -= dt
	update_core()
	flash -= dt
	shield -= dt
	attack -= dt
	route_cooldown -= dt
	ai_time += dt
	phase += dt * 7
	if burn_time > 0 or burn_pool > 1.0:
		burn_time -= dt
		burn_tick -= dt
		if burn_tick <= 0:
			burn_tick = 0.45
			var from_pool = burn_pool * 0.15
			burn_pool -= from_pool
			take_damage(maxf(burn_damage if burn_time > 0 else 0.0, from_pool), false)
			if dead: return
	for mesh in meshes: mesh.material_overlay = hit_overlay if flash > 0 else null
	art.root.scale = Vector3.ONE * 2.35 if kind == 3 else Vector3(1.15, 0.9, 1.15) if kind == 4 else Vector3.ONE
	health_bar.visible = health < max_health
	health_bar.scale.x = maxf(0.01, health / max_health)
	var direction = target.position - position
	direction.y = 0
	direction = direction.normalized()
	var movement = Vector3.ZERO
	var speed = [4.2, 2.9, 2.6, 2.8, 2.2, 3.6][kind] * (1.0 + 0.08 * (game.depth - 1)) * (0.40 if slow > 0 else 1)
	if kind == 3 and health < max_health * 0.5: speed *= 1.2
	if state == "windup":
		state_time -= dt
		rotation.y = lerp_angle(rotation.y, atan2(-aim_direction.x, -aim_direction.z), minf(1, dt * 12))
		var progress = 1 - maxf(0, state_time) / windup_duration
		art.root.rotation.x = -0.16 * progress
		art.root.position.y = -0.10 * progress
		if not aim_locked and state_time <= 0.22 and planned in ["shot", "fan"]: lock_aim()
		if is_instance_valid(marker): marker.visible = state_time > 0.20 or int(state_time * 35) % 2 == 0
		if state_time <= 0: resolve_attack()
	elif state == "charge":
		state_time -= dt
		movement = aim_direction
		speed = 17.0
		check_charge_contact()
		if state_time <= 0 or is_on_wall(): recover(0.8)
	elif state == "recover":
		state_time -= dt
		art.root.rotation.x = lerpf(art.root.rotation.x, 0, dt * 9)
		art.root.position.y = lerpf(art.root.position.y, 0, dt * 9)
		if state_time <= 0: state = "approach"
	else:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1, dt * 5))
		var sight = sees(target)
		movement = chase_direction(dt, direction, sight)
		if kind == 1 and sight:
			movement = direction * (1 if distance > 10 else -0.45 if distance < 6 else 0) + direction.cross(Vector3.UP) * 0.5 * strafe_sign
			if is_on_wall(): strafe_sign *= -1
		if kind == 4 and sight:
			# Grenadiers keep their distance and lob shells over cover.
			movement = direction * (1 if distance > 14 else -0.6 if distance < 8 else 0) + direction.cross(Vector3.UP) * 0.3 * strafe_sign
			if is_on_wall(): strafe_sign *= -1
		if kind == 5: movement = mender_move(direction, distance)
		if kind in [1, 5]: art.root.position.y = sin(phase * 0.5) * 0.12
		if kind in [0, 2, 3] and distance < (2.8 if kind == 3 else 1.5): movement = Vector3.ZERO
		if attack <= 0 and sight:
			if kind == 1 and distance < 22: begin_attack("shot", 0.65)
			elif kind == 2 and distance < 10: begin_attack("charge", 0.70)
			elif kind == 0 and distance < 2.0: begin_attack("melee", 0.46)
			elif kind == 4 and distance < 20: begin_attack("lob", 1.2)
			elif kind == 3 and distance < 28:
				attack_cycle += 1
				if distance < 4.2: begin_attack("slam", 0.95)
				elif game.depth == 2 and attack_cycle % 2 == 1: begin_attack("bombard", 1.05)
				elif game.depth == 3 and attack_cycle % 2 == 1: begin_attack("cross", 1.10)
				else: begin_attack("fan", 0.8)
			else: attack = 0.15
		if kind == 5: mender_repair(dt)
		if state == "windup": movement = Vector3.ZERO
	knockback = knockback.move_toward(Vector3.ZERO, dt * 18)
	velocity.x = movement.x * speed + knockback.x
	velocity.z = movement.z * speed + knockback.z
	velocity.y -= dt * 25
	move_and_slide()
	for i in art.limbs.size(): art.limbs[i].rotation.x = sin(phase + i * PI) * movement.length() * 0.45

# Damage checks always use this machine's own digger; the AI uses sees(target).
func has_sight() -> bool:
	return sees(game.player)

func sees(who: Node3D) -> bool:
	return unobstructed(global_position + Vector3.UP * 1.2, who.global_position + Vector3.UP)

func check_charge_contact() -> void:
	if not charge_hit and global_position.distance_to(game.player.global_position) < 1.7 and has_sight():
		game.player.hurt(hit(22, 6))
		charge_hit = true

func unobstructed(from: Vector3, to: Vector3) -> bool:
	var ray = PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func chase_direction(_dt: float, direction: Vector3, sight: bool) -> Vector3:
	# A digger up on a terrace is in sight but out of reach: take the ramp.
	if sight and not is_on_wall() and absf(target.position.y - position.y) < 0.8 and game.floor_height(target.position) == game.floor_height(position): return direction
	if route_cooldown <= 0 or path.is_empty():
		route_cooldown = 0.65 + float(get_instance_id() % 5) * 0.06
		path = game.navigation.route(position, target.position)
		path_index = 1 if path.size() > 1 else 0
	if not path.is_empty():
		while path_index < path.size() - 1 and Vector2(position.x - path[path_index].x, position.z - path[path_index].z).length() < 0.55: path_index += 1
		var delta = path[path_index] - position
		delta.y = 0
		return delta.normalized()
	return (direction + get_wall_normal()).normalized() if is_on_wall() else direction

func begin_attack(type: String, duration: float) -> void:
	var aim = (target if is_instance_valid(target) else game.player).global_position + Vector3.UP
	duration *= pace() * chill()
	game.net.broadcast([DiverNet.M_ATTACK, game.depth, net_id, type, duration, aim])
	show_attack(type, duration, aim)

func show_attack(type: String, duration: float, point: Vector3) -> void:
	clear_marker()
	planned = type
	aim_locked = false
	state = "windup"
	windup_duration = duration
	state_time = duration
	aim_point = point
	aim_direction = (aim_point - global_position - Vector3.UP).normalized()
	aim_direction.y = 0
	aim_direction = aim_direction.normalized()
	marker = Node3D.new()
	game.world.add_child(marker)
	var origin = global_position
	# Warnings lie on whatever floor the robot or its target stands on.
	origin.y += 0.075
	var target_floor = game.floor_height(aim_point) + 0.075
	var amber = Color("ffb257")
	var danger = Color("fa775e")
	strike_points.clear()
	match type:
		"melee":
			var arc = DiverArt.ring(marker, origin, 2.5, amber, 0.15, 2.4)
			arc.rotation.y = atan2(-aim_direction.x, -aim_direction.z)
		"charge":
			warning_line(origin, origin + aim_direction * 9, 3.0, amber)
		"shot", "fan":
			warning_line(origin, Vector3(aim_point.x, target_floor, aim_point.z), 0.08, amber)
			DiverArt.ring(marker, origin, 0.7 if kind == 1 else 1.8, amber, 0.12)
		"slam":
			DiverArt.ring(marker, origin, 4.7, danger, 0.18)
			DiverArt.ring(marker, origin + Vector3.UP * 0.015, 2.4, amber, 0.08)
		"bombard":
			var at = Vector3(aim_point.x, target_floor, aim_point.z)
			for offset in [Vector3.ZERO, Vector3(3.8, 0, 1.8), Vector3(-3.8, 0, -1.8)]:
				strike_points.append(at + offset)
				DiverArt.ring(marker, at + offset, 2.2, danger, 0.15)
		"cross":
			for direction in [aim_direction, aim_direction.rotated(Vector3.UP, PI / 2)]:
				warning_line(origin - direction * 11, origin + direction * 11, 1.5, danger)
		"lob":
			var at = Vector3(aim_point.x, target_floor, aim_point.z)
			var side = aim_direction.cross(Vector3.UP)
			for offset in [Vector3.ZERO, side * 2.4 + aim_direction * 1.2, -side * 2.4 + aim_direction * 1.2]:
				strike_points.append(at + offset)
				DiverArt.ring(marker, at + offset, 1.8, danger, 0.15)
	game.sound.play("warning", 0.8 if kind == 3 else 1.3)

func warning_line(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var line = DiverArt.box(marker, (from + to) * 0.5, Vector3(width, 0.025, maxf(0.1, from.distance_to(to))), color, false, 0.4)
	line.look_at(to + Vector3(0, 0.001, 0))

func resolve_attack() -> void:
	if game.net.is_host(): game.net.broadcast([DiverNet.M_RESOLVE, game.depth, net_id, global_position])
	clear_marker()
	match planned:
		"melee":
			var delta = game.player.global_position - global_position
			delta.y = 0
			if delta.length() < 2.5 and delta.normalized().dot(aim_direction) > 0.4 and has_sight(): game.player.hurt(hit(15, 5))
			game.impact_ring(global_position + Vector3.UP * 0.06, 2.3, Color("ffc779"), 0.16)
			recover(0.6)
		"shot": fire_at_point(1); recover(0.95)
		"fan":
			fire_at_point(5 + (2 if game.depth == 3 else 0)); recover(0.9 if health > max_health * 0.5 else 0.55)
			# The first guardian has no big area attack, so every other fan vents too.
			if game.depth == 1 and attack_cycle % 2 == 0: open_vent()
		"charge":
			state = "charge"
			state_time = 0.52
			charge_hit = false
			game.sound.play("dash", 0.75, global_position)
		"slam":
			blast(global_position, 4.7, hit(26, 7))
			recover(1.0)
			open_vent()
		"bombard":
			for point in strike_points: blast(point, 2.2, hit(20, 7))
			recover(0.85)
			open_vent()
		"lob":
			for point in strike_points: blast(point, 1.8, hit(14, 5))
			recover(1.1)
		"cross":
			var origin = global_position
			origin.y += 0.08
			var delta = game.player.global_position - origin
			delta.y = 0
			for direction in [aim_direction, aim_direction.rotated(Vector3.UP, PI / 2)]:
				var from = origin - direction * 11
				var to = origin + direction * 11
				game.beam_flash(from, to, 1.5)
				if absf(delta.dot(direction.cross(Vector3.UP))) < 1.05 and absf(delta.dot(direction)) < 11 and has_sight(): game.player.hurt(hit(26, 7))
			game.sound.play("slam", 1.0, global_position)
			recover(1.1)
			open_vent()
	attack = 0.15

func blast(pos: Vector3, radius: float, amount: float) -> void:
	game.impact_ring(Vector3(pos.x, pos.y + 0.015, pos.z), radius, Color("ff9568"), 0.35)
	game.burst(pos + Vector3.UP * 0.6, Color("ffca68"), 15)
	game.sound.play("slam", 1.0, pos)
	var delta = game.player.global_position - pos
	delta.y = 0
	if delta.length() < radius and absf(game.player.position.y - pos.y) < 0.70 and unobstructed(pos + Vector3.UP * 0.8, game.player.global_position + Vector3.UP): game.player.hurt(amount)
	if delta.length() < 12: game.player.add_trauma(0.20)
	game.damage_pillars(pos, radius, amount)

func fire_at_point(number: int) -> void:
	var origin = global_position + Vector3.UP * (2.6 if kind == 3 else 1.5)
	var dir = (aim_point - origin).normalized()
	for i in number:
		game.spawn_bolt(origin + dir * (1.2 if kind == 3 else 0.7), dir.rotated(Vector3.UP, (i - (number - 1) * 0.5) * 0.14), hit(16, 5) if kind == 3 else hit(11, 4), true, false, 0)
	game.muzzle_flash(origin + dir * 0.7, Color("ff9e6c"), 0.32)
	game.sound.play("enemy", 0.7 if kind == 3 else 1, global_position)

func recover(duration: float) -> void:
	state = "recover"
	state_time = duration * pace() * chill() * (0.8 if kind == 3 and health < max_health * 0.5 else 1.0)
	clear_marker()

func clear_marker() -> void:
	if is_instance_valid(marker): marker.queue_free()
	marker = null

func take_damage(amount: float, effects: bool = true, source: Node3D = null) -> void:
	if dead: return
	if shield > 0:
		flash = 0.1
		if Time.get_ticks_msec() - guard_shown > 350:
			guard_shown = Time.get_ticks_msec()
			game.float_text(global_position + Vector3.UP * 3.5, "GUARD", Color("9fd8ff"))
		return
	# Part effects come from whoever fired the shot, local or remote.
	if not is_instance_valid(source): source = game.player
	var local_shot = source == game.player
	active = true
	flash = 0.1
	if effects:
		last_source = source
		if local_shot: game.hit_confirm = 0.14
		if kind != 3:
			knockback = (global_position - source.global_position).normalized() * 2.5
	# Specializations are judged here, on the host, for local and remote shooters.
	var key = source.specialization()
	if effects and key == "focus":
		if source.focus_target == self: source.focus_stacks = mini(5, source.focus_stacks + 1)
		else:
			source.focus_target = self
			source.focus_stacks = 0
		amount *= 1.0 + 0.08 * source.focus_stacks
	# Refractor Crystal: exposed machines take even more from its owner.
	if exposed > 0: amount *= 1.2 * (1.0 + 0.4 * source.count("refractor"))
	# Winter Flywheel slows soften machines; Shatter Core hits slowed ones harder.
	if slow > 0: amount *= 1.10 * (1.0 + 0.15 * source.count("shatter"))
	if effects and source.has_milestone("salvo") and health > max_health * 0.75: amount *= 1.35
	if effects and key == "storm":
		needle_hits += 1
		if needle_hits % 6 == 0:
			exposed = 3.0
			game.float_text(global_position + Vector3.UP * (4.0 if kind == 3 else 2.6), "EXPOSED", Color("ffdc68"))
	var crit = false
	if effects and game.rng.randf() < minf(0.6, source.count("prism") * 0.10 + (0.15 if source.has_milestone("fortune") else 0.0)):
		amount *= 3 if source.has_milestone("fortune") else 2
		crit = true
	health -= amount
	if kind == 3 and not overdrive_triggered and health > 0 and health < max_health * 0.5:
		overdrive_triggered = true
		recover(1.2)
		shield = 1.6
		game.announce("OVERDRIVE / " + game.BOSS_NAMES[game.depth - 1], "The guardian shields itself and calls for help. Watch its attack warnings.")
		game.call_deferred("guardian_adds", self)
		game.sound.play("warning", 0.7)
	game.total_damage += amount
	show_damage(amount, crit, true)
	if game.net.is_host(): game.net.broadcast([DiverNet.M_DAMAGE, game.depth, net_id, amount, crit, source.slot if effects else 0])
	if effects and local_shot: game.player.add_trauma(0.025)
	if effects:
		if source.count("ember") > 0 or source.has_milestone("wildfire"):
			burn_time = 3
			burn_damage = 2.0 * maxi(1, source.count("ember"))
			burn_pool += amount * 0.12 * source.count("ember")
		if (source.count("coil") > 0 or source.has_milestone("arc")) and game.rng.randf() < minf(0.75, 0.18 * source.count("coil") + (0.25 if source.has_milestone("arc") else 0.0)):
			var candidates = game.enemies.duplicate()
			var chains = 0
			for other in candidates:
				if other == self or not is_instance_valid(other) or other.dead: continue
				if other.position.distance_to(position) < 7:
					game.lightning(global_position + Vector3.UP, other.global_position + Vector3.UP)
					other.take_damage(amount * 0.45, false)
					chains += 1
					if chains >= 1 + source.count("coil"): break
			# With nothing else in reach, the arc grounds back into this machine.
			if chains == 0 and not dead:
				game.lightning(global_position + Vector3(0.9, 3.0, 0.4), global_position + Vector3.UP)
				take_damage(amount * 0.30, false)
	if health <= 0: die()

func die() -> void:
	if dead: return
	dead = true
	game.sound.play("guardian_down" if kind == 3 else "destroy", 1.0, global_position)
	clear_marker()
	if not is_instance_valid(last_source) or last_source == game.player:
		game.hit_confirm = 0.25
		game.kill_confirm = 0.25
	collision_layer = 0
	game.kills += 1
	game.burst(global_position + Vector3.UP, DiverArt.TEAL, 12 if kind != 3 else 30)
	game.impact_ring(global_position + Vector3.UP * 0.10, 1.0 if kind != 3 else 3.5, DiverArt.TEAL, 0.25)
	game.net.broadcast([DiverNet.M_DIE, game.depth, net_id])
	var killer = last_source if is_instance_valid(last_source) else game.player
	game.drop_pickup(position + Vector3.UP * 0.5, "xp", 18 if kind == 3 else 5 if kind in [2, 4] else 4 if kind == 5 else 3)
	game.drop_pickup(position + Vector3(0.4, 0.5, 0), "scrap", (30 if kind == 3 else game.rng.randi_range(2, 5)) + (2 if killer.specialization() == "runner" else 0))
	if killer.count("moss") > 0: game.heal_player(killer, 1.5 * killer.count("moss"))
	if killer.has_milestone("scavenger"): game.heal_player(killer, 3.0)
	# Wildfire Core: a burning machine spreads its fire as it falls.
	if burn_time > 0 and killer.has_milestone("wildfire"):
		for other in game.enemies:
			if other != self and is_instance_valid(other) and not other.dead and other.global_position.distance_to(global_position) < 4.0:
				other.burn_time = 3
				other.burn_damage = maxf(other.burn_damage, burn_damage)
				other.burn_pool = maxf(other.burn_pool, burn_pool * 0.5)
				game.burst(other.global_position + Vector3.UP, Color("f99668"), 5)
	# Shatter Core: a slowed machine bursts into a frost ring that hurts its neighbours.
	if slow > 0 and killer.count("shatter") > 0:
		game.frost_burst(position, 2.0 + killer.count("shatter"), 3.0)
		game.impact_ring(position + Vector3.UP * 0.08, 3.0, Color("b2e4ef"), 0.25)
		for other in game.enemies.duplicate():
			if other != self and is_instance_valid(other) and not other.dead and other.global_position.distance_to(global_position) < 3.0:
				other.take_damage(minf(max_health, 400.0) * 0.15 * killer.count("shatter"), false)
	if game.rng.randf() < 0.12: game.drop_pickup(position + Vector3(-0.4, 0.5, 0), "health", 12)
	if kind == 3:
		game.guardian_dead = true
		game.notify("GUARDIAN SILENCED", "The extraction lift is online. Collect the core and head to the beacon.")
		# Each digger gets their own guardian core.
		var diggers = game.all_players()
		for i in diggers.size():
			game.drop_relic(position + Vector3((i - (diggers.size() - 1) * 0.5) * 1.3, 0.8, 1), diggers[i].player_id if diggers.size() > 1 else "")
	elif game.rng.randf() < 0.07 + killer.count("clover") * 0.025 + (0.05 if killer.has_milestone("scavenger") else 0.0):
		game.drop_relic(position + Vector3.UP)
	queue_free()

# Hit numbers, sparks and sound shared by the host and guest views.
func show_damage(amount: float, crit: bool, with_sound: bool) -> void:
	flash = 0.1
	game.float_text(global_position + Vector3.UP * (3.5 if kind == 3 else 1.8), str(int(amount)) + ("!" if crit else ""), DiverArt.GOLD if crit else Color("c3f5ee"))
	game.burst(global_position + Vector3.UP, Color("ffca68"), 4)
	if with_sound: game.sound.play("hit", 1.0, global_position)

func apply_snapshot(pos: Vector3, rot: float, life: float) -> void:
	if not net_seen or pos.distance_to(global_position) > 8: global_position = pos
	net_seen = true
	net_pos = pos
	net_rot = rot
	health = life
	active = true

# Guest-side robot: follow the host, play warnings, and check hits on our digger.
func proxy_process(dt: float) -> void:
	flash -= dt
	phase += dt * 7
	vent_time -= dt
	update_core()
	if kind == 5: mender_repair(dt)
	for mesh in meshes: mesh.material_overlay = hit_overlay if flash > 0 else null
	art.root.scale = Vector3.ONE * 2.35 if kind == 3 else Vector3(1.15, 0.9, 1.15) if kind == 4 else Vector3.ONE
	health_bar.visible = health < max_health
	health_bar.scale.x = maxf(0.01, health / max_health)
	var before = global_position
	if net_seen:
		global_position = global_position.lerp(net_pos, minf(1, dt * 12))
		rotation.y = lerp_angle(rotation.y, net_rot, minf(1, dt * 12))
	var moved = Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(dt, 0.001)
	match state:
		"windup":
			state_time -= dt
			var progress = 1 - maxf(0, state_time) / windup_duration
			art.root.rotation.x = -0.16 * progress
			art.root.position.y = -0.10 * progress
			if not aim_locked and state_time <= 0.22 and planned in ["shot", "fan"]: lock_aim()
			if is_instance_valid(marker): marker.visible = state_time > 0.20 or int(state_time * 35) % 2 == 0
			if state_time < -2.0:
				clear_marker()
				state = "approach"
		"charge":
			state_time -= dt
			check_charge_contact()
			if state_time <= 0: recover(0.8)
		"recover":
			state_time -= dt
			art.root.rotation.x = lerpf(art.root.rotation.x, 0, dt * 9)
			art.root.position.y = lerpf(art.root.position.y, 0, dt * 9)
			if state_time <= 0: state = "approach"
		_:
			if kind in [1, 5]: art.root.position.y = sin(phase * 0.5) * 0.12
	for i in art.limbs.size(): art.limbs[i].rotation.x = sin(phase + i * PI) * clampf(moved / 3.0, 0, 1) * 0.45

func remote_die() -> void:
	if dead: return
	dead = true
	game.sound.play("guardian_down" if kind == 3 else "destroy", 1.0, global_position)
	clear_marker()
	if Time.get_ticks_msec() - my_last_hit < 600:
		game.hit_confirm = 0.25
		game.kill_confirm = 0.25
	collision_layer = 0
	game.burst(global_position + Vector3.UP, DiverArt.TEAL, 12 if kind != 3 else 30)
	game.impact_ring(global_position + Vector3.UP * 0.10, 1.0 if kind != 3 else 3.5, DiverArt.TEAL, 0.25)
	if kind == 3:
		game.guardian_dead = true
		game.notify("GUARDIAN SILENCED", "The extraction lift is online. Each digger has a core waiting. Head to the beacon together.")
	queue_free()

# --- BAL-02 / ENEMY-01 / BOSS-01 helpers ------------------------------------

# Frost-slowed machines wind up and recover more slowly.
func chill() -> float:
	return 1.35 if slow > 0 else 1.0

# A glowing core panel on the guardian's back, shown only while it vents.
func make_core() -> Node3D:
	var node = Node3D.new()
	add_child(node)
	node.position = CORE_OFFSET
	DiverArt.box(node, Vector3.ZERO, Vector3(0.95, 0.75, 0.25), DiverArt.INK)
	DiverArt.orb(node, Vector3(0, 0, 0.1), 0.34, Color("ffdc68"), 1.5)
	node.visible = false
	return node

func update_core() -> void:
	if not is_instance_valid(core): return
	core.visible = vent_time > 0 and (vent_time > 0.6 or int(vent_time * 12) % 2 == 0)

# Runs everywhere the attack resolves (host and guests), so no extra message.
func open_vent() -> void:
	if kind != 3 or dead: return
	vent_time = VENT_SECONDS
	update_core()
	game.float_text(global_position + Vector3.UP * 4.2, "CORE EXPOSED", Color("ffdc68"))

func core_point() -> Vector3:
	return global_position + CORE_OFFSET.rotated(Vector3.UP, rotation.y)

# Menders hang back near the machines they repair and keep away from diggers.
func mender_move(direction: Vector3, distance: float) -> Vector3:
	if distance < 9: return -direction
	var ally = mender_target()
	if ally and ally.global_position.distance_to(global_position) > 4.5:
		var to = ally.global_position - global_position
		to.y = 0
		return to.normalized()
	return direction.cross(Vector3.UP) * 0.4 * strafe_sign

# The most damaged machine in reach (guardians count, but heal slowly).
func mender_target() -> DiverEnemy:
	var best: DiverEnemy = null
	var worst = 1.0
	for other in game.enemies:
		if other == self or not is_instance_valid(other) or other.dead or other.kind == 5: continue
		if other.global_position.distance_to(global_position) > 8.0: continue
		var share = other.health / maxf(1.0, other.max_health)
		if share < worst:
			worst = share
			best = other
	return best

# Host repairs; guests only draw the beam (Life arrives in robot snapshots).
func mender_repair(dt: float) -> void:
	heal_clock -= dt
	if heal_clock > 0: return
	heal_clock = 0.5
	var ally = mender_target()
	if ally == null: return
	game.beam_flash(global_position + Vector3.UP * 1.5, ally.global_position + Vector3.UP * (2.5 if ally.kind == 3 else 1.1), 0.06, Color("8ee3a0"))
	if game.net.is_guest(): return
	ally.health = minf(ally.max_health, ally.health + ally.max_health * (0.01 if ally.kind == 3 else 0.04))
