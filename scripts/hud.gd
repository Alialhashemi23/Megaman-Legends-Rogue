extends Control

# Console-style windows, shaded lettering, and painted equipment icons.
const BASE = Vector2(1440, 900)
const INK = Color("101b48")
const BLUE = Color("16357f")
const PANEL = Color("12336e")
const SELECT = Color("285fb7")
const EDGE = Color("b8d7ec")
const WHITE = Color("fff9df")
const MUTED = Color("adc8e8")
const CYAN = Color("7ad6ef")
const YELLOW = Color("ffdc68")
const GREEN = Color("9cde70")
const ORANGE = Color("ff9565")
const ICONS = {"lens": 0, "spring": 1, "heart": 2, "boots": 3, "shell": 4, "moss": 5, "ember": 6, "coil": 7, "prism": 8, "echo": 9, "split": 10, "frost": 11, "clover": 12, "pulse": 13, "needle": 14, "siege": 15, "scrap": 16, "xp": 17, "map": 18, "lock": 19, "dash": 20, "cache": 21, "wrench": 22, "exit": 23, "life": 24, "settings": 25, "save": 26, "cursor": 27, "warning": 28, "record": 29, "eye": 30, "unknown": 31, "refractor": 32, "flare": 33, "shatter": 34, "overclock": 35}
const DESCRIPTIONS = {
    "lens": "Raises buster power by 16% for each lens fitted.",
    "spring": "Raises fire rate by 14% for each spring fitted.",
    "heart": "Adds 20 maximum Life and restores 20 Life when fitted.",
    "boots": "Run 9% faster per pair. Your dash also recharges sooner.",
    "shell": "Reduces incoming damage. Fitting more plates improves protection.",
    "moss": "Restore 1.5 Life per stack whenever you defeat a machine.",
    "ember": "Buster hits cause a three-second burn. Each stack adds 2 burn damage per tick.",
    "coil": "Adds an 18% lightning chance per stack. Extra coils reach more machines.",
    "prism": "Adds an 8% critical chance per stack. Critical hits deal double damage.",
    "echo": "Adds a 12% extra-shot chance per stack. Echo shots deal 70% damage.",
    "split": "Adds two side shots. Extra antennas raise their damage.",
    "frost": "Dashing slows nearby machines. Extra flywheels extend the effect.",
    "clover": "Adds 2.5 percentage points to the chance of finding a part on a machine."
}
const TYPES = {"lens": "POWER", "spring": "RAPID", "heart": "LIFE", "boots": "MOBILITY", "shell": "ARMOR", "moss": "REPAIR", "ember": "FIRE", "coil": "ELECTRIC", "prism": "CRITICAL", "echo": "EXTRA SHOT", "split": "SPREAD", "frost": "SLOW", "clover": "SALVAGE"}
var game: Node3D
var font = preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
var heading = preload("res://assets/fonts/RussoOne-Regular.ttf")
var atlas = preload("res://assets/ui/parts_atlas.svg")
var portraits: Array[Texture2D] = []
var pattern = preload("res://assets/ui/menu_pattern.svg")
var hits: Array = []
var pointer = Vector2(-100, -100)
var pointer_travel = 0.0
var ui_scale = 1.0
var ui_offset = Vector2.ZERO
var focus_index = 0
var selected_item = 0
var list_scroll = 0
var choice_preview = 0
var previous_mode = ""
# Keep semantic targets across page changes and account/roster redraws.
var page_focus: Dictionary = {}
var pending_focus: Dictionary = {}
var accept_held = false
var back_held = false
var reroll_held = false
var name_edit: LineEdit
var code_edit: LineEdit
var server_edit: LineEdit
var pass_edit: LineEdit
var new_pass_edit: LineEdit
var chat_edit: LineEdit
var copied_time = 0.0
# Destructive buttons need a second click within a few seconds.
const CONFIRM = ["leave_online", "leave_dig", "abandon", "kick", "discard", "start_new", "give_up", "reset_controls", "takeover", "clear_session"]
# Options page rows: sound, display, then controls.
const OPTIONS = ["master", "music", "effects", "ambience", "mute", "fullscreen", "camera", "fov", "mouse", "look", "invert", "vibration", "controls", "map_zoom", "handheld_ui", "large_minimap", "close_camera", "controller_test", "back"]
const MENU_MODES = ["title", "solo_prep", "pause", "options", "controls", "controller_test", "choice", "inventory", "archive", "end", "online", "lobby", "launch_preparing", "workshop", "purchase_review", "save_codes", "account", "android_update", "credits"]
var credits_lines: PackedStringArray = []
var credits_page = 0
var options_return = "title"
var controller_device = -1
var controller_raw_page = 0
var controller_snapshot: Dictionary = {}
var controller_sample_at = 0
var controller_last_button = "No button event yet"
var workshop_return = "title"
var workshop_character = 0
var workshop_message = ""
var workshop_focus_pending = false
# One reviewed node and its existing purchase operation; never a second outbox.
var purchase_review: Dictionary = {}
var purchase_need_release = false
var purchase_lock_until = 0
const PURCHASE_ARM_MS = 200
# Workshop grid view: centre in grid cells, zoom step, mouse-drag state.
var GRID_RECT = Rect2(394, 366, 982, 414)
const GRID_CELL = Vector2(96, 38)
const GRID_ZOOMS = [0.8, 1.0, 1.35]
var grid_center = Vector2(0, 2.4)
var grid_zoom_step = 1
var grid_dragging = false
var save_edit: LineEdit
# In-game sign-in modal fields; `underlay` draws the title behind it, inert.
var auth_name_edit: LineEdit
var auth_email_edit: LineEdit
var auth_password_edit: LineEdit
var auth_code_edit: LineEdit
var auth_backup = false
var underlay = false
var save_message = "Export a code to keep a backup outside this browser."
var pending_import: Dictionary = {}
var waiting_for_paste = false
# Rebinding: {"id": action, "column": "kb"/"pad", "time": seconds left}.
var listening: Dictionary = {}
var confirming = ""
var confirm_time = 0.0

func _ready() -> void:
    game.account.purchase_settled.connect(purchase_settled)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    for id in DiverCharacter.IDS: portraits.append(load("res://assets/ui/%s_portrait.png" % id))
    save_edit = make_field(32768, "Paste a Relic Diver save code here")
    auth_name_edit = make_field(16, "Digger name")
    auth_email_edit = make_field(254, "Email")
    auth_email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
    auth_password_edit = make_field(128, "Password")
    auth_password_edit.secret = true
    auth_password_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
    auth_code_edit = make_field(16, "123456")
    for field in [auth_name_edit, auth_email_edit, auth_password_edit, auth_code_edit]:
        field.text_submitted.connect(func(_text): auth_field_submitted(field))
        field.gui_input.connect(func(event):
            if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
                get_viewport().gui_release_focus()
                field.accept_event())
    name_edit = make_field(16, "Your digger name")
    name_edit.text_submitted.connect(func(_text): commit_name(); get_viewport().gui_release_focus())
    name_edit.focus_exited.connect(commit_name)
    code_edit = make_field(12, "CODE")
    code_edit.text_submitted.connect(func(_text): activate("join_code"))
    server_edit = make_field(120, "wss://your-domain/ws")
    server_edit.text_submitted.connect(func(_text): commit_server(); get_viewport().gui_release_focus())
    server_edit.focus_exited.connect(commit_server)
    pass_edit = make_field(24, "Password")
    pass_edit.secret = true
    pass_edit.text_submitted.connect(func(_text): activate("join_code"))
    new_pass_edit = make_field(24, "No password")
    chat_edit = make_field(120, "Say something to your team…")
    chat_edit.text_submitted.connect(send_chat)
    chat_edit.gui_input.connect(func(event):
        if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
            close_chat()
            chat_edit.accept_event())
    chat_edit.focus_exited.connect(func(): if game.mode == "play": game.chat_open = false)

func send_chat(text: String) -> void:
    game.say(text)
    chat_edit.text = ""
    if game.mode == "play": close_chat()

func close_chat() -> void:
    game.chat_open = false
    chat_edit.text = ""
    get_viewport().gui_release_focus()

# Text fields styled like the cobalt menu windows.
func make_field(max_length: int, hint: String) -> LineEdit:
    var field = LineEdit.new()
    field.max_length = max_length
    field.placeholder_text = hint
    field.visible = false
    field.mouse_filter = Control.MOUSE_FILTER_STOP
    field.add_theme_font_override("font", font)
    field.add_theme_color_override("font_color", WHITE)
    field.add_theme_color_override("font_placeholder_color", Color(0.68, 0.78, 0.91, 0.6))
    field.add_theme_color_override("caret_color", YELLOW)
    field.add_theme_color_override("selection_color", Color(0.16, 0.37, 0.72))
    for state in ["normal", "focus", "read_only"]:
        var style = StyleBoxFlat.new()
        style.bg_color = INK
        style.border_color = YELLOW if state == "focus" else EDGE
        style.set_border_width_all(2)
        style.set_corner_radius_all(4)
        style.content_margin_left = 12
        style.content_margin_right = 12
        field.add_theme_stylebox_override(state, style)
    add_child(field)
    return field

func place_field(field: LineEdit, pos: Vector2, size: Vector2, font_size: int = 24) -> void:
    field.visible = true
    field.position = ui_offset + pos * ui_scale
    field.size = size * ui_scale
    field.add_theme_font_size_override("font_size", maxi(8, int(readable_size(font_size) * ui_scale)))

func editing() -> bool:
    return get_viewport().gui_get_focus_owner() is LineEdit

func commit_name() -> void:
    var value = name_edit.text.strip_edges()
    if value != "" and value != game.net.player_name:
        game.net.rename(value)
        if game.mode == "lobby": game.send_info()

func commit_server() -> void:
    var value = server_edit.text.strip_edges()
    if value == "" or value == game.net.server_url: return
    if game.profile_source == "account" or game.account.state in ["signing_in", "restoring"]:
        game.net.error_text = "Sign out of the account before changing servers."
        server_edit.text = game.net.server_url
        return
    game.net.disconnect_server()
    game.net.server_url = value
    game.net.save_profile()
    game.net.connect_server()

func portrait() -> Texture2D:
    return portraits[game.player.character]

func select_character(index: int) -> void:
    if game.net.active() and game.net.ready_phase() != "idle": return
    game.selected_character = wrapi(index, 0, DiverCharacter.COUNT)
    game.player.set_character(game.selected_character)
    game.player.visual.preview(0)
    game.send_info()

func select_workshop_character(index: int) -> void:
    if game.mode == "purchase_review": close_purchase_review()
    workshop_character = wrapi(index, 0, DiverCharacter.COUNT)
    workshop_message = ""
    pointer = Vector2(-100, -100)
    workshop_focus_pending = true

# Entry focus: the first node you can buy, else the next node you could reach.
func workshop_first_node() -> int:
    var skills = DiverProgression.owned(game.meta, workshop_character)
    var fallback = -1
    for i in DiverProgression.NODES.size():
        var id = DiverProgression.NODES[i].id
        if DiverProgression.can_buy(game.meta, workshop_character, id): return i
        if fallback < 0 and id not in skills and DiverProgression.reachable(skills, id): fallback = i
    return maxi(0, fallback)

func grid_zoom() -> float:
    return GRID_ZOOMS[grid_zoom_step]

func grid_point(i: int) -> Vector2:
    var at: Array = DiverProgression.NODES[i].pos
    return GRID_RECT.get_center() + (Vector2(at[0], at[1]) - grid_center) * GRID_CELL * grid_zoom()

# Pan just enough to keep a node inside the grid frame.
func grid_reveal(i: int) -> void:
    var inner = Rect2(GRID_RECT.position + Vector2(56, 40), GRID_RECT.size - Vector2(112, 96))
    var at = grid_point(i)
    var shift = Vector2(minf(0, at.x - inner.position.x) + maxf(0, at.x - inner.end.x), minf(0, at.y - inner.position.y) + maxf(0, at.y - inner.end.y))
    grid_center += shift / (GRID_CELL * grid_zoom())

# Overview framing: the whole grid sits below the progress/zoom strip.
func grid_recenter() -> void:
    grid_center = Vector2(0, 2.4)

func grid_zoom_by(step: int) -> void:
    grid_zoom_step = clampi(grid_zoom_step + step, 0, GRID_ZOOMS.size() - 1)
    if grid_zoom_step <= 1: grid_recenter()
    var node = focus_index - DiverCharacter.COUNT
    if node >= 0 and node < DiverProgression.NODES.size(): grid_reveal(node)

# Nearest node in a direction, inside a cone so diagonals feel natural.
func grid_step(from: int, direction: Vector2) -> int:
    var origin: Array = DiverProgression.NODES[from].pos
    var best = -1
    var best_score = INF
    for i in DiverProgression.NODES.size():
        var at: Array = DiverProgression.NODES[i].pos
        var offset = Vector2(at[0] - origin[0], at[1] - origin[1])
        var along = offset.dot(direction)
        var across = absf(offset.cross(direction))
        if i == from or along <= 0.1 or across > along * 1.25: continue
        var score = along + across * 2.0
        if score < best_score:
            best_score = score
            best = i
    return best

func grid_state(i: int) -> String:
    var id = DiverProgression.NODES[i].id
    var skills = DiverProgression.owned(game.meta, workshop_character)
    if id in skills: return "owned"
    if not DiverProgression.reachable(skills, id): return "locked"
    if int(game.meta.zenny) < DiverProgression.NODES[i].cost: return "short"
    if game.profile_source == "account" and game.account.status != "Synced": return "syncing"
    return "available"

func grid_name(entry: Dictionary) -> String:
    var special = DiverProgression.spec(workshop_character, entry.id)
    return entry.name if special.is_empty() else special.name

func grid_equipped(entry: Dictionary) -> bool:
    return entry.id in DiverProgression.SPEC_NODES and game.equipped_spec(workshop_character) == entry.id

func grid_detail(entry: Dictionary) -> String:
    var special = DiverProgression.spec(workshop_character, entry.id)
    if not special.is_empty(): return special.desc
    match entry.id:
        "salvage": return "Adds %s to this digger's drop pool." % game.ITEMS[DiverProgression.RESEARCH[workshop_character]].name
        "ability": return DiverProgression.ABILITIES[workshop_character]
        "ability2": return DiverProgression.ABILITIES_2[workshop_character]
    return entry.desc

func grid_icon(entry: Dictionary) -> String:
    match entry.icon:
        "research": return DiverProgression.RESEARCH[workshop_character]
        "weapon": return ["pulse", "needle", "siege", "scrap"][workshop_character]
        "spec": return DiverProgression.spec(workshop_character, entry.id).icon
    return entry.icon

func buy_grid_node(i: int) -> void:
    if game.mode != "workshop": return
    if i < 0 or i >= DiverProgression.NODES.size(): return
    if not purchase_review.is_empty() and purchase_review.phase == "pending" and purchase_review.character == workshop_character and purchase_review.index == i and purchase_context_matches():
        show_purchase_review()
        return
    var entry = DiverProgression.NODES[i]
    match grid_state(i):
        "owned":
            if entry.id not in DiverProgression.SPEC_NODES: workshop_message = "%s is already fitted." % entry.name
            elif grid_equipped(entry):
                game.equip_spec(workshop_character, "")
                workshop_message = "%s unequipped. The next dig uses the default loadout." % grid_name(entry)
            elif game.equip_spec(workshop_character, entry.id): workshop_message = "%s equipped for this digger's next dig." % grid_name(entry)
            else: workshop_message = "Specializations can't change during a dig."
        "locked": workshop_message = "Buy a linked circuit first to reach %s." % entry.name
        "short": workshop_message = "%s needs %d more Zenny." % [entry.name, entry.cost - int(game.meta.zenny)]
        "syncing": workshop_message = "Waiting for your account to sync before buying."
        _:
            begin_purchase_review(i)

func purchase_context_matches() -> bool:
    if purchase_review.is_empty() or game.profile_source != purchase_review.source or str(game.account.identity.get("id", "")) != purchase_review.account_id: return false
    # A durable submitted operation still belongs to this account after sign-in
    # renewal. An unsubmitted review cannot cross an authentication generation.
    return game.account.generation == purchase_review.generation or (purchase_review.source == "account" and purchase_review.op_id != "")

func begin_purchase_review(i: int) -> void:
    var entry = DiverProgression.NODES[i]
    purchase_review = {"index": i, "node": entry.id, "character": workshop_character,
        "name": grid_name(entry), "detail": grid_detail(entry), "icon": grid_icon(entry),
        "cost": int(entry.cost), "wallet": int(game.meta.zenny),
        "revision": game.account.revision if game.profile_source == "account" else int(game.meta.revision),
        "source": game.profile_source, "account_id": str(game.account.identity.get("id", "")),
        "generation": game.account.generation, "phase": "review", "op_id": "", "note": ""}
    show_purchase_review()

func show_purchase_review() -> void:
    page_focus.purchase_review = {"action": "purchase_cancel" if purchase_review.phase == "review" else "purchase_close", "value": 0}
    game.mode = "purchase_review"
    grid_dragging = false
    purchase_need_release = purchase_confirm_held()
    purchase_lock_until = Time.get_ticks_msec() + PURCHASE_ARM_MS

