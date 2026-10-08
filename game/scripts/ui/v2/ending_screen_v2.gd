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
	# 결과 네 갈래(U3): 그림 · 도장 · 제목을 결과의 감정에 맞춘다
	var look := _look(e)
	var art: Texture2D = look["art"]
	if art != null:
		var img := TextureRect.new()
		img.texture = art
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.custom_minimum_size = Vector2(900, 360)
		if look["gray"]:
			img.material = _gray_material()
		v.add_child(img)
	v.add_child(UiKit.stamp(look["stamp"], 26, Style.GOOD if won else Style.SEAL, -6))
	v.add_child(UiKit.title(look["title"], Style.FS_H1))
	for line in _why(e, won):
		var why := UiKit.text(line, 17, Style.INK_2, false, 700)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(why)
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
		# 후일담 한 사람: 초상(있으면) + 사연 · 문장. 차례로 떠오른다
		var row_ep := HBoxContainer.new()
		row_ep.add_theme_constant_override("separation", 14)
		var face := ArtV2.get_tex("char", str(p["character"]))
		if face != null:
			var fr := TextureRect.new()
			fr.texture = face
			fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			fr.custom_minimum_size = Vector2(72, 96)
			if not ep.get("done", false) and not won:
				fr.modulate = Color(0.75, 0.72, 0.68)   # 지고 못 이룬 사람은 빛바래게
			row_ep.add_child(fr)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_child(UiKit.title(head, 17, Style.INK))
		var body := UiKit.text(str(ep.get("text", "")), 16, Style.INK_2)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(body)
		row_ep.add_child(tv)
		v.add_child(row_ep)
		row_ep.modulate.a = 0.0
		create_tween().tween_property(row_ep, "modulate:a", 1.0, 0.5).set_delay(0.6 + 0.45 * float(pid))
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


func _look(e: Dictionary) -> Dictionary:
	## 결과별 그림 · 도장 · 제목: 성공 / 문턱에서 멈춤 / 중간에 멈춤 / 결행 못 함 (지시서 U3)
	var target := str(e.get("target", ""))
	var strike: Dictionary = game.data.strike(target) if target != "" else {}
	var strike_tex := ArtV2.get_tex("strike", target) if target != "" else null
	var kind := str(e.get("id", ""))
	if kind == "history" and int(e.get("scene_index", -1)) >= 0:
		kind = "fail_middle"   # 결행은 했지만 첫 장면에서 멈춤: 엔진 엔딩은 「정사」지만 화면은 멈춘 장면을 보여 준다
	match kind:
		"victory":
			return {"art": ArtV2.get_tex("ending", target + "_win"), "gray": false, "stamp": "대 성 공",
				"title": "%s — %s" % [e.get("title", ""), strike.get("name", "")] if not strike.is_empty() else str(e.get("title", ""))}
		"fail_final":
			return {"art": strike_tex, "gray": true, "stamp": "실 패", "title": str(e.get("title", ""))}
		"fail_middle":
			var card := _stopped_scene(e)
			var t: Texture2D = ArtV2.get_tex("scene", str(card.get("id", "")), strike_tex)
			return {"art": t, "gray": true, "stamp": "작 전 중 단",
				"title": "결행은 「%s」에서 멈췄다" % card.get("name", "") if not card.is_empty() else str(e.get("title", ""))}
	return {"art": ArtV2.get_tex("ending", "fail"), "gray": false, "stamp": "작 전 종 료", "title": str(e.get("title", ""))}


func _stopped_scene(e: Dictionary) -> Dictionary:
	var i := int(e.get("scene_index", -1))
	return game._scene_card(str(game.scenes[i])) if i >= 0 and i < game.scenes.size() else {}


func _why(e: Dictionary, won: bool) -> Array:
	## 왜 이런 결과가 났는지 한두 문장 + 내 몫 한 문장 (판 기록에서 고름)
	var out := []
	var li: Dictionary = game.launch_info
	var launched := not li.is_empty() and str(li.get("target", "")) != ""
	if launched:
		var tgt := str(li["target"])
		out.append("%d일째, %s 첩보 %d · 결행 준비 %d로 결행했습니다." % [int(li.get("day", 0)),
			game.base_name(game.data.base_ids.find(tgt)), int(li.get("intel", {}).get(tgt, 0)), int(li.get("ready", 0))])
	else:
		out.append("결행 준비가 %d / %d에 그쳐 결행을 선언하지 못했습니다." % [game.ready, int(game.data.rules["launch_min"])])
	if not won:
		# 가장 컸던 어려움 하나
		var missed := int(game.stats.get("ops_seen", 0)) - int(game.stats.get("ops_blocked", 0))
		var jailed := 0
		for p in game.players:
			jailed += int(p["stats"].get("jailed", 0))
		var peak := int(game.stats.get("max_exposure", game.exposure))
		var cands := [
			[float(missed) / 2.0, "일제 작전을 %d번 놓쳐 일제의 압박이 커졌습니다." % missed],
			[float(jailed) / 5.0, "요원들이 모두 %d번 투옥되어 손이 모자랐습니다." % jailed],
			[float(peak) / 7.0, "노출이 %d까지 올라 경찰이 거세게 움직였습니다." % peak],
		]
		cands.sort_custom(func(a, b): return a[0] > b[0])
		if cands[0][0] >= 1.0:
			out.append(cands[0][1])
	var me: Dictionary = game.players[human] if human >= 0 and human < game.players.size() else {}
	if not me.is_empty():
		var st: Dictionary = me["stats"]
		var bits := ["미션 %d개를 이루었고" % int(st.get("missions", 0))]
		if int(st.get("rescues", 0)) > 0:
			bits.append("동료를 %d번 구했고" % int(st["rescues"]))
		bits.append("%d번 갇혔습니다" % int(st.get("jailed", 0)) if int(st.get("jailed", 0)) > 0 else "한 번도 잡히지 않았습니다")
		out.append("나(%s)는 %s." % [game.char_def(me).get("name", ""), " ".join(bits)])
	return out


func _gray_material() -> ShaderMaterial:
	## 실패한 결과의 그림: 흑백 · 조금 어둡게
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g) * vec3(0.92, 0.88, 0.82), c.a);
}
"
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


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
