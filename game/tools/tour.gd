extends Node
## 화면 둘러보기 캡처 (개발용, 빌드에서 제외). 실제 저장 파일은 건드리지 않는다.
## 실행: godot --path game --position -3000,-3000 -- tour out=<폴더> [w=1600 h=900]
## 메뉴 → 새 작전 설정 → 규칙 도감 → 브리핑 → 내 차례(주사위·경로 미리보기) → 동료 차례들 → 일시정지 → 엔딩 → 보고서

var main: Node
var out := "user://tour"
var _n := 0


func _ready() -> void:
	main = get_parent()
	SaveGame.disabled = true
	SaveGameV2.disabled = true
	Records.disabled = true
	PlaytestLog.disabled = true
	var w := 1600
	var h := 900
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("w="):
			w = int(a.substr(2))
		elif a.begins_with("h="):
			h = int(a.substr(2))
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(w, h)
	Prefs.speed = 1
	if "store" in OS.get_cmdline_user_args():
		_store()
	elif "survey" in OS.get_cmdline_user_args():
		await _wait(0.5)
		main._swap(SurveyScreen.new({"survey": [], "file": "x.json"}, [{"id": 0, "name": "1번 요원 (한국광복군)"}, {"id": 1, "name": "2번 요원 (조선의용대)"}]))
		await _wait(0.8)
		await _shot("survey")
		get_tree().quit()
	elif "hot" in OS.get_cmdline_user_args():
		_hot()
	elif "tut2" in OS.get_cmdline_user_args():
		_tut2()
	elif "online" in OS.get_cmdline_user_args():
		_online()
	elif "gif" in OS.get_cmdline_user_args():
		_gif()
	elif "gate" in OS.get_cmdline_user_args():
		await _wait(0.5)
		main._web_gate()   # 웹 첫 화면 (데스크톱에서 미리 보기)
		await _wait(0.8)
		await _shot("web_gate")
		get_tree().quit()
	elif "measure" in OS.get_cmdline_user_args():
		_measure()
	elif "perf" in OS.get_cmdline_user_args():
		_perf()
	elif "endings" in OS.get_cmdline_user_args():
		_endings()
	elif "fx" in OS.get_cmdline_user_args():
		_fxshots()
	elif "q" in OS.get_cmdline_user_args():
		_q()
	elif "v2f" in OS.get_cmdline_user_args():
		_v2f()
	elif "v2" in OS.get_cmdline_user_args():
		_v2()
	elif "act2" in OS.get_cmdline_user_args():
		_act2()
	else:
		_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, _n, name])
	print("[tour] %02d_%s" % [_n, name])


func title_defs(n: int) -> Array:
	var keys: Array = main.data.faction_keys()
	var defs := []
	for i in n:
		var f: String = keys[i % keys.size()]
		defs.append({"name": ("나" if i == 0 else "동지 %d" % i) + " (%s)" % main.data.faction(f)["name"], "faction": f, "ai": i > 0})
	return defs


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _until(cond: Callable, limit := 20.0) -> bool:
	var t := 0.0
	while not cond.call():
		await _wait(0.1)
		t += 0.1
		if t > limit:
			return false
	return true


