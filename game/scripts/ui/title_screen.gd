class_name TitleScreen
extends HBoxContainer
## 메인 메뉴: 왼쪽은 표지 그림, 오른쪽은 책상 위 "작전 서류철".
## 서류철 안에서 메뉴 ↔ 새 작전 설정이 바뀐다.

signal start_requested(config: Dictionary)   # {"defs", "stations", "difficulty"}
signal continue_requested
signal tutorial_requested
signal intro_requested

const DIFFICULTY := [{"name": "쉬움", "days": 1}, {"name": "보통", "days": 0}, {"name": "어려움", "days": -1}]

var _data: GameData
var _panel: VBoxContainer
var _overlay: Overlay
var _n_players := 4
var _faction := 0
var _diff := 1
var _chk_stations: CheckBox
var _info: Label
var _seg := {}          # 그룹 이름 -> [Button]
var _faction_cards: Array = []


func _init(data: GameData) -> void:
	_data = data


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 0)
	Music.play("main")

	var art := TextureRect.new()
	art.texture = load("res://assets/ui/title.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size = Vector2(820, 0)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.size_flags_stretch_ratio = 1.1
	add_child(art)
	var shade := TextureRect.new()   # 그림과 책상 사이를 부드럽게
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 8
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	art.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	shade.offset_left = -80

	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	desk.custom_minimum_size = Vector2(740, 0)
	desk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(desk)
	var center := CenterContainer.new()
	desk.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var folder := PanelContainer.new()
	folder.add_theme_stylebox_override("panel", Style.paper(34))
	folder.rotation_degrees = -0.6
	center.add_child(folder)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)
	_panel.custom_minimum_size = Vector2(600, 0)
	folder.add_child(_panel)
	var clip := _clip()
	folder.add_child(clip)

	_overlay = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	# HBoxContainer 안에 두면 배치가 틀어지므로 부모(메인)에 붙일 수 있게 나중에 추가
	call_deferred("_attach_overlay")
	_show_menu()


func _clip() -> Control:
	## 서류를 잡고 있는 클립 (그림)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_SHRINK_END
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	c.custom_minimum_size = Vector2(40, 10)
	c.draw.connect(func():
		# 철사 한 가닥이 두 번 접힌 클립
		var col := Color("#9a968f")
		var hi := Color("#d8d4cc")
		for pass_i in 2:
			var cc := col if pass_i == 0 else hi
			var w := 3.2 if pass_i == 0 else 1.0
			var o := Vector2(0, 0) if pass_i == 0 else Vector2(-0.8, -0.8)
			c.draw_line(Vector2(10, -40) + o, Vector2(10, 4) + o, cc, w, true)
			c.draw_arc(Vector2(18, 4) + o, 8, 0, PI, 16, cc, w, true)
			c.draw_line(Vector2(26, 4) + o, Vector2(26, -46) + o, cc, w, true)
			c.draw_arc(Vector2(20, -46) + o, 6, PI, TAU, 16, cc, w, true)
			c.draw_line(Vector2(14, -46) + o, Vector2(14, -6) + o, cc, w, true))
	return c


func _attach_overlay() -> void:
	get_parent().add_child(_overlay)


func _exit_tree() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()


# ------------------------------------------------------------------ 메뉴

func _show_menu() -> void:
	UiKit.clear(_panel)
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UiKit.title(_data.text["title"], 54, Style.INK, 900))
	tv.add_child(UiKit.text("1945, 우리 손으로 되찾는 광복", 16, Style.INK_3, false, 600))
	head.add_child(tv)
	var st := UiKit.stamp("極 秘", 24, Style.SEAL, -9)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(st)
	_panel.add_child(head)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	_panel.add_child(sp)
	if SaveGame.exists():
		_menu_button("이어하기", func(): continue_requested.emit(), SaveGame.summary(), true)
	_menu_button("새 작전", _show_setup, "인원 · 세력 · 난이도", not SaveGame.exists())
	_menu_button("튜토리얼", func(): tutorial_requested.emit(), "5분" + ("" if Prefs.tutorial_done else " · 처음이라면 추천"))
	_menu_button("규칙 도감", _show_rulebook, "")
	_menu_button("설정", _show_settings, "")
	_menu_button("도입부 다시 보기", func(): intro_requested.emit(), "")
	_menu_button("종료", func(): get_tree().quit(), "")


