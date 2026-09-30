class_name EndingScreen
extends Control
## 엔딩: 결말 문장이 한 줄씩 나타나고 결과 도장이 찍힌 뒤, 책상 위 "작전 보고서"(요원 기록·연표·역사 해설)를 보여 준다.

signal to_menu
signal replay

const STAMPS := {"victory": "대 성 공", "operation": "작 전 개 시", "history": "광 복"}


static func _stamp_text(id: String) -> String:
	return Loc.t(STAMPS.get(id, "완 료"))

var game: GameRules
var tutorial := false
var fresh: Array = []        # 이번 판에서 새로 달성한 도전 과제
var _intro_tw: Tween
var _stage: VBoxContainer
var _art: TextureRect
var _desk: TextureRect
var _margin: MarginContainer


func _init(g: GameRules, is_tutorial := false, new_achievements := []) -> void:
	game = g
	tutorial = is_tutorial
	fresh = new_achievements


func _epilogue() -> Array:
	## [내 세력 후일담, 최고 공로자] (튜토리얼은 없음)
	if tutorial:
		return []
	var ep: Dictionary = game.data.text.get("epilogues", {})
	var out := []
	var line: String = ep.get(game.ending.get("id", ""), {}).get(game.players[0]["faction"], "")
	if line != "":
		out.append(line)
	var best: Dictionary = {}
	for p in game.players:
		if best.is_empty() or p["stats"]["points"] > best["stats"]["points"]:
			best = p
	if not best.is_empty() and best["stats"]["points"] > 0 and ep.has("mvp"):
		out.append(str(ep["mvp"]).format({"name": best["name"].split(" (")[0], "points": best["stats"]["points"]}))
	return out


func _achievement_row(size_fs: int, on_dark: bool) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.alignment = FlowContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("h_separation", 14)
	h.add_theme_constant_override("v_separation", 8)
	for a in fresh:
		var st := UiKit.stamp(Loc.t("도전 과제 · ") + a["name"], size_fs, Color("#e0b04a") if on_dark else Style.SEAL, -4)
		st.tooltip_text = a["desc"]
		st.mouse_filter = Control.MOUSE_FILTER_STOP
		h.add_child(st)
	return h


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art = TextureRect.new()
	_art.texture = load("res://assets/ui/title.png")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.modulate = Color(1, 1, 1, 0.35 if game.ending["id"] == "victory" else 0.18)
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desk = TextureRect.new()
	_desk.texture = Style.tex("desk")
	_desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_desk.modulate.a = 0.0
	add_child(_desk)
	_desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = UiKit.margin(60)
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = VBoxContainer.new()
	_stage.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage.add_theme_constant_override("separation", 16)
	_margin.add_child(_stage)
	Music.play("ending" if game.ending["id"] != "history" else "main")
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)
	_show_ending()


