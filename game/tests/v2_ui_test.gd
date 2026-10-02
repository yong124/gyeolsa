extends Node
## v2 화면 시험: 사람 자리(0번)를 AI 판단으로 흉내 내며 판을 끝까지 둔다.
## 사람이 해야 할 행동이 화면(보드 · 주사위 · 선택 창 · 행동 단추)에 늘 나오는지, 화면이 멈추지 않는지 확인한다.
## 실행: godot --headless --path game -- v2uitest [판수]   (화면은 자동 로드(Music·Sfx)가 필요해 메인 장면을 거쳐 돈다)

var failed := 0
var first := 0        # 첫 판 번호 (여러 프로세스로 나눠 돌릴 때)


func _ready() -> void:
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
			# 사람이 둘 차례
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
				screen.choose_now(a["value"])
			else:
				screen.act_now(a)
		endings[game.ending.get("id", "멈춤")] = int(endings.get(game.ending.get("id", "멈춤"), 0)) + 1
		print("판 %d: %s · %d일째 · %d막 · 액션 %d" % [g_i, game.ending.get("id", "-"), game.day, game.act, game.actions.size()])
		screen.queue_free()
		await get_tree().process_frame
	print("엔딩: %s" % str(endings))
	print("v2 화면 시험: %s" % ("실패 %d건" % failed if failed > 0 else "통과"))
	get_tree().quit(1 if failed > 0 else 0)


func _fail(msg: String) -> void:
	failed += 1
	print("FAIL ", msg)
