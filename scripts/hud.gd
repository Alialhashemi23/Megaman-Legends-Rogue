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

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    for id in ["volnutt", "roll"]: portraits.append(load("res://assets/ui/%s_portrait.png" % id))

func portrait() -> Texture2D:
    return portraits[game.player.character]

func select_character(index: int) -> void:
    game.selected_character = clampi(index, 0, 1)
    game.player.set_character(game.selected_character)
    game.player.visual.preview(0)

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

func keycap(pos: Vector2, value: String, width: float = 44) -> void:
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
            var point = (event.position - ui_offset) / ui_scale
            for hit in hits:
                if hit.rect.has_point(point):
                    activate(hit.action, hit.value)
                    get_viewport().set_input_as_handled()
                    break
    if event is InputEventKey and event.pressed and not event.echo and game.mode in ["title", "pause", "audio", "choice", "inventory", "archive", "end"]:
        var key = event.physical_keycode
        if key == 0: key = event.keycode
        if key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
            var delta = -1 if key in [KEY_UP, KEY_LEFT] else 1
            pointer = Vector2(-100, -100)
            if game.mode == "audio" and key in [KEY_LEFT, KEY_RIGHT]:
                if focus_index < 4: game.sound.adjust_volume(["Master", "Music", "Effects", "Ambience"][focus_index], delta * 0.05)
            elif game.mode == "choice": choice_preview = wrapi(choice_preview + delta, 0, 3)
            elif game.mode in ["archive", "inventory"]: select_part(delta)
            elif game.mode == "title" and key in [KEY_LEFT, KEY_RIGHT]:
                if not hits.is_empty() and hits[clampi(focus_index, 0, hits.size()-1)].action == "character":
                    select_character(1 - game.selected_character)
                else:
                    var count = 3 if game.meta.kills >= 50 else 2 if game.meta.kills >= 10 else 1
                    game.selected_weapon = wrapi(game.selected_weapon + delta, 0, count)
            else: move_focus(delta)
            game.sound.play("menu_move")
            get_viewport().set_input_as_handled()
        elif key == KEY_C and game.mode == "title":
            select_character(1 - game.selected_character)
            game.sound.play("menu_confirm")
            get_viewport().set_input_as_handled()
        elif key == KEY_ENTER:
            if game.mode == "choice": activate("choice", choice_preview)
            elif game.mode in ["inventory", "archive"]: activate("resume" if game.mode == "inventory" else "title")
            elif not hits.is_empty():
                var hit = hits[clampi(focus_index, 0, hits.size() - 1)]
                activate(hit.action, hit.value)
            get_viewport().set_input_as_handled()
        elif key == KEY_ESCAPE and game.mode in ["archive", "inventory", "audio"]:
            activate("pause" if game.mode == "audio" else "resume" if game.mode == "inventory" else "title")
            get_viewport().set_input_as_handled()

func move_focus(delta: int) -> void:
    var choices: Array[int] = []
    for i in hits.size():
        if hits[i].action != "weapon": choices.append(i)
    if choices.is_empty(): return
    focus_index = choices[wrapi(choices.find(focus_index) + delta, 0, choices.size())]

func select_part(delta: int) -> void:
    var count = game.ITEMS.size() if game.mode == "archive" else game.player.items.size()
    if count > 0: selected_item = clampi(selected_item + delta, 0, count - 1)

func activate(action: String, value: int = 0) -> void:
    game.sound.play("menu_confirm")
    match action:
        "start": game.start_run()
        "resume": game.resume_game()
        "choice": game.choose(value)
        "archive": game.mode = "archive"
        "inventory": game.mode = "inventory"
        "inspect": selected_item = value
        "title": game.show_title()
        "weapon": game.selected_weapon = value
        "character": select_character(value)
        "mute": game.sound.muted = not game.sound.muted
        "audio": game.mode = "audio"
        "pause": game.mode = "pause"
        "volume":
            var bus: String = ["Master", "Music", "Effects", "Ambience"][value]
            game.sound.adjust_volume(bus, -1.0 if game.sound.volumes[bus] >= 0.99 else 0.10)
        "camera_fx": game.camera_effects = not game.camera_effects
        "quit": game.get_tree().quit()
        "abandon": game.finish_run(false)

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
    hits.clear()
    match game.mode:
        "model_preview": return
        "title": draw_title()
        "archive": draw_parts(true)
        "choice": draw_choice()
        "pause": draw_pause()
        "audio": draw_audio()
        "inventory": draw_parts(false)
        "end": draw_end()
        _: draw_hud()

