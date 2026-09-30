class_name Style
extends RefCounted
## 디자인 체계 "1945 경성 기밀 작전 문서": 색, 글꼴, 재질(StyleBox), 테마를 한곳에서 만든다.
## 화면 코드는 색·크기를 직접 적지 않고 여기 값을 쓴다. 톤을 바꾸려면 이 파일만 고치면 된다.

# ---------------------------------------------------------------- 색
const PAPER := Color("#eadfc4")
const PAPER_HI := Color("#f4ecd8")
const PAPER_LO := Color("#d8c7a2")
const INK := Color("#221c16")
const INK_2 := Color("#4a3f33")
const INK_3 := Color("#7d6d58")
const SEAL := Color("#b3261e")        # 인주 빨강 (강조·도장·위험)
const SEAL_DARK := Color("#5e0f0b")
const GOLD := Color("#c59b4d")        # 바랜 금 (선택·경로)
const GOLD_HI := Color("#f0c86e")
const DESK := Color("#1a1511")
const ON_DARK := Color("#e8dcc6")     # 어두운 바탕 위 본문
const ON_DARK_DIM := Color("#a8997f")
const ON_DARK_TITLE := Color("#f3e3c3")
const ON_DARK_ACCENT := Color("#f0d59a")
const GOOD := Color("#3f7a4a")
const GOOD_ON_DARK := Color("#9fd89f")
const BAD_ON_DARK := Color("#ff8a80")
const WARN := Color("#b86a1e")
const MISSION := Color("#5e8a36")
const ITEM := Color("#36588f")
const EVENT := Color("#a8443a")
const SEATS := [Color("#a83a2c"), Color("#2f5a8a"), Color("#3f7a4a"), Color("#b8892b"), Color("#6b4f8a"), Color("#2f7f7a")]

# ---------------------------------------------------------------- 글자 크기
const FS_SMALL := 13
const FS_BODY := 16
const FS_LEAD := 19
const FS_H3 := 22
const FS_H2 := 30
const FS_H1 := 44

static var _fonts := {}
static var _tex := {}
static var _theme: Theme


static func seat(id: int) -> Color:
	return SEATS[id % SEATS.size()]


# ---------------------------------------------------------------- 글꼴

static func sans(weight := 500) -> Font:
	return _font("res://assets/fonts/NotoSansKR-VF.ttf", weight)


static func serif(weight := 700) -> Font:
	return _font("res://assets/fonts/NotoSerifKR-VF.ttf", weight)


static func _font(path: String, weight: int) -> Font:
	var key := "%s@%d" % [path, weight]
	if not _fonts.has(key):
		var base: FontFile = load(path)
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = fv
	return _fonts[key]


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/ui/%s.png" % name)
	return _tex[name]


# ---------------------------------------------------------------- 재질

static func paper(pad := 16.0) -> StyleBoxTexture:
	## 그림자가 있는 바랜 종이 패널
	var s := StyleBoxTexture.new()
	s.texture = tex("paper_panel")
	s.set_texture_margin_all(38)
	s.set_expand_margin_all(16)
	s.expand_margin_bottom = 20
	s.set_content_margin_all(pad)
	return s


