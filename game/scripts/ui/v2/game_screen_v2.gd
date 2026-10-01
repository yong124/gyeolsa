class_name GameScreenV2
extends Control
## v2 게임 화면: 상단 정보줄 + 보드 + 오른쪽 열(오늘의 위협·미션 줄/장면 · 팀 주사위 · 요원 명부 · 행동 · 기록).
##
## 흐름: 엔진에 액션 → 엔진이 쌓은 events를 연출 큐에 넣음 → 하나씩 재생(await)
##      → 큐가 비면 화면을 실제 상태와 맞추고 → 사람 입력을 기다리거나 AI가 한 수를 둔다.
## 버튼은 모두 엔진의 legal_actions()에서 만든다. 그래서 화면이 규칙과 어긋나지 않는다.

signal back_to_title
signal finished

const GAP := 12.0
const AI_DELAY := 0.28

var game: RulesV2
var human := 0
var meta := {}

var _queue: Array = []
var _playing := false
var _started := false
var _paused := false
var _fast := false
var _ai_timer := 0.0
var _ai_waiting := false
var _walk: Array = []
var _let_allies := false          # 낮: 사람이 "동료 먼저"를 눌러 둔 상태
var _auto := false                # 자동 진행 (내 자리도 AI가 둠, 화면 확인·캡처용)

var _board: BoardViewV2
var _frame: PanelContainer
var _top: HBoxContainer
var _top_labels := {}
var _right: VBoxContainer          # 지금 섹션을 넣는 열
var _cols: Array = []              # [왼쪽 열 스크롤, 오른쪽 열 스크롤]
var _today: VBoxContainer
var _dice_box: VBoxContainer
var _roster: VBoxContainer
var _mine: VBoxContainer
var _actions: HFlowContainer
var _hint: Label
var _log: RichTextLabel
var _fx: FxLayer
var _choice: Overlay


func _init(g: RulesV2, human_id := 0, meta_info := {}) -> void:
	game = g
	human = human_id
	meta = meta_info
	_auto = bool(meta.get("autoplay", false))
	_fast = _auto


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	_board.sync_from_game()
	_refresh()
	Music.play("main")
	_started = true
	_pump()


func _mult() -> float:
	return 0.35 if _fast else 1.0


# ================================================================ 구성

func _build() -> void:
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 18)
	add_child(_top)
	for k in ["date", "act", "leader", "alert", "ready", "intel"]:
		var l := UiKit.label("", 17, UiKit.COL_TEXT)
		_top.add_child(l)
		_top_labels[k] = l
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(sp)
	var fast := CheckButton.new()
	fast.text = "빠르게"
	fast.toggled.connect(func(on): _fast = on)
	_top.add_child(fast)
	_top.add_child(UiKit.button("규칙 요약", _show_rules, 15))
	_top.add_child(UiKit.button("메뉴", _pause, 15))

	_frame = PanelContainer.new()
	var fs := Style.flat(Color("#3b2a1c"), Color("#5a4330"), 2, 3, 9)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 18
	fs.shadow_offset = Vector2(0, 8)
	_frame.add_theme_stylebox_override("panel", fs)
	add_child(_frame)
	_board = BoardViewV2.new()
	_board.cell_clicked.connect(_on_cell)
	_frame.add_child(_board)
	_board.setup(game, human)

	# 오른쪽은 두 열: (행동 · 팀 주사위 · 오늘) | (요원 명부 · 내 손 · 작전 기록)
	for i in 2:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", int(GAP))
		scroll.add_child(col)
		_cols.append(scroll)
	_right = _cols[0].get_child(0)
	var act_panel := _section("행동")
	_dice_box = _section("팀 주사위")
	_today = _section("오늘")
	_right = _cols[1].get_child(0)
	_roster = _section("요원 명부")
	_mine = _section("내 손")
	_hint = UiKit.label("", 15, UiKit.COL_ACCENT, true)
	act_panel.add_child(_hint)
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	act_panel.add_child(_actions)
	var log_panel := _section("작전 기록")
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = false
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", UiKit.COL_DIM)
	log_panel.add_child(_log)

	_fx = FxLayer.new()
	add_child(_fx)
	_choice = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	add_child(_choice)


func _section(title: String) -> VBoxContainer:
	var panel := UiKit.panel(Color(0.08, 0.065, 0.05, 0.86), Color("#5a4330"), 1)
	_right.add_child(panel)
	var m := UiKit.margin(10)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	v.add_child(UiKit.label(title, 15, UiKit.COL_TITLE))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	v.add_child(body)
	return body