func purchase_confirm_held() -> bool:
    return Input.is_action_pressed("nav_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func purchase_input_ready() -> bool:
    return game.mode == "purchase_review" and not purchase_need_release and Time.get_ticks_msec() >= purchase_lock_until

func purchase_problem() -> String:
    if not purchase_context_matches() or workshop_character != int(purchase_review.character): return "Your account or digger changed. Close and review this circuit again."
    var character = int(purchase_review.character)
    var node = str(purchase_review.node)
    if node in DiverProgression.owned(game.meta, character): return "This circuit is already fitted. No purchase is needed."
    if game.net.active() and (game.net.loadout_locked() or game.net.own_ready()): return "Your loadout is locked. Unready in the lobby before buying."
    if game.in_run(): return "Circuits can only be bought between digs."
    if int(game.meta.zenny) < int(purchase_review.cost): return "You need %d more Zenny. Nothing has been spent." % (int(purchase_review.cost) - int(game.meta.zenny))
    var revision = game.account.revision if game.profile_source == "account" else int(game.meta.revision)
    if revision != int(purchase_review.revision) or int(game.meta.zenny) != int(purchase_review.wallet): return "Your progress changed. Close and review the updated wallet before buying."
    if not DiverProgression.can_buy(game.meta, character, node): return "This circuit is no longer available. Check its linked circuits."
    if game.profile_source == "account" and (not game.account.signed_in() or game.account.status != "Synced" or not game.account.outbox.is_empty()): return "Wait for your account to sync, then review this circuit again."
    return ""

func confirm_purchase() -> void:
    if not purchase_input_ready() or purchase_review.is_empty() or purchase_review.phase != "review": return
    var problem = purchase_problem()
    if problem != "":
        purchase_review.phase = "refused"
        purchase_review.note = problem
        return
    # Change phase before calling helpers so a repeated click cannot submit again.
    purchase_review.phase = "pending"
    pointer = Vector2(-100, -100)
    pointer_travel = 0.0
    if not game.buy_skill(int(purchase_review.character), str(purchase_review.node)):
        purchase_review.phase = "refused"
        purchase_review.note = "Purchase was not queued. Restore account sync or free device storage, then review again." if game.profile_source == "account" else "Could not save the purchase. Your Zenny and circuits are unchanged. Free device storage and try again."
    elif game.profile_source == "account":
        purchase_review.op_id = str(game.account.outbox.back().body.op_id)
        workshop_message = "Purchase submitted. Closing the review does not cancel it."
    else:
        purchase_review.phase = "confirmed"
        purchase_review.note = "Fitted %s. Saved on this device." % purchase_review.name
        workshop_message = purchase_review.note

func purchase_settled(operation_id: String, outcome: String) -> void:
    if purchase_review.is_empty() or purchase_review.op_id != operation_id or not purchase_context_matches(): return
    purchase_review.phase = "confirmed" if outcome == "confirmed" else "refused"
    pointer = Vector2(-100, -100)
    pointer_travel = 0.0
    purchase_review.note = "Fitted %s. Your account confirmed the purchase." % purchase_review.name if outcome == "confirmed" else "Your progress changed on another device. Review again before buying." if outcome == "revision_conflict" else "Purchase refused: %s. Check your synced wallet and circuits." % outcome.replace("_", " ")
    workshop_message = "%s / %s" % [DiverCharacter.DISPLAY_NAMES[int(purchase_review.character)], purchase_review.note]

func close_purchase_review() -> void:
    if game.mode != "purchase_review" or purchase_review.is_empty(): return
    if purchase_review.phase == "pending": workshop_message = "Purchase still pending / %s. Closing does not cancel it." % game.account.status
    elif purchase_review.phase == "review": workshop_message = "Purchase canceled. Nothing spent."
    else: workshop_message = purchase_review.note
    page_focus.workshop = {"action": "grid_node", "value": int(purchase_review.index)}
    workshop_focus_pending = false
    game.mode = "workshop"
    if purchase_review.phase == "review": purchase_review = {}

# The Workshop is three rows: digger headers, the circuit grid and the bottom
# buttons. Inside the grid each direction moves to the nearest node that way;
# leaving the grid's top or bottom reaches the other rows.
func workshop_navigate(delta: int, horizontal: bool) -> void:
    var tabs: Array[int] = []
    var nodes: Array[int] = []
    var row: Array[int] = []
    for i in hits.size():
        match hits[i].action:
            "tree_character": tabs.append(i)
            "grid_node": nodes.append(i)
            "grid_zoom", "grid_center": pass
            _: row.append(i)
    if tabs.is_empty() or nodes.is_empty() or row.is_empty(): return
    var primary = row[mini(1, row.size() - 1)]
    var enter = func(node: int) -> void:
        focus_index = nodes[node]
        grid_reveal(node)
    if focus_index in tabs:
        if horizontal:
            # Preview the neighbouring digger without leaving the header row.
            workshop_character = wrapi(tabs.find(focus_index) + delta, 0, tabs.size())
            workshop_message = ""
            focus_index = tabs[workshop_character]
        elif delta > 0: enter.call(workshop_first_node())
        else: focus_index = primary
    elif focus_index in nodes:
        var next = grid_step(nodes.find(focus_index), Vector2(delta, 0) if horizontal else Vector2(0, delta))
        if next >= 0: enter.call(next)
        elif not horizontal: focus_index = tabs[workshop_character] if delta < 0 else primary
    elif focus_index in row:
        if horizontal: focus_index = row[clampi(row.find(focus_index) + delta, 0, row.size() - 1)]
        elif delta < 0:
            # Come back up into the bottom of the grid.
            var lowest = 0
            for i in DiverProgression.NODES.size():
                if DiverProgression.NODES[i].pos[1] > DiverProgression.NODES[lowest].pos[1]: lowest = i
            enter.call(lowest)
        else: focus_index = tabs[workshop_character]
    else: enter.call(workshop_first_node())

func title_account_copy() -> Dictionary:
    var a = game.account
    if a.state == "restoring":
        return {"label": "Account offline / Retry" if a.status == "Offline" else "Restoring account…", "detail": "Saved sign-in awaiting confirmation"}
    if a.state == "signing_in":
        return {"label": "Signing in…", "detail": "Loading your account progress"}
    if a.state == "needs_sign_in":
        return {"label": "Sign in again", "detail": "Cloud progress / Sign-in needed" if game.profile_source == "account" else "Saved sign-in needs renewal"}
    if a.signed_in():
        return {"label": "Signed in as " + str(a.identity.get("name", "Digger")), "detail": "Cloud progress / " + a.status if game.profile_source == "account" else "Guest progress / Account signed in"}
    # Browser session discovery starts while Guest is still the active profile.
    # Ignore obsolete requests left over from a cancelled sign-in/sign-out.
    for request in a.requests:
        if request.generation == a.generation and request.path == "/api/v1/profile":
            return {"label": "Checking account…", "detail": "Guest progress until confirmed"}
    return {"label": "Guest / Sign in to sync", "detail": "Guest progress / this device"}

func handheld() -> bool:
    return game.settings.handheld_ui

# Enlarge small copy without changing large headings or the world camera.
func readable_size(size: int) -> int:
    return maxi(22, roundi(size * 1.18)) if handheld() and 19 <= size and size <= 28 else size

func text_at(pos: Vector2, value: String, size: int = 24, color: Color = WHITE, display: bool = false, width: float = -1) -> void:
    size = readable_size(size)
    var face: Font = heading if display else font
    var shown = value
    if width > 0:
        while shown.length() > 1 and face.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
            shown = shown.left(shown.length() - 2) + "…"
    draw_string_outline(face, pos + Vector2(1, 2), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4 if display else 2, INK)
    draw_string(face, pos, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func paragraph(pos: Vector2, value: String, width: float, size: int = 24, color: Color = WHITE, max_lines: int = 4) -> void:
    var line = ""
    var y = pos.y
    var row = 1
    var measured_size = readable_size(size)
    for word in value.split(" "):
        var proposed = line + (" " if line != "" else "") + word
        if font.get_string_size(proposed, HORIZONTAL_ALIGNMENT_LEFT, -1, measured_size).x > width and line != "":
            text_at(Vector2(pos.x, y), line, size, color)
            y += measured_size * 1.3
            row += 1
            line = word
            if row > max_lines: return
        else: line = proposed
    text_at(Vector2(pos.x, y), line, size, color)

func rect(pos: Vector2, size: Vector2, color: Color) -> void:
    draw_rect(Rect2(pos, size), color)

func window(pos: Vector2, size: Vector2, color: Color = PANEL, border: Color = EDGE, shadow: bool = true) -> void:
    var style = StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(2)
    style.set_corner_radius_all(5)
    style.anti_aliasing = false
    if shadow:
        style.shadow_color = Color(0.025, 0.04, 0.15, 0.65)
        style.shadow_offset = Vector2(4, 5)
        style.shadow_size = 2
    draw_style_box(style, Rect2(pos, size))
    draw_line(pos + Vector2(6, 5), pos + Vector2(size.x - 6, 5), Color(0.38, 0.62, 0.9, 0.55), 2)

func icon(pos: Vector2, id: String, side: float = 48, tint: Color = Color.WHITE) -> void:
    var index: int = ICONS.get(id, 31)
    var region = Rect2((index % 8) * 64, (index / 8) * 64, 64, 64)
    draw_texture_rect_region(atlas, Rect2(pos, Vector2.ONE * side), region, tint)

func badge(pos: Vector2, value: String, width: float = 54, color: Color = YELLOW) -> void:
    window(pos, Vector2(width, 30), INK, EDGE, false)
    text_at(pos + Vector2(10, 23), value, 20, color, true, width - 16)

# Label of a control for the device in use (keyboard/mouse or controller).
func p(id: String) -> String:
    return game.settings.prompt(id)

func pad() -> bool:
    return game.settings.using_pad

func keycap(pos: Vector2, value: String, width: float = 44) -> void:
    width = maxf(width, heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if handheld() else 17).x + 16) if value != "↑↓" else width
    window(pos, Vector2(width, 32 if handheld() else 28), Color("d1e5ed"), WHITE, false)
    if value == "↑↓":
        draw_colored_polygon(PackedVector2Array([pos + Vector2(11, 12), pos + Vector2(17, 5), pos + Vector2(23, 12)]), INK)
        draw_line(pos + Vector2(17, 10), pos + Vector2(17, 23), INK, 3)
        draw_colored_polygon(PackedVector2Array([pos + Vector2(27, 16), pos + Vector2(33, 23), pos + Vector2(39, 16)]), INK)
        draw_line(pos + Vector2(33, 6), pos + Vector2(33, 18), INK, 3)
    elif value == "←→":
        draw_colored_polygon(PackedVector2Array([pos + Vector2(6, 15), pos + Vector2(13, 8), pos + Vector2(13, 22)]), INK)
        draw_line(pos + Vector2(12, 15), pos + Vector2(21, 15), INK, 3)
        draw_colored_polygon(PackedVector2Array([pos + Vector2(40, 15), pos + Vector2(33, 8), pos + Vector2(33, 22)]), INK)
        draw_line(pos + Vector2(25, 15), pos + Vector2(34, 15), INK, 3)
    else:
        draw_string(heading, pos + Vector2(8, 21), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if handheld() else 17, INK)

func cursor(pos: Vector2, side: float = 30) -> void:
    icon(pos + Vector2(sin(Time.get_ticks_msec() * 0.008) * 2, 0), "cursor", side)

func button(pos: Vector2, size: Vector2, title: String, action: String, value: int = 0, primary: bool = false) -> void:
    var area = Rect2(pos, size)
    var hot = not underlay and (focus_index == hits.size() or area.has_point(pointer))
    window(pos, size, SELECT if hot else Color("254991") if primary else PANEL, YELLOW if hot else EDGE)
    if hot: cursor(pos + Vector2(-28, size.y / 2 - 16))
    text_at(pos + Vector2(24, size.y / 2 + 10), title, 28, WHITE, false, size.x - 48)
    hits.append({"rect": area, "action": action, "value": value})

func _input(event: InputEvent) -> void:
    var reroll_event = (event is InputEventKey and (event.keycode == KEY_R or event.physical_keycode == KEY_R)) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y)
    if reroll_event and not event.is_echo():
        if not event.is_pressed(): reroll_held = false
        elif reroll_held:
            get_viewport().set_input_as_handled()
            return
        else: reroll_held = true
    # Release is observed even while a text field or a different page owns input.
    # Repeated pressed events cannot carry a held A/Enter/B into the next layer.
    if event.is_action("nav_accept") and not event.is_echo():
        if not event.is_pressed(): accept_held = false
        elif accept_held:
            get_viewport().set_input_as_handled()
            return
        else: accept_held = true
    if event.is_action("nav_back") and not event.is_echo():
        if not event.is_pressed(): back_held = false
        elif back_held:
            get_viewport().set_input_as_handled()
            return
        else: back_held = true
    if game.mode == "controller_test":
        if event is InputEventJoypadButton:
            controller_last_button = "Button %d: %s" % [event.button_index, "pressed" if event.pressed else "released"]
            if event.button_index == JOY_BUTTON_B and event.pressed and not event.is_echo(): back()
            get_viewport().set_input_as_handled()
            return
        if event is InputEventJoypadMotion:
            get_viewport().set_input_as_handled()
            return
    if event is InputEventMouseMotion:
        # Window/viewport updates can emit motion at the stationary pointer.
        if event.relative.is_zero_approx(): return
        if pointer.x < -50 and not grid_dragging:
            pointer_travel += event.relative.length()
            if pointer_travel <= 4: return
        game.settings.using_pad = false
        pointer = (event.position - ui_offset) / ui_scale
        if grid_dragging and game.mode == "workshop":
            grid_center -= event.relative / ui_scale / (GRID_CELL * grid_zoom())
            return
        if game.mode != "play":
            for i in hits.size():
                if hits[i].rect.has_point(pointer):
                    if focus_index != i: game.sound.play("menu_move")
                    focus_index = i
                    if hits[i].action == "inspect": selected_item = hits[i].value
                    if hits[i].action == "choice": choice_preview = hits[i].value
                    break
    if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT: grid_dragging = false
    if event is InputEventMouseButton and event.pressed and game.mode != "play":
        if game.mode != previous_mode: return
        var at = (event.position - ui_offset) / ui_scale
        if game.mode == "workshop" and GRID_RECT.has_point(at) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            grid_zoom_by(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
            get_viewport().set_input_as_handled()
            return
        if game.mode == "workshop" and event.button_index == MOUSE_BUTTON_LEFT and GRID_RECT.has_point(at) and hits.all(func(hit): return not hit.rect.has_point(at)):
            # Drag empty grid space to pan; nodes and buttons still click.
            grid_dragging = true
            get_viewport().set_input_as_handled()
            return
        if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and game.mode in ["inventory", "archive"]:
            select_part(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if editing():
                var owner_field: Control = get_viewport().gui_get_focus_owner()
                if not owner_field.get_global_rect().has_point(event.position): get_viewport().gui_release_focus()
            var point = (event.position - ui_offset) / ui_scale
            for i in hits.size():
                var hit = hits[i]
                if hit.rect.has_point(point):
                    focus_index = i
                    activate(hit.action, hit.value)
                    get_viewport().set_input_as_handled()
                    break
    if not listening.is_empty():
        capture_binding(event)
        return
    # Keys and controller buttons; stick motion is handled by game.pad_motion().
    if event is InputEventJoypadMotion or not event.is_pressed() or event.is_echo(): return
    if not game.mode in MENU_MODES: return
    if editing():
        if event.is_action_pressed("nav_back") and back(): get_viewport().set_input_as_handled()
        return
    if event is InputEventMouseButton: return
    pointer = Vector2(-100, -100)
    pointer_travel = 0.0
    if game.mode == "choice" and reroll_event:
        game.reroll_choice()
        get_viewport().set_input_as_handled()
        return
    if game.mode == "workshop" and ((event is InputEventKey and event.keycode == KEY_Z) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_X)):
        grid_zoom_by(1 if grid_zoom_step < GRID_ZOOMS.size() - 1 else -GRID_ZOOMS.size())
        game.sound.play("menu_move")
        get_viewport().set_input_as_handled()
        return
    if game.mode == "workshop" and event is InputEventJoypadButton:
        if event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
            select_workshop_character(workshop_character + (-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1))
            game.sound.play("menu_move")
            get_viewport().set_input_as_handled()
            return
    for dir in [["nav_up", -1, false], ["nav_down", 1, false], ["nav_left", -1, true], ["nav_right", 1, true]]:
        if event.is_action_pressed(dir[0]):
            navigate(dir[1], dir[2])
            get_viewport().set_input_as_handled()
            return
    if event.is_action_pressed("switch_digger") and game.mode in ["title", "workshop"]:
        if game.mode == "workshop": select_workshop_character(workshop_character + 1)
        else: select_character(game.selected_character + 1)
        game.sound.play("menu_confirm")
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("nav_accept"):
        confirm()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("nav_back") and back():
        get_viewport().set_input_as_handled()

# Move the menu cursor (arrows, D-pad or left stick).
func navigate(delta: int, horizontal: bool) -> void:
    if not listening.is_empty() or editing() or not game.mode in MENU_MODES: return
    if game.mode != previous_mode: return
    pointer = Vector2(-100, -100)
    pointer_travel = 0.0
    if game.mode == "controller_test" and horizontal:
        cycle_controller(delta)
    elif game.mode == "options" and horizontal:
        if focus_index < OPTIONS.size(): adjust_option(focus_index, delta)
    elif game.mode == "controls" and not horizontal and focus_index < DiverSettings.ACTIONS.size() * 2:
        focus_index = clampi(focus_index + delta * 2, focus_index % 2, hits.size() - 1)
    elif game.mode == "choice": choice_preview = wrapi(choice_preview + delta, 0, 3)
    elif game.mode in ["archive", "inventory"]: select_part(delta)
    elif game.mode == "workshop": workshop_navigate(delta, horizontal)
    elif game.mode == "solo_prep":
        if horizontal:
            if focused_action() in ["solo_character", "solo_cycle"]: select_character(game.selected_character + delta)
        else:
            var regions = ["solo_character", "launch_solo", "title"]
            var region = "solo_character" if focused_action() == "solo_cycle" else focused_action()
            focus_action(regions[wrapi(regions.find(region) + delta, 0, regions.size())])
    elif game.mode == "title" and horizontal: return
    else: move_focus(delta)
    game.sound.play("menu_move")

func confirm() -> void:
    # Until the new page has drawn, its predecessor's hit targets are stale.
    if game.mode != previous_mode: return
    pointer = Vector2(-100, -100)
    pointer_travel = 0.0
    if game.mode == "solo_prep" and focused_action() == "solo_cycle": focus_action("launch_solo")
    elif game.mode == "choice": activate("choice", choice_preview)
    elif game.mode in ["inventory", "archive"]: activate("resume" if game.mode == "inventory" else "title")
    elif not hits.is_empty():
        var hit = hits[clampi(focus_index, 0, hits.size() - 1)]
        activate(hit.action, hit.value)

# Esc / B: step back out of the current menu. Returns true when handled.
func back() -> bool:
    pointer = Vector2(-100, -100)
    if editing():
        get_viewport().gui_release_focus()
        return true
    match game.mode:
        "purchase_review": close_purchase_review()
        "lobby", "launch_preparing":
            if game.net.loadout_locked(): game.net.cancel_launch()
            else: activate("leave_online")
        "solo_prep":
            page_focus.title = {"action": "solo", "value": 0}
            activate("title")
        "android_update": game.android_updates.later()
        "credits": activate("title")
        "account":
            var a = game.account
            if game.profile_source != "account" and a.state != "restoring" and a.auth.view != "sign_in":
                activate("auth_view", AUTH_VIEWS.find("sign_in"))
            else:
                if a.state == "signing_in" or a.auth.busy: a.cancel_sign_in()
                activate("title")
        "archive", "online": activate("title")
        "workshop": activate(workshop_return)
        "save_codes": activate("workshop")
        "inventory", "pause": activate("resume")
        "options": activate(options_return)
        "controls", "controller_test": activate("options")
        "choice": game.close_choice()
        _: return false
    return true

func capture_binding(event: InputEvent) -> void:
    get_viewport().set_input_as_handled()
    if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and listening.column == "pad":
        listening = {}
        return
    if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and listening.column == "kb" and listening.id != "menu":
        listening = {}
        return
    var binding = game.settings.binding_from_event(event, listening.column)
    if binding.is_empty(): return
    game.settings.rebind(listening.id, listening.column, binding)
    game.sound.play("menu_confirm")
    listening = {}

func move_focus(delta: int) -> void:
    var choices: Array[int] = []
    for i in hits.size():
        if hits[i].action != "weapon": choices.append(i)
    if choices.is_empty(): return
    focus_index = choices[wrapi(choices.find(focus_index) + delta, 0, choices.size())]

func focused_action() -> String:
    return str(hits[focus_index].action) if focus_index >= 0 and focus_index < hits.size() else ""

func remember_focus(mode: String) -> void:
    if focus_index >= 0 and focus_index < hits.size():
        page_focus[mode] = {"action": hits[focus_index].action, "value": hits[focus_index].value}

func focus_action(action: String, value: int = 0) -> bool:
    for i in hits.size():
        if hits[i].action == action and hits[i].value == value:
            focus_index = i
            return true
    return false

func open_solo() -> void:
    page_focus.title = {"action": "solo", "value": 0}
    page_focus.solo_prep = {"action": "solo_character", "value": 0}
    game.show_solo_prep()

func select_part(delta: int) -> void:
    var count = game.ITEMS.size() if game.mode == "archive" else game.player.items.size()
    if count > 0: selected_item = clampi(selected_item + delta, 0, count - 1)

func confirm_label(action: String, value: int, normal: String) -> String:
    return "Press again to confirm" if confirming == "%s:%d" % [action, value] else normal

func activate(action: String, value: int = 0) -> void:
    # A pick needs a fresh press on a settled offer (no held A, no double click).
    if action == "choice" and not game.choice_input_ready(): return
    if game.mode == previous_mode: remember_focus(game.mode)
    game.sound.play("menu_confirm")
    if action in CONFIRM and confirming != "%s:%d" % [action, value]:
        confirming = "%s:%d" % [action, value]
        confirm_time = 3.0
        return
    confirming = ""
    match action:
        "controller_cycle": cycle_controller(value)
        "controller_raw_page":
            controller_raw_page = (controller_raw_page + 1) % 4
            controller_sample_at = 0
        "reroll": game.reroll_choice()
        "purchase_confirm": confirm_purchase()
        "purchase_cancel", "purchase_close": close_purchase_review()
        "purchase_retry":
            if purchase_context_matches() and game.account.signed_in(): game.account.retry()
        "android_download": game.android_updates.download()
        "android_later": game.android_updates.later()
        "credits":
            credits_lines.clear()
            for source in FileAccess.get_file_as_string("res://assets/notices/credits.txt").split("\n"):
                var line = ""
                for word in source.split(" "):
                    if font.get_string_size(line + " " + word, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x > 1220 and line != "":
                        credits_lines.append(line)
                        line = word
                    else: line += (" " if line != "" else "") + word
                credits_lines.append(line)
            credits_page = 0
            game.mode = "credits"
        "credits_page": credits_page = clampi(credits_page + value, 0, maxi(0, (credits_lines.size() - 1) / 13))
        "account":
            if not game.account.switch_allowed(): return
            game.mode = "account"
        "sign_in": game.account.sign_in()
        "account_retry": game.account.retry()
        "sign_out":
            game.account.sign_out()
            game.show_title()
        "guest":
            game.account.play_guest()
            game.show_title()
        "migrate_confirm": game.account.confirm_migration()
        "auth_field": [auth_name_edit, auth_email_edit, auth_password_edit, auth_code_edit][value].grab_focus()
        "auth_view":
            auth_backup = false
            auth_code_edit.text = ""
            game.account.open_auth(AUTH_VIEWS[value])
            if AUTH_VIEWS[value] in ["sign_in", "create", "forgot"] and auth_email_edit.text == "": auth_email_edit.text = game.account.auth.email
        "auth_submit": submit_auth()
        "auth_backup":
            auth_backup = not auth_backup
            auth_code_edit.text = ""
        "takeover":
            game.account.retry_run(true)
        "retry_run": game.account.retry_run()
        "clear_session":
            game.account.clear_local_session()
            if game.profile_source == "guest": game.show_title()
        "invite_continue":
            game.mode = "online"
            game.net.join_lobby(game.net.invited_code(), game.net.url_param("key"))
        "start", "solo": open_solo()
        "solo_character": focus_action("launch_solo")
        "solo_cycle":
            select_character(game.selected_character + value)
            focus_action("solo_character")
        "launch_solo":
            if game.saved_dig.is_empty(): game.start_run()
            else: activate("start_new")
        "start_new": game.start_run()
        "continue": game.continue_saved_dig()
        "discard": game.discard_saved_dig()
        "give_up": game.net.give_up("You left while reconnecting.")
        "kick": game.net.kick(value)
        "lock": game.net.set_locked(not bool(game.net.lobby.get("locked", false)))
        "resume": game.resume_game()
        "choice": game.choose(value)
        "choice_later": game.close_choice()
        "workshop":
            if game.mode != "save_codes":
                page_focus.erase("workshop")
                workshop_return = game.mode
                workshop_character = game.selected_character
                workshop_message = ""
            game.mode = "workshop"
        "tree_character": select_workshop_character(value)
        "grid_node": buy_grid_node(value)
        "grid_zoom": grid_zoom_by(value)
        "grid_center":
            grid_zoom_step = 1
            grid_recenter()
        "save_codes":
            game.mode = "save_codes"
            save_edit.text = ""
            pending_import = {}
            save_message = "Export a code, then copy the whole field somewhere safe."
        "export_save":
            save_edit.text = DiverProgression.encode(game.meta)
            DisplayServer.clipboard_set(save_edit.text)
            save_message = "Code ready. Copy the field if your browser blocked clipboard access."
            pending_import = {}
        "paste_save":
            if OS.has_feature("web"):
                JavaScriptBridge.eval("window.relicSavePaste = null; navigator.clipboard.readText().then(v => window.relicSavePaste = v).catch(() => window.relicSavePaste = '');", true)
                waiting_for_paste = true
                save_message = "Reading clipboard…"
            else:
                save_edit.text = DisplayServer.clipboard_get().left(32768)
                pending_import = {}
        "check_import":
            if game.profile_source == "account" and not game.account.empty_account():
                save_message = "Cloud progress cannot be replaced by a save code. Export remains available."
                pending_import = {}
                return
            pending_import = DiverProgression.decode(save_edit.text)
            save_message = "Invalid or damaged code. Your progress is unchanged." if pending_import.is_empty() else ("Backup: %d digs / %d Zenny. Preview adoption into this empty cloud account?" if game.profile_source == "account" else "Backup: %d digs / %d Zenny. Replace this device's progress?") % [pending_import.runs, pending_import.zenny]
            get_viewport().gui_release_focus()
        "confirm_import":
            if game.profile_source == "account":
                if not pending_import.is_empty(): game.account.preview_migration(pending_import)
                return
            if not pending_import.is_empty() and game.import_progress(pending_import):
                save_message = "Progress restored and saved."
                pending_import = {}
            else: save_message = "Import blocked. Leave online and finish or discard a saved dig first."
        "archive": game.mode = "archive"
        "inventory": game.mode = "inventory"
        "inspect": selected_item = value
        "title": game.show_title()
        "character": select_character(value)
        "ready": game.net.set_ready(not game.net.own_ready())
        "cancel_launch": game.net.cancel_launch()
        "lobby_workshop": game.request_loadout_change()
        "mute": game.sound.muted = not game.sound.muted
        "options":
            if game.mode in ["title", "pause"]: options_return = game.mode
            game.mode = "options"
        "option": activate_option(value)
        "controls": game.mode = "controls"
        "controller_test":
            controller_sample_at = 0
            controller_raw_page = 0
            game.mode = "controller_test"
            game.pad_held.clear()
            return
        "bind": listening = {"id": DiverSettings.ACTIONS[value / 2].id, "column": "kb" if value % 2 == 0 else "pad", "time": 6.0}
        "reset_controls":
            game.settings.reset_bindings()
            game.settings.apply_bindings()
            game.settings.save_settings()
        "leave_dig":
            game.end_reason = "You left the dig"
            if game.net.active(): game.leave_online()
            else: game.finish_run(false)
        "pause": game.mode = "pause"
        "end": game.mode = "end"
        "volume":
            var bus: String = ["Master", "Music", "Effects", "Ambience"][value]
            game.sound.adjust_volume(bus, -1.0 if game.sound.volumes[bus] >= 0.99 else 0.10)
        "camera_fx": game.camera_effects = not game.camera_effects
        "quit": game.get_tree().quit()
        "abandon":
            if game.net.is_host(): game.end_run_all(false)
            else: game.finish_run(false)
        "online":
            game.mode = "online"
            game.net.error_text = ""
            game.net.refresh_list()
        "create_public", "create_private":
            commit_name()
            game.net.create_lobby("%s's Dig" % game.net.player_name, action == "create_public", new_pass_edit.text)
        "join":
            if value < game.net.public_lobbies.size():
                var info: Dictionary = game.net.public_lobbies[value]
                # Password lobbies need the password typed in first.
                if bool(info.get("password", false)) and pass_edit.text.strip_edges() == "":
                    code_edit.text = str(info.code)
                    pass_edit.grab_focus()
                    game.net.error_text = "That lobby needs a password. Type it, then press Join."
                else: game.net.join_lobby(str(info.code), pass_edit.text)
        "join_code":
            if code_edit.text.strip_edges().length() >= 3:
                commit_name()
                game.net.join_lobby(code_edit.text, pass_edit.text)
                get_viewport().gui_release_focus()
        "refresh": game.net.refresh_list()
        "copy_link":
            DisplayServer.clipboard_set(game.net.invite_link())
            copied_time = 2.5
        "start_online": game.host_start_run()
        "lobby_room": game.enter_lobby_room()
        "leave_online": game.leave_online()

func _draw() -> void:
    if purchase_need_release and not purchase_confirm_held(): purchase_need_release = false
    if game.mode == "purchase_review" and not purchase_context_matches():
        close_purchase_review()
        purchase_review = {}
        workshop_message = "Account changed. Submitted purchases stay with their original account. Review again here."
    GRID_RECT = Rect2(454, 366, 922, 414) if handheld() else Rect2(394, 366, 982, 414)
    ui_scale = minf(get_viewport_rect().size.x / BASE.x, get_viewport_rect().size.y / BASE.y)
    ui_offset = (get_viewport_rect().size - BASE * ui_scale) * 0.5
    draw_set_transform(ui_offset, 0, Vector2.ONE * ui_scale)
    if game.mode != previous_mode:
        if previous_mode != "": remember_focus(previous_mode)
        previous_mode = game.mode
        focus_index = 0
        pending_focus = page_focus.get(game.mode, {}).duplicate()
        selected_item = 0
        list_scroll = 0
        choice_preview = 0
        pointer = Vector2(-100, -100)
        pointer_travel = 0.0
        if game.mode == "workshop": workshop_focus_pending = pending_focus.is_empty()
    else:
        remember_focus(game.mode)
        pending_focus = page_focus.get(game.mode, {}).duplicate()
    if game.mode == "workshop" and workshop_focus_pending: pending_focus = {}
    hits.clear()
    copied_time = maxf(0, copied_time - get_process_delta_time())
    confirm_time -= get_process_delta_time()
    if confirm_time <= 0: confirming = ""
    # Hiding a focused LineEdit releases focus, even if shown again in this draw.
    # Only hide fields when their page no longer owns them.
    name_edit.visible = game.mode in ["online", "lobby", "launch_preparing"]
    for field in [code_edit, server_edit, pass_edit, new_pass_edit]:
        if game.mode != "online": field.visible = false
    save_edit.visible = game.mode == "save_codes"
    if game.mode != "account":
        for field in [auth_name_edit, auth_email_edit, auth_password_edit, auth_code_edit]: field.visible = false
    var chatting = game.net.active() and (game.mode in ["lobby", "launch_preparing"] or (game.mode == "play" and game.chat_open))
    if not chatting: chat_edit.visible = false
    match game.mode:
        "model_preview": return
        "title": draw_title()
        "solo_prep": draw_solo_prep()
        "online": draw_online()
        "lobby": draw_lobby()
        "launch_preparing": draw_lobby()
        "archive": draw_parts(true)
        "choice": draw_choice_overlay()
        "pause": draw_pause()
        "options": draw_options()
        "controls": draw_controls()
        "controller_test": draw_controller_test()
        "inventory": draw_parts(false)
        "end": draw_end()
        "workshop": draw_workshop()
        "purchase_review": draw_purchase_review()
        "save_codes": draw_save_codes()
        "account": draw_account()
        "android_update": draw_android_update()
        "credits": draw_credits()
        _: draw_hud()
    if not pending_focus.is_empty() and not focus_action(pending_focus.action, pending_focus.value): focus_index = 0
    focus_index = clampi(focus_index, 0, maxi(0, hits.size() - 1))
    pending_focus = {}

func backdrop() -> void:
    var extra = ui_offset / ui_scale
    # Online menus stay slightly see-through: the dig keeps going behind them.
    var live = game.world_running()
    rect(-extra, BASE + extra * 2, Color(BLUE, 0.84) if live else BLUE)
    for x in range(floori(-extra.x / 256), ceili((BASE.x + extra.x) / 256)):
        for y in range(floori(-extra.y / 256), ceili((BASE.y + extra.y) / 256)): draw_texture_rect(pattern, Rect2(x * 256, y * 256, 256, 256), false, Color(0.75, 0.85, 1, 0.35 if live else 0.62))
    rect(Vector2.ZERO, BASE, Color(0.02, 0.05, 0.20, 0.12))

func pips(pos: Vector2, width: float, height: float, fraction: float, count: int = 16, color: Color = GREEN) -> void:
    rect(pos - Vector2.ONE * 3, Vector2(width + 6, height + 6), INK)
    var cell = width / count
    for i in count:
        var filled = float(i) / count < fraction and fraction > 0
        rect(pos + Vector2(i * cell, 0), Vector2(cell - 3, height), color if filled else Color("274575"))
        if filled: rect(pos + Vector2(i * cell + 1, 1), Vector2(cell - 5, 3), Color("e1f7af") if color == GREEN else Color("fff3bd"))

func stats_header() -> void:
    var p = game.player
    window(Vector2(48, 32), Vector2(448, 96))
    text_at(Vector2(68, 64), "LIFE", 22, WHITE, true)
    pips(Vector2(70, 83), 278, 19, p.hp / p.max_hp())
    text_at(Vector2(368, 101), "%d" % int(p.hp), 30, WHITE, true)
    window(Vector2(520, 32), Vector2(304, 96))
    icon(Vector2(538, 58), "scrap", 54)
    text_at(Vector2(608, 65), "SCRAP", 20, WHITE, true)
    text_at(Vector2(608, 108), "%06d" % game.scrap, 34, YELLOW, true)
    window(Vector2(848, 32), Vector2(264, 96))
    text_at(Vector2(872, 65), "TIME", 20, WHITE, true)
    text_at(Vector2(872, 108), game.time_string(), 34, WHITE, true)
    window(Vector2(1136, 32), Vector2(256, 96))
    draw_texture_rect(portrait(), Rect2(1151, 43, 66, 74), false)
    text_at(Vector2(1230, 68), DiverCharacter.SHORT_NAMES[p.character], 22, CYAN, true)
    text_at(Vector2(1230, 109), "Lv. %02d" % p.level, 27, WHITE, true)

func page_title(title: String, detail: String) -> void:
    text_at(Vector2(64, 207), title, 46, WHITE, true)
    rect(Vector2(66, 223), Vector2(80, 5), YELLOW)
    text_at(Vector2(166, 242), detail, 24, MUTED, false, 1210)

func menu_footer(detail: String = "Select", back: String = "Back", confirm: String = "Confirm") -> void:
    keycap(Vector2(64, 842), "D-PAD" if pad() else "↑↓", 46)
    text_at(Vector2(124 + (34 if pad() else 0), 865), detail, 21)
    keycap(Vector2(284, 842), "A" if pad() else "ENTER", 76)
    text_at(Vector2(374, 865), confirm, 21)
    keycap(Vector2(1150, 842), "B" if pad() else "ESC", 55)
    text_at(Vector2(1220, 865), back, 21)

func draw_title() -> void:
    if handheld():
        draw_handheld_title()
        return
    var extra = ui_offset / ui_scale
    rect(-extra, Vector2(extra.x + 60, BASE.y + extra.y * 2), BLUE)
    var plate = PackedVector2Array([Vector2(0, 0), Vector2(626, 0), Vector2(586, 900), Vector2(0, 900)])
    draw_colored_polygon(plate, Color(0.055, 0.14, 0.36, 0.96))
    for y in range(0, 900, 256): draw_texture_rect(pattern, Rect2(0, y, 590, 256), true, Color(0.65, 0.8, 1, 0.26))
    draw_line(Vector2(626, 0), Vector2(586, 900), EDGE, 3)
    text_at(Vector2(62, 67), "MEGA MAN LEGENDS", 26, CYAN, true)
    draw_string_outline(heading, Vector2(69, 177), "RELIC", HORIZONTAL_ALIGNMENT_LEFT, -1, 94, 14, INK)
    draw_string(heading, Vector2(69, 177), "RELIC", HORIZONTAL_ALIGNMENT_LEFT, -1, 94, Color("5275b4"))
    draw_string_outline(heading, Vector2(62, 168), "RELIC", HORIZONTAL_ALIGNMENT_LEFT, -1, 94, 5, INK)
    draw_string(heading, Vector2(62, 168), "RELIC", HORIZONTAL_ALIGNMENT_LEFT, -1, 94, YELLOW)
    draw_string_outline(heading, Vector2(69, 292), "DIVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 110, 14, INK)
    draw_string(heading, Vector2(69, 292), "DIVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color("5275b4"))
    draw_string_outline(heading, Vector2(62, 283), "DIVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 110, 5, INK)
    draw_string(heading, Vector2(62, 283), "DIVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 110, WHITE)
    window(Vector2(64, 315), Vector2(476, 46), BLUE)
    text_at(Vector2(86, 347), "THE TIDAL ARCHIVE", 24, WHITE, true)
    text_at(Vector2(66, 399), "A dungeon-crawling fan adventure", 25, MUTED)
    var account_copy = title_account_copy()
    var menu_y = 418
    var saved: Dictionary = game.saved_dig
    if not saved.is_empty():
        var w: Dictionary = saved.world
        var detail = "B%d · %02d:%02d" % [int(w.get("depth", 1)), int(w.get("run_time", 0)) / 60, int(w.get("run_time", 0)) % 60]
        button(Vector2(64, menu_y), Vector2(476, 40), ("Rejoin Dig %s  (%s)" % [saved.lobby_code, detail]) if saved.get("online", false) else "Continue Dig  (%s)" % detail, "continue", 0, true)
        menu_y += 46
    var actions = [["Solo Dig" if saved.is_empty() else "Solo Dig / New Dig", "solo"], ["Play Online", "online"], ["Workshop", "workshop"], ["Options", "options"], [account_copy.label, "account"], ["Credits / Licenses", "credits"], ["Parts Collection", "archive"]]
    if not OS.has_feature("web"): actions.append(["Quit", "quit"])
    for entry in actions:
        button(Vector2(64, menu_y), Vector2(476, 40), entry[0], entry[1], 0, entry[1] == "solo")
        menu_y += 46
    window(Vector2(1020, 32), Vector2(372, 104), Color(0.06, 0.16, 0.40, 0.92))
    icon(Vector2(1038, 51), "record", 48)
    text_at(Vector2(1102, 65), "DIG RECORD", 21, WHITE, true)
    text_at(Vector2(1102, 101), "%d digs   /   %d clears" % [game.meta.runs, game.meta.wins], 24, YELLOW)
    window(Vector2(1020, 164), Vector2(372, 112))
    text_at(Vector2(1042, 200), "ACCOUNT", 22, WHITE, true)
    paragraph(Vector2(1042, 237), account_copy.detail, 328, 23, CYAN, 2)
    window(Vector2(1020, 348), Vector2(372, 200), Color(0.06, 0.16, 0.40, 0.96))
    draw_texture_rect(portraits[game.selected_character], Rect2(1042, 370, 80, 90), false)
    text_at(Vector2(1136, 410), DiverCharacter.DISPLAY_NAMES[game.selected_character], 25, YELLOW, true, 236)
    paragraph(Vector2(1042, 498), "Choose your digger in Solo preparation or the online lobby.", 328, 23, MUTED, 2)
    window(Vector2(1020, 574), Vector2(372, 274), Color(0.06, 0.16, 0.40, 0.94))
    text_at(Vector2(1044, 613), "CONTROLLER" if pad() else "CONTROLS", 24, WHITE, true)
    var controls = [["move", "Move"], ["fire", "Fire buster"], ["dash", "Dash"], ["jump", "Jump"], ["interact", "Salvage / use"], ["lock_on", "Lock on"]]
    for i in controls.size():
        var y = 636 + i * 32
        keycap(Vector2(1044, y), p(controls[i][0]), 76)
        text_at(Vector2(1140, y + 23), controls[i][1], 23)

func draw_handheld_title() -> void:
    var extra = ui_offset / ui_scale
    rect(-extra, Vector2(extra.x + 610, BASE.y + extra.y * 2), Color(0.055, 0.14, 0.36, 0.96))
    for y in range(0, 900, 256): draw_texture_rect(pattern, Rect2(0, y, 610, 256), true, Color(0.65, 0.8, 1, 0.26))
    draw_line(Vector2(610, 0), Vector2(610, 900), EDGE, 3)
    text_at(Vector2(62, 66), "MEGA MAN LEGENDS", 26, CYAN, true)
    text_at(Vector2(62, 160), "RELIC", 84, YELLOW, true)
    text_at(Vector2(62, 266), "DIVER", 100, WHITE, true)
    text_at(Vector2(66, 312), "THE TIDAL ARCHIVE", 24, CYAN, true)
    var account_copy = title_account_copy()
    var menu_y = 340
    var saved: Dictionary = game.saved_dig
    if not saved.is_empty():
        button(Vector2(64, menu_y), Vector2(500, 54), "Rejoin Dig" if saved.get("online", false) else "Continue Dig", "continue", 0, true)
        menu_y += 60
    var actions = [["Solo Dig / New Dig" if not saved.is_empty() else "Solo Dig", "solo"], ["Play Online", "online"], ["Workshop", "workshop"], ["Options", "options"], [account_copy.label, "account"], ["Credits / Licenses", "credits"], ["Parts Collection", "archive"]]
    if not OS.has_feature("web"): actions.append(["Quit", "quit"])
    for entry in actions:
        button(Vector2(64, menu_y), Vector2(500, 54), entry[0], entry[1], 0, entry[1] == "solo")
        menu_y += 60
    window(Vector2(1020, 32), Vector2(372, 110))
    text_at(Vector2(1042, 74), "DIG RECORD", 22, WHITE, true)
    text_at(Vector2(1042, 116), "%d digs / %d clears" % [game.meta.runs, game.meta.wins], 25, YELLOW)
    window(Vector2(1020, 166), Vector2(372, 150))
    text_at(Vector2(1042, 206), "ACCOUNT", 22, WHITE, true)
    paragraph(Vector2(1042, 250), account_copy.detail, 328, 25, CYAN, 2)
    window(Vector2(1020, 352), Vector2(372, 232))
    draw_texture_rect(portraits[game.selected_character], Rect2(1042, 374, 80, 90), false)
    paragraph(Vector2(1136, 414), DiverCharacter.DISPLAY_NAMES[game.selected_character], 232, 26, YELLOW, 2)
    paragraph(Vector2(1042, 510), "Choose a digger in Solo or the online lobby.", 328, 24, MUTED, 2)
    window(Vector2(1020, 620), Vector2(372, 236))
    text_at(Vector2(1042, 660), "CONTROLS", 24, WHITE, true)
    paragraph(Vector2(1042, 708), "Left / right: select. A: accept. B: back." if pad() else "Arrows: select. Enter: accept. Esc: back.", 328, 26, WHITE, 3)
    text_at(Vector2(1042, 830), "Options: UI / text preset", 21, CYAN, false, 328)

func draw_solo_prep() -> void:
    # Keep the supplied model and ruins visible between the cobalt side panels.
    text_at(Vector2(64, 110), "SOLO DIG", 48, YELLOW, true)
    text_at(Vector2(66, 157), "Choose your digger. Run parts and levels reset each dig.", 26, WHITE)
    window(Vector2(64, 210), Vector2(490, 594))
    var character = game.selected_character
    text_at(Vector2(90, 260), DiverCharacter.DISPLAY_NAMES[character], 34, YELLOW, true, 438)
    text_at(Vector2(90, 320), "SIGNATURE ATTACK", 22, CYAN, true)
    text_at(Vector2(90, 366), game.WEAPONS[game.selected_weapon], 28, WHITE, true, 438)
    paragraph(Vector2(90, 410), DiverPlayer.ATTACK_DETAILS[character], 438, 25, WHITE, 3)
    rect(Vector2(90, 492), Vector2(438, 2), EDGE)
    text_at(Vector2(90, 542), "EQUIPPED SPECIALIZATION", 22, CYAN, true)
    var equipped = DiverProgression.spec(character, game.equipped_spec(character))
    text_at(Vector2(90, 588), equipped.get("name", "None equipped"), 28, YELLOW, true, 438)
    paragraph(Vector2(90, 632), equipped.get("desc", "Unlock and equip specializations in the Workshop."), 438, 24, MUTED, 5)
    var area = Rect2(600, 210, 390, 524)
    var hot = focus_index in [0, 1, 2, 3]
    draw_rect(area, YELLOW if hot else EDGE, false, 3)
    text_at(Vector2(620, 710), DiverCharacter.DISPLAY_NAMES[character], 28, YELLOW, true, 350)
    hits.append({"rect": area, "action": "solo_character", "value": 0})
    small_button(Vector2(600, 756), Vector2(64, 48), "<", "solo_cycle", -1)
    button(Vector2(680, 756), Vector2(230, 48), "Accept" if handheld() else "Accept digger", "solo_character")
    small_button(Vector2(926, 756), Vector2(64, 48), ">", "solo_cycle", 1)
    window(Vector2(1020, 560), Vector2(372, 244))
    button(Vector2(1042, 584), Vector2(328, 64), confirm_label("start_new", 0, "Start Dig"), "launch_solo", 0, true)
    button(Vector2(1042, 714), Vector2(328, 64), "Back to Title", "title")
    paragraph(Vector2(1042, 678), "Starts a new dig." if game.saved_dig.is_empty() else "Replaces your saved dig.", 328, 22, MUTED, 1)
    window(Vector2(64, 830), Vector2(1312, 54), INK, EDGE, false)
    if handheld():
        text_at(Vector2(84, 853), "Left / Right: Digger    Up / Down: Selection / Start / Back", 21, WHITE)
        text_at(Vector2(84, 882), "A: Accept / Start    B: Back" if pad() else "Enter: Accept / Start    Esc: Back", 21, YELLOW)
    else:
        text_at(Vector2(84, 865), "Left / Right: Digger    Up / Down: Selection / Start / Back", 23, WHITE)
        text_at(Vector2(832, 865), "A: Accept / Start    B: Back" if pad() else "Enter: Accept / Start    Esc: Back", 23, YELLOW)

# `overlay`: drawn beneath the pick overlay, keeping Life, map, team, boss and
# warnings while leaving out the aim reticle and banners the cards replace.
func draw_hud(overlay: bool = false) -> void:
    var p = game.player
    text_at(Vector2(34, 38), DiverCharacter.SHORT_NAMES[p.character], 24, WHITE, true)
    window(Vector2(30, 52), Vector2(78, 86), BLUE)
    draw_texture_rect(portrait(), Rect2(34, 55, 70, 79), false)
    text_at(Vector2(34, 166), "LIFE", 18, WHITE, true)
    window(Vector2(43, 180), Vector2(32, 222), INK)
    for i in 12:
        var filled = float(i) / 12 < p.hp / p.max_hp() and p.hp > 0
        var y = 382 - i * 17
        var col = GREEN if p.hp > p.max_hp() * 0.3 else ORANGE
        rect(Vector2(49, y), Vector2(20, 14), col if filled else Color("244574"))
        if filled: rect(Vector2(50, y + 1), Vector2(18, 3), Color("e1f7af"))
    text_at(Vector2(27, 434), "%03d" % int(p.hp), 27, WHITE, true)
    text_at(Vector2(28, 459), "/ %d" % int(p.max_hp()), 20, MUTED)
    window(Vector2(132, 55), Vector2(118, 47), Color(0.05, 0.13, 0.35, 0.88))
    text_at(Vector2(148, 87), "Lv. %02d" % p.level, 25, YELLOW, true)
    window(Vector2(430, 22), Vector2(580, 49), Color(0.05, 0.13, 0.35, 0.86))
    text_at(Vector2(451, 55), "B%d  %s" % [game.depth, game.DEPTH_NAMES[game.depth - 1]], 23, WHITE, true, 538)
    text_at(Vector2(450, 96), "Find the guardian and restore the lift." if not game.guardian_dead else "The lift is ready. Head for the beacon.", 23, YELLOW)
    var map_side = 256.0 if game.settings.large_minimap else 192.0
    var map_x = 1392 - map_side
    window(Vector2(map_x - 14, 28), Vector2(map_side + 30, map_side + 52), Color(0.05, 0.13, 0.35, 0.88))
    text_at(Vector2(map_x + 3, 57), "RUINS MAP", 19, WHITE, true)
    map_at(Vector2(map_x, 72), map_side)
    var map_bottom = 72 + map_side
    icon(Vector2(map_x - 16, map_bottom + 25), "scrap", 45)
    text_at(Vector2(map_x + 36, map_bottom + 59), "%06d" % game.scrap, 29, YELLOW, true)
    text_at(Vector2(map_x + 22, map_bottom + 92), game.time_string(), 24, WHITE, true)
    text_at(Vector2(map_x - 12, map_bottom + 127), "%d / %d rooms" % [visited_count(), game.rooms.size()], 21, WHITE)
    var center = Vector2(720, 450)
    var spread = 5.0 + p.recoil * 5
    if not overlay:
        for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
            draw_line(center + dir * spread, center + dir * (spread + 6), INK, 4)
            draw_line(center + dir * spread, center + dir * (spread + 6), WHITE, 2)
        draw_circle(center, 2, YELLOW)
        if game.hit_confirm > 0:
            for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]: draw_line(center + dir * 14, center + dir * 21, GREEN if game.kill_confirm > 0 else YELLOW, 3)
        if game.kill_confirm > 0: text_at(center + Vector2(-40, 45), "SALVAGED", 18, GREEN)
    if is_instance_valid(p.lock_target) and not overlay:
        var enemy = p.lock_target
        var at = enemy.global_position + Vector3.UP * (2.5 if enemy.kind == 3 else 1.2)
        if not p.camera.is_position_behind(at):
            var screen = (p.camera.unproject_position(at) - ui_offset) / ui_scale
            for sign_x in [-1, 1]:
                for sign_y in [-1, 1]:
                    var corner = screen + Vector2(sign_x * 34, sign_y * 34)
                    draw_line(corner, corner - Vector2(sign_x * 13, 0), YELLOW, 3)
                    draw_line(corner, corner - Vector2(0, sign_y * 13), YELLOW, 3)
            text_at(screen + Vector2(-31, -48), "LOCK ON", 18, YELLOW)
    for enemy in game.enemies:
        if not is_instance_valid(enemy) or enemy.dead or enemy.kind != 3 or not enemy.active: continue
        window(Vector2(440, 120), Vector2(560, 66), Color(0.08, 0.13, 0.34, 0.92))
        icon(Vector2(449, 130), "eye", 43)
        text_at(Vector2(504, 148), game.BOSS_NAMES[game.depth - 1], 22, WHITE, true)
        pips(Vector2(505, 160), 465, 12, maxf(0, enemy.health / enemy.max_health), 24, ORANGE)
        if enemy.state == "windup":
            window(Vector2(472, 198), Vector2(496, 39), INK, YELLOW)
            icon(Vector2(480, 201), "warning", 31)
            var names = {"slam": "Shockwave! Jump or dash away!", "bombard": "Bombardment! Leave the rings!", "cross": "Cross beam! Clear the lanes!", "fan": "Burst incoming! Keep moving!"}
            text_at(Vector2(522, 226), names.get(enemy.planned, "Watch out!"), 23, YELLOW)
    window(Vector2(30, 738), Vector2(340 if handheld() else 310, 104), Color(0.05, 0.13, 0.35, 0.92))
    icon(Vector2(42, 750), ["pulse", "needle", "siege", "scrap"][p.weapon], 62)
    text_at(Vector2(114, 774), ["Pulse Buster", "Needle Buster", "Siege Buster", "Salvage Bombs"][p.weapon], 25, WHITE, true, 242 if handheld() else 212)
    text_at(Vector2(114, 805), "POWER %d  /  RAPID %.1f" % [buster_power(), 1 / p.fire_delay()], 21, MUTED)
    pips(Vector2(48, 824), 300 if handheld() else 270, 6, float(p.xp) / p.xp_required, 20, YELLOW)
    keycap(Vector2(30, 856), p("parts"), 54)
    var waiting = game.pending_choices.size()
    if waiting > 0:
        var label: String = {"level": "Level Up", "milestone": "Milestone"}.get(str(game.pending_choices[0].get("kind", "relic")), "Choose Part") if waiting == 1 else "Upgrades ×%d" % waiting
        text_at(Vector2(99, 879), label, 21, YELLOW if overlay or int(Time.get_ticks_msec() / 400) % 2 == 0 else WHITE)
    else: text_at(Vector2(99, 879), "Buster Parts", 21)
    var n = 0
    for id in p.items:
        var x = 382 + n * 53
        window(Vector2(x, 792), Vector2(48, 53), BLUE, EDGE, false)
        icon(Vector2(x + 2, 792), id, 44)
        var count_text = str(p.items[id])
        var count_width = maxf(30, heading.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, readable_size(20)).x + 18)
        badge(Vector2(x + 48 - count_width, 830), count_text, count_width)
        n += 1
    if n == 0:
        icon(Vector2(382, 798), "cache", 46)
        text_at(Vector2(438, 830), "Find a cache to collect your first part.", 23, WHITE)
    icon(Vector2(1230, 754), "dash", 48)
    text_at(Vector2(1290, 779), "DASH", 20, WHITE, true)
    text_at(Vector2(1290, 809), "Ready" if p.dash_cooldown <= 0 else "Charging", 22, YELLOW if p.dash_cooldown <= 0 else MUTED)
    pips(Vector2(1240, 825), 156, 7, clampf(1 - p.dash_cooldown / 1.35, 0, 1), 8, CYAN)
    keycap(Vector2(1240, 856), p("menu"), 54)
    text_at(Vector2(1308, 879), "Menu", 21)
    if game.net.active():
        draw_team()
        draw_chat(Vector2(1060, 700), 352, 6, not game.chat_open)
        if game.chat_open:
            place_field(chat_edit, Vector2(1056, 708), Vector2(356, 40), 21)
            if not chat_edit.has_focus(): chat_edit.grab_focus()
        elif overlay: pass
        elif pad(): text_at(Vector2(1064, 734), "%s ping  ·  D-pad callouts" % p("ping"), 19, MUTED)
        else: text_at(Vector2(1064, 734), "%s chat  ·  %s ping  ·  1–4 callouts" % [p("chat"), p("ping")], 19, MUTED)
        if game.net.reconnecting(): draw_reconnecting()
    if game.message_time > 0 and not overlay: draw_notice()
    if not game.nearest.is_empty() and game.mode == "play" and not p.downed: interaction_prompt()
    if game.mode == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless" and not pad() and not OS.has_feature("android"):
        window(Vector2(560, 384), Vector2(320, 46), INK, YELLOW, false)
        text_at(Vector2(584, 415), "Click to take aim", 24, YELLOW, true)
    if game.hurt_flash > 0: rect(Vector2.ZERO, BASE, Color(0.9, 0.2, 0.08, game.hurt_flash * 0.25))

func draw_notice() -> void:
    window(Vector2(402, 630), Vector2(636, 98), Color(0.06, 0.16, 0.39, 0.96))
    icon(Vector2(419, 647), {"PART CHOICE WAITING": "cache", "LEVEL UP!": "xp", "UPGRADES FULL": "warning"}.get(game.message, "record"), 48)
    var title: String = {"CHAMBER SECURED": "Room Cleared!", "GUARDIAN SILENCED": "Guardian Defeated!", "BUSTER CALIBRATED": "Power Increased!", "CORE EXPANDED": "Life Increased!", "CAPACITOR TUNED": "Rapid Fire Increased!", "SYSTEMS RESTORED": "Life Restored!", "INSUFFICIENT SCRAP": "Not Enough Scrap", "CACHE SEALED": "Cache Sealed", "LIFT SEALED": "Lift Sealed", "PART CHOICE WAITING": "Part Choice Waiting!", "LEVEL UP!": "Level Up!", "MILESTONE READY": "Milestone Ready!", "UPGRADES FULL": "Upgrade Queue Full"}.get(game.message, game.message)
    var detail: String = game.message_detail
    if game.message.begins_with("DESCENT"): title = "Entering B%d" % game.depth
    if game.message == "CHAMBER SECURED": detail = "+5 Scrap. Part caches are now available."
    if game.message == "GUARDIAN SILENCED": detail = "The lift is ready. Salvage the area, then head for the beacon."
    text_at(Vector2(483, 664), title, 23, YELLOW, true, 533)
    paragraph(Vector2(483, 690), detail, 530, 22, WHITE, 2)

func interaction_prompt() -> void:
    var obj = game.nearest
    window(Vector2(450, 731), Vector2(540, 49), BLUE, YELLOW)
    keycap(Vector2(462, 741), p("interact"), 33)
    var title: String = {"cache": "Open Part Cache", "spring": "Use Restoration Well", "pot": "Salvage Vessel", "lift": "Extract" if game.depth == 3 else "Take the Lift"}.get(obj.kind, obj.title)
    if obj.kind == "lift" and not game.guardian_dead: title = "Lift sealed — defeat the guardian"
    # Unpicked upgrades expire at extraction; say so before the press.
    elif obj.kind == "lift" and game.depth == 3 and not game.pending_choices.is_empty(): title = "Extract · %d unpicked expire" % game.pending_choices.size()
    elif obj.kind == "cache" and not game.rooms[obj.room].cleared: title = "Clear the room to open this cache"
    text_at(Vector2(510, 764), title, 23, WHITE, false, 376 if obj.cost == 0 else 325)
    if obj.cost > 0:
        icon(Vector2(892, 738), "scrap", 31)
        text_at(Vector2(933, 764), str(obj.cost), 23, YELLOW, true)

func map_at(pos: Vector2, side: float) -> void:
    rect(pos, Vector2.ONE * side, Color("0c2456"))
    # The map is the floor plan to zoom, north up: rooms and corridors sit
    # where they really are, and the arrow is the digger's exact position.
    var low = Vector2(INF, INF)
    var high = Vector2(-INF, -INF)
    for room in game.rooms:
        var middle = Vector2(room.center.x, room.center.z)
        low = low.min(middle - room.half)
        high = high.max(middle + room.half)
    var span = high - low
    var zoom = (side - 20) / maxf(1.0, maxf(span.x, span.y))
    var origin = pos + (Vector2.ONE * side - span * zoom) * 0.5 - low * zoom
    var bounds = Rect2(pos + Vector2.ONE * 4, Vector2.ONE * (side - 8))
    if game.settings.map_zoom:
        zoom = (side - 8) / 80.0
        origin = pos + Vector2.ONE * side * 0.5 - Vector2(game.player.position.x, game.player.position.z) * zoom
    var clip_polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
    var known = []
    for i in game.rooms.size(): known.append(game.rooms[i].visited)
    for link in game.links:
        if not (game.rooms[link.a].visited or game.rooms[link.b].visited): continue
        known[link.a] = true
        known[link.b] = true
        for segment in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([origin + link.from * zoom, origin + link.to * zoom]), clip_polygon):
            draw_polyline(segment, Color("5077b0"), maxf(2.0, 3.5 * zoom))
    for i in game.rooms.size():
        if not known[i]: continue
        var room = game.rooms[i]
        var corner = origin + (Vector2(room.center.x, room.center.z) - room.half) * zoom
        var size: Vector2 = room.half * 2 * zoom
        var area = Rect2(corner, size).intersection(bounds)
        if not area.has_area(): continue
        corner = area.position
        size = area.size
        rect(corner, size, CYAN if i == game.current_room else YELLOW if i == game.exit_room else EDGE)
        rect(corner + Vector2.ONE, (size - Vector2.ONE * 2).max(Vector2.ZERO), Color("3f7fc4") if i == game.current_room else Color("668daf") if room.cleared and room.visited else Color("224779") if room.visited else INK)
        if i == game.exit_room and bounds.has_point(origin + Vector2(room.center.x, room.center.z) * zoom): draw_circle(origin + Vector2(room.center.x, room.center.z) * zoom, 2.5, YELLOW)
    var marker_scale = 1.3 if game.settings.large_minimap else 1.0
    var inside = Rect2(pos + Vector2.ONE * 4, Vector2.ONE * (side - 8)).grow(-10 if game.settings.large_minimap else 0)
    # Part caches in revealed rooms: grey while the room is sealed, gold when
    # ready, flashing cyan while this digger's pick from it waits, dim once opened.
    for i in game.interactables.size():
        var obj: Dictionary = game.interactables[i]
        if obj.kind != "cache" or not game.rooms[obj.room].visited: continue
        var at = origin + Vector2(obj.node.position.x, obj.node.position.z) * zoom
        if not bounds.has_point(at): continue
        var color = MUTED if not game.rooms[obj.room].cleared else YELLOW
        if game.choice_waiting(i): color = CYAN if int(Time.get_ticks_msec() / 300) % 2 == 0 else WHITE
        elif obj.used: color = Color("4d6690")
        rect(at - Vector2(5, 4), Vector2(10, 8), INK)
        rect(at - Vector2(4, 3), Vector2(8, 6), color)
        rect(at - Vector2(4, 0.5), Vector2(8, 1), INK)
    for mate in game.remote_players.values():
        if not is_instance_valid(mate): continue
        var at = (origin + Vector2(mate.global_position.x, mate.global_position.z) * zoom).clamp(inside.position, inside.end)
        draw_circle(at, 3.5 * marker_scale, INK)
        draw_circle(at, 2.5 * marker_scale, ORANGE if mate.downed else DiverNet.SLOT_COLORS[clampi(mate.slot, 0, 4)])
    var p = game.player
    var here = (origin + Vector2(p.global_position.x, p.global_position.z) * zoom).clamp(inside.position, inside.end)
    var forward = Vector2(-sin(p.yaw), -cos(p.yaw)) * marker_scale
    var right = Vector2(-forward.y, forward.x)
    draw_colored_polygon(PackedVector2Array([here + forward * 10.5, here - forward * 6.5 + right * 7.2, here - forward * 3, here - forward * 6.5 - right * 7.2]), INK)
    draw_colored_polygon(PackedVector2Array([here + forward * 8.2, here - forward * 4.9 + right * 5.2, here - forward * 2.2, here - forward * 4.9 - right * 5.2]), WHITE)

func visited_count() -> int:
    var n = 0
    for room in game.rooms:
        if room.visited: n += 1
    return n

func draw_pause() -> void:
    backdrop()
    stats_header()
    page_title("DIG MENU", "B%d / %s" % [game.depth, game.DEPTH_NAMES[game.depth - 1]] + ("   ·   The dig continues while this menu is open." if game.net.active() else ""))
    button(Vector2(64, 288), Vector2(400, 62), "Return to Ruins", "resume", 0, true)
    button(Vector2(64, 366), Vector2(400, 62), "Buster Parts", "inventory")
    button(Vector2(64, 444), Vector2(400, 62), "Options", "options")
    # Anyone can leave; online, the others keep digging (hosting moves on).
    button(Vector2(64, 522), Vector2(400, 62), confirm_label("leave_dig", 0, "Leave Dig"), "leave_dig")
    if game.net.is_host(): button(Vector2(64, 600), Vector2(400, 62), confirm_label("abandon", 0, "End Dig for Everyone"), "abandon")
    window(Vector2(508, 280), Vector2(868, 392))
    window(Vector2(536, 308), Vector2(178, 226), BLUE)
    draw_texture_rect(portrait(), Rect2(542, 319, 166, 187), false)
    text_at(Vector2(548, 556), DiverCharacter.DISPLAY_NAMES[game.player.character], 24)
    text_at(Vector2(752, 335), "EQUIPMENT", 28, WHITE, true)
    icon(Vector2(752, 358), ["pulse", "needle", "siege", "scrap"][game.player.weapon], 68)
    text_at(Vector2(840, 402), ["Pulse Buster", "Needle Buster", "Siege Buster", "Salvage Bombs"][game.player.weapon], 30, YELLOW)
    stat_line(Vector2(752, 464), "Power", "%.1f" % buster_power(), 560)
    stat_line(Vector2(752, 509), "Fire rate", "%.1f / sec" % (1 / game.player.fire_delay()), 560)
    stat_line(Vector2(752, 554), "Run speed", "%.1f" % game.player.speed(), 560)
    stat_line(Vector2(752, 599), "Fitted parts", str(total_parts()), 560)
    window(Vector2(64, 706), Vector2(1312, 106))
    icon(Vector2(86, 725), "warning", 58)
    paragraph(Vector2(164, 744), "Watch the ground before an enemy attacks. Leave the warning area, jump over shockwaves, or dash through danger. Use cover to break a machine's aim.", 1176, 26, WHITE, 2)
    menu_footer("Select", "Return")

func option_label(id: String) -> String:
    return {"master": "Master volume", "music": "Music", "effects": "Effects", "ambience": "Ambience", "mute": "Mute all", "fullscreen": "Fullscreen", "camera": "Camera motion", "fov": "Field of view", "mouse": "Mouse sensitivity", "look": "Controller look speed", "invert": "Invert look (up/down)", "vibration": "Controller vibration", "controls": "Controls & bindings…", "map_zoom": "Ruins map", "handheld_ui": "UI / text preset", "large_minimap": "Minimap size", "close_camera": "Camera framing", "controller_test": "Controller test…", "back": "Back"}.get(id, id)

func option_value(id: String) -> String:
    var s = game.settings
    match id:
        "master", "music", "effects", "ambience": return "%d%%" % roundi(game.sound.volumes[id.capitalize()] * 100)
        "mute": return "On" if game.sound.muted else "Off"
        "fullscreen": return "On" if s.fullscreen else "Off"
        "map_zoom": return "Follow / zoomed" if s.map_zoom else "Whole floor"
        "handheld_ui": return "Handheld" if s.handheld_ui else "Standard"
        "large_minimap": return "Large" if s.large_minimap else "Standard"
        "close_camera": return "Close" if s.close_camera else "Standard"
        "camera": return "On" if s.camera_effects else "Off"
        "fov": return "%d°" % int(s.fov)
        "mouse": return "%.1f×" % s.mouse_sensitivity
        "look": return "%.1f×" % s.look_speed
        "invert": return "On" if s.invert_y else "Off"
        "vibration": return "On" if s.vibration else "Off"
    return ""

# Left/right adjusts sliders and flips switches.
func adjust_option(index: int, delta: int) -> void:
    var id: String = OPTIONS[index]
    var s = game.settings
    match id:
        "master", "music", "effects", "ambience": game.sound.adjust_volume(id.capitalize(), delta * 0.05)
        "fov": s.fov = clampf(s.fov + delta * 2, 55, 85)
        "mouse": s.mouse_sensitivity = clampf(snappedf(s.mouse_sensitivity + delta * 0.1, 0.1), 0.2, 3.0)
        "look": s.look_speed = clampf(snappedf(s.look_speed + delta * 0.1, 0.1), 0.2, 3.0)
        "mute", "fullscreen", "camera", "invert", "vibration", "map_zoom", "handheld_ui", "large_minimap", "close_camera": activate_option(index)
        _: return
    s.save_settings()

# Enter / A / click: toggle, or step a slider up (wrapping).
func activate_option(index: int) -> void:
    var id: String = OPTIONS[clampi(index, 0, OPTIONS.size() - 1)]
    var s = game.settings
    focus_index = index
    match id:
        "master", "music", "effects", "ambience":
            var bus = id.capitalize()
            game.sound.adjust_volume(bus, -1.0 if game.sound.volumes[bus] >= 0.99 else 0.10)
        "mute": game.sound.muted = not game.sound.muted
        "fullscreen": s.set_fullscreen(not s.fullscreen)
        "map_zoom": s.map_zoom = not s.map_zoom
        "handheld_ui": s.handheld_ui = not s.handheld_ui
        "large_minimap": s.large_minimap = not s.large_minimap
        "close_camera": s.close_camera = not s.close_camera
        "camera": s.camera_effects = not s.camera_effects
        "fov": s.fov = 55.0 if s.fov >= 85 else s.fov + 5
        "mouse": s.mouse_sensitivity = 0.2 if s.mouse_sensitivity >= 3.0 else snappedf(s.mouse_sensitivity + 0.2, 0.1)
        "look": s.look_speed = 0.2 if s.look_speed >= 3.0 else snappedf(s.look_speed + 0.2, 0.1)
        "invert": s.invert_y = not s.invert_y
        "vibration":
            s.vibration = not s.vibration
            s.rumble(0.4, 0.4, 0.15)
        "controls": game.mode = "controls"
        "controller_test":
            controller_sample_at = 0
            controller_raw_page = 0
            game.mode = "controller_test"
            game.pad_held.clear()
            return
        "back": activate(options_return)
    s.save_settings()

func option_row(pos: Vector2, index: int) -> void:
    var id: String = OPTIONS[index]
    var area = Rect2(pos, Vector2(640, 48))
    var hot = focus_index == index or area.has_point(pointer)
    window(pos, area.size, SELECT if hot else PANEL, YELLOW if hot else EDGE, false)
    if hot: cursor(pos + Vector2(-30, 12))
    text_at(pos + Vector2(22, 36), option_label(id), 25, WHITE, false, 340)
    var value = option_value(id)
    if value != "":
        if id in ["master", "music", "effects", "ambience"]:
            pips(pos + Vector2(330, 21), 180, 12, game.sound.volumes[id.capitalize()], 12, CYAN if id == "music" else GREEN)
        text_at(pos + Vector2(612 - heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, readable_size(22)).x, 36), value, 22, YELLOW, true)
    hits.append({"rect": area, "action": "option", "value": index})

func draw_options() -> void:
    backdrop()
    page_title("OPTIONS", "Sound, display and controls. Changes save right away%s." % (" in this browser" if OS.has_feature("web") else " on this PC"))
    text_at(Vector2(66, 278), "SOUND & CAMERA", 20, CYAN, true)
    text_at(Vector2(738, 278), "INPUT & READABILITY", 20, CYAN, true)
    for i in OPTIONS.size():
        option_row(Vector2(64, 292 + i * 52) if i < 9 else Vector2(736, 292 + (i - 9) * 52), i)
    text_at(Vector2(66, 830), "Left / right adjusts. Readability and camera preferences save on this device.", 20, MUTED, false, 1310)
    menu_footer("Select", "Back", "Change")

func cycle_controller(delta: int) -> void:
    var devices = Input.get_connected_joypads()
    if devices.is_empty(): controller_device = -1
    else: controller_device = devices[wrapi(devices.find(controller_device) + delta, 0, devices.size())]
    controller_raw_page = 0
    controller_sample_at = 0

func sample_controller() -> Dictionary:
    var devices = Input.get_connected_joypads()
    if controller_device not in devices: controller_device = devices[0] if not devices.is_empty() else -1
    return DiverControllerProbe.sample(controller_device)

func probe_axes(pos: Vector2, values: Array, raw: bool) -> void:
    var start = controller_raw_page * 8 if raw else 0
    var count = mini(8, maxi(0, values.size() - start))
    for row in count:
        var index = start + row
        var value = float(values[index])
        var at = pos + Vector2(0, row * (21 if raw else 24))
        var label = "Axis %d" % index if raw else DiverControllerProbe.AXIS_LABELS[index]
        text_at(at + Vector2(0, 19), label, 19, WHITE, false, 190)
        var bar = at + Vector2(200, 5)
        rect(bar, Vector2(230, 15), INK)
        draw_line(bar + Vector2(115, 0), bar + Vector2(115, 15), EDGE, 1)
        rect(bar + Vector2(minf(115, 115 + value * 115), 2), Vector2(maxf(2, absf(value) * 115), 11), GREEN if value >= 0 else CYAN)
        text_at(at + Vector2(450, 19), "%+.3f" % value, 19, YELLOW)

func probe_buttons(pos: Vector2, values: Array, raw: bool) -> void:
    var start = controller_raw_page * 16 if raw else 0
    for i in mini(24 if not raw else 16, maxi(0, values.size() - start)):
        var index = start + i
        var columns = 4 if raw else 8
        var at = pos + Vector2((i % columns) * (144 if raw else 72), (i / columns) * (26 if raw else 30))
        var down = float(values[index]) > 0.1
        window(at, Vector2(136 if raw else 64, 24 if raw else 26), SELECT if down else INK, YELLOW if down else EDGE, false)
        text_at(at + Vector2(7, 20), "%d: %.2f" % [index, float(values[index])] if raw else str(index), 19, YELLOW if down else MUTED)

func draw_controller_test() -> void:
    backdrop()
    page_title("CONTROLLER TEST", "Move sticks / press buttons. Read-only: bindings and deadzones stay as they are.")
    if controller_snapshot.is_empty() or Time.get_ticks_msec() >= controller_sample_at:
        controller_snapshot = sample_controller()
        controller_sample_at = Time.get_ticks_msec() + 50
    var info = controller_snapshot
    window(Vector2(64, 276), Vector2(1312, 118))
    text_at(Vector2(86, 312), "Godot pad #%d: %s" % [controller_device, str(info.name)] if info.connected else "No controller detected — connect a pad and move a stick.", 25, YELLOW, false, 1266)
    text_at(Vector2(86, 349), "GUID: " + str(info.guid), 22, CYAN, false, 1266)
    text_at(Vector2(86, 380), ("Known mapping" if info.known else "Unknown mapping") + " / " + controller_last_button, 21, MUTED, false, 1266)
    window(Vector2(64, 414), Vector2(640, 366))
    window(Vector2(736, 414), Vector2(640, 366))
    text_at(Vector2(86, 449), "GODOT AXES / BUTTON NUMBERS", 22, CYAN, true)
    if info.connected:
        probe_axes(Vector2(86, 470), info.axes, false)
        probe_buttons(Vector2(86, 654), info.buttons, false)
    else: paragraph(Vector2(86, 510), "Waiting for a controller. No input settings are changed here.", 590, 25, MUTED, 3)
    var browser = info.browser
    var raw: Dictionary = {}
    for entry in browser:
        if int(entry.index) == controller_device: raw = entry
    if raw.is_empty() and browser.size() == 1: raw = browser[0]
    if not raw.is_empty():
        text_at(Vector2(758, 449), "RAW BROWSER #%d / %s" % [int(raw.index), str(raw.mapping) if raw.mapping != "" else "non-standard"], 22, CYAN, true, 592)
        probe_axes(Vector2(758, 470), raw.axes, true)
        probe_buttons(Vector2(758, 650), raw.buttons, true)
        text_at(Vector2(758, 778), "%d axes / %d buttons / %s" % [raw.axes.size(), raw.buttons.size(), str(raw.name)], 19, MUTED, false, 592)
    else:
        text_at(Vector2(758, 449), "RAW BROWSER INPUT", 22, CYAN, true)
        paragraph(Vector2(758, 510), "Raw browser values are available in the Web build." if not OS.has_feature("web") else "No raw browser pad available. Press a button to let the browser detect it.", 592, 25, MUTED, 4)
    if info.devices.size() > 1:
        button(Vector2(64, 800), Vector2(260, 56), "Previous pad", "controller_cycle", -1)
        button(Vector2(340, 800), Vector2(260, 56), "Next pad", "controller_cycle", 1)
    if not raw.is_empty(): button(Vector2(620, 800), Vector2(380, 56), "Raw page %d / 4" % [controller_raw_page + 1], "controller_raw_page")
    button(Vector2(1020, 800), Vector2(356, 56), "Back", "options")
    text_at(Vector2(66, 884), "B / Esc: Return     Keyboard Left / Right: Pad     A is tested here; it does not close the page.", 21, MUTED, false, 1310)

func draw_controls() -> void:
    backdrop()
    if not listening.is_empty():
        listening.time -= get_process_delta_time()
        if listening.time <= 0: listening = {}
    page_title("CONTROLS", "Select a binding, then press the new key, mouse button or controller button.")
    var actions = DiverSettings.ACTIONS
    var s = game.settings
    for i in actions.size():
        var column = 0 if i < 9 else 1
        var row = i if i < 9 else i - 9
        var pos = Vector2(64 + column * 672, 300 + row * 52)
        text_at(pos + Vector2(0, 32), actions[i].name, 22, WHITE, false, 280)
        for c in 2:
            var cell = Rect2(pos + Vector2(300 + c * 166, 0), Vector2(156, 44))
            var index = i * 2 + c
            var hot = focus_index == hits.size() or cell.has_point(pointer)
            var waiting = not listening.is_empty() and listening.id == actions[i].id and listening.column == ["kb", "pad"][c]
            window(cell.position, cell.size, YELLOW.darkened(0.55) if waiting else SELECT if hot else INK, YELLOW if hot or waiting else EDGE, false)
            var label = "Press…" if waiting else s.binding_label(s.bindings[actions[i].id]["kb" if c == 0 else "pad"])
            if c == 1 and label == "—" and actions[i].id.begins_with("move_"): label = "L-Stick"
            text_at(cell.position + Vector2(14, 30), label, 21, YELLOW if waiting else WHITE, false, 132)
            hits.append({"rect": cell, "action": "bind", "value": index})
    text_at(Vector2(364, 290), "KEYBOARD", 17, CYAN, true)
    text_at(Vector2(530, 290), "CONTROLLER", 17, CYAN, true)
    text_at(Vector2(1036, 290), "KEYBOARD", 17, CYAN, true)
    text_at(Vector2(1202, 290), "CONTROLLER", 17, CYAN, true)
    button(Vector2(736, 726), Vector2(310, 54), confirm_label("reset_controls", 0, "Reset to Defaults"), "reset_controls")
    button(Vector2(1066, 726), Vector2(310, 54), "Back", "options", 0, true)
    var note = "Waiting for input… (Esc cancels)" if not listening.is_empty() else ("Right stick: look. Reused bindings swap actions." if handheld() else "The right stick always looks around. Taking a key from another action swaps them.")
    text_at(Vector2(736, 812), note, 21, YELLOW if not listening.is_empty() else MUTED, false, 640)
    menu_footer("Select", "Options", "Rebind")

func stat_line(pos: Vector2, title: String, value: String, width: float) -> void:
    text_at(pos, title, 26, MUTED)
    draw_line(pos + Vector2(0, 12), pos + Vector2(width, 12), Color("416399"), 1)
    text_at(pos + Vector2(width - heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, readable_size(25)).x, 0), value, 25, WHITE, true)

func total_parts() -> int:
    var count = 0
    for id in game.player.items: count += int(game.player.items[id])
    return count

func buster_power() -> float:
    return game.player.damage() * [1.0, 0.55, 2.4, 2.0][game.player.weapon]

func draw_parts(collection: bool) -> void:
    backdrop()
    stats_header()
    page_title("PARTS COLLECTION" if collection else "BUSTER PARTS", "%d machines recorded across your digs" % game.meta.kills if collection else "%d parts fitted / This dig's equipment" % total_parts())
    var ids: Array = game.ITEMS.keys() if collection else game.player.items.keys()
    window(Vector2(64, 276), Vector2(652, 516))
    window(Vector2(744, 276), Vector2(632, 516))
    if ids.is_empty():
        icon(Vector2(264, 379), "cache", 128)
        paragraph(Vector2(128, 565), "No parts fitted yet. Open a golden cache or salvage a machine to find your first one.", 510, 30, WHITE, 3)
        text_at(Vector2(782, 334), "NO PARTS FITTED", 31, YELLOW, true)
        paragraph(Vector2(782, 398), "Every part you collect lasts for this dig. Finding the same part again strengthens its effect.", 550, 29, WHITE, 4)
    else:
        selected_item = clampi(selected_item, 0, ids.size() - 1)
        if selected_item < list_scroll: list_scroll = selected_item
        if selected_item >= list_scroll + 7: list_scroll = selected_item - 6
        for row in mini(7, ids.size() - list_scroll):
            var i = row + list_scroll
            var id: String = ids[i]
            var unlocked = not collection or game.item_unlocked(id)
            var pos = Vector2(80, 290 + row * 68)
            var area = Rect2(pos, Vector2(620, 60))
            if i == selected_item:
                window(pos, area.size, SELECT, YELLOW, false)
                cursor(pos + Vector2(-31, 14))
            icon(pos + Vector2(9, 5), id if unlocked else "lock", 50, Color.WHITE if unlocked else Color("8398bd"))
            text_at(pos + Vector2(78, 38), game.ITEMS[id].name if unlocked else "Unknown Part", 29, WHITE if unlocked else MUTED, false, 420)
            if collection: text_at(pos + Vector2(507, 38), "Found" if game.meta.discovered.has(id) else "Ready" if unlocked else "Sealed", 22, YELLOW if game.meta.discovered.has(id) else MUTED)
            else: text_at(pos + Vector2(524, 39), "×%d" % game.player.count(id), 27, YELLOW, true)
            hits.append({"rect": area, "action": "inspect", "value": i})
        part_detail(Vector2(774, 306), ids[selected_item], collection)
        text_at(Vector2(592, 780), "%02d / %02d" % [selected_item + 1, ids.size()], 20, MUTED)
        if ids.size() > 7: text_at(Vector2(88, 780), "↑↓ / Mouse wheel to browse", 20, MUTED)
    menu_footer("Browse parts", "Title" if collection else "Return", "Return")
    button(Vector2(770, 826), Vector2(338, 52), "Return to Title" if collection else "Return to Ruins", "title" if collection else "resume")

func part_detail(pos: Vector2, id: String, collection: bool) -> void:
    var data = game.ITEMS[id]
    var unlocked = not collection or game.item_unlocked(id)
    text_at(pos + Vector2(0, 30), data.name if unlocked else "UNKNOWN PART", 32, WHITE, true, 568)
    text_at(pos + Vector2(0, 68), TYPES[id] if unlocked else "SEALED RECORD", 21, CYAN, true)
    window(pos + Vector2(174, 96), Vector2(212, 192), INK, Color("6285b8"), false)
    icon(pos + Vector2(200, 112), id if unlocked else "lock", 160)
    if unlocked:
        paragraph(pos + Vector2(0, 334), DESCRIPTIONS[id], 568, 28, WHITE, 3)
        var value = "Found on a previous dig" if collection and game.meta.discovered.has(id) else "Available in the ruins" if collection else "Fitted ×%d  /  %s" % [game.player.count(id), current_effect(id)]
        text_at(pos + Vector2(0, 452), value, 24, YELLOW, false, 568)
    else:
        paragraph(pos + Vector2(0, 334), "Defeat %d machines across your digs to unlock this part." % data.unlock, 568, 28, WHITE, 3)
        text_at(pos + Vector2(0, 452), "%d more machines to go" % (data.unlock - game.meta.kills), 24, YELLOW)

func current_effect(id: String) -> String:
    var n = game.player.count(id)
    match id:
        "lens": return "+%d%% power" % (n * 16)
        "spring": return "+%d%% rapid" % (n * 14)
        "heart": return "+%d Life" % (n * 20)
        "boots": return "+%d%% speed" % (n * 9)
        "shell": return "%d%% damage reduction" % int(100 * (1 - 1.0 / (1 + n * 0.18)))
        "moss": return "+%.1f Life per machine" % (n * 1.5)
        "ember": return "%d burn damage per tick" % (n * 2)
        "coil": return "%d%% chain chance" % mini(75, n * 18)
        "prism": return "%d%% critical chance" % mini(60, n * 8)
        "echo": return "%d%% extra-shot chance" % mini(80, n * 12)
        "split": return "Side shots: %d%% power" % int(minf(0.75, 0.25 + n * 0.12) * 100)
        "frost": return "%d seconds of slow" % (2 + n)
        "clover": return "+%.1f%% part drop chance" % (n * 2.5)
    return ""

# Upgrade picks open over the live view: the dig stays visible behind a light
# cobalt dim (it pauses solo and keeps going online), Life, map, team and
# warnings stay on screen, and three cards sit in the clear middle band.
const CHOICE_BAND = Rect2(380, 248, 680, 488)
const CHOICE_FADE_MS = 150.0
const LEVEL_TITLES = ["Buster Power", "Life Expansion", "Rapid Fire"]
const LEVEL_ICONS = ["pulse", "life", "spring"]
const LEVEL_LINES = ["+3 base power", "+20 max Life · heal 35", "+15% base fire rate"]
const LEVEL_DETAILS = ["Adds 3 base buster power. Power-boosting parts multiply the new total.", "Adds 20 maximum Life and restores 35 Life right away.", "Adds 15% base fire rate. Combine it with Clockwork Springs for faster firing."]

func choice_title(i: int) -> String:
    var id: String = game.choice_items[i]
    match game.choice_kind:
        "relic": return game.ITEMS[id].name
        "milestone": return game.MILESTONES[id].name
    return LEVEL_TITLES[i]

func choice_icon(i: int) -> String:
    var id: String = game.choice_items[i]
    match game.choice_kind:
        "relic": return id
        "milestone": return game.MILESTONES[id].icon
    return LEVEL_ICONS[i]

func choice_line(i: int) -> String:
    var id: String = game.choice_items[i]
    match game.choice_kind:
        "relic": return TYPES[id]
        "milestone": return milestone_match(id)
    return LEVEL_LINES[i]

# Centred card text; long names step down a few sizes before being shortened.
func centered(center_x: float, y: float, value: String, size: int, color: Color, display: bool, width: float) -> void:
    var face: Font = heading if display else font
    while size > 18 and face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, readable_size(size)).x > width: size -= 1
    var shown_width = minf(width, face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, readable_size(size)).x)
    text_at(Vector2(center_x - shown_width / 2, y), value, size, color, display, width)

