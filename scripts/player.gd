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
var trauma = 0.0
var lock_blocked = 0.0
var footstep_time = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var col = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	set_character(character)
	camera = Camera3D.new()
	game.add_child(camera)
	camera.fov = 67
	camera.current = true
	camera.far = 180
	update_camera(1.0)

func set_character(index: int) -> void:
	character = clampi(index, 0, 1)
	var facing = visual.rotation.y if is_instance_valid(visual) else yaw
	if is_instance_valid(visual):
		remove_child(visual)
		visual.queue_free()
	visual = DiverCharacter.new()
	visual.character = character
	add_child(visual)
	visual.rotation.y = facing
	visual.equip(weapon)
	art = {"root": visual}

func count(id: String) -> int:
	return int(items.get(id, 0))

func max_hp() -> float:
	return base_health + 20 * count("heart")

func damage() -> float:
	return base_damage * (1.0 + 0.16 * count("lens"))

func speed() -> float:
	return base_speed * (1.0 + 0.09 * count("boots"))

func fire_delay() -> float:
	var base = [0.25, 0.13, 0.65][weapon]
	return base / (fire_multiplier * (1.0 + 0.14 * count("spring")))

func _physics_process(dt: float) -> void:
	if game.mode != "play": return
	cooldown -= dt
	invincible -= dt
	dash_cooldown -= dt
	dash_time -= dt
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
	var input = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
	var move = Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	if Input.is_physical_key_pressed(KEY_SHIFT) and dash_cooldown <= 0:
		dash_direction = move if move.length() > 0 else Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		dash_time = 0.19
		dash_cooldown = maxf(0.65, 1.35 - count("boots") * 0.06)
		invincible = 0.26
		game.sound.play("dash")
		if count("frost") > 0:
			for enemy in game.enemies:
				if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_to(position) < 6:
					enemy.slow = 2 + count("frost")
	if dash_time > 0:
		velocity.x = dash_direction.x * 19
		velocity.z = dash_direction.z * 19
	else:
		velocity.x = move.x * speed()
		velocity.z = move.z * speed()
	if not is_on_floor(): velocity.y -= 25 * dt
	else:
		velocity.y = 0
		if Input.is_physical_key_pressed(KEY_SPACE):
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
	var aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or is_instance_valid(lock_target) or cooldown > 0
	visual.equip(weapon)
	visual.animate(dt, input, is_on_floor(), velocity.y, dash_time > 0, aiming, pitch, recoil, speed() / base_speed)
	if visual.foot_contact and footstep_time <= 0:
		game.sound.play("step", 1.0, global_position)
		footstep_time = .08
	art.root.visible = invincible <= 0 or int(invincible * 25) % 2 == 0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()
	update_camera(dt)

func update_camera(dt: float) -> void:
	var pivot = global_position + Vector3(0, 1.55, 0)
	var basis_cam = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var desired = pivot + basis_cam * Vector3(-0.78, 0.60, 5.8)
	var ray = PhysicsRayQueryParameters3D.create(pivot, desired, 1)
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty(): desired = hit.position + hit.normal * 0.25
	camera.global_position = camera.global_position.lerp(desired, minf(dt * 20, 1))
	camera.rotation = Vector3(pitch, yaw, 0)
	if is_instance_valid(lock_target): camera.look_at(lock_target.global_position + Vector3.UP * (2.5 if lock_target.kind == 3 else 1.15))
	camera.fov = lerpf(camera.fov, 67 + (recoil * 0.8 if game.camera_effects else 0.0), minf(1, dt * 14))
	var amount = trauma * 0.09 if game.camera_effects else 0.0
	camera.h_offset = sin(Time.get_ticks_msec() * 0.061) * amount
	camera.v_offset = cos(Time.get_ticks_msec() * 0.077) * amount

func add_trauma(amount: float) -> void:
	trauma = minf(0.45, trauma + amount)

func look_mouse(relative: Vector2) -> void:
	if is_instance_valid(lock_target): return
	yaw -= relative.x * 0.0027
	pitch = clampf(pitch - relative.y * 0.0024, -0.85, 0.50)

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
	game.sound.play(["shot", "needle", "siege"][weapon])
	# Apply full aim on the first shot as well as during sustained fire.
	visual.arm_weight = 1.0
	visual.layer_aim(0, true, pitch, recoil)
	var start = visual.muzzle.global_position
	var muzzle_wall = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.2, start, 1)
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
	var amount = damage() * ([1.0, 0.55, 2.4][weapon])
	game.spawn_bolt(start, direction, amount, false, weapon == 2, 0)
	if count("echo") > 0 and game.rng.randf() < minf(0.8, 0.12 * count("echo")):
		game.spawn_bolt(start + Vector3.UP * 0.18, direction.rotated(Vector3.UP, 0.025), amount * 0.7, false, false, 0)
	if count("split") > 0:
		for sign_dir in [-1, 1]:
			game.spawn_bolt(start, direction.rotated(Vector3.UP, sign_dir * 0.13), amount * minf(0.75, 0.25 + count("split") * 0.12), false, false, 0)

func hurt(amount: float) -> void:
	if invincible > 0 or game.mode != "play": return
	amount *= 1.0 / (1 + count("shell") * 0.18)
	hp = maxf(0, hp - amount)
	visual.hurt()
	invincible = 0.65
	game.hurt_flash = 0.5
	add_trauma(0.22)
	game.sound.play("hurt")
	game.float_text(global_position + Vector3.UP * 2, "−%d" % int(amount), Color("ff795f"))
	if hp <= 0: game.finish_run(false)

func heal(amount: float) -> void:
	hp = minf(max_hp(), hp + amount)

func add_item(id: String) -> void:
	items[id] = count(id) + 1
	if id == "heart": heal(20)
	game.meta.discovered[id] = true
	game.save_meta()
	game.sound.play("loot")
	game.notify("%s ×%d" % [game.ITEMS[id].name, count(id)], game.ITEMS[id].desc)

func gain_xp(amount: int) -> void:
	xp += amount
	if xp >= xp_required:
		xp -= xp_required
		level += 1
		xp_required = 10 + level * 6
		heal(12)
		game.queue_level = true
