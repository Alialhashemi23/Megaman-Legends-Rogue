extends SceneTree
var game: Node3D
var folder = "res://save/overnight-captures"
func _initialize() -> void: run.call_deferred()
func capture(label: String) -> void:
	for n in 4:
		game.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	print("CAPTURE: " + label)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game = load("res://main.tscn").instantiate()
	game.save_path = folder.path_join("guest.json")
	game.checkpoint_path = folder.path_join("run.dat")
	root.add_child(game)
	game.set_process(false)
	game.account.set_process(false)
	game.net.set_process(false)
	game.sound.muted = true
	game.sound.settings_path = folder.path_join("audio.json")
	game.settings.path = folder.path_join("settings.json")
	for small in [false,true]:
		root.size = Vector2i(960,540) if small else Vector2i(1440,900)
		game.settings.handheld_ui = small
		game.mode = "options"
		await capture("options-small" if small else "options-desktop")
		game.mode = "controller_test"
		await capture("controller-small" if small else "controller-desktop")
		game.hud.controller_sample_at = Time.get_ticks_msec() + 60000
		game.hud.controller_device = 0
		game.hud.controller_snapshot = {"devices":[0],"connected":true,"name":"Example Standard Pad","guid":"030000005e0400008e02000000000000","known":true,"axes":[-0.5,0.25,0.0,0.75,-1.0,0.5],"buttons":[1,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"browser":[{"index":0,"mapping":"standard","name":"Example Standard Pad","axes":[-0.5,0.25,0.0,0.75],"buttons":[1,0,0,0,1,0,0.25,0.5,0,0,0,0,0,0,0,0]}]}
		await capture("controller-example-small" if small else "controller-example-desktop")
	game.hud.controller_snapshot = {}
	game.start_run(40404)
	game.set_process(false)
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	game.mode = "choice"
	game.choice_kind = "relic"
	game.choice_source = game.choice_entry("relic","cache:1:3",1,3,["lens","spring","ember"])
	game.choice_items = ["lens","spring","ember"]
	game.choice_opened_at = Time.get_ticks_msec() - 1000
	game.choice_lock_until = 0
	game.choice_need_release = false
	game.message_time = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await capture("reroll-small")
	root.size = Vector2i(1440,900)
	game.settings.handheld_ui = false
	await capture("reroll-desktop")
	game.run_log.observe(0)
	var sample_build = game.build_state()
	sample_build.items = {"lens":3,"spring":2,"shell":1,"ember":2,"coil":1,"frost":1,"echo":1,"boots":1}
	game.run_log.current.guardians = [{"depth":1,"seconds":38.5,"life_lost":25.5,"defeated":true,"partial":false,"build":DiverRunLog.clean_build(sample_build)}]
	game.run_log.current.life_lost = 43.0
	game.run_log.current.events = [{"kind":"pick","item":"lens","depth":1,"cards":[]},{"kind":"reroll","item":"","depth":1,"cards":["spring","ember","coil"]}]
	game.run_log.current.pick_count = 6
	game.run_log.current.reroll_count = 1
	game.finish_run(false)
	await capture("end-desktop")
	game.hud.activate("run_log")
	await capture("log-desktop")
	root.size = Vector2i(960,540)
	game.settings.handheld_ui = true
	await capture("log-small")
	root.size = Vector2i(1440,900)
	game.hud.visible = false
	var display = TextureRect.new()
	display.texture = load("res://assets/ui/parts_atlas.svg")
	display.position = Vector2(208,130)
	display.size = Vector2(1024,640)
	root.add_child(display)
	await capture("atlas")
	quit()
