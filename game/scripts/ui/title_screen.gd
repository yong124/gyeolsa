class_name TitleScreen
extends HBoxContainer
## 메인 메뉴: 왼쪽은 표지 그림, 오른쪽은 책상 위 "작전 서류철".
## 서류철 안에서 메뉴 ↔ 새 작전 설정이 바뀐다.

signal start_requested(config: Dictionary)   # {"defs", "difficulty", "scenario", "seed"}
signal continue_requested
signal tutorial_requested(id: String)
signal intro_requested
signal v2_requested            # v2 요원 골라 시작
signal quick_requested         # v2 바로 시작
signal continue_v2_requested
signal training_requested      # v2 훈련 작전
signal online_requested        # v2 온라인 (방 · 코드)

const DIFFICULTY := [{"name": "쉬움", "days": 1}, {"name": "보통", "days": 0}, {"name": "어려움", "days": -1}]

var _data: GameData
var _panel: VBoxContainer
var _overlay: Overlay
var _n_players := 4
var _n_humans := 1       # 핫시트: 앞에서부터 이만큼이 사람
var _faction := 0
var _diff := 1
var _info: Label
var _seg := {}          # 그룹 이름 -> [Button]
var _faction_cards: Array = []
var _op := {}            # 특수 작전 설정 화면에서 고른 작전 (빈 사전이면 일반 새 작전)


func _init(data: GameData) -> void:
	_data = data


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 0)
	Music.play("main")

	var art := TextureRect.new()
	art.texture = _street_art()
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
	art.add_child(_cover_title())

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
	_panel.custom_minimum_size = Vector2(640, 0)
	folder.add_child(_panel)
	var clip := _clip()
	folder.add_child(clip)

	_overlay = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	# HBoxContainer 안에 두면 배치가 틀어지므로 부모(메인)에 붙일 수 있게 나중에 추가
	call_deferred("_attach_overlay")
	_show_menu()


func _street_art() -> Texture2D:
	## 왼쪽 그림: 1945년 경성 거리 (오프닝 첫 장면). 그림 위아래 종이 여백은 잘라 낸다. 없으면 예전 표지
	var t := ArtV2.get_tex("cut", "opening_1")
	if t == null:
		return cover_texture()
	var a := AtlasTexture.new()
	a.atlas = t
	var k := t.get_height() / 1024.0
	a.region = Rect2(0, 140 * k, t.get_width(), 745 * k)
	return a


static func cover_texture() -> AtlasTexture:
	## 표지 그림의 태극기 쪽 (왼쪽에 박힌 「光復 IF」 글씨는 쓰지 않는다. 이름은 「결사」)
	var cover := AtlasTexture.new()
	cover.atlas = load("res://assets/ui/title.png")
	cover.region = Rect2(620, 0, 780, 1318)
	return cover


