extends SceneTree

# Contact sheets of every digger's dash (or any) clips: one row per moment in the clip,
# rendered from the side and from behind (the gameplay view).
# Usage: --script tests/dash_preview.gd -- <output folder> [clip,clip,...]

const TIMES = [0.0, 0.04, 0.09, 0.15, 0.21, 0.27, 0.33]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var clips = (args[1] if args.size() > 1 else "dash,dash_back,dash_left,dash_right").split(",")
	root.size = Vector2i(1280, 360)
	var scene = Node3D.new()
	root.add_child(scene)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("14263e")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c6d8eb")
	scene.add_child(env)
	DiverArt.box(scene, Vector3(0, -.07, 0), Vector3(14, .14, 3), Color("244765"))
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.fov = 34
	camera.current = true
	var cast: Array[DiverCharacter] = []
	for i in DiverCharacter.COUNT:
		var character = DiverCharacter.new()
		character.character = i
		scene.add_child(character)
		cast.append(character)
	var label = DiverArt.label(scene, Vector3.ZERO, "", Color("ffdc68"), 40)
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	for clip in clips:
		if not cast[0].animator.has_animation(clip):
			push_warning("missing clip " + clip)
			continue
		for view in ["side", "back"]:
			var sheet = Image.create(root.size.x, root.size.y * TIMES.size(), false, Image.FORMAT_RGBA8)
			# Dashes use fixed moments; other clips are sampled evenly over their length.
			var length = cast[0].animator.get_animation(clip).length
			var times = TIMES if clip.begins_with("dash") else range(TIMES.size()).map(func(i): return length * i / TIMES.size())
			for row in times.size():
				for i in cast.size():
					var character = cast[i]
					# Diggers face -Z. Side view: a row along Z seen from -X (facing left on screen).
					# Back view: a row across X seen from behind, like the gameplay camera.
					character.position = Vector3(0, 0, 4.5 - i * 3.0) if view == "side" else Vector3(-4.5 + i * 3.0, 0, 0)
					character.current_clip = ""
					character.select_clip(clip, true)
					character.animator.seek(minf(times[row], character.animator.current_animation_length), true)
					character.update_mount()
				camera.position = Vector3(-5.6, 1.0, 0) if view == "side" else Vector3(0, 1.9, 5.6)
				camera.look_at(Vector3(0, 0.9, 0))
				label.position = camera.position + (Vector3(0, 0.9, 0) - camera.position).normalized() * 3.0 + Vector3(0, 0.62, 0)
				label.text = "%s  %s  t=%.2f" % [clip, view, times[row]]
				await process_frame
				await RenderingServer.frame_post_draw
				var frame = root.get_texture().get_image()
				frame.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, root.size), Vector2i(0, row * root.size.y))
			sheet.save_png(out.path_join("%s-%s.png" % [clip, view]))
	print("DASH_PREVIEW: ", clips, " -> ", out)
	quit()