func _layout() -> void:
	var w := size.x
	var h := size.y
	_top.position = Vector2(20, 12)
	_top.size = Vector2(w - 40, 40)
	var top_y := 60.0
	var side := floorf(minf(h - top_y - 12, w * 0.55))
	_frame.position = Vector2(20, top_y)
	_frame.size = Vector2(side, side)
	var rx := 20 + side + 16
	var cw := floorf((w - rx - 16 - GAP) / 2.0)
	for i in 2:
		_cols[i].position = Vector2(rx + i * (cw + GAP), top_y)
		_cols[i].size = Vector2(cw, h - top_y - 10)
	_fx.focus_center = _frame.position + _frame.size / 2.0
	_fx.board_rect = Rect2(_frame.position, _frame.size)


# ================================================================ 진행

func _act(a: Dictionary) -> void:
	if not _started or _playing or _paused or game.phase == "over":
		return
	a = a.duplicate()
	a["player"] = int(a.get("player", human))
	Sfx.play("click")
	if game.apply(a):
		_pump()
	else:
		push_warning("받아들여지지 않은 액션: %s" % str(a))


func _pump() -> void:
	for e in game.events:
		if e["kind"] == "reveal":
			_board.hidden_tiles[e["pos"]] = true
		_queue.append(e)
	game.events.clear()
	if not _playing:
		_play_queue()


func _play_queue() -> void:
	_playing = true
	_board.interactive = false
	_refresh_actions()
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		await _play_event(e)
	_playing = false
	_board.sync_from_game()
	_board.interactive = true
	_refresh()
	_after_queue()


func _after_queue() -> void:
	if game.phase == "over":
		await get_tree().create_timer(0.6).timeout
		finished.emit()
		return
	if not _walk.is_empty():
		if game.phase == "turn" and game.current == human and game.steps_left > 0:
			var nxt: Vector2i = _walk.pop_front()
			if game.can_step(game.players[human], nxt):
				_act({"type": "step", "to": nxt})
				return
		_walk.clear()
	if game.phase == "choice" and int(game.pending["player"]) == human and not _auto:
		_show_choice()
		return
	if _ai_actor() >= 0:
		_ai_waiting = true
		_ai_timer = AI_DELAY * _mult()


func _process(delta: float) -> void:
	if _ai_waiting and not _playing and not _paused:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_waiting = false
			_ai_step()


func _ai_actor() -> int:
	## 지금 AI가 둘 차례면 그 요원 id, 사람이 둘 차례면 -1
	if game.phase == "over":
		return -1
	if _auto:
		return GameAIV2.next_actor(game)
	match game.phase:
		"choice":
			var pid := int(game.pending["player"])
			return -1 if pid == human else pid
		"turn":
			return -1 if game.current == human else game.current
		"plan":
			var me: Dictionary = game.players[human]
			if me["die"] < 0 and not me["jailed"] and not me["skip_dice_tomorrow"] and _has_take(human):
				return -1   # 사람이 먼저 주사위를 고른다
			for p in game.players:
				if p["id"] == human:
					continue
				var a := GameAIV2.decide(game, p["id"])
				if _plan_move_ok(p, a):
					return p["id"]
			return -1
		"day":
			var me: Dictionary = game.players[human]
			if game.can_begin_turn(me) and not _let_allies:
				return -1
			for a in game.legal_actions():
				if a["type"] == "begin_turn" and int(a["player"]) != human:
					return int(a["player"])
			return -1
	return -1


func _plan_move_ok(p: Dictionary, a: Dictionary) -> bool:
	## 아침 계획에서 AI가 둘 만한 수인가. 주사위를 이미 가졌으면 바꿔 잡지 않는다 (사람이 하루를 시작할 때까지 기다림).
	if a.is_empty() or int(a.get("player", -1)) != p["id"]:
		return false
	match a["type"]:
		"take_die": return p["die"] < 0
		"carry_die", "use_item", "ability": return true
	return false


func _has_take(pid: int) -> bool:
	for a in game.legal_actions():
		if a["type"] == "take_die" and int(a["player"]) == pid:
			return true
	return false


func _ai_step() -> void:
	var pid := _ai_actor()
	if pid < 0:
		_refresh()
		return
	var a: Dictionary
	if _auto:
		a = GameAIV2.decide(game, pid)
	elif game.phase == "day":
		# 동료끼리의 순서: AI가 정하되 사람은 빼고
		var best := -1
		var nxt := GameAIV2.next_actor(game)
		for x in game.legal_actions():
			if x["type"] == "begin_turn" and int(x["player"]) != human:
				if best < 0 or int(x["player"]) == nxt:
					best = int(x["player"])
		a = {"type": "begin_turn", "player": best}
		_let_allies = false
	else:
		a = GameAIV2.decide(game, pid)
	if a.is_empty():
		return
	if game.apply(a):
		_pump()


