extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for index in 2:
		var viewport = SubViewport.new()
		viewport.size = Vector2i(256, 288)
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var character = DiverCharacter.new()
		character.character = index
		viewport.add_child(character)
		var camera = Camera3D.new()
		viewport.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = .90
		camera.position = Vector3(.10, 1.55 if index == 0 else 1.50, -3)
		camera.look_at(Vector3(0, camera.position.y, 0))
		camera.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://assets/ui/%s_portrait.png" % ["volnutt", "roll"][index])
		viewport.queue_free()
		await process_frame
	print("CHARACTER_PORTRAITS: rendered from original skinned meshes")
	quit()
