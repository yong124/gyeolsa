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
		elif game.act == 2 and game.phase == "plan" and not shots["act2_plan"]:
			shots["act2_plan"] = true
			await _wait(0.4)
			await _shot("v2_act2_plan")
		elif game.act == 2 and game.phase == "turn" and not shots["act2_turn"] and game.day > int(game.launch_info.get("day", 0)):
			shots["act2_turn"] = true
			await _shot("v2_act2_turn")
	print("[tour] v2 끝: phase=%s ending=%s day=%d act=%d" % [game.phase, game.ending.get("id", "-"), game.day, game.act])
	var e := EndingScreenV2.new(game, 0)
	main._swap(e)
	await _wait(0.8)
	await _shot("v2_ending")
	get_tree().quit()