func _cover_title() -> Control:
	## 표지 위 제목: 세로로 큰 「結社」와 한 줄 (먹 글씨 · 종이 그림자)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", -18)
	box.position = Vector2(64, 70)
	for ch in ["結", "社"]:
		var l := UiKit.title(ch, 168, Color("#f3e7cf"), 900)
		l.add_theme_font_override("font", Style.serif(900))
		l.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.03, 0.85))
		l.add_theme_constant_override("shadow_offset_x", 3)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.add_theme_constant_override("shadow_outline_size", 10)
		box.add_child(l)
	var sub := UiKit.title("1945 · 경성", 26, Color("#f0c86e"), 800)
	sub.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.03, 0.9))
	sub.add_theme_constant_override("shadow_outline_size", 8)
	box.add_child(sub)
	return box


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
	## 큰 선택 하나(이어하기, 없으면 바로 시작) + 그림 카드 셋(새 작전 · 훈련 · 온라인) + 작은 글자 줄
	UiKit.clear(_panel)
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := UiKit.title(_data.text["title"], 50, Style.INK, 900)
	name_l.add_theme_font_override("font", Style.serif(900))
	tv.add_child(name_l)
	tv.add_child(UiKit.text("1945년 8월, 경성 · 네 요원의 협력 보드게임", 16, Style.INK_3, false, 600))
	head.add_child(tv)
	var st := UiKit.stamp("極 秘", 24, Style.SEAL, -9)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(st)
	_panel.add_child(head)
	_panel.add_child(UiKit.hsep())
	var saved := SaveGameV2.exists()
	var quick := func(): _confirm_new(func(): quick_requested.emit())
	if saved:
		_panel.add_child(_hero("이어하기", SaveGameV2.summary(), ArtV2.get_tex("cut", "opening_2"), func(): continue_v2_requested.emit()))
	else:
		_panel.add_child(_hero("바로 시작", "", ArtV2.get_tex("cut", "opening_2"), quick))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	if saved:
		row.add_child(_card("새 작전", "", ArtV2.get_tex("cut", "opening_3"), quick))
	else:
		row.add_child(_card("요원 골라 시작", "", ArtV2.get_tex("cut", "opening_3"), func(): _confirm_new(func(): v2_requested.emit())))
	row.add_child(_card("튜토리얼", "", ArtV2.get_tex("mission", "work"), func(): training_requested.emit(), not Prefs.v2_training_done))
	if not OS.has_feature("web") or NetClientV2.web_online_ready():   # 웹판은 wss:// 서버 주소(online.json)가 있을 때만
		row.add_child(_card("온라인", "", ArtV2.get_tex("cut", "opening_4"), func(): online_requested.emit()))
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation", 4)
	links.alignment = FlowContainer.ALIGNMENT_CENTER
	_panel.add_child(links)
	var items := []
	if saved:
		items.append(["요원 골라 시작", func(): _confirm_new(func(): v2_requested.emit())])
	items.append(["규칙 요약", func():
		var r := GameScreenV2.rules_panel(GameDataV2.load_default(), func(): _overlay.visible = false)
		_overlay.show_with(r)])
	items.append(["설정", _show_settings])
	items.append(["도입부", func(): intro_requested.emit()])
	if not OS.has_feature("web"):   # 웹판에서는 구판과 종료를 숨긴다 (창을 닫으면 끝)
		items.append(["구판 (v1)", _show_v1])
		items.append(["종료", func(): get_tree().quit()])
	for i in items.size():
		if i > 0:
			links.add_child(UiKit.text("·", 15, Style.INK_3, false))
		var it: Array = items[i]
		var b := UiKit.button(str(it[0]), func():
			Sfx.play("click")
			it[1].call(), 16, "tab")
		b.custom_minimum_size = Vector2(0, 34)
		links.add_child(b)


func _choice_style(b: Button, accent: bool) -> void:
	## 그림 카드 단추: 종이 바탕 · 먹 테두리, 올리면 인주 테두리
	var normal := Style.flat(Color("#f6eedb"), Style.SEAL if accent else Style.INK_3, 2 if accent else 1, 4, 0)
	var hover := Style.flat(Color("#fff7e4"), Style.SEAL, 3, 4, 0)
	var pressed := Style.flat(Color("#efe2c4"), Style.SEAL_DARK, 3, 4, 0)
	for k in [["normal", normal], ["hover", hover], ["pressed", pressed], ["focus", hover]]:
		b.add_theme_stylebox_override(k[0], k[1])
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2(1.02, 1.02), 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))


func _art_rect(tex: Texture2D, sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.custom_minimum_size = sz
	t.clip_contents = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _hero(title: String, sub: String, tex: Texture2D, cb: Callable) -> Button:
	## 큰 선택: 왼쪽 그림 · 오른쪽 제목과 한 줄
	var b := Button.new()
	_choice_style(b, true)
	b.custom_minimum_size = Vector2(0, 150)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 18)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_top = 6
	h.offset_bottom = -6
	h.offset_right = -14
	if tex != null:
		h.add_child(_art_rect(tex, Vector2(230, 0)))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := UiKit.title(title, 34, Style.SEAL_DARK, 900)
	t.add_theme_font_override("font", Style.serif(900))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if sub != "":   # 이어하기: 저장된 판 (며칠째 · 남은 날)
		var s := UiKit.text(sub, 15, Style.INK_2, true, 600)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(s)
	return b


