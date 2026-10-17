extends SceneTree

var game: Node3D
var hud: Control
var account: DiverAccount
var checks = 0
var failures = 0
var responses: Array = []
var sent: Array = []
var folder = "res://save/ui03-checks-" + DiverAccount.uuid()

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PURCHASE_CHECK_FAILED: " + label)

func refresh() -> void:
	game.hud.queue_redraw()
	await process_frame
	await process_frame

func settle() -> void:
	for n in 10: await process_frame
	await refresh()

func press(key: int) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		root.push_input(event, true)

func pad(button: int) -> void:
	for down in [true, false]:
		var event = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		root.push_input(event, true)

func click(hit: Dictionary) -> void:
	var point: Vector2 = hud.ui_offset + hit.rect.get_center() * hud.ui_scale
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event, true)

func node_index(id: String) -> int:
	for i in DiverProgression.NODES.size():
		if DiverProgression.NODES[i].id == id: return i
	return -1

func document(id: String, wallet: int, revision: int, owned: Array = []) -> Dictionary:
	var profile = DiverProgression.fresh()
	profile.zenny = wallet
	if not owned.is_empty(): profile.trees["0"] = owned.duplicate()
	return {"account": {"id": id, "name": "Review Test", "role": "player"}, "profile": profile, "revision": revision}

func fake(path: String, body: Variant, _method: int) -> Dictionary:
	sent.append({"path": path, "body": body.duplicate(true) if body is Dictionary else body})
	return responses.pop_front() if not responses.is_empty() else {"code": 503, "data": {}}

func review(id: String = "frame") -> void:
	game.mode = "workshop"
	await refresh()
	hud.activate("grid_node", node_index(id))
	await refresh()

func arm() -> void:
	hud.purchase_lock_until = 0
	await refresh()

