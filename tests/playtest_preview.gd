extends SceneTree

var game: Node3D
const OUT = "res://save/playtest-captures"

func _initialize() -> void:
	run.call_deferred()

func shot(name: String) -> void:
	game.hud.queue_redraw()
	for n in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = "res://save/pt-preview.json"
	game.checkpoint_path = "res://save/pt-preview.dat"
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	root.size = Vector2i(1440, 900)
	game.start_run(31336)
	game.message_time = 0
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.1, 4)
	game.player.camera.position = Vector3(3.8, 3.2, 7)
	game.player.camera.look_at(Vector3(0, 0.8, -1))
	var target = game.spawn_enemy(Vector3(0, 0.1, -1), 0, 0)
	target.set_physics_process(false)
	game.flare_patch(target.position, 12, 1, game.player)
	for age in [0.18, 0.65, 1.45, 1.88]:
		for patch in game.flare_patches: patch.node.animate(age)
		await shot("fire-%.2f" % age)
	game.settings.handheld_ui = true
	game.mode = "workshop"
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 500
	await shot("workshop")
	game.hud.buy_grid_node(0)
	await shot("workshop-selected")
	game.hud.purchase_lock_until = 0
	game.hud.confirm_purchase()
	await shot("workshop-purchased")
	game.mode = "end"
	await shot("results")
	game.mode = "solo_prep"
	await shot("solo-carousel")
	print("PLAYTEST_CAPTURES_PASS: " + ProjectSettings.globalize_path(OUT))
	quit()
