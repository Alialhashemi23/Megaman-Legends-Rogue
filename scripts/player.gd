extends CharacterBody3D
class_name DiverPlayer

var game: Node3D
var art: Dictionary
var character = 0
var visual: DiverCharacter
var camera: Camera3D
var yaw = 0.0
var pitch = -0.20
var cooldown = 0.0
var invincible = 0.0
var dash_time = 0.0
var dash_cooldown = 0.0
var dash_direction = Vector3.ZERO
var step = 0.0
var lock_target: Node3D
var recoil = 0.0
var hp = 100.0
var base_health = 100.0
var base_damage = 12.0
var base_speed = 6.2
var fire_multiplier = 1.0
var level = 1
var xp = 0
var xp_required = 12
var items: Dictionary = {}
var weapon = 0
var skills: Array = []
# Equipped specialization node ("spec_a"/"spec_b") for this dig, or "".
var spec = ""
var storm_heat = 0.0
var focus_target: Node3D
var focus_stacks = 0
var last_hurt = -100000
var medic_glow = 0.0
# Guardian milestones taken this dig, and which descents granted them.
var milestones: Array = []
var milestone_depths: Array = []
var kinetic_time = 0.0
var second_wind_depth = 0
var shot_count = 0
var repair_cooldown = 0.0
const SIGNATURES = [0, 1, 2, 3]
const ATTACK_DETAILS = ["Steady all-round Pulse shots", "Rapid Needle shots / revives twice as fast", "Heavy Siege shots / splash behind exposed targets", "Arcing salvage bombs / small, fast, fragile"]
var trauma = 0.0
var lock_blocked = 0.0
var footstep_time = 0.0
# Online co-op: remote teammates are proxies driven by their owner's state packets.
var is_local = true
var slot = 0
var player_id = ""
var display_name = ""
var bubble: Label3D
var bubble_time = 0.0
var downed = false
var revive = 0.0
var aiming_now = false
var move_input = Vector2.ZERO
var net_pos = Vector3.ZERO
var net_vel = Vector3.ZERO
var net_age = 0.0
var net_flags = 0
var net_seen = false
var name_tag: Label3D
const FLAG_FLOOR = 1
const FLAG_DASH = 2
const FLAG_AIM = 4
const FLAG_DOWN = 8
const FLAG_CHOOSING = 16

func _ready() -> void:
	# Teammate proxies sit on their own layer: robots and local movement ignore them.
	collision_layer = 2 if is_local else 8
	collision_mask = 1 if is_local else 0
	var col = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	set_character(character)
	if not is_local:
		name_tag = DiverArt.label(self, Vector3(0, 2.35, 0), display_name, DiverNet.SLOT_COLORS[clampi(slot, 0, 4)], 40)
		name_tag.no_depth_test = true
		return
	camera = Camera3D.new()
	game.add_child(camera)
	camera.fov = 67
	camera.current = true
	camera.far = 180
	update_camera(1.0)

func set_character(index: int) -> void:
	character = clampi(index, 0, DiverCharacter.COUNT - 1)
	weapon = SIGNATURES[character]
	for child in get_children():
		if child is CollisionShape3D:
			child.shape.height = 1.05 if character == 3 else 1.8
			child.shape.radius = 0.23 if character == 3 else 0.34
			child.position.y = child.shape.height * 0.5
	var facing = visual.rotation.y if is_instance_valid(visual) else yaw
	if is_instance_valid(visual):
		remove_child(visual)
		visual.queue_free()
	visual = DiverCharacter.new()
	visual.character = character
	add_child(visual)
	visual.rotation.y = facing
	visual.equip(mini(weapon, 2))
	art = {"root": visual}

func count(id: String) -> int:
	return int(items.get(id, 0))

# Permanent Workshop multiplier on the digger's starting Life.
func life_bonus() -> float:
	return (DiverProgression.BONUS.frame if "frame" in skills else 1.0) * (DiverProgression.BONUS.cell if "cell" in skills else 1.0)

# The equipped specialization's effect key ("focus", "medic"...), or "".
func specialization() -> String:
	if spec == "" or spec not in skills: return ""
	return str(DiverProgression.spec(character, spec).get("key", ""))

# Field Medic: Roll herself, or a nearby teammate's Roll, keeps repairs going.
func medic_nearby() -> bool:
	if character == 1 and specialization() == "medic": return true
	for other in game.remote_players.values():
		if is_instance_valid(other) and not other.downed and other.character == 1 and other.specialization() == "medic" and other.global_position.distance_to(global_position) < 6.0: return true
	return false