# ================================================================ 연출

func _play_event(e: Dictionary) -> void:
	var m := _mult()
	var k: String = e["kind"]
	match k:
		"move":
			Sfx.play("step", 0.1, 0.5)
			await _board.animate_move(int(e["player"]), e["from"], e["to"], 0.13 * m)
		"reveal":
			Sfx.play("flip", 0.1, 0.6)
			await _board.reveal(e["pos"], 0.22 * m)
		"police":
			if _board.police_changed(e["police_snap"]):
				await _board.animate_police(e["police_snap"], 0.28 * m)
		"dice":
			await _fx.roll_dice(e, m)
		"banner":
			await _fx.banner(str(e["text"]), str(e["tone"]), m)
		"morning":
			Sfx.play("day")
			await _fx.banner("%d일째 아침" % int(e["day"]), "info", m, "리더: %s · 남은 날 %d" % [_name(int(e["leader"])), game.rounds_left])
		"threat":
			var t: Dictionary = game.data.threat(str(e["id"]))
			Sfx.play("alert")
			await _fx.banner("일제 위협 · " + str(t.get("name", "")), "bad" if t.get("tone", "bad") == "bad" else "info", m, str(t.get("text", "")))
		"jail":
			await _board.animate_move(int(e["player"]), e["from"], e["to"], 0.25 * m)
		"mission_done":
			Sfx.play("score")
			_fx.toast("미션 성공 · %s (%s)" % [game.mission_def(str(e["id"])).get("name", ""), _name(int(e["player"]))], "good")
		"saga_done":
			Sfx.play("success")
			_fx.toast("사연을 이룸 · %s — %s" % [_name(int(e["player"])), game.data.saga(str(e["id"])).get("name", "")], "good")
		"scene":
			var card: Dictionary = game.current_scene()
			await _fx.banner("장면 %d/%d · %s" % [int(e["index"]) + 1, game.scenes.size(), card.get("name", "")], "info", m, _cond_text(card.get("condition", {}), card))
		"scene_break":
			Sfx.play("success")
		"launch":
			Music.play("tension")
		"traitor":
			Sfx.play("fail")
			await _fx.banner("%s 변절" % _name(int(e["player"])), "bad", m, "“%s”" % str(e.get("lure", "")))
		"interrogation":
			_fx.toast("%s: 심문 카드 %d장" % [_name(int(e["player"])), int(e["count"])], "warn")
		"interrogation_card":
			if int(e["player"]) == human:
				var c := _interro_card(str(e["card"]))
				_fx.toast("내 심문 카드: %s" % c.get("name", ""), "bad" if c.get("shaken", false) else "info")
		"persuade_cards":
			if int(e["player"]) == human:
				_fx.toast("동료의 설득으로 심문 카드를 덜었습니다", "good")
		"card":
			if str(e.get("deck", "")) == "item" and int(e.get("player", -1)) == human and str(e.get("id", "")) != "bomb":
				_fx.toast("아이템 획득 · %s" % game.item_def(str(e["id"])).get("name", ""), "info")
			elif str(e.get("deck", "")) == "event":
				var ev: Dictionary = game.data.event(str(e["id"]))
				_fx.toast("이벤트 · %s — %s" % [ev.get("name", ""), ev.get("text", "")], "info")
		"dice_rolled":
			Sfx.play("dice", 0.1, 0.6)
	if e.has("players_snap"):
		_board.apply_players_snap(e["players_snap"])
	if k in ["morning", "threat", "dice_rolled", "day_start", "mission_done", "launch", "scene", "scene_break", "traitor",
			"saga_done", "jail", "rescue", "intel", "ready", "exposure", "turn", "night"]:
		_refresh_panels()
	_refresh_log()


func _refresh_panels() -> void:
	## 연출 중에도 정보 패널은 엔진 상태로 맞춘다 (행동 버튼은 연출이 끝난 뒤에)
	_refresh_top()
	_refresh_today()
	_refresh_dice()
	_refresh_roster()
	_refresh_mine()


func _interro_card(id: String) -> Dictionary:
	for c in game.data.interrogation.get("cards", []):
		if c["id"] == id:
			return c
	return {}


# ================================================================ 입력

func _on_cell(c: Vector2i) -> void:
	if _playing or _paused:
		return
	# 선택: 칸 고르기
	if game.phase == "choice" and int(game.pending["player"]) == human and game.pending["kind"] in ["pick_cell", "hop"]:
		for o in game.pending["options"]:
			if o["value"] is Vector2i and o["value"] == c:
				_choice.visible = false
				_board.pick_cells = []
				_act({"type": "choose", "value": c})
				return
		return
	if game.phase != "turn" or game.current != human:
		return
	var me: Dictionary = game.players[human]
	if game.can_step(me, c):
		_act({"type": "step", "to": c})
		return
	var path := _board.preview_path()
	if not path.is_empty() and path[-1] == c:
		_walk = path.duplicate()
		var first: Vector2i = _walk.pop_front()
		_act({"type": "step", "to": first})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_pause()


