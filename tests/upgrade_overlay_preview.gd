extends SceneTree

# Renders the UI-02 upgrade overlay over a live dig view into res://save/ui02-captures/
# (ignored). Needs a real renderer, so run it windowed, not --headless.

var game: Node3D
const OUT = "res://save/ui02-captures"

func _initialize() -> void:
	run.call_deferred()

func shot(filename: String, opened_ago_ms: int = 1000) -> void:
	game.choice_opened_at = Time.get_ticks_msec() - opened_ago_ms
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, filename])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game = load("res://main.tscn").instantiate()
	game.save_path = "res://save/overlay-preview-archive.json"
	game.checkpoint_path = "res://save/overlay-preview-run.dat"
	root.add_child(game)
	game.settings.path = "res://save/overlay-preview-settings.json"
	game.account.cache_root = "res://save/overlay-preview-accounts"
	game.set_process(false)
	game.smoke_test = true
	game.sound.muted = true
	root.size = Vector2i(1440, 900)
	game.start_run(49381)
	var p: DiverPlayer = game.player
	for id in ["lens", "spring", "coil"]: p.items[id] = 2 if id == "lens" else 1
	p.hp = 82
	p.level = 4
	p.xp = 9
	p.xp_required = 34
	game.scrap = 412
	game.run_time = 204
	game.message_time = 0
	# Look into the first chamber so the dimmed view has ruins and a robot in it.
	p.yaw = PI
	p.pitch = -0.12
	p.update_camera(1)
	await process_frame
	await shot("00-play-before")
	game.open_relic_choice({"depth": 1, "cache": 0})
	await shot("01-solo-part")
	game.hud.choice_preview = 1
	await shot("01b-solo-part-second-card")
	await shot("02-solo-part-fadein", 60)
	game.close_choice()
	await shot("03-play-after-close")
	game.pending_choices.clear()
	game.open_level_choice()
	await shot("04-solo-level-flash", 120)
	await shot("05-solo-level")
	game.close_choice()
	game.pending_choices.clear()
	game.open_relic_choice({"kind": "milestone", "depth": 1, "cache": -1, "items": game.milestone_offer(1, p)})
	await shot("06-solo-milestone")
	game.close_choice()
	game.pending_choices.clear()

	# Co-op guest: two teammates on the team panel, four picks queued, one taken.
	game.finish_run(false)
	game.net.slot = 2
	game.net.host_slot = 1
	game.net.status = "online"
	game.net.lobby = {"players": [{"slot": 1, "name": "Volnutt", "id": "h"}, {"slot": 2, "name": "Roll", "id": "m"}, {"slot": 3, "name": "Tron", "id": "t"}]}
	game.selected_character = 1
	game.start_run(4242, 3, "overlay-preview")
	p = game.player
	for slot in [1, 3]:
		var mate = game.create_remote_player(slot)
		mate.global_position = p.global_position + Vector3(-1.5 if slot == 1 else 1.5, 0, -2.5)
	game.remote_players[3].downed = true
	p.items = {"ember": 2, "frost": 1}
	p.yaw = PI
	p.update_camera(1)
	game.net_message(1, [DiverNet.M_CHOICE, 1, 0, 1])
	p.gain_xp(p.xp_required)
	game.net_message(1, [DiverNet.M_CHOICE, 1, 1, 2])
	game.grant_milestone(1)
	game.message_time = 0
	await shot("07-coop-play-waiting")
	game.game_action("parts")
	game.choose(0)
	game.hud.choice_preview = 0
	await shot("08-coop-pick2of4-level")
	game.choose(1)
	await shot("09-coop-pick3of4-part")
	for size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = size
		await shot("10-coop-%dx%d" % [size.x, size.y])
	root.size = Vector2i(1440, 900)
	game.hud.back()
	game.net.slot = 0
	game.net.status = "offline"
	game.net.lobby = {}
	for path in [game.save_path, game.checkpoint_path, game.checkpoint_path + ".tmp", game.settings.path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("UI02_PREVIEW_SAVED")
	quit()
