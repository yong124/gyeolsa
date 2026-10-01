class_name GameScreen
extends Control
## 게임 화면: 상단 바 + 보드 + 요원 명부 · 손패 · 행동 · 작전 기록 + 연출 + 오버레이.
##
## 흐름: 엔진에 액션 → 엔진이 쌓은 events를 연출 큐에 넣음 → 하나씩 재생(await)
##      → 큐가 비면 화면을 실제 상태와 맞추고 → 다음 입력(사람) 또는 AI 행동을 기다린다.

signal back_to_title
signal finished            # 작전 종료 → 엔딩 화면으로
signal _popup_closed
signal _tip_closed

const POPUP_TIME := 2.6
const STEP_TIME := 0.16
const GAP := 14.0
const DIR_KEYS := {KEY_UP: Vector2i(0, -1), KEY_DOWN: Vector2i(0, 1),
	KEY_LEFT: Vector2i(-1, 0), KEY_RIGHT: Vector2i(1, 0),
	KEY_W: Vector2i(0, -1), KEY_S: Vector2i(0, 1), KEY_A: Vector2i(-1, 0), KEY_D: Vector2i(1, 0)}

var game: GameRules
var human := 0
var meta := {}             # {"cfg": 새 작전 설정, "tutorial": bool} — 저장·다시 하기에 쓴다
var tutorial := false
var _briefing := true
var _tips_shown := {}
var _paused := false

var _queue: Array = []
var _playing := false
var _ai_busy := false
var _started := false
var _popup_left := 0.0
var _skip_ai := false            # 스페이스로 동료 차례 연출을 건너뛰는 중
var _walk: Array = []            # 목적지 클릭 시 남은 자동 이동 경로
var _vis_cur := -1               # 화면에 보이는 차례 (연출이 엔진 상태보다 늦게 따라간다)

var _board: BoardView
var _frame: PanelContainer
var _right: VBoxContainer
var _top: TopBar
var _agents: AgentPanel
var _hand: HandPanel
var _actions: ActionBar
var _ticker: LogTicker
var _fx: FxLayer
var _choice: Overlay
var _popup: Overlay


func _init(g: GameRules, human_id := 0, meta_info := {}, briefing := true) -> void:
	game = g
	human = human_id
	meta = meta_info
	tutorial = meta.get("tutorial", false)
	_briefing = briefing


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if _hotseat() and not game.cur()["ai"]:
		human = game.current
		_agents.human = human
		_hand.human = human
		_board.human_id = human
	resized.connect(_layout)
	_layout()
	_board.sync_from_game()
	_refresh()
	Music.play("tension" if game.alert_level() >= 3 else "main")
	if game.players[human]["ai"]:
		_begin()          # autoplay: 브리핑 없이 바로
	elif tutorial:
		await _tip("welcome")
		_begin()
	elif _briefing:
		_show_briefing()
	else:
		_fx.toast("작전 재개 — %s" % game.date_label(), "info")
		_begin()


func _begin() -> void:
	_started = true
	_pump()


# ================================================================ 핫시트 · 플레이테스트 기록

var _turn_t0 := -1.0      # 사람 차례에서 조작할 수 있게 된 시각 (생각 시간 측정)
var _turn_pid := -1
var _turn_a0 := 0         # 그 차례가 시작될 때의 액션 수 (되돌리기 횟수 계산)


func _hotseat() -> bool:
	var n := 0
	for p in game.players:
		if not p["ai"]:
			n += 1
	return n > 1


func _set_human(id: int) -> void:
	## 화면의 "나"를 바꾼다 (핫시트)
	human = id
	_agents.human = id
	_hand.human = id
	_board.human_id = id
	var ab := game.ability_def(game.players[id])
	_actions.set_ability(ab.get("name", "능력"), ab.get("desc", ""))
	_refresh()


func _hand_over(id: int, why: String) -> void:
	## 자리 교대: 다음 사람에게 넘기라는 안내 뒤 시점을 바꾼다
	if id == human or game.players[id]["ai"] or not _hotseat():
		return
	_set_human(id)
	await _notice("자리 교대", "%s의 %s입니다.\n\n컴퓨터를 넘겨 주세요." % [game.players[id]["name"], why])


func _log_turn_start() -> void:
	if _turn_t0 < 0.0 and meta.has("playtest") and not game.cur()["ai"] and game.phase in ["start", "move"]:
		_turn_t0 = Time.get_ticks_msec() / 1000.0
		_turn_pid = game.current
		_turn_a0 = game.actions.size()


func _log_turn_end() -> void:
	if _turn_t0 >= 0.0 and meta.has("playtest"):
		var undos := 0
		for i in range(_turn_a0, game.actions.size()):
			if game.actions[i].get("type", "") == "undo_step":
				undos += 1
		PlaytestLog.turn(meta["playtest"], game, _turn_pid, Time.get_ticks_msec() / 1000.0 - _turn_t0, undos)
	_turn_t0 = -1.0


