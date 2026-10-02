class_name TopBarV2
extends PanelContainer
## v2 상단 바 (v1 TopBar 모양): 막 · 날짜 달력 · 남은 날 · 오늘의 일제 위협(다음 위협) · 결행 준비 칸 / 첩보 토큰 · 노출·경계 · 메뉴

signal menu_pressed

var game: RulesV2
var _act_lbl: Label
var _sub_lbl: Label
var _cal: Control
var _dleft: Label
var _threat: PanelContainer
var _threat_name: Label
var _threat_next: Label
var _gauge_title: Label
var _gauge_lbl: Label
var _gauge: Control
var _alert: Control
var _alert_lbl: Label
var _funds: Control
var _trend_box: Control
var _trend_lbl: Label
var _trend: Control


func _init(g: RulesV2) -> void:
	game = g


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)

	var op := VBoxContainer.new()
	op.add_theme_constant_override("separation", -4)
	_act_lbl = UiKit.title("", 18)
	op.add_child(_act_lbl)
	_sub_lbl = UiKit.text("", 12, Style.INK_3, false)
	op.add_child(_sub_lbl)
	h.add_child(op)
	h.add_child(_vsep())

	_cal = Control.new()
	_cal.draw.connect(_draw_calendar)
	_cal.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_cal)
	var dl := VBoxContainer.new()
	dl.add_theme_constant_override("separation", -8)
	dl.alignment = BoxContainer.ALIGNMENT_CENTER
	_dleft = UiKit.title("", 26, Style.SEAL, 900)
	dl.add_child(_dleft)
	dl.add_child(UiKit.text("남은 날", 11, Style.INK_3, false))
	h.add_child(dl)

	# 오늘의 일제 위협 (v1의 "오늘의 일제 동향" 자리)
	_threat = PanelContainer.new()
	_threat.add_theme_stylebox_override("panel", Style.flat(Style.INK, Style.SEAL, 2, 2, 5))
	_threat.mouse_filter = Control.MOUSE_FILTER_PASS
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	_threat.add_child(th)
	th.add_child(UiKit.icon(Style.tex("police"), Vector2(30, 30)))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	tv.add_child(UiKit.label("오늘의 일제 위협", 11, Style.ON_DARK_DIM))
	_threat_name = UiKit.label("", 15, Style.ON_DARK_ACCENT)
	_threat_name.add_theme_font_override("font", Style.serif(800))
	tv.add_child(_threat_name)
	th.add_child(tv)
	_threat_next = UiKit.label("", 11, Style.ON_DARK_DIM)
	th.add_child(_threat_next)
	h.add_child(_threat)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)

	var gl := VBoxContainer.new()
	gl.add_theme_constant_override("separation", -6)
	gl.alignment = BoxContainer.ALIGNMENT_CENTER
	_gauge_title = UiKit.text("", 12, Style.INK_2, false, 700)
	_gauge_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.add_child(_gauge_title)
	_gauge_lbl = UiKit.title("", 22, Style.INK, 900)
	_gauge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.add_child(_gauge_lbl)
	h.add_child(gl)
	_gauge = Control.new()
	_gauge.draw.connect(_draw_gauge)
	_gauge.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_gauge)
	h.add_child(_vsep())

	_funds = Control.new()
	_funds.custom_minimum_size = Vector2(86, 44)
	_funds.draw.connect(_draw_funds)
	_funds.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_funds)
	h.add_child(_vsep())

	_trend_box = VBoxContainer.new()
	_trend_box.add_theme_constant_override("separation", -6)
	_trend_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_trend_lbl = UiKit.text("", 12, Style.INK_2, false, 700)
	_trend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_trend_box.add_child(_trend_lbl)
	_trend = Control.new()
	_trend.draw.connect(_draw_trend)
	_trend.mouse_filter = Control.MOUSE_FILTER_PASS
	_trend_box.add_child(_trend)
	h.add_child(_trend_box)
	h.add_child(_vsep())

	_alert = Control.new()
	_alert.custom_minimum_size = Vector2(84, 40)
	_alert.draw.connect(_draw_alert)
	_alert.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_alert)
	_alert_lbl = UiKit.text("", 13, Style.INK_2, false, 700)
	h.add_child(_alert_lbl)

	var menu := UiKit.button("", func(): menu_pressed.emit(), 14, "paper")
	menu.icon = UiKit.ui_icon("menu")
	menu.expand_icon = true
	menu.custom_minimum_size = Vector2(44, 40)
	menu.add_theme_constant_override("icon_max_width", 22)
	menu.tooltip_text = "일시정지 · 속도 · 규칙 요약 (ESC)"
	h.add_child(menu)
	refresh()