func draw_choice_overlay() -> void:
    var extra = ui_offset / ui_scale
    var fade = clampf((Time.get_ticks_msec() - game.choice_opened_at) / CHOICE_FADE_MS, 0.0, 1.0)
    rect(-extra, BASE + extra * 2, Color(0.02, 0.05, 0.20, 0.30 * fade))
    draw_hud(true)
    var kind: String = game.choice_kind
    var gold = Color("e7b85a")
    var band = Rect2(290, 230, 860, 506) if handheld() else CHOICE_BAND
    # Header: what kind of pick, and where it sits in the queue.
    var total = game.choice_picks + 1 + game.pending_choices.size()
    window(band.position, Vector2(band.size.x, 62), Color(0.05, 0.13, 0.35, 0.94), gold if kind != "relic" else EDGE)
    var title = {"relic": "CHOOSE A PART", "level": "LEVEL UP!", "milestone": "GUARDIAN MILESTONE"}.get(kind, "CHOOSE")
    text_at(band.position + Vector2(24, 42), title, 30, YELLOW if kind != "relic" else WHITE, true, 400)
    if total > 1: text_at(band.position + Vector2(band.size.x - 170, 40), "PICK %d OF %d" % [game.choice_picks + 1, total], 22, CYAN, true, 150)
    else: text_at(band.position + Vector2(band.size.x - 230, 40), "Lasts for this dig", 21, MUTED, false, 210)
    var since = Time.get_ticks_msec() - game.choice_opened_at
    if kind == "level" and game.choice_picks == 0 and since < 650:
        # A brief level-up flash on the header; caches and milestones skip it.
        rect(band.position + Vector2(2, 2), Vector2(band.size.x - 4, 58), Color(1, 0.86, 0.4, 0.38 * (1.0 - since / 650.0)))
    # Three cards side by side.
    choice_preview = clampi(choice_preview, 0, maxi(0, game.choice_items.size() - 1))
    for i in game.choice_items.size():
        var pos = band.position + Vector2(i * ((band.size.x + 22) / 3), 74)
        var size = Vector2((band.size.x - 44) / 3, 214)
        var selected = i == choice_preview
        window(pos, size, SELECT if selected else Color(0.07, 0.20, 0.43, 0.96), YELLOW if selected else (gold if kind == "milestone" else EDGE))
        badge(pos + Vector2(10, 10), str(i + 1), 38)
        window(pos + Vector2((size.x - 100) / 2, 24), Vector2(100, 100), INK, Color("6285b8") if kind != "milestone" else gold, false)
        icon(pos + Vector2((size.x - 88) / 2, 30), choice_icon(i), 88, Color("ffe7a8") if kind == "milestone" else Color.WHITE)
        centered(pos.x + size.x / 2, pos.y + 160, choice_title(i), 24, YELLOW if kind == "milestone" else WHITE, true, size.x - 20)
        var line = choice_line(i)
        centered(pos.x + size.x / 2, pos.y + 192, line, 19, GREEN if line.begins_with("Matches") else CYAN, false, size.x - 20)
        hits.append({"rect": Rect2(pos, size), "action": "choice", "value": i})
    # Details for the highlighted card.
    var detail_pos = band.position + Vector2(0, 300)
    window(detail_pos, Vector2(band.size.x, 144 if handheld() else 132), Color(0.05, 0.13, 0.35, 0.94), gold if kind == "milestone" else EDGE)
    var id: String = game.choice_items[choice_preview]
    text_at(detail_pos + Vector2(24, 36), choice_title(choice_preview), 26, YELLOW if kind == "milestone" else WHITE, true, 400)
    var effect = "Fitted %d to %d" % [game.player.count(id), game.player.count(id) + 1] if kind == "relic" else ("Milestone %d of %d" % [game.player.milestones.size() + 1, game.MILESTONE_DEPTHS.size()] if kind == "milestone" else "Lv. %02d" % game.player.level)
    text_at(detail_pos + Vector2(band.size.x - 210, 36), effect, 22, YELLOW, false, 190)
    var detail: String = DESCRIPTIONS[id] if kind == "relic" else (game.MILESTONES[id].desc if kind == "milestone" else LEVEL_DETAILS[choice_preview])
    paragraph(detail_pos + Vector2(24, 70), detail, band.size.x - 48, 22, WHITE, 3)
    # Actions: apply (fresh press) or close; the offer keeps waiting.
    var actions_y = band.position.y + 450 if handheld() else band.position.y + 442
    var verb = {"relic": "Fit This Part", "level": "Apply Upgrade", "milestone": "Take Milestone"}.get(kind, "Choose")
    var apply_width = 360.0 if handheld() else 280.0
    var later_width = 180.0 if handheld() else 160.0
    var reroll_width = band.size.x - apply_width - later_width - 32
    var height = 50.0 if handheld() else 46.0
    button(Vector2(band.position.x, actions_y), Vector2(apply_width, height), verb, "choice", choice_preview, true)
    button(Vector2(band.position.x + apply_width + 16, actions_y), Vector2(later_width, height), "Later", "choice_later")
    var reroll_pos = Vector2(band.end.x - reroll_width, actions_y)
    if game.can_reroll_choice(): button(reroll_pos, Vector2(reroll_width, height), "Reroll ×%d" % game.rerolls_left, "reroll")
    else: disabled_button(reroll_pos, Vector2(reroll_width, height), "Stat pick" if kind == "level" else "Rerolled" if int(game.choice_source.get("rerolls", 0)) > 0 else "No rerolls")
    # Quiet hints under the band, clear of the parts row and the dash meter.
    var hint_y = band.end.y + 30
    keycap(Vector2(band.position.x, hint_y - 22), "D-PAD" if pad() else "←→", 46 if not pad() else 66)
    text_at(Vector2(band.position.x + (78 if pad() else 56), hint_y), "Browse", 20, MUTED)
    keycap(Vector2(band.position.x + 160, hint_y - 22), "Y" if pad() else "R", 50)
    text_at(Vector2(band.position.x + 220, hint_y), "Reroll", 20, MUTED)
    keycap(Vector2(band.position.x + 360, hint_y - 22), p("parts"), 54)
    text_at(Vector2(band.position.x + 428, hint_y), "Close · picks keep waiting", 20, MUTED, false, band.size.x - 428)

