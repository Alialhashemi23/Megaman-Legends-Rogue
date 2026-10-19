extends Node3D
class_name DiverBolt

var game: Node3D
var direction = Vector3.FORWARD
var amount = 10.0
var hostile = false
var heavy = false
var life = 2.5
var mesh: MeshInstance3D
var trail_time = 0.0
var source: Node3D
# Teammates' shots are replayed for show; their owner reports the real hits.
var cosmetic = false
var bomb = false
var flight_velocity = Vector3.ZERO
# A Ricochet Coil bounce doesn't bounce again.
var bounced = false
# Flare Cartridge stacks: this shot leaves a burning patch where it lands.
var flare = 0
var guardian_room = -1

func _ready() -> void:
	var color = Color("ff8060") if hostile else Color("e87545") if bomb else DiverArt.GOLD if heavy else Color("82f5ee")
	mesh = DiverArt.orb(self, Vector3.ZERO, 0.20 if heavy else 0.17 if hostile else 0.11, color, 1.0)
	mesh.scale.z = 2.2
	if bomb:
		mesh.scale.z = 1.0
		flight_velocity = direction
	if direction.length() > 0.1: look_at(global_position + direction)

func _physics_process(dt: float) -> void:
	if not game.world_running(): return
	life -= dt
	if life <= 0:
		if bomb: explode(global_position, null)
		queue_free()
		return
	# Hostile bolts speed up on deeper floors (DiverEnemy.lock_aim leads by the same speed).
	var next = global_position + direction * (17 + game.depth * 2 if hostile else 35 if heavy else 46) * dt
	if bomb:
		next = global_position + flight_velocity * dt - Vector3.UP * 10.0 * dt * dt
		flight_velocity.y -= 20.0 * dt
	var mask = 11 if hostile else 5
	var ray = PhysicsRayQueryParameters3D.create(global_position, next, mask)
	ray.hit_from_inside = true
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var collider = hit.collider
		if hostile and collider == game.player:
			if guardian_room < 0 or game.room_index_at(game.player.global_position) == guardian_room: game.player.hurt(amount)
		elif hostile and collider.has_meta("pillar"):
			game.damage_pillar(int(collider.get_meta("pillar")), amount)
		elif collider is DiverEnemy and not cosmetic:
			var dealt = amount * (1.4 if heavy and spec() == "breaker" else 1.0) * guardian_bonus(collider) * core_bonus(collider, hit.position)
			game.damage_enemy(collider, dealt, source)
			if spec() == "breaker" and heavy: game.frost_burst(hit.position, 0.5, 2.0)
			if spec() == "ricochet" and not bounced: ricochet(collider, hit.position + hit.normal * 0.2)
		if flare > 0 and not hostile and not cosmetic: game.flare_patch(hit.position, amount, flare, source)
		if heavy and not hostile:
			explode(hit.position + hit.normal * 0.1, collider)
		game.burst(hit.position, Color("ff8060") if hostile else DiverArt.GOLD, 3)
		queue_free()
		return
	global_position = next
	trail_time -= dt
	if not hostile and trail_time <= 0:
		trail_time = 0.05
		game.beam_flash(global_position - direction.normalized() * (0.8 if heavy else 0.45), global_position, 0.04, DiverArt.GOLD if heavy else Color("8bf0dc"))

func spec() -> String:
	return source.specialization() if is_instance_valid(source) and not hostile else ""

# Demolition Charge: bombs hit guardians harder.
func guardian_bonus(enemy: Object) -> float:
	return 1.25 if spec() == "demolition" and enemy is DiverEnemy and enemy.kind == 3 else 1.0

# Exposed core (BOSS-01): hits near a venting guardian's core land much harder,
# more so with Refractor Crystals. Lock-on aims at the body, so this rewards aim.
func core_bonus(enemy: DiverEnemy, at: Vector3) -> float:
	if enemy.kind != 3 or enemy.vent_time <= 0 or at.distance_to(enemy.core_point()) > 0.85: return 1.0
	game.float_text(at + Vector3.UP * 0.4, "CORE!", Color("ffdc68"))
	var refractors = source.count("refractor") if is_instance_valid(source) else 0
	return 2.5 * (1.0 + 0.4 * refractors)

func ricochet(from_enemy: Object, origin: Vector3) -> void:
	var best: DiverEnemy = null
	var best_distance = 9.0
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy == from_enemy: continue
		var d = enemy.global_position.distance_to(origin)
		if d >= best_distance: continue
		var sight = PhysicsRayQueryParameters3D.create(origin, enemy.global_position + Vector3.UP, 1)
		if get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
			best = enemy
			best_distance = d
	if best == null: return
	var target = best.global_position + Vector3.UP * (2.5 if best.kind == 3 else 1.1)
	var bounce = game.spawn_bolt(origin, (target - origin).normalized(), amount * 0.6, false, false, 0, source)
	bounce.bounced = true

func splash_radius() -> float:
	var radius = 3.5
	if is_instance_valid(source) and source.character in [2, 3] and "ability" in source.skills:
		radius = DiverProgression.BONUS.splash_radius_2 if "ability2" in source.skills else DiverProgression.BONUS.splash_radius
	return radius + (1.5 if spec() == "barrage" else 0.0)

func explode(origin: Vector3, collider: Object) -> void:
	for enemy in game.enemies.duplicate():
		if cosmetic or not is_instance_valid(enemy) or enemy.dead or enemy == collider: continue
		var target = enemy.global_position + Vector3.UP * (2.5 if enemy.kind == 3 else 1.0)
		if target.distance_to(origin) < splash_radius():
			var ray = PhysicsRayQueryParameters3D.create(origin, target, 1)
			ray.hit_from_inside = true
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): game.damage_enemy(enemy, amount * (0.65 if spec() == "barrage" else 0.5) * guardian_bonus(enemy), source)
	if spec() == "barrage" and not cosmetic: game.frost_burst(origin, 1.5, splash_radius())
	game.impact_ring(Vector3(origin.x, game.floor_height(origin) + 0.08, origin.z), splash_radius(), DiverArt.GOLD, 0.18)
	game.sound.play("slam", 1.4)