func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = Color(Style.INK, 0.18)
	c.custom_minimum_size = Vector2(1, 36)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func refresh() -> void:
	if game.act == 1:
		_act_lbl.text = "1막 · 정찰"
		_act_lbl.add_theme_color_override("font_color", Style.INK)
		_sub_lbl.text = "4인 · 리더 %s" % _short(game.leader)
	else:
		_act_lbl.text = "2막 · 결행"
		_act_lbl.add_theme_color_override("font_color", Style.SEAL)
		_sub_lbl.text = "%s · 리더 %s" % [game.data.strike(str(game.launch_info.get("target", ""))).get("name", ""), _short(game.leader)]
	_dleft.text = "D-%d" % game.rounds_left
	_cal.tooltip_text = "오늘 %s · 남은 날 %d일\n남은 날이 %d일이 되면 강제로 결행합니다." % [game.date_label(), game.rounds_left, int(game.data.rules["forced_launch_days_left"])]
	_cal.custom_minimum_size = Vector2(game.rounds_total * 35, 44)
	# 위협
	_threat.visible = game.threat_today != ""
	if game.threat_today != "":
		var t: Dictionary = game.data.threat(game.threat_today)
		_threat_name.text = str(t.get("name", ""))
		_threat.tooltip_text = "%s\n%s" % [t.get("name", ""), t.get("text", "")]
	var peek := game.threat_preview()
	var nx := []
	for i in peek.size():
		nx.append("%s: %s" % [["내일", "모레", "글피"][mini(i, 2)], game.data.threat(str(peek[i])).get("name", "")])
	_threat_next.text = "\n".join(nx)
	_threat_next.visible = not nx.is_empty()
	# 결행 준비 / 첩보 토큰
	if game.act == 1:
		_gauge_title.text = "결행 준비 (투표 %d)" % int(game.data.rules["launch_min"])
		var extra: int = game.ready - int(game.data.rules["launch_min"])
		_gauge_lbl.text = "%d / %d" % [game.ready, int(game.data.rules["launch_min"])] + ((" · 혜택 %d" % extra) if extra > 0 else "")
		_gauge.custom_minimum_size = Vector2(maxi(game.ready, int(game.data.rules["launch_min"]) + 2) * 21 + 2, 44)
		_gauge.tooltip_text = "공개 미션을 이루면 결행 준비가 오릅니다. %d가 되면 아침마다 결행 투표가 열리고, %d를 넘는 1점마다 결행할 때 「결행 혜택」을 하나씩 고릅니다 (지금 혜택 %d개)." % [int(game.data.rules["launch_min"]), int(game.data.rules["launch_min"]), maxi(0, game.ready - int(game.data.rules["launch_min"]))]
	else:
		_gauge_title.text = "첩보 토큰"
		_gauge_lbl.text = "%d" % game.intel_tokens
		_gauge.custom_minimum_size = Vector2(maxi(game.intel_tokens, 1) * 24 + 2, 44)
		_gauge.tooltip_text = "결행 거점의 첩보가 토큰이 되었습니다. 1개로 장면 판정 +%d, 또는 주사위 조건 −%d." % [
			int(game.data.rules["intel_token"]["check_bonus"]), int(game.data.rules["intel_token"]["dice_reduce"])]
	# 군자금
	_funds.tooltip_text = "군자금 %d / %d — 팀이 함께 쓰는 돈입니다.\n장터(아이템 %d · 폭탄 %d), 검문소 뇌물 %d, 간수 매수·정보원·무기 조달, 장면 매수에 씁니다.\n가택 수색·자금 동결·노출 9에서 잃습니다." % [
		game.funds, int(game.data.rules["funds"]["max"]), int(game.data.rules["market"]["offers"][0]["cost"]), int(game.data.rules["market"]["offers"][1]["cost"]),
		int(game.data.rules["checkpoint"]["bribe"])]
	_funds.queue_redraw()
	# 일제 동향 (1막만)
	_trend_box.visible = game.act == 1
	var tmax := int(game.data.rules["ops"]["trend_max"])
	_trend_lbl.text = "일제 동향 %d / %d" % [game.trend, tmax]
	_trend.custom_minimum_size = Vector2(tmax * 17 + 2, 26)
	var pen := []
	for e in game._trend_penalty():
		match str(e.get("op", "")):
			"exposure": pen.append("노출 %+d" % int(e["value"]))
			"police_dispatch": pen.append("가까운 거점에서 경찰이 출동해 가장 가까운 요원을 쫓음")
			"ready": pen.append("결행 준비 %+d" % int(e["value"]))
	var rf := game._trend_reinforce()
	_trend_box.tooltip_text = "일제 동향 %d / %d — 일제 작전이 나올 때마다 1, 못 막으면 1 더 오릅니다 (막아도 내려가지 않음).\n지금 못 막으면 카드 벌칙에 더해: %s\n결행하면 남은 작전은 치우고, 지금 동향이면 2막 위협 덱에 증원 %d장을 더 섞습니다." % [
		game.trend, tmax, ", ".join(pen) if not pen.is_empty() else "없음", rf]
	_trend.tooltip_text = _trend_box.tooltip_text
	var th: Array = game.data.rules["exposure"]["thresholds"]
	_alert_lbl.text = "노출 %d\n경계 %d단계" % [game.exposure, game.alert_level()]
	_alert.tooltip_text = "노출 %d — 경계 %d단계 · 경찰 이동 %d칸\n노출 %d부터 2단계, %d부터 3단계. 결행할 때 경계가 높으면 「경비 강화」 장면이 늘어납니다." % [
		game.exposure, game.alert_level(), game.police_speed(), int(th[0]), int(th[1])]
	_cal.queue_redraw()
	_gauge.queue_redraw()
	_alert.queue_redraw()
	_trend.queue_redraw()