func _run() -> void:
	await _wait(0.8)
	main._show_title()
	await _wait(1.2)
	await _shot("title")
	var title: TitleScreen = main._screen
	var defs: Array = title.make_players(4, 0)
	title._show_setup()
	await _wait(0.5)
	await _shot("setup")
	title._show_special()
	await _wait(0.4)
	await _shot("special")
	title._show_op(main.data.special_ops()[2])
	await _wait(0.4)
	await _shot("special_op")
	title._show_daily()
	await _wait(0.4)
	await _shot("daily")
	title._show_records()
	await _wait(0.4)
	await _shot("records")
	title._show_menu()
	await _wait(0.3)
	await _shot("menu")
	title._show_rulebook()
	await _wait(0.5)
	await _shot("rulebook")
	title._overlay.visible = false

	# 사람 자리로 한 판 (브리핑 → 내 차례)
	var game := GameRules.new()
	game.setup(defs.duplicate(true), 7, main.data)
	main._open_game(game, {"cfg": {"defs": defs, "difficulty": 0}, "tutorial": false}, true)
	await _wait(1.0)
	await _shot("briefing")
	var gs: GameScreen = main._screen
	gs._choice.visible = false
	gs._begin()
	var idle := func(): return not gs._playing and gs._queue.is_empty()
	await _until(func(): return idle.call() and game.current == 0 and game.phase == "start")
	await _wait(0.3)
	await _shot("my_turn_start")
	# 아이템 카드 (쓸 수 있는 카드는 빛난다) · 튜토리얼 안내 · 선택 창
	game.players[0]["items"] = ["ticket", "scope"]
	gs._refresh()
	await _wait(0.3)
	await _shot("hand_items")
	gs.tutorial = true
	gs._tip("move")
	await _wait(0.4)
	await _shot("tip")
	gs._choice.visible = false
	gs._tip_closed.emit()
	gs.tutorial = false
	gs._show_local_choice("미끼", "어느 경찰을 내 쪽으로 끌어올까요?", [{"label": "동지 1을 쫓는 경찰 (2칸)", "action": {}}, {"label": "동지 3을 쫓는 경찰 (3칸)", "action": {}}])
	await _wait(0.3)
	await _shot("choice")
	gs._choice.visible = false
	game.players[0]["items"] = []
	gs._refresh()
	gs._act({"type": "roll"})
	await _until(func(): return idle.call() and game.phase == "move")
	await _wait(0.2)
	# 가장 먼 도달 가능 칸에 마우스를 올린 상태
	var best := Vector2i(-1, -1)
	var best_d := -1
	for x in main.data.size:
		for y in main.data.size:
			var pr := game.path_to(game.players[0], Vector2i(x, y))
			if not pr.is_empty() and pr["reachable"] and pr["steps"] > best_d:
				best_d = pr["steps"]
				best = Vector2i(x, y)
	if best.x >= 0:
		gs._board.hover = best
		gs._board._update_preview()
		gs._board.queue_redraw()
	await _wait(0.3)
	await _shot("my_turn_move")
	# 연출 부품
	gs._fx.day({"date": "8월 6일", "month_label": "8월", "day_num": 6, "alert": 2, "police_speed": 3, "days_left": 9, "dispatch": "지하조직 보고: 헌병대 트럭이 거점을 나섰다. 주의하라."}, 1.0)
	await _wait(0.6)
	await _shot("fx_day")
	await _wait(1.6)
	gs._show_card({"deck": "occupation", "id": "more_checkpoints", "player": -1}, 1.0)
	await _wait(0.5)
	await _shot("fx_occupation")
	gs._close_popup()
	await _wait(0.2)
	await _shot("fx_card_fly")
	await _wait(0.8)
	gs._fx.roll_dice({"dice": [4, 6], "what": "암살", "target": 9, "bonus": 1}, 1.0)
	await _wait(0.85)
	await _shot("fx_judge")
	await _wait(1.3)
	gs._ticker.toggle()
	await _wait(0.2)
	await _shot("log_drawer")
	gs._ticker.toggle()
	gs._act({"type": "end_move"})

	# 이후는 AI가 내 자리도 두게 하고 동료 차례들을 캡처
	game.players[0]["ai"] = true
	gs._after_queue_if_idle()
	for i in 10:
		await _wait(1.5)
		if main._screen != gs:
			break
		await _shot("ai_%02d" % i)
	if main._screen == gs:
		gs._pause()
		await _wait(0.3)
		await _shot("pause")

	# 엔딩: 따로 한 판을 끝까지 둔 뒤 보여 준다
	var g := GameRules.new()
	var all_ai: Array = defs.duplicate(true)
	for d in all_ai:
		d["ai"] = true
	g.setup(all_ai, 11, main.data)
	while g.phase != "over":
		g.apply(GameAI.decide(g))
	# 도전 과제 표시를 보려고 달성 목록을 두 개 넣어 엔딩 화면을 직접 연다 (기록은 하지 않음)
	var sample: Array = main.data.achievements.get("list", []).slice(0, 2)
	var es := EndingScreen.new(g, false, sample)
	es.to_menu.connect(main._show_title)
	main._swap(es)
	await _wait(8.0)
	await _shot("ending")
	(main._screen as EndingScreen)._show_report()
	await _wait(0.8)
	await _shot("report")
	get_tree().quit()


func _store() -> void:
	## 스토어용: 며칠 진행되어 보드가 채워진 판에서 내 차례 장면들
	await _wait(0.5)
	var defs := title_defs(4)
	var game := GameRules.new()
	game.setup(defs.duplicate(true), 21, main.data)
	game.players[0]["ai"] = true
	while game.phase != "over" and not (game.rounds_left <= game.rounds_total - 4 and game.current == 0 and game.phase == "start" and not game.players[0]["jailed"]):
		game.apply(GameAI.decide(game))
	game.players[0]["ai"] = false
	game.events.clear()
	main._open_game(game, {"cfg": {"defs": defs, "difficulty": 0}, "tutorial": false}, false)
	await _wait(2.5)
	var gs: GameScreen = main._screen
	await _shot("store_turn")
	gs._act({"type": "roll"})
	await _until(func(): return not gs._playing and game.phase == "move")
	var best := Vector2i(-1, -1)
	var best_d := -1
	for x in main.data.size:
		for y in main.data.size:
			var pr := game.path_to(game.players[0], Vector2i(x, y))
			if not pr.is_empty() and pr["reachable"] and pr["steps"] > best_d and pr["steps"] <= 5:
				best_d = pr["steps"]
				best = Vector2i(x, y)
	if best.x >= 0:
		gs._board.hover = best
		gs._board._update_preview()
	await _wait(0.4)
	await _shot("store_path")
	gs._fx.roll_dice({"dice": [5, 5], "what": "암살", "target": 9, "bonus": 0}, 1.0)
	await _wait(0.85)
	await _shot("store_judge")
	await _wait(1.4)
	gs._show_card({"deck": "occupation", "id": "raid", "player": -1}, 1.0)
	await _wait(0.5)
	await _shot("store_occupation")
	gs._close_popup()
	await _wait(1.0)
	get_tree().quit()


func _play_until(game: GameRules, cond: Callable) -> void:
	game.players[0]["ai"] = true
	var guard := 0
	while game.phase != "over" and not cond.call() and guard < 20000:
		guard += 1
		game.apply(GameAI.decide(game))
	game.players[0]["ai"] = false
	game.events.clear()