# Which of a milestone's favoured parts this digger has fitted.
func milestone_match(id: String) -> String:
    var names = []
    for part in game.MILESTONES[id].affinity:
        if game.player.count(part) > 0: names.append(game.ITEMS[part].name)
    return "Matches your " + ", ".join(names) if not names.is_empty() else "Works with any build"

func draw_end() -> void:
    backdrop()
    stats_header()
    page_title("DIG COMPLETE!" if game.outcome else "DIG ENDED", ("Account progress: " + game.account.status) if game.profile_source == "account" else ("Core recovered. You've returned to the surface." if game.outcome else (game.end_reason + ". Record saved." if game.end_reason != "" else "Record saved. Equipment resets when you start another dig.")))
    window(Vector2(64, 282), Vector2(1312, 146))
    var labels = ["DEPTH", "MACHINES", "TIME", "LEVEL"]
    var values = ["B%d / B3" % game.depth, str(game.kills), game.time_string(), str(game.player.level)]
    for i in 4:
        var x = 92 + i * 324
        icon(Vector2(x, 311), ["map", "eye", "record", "xp"][i], 48)
        text_at(Vector2(x + 65, 329), labels[i], 21, CYAN, true)
        text_at(Vector2(x + 65, 389), values[i], 42, WHITE, true)
        if i < 3: draw_line(Vector2(x + 298, 305), Vector2(x + 298, 402), Color("5877aa"), 2)
    window(Vector2(64, 466), Vector2(832, 252))
    text_at(Vector2(92, 507), "DISCOVERY LOG", 26, WHITE, true)
    if game.new_unlocks.is_empty():
        icon(Vector2(96, 538), "cache", 88)
        paragraph(Vector2(212, 566), "No new parts unlocked. Machines salvaged on this dig count toward your next unlock.", 630, 28, WHITE, 3)
    else:
        for i in mini(6, game.new_unlocks.size()):
            var x = 92 + (i % 2) * 394
            var y = 532 + (i / 2) * 55
            var title: String = game.new_unlocks[i]
            var image_id = "record"
            for id in game.ITEMS:
                if game.ITEMS[id].name == title: image_id = id
            if title == "Needle Buster": image_id = "needle"
            if title == "Siege Buster": image_id = "siege"
            icon(Vector2(x, y), image_id, 46)
            text_at(Vector2(x + 58, y + 31), title, 25, YELLOW, false, 320)
    window(Vector2(920, 466), Vector2(456, 252))
    text_at(Vector2(948, 507), "DIG RECORD", 26, WHITE, true)
    stat_line(Vector2(948, 560), "Total machines", str(game.meta.kills), 398)
    stat_line(Vector2(948, 608), "Successful digs", str(game.meta.wins), 398)
    var next_unlock = 40 if game.meta.kills < 40 else 100 if game.meta.kills < 100 else 220
    text_at(Vector2(948, 673), "%d to next unlock" % (next_unlock - game.meta.kills) if game.meta.kills < 220 else "All parts unlocked!", 27, YELLOW)
    if game.net.active():
        button(Vector2(64, 764), Vector2(620, 62), "Workshop / Spend Zenny", "workshop", 0, true)
        button(Vector2(716, 764), Vector2(660, 62), confirm_label("leave_online", 0, "Leave Lobby"), "leave_online")
    else:
        button(Vector2(64, 764), Vector2(620, 62), "Workshop / Spend Zenny", "workshop", 0, true)
        button(Vector2(716, 764), Vector2(660, 62), "Return to Title", "title")
    icon(Vector2(64, 848), "save", 32)
    text_at(Vector2(108, 873), ("%s / +%d pending / %d in wallet" % [game.account.status, game.account.pending_zenny(), game.meta.zenny]) if game.profile_source == "account" else "+%d Zenny earned / %d in wallet" % [game.zenny_earned, game.meta.zenny], 23, YELLOW)