func has_milestone(id: String) -> bool:
	return id in milestones

func max_hp() -> float:
	var starting_life = 65.0 if character == 3 else 100.0
	return base_health - 100.0 + starting_life * life_bonus() + 20 * count("heart")

func damage() -> float:
	return base_damage * (1.0 + 0.16 * count("lens")) * (DiverProgression.BONUS.barrel if "barrel" in skills else 1.0)

func speed() -> float:
	return base_speed * (1.18 if character == 3 else 1.0) * (DiverProgression.BONUS.mobility if "mobility" in skills else 1.0) * (1.0 + 0.09 * count("boots"))

func fire_delay() -> float:
	var base = [0.25, 0.13, 0.65, 0.75][weapon]
	var workshop = (DiverProgression.BONUS.mastery if "mastery" in skills else 1.0) * (DiverProgression.BONUS.loader if "loader" in skills else 1.0)
	return base / (fire_multiplier * workshop * (1.0 + 0.14 * count("spring")) * (1.0 + storm_heat) * (1.3 if kinetic_time > 0 else 1.0))

func _physics_process(dt: float) -> void:
	if not game.world_running(): return
	if not is_local:
		remote_process(dt)
		return
	# Online menus and choices keep the world running; the digger simply stands still.
	var controls = game.mode == "play" and not downed and not game.chat_open
	cooldown -= dt
	repair_cooldown -= dt
	invincible -= dt
	dash_cooldown -= dt
	dash_time -= dt
	kinetic_time -= dt
	# Needle Storm cools off shortly after the trigger is released.
	if cooldown < -0.35: storm_heat = move_toward(storm_heat, 0.0, dt * 0.6)
	if not downed and hp < max_hp() and Time.get_ticks_msec() - last_hurt > 2000 and medic_nearby():
		hp = minf(max_hp(), hp + 2.0 * dt)
		medic_glow -= dt
		if medic_glow <= 0:
			medic_glow = 0.7
			game.burst(global_position + Vector3.UP * 0.9, Color("9cde70"), 2)
	recoil = move_toward(recoil, 0.0, dt * 8)
	trauma = move_toward(trauma, 0.0, dt * 1.8)
	if is_instance_valid(lock_target):
		if lock_target.dead or global_position.distance_to(lock_target.global_position) > 33:
			lock_target = null
		else:
			var direction = lock_target.global_position - global_position
			var sight = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.2, lock_target.global_position + Vector3.UP * (2.5 if lock_target.kind == 3 else 1.1), 1)
			lock_blocked = lock_blocked + dt if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty() else 0
			if lock_blocked > 0.75: lock_target = null
			else: yaw = lerp_angle(yaw, atan2(-direction.x, -direction.z), dt * 8)
	# Keyboard or left stick (analog, so a light tilt walks).
	var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if not controls: input = Vector2.ZERO
	elif not is_instance_valid(lock_target):
		var look = Input.get_vector("look_left", "look_right", "look_up", "look_down")
		yaw -= look.x * 2.7 * game.settings.look_speed * dt
		pitch = clampf(pitch - look.y * 1.9 * game.settings.look_speed * dt * (-1.0 if game.settings.invert_y else 1.0), -0.85, 0.50)
	move_input = input
	var move = Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	if controls and Input.is_action_pressed("dash") and dash_cooldown <= 0:
		dash_direction = move if move.length() > 0 else Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		dash_time = 0.19
		dash_cooldown = maxf(0.65, 1.35 - count("boots") * 0.06) - (DiverProgression.BONUS.servos if "servos" in skills else 0.0)
		invincible = 0.26
		game.sound.play("dash")
		if specialization() == "runner":
			game.spawn_bolt(global_position + Vector3.UP * 0.6, Vector3(0, 3.0, 0), damage() * 2.0, false, true, 1, self)
		if character == 1 and "ability" in skills and repair_cooldown <= 0:
			heal(DiverProgression.BONUS.repair_life_2 if "ability2" in skills else DiverProgression.BONUS.repair_life)
			repair_cooldown = DiverProgression.BONUS.repair_delay
			game.burst(global_position + Vector3.UP, Color("9cde70"), 6)
		if has_milestone("kinetic"): kinetic_time = 2.5
		if has_milestone("glacier"):
			game.frost_burst(position, 3.0 + count("frost"))
			game.impact_ring(Vector3(position.x, game.floor_height(position) + 0.08, position.z), 6.0, Color("b2e4ef"), 0.22)
		elif count("frost") > 0: game.frost_burst(position, 2 + count("frost"))
	if dash_time > 0:
		velocity.x = dash_direction.x * 19
		velocity.z = dash_direction.z * 19
	else:
		velocity.x = move.x * speed()
		velocity.z = move.z * speed()
	if not is_on_floor(): velocity.y -= 25 * dt
	else:
		velocity.y = 0
		if controls and Input.is_action_pressed("jump"):
			velocity.y = 8
			game.sound.play("jump")
	var was_grounded = is_on_floor()
	var fall_speed = velocity.y
	move_and_slide()
	if is_on_floor() and not was_grounded and fall_speed < -2: game.sound.play("land")
	footstep_time -= dt
	if position.y < -15:
		position = game.rooms[game.current_room].center + Vector3(0, 2, 0)
		hurt(15)
	art.root.rotation.y = lerp_angle(art.root.rotation.y, yaw, dt * 16)
	art.root.rotation.z = lerpf(art.root.rotation.z, -input.x * 0.065, dt * 8)
	var aiming = controls and (Input.is_action_pressed("fire") or is_instance_valid(lock_target) or cooldown > 0)
	aiming_now = aiming
	visual.equip(mini(weapon, 2))
	if downed:
		visual.preview(dt, true, false)
		update_revive(dt)
	else: visual.animate(dt, input, is_on_floor(), velocity.y, dash_time > 0, aiming, pitch, recoil, speed() / base_speed)
	if visual.foot_contact and footstep_time <= 0:
		game.sound.play("step", 1.0, global_position)
		footstep_time = .08
	art.root.visible = invincible <= 0 or int(invincible * 25) % 2 == 0
	if controls and Input.is_action_pressed("fire") and cooldown <= 0 and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or game.settings.using_pad):
		shoot()
	update_camera(dt)

