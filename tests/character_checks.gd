extends SceneTree

var game: Node3D
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func verify(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func press(key: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	root.push_input(event, true)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	await process_frame
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	press(KEY_C)
	verify(game.selected_character == 1 and game.player.character == 1, "C selects Roll and updates the preview")
	press(KEY_C)
	verify(game.selected_character == 2 and game.player.character == 2, "C moves on to Tron")
	press(KEY_C)
	verify(game.selected_character == 3 and game.player.character == 3, "C moves on to the Servbot")
	press(KEY_C)
	verify(game.selected_character == 0 and game.player.character == 0, "C returns to Mega")
	for index in DiverCharacter.COUNT:
		# Tron's cutscene rig has one fewer face joint; a Servbot has one joint per limb.
		var joint_count = [18, 18, 17, 7][index]
		game.selected_character = index
		game.start_run(49381)
		for enemy in game.enemies: enemy.set_physics_process(false)
		game.player.set_physics_process(false)
		var visual: DiverCharacter = game.player.visual
		verify(game.player.character == index, "Selected digger carries into a new run")
		verify(visual.skeleton.get_bone_count() == joint_count, "Original skeleton keeps all its joints")
		verify(visual.animator.get_animation_list().size() >= 12, "Twelve authored clips are imported")
		var meshes = visual.model.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.skin != null)
		verify(meshes.size() == 1 and meshes[0].skin != null, "Original body uses a skinned mesh")
		var mesh: MeshInstance3D = meshes[0]
		verify(mesh.skin.get_bind_count() == joint_count, "Skin retains all original binds")
		var arrays = mesh.mesh.surface_get_arrays(0)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in range(0, weights.size(), 4):
			verify(is_equal_approx(weights[vertex] + weights[vertex+1] + weights[vertex+2] + weights[vertex+3], 1.0), "Skin weight remains normalized")
		for clip in ["idle", "run", "backpedal", "strafe_left", "strafe_right", "jump", "fall", "dash", "dash_back", "dash_left", "dash_right", "hurt", "fire", "victory", "defeat"]:
			verify(visual.animator.has_animation(clip), "Clip exists: " + clip)
			visual.current_clip = ""
			visual.select_clip(clip, true)
			visual.animator.advance(visual.animator.get_animation(clip).length * .35)
			for joint in visual.joints.values():
				var pose = visual.skeleton.get_bone_global_pose(joint)
				verify(pose.origin.is_finite() and pose.origin.length() < 2.8, "Animation joint remains finite and within character bounds")
		visual.animate(.12, Vector2(0, -1), true, 0, false, true, -.2, 0)
		visual.animate(.1, Vector2(0, -1), true, 0, false, true, -.2, 0)
		verify(visual.current_clip == "run", "Forward movement selects running")
		verify(absf(visual.skeleton.get_bone_pose_rotation(visual.joints.LeftUpperLeg).get_euler().x) > .05, "Running moves the skinned leg bones")
		game.player.shoot()
		verify(visual.current_clip == "run", "Firing preserves running animation")
		var barrel = (visual.weapon_mount.global_basis * Vector3.DOWN).normalized()
		verify(barrel.dot(Vector3(0, sin(-.2), -cos(-.2))) > .97, "Buster points along intended pitch")
		# A Servbot's arm is short, so its muzzle sits closer in.
		verify(visual.muzzle.global_position.z < game.player.position.z - [.3, .3, .3, .15][index], "Projectile muzzle sits beyond the body")
		verify(visual.muzzle.global_position.x < game.player.position.x, "Muzzle follows left arm")
		for i in 80: visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
		var arm_joint = visual.joints.get("LeftForeArm", visual.joints.LeftUpperArm)
		var relaxed = visual.skeleton.get_bone_pose_rotation(arm_joint)
		visual.animator.advance(0)
		verify(relaxed.angle_to(visual.skeleton.get_bone_pose_rotation(arm_joint)) < .001 and absf(relaxed.get_euler().x) < .2, "Aim releases to the authored relaxed arm without accumulating overrides")
		# Changing direction keeps the current left/right step instead of restarting.
		visual.select_clip("run", true)
		visual.animator.advance(.18)
		var stride_phase = visual.animator.current_animation_position / visual.animator.current_animation_length
		visual.animate(1.0/120, Vector2.LEFT, true, 0, false, false, 0, 0)
		var new_phase = visual.animator.current_animation_position / visual.animator.current_animation_length
		verify(absf(new_phase - stride_phase - (1.0/120) / visual.animator.current_animation_length) < .002, "Direction changes retain stride phase")
		# Verify contact against skinned boot vertices, not just bone origins.
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var sole_vertices: Array = []
		for vertex in vertices.size():
			var bind_index = bones[vertex * 4]
			var name = mesh.skin.get_bind_name(bind_index)
			if str(name).ends_with("Foot" if visual.joints.has("LeftFoot") else "UpperLeg"):
				sole_vertices.append([vertex, bind_index, visual.skeleton.find_bone(name)])
		verify(not sole_vertices.is_empty(), "Boot geometry is available for contact checks")
		# Rigs with knees plant run/backpedal steps with an airborne moment between them.
		var planted_clips = {"run": -1.0, "backpedal": 1.0} if visual.joints.has("LeftLowerLeg") else {}
		for locomotion in DiverCharacter.LOCOMOTION:
			visual.select_clip(locomotion, true)
			var clip_length = visual.animator.get_animation(locomotion).length
			var touching = 0
			var previous = {}
			for frame in 33:
				visual.animator.seek(clip_length * frame / 32.0, true)
				var lowest = INF
				var soles = {}
				for sole in sole_vertices:
					var deformed = visual.skeleton.get_bone_global_pose(sole[2]) * mesh.skin.get_bind_pose(sole[1]) * vertices[sole[0]]
					lowest = minf(lowest, deformed.y)
					if deformed.y < .01: soles[sole[0]] = deformed
				if not planted_clips.has(locomotion):
					verify(absf(lowest) < .018, "At least one boot meets the floor during " + locomotion)
					continue
				verify(lowest > -.018, "Boots never sink into the floor during " + locomotion)
				if lowest < .01: touching += 1
				# A sole touching in consecutive samples stays put while the body travels on.
				var travel = Vector3(0, 0, planted_clips[locomotion] * 6.2 * clip_length / 32.0)
				for vertex in soles:
					if previous.has(vertex): verify((soles[vertex] + travel).distance_to(previous[vertex]) < .03, "Planted boots don't skate during " + locomotion)
				previous = soles
			if planted_clips.has(locomotion): verify(touching >= 14 and touching <= 26, "Planted steps alternate with airborne moments during " + locomotion)
		visual.select_clip("run", true)
		visual.animator.advance(0)
		for frame in 10: visual.animate(1.0/60, Vector2.UP, true, 0, false, true, -.2, 0)
		var contacts = 0
		for frame in 180:
			visual.animate(1.0/60, Vector2.UP, true, 0, false, true, -.2, 0)
			if visual.foot_contact: contacts += 1
			var running_barrel = (visual.weapon_mount.basis * Vector3.DOWN).normalized()
			verify(running_barrel.dot(Vector3(0, sin(-.2), -cos(-.2))) > .97, "Buster stays steady throughout running")
		verify(contacts >= 12 and contacts <= 13, "Footsteps follow the two contacts in each run cycle")
		visual.animate(.1, Vector2.LEFT, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "strafe_left", "Left movement selects strafing")
		visual.animate(.1, Vector2.DOWN, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "backpedal", "Backward movement selects backpedal")
		visual.animate(.1, Vector2.ZERO, false, 6, false, false, 0, 0)
		verify(visual.current_clip == "jump", "Rising selects jump")
		visual.animate(.4, Vector2.ZERO, false, -2, false, false, 0, 0)
		verify(visual.current_clip == "fall", "Descending selects fall")
		visual.animate(.1, Vector2.ZERO, true, 0, true, false, 0, 0)
		verify(visual.current_clip == "dash", "Dash selects its own pose")
		# Each dash direction has its own one-shot clip, started from the onset.
		for pair in [[Vector2(0, -1), "dash"], [Vector2(0, 1), "dash_back"], [Vector2(-1, 0), "dash_left"], [Vector2(1, 0), "dash_right"], [Vector2(.5, -.9), "dash"]]:
			for frame in 30: visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
			verify(visual.current_clip == "idle", "A finished dash hands back to idle")
			visual.animate(1.0/60, Vector2.ZERO, true, 0, true, false, 0, 0, 1.0, pair[0])
			verify(visual.current_clip == pair[1] and visual.animator.current_animation_position < .03, "Dash direction selects %s from its onset" % pair[1])
		# Travel shows a clear lean, the buster holds its aim, and the recovery plays out.
		for frame in 30: visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
		var steady = true
		for frame in 11:
			visual.animate(1.0/60, Vector2.ZERO, true, 0, true, true, -.2, 0, 1.0, Vector2(0, -1))
			var dash_barrel = (visual.weapon_mount.basis * Vector3.DOWN).normalized()
			if frame > 6: steady = steady and dash_barrel.dot(Vector3(0, sin(-.2), -cos(-.2))) > .97
		verify(steady, "Buster stays steady through the dash")
		verify(visual.skeleton.get_bone_pose_rotation(visual.joints.Hips).get_angle() > .3, "Dash travel leans the whole body clearly")
		var planted = false
		for frame in 4:
			visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
			planted = planted or visual.foot_contact
		verify(visual.current_clip == "dash", "Standing still lets the dash recovery play")
		for frame in 8:
			visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
			planted = planted or visual.foot_contact
		verify(planted, "The dash plant sounds a footstep")
		for frame in 30: visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
		for frame in 11: visual.animate(1.0/60, Vector2.ZERO, true, 0, true, false, 0, 0)
		for frame in 6: visual.animate(1.0/60, Vector2.UP, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "run", "Running on cuts the dash recovery short")
		# A real fall lands in a squash; moving on (or a short hop) goes straight to running.
		visual.animate(.5, Vector2.ZERO, false, -6, false, false, 0, 0)
		visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "land" and visual.animator.current_animation_position < .03, "Landing from a fall squashes from its start")
		for frame in 20: visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "idle", "The landing squash settles back to idle")
		visual.animate(.5, Vector2.ZERO, false, -6, false, false, 0, 0)
		visual.animate(1.0/60, Vector2.UP, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "run", "Landing while moving keeps running")
		visual.animate(.1, Vector2.ZERO, false, -2, false, false, 0, 0)
		visual.animate(1.0/60, Vector2.ZERO, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "idle", "A short hop skips the landing squash")
		if index == 0:
			# A teammate's dash clip follows its synced velocity relative to its facing.
			var proxy = game.create_remote_player(1)
			var turned = 0.7
			var right = Vector3.RIGHT.rotated(Vector3.UP, turned)
			proxy.apply_state(proxy.position, right * 19, turned, 0, Vector2.ZERO, DiverPlayer.FLAG_DASH | DiverPlayer.FLAG_FLOOR, 100, 100, 0)
			proxy.remote_process(1.0/60)
			verify(proxy.visual.current_clip == "dash_right", "Remote dash plays the clip for its travel direction")
			game.remove_remote_player(1)
		visual.animate(.1, Vector2.ZERO, true, 0, true, false, 0, 0)
		visual.hurt()
		visual.animate(.02, Vector2.ZERO, true, 0, false, false, 0, 0)
		verify(visual.current_clip == "hurt", "Damage triggers a hit reaction")
		var target = game.spawn_enemy(Vector3(0, 0, -5), 0, 0)
		target.set_physics_process(false)
		game.player.lock_target = target
		game.player.cooldown = 0
		game.player.shoot()
		var health = target.health
		await create_timer(.5).timeout
		verify(target.health < health, "Sourced character fires a damaging projectile from its muzzle")
		game.depth = 2
		game.build_floor(true)
		verify(game.player.character == index and game.player.visual == visual, "Character and rig survive descent changes")
	print("CHARACTER_CHECKS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