func _process(delta: float) -> void:
	if _popup.visible:
		_popup_left -= delta
		if _popup_left <= 0.0:
			_close_popup()


# ================================================================ 구성

func _build() -> void:
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top = TopBar.new(game, _subtitle())
	_top.menu_pressed.connect(func():
		if _started and not _paused and game.phase != "over":
			_pause())
	add_child(_top)

	_frame = PanelContainer.new()
	var fs := Style.flat(Color("#3b2a1c"), Color("#5a4330"), 2, 3, 9)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 18
	fs.shadow_offset = Vector2(0, 8)
	_frame.add_theme_stylebox_override("panel", fs)
	add_child(_frame)
	_board = BoardView.new()
	_board.cell_clicked.connect(_on_cell)
	_frame.add_child(_board)
	_board.setup(game, human)

	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", int(GAP))
	add_child(_right)
	_agents = AgentPanel.new(game, human)
	_right.add_child(_agents)
	_hand = HandPanel.new(game, human)
	_hand.use_item.connect(func(i): _act({"type": "use_item", "index": i}))
	_right.add_child(_hand)
	_actions = ActionBar.new()
	_right.add_child(_actions)
	var ab := game.ability_def(game.players[human])
	_actions.set_ability(ab.get("name", "능력"), ab.get("desc", ""))
	_actions.primary.connect(_on_primary)
	_actions.undo.connect(func(): _act({"type": "undo_step"}))
	_actions.ability.connect(func(): _act({"type": "ability"}))
	_actions.give.connect(_on_give)
	_actions.decoy.connect(func():
		if game.players[human]["traitor"]:
			_on_inform()
		else:
			_on_decoy())
	_actions.swap.connect(_on_swap)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(sp)
	_ticker = LogTicker.new(game)
	_right.add_child(_ticker)
	add_child(_ticker.drawer)

	_fx = FxLayer.new()
	add_child(_fx)
	_choice = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	add_child(_choice)
	_popup = Overlay.new(Color(0.03, 0.02, 0.01, 0.45))
	_popup.clicked.connect(_close_popup)
	add_child(_popup)


func _subtitle() -> String:
	if tutorial:
		return ("2막 훈련" if meta.get("tutorial_id", "") == "tutorial2" else "훈련") + " · %d인" % game.players.size()
	var cfg: Dictionary = meta.get("cfg", {})
	var sc: String = cfg.get("scenario", "")
	if sc == "daily":
		return "오늘의 작전 · %s" % cfg.get("date", "")
	if sc != "":
		return "%s · %d인" % [game.data.special_op(sc).get("name", sc), game.players.size()]
	var diff: int = cfg.get("difficulty", 0)
	return "%d인 · %s" % [game.players.size(), {1: "쉬움", 0: "보통", -1: "어려움"}.get(diff, "보통")]


func _layout() -> void:
	## 창 크기에 맞춰 배치: 보드는 정사각형으로 왼쪽, 나머지는 오른쪽 열
	var w := size.x
	var h := size.y
	_top.position = Vector2(20, 10)
	_top.size = Vector2(w - 40, 56)
	var top_y := 80.0
	var side := floorf(minf(h - top_y - 12, w * 0.54))
	_frame.position = Vector2(20, top_y)
	_frame.size = Vector2(side, side)
	var rx := 20 + side + 24
	_right.position = Vector2(rx, top_y + 4)
	_right.size = Vector2(w - rx - 20, h - top_y - 16)
	var dy := top_y + 4 + h * 0.2
	_ticker.drawer.position = Vector2(rx, dy)
	_ticker.drawer.size = Vector2(w - rx - 20, h - 16 - 38 - 10 - dy)
	_fx.focus_center = _frame.position + _frame.size / 2.0
	_fx.board_rect = Rect2(_frame.position, _frame.size)


# ================================================================ 진행

func _act(a: Dictionary) -> void:
	if not _started or _playing or _paused or game.phase == "over" or _popup.visible:
		return
	if game.current != human and a["type"] != "choose":
		return
	Sfx.play("click")
	if game.apply(a):
		_pump()


func _on_primary() -> void:
	var me: Dictionary = game.players[human]
	if game.can_strike(me):
		_act({"type": "strike"})
		return
	if game.phase == "start":
		_act({"type": "escape" if me["jailed"] else "roll"})
	elif game.phase == "move":
		_request_end_move()


func _request_end_move() -> void:
	if game.steps_left <= 0:
		_act({"type": "end_move"})
		return
	_show_local_choice("이동 종료", "이동이 %d칸 남았습니다. 지금 차례를 마칠까요?" % game.steps_left,
		[{"label": "이동 종료", "action": {"type": "end_move"}}])


