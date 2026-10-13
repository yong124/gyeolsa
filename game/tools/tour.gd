extends Node
## 화면 둘러보기 캡처 (개발용, 빌드에서 제외). 실제 저장 파일은 건드리지 않는다.
## 실행: godot --path game --position -3000,-3000 -- tour out=<폴더> [w=1600 h=900]
## 모드: (없음 · v2) 요원 고르기 → 자동 진행 캡처 → 엔딩 · tutorial · firstrun · gate · online · endings · fx · q · v2f · measure · perf · gif

var main: Node
var out := "user://tour"
var _n := 0


func _ready() -> void:
	main = get_parent()
	SaveGameV2.disabled = true
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
	if "online" in OS.get_cmdline_user_args():
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
	elif "tutorial" in OS.get_cmdline_user_args():
		_tutorial()
	elif "firstrun" in OS.get_cmdline_user_args():
		await _wait(0.5)
		main._show_title()
		main._screen.offer_tutorial()
		await _wait(1.5)
		await _shot("firstrun_offer")
		Prefs.v2_trainings = ["t1"]
		main._screen._overlay.visible = false
		main._screen._show_trainings()
		await _wait(0.6)
		await _shot("training_list")
		Prefs.v2_trainings = []
		get_tree().quit()
	elif "endings" in OS.get_cmdline_user_args():
		_endings()
	elif "fx" in OS.get_cmdline_user_args():
		_fxshots()
	elif "q" in OS.get_cmdline_user_args():
		_q()
	elif "v2f" in OS.get_cmdline_user_args():
		_v2f()
	else:
		_v2()   # 기본: v2 요원 고르기부터 자동 진행 캡처


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, _n, name])
	print("[tour] %02d_%s" % [_n, name])


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
	# 공개 방 목록이 비지 않게: 다른 사람 둘이 공개 방을 하나씩 열어 둔다
	for nm in [["다른1", "초보 환영"], ["다른2", "종로 작전"]]:
		var o := NetClientV2.new()
		main.add_child(o)
		o.open(Prefs.online_url, nm[0])
		await _until(func(): return o.token != "")
		o.send({"t": "create", "name": nm[1], "public": true})
		await _until(func(): return o.room.has("code"))
	net.send({"t": "list"})
	await _wait(0.6)
	await _shot("online_choose")
	net.send({"t": "create", "name": "광복 작전 1호", "public": true})
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
	friend.send({"t": "ready", "on": true})
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
	main._quick_v2()
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
	game.board[Vector2i(4, 4)] = game._new_tile("item")
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
	# 첫 판 안내
	Prefs.v2_notes_seen = []
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


func _click(pos: Vector2) -> void:
	## 진짜 마우스처럼: 움직이고 누르고 뗀다 (Input을 거쳐 _input · GUI가 모두 받음)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await _wait(0.05)
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = pos
		mb.global_position = pos
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		Input.parse_input_event(mb)
		await _wait(0.05)


func _find_button(root: Node, text: String) -> Control:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.text == text or b.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == text):
			return b
	return null


var _tut_fail := 0


func _tfail(msg: String) -> void:
	_tut_fail += 1
	print("[tutorial] FAIL ", msg)


func _tutorial() -> void:
	## 튜토리얼 훈련 클릭 투어: 훈련 4개를 사람처럼 끝까지 (밝힌 곳만 누르고 「다음」을 누른다).
	## 옵션: tr=1..4 그 훈련만 · bad 훈련 2에서 2를 먼저 고르는 길 · skip 건너뛰기 · menu 중간에 메뉴로 나갔다가 다시 · notes 실전 쪽지
	await _wait(0.5)
	Prefs.speed = 1 if "real" in OS.get_cmdline_user_args() else 3   # 동료 차례는 즉시 (투어를 빨리). real이면 보통 속도로 시간을 잼
	Prefs.v2_training_done = false
	Prefs.v2_trainings = []
	var args := OS.get_cmdline_user_args()
	if "skip" in args:
		await _tut_skip()
	elif "menu" in args:
		await _tut_menu()
	elif "notes" in args:
		await _tut_notes()
	elif "help" in args:
		await _tut_help()
	else:
		var only := -1
		for a in args:
			if a.begins_with("tr="):
				only = int(a.substr(3)) - 1
		for idx in range(4):
			if only >= 0 and idx != only:
				continue
			await _tut_one(idx, "bad" in args and idx == 1, only >= 0 or idx == 3)
		if only < 0:
			if Prefs.v2_trainings.size() != 4:
				_tfail("훈련 4개를 모두 마치지 못함: %s" % str(Prefs.v2_trainings))
		print("[tutorial] 마친 훈련: ", Prefs.v2_trainings)
	print("[tutorial] ", "통과" if _tut_fail == 0 else "실패 %d건" % _tut_fail)
	get_tree().quit(1 if _tut_fail > 0 else 0)