func _card(title: String, sub: String, tex: Texture2D, cb: Callable, accent := false) -> Button:
	## 작은 선택: 위에 그림 · 아래 제목과 한 줄
	var b := Button.new()
	_choice_style(b, accent)
	b.custom_minimum_size = Vector2(0, 172)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 5
	v.offset_top = 5
	v.offset_right = -5
	v.offset_bottom = -8
	if tex != null:
		var a := _art_rect(tex, Vector2(0, 112))
		v.add_child(a)
	var t := UiKit.title(title, 20, Style.INK, 900)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if sub != "":
		var s := UiKit.text(sub, 13, Style.SEAL if accent else Style.INK_3, false, 700)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(s)
	return b


func offer_tutorial() -> void:
	## 처음 켠 사람에게: 첫 화면 위에 튜토리얼 창
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var panel := UiKit.paper_panel(30)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var mark := UiKit.title("結社", 52, Style.SEAL, 900)
	mark.add_theme_font_override("font", Style.serif(900))
	head.add_child(mark)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	hv.add_child(UiKit.title("처음이신가요?", 28, Style.INK, 900))
	hv.add_child(UiKit.text("튜토리얼 · 약 15분", 15, Style.INK_3, false, 700))
	box.add_child(UiKit.hsep())
	var t := UiKit.text("결사가 어떤 게임인지부터, 주사위 · 이동 · 미션 · 경찰 · 협력 · 결행까지
정해진 상황에서 하나씩 직접 해 보며 배웁니다.", 16, Style.INK_2)
	box.add_child(t)
	var go := UiKit.button("튜토리얼 시작", func():
		_overlay.visible = false
		training_requested.emit(), 22, "primary")
	go.custom_minimum_size = Vector2(0, 56)
	box.add_child(go)
	var later := UiKit.button("나중에 하기", func(): _overlay.visible = false, 13, "tab")
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(later)
	_overlay.show_with(panel)


func _confirm_new(go: Callable) -> void:
	## 저장된 판이 있으면 지워도 되는지 묻는다
	if not SaveGameV2.exists():
		go.call()
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var panel := UiKit.paper_panel(24)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("새 판을 시작할까요?", Style.FS_H3))
	box.add_child(UiKit.text("이어하던 판(%s)은 지워집니다." % SaveGameV2.summary(), 15, Style.INK_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiKit.button("새로 시작", func():
		_overlay.visible = false
		SaveGameV2.erase()
		go.call(), 16, "primary"))
	row.add_child(UiKit.button("취소", func(): _overlay.visible = false, 16, "paper"))
	_overlay.show_with(panel)


func _show_v1() -> void:
	## 구판(v1) 메뉴: 처음 만든 규칙의 모드를 기록용으로 남겨 둔다
	UiKit.clear(_panel)
	_heading("기 록 용", "구판 (v1)")
	_panel.add_child(UiKit.text("처음 만든 규칙입니다. 지금 규칙(v2)과 다릅니다.", 15, Style.INK_3))
	if SaveGame.exists():
		_menu_button("이어하기 (v1)", func(): continue_requested.emit(), SaveGame.summary(), true)
	_menu_button("새 작전 (v1)", _show_setup, "인원 · 세력 · 난이도")
	var rec := Records.data()
	var date := Records.today()
	var best_today: int = int(rec["daily"].get(date, -1))
	_menu_button("오늘의 작전", _show_daily, "%s%s" % [_date_label(date), " · 최고 광복 %d" % best_today if best_today >= 0 else " · 새 작전"])
	_menu_button("특수 작전", _show_special, "성공 %d / %d" % [rec["scenarios_won"].size(), _data.special_ops().size()])
	_menu_button("튜토리얼", _show_tutorials, "기본 훈련 · 2막 훈련" + ("" if Prefs.tutorial_done else " · 처음이라면 추천"))
	_menu_button("작전 기록", _show_records, "%d판 · 도전 과제 %d / %d" % [int(rec["games"]), rec["unlocked"].size(), _data.achievements.get("list", []).size()])
	_menu_button("규칙 도감 (v1)", _show_rulebook, "")
	var back := UiKit.button("← 메뉴로", _show_menu, 15, "tab")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(back)


func _menu_button(text: String, cb: Callable, sub: String, main := false) -> void:
	var b := UiKit.button(text, func():
		Sfx.play("click")
		cb.call(), 24 if main else 21, "tab")
	b.custom_minimum_size = Vector2(0, 46)
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
	_op = {}
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
	for n in range(2, 5):   # 2~4인 (기획서 17.1)
		opts.append([str(n) + "인", n])
	grid.add_child(_segment("players", opts, _n_players, func(v):
		_n_players = v
		if _n_humans > v:
			_n_humans = v
			_mark("humans", v)))
	grid.add_child(_row_label("사람"))
	var hopts := []
	for n in range(1, 5):
		hopts.append([str(n) + "명", n])
	grid.add_child(_segment("humans", hopts, _n_humans, func(v):
		_n_humans = mini(v, _n_players)
		if _n_humans != v:
			_mark.call_deferred("humans", _n_humans)))
	grid.add_child(_row_label("난이도"))
	var dopts := []
	for i in DIFFICULTY.size():
		dopts.append([DIFFICULTY[i]["name"], i])
	grid.add_child(_segment("diff", dopts, _diff, func(v): _diff = v))

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
	if not _op.is_empty():
		var n: int = int(_op["players"])
		var sc: Dictionary = _op.get("scenario", {})
		_info.text = "특성: %s\n능력 [%s] (하루 1회): %s\n\n나 + AI 동료 %d명 · 작전 기간 %d일 · 목표 광복수치 %d" % [
			f["ability"], a.get("name", "-"), a.get("desc", ""), n - 1, int(sc.get("rounds", _data.rounds_for(n, bool(sc.get("two_act", true))))), int(sc.get("goal", _data.goal_for(n)))]
		return
	var days: int = _data.rounds_for(_n_players) + DIFFICULTY[_diff]["days"]
	var who := "나 + AI 동료 %d명" % (_n_players - 1)
	if _n_humans > 1:
		who = "사람 %d명 (한 컴퓨터에서 돌아가며)%s" % [_n_humans, " + AI %d명" % (_n_players - _n_humans) if _n_players > _n_humans else ""]
	_info.text = "특성 (1번 요원): %s\n능력 [%s] (하루 1회): %s\n\n%s · 작전 기간 %d일 · 목표 광복수치 %d" % [
		f["ability"], a.get("name", "-"), a.get("desc", ""), who, days, _data.goal_for(_n_players)]


func _on_start() -> void:
	Sfx.play("click")
	var cfg := {
		"defs": make_players(_n_players, _faction, _n_humans),
		"difficulty": DIFFICULTY[_diff]["days"],
	}
	_launch(cfg)


func _show_tutorials() -> void:
	var d := UiKit.dossier(560, "훈련", "교 육 과 정")
	var v: VBoxContainer = d[1]
	for t in [
		["기본 훈련", "5분 · 이동, 미션, 판정, 경찰, 감옥", "tutorial"],
		["2막 훈련", "5분 · 첩보와 노출, 결행 투표, 결행", "tutorial2"],
	]:
		var id: String = t[2]
		var b := UiKit.button(t[0], func():
			_overlay.visible = false
			tutorial_requested.emit(id), 20, "tab")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 46)
		v.add_child(b)
		v.add_child(UiKit.text(t[1], 14, Style.INK_3, false))
	v.add_child(UiKit.button("닫기", func(): _overlay.visible = false, 16, "paper"))
	_overlay.show_with(d[0])


