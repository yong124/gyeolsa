extends Node
## v2 화면 시험: 사람 자리(0번)를 AI 판단으로 흉내 내며 판을 끝까지 둔다.
## 사람이 해야 할 행동이 화면(보드 · 주사위 · 선택 창 · 행동 단추)에 늘 나오는지, 화면이 멈추지 않는지 확인한다.
## 실행: godot --headless --path game -- v2uitest [판수]   (화면은 자동 로드(Music·Sfx)가 필요해 메인 장면을 거쳐 돈다)

var failed := 0
var first := 0        # 첫 판 번호 (여러 프로세스로 나눠 돌릴 때)
var seen := {}        # 거친 화면 종류 {이름: 횟수} (행동 메뉴 · 선택 창 종류)


func _ready() -> void:
	SaveGameV2.disabled = true   # 시험이 실제 이어하기 저장을 건드리지 않게
	ArtV2.disabled = "noart" in OS.get_cmdline_user_args()   # 그림 없이도 화면이 도는가 (R 2.4)
	if "flat" in OS.get_cmdline_user_args():
		Prefs.v2_tilt = false   # 평면 보드 설정도 도는가 (M2)
	Prefs.v2_tips = true   # 가장 넘치기 쉬운 경우(첫 판 고정 안내가 보임)로 잰다. 저장하지 않으므로 설정은 그대로
	var n := 3
	var args := OS.get_cmdline_user_args()
	var i := args.find("v2uitest")
	if i >= 0 and args.size() > i + 1:
		n = int(args[i + 1])
	for a in args:
		if a.begins_with("first="):
			first = int(a.substr(6))
	_run(n)