func _tut_one(idx: int, bad: bool, last_stays: bool) -> void:
	## 훈련 idx를 처음부터 끝까지. 끝나면 완료 화면에서 「다음 훈련」(마지막이면 「실전 시작」)을 누른다
	main._tutorial_v2(idx)
	await _wait(1.5)
	var screen = main._screen
	var tut: TutorialV2 = screen._tutor
	var t0 := Time.get_ticks_msec()
	var last := -1
	var same := 0
	var bad_done := not bad
	var shots := {}
	var clicks := 0
	var tag := "t%d" % (idx + 1)
	if tut == null:
		_tfail("%s: 훈련 화면이 아님" % tag)
		return
	for n in 1200:
		await _wait(0.25)
		if not is_instance_valid(screen) or screen != main._screen:
			break   # 화면이 바뀜 (다음 훈련 · 실전 · 메뉴)
		if tut._complete != null and is_instance_valid(tut._complete):
			if not shots.has("done"):
				shots["done"] = true
				await _wait(0.3)
				await _shot("%s_complete" % tag)
				print("[tutorial] %s 완료 · 단계 %d · 누른 횟수 %d · 걸린 시간(투어) %.0f초 · 기다린 시간 %s" % [tag, tut.steps.size(), clicks, (Time.get_ticks_msec() - t0) / 1000.0, str(screen.wait_stats)])
			var label := "다음 훈련" if idx < 3 else "실전 시작"
			var btn := _find_button(tut._complete, label)
			if btn == null:
				_tfail("%s: 완료 화면에 「%s」 단추가 없음" % [tag, label])
				return
			await _click(btn.get_global_rect().get_center())
			await _wait(1.0)
			return
		if not tut.active:
			break
		if tut.i != last:
			last = tut.i
			same = 0
		same += 1
		if same > 160:
			print("[tutorial] 멈춤: %s 단계 %d · phase %s · current %d · 짚는 곳 %s · 연출 %s · 선택 %s" % [tag, tut.i, screen.game.phase, screen.game.current, str(tut.focus()), screen._playing, str(screen.game.pending.get("kind", ""))])
			await _shot("%s_stuck" % tag)
			_tfail("%s: 단계 %d에서 멈춤" % [tag, tut.i])
			return
		var f: Array = tut.focus()
		if f[1] == "":
			continue
		var st := tut.step()
		var key := "s%d" % int(st["si"])
		if not shots.has(key) and (int(st["si"]) == 0 or str(f[4]) == "watch" and not shots.has("watch") or st.has("pick") or "all" in OS.get_cmdline_user_args()):
			shots[key] = true
			if str(f[4]) == "watch":
				shots["watch"] = true
			await _wait(0.3)
			await _shot("%s_step%d_%s" % [tag, int(st["si"]) + 1, str(f[4])])
		if f[3]:
			await _click(tut.spot._next.get_global_rect().get_center())
			clicks += 1
			continue
		if screen._choice.visible and not str(st.get("target", "")).begins_with("choice"):
			var bs: Array = screen._choice.find_children("*", "Button", true, false)
			if not bs.is_empty():
				await _click((bs[0] as Control).get_global_rect().get_center())
				clicks += 1
				continue
		if st.has("pick"):
			# 고르기: 「작전 판정」 → 주사위. bad이면 나쁜 눈(2)을 먼저 눌러 되묻는지 본다
			var pk: Dictionary = st["pick"]
			if screen._verb == "":
				await _click(f[0].get_center())
				clicks += 1
				continue
			var good_i := -1
			var bad_i := -1
			for di in screen._actions.focus.get("dice", {}):
				var dd: Dictionary = screen.game.op_dice[di]
				if dd["used"] or int(dd["owner"]) != 0:
					continue
				if int(dd["value"]) == int(pk["good"]):
					good_i = di
				else:
					bad_i = di
			if not bad_done and bad_i >= 0:
				var before: int = screen.game.actions.size()
				await _click(screen._actions.focus["dice"][bad_i].get_global_rect().get_center())
				clicks += 1
				await _wait(0.4)
				if screen.game.actions.size() != before:
					_tfail("%s: 나쁜 눈을 눌렀는데 행동이 들어감" % tag)
				if tut._bad_say == "":
					_tfail("%s: 나쁜 눈을 눌러도 되묻지 않음" % tag)
				else:
					bad_done = true
					await _shot("%s_pick_bad" % tag)
				continue
			if good_i >= 0:
				await _click(screen._actions.focus["dice"][good_i].get_global_rect().get_center())
				clicks += 1
			continue
		var tgt := str(st.get("target", ""))
		if tgt.begins_with("act:") and tgt.split(":").size() == 2 and screen._verb != "":
			# 행동을 골랐고 아무 주사위나 내면 되는 단계: 쓸 수 있는 주사위 하나를 누른다
			var any_i := -1
			for di in screen._actions.focus.get("dice", {}):
				var d2: Dictionary = screen.game.op_dice[di]
				if not d2["used"] and int(d2["owner"]) == 0:
					any_i = di
					break
			if any_i >= 0:
				await _click(screen._actions.focus["dice"][any_i].get_global_rect().get_center())
				clicks += 1
				continue
		var r: Rect2 = f[0]
		if r.size != Vector2.ZERO:
			await _click(r.get_center())
			clicks += 1
	_tfail("%s: 끝나지 않음" % tag)