# ================================================================ 화면 갱신

func _refresh() -> void:
	_refresh_top()
	_refresh_today()
	_refresh_dice()
	_refresh_roster()
	_refresh_mine()
	_refresh_actions()
	_refresh_log()


func _name(pid: int) -> String:
	if pid < 0 or pid >= game.players.size():
		return "-"
	var p: Dictionary = game.players[pid]
	return ("나 (%s)" % game.char_def(p).get("name", "")) if pid == human else str(game.char_def(p).get("name", p["name"]))


func _refresh_top() -> void:
	_top_labels["date"].text = "%s · 남은 %d일" % [game.date_label(), game.rounds_left]
	_top_labels["act"].text = "1막 정찰" if game.act == 1 else "2막 결행"
	_top_labels["leader"].text = "리더 %s" % _name(game.leader)
	_top_labels["alert"].text = "노출 %d · 경계 %d단계 · 경찰 %d칸" % [game.exposure, game.alert_level(), game.police_speed()]
	_top_labels["alert"].add_theme_color_override("font_color", UiKit.COL_BAD if game.alert_level() >= 3 else (UiKit.COL_WARN if game.alert_level() == 2 else UiKit.COL_TEXT))
	if game.act == 1:
		_top_labels["ready"].text = "결행 준비 %d / %d" % [game.ready, int(game.data.rules["launch_min"])]
	else:
		_top_labels["ready"].text = "첩보 토큰 %d" % game.intel_tokens
	var parts := []
	for i in GameDataV2.BASE_IDS.size():
		parts.append("%s %d" % [game.data.base_names[i].substr(0, 2), int(game.intel.get(GameDataV2.BASE_IDS[i], 0))])
	_top_labels["intel"].text = "첩보: " + " · ".join(parts)


func _card_row(parent: Control, band: String, band_col: Color, title: String, body: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.flat(Color(0.95, 0.91, 0.82), band_col, 2, 3, 8))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var tag := UiKit.label(" %s " % band, 12, Color.WHITE)
	var tagbg := PanelContainer.new()
	tagbg.add_theme_stylebox_override("panel", Style.flat(band_col, Color.TRANSPARENT, 0, 2, 2))
	tagbg.add_child(tag)
	hb.add_child(tagbg)
	hb.add_child(UiKit.title(" " + title, 16, Style.INK))
	if body != "":
		v.add_child(UiKit.text(body, 14, Style.INK_2))


func _refresh_today() -> void:
	UiKit.clear(_today)
	if game.threat_today != "":
		var t: Dictionary = game.data.threat(game.threat_today)
		_card_row(_today, "오늘의 위협", Style.SEAL, str(t.get("name", "")), str(t.get("text", "")))
	var peek := game.threat_preview()
	if not peek.is_empty():
		var names := []
		for id in peek:
			names.append(str(game.data.threat(str(id)).get("name", "")))
		_today.add_child(UiKit.label("다음 위협 (정 인쇄공): " + " → ".join(names), 14, UiKit.COL_WARN, true))
	if game.act == 1:
		_today.add_child(UiKit.label("공개 미션 줄 — 누구든 이루면 결행 준비가 오릅니다", 13, UiKit.COL_DIM))
		for id in game.mission_row:
			var m: Dictionary = game.mission_def(str(id))
			var td: Dictionary = game.mission_type_def(str(m.get("type", "")))
			var how := str(m.get("how", td.get("how", "")))
			var body := str(m.get("text", ""))
			if how != "" and td.get("ready") != null:
				body = "%s → %s · 결행 준비 +%d" % [how, body, int(m.get("ready", td.get("ready", 1)))]
			_card_row(_today, str(td.get("name", "미션")), Style.MISSION, str(m.get("name", "")), body)
	else:
		var card := game.current_scene()
		if not card.is_empty():
			var strike: Dictionary = game.data.strike(str(game.launch_info.get("target", "")))
			_today.add_child(UiKit.label("%s — 장면 %d / %d" % [strike.get("name", ""), int(card["index"]) + 1, int(card["total"])], 15, UiKit.COL_ACCENT))
			var need := game.scene_need()
			var need_parts := []
			for key in need:
				need_parts.append("%s %d" % [{"dice": "주사위 합", "item": "아이템", "bomb": "폭탄", "check_pair": "판정 성공", "people": "사람", "hold": "밤"}.get(key, key), int(need[key])])
			_card_row(_today, "지금 장면", Style.GOLD, str(card.get("name", "")),
				_cond_text(card.get("condition", {}), card) + ("\n남은 것: " + ", ".join(need_parts) if not need_parts.is_empty() else "") \
				+ "\n여기서 멈추면: " + str(card.get("stop_text", "")))