func _act2() -> void:
	## 2막 화면: 결행 투표 → 결행 카드 → 2막 보드
	await _wait(0.5)
	var defs := title_defs(4)
	var cfg := {"defs": defs, "difficulty": 0}
	# 1막에 광복수치가 결행 최소치에 닿는 판을 찾는다
	var g := GameRules.new()
	for sd in range(21, 80):
		g = GameRules.new()
		g.setup(defs.duplicate(true), sd, main.data)
		await _play_until(g, func(): return g.act == 2 or (g.score >= g.launch_min() and g.phase == "start" and g.current == 0))
		if g.act == 1 and g.phase != "over":
			break
	if "traitor" in OS.get_cmdline_user_args():
		g.players[0]["stats"]["jailed"] = 9   # 내가 가장 많이 투옥됨 → 결행 때 내가 변절
	g.intel[3] = 3   # 동료들도 찬성하도록 첩보를 넉넉히
	g._start_vote()
	main._open_game(g, {"cfg": cfg, "tutorial": false}, false)
	await _wait(2.5)
	await _shot("vote")
	var gs: GameScreen = main._screen
	gs._choice.visible = false
	gs._act({"type": "choose", "value": true})
	await _wait(3.0)
	await _shot("strike_card")
	gs._close_popup()
	await _wait(3.5)
	await _shot("after_launch")
	if "traitor" in OS.get_cmdline_user_args():
		gs._choice.visible = false
		gs._notice_closed.emit()
		await _wait(4.0)
		await _shot("traitor_turn")
		get_tree().quit()
		return
	await _wait(1.5)
	# 2막이 며칠 진행된 보드
	var h := GameRules.new()
	h.setup(defs.duplicate(true), 21, main.data)
	await _play_until(h, func(): return h.act == 2 and h.phase == "start" and h.current == 0 and not h.players[0]["jailed"])
	main._open_game(h, {"cfg": cfg, "tutorial": false}, false)
	await _wait(2.5)
	await _shot("act2_board")
	get_tree().quit()


func _tut2() -> void:
	## 2막 훈련: 안내 창이 뜰 때마다 찍고 넘기며, 내 차례는 AI 판단으로 둔다
	await _wait(0.8)
	main._start_tutorial("tutorial2")
	var gs: GameScreen = main._screen
	var game: GameRules = gs.game
	var shot_tips := {}
	var t := 0.0
	while game.phase != "over" and t < 240.0:
		await _wait(0.2)
		t += 0.2
		if gs._choice.visible:
			var key := "choice_%s" % game.pending.get("kind", "tip")
			for id in gs._tips_shown:
				if not shot_tips.has(id):
					shot_tips[id] = true
					key = "tip_" + id
			await _wait(0.4)
			await _shot(key)
			if key.begins_with("tip_"):
				gs._choice.visible = false
				gs._tip_closed.emit()
			elif game.phase == "choice":
				gs._choice.visible = false
				gs._act({"type": "choose", "value": true if game.pending["kind"] == "launch_vote" else game.pending["options"][0]["value"]})
		elif not gs._playing and gs._queue.is_empty() and game.current == 0 and game.phase in ["start", "move"]:
			if game.act == 2 and not shot_tips.has("act2_board"):
				shot_tips["act2_board"] = true
				await _shot("act2_board")
			gs._act(GameAI.decide(game))
	await _until(func(): return gs._choice.visible, 30.0)
	await _wait(0.4)
	await _shot("tip_done")
	gs._choice.visible = false
	gs._tip_closed.emit()
	await _wait(4.0)
	await _shot("ending")
	get_tree().quit()


func _hot() -> void:
	## 핫시트 3인(사람 2 + AI 1) 한 판: 설정 화면 → 자리 교대 안내 → 투표 → 엔딩 → 설문 → 기록 파일
	PlaytestLog.disabled = false
	PlaytestLog.dir = out + "/logs"
	Prefs.speed = 3
	Prefs.reduce_motion = true
	await _wait(0.8)
	main._show_title()
	await _wait(0.8)
	var title: TitleScreen = main._screen
	title._n_players = 3
	title._n_humans = 2
	title._show_setup()
	await _wait(0.5)
	await _shot("setup_hotseat")
	var cfg := {"defs": title.make_players(3, 0, 2), "difficulty": 0, "seed": 4242}
	main._start(cfg)
	await _wait(1.0)
	var gs: GameScreen = main._screen
	var game: GameRules = gs.game
	gs._choice.visible = false
	gs._begin()
	var shots := {}
	var t := 0.0
	while game.phase != "over" and t < 400.0:
		await _wait(0.1)
		t += 0.1
		if gs._choice.visible:
			await _wait(0.2)
			if gs._noticing:
				var k := "handover_%d" % gs.human
				if not shots.has(k):
					shots[k] = true
					await _shot(k)
				gs._choice.visible = false
				gs._notice_closed.emit()
			elif game.phase == "choice" and not game.players[game.pending["player"]]["ai"]:
				var k2: String = "choice_" + str(game.pending["kind"])
				if not shots.has(k2):
					shots[k2] = true
					await _shot(k2)
				gs._choice.visible = false
				gs._act(GameAI.decide(game))
			else:
				gs._choice.visible = false
		elif not gs._playing and gs._queue.is_empty() and not game.cur()["ai"] and game.phase in ["start", "move"] and game.current == gs.human:
			if not shots.has("turn_%d" % gs.human):
				shots["turn_%d" % gs.human] = true
				await _shot("turn_%d" % gs.human)
			gs._act(GameAI.decide(game))
	await _until(func(): return main._screen is EndingScreen, 30.0)
	await _wait(3.0)
	(main._screen as EndingScreen).to_menu.emit()
	await _wait(0.8)
	var sv: SurveyScreen = main._screen
	sv._ans = {"fun": 4, "clarity": 3, "agency": 3, "tension": 5, "launch": 4, "again": 4, "length": 2}
	sv._checks["confusing"]["vote"].button_pressed = true
	sv._checks["cut"]["decoy"].button_pressed = true
	sv._texts["best"].text = "형무소 자물쇠를 마지막에 풀었을 때"
	await _wait(0.3)
	await _shot("survey")
	sv._save()
	sv._build()
	sv._ans = {"fun": 5, "clarity": 4, "agency": 2, "tension": 4, "launch": 3, "again": 5, "length": 3}
	sv._checks["confusing"]["exposure"].button_pressed = true
	sv._texts["worst"].text = "동료 차례를 기다릴 때"
	sv._save()
	sv.finished.emit()
	await _wait(0.8)
	await _shot("after_survey")
	print("[tour] 결말 %s, 기록 %s" % [game.ending.get("id", ""), DirAccess.get_files_at(PlaytestLog.dir)])
	get_tree().quit()


