extends SceneTree
## 플레이테스트 기록 재생 검증: AI끼리 둔 판을 기록(JSON)으로 쓰고 읽은 뒤, 시드와 액션만으로 다시 두어 같은 결말이 나오는지.
## 무작위 시드(-1), 특수 작전, 난이도, 핫시트(사람 여러 자리) 설정을 섞는다.
## 실행: godot --headless --path game --script res://tests/replay_test.gd [-- 판수]

func _init() -> void:
	var data := GameData.load_default()
	var games := 60
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			games = int(a)
	PlaytestLog.disabled = true
	var failures := 0
	var ops := data.special_ops()
	for i in games:
		var n := 2 + i % 3
		var defs := []
		for s in n:
			defs.append({"name": "요원 %d" % s, "faction": data.faction_keys()[s % 3], "ai": true})
		var cfg := {"defs": defs, "difficulty": [0, 1, -1][i % 3], "seed": -1}
		if i % 5 == 4:
			var op: Dictionary = ops[i % ops.size()]
			cfg["scenario"] = op["id"]
			cfg["difficulty"] = 0
			defs.resize(int(op["players"]))
			for s in defs.size():
				if defs[s] == null:
					defs[s] = {"name": "요원 %d" % s, "faction": data.faction_keys()[s % 3], "ai": true}
		var g := GameRules.from_cfg(cfg, data)
		var log := PlaytestLog.begin(g, cfg)
		while g.phase != "over":
			if not g.apply(GameAI.decide(g)):
				failures += 1
				push_error("AI 액션 거부")
				break
		PlaytestLog.finish(log, g)
		var back = JSON.parse_string(JSON.stringify(PlaytestLog._plain(log)))
		var why := _replay(back, data)
		if why != "":
			failures += 1
			push_error("재생 결과가 다름 (%d판째, %s): %s" % [i, cfg.get("scenario", "일반"), why])
	print("기록 재생 %d판, 실패 %d건" % [games, failures])
	quit(1 if failures > 0 else 0)


func _replay(l: Dictionary, data: GameData) -> String:
	var g := GameRules.from_cfg(l["cfg"], data, int(l["seed"]))
	for a in l["actions"]:
		var act := {}
		for k in a:
			var v = a[k]
			if v is Array and v.size() == 2 and k in ["to", "cell", "pos"]:
				v = Vector2i(int(v[0]), int(v[1]))
			elif v is float and v == floorf(v):
				v = int(v)
			act[k] = v
		if not g.apply(act):
			return "액션 거부 %s" % [a]
	if g.ending.get("id", "") != l["ending"]["id"] or g.score != int(l["final"]["score"]) or g.rounds_left != int(l["final"]["days_left"]):
		return "결말 %s/%d vs 기록 %s/%d" % [g.ending.get("id", ""), g.score, l["ending"]["id"], int(l["final"]["score"])]
	return ""