func _on_swap() -> void:
	## 보조 버튼 자리: 결행 판정을 할 수 있을 때 "주사위로 이동"(갇혀 있으면 탈옥)
	var me: Dictionary = game.players[human]
	if game.can_strike(me):
		_act({"type": "escape" if me["jailed"] else "roll"})


func _pump() -> void:
	## 엔진 이벤트를 연출 큐로 옮기고, 재생 중이 아니면 재생을 시작한다.
	for e in game.events:
		if e["kind"] == "reveal":
			_board.hidden_tiles[e["pos"]] = true
		if e["kind"] == "turn" or e["kind"] == "over":
			_log_turn_end()
		if e["kind"] == "turn" and game.players[e["player"]]["ai"]:
			e["intent"] = GameAI.intent(game, game.players[e["player"]])
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
	_set_vis_cur(game.current)
	_board.sync_from_game()
	_board.interactive = true
	_refresh()
	_after_queue()


func _after_queue() -> void:
	if not _ai_to_move():
		_skip_ai = false
	if not _walk.is_empty():
		if game.phase == "move" and game.current == human:
			_walk_next()
			return
		_walk.clear()
	if tutorial and game.current == human and game.phase in ["start", "move"]:
		await _tutorial_after_queue()
	_log_turn_start()
	if game.phase == "over":
		_finish_game()
	elif _ai_to_move():
		_schedule_ai()
	elif game.phase == "choice":
		_show_choice()


func _mult_for(e: Dictionary) -> float:
	## 내 행동은 항상 보통 속도로, 동료 행동은 설정 속도로 (스페이스를 누르면 즉시)
	var pid: int = e.get("player", game.current)
	if pid >= 0 and pid < game.players.size() and not game.players[pid]["ai"]:
		return Prefs.my_mult()
	if _skip_ai:
		return 0.0
	return Prefs.mult() * (0.5 if e["kind"] == "move" else 1.0)


func _board_pos(c: Vector2i) -> Vector2:
	## 보드 칸 중심의 이 화면 기준 좌표
	return _board.cell_center(c) + _board.global_position - global_position


