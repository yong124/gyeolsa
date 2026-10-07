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
		"saga_dealt": {}, "saga_done": {}, "saga_lost": {}, "saga_kept": {}, "saga_kept_done": {}, "saga_per_game": 0, "character_games": {}, "character_wins": {},
		"jails": 0, "escapes": 0, "rescues": 0, "confiscated": 0, "action_types": {}, "benefits": {}, "funds_gained": 0, "funds_spent": {}, "funds_lost": 0, "funds_end": [], "mission_offered": {}, "mission_missed": {}, "ops_seen": {}, "ops_blocked": {}, "ops_missed": {}, "trend_at_launch": [], "reinforce_at_launch": [],
		"exposure_sum": 0, "exposure_days": 0, "counter_days": 0, "counter_blocked": 0, "vote_target": {}, "dice_rolled": 0, "dice_left": 0, "turns": 0,
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
		var dealt_by: Array = g.players.map(func(p): return g.saga_cards(p["id"]).duplicate())
		var before_fallback := GameAIV2.fallback_count
		var steps := 0
		while g.phase != "over" and steps < ACTION_CAP:
			var legal := g.legal_actions()
			if legal.is_empty():
				break
			var pid := GameAIV2.next_actor(g)
			var a := GameAIV2.decide(g, pid)
			if str(a.get("type", "")) == "end_turn":
				s["turns"] += 1
				s["dice_left"] += g.my_dice(int(a["player"])).size()   # 차례를 마치며 쓰지 않고 남긴 주사위
			if not g.apply(a):
				s["rejected"] += 1
				break
			_inc(s["action_types"], str(a["type"]))
			steps += 1
			for e in g.events:
				match str(e.get("kind", "")):
					"scene": _inc(s["scene_shown"], str(e["id"]))
					"scene_break": _inc(s["scene_broken"], str(e["id"]))
					"mission_done": _inc(s["missions"], str(data.mission(str(e["id"])).get("type", "")))
					"card":
						if str(e.get("deck", "")) == "mission":
							_inc(s["mission_offered"], str(data.mission(str(e["id"])).get("type", "")))
					"mission_missed": _inc(s["mission_missed"], str(data.mission(str(e["id"])).get("type", "")))
					"funds":
						var ch := int(e.get("change", 0))
						if ch > 0:
							s["funds_gained"] += ch
						elif ch < 0 and str(e.get("why", "")) in ["lose", "cap"]:
							s["funds_lost"] += -ch
						elif ch < 0:
							s["funds_spent"][str(e.get("why", "?"))] = int(s["funds_spent"].get(str(e.get("why", "?")), 0)) + -ch
					"op_appear": _inc(s["ops_seen"], str(e["id"]))
					"op_blocked": _inc(s["ops_blocked"], str(e["id"]))
					"op_missed": _inc(s["ops_missed"], str(e["id"]))
					"threat": _inc(s["threats"], str(e["id"]))
					"morning":
						_inc(s["alert_days"], str(g.alert_level()))
						s["exposure_sum"] += g.exposure
						s["exposure_days"] += 1
					"rescue": s["rescues"] += 1
					"benefit": _inc(s["benefits"], str(e["id"]))
					"counter": s["counter_days"] += 1
					"counter_blocked": s["counter_blocked"] += 1
					"vote_reveal":
						for tp in e["targets"]:
							_inc(s["vote_target"], str(e["targets"][tp]))
					"dice_rolled":
						if not e.get("again", false):
							s["dice_rolled"] += e["values"].size()
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
		s["funds_end"].append(g.funds)
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
			s["trend_at_launch"].append(int(g.launch_info.get("trend", 0)))
			s["reinforce_at_launch"].append(int(g.launch_info.get("reinforce", 0)))
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
			if str(p["saga_kept"]) != "":
				_inc(s["saga_kept"], str(p["saga_kept"]))
				if str(p["saga_done"]) == str(p["saga_kept"]):
					_inc(s["saga_kept_done"], str(p["saga_kept"]))
			if str(p["saga_done"]) != "":
				_inc(s["saga_done"], str(p["saga_done"]))
				for other in dealt_by[int(p["id"])]:
					if str(other) != str(p["saga_done"]):
						_inc(s["saga_lost"], str(other))   # 다른 사연을 먼저 이뤄서 기회가 없어진 장
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
	# 기회가 남았던 장 기준 이룸률: 받은 장 − 같은 요원이 다른 사연을 먼저 이뤄 못 쓰게 된 장
	var chance := {}
	for id in s["saga_dealt"]:
		chance[id] = int(s["saga_dealt"][id]) - int(s["saga_lost"].get(id, 0))
	s["saga_rate_open"] = _ratios(s["saga_done"], chance)
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