func backdrop() -> void:
    var extra = ui_offset / ui_scale
    rect(-extra, BASE + extra * 2, BLUE)
    for x in range(floori(-extra.x / 256), ceili((BASE.x + extra.x) / 256)):
        for y in range(floori(-extra.y / 256), ceili((BASE.y + extra.y) / 256)): draw_texture_rect(pattern, Rect2(x * 256, y * 256, 256, 256), false, Color(0.75, 0.85, 1, 0.62))
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
    keycap(Vector2(64, 842), "↑↓", 46)
    text_at(Vector2(124, 865), detail, 21)
    keycap(Vector2(284, 842), "ENTER", 76)
    text_at(Vector2(374, 865), confirm, 21)
    keycap(Vector2(1150, 842), "ESC", 55)
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
    button(Vector2(64, 438), Vector2(476, 62), "Start Dig", "start", 0, true)
    button(Vector2(64, 516), Vector2(476, 62), "Parts Collection", "archive")
    button(Vector2(64, 594), Vector2(476, 62), "Quit", "quit")
    window(Vector2(48, 690), Vector2(508, 156))
    text_at(Vector2(68, 723), "SELECT BUSTER", 21, WHITE, true)
    for i in 3:
        var pos = Vector2(70 + i * 157, 740)
        var available = game.meta.kills >= [0, 10, 50][i]
        var selected = game.selected_weapon == i
        window(pos, Vector2(144, 82), SELECT if selected else INK, YELLOW if selected else EDGE, false)
        icon(pos + Vector2(8, 7), ["pulse", "needle", "siege"][i] if available else "lock", 48, Color.WHITE if available else Color("8197bc"))
        text_at(pos + Vector2(60, 35), ["Pulse", "Needle", "Siege"][i], 21, WHITE if available else MUTED)
        text_at(pos + Vector2(60, 63), "Fitted" if selected else "%d kills" % [0, 10, 50][i] if not available else "Select", 18, YELLOW if selected else MUTED)
        if available: hits.append({"rect": Rect2(pos, Vector2(144, 82)), "action": "weapon", "value": i})
    text_at(Vector2(68, 881), "A fresh dig starts with base power.", 20, MUTED)
    window(Vector2(1080, 32), Vector2(312, 104), Color(0.06, 0.16, 0.40, 0.92))
    icon(Vector2(1098, 51), "record", 48)
    text_at(Vector2(1162, 65), "DIG RECORD", 21, WHITE, true)
    text_at(Vector2(1162, 101), "%d digs   /   %d clears" % [game.meta.runs, game.meta.wins], 24, YELLOW)
    window(Vector2(1020, 414), Vector2(372, 134), Color(0.06, 0.16, 0.40, 0.96))
    text_at(Vector2(1042, 448), "SELECT DIGGER", 22, WHITE, true)
    keycap(Vector2(1336, 426), "C", 34)
    for i in 2:
        var pos = Vector2(1038 + i * 172, 465)
        var selected = game.selected_character == i
        var hot = focus_index == hits.size() or Rect2(pos, Vector2(162, 64)).has_point(pointer)
        window(pos, Vector2(162, 64), SELECT if selected else INK, YELLOW if selected or hot else EDGE)
        draw_texture_rect(portraits[i], Rect2(pos + Vector2(2, 3), Vector2(52, 58)), false)
        text_at(pos + Vector2(60, 41), "Mega" if i == 0 else "Roll", 25, WHITE, true)
        if hot: cursor(pos + Vector2(-22, 20), 24)
        hits.append({"rect": Rect2(pos, Vector2(162, 64)), "action": "character", "value": i})
    window(Vector2(1020, 574), Vector2(372, 274), Color(0.06, 0.16, 0.40, 0.94))
    text_at(Vector2(1044, 613), "CONTROLS", 24, WHITE, true)
    var controls = [["WASD", "Move"], ["LMB", "Fire buster"], ["SHIFT", "Dash"], ["SPACE", "Jump"], ["E", "Salvage / use"], ["Q", "Lock on"]]
    for i in controls.size():
        var y = 636 + i * 32
        keycap(Vector2(1044, y), controls[i][0], 76)
        text_at(Vector2(1140, y + 23), controls[i][1], 23)

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
    icon(Vector2(42, 750), ["pulse", "needle", "siege"][p.weapon], 62)
    text_at(Vector2(114, 774), ["Pulse Buster", "Needle Buster", "Siege Buster"][p.weapon], 25, WHITE, true, 212)
    text_at(Vector2(114, 805), "POWER %d  /  RAPID %.1f" % [buster_power(), 1 / p.fire_delay()], 21, MUTED)
    pips(Vector2(48, 824), 270, 6, float(p.xp) / p.xp_required, 20, YELLOW)
    keycap(Vector2(30, 856), "TAB", 54)
    text_at(Vector2(99, 879), "Buster Parts", 21)
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
    keycap(Vector2(1240, 856), "ESC", 54)
    text_at(Vector2(1308, 879), "Menu", 21)
    if game.message_time > 0: draw_notice()
    if not game.nearest.is_empty() and game.mode == "play": interaction_prompt()
    if game.hurt_flash > 0: rect(Vector2.ZERO, BASE, Color(0.9, 0.2, 0.08, game.hurt_flash * 0.25))