func _play_event(e: Dictionary) -> void:
	var m := _mult_for(e)
	match e["kind"]:
		"turn":
			_set_vis_cur(e["player"])
			_refresh()
			var p: Dictionary = game.players[e["player"]]
			if p["ai"]:
				await _fx.bubble(_board_pos(e["players_snap"][p["id"]]["pos"]), "%s: %s" % [p["name"].split(" (")[0], e.get("intent", "")], Style.seat(p["id"]), m)
			else:
				_skip_ai = false
				await _hand_over(p["id"], "차례")
				Sfx.play("card", 0.0, 0.6)
				await _fx.banner("당신의 차례" if not _hotseat() else "%s의 차례" % p["name"].split(" (")[0], "turn", 1.0, "")
		"move":
			Sfx.play("step", 0.15)
			var dur := STEP_TIME * m * (2.0 if e.get("teleport", false) else 1.0)
			await _board.animate_move(e["player"], e["from"], e["to"], dur)
		"reveal":
			Sfx.play("flip", 0.1)
			await _board.reveal(e["pos"], 0.28 * m)
			if e["tile"] == "check":
				Sfx.play("alert", 0.0, 0.5)
			if tutorial:
				await _tip("reveal")
		"dice":
			if tutorial and e.has("target") and e.get("player", game.current) == human:
				await _tip("judge")
			var roller: int = _vis_cur if _vis_cur >= 0 else game.current
			if e.has("target") or not game.players[roller]["ai"]:
				await _fx.roll_dice(e, m)
		"banner":
			var who := ""
			if e["player"] >= 0:
				who = game.players[e["player"]]["name"].split(" (")[0] + ": "
			match e["tone"]:
				"good": Sfx.play("success")
				"bad": Sfx.play("fail")
				_: Sfx.play("card", 0.0, 0.5)
			if e["tone"] == "bad" and m > 0.0:
				_fx.alarm(m)
			if e["tone"] == "good":
				_fx.paper_burst(_board_pos(e["players_snap"][e["player"]]["pos"]) if e["player"] >= 0 else _fx.focus_center, m)
			await _fx.banner(e["text"], e["tone"], m, who.trim_suffix(": "))
		"score":
			Sfx.play("score")
			var from := _fx.focus_center
			if e.has("player") and e["player"] >= 0 and e.has("players_snap"):
				from = _board_pos(e["players_snap"][e["player"]]["pos"])
			var prev := roundi(_top._shown_score)
			var d := maxf(m, 0.3)
			for i in range(prev, mini(e["score"], game.goal)):
				_fx.fly(from, _top.pip_center(i) - global_position, Style.SEAL, 0.55 * d)
			await get_tree().create_timer(0.45 * d).timeout
			await _top.animate_score(e["score"], 0.35 * d)
			await _fx.banner(("결행 준비 %d" % e["score"]) if game.two_act() else ("광복수치 %d / %d" % [e["score"], game.goal]), "good", m * 0.8)
			if tutorial:
				await _tip("score")
		"intel":
			# 첩보: 요원 자리에서 거점으로 붉은 점이 날아간다
			if m > 0.0 and e.has("players_snap") and e.get("player", -1) >= 0:
				_fx.fly(_board_pos(e["players_snap"][e["player"]]["pos"]), _board_pos(game.data.bases[e["base"]]), Style.SEAL, 0.5 * m)
				await get_tree().create_timer(0.45 * m).timeout
			_board.queue_redraw()
			if tutorial:
				await _tip("intel")
		"traitor":
			var tp: Dictionary = game.players[e["player"]]
			Sfx.play("alert")
			if m > 0.0:
				_fx.alarm(maxf(m, 0.8))
				await _fx.stamp_at(_board_pos(e["players_snap"][tp["id"]]["pos"]), "변 절", Style.INK, maxf(m, 0.8))
			_agents.refresh(_vis_cur)
			if e["player"] == human and not game.players[human]["ai"]:
				await _notice("변절", "당신은 옥중에서 일제에 회유되었습니다.\n\n이제 당신의 목표는 결행을 막는 것입니다. 요원이 있는 칸에 들어가 기습 체포하고, [밀고]로 가까운 요원에게 경찰을 붙이십시오. 8월 15일까지 버티면 당신이 이깁니다.")
		"exposure", "strike_progress":
			if e["kind"] == "strike_progress":
				Sfx.play("score")
			_top.refresh()
			if tutorial:
				await _tip(e["kind"])
		"catch":
			Sfx.play("whistle")
			if m > 0.0:
				_fx.alarm(m)
			await _board.animate_police(e["police_snap"], 0.3 * m)
		"jail":
			_board.apply_players_snap(e["players_snap"])
			await _board.animate_move(e["player"], e["from"], e["to"], 0.35 * m)
			if m > 0.0:
				await _shake_board(m)
				await _fx.stamp_at(_board_pos(e["to"]), "투 옥", Style.SEAL, m)
			if tutorial:
				await _tip("jail")
		"day":
			_top.refresh()
			var de := e.duplicate()
			de["dispatch"] = _dispatch()
			var dd := game.date_of(int(e["days_left"]))
			de["month_label"] = "%d월" % dd.x
			de["day_num"] = dd.y
			await _fx.day(de, Prefs.mult() if Prefs.mult() > 0 else 0.5)
			_top.refresh()
			if e["alert"] >= 3:
				Music.play("tension")
			if meta.has("playtest"):
				PlaytestLog.day(meta["playtest"], game)
			if tutorial:
				await _tip("day")
			elif not game.players[human]["ai"]:
				SaveGame.write(game, meta)   # 매일 아침 자동 저장
		"card":
			await _show_card(e, m)
			if e["deck"] in ["occupation", "strike"]:
				_top.refresh()
			if tutorial and e["deck"] == "strike":
				await _tip("strike")
			if tutorial and e["player"] == human:
				await _tip("card")
		_:
			pass
	# 모든 이벤트 뒤: 경찰 위치를 그 시점 스냅숏으로 맞춘다
	if e.has("police_snap") and _board.police_changed(e["police_snap"]):
		if e["kind"] != "catch":
			Sfx.play("whistle", 0.1, 0.35)
		await _board.animate_police(e["police_snap"], 0.25 * m)
		if tutorial and e["police_snap"].has(human):
			await _tip("police")
	if e.has("players_snap"):
		_board.apply_players_snap(e["players_snap"])
	_ticker.refresh()


func _dispatch() -> String:
	## 아침 무전: 오늘의 일제 동향에 맞는 한 줄 (같은 날에는 같은 줄)
	var d: Dictionary = game.data.text.get("dispatches", {})
	var pool: Array = d.get("strike", []) if game.act == 2 else d.get(game.today_occupation(), d.get("default", []))
	if pool.is_empty():
		return ""
	return pool[game.rounds_left % pool.size()]


func _ai_to_move() -> bool:
	if game.phase == "over":
		return false
	if game.phase == "choice":
		return game.players[game.pending["player"]]["ai"]
	return game.cur()["ai"]


func _shake_board(mult: float) -> void:
	var origin := _frame.position
	var tw := create_tween()
	for offset in [Vector2(8, 0), Vector2(-7, 2), Vector2(5, -2), Vector2.ZERO]:
		tw.tween_property(_frame, "position", origin + offset * mult, 0.045 * mult)
	await tw.finished


