class_name EndingScreenV2
extends Control
## v2 엔딩: 결말 문장 + 요원별 후일담 (4단계 ending 딕셔너리를 그대로 보여 준다).

signal to_menu
signal replay

var game: RulesV2
var human := 0
var training := false


func _init(g: RulesV2, human_id := 0, is_training := false) -> void:
	game = g
	human = human_id
	training = is_training


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := UiKit.paper_panel(34)
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var e: Dictionary = game.ending
	var won: bool = e.get("won", false)
	Music.play("ending")
	# 엔딩 그림 (R 그림): 이기면 결행 대상의 승리 장면, 아니면 정사
	var art := ArtV2.get_tex("ending", (str(e.get("target", "")) + "_win") if won else "fail")
	if art != null:
		var img := TextureRect.new()
		img.texture = art
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.custom_minimum_size = Vector2(900, 360)
		v.add_child(img)
	v.add_child(UiKit.stamp("대 성 공" if won else "작 전 종 료", 26, Style.GOOD if won else Style.SEAL, -6))
	v.add_child(UiKit.title(str(e.get("title", "")), Style.FS_H1))
	if training:
		v.add_child(UiKit.text("훈련 작전을 마쳤습니다. 이제 진짜 작전입니다. 「바로 시작」을 누르면 요원과 판이 새로 정해집니다.", 16, Style.SEAL_DARK, false, 700))
	v.add_child(_summary(e, won))
	v.add_child(UiKit.text(str(e.get("text", "")), Style.FS_LEAD, Style.INK))
	v.add_child(UiKit.hsep())
	v.add_child(UiKit.title("요원들의 후일담", Style.FS_H3))
	for ep in e.get("epilogues", []):
		var pid := int(ep["player"])
		var p: Dictionary = game.players[pid]
		var s: Dictionary = game.data.saga(str(ep.get("saga", "")))
		var head := "%s%s — 사연 「%s」 %s" % ["(나) " if pid == human else "", game.char_def(p).get("name", ""), s.get("name", ""),
			"이룸" if ep.get("done", false) else "못 이룸"]
		v.add_child(UiKit.title(head, 17, Style.INK))
		v.add_child(UiKit.text(str(ep.get("text", "")), 16, Style.INK_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(UiKit.button("바로 시작" if training else "다시 하기", func(): replay.emit(), 18, "primary"))
	row.add_child(UiKit.button("메인 메뉴", func(): to_menu.emit(), 18, "paper"))
	v.add_child(UiKit.hsep())
	v.add_child(UiKit.title("작전 일지", Style.FS_H3))
	for h in _key_records():
		var l := UiKit.text("%s · %s" % [h["date"], h["text"]], 14, Style.GOOD if h["tone"] == "good" else (Style.SEAL if h["tone"] == "bad" else Style.INK_2))
		v.add_child(l)


func _summary(e: Dictionary, won: bool) -> Control:
	## 이 판의 요약: 결행 · 미션 · 일제 작전 · 투옥 · 노출 · 사연
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	var strike: Dictionary = game.data.strike(str(e.get("target", "")))
	var launched := not game.launch_info.is_empty() and not strike.is_empty()
	var missions := 0
	var jailed := 0
	var sagas := 0
	for p in game.players:
		missions += int(p["stats"].get("missions", 0))
		jailed += int(p["stats"].get("jailed", 0))
		if p["saga_done"] != "":
			sagas += 1
	var cleared := int(e.get("scene_index", game.scene_index)) + (1 if won else 0)
	var cells := [
		["결행", strike.get("name", "") if launched else "결행하지 못함",
			"%d일째에 결행" % int(game.launch_info.get("day", 0)) if launched else "1막에서 날이 다 갔습니다"],
		["장면 돌파", "%d / %d" % [cleared, game.scenes.size()] if launched else "—", "마지막 장면까지" if won else ""],
		["이룬 미션", "%d개" % missions, ""],
		["일제 작전", "%d / %d 막음" % [int(game.stats.get("ops_blocked", 0)), int(game.stats.get("ops_seen", 0))], ""],
		["투옥", "%d번" % jailed, "최고 노출 %d" % int(game.stats.get("max_exposure", game.exposure))],
		["사연", "%d / %d 이룸" % [sagas, game.players.size()], ""],
	]
	for c in cells:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Style.flat(Color("#f6efdd"), Style.INK_3, 1, 4, 10))
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 0)
		box.add_child(cv)
		cv.add_child(UiKit.text(c[0], 12, Style.INK_3, false, 700))
		cv.add_child(UiKit.title(c[1], 20, Style.INK))
		if c[2] != "":
			cv.add_child(UiKit.text(c[2], 12, Style.INK_3, false))
		grid.add_child(box)
	return grid


func _key_records() -> Array:
	## 작전 일지: 위협 카드를 뺀 주요 기록 (많으면 앞뒤를 남기고 줄임)
	var out := game.history.filter(func(h): return not str(h["text"]).begins_with("위협:"))
	if out.size() > 16:
		out = out.slice(0, 6) + [{"date": "…", "text": "(%d줄 생략)" % (out.size() - 12), "tone": "info"}] + out.slice(out.size() - 6)
	return out