func _show_ending() -> void:
	UiKit.clear(_stage)
	var reason := Loc.t("목표 달성 — %s") % game.date_label() if game.ending["reason"] == "goal" else Loc.t("8월 15일, 일본 항복")
	var head := UiKit.label(Loc.t("%s  ·  광복수치 %d / %d") % [reason, game.score, game.goal], 18, Style.ON_DARK_ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(head)
	var name := UiKit.label(game.ending["name"], 60, Style.ON_DARK_TITLE)
	name.add_theme_font_override("font", Style.serif(900))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(name)
	var st := UiKit.stamp(_stamp_text(game.ending["id"]), 34, Color("#d8392f"), -9)
	st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	st.modulate.a = 0.0
	_stage.add_child(st)
	var lines: PackedStringArray = game.ending["text"].split("\n")
	var labels := []
	for l in lines:
		var lab := UiKit.label(l, 21, Style.ON_DARK)
		lab.add_theme_font_override("font", Style.serif(500))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.modulate.a = 0.0
		_stage.add_child(lab)
		labels.append(lab)
	var ep := _epilogue()
	for i in ep.size():
		var el := UiKit.label(ep[i], 19 if i == 0 else 16, Style.ON_DARK_ACCENT if i == 0 else Style.ON_DARK_DIM)
		el.add_theme_font_override("font", Style.serif(700 if i == 0 else 500))
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.modulate.a = 0.0
		_stage.add_child(el)
		labels.append(el)
	if not fresh.is_empty():
		var row := _achievement_row(15, true)
		row.modulate.a = 0.0
		_stage.add_child(row)
		labels.append(row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	buttons.modulate.a = 0.0
	_stage.add_child(buttons)
	var report := UiKit.button(Loc.t("작전 보고서 보기"), _show_report, 20, "primary")
	report.custom_minimum_size = Vector2(240, 54)
	buttons.add_child(report)
	var menu := UiKit.button(Loc.t("메인 메뉴"), func(): to_menu.emit(), 18, "dark")
	menu.custom_minimum_size = Vector2(200, 54)
	buttons.add_child(menu)
	for b in [report, menu]:
		b.disabled = true
	# 문장을 한 줄씩 띄운 뒤 도장을 찍는다
	var tw := create_tween()
	_intro_tw = tw
	tw.tween_interval(1.0)
	for lab in labels:
		tw.tween_property(lab, "modulate:a", 1.0, 0.7 if not (lab is Label) or lab.text != "" else 0.1)
		tw.tween_interval(0.3)
	var inner: Control = st.get_meta("inner")
	tw.tween_callback(func():
		inner.scale = Vector2(2.2, 2.2)
		Sfx.play("score" if game.ending["id"] == "victory" else "card"))
	tw.tween_property(st, "modulate:a", 1.0, 0.05)
	tw.tween_property(inner, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.4)
	tw.tween_property(buttons, "modulate:a", 1.0, 0.5)
	tw.tween_callback(func():
		for b in [report, menu]:
			b.disabled = false)


func _show_report() -> void:
	if _intro_tw and _intro_tw.is_valid():
		_intro_tw.kill()
	Sfx.play("card")
	var tw := create_tween().set_parallel()
	tw.tween_property(_art, "modulate:a", 0.0, 0.4)
	tw.tween_property(_desk, "modulate:a", 1.0, 0.4)
	UiKit.clear(_stage)
	_margin.add_theme_constant_override("margin_top", 30)
	_margin.add_theme_constant_override("margin_bottom", 30)
	_stage.alignment = BoxContainer.ALIGNMENT_BEGIN
	var paper := UiKit.paper_panel(30)
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.add_child(paper)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	paper.add_child(root)
	var head := HBoxContainer.new()
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UiKit.label(Loc.t("작 전 보 고 서"), Style.FS_SMALL, Style.SEAL))
	hv.add_child(UiKit.title(Loc.t("%s  —  광복수치 %d / %d") % [game.ending["name"], game.score, game.goal], 30, Style.INK, 900))
	head.add_child(hv)
	var st := UiKit.stamp(_stamp_text(game.ending["id"]), 22, Style.SEAL, -8)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(st)
	root.add_child(head)
	for line in _epilogue():
		root.add_child(UiKit.text(line, 15, Style.INK_2, true, 600))
	if not fresh.is_empty():
		var ar := _achievement_row(13, false)
		ar.alignment = FlowContainer.ALIGNMENT_BEGIN
		root.add_child(ar)
	root.add_child(UiKit.hsep())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# 왼쪽: 요원 기록 + 역사 해설 (길면 스크롤)
	var lsc := ScrollContainer.new()
	lsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.size_flags_stretch_ratio = 1.4
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(lsc)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	lsc.add_child(left)
	left.add_child(UiKit.title(Loc.t("요원 인사 기록"), 20, Style.SEAL_DARK))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for h in [Loc.t("요원"), Loc.t("미션"), Loc.t("광복 기여"), Loc.t("구출"), Loc.t("투옥"), Loc.t("능력")]:
		grid.add_child(UiKit.text(h, 13, Style.INK_3, false, 700))
	var best := -1
	var best_pts := -1
	for p in game.players:
		if p["stats"]["points"] > best_pts:
			best_pts = p["stats"]["points"]
			best = p["id"]
	for p in game.players:
		var s: Dictionary = p["stats"]
		var nm := UiKit.title(p["name"] + ("  ★" if p["id"] == best and best_pts > 0 else ""), 16, Style.seat(p["id"]).darkened(0.15), 800)
		grid.add_child(nm)
		for k in ["missions", "points", "rescues", "jailed", "abilities"]:
			grid.add_child(UiKit.text(str(s[k]), 16, Style.INK, false, 700))
	left.add_child(UiKit.hsep())
	var notes: Dictionary = game.data.text.get("history_notes", {})
	left.add_child(UiKit.title(Loc.t("실제 역사에서는"), 20, Style.SEAL_DARK))
	for n in notes.get("notes", []):
		left.add_child(UiKit.title(n["title"], 16, Style.INK, 800))
		left.add_child(UiKit.text(n["text"], 14, Style.INK_2))
	left.add_child(UiKit.text(notes.get("disclaimer", ""), 12, Style.INK_3))

	# 오른쪽: 작전 연표 (먹색 띠)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.flat(Color(Style.INK, 0.06), Color(Style.INK, 0.15), 1, 2, 14))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	rv.add_child(UiKit.title(Loc.t("작전 연표"), 20, Style.SEAL_DARK))
	var log := RichTextLabel.new()
	log.bbcode_enabled = true
	log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log.add_theme_font_size_override("normal_font_size", 14)
	log.add_theme_font_size_override("bold_font_size", 16)
	log.add_theme_font_override("bold_font", Style.serif(800))
	log.add_theme_color_override("default_color", Style.INK)
	rv.add_child(log)
	var tone_col := {"good": "2f6b3a", "bad": "b3261e", "warn": "9a5412", "info": "4a3f33"}
	var last_date := ""
	for h in game.history:
		if h["date"] != last_date:
			log.append_text("%s[b]%s[/b]\n" % ["" if last_date == "" else "\n", h["date"]])
			last_date = h["date"]
		log.append_text("  [color=#%s]●[/color]  [color=#%s]%s[/color]\n" % [tone_col.get(h["tone"], "4a3f33"), tone_col.get(h["tone"], "221c16") if h["tone"] != "info" else "4a3f33", h["text"]])

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	root.add_child(buttons)
	if not tutorial:
		var again := UiKit.button(Loc.t("같은 설정으로 다시"), func(): replay.emit(), 18, "primary")
		again.custom_minimum_size = Vector2(250, 50)
		buttons.add_child(again)
	var menu := UiKit.button(Loc.t("메인 메뉴"), func(): to_menu.emit(), 18, "paper")
	menu.custom_minimum_size = Vector2(200, 50)
	buttons.add_child(menu)
