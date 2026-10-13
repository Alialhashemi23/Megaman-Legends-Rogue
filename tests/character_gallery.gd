extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440, 900)
	var scene = Node3D.new()
	root.add_child(scene)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("14263e")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c6d8eb")
	env.environment.ambient_light_energy = 0.9
	scene.add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -20, 0)
	light.light_energy = .8
	scene.add_child(light)
	DiverArt.box(scene, Vector3(0, -.07, 0), Vector3(7, .14, 3), Color("244765"))
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 1.38, -5.4)
	camera.look_at(Vector3(0, 1.05, 0))
	camera.fov = 40
	camera.current = true
	var cast: Array[DiverCharacter] = []
	for i in 2:
		var character = DiverCharacter.new()
		character.character = i
		scene.add_child(character)
		character.position.x = -1 if i == 0 else 1
		cast.append(character)
		var label = DiverArt.label(scene, Vector3(character.position.x, 2.22, 0), "MEGA MAN VOLNUTT" if i == 0 else "ROLL CASKETT", Color("ffdc68"), 28)
		label.pixel_size = .0017
	for pose in ["idle", "run", "aim", "dash", "jump", "hurt"]:
		for character in cast:
			character.current_clip = ""
			character.select_clip("idle" if pose == "aim" else pose, true)
			character.animator.advance(.15 if pose in ["hurt", "jump"] else .18)
			if pose == "aim":
				character.arm_weight = 1
				character.layer_aim(0, true, -.08, .3)
			else: character.update_mount()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/characters-%s.png" % pose)
	print("CHARACTER_GALLERY: both original models, six poses rendered")
	quit()