func draw_notice() -> void:
    window(Vector2(402, 630), Vector2(636, 98), Color(0.06, 0.16, 0.39, 0.96))
    icon(Vector2(419, 647), "record", 48)
    var title: String = {"CHAMBER SECURED": "Room Cleared!", "GUARDIAN SILENCED": "Guardian Defeated!", "BUSTER CALIBRATED": "Power Increased!", "CORE EXPANDED": "Life Increased!", "CAPACITOR TUNED": "Rapid Fire Increased!", "SYSTEMS RESTORED": "Life Restored!", "INSUFFICIENT SCRAP": "Not Enough Scrap", "CACHE SEALED": "Cache Sealed", "LIFT SEALED": "Lift Sealed"}.get(game.message, game.message)
    var detail: String = game.message_detail
    if game.message.begins_with("DESCENT"): title = "Entering B%d" % game.depth
    if game.message == "CHAMBER SECURED": detail = "+5 Scrap. Part caches are now available."
    if game.message == "GUARDIAN SILENCED": detail = "The lift is ready. Salvage the area, then head for the beacon."
    text_at(Vector2(483, 664), title, 23, YELLOW, true, 533)
    paragraph(Vector2(483, 690), detail, 530, 22, WHITE, 2)

func interaction_prompt() -> void:
    var obj = game.nearest
    window(Vector2(450, 731), Vector2(540, 49), BLUE, YELLOW)
    keycap(Vector2(462, 741), "E", 33)
    var title: String = {"cache": "Open Part Cache", "spring": "Use Restoration Well", "pot": "Salvage Vessel", "lift": "Extract" if game.depth == 3 else "Take the Lift"}.get(obj.kind, obj.title)
    if obj.kind == "lift" and not game.guardian_dead: title = "Lift sealed — defeat the guardian"
    elif obj.kind == "cache" and not game.rooms[obj.room].cleared: title = "Clear the room to open this cache"
    text_at(Vector2(510, 764), title, 23, WHITE, false, 376 if obj.cost == 0 else 325)
    if obj.cost > 0:
        icon(Vector2(892, 738), "scrap", 31)
        text_at(Vector2(933, 764), str(obj.cost), 23, YELLOW, true)

