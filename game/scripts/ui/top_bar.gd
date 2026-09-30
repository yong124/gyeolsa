class_name TopBar
extends PanelContainer
## 상단 바: 작전 이름 · 날짜 달력 · 남은 날 · 광복수치 게이지 · 경계 단계 · 오늘의 일제 동향 · 메뉴

signal menu_pressed

var game: GameRules
var _subtitle := ""
var _cal: Control
var _dleft: Label
var _gauge: Control
var _score_lbl: Label
var _alert: Control
var _alert_lbl: Label
var _today: PanelContainer
var _today_name: Label
var _today_icon: TextureRect
var _shown_score := -1.0      # 게이지 연출 중 표시 값


func _init(g: GameRules, subtitle: String) -> void:
	game = g
	_subtitle = subtitle


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	add_child(h)

	var op := VBoxContainer.new()
	op.add_theme_constant_override("separation", -4)
	op.add_child(UiKit.title("경성 작전", 18))
	op.add_child(UiKit.text(_subtitle, 12, Style.INK_3, false))
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

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)

	var gl := VBoxContainer.new()
	gl.add_theme_constant_override("separation", -6)
	gl.alignment = BoxContainer.ALIGNMENT_CENTER
	var gl1 := UiKit.text("광복수치", 12, Style.INK_2, false, 700)
	gl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.add_child(gl1)
	_score_lbl = UiKit.title("", 22, Style.INK, 900)
	_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.add_child(_score_lbl)
	h.add_child(gl)
	_gauge = Control.new()
	_gauge.draw.connect(_draw_gauge)
	h.add_child(_gauge)
	h.add_child(_vsep())

	_alert = Control.new()
	_alert.custom_minimum_size = Vector2(84, 40)
	_alert.draw.connect(_draw_alert)
	_alert.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_alert)
	_alert_lbl = UiKit.text("", 13, Style.INK_2, false, 700)
	h.add_child(_alert_lbl)

	_today = PanelContainer.new()
	_today.add_theme_stylebox_override("panel", Style.flat(Style.INK, Color.TRANSPARENT, 0, 2, 5))
	_today.mouse_filter = Control.MOUSE_FILTER_PASS
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	_today.add_child(th)
	_today_icon = UiKit.icon(Style.tex("police"), Vector2(30, 30))
	th.add_child(_today_icon)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	tv.add_child(UiKit.label("오늘의 일제 동향", 11, Style.ON_DARK_DIM))
	_today_name = UiKit.label("", 15, Style.ON_DARK_ACCENT)
	_today_name.add_theme_font_override("font", Style.serif(800))
	tv.add_child(_today_name)
	th.add_child(tv)
	h.add_child(_today)

	var menu := UiKit.button("", func(): menu_pressed.emit(), 14, "paper")
	menu.icon = UiKit.ui_icon("menu")
	menu.expand_icon = true
	menu.custom_minimum_size = Vector2(44, 40)
	menu.add_theme_constant_override("icon_max_width", 22)
	menu.tooltip_text = "일시정지 · 설정 · 규칙 도감 (ESC)"
	h.add_child(menu)
	refresh()


func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = Color(Style.INK, 0.18)
	c.custom_minimum_size = Vector2(1, 36)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func refresh() -> void:
	_dleft.text = "D-%d" % game.rounds_left
	if _shown_score < 0.0 or not _gauge.has_meta("anim"):
		_shown_score = game.score
	_score_lbl.text = "%d / %d" % [roundi(_shown_score), game.goal]
	_alert_lbl.text = "경계\n%d단계" % game.alert_level()
	_alert.tooltip_text = "경계 %d단계 · 경찰 이동 %d칸\n날짜가 지날수록 단계가 오르고 경찰이 빨라집니다." % [game.alert_level(), game.police_speed()]
	_cal.tooltip_text = "오늘 %s · 8월 15일까지 %d일\n8월 15일이 되면 일본이 항복하며 작전이 끝납니다." % [game.date_label(), game.rounds_left]
	var occ := game.today_occupation()
	_today.visible = occ != ""
	if occ != "":
		var d := game.data.occupation(occ)
		_today_name.text = d["name"]
		_today.tooltip_text = "%s\n%s" % [d["text"], d["effect_text"]]
	_cal.custom_minimum_size = Vector2(_cal_cells().size() * 41, 44)
	_gauge.custom_minimum_size = Vector2(game.goal * 21 + 2, 44)
	_cal.queue_redraw()
	_gauge.queue_redraw()
	_alert.queue_redraw()


