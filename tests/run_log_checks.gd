extends SceneTree
var game: Node3D
var checks = 0
var failures = 0
var folder = "res://save/run-log-" + DiverAccount.uuid()
func _initialize() -> void: run.call_deferred()
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RUN_LOG_CHECK_FAILED: " + label)
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
	game.account.set_process(false)
	game.net.set_process(false)
	game.run_log.set_physics_process(false)
	game.settings.path = folder.path_join("settings.json")
	game.sound.settings_path = folder.path_join("audio.json")
	game.sound.muted = true
	game.start_run(40404)
	game.set_process(false)
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	var log = game.run_log
	game.run_id = "first-interrupted"
	log.observe(0)
	game.run_id = "measured"
	log.observe(0)
	verify(log.current.id == game.run_id and log.current.guardians.is_empty(), "Log starts lazily for the active dig")
	var boss: Node3D
	for enemy in game.enemies:
		if enemy.kind == 3: boss = enemy
	game.player.items = {"lens":2,"shell":1}
	boss.active = true
	game.run_time = 2
	log.observe(2)
	verify(log.current.guardians.size()==1 and log.current.guardians[0].build.items.lens==2, "First engaged guardian captures the build")
	game.player.items.lens=3
	game.player.hp -= 12.5
	game.run_time = 3
	log.observe(1)
	verify(log.current.life_lost==12.5 and log.current.guardians[0].life_lost==12.5, "Fractional observed Life lost recorded per fight and dig")
	verify(log.current.guardians[0].build.items.lens==2, "Captured build cannot change with later pickups")
	game.player.hp += 8
	log.observe(0)
	verify(log.current.life_lost==12.5, "Healing never subtracts losses")
	game.mode = "pause"
	log.observe(10)
	verify(log.current.guardians[0].seconds==3, "Solo pause excludes fight time")
	game.net.slot=1
	game.net.status="online"
	log.observe(2)
	verify(log.current.guardians[0].seconds==5, "Co-op overlay includes live fight time")
	game.net.status="connecting"
	game.player.hp -= 20
	log.observe(20)
	verify(log.current.life_lost==12.5 and log.current.guardians[0].seconds==5, "Reconnect gaps count neither Life loss nor seconds")
	game.net.status="online"
	log.observe(1)
	verify(log.current.life_lost==12.5 and log.current.guardians[0].partial, "Resync resets baseline and marks partial timings")
	game.net.slot=0
	game.net.status="offline"
	game.mode="play"
	game.guardian_dead=true
	log.observe(0)
	verify(log.current.guardians[0].defeated, "Guardian defeat closes the fight")
	var entry = game.choice_entry("relic","cache:1:3",1,3,["lens","spring","ember"])
	log.event("reroll",entry)
	log.event("pick",entry,"spring")
	verify(log.current.pick_count==1 and log.current.reroll_count==1 and log.current.events[1].item=="spring", "Picks and rerolls retained with offer identity")
	var restored = DiverRunLog.new()
	restored.path = log.path
	restored.load_notes()
	verify(restored.current.pick_count==1 and restored.current.guardians[0].seconds==6, "Active log survives reload")
	verify(not log.current.has("account_id") and not log.current.guardians[0].build.has("id") and not log.current.guardians[0].build.has("name"), "Log excludes account/player identifiers")
	var before_build = game.build_state()
	game.finish_run(false)
	verify(log.runs.size()==2 and log.runs[-1].finished and log.runs[0].interrupted and game.mode=="end", "End screen finalizes one device record")
	log.finish(false)
	verify(log.runs.size()==2, "Finish retries do not duplicate records")
	verify(not before_build.has("run_log") and not game.build_state().has("run_log"), "No log fields added to the network build")
	game.hud.activate("run_log")
	await refresh()
	verify(game.mode=="run_log" and game.hud.hits.any(func(hit): return hit.action=="log_guardian"), "End action opens guardian details")
	for small in [false,true]:
		game.settings.handheld_ui=small
		await refresh()
		for hit in game.hud.hits: verify(Rect2(Vector2.ZERO,game.hud.BASE).encloses(hit.rect), "Dig log controls remain on screen")
	game.hud.back()
	verify(game.mode=="end", "B/Esc restores end screen")
	for n in 25:
		game.run_id="retention-%d" % n
		game.run_recorded=false
		log.finish(false)
	verify(log.runs.size()==20 and log.runs[0].id=="retention-5" and log.runs[-1].id=="retention-24", "Retention keeps the latest 20 digs")
	restored.loaded=false
	restored.runs=[]
	restored.load_notes()
	verify(restored.runs.size()==20 and restored.current.is_empty(), "Completed log reload obeys retention and clears active slot")
	var bad = DiverRunLog.clean_record({"id":"safe","life_lost":NAN,"guardians":[{"depth":99,"seconds":-1,"build":{"items":{"lens":NAN},"name":"private","account_id":"private","power_picks":4}}],"events":[null,{"kind":"unknown"}]})
	verify(bad.life_lost==0 and bad.guardians[0].seconds==0 and bad.guardians[0].depth==3 and bad.events.is_empty(), "Malformed local notes are bounded and finite")
	verify(bad.guardians[0].build.power_picks==4 and not bad.guardians[0].build.has("account_id"), "Future Growth C fields retained without unknown data")
	var file=FileAccess.open(log.path,FileAccess.WRITE)
	file.store_string("broken json")
	file.close()
	restored.loaded=false
	restored.runs=[]
	restored.load_notes()
	verify(restored.runs.is_empty(), "Corrupt log does not prevent starting/ending a dig")
	# Exercise real choice hooks and automatic after-physics observation.
	game.run_id="real-hook-run"
	game.run_recorded=false
	game.mode="play"
	game.guardian_dead=false
	game.player.hp=80
	game.player.invincible=0
	log.observe(0)
	log.set_physics_process(true)
	game.player.hurt(12.5)
	await physics_frame
	await physics_frame
	verify(is_equal_approx(log.current.life_lost,12.5 / (1 + game.player.count("shell") * 0.18)), "Automatic observer captures real mitigated hurt")
	game.choice_kind="relic"
	game.choice_items=["lens","spring","ember"]
	game.choice_source=game.choice_entry("relic","relic:hook",1,-1,game.choice_items)
	game.mode="choice"
	game.choice_need_release=false
	game.choice_lock_until=0
	verify(game.reroll_choice() and log.current.reroll_count==1, "Actual reroll hook records one event")
	game.choose(0)
	verify(log.current.pick_count==1, "Actual choose hook records one event")
	log.set_physics_process(false)
	var safe_path=log.path
	var blocker=folder.path_join("blocked-log")
	file=FileAccess.open(blocker,FileAccess.WRITE)
	file.store_string("fixture")
	file.close()
	log.path=blocker.path_join("dig-log.json")
	game.finish_run(false)
	verify(game.run_recorded and game.mode=="end" and not log.storage_ok, "Log storage failure does not block normal dig completion")
	log.path=safe_path
	restored.free()
	print("RUN_LOG_CHECKS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
