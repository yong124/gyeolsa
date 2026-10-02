extends SceneTree
## v2 AI 판의 지표를 같은 시드 묶음으로 측정한다.
## 옵션: games= seed= players= set=경로=값 sweep=경로=값1,값2 (값에 쉼표가 있으면 set으로 따로 실행)
##       force_strike= force_char= out= data=데이터 폴더(기본 res://data/v2, 수치 실험용 사본)

const ACTION_CAP := 6000


func _init() -> void:
	var opt := {"games": "400", "seed": "610000", "players": "4", "out": "user://v2_balance.json"}
	var sets := []
	var sweep := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("set="):
			sets.append(arg.substr(4))
		elif arg.begins_with("sweep="):
			sweep = arg.substr(6)
		elif arg.contains("="):
			var pair := arg.split("=", false, 1)
			opt[pair[0]] = pair[1]
	var rows := []
	if sweep != "":
		var pair := sweep.split("=", false, 1)
		for value in pair[1].split(","):
			var changes: Array = sets.duplicate()
			changes.append(pair[0] + "=" + value)
			rows.append(_run(opt, changes))
	else:
		rows.append(_run(opt, sets))
	_print_rows(rows)
	var path := str(opt["out"])
	if path.begins_with("user://") or path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"옵션": opt, "결과": rows}, "\t", false, true))
		print("결과 저장: ", path)
	else:
		printerr("결과 파일을 열지 못했습니다: ", path)
	quit(0)


func _run(opt: Dictionary, sets: Array) -> Dictionary:
	var source := GameDataV2.load_default()
	var data := GameDataV2.new()
	var dir := str(opt.get("data", ""))
	data.load_dir(dir if dir != "" else GameDataV2.DIR)
	data.rules = data.rules.duplicate(true) if dir != "" else source.rules.duplicate(true)
	for assignment in sets:
		var pair: Array = str(assignment).split("=", false, 1)
		if pair.size() != 2:
			continue
		var keys: PackedStringArray = pair[0].split(".")
		var node: Dictionary = data.rules
		for i in keys.size() - 1:
			if not node.has(keys[i]) or typeof(node[keys[i]]) != TYPE_DICTIONARY:
				printerr("규칙 경로가 없습니다: ", pair[0])
				quit(2)
				return {}
			node = node[keys[i]]
		if not node.has(keys[-1]):
			printerr("규칙 경로가 없습니다: ", pair[0])
			quit(2)
			return {}
		var value = JSON.parse_string(pair[1])
		node[keys[-1]] = value if value != null else pair[1]
	var n := int(opt.get("games", 400))
	var seed := int(opt.get("seed", 610000))
	var count := int(opt.get("players", 4))
	var force_char := str(opt.get("force_char", ""))
	var force_strike := str(opt.get("force_strike", ""))
	var ids: Array = data.characters.get("characters", []).map(func(c): return c["id"])
	var s := {"games": n, "seed": seed, "players": count, "set": sets, "force_char": force_char, "force_strike": force_strike,
		"ended": 0, "stuck": 0, "rejected": 0, "fallback": 0, "actions": 0, "victory": 0,
		"endings": {}, "launch_days": [], "launch_percent": [], "launch_reason": {}, "act2_days": [],
		"strikes": {}, "strike_wins": {}, "scene_shown": {}, "scene_broken": {}, "stopped_scene": {},
		"saga_dealt": {}, "saga_done": {}, "saga_per_game": 0, "character_games": {}, "character_wins": {},
		"jails": 0, "escapes": 0, "rescues": 0, "confiscated": 0,
		"exposure_peak": 0, "alert_days": {}, "missions": {}, "threats": {}}
	for i in n:
		var selector := RandomNumberGenerator.new()
		selector.seed = seed + i
		var pool: Array = ids.duplicate()
		var chars := []
		if force_char != "" and force_char in pool:
			chars.append(force_char)
			pool.erase(force_char)
		for j in count - chars.size():
			chars.append(pool.pop_at(selector.randi_range(0, pool.size() - 1)))
		var defs := []
		for id in chars:
			defs.append({"name": data.character(str(id)).get("name", str(id)), "character": id})
		var g := RulesV2.new()
		g.setup(defs, seed + i, data)
		if force_strike != "" and data.base_index(force_strike) >= 0:
			# 강제 거점 실험은 시작 첩보를 주므로 자연 선택 판과 구분해 해석한다.
			g.intel[force_strike] = 3
		for p in g.players:
			_inc(s["character_games"], str(p["character"]))
			for id in g.saga_cards(p["id"]):
				_inc(s["saga_dealt"], str(id))
		var before_fallback := GameAIV2.fallback_count
		var steps := 0
		while g.phase != "over" and steps < ACTION_CAP:
			var legal := g.legal_actions()
			if legal.is_empty():
				break
			var pid := GameAIV2.next_actor(g)
			var a := GameAIV2.decide(g, pid)
			if not g.apply(a):
				s["rejected"] += 1
				break
			steps += 1
			for e in g.events:
				match str(e.get("kind", "")):
					"scene": _inc(s["scene_shown"], str(e["id"]))
					"scene_break": _inc(s["scene_broken"], str(e["id"]))
					"mission_done": _inc(s["missions"], str(data.mission(str(e["id"])).get("type", "")))
					"threat": _inc(s["threats"], str(e["id"]))
					"morning": _inc(s["alert_days"], str(g.alert_level()))
					"rescue": s["rescues"] += 1
					"confiscate": s["confiscated"] += e["items"].size()
			g.events.clear()
			s["exposure_peak"] = maxi(int(s["exposure_peak"]), g.exposure)
		s["actions"] += steps
		s["fallback"] += GameAIV2.fallback_count - before_fallback
		if g.phase != "over":
			s["stuck"] += 1
			if s["stuck"] <= 5:
				print("멈춘 판 %d: 단계 %s · 날 %d · 현재 %d · 동작 %d" % [i, g.phase, g.day, g.current, steps])
			continue
		s["ended"] += 1
		var won: bool = g.ending.get("id", "") == "victory"
		if won:
			s["victory"] += 1
		_inc(s["endings"], str(g.ending.get("id", "")))
		if g.act == 2:
			var strike := str(g.launch_info.get("target", ""))
			_inc(s["strikes"], strike)
			if won:
				_inc(s["strike_wins"], strike)
			s["launch_days"].append(int(g.launch_info.get("day", 0)))
			s["launch_percent"].append(100.0 * float(g.launch_info.get("day", 0)) / float(maxi(1, g.rounds_total)))
			_inc(s["launch_reason"], str(g.launch_info.get("reason", "")))
			s["act2_days"].append(g.day - int(g.launch_info.get("day", g.day)) + 1)
			if not won and not g.current_scene().is_empty():
				_inc(s["stopped_scene"], str(g.current_scene().get("id", "")))
		for p in g.players:
			if won:
				_inc(s["character_wins"], str(p["character"]))
			s["jails"] += int(p["stats"]["jailed"])
			s["escapes"] += int(p["stats"]["escapes"])
			if str(p["saga_done"]) != "":
				_inc(s["saga_done"], str(p["saga_done"]))
				s["saga_per_game"] += 1
	s["win_rate"] = _rate(s["victory"], n)
	s["standard_error"] = sqrt(float(s["win_rate"]) * (1.0 - float(s["win_rate"])) / float(maxi(n, 1)))
	s["launch_day_mean"] = _mean(s["launch_days"])
	s["launch_percent_mean"] = _mean(s["launch_percent"])
	s["act2_days_mean"] = _mean(s["act2_days"])
	s["vote_rate"] = _rate(int(s["launch_reason"].get("vote", 0)), s["launch_days"].size())
	s["saga_per_game"] = float(s["saga_per_game"]) / float(maxi(n, 1))
	s["ending_rate"] = _rates(s["endings"], n)
	s["strike_share"] = _rates(s["strikes"], s["launch_days"].size())
	s["strike_win_rate"] = _ratios(s["strike_wins"], s["strikes"])
	s["scene_break_rate"] = _ratios(s["scene_broken"], s["scene_shown"])
	s["saga_rate"] = _ratios(s["saga_done"], s["saga_dealt"])
	s["character_win_rate"] = _ratios(s["character_wins"], s["character_games"])
	s["character_diff_pp"] = {}
	for id in s["character_win_rate"]:
		s["character_diff_pp"][id] = 100.0 * (float(s["character_win_rate"][id]) - float(s["win_rate"]))
	return s