func update_camera(dt: float) -> void:
	update_bubble(dt)
	# While down, the camera follows a standing teammate instead.
	var focus: Node3D = self
	if downed and is_local:
		var mate = game.spectate_target()
		if mate: focus = mate
	var pivot = focus.global_position + Vector3(0, 0.85 if focus.character == 3 else 1.55, 0)
	var basis_cam = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var desired = pivot + basis_cam * Vector3(-0.78, 0.60, 5.8)
	var ray = PhysicsRayQueryParameters3D.create(pivot, desired, 1)
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty(): desired = hit.position + hit.normal * 0.25
	camera.global_position = camera.global_position.lerp(desired, minf(dt * 20, 1))
	camera.rotation = Vector3(pitch, yaw, 0)
	if is_instance_valid(lock_target) and focus == self: camera.look_at(lock_target.global_position + Vector3.UP * (2.5 if lock_target.kind == 3 else 1.15))
	camera.fov = lerpf(camera.fov, game.settings.fov + (recoil * 0.8 if game.camera_effects else 0.0), minf(1, dt * 14))
	var amount = trauma * 0.09 if game.camera_effects else 0.0
	camera.h_offset = sin(Time.get_ticks_msec() * 0.061) * amount
	camera.v_offset = cos(Time.get_ticks_msec() * 0.077) * amount

func add_trauma(amount: float) -> void:
	trauma = minf(0.45, trauma + amount)

func look_mouse(relative: Vector2) -> void:
	if is_instance_valid(lock_target): return
	var sensitivity = game.settings.mouse_sensitivity
	yaw -= relative.x * 0.0027 * sensitivity
	pitch = clampf(pitch - relative.y * 0.0024 * sensitivity * (-1.0 if game.settings.invert_y else 1.0), -0.85, 0.50)

func toggle_lock() -> void:
	lock_blocked = 0
	if is_instance_valid(lock_target):
		lock_target = null
		return
	var best = 100.0
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead: continue
		var dist = position.distance_to(enemy.position)
		var to_enemy = (enemy.global_position + Vector3.UP - camera.global_position).normalized()
		var alignment = -camera.global_basis.z.dot(to_enemy)
		if dist < 30 and alignment > 0.45 and dist - alignment * 12 < best:
			var ray = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, enemy.global_position + Vector3.UP, 1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			best = dist - alignment * 12
			lock_target = enemy
	if is_instance_valid(lock_target): game.sound.play("lock")