func _schedule_ai() -> void:
	if _ai_busy:
		return
	_ai_busy = true
	var delay := 0.025 if game.phase == "move" else 0.1
	await get_tree().create_timer(delay + 0.1 * Prefs.mult()).timeout
	_ai_busy = false
	if _playing or _popup.visible or _paused or not _ai_to_move():
		return
	var a := GameAI.decide(game)
	if not game.apply(a):
		push_warning("AI 액션 거부: %s (phase=%s)" % [a, game.phase])
	_pump()


func _on_cell(c: Vector2i) -> void:
	if _playing or game.current != human or game.phase != "move":
		return
	var me: Dictionary = game.players[human]
	if game.can_step(me, c):
		_walk.clear()
		_act({"type": "step", "to": c})
		return
	# 먼 칸을 누르면 미리보기 경로를 따라 한 칸씩 자동으로 걷는다
	var path := _board.preview_path()
	if not path.is_empty() and path[-1] == c:
		_walk = path.duplicate()
		_walk_next()


func _walk_next() -> void:
	var me: Dictionary = game.players[human]
	var nxt: Vector2i = _walk.pop_front()
	if game.can_step(me, nxt):
		_act({"type": "step", "to": nxt})
	else:
		_walk.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _started and game.phase != "over":
		if _ticker.drawer.visible:
			_ticker.toggle()
		elif _paused:
			_resume()
		else:
			_pause()
		return
	if event.keycode == KEY_SPACE and _started and (_playing or _ai_to_move()) and not _skip_ai:
		if game.phase == "over" or game.cur()["ai"] or _ai_to_move():
			_skip_ai = true
			_close_popup()
			return
	if not _started or _playing or game.current != human or _popup.visible or _choice.visible:
		return
	if game.phase == "move" and DIR_KEYS.has(event.keycode):
		var to: Vector2i = game.players[human]["pos"] + DIR_KEYS[event.keycode]
		if game.can_step(game.players[human], to):
			_act({"type": "step", "to": to})
	elif event.keycode == KEY_SPACE:
		if game.can_strike(game.players[human]):
			_act({"type": "strike"})
		elif game.phase == "start" and not game.players[human]["jailed"]:
			_act({"type": "roll"})
		elif game.phase == "move":
			_request_end_move()
	elif event.keycode == KEY_BACKSPACE and game.phase == "move" and game.can_undo_step():
		_act({"type": "undo_step"})


# ================================================================ 갱신

func _refresh() -> void:
	_board.queue_redraw()
	_top.refresh()
	_agents.refresh(_vis_cur)
	_refresh_actions()
	_ticker.refresh()


func _set_vis_cur(id: int) -> void:
	_vis_cur = id
	_board.vis_current = id


func _my_turn() -> bool:
	return _started and not _playing and game.current == human and game.phase in ["start", "move"]


func _refresh_actions() -> void:
	var me: Dictionary = game.players[human]
	var my_turn := _my_turn()
	_hand.refresh(my_turn)
	var s := {
		"ability_on": my_turn and game.can_use_ability(me),
		"ability_used": me["ability_day"] == game.rounds_left,
		"give_on": my_turn and not game.give_options(me).is_empty(),
		"decoy_on": my_turn and (not game.inform_options(me).is_empty() if me["traitor"] else not game.decoy_options(me).is_empty()),
		"decoy_label": "밀고" if me["traitor"] else "미끼",
		"swap_on": false,
		"swap_visible": false,   # 이 자리는 결행 판정 때 "주사위로 이동"으로만 쓴다 (미션 교체는 자동)
	}
	var shown := _vis_cur if _vis_cur >= 0 else game.current
	if game.phase == "over":
		s.merge({"doing": "작전 종료", "primary_text": "작전 종료", "primary_on": false}, true)
	elif _playing and shown != human:
		s.merge({"doing": "%s의 차례" % game.players[shown]["name"].split(" (")[0],
			"hint": "Space를 누르면 동료 차례를 빨리 넘깁니다", "primary_text": "동료 차례", "primary_on": false}, true)
	elif not _playing and (game.current != human or game.phase == "choice" and game.pending.get("player", -1) != human):
		var who: String = game.cur()["name"].split(" (")[0]
		s.merge({"doing": "%s의 차례" % who, "hint": "Space를 누르면 동료 차례를 빨리 넘깁니다",
			"primary_text": "동료 차례", "primary_on": false})
	elif _playing:
		s.merge({"doing": "진행 중", "primary_text": "…", "primary_on": false}, true)
	else:
		match game.phase:
			"start":
				if game.can_strike(me):
					s.merge({"doing": "결행", "hint": game.strike_goal_text(), "primary_text": "결행 판정",
						"primary_icon": "dice", "primary_on": true, "key": true,
						"swap_on": true, "swap_visible": true, "swap_label": "탈옥 시도" if me["jailed"] else "주사위로 이동"}, true)
				elif me["jailed"]:
					s.merge({"doing": "감옥", "hint": _jail_hint(me), "primary_text": "탈옥 시도",
						"primary_icon": "escape", "primary_on": true})
				else:
					var found := "" if not game.mission_targets(me).is_empty() else " · 목표 미발견: 새 길을 열어 찾으세요"
					if me["traitor"]:
						found = " · 변절자: 요원을 기습하거나 밀고해 8월 15일까지 결행을 막으십시오"
					elif game.act == 2:
						found = " · " + game.strike_goal_text()
					s.merge({"doing": "내 차례", "hint": "주사위를 굴려 이동하세요%s" % found,
						"primary_text": "주사위 굴리기", "primary_icon": "dice", "primary_on": true, "key": true})
			"move":
				s.merge({"doing": "이동 중", "hint": "남은 %d칸 · 칸을 누르면 경로를 따라 자동 이동 · 붉은 빗금 = 체포 위험" % game.steps_left,
					"primary_text": "이동 종료", "primary_icon": "end", "primary_on": true, "key": true,
					"steps": game.steps_left, "steps_max": maxi(game.steps_left, _roll_total()),
					"undo_on": game.can_undo_step()})
			"choice":
				s.merge({"doing": "선택", "hint": "선택하세요", "primary_text": "선택 중", "primary_on": false}, true)
	_actions.refresh(s)