func _v2() -> void:
	## v2 시험판: 요원 고르기 → 자동 진행하며 단계마다 캡처 → 엔딩
	await _wait(0.5)
	main._show_v2_setup()
	await _wait(0.8)
	await _shot("v2_setup")
	var setup = main._screen
	var defs := []
	var data := GameDataV2.load_default()
	for id in ["yun", "jeong", "gaeddong", "oh"]:
		defs.append({"name": "나" if defs.is_empty() else str(data.character(id)["name"]), "character": id})
	var game := RulesV2.new()
	game.setup(defs, 4242)
	var screen := GameScreenV2.new(game, 0, {"autoplay": true})
	var done := [false]
	screen.finished.connect(func(): done[0] = true)
	main._swap(screen)
	var shots := {"plan": false, "turn": false, "act2_plan": false, "act2_turn": false}
	var guard := 0
	while not done[0] and guard < 6000:
		guard += 1
		await _wait(0.05)
		if game.act == 1 and game.day >= 2 and game.phase == "plan" and not shots["plan"]:
			shots["plan"] = true
			await _wait(0.4)
			await _shot("v2_plan")
		elif game.act == 1 and game.day >= 3 and game.phase == "turn" and game.current == 0 and not shots["turn"]:
			shots["turn"] = true
			await _shot("v2_turn")
			if not game.mission_row.is_empty() and screen._mid_box.get_child_count() > 0:
				screen._peek.show_for(screen._mid_box.get_child(0), screen._text.mission_info(str(game.mission_row[0])), true)
				await _wait(0.2)
				await _shot("v2_peek_mission")
			var sg: Array = game.saga_cards(0)
			screen._peek.show_for(screen._hand_row.get_child(0), screen._text.saga_info(str(sg[0]), game.saga_progress(0).get(sg[0], {"have": 0, "need": 1}), false), true)
			await _wait(0.2)
			await _shot("v2_peek_saga")
			screen._peek.show_for(screen._top._threat, screen._text.threat_info(), true)
			await _wait(0.2)
			await _shot("v2_peek_threat")
			screen._peek.visible = false
		elif game.act == 2 and game.phase == "plan" and not shots["act2_plan"]:
			shots["act2_plan"] = true
			await _wait(0.4)
			await _shot("v2_act2_plan")
		elif game.act == 2 and game.phase == "turn" and not shots["act2_turn"] and game.day > int(game.launch_info.get("day", 0)):
			shots["act2_turn"] = true
			await _shot("v2_act2_turn")
			for c in screen._mid_box.get_children():
				if c is PanelContainer and c.custom_minimum_size.x > 200:
					screen._peek.show_for(c, screen._text.scene_info(screen._text.scene_card_dict(str(game.scenes[game.scene_index])), game.scene_index), true)
			await _wait(0.2)
			await _shot("v2_peek_scene")
			screen._peek.show_for(screen._rows[1]["panel"], screen._text.char_info(game.players[1]), true)
			await _wait(0.2)
			await _shot("v2_peek_char")
			screen._peek.visible = false
	print("[tour] v2 끝: phase=%s ending=%s day=%d act=%d" % [game.phase, game.ending.get("id", "-"), game.day, game.act])
	var e := EndingScreenV2.new(game, 0)
	main._swap(e)
	await _wait(0.8)
	await _shot("v2_ending")
	get_tree().quit()


func _online() -> void:
	## 온라인 확인: 같은 프로세스에 서버를 띄우고, 실제 로비 화면으로 방을 만들고, 두 번째 사람(가짜 클라이언트)이 들어와
	## 판을 끝까지 둔다. 화면 쪽 사람 차례는 AI 판단으로 화면 단추를 누르듯 둔다 (화면이 멈추지 않는지 확인)
	var port := 8951
	var srv := NetServerV2.new()
	srv.port = port
	srv.quiet = true
	srv.ai_step = 0.05
	main.add_child(srv)
	Prefs.online_url = "ws://127.0.0.1:%d" % port
	Prefs.online_name = "나"
	await _wait(0.3)
	main._show_online()
	await _wait(0.6)
	await _shot("online_connect")
	var net: NetClientV2 = main._net
	net.open(Prefs.online_url, "나")
	await _until(func(): return net.token != "")
	await _wait(0.3)
	await _shot("online_choose")
	net.send({"t": "create"})
	await _until(func(): return net.room.has("code"))
	var friend := NetClientV2.new()
	main.add_child(friend)
	friend.open(Prefs.online_url, "친구")
	await _until(func(): return friend.token != "")
	friend.send({"t": "join", "code": net.room["code"]})
	await _until(func(): return friend.seat >= 0)
	friend.send({"t": "pick", "character": friend.room["seats"][friend.seat]["offer"][0]})
	await _wait(0.4)
	net.send({"t": "pick", "character": net.room["seats"][net.seat]["offer"][1]})
	await _wait(0.6)
	await _shot("online_room")
	var fview := [null]
	friend.game_started.connect(func(_s, v, _n): fview[0] = v)
	friend.game_updated.connect(func(v, _e, _i): fview[0] = v)
	net.send({"t": "start"})
	await _until(func(): return main._screen is GameScreenV2)
	await _wait(1.5)
	await _shot("online_game")
	var screen: GameScreenV2 = main._screen
	var fsent := [false]
	friend.game_updated.connect(func(_v, _e, _i): fsent[0] = false)
	var guard := 0
	var shot_turn := false
	var day_sent := {}   # 아침 「하루 시작」은 하루에 한 번만 보낸다
	while guard < 40000 and main._screen is GameScreenV2 and screen.game.phase != "over":
		guard += 1
		await get_tree().process_frame
		# 두 번째 사람: 자기 보기만 보고 둔다
		if fview[0] != null and not fsent[0]:
			var fg := RulesV2.new()
			fg.load_state(fview[0])
			var fa := _seat_move(fg, friend.seat)
			if fa.get("type", "") == "start_day":
				if day_sent.get("f", -1) == fg.day:
					fa = {}
				else:
					day_sent["f"] = fg.day
			if not fa.is_empty():
				fsent[0] = true
				friend.act(fa)
		# 화면 쪽 사람: 화면이 입력을 기다릴 때만
		if screen.is_idle():
			var a := _seat_move(screen.game, screen.human)
			if a.get("type", "") == "start_day":
				if day_sent.get("me", -1) == screen.game.day:
					a = {}
				else:
					day_sent["me"] = screen.game.day
			if not a.is_empty():
				if not shot_turn and screen.game.phase == "turn":
					shot_turn = true
					await _shot("online_my_turn")
				if a["type"] == "choose":
					screen.choose_now(a["value"])
				else:
					screen.act_now(a)
				await _wait(0.05)
	print("[tour] 온라인 판 끝: phase=%s ending=%s day=%d" % [screen.game.phase, screen.game.ending.get("id", "-"), screen.game.day])
	await _wait(3.0)
	await _shot("online_end")
	get_tree().quit()