func shoot() -> void:
	cooldown = fire_delay()
	recoil = 1
	visual.fire()
	game.sound.play(["shot", "needle", "siege", "siege"][weapon])
	# Apply full aim on the first shot as well as during sustained fire.
	visual.arm_weight = 1.0
	visual.layer_aim(0, true, pitch, recoil)
	var start = visual.muzzle.global_position
	var muzzle_wall = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * (0.65 if character == 3 else 1.2), start, 1)
	if not get_world_3d().direct_space_state.intersect_ray(muzzle_wall).is_empty():
		game.burst(start, Color("ffca68"), 3)
		return
	game.muzzle_flash(start, Color("ffda82"), 0.28 if weapon == 2 else 0.16)
	add_trauma(0.10 if weapon == 2 else 0.025)
	var screen_center = get_viewport().get_visible_rect().size * 0.5
	var ray_origin = camera.project_ray_origin(screen_center)
	var aim = ray_origin + camera.project_ray_normal(screen_center) * 100
	var query = PhysicsRayQueryParameters3D.create(ray_origin, aim, 5)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): aim = hit.position
	if is_instance_valid(lock_target): aim = lock_target.global_position + Vector3.UP * (2.5 if lock_target.kind == 3 else 1.1)
	var direction = (aim - start).normalized()
	if weapon == 3:
		var target = start + (aim - start).limit_length(28.0)
		var flight = maxf(0.25, Vector2(target.x - start.x, target.z - start.z).length() / 18.0)
		direction = (target - start) / flight + Vector3.UP * 10.0 * flight
	var amount = damage() * ([1.0, 0.55, 2.4, 2.0][weapon])
	if specialization() == "demolition": amount *= 1.45
	if specialization() == "storm": storm_heat = minf(0.30, storm_heat + 0.03)
	shot_count += 1
	var interval = int(DiverProgression.BONUS.pulse_interval_2 if "ability2" in skills else DiverProgression.BONUS.pulse_interval)
	if character == 0 and "ability" in skills and shot_count % interval == 0: amount *= DiverProgression.BONUS.pulse_power
	game.spawn_bolt(start, direction, amount, false, weapon >= 2, 1 if weapon == 3 else 0, self)
	game.build_changed()
	if (count("echo") > 0 or has_milestone("twin")) and game.rng.randf() < minf(0.8, 0.12 * count("echo") + (0.35 if has_milestone("twin") else 0.0)):
		game.spawn_bolt(start + Vector3.UP * 0.18, direction.rotated(Vector3.UP, 0.025), amount * 0.7, false, weapon >= 2, 1 if weapon == 3 else 0, self)
	if count("split") > 0:
		for sign_dir in [-1, 1]:
			game.spawn_bolt(start, direction.rotated(Vector3.UP, sign_dir * 0.13), amount * minf(0.75, 0.25 + count("split") * 0.12), false, weapon >= 2, 1 if weapon == 3 else 0, self)

func hurt(amount: float) -> void:
	if invincible > 0 or downed or not game.world_running(): return
	# Online part and level choices don't pause the dig, so choosing is protected.
	if game.mode == "choice": return
	amount *= 1.0 / (1 + count("shell") * 0.18)
	if has_milestone("bulwark") and hp > max_hp() * 0.5: amount *= 0.75
	if has_milestone("second_wind") and hp - amount <= 0 and second_wind_depth != game.depth:
		second_wind_depth = game.depth
		amount = 0.0
		hp = max_hp() * 0.3
		game.float_text(global_position + Vector3.UP * 2.4, "SECOND WIND", Color("9cde70"))
		game.burst(global_position + Vector3.UP, Color("9cde70"), 10)
		game.build_changed()
	hp = maxf(0, hp - amount)
	last_hurt = Time.get_ticks_msec()
	visual.hurt()
	invincible = 0.65 + (DiverProgression.BONUS.plating if "plating" in skills else 0.0)
	game.hurt_flash = 0.5
	add_trauma(0.22)
	game.sound.play("hurt")
	game.settings.rumble(0.35, 0.65, 0.22)
	game.float_text(global_position + Vector3.UP * 2, "−%d" % int(amount), Color("ff795f"))
	if hp <= 0: game.local_player_down()

func heal(amount: float) -> void:
	if downed: return
	hp = minf(max_hp(), hp + amount)

func add_item(id: String) -> void:
	items[id] = count(id) + 1
	if id == "heart": heal(20)
	game.record_discovery(id)
	game.sound.play("loot")
	game.notify("%s ×%d" % [game.ITEMS[id].name, count(id)], game.ITEMS[id].desc)
	game.build_changed()