func _menu_button(text: String, cb: Callable, sub: String, main := false) -> void:
	var b := UiKit.button(text, func():
		Sfx.play("click")
		cb.call(), 24 if main else 21, "tab")
	b.custom_minimum_size = Vector2(0, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if main:
		b.add_theme_color_override("font_color", Style.SEAL_DARK)
	_panel.add_child(b)
	if sub != "":
		var l := UiKit.text(sub, 13, Style.INK_3, false)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.position.x -= 12


func _show_settings() -> void:
	var s := SettingsPanel.new()
	s.closed.connect(func(): _overlay.visible = false)
	_overlay.show_with(s)


func _show_rulebook() -> void:
	var r := Rulebook.new(_data)
	r.closed.connect(func(): _overlay.visible = false)
	_overlay.show_with(r)


# ------------------------------------------------------------------ 새 작전 설정

func _show_setup() -> void:
	UiKit.clear(_panel)
	_seg.clear()
	_panel.add_child(UiKit.label("작 전 명 령 서", Style.FS_SMALL, Style.SEAL))
	_panel.add_child(UiKit.title("새 작전", 40, Style.INK, 900))
	var syn := UiKit.text(_data.text["synopsis"].split("\n\n")[0], 14, Style.INK_2)
	syn.custom_minimum_size = Vector2(600, 0)
	_panel.add_child(syn)
	_panel.add_child(UiKit.hsep())

	_panel.add_child(_row_label("내 세력"))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 10)
	_panel.add_child(fr)
	_faction_cards.clear()
	var keys := _data.faction_keys()
	for i in keys.size():
		var card := _faction_card(i, keys[i])
		fr.add_child(card)
		_faction_cards.append(card)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	_panel.add_child(grid)
	grid.add_child(_row_label("인원"))
	var opts := []
	for n in range(2, 7):
		opts.append([str(n) + "인", n])
	grid.add_child(_segment("players", opts, _n_players, func(v): _n_players = v))
	grid.add_child(_row_label("난이도"))
	var dopts := []
	for i in DIFFICULTY.size():
		dopts.append([DIFFICULTY[i]["name"], i])
	grid.add_child(_segment("diff", dopts, _diff, func(v): _diff = v))
	grid.add_child(_row_label("전차 역"))
	_chk_stations = CheckBox.new()
	_chk_stations.text = "사용 (보드 가장자리 4곳)"
	_chk_stations.button_pressed = true
	_chk_stations.focus_mode = Control.FOCUS_NONE
	grid.add_child(_chk_stations)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Style.flat(Color(Style.INK, 0.06), Color(Style.INK, 0.15), 1, 2, 12))
	_info = UiKit.text("", 14, Style.INK)
	_info.custom_minimum_size = Vector2(560, 0)
	box.add_child(_info)
	_panel.add_child(box)
	_update_info()

	var start := UiKit.button("작전 개시", _on_start, 24, "primary")
	start.custom_minimum_size = Vector2(0, 58)
	_panel.add_child(start)
	var back := UiKit.button("← 메뉴로", _show_menu, 15, "tab")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(back)


func _row_label(t: String) -> Label:
	var l := UiKit.title(t, 17, Style.INK_2, 700)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _segment(group: String, opts: Array, current: int, on_pick: Callable) -> HBoxContainer:
	## 여러 값 중 하나를 고르는 버튼 줄
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var buttons := []
	for o in opts:
		var val: int = o[1]
		var b := UiKit.button(o[0], func():
			Sfx.play("click")
			on_pick.call(val)
			_mark(group, val)
			_update_info(), 16, "paper")
		b.custom_minimum_size = Vector2(64, 38)
		b.set_meta("val", val)
		h.add_child(b)
		buttons.append(b)
	_seg[group] = buttons
	_mark(group, current)
	return h


func _mark(group: String, val: int) -> void:
	for b in _seg[group]:
		var on: bool = b.get_meta("val") == val
		if on:
			Style.style_button(b, "primary")
			b.add_theme_font_override("font", Style.sans(800))
		else:
			Style.style_button(b, "paper")


func _faction_card(i: int, key: String) -> PanelContainer:
	var f := _data.faction(key)
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var ic := UiKit.icon(load(f["emblem"]), Vector2(0, 56))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var n := UiKit.title(f["name"], 17, Style.INK, 800)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var a := UiKit.text(f.get("active", {}).get("name", ""), 12, Style.INK_3, false, 700)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	p.tooltip_text = "%s\n\n특성: %s\n능력 [%s]: %s" % [f["desc"], f["ability"], f.get("active", {}).get("name", "-"), f.get("active", {}).get("desc", "")]
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click")
			_faction = i
			_update_info())
	return p


func _update_info() -> void:
	for i in _faction_cards.size():
		var on := i == _faction
		var s := Style.flat(Color("#fff8e1", 0.9) if on else Color(1, 1, 1, 0.25), Style.SEAL if on else Color(Style.INK, 0.2), 3 if on else 1, 3, 10)
		_faction_cards[i].add_theme_stylebox_override("panel", s)
	var f := _data.faction(_data.faction_keys()[_faction])
	var a: Dictionary = f.get("active", {})
	var days: int = _data.rounds_for(_n_players) + DIFFICULTY[_diff]["days"]
	_info.text = "특성: %s\n능력 [%s] (하루 1회): %s\n\n나 + AI 동료 %d명 · 작전 기간 %d일 · 목표 광복수치 %d" % [
		f["ability"], a.get("name", "-"), a.get("desc", ""), _n_players - 1, days, _data.goal_for(_n_players)]


func _on_start() -> void:
	Sfx.play("click")
	var cfg := {
		"defs": make_players(_n_players, _faction),
		"stations": _chk_stations.button_pressed,
		"difficulty": DIFFICULTY[_diff]["days"],
	}
	if Prefs.tutorial_done:
		start_requested.emit(cfg)
		return
	# 처음이라면 튜토리얼을 권한다
	var d := UiKit.dossier(540, "처음이신가요?", "권 고")
	var v: VBoxContainer = d[1]
	v.add_child(UiKit.text("5분짜리 튜토리얼로 규칙을 직접 해 보며 배울 수 있습니다.", 17, Style.INK))
	v.add_child(UiKit.button("튜토리얼부터 하기", func():
		_overlay.visible = false
		tutorial_requested.emit(), 18, "primary"))
	v.add_child(UiKit.button("바로 작전 개시", func():
		_overlay.visible = false
		Prefs.tutorial_done = true
		Prefs.save()
		start_requested.emit(cfg), 18, "paper"))
	_overlay.show_with(d[0])


func make_players(n: int, faction_index: int) -> Array:
	## 0번 자리가 나, 나머지는 AI. 세력은 내 세력부터 차례로 돌아가며 배정한다.
	var keys := _data.faction_keys()
	var defs := []
	for i in n:
		var f: String = keys[(faction_index + i) % keys.size()]
		var fname: String = _data.faction(f)["name"]
		if i == 0:
			defs.append({"name": "나 (%s)" % fname, "faction": f, "ai": false})
		else:
			defs.append({"name": "동지 %d (%s)" % [i, fname], "faction": f, "ai": true})
	return defs
