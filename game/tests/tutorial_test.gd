extends SceneTree
## 튜토리얼 시나리오 검증: 설정이 적용되는지, AI가 둬도 대부분 이길 수 있는지 (사람은 안내를 받으며 둔다).
## 실행: godot --headless --path game --script res://tests/tutorial_test.gd


func _init() -> void:
	var data := GameData.load_default()
	var sc: Dictionary = data.text["tutorial"]["scenario"]
	var wins := 0
	var days_used := 0
	var failures := 0
	var games := 200
	for i in games:
		var g := GameRules.new()
		for k in ["goal", "rounds", "first_missions", "start_items", "tile_order_top", "two_act"]:
			g.scenario[k] = sc[k]
		var defs: Array = sc["players"].duplicate(true)
		defs[0]["ai"] = true
		g.setup(defs, 1945 + i, data)
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
	print("튜토리얼: AI 승률 %.0f%%, 승리 시 평균 %.1f일 사용, 실패 %d건" % [100.0 * wins / games, float(days_used) / maxi(wins, 1), failures])
	quit(1 if failures > 0 else 0)