func _seat_move(g: RulesV2, seat: int) -> Dictionary:
	## 한 자리가 지금 둘 수(없으면 빈 사전): 아침 「하루 시작」, 낮 내 차례 시작, 내 차례 · 내 선택 창은 AI 판단
	match g.phase:
		"plan":
			return {"type": "start_day", "player": seat}
		"day":
			return {"type": "begin_turn", "player": seat} if g.can_begin_turn(g.players[seat]) else {}
		"turn":
			return GameAIV2.decide(g, seat) if g.current == seat else {}
		"choice":
			return GameAIV2.decide(g, seat) if int(g.pending.get("player", -1)) == seat else {}
	return {}


func _fxshots() -> void:
	## V 연출 확인용: 결행 컷(초상 · 도장) · 장면 컷 · 투옥 컷 · 일제 작전 컷 · 비네트 · 먹 번짐 · 금 · 보드 타일
	await _wait(0.5)
	var defs := []
	var data := GameDataV2.load_default()
	for id in ["yun", "jeong", "gaeddong", "oh"]:
		defs.append({"name": "나" if defs.is_empty() else str(data.character(id)["name"]), "character": id})
	var game := RulesV2.new()
	game.setup(defs, 4242)
	var guard := 0   # 2막까지 AI로 진행해 보드에 타일이 깔리게
	while game.act == 1 and game.phase != "over" and guard < 20000:
		guard += 1
		game.apply(GameAIV2.decide(game, GameAIV2.next_actor(game)))
	var screen := GameScreenV2.new(game, 0, {"autoplay": true})
	main._swap(screen)
	screen._paused = true   # 캡처하는 동안 AI가 두지 않게
	await _wait(1.0)
	await _shot("fx_board")
	var c: CinemaV2 = screen._cine
	var faces := []
	for q in game.players:
		faces.append(ArtV2.get_tex("char", str(q["character"])))
	var target := str(game.launch_info.get("target", "gg"))
	c.cut({"tex": ArtV2.get_tex("strike", target), "title": "결행 · " + str(data.strike(target).get("name", "")), "sub": "오늘 밤, 들이친다",
		"portraits": faces, "stamp": "결 행", "hold": 4.0}, 1.0)
	await _wait(2.2)
	await _shot("fx_launch")
	c._skip = true
	await _wait(0.6)
	var sid := str(game.scenes[game.scene_index])
	c.cut({"tex": ArtV2.get_tex("scene", sid), "title": "장면 · " + str(screen._text.scene_card_dict(sid).get("name", "")), "sub": "조건 한 줄", "stamp": "돌 파",
		"stamp_color": Style.GOOD, "hold": 3.0}, 1.0)
	await _wait(1.2)
	await _shot("fx_scene_break")
	c._skip = true
	await _wait(0.6)
	c.cut({"tex": ArtV2.get_tex("cut", "jail", ArtV2.get_tex("threat", "prison")), "title": "투옥 · 서대문형무소 감옥", "sub": "탈옥 판정을 하거나 동료가 구하러 올 때까지 기다린다",
		"stamp": "투 옥", "hold": 3.0}, 1.0)
	await _wait(1.2)
	await _shot("fx_jail")
	c._skip = true
	await _wait(0.6)
	c.vignette(Style.SEAL, 0.55, 3.0)
	c.ink(screen._fx.focus_center + Vector2(-150, 0), true, 3.0)
	c.ink(screen._fx.focus_center + Vector2(150, 0), false, 3.0)
	await _wait(0.8)
	await _shot("fx_vignette_ink")
	await _wait(2.5)
	# 캐릭터 컷인 (동료: 오른쪽에서)
	screen._playback.cutin(2, 1.0)
	await _wait(0.6)
	await _shot("fx_cutin")
	await _wait(1.2)
	# 보드 분위기: 2막 밤 + 탐조등 / 비, 먹 발자국
	screen._atmos.set_state("turn", 2, "curfew")
	screen._board.note_footprint(game.players[0]["pos"] + Vector2i(0, 1), 0)
	screen._board.note_footprint(game.players[0]["pos"] + Vector2i(0, 2), 0)
	await _wait(1.6)
	await _shot("fx_night_searchlight")
	screen._atmos.set_state("turn", 1, "monsoon")
	await _wait(1.6)
	await _shot("fx_rain")
	# 마지막 장면 심장 박동, 먹 전환
	c.heartbeat(true)
	await _wait(1.13)
	await _shot("fx_heartbeat")
	c.heartbeat(false)
	c.ink_wipe(2.0)
	await _wait(0.9)
	await _shot("fx_ink_wipe")
	await _wait(1.6)
	# 끝: 만세 / 흑백
	c.victory(2.0)
	await _wait(0.7)
	await _shot("fx_victory")
	await _wait(3.5)
	c.defeat(1.0)
	await _wait(1.6)
	await _shot("fx_defeat")
	get_tree().quit()


