extends SceneTree
var game: Node3D
var clock = 10.0
var checks = 0
var failures = 0
var folder = "res://save/info-trim-" + DiverAccount.uuid()
func _initialize() -> void: run.call_deferred()
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INFO_TRIM_CHECK_FAILED: " + label)
func packets() -> Array:
	return game.net.outbox.get(0,[]).filter(func(m): return int(m[0])==DiverNet.M_INFO)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game=load("res://main.tscn").instantiate()
	game.save_path=folder.path_join("guest.json")
	game.checkpoint_path=folder.path_join("run.dat")
	root.add_child(game)
	game.set_process(false)
	game.net.set_process(false)
	game.account.set_process(false)
	game.info_publisher.set_process(false)
	game.run_log.set_physics_process(false)
	game.info_publisher.clock=func(): return clock
	game.sound.settings_path=folder.path_join("audio.json")
	game.sound.muted=true
	game.start_run(40404,2,"trim-run")
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	game.net.slot=1
	game.net.host_slot=1
	game.net.player_id="trim-player"
	game.net.status="online"
	game.net.outbox={}
	game.send_info()
	verify(packets().size()==1, "Initial build publishes immediately")
	for n in 100:
		clock=10+(n+1)*0.01
		game.player.shot_count=n+1
		game.build_changed()
		verify(game.roster[game.net.player_id].shot_count==n+1, "Local recovery roster stays exact for every shot")
	verify(packets().size()==5, "100 shot updates in one second coalesce to four timed packets plus initial")
	verify(packets()[-1][1].shot_count==100, "Latest coalesced shot state sent")
	clock=11.01
	game.player.shot_count=101
	game.build_changed()
	verify(packets().size()==5 and not game.info_publisher.latest.is_empty(), "Final rapid update waits behind rate limit")
	clock=11.25
	game.info_publisher.flush_pending()
	verify(packets().size()==6 and packets()[-1][1].shot_count==101, "Trailing edge flushes even after firing stops")
	var old = packets().size()
	clock=12
	game.send_info()
	verify(packets().size()==old, "Unchanged builds suppressed")
	for field in ["items","milestones","pending","rerolls_left","downed","level","spec","power_picks","haste_picks"]:
		var b=game.build_state()
		match field:
			"items": b.items={"lens":1}
			"milestones": b.milestones=["bulwark"]
			"pending": b.pending=[game.choice_entry("relic","relay:1",1,-1,["lens","shell","ember"])]
			"rerolls_left": b.rerolls_left=0
			"downed": b.downed=true
			"level": b.level=2
			"spec": b.spec="storm"
			_: b[field]=1
		game.info_publisher.clear()
		game.info_publisher.submit(game.build_state())
		old=packets().size()
		game.info_publisher.submit(b)
		verify(packets().size()==old+1, "%s real build change bypasses coalescing" % field)
	game.info_publisher.clear()
	game.send_info()
	old=packets().size()
	game.send_info(true)
	verify(packets().size()==old+1, "Explicit resync sends unchanged build")
	game.player.shot_count += 1
	game.send_info()
	game.net.connection_epoch += 1
	clock += 1
	game.info_publisher.flush_pending()
	verify(packets().size()==old+1 and game.info_publisher.latest.is_empty(), "Stale pending update cannot cross connection epoch")
	game.send_info()
	verify(packets().size()==old+2, "New connection gets an immediate build")
	game.player.shot_count += 1
	game.send_info()
	old=packets().size()
	game.net.status="reconnecting"
	clock += 1
	game.info_publisher.flush_pending()
	verify(packets().size()==old and game.info_publisher.latest.is_empty(), "Disconnected flush clears pending state")
	game.net.status="online"
	game.send_info()
	old=packets().size()
	game.peer_entered(2,"new-player")
	verify(packets().size()==old+1, "Late/rejoining peer gets unchanged build immediately")
	var snapshot = packets()[-1][1].shot_count
	game.player.shot_count += 1
	game.send_info()
	verify(packets()[-1][1].shot_count==snapshot, "Queued packet snapshot does not alias live build")
	verify(packets()[-1].size()==2 and packets()[-1][0]==DiverNet.M_INFO and packets()[-1][1] is Dictionary, "Existing M_INFO wire shape preserved")
	print("INFO_TRIM_CHECKS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
