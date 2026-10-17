extends SceneTree

var game: Node3D
var checks = 0
var failures = 0
var folder = "res://save/ui04-" + DiverAccount.uuid()

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HANDHELD_CHECK_FAILED: " + label)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game = load("res://main.tscn").instantiate()
	game.save_path = folder.path_join("guest.json")
	game.checkpoint_path = folder.path_join("run.dat")
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	game.account.set_process(false)
	game.account.cache_root = folder.path_join("accounts")
	game.settings.path = folder.path_join("device-a.json")
	var s = game.settings
	var hud = game.hud
	verify(not s.handheld_ui and not s.large_minimap and not s.close_camera and s.fov == 67, "Desktop defaults preserve UI, map and camera")
	var original_selection = game.net.current_selection().duplicate(true)
	for id in ["handheld_ui", "large_minimap", "close_camera"]:
		hud.activate_option(hud.OPTIONS.find(id))
	verify(s.handheld_ui and s.large_minimap and s.close_camera, "Every preference is independently selectable")
	hud.activate_option(hud.OPTIONS.find("handheld_ui"))
	verify(not s.handheld_ui and s.large_minimap and s.close_camera, "UI preset does not force map size or camera framing")
	hud.activate_option(hud.OPTIONS.find("handheld_ui"))
	verify(s.fov == 67 and not s.map_zoom, "Framing and map size do not change FOV or map follow")
	verify(game.net.current_selection() == original_selection, "Preferences do not invalidate a ready loadout")
	verify(hud.readable_size(24) > 24 and hud.readable_size(46) == 46, "Small copy grows; large headings retain their size")
	var device_a = DiverSettings.new()
	device_a.path = s.path
	device_a.reset_bindings()
	device_a.load_settings()
	verify(device_a.handheld_ui and device_a.large_minimap and device_a.close_camera, "Preferences survive device settings reload")
	var device_b = DiverSettings.new()
	device_b.path = folder.path_join("device-b.json")
	device_b.reset_bindings()
	device_b.load_settings()
	verify(not device_b.handheld_ui and not device_b.large_minimap and not device_b.close_camera, "Another device keeps independent defaults")
	var old = FileAccess.open(folder.path_join("old.json"), FileAccess.WRITE)
	old.store_string('{"fov":73,"map_zoom":true}')
	old.close()
	device_b.path = folder.path_join("old.json")
	device_b.load_settings()
	verify(device_b.fov == 73 and device_b.map_zoom and not device_b.close_camera and not device_b.handheld_ui, "Old settings preserve existing preferences without forced migration")
	for mode in ["title", "solo_prep", "options", "account", "workshop"]:
		game.mode = mode
		await refresh()
		for hit in hud.hits:
			if hit.rect.has_area(): verify(Rect2(Vector2.ZERO, hud.BASE).encloses(hit.rect), mode + ": action remains inside the layout")
		if mode == "options":
			verify(hud.hits.size() == hud.OPTIONS.size(), "All Options rows remain reachable")
			for i in hud.hits.size():
				for j in range(i + 1, hud.hits.size()): verify(not hud.hits[i].rect.intersects(hud.hits[j].rect), "Options rows do not overlap")
		if mode == "workshop": verify(hud.GRID_RECT.position.x == 454, "Handheld Workshop gives the description panel more room")
	game.meta.zenny = 500
	hud.buy_grid_node(0)
	await refresh()
	verify(game.mode == "purchase_review" and hud.focused_action() == "purchase_cancel", "Handheld purchase keeps Cancel first")
	hud.back()
	await refresh()
	verify(game.mode == "workshop" and hud.focused_action() == "grid_node" and game.meta.zenny == 500, "Back restores the selected node without spending")
	game.start_run(40404)
	game.set_process(false)
	game.player.set_physics_process(false)
	await physics_frame
	var player = game.player
	var target = game.spawn_enemy(player.position + Vector3(0, 0, -6), 0, 0)
	player.lock_target = target
	var standard_distance = 0.0
	for close in [false, true]:
		s.close_camera = close
		player.update_camera(1.0)
		var camera_distance = player.camera.global_position.distance_to(player.global_position + Vector3(0, 1.55, 0))
		if not close: standard_distance = camera_distance
		else: verify(camera_distance < standard_distance - 0.5, "Close framing actually moves nearer in open space")
		var aim = (target.global_position + Vector3.UP * 1.15 - player.camera.global_position).normalized()
		verify((-player.camera.global_basis.z).dot(aim) > 0.999, "Lock-on points at the target in either framing")
		verify(is_equal_approx(player.camera.fov, 67), "Framing keeps default FOV")
		verify(player.camera.global_position.is_finite(), "Camera remains finite after collision resolution")
	player.lock_target = null
	# Put a wall between pivot and both requested camera positions.
	var pivot = player.global_position + Vector3(0, 1.55, 0)
	var wall = StaticBody3D.new()
	var shape_node = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(12, 12, 0.5)
	shape_node.shape = shape
	wall.add_child(shape_node)
	game.add_child(wall)
	wall.global_position = pivot + Vector3(0, 0, 2)
	player.yaw = 0
	player.pitch = 0
	await physics_frame
	for close in [false, true]:
		s.close_camera = close
		player.update_camera(1.0)
		verify(player.camera.global_position.z < wall.global_position.z, "Both framings stay in front of an intervening wall")
	device_a.free()
	device_b.free()
	print("HANDHELD_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