func _counts(values: Array) -> Dictionary:
	var out := {}
	for v in values:
		_inc(out, str(int(v)))
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
		var sr := []
		for id in r["saga_rate"]:
			sr.append("%s %d%%/%d%%" % [id, roundi(100.0 * float(r["saga_rate"][id])), roundi(100.0 * float(r["saga_rate_open"].get(id, 0.0)))])
		print("사연 이룸률(받은 장 / 기회가 남았던 장): ", ", ".join(sr))
		var kr := []
		for id in r["saga_kept"]:
			kr.append("%s %d/%d" % [id, int(r["saga_kept_done"].get(id, 0)), int(r["saga_kept"][id])])
		print("결행에 품고 간 사연(이룸/품음): ", ", ".join(kr))
		print("투옥 %d · 탈옥 %d · 구출 %d · 압수 %d장 · 판당 사연 %.2f" % [r["jails"], r["escapes"], r["rescues"], r["confiscated"], r["saga_per_game"]])
		var per_game := {}
		for k in r["action_types"]:
			per_game[k] = snappedf(float(r["action_types"][k]) / float(maxi(int(r["games"]), 1)), 0.1)
		print("판당 행동: ", per_game)
		print("결행 대상 표 분포: ", r["vote_target"], " · 결행 혜택 선택: ", r["benefits"])
		var done_rate := {}
		for t in r["mission_offered"]:
			done_rate[t] = "%d/%d (%.0f%%)" % [int(r["missions"].get(t, 0)), int(r["mission_offered"][t]), 100.0 * float(r["missions"].get(t, 0)) / float(maxi(int(r["mission_offered"][t]), 1))]
		var missed_total := 0
		for t in r["mission_missed"]:
			missed_total += int(r["mission_missed"][t])
		print("미션 종류별 이룬 비율(이룬/나온): ", done_rate, " · 놓친 미션 %d (판당 %.2f) %s" % [missed_total, float(missed_total) / float(maxi(int(r["games"]), 1)), r["mission_missed"]])
		var ops_n := 0
		var ops_b := 0
		for k in r["ops_seen"]:
			ops_n += int(r["ops_seen"][k])
			ops_b += int(r["ops_blocked"].get(k, 0))
		print("일제 작전 %d번 중 막은 것 %d번 (%.1f%%) · 놓친 것 %s · 막은 것 %s" % [ops_n, ops_b, 100.0 * float(ops_b) / float(maxi(ops_n, 1)), r["ops_missed"], r["ops_blocked"]])
		print("결행 때 일제 동향 평균 %.2f (분포 %s) · 증원 평균 %.2f장 · 판당 하루 아침 노출 평균 %.2f" % [_mean(r["trend_at_launch"]), _counts(r["trend_at_launch"]), _mean(r["reinforce_at_launch"]),
			float(r["exposure_sum"]) / float(maxi(int(r["exposure_days"]), 1))])
		var spent_total := 0
		for w in r["funds_spent"]:
			spent_total += int(r["funds_spent"][w])
		var games_f := float(maxi(int(r["games"]), 1))
		print("군자금: 판당 번 돈 %.2f · 쓴 돈 %.2f %s · 잃은 돈 %.2f · 끝에 남은 돈 평균 %.2f (분포 %s)" % [float(r["funds_gained"]) / games_f, float(spent_total) / games_f,
			r["funds_spent"], float(r["funds_lost"]) / games_f, _mean(r["funds_end"]), _counts(r["funds_end"])])
		print("반격 %d번 중 막은 것 %d번 (%.1f%%)" % [r["counter_days"], r["counter_blocked"], 100.0 * float(r["counter_blocked"]) / float(maxi(int(r["counter_days"]), 1))])
		print("굴린 주사위 %d개 중 차례를 마치며 남긴 것 %d개 (%.1f%%) · 차례 %d번" % [r["dice_rolled"], r["dice_left"],
			100.0 * float(r["dice_left"]) / float(maxi(int(r["dice_rolled"]), 1)), r["turns"]])