func _inc(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


func _rate(hit: int, total: int) -> float:
	return float(hit) / float(maxi(total, 1))


func _rates(hits: Dictionary, total: int) -> Dictionary:
	var out := {}
	for key in hits:
		out[key] = _rate(int(hits[key]), total)
	return out


func _ratios(hits: Dictionary, totals: Dictionary) -> Dictionary:
	var out := {}
	for key in totals:
		out[key] = _rate(int(hits.get(key, 0)), int(totals[key]))
	return out


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _print_rows(rows: Array) -> void:
	print("--- v2 밸런스 측정 ---")
	print("설정 | 승률 | 표준오차 | 결행 시점 | 투표 | 2막 | 멈춤 | 대체")
	for r in rows:
		print("%s | %.1f%% | %.1f%%p | %.1f%% | %.1f%% | %.2f일 | %d | %d" % [
			str(r["set"]), 100.0 * r["win_rate"], 100.0 * r["standard_error"], r["launch_percent_mean"],
			100.0 * r["vote_rate"], r["act2_days_mean"], r["stuck"], r["fallback"]])
		print("엔딩: ", r["endings"], " · 거점: ", r["strikes"])
		print("거점별 승률: ", r["strike_win_rate"], " · 장면 돌파율: ", r["scene_break_rate"])
		print("사연 이룸률: ", r["saga_rate"], " · 캐릭터 승률 차이(%p): ", r["character_diff_pp"])
		print("투옥 %d · 탈옥 %d · 구출 %d · 압수 %d장 · 판당 사연 %.2f" % [r["jails"], r["escapes"], r["rescues"], r["confiscated"], r["saga_per_game"]])
