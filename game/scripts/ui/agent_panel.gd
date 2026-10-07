class_name AgentPanel
extends PanelContainer
## 요원 명부: 요원마다 초상 · 이름 · 미션/아이템/상태 칩(마우스를 올리면 설명) · 차례 도장.
## 줄은 한 번 만들고, 내용이 바뀐 줄의 칩만 다시 만든다.

var game: GameRules
var human := 0
var _box: VBoxContainer
var _rows: Array = []     # [{"panel", "face", "name", "sub", "chips", "stamp", "sig", "cur"}]


func _init(g: GameRules, human_id: int) -> void:
	game = g
	human = human_id


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UiKit.title("요 원 명 부", 16, Style.INK_2)
	head.add_child(t)
	var hint := UiKit.text("마우스를 올리면 자세히", 11, Style.INK_3, false)
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(hint)
	v.add_child(head)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 5)
	v.add_child(_box)
	for p in game.players:
		_rows.append(_make_row(p))
	refresh()


func _make_row(p: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var bar := ColorRect.new()
	bar.color = Style.seat(p["id"])
	bar.custom_minimum_size = Vector2(5, 0)
	h.add_child(bar)
	var face := Face.new()
	face.tex = load(game.data.faction(p["faction"])["emblem"])
	face.ring = Style.seat(p["id"])
	face.custom_minimum_size = Vector2(48, 48)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 6)
	var short: String = p["name"].split(" (")[0]
	var name := UiKit.title(short, 16, Style.INK)
	nh.add_child(name)
	var f := game.data.faction(p["faction"])
	var personality := GameAI.persona_name(game, p)
	var desc := "%s · %s" % [f["name"], f.get("active", {}).get("name", "")]
	if personality != "":
		desc += " · %s형" % personality
	var sub := UiKit.text(desc, 12, Style.INK_3, false)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	if personality != "":
		sub.tooltip_text = "%s형: %s" % [personality, GameAI.persona_desc(game, p)]
		sub.mouse_filter = Control.MOUSE_FILTER_STOP
	nh.add_child(sub)
	v.add_child(nh)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 5)
	chips.add_theme_constant_override("v_separation", 3)
	v.add_child(chips)
	var stamp := UiKit.stamp("차 례", 14)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(stamp)
	var right := UiKit.text("", 11, Style.INK_3, false)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	h.add_child(pad)
	_box.add_child(panel)
	return {"panel": panel, "face": face, "chips": chips, "stamp": stamp, "right": right, "sig": "", "cur": null}


func refresh(cur := -1) -> void:
	## cur: 화면에 보이는 차례 (연출이 엔진보다 늦을 수 있다)
	if cur < 0:
		cur = game.current
	for p in game.players:
		var row: Dictionary = _rows[p["id"]]
		var is_cur: bool = p["id"] == cur and game.phase != "over"
		if row["cur"] != is_cur:
			row["cur"] = is_cur
			var st := Style.row(Color("#fff8e1", 0.8) if is_cur else Color(1, 1, 1, 0.26),
				Style.GOLD if is_cur else Color(Style.INK, 0.14), 2 if is_cur else 1)
			st.content_margin_left = 0
			st.content_margin_top = 6
			st.content_margin_bottom = 6
			if is_cur:
				st.shadow_color = Color(0, 0, 0, 0.12)
				st.shadow_offset = Vector2(4, 4)
			row["panel"].add_theme_stylebox_override("panel", st)
			row["stamp"].visible = is_cur
		var face: Face = row["face"]
		var ring: Color = Style.INK if p["traitor"] else Style.seat(p["id"])
		if face.jailed != p["jailed"] or face.ring != ring:
			face.jailed = p["jailed"]
			face.ring = ring
			face.queue_redraw()
		var jailed_n: int = p["stats"].get("jailed", 0) if p.has("stats") else 0
		row["right"].text = "투옥 %d회" % jailed_n if jailed_n > 0 and not is_cur else ""
		var chips := _chips(p)
		var sig := str(chips)
		if sig != row["sig"]:
			row["sig"] = sig
			UiKit.clear(row["chips"])
			for c in chips:
				row["chips"].add_child(_chip(c))