func login(id: String, wallet: int, revision: int, owned: Array = []) -> void:
	account.receive_profile(200, document(id, wallet, revision, owned), PackedStringArray())
	await settle()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game = load("res://main.tscn").instantiate()
	game.save_path = folder.path_join("guest.json")
	game.checkpoint_path = folder.path_join("checkpoint.dat")
	root.add_child(game)
	game.set_process(false)
	game.sound.muted = true
	game.settings.path = folder.path_join("settings.json")
	hud = game.hud
	account = game.account
	account.set_process(false)
	account.cache_root = folder.path_join("accounts")
	account.transport = fake
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 400
	game.mode = "workshop"
	await refresh()
	var frame_hit: Dictionary = hud.hits.filter(func(h): return h.action == "grid_node" and h.value == 0)[0].duplicate()
	var move = InputEventMouseMotion.new()
	move.position = hud.ui_offset + frame_hit.rect.get_center() * hud.ui_scale
	move.relative = Vector2(12, 0)
	root.push_input(move, true)
	verify(game.meta.zenny == 400 and game.meta.trees.is_empty(), "Hover spends nothing")
	click(frame_hit)
	await refresh()
	verify(game.mode == "purchase_review" and game.meta.zenny == 400 and game.meta.trees.is_empty(), "Mouse selection opens review without buying")
	verify(hud.focused_action() == "purchase_cancel", "Cancel owns default focus")
	verify(hud.purchase_review.character == 0 and hud.purchase_review.node == "frame" and hud.purchase_review.cost == 100 and hud.purchase_review.wallet == 400, "Review freezes one digger/node/cost/wallet")
	verify(hud.hits.all(func(h): return h.action.begins_with("purchase_")), "Underlying Workshop has no interactive hit targets")
	hud.activate("purchase_confirm")
	verify(game.meta.zenny == 400, "Opening click cannot immediately confirm")
	click(frame_hit)
	verify(game.meta.zenny == 400, "Double click on the old node spends nothing")
	press(KEY_ENTER)
	await refresh()
	verify(game.mode == "workshop" and game.meta.zenny == 400, "Default confirm selects Cancel without spending")
	verify(hud.focused_action() == "grid_node" and hud.hits[hud.focus_index].value == 0, "Cancel restores the reviewed node")
	await review()
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "workshop" and game.meta.zenny == 400, "B/Esc cancels before submission")

	Input.action_press("nav_accept")
	await review()
	hud.purchase_lock_until = 0
	hud.activate("purchase_confirm")
	verify(game.meta.zenny == 400 and hud.purchase_need_release, "Held A cannot confirm the next layer")
	Input.action_release("nav_accept")
	await refresh()
	verify(not hud.purchase_need_release, "Releasing A arms a fresh confirmation")
	hud.focus_action("purchase_confirm")
	press(KEY_ENTER)
	await refresh()
	verify(hud.purchase_review.phase == "confirmed" and game.meta.zenny == 300 and DiverProgression.owned(game.meta, 0) == ["frame"], "Fresh Confirm buys the Guest circuit once")
	for n in 3: hud.activate("purchase_confirm")
	verify(game.meta.zenny == 300 and DiverProgression.owned(game.meta, 0) == ["frame"], "Repeated/held confirmation cannot charge twice")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	verify(saved.zenny == 300 and saved.trees["0"] == ["frame"], "Guest purchase is saved atomically")
	press(KEY_ESCAPE)
	await refresh()
	hud.activate("grid_node", 0)
	verify(game.mode == "workshop" and game.meta.zenny == 300, "Already-owned circuits never open another charged purchase")
	hud.activate("grid_node", node_index("spec_a"))
	verify(game.mode == "workshop" and hud.workshop_message.begins_with("Buy a linked"), "Unlinked circuits remain blocked")

	await review("mobility")
	game.meta.zenny = 20
	await arm()
	hud.activate("purchase_confirm")
	verify(hud.purchase_review.phase == "refused" and hud.purchase_review.note.contains("120 more") and game.meta.zenny == 20, "Insufficient funds at confirmation explain the exact shortfall")
	verify(not "mobility" in DiverProgression.owned(game.meta, 0), "Failed affordability does not grant ownership")
	hud.close_purchase_review()
	game.meta.zenny = 300
	await review("mobility")
	game.meta.revision += 1
	await arm()
	hud.confirm_purchase()
	verify(hud.purchase_review.phase == "refused" and hud.purchase_review.note.contains("progress changed") and game.meta.zenny == 300, "Changed Guest revision requires a new review")
	hud.close_purchase_review()
	await review("mobility")
	game.meta.trees["0"].append("mobility")
	await arm()
	hud.confirm_purchase()
	verify(game.meta.zenny == 300 and hud.purchase_review.note.contains("already fitted"), "Ownership acquired after review is not charged again")
	hud.close_purchase_review()
	await review("salvage")
	hud.select_workshop_character(1)
	await refresh()
	verify(game.mode == "workshop" and hud.purchase_review.is_empty() and hud.workshop_character == 1, "A digger switch cancels an unsubmitted review")
	await review()
	verify(hud.purchase_review.character == 1 and hud.purchase_review.node == "frame", "A different digger gets their own new review")
	hud.back()

	# Specializations stay an immediate free equip toggle, outside purchase review.
	hud.select_workshop_character(0)
	game.meta.trees["0"] = DiverProgression.NODES.map(func(n): return n.id)
	await refresh()
	hud.activate("grid_node", node_index("spec_a"))
	verify(game.mode == "workshop" and game.equipped_spec(0) == "spec_a" and game.meta.zenny == 300, "Owned specialization equips freely without purchase review")
	hud.activate("grid_node", node_index("spec_a"))
	verify(game.equipped_spec(0) == "" and game.meta.zenny == 300, "Owned specialization unequips freely")

	# A real write failure must restore the Guest wallet and tree.
	game.meta = DiverProgression.fresh()
	game.meta.zenny = 500
	var blocked = folder.path_join("blocked")
	var file = FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("intentional storage failure fixture")
	file.close()
	var normal_save = game.save_path
	game.save_path = blocked.path_join("guest.json")
	await review()
	await arm()
	hud.confirm_purchase()
	verify(hud.purchase_review.phase == "refused" and hud.purchase_review.note.contains("unchanged"), "Guest write failure reports failure, never Purchased")
	verify(game.meta.zenny == 500 and game.meta.trees.is_empty() and game.meta.revision == 0, "Guest write failure rolls back wallet, ownership and revision")
	game.save_path = normal_save
	hud.close_purchase_review()
	hud.select_workshop_character(3)
	await refresh()
	hud.focus_action("grid_node", 0)
	pad(JOY_BUTTON_A)
	await refresh()
	verify(game.mode == "purchase_review" and hud.focused_action() == "purchase_cancel", "Controller A opens review on Cancel")
	pad(JOY_BUTTON_A)
	await refresh()
	verify(game.mode == "workshop" and game.meta.zenny == 500, "Controller default A cancels without spending")
	pad(JOY_BUTTON_A)
	await refresh()
	await create_timer(0.25).timeout
	pad(JOY_BUTTON_DPAD_RIGHT)
	verify(hud.focused_action() == "purchase_confirm", "Controller D-pad reaches explicit Confirm")
	pad(JOY_BUTTON_A)
	await refresh()
	verify(game.meta.zenny == 400 and DiverProgression.owned(game.meta, 3) == ["frame"], "Controller fresh A confirms the selected digger once")
	pad(JOY_BUTTON_B)
	await refresh()
	verify(game.mode == "workshop" and hud.focused_action() == "grid_node", "Controller B closes the receipt and restores node focus")
	hud.select_workshop_character(0)

	# Real client outbox semantics, with controlled server replies.
	await login("acc_ui03_a", 500, 10)
	await review()
	await arm()
	responses.append({"code": 503, "data": {}})
	hud.confirm_purchase()
	var operation = account.outbox[0].body.duplicate(true)
	verify(hud.purchase_review.op_id == operation.op_id and operation.expected_revision == 10, "Review tracks the existing immutable operation/revision")
	await settle()
	verify(hud.purchase_review.phase == "pending" and account.status == "Offline" and account.outbox.size() == 1, "Lost response stays pending and retryable")
	verify(game.meta.zenny == 500 and game.meta.trees.is_empty(), "Pending purchase does not optimistically change the cloud wallet")
	var sent_before = sent.size()
	hud.confirm_purchase()
	hud.activate("purchase_confirm")
	verify(sent.size() == sent_before and account.outbox[0].body == operation, "Repeated Confirm cannot enqueue another operation")
	verify(hud.hits.all(func(h): return h.action != "purchase_cancel"), "A submitted purchase never advertises Cancel")
	press(KEY_ESCAPE)
	await refresh()
	verify(game.mode == "workshop" and hud.workshop_message.contains("does not cancel") and account.outbox[0].body == operation, "B closes the receipt without canceling the submitted operation")
	hud.select_workshop_character(1)
	await refresh()
	hud.activate("grid_node", 0)
	verify(game.mode == "workshop" and account.outbox[0].body.character == 0, "Another digger cannot inherit or resubmit the pending node")
	hud.select_workshop_character(0)
	await review()
	verify(hud.purchase_review.op_id == operation.op_id and hud.focused_action() == "purchase_close", "Reselecting the pending node reopens its receipt safely")
	responses.append({"code": 200, "data": document("acc_ui03_a", 500, 10)})
	responses.append({"code": 200, "data": document("acc_ui03_a", 400, 11, ["frame"])})
	hud.activate("purchase_retry")
	await settle()
	verify(account.outbox.is_empty() and game.meta.zenny == 400 and hud.purchase_review.phase == "confirmed", "Retry displays real server confirmation and one deduction")
	var purchases = sent.filter(func(r): return r.path == "/api/v1/purchases")
	verify(purchases.size() == 2 and purchases[0].body == purchases[1].body, "Lost-response retry uses exactly the same op_id/body")
	verify("frame" in DiverProgression.owned(game.meta, 0), "Confirmed ownership remains on the original digger")
	hud.close_purchase_review()

	await review("mobility")
	await login("acc_ui03_a", 320, 12, ["frame"])
	await arm()
	var requests_before = sent.size()
	hud.confirm_purchase()
	verify(hud.purchase_review.phase == "refused" and sent.size() == requests_before and game.meta.zenny == 320, "A profile revision change before Confirm cannot submit a stale purchase")
	hud.close_purchase_review()
	await review("mobility")
	await arm()
	responses.append({"code": 409, "data": {"error": {"code": "revision_conflict"}, "profile": document("acc_ui03_a", 10, 13, ["frame"]).profile, "revision": 13}})
	hud.confirm_purchase()
	await settle()
	verify(hud.purchase_review.phase == "refused" and hud.purchase_review.note.contains("another device"), "Server conflict shows the actual refusal, not Purchased")
	verify(account.outbox.is_empty() and game.meta.zenny == 10 and DiverProgression.owned(game.meta, 0) == ["frame"], "Conflict adopts the real wallet and ownership, without retrying stale spend")
	hud.close_purchase_review()

	await login("acc_ui03_a", 500, 14, ["frame"])
	await review("mobility")
	await arm()
	responses.append({"code": 401, "data": {"error": {"code": "unauthorized"}}})
	hud.confirm_purchase()
	await settle()
	operation = account.outbox[0].body.duplicate(true)
	verify(hud.purchase_review.phase == "pending" and account.status == "Sign-in needed", "Expired authentication retains the pending operation")
	verify(hud.hits.all(func(h): return h.action != "purchase_cancel" and h.action != "purchase_retry"), "Expired auth does not offer cancellation or unauthenticated retries")
	account.generation += 1
	responses.append({"code": 503, "data": {}})
	await login("acc_ui03_a", 500, 14, ["frame"])
	verify(game.mode == "purchase_review" and hud.purchase_review.op_id == operation.op_id and account.outbox[0].body == operation, "Same-account authentication renewal keeps the original pending receipt and operation")
	account.sign_out()
	await login("acc_ui03_b", 700, 0)
	await refresh()
	verify(game.mode == "workshop" and hud.purchase_review.is_empty() and game.meta.zenny == 700, "Account switching clears the old account's receipt")
	var stored = JSON.parse_string(FileAccess.get_file_as_string(account.cache_root.path_join("acc_ui03_a/outbox.json")))
	verify(stored.size() == 1 and stored[0].body.op_id == operation.op_id, "The original account retains its durable operation after switching")

	# All review buttons fit and keep Cancel as the safe default at small sizes.
	for size in [Vector2i(1440, 900), Vector2i(1280, 720), Vector2i(960, 600), Vector2i(960, 540)]:
		root.size = size
		await review()
		verify(hud.focused_action() == "purchase_cancel", "Cancel defaults at %s" % size)
		for hit in hud.hits:
			verify(Rect2(Vector2.ZERO, hud.BASE).encloses(hit.rect), "Review action remains on screen at %s" % size)
		hud.close_purchase_review()
	print("PURCHASE_REVIEW_CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