func _launch(cfg: Dictionary) -> void:
	if Prefs.tutorial_done:
		start_requested.emit(cfg)
		return
	# 처음이라면 튜토리얼을 권한다
	var d := UiKit.dossier(540, "처음이신가요?", "권 고")
	var v: VBoxContainer = d[1]
	v.add_child(UiKit.text("5분짜리 튜토리얼로 규칙을 직접 해 보며 배울 수 있습니다.", 17, Style.INK))
	v.add_child(UiKit.button("튜토리얼부터 하기", func():
		_overlay.visible = false
		tutorial_requested.emit("tutorial"), 18, "primary"))
	v.add_child(UiKit.button("바로 작전 개시", func():
		_overlay.visible = false
		Prefs.tutorial_done = true
		Prefs.save()
		start_requested.emit(cfg), 18, "paper"))
	_overlay.show_with(d[0])


func make_players(n: int, faction_index: int, humans := 1) -> Array:
	## 앞에서부터 humans 자리가 사람(한 컴퓨터에서 돌아가며 두는 핫시트), 나머지는 AI.
	## 세력은 0번 자리의 세력부터 차례로 돌아가며 배정한다.
	var keys := _data.faction_keys()
	var agents: Dictionary = _data.text.get("agents", {})
	var codenames: Array = agents.get("codenames", ["동지"])
	var personalities: Array = agents.get("order", ["bold", "support", "careful"])
	var defs := []
	for i in n:
		var f: String = keys[(faction_index + i) % keys.size()]
		var fname: String = _data.faction(f)["name"]
		if i == 0 and humans <= 1:
			defs.append({"name": "나 (%s)" % fname, "faction": f, "ai": false})
		elif i < humans:
			defs.append({"name": "%d번 요원 (%s)" % [i + 1, fname], "faction": f, "ai": false})
		else:
			defs.append({"name": "%s (%s)" % [codenames[(i - 1) % codenames.size()], fname],
				"faction": f, "ai": true, "personality": personalities[(i - 1) % personalities.size()]})
	return defs


