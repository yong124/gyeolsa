class_name UiKit
extends RefCounted
## 공용 위젯 헬퍼. 색·글꼴·재질은 Style에서 가져온다.

# 어두운 바탕(엔딩·도입부·오버레이 밖)용 색 — 예전 이름을 유지한다
const COL_TEXT := Style.ON_DARK
const COL_DIM := Style.ON_DARK_DIM
const COL_TITLE := Style.ON_DARK_TITLE
const COL_ACCENT := Style.ON_DARK_ACCENT
const COL_GOOD := Style.GOOD_ON_DARK
const COL_BAD := Style.BAD_ON_DARK
const COL_WARN := Color("#f0b27a")
const COL_BG := Style.DESK


static func seat_color(id: int) -> Color:
	return Style.seat(id)


static func label(t: String, fs: int, col: Color = COL_TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(t: String, fs: int, col: Color = Style.INK, weight := 800) -> Label:
	## 명조 제목
	var l := label(t, fs, col)
	l.add_theme_font_override("font", Style.serif(weight))
	return l


static func text(t: String, fs: int, col: Color = Style.INK_2, wrap := true, weight := 500) -> Label:
	## 종이 위 본문 (먹색)
	var l := label(t, fs, col, wrap)
	if weight != 500:
		l.add_theme_font_override("font", Style.sans(weight))
	return l


static func button(t: String, cb: Callable, fs := 17, kind := "dark") -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE  # 스페이스·엔터가 포커스된 버튼을 누르지 않게 (단축키는 화면이 직접 처리)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Style.style_button(b, kind)
	b.pressed.connect(cb)
	return b


static func margin(m: int) -> MarginContainer:
	var c := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		c.add_theme_constant_override("margin_" + side, m)
	return c


static func paper_panel(pad := 22.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.paper(pad))
	return p


static func dossier(width: float, heading: String, sub := "", pad := 28.0) -> Array:
	## 종이 서류 창: [PanelContainer, 내용을 넣을 VBoxContainer]
	var p := paper_panel(pad)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, 0)
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	if sub != "":
		v.add_child(label(sub, Style.FS_SMALL, Style.SEAL))
	if heading != "":
		v.add_child(title(heading, Style.FS_H2))
	return [p, v]


static func panel_style(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	return Style.flat(bg, border, bw, 4, 14)


static func panel(bg: Color, border: Color, bw := 2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border, bw))
	return p


static func icon(tex: Texture2D, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	return t


static func ui_icon(name: String) -> Texture2D:
	return load("res://assets/ui/icons/%s.svg" % name)


static func stamp(t: String, fs := 16, col: Color = Style.SEAL, angle := -8.0) -> Control:
	## 붉은 도장 (이중 테두리, 살짝 기울임)
	var holder := Control.new()
	var p := PanelContainer.new()
	var s := Style.flat(Color(col, 0.06), col, 2, 2, 3)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.expand_margin_left = 3
	s.expand_margin_right = 3
	s.expand_margin_top = 3
	s.expand_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	var l := label(t, fs, col)
	l.add_theme_font_override("font", Style.serif(900))
	p.add_child(l)
	holder.add_child(p)
	p.modulate.a = 0.9
	holder.set_meta("inner", p)
	p.resized.connect(func():
		holder.custom_minimum_size = p.size
		p.pivot_offset = p.size / 2.0)
	p.rotation_degrees = angle
	return holder


static func hsep() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(Style.INK, 0.22)
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	return s


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