# --- Online co-op screens -----------------------------------------------------

func status_line(pos: Vector2) -> void:
    var net = game.net
    var text = net.error_text
    var color = ORANGE
    if text == "":
        color = MUTED
        text = {"offline": "Not connected", "connecting": "Connecting to the dig server…", "online": "Connected · %d ms" % net.ping_ms if net.ping_ms > 0 else "Connected"}.get(net.status, "")
        if net.status != "online" and net.pending.get("t", "") == "join": text = "Joining lobby %s…" % str(net.pending.code)
    draw_circle(pos + Vector2(8, -7), 6, GREEN if net.status == "online" and net.error_text == "" else YELLOW if net.status == "connecting" else ORANGE)
    text_at(pos + Vector2(24, 0), text, 22, color, false, 1200)

func draw_online() -> void:
    backdrop()
    page_title("PLAY ONLINE", "Dig together with up to four diggers. Share a link or pick an open lobby.")
    window(Vector2(64, 276), Vector2(448, 96))
    text_at(Vector2(86, 306), "YOUR NAME", 20, WHITE, true)
    if not editing() or get_viewport().gui_get_focus_owner() != name_edit: name_edit.text = game.net.player_name
    place_field(name_edit, Vector2(86, 318), Vector2(404, 42))
    window(Vector2(64, 384), Vector2(448, 86))
    text_at(Vector2(86, 412), "NEW LOBBY PASSWORD (OPTIONAL)", 18, WHITE, true)
    place_field(new_pass_edit, Vector2(86, 422), Vector2(404, 38), 20)
    button(Vector2(64, 482), Vector2(448, 52), "Create Public Lobby", "create_public", 0, true)
    button(Vector2(64, 546), Vector2(448, 52), "Create Private Lobby", "create_private")
    window(Vector2(64, 612), Vector2(448, 96))
    text_at(Vector2(86, 642), "JOIN BY CODE", 20, WHITE, true)
    place_field(code_edit, Vector2(86, 654), Vector2(130, 40), 22)
    place_field(pass_edit, Vector2(226, 654), Vector2(150, 40), 20)
    button(Vector2(390, 654), Vector2(100, 40), "Join", "join_code")
    if not OS.has_feature("web"):
        window(Vector2(64, 720), Vector2(448, 96))
        text_at(Vector2(86, 750), "DIG SERVER", 20, WHITE, true)
        if not editing() or get_viewport().gui_get_focus_owner() != server_edit: server_edit.text = game.net.server_url
        place_field(server_edit, Vector2(86, 762), Vector2(404, 40), 20)
    window(Vector2(544, 276), Vector2(832, 560))
    text_at(Vector2(570, 316), "OPEN LOBBIES", 26, WHITE, true)
    button(Vector2(1184, 292), Vector2(170, 44), "Refresh", "refresh")
    var lobbies: Array = game.net.public_lobbies
    if lobbies.is_empty():
        icon(Vector2(896, 430), "map", 128)
        paragraph(Vector2(620, 616), "No open lobbies right now. Create one, then send your friends the invite link.", 680, 28, WHITE, 3)
    for i in mini(7, lobbies.size()):
        var info: Dictionary = lobbies[i]
        var pos = Vector2(568, 352 + i * 68)
        var area = Rect2(pos, Vector2(784, 60))
        var full = int(info.get("players", 0)) >= int(info.get("max", 4))
        var locked = bool(info.get("locked", false))
        var hot = focus_index == hits.size() or area.has_point(pointer)
        window(pos, area.size, SELECT if hot else INK, YELLOW if hot else EDGE, false)
        if hot: cursor(pos + Vector2(-30, 14))
        icon(pos + Vector2(8, 6), "lock" if locked or bool(info.get("password", false)) else "record" if info.state == "lobby" else "map", 48)
        text_at(pos + Vector2(66, 27), str(info.name), 24, WHITE, false, 380)
        text_at(pos + Vector2(66, 51), "Host: " + str(info.host) + ("  ·  password" if bool(info.get("password", false)) else ""), 19, MUTED, false, 380)
        text_at(pos + Vector2(470, 38), "Locked" if locked else "Waiting" if info.state == "lobby" else "Digging B%d" % int(info.depth), 22, ORANGE if locked else YELLOW if info.state == "lobby" else CYAN)
        text_at(pos + Vector2(650, 39), "%d / %d" % [int(info.players), int(info.max)], 25, ORANGE if full else WHITE, true)
        if not full and not locked: hits.append({"rect": area, "action": "join", "value": i})
    window(Vector2(64, 846), Vector2(1312, 40), INK, EDGE, false)
    status_line(Vector2(80, 874))
    button(Vector2(1144, 790), Vector2(232, 46), "Back to Title", "title")