func _q() -> void:
	## Q 완성도 확인용: 타이틀 · 훈련 작전 안내 · 내 차례 화면(넘침) · 엔딩 요약과 작전 일지
	await _wait(0.5)
	main._show_title()
	await _wait(0.8)
	await _shot("q_title")
	main._training_v2()
	await _wait(1.2)
	var screen: GameScreenV2 = main._screen
	var game: RulesV2 = screen.game
	await _shot("q_training_morning")
	for step in 120:   # 아침 → 낮 → 내 차례까지: 안내를 닫고 사람 자리의 다음 수를 둔다
		screen._tip.visible = false
		if game.phase == "turn" and game.current == 0:
			break
		if screen.is_idle() and screen._ai_actor() < 0:
			var mine := game.legal_actions().filter(func(a): return int(a.get("player", -1)) == 0 and a["type"] in ["start_day", "begin_turn"])
			if not mine.is_empty():
				screen.act_now(mine[0])
		await _wait(0.6)
	await _wait(0.8)
	screen._coach.tip_check()
	await _wait(0.3)
	await _shot("q_training_turn")
	print("[tour] 넘침 %.0f · 받은 높이 %.0f · 최소 %s · 크기 %s · 화면 %s" % [screen.right_overflow(), screen._right_h, str(screen._right.get_combined_minimum_size()), str(screen._right.size), str(screen.size)])
	screen._tip.visible = false
	screen._coach.tip_check()
	await _wait(0.3)
	await _shot("q_training_marker")
	# U1: 이동 주사위에 올렸을 때 선택 미리보기 띠 · 갈 수 있는 칸
	screen._tip.visible = false
	var mv := game.legal_actions().filter(func(a): return int(a.get("player", -1)) == 0 and a["type"] == "move_die")
	if not mv.is_empty():
		screen._actions.pick_verb("move", mv)   # M3: 「이동」을 누르면 쓸 주사위가 반짝
		await _wait(0.4)
		await _shot("q_verb_move")
		screen._actions.hover_action(mv[mv.size() - 1])
		await _wait(0.4)
		await _shot("q_preview_move")
		# M2: 기운 보드에서 칸 누르기가 맞는 칸으로 가는가
		if screen._tilt != null and not screen._board.reach.is_empty():
			var target: Vector2i = screen._board.reach.keys()[0]
			var before: Vector2i = game.players[0]["pos"]
			screen.act_now(mv[mv.size() - 1])   # 이동 주사위를 먼저 고른다 (걷는 중이어야 칸을 눌러 감)
			await _wait(1.0)
			for c in game.reach_cells(game.players[0], game.steps_left):
				target = c
				break
			var lp: Vector2 = screen._tilt.board_to_local(screen._board.cell_rect(target).get_center())
			var mm := InputEventMouseMotion.new()
			mm.position = lp
			screen._tilt._gui_input(mm)
			await _wait(0.2)
			var hov: Vector2i = screen._board.hover
			var mb := InputEventMouseButton.new()
			mb.position = lp
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			screen._tilt._gui_input(mb)
			var mb2: InputEventMouseButton = mb.duplicate()
			mb2.pressed = false
			screen._tilt._gui_input(mb2)
			await _wait(2.5)
			print("[tour] 기운 보드 누르기: 목표 %s · 가리킨 칸 %s · 전 %s → 후 %s" % [str(target), str(hov), str(before), str(game.players[0]["pos"])])
	# 엔딩: AI로 한 판을 끝까지 두고 요약을 본다
	var g := RulesV2.new()
	var defs := []
	for id in ["seo", "han", "lee", "mun"]:
		defs.append({"name": "나" if defs.is_empty() else id, "character": id})
	g.setup(defs, 2468)
	var guard := 0
	while g.phase != "over" and guard < 20000:
		guard += 1
		g.apply(GameAIV2.decide(g, GameAIV2.next_actor(g)))
	var e := EndingScreenV2.new(g, 0)
	main._swap(e)
	await _wait(0.8)
	await _shot("q_ending")
	var sc := e.get_child(1) as ScrollContainer
	if sc:
		sc.scroll_vertical = 100000
		await _wait(0.3)
		await _shot("q_ending_log")
	get_tree().quit()


