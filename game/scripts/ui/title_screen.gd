class_name TitleScreen
extends HBoxContainer
## 메인 메뉴: 왼쪽은 표지 그림, 오른쪽은 책상 위 "작전 서류철".
## 서류철 안에서 메뉴 ↔ 새 작전 설정이 바뀐다.

signal intro_requested
signal v2_requested            # v2 요원 골라 시작
signal quick_requested         # v2 바로 시작
signal continue_v2_requested
signal training_requested(index: int)   # v2 튜토리얼 훈련 (0부터)
signal online_requested        # v2 온라인 (방 · 코드)

var _panel: VBoxContainer
var _overlay: Overlay


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
	var name_l := UiKit.title("결 사", 50, Style.INK, 900)
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
	row.add_child(_card("튜토리얼", "", ArtV2.get_tex("mission", "work"), func(): _show_trainings(), not Prefs.v2_training_done))
	if not OS.has_feature("web") or NetClientV2.web_online_ready():   # 웹판은 wss:// 서버 주소(online.json)가 있을 때만
		row.add_child(_card("온라인", "", ArtV2.get_tex("cut", "opening_4"), func(): online_requested.emit()))
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation", 4)
	links.alignment = FlowContainer.ALIGNMENT_CENTER
	_panel.add_child(links)
	var items := []
	if saved:
		items.append(["요원 골라 시작", func(): _confirm_new(func(): v2_requested.emit())])
	items.append(["도움말", func():
		var r := GameScreenV2.rules_panel(GameDataV2.load_default(), func(): _overlay.visible = false)
		_overlay.show_with(r)])
	items.append(["설정", _show_settings])
	items.append(["도입부", func(): intro_requested.emit()])
	if not OS.has_feature("web"):   # 웹판에서는 종료를 숨긴다 (창을 닫으면 끝)
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
	hv.add_child(UiKit.title("처음이라면 훈련부터", 28, Style.INK, 900))
	hv.add_child(UiKit.text("짧은 훈련 4개 · 하나에 2~3분", 15, Style.INK_3, false, 700))
	box.add_child(UiKit.hsep())
	var t := UiKit.text("먼저 해 보고, 한 줄로 알려 드립니다.
훈련 1만 해 봐도 바로 실전을 할 수 있습니다.", 16, Style.INK_2)
	box.add_child(t)
	var go := UiKit.button("훈련 1 시작", func():
		_overlay.visible = false
		training_requested.emit(0), 22, "primary")
	go.custom_minimum_size = Vector2(0, 56)
	box.add_child(go)
	var later := UiKit.button("나중에 하기", func(): _overlay.visible = false, 13, "tab")
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(later)
	_overlay.show_with(panel)


func _show_trainings() -> void:
	## 튜토리얼 카드: 훈련 4개 (마친 것은 ✓). 하나 골라 새 판에서 시작한다
	var data := GameDataV2.load_default()
	var list: Array = data.tutorial.get("trainings", [])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var panel := UiKit.paper_panel(26)
	panel.custom_minimum_size = Vector2(900, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("튜토리얼", Style.FS_H3))
	box.add_child(UiKit.text("훈련 하나는 2~3분입니다. 훈련 1만 하고 바로 실전으로 가도 됩니다.", 15, Style.INK_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var art := ["work", "assassin", "coop", "infiltrate"]
	for i in list.size():
		var tr: Dictionary = list[i]
		var done: bool = Prefs.v2_trainings.has(str(tr.get("id", "")))
		var idx := i
		var title := "%s훈련 %d · %s" % ["✓ " if done else "", i + 1, tr.get("title", "")]
		row.add_child(_card(title, str(tr.get("goal", "")), ArtV2.get_tex("mission", art[i % art.size()]), func():
			_overlay.visible = false
			training_requested.emit(idx), not done and (i == 0 or Prefs.v2_trainings.has(str(list[i - 1].get("id", ""))))))
	box.add_child(UiKit.button("닫기", func(): _overlay.visible = false, 16, "paper"))
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


func _show_settings() -> void:
	var s := SettingsPanel.new()
	s.closed.connect(func(): _overlay.visible = false)
	_overlay.show_with(s)