# Compact button for rows like the lobby's kick controls.
func small_button(pos: Vector2, size: Vector2, title: String, action: String, value: int = 0, color: Color = PANEL) -> void:
    var area = Rect2(pos, size)
    var hot = not underlay and (focus_index == hits.size() or area.has_point(pointer))
    window(pos, size, SELECT if hot else color, YELLOW if hot else EDGE, false)
    text_at(pos + Vector2(12, size.y / 2 + 7), title, 19, WHITE, false, size.x - 20)
    hits.append({"rect": area, "action": action, "value": value})

func disabled_button(pos: Vector2, size: Vector2, title: String) -> void:
    window(pos, size, INK, Color("4c6ea6"), false)
    text_at(pos + Vector2(18, size.y / 2 + 8), title, 23, MUTED, false, size.x - 36)

func digger_card(pos: Vector2, member: Dictionary) -> void:
    var net = game.net
    var member_slot = int(member.slot)
    var selection: Dictionary = member.get("selection", {})
    var character = int(selection.get("character", 0))
    var weapon = int(selection.get("weapon", 0))
    var color: Color = DiverNet.SLOT_COLORS[member_slot]
    window(pos, Vector2(672, 86), BLUE if member_slot == net.slot else INK, color, false)
    draw_texture_rect(portraits[character], Rect2(pos + Vector2(14, 6), Vector2(62, 72)), false)
    text_at(pos + Vector2(94, 28), str(member.name), 25, color, true, 310)
    text_at(pos + Vector2(94, 54), "%s / %s" % [DiverCharacter.SHORT_NAMES[character].capitalize(), game.WEAPONS[weapon]], 21, WHITE, false, 320)
    var spec = DiverProgression.spec(character, str(selection.get("spec", "")))
    text_at(pos + Vector2(94, 78), spec.get("name", "No specialization"), 19, MUTED, false, 320)
    text_at(pos + Vector2(430, 70), "READY" if member.get("ready", false) else "NOT READY", 20, GREEN if member.get("ready", false) else YELLOW, true, 136)
    if member_slot == net.host_slot: badge(pos + Vector2(576, 8), "HOST", 86, YELLOW)
    elif member_slot == net.slot: badge(pos + Vector2(576, 8), "YOU", 80, CYAN)
    if net.is_host() and member_slot != net.slot: small_button(pos + Vector2(576, 48), Vector2(86, 30), "Kick" if handheld() else "Remove", "kick", member_slot, Color(0.30, 0.10, 0.14))