func _v2f() -> void:
	## v2 화면 다듬기 확인용: 만들어 둔 장면(행동 메뉴 · 마커 · 같은 칸 · 동향 띠 · 결행 투표 · 혜택 · 반격 · 장터)을 캡처한다
	await _wait(0.5)
	var data := GameDataV2.load_default()
	var defs := []
	for id in ["park", "jeong", "gaeddong", "oh"]:
		defs.append({"name": "나" if defs.is_empty() else str(data.character(id)["name"]), "character": id})
	var game := RulesV2.new()
	game.setup(defs, 4242)
	var guard := 0
	while game.phase == "choice" and guard < 20:
		guard += 1
		game.apply({"type": "choose", "player": game.pending["player"], "value": game.pending["options"][0]["value"]})
	for y in 11:
		for x in 11:
			var c := Vector2i(x, y)
			if not game.board.has(c) and absi(x - 5) + absi(y - 5) <= 5:
				game.board[c] = game._new_tile("normal")
	game.board[Vector2i(4, 6)] = game._new_tile("alley")
	game.board[Vector2i(6, 6)] = game._new_tile("watchtower")
	game.board[Vector2i(4, 4)] = game._new_tile("market")
	game.board[Vector2i(6, 4)] = game._new_tile("tavern")
	game.mission_row = []
	game.markers = []
	game.mission_state = {}
	for id in ["m_police_chief", "m_secret_docs", "m_open_rice", "m_police_watch"]:
		game.mission_row.append(id)
		game._place_card(id)
	game.op_row.append("op_censorship")
	game._place_card("op_censorship")
	game.trend = 3
	game.funds = 4
	game.ready = 5
	game.exposure = 3
	game.mission_state["m_open_rice"]["sum"] = 5
	game.mission_state["m_secret_docs"]["holder"] = 1
	game.players[0]["grants"] = [{"kind": "check_bonus", "value": 2, "scope": "strike"}, {"kind": "reroll", "value": 0, "scope": "any"}]
	game.players[0]["items"] = ["telescope"]
	game.players[1]["pos"] = Vector2i(5, 6)
	game.players[0]["pos"] = Vector2i(5, 6)
	game.police[1] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	game.phase = "day"
	game.apply({"type": "begin_turn", "player": 0})
	game.op_dice = []
	for v in [5, 2, 6]:
		game.op_dice.append({"value": v, "owner": 0, "used": false})
	var screen := GameScreenV2.new(game, 0, {})
	screen._paused = true
	main._swap(screen)
	await _wait(0.8)
	screen._tips_seen = {"turn": true}
	screen._board.note_scouted(Vector2i(5, 7))
	game.players[0]["fx_cells"] = [Vector2i(6, 6)]
	screen._refresh()
	await _wait(0.4)
	await _shot("v2f_board_top")
	var acts := game.legal_actions().filter(func(a): return int(a.get("player", -1)) == 0 and a.has("die") and int(a["die"]) == 0)
	screen._actions.die_menu(acts, 0)
	await _wait(0.5)
	await _shot("v2f_menu")
	screen._actions.hover_action(acts[0])
	await _wait(0.3)
	await _shot("v2f_menu_reach")
	screen._actions.close_menu()
	# 장터
	game.players[0]["pos"] = Vector2i(4, 4)
	screen._refresh()
	var macts := game.legal_actions().filter(func(a): return int(a.get("player", -1)) == 0 and a.has("die") and int(a["die"]) == 1)
	screen._actions.die_menu(macts, 1)
	await _wait(0.5)
	await _shot("v2f_market_menu")
	screen._actions.close_menu()
	# 첫 판 안내
	screen._tips_seen = {}
	Prefs.v2_tips = true
	screen._coach.tip_check()
	screen._layout()
	await _wait(0.3)
	await _shot("v2f_tip")
	screen._tip.visible = false
	# 결행 투표
	game.phase = "morning"
	game.act = 1
	game.intel = {"barracks": 2, "police_hq": 3, "prison": 0, "gg": 1}
	game._start_vote(false)
	screen._show_choice()
	await _wait(0.4)
	await _shot("v2f_vote")
	screen._choice.visible = false
	# 결행 혜택
	game.vote_state = {}
	game.pending = {}
	game.phase = "day"
	game.ready = 6
	game._launch("vote", "prison")
	screen._refresh()
	if game.phase == "choice":
		screen._show_choice()
	await _wait(0.4)
	await _shot("v2f_benefit")
	screen._choice.visible = false
	# 반격 (버티기 장면)
	game.pending = {}
	game.phase = "day"
	var strike := game.data.strike("barracks")
	game.launch_info = {"target": "barracks", "reason": "test", "day": game.day, "rounds_left": game.rounds_left}
	game.act = 2
	game.markers = []
	game.mission_row = []
	game.op_row = []
	game.scenes = [strike["entry"]["id"], "barracks_shift", strike["final"]["id"]]
	game.scene_index = 1
	game.scene_state = {}
	game.counter = {"day": game.day, "blocked": false}
	game.players[0]["pos"] = Vector2i(2, 1)
	screen._refresh()
	await _wait(0.4)
	await _shot("v2f_counter")
	get_tree().quit()


func _endings() -> void:
	## U3: 엔딩 네 갈래를 AI 판으로 하나씩 찾아 캡처한다
	await _wait(0.5)
	var data := GameDataV2.load_default()
	var want := ["victory", "fail_final", "fail_middle", "history"]
	var found := {}
	for i in 400:
		if found.size() == want.size():
			break
		var g := RulesV2.new()
		var defs := []
		for id in ["yun", "jeong", "gaeddong", "oh"]:
			defs.append({"name": data.character(id).get("name", id), "character": id})
		g.setup(defs, 520000 + i, data)
		var steps := 0
		while g.phase != "over" and steps < 6000:
			g.apply(GameAIV2.decide(g, GameAIV2.next_actor(g)))
			g.events.clear()
			steps += 1
		var id := str(g.ending.get("id", ""))
		if id in want and not found.has(id):
			found[id] = g
	for id in want:
		if not found.has(id):
			print("[tour] 엔딩 못 찾음: ", id)
			continue
		main._swap(EndingScreenV2.new(found[id], 0))
		await _wait(2.6)
		await _shot("ending_" + id)
	get_tree().quit()