func _roll_total() -> int:
	var t := 0
	for v in game.last_roll:
		t += int(v)
	return t


func _jail_hint(me: Dictionary) -> String:
	var near := 99
	for q in game.players:
		if q["id"] != human and not q["jailed"] and q["started"]:
			near = mini(near, absi(q["pos"].x - me["pos"].x) + absi(q["pos"].y - me["pos"].y))
	return "탈옥 확률 %d%%%s · 가장 가까운 동료 %s칸 (동료가 거점에 들어오면 구출)" % [
		roundi(game.escape_chance(me) * 100), " · 옷핀으로 즉시 탈옥 가능" if game.has_item(me, "pin") else "",
		str(near) if near < 99 else "-"]


# ================================================================ 튜토리얼

func _tip(id: String) -> void:
	## 튜토리얼 안내 창 (같은 안내는 한 번만)
	if not tutorial or _tips_shown.has(id):
		return
	var text: String = game.data.text[meta.get("tutorial_id", "tutorial")]["tips"].get(id, "")
	if text == "":
		return
	_tips_shown[id] = true
	var d := UiKit.dossier(600, "", "훈 련 교 관")
	var v: VBoxContainer = d[1]
	v.add_child(UiKit.text(text, Style.FS_LEAD, Style.INK))
	var ok := UiKit.button("알겠습니다", func():
		_choice.visible = false
		_tip_closed.emit(), 18, "primary")
	ok.custom_minimum_size = Vector2(0, 50)
	v.add_child(ok)
	Sfx.play("card", 0.0, 0.6)
	_choice.show_with(d[0])
	await _tip_closed


func _tutorial_after_queue() -> void:
	var me: Dictionary = game.players[human]
	if game.phase == "start":
		await _tip("roll")
		if game.rounds_left < game.rounds_total and game.can_use_ability(me):
			await _tip("ability")
	elif game.phase == "move":
		await _tip("move")
	if not game.mission_targets(me).is_empty() and me["mission"].get("type", "") == "assassin":
		await _tip("target")
	if game.can_strike(me):
		await _tip("strike_turn")


# ================================================================ 일시정지 · 종료

func _pause() -> void:
	_paused = true
	get_tree().paused = false   # 연출 트윈은 멈추지 않고, 입력만 막는다
	var d := UiKit.dossier(440, "일시정지", "작 전 중 단")
	var v: VBoxContainer = d[1]
	v.add_child(UiKit.text("%s · 광복 %d/%d · 남은 %d일" % [game.date_label(), game.score, game.goal, game.rounds_left], 15, Style.INK_3, false))
	v.add_child(UiKit.hsep())
	for b in [
		["계속하기", _resume],
		["설정", func():
			var sp := SettingsPanel.new()
			sp.closed.connect(_pause)
			_choice.show_with(sp)],
		["규칙 도감", func():
			var r := Rulebook.new(game.data)
			r.closed.connect(_pause)
			_choice.show_with(r)],
		["저장하고 메인 메뉴로" if not tutorial else "튜토리얼 그만두기", func():
			if not tutorial:
				SaveGame.write(game, meta)
			if meta.has("playtest"):
				PlaytestLog.finish(meta["playtest"], game, "paused")
			back_to_title.emit()],
	]:
		var btn := UiKit.button(b[0], b[1], 20, "tab")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 46)
		v.add_child(btn)
	_choice.show_with(d[0])


func _resume() -> void:
	_paused = false
	_choice.visible = false
	_after_queue_if_idle()


func _after_queue_if_idle() -> void:
	if not _playing:
		_after_queue()