func animate_score(to: int, dur: float) -> void:
	## 게이지를 한 칸씩 채운다
	_gauge.set_meta("anim", true)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_shown_score = v
		_score_lbl.text = "%d / %d" % [roundi(v), game.goal]
		_gauge.queue_redraw(), _shown_score, float(to), maxf(dur, 0.01))
	await tw.finished
	_gauge.remove_meta("anim")


func pip_center(i: int) -> Vector2:
	## 광복수치 i번째 칸의 화면 좌표 (점수가 날아올 곳)
	return _gauge.global_position + Vector2(1 + i * 21 + 10, _gauge.size.y / 2.0)


func today_center() -> Vector2:
	return _today.global_position + _today.size / 2.0 if _today.visible else global_position + Vector2(size.x - 200, size.y / 2)


# ---------------------------------------------------------------- 그리기

func _cal_cells() -> Array:
	## 보여 줄 날짜 칸: 남은 일수 목록 (큰 수 = 과거). 길면 오늘 앞뒤만 보이고 마지막(15일)은 항상
	var total := game.rounds_total
	var cells := []
	var first := mini(total, game.rounds_left + 2)
	var last := maxi(0, game.rounds_left - 7)
	for rl in range(first, last - 1, -1):
		cells.append(rl)
	if last > 0:
		cells.append(-1)   # … 생략
		cells.append(0)
	return cells


func _draw_calendar() -> void:
	var font := Style.sans(600)
	var sfont := Style.serif(800)
	var x := 0.0
	for rl in _cal_cells():
		var r := Rect2(x, 2, 38, 40)
		x += 41
		if rl == -1:
			_cal.draw_string(font, Vector2(r.position.x + 12, 28), "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.INK_3)
			continue
		var d := game.date_of(rl)
		var past: bool = rl > game.rounds_left
		var today: bool = rl == game.rounds_left
		var col := Style.INK
		if today:
			r.position.y -= 3
			_cal.draw_rect(r, Color(Style.SEAL, 0.1))
			_cal.draw_rect(r, Style.SEAL, false, 2.0)
			col = Style.SEAL
		elif rl == 0:
			_dashed_rect(r, Style.SEAL)
		else:
			_cal.draw_rect(r, Color(1, 1, 1, 0.35 if not past else 0.15))
			_cal.draw_rect(r, Color(Style.INK_2, 0.35), false, 1.0)
		var a := 0.45 if past else 1.0
		var top := "오늘" if today else ("광복" if rl == 0 else "%d월" % d.x)
		_center(font, top, Vector2(r.get_center().x, r.position.y + 13), 10, Color(Style.INK_3 if not today else Style.SEAL, a))
		_center(sfont, str(d.y), Vector2(r.get_center().x, r.position.y + 34), 17, Color(col, a))
		if past:
			var inset := r.grow(-6)
			_cal.draw_line(inset.position, inset.end, Color(Style.SEAL, 0.75), 2.5, true)
			_cal.draw_line(Vector2(inset.end.x, inset.position.y), Vector2(inset.position.x, inset.end.y), Color(Style.SEAL, 0.75), 2.5, true)


func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		_cal.draw_dashed_line(pts[i], pts[i + 1], col, 2.0, 4.0)


func _center(font: Font, t: String, at: Vector2, fs: int, col: Color, on: CanvasItem = null) -> void:
	var c: CanvasItem = on if on else _cal
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, at - Vector2(w / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_gauge() -> void:
	var filled := _shown_score
	for i in game.goal:
		var r := Rect2(1 + i * 21, 8, 18, 28)
		_gauge.draw_rect(r, Color(1, 1, 1, 0.3))
		var f := clampf(filled - i, 0.0, 1.0)
		if f > 0.0:
			var fr := Rect2(r.position.x, r.end.y - r.size.y * f, r.size.x, r.size.y * f)
			_gauge.draw_rect(fr, Style.SEAL)
			_gauge.draw_rect(fr.grow(-2), Color(1, 1, 1, 0.1), false, 1.0)
		_gauge.draw_rect(r, Style.INK_2 if f < 1.0 else Style.SEAL_DARK, false, 1.5)


func _draw_alert() -> void:
	var t := Style.tex("police")
	var lvl := game.alert_level()
	for i in 3:
		var r := Rect2(i * 27, 7, 26, 26)
		_alert.draw_texture_rect(t, r, false, Color(1, 1, 1, 1.0) if i < lvl else Color(0.5, 0.45, 0.4, 0.28))
