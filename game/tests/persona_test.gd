extends SceneTree
## 동료 성격과 이동 되돌리기 검증.
## 1) 성격 있는 동료 vs 성격 없는 동료: 4인 승률이 크게 달라지지 않는지 (밸런스)
## 2) 되돌리기: 한 칸 걷고 되돌린 뒤 다시 같은 칸을 걸으면, 되돌리지 않은 판과 상태가 완전히 같은지 (결정성)
## 실행: godot --headless --path game --script res://tests/persona_test.gd [-- 판수]


func _init() -> void:
	var data := GameData.load_default()
	var games := 200
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			games = int(a)
	var failures := 0
	var agents: Dictionary = data.text["agents"]
	var order: Array = agents["order"]
	for with_persona in [false, true]:
		var wins := 0
		var jailed := 0.0
		for i in games:
			var defs := []
			for s in 4:
				var f: String = data.faction_keys()[s % 3]
				var d := {"name": "요원 %d (%s)" % [s, f], "faction": f, "ai": true}
				if with_persona and s > 0:
					d["personality"] = order[(s - 1) % order.size()]
				defs.append(d)
			var g := GameRules.new()
			g.setup(defs, 7000 + i, data)
			var guard := 0
			while g.phase != "over" and guard < 20000:
				guard += 1
				if g.phase == "start" or g.phase == "move":
					GameAI.intent(g, g.cur())   # 대사 선택이 오류 없이 되는지
				if not g.apply(GameAI.decide(g)):
					failures += 1
					push_error("AI 액션 거부 (성격=%s)" % with_persona)
					break
			if g.ending.get("id", "") == "victory":
				wins += 1
			for p in g.players:
				jailed += p["stats"]["jailed"]
		print("%s  대성공 %.1f%%  투옥 %.1f" % ["성격 있음" if with_persona else "성격 없음", 100.0 * wins / games, jailed / games])

	# 되돌리기 결정성
	var undo_checks := 0
	for i in 60:
		var defs := []
		for s in 3:
			defs.append({"name": "요원 %d" % s, "faction": data.faction_keys()[s], "ai": true})
		var a := GameRules.new()
		var b := GameRules.new()
		a.setup(defs.duplicate(true), 900 + i, data)
		b.setup(defs.duplicate(true), 900 + i, data)
		var guard := 0
		while a.phase != "over" and guard < 20000:
			guard += 1
			var act := GameAI.decide(a)
			a.apply(act)
			b.apply(act)
			if act["type"] == "step" and b.can_undo_step():
				b.apply({"type": "undo_step"})
				if not b.apply(act):
					failures += 1
					push_error("되돌린 뒤 같은 칸을 다시 걸을 수 없음")
					break
				undo_checks += 1
			a.events.clear()
			b.events.clear()
		var sa := a.save_state()
		var sb := b.save_state()
		for k in ["log_lines", "history", "undo_steps", "actions"]:
			sa.erase(k)
			sb.erase(k)
		if var_to_str(sa) != var_to_str(sb):
			failures += 1
			push_error("되돌리기 후 상태가 다름 (seed %d)" % (900 + i))
	print("되돌리기 검증 %d회, 실패 %d건" % [undo_checks, failures])
	quit(1 if failures > 0 else 0)