func _tut_skip() -> void:
	## 건너뛰기: 훈련 1 어디서든 「훈련 건너뛰기」를 두 번 눌러 메뉴로 (훈련 ✔는 안 붙고, 더는 처음 켤 때 권하지 않음)
	main._tutorial_v2(0)
	await _wait(1.5)
	var screen = main._screen
	var tut: TutorialV2 = screen._tutor
	var skip := tut.spot._skip
	await _click(skip.get_global_rect().get_center())
	await _wait(0.2)
	await _click(skip.get_global_rect().get_center())
	await _wait(1.0)
	if main._screen is GameScreenV2:
		_tfail("건너뛰기 뒤에도 게임 화면")
	if not Prefs.v2_training_done:
		_tfail("건너뛰었는데 v2_training_done이 꺼져 있음")
	if Prefs.v2_trainings.has("t1"):
		_tfail("건너뛰었는데 훈련 1에 ✔")
	print("[tutorial] 건너뛰기 확인 · 화면 ", main._screen.get_class())


func _tut_menu() -> void:
	## 중간에 메뉴로 나갔다가 다시 시작: 이어하기 저장이 생기지 않고, 훈련 1이 처음 단계부터 다시 시작
	SaveGameV2.erase()
	main._tutorial_v2(0)
	await _wait(1.5)
	var screen = main._screen
	var tut: TutorialV2 = screen._tutor
	for n in 120:
		await _wait(0.25)
		if tut.i >= 4:
			break
		var f: Array = tut.focus()
		if f[1] == "":
			continue
		if f[3]:
			await _click(tut.spot._next.get_global_rect().get_center())
			continue
		var r: Rect2 = f[0]
		if r.size != Vector2.ZERO:
			await _click(r.get_center())
	print("[tutorial] 나가기 전 단계 ", tut.i)
	screen._pause()
	await _wait(0.4)
	var leave := _find_button(screen._choice, "훈련 그만두고 메인 메뉴로")
	if leave == null:
		_tfail("일시정지 메뉴에 「훈련 그만두고 메인 메뉴로」가 없음")
		return
	await _click(leave.get_global_rect().get_center())
	await _wait(1.0)
	if main._screen is GameScreenV2:
		_tfail("메뉴로 나갔는데 게임 화면")
	if SaveGameV2.exists():
		_tfail("훈련에서 나왔는데 이어하기 저장이 생김")
	main._tutorial_v2(0)
	await _wait(1.5)
	var tut2: TutorialV2 = main._screen._tutor
	if tut2.i != 0 or main._screen.game.day != 1:
		_tfail("다시 시작했는데 처음 단계가 아님 (단계 %d)" % tut2.i)
	print("[tutorial] 다시 시작 단계 ", tut2.i)