func _where_text(w: String) -> String:
	if w in GameDataV2.BASE_IDS:
		return "거점 안"
	return {"inside": "거점 안", "adjacent": "거점 옆 칸", "inside_or_adjacent": "거점 안이나 옆 칸"}.get(w, w)


func _cond_text(c: Dictionary, card := {}) -> String:
	## 장면 조건을 문장으로 (데이터의 kind만 보고 만든다)
	var where := _where_text(str(c.get("where", card.get("where", "inside"))))
	match str(c.get("kind", "")):
		"check":
			var nm: String = {"generic": "판정", "lock": "자물쇠 판정", "assassin": "암살 판정", "evade": "회피 판정"}.get(str(c.get("check", "")), "판정")
			return "%s에서 %s %d 이상" % [where, nm, int(c.get("target", game.data.rules["checks"].get(str(c.get("check", "")), 9)))]
		"check_pair":
			return "%d명이 같은 날 %s에서 회피 판정 성공" % [int(c.get("count", 2)), where]
		"dice":
			return "%s에서 아침 주사위 합 %d 이상을 바침" % [where, int(c.get("sum", 0))]
		"pay_item":
			return "%s에서 아이템 %d장을 바침" % [where, int(c.get("count", 1))]
		"pay_bomb":
			return "%s에서 폭탄 %d개를 바침%s" % [where, int(c.get("count", 1)), " (나눠 바쳐도 됨)" if c.get("split", false) else ""]
		"people":
			return "%d명이 같은 날 %s에서 차례를 마침" % [int(c.get("count", 2)), where]
		"hold":
			return "%d명이 %s에서 %d밤을 넘김" % [int(c.get("count", 1)), where, int(c.get("days", 1))]
		"jailed_here":
			return "결행 거점 감옥에 요원이 갇혀 있음"
		"any_of":
			var parts := []
			for o in c.get("options", []):
				parts.append(_cond_text(o, card))
			return " 또는 ".join(parts)
		"all_of":
			var parts2 := []
			for o in c.get("options", []):
				parts2.append(_cond_text(o, card))
			return " 그리고 ".join(parts2)
	return str(c.get("kind", ""))


