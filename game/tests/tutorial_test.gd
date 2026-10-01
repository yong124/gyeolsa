extends SceneTree
## 튜토리얼 시나리오 검증: 설정이 적용되는지, AI가 둬도 대부분 이길 수 있는지 (사람은 안내를 받으며 둔다).
## 기본 훈련(tutorial)과 2막 훈련(tutorial2)을 모두 검사한다.
## 실행: godot --headless --path game --script res://tests/tutorial_test.gd


func _make(data: GameData, id: String, seed_value: int) -> GameRules:
	## main.gd의 _start_tutorial과 같은 방식으로 판을 만든다 (사람 자리도 AI)
	var sc: Dictionary = data.text[id]["scenario"]
	var g := GameRules.new()
	for k in sc:
		if not k in ["players", "seed"]:
			g.scenario[k] = sc[k]
	var defs: Array = sc["players"].duplicate(true)
	defs[0]["ai"] = true
	g.setup(defs, seed_value, data)
	return g


func _init() -> void:
	var data := GameData.load_default()
	var failures := 0
	var games := 200

	# 기본 훈련
	var sc: Dictionary = data.text["tutorial"]["scenario"]
	var wins := 0
	var days_used := 0
	for i in games:
		var g := _make(data, "tutorial", 1945 + i)
		if i == 0:
			var me: Dictionary = g.players[0]
			if me["mission"]["type"] != sc["first_missions"][0]["type"] or not "scope" in me["items"] or g.goal != int(sc["goal"]):
				failures += 1
				push_error("시나리오 설정이 적용되지 않음: %s %s goal=%d" % [me["mission"], me["items"], g.goal])
			var top: Array = sc["tile_order_top"]
			if g.tile_deck[-1] != top[0] or g.tile_deck[-2] != top[1]:
				failures += 1
				push_error("타일 순서가 다름: %s" % [g.tile_deck.slice(-3)])
		while g.phase != "over":
			if not g.apply(GameAI.decide(g)):
				failures += 1
				break
		if g.ending["id"] == "victory":
			wins += 1
			days_used += g.rounds_total - g.rounds_left + 1
	print("기본 훈련: AI 승률 %.0f%%, 승리 시 평균 %.1f일 사용, 실패 %d건" % [100.0 * wins / games, float(days_used) / maxi(wins, 1), failures])

	# 2막 훈련: 1막 막바지에서 시작해 결행까지 간다
	var sc2: Dictionary = data.text["tutorial2"]["scenario"]
	wins = 0
	var launched := 0
	var prison := 0
	var launch_day := 0.0
	for i in games:
		var g := _make(data, "tutorial2", 815 + i)
		if i == 0:
			if g.score != int(sc2["start_score"]) or g.exposure != int(sc2["start_exposure"]) \
					or int(g.intel[2]) != int(sc2["start_intel"][2]) or g.launch_min() != int(sc2["launch_min"]) or not g.two_act():
				failures += 1
				push_error("2막 훈련 설정이 적용되지 않음: score=%d exposure=%d intel=%s" % [g.score, g.exposure, g.intel])
		var launched_at := -1
		while g.phase != "over":
			if not g.apply(GameAI.decide(g)):
				failures += 1
				push_error("2막 훈련: AI 액션 거부")
				break
			if g.act == 2 and launched_at < 0:
				launched_at = g.rounds_total - g.rounds_left
				if g.strike.get("id", "") == "prison":
					prison += 1
		if launched_at >= 0:
			launched += 1
			launch_day += launched_at
		if g.ending["id"] == "victory":
			wins += 1
	print("2막 훈련: 결행 %.0f%% (형무소 %.0f%%, 평균 %.1f일째), AI 승률 %.0f%%, 실패 %d건" % [
		100.0 * launched / games, 100.0 * prison / maxi(launched, 1), launch_day / maxi(launched, 1), 100.0 * wins / games, failures])
	if launched < games:
		failures += 1
		push_error("2막 훈련에서 결행하지 않은 판이 있음")
	quit(1 if failures > 0 else 0)