func _short(pid: int) -> String:
	var p: Dictionary = game.players[pid]
	return "나" if pid == 0 else str(game.char_def(p).get("name", p["name"]))


func threat_center() -> Vector2:
	return _threat.global_position + _threat.size / 2.0


# ---------------------------------------------------------------- 그리기

func _center(c: CanvasItem, font: Font, t: String, at: Vector2, fs: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, at - Vector2(w / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_calendar() -> void:
	var font := Style.sans(600)
	var sfont := Style.serif(800)
	var launch_day := int(game.launch_info.get("day", -1)) if not game.launch_info.is_empty() else -1
	var forced_day := game.rounds_total - int(game.data.rules["forced_launch_days_left"]) + 1
	for d in range(1, game.rounds_total + 1):
		var r := Rect2((d - 1) * 35, 2, 32, 40)
		var past := d < game.day
		var today := d == game.day
		var col := Style.INK
		if today:
			r.position.y -= 3
			_cal.draw_rect(r, Color(Style.SEAL, 0.1))
			_cal.draw_rect(r, Style.SEAL, false, 2.0)
			col = Style.SEAL
		else:
			_cal.draw_rect(r, Color(1, 1, 1, 0.35 if not past else 0.15))
			_cal.draw_rect(r, Color(Style.INK_2, 0.35), false, 1.0)
		var top := ""
		if today:
			top = "오늘"
		elif d == launch_day:
			top = "결행"
		elif game.act == 1 and d == forced_day:
			top = "강제"
		if d == launch_day and not today:
			var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
			for i in 4:
				_cal.draw_dashed_line(pts[i], pts[i + 1], Style.SEAL, 2.0, 4.0)
		var a := 0.45 if past else 1.0
		_center(_cal, font, top, Vector2(r.get_center().x, r.position.y + 12), 9, Color(Style.SEAL if today or top != "" else Style.INK_3, a))
		_center(_cal, sfont, str(d), Vector2(r.get_center().x, r.position.y + 33), 16, Color(col, a))
		if past:
			var inset := r.grow(-7)
			_cal.draw_line(inset.position, inset.end, Color(Style.SEAL, 0.6), 2.0, true)
			_cal.draw_line(Vector2(inset.end.x, inset.position.y), Vector2(inset.position.x, inset.end.y), Color(Style.SEAL, 0.6), 2.0, true)


func _draw_gauge() -> void:
	if game.act == 1:
		var need := int(game.data.rules["launch_min"])
		var n := maxi(game.ready, need + 2)
		for i in n:
			var r := Rect2(1 + i * 21, 8, 18, 28)
			_gauge.draw_rect(r, Color(1, 1, 1, 0.3))
			if i < game.ready:
				_gauge.draw_rect(r, Style.MISSION)
			_gauge.draw_rect(r, Style.INK_2 if i >= game.ready else Style.MISSION.darkened(0.3), false, 1.5)
		var x := 1 + need * 21 - 2.0
		_gauge.draw_line(Vector2(x, 2), Vector2(x, 42), Style.GOLD, 3.0)
		_gauge.draw_string(Style.sans(800), Vector2(x + 3, 10), "투표", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Style.GOLD)
	else:
		for i in maxi(game.intel_tokens, 1):
			var c := Vector2(12 + i * 24, 22)
			if i < game.intel_tokens:
				_gauge.draw_circle(c, 9, Style.SEAL)
				_gauge.draw_arc(c, 9, 0, TAU, 20, Style.SEAL_DARK, 1.5, true)
			else:
				_gauge.draw_arc(c, 8, 0, TAU, 20, Color(Style.INK_2, 0.4), 1.5, true)


func _draw_funds() -> void:
	## 군자금: 엽전 모양 동전 + 숫자 (돈 그림은 F단계에서 다듬음)
	var c := Vector2(20, 22)
	_funds.draw_circle(c + Vector2(1, 2), 14, Color(0, 0, 0, 0.3))
	_funds.draw_circle(c, 14, Style.GOLD)
	_funds.draw_arc(c, 14, 0, TAU, 28, Style.INK_2, 2.0, true)
	_funds.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Style.PAPER_HI)
	_funds.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Style.INK_2, false, 1.5)
	var font := Style.serif(900)
	var t := "%d" % game.funds
	_funds.draw_string(font, Vector2(40, 31), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Style.INK)
	_funds.draw_string(Style.sans(700), Vector2(40 + font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 3, 31), "군자금", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Style.INK_3)


func _draw_trend() -> void:
	## 일제 동향 칸 (벌칙이 커지는 문턱마다 금색 선)
	var tmax := int(game.data.rules["ops"]["trend_max"])
	for i in tmax:
		var r := Rect2(1 + i * 17, 5, 15, 20)
		_trend.draw_rect(r, Color(1, 1, 1, 0.3))
		if i < game.trend:
			_trend.draw_rect(r, Style.SEAL)
		_trend.draw_rect(r, Style.INK_2 if i >= game.trend else Style.SEAL_DARK, false, 1.5)
	for row in game.data.rules["ops"]["penalties"]:
		var mn := int(row["min"])
		if mn > 0 and mn < tmax:
			var x := 1 + mn * 17 - 1.0
			_trend.draw_line(Vector2(x, 1), Vector2(x, 25), Style.GOLD, 2.0)


func _draw_alert() -> void:
	var t := Style.tex("police")
	var lvl := game.alert_level()
	for i in 3:
		var r := Rect2(i * 27, 7, 26, 26)
		_alert.draw_texture_rect(t, r, false, Color(1, 1, 1, 1.0) if i < lvl else Color(0.5, 0.45, 0.4, 0.28))