func map_at(pos: Vector2, side: float) -> void:
    rect(pos, Vector2.ONE * side, Color("0c2456"))
    var low = Vector2(999, 999)
    var high = Vector2(-999, -999)
    for room in game.rooms:
        low = low.min(Vector2(room.cell))
        high = high.max(Vector2(room.cell))
    var span = high - low + Vector2.ONE
    var cell = minf((side - 24) / span.x, (side - 24) / span.y)
    var origin = pos + (Vector2.ONE * side - span * cell) * 0.5
    for i in game.rooms.size():
        var room = game.rooms[i]
        var known = room.visited
        if not known:
            for other in game.rooms:
                if other.visited and (other.cell - room.cell).length() <= 1.01: known = true
        if not known: continue
        var center = origin + (Vector2(room.cell) - low + Vector2.ONE * 0.5) * cell
        for other in game.rooms:
            if other.visited and (other.cell - room.cell).length() <= 1.01:
                var to = origin + (Vector2(other.cell) - low + Vector2.ONE * 0.5) * cell
                draw_line(center, to, Color("5077b0"), 4)
        var size = cell * 0.58
        rect(center - Vector2.ONE * size / 2 - Vector2.ONE, Vector2.ONE * (size + 2), YELLOW if i == game.exit_room else EDGE)
        rect(center - Vector2.ONE * size / 2, Vector2.ONE * size, CYAN if i == game.current_room else Color("668daf") if room.cleared else Color("224779") if room.visited else INK)
        if i == game.current_room:
            var triangle = PackedVector2Array([center + Vector2(0, -5), center + Vector2(4, 4), center + Vector2(-4, 4)])
            draw_colored_polygon(triangle, WHITE)
        elif i == game.exit_room: draw_circle(center, 2, YELLOW)

func visited_count() -> int:
    var n = 0
    for room in game.rooms:
        if room.visited: n += 1
    return n

func draw_pause() -> void:
    backdrop()
    stats_header()
    page_title("DIG MENU", "B%d / %s" % [game.depth, game.DEPTH_NAMES[game.depth - 1]])
    button(Vector2(64, 288), Vector2(400, 62), "Return to Ruins", "resume", 0, true)
    button(Vector2(64, 366), Vector2(400, 62), "Buster Parts", "inventory")
    button(Vector2(64, 444), Vector2(400, 62), "Sound Settings", "audio")
    button(Vector2(64, 522), Vector2(400, 62), "Camera Motion: " + ("On" if game.camera_effects else "Off"), "camera_fx")
    button(Vector2(64, 600), Vector2(400, 62), "End Dig & Save Record", "abandon")
    window(Vector2(508, 280), Vector2(868, 392))
    window(Vector2(536, 308), Vector2(178, 226), BLUE)
    draw_texture_rect(portrait(), Rect2(542, 319, 166, 187), false)
    text_at(Vector2(548, 556), DiverCharacter.DISPLAY_NAMES[game.player.character], 24)
    text_at(Vector2(752, 335), "EQUIPMENT", 28, WHITE, true)
    icon(Vector2(752, 358), ["pulse", "needle", "siege"][game.player.weapon], 68)
    text_at(Vector2(840, 402), ["Pulse Buster", "Needle Buster", "Siege Buster"][game.player.weapon], 30, YELLOW)
    stat_line(Vector2(752, 464), "Power", "%.1f" % buster_power(), 560)
    stat_line(Vector2(752, 509), "Fire rate", "%.1f / sec" % (1 / game.player.fire_delay()), 560)
    stat_line(Vector2(752, 554), "Run speed", "%.1f" % game.player.speed(), 560)
    stat_line(Vector2(752, 599), "Fitted parts", str(total_parts()), 560)
    window(Vector2(64, 706), Vector2(1312, 106))
    icon(Vector2(86, 725), "warning", 58)
    paragraph(Vector2(164, 744), "Watch the ground before an enemy attacks. Leave the warning area, jump over shockwaves, or dash through danger. Use cover to break a machine's aim.", 1176, 26, WHITE, 2)
    menu_footer("Select", "Return")