func _finish_game() -> void:
	if not tutorial:
		SaveGame.erase()
	if tutorial:
		await _tip("done")
	Sfx.play("score" if game.ending["id"] == "victory" else "day")
	await _fx.banner(game.ending["name"], "good" if game.ending["id"] == "victory" else "info", 1.4)
	finished.emit()


# ================================================================ 오버레이

func _show_briefing() -> void:
	var me: Dictionary = game.players[human]
	var f := game.data.faction(me["faction"])
	var d := UiKit.dossier(760, "%s, 경성" % game.date_label(), "작 전 브 리 핑")
	var p: PanelContainer = d[0]
	var v: VBoxContainer = d[1]
	var stamp := UiKit.stamp("極 秘", 22, Style.SEAL, -10)
	p.add_child(stamp)
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_END
	stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.add_child(UiKit.text(game.data.text["background"], 15, Style.INK_2))
	v.add_child(UiKit.hsep())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var rows := [
		["목표", "8월 15일 일본이 항복하기 전에 광복수치 %d 채우기 (남은 %d일)" % [game.goal, game.rounds_left]] if not game.two_act() else
			["목표", "1막에 거점 첩보와 광복수치(%d 이상)를 모아 결행하고, 8월 15일 전에 결행 목표를 달성하기 (남은 %d일)" % [game.launch_min(), game.rounds_left]],
		["변절", "결행하는 순간, 가장 많이 투옥된 요원이 일제에 회유되어 변절합니다. 변절자는 결행을 막으려 합니다"] if game.traitor_mode() else ["", ""],
		["당신", "%s — %s" % [f["name"], f["ability"]]],
		["세력 능력", "%s — %s (하루 1회)" % [f.get("active", {}).get("name", "-"), f.get("active", {}).get("desc", "")]],
		["첫 미션", game.mission_label(me["mission"])],
		["동지", ", ".join(game.players.filter(func(q): return q["id"] != human).map(func(q): return q["name"]))],
		["조작", "주사위 → 금색 칸 클릭(또는 방향키). 스페이스로 주사위·이동 종료. ESC 일시정지"],
	]
	for r in rows:
		if r[0] == "":
			continue
		var k := UiKit.title(r[0], 15, Style.SEAL if r[0] == "목표" else Style.INK_2, 800)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(k)
		var t := UiKit.text(r[1], 15, Style.INK)
		t.custom_minimum_size = Vector2(620, 0)
		grid.add_child(t)
	var go := UiKit.button("작전 개시", func():
		_choice.visible = false
		Sfx.play("day")
		_begin(), 24, "primary")
	go.custom_minimum_size = Vector2(0, 58)
	v.add_child(go)
	_choice.show_with(p)


func _on_give() -> void:
	var opts := []
	for o in game.give_options(game.players[human]):
		opts.append({"label": o["label"], "action": {"type": "give_item", "index": o["index"], "to": o["to"]}})
	_show_local_choice("아이템 건네기", "누구에게 어떤 아이템을 건넬까요?", opts)


func _on_decoy() -> void:
	var opts := []
	for o in game.decoy_options(game.players[human]):
		opts.append({"label": o["label"], "action": {"type": "decoy", "from": o["from"]}})
	_show_local_choice("미끼", "어느 경찰을 내 쪽으로 끌어올까요?", opts)


func _choice_panel(heading: String, prompt: String) -> Array:
	var d := UiKit.dossier(500, heading, "선 택")
	var v: VBoxContainer = d[1]
	if prompt != "" and prompt != heading:
		v.add_child(UiKit.text(prompt, 16, Style.INK_2))
	return d