# ------------------------------------------------------------------ 오늘의 작전 · 특수 작전 · 작전 기록

func _date_label(date: String) -> String:
	var parts := date.split("-")
	return "%d월 %d일" % [int(parts[1]), int(parts[2])] if parts.size() == 3 else date


func _heading(sub: String, t: String) -> void:
	_panel.add_child(UiKit.label(sub, Style.FS_SMALL, Style.SEAL))
	_panel.add_child(UiKit.title(t, 40, Style.INK, 900))


func _show_daily() -> void:
	## 날짜로 시드를 정한 작전. 같은 날에는 누구나 같은 타일·카드 순서를 만난다. 세력도 날짜로 정해진다.
	UiKit.clear(_panel)
	_op = {}
	var date := Records.today()
	var seed_value := Records.daily_seed(date)
	var keys := _data.faction_keys()
	var fidx := seed_value % keys.size()
	var info: Dictionary = _data.scenarios.get("daily", {})
	var n: int = int(info.get("players", 4))
	_heading("오 늘 의 작 전 · " + _date_label(date), info.get("name", "오늘의 작전"))
	_panel.add_child(UiKit.text(info.get("brief", ""), 15, Style.INK_2))
	_panel.add_child(UiKit.hsep())
	var f := _data.faction(keys[fidx])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.add_child(UiKit.icon(load(f["emblem"]), Vector2(72, 72)))
	var v := VBoxContainer.new()
	v.add_child(UiKit.title("오늘의 세력: " + f["name"], 20, Style.INK, 800))
	v.add_child(UiKit.text("%d인 작전 · 작전 기간 %d일 · 목표 광복수치 %d" % [n, _data.rounds_for(n), _data.goal_for(n)], 14, Style.INK_2))
	var best: int = int(Records.data()["daily"].get(date, -1))
	v.add_child(UiKit.text("오늘 최고 기록: " + ("광복 %d" % best if best >= 0 else "아직 없음"), 14, Style.SEAL_DARK, true, 700))
	h.add_child(v)
	_panel.add_child(h)
	var start := UiKit.button("작전 개시", func():
		Sfx.play("click")
		_launch({"defs": make_players(n, fidx), "difficulty": 0,
			"scenario": "daily", "date": date, "seed": seed_value}), 24, "primary")
	start.custom_minimum_size = Vector2(0, 58)
	_panel.add_child(start)
	var back := UiKit.button("← 메뉴로", _show_menu, 15, "tab")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(back)


func _show_special() -> void:
	UiKit.clear(_panel)
	_op = {}
	_heading("특 수 작 전", "특수 작전")
	_panel.add_child(UiKit.text("조건이 다른 작전입니다. 모두 성공하면 도전 과제를 얻습니다.", 14, Style.INK_2))
	_panel.add_child(UiKit.hsep())
	var won: Dictionary = Records.data()["scenarios_won"]
	for op in _data.special_ops():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var b := UiKit.button(op["name"], func():
			Sfx.play("click")
			_show_op(op), 21, "tab")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = op["brief"]
		var sub := UiKit.text("%d인" % int(op["players"]), 13, Style.INK_3, false)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sub)
		sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		sub.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		sub.position.x -= 12
		row.add_child(b)
		if won.has(op["id"]):
			var st := UiKit.stamp("성 공", 13, Style.SEAL, -8)
			st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(st)
		_panel.add_child(row)
		var brief := UiKit.text(op["brief"], 13, Style.INK_2)
		brief.custom_minimum_size = Vector2(580, 0)
		_panel.add_child(brief)
	var back := UiKit.button("← 메뉴로", _show_menu, 15, "tab")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(back)