func draw_lobby() -> void:
    backdrop()
    var net = game.net
    var info: Dictionary = net.lobby
    var phase = net.ready_phase()
    var locked = net.loadout_locked() or phase == "running"
    var extras = []
    if net.lobby_password != "": extras.append("password %s" % net.lobby_password)
    if bool(info.get("locked", false)): extras.append("locked")
    page_title(str(info.get("name", "Lobby")).to_upper(), "%s lobby / Code %s%s" % ["Public" if info.get("isPublic", true) else "Private", net.lobby_code, (" / " + " / ".join(extras)) if not extras.is_empty() else ""])
    window(Vector2(64, 276), Vector2(560, 150))
    text_at(Vector2(86, 310), "INVITE LINK", 20, WHITE, true)
    text_at(Vector2(86, 346), net.invite_link(), 22, CYAN, false, 516)
    button(Vector2(86, 362), Vector2(272, 50), "Copied!" if copied_time > 0 else "Copy Invite Link", "copy_link", 0, true)
    text_at(Vector2(390, 400), net.lobby_code, 38, YELLOW, true)
    window(Vector2(64, 444), Vector2(560, 100))
    text_at(Vector2(86, 476), "YOUR NAME", 20, WHITE, true)
    if not editing() or get_viewport().gui_get_focus_owner() != name_edit: name_edit.text = net.player_name
    place_field(name_edit, Vector2(86, 488), Vector2(516, 44))
    window(Vector2(64, 562), Vector2(560, 174))
    text_at(Vector2(86, 594), "LOADOUT LOCKED" if locked else "YOUR DIGGER", 20, WHITE, true)
    for i in DiverCharacter.COUNT:
        var pos = Vector2(86 + i * 131, 606)
        var selected = game.selected_character == i
        var hot = not locked and (focus_index == hits.size() or Rect2(pos, Vector2(125, 60)).has_point(pointer))
        window(pos, Vector2(125, 60), SELECT if selected else INK, YELLOW if selected or hot else EDGE, false)
        draw_texture_rect(portraits[i], Rect2(pos + Vector2(4, 3), Vector2(48, 54)), false)
        text_at(pos + Vector2(56, 38), DiverCharacter.SHORT_NAMES[i].capitalize(), 19 if i < 3 else 15, WHITE, true)
        if not locked: hits.append({"rect": Rect2(pos, Vector2(125, 60)), "action": "character", "value": i})
    text_at(Vector2(86, 695), game.WEAPONS[game.selected_weapon], 24, YELLOW, true)
    var spec = DiverProgression.spec(game.selected_character, game.equipped_spec(game.selected_character))
    text_at(Vector2(86, 724), "Spec: " + str(spec.get("name", "None equipped")), 21, MUTED, false, 516)
    if phase == "running": disabled_button(Vector2(64, 740), Vector2(270, 44), "Joining active dig...")
    elif not game.account_ready_to_prepare(): disabled_button(Vector2(64, 740), Vector2(270, 44), "Confirm account first")
    elif net.server_ready and not net.readiness().is_empty() and net.selection_acknowledged():
        button(Vector2(64, 740), Vector2(270, 44), ("Unready" if handheld() else "Unready / Cancel") if net.own_ready() else "Ready", "ready", 0, true)
    else: disabled_button(Vector2(64, 740), Vector2(270, 44), "Confirming loadout..." if net.server_ready else "Server update needed")
    if game.account.takeover_needed: button(Vector2(354, 740), Vector2(270, 44), confirm_label("takeover", 0, "Take over account dig"), "takeover")
    elif game.account.pending_run_callback.is_valid() and (game.account.server_run == "" or game.account.lease_retry.is_valid()): button(Vector2(354, 740), Vector2(270, 44), "Retry account dig", "retry_run")
    elif phase == "running": disabled_button(Vector2(354, 740), Vector2(270, 44), "Waiting for host sync")
    else: button(Vector2(354, 740), Vector2(270, 44), "Change loadout" if locked or net.own_ready() else "Workshop", "lobby_workshop")
    if net.loadout_locked(): button(Vector2(64, 792), Vector2(270, 44), "Cancel launch", "cancel_launch", 0, true)
    elif net.can_start(): button(Vector2(64, 792), Vector2(270, 44), "Start Dig", "start_online", 0, true)
    else: disabled_button(Vector2(64, 792), Vector2(270, 44), "Ready the party first" if net.is_host() else "Host starts the dig")
    button(Vector2(354, 792), Vector2(270, 44), confirm_label("leave_online", 0, "Leave Lobby"), "leave_online")
    var members: Array = net.members()
    window(Vector2(656, 276), Vector2(720, 430))
    text_at(Vector2(680, 314), "PARTY   %d / %d" % [members.size(), DiverNet.MAX_PLAYERS], 26, WHITE, true)
    if net.is_host(): small_button(Vector2(1176, 288), Vector2(180, 36), "Unlock Lobby" if bool(info.get("locked", false)) else "Lock Lobby", "lock")
    for i in DiverNet.MAX_PLAYERS:
        var pos = Vector2(680, 330 + i * 92)
        if i < members.size(): digger_card(pos, members[i])
        else:
            window(pos, Vector2(672, 86), Color(0.05, 0.12, 0.32, 0.6), Color("4c6ea6"), false)
            text_at(pos + Vector2(28, 50), "Open slot - waiting for a digger", 23, Color("6f8fc0"))
    window(Vector2(656, 718), Vector2(720, 54), INK, EDGE, false)
    var detail = "Waiting for: " + net.waiting_names()
    if not net.server_ready: detail = "Update the game and lobby server before starting online."
    elif phase == "countdown": detail = "Starting in %d... Cancel to change the party." % net.countdown_left()
    elif phase == "preparing": detail = "Preparing dig - waiting for " + net.waiting_names()
    elif phase == "running": detail = "Joining the active dig - waiting for the host to sync."
    elif bool(net.readiness().get("canStart", false)): detail = "Everyone is Ready. The host can Start Dig."
    elif net.waiting_names() == "": detail = "Waiting for the server to confirm the party."
    text_at(Vector2(678, 752), detail, 22, YELLOW, false, 674)
    draw_chat(Vector2(660, 798), 716, 1, false)
    place_field(chat_edit, Vector2(656, 804), Vector2(720, 32), 19)
    window(Vector2(64, 846), Vector2(1312, 40), INK, EDGE, false)
    status_line(Vector2(80, 874))
    if net.reconnecting(): draw_reconnecting()

# Recent chat, newest at the bottom; in the dig it fades after a while.
func draw_chat(bottom_left: Vector2, width: float, lines: int, fade: bool) -> void:
    var now = Time.get_ticks_msec()
    var shown = []
    for entry in game.chat_log:
        if not fade or now - int(entry.time) < 12000: shown.append(entry)
    shown = shown.slice(maxi(0, shown.size() - lines))
    for i in shown.size():
        var entry: Dictionary = shown[shown.size() - 1 - i]
        var y = bottom_left.y - i * 25
        var who = "%s:" % str(entry.name)
        var name_width = font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, readable_size(20)).x + 8
        rect(Vector2(bottom_left.x - 4, y - 19), Vector2(width, 24), Color(0.03, 0.07, 0.2, 0.55))
        text_at(Vector2(bottom_left.x, y), who, 20, DiverNet.SLOT_COLORS[clampi(int(entry.slot), 0, 4)])
        text_at(Vector2(bottom_left.x + name_width, y), str(entry.text), 20, YELLOW if entry.quick else WHITE, false, width - name_width - 8)

func draw_reconnecting() -> void:
    rect(Vector2(-200, -200), BASE + Vector2(400, 400), Color(0.02, 0.04, 0.14, 0.55))
    window(Vector2(420, 330), Vector2(600, 210), PANEL, YELLOW)
    text_at(Vector2(450, 378), "RECONNECTING…", 32, YELLOW, true)
    paragraph(Vector2(450, 418), "The connection dropped. Your dig and build are saved; the action resumes as soon as you're back.", 540, 23, WHITE, 2)
    text_at(Vector2(450, 486), "Attempt %d" % maxi(1, game.net.reconnect_attempts), 21, MUTED)
    small_button(Vector2(760, 470), Vector2(234, 40), confirm_label("give_up", 0, "Return to Title"), "give_up")

# Teammate Life and revive status during an online dig.
func draw_team() -> void:
    var row = 0
    for member_slot in game.remote_players:
        var mate: DiverPlayer = game.remote_players[member_slot]
        if not is_instance_valid(mate): continue
        var pos = Vector2(28, 486 + row * 80)
        window(pos, Vector2(268, 72), Color(0.05, 0.13, 0.35, 0.88), DiverNet.SLOT_COLORS[clampi(member_slot, 0, 4)], false)
        draw_texture_rect(portraits[clampi(mate.character, 0, DiverCharacter.COUNT - 1)], Rect2(pos + Vector2(6, 5), Vector2(54, 62)), false)
        text_at(pos + Vector2(70, 27), mate.display_name, 21, DiverNet.SLOT_COLORS[clampi(member_slot, 0, 4)], true, 180)
        if mate.downed:
            text_at(pos + Vector2(70, 58), "DOWN", 21, ORANGE, true)
            pips(Vector2(pos.x + 140, pos.y + 44), 112, 10, mate.revive, 8, YELLOW)
        else: pips(Vector2(pos.x + 72, pos.y + 42), 182, 12, mate.hp / maxf(1, mate.max_hp()), 12, GREEN if mate.hp > mate.max_hp() * 0.3 else ORANGE)
        if mate.downed and not game.player.downed and mate.global_position.distance_to(game.player.global_position) < 2.4:
            window(Vector2(450, 674), Vector2(540, 49), BLUE, YELLOW)
            icon(Vector2(460, 677), "life", 42)
            text_at(Vector2(512, 707), "Reviving %s…" % mate.display_name, 23, WHITE, false, 300)
            pips(Vector2(812, 692), 160, 14, mate.revive, 8, YELLOW)
        row += 1
    if game.player.downed:
        var watching = game.spectate_target()
        window(Vector2(420, 250), Vector2(600, 140), Color(0.30, 0.08, 0.10, 0.92), ORANGE)
        text_at(Vector2(446, 292), "YOU'RE DOWN!", 30, YELLOW, true)
        text_at(Vector2(446, 330), "A teammate can revive you by standing close.", 23, WHITE, false, 550)
        pips(Vector2(446, 342), 548, 8, game.player.revive, 24, YELLOW)
        text_at(Vector2(446, 378), "Watching %s  ·  %s to switch" % [watching.display_name, "A" if pad() else "click"] if watching else "Hold on — help is on the way.", 21, MUTED, false, 550)

func draw_workshop() -> void:
    backdrop()
    page_title("THE WORKSHOP", "Permanent circuits. Parts and levels reset each dig." if handheld() else "Permanent circuits / Each digger has their own tree. Parts and levels reset each dig.")
    text_at(Vector2(1090, 232), "%d ZENNY" % game.meta.zenny, 30, YELLOW, true)
    if game.profile_source == "account": text_at(Vector2(64, 262), "%s / +%d pending" % [game.account.status, game.account.pending_zenny()], 21, CYAN)
    var first_node = workshop_first_node() if workshop_focus_pending else -1
    if workshop_focus_pending: focus_index = -1
    for i in DiverCharacter.COUNT:
        var tab = Rect2(Vector2(64 + i * 328, 278), Vector2(312, 62))
        var chosen = workshop_character == i
        var hot = focus_index == hits.size() or tab.has_point(pointer)
        window(tab.position, tab.size, SELECT if chosen else PANEL, YELLOW if chosen or hot else EDGE)
        if hot: cursor(tab.position + Vector2(-28, 15))
        draw_texture_rect(portraits[i], Rect2(tab.position + Vector2(6, 4), Vector2(48, 54)), false)
        text_at(tab.position + Vector2(64, 41), DiverCharacter.DISPLAY_NAMES[i], 26, YELLOW if chosen else WHITE, false, 236)
        hits.append({"rect": tab, "action": "tree_character", "value": i})
    draw_grid(first_node)
    workshop_focus_pending = false
    var hint = "LB / RB: Digger   D-pad / Stick: Circuits   X: Zoom" if pad() else "C: Digger   Arrows: Circuits   Z / Wheel: Zoom   Drag: Pan"
    text_at(Vector2(GRID_RECT.position.x, 812), workshop_message if workshop_message != "" else hint, 21, CYAN, false, GRID_RECT.size.x)
    button(Vector2(64, 828), Vector2(300, 56), "Save Codes" if handheld() else "Save Codes / Backup", "save_codes")
    button(Vector2(394, 828), Vector2(460, 56), "Return to Lobby" if game.net.active() else "Start Another Dig", "lobby_room" if game.net.active() else "start", 0, true)
    button(Vector2(884, 828), Vector2(492, 56), "Back", workshop_return)

func draw_purchase_review() -> void:
    if purchase_review.is_empty():
        game.mode = "workshop"
        return
    # The spatial grid remains visible, but none of its controls own hit targets.
    underlay = true
    var saved_pointer = pointer
    var saved_focus = focus_index
    pointer = Vector2(-100, -100)
    focus_index = DiverCharacter.COUNT + int(purchase_review.index)
    draw_workshop()
    pointer = saved_pointer
    focus_index = saved_focus
    underlay = false
    hits.clear()
    var extra = ui_offset / ui_scale
    rect(-extra, BASE + extra * 2, Color(0.02, 0.05, 0.18, 0.68))
    window(Vector2(280, 132), Vector2(880, 670), PANEL, EDGE)
    text_at(Vector2(320, 190), "PURCHASE REVIEW", 32, YELLOW, true)
    var character = int(purchase_review.character)
    draw_texture_rect(portraits[character], Rect2(320, 218, 72, 82), false)
    text_at(Vector2(410, 266), DiverCharacter.DISPLAY_NAMES[character], 29, CYAN, true, 700)
    icon(Vector2(320, 318), str(purchase_review.icon), 72)
    text_at(Vector2(410, 360), str(purchase_review.name), 30, WHITE, true, 690)
    paragraph(Vector2(320, 418), str(purchase_review.detail), 800, 26, WHITE, 3)
    var phase = str(purchase_review.phase)
    var result_wallet = phase in ["confirmed", "refused"]
    for column in 3:
        var pos = Vector2(320 + column * 274, 508)
        window(pos, Vector2(252, 90), INK, EDGE, false)
        text_at(pos + Vector2(18, 29), ["WALLET BEFORE", "COST", "ACCOUNT WALLET" if result_wallet and game.profile_source == "account" else "CURRENT WALLET" if result_wallet else "IF CONFIRMED" if phase == "pending" else "AFTER PURCHASE"][column], 20, CYAN)
        var after = int(game.meta.zenny) if result_wallet else int(purchase_review.wallet) - int(purchase_review.cost)
        var value = [int(purchase_review.wallet), int(purchase_review.cost), after][column]
        text_at(pos + Vector2(18, 68), "%d Z" % value, 30, YELLOW if column != 2 else GREEN if value >= 0 else ORANGE, true)
    var note = str(purchase_review.note)
    if phase == "review": note = purchase_problem()
    if phase == "review" and note == "": note = "Review this one circuit. Confirm spends Zenny; Cancel spends nothing."
    if phase == "pending": note = "Purchase submitted / %s. It may already be charged; closing does not cancel it." % game.account.status
    if phase == "confirmed" and game.profile_source == "account" and game.account.status != "Synced": note += " Progress still needs sync; Retry keeps the same purchase."
    paragraph(Vector2(320, 634), note, 800, 23, GREEN if phase == "confirmed" else ORANGE if phase == "refused" or (phase == "review" and purchase_problem() != "") else CYAN, 2)
    if phase == "review":
        button(Vector2(320, 710), Vector2(384, 62), "Cancel", "purchase_cancel")
        if purchase_problem() == "": button(Vector2(736, 710), Vector2(384, 62), "Confirm Purchase", "purchase_confirm", 0, true)
    else:
        button(Vector2(320, 710), Vector2(384, 62), "Close", "purchase_close")
        if purchase_context_matches() and game.account.signed_in() and game.account.status == "Offline": button(Vector2(736, 710), Vector2(384, 62), "Retry Sync", "purchase_retry")
    text_at(Vector2(320, 792), ("Last synced wallet: %d Z" if game.profile_source == "account" else "Current wallet: %d Z") % int(game.meta.zenny), 20, MUTED)

# Liang-Barsky: the part of a segment inside the grid frame, or [] if none.
func clip_segment(a: Vector2, b: Vector2, box: Rect2) -> Array:
    var t0 = 0.0
    var t1 = 1.0
    var d = b - a
    for edge in [[-d.x, a.x - box.position.x], [d.x, box.end.x - a.x], [-d.y, a.y - box.position.y], [d.y, box.end.y - a.y]]:
        if absf(edge[0]) < 1e-6:
            if edge[1] < 0: return []
            continue
        var t = edge[1] / edge[0]
        if edge[0] < 0: t0 = maxf(t0, t)
        else: t1 = minf(t1, t)
        if t0 > t1: return []
    return [a + d * t0, a + d * t1]

func octagon(center: Vector2, radius: float) -> PackedVector2Array:
    var points = PackedVector2Array()
    for k in 9: points.append(center + Vector2.from_angle(PI / 8 + k * TAU / 8) * radius)
    return points

