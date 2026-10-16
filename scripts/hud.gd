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
const ICONS = {"lens": 0, "spring": 1, "heart": 2, "boots": 3, "shell": 4, "moss": 5, "ember": 6, "coil": 7, "prism": 8, "echo": 9, "split": 10, "frost": 11, "clover": 12, "pulse": 13, "needle": 14, "siege": 15, "scrap": 16, "xp": 17, "map": 18, "lock": 19, "dash": 20, "cache": 21, "wrench": 22, "exit": 23, "life": 24, "settings": 25, "save": 26, "cursor": 27, "warning": 28, "record": 29, "eye": 30, "unknown": 31}
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
var ui_scale = 1.0
var ui_offset = Vector2.ZERO
var focus_index = 0
var selected_item = 0
var list_scroll = 0
var choice_preview = 0
var previous_mode = ""
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
const OPTIONS = ["master", "music", "effects", "ambience", "mute", "fullscreen", "camera", "fov", "mouse", "look", "invert", "vibration", "controls", "map_zoom", "back"]
const MENU_MODES = ["title", "pause", "options", "controls", "choice", "inventory", "archive", "end", "online", "lobby", "workshop", "save_codes", "account", "android_update", "credits"]
var credits_lines: PackedStringArray = []
var credits_page = 0
var options_return = "title"
var workshop_return = "title"
var workshop_character = 0
var workshop_message = ""
var workshop_focus_pending = false
var save_edit: LineEdit
var save_message = "Export a code to keep a backup outside this browser."
var pending_import: Dictionary = {}
var waiting_for_paste = false
# Rebinding: {"id": action, "column": "kb"/"pad", "time": seconds left}.
var listening: Dictionary = {}
var confirming = ""
var confirm_time = 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    for id in DiverCharacter.IDS: portraits.append(load("res://assets/ui/%s_portrait.png" % id))
    save_edit = make_field(32768, "Paste a Relic Diver save code here")
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
    field.add_theme_font_size_override("font_size", maxi(8, int(font_size * ui_scale)))

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
    game.selected_character = wrapi(index, 0, DiverCharacter.COUNT)
    game.player.set_character(game.selected_character)
    game.player.visual.preview(0)
    game.send_info()

func select_workshop_character(index: int) -> void:
    workshop_character = wrapi(index, 0, DiverCharacter.COUNT)
    workshop_message = ""
    pointer = Vector2(-100, -100)
    workshop_focus_pending = true

func workshop_first_node() -> int:
    var owned = DiverProgression.owned(game.meta, workshop_character)
    var first_unowned = -1
    for i in DiverProgression.NODES.size():
        var id = DiverProgression.NODES[i].id
        if id not in owned and first_unowned < 0: first_unowned = i
        if DiverProgression.can_buy(game.meta, workshop_character, id): return i
    # Keep the skills inspectable even when nothing is affordable or all are fitted.
    return maxi(0, first_unowned)

# The Workshop is three rows: digger headers, the skill column and the bottom
# buttons. Each keeps its own Left/Right meaning; Up/Down moves between them.
func workshop_navigate(delta: int, horizontal: bool) -> void:
    var tabs: Array[int] = []
    var nodes: Array[int] = []
    var row: Array[int] = []
    for i in hits.size():
        match hits[i].action:
            "tree_character": tabs.append(i)
            "buy_skill": nodes.append(i)
            _: row.append(i)
    if tabs.is_empty() or nodes.is_empty() or row.is_empty(): return
    var primary = row[mini(1, row.size() - 1)]
    if focus_index in tabs:
        if horizontal:
            # Preview the neighbouring digger without leaving the header row.
            workshop_character = wrapi(tabs.find(focus_index) + delta, 0, tabs.size())
            workshop_message = ""
            focus_index = tabs[workshop_character]
        else: focus_index = nodes[workshop_first_node()] if delta > 0 else primary
    elif focus_index in nodes:
        if horizontal: select_workshop_character(workshop_character + delta)
        else:
            var next = nodes.find(focus_index) + delta
            focus_index = tabs[workshop_character] if next < 0 else primary if next >= nodes.size() else nodes[next]
    elif focus_index in row:
        if horizontal: focus_index = row[clampi(row.find(focus_index) + delta, 0, row.size() - 1)]
        else: focus_index = nodes[nodes.size() - 1] if delta < 0 else tabs[workshop_character]
    else: focus_index = nodes[workshop_first_node()]

func workshop_label(entry: Dictionary, skills: Array, available: bool) -> String:
    if entry.id in skills: return "Fitted"
    if available: return "%d Z / Buy" % entry.cost
    if (entry.requires != "" and entry.requires not in skills) or (entry.id == "mastery" and "ability" not in skills): return "%d Z / Locked" % entry.cost
    if int(game.meta.zenny) < entry.cost: return "Need %d Z" % entry.cost
    return "%d Z / Syncing" % entry.cost

func title_account_copy() -> Dictionary:
    var a = game.account
    if a.state == "restoring":
        return {"label": "Account offline / Retry" if a.status == "Offline" else "Restoring account…", "detail": "Saved sign-in awaiting confirmation"}
    if a.state == "signing_in":
        return {"label": "Finish signing in…", "detail": "Approve this device in your browser"}
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