func _run(n: int) -> void:
	Engine.time_scale = 30.0   # 연출 시간을 줄인다 (트윈·타이머가 빨라짐)
	await get_tree().process_frame
	var data := GameDataV2.load_default()
	var ids: Array = data.characters.get("characters", []).map(func(c): return c["id"])
	var endings := {}
	for g_i in range(first, first + n):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + g_i
		var pool := ids.duplicate()
		var defs := []
		for i in 4:
			var k := rng.randi_range(0, pool.size() - 1)
			defs.append({"name": "나" if i == 0 else str(pool[k]), "character": pool[k]})
			pool.remove_at(k)
		var game := RulesV2.new()
		game.setup(defs, 9100 + g_i)
		var screen := GameScreenV2.new(game, 0, {})
		screen._fast = true
		add_child(screen)
		var idle_frames := 0
		var guard := 0
		var last_day := 0
		var last_acts := -1
		var still_since := Time.get_ticks_msec()
		var overflowed := false
		while game.phase != "over" and guard < 200000:
			guard += 1
			await get_tree().process_frame
			if game.day != last_day:
				last_day = game.day
				print("  판 %d · %d일째 · %d막 · 액션 %d" % [g_i, game.day, game.act, game.actions.size()])
			if game.actions.size() > 3000:
				_fail("판 %d: 액션이 3000개를 넘음 (반복) — phase=%s 최근=%s" % [g_i, game.phase, str(game.actions.slice(game.actions.size() - 6))])
				break
			if game.actions.size() != last_acts:
				last_acts = game.actions.size()
				still_since = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - still_since > 20000:
				_fail("판 %d: 20초 동안 액션이 없음 — phase=%s playing=%s ai_wait=%s paused=%s queue=%d ai=%d choice=%s 최근=%s" % [
					g_i, game.phase, screen._playing, screen._ai_waiting, screen._paused, screen._queue.size(), screen._ai_actor(),
					str(game.pending.get("kind", "")), str(game.actions.slice(maxi(0, game.actions.size() - 3)))])
				break
			if not screen.is_idle():
				idle_frames = 0
				continue
			if screen._ai_actor() >= 0:
				idle_frames += 1
				if idle_frames > 600:
					_fail("판 %d: AI 차례인데 화면이 멈춤 (phase=%s)" % [g_i, game.phase])
					break
				continue
			# 사람이 둘 차례: 오른쪽 패널이 작전 기록 띠를 가리지 않는가 (창 비율이 16:9보다 넓어도 높이는 900 그대로)
			for _f in 4:   # 넘침 맞추기(_fit_right)는 다음 프레임들에 돈다
				await get_tree().process_frame
			var over := screen.right_overflow()
			if over > 1.0 and not overflowed:
				overflowed = true
				_fail("판 %d: 오른쪽 패널이 %.0fpx 넘침 (phase=%s, %d일째 %d막, 화면 %s) — %s" % [g_i, over, game.phase, game.day, game.act, str(screen.size), screen.layout_report()])
			var mine := game.legal_actions().filter(func(a): return int(a.get("player", -1)) == 0)
			if game.phase == "day" and game.can_begin_turn(game.players[0]) and GameAIV2.next_actor(game) != 0:
				screen.press_allies_first()
				continue
			if mine.is_empty():
				idle_frames += 1
				if idle_frames > 600:
					_fail("판 %d: 사람이 할 일이 없는데 진행도 안 됨 (phase=%s, day=%d)" % [g_i, game.phase, game.day])
					break
				continue
			idle_frames = 0
			var a := GameAIV2.decide(game, 0)
			if a.is_empty():
				# 사람은 할 일이 없음 (아침: 동료가 고를 때까지 기다림)
				idle_frames += 1
				if idle_frames > 600:
					var nodie := game.players.filter(func(q): return q["die"] < 0).map(func(q): return "%d(감옥%s)" % [q["id"], q["jailed"]])
					_fail("판 %d: 아무도 두지 않음 — phase=%s 주사위 없는 요원=%s" % [g_i, game.phase, str(nodie)])
					break
				continue
			if int(a.get("player", -1)) != 0:
				a = mine[0]
			if not screen.ui_offers(a):
				_fail("판 %d: 화면에 없는 행동 %s (phase=%s)" % [g_i, str(a), game.phase])
				break
			if a["type"] == "choose":
				var ck := "choose:" + str(game.pending.get("kind", ""))
				seen[ck] = int(seen.get(ck, 0)) + 1
				screen.choose_now(a["value"])
			else:
				if a.has("die") and int(a["die"]) >= 0:
					await _try_menu(screen, game, a, g_i)
				screen.act_now(a)
		endings[game.ending.get("id", "멈춤")] = int(endings.get(game.ending.get("id", "멈춤"), 0)) + 1
		print("판 %d: %s · %d일째 · %d막 · 액션 %d" % [g_i, game.ending.get("id", "-"), game.day, game.act, game.actions.size()])
		screen.queue_free()
		await get_tree().process_frame
	print("엔딩: %s" % str(endings))
	print("거친 화면: %s" % str(seen))
	print("v2 화면 시험: %s" % ("실패 %d건" % failed if failed > 0 else "통과"))
	get_tree().quit(1 if failed > 0 else 0)


func _try_menu(screen: GameScreenV2, game: RulesV2, a: Dictionary, g_i: int) -> void:
	## 행동 메뉴를 실제로 열어 본다: 같은 주사위의 행동이 모두 단추로 나오고, 미리 보기(이동 도달 칸)가 그려지는지
	var die := int(a["die"])
	var acts := game.legal_actions().filter(func(x): return int(x.get("player", -1)) == 0 and x.has("die") and int(x["die"]) == die)
	screen._actions.die_menu(acts, die)
	await get_tree().process_frame
	await get_tree().process_frame
	if screen._actions._menu == null or not is_instance_valid(screen._actions._menu):
		_fail("판 %d: 행동 메뉴가 안 열림 (%s)" % [g_i, str(a)])
		return
	seen["menu"] = int(seen.get("menu", 0)) + 1
	seen["menu:" + str(a["type"])] = int(seen.get("menu:" + str(a["type"]), 0)) + 1
	for x in acts:
		screen._actions.hover_action(x)
		if x["type"] == "move_die":
			if screen._board.reach.is_empty() and not game.reach_cells(game.players[0], game.move_value(game.players[0], die)).is_empty():
				_fail("판 %d: 이동 미리 보기가 비어 있음" % g_i)
		if screen._actions.hint(x) == null:
			_fail("판 %d: 힌트 없음" % g_i)
	screen._actions.close_menu()


func _fail(msg: String) -> void:
	failed += 1
	print("FAIL ", msg)
