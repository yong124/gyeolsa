extends SceneTree
## 2막 구조 검증 (기획서 16.7): 인원별 AI N판 → 대성공, 결행 시점·이유, 거점별 선택률과 성공률, 2막 길이.
## 실행: godot --headless --path game --script res://tests/act2_test.gd [-- 판수]


func _init() -> void:
	var data := GameData.load_default()
	var games := 300
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			games = int(a)
	var failures := 0
	var order: Array = data.text["agents"]["order"]
	for n in range(2, 5):
		var ends := {"victory": 0, "operation": 0, "history": 0}
		var launch_at := 0.0
		var launched := 0
		var reasons := {}
		var picked := {}
		var won := {}
		var act2_days := 0.0
		var t_arrests := 0.0
		var t_informs := 0.0
		var t_games := 0
		for i in games:
			var defs := []
			for s in n:
				var d := {"name": "요원 %d" % s, "faction": data.faction_keys()[s % 3], "ai": true}
				if s > 0:
					d["personality"] = order[(s - 1) % order.size()]
				defs.append(d)
			var g := GameRules.new()
			g.setup(defs, 9000 + i, data)
			var launch_day := -1
			var guard := 0
			while g.phase != "over" and guard < 30000:
				guard += 1
				var before := g.act
				if not g.apply(GameAI.decide(g)):
					failures += 1
					push_error("%d인: AI 액션 거부 (phase=%s act=%d pending=%s)" % [n, g.phase, g.act, g.pending.get("kind", "")])
					break
				if before == 1 and g.act == 2:
					launch_day = g.rounds_total - g.rounds_left
					var rs: String = g.history[-1]["text"] if not g.history.is_empty() else "?"
					reasons[rs] = reasons.get(rs, 0) + 1
				g.events.clear()
			if g.phase != "over":
				failures += 1
				push_error("%d인: 끝나지 않음" % n)
				continue
			var tid := g.traitor_id()
			if tid >= 0:
				t_games += 1
				t_arrests += int(g.players[tid]["stats"].get("arrests", 0))
				for line in g.log_lines:
					if "밀고했습니다" in line:
						t_informs += 1
			var e: String = g.ending["id"]
			ends[e] += 1
			if launch_day >= 0:
				launched += 1
				launch_at += float(launch_day) / g.rounds_total
				act2_days += (g.rounds_total - g.rounds_left) - launch_day
				var sid: String = g.strike["id"]
				picked[sid] = picked.get(sid, 0) + 1
				if e == "victory":
					won[sid] = won.get(sid, 0) + 1
		var line := "%d인  대성공 %4.1f%%  실행 %4.1f%%  정사 %4.1f%%  |  결행 %d%% 시점 평균 %.0f%%  2막 %.1f일" % [
			n, 100.0 * ends["victory"] / games, 100.0 * ends["operation"] / games, 100.0 * ends["history"] / games,
			100 * launched / games, 100.0 * launch_at / maxi(launched, 1), act2_days / maxi(launched, 1)]
		print(line)
		var parts := []
		for sid in ["barracks", "police_hq", "prison", "gg"]:
			var c: int = picked.get(sid, 0)
			parts.append("%s 선택 %d%% 성공 %d%%" % [sid, 100 * c / maxi(launched, 1), 100 * won.get(sid, 0) / maxi(c, 1)])
		print("     " + " · ".join(parts))
		if t_games > 0:
			print("     변절자 %d판: 기습 체포 %.2f회, 밀고 %.1f회 (판당)" % [t_games, t_arrests / t_games, t_informs / t_games])
	print("실패 %d건" % failures)
	quit(1 if failures > 0 else 0)