static func card_paper(pad := 0.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex("paper_card")
	s.set_texture_margin_all(20)
	s.set_expand_margin_all(8)
	s.expand_margin_bottom = 10
	s.set_content_margin_all(pad)
	return s


static func flat(bg: Color, border := Color.TRANSPARENT, bw := 0, radius := 3, pad := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func ink(pad := 12.0) -> StyleBoxFlat:
	## 먹색 패널 (툴팁, 강조 띠)
	var s := flat(Color(INK, 0.96), Color("#5a4c38"), 1, 3, pad)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	return s


static func row(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	## 종이 위의 한 줄 칸 (요원 명부 등)
	var s := flat(bg, border, bw, 2, 8)
	return s


# ---------------------------------------------------------------- 버튼

static func _btn(bg: Color, border: Color, bw: int, shadow: Color, drop := 4, radius := 3) -> StyleBoxFlat:
	var s := flat(bg, border, bw, radius, 8)
	s.content_margin_left = 16
	s.content_margin_right = 16
	if drop > 0:
		s.shadow_color = shadow
		s.shadow_size = 0
		s.shadow_offset = Vector2(0, drop)
	return s


static func style_button(b: Button, kind := "paper") -> void:
	## 버튼 종류: primary(붉은 주 행동) / paper(종이 위 보조) / dark(어두운 바탕 위) / tab(메뉴 항목)
	match kind:
		"primary":
			b.add_theme_stylebox_override("normal", _btn(Color("#b0302a"), SEAL_DARK, 2, SEAL_DARK, 5))
			b.add_theme_stylebox_override("hover", _btn(Color("#c63b33"), SEAL_DARK, 2, SEAL_DARK, 5))
			var pr := _btn(Color("#9b231d"), SEAL_DARK, 2, SEAL_DARK, 1)
			pr.content_margin_top = 12
			b.add_theme_stylebox_override("pressed", pr)
			b.add_theme_stylebox_override("disabled", _btn(Color("#8c7b68", 0.55), Color("#6e5f4c"), 2, Color(0, 0, 0, 0.15), 2))
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, Color("#fff5e6"))
			b.add_theme_color_override("font_disabled_color", Color("#f4ecd8", 0.7))
			b.add_theme_font_override("font", serif(800))
		"paper":
			b.add_theme_stylebox_override("normal", _btn(Color(1, 1, 1, 0.32), INK_2, 1, Color(0.24, 0.18, 0.12, 0.45), 3))
			b.add_theme_stylebox_override("hover", _btn(Color("#fff7e2"), GOLD, 2, Color("#7a5a1e"), 3))
			b.add_theme_stylebox_override("pressed", _btn(Color("#efe2c2"), GOLD, 2, Color("#7a5a1e"), 1))
			b.add_theme_stylebox_override("disabled", _btn(Color(1, 1, 1, 0.12), Color(INK_2, 0.35), 1, Color.TRANSPARENT, 0))
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, INK)
			b.add_theme_color_override("font_disabled_color", Color(INK, 0.38))
			b.add_theme_font_override("font", sans(700))
		"dark":
			b.add_theme_stylebox_override("normal", _btn(Color(0, 0, 0, 0.35), Color("#6b5a42"), 1, Color(0, 0, 0, 0.4), 3))
			b.add_theme_stylebox_override("hover", _btn(Color(0.2, 0.15, 0.1, 0.7), GOLD, 2, Color(0, 0, 0, 0.4), 3))
			b.add_theme_stylebox_override("pressed", _btn(Color(0.15, 0.1, 0.07, 0.8), GOLD, 2, Color(0, 0, 0, 0.4), 1))
			b.add_theme_stylebox_override("disabled", _btn(Color(0, 0, 0, 0.2), Color("#4a3f33"), 1, Color.TRANSPARENT, 0))
			for k in ["font_color", "font_focus_color"]:
				b.add_theme_color_override(k, ON_DARK)
			b.add_theme_color_override("font_hover_color", ON_DARK_ACCENT)
			b.add_theme_color_override("font_pressed_color", ON_DARK_ACCENT)
			b.add_theme_color_override("font_disabled_color", Color(ON_DARK, 0.35))
			b.add_theme_font_override("font", sans(700))
		"tab":
			var n := flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 6)
			n.content_margin_left = 14
			n.border_width_bottom = 1
			n.border_color = Color(INK, 0.22)
			var h := flat(Color(SEAL, 0.12), SEAL, 0, 0, 6)
			h.content_margin_left = 14
			h.border_width_left = 5
			b.add_theme_stylebox_override("normal", n)
			b.add_theme_stylebox_override("hover", h)
			b.add_theme_stylebox_override("pressed", h)
			b.add_theme_stylebox_override("disabled", n)
			for k in ["font_color", "font_focus_color"]:
				b.add_theme_color_override(k, INK)
			b.add_theme_color_override("font_hover_color", SEAL_DARK)
			b.add_theme_color_override("font_pressed_color", SEAL_DARK)
			b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))
			b.add_theme_font_override("font", serif(700))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# ---------------------------------------------------------------- 테마 (창 전체 기본값)

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = sans(500)
	t.default_font_size = FS_BODY
	# 툴팁: 먹색 띠
	t.set_stylebox("panel", "TooltipPanel", ink(10))
	t.set_color("font_color", "TooltipLabel", PAPER)
	t.set_font_size("font_size", "TooltipLabel", 14)
	# 기본 버튼은 어두운 바탕용
	var tmp := Button.new()
	style_button(tmp, "dark")
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(k, "Button", tmp.get_theme_stylebox(k))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		t.set_color(k, "Button", tmp.get_theme_color(k))
	tmp.free()
	t.set_color("font_color", "Label", ON_DARK)
	# 선택 상자·체크·슬라이더 (종이 위에서 쓴다)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := flat(Color(1, 1, 1, 0.45) if k != "hover" else Color("#fff7e2"), GOLD if k == "hover" else INK_2, 1, 3, 8)
		t.set_stylebox(k, "OptionButton", s)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "OptionButton", INK)
		t.set_color(k, "CheckBox", INK)
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(k, "CheckBox", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 4))
	t.set_color("font_hover_color", "CheckBox", SEAL_DARK)
	t.set_color("font_hover_pressed_color", "CheckBox", SEAL_DARK)
	t.set_stylebox("panel", "PopupMenu", flat(PAPER_HI, INK_2, 1, 2, 6))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", SEAL_DARK)
	t.set_stylebox("hover", "PopupMenu", flat(Color(SEAL, 0.14), Color.TRANSPARENT, 0, 0, 4))
	t.set_stylebox("slider", "HSlider", flat(Color(INK, 0.25), Color.TRANSPARENT, 0, 3, 3))
	t.set_stylebox("grabber_area", "HSlider", flat(SEAL, Color.TRANSPARENT, 0, 3, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(SEAL, Color.TRANSPARENT, 0, 3, 3))
	# 탭 (규칙 도감)
	t.set_stylebox("panel", "TabContainer", flat(Color(1, 1, 1, 0.25), Color(INK, 0.25), 1, 2, 4))
	t.set_stylebox("tab_selected", "TabContainer", flat(PAPER_HI, INK_2, 1, 2, 8))
	t.set_stylebox("tab_unselected", "TabContainer", flat(Color(INK, 0.08), Color(INK, 0.15), 1, 2, 8))
	t.set_stylebox("tab_hovered", "TabContainer", flat(Color("#fff7e2"), GOLD, 1, 2, 8))
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", INK_2)
	t.set_color("font_hovered_color", "TabContainer", SEAL_DARK)
	t.set_font("font", "TabContainer", serif(700))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "VScrollBar", flat(Color(INK, 0.1), Color.TRANSPARENT, 0, 3, 2))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(INK_2, 0.55), Color.TRANSPARENT, 0, 3, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(INK_2, Color.TRANSPARENT, 0, 3, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(INK, Color.TRANSPARENT, 0, 3, 2))
	var line := StyleBoxLine.new()
	line.color = Color(INK, 0.22)
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 12)
	_theme = t
	return t