func _tut_help() -> void:
	## 도움말 창: 탭마다 한 장 (위쪽 「?」로 열고, 탭을 눌러 본다)
	var data := GameDataV2.load_default()
	var defs := []
	for id in ["park", "jeong", "gaeddong", "oh"]:
		defs.append({"name": "나" if defs.is_empty() else str(data.character(id).get("name", "")), "character": id})
	var game := RulesV2.new()
	game.setup(defs, 20450815, data)
	var screen := GameScreenV2.new(game, 0, {})
	main._swap(screen)
	await _wait(1.0)
	var q := _find_button(screen._top, "?")
	if q == null:
		_tfail("위쪽 띠에 「?」 단추가 없음")
		return
	await _click(q.get_global_rect().get_center())
	await _wait(0.5)
	if not screen._paused or not screen._choice.visible:
		_tfail("「?」를 눌러도 도움말 창이 안 열림")
		return
	await _shot("help_first")
	for tab in ["미션", "타일", "판정", "경찰 · 노출", "결행 · 2막"]:
		var b := _find_button(screen._choice, tab)
		if b == null:
			_tfail("도움말 탭 「%s」가 없음" % tab)
			continue
		await _click(b.get_global_rect().get_center())
		await _wait(0.3)
		await _shot("help_" + tab.replace(" · ", "_"))
	var cl := _find_button(screen._choice, "닫기")
	await _click(cl.get_global_rect().get_center())
	await _wait(0.4)
	if screen._paused:
		_tfail("닫기를 눌러도 판이 멈춰 있음")


func _tut_notes() -> void:
	## 실전 첫 판 쪽지: 새 판을 AI로 돌리며 쪽지가 처음에만, 판을 멈추지 않고 뜨는지
	Prefs.v2_tips = true
	Prefs.v2_notes_seen = []
	var data := GameDataV2.load_default()
	var defs := []
	for id in ["park", "jeong", "gaeddong", "oh"]:
		defs.append({"name": "나" if defs.is_empty() else str(data.character(id).get("name", "")), "character": id})
	var game := RulesV2.new()
	game.setup(defs, 20450815, data)
	var screen := GameScreenV2.new(game, 0, {})
	main._swap(screen)
	await _wait(1.0)
	var shown := {}
	var shot_taken := false
	var steps := 0
	for n in 1500:
		await _wait(0.2)
		if game.phase == "over":
			break
		if screen._tip.visible:
			var key: String = screen._coach._cur
			if key != "" and not shown.has(key):
				shown[key] = 1
				if not shot_taken:
					shot_taken = true
					await _shot("note_%s" % key)
			elif key != "" and shown.has(key):
				shown[key] += 1
			if shown.size() >= 3 and n > 200:
				break
		if screen.is_idle() and screen._ai_actor() < 0:
			var a := GameAIV2.decide(game, 0)
			if not a.is_empty():
				screen.act_now(a)
				steps += 1
	print("[tutorial] 쪽지: ", shown, " · 사람 행동 ", steps, " · 본 쪽지 ", Prefs.v2_notes_seen)
	if shown.is_empty():
		_tfail("쪽지가 하나도 뜨지 않음")
	for k in shown:
		if int(Prefs.v2_notes_seen.count(k)) != 1:
			_tfail("쪽지 %s가 한 번이 아님" % k)
	if steps < 3:
		_tfail("쪽지가 떠 있는 동안 판이 멈춤 (사람 행동 %d)" % steps)
	# 도움말 창
	screen._show_rules("police")
	await _wait(0.4)
	await _shot("help_police")
	screen._choice.visible = false
	screen._paused = false


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