func text_at(pos: Vector2, value: String, size: int = 24, color: Color = WHITE, display: bool = false, width: float = -1) -> void:
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
    for word in value.split(" "):
        var proposed = line + (" " if line != "" else "") + word
        if font.get_string_size(proposed, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line != "":
            text_at(Vector2(pos.x, y), line, size, color)
            y += size * 1.3
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
    width = maxf(width, heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 16) if value != "↑↓" else width
    window(pos, Vector2(width, 28), Color("d1e5ed"), WHITE, false)
    if value == "↑↓":
        draw_colored_polygon(PackedVector2Array([pos + Vector2(11, 12), pos + Vector2(17, 5), pos + Vector2(23, 12)]), INK)
        draw_line(pos + Vector2(17, 10), pos + Vector2(17, 23), INK, 3)
        draw_colored_polygon(PackedVector2Array([pos + Vector2(27, 16), pos + Vector2(33, 23), pos + Vector2(39, 16)]), INK)
        draw_line(pos + Vector2(33, 6), pos + Vector2(33, 18), INK, 3)
    else:
        draw_string(heading, pos + Vector2(8, 21), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)

func cursor(pos: Vector2, side: float = 30) -> void:
    icon(pos + Vector2(sin(Time.get_ticks_msec() * 0.008) * 2, 0), "cursor", side)

func button(pos: Vector2, size: Vector2, title: String, action: String, value: int = 0, primary: bool = false) -> void:
    var area = Rect2(pos, size)
    var hot = focus_index == hits.size() or area.has_point(pointer)
    window(pos, size, SELECT if hot else Color("254991") if primary else PANEL, YELLOW if hot else EDGE)
    if hot: cursor(pos + Vector2(-28, size.y / 2 - 16))
    text_at(pos + Vector2(24, size.y / 2 + 10), title, 28, WHITE, false, size.x - 48)
    hits.append({"rect": area, "action": action, "value": value})

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        pointer = (event.position - ui_offset) / ui_scale
        if game.mode != "play":
            for i in hits.size():
                if hits[i].rect.has_point(pointer):
                    if focus_index != i: game.sound.play("menu_move")
                    focus_index = i
                    if hits[i].action == "inspect": selected_item = hits[i].value
                    if hits[i].action == "choice": choice_preview = hits[i].value
                    break
    if event is InputEventMouseButton and event.pressed and game.mode != "play":
        if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and game.mode in ["inventory", "archive"]:
            select_part(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if editing():
                var owner_field: Control = get_viewport().gui_get_focus_owner()
                if not owner_field.get_global_rect().has_point(event.position): get_viewport().gui_release_focus()
            var point = (event.position - ui_offset) / ui_scale
            for hit in hits:
                if hit.rect.has_point(point):
                    activate(hit.action, hit.value)
                    get_viewport().set_input_as_handled()
                    break
    if not listening.is_empty():
        capture_binding(event)
        return
    # Keys and controller buttons; stick motion is handled by game.pad_motion().
    if event is InputEventJoypadMotion or not event.is_pressed() or event.is_echo(): return
    if not game.mode in MENU_MODES or editing(): return
    if event is InputEventMouseButton: return
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
    pointer = Vector2(-100, -100)
    if game.mode == "options" and horizontal:
        if focus_index < OPTIONS.size(): adjust_option(focus_index, delta)
    elif game.mode == "controls" and not horizontal and focus_index < DiverSettings.ACTIONS.size() * 2:
        focus_index = clampi(focus_index + delta * 2, focus_index % 2, hits.size() - 1)
    elif game.mode == "choice": choice_preview = wrapi(choice_preview + delta, 0, 3)
    elif game.mode in ["archive", "inventory"]: select_part(delta)
    elif game.mode == "workshop": workshop_navigate(delta, horizontal)
    elif game.mode == "title" and horizontal:
        if not hits.is_empty() and hits[clampi(focus_index, 0, hits.size()-1)].action == "character":
            select_character(game.selected_character + 1)
        else:
            select_character(game.selected_character + delta)
    else: move_focus(delta)
    game.sound.play("menu_move")

func confirm() -> void:
    if game.mode == "choice": activate("choice", choice_preview)
    elif game.mode in ["inventory", "archive"]: activate("resume" if game.mode == "inventory" else "title")
    elif not hits.is_empty():
        var hit = hits[clampi(focus_index, 0, hits.size() - 1)]
        activate(hit.action, hit.value)

# Esc / B: step back out of the current menu. Returns true when handled.
func back() -> bool:
    match game.mode:
        "android_update": game.android_updates.later()
        "credits": activate("title")
        "account":
            if game.account.state == "signing_in": game.account.cancel_sign_in()
            activate("title")
        "archive", "online": activate("title")
        "workshop": activate(workshop_return)
        "save_codes": activate("workshop")
        "inventory", "pause": activate("resume")
        "options": activate(options_return)
        "controls": activate("options")
        "choice":
            if not game.can_defer_choice(): return false
            game.defer_choice()
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

func select_part(delta: int) -> void:
    var count = game.ITEMS.size() if game.mode == "archive" else game.player.items.size()
    if count > 0: selected_item = clampi(selected_item + delta, 0, count - 1)

func confirm_label(action: String, value: int, normal: String) -> String:
    return "Click again to confirm" if confirming == "%s:%d" % [action, value] else normal

func activate(action: String, value: int = 0) -> void:
    game.sound.play("menu_confirm")
    if action in CONFIRM and confirming != "%s:%d" % [action, value]:
        confirming = "%s:%d" % [action, value]
        confirm_time = 3.0
        return
    confirming = ""
    match action:
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
        "device_open": game.account.open_device_page()
        "device_cancel": game.account.cancel_sign_in()
        "migrate_guest": game.account.preview_migration(game.guest_meta)
        "migrate_confirm": game.account.confirm_migration()
        "takeover":
            game.account.retry_run(true)
        "retry_run": game.account.retry_run()
        "clear_session":
            game.account.clear_local_session()
            if game.profile_source == "guest": game.show_title()
        "invite_continue":
            game.mode = "online"
            game.net.join_lobby(game.net.invited_code(), game.net.url_param("key"))
        "start": game.start_run()
        "start_new": game.start_run()
        "continue": game.continue_saved_dig()
        "discard": game.discard_saved_dig()
        "give_up": game.net.give_up("You left while reconnecting.")
        "kick": game.net.kick(value)
        "lock": game.net.set_locked(not bool(game.net.lobby.get("locked", false)))
        "resume": game.resume_game()
        "choice": game.choose(value)
        "workshop":
            if game.mode != "save_codes":
                workshop_return = game.mode
                workshop_character = game.selected_character
                workshop_message = ""
            game.mode = "workshop"
        "tree_character": select_workshop_character(value)
        "buy_skill":
            var id = DiverProgression.NODES[value].id
            var accepted = game.buy_skill(workshop_character, id)
            workshop_message = ("Purchase queued. Waiting for server confirmation." if game.profile_source == "account" else "Purchased " + DiverProgression.NODES[value].name) if accepted else "Purchase unavailable: check connection, Zenny and prerequisites."
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
        "mute": game.sound.muted = not game.sound.muted
        "options":
            if game.mode in ["title", "pause"]: options_return = game.mode
            game.mode = "options"
            focus_index = 0
        "option": activate_option(value)
        "controls": game.mode = "controls"
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
    ui_scale = minf(get_viewport_rect().size.x / BASE.x, get_viewport_rect().size.y / BASE.y)
    ui_offset = (get_viewport_rect().size - BASE * ui_scale) * 0.5
    draw_set_transform(ui_offset, 0, Vector2.ONE * ui_scale)
    if game.mode != previous_mode:
        previous_mode = game.mode
        focus_index = 0
        selected_item = 0
        list_scroll = 0
        choice_preview = 0
        pointer = Vector2(-100, -100)
        if game.mode == "workshop": workshop_focus_pending = true
    hits.clear()
    copied_time = maxf(0, copied_time - get_process_delta_time())
    confirm_time -= get_process_delta_time()
    if confirm_time <= 0: confirming = ""
    # Hiding a focused LineEdit releases focus, even if shown again in this draw.
    # Only hide fields when their page no longer owns them.
    name_edit.visible = game.mode in ["online", "lobby"]
    for field in [code_edit, server_edit, pass_edit, new_pass_edit]:
        if game.mode != "online": field.visible = false
    save_edit.visible = game.mode == "save_codes"
    var chatting = game.net.active() and (game.mode == "lobby" or (game.mode == "play" and game.chat_open))
    if not chatting: chat_edit.visible = false
    match game.mode:
        "model_preview": return
        "title": draw_title()
        "online": draw_online()
        "lobby": draw_lobby()
        "archive": draw_parts(true)
        "choice": draw_choice()
        "pause": draw_pause()
        "options": draw_options()
        "controls": draw_controls()
        "inventory": draw_parts(false)
        "end": draw_end()
        "workshop": draw_workshop()
        "save_codes": draw_save_codes()
        "account": draw_account()
        "android_update": draw_android_update()
        "credits": draw_credits()
        _: draw_hud()

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
    text_at(Vector2(166, 242), detail, 24, MUTED)

func menu_footer(detail: String = "Select", back: String = "Back", confirm: String = "Confirm") -> void:
    keycap(Vector2(64, 842), "D-PAD" if pad() else "↑↓", 46)
    text_at(Vector2(124 + (34 if pad() else 0), 865), detail, 21)
    keycap(Vector2(284, 842), "A" if pad() else "ENTER", 76)
    text_at(Vector2(374, 865), confirm, 21)
    keycap(Vector2(1150, 842), "B" if pad() else "ESC", 55)
    text_at(Vector2(1220, 865), back, 21)

func draw_title() -> void:
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
    text_at(Vector2(1042, 237), account_copy.detail, 23, CYAN, false, 328)
    var menu_y = 418
    var saved: Dictionary = game.saved_dig
    if not saved.is_empty():
        var w: Dictionary = saved.world
        var detail = "B%d · %02d:%02d" % [int(w.get("depth", 1)), int(w.get("run_time", 0)) / 60, int(w.get("run_time", 0)) % 60]
        button(Vector2(64, menu_y), Vector2(476, 48), ("Rejoin Dig %s  (%s)" % [saved.lobby_code, detail]) if saved.get("online", false) else "Continue Dig  (%s)" % detail, "continue", 0, true)
        menu_y += 56
        button(Vector2(64, menu_y), Vector2(476, 48), confirm_label("start_new", 0, "New Dig (ends the saved one)"), "start_new")
    else: button(Vector2(64, menu_y), Vector2(476, 48), "Start Dig", "start", 0, true)
    menu_y += 56
    button(Vector2(64, menu_y), Vector2(476, 48), "Play Online", "online", 0, saved.is_empty())
    menu_y += 56
    button(Vector2(64, menu_y), Vector2(476, 48), "Parts Collection", "archive")
    menu_y += 56
    if OS.has_feature("web"): button(Vector2(64, menu_y), Vector2(476, 48), "Options", "options")
    else:
        button(Vector2(64, menu_y), Vector2(230, 48), "Options", "options")
        button(Vector2(310, menu_y), Vector2(230, 48), "Quit", "quit")
    window(Vector2(48, 690), Vector2(508, 156))
    text_at(Vector2(68, 723), "SIGNATURE ATTACK", 21, WHITE, true)
    button(Vector2(68, 854), Vector2(472, 40), "Workshop / Zenny & Skill Trees", "workshop")
    text_at(Vector2(72, 766), game.WEAPONS[game.selected_weapon], 28, YELLOW, true)
    paragraph(Vector2(72, 808), DiverPlayer.ATTACK_DETAILS[game.selected_character], 460, 22, MUTED, 2)
    window(Vector2(1080, 32), Vector2(312, 104), Color(0.06, 0.16, 0.40, 0.92))
    icon(Vector2(1098, 51), "record", 48)
    text_at(Vector2(1162, 65), "DIG RECORD", 21, WHITE, true)
    text_at(Vector2(1162, 101), "%d digs   /   %d clears" % [game.meta.runs, game.meta.wins], 24, YELLOW)
    window(Vector2(1020, 348), Vector2(372, 200), Color(0.06, 0.16, 0.40, 0.96))
    text_at(Vector2(1042, 382), "SELECT DIGGER", 22, WHITE, true)
    keycap(Vector2(1336, 360), "Y" if pad() else "C", 34)
    for i in DiverCharacter.COUNT:
        var pos = Vector2(1038 + (i % 2) * 172, 399 + (i / 2) * 70)
        var selected = game.selected_character == i
        var hot = focus_index == hits.size() or Rect2(pos, Vector2(162, 64)).has_point(pointer)
        window(pos, Vector2(162, 64), SELECT if selected else INK, YELLOW if selected or hot else EDGE)
        draw_texture_rect(portraits[i], Rect2(pos + Vector2(2, 3), Vector2(52, 58)), false)
        text_at(pos + Vector2(60, 41), DiverCharacter.SHORT_NAMES[i].capitalize(), 25 if i < 3 else 21, WHITE, true)
        if hot: cursor(pos + Vector2(-22, 20), 24)
        hits.append({"rect": Rect2(pos, Vector2(162, 64)), "action": "character", "value": i})
    window(Vector2(1020, 574), Vector2(372, 274), Color(0.06, 0.16, 0.40, 0.94))
    text_at(Vector2(1044, 613), "CONTROLLER" if pad() else "CONTROLS", 24, WHITE, true)
    var controls = [["move", "Move"], ["fire", "Fire buster"], ["dash", "Dash"], ["jump", "Jump"], ["interact", "Salvage / use"], ["lock_on", "Lock on"]]
    for i in controls.size():
        var y = 636 + i * 32
        keycap(Vector2(1044, y), p(controls[i][0]), 76)
        text_at(Vector2(1140, y + 23), controls[i][1], 23)

    button(Vector2(1020, 154), Vector2(372, 50), account_copy.label, "account")
    small_button(Vector2(1020, 274), Vector2(372, 42), "Credits / Licenses", "credits")

func draw_hud() -> void:
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
    window(Vector2(1186, 28), Vector2(222, 244), Color(0.05, 0.13, 0.35, 0.88))
    text_at(Vector2(1203, 57), "RUINS MAP", 19, WHITE, true)
    map_at(Vector2(1200, 72), 192)
    icon(Vector2(1184, 289), "scrap", 45)
    text_at(Vector2(1236, 323), "%06d" % game.scrap, 29, YELLOW, true)
    text_at(Vector2(1222, 356), game.time_string(), 24, WHITE, true)
    text_at(Vector2(1188, 391), "%d / %d rooms" % [visited_count(), game.rooms.size()], 21, WHITE)
    var center = Vector2(720, 450)
    var spread = 5.0 + p.recoil * 5
    for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
        draw_line(center + dir * spread, center + dir * (spread + 6), INK, 4)
        draw_line(center + dir * spread, center + dir * (spread + 6), WHITE, 2)
    draw_circle(center, 2, YELLOW)
    if game.hit_confirm > 0:
        for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]: draw_line(center + dir * 14, center + dir * 21, GREEN if game.kill_confirm > 0 else YELLOW, 3)
    if game.kill_confirm > 0: text_at(center + Vector2(-40, 45), "SALVAGED", 18, GREEN)
    if is_instance_valid(p.lock_target):
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
    window(Vector2(30, 738), Vector2(310, 104), Color(0.05, 0.13, 0.35, 0.92))
    icon(Vector2(42, 750), ["pulse", "needle", "siege", "scrap"][p.weapon], 62)
    text_at(Vector2(114, 774), ["Pulse Buster", "Needle Buster", "Siege Buster", "Salvage Bombs"][p.weapon], 25, WHITE, true, 212)
    text_at(Vector2(114, 805), "POWER %d  /  RAPID %.1f" % [buster_power(), 1 / p.fire_delay()], 21, MUTED)
    pips(Vector2(48, 824), 270, 6, float(p.xp) / p.xp_required, 20, YELLOW)
    keycap(Vector2(30, 856), p("parts"), 54)
    var waiting = game.pending_choices.size()
    if waiting > 0: text_at(Vector2(99, 879), "Choose Part ×%d" % waiting if waiting > 1 else "Choose Part", 21, YELLOW if int(Time.get_ticks_msec() / 400) % 2 == 0 else WHITE)
    else: text_at(Vector2(99, 879), "Buster Parts", 21)
    var n = 0
    for id in p.items:
        var x = 382 + n * 53
        window(Vector2(x, 792), Vector2(48, 53), BLUE, EDGE, false)
        icon(Vector2(x + 2, 792), id, 44)
        var count_text = str(p.items[id])
        var count_width = maxf(30, heading.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 18)
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
        elif pad(): text_at(Vector2(1064, 734), "%s ping  ·  D-pad callouts" % p("ping"), 19, MUTED)
        else: text_at(Vector2(1064, 734), "%s chat  ·  %s ping  ·  1–4 callouts" % [p("chat"), p("ping")], 19, MUTED)
        if game.net.reconnecting(): draw_reconnecting()
    if game.message_time > 0: draw_notice()
    if not game.nearest.is_empty() and game.mode == "play" and not p.downed: interaction_prompt()
    if game.mode == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless" and not pad() and not OS.has_feature("android"):
        window(Vector2(560, 384), Vector2(320, 46), INK, YELLOW, false)
        text_at(Vector2(584, 415), "Click to take aim", 24, YELLOW, true)
    if game.hurt_flash > 0: rect(Vector2.ZERO, BASE, Color(0.9, 0.2, 0.08, game.hurt_flash * 0.25))

func draw_notice() -> void:
    window(Vector2(402, 630), Vector2(636, 98), Color(0.06, 0.16, 0.39, 0.96))
    icon(Vector2(419, 647), "cache" if game.message == "PART CHOICE WAITING" else "record", 48)
    var title: String = {"CHAMBER SECURED": "Room Cleared!", "GUARDIAN SILENCED": "Guardian Defeated!", "BUSTER CALIBRATED": "Power Increased!", "CORE EXPANDED": "Life Increased!", "CAPACITOR TUNED": "Rapid Fire Increased!", "SYSTEMS RESTORED": "Life Restored!", "INSUFFICIENT SCRAP": "Not Enough Scrap", "CACHE SEALED": "Cache Sealed", "LIFT SEALED": "Lift Sealed", "PART CHOICE WAITING": "Part Choice Waiting!"}.get(game.message, game.message)
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
    var inside = Rect2(pos + Vector2.ONE * 4, Vector2.ONE * (side - 8))
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
        draw_circle(at, 3.5, INK)
        draw_circle(at, 2.5, ORANGE if mate.downed else DiverNet.SLOT_COLORS[clampi(mate.slot, 0, 4)])
    var p = game.player
    var here = (origin + Vector2(p.global_position.x, p.global_position.z) * zoom).clamp(inside.position, inside.end)
    var forward = Vector2(-sin(p.yaw), -cos(p.yaw))
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
    return {"master": "Master volume", "music": "Music", "effects": "Effects", "ambience": "Ambience", "mute": "Mute all", "fullscreen": "Fullscreen", "camera": "Camera motion", "fov": "Field of view", "mouse": "Mouse sensitivity", "look": "Controller look speed", "invert": "Invert look (up/down)", "vibration": "Controller vibration", "controls": "Controls & bindings…", "map_zoom": "Ruins map", "back": "Back"}.get(id, id)

func option_value(id: String) -> String:
    var s = game.settings
    match id:
        "master", "music", "effects", "ambience": return "%d%%" % roundi(game.sound.volumes[id.capitalize()] * 100)
        "mute": return "On" if game.sound.muted else "Off"
        "fullscreen": return "On" if s.fullscreen else "Off"
        "map_zoom": return "Follow / zoomed" if s.map_zoom else "Whole floor"
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
        "mute", "fullscreen", "camera", "invert", "vibration", "map_zoom": activate_option(index)
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
        "camera": s.camera_effects = not s.camera_effects
        "fov": s.fov = 55.0 if s.fov >= 85 else s.fov + 5
        "mouse": s.mouse_sensitivity = 0.2 if s.mouse_sensitivity >= 3.0 else snappedf(s.mouse_sensitivity + 0.2, 0.1)
        "look": s.look_speed = 0.2 if s.look_speed >= 3.0 else snappedf(s.look_speed + 0.2, 0.1)
        "invert": s.invert_y = not s.invert_y
        "vibration":
            s.vibration = not s.vibration
            s.rumble(0.4, 0.4, 0.15)
        "controls": game.mode = "controls"
        "back": activate(options_return)
    s.save_settings()

func option_row(pos: Vector2, index: int) -> void:
    var id: String = OPTIONS[index]
    var area = Rect2(pos, Vector2(640, 54))
    var hot = focus_index == index or area.has_point(pointer)
    window(pos, area.size, SELECT if hot else PANEL, YELLOW if hot else EDGE, false)
    if hot: cursor(pos + Vector2(-30, 12))
    text_at(pos + Vector2(22, 36), option_label(id), 25, WHITE, false, 400)
    var value = option_value(id)
    if value != "":
        if id in ["master", "music", "effects", "ambience"]:
            pips(pos + Vector2(330, 21), 180, 12, game.sound.volumes[id.capitalize()], 12, CYAN if id == "music" else GREEN)
        text_at(pos + Vector2(612 - heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, 36), value, 22, YELLOW, true)
    hits.append({"rect": area, "action": "option", "value": index})

func draw_options() -> void:
    backdrop()
    page_title("OPTIONS", "Sound, display and controls. Changes save right away%s." % (" in this browser" if OS.has_feature("web") else " on this PC"))
    text_at(Vector2(66, 278), "SOUND & DISPLAY", 20, CYAN, true)
    text_at(Vector2(738, 278), "CONTROLS", 20, CYAN, true)
    for i in OPTIONS.size():
        option_row(Vector2(64, 292 + i * 62) if i < 8 else Vector2(736, 292 + (i - 8) * 62), i)
    window(Vector2(736, 752), Vector2(640, 72), Color(0.06, 0.16, 0.40, 0.9))
    paragraph(Vector2(758, 780), "Left / right adjusts. Plug in a controller any time: prompts switch to it automatically.", 600, 23, MUTED, 2)
    menu_footer("Select", "Back", "Change")

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
    var note = "Waiting for input… (Esc cancels)" if not listening.is_empty() else "The right stick always looks around. Taking a key from another action swaps them."
    text_at(Vector2(736, 812), note, 21, YELLOW if not listening.is_empty() else MUTED, false, 640)
    menu_footer("Select", "Options", "Rebind")

func stat_line(pos: Vector2, title: String, value: String, width: float) -> void:
    text_at(pos, title, 26, MUTED)
    draw_line(pos + Vector2(0, 12), pos + Vector2(width, 12), Color("416399"), 1)
    text_at(pos + Vector2(width - heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x, 0), value, 25, WHITE, true)

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

func draw_choice() -> void:
    backdrop()
    stats_header()
    var relic = game.choice_kind == "relic"
    page_title("CHOOSE A PART" if relic else "LEVEL UP!", "Fit one part. Finding duplicates strengthens their effect." if relic else "Choose an upgrade for this dig.")
    for i in 3:
        var pos = Vector2(64, 288 + i * 128)
        var id: String = game.choice_items[i]
        var selected = i == choice_preview
        window(pos, Vector2(664, 112), SELECT if selected else PANEL, YELLOW if selected else EDGE)
        if selected: cursor(pos + Vector2(-31, 37))
        icon(pos + Vector2(23, 19), id if relic else ["pulse", "life", "spring"][i], 74)
        var title: String = game.ITEMS[id].name if relic else ["Buster Power", "Life Expansion", "Rapid Fire"][i]
        text_at(pos + Vector2(122, 42), title, 29, WHITE, true, 455)
        text_at(pos + Vector2(122, 79), TYPES[id] if relic else ["+3 base power", "+20 max Life / restore 35 Life", "+15% base fire rate"][i], 24, CYAN)
        badge(pos + Vector2(589, 39), str(i + 1), 44)
        hits.append({"rect": Rect2(pos, Vector2(664, 112)), "action": "choice", "value": i})
    window(Vector2(768, 280), Vector2(608, 488))
    var selected_id: String = game.choice_items[choice_preview]
    text_at(Vector2(800, 329), game.ITEMS[selected_id].name if relic else ["Buster Power", "Life Expansion", "Rapid Fire"][choice_preview], 32, WHITE, true, 544)
    window(Vector2(968, 356), Vector2(208, 166), INK, Color("6285b8"), false)
    icon(Vector2(1000, 367), selected_id if relic else ["pulse", "life", "spring"][choice_preview], 144)
    var detail: String = DESCRIPTIONS[selected_id] if relic else ["Adds 3 base buster power. Power-boosting parts multiply the new total.", "Adds 20 maximum Life and restores 35 Life right away.", "Adds 15% base fire rate. Combine it with Clockwork Springs for faster firing."][choice_preview]
    paragraph(Vector2(800, 564), detail, 544, 27, WHITE, 3)
    text_at(Vector2(800, 682), "Fitted ×%d  →  ×%d" % [game.player.count(selected_id), game.player.count(selected_id) + 1] if relic else "Upgrade lasts for this dig", 25, YELLOW)
    button(Vector2(800, 706), Vector2(544, 48), "Fit This Part" if relic else "Apply Upgrade", "choice", choice_preview)
    window(Vector2(64, 706), Vector2(664, 62))
    var fitted: Dictionary = game.player.items
    if fitted.is_empty(): text_at(Vector2(86, 747), "No parts fitted yet. Parts stay fitted until this dig ends.", 24, MUTED)
    else:
        text_at(Vector2(82, 745), "FITTED", 18, MUTED, true)
        var step = minf(50.0, 548.0 / fitted.size())
        var n = 0
        for id in fitted:
            var x = 166 + n * step
            icon(Vector2(x, 712), id, 44)
            text_at(Vector2(x + 30, 762), str(fitted[id]), 17, YELLOW, true)
            n += 1
    keycap(Vector2(64, 842), "D-PAD" if pad() else "1 2 3", 86)
    text_at(Vector2(168, 865), "Quick select", 22)
    keycap(Vector2(382, 842), "D-PAD" if pad() else "↑↓", 46)
    text_at(Vector2(443, 865), "Browse", 22)
    if game.can_defer_choice():
        keycap(Vector2(640, 842), p("parts"), 54)
        text_at(Vector2(708, 865), "Choose later", 22)
    keycap(Vector2(1050, 842), "A" if pad() else "ENTER", 76)
    text_at(Vector2(1142, 865), "Fit selected part", 22)

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
    var hot = area.has_point(pointer)
    window(pos, size, SELECT if hot else color, YELLOW if hot else EDGE, false)
    text_at(pos + Vector2(12, size.y / 2 + 7), title, 19, WHITE, false, size.x - 20)
    hits.append({"rect": area, "action": action, "value": value})

func digger_card(pos: Vector2, member_slot: int, member_name: String, character: int, weapon: int) -> void:
    var net = game.net
    var color: Color = DiverNet.SLOT_COLORS[clampi(member_slot, 0, 4)]
    window(pos, Vector2(672, 92), BLUE if member_slot == net.slot else INK, color, false)
    window(pos + Vector2(10, 8), Vector2(68, 76), BLUE, EDGE, false)
    draw_texture_rect(portraits[clampi(character, 0, DiverCharacter.COUNT - 1)], Rect2(pos + Vector2(13, 10), Vector2(62, 72)), false)
    text_at(pos + Vector2(94, 38), member_name, 27, color, true, 330)
    text_at(pos + Vector2(94, 72), "%s  ·  %s" % [DiverCharacter.SHORT_NAMES[clampi(character, 0, DiverCharacter.COUNT - 1)].capitalize(), ["Pulse Buster", "Needle Buster", "Siege Buster", "Salvage Bombs"][clampi(weapon, 0, 3)]], 22, MUTED, false, 360)
    var x = 576
    if member_slot == net.host_slot:
        badge(pos + Vector2(x, 14), "HOST", 86, YELLOW)
        x -= 92
    if member_slot == net.slot: badge(pos + Vector2(x, 14), "YOU", 80, CYAN)
    elif net.is_host(): small_button(pos + Vector2(486, 50), Vector2(176, 34), confirm_label("kick", member_slot, "Remove"), "kick", member_slot, Color(0.30, 0.10, 0.14))

func draw_lobby() -> void:
    backdrop()
    var net = game.net
    var info: Dictionary = net.lobby
    var extras = []
    if net.lobby_password != "": extras.append("password %s" % net.lobby_password)
    if bool(info.get("locked", false)): extras.append("locked")
    page_title(str(info.get("name", "Lobby")).to_upper(), "%s lobby · Code %s%s" % ["Public" if info.get("isPublic", true) else "Private", net.lobby_code, ("  ·  " + "  ·  ".join(extras)) if not extras.is_empty() else ""])
    window(Vector2(64, 276), Vector2(560, 150))
    text_at(Vector2(86, 310), "INVITE LINK", 20, WHITE, true)
    text_at(Vector2(86, 346), net.invite_link(), 22, CYAN, false, 516)
    button(Vector2(86, 362), Vector2(272, 50), "Copied!" if copied_time > 0 else "Copy Invite Link", "copy_link", 0, true)
    text_at(Vector2(390, 400), net.lobby_code, 38, YELLOW, true)
    window(Vector2(64, 444), Vector2(560, 100))
    text_at(Vector2(86, 476), "YOUR NAME", 20, WHITE, true)
    if not editing() or get_viewport().gui_get_focus_owner() != name_edit: name_edit.text = net.player_name
    place_field(name_edit, Vector2(86, 488), Vector2(516, 44))
    window(Vector2(64, 562), Vector2(560, 196))
    text_at(Vector2(86, 594), "YOUR DIGGER", 20, WHITE, true)
    for i in DiverCharacter.COUNT:
        var pos = Vector2(86 + i * 131, 606)
        var selected = game.selected_character == i
        var hot = Rect2(pos, Vector2(125, 60)).has_point(pointer)
        window(pos, Vector2(125, 60), SELECT if selected else INK, YELLOW if selected or hot else EDGE, false)
        draw_texture_rect(portraits[i], Rect2(pos + Vector2(4, 3), Vector2(48, 54)), false)
        text_at(pos + Vector2(56, 38), DiverCharacter.SHORT_NAMES[i].capitalize(), 19 if i < 3 else 15, WHITE, true)
        hits.append({"rect": Rect2(pos, Vector2(125, 60)), "action": "character", "value": i})
    text_at(Vector2(86, 710), game.WEAPONS[game.selected_weapon], 25, YELLOW, true)
    paragraph(Vector2(86, 746), DiverPlayer.ATTACK_DETAILS[game.selected_character], 520, 22, MUTED, 2)
    if game.account.takeover_needed: button(Vector2(64, 778), Vector2(280, 58), confirm_label("takeover", 0, "Take over dig"), "takeover", 0, true)
    elif game.account.pending_run_callback.is_valid(): button(Vector2(64, 778), Vector2(280, 58), "Retry account dig", "retry_run", 0, true)
    elif net.is_host(): button(Vector2(64, 778), Vector2(280, 58), "Start Dig", "start_online", 0, true)
    else:
        window(Vector2(64, 778), Vector2(280, 58), INK, EDGE, false)
        text_at(Vector2(84, 815), "Waiting for host…", 23, YELLOW)
    button(Vector2(364, 778), Vector2(260, 58), confirm_label("leave_online", 0, "Leave Lobby"), "leave_online")
    var members: Array = net.members()
    window(Vector2(656, 276), Vector2(720, 470))
    text_at(Vector2(680, 314), "PARTY   %d / %d" % [members.size(), DiverNet.MAX_PLAYERS], 26, WHITE, true)
    if net.is_host(): small_button(Vector2(1176, 288), Vector2(180, 36), "Unlock Lobby" if bool(info.get("locked", false)) else "Lock Lobby", "lock")
    for i in DiverNet.MAX_PLAYERS:
        var pos = Vector2(680, 330 + i * 102)
        if i < members.size():
            var member_slot = int(members[i].slot)
            if member_slot == net.slot: digger_card(pos, member_slot, net.player_name, game.selected_character, game.selected_weapon)
            else:
                var peer: Dictionary = game.peers.get(member_slot, {})
                digger_card(pos, member_slot, str(members[i].name), int(peer.get("character", 0)), int(peer.get("weapon", 0)))
        else:
            window(pos, Vector2(672, 92), Color(0.05, 0.12, 0.32, 0.6), Color("4c6ea6"), false)
            text_at(pos + Vector2(28, 54), "Open slot — waiting for a digger", 23, Color("6f8fc0"))
    # Lobby chat.
    draw_chat(Vector2(660, 790), 716, 2, false)
    place_field(chat_edit, Vector2(656, 800), Vector2(720, 36), 19)
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
        var name_width = font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 8
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
    page_title("THE WORKSHOP", "Permanent circuits / Each digger has their own tree. Parts and levels reset each dig.")
    text_at(Vector2(1090, 232), "%d ZENNY" % game.meta.zenny, 30, YELLOW, true)
    if game.profile_source == "account": text_at(Vector2(64, 262), "%s / +%d pending" % [game.account.status, game.account.pending_zenny()], 21, CYAN)
    text_at(Vector2(824, 262), "LB / RB: Digger   Up / Down: Skills" if pad() else "Left / Right: Digger   Up / Down: Skills", 20, MUTED, false, 552)
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
    window(Vector2(64, 366), Vector2(300, 414))
    draw_texture_rect(portraits[workshop_character], Rect2(92, 388, 244, 282), false)
    paragraph(Vector2(86, 712), DiverPlayer.ATTACK_DETAILS[workshop_character], 260, 23, CYAN, 3)
    var skills = DiverProgression.owned(game.meta, workshop_character)
    for i in DiverProgression.NODES.size():
        var entry = DiverProgression.NODES[i]
        var pos = Vector2(394, 366 + i * 82)
        var owned = entry.id in skills
        var available = DiverProgression.can_buy(game.meta, workshop_character, entry.id) and (game.profile_source == "guest" or game.account.status == "Synced")
        window(pos, Vector2(982, 72), SELECT if owned else PANEL, GREEN if owned else EDGE, false)
        text_at(pos + Vector2(18, 28), entry.name, 24, YELLOW if owned else WHITE, true)
        var detail = DiverProgression.ABILITIES[workshop_character] if entry.id == "ability" else "Adds %s to this digger's drop pool." % game.ITEMS[DiverProgression.RESEARCH[workshop_character]].name if entry.id == "salvage" else entry.desc
        text_at(pos + Vector2(18, 56), detail, 21, MUTED, false, 715)
        var label = workshop_label(entry, skills, available)
        if workshop_focus_pending and i == first_node: focus_index = hits.size()
        button(pos + Vector2(748, 12), Vector2(216, 48), label, "buy_skill", i)
    workshop_focus_pending = false
    text_at(Vector2(394, 802), workshop_message if workshop_message != "" else "Frame > Mobility + Research > Signature Circuit > Master Mechanic", 22, CYAN)
    button(Vector2(64, 828), Vector2(300, 56), "Save Codes / Backup", "save_codes")
    button(Vector2(394, 828), Vector2(460, 56), "Return to Lobby" if game.net.active() else "Start Another Dig", "lobby_room" if game.net.active() else "start", 0, true)
    button(Vector2(884, 828), Vector2(492, 56), "Back", workshop_return)

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

func draw_account() -> void:
    backdrop()
    page_title("DIGGER ACCOUNT", "Permanent progress across browser, Windows and Android. Guest progress stays on this device.")
    var a = game.account
    window(Vector2(64, 282), Vector2(1312, 430))
    if a.state == "signing_in":
        text_at(Vector2(96, 335), "SIGN IN ON YOUR BROWSER", 30, CYAN, true)
        text_at(Vector2(96, 430), str(a.device.get("user_code", "Requesting code…")), 64, YELLOW, true)
        paragraph(Vector2(96, 496), ("Approve this device in your browser. Code expires in %d seconds. " % maxi(0, int(a.device_remaining))) + ("Android remembers your session using secure storage." if OS.has_feature("android") else "Windows sessions stay in memory; sign in again after closing the game."), 1180, 27, WHITE, 3)
        button(Vector2(96, 620), Vector2(560, 58), "Open sign-in page", "device_open")
        button(Vector2(688, 620), Vector2(560, 58), "Cancel", "device_cancel")
    elif a.state == "restoring":
        text_at(Vector2(96, 342), "RESTORING YOUR ACCOUNT", 30, CYAN, true)
        paragraph(Vector2(96, 412), "Waiting for the server to confirm your saved session. Retry when connected, or explicitly choose Guest to play offline.", 1180, 30, WHITE, 4)
        button(Vector2(96, 620), Vector2(560, 58), "Retry sync", "account_retry")
        button(Vector2(688, 620), Vector2(560, 58), "Play as Guest", "guest")
    elif game.profile_source == "account":
        text_at(Vector2(96, 335), str(a.identity.get("name", "Digger")) + " / " + a.status, 30, CYAN, true)
        var synced = "Never" if a.last_sync == 0 else Time.get_datetime_string_from_unix_time(int(a.last_sync), true) + " UTC"
        text_at(Vector2(96, 382), "Last sync: " + synced + " / +%d pending Zenny" % a.pending_zenny(), 25, YELLOW)
        text_at(Vector2(96, 430), "Cloud: %d digs / %d machines / %d Zenny" % [game.meta.runs, game.meta.kills, game.meta.zenny], 27)
        text_at(Vector2(96, 476), "This device's Guest: %d digs / %d machines / %d Zenny" % [game.guest_meta.runs, game.guest_meta.kills, game.guest_meta.zenny], 27)
        if not a.migration.is_empty():
            text_at(Vector2(96, 531), "Adopt: %d digs / %d Zenny / %d purchased circuits" % [a.migration.preview.runs, a.migration.preview.zenny, a.migration.preview.trees], 26, YELLOW)
            button(Vector2(96, 550), Vector2(600, 56), "Confirm adoption into empty account", "migrate_confirm")
        elif a.empty_account(): button(Vector2(96, 550), Vector2(600, 56), "Use this PC's progress / Preview", "migrate_guest")
        else: text_at(Vector2(96, 570), "Cloud progress is active. Your Guest archive remains untouched.", 26, MUTED)
        button(Vector2(96, 630), Vector2(340, 56), "Retry sync", "account_retry")
        button(Vector2(468, 630), Vector2(340, 56), "Sign Out", "sign_out")
        if a.state == "needs_sign_in": button(Vector2(840, 630), Vector2(400, 56), "Sign In again", "sign_in")
    else:
        text_at(Vector2(96, 342), "PLAY AS GUEST OR BRING YOUR PROGRESS", 30, CYAN, true)
        paragraph(Vector2(96, 412), "Guest digs work offline. Account digs and Workshop purchases need the server. Pending results retry safely and become spendable after confirmation.", 1180, 30, WHITE, 4)
        button(Vector2(96, 620), Vector2(560, 58), "Sign In", "sign_in", 0, true)
        button(Vector2(688, 620), Vector2(560, 58), "Play as Guest", "guest")
    if a.takeover_needed: button(Vector2(64, 736), Vector2(620, 56), confirm_label("takeover", 0, "Take over active account dig"), "takeover")
    elif a.pending_run_callback.is_valid(): button(Vector2(64, 736), Vector2(620, 56), "Retry account dig", "retry_run")
    elif game.net.invited_code() != "": button(Vector2(64, 736), Vector2(620, 56), "Continue to invited lobby", "invite_continue")
    else: button(Vector2(64, 736), Vector2(620, 56), "Return to Title", "title")
    if game.profile_source == "account": button(Vector2(716, 736), Vector2(660, 56), "Play as Guest / keep cloud outbox", "guest")
    if game.profile_source == "account" and a.outbox.is_empty(): button(Vector2(716, 810), Vector2(660, 48), confirm_label("clear_session", 0, "Sign Out + clear this account's local cache"), "clear_session")
    paragraph(Vector2(64, 880), game.message_detail if game.message_time > 0 else "No automatic merges. Leave a dig or lobby before changing accounts.", 1312, 22, YELLOW, 1)

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