func gain_xp(amount: int) -> void:
	xp += amount
	if xp >= xp_required:
		xp -= xp_required
		level += 1
		xp_required = 10 + level * 6
		heal(12)
		game.queue_level = true
	game.build_changed()

# A downed digger revives after a teammate stands close for a few seconds.
func update_revive(dt: float) -> void:
	var helper = ""
	for other in game.remote_players.values():
		if is_instance_valid(other) and not other.downed and other.global_position.distance_to(global_position) < 2.4: helper = other.display_name
	var rate = 1.0
	for other in game.remote_players.values():
		if is_instance_valid(other) and not other.downed and other.character == 1 and other.global_position.distance_to(global_position) < 2.4: rate = 2.0
	revive = clampf(revive + (dt * rate / 2.5 if helper != "" else -dt * 0.25), 0, 1)
	if revive >= 1: revive_now(0.35, helper)

func revive_now(fraction: float, helper: String = "") -> void:
	downed = false
	revive = 0
	hp = max_hp() * fraction
	invincible = 1.5
	visual.current_clip = ""
	game.build_changed()
	if helper != "": game.notify("BACK ON YOUR FEET", "%s pulled you up. Restored %d%% Life." % [helper, int(fraction * 100)])

func state_flags() -> int:
	var flags = 0
	if is_on_floor(): flags |= FLAG_FLOOR
	if dash_time > 0: flags |= FLAG_DASH
	if aiming_now: flags |= FLAG_AIM
	if downed: flags |= FLAG_DOWN
	if game.mode == "choice": flags |= FLAG_CHOOSING
	return flags

func apply_state(pos: Vector3, vel: Vector3, new_yaw: float, new_pitch: float, input: Vector2, flags: int, life: float, life_max: float, revive_amount: float) -> void:
	if not net_seen or pos.distance_to(global_position) > 6: global_position = pos
	net_seen = true
	net_pos = pos
	net_vel = vel
	net_age = 0
	yaw = new_yaw
	pitch = new_pitch
	move_input = input
	net_flags = flags
	hp = life
	base_health = life_max - 20 * count("heart") - (65.0 if character == 3 else 100.0) * life_bonus() + 100.0
	revive = revive_amount
	var was_down = downed
	downed = flags & FLAG_DOWN != 0
	if downed != was_down: visual.current_clip = ""

func remote_process(dt: float) -> void:
	update_bubble(dt)
	net_age += dt
	recoil = move_toward(recoil, 0.0, dt * 8)
	footstep_time -= dt
	var target = net_pos + net_vel * minf(net_age, 0.12)
	global_position = global_position.lerp(target, minf(1, dt * 14))
	art.root.rotation.y = lerp_angle(art.root.rotation.y, yaw, dt * 16)
	art.root.rotation.z = lerpf(art.root.rotation.z, -move_input.x * 0.065, dt * 8)
	visual.equip(mini(weapon, 2))
	if downed: visual.preview(dt, true, false)
	else: visual.animate(dt, move_input, net_flags & FLAG_FLOOR != 0, net_vel.y, net_flags & FLAG_DASH != 0, net_flags & FLAG_AIM != 0, pitch, recoil, speed() / base_speed)
	if visual.foot_contact and footstep_time <= 0 and not downed:
		game.sound.play("step", 0.95, global_position)
		footstep_time = .08
	if is_instance_valid(name_tag):
		name_tag.text = display_name + ("\nDOWN · stand close to revive" if downed else "\nchoosing a part…" if net_flags & FLAG_CHOOSING else "")
		name_tag.modulate = Color("ff9565") if downed else DiverNet.SLOT_COLORS[clampi(slot, 0, 4)]

func remote_shot(start: Vector3) -> void:
	recoil = 1
	visual.fire()
	visual.arm_weight = 1.0
	game.muzzle_flash(start, Color("ffda82"), 0.28 if weapon == 2 else 0.16)
	game.sound.play(["shot", "needle", "siege", "siege"][weapon], 1.0, start)

# Quick-chat callouts float above the digger for a few seconds.
func speak(text: String) -> void:
	if not is_instance_valid(bubble):
		bubble = DiverArt.label(self, Vector3(0, 2.95, 0), "", Color("fff9df"), 44)
		bubble.no_depth_test = true
	bubble.text = text
	bubble.visible = true
	bubble_time = 3.0

func update_bubble(dt: float) -> void:
	if bubble_time <= 0: return
	bubble_time -= dt
	if is_instance_valid(bubble): bubble.visible = bubble_time > 0
