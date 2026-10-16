extends SceneTree

# UI-01 review gallery. Only fixture progress/settings; no network or real saves.
var game: Node3D
var output = "res://save/ui01-captures"

func _initialize() -> void:
	run.call_deferred()

func capture(label: String) -> void:
	for i in 3:
		game.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://main.tscn").instantiate()
	game.smoke_test = true
	game.save_path = "res://save/ui01-preview-archive.json"
	game.checkpoint_path = "res://save/ui01-preview-run.dat"
	root.add_child(game)
	game.set_process(false)
	game.account.set_process(false)
	game.settings.path = "res://save/ui01-preview-settings.json"
	game.sound.muted = true
	game.meta = DiverProgression.fresh()
	if "--baseline" in OS.get_cmdline_user_args():
		for size in [Vector2i(1440, 900), Vector2i(960, 540)]:
			root.size = size
			await capture("before-title-guest-%dx%d" % [size.x, size.y])
		print("UI_ENTRY_BASELINE_SAVED")
		quit()
		return
	for size in [Vector2i(1440, 900), Vector2i(960, 600), Vector2i(960, 540)]:
		root.size = size
		var suffix = "%dx%d" % [size.x, size.y]
		game.show_title()
		await capture("title-guest-" + suffix)
		game.hud.activate("solo")
		await capture("solo-mega-" + suffix)
		game.meta.trees["1"] = DiverProgression.NODES.map(func(node): return node.id)
		game.settings.specs["1"] = "spec_b"
		game.hud.select_character(1)
		await capture("solo-roll-specialization-" + suffix)
		game.hud.confirm()
		await capture("solo-start-" + suffix)
		for character in [2, 3]:
			game.hud.select_character(character)
			await capture("solo-%s-" % DiverCharacter.IDS[character] + suffix)
		game.hud.select_character(1)
		game.hud.back()
		game.saved_dig = {"online": true, "lobby_code": "TEST", "world": {"depth": 2, "run_time": 618}}
		game.profile_source = "account"
		game.account.state = "signed_in"
		game.account.status = "Synced"
		game.account.identity = {"id": "fixture", "name": "GALOSENGEN / preview digger"}
		await capture("title-account-rejoin-" + suffix)
		game.profile_source = "guest"
		game.account.identity = {}
		game.account.state = "guest"
		game.saved_dig = {}
		game.hud.select_character(0)
	print("UI_ENTRY_GALLERY_SAVED: " + ProjectSettings.globalize_path(output))
	quit()