func _refresh_dice() -> void:
	UiKit.clear(_dice_box)
	if game.team_dice.is_empty():
		_dice_box.add_child(UiKit.label("아침에 굴립니다.", 14, UiKit.COL_DIM))
		return
	var legal := game.legal_actions()
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	_dice_box.add_child(row)
	for i in game.team_dice.size():
		var d: Dictionary = game.team_dice[i]
		var owner := int(d["owner"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 54)
		b.add_theme_font_size_override("font_size", 22)
		var sub := "예비"
		if owner >= 0:
			sub = ("맡음 " if d.get("carry", false) else "") + (_name(owner).split(" ")[0] if owner != human else "나")
		elif d.get("spare_used", false):
			sub = "씀"
		b.text = "%d\n%s" % [int(d["value"]), sub]
		b.add_theme_font_size_override("font_size", 16)
		Style.style_button(b, "paper" if owner < 0 else "dark")
		if owner >= 0:
			b.add_theme_color_override("font_color", Style.seat(owner).lightened(0.3))
		var acts := []
		for a in legal:
			if int(a.get("player", -1)) == human and a["type"] in ["take_die", "carry_die", "drop_carry"] and int(a["die"]) == i:
				acts.append(a)
		if owner == human and not d.get("carry", false):
			for a in legal:
				if a["type"] == "release_die" and int(a["player"]) == human:
					acts.append(a)
		if acts.is_empty():
			b.disabled = true
		else:
			var a0: Dictionary = acts[0]
			b.tooltip_text = {"take_die": "이 주사위를 오늘 내 이동으로", "carry_die": "장면에 바칠 주사위로 맡아 둠", "drop_carry": "맡은 주사위를 내려놓음", "release_die": "내 주사위를 내려놓음"}.get(a0["type"], "")
			b.pressed.connect(func(): _act(a0))
		row.add_child(b)
	if game.phase == "plan":
		var tip := "주사위를 하나 골라 오늘 이동으로 쓰세요. 남는 주사위는 예비입니다 (판정 다시 굴리기 · 설득 · 이동 보태기 · 탈옥 보태기)."
		if game.act == 2:
			tip += "\n2막: 남는 주사위를 장면에 바칠 주사위로 맡아 둘 수 있습니다."
		_dice_box.add_child(UiKit.label(tip, 13, UiKit.COL_DIM, true))


func _refresh_roster() -> void:
	UiKit.clear(_roster)
	for p in game.players:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		_roster.add_child(hb)
		var bar := ColorRect.new()
		bar.color = Style.INK if p["traitor"] else Style.seat(p["id"])
		bar.custom_minimum_size = Vector2(6, 34)
		hb.add_child(bar)
		var ch: Dictionary = game.char_def(p)
		var fac: String = str(game.data.characters.get("factions", {}).get(ch.get("faction", ""), {}).get("name", ""))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(v)
		var head := "%s%s · %s" % ["▶ " if game.current == p["id"] and game.phase in ["turn", "choice"] else "", _name(p["id"]), fac]
		var hl := UiKit.label(head, 15, UiKit.COL_TITLE if p["id"] == human else UiKit.COL_TEXT)
		hl.tooltip_text = "특성: %s\n능력: %s" % [ch.get("trait_text", ""), ch.get("ability_text", "")]
		hl.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(hl)
		var chips := []
		if p["traitor"]:
			chips.append("[변절자]")
		if p["jailed"]:
			chips.append("감옥")
		if game.police.has(p["id"]):
			chips.append("추격당함")
		if p["done_today"]:
			chips.append("차례 마침")
		if p["die"] >= 0:
			chips.append("주사위 %d" % int(p["die"]))
		chips.append("아이템 %d" % p["items"].size())
		if p["bombs"] > 0:
			chips.append("폭탄 %d" % p["bombs"])
		var ni := game.interrogation_count(p["id"])
		if ni > 0:
			chips.append("심문 %d장" % ni)
		var ps := game.public_saga(p["id"])
		if ps != "" and p["saga_done"] != "":
			chips.append("사연 이룸: %s" % game.data.saga(ps).get("name", ""))
		v.add_child(UiKit.label(" · ".join(chips), 13, UiKit.COL_BAD if p["jailed"] or p["traitor"] else UiKit.COL_DIM, true))


func _refresh_mine() -> void:
	UiKit.clear(_mine)
	var me: Dictionary = game.players[human]
	var ch: Dictionary = game.char_def(me)
	_mine.add_child(UiKit.label("%s — %s" % [ch.get("name", ""), ch.get("origin", "")], 15, UiKit.COL_TITLE, true))
	_mine.add_child(UiKit.label("특성: " + str(ch.get("trait_text", "")), 13, UiKit.COL_TEXT, true))
	_mine.add_child(UiKit.label("능력 (하루 1번): " + str(ch.get("ability_text", "")), 13, UiKit.COL_TEXT, true))
	for id in me["items"]:
		var it: Dictionary = game.item_def(str(id))
		_card_row(_mine, "아이템", Style.ITEM, str(it.get("name", "")), str(it.get("text", "")))
	var prog := game.saga_progress(human)
	for id in game.saga_cards(human):
		var s: Dictionary = game.data.saga(str(id))
		var pr: Dictionary = prog.get(id, {"have": 0, "need": 1})
		var done: bool = me["saga_done"] == id
		var band := "사연 (비밀)" if not done else "사연 이룸"
		_card_row(_mine, band, Color("#6b4f8a"), "%s  %d/%d" % [s.get("name", ""), int(pr["have"]), int(pr["need"])],
			"%s\n조건: %s\n보상: %s" % [s.get("story", ""), s.get("condition_text", ""), s.get("reward_text", "")])
	if game.interrogation_count(human) > 0:
		_mine.add_child(UiKit.label("내 심문 카드: %d장 중 흔들렸다 %d장 (2장이면 결행 때 변절할 수 있음 — 동료에게 설득을 부탁하세요)" % [
			game.interrogation_count(human), game.shaken_count(human)], 13, UiKit.COL_BAD, true))
	if not me["grants"].is_empty():
		var g := []
		for x in me["grants"]:
			g.append(str(x.get("kind", "")))
		_mine.add_child(UiKit.label("한 번 쓰는 권리: " + ", ".join(g), 13, UiKit.COL_GOOD, true))


func _refresh_log() -> void:
	var lines: Array = game.log_lines.slice(maxi(0, game.log_lines.size() - 9))
	_log.text = "\n".join(lines.map(func(s): return str(s)))


# ---------------------------------------------------------------- 행동 버튼

func _refresh_actions() -> void:
	UiKit.clear(_actions)
	_hint.text = ""
	if _playing or game.phase == "over":
		_hint.text = "…"
		return
	var me: Dictionary = game.players[human]
	var legal := game.legal_actions()
	var mine := legal.filter(func(a): return int(a.get("player", -1)) == human)
	match game.phase:
		"plan":
			_hint.text = "아침 계획: 팀 주사위에서 하나를 고르고 [하루 시작]을 누르세요." if me["die"] < 0 and not me["jailed"] else "준비되면 [하루 시작]을 누르세요."
		"day":
			if game.can_begin_turn(me):
				_hint.text = "자유 순서: 내가 먼저 할지, 동료에게 먼저 맡길지 고르세요."
				_add_btn("동료 먼저", func():
					_let_allies = true
					_after_queue(), "paper")
			else:
				_hint.text = "동료들이 움직이는 중입니다."
		"turn":
			if game.current == human:
				if me["jailed"]:
					_hint.text = "감옥: 탈옥 판정(%d 이상)을 하거나 차례를 넘기세요." % game.check_target("escape")
				else:
					_hint.text = "이동 %d칸 남음. 보드에서 칸을 누르세요 (멀리 누르면 그 길로 걸어갑니다)." % game.steps_left
			else:
				_hint.text = "%s의 차례" % _name(game.current)
		"choice":
			if int(game.pending["player"]) != human:
				_hint.text = "%s가 고르는 중" % _name(int(game.pending["player"]))
	for a in mine:
		if a["type"] in ["take_die", "carry_die", "drop_carry", "release_die", "step", "choose"]:
			continue
		var label := _label(a)
		if label == "":
			continue
		var kind := "dark"
		if a["type"] in ["start_day", "begin_turn", "end_move", "scene_check"]:
			kind = "primary"
		var aa: Dictionary = a
		_add_btn(label, func(): _act(aa), kind)


func _add_btn(text: String, cb: Callable, kind := "dark") -> void:
	var b := UiKit.button(text, cb, 15, kind)
	_actions.add_child(b)


func _label(a: Dictionary) -> String:
	var me: Dictionary = game.players[human]
	match a["type"]:
		"start_day": return "하루 시작"
		"begin_turn": return "내 차례 시작"
		"end_move": return "이동 마치기" if game.steps_left > 0 else "차례 마치기"
		"end_turn": return "차례 넘기기"
		"escape": return "탈옥 시도"
		"use_item":
			return "[%s] 사용" % game.item_def(str(me["items"][int(a["index"])])).get("name", "")
		"ability":
			var ab := game.ability_def(me)
			if a.has("target"):
				return "능력 「%s」 → %s" % [ab.get("name", ""), _name(int(a["target"]))]
			return "능력 「%s」" % ab.get("name", "")
		"give_item":
			return "[%s] → %s 건네기" % [game.item_def(str(me["items"][int(a["index"])])).get("name", ""), _name(int(a["to"]))]
		"decoy":
			return "미끼: %s의 경찰을 내 쪽으로" % _name(int(a["from"]))
		"use_spare":
			var v := int(game.team_dice[int(a["die"])]["value"])
			match a["use"]:
				"move": return "예비 %d: 이동 +%d" % [v, v]
				"escape": return "예비 %d: 탈옥에 보탬" % v
				"persuade": return "예비 %d: %s 설득" % [v, _name(int(a["target"]))]
				"reroll": return "예비 %d: 다시 굴림" % v
		"inform":
			return "밀고: %s" % _name(int(a["target"]))
		"scene_check":
			return "장면 판정"
		"scene_pay":
			match a["what"]:
				"die": return "주사위 %d 바치기" % int(game.team_dice[int(a["die"])]["value"])
				"item": return "[%s] 바치기" % game.item_def(str(me["items"][int(a["index"])])).get("name", "")
				"bomb": return "폭탄 바치기"
		"use_intel":
			return "첩보 토큰: 판정 +%d" % int(game.data.rules["intel_token"]["check_bonus"]) if a["mode"] == "check" \
				else "첩보 토큰: 주사위 조건 −%d" % int(game.data.rules["intel_token"]["dice_reduce"])
	return str(a["type"])


# ================================================================ 선택 창

func _show_choice() -> void:
	var pd: Dictionary = game.pending
	var kind: String = pd["kind"]
	if kind in ["pick_cell", "hop"]:
		var cells := []
		for o in pd["options"]:
			if o["value"] is Vector2i:
				cells.append(o["value"])
		_board.pick_cells = cells
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var panel := UiKit.paper_panel(22)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	box.add_child(UiKit.title({"launch_vote": "결행 투표", "saga_keep": "남길 사연", "reroll": "다시 굴리기", "discard": "버릴 아이템"}.get(kind, "선택"), Style.FS_H3))
	box.add_child(UiKit.text(str(pd.get("prompt", "")), Style.FS_BODY))
	if kind in ["pick_cell", "hop"]:
		box.add_child(UiKit.text("보드에서 빨간 점선 칸을 눌러도 됩니다.", 14, Style.INK_3))
	for o in pd["options"]:
		var val = o["value"]
		var label := str(o.get("label", str(val)))
		if kind == "saga_keep":
			var s: Dictionary = game.data.saga(str(val))
			label = "%s — %s" % [s.get("name", ""), s.get("condition_text", "")]
		var b := UiKit.button(label, func():
			_choice.visible = false
			_board.pick_cells = []
			_act({"type": "choose", "value": val}), 16, "paper")
		box.add_child(b)
	if kind == "reroll":
		for a in game.legal_actions():
			if a["type"] == "use_spare" and int(a["player"]) == human:
				var aa: Dictionary = a
				box.add_child(UiKit.button("예비 주사위 %d로 다시 굴리기" % int(game.team_dice[int(a["die"])]["value"]), func():
					_choice.visible = false
					_act(aa), 16, "paper"))
	_choice.show_with(panel)


# ================================================================ 메뉴

func _pause() -> void:
	if _paused:
		return
	_paused = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var panel := UiKit.paper_panel(24)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("일시 정지", Style.FS_H3))
	box.add_child(UiKit.button("계속하기", func():
		_paused = false
		_choice.visible = false
		_after_queue(), 17, "paper"))
	box.add_child(UiKit.button("메인 메뉴로 (이 판은 저장되지 않음)", func():
		_choice.visible = false
		back_to_title.emit(), 17, "paper"))
	_choice.show_with(panel)