func _option_button(v: VBoxContainer, text: String, desc: String, cb: Callable) -> void:
	var b := UiKit.button(text, cb, 17, "paper")
	b.custom_minimum_size = Vector2(0, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(b)
	if desc != "":
		var l := UiKit.text(desc, 13, Style.INK_3)
		l.custom_minimum_size = Vector2(480, 0)
		var m := UiKit.margin(0)
		m.add_theme_constant_override("margin_left", 16)
		m.add_theme_constant_override("margin_top", -6)
		m.add_child(l)
		v.add_child(m)


func _on_inform() -> void:
	var opts := []
	for o in game.inform_options(game.players[human]):
		opts.append({"label": o["label"], "action": {"type": "inform", "target": o["target"]}})
	_show_local_choice("밀고", "누구의 행방을 헌병대에 알릴까요? (그 요원에게 경찰이 붙습니다)", opts)


signal _notice_closed
var _noticing := false


func _notice(heading: String, body: String) -> void:
	## 확인 버튼 하나짜리 안내 창
	_noticing = true
	var d := UiKit.dossier(560, heading, "통 보")
	var v: VBoxContainer = d[1]
	v.add_child(UiKit.text(body, 17, Style.INK))
	var ok := UiKit.button("알겠습니다", func():
		_choice.visible = false
		_notice_closed.emit(), 18, "primary")
	ok.custom_minimum_size = Vector2(0, 48)
	v.add_child(ok)
	_choice.show_with(d[0])
	await _notice_closed
	_noticing = false


func _show_local_choice(heading: String, prompt: String, opts: Array) -> void:
	## 엔진 선택지가 아닌, 화면에서만 고르는 목록 (고르면 해당 액션 실행)
	if opts.is_empty():
		return
	var d := _choice_panel(heading, prompt)
	var v: VBoxContainer = d[1]
	for o in opts + [{"label": "취소", "action": {}}]:
		var a: Dictionary = o["action"]
		_option_button(v, o["label"], "", func():
			_choice.visible = false
			if not a.is_empty():
				_act(a))
	_choice.show_with(d[0])


func _show_choice() -> void:
	var titles := {"launch_vote": "결행 투표", "strike_target": "결행 목표 선택"}
	var kind: String = game.pending["kind"]
	await _hand_over(int(game.pending["player"]), "결행 투표 차례" if kind == "launch_vote" else "선택")
	if tutorial and kind == "launch_vote":
		await _tip("vote")
	var d := _choice_panel(titles[kind], game.pending["prompt"]) if titles.has(kind) else _choice_panel(game.pending["prompt"], "")
	var v: VBoxContainer = d[1]
	for o in game.pending["options"]:
		var val = o["value"]
		_option_button(v, o["label"], _option_desc(game.pending, o), func():
			_choice.visible = false
			_act({"type": "choose", "value": val}))
	_choice.show_with(d[0])


func _option_desc(pd: Dictionary, o: Dictionary) -> String:
	## 선택지를 고르면 어떻게 되는지 한 줄 요약
	var p: Dictionary = game.players[pd["player"]]
	var val = o["value"]
	match pd["kind"]:
		"react_evade":
			return "회피 100%% 성공 (아이템 소모)" if val else "주사위 판정 · 성공 확률 %d%%" % roundi(game.evade_chance(p) * 100)
		"react_event":
			return "이 이벤트를 무시합니다 (신호탄 소모)" if val else game.event_def(game.current_event()).get("effect_text", "")
		"discard":
			if int(val) < p["items"].size():
				return game.item_def(p["items"][int(val)]).get("effect_text", "")
		"launch_vote":
			return ("2막 시작 — 지금의 경계 %d단계가 2막 내내 이어집니다%s" % [game.alert_level(),
				"" if game.alert_level() <= 1 else " (경비가 삼엄해 결행 판정이 어려워짐)"]) if val \
				else "하루 더 정찰해 첩보를 모읍니다. 8월 13일 아침에는 반드시 결행합니다"
		"strike_target":
			var sd := game.strike_for_base(int(val))
			var info: Dictionary = game.data.text["strikes"].get(sd.get("id", ""), {})
			return "%s (%s %d)" % [info.get("brief", ""), "첩보", int(game.intel[int(val)])]
		"ability_target":
			if int(val) >= 0 and game.ability_def(p).get("target", "") != "police_near":
				return "미션: %s" % game.mission_label(game.players[int(val)]["mission"])
	return ""


func _show_card(e: Dictionary, m: float = 1.0) -> void:
	var who := "경성 전역"
	var slow := true
	if e["player"] >= 0:
		var owner: Dictionary = game.players[e["player"]]
		who = owner["name"]
		slow = not owner["ai"]
	if not slow and m <= 0.0:
		return
	Sfx.play("alert" if e["deck"] == "occupation" else "card")
	var card := CardView.build(game, e["deck"], e["id"], who)
	_popup.show_with(card)
	card.pivot_offset = Vector2(180, 250)
	card.scale = Vector2(0.6, 0.6)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel()
	tw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	_popup_left = POPUP_TIME * 1.6 if slow else POPUP_TIME * maxf(m, 0.5)
	await _popup_closed
	if e["deck"] == "strike":
		# 결행 사건은 상단 바 "결행 목표"로 날아가 남는다
		_top.refresh()
		await _fx.fly_card(size / 2.0, _top.today_center() - global_position, game.data.text["strikes"][e["id"]]["name"], 0.5)
	elif e["deck"] == "occupation" and m > 0.0:
		# 일제 동향은 상단 바 "오늘의 일제 동향"으로 날아가 남는다
		await _fx.fly_card(size / 2.0, _top.today_center() - global_position, game.data.occupation(e["id"])["name"], 0.45 * maxf(m, 0.5))
	elif e["deck"] == "item" and e["player"] == human and m > 0.0:
		await _fx.fly_card(size / 2.0, _hand.global_position + Vector2(_hand.size.x * 0.45, 110) - global_position,
			game.item_def(e["id"])["name"], 0.4)


func _close_popup() -> void:
	if _popup.visible:
		_popup.visible = false
		_popup_closed.emit()