func _show_op(op: Dictionary) -> void:
	UiKit.clear(_panel)
	_op = op
	_heading("특 수 작 전", op["name"])
	var brief := UiKit.text(op["brief"], 15, Style.INK_2)
	brief.custom_minimum_size = Vector2(600, 0)
	_panel.add_child(brief)
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
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Style.flat(Color(Style.INK, 0.06), Color(Style.INK, 0.15), 1, 2, 12))
	_info = UiKit.text("", 14, Style.INK)
	_info.custom_minimum_size = Vector2(560, 0)
	box.add_child(_info)
	_panel.add_child(box)
	_update_info()
	var start := UiKit.button("작전 개시", func():
		Sfx.play("click")
		_launch({"defs": make_players(int(op["players"]), _faction), "difficulty": 0, "scenario": op["id"]}), 24, "primary")
	start.custom_minimum_size = Vector2(0, 58)
	_panel.add_child(start)
	var back := UiKit.button("← 특수 작전 목록", _show_special, 15, "tab")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(back)


func _show_records() -> void:
	UiKit.clear(_panel)
	_op = {}
	var rec := Records.data()
	_heading("작 전 기 록", "작전 기록")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	var ends: Dictionary = rec["endings"]
	for pair in [["참가", "%d판" % int(rec["games"])], ["대성공", "%d번" % int(ends.get("victory", 0))],
			["최단 성공", "%d일 남기고" % int(rec["best_days_left"]) if int(rec["best_days_left"]) >= 0 else "-"],
			["최고 기여", "광복 %d" % int(rec["best_score"])]]:
		grid.add_child(UiKit.text(pair[0], 13, Style.INK_3, false, 700))
		grid.add_child(UiKit.title(pair[1], 17, Style.INK, 800))
	_panel.add_child(grid)
	var fg := GridContainer.new()
	fg.columns = 3
	fg.add_theme_constant_override("h_separation", 22)
	for k in _data.faction_keys():
		var fs: Dictionary = rec["factions"].get(k, {"games": 0, "wins": 0})
		var g: int = int(fs["games"])
		fg.add_child(UiKit.text("%s  %d판 %d승%s" % [_data.faction(k)["name"], g, int(fs["wins"]),
			" (%d%%)" % roundi(100.0 * int(fs["wins"]) / g) if g > 0 else ""], 13, Style.INK_2, false, 600))
	_panel.add_child(fg)
	_panel.add_child(UiKit.hsep())
	var list: Array = _data.achievements.get("list", [])
	_panel.add_child(UiKit.title("도전 과제  %d / %d" % [rec["unlocked"].size(), list.size()], 19, Style.SEAL_DARK))
	var ag := GridContainer.new()
	ag.columns = 2
	ag.add_theme_constant_override("h_separation", 14)
	ag.add_theme_constant_override("v_separation", 6)
	for a in list:
		var got: bool = rec["unlocked"].has(a["id"])
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(292, 0)
		cell.add_theme_stylebox_override("panel", Style.flat(Color("#fff8e1", 0.7) if got else Color(Style.INK, 0.05),
			Style.SEAL if got else Color(Style.INK, 0.15), 2 if got else 1, 2, 7))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 0)
		cv.add_child(UiKit.title(("● " if got else "○ ") + a["name"], 14, Style.SEAL_DARK if got else Style.INK_3, 800))
		cv.add_child(UiKit.text(a["desc"], 11, Style.INK_2 if got else Style.INK_3))
		cell.add_child(cv)
		if got:
			cell.tooltip_text = "달성: %s" % rec["unlocked"][a["id"]]
		ag.add_child(cell)
	_panel.add_child(ag)
	var back := UiKit.button("← 메뉴로", _show_menu, 15, "tab")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(back)
