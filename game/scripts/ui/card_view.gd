class_name CardView
extends RefCounted
## 카드 앞면 그리기. 손패의 작은 카드와 가운데 뜨는 큰 카드가 같은 모양을 쓴다.

const DECKS := {
	"event": {"title": "이 벤 트", "color": Style.EVENT, "image": "res://assets/tiles/event.png"},
	"item": {"title": "아 이 템", "color": Style.ITEM, "image": "res://assets/tiles/item.png"},
	"occupation": {"title": "일 제 동 향", "color": Style.INK, "image": "res://assets/ui/police.png"},
	"mission": {"title": "미 션", "color": Style.MISSION, "image": "res://assets/tiles/assassin.png"},
	"strike": {"title": "결 행", "color": Style.SEAL, "image": "res://assets/tiles/base.png"},
}


static func face(band: String, band_col: Color, art: Texture2D, name: String, desc: String, w: float, h: float, round_art := false, art_frac := 0.36, one_line := false) -> PanelContainer:
	## one_line: 이름을 한 줄로 줄이고(넘치면 …), 설명이 비면 설명 칸을 두지 않는다 (좁은 줄에 여러 장을 놓을 때)
	## 종이 카드: 색 띠(종류) · 그림 · 이름(명조) · 설명
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.card_paper(0))
	card.custom_minimum_size = Vector2(w, h)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	var b := Label.new()
	b.text = band
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", maxi(11, int(w * 0.095)))
	b.add_theme_font_override("font", Style.sans(800))
	b.add_theme_color_override("font_color", Color.WHITE)
	var bs := Style.flat(band_col, Color.TRANSPARENT, 0, 0, 3)
	bs.corner_radius_top_left = 5
	bs.corner_radius_top_right = 5
	b.add_theme_stylebox_override("normal", bs)
	v.add_child(b)
	var art_rect := TextureRect.new()
	art_rect.texture = art
	art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art_rect.custom_minimum_size = Vector2(0, h * art_frac)
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var am := UiKit.margin(int(w * 0.07))
	am.add_theme_constant_override("margin_top", 4)
	am.add_theme_constant_override("margin_bottom", 0)
	am.add_child(art_rect)
	v.add_child(am)
	var n := UiKit.title(name, maxi(14, int(w * 0.13)), Style.INK, 800)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if one_line:
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	var dm := UiKit.margin(int(w * 0.06))
	dm.add_theme_constant_override("margin_top", 0)
	var d := UiKit.text(desc, maxi(11, int(w * 0.088)), Style.INK_2)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.clip_text = true
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dm.add_child(d)
	dm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var keep_desc := not (one_line and desc == "")
	if keep_desc:
		v.add_child(dm)
	for c in [v, b, n, d, dm, am]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not keep_desc:
		dm.free()   # 트리에 붙이지 않은 설명 칸
	return card


static func build(game: GameRules, deck: String, id: String, who: String) -> Control:
	## 가운데 뜨는 큰 카드 (뽑은 이벤트·아이템·일제 동향)
	var info: Dictionary = DECKS[deck]
	var d: Dictionary
	match deck:
		"event": d = game.event_def(id)
		"item": d = game.item_def(id)
		"occupation": d = game.data.occupation(id)
		"strike":
			var st: Dictionary = game.data.text["strikes"][id]
			d = {"name": st["name"], "text": "%s — %s" % [st["base_name"], st["brief"]], "effect_text": game.strike_goal_text()}
	var head: Color = info["color"]
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var whol := UiKit.label(who, 15, Style.ON_DARK_ACCENT)
	whol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(whol)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.card_paper(0))
	card.custom_minimum_size = Vector2(360, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var b := Label.new()
	b.text = info["title"]
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_font_override("font", Style.sans(800))
	b.add_theme_color_override("font_color", Color.WHITE if deck != "occupation" else Style.ON_DARK_ACCENT)
	var bs := Style.flat(head, Color.TRANSPARENT, 0, 0, 6)
	bs.corner_radius_top_left = 5
	bs.corner_radius_top_right = 5
	b.add_theme_stylebox_override("normal", bs)
	v.add_child(b)
	var art := UiKit.icon(load(d.get("image", info["image"])), Vector2(0, 150))
	v.add_child(art)
	var m := UiKit.margin(22)
	m.add_theme_constant_override("margin_top", 0)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	m.add_child(mv)
	v.add_child(m)
	var n := UiKit.title(d["name"], 32, Style.INK, 900)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(n)
	var t := UiKit.text(d["text"], 15, Style.INK_2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(t)
	var fx := PanelContainer.new()
	fx.add_theme_stylebox_override("panel", Style.flat(Style.INK if deck == "occupation" else Color(head, 0.14), Color.TRANSPARENT, 0, 2, 8))
	var fl := UiKit.text(d["effect_text"], 16, Style.ON_DARK_ACCENT if deck == "occupation" else head.darkened(0.35), true, 700)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx.add_child(fl)
	mv.add_child(fx)
	var hint := UiKit.text("클릭하면 닫힙니다", 11, Style.INK_3, false)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(hint)
	for c in [v, b, art, m, mv, n, t, fx, fl, hint, whol]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	return root