func draw_audio() -> void:
    backdrop()
    stats_header()
    page_title("SOUND SETTINGS", "Find your balance. Changes are saved on this PC.")
    var buses = ["Master", "Music", "Effects", "Ambience"]
    for i in buses.size():
        var bus: String = buses[i]
        button(Vector2(64, 288 + i * 78), Vector2(440, 62), "%s   %d%%" % [bus, roundi(game.sound.volumes[bus] * 100)], "volume", i)
    button(Vector2(64, 600), Vector2(440, 62), "Mute All: " + ("On" if game.sound.muted else "Off"), "mute")
    button(Vector2(64, 678), Vector2(440, 62), "Return to Dig Menu", "pause")
    window(Vector2(548, 280), Vector2(828, 460))
    icon(Vector2(580, 308), "settings", 64)
    text_at(Vector2(664, 350), "A SOUND FROM BELOW", 29, YELLOW, true)
    paragraph(Vector2(584, 402), "Music follows your descent and changes when a guardian awakens. Ruin ambience and machine sounds have their own space in the mix.", 748, 27, WHITE, 4)
    for i in buses.size():
        var y = 544 + i * 40
        text_at(Vector2(584, y + 17), buses[i], 23, MUTED)
        pips(Vector2(770, y), 560, 16, game.sound.volumes[buses[i]], 20, CYAN if i == 1 else GREEN)
    paragraph(Vector2(66, 788), "Left / right: adjust by 5%. Click or Enter: raise by 10% (wraps to Off). M: mute all.", 1260, 24, MUTED, 1)
    menu_footer("Select", "Dig Menu", "Adjust")

func stat_line(pos: Vector2, title: String, value: String, width: float) -> void:
    text_at(pos, title, 26, MUTED)
    draw_line(pos + Vector2(0, 12), pos + Vector2(width, 12), Color("416399"), 1)
    text_at(pos + Vector2(width - heading.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x, 0), value, 25, WHITE, true)

func total_parts() -> int:
    var count = 0
    for id in game.player.items: count += int(game.player.items[id])
    return count

func buster_power() -> float:
    return game.player.damage() * [1.0, 0.55, 2.4][game.player.weapon]

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
            var unlocked = not collection or game.meta.kills >= game.ITEMS[id].unlock
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
    var unlocked = not collection or game.meta.kills >= data.unlock
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
    text_at(Vector2(86, 747), "Parts stay fitted until this dig ends.", 27, MUTED)
    keycap(Vector2(64, 842), "1 2 3", 86)
    text_at(Vector2(168, 865), "Quick select", 22)
    keycap(Vector2(382, 842), "↑↓", 46)
    text_at(Vector2(443, 865), "Browse", 22)
    keycap(Vector2(1050, 842), "ENTER", 76)
    text_at(Vector2(1142, 865), "Fit selected part", 22)

func draw_end() -> void:
    backdrop()
    stats_header()
    page_title("DIG COMPLETE!" if game.outcome else "DIG ENDED", "Core recovered. You've returned to the surface." if game.outcome else "Record saved. Equipment resets when you start another dig.")
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
    var next_unlock = 10 if game.meta.kills < 10 else 25 if game.meta.kills < 25 else 50
    text_at(Vector2(948, 673), "%d to next unlock" % (next_unlock - game.meta.kills) if game.meta.kills < 50 else "All parts unlocked!", 27, YELLOW)
    button(Vector2(64, 764), Vector2(620, 62), "Start Another Dig" if game.outcome else "Try Again", "start", 0, true)
    button(Vector2(716, 764), Vector2(660, 62), "Return to Title", "title")
    icon(Vector2(64, 848), "save", 32)
    text_at(Vector2(108, 873), "Dig record saved on this computer.", 23, MUTED)

