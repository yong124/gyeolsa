class_name CardFaceV2
extends RefCounted
## 카드 앞면 그리기 (손패 · 사연 카드)


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