func draw_grid(first_node: int) -> void:
    var skills = DiverProgression.owned(game.meta, workshop_character)
    var nodes = DiverProgression.NODES
    window(GRID_RECT.position, GRID_RECT.size, INK, EDGE)
    var zoom = grid_zoom()
    # Faint machined backing lines every cell.
    var spacing = GRID_CELL * zoom
    var origin = GRID_RECT.get_center() - grid_center * spacing
    # Resolve the entry focus (and any pan it needs) before drawing anything.
    if workshop_focus_pending and first_node >= 0:
        grid_reveal(first_node)
        origin = GRID_RECT.get_center() - grid_center * spacing
    for k in range(-14, 15):
        var x = origin.x + k * spacing.x
        var y = origin.y + k * spacing.y
        if x > GRID_RECT.position.x + 4 and x < GRID_RECT.end.x - 4: draw_line(Vector2(x, GRID_RECT.position.y + 4), Vector2(x, GRID_RECT.end.y - 4), Color(0.45, 0.6, 0.95, 0.07), 1)
        if y > GRID_RECT.position.y + 4 and y < GRID_RECT.end.y - 4: draw_line(Vector2(GRID_RECT.position.x + 4, y), Vector2(GRID_RECT.end.x - 4, y), Color(0.45, 0.6, 0.95, 0.07), 1)
    var frame = GRID_RECT.grow(-6)
    for link in DiverProgression.LINKS:
        var a = -1
        var b = -1
        for i in nodes.size():
            if nodes[i].id == link[0]: a = i
            if nodes[i].id == link[1]: b = i
        var both = link[0] in skills and link[1] in skills
        var one = link[0] in skills or link[1] in skills
        var segment = clip_segment(grid_point(a), grid_point(b), frame)
        if segment.is_empty(): continue
        draw_line(segment[0], segment[1], Color("0a1233"), (12 if both else 9) * zoom)
        draw_line(segment[0], segment[1], GREEN if both else CYAN if one else Color(EDGE, 0.30), (6 if both else 4 if one else 3) * zoom)
    var radius = 27.0 * zoom
    var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
    for i in nodes.size():
        var entry = nodes[i]
        if workshop_focus_pending and i == first_node: focus_index = hits.size()
        var at = grid_point(i)
        var state = grid_state(i)
        var special = entry.id in DiverProgression.SPEC_NODES
        var size = radius * (1.22 if special else 1.0)
        var visible = frame.grow(-size).has_point(at)
        var area = Rect2(at - Vector2.ONE * (size + 6), Vector2.ONE * (size + 6) * 2)
        var hot = focus_index == hits.size() or (visible and area.has_point(pointer))
        hits.append({"rect": area if visible else Rect2(), "action": "grid_node", "value": i})
        if not visible: continue
        var fill = {"owned": SELECT, "available": PANEL, "short": PANEL, "syncing": PANEL, "locked": Color("0c1538")}[state]
        var border = {"owned": GREEN, "available": YELLOW.lerp(WHITE, pulse * 0.5), "short": EDGE, "syncing": EDGE, "locked": Color(EDGE, 0.35)}[state]
        var equipped = grid_equipped(entry)
        if equipped:
            fill = Color("8a6516")
            border = YELLOW
        if hot: draw_colored_polygon(octagon(at, size + 8), Color(YELLOW, 0.35))
        if special: draw_colored_polygon(octagon(at, size + 4), Color(YELLOW if equipped else EDGE, 0.5 if state != "locked" else 0.2))
        draw_colored_polygon(octagon(at, size), fill)
        draw_polyline(octagon(at, size), YELLOW if hot else border, 3.5 if hot or state == "owned" else 2.5)
        var side = size * 1.25
        icon(at - Vector2.ONE * side / 2, grid_icon(entry), side, Color(1, 1, 1, 0.38) if state == "locked" else Color.WHITE)
        if state == "owned":
            draw_colored_polygon(octagon(at + Vector2(size * 0.72, size * 0.72), 9 * zoom), YELLOW if equipped else GREEN)
        if special and zoom >= 0.8:
            # Specializations carry their name, so the two destinations read at a glance.
            var title = grid_name(entry).to_upper() + ("  ·  EQUIPPED" if equipped else "" if state == "owned" else "  ·  %d" % entry.cost)
            var title_width = heading.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
            text_at(at + Vector2(-title_width / 2, size + 19), title, 15, YELLOW if equipped else WHITE if state == "owned" else ORANGE if state == "short" else MUTED, true)
        elif state != "owned" and (zoom >= 1.0 or hot):
            var price = "%d" % entry.cost
            var color = YELLOW if state == "available" else ORANGE if state == "short" else MUTED
            text_at(at + Vector2(-heading.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x / 2, size + 19), price, 17, color, true)
        if hot: cursor(at + Vector2(-size - 34, -15), 28)
    # Completion and view controls along the top of the frame.
    var count = skills.size()
    window(GRID_RECT.position + Vector2(10, 10), Vector2(170, 84), INK, Color(EDGE, 0.5), false)
    text_at(GRID_RECT.position + Vector2(24, 38), "%s GRID" % DiverCharacter.SHORT_NAMES[workshop_character].to_upper(), 20, WHITE, true)
    var bar = Rect2(GRID_RECT.position + Vector2(24, 48), Vector2(142, 10))
    draw_rect(bar, Color("0c1538"))
    draw_rect(Rect2(bar.position, Vector2(bar.size.x * count / nodes.size(), bar.size.y)), GREEN if count == nodes.size() else CYAN)
    draw_rect(bar, EDGE, false, 1.5)
    text_at(GRID_RECT.position + Vector2(24, 82), "%d / %d  ·  %d%%" % [count, nodes.size(), roundi(100.0 * count / nodes.size())], 19, MUTED)
    small_button(GRID_RECT.position + Vector2(GRID_RECT.size.x - 214, 12), Vector2(40, 34), "−", "grid_zoom", -1)
    small_button(GRID_RECT.position + Vector2(GRID_RECT.size.x - 168, 12), Vector2(40, 34), "+", "grid_zoom", 1)
    small_button(GRID_RECT.position + Vector2(GRID_RECT.size.x - 122, 12), Vector2(108, 34), "Recenter", "grid_center")
    # Details for the focused circuit (or the first useful one).
    var shown = focus_index - DiverCharacter.COUNT
    if shown < 0 or shown >= nodes.size(): shown = workshop_first_node()
    var entry = nodes[shown]
    var state = grid_state(shown)
    window(Vector2(64, 366), Vector2(360 if handheld() else 300, 414))
    window(Vector2(82, 384), Vector2(72, 72), SELECT if state == "owned" else PANEL, GREEN if state == "owned" else EDGE, false)
    icon(Vector2(86, 388), grid_icon(entry), 64, Color(1, 1, 1, 0.45) if state == "locked" else Color.WHITE)
    var special = entry.id in DiverProgression.SPEC_NODES
    paragraph(Vector2(168, 410), grid_name(entry), 240 if handheld() else 180, 23, YELLOW if state == "owned" else WHITE, 2)
    var tag = {"owned": "FITTED", "available": "AVAILABLE", "short": "NEED ZENNY", "syncing": "SYNCING", "locked": "NOT LINKED"}[state]
    if special and state == "owned": tag = "EQUIPPED" if grid_equipped(entry) else "UNLOCKED"
    badge(Vector2(82, 470), tag, 160, {"owned": GREEN, "available": YELLOW, "short": ORANGE, "syncing": CYAN, "locked": MUTED}[state] if tag != "EQUIPPED" else YELLOW)
    text_at(Vector2(256, 493), "" if state == "owned" else "%d Z" % entry.cost, 22, YELLOW, true)
    paragraph(Vector2(84, 534), grid_detail(entry), 322 if handheld() else 262, 21, MUTED, 6)
    var linked = []
    for other in DiverProgression.neighbors(entry.id): linked.append(grid_name(DiverProgression.node(other)))
    paragraph(Vector2(84, 700), "Links: " + ", ".join(linked), 322 if handheld() else 262, 19, CYAN, 2)
    var action = {"owned": "Already fitted.", "available": ("A" if pad() else "Enter / click") + ": review purchase", "short": "Earn Zenny in digs.", "syncing": "Waiting for sync.", "locked": "Buy a linked circuit first."}[state]
    if special and state == "owned": action = ("A" if pad() else "Enter / click") + (": unequip" if grid_equipped(entry) else ": equip for next dig")
    elif special: action = "Unlock, then equip one per dig."
    text_at(Vector2(84, 764), action, 20, YELLOW if state == "available" or (special and state == "owned") else MUTED, false, 322 if handheld() else 262)

func draw_save_codes() -> void:
    if waiting_for_paste:
        var pasted = JavaScriptBridge.eval("window.relicSavePaste", true)
        if pasted is String:
            waiting_for_paste = false
            save_edit.text = pasted.left(32768)
            pending_import = {}
            save_message = "Code pasted. Check it before replacing progress." if pasted != "" else "Clipboard access blocked. Click the field and paste your code manually."
    backdrop()
    page_title("SAVE CODE", "Keep your Zenny, skill trees, discoveries and records across browsers or devices.")
    window(Vector2(64, 282), Vector2(1312, 440))
    text_at(Vector2(96, 332), "YOUR PROGRESS / YOUR BACKUP", 27, CYAN, true)
    paragraph(Vector2(96, 392), ("Export your cloud progress. Import can only preview adoption into an empty account; an established cloud wallet cannot be replaced." if game.profile_source == "account" else "Export, then copy the entire code to a safe place. Paste it here on another device, check it, then confirm. Import replaces the local progress record."), 1216, 29, WHITE, 3)
    place_field(save_edit, Vector2(96, 492), Vector2(1248, 68), 23)
    button(Vector2(96, 570), Vector2(330, 46), "Paste from Clipboard", "paste_save")
    paragraph(Vector2(96, 660), save_message, 1216, 26, YELLOW, 2)
    button(Vector2(64, 764), Vector2(300, 62), "Export / Copy Code", "export_save", 0, true)
    button(Vector2(388, 764), Vector2(300, 62), "Check Pasted Code", "check_import")
    if not pending_import.is_empty(): button(Vector2(712, 764), Vector2(348, 62), "Preview Cloud Adoption" if game.profile_source == "account" else "Replace Local Progress", "confirm_import")
    button(Vector2(1084, 764), Vector2(292, 62), "Back", "workshop")
    text_at(Vector2(64, 876), "Run checkpoints and control settings are separate from this backup.", 23, MUTED)

const AUTH_VIEWS = ["sign_in", "create", "forgot", "two_factor", "check_email"]

func submit_auth() -> void:
    var a = game.account
    get_viewport().gui_release_focus()
    match a.auth.view:
        "sign_in": a.sign_in_email(auth_email_edit.text, auth_password_edit.text)
        "create": a.create_account(auth_name_edit.text, auth_email_edit.text, auth_password_edit.text)
        "forgot": a.send_reset(auth_email_edit.text)
        "two_factor": a.verify_code(auth_code_edit.text, auth_backup)
    if a.auth.view != "forgot": auth_password_edit.text = ""

# Enter moves to the next field of the form, or submits from the last one.
func auth_field_submitted(field: LineEdit) -> void:
    var order = auth_fields()
    var at = order.find(field)
    if at >= 0 and at < order.size() - 1: order[at + 1].grab_focus()
    else: submit_auth()

func auth_fields() -> Array:
    match game.account.auth.view:
        "sign_in": return [auth_email_edit, auth_password_edit]
        "create": return [auth_name_edit, auth_email_edit, auth_password_edit]
        "forgot": return [auth_email_edit]
        "two_factor": return [auth_code_edit]
    return []

# A labelled text box; focusing it with Enter / A opens the on-screen keyboard.
func auth_field(field: LineEdit, index: int, pos: Vector2, label: String) -> void:
    text_at(pos + Vector2(0, -10), label, 21, MUTED)
    var area = Rect2(pos, Vector2(560, 48))
    if focus_index == hits.size() and not field.has_focus(): window(pos - Vector2(4, 4), area.size + Vector2(8, 8), INK, YELLOW, false)
    hits.append({"rect": area, "action": "auth_field", "value": index})
    place_field(field, pos, area.size, 24)

func draw_account() -> void:
    # A modal over the title: the title stays visible behind it but can't be used.
    underlay = true
    draw_title()
    underlay = false
    hits.clear()
    var extra = ui_offset / ui_scale
    rect(-extra, BASE + extra * 2, Color(0.02, 0.04, 0.14, 0.72))
    var a = game.account
    var origin = Vector2(400, 96)
    window(origin, Vector2(640, 708))
    var x = origin.x + 40
    var shown: Array = []
    if a.state == "restoring":
        text_at(Vector2(x, 160), "RESTORING YOUR ACCOUNT", 30, CYAN, true)
        paragraph(Vector2(x, 222), "Waiting for the server to confirm your saved sign-in. Retry when connected, or play as Guest for now.", 560, 26, WHITE, 5)
        button(Vector2(x, 470), Vector2(560, 56), "Retry", "account_retry", 0, true)
        button(Vector2(x, 540), Vector2(560, 56), "Play as Guest", "guest")
    elif game.profile_source == "account" and not a.state in ["needs_sign_in", "signing_in"]:
        text_at(Vector2(x, 160), str(a.identity.get("name", "Digger")), 34, YELLOW, true, 560)
        text_at(Vector2(x, 200), "Signed in / " + a.status, 24, CYAN)
        var synced = "Never" if a.last_sync == 0 else Time.get_datetime_string_from_unix_time(int(a.last_sync), true) + " UTC"
        text_at(Vector2(x, 246), "Last sync: " + synced, 22, MUTED)
        text_at(Vector2(x, 290), "%d digs  /  %d clears  /  %d machines" % [game.meta.runs, game.meta.wins, game.meta.kills], 25)
        text_at(Vector2(x, 326), "%d Zenny  (+%d pending)" % [game.meta.zenny, a.pending_zenny()], 25, YELLOW)
        if not a.migration.is_empty():
            text_at(Vector2(x, 372), "Adopt: %d digs / %d Zenny / %d circuits" % [a.migration.preview.runs, a.migration.preview.zenny, a.migration.preview.trees], 24, YELLOW)
            button(Vector2(x, 390), Vector2(560, 52), "Confirm adoption into this account", "migrate_confirm")
        button(Vector2(x, 486), Vector2(560, 52), "Close", "title", 0, true)
        button(Vector2(x, 548), Vector2(272, 52), "Retry sync", "account_retry")
        button(Vector2(x + 288, 548), Vector2(272, 52), "Sign Out", "sign_out")
        if a.outbox.is_empty(): small_button(Vector2(x, 612), Vector2(560, 40), confirm_label("clear_session", 0, "Sign out and clear this device's account cache"), "clear_session")
    else:
        # Guest, or an account whose sign-in ended (its pending progress waits).
        if game.profile_source == "account" and a.auth.view == "sign_in" and a.auth.note == "":
            a.auth.note = "Your sign-in ended. Sign in again to sync your progress."
            a.auth.bad = false
        match a.auth.view:
            "sign_in":
                text_at(Vector2(x, 160), "SIGN IN", 32, CYAN, true)
                paragraph(Vector2(x, 202), "Keep your progress on every device. Signing in replaces this device's Guest progress with your account's.", 560, 21, MUTED, 3)
                auth_field(auth_email_edit, 1, Vector2(x, 300), "Email")
                auth_field(auth_password_edit, 2, Vector2(x, 386), "Password")
                shown = [auth_email_edit, auth_password_edit]
                button(Vector2(x, 454), Vector2(560, 54), "Signing in…" if a.auth.busy else "Sign In", "auth_submit", 0, true)
                button(Vector2(x, 518), Vector2(272, 50), "Create account", "auth_view", AUTH_VIEWS.find("create"))
                button(Vector2(x + 288, 518), Vector2(272, 50), "Forgot password", "auth_view", AUTH_VIEWS.find("forgot"))
            "create":
                text_at(Vector2(x, 160), "CREATE AN ACCOUNT", 32, CYAN, true)
                paragraph(Vector2(x, 202), ("Your Guest progress moves into the new account." if handheld() else "Your Guest progress on this device moves into the new account."), 560, 21, MUTED, 2)
                auth_field(auth_name_edit, 0, Vector2(x, 272), "Digger name")
                auth_field(auth_email_edit, 1, Vector2(x, 352), "Email")
                auth_field(auth_password_edit, 2, Vector2(x, 432), "Password (10+ characters)")
                shown = [auth_name_edit, auth_email_edit, auth_password_edit]
                button(Vector2(x, 494), Vector2(560, 54), "Creating…" if a.auth.busy else "Create account", "auth_submit", 0, true)
                button(Vector2(x, 556), Vector2(560, 46), "I already have an account", "auth_view", AUTH_VIEWS.find("sign_in"))
            "forgot":
                text_at(Vector2(x, 160), "FORGOT YOUR PASSWORD?", 32, CYAN, true)
                paragraph(Vector2(x, 202), "We'll email you a link to choose a new one. It opens in your browser.", 560, 21, MUTED, 2)
                auth_field(auth_email_edit, 1, Vector2(x, 300), "Email")
                shown = [auth_email_edit]
                button(Vector2(x, 370), Vector2(560, 54), "Sending…" if a.auth.busy else "Send reset link", "auth_submit", 0, true)
                button(Vector2(x, 434), Vector2(560, 50), "Back to sign in", "auth_view", AUTH_VIEWS.find("sign_in"))
            "two_factor":
                text_at(Vector2(x, 160), "AUTHENTICATOR CODE", 32, CYAN, true)
                paragraph(Vector2(x, 202), "Enter a backup code." if auth_backup else "Enter the 6-digit code from your authenticator app.", 560, 21, MUTED, 2)
                auth_field(auth_code_edit, 3, Vector2(x, 300), "Backup code" if auth_backup else "Code")
                shown = [auth_code_edit]
                button(Vector2(x, 370), Vector2(560, 54), "Checking…" if a.auth.busy else "Continue", "auth_submit", 0, true)
                button(Vector2(x, 434), Vector2(272, 50), ("Authenticator" if handheld() else "Use authenticator") if auth_backup else ("Backup code" if handheld() else "Use a backup code"), "auth_backup")
                button(Vector2(x + 288, 434), Vector2(272, 50), "Back to sign in", "auth_view", AUTH_VIEWS.find("sign_in"))
            "check_email":
                text_at(Vector2(x, 160), "CHECK YOUR EMAIL", 32, CYAN, true)
                paragraph(Vector2(x, 214), "We sent a confirmation link to %s. Open it to finish creating your account, then sign in here." % a.auth.email, 560, 25, WHITE, 5)
                button(Vector2(x, 400), Vector2(560, 54), "Sign In", "auth_view", AUTH_VIEWS.find("sign_in"), true)
        if game.profile_source == "account": button(Vector2(x, 616), Vector2(560, 50), "Sign out", "sign_out")
        else: button(Vector2(x, 616), Vector2(560, 50), "Close / play as Guest", "title")
    for field in [auth_name_edit, auth_email_edit, auth_password_edit, auth_code_edit]:
        if not field in shown: field.visible = false
    if a.takeover_needed: button(Vector2(x, 680), Vector2(560, 44), confirm_label("takeover", 0, "Take over active account dig"), "takeover")
    elif a.pending_run_callback.is_valid(): button(Vector2(x, 680), Vector2(560, 44), "Retry account dig", "retry_run")
    elif game.net.invited_code() != "": button(Vector2(x, 680), Vector2(560, 44), "Continue to invited lobby", "invite_continue")
    var note = a.auth.note if a.auth.note != "" else (game.message_detail if game.message_time > 0 else "")
    if note != "": paragraph(Vector2(x, 752), note, 560, 22, ORANGE if a.auth.bad else YELLOW, 2)

func draw_android_update() -> void:
    backdrop()
    var update = game.android_updates
    var release = update.metadata
    page_title("UPDATE AVAILABLE", "Update for online play" if update.blocks_online() else "A new Android build is ready. Your saves stay on this device.")
    window(Vector2(64, 282), Vector2(1312, 430))
    text_at(Vector2(96, 340), "Relic Diver %s / %.1f MB" % [release.get("versionName", ""), float(release.get("bytes", 0)) / 1048576.0], 32, CYAN, true)
    paragraph(Vector2(96, 402), str(release.get("notes", "")), 1180, 27, WHITE, 5)
    paragraph(Vector2(96, 592), "Opens the download page in your browser. Install over this app; keep your saves. Android checks the signing key. No automatic download or installation.", 1180, 25, MUTED, 3)
    button(Vector2(64, 746), Vector2(620, 62), "Download update", "android_download", 0, true)
    button(Vector2(716, 746), Vector2(660, 62), "Continue solo / update later" if update.blocks_online() else "Later", "android_later")

func draw_credits() -> void:
    backdrop()
    page_title("CREDITS / LICENSES", "Non-profit fan game. Original Mega Man Legends characters and assets belong to Capcom.")
    window(Vector2(64, 282), Vector2(1312, 430))
    for i in 13:
        var index = credits_page * 13 + i
        if index < credits_lines.size(): text_at(Vector2(96, 320 + i * 29), credits_lines[index], 23, WHITE, false, 1220)
    button(Vector2(64, 746), Vector2(360, 62), "Previous page", "credits_page", -1)
    button(Vector2(456, 746), Vector2(360, 62), "Next page", "credits_page", 1)
    button(Vector2(848, 746), Vector2(528, 62), "Return to Title", "title")
    text_at(Vector2(64, 865), "Page %d / %d" % [credits_page + 1, maxi(1, ceili(credits_lines.size() / 13.0))], 23, CYAN)
