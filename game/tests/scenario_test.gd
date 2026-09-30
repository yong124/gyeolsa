extends SceneTree
## 특수 작전 검증: 작전마다 AI끼리 N판 → 대성공 확률, 불법 액션·교착 검사.
## 목표 범위(대성공 25~60%)를 벗어나면 경고만 한다 (밸런스 조정 참고용).
## 실행: godot --headless --path game --script res://tests/scenario_test.gd [-- 판수]


func _init() -> void:
	var data := GameData.load_default()
	var games := 200
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			games = int(a)
	var failures := 0
	var order: Array = data.text["agents"]["order"]
	for op in data.special_ops():
		var n: int = int(op["players"])
		var wins := 0
		var days := 0.0
		for i in games:
			var defs := []
			for s in n:
				var d := {"name": "요원 %d" % s, "faction": data.faction_keys()[s % 3], "ai": true}
				if s > 0:
					d["personality"] = order[(s - 1) % order.size()]
				defs.append(d)
			var g := GameRules.new()
			g.scenario = op.get("scenario", {}).duplicate(true)
			g.setup(defs, 3000 + i, data)
			if i == 0:
				for idx in op["scenario"].get("start_jailed", []):
					if not g.players[int(idx)]["jailed"]:
						failures += 1
						push_error("%s: 감옥에서 시작하지 않음" % op["id"])
			var guard := 0
			while g.phase != "over" and guard < 20000:
				guard += 1
				if not g.apply(GameAI.decide(g)):
					failures += 1
					push_error("%s: AI 액션 거부" % op["id"])
					break
			if g.phase != "over":
				failures += 1
				push_error("%s: 끝나지 않음" % op["id"])
			if g.ending.get("id", "") == "victory":
				wins += 1
				days += g.rounds_total - g.rounds_left
		var rate := 100.0 * wins / games
		var note := "" if rate >= 25.0 and rate <= 60.0 else "  ← 범위 밖"
		print("%-10s %d인  대성공 %5.1f%%  (성공 시 평균 %.1f일)%s" % [op["name"], n, rate, days / maxi(wins, 1), note])
	print("실패 %d건" % failures)
	quit(1 if failures > 0 else 0)