func _show_rules() -> void:
	if _paused:
		return
	_paused = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var panel := UiKit.paper_panel(24)
	panel.custom_minimum_size = Vector2(720, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("v2 규칙 요약", Style.FS_H3))
	var lines := [
		"하루: 아침에 위협 카드 → (1막) 결행 투표 → 공개 미션 줄 채우기 → 팀 주사위. 팀 주사위에서 하나씩 골라 오늘 이동으로 씁니다. 남은 주사위는 예비입니다.",
		"차례는 자유 순서입니다. 아직 안 한 사람 중 누구든 합니다. 경찰은 각자 차례 끝에 자기가 쫓는 요원 쪽으로 움직입니다.",
		"1막: 공개 미션을 이뤄 결행 준비를 %d까지 올리면 아침에 결행 투표가 열립니다. 남은 날이 %d일이 되면 강제로 결행합니다." % [int(game.data.rules["launch_min"]), int(game.data.rules["forced_launch_days_left"])],
		"2막: 첩보가 가장 많은 거점을 칩니다. 장면을 하나씩 돌파하고 마지막 장면을 돌파하면 대성공입니다. 첩보는 토큰이 되어 판정 +1 또는 주사위 조건 −2로 씁니다.",
		"개인 사연: 비밀입니다. 이루면 즉시 보상을 받고, 심문 카드를 모두 버린 뒤 더는 받지 않습니다.",
		"심문 카드: 투옥되거나 「회유 공작」에 걸리면 받습니다. 흔들렸다가 2장 이상이면 결행 순간이나 2막 아침에 변절합니다. 같은 칸의 동료가 예비 주사위로 설득하면 한 장을 무작위로 뗍니다.",
	]
	for l in lines:
		box.add_child(UiKit.text("· " + l, 15))
	box.add_child(UiKit.button("닫기", func():
		_paused = false
		_choice.visible = false
		_after_queue(), 17, "paper"))
	_choice.show_with(panel)


# ================================================================ 시험용 조회

func is_idle() -> bool:
	## 연출·AI 대기가 없고 사람 입력을 기다리는 중인가 (tests/v2_ui_test.gd)
	return _started and not _playing and not _ai_waiting and not _paused and game.phase != "over"


func ui_offers(a: Dictionary) -> bool:
	## 이 액션을 사람이 화면에서 할 수 있는가: 보드 클릭 · 주사위 단추 · 선택 창 · 행동 단추
	match a["type"]:
		"step":
			return game.phase == "turn" and game.current == human
		"take_die", "carry_die", "drop_carry", "release_die":
			return _dice_box.get_child_count() > 0
		"choose":
			return _choice.visible or not _board.pick_cells.is_empty()
	for b in _actions.get_children():
		if b is Button and b.text == _label(a):
			return true
	return false


func press_allies_first() -> void:
	_let_allies = true
	_after_queue()


func choose_now(value) -> void:
	_choice.visible = false
	_board.pick_cells = []
	_act({"type": "choose", "value": value})


func act_now(a: Dictionary) -> void:
	_act(a)
