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

func _ready() -> void:
	var color = Color("ff8060") if hostile else DiverArt.GOLD if heavy else Color("82f5ee")
	mesh = DiverArt.orb(self, Vector3.ZERO, 0.20 if heavy else 0.17 if hostile else 0.11, color, 1.0)
	mesh.scale.z = 2.2
	if direction.length() > 0.1: look_at(global_position + direction)

func _physics_process(dt: float) -> void:
	if not game.world_running(): return
	life -= dt
	if life <= 0: queue_free(); return
	var next = global_position + direction * (12 if hostile else 35 if heavy else 46) * dt
	var mask = 11 if hostile else 5
	var ray = PhysicsRayQueryParameters3D.create(global_position, next, mask)
	ray.hit_from_inside = true
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var collider = hit.collider
		if hostile and collider == game.player:
			game.player.hurt(amount)
		elif collider is DiverEnemy and not cosmetic:
			game.damage_enemy(collider, amount, source)
		if heavy and not hostile:
			var origin: Vector3 = hit.position + hit.normal * 0.1
			for enemy in game.enemies.duplicate():
				if cosmetic or not is_instance_valid(enemy) or enemy.dead or enemy == collider: continue
				var target = enemy.global_position + Vector3.UP * (2.5 if enemy.kind == 3 else 1.0)
				if target.distance_to(origin) < 3.5:
					var splash_ray = PhysicsRayQueryParameters3D.create(origin, target, 1)
					splash_ray.hit_from_inside = true
					if get_world_3d().direct_space_state.intersect_ray(splash_ray).is_empty(): game.damage_enemy(enemy, amount * 0.5, source)
			game.impact_ring(Vector3(hit.position.x, 0.08, hit.position.z), 1.2, DiverArt.GOLD, 0.18)
			game.sound.play("slam", 1.4)
		game.burst(hit.position, Color("ff8060") if hostile else DiverArt.GOLD, 3)
		queue_free()
		return
	global_position = next
	trail_time -= dt
	if not hostile and trail_time <= 0:
		trail_time = 0.05
		game.beam_flash(global_position - direction * (0.8 if heavy else 0.45), global_position, 0.04, DiverArt.GOLD if heavy else Color("8bf0dc"))