func _measure() -> void:
	## U4: 한 판 동안 사람이 기다린 시간을 종류별로 잰다 (내 자리도 AI가 두되 연출은 사람 판과 같은 빠르기).
	## 같은 시드로 「연출 전부 · 동료 보통」과 「같은 컷신은 처음만 · 동료 빠르게」를 견준다. 게임 시간 기준(배속과 무관)
	await _wait(0.5)
	var data := GameDataV2.load_default()
	Engine.time_scale = 3.0   # 너무 빠르면 한 프레임이 길어져 짧은 기다림이 부풀려 재진다
	for setting in [[0, 1, "연출 전부 · 동료 보통"], [1, 2, "처음만 · 동료 빠르게"], [2, 3, "컷신 줄임 · 동료 즉시"]]:
		Prefs.v2_cine = setting[0]
		Prefs.speed = setting[1]
		var defs := []
		for id in ["yun", "jeong", "gaeddong", "oh"]:
			defs.append({"name": str(data.character(id)["name"]), "character": id})
		var game := RulesV2.new()
		game.setup(defs, 4242)
		var screen := GameScreenV2.new(game, 0, {"autoplay": true})
		var done := [false]
		screen.finished.connect(func(): done[0] = true)
		main._swap(screen)
		await _wait(0.1)
		screen._fast = false
		var guard := 0
		while not done[0] and guard < 200000:
			guard += 1
			await _wait(0.05)
		var total := 0.0
		var steps := int(screen.wait_stats.get("_ai_steps", 0))
		screen.wait_stats.erase("_ai_steps")
		for k in screen.wait_stats:
			total += float(screen.wait_stats[k])
		var parts := ["AI 수 %d" % steps]
		for k in screen.wait_stats:
			parts.append("%s %.0f초" % [k, float(screen.wait_stats[k])])
		print("[measure] %s · %d일 · 합계 %.1f분 · %s" % [setting[2], game.day, total / 60.0, " · ".join(parts)])
	Engine.time_scale = 1.0
	get_tree().quit()


func _perf() -> void:
	## Z5: 화면 프레임 시간. 내 차례에 입력을 기다리는 동안(가장 흔한 상태) 3초씩 잰다. 수직 동기 끄고 프레임 제한 없음
	await _wait(0.5)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var data := GameDataV2.load_default()
	for tilt in [true, false]:
		Prefs.v2_tilt = tilt
		Prefs.v2_tips = false
		var defs := []
		for id in ["yun", "jeong", "gaeddong", "oh"]:
			defs.append({"name": str(data.character(id)["name"]), "character": id})
		var game := RulesV2.new()
		game.setup(defs, 4242)
		var screen := GameScreenV2.new(game, 0, {})
		main._swap(screen)
		screen._fast = true
		var guard := 0
		while guard < 4000 and not (screen.is_idle() and game.phase == "turn" and game.current == 0):
			guard += 1
			await _wait(0.05)
			if screen.is_idle() and game.phase == "plan":
				screen.act_now({"type": "start_day", "player": 0})
			elif screen.is_idle() and game.phase == "day":
				screen.act_now({"type": "begin_turn", "player": 0})
		await _wait(1.0)
		BoardViewV2.draw_usec = 0
		BoardViewV2.draw_count = 0
		TiltBoardV2.pieces_usec = 0
		TiltBoardV2.pieces_count = 0
		var frames := 0
		var calls := 0.0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 3000000:
			await get_tree().process_frame
			frames += 1
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var sec := (Time.get_ticks_usec() - t0) / 1000000.0
		print("[perf] %s · 내 차례 대기 · %.0f fps (프레임 %.2fms) · 보드 그리기 초당 %.0f회 × %.2fms · 말 그리기 초당 %.0f회 × %.2fms · 그리기 호출 %.0f/프레임" % [
			"기운 보드" if tilt else "평면 보드", frames / sec, 1000.0 * sec / frames,
			BoardViewV2.draw_count / sec, BoardViewV2.draw_usec / 1000.0 / maxf(1, BoardViewV2.draw_count),
			TiltBoardV2.pieces_count / sec, TiltBoardV2.pieces_usec / 1000.0 / maxf(1, TiltBoardV2.pieces_count),
			calls / frames])
	Prefs.v2_tilt = true
	get_tree().quit()


func _gif() -> void:
	## itch.io용 짧은 GIF의 낱장: AI 자동 진행(보통 빠르기)으로 둘째 날 아침부터 프레임을 찍는다 (tools/make_gif.py가 묶음)
	await _wait(0.5)
	var data := GameDataV2.load_default()
	var defs := []
	for id in ["yun", "jeong", "gaeddong", "oh"]:
		defs.append({"name": str(data.character(id)["name"]), "character": id})
	var game := RulesV2.new()
	game.setup(defs, 4242)
	Prefs.speed = 1
	Prefs.v2_cine = 1
	var screen := GameScreenV2.new(game, 0, {"autoplay": true})
	main._swap(screen)
	await _wait(0.2)
	screen._fast = false
	var guard := 0
	while not (game.day >= 2 and game.phase == "plan") and guard < 20000:
		guard += 1
		await _wait(0.05)
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 14000 and game.phase != "over":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(800, 450, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/f_%04d.png" % [out, n])
		n += 1
		await _wait(0.1)
	print("[tour] GIF 낱장 %d장" % n)
	get_tree().quit()