func _chips(p: Dictionary) -> Array:
	## [표시 글, 아이콘 글자, 색, 설명, 흐리게?]
	var out := []
	if p["traitor"]:
		out.append(["변절자", "✕", Style.INK, "일제에 회유되어 돌아섰습니다. 요원이 있는 칸에 들어가 기습 체포하고, 가까운 요원을 밀고합니다.\n8월 15일까지 결행을 막으면 변절자가 이깁니다.", false])
	if p["mission"].get("type", "") != "":
		var m := game.data.mission(p["mission"]["type"])
		var desc: String = m.get("effect_text", "")
		if p["mission"].has("base"):
			desc = desc.replace("{base}", game.data.base_names[p["mission"]["base"]])
		out.append([game.mission_label(p["mission"]).replace(" - ", " · "), "◎", Style.MISSION,
			"미션: %s\n%s" % [m.get("name", ""), desc], false])
	if not p["items"].is_empty():
		var names: Array = p["items"].map(func(id): return "· %s — %s" % [game.item_def(id)["name"], game.item_def(id)["effect_text"]])
		var lbl := "아이템" if p["id"] != human else ", ".join(p["items"].map(func(id): return game.item_def(id)["name"]))
		out.append([lbl, str(p["items"].size()), Style.ITEM, "아이템\n" + "\n".join(names), false])
	if p["bombs"] > 0:
		out.append(["폭탄", str(p["bombs"]), Style.INK_2, game.item_def("bomb")["effect_text"], false])
	if p["jailed"]:
		out.append(["감옥", "!", Style.SEAL, "거점 감옥에 갇혀 있습니다. 차례마다 탈옥을 시도하거나, 동료가 거점에 들어오면 구출됩니다.", false])
	if game.police.has(p["id"]):
		if game.police_active(p["id"]):
			out.append(["경찰 추격", "!", Style.SEAL, "경찰이 이 요원을 쫓고 있습니다. 차례가 끝날 때 경찰이 다가오고, 같은 칸이 되면 체포됩니다.", false])
		else:
			out.append(["경찰 대기", "…", Style.WARN, "방금 나타난 경찰입니다. 이번 차례에는 움직이지 않습니다.", false])
	if p["move_mod"] != 0:
		out.append(["다음 이동 %+d" % p["move_mod"], "↑" if p["move_mod"] > 0 else "↓",
			Style.GOOD if p["move_mod"] > 0 else Style.SEAL, "다음 차례 주사위 이동에 %+d칸" % p["move_mod"], false])
	if p["skip_next"]:
		out.append(["휴식", "z", Style.INK_3, "다음 차례를 쉽니다.", false])
	if p["ability_day"] == game.rounds_left:
		var ab := game.ability_def(p)
		out.append([ab.get("name", "능력"), "✓", Style.INK_3, "오늘은 세력 능력을 이미 썼습니다. 내일 다시 쓸 수 있습니다.", true])
	return out


func _chip(c: Array) -> Control:
	var col: Color = c[2]
	var used: bool = c[4]
	var panel := PanelContainer.new()
	var st := Style.flat(Color(col, 0.9) if not used else Color(Style.INK, 0.06), col.darkened(0.25) if not used else Color(Style.INK, 0.2), 1, 9, 0)
	st.content_margin_left = 3
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", st)
	panel.tooltip_text = c[3]
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	panel.add_child(h)
	var dot := Label.new()
	dot.text = c[1]
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.custom_minimum_size = Vector2(16, 16)
	dot.add_theme_font_size_override("font_size", 10)
	dot.add_theme_font_override("font", Style.sans(800))
	dot.add_theme_color_override("font_color", Color.WHITE if not used else Style.INK_3)
	var ds := Style.flat(col.darkened(0.35) if not used else Color(Style.INK, 0.1), Color.TRANSPARENT, 0, 8, 0)
	dot.add_theme_stylebox_override("normal", ds)
	h.add_child(dot)
	var l := UiKit.label(c[0], 12, Color.WHITE if not used else Style.INK_3)
	l.add_theme_font_override("font", Style.sans(700))
	h.add_child(l)
	return panel


class Face extends Control:
	## 세력 문장 원형 초상 (좌석 색 테두리, 감옥이면 창살)
	var tex: Texture2D
	var ring := Color.WHITE
	var jailed := false
	var full := false   # 동그랗게 자른 초상: 테두리 안을 가득 채운다 (v2 요원 초상)

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var c := size / 2.0
		draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.25))
		draw_circle(c, r, ring)
		draw_circle(c, r - 3.5, Style.PAPER_HI)
		var ir := (r - 3.5) * (1.0 if full else 0.82)
		draw_texture_rect(tex, Rect2(c - Vector2(ir, ir), Vector2(ir, ir) * 2), false, Color(1, 1, 1, 0.55 if jailed else 1.0))
		if jailed:
			for k in 4:
				var x := c.x - r * 0.6 + k * r * 0.4
				draw_line(Vector2(x, c.y - r * 0.85), Vector2(x, c.y + r * 0.85), Color(0.12, 0.1, 0.08, 0.9), 2.5)
