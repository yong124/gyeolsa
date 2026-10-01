extends SceneTree
## 플레이테스트 기록 요약: 폴더 안의 *.json을 모두 읽어 결과·결행·생각 시간·설문을 모아 보여 준다.
## 기록마다 시드와 액션으로 판을 다시 재생해, 같은 결말이 나오는지도 확인한다 (재생 검증).
## 실행: godot --headless --path game --script res://tools/playtest_report.gd [-- 폴더] [md=보고서.md]
## 폴더를 주지 않으면 이 컴퓨터의 user://playtests를 읽는다. md=를 주면 마크다운으로도 쓴다.

var _out: PackedStringArray = []


func _p(s := "") -> void:
	print(s)
	_out.append(s)


func _init() -> void:
	var dir := PlaytestLog.dir
	var md := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("md="):
			md = a.substr(3)
		elif a != "":
			dir = a
	var data := GameData.load_default()
	var logs := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
			if typeof(parsed) == TYPE_DICTIONARY:
				logs.append(parsed)
	_p("# 플레이테스트 요약")
	_p("")
	_p("기록 %d판 (%s)" % [logs.size(), ProjectSettings.globalize_path(dir)])
	if logs.is_empty():
		_finish(md)
		return

	# ---- 결과
	var finished := logs.filter(func(l): return l.get("ending", {}).get("id", "paused") != "paused")
	_p("")
	_p("## 결과")
	_p("")
	_p("| 인원 | 사람 | 판 | 대성공 | 결행 | 평균 결행일 (남은 날) | 평균 플레이 시간 |")
	_p("|---|---|---|---|---|---|---|")
	var groups := {}
	for l in finished:
		var n: int = l["players"].size()
		var h: int = l["players"].filter(func(p): return not p["ai"]).size()
		var k := "%d|%d" % [n, h]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(l)
	for k in groups:
		var g: Array = groups[k]
		var wins := g.filter(func(l): return l["ending"]["id"] == "victory").size()
		var launched := g.filter(func(l): return not l.get("launch", {}).is_empty())
		var ld := 0.0
		for l in launched:
			ld += float(l["launch"]["days_left"])
		var mins := 0.0
		for l in g:
			mins += float(l.get("play_seconds", 0)) / 60.0
		var parts: PackedStringArray = k.split("|")
		_p("| %s인 | %s명 | %d | %d (%.0f%%) | %d | %s | %.0f분 |" % [parts[0], parts[1], g.size(), wins, 100.0 * wins / g.size(),
			launched.size(), "%.1f" % (ld / launched.size()) if launched.size() > 0 else "-", mins / g.size()])
	var paused := logs.size() - finished.size()
	if paused > 0:
		_p("")
		_p("중간에 그만둔 판 %d개" % paused)

	# ---- 결행
	_p("")
	_p("## 결행")
	_p("")
	var reasons := {}
	var targets := {}
	var traitor := {"won": 0, "lost": 0}
	for l in finished:
		var r: String = l.get("launch", {}).get("reason", "안 함")
		reasons[r] = int(reasons.get(r, 0)) + 1
		var t: String = l["ending"].get("strike", "")
		if t != "":
			if not targets.has(t):
				targets[t] = [0, 0]
			targets[t][0] += 1
			if l["ending"]["id"] == "victory":
				targets[t][1] += 1
		if int(l["ending"].get("traitor", -1)) >= 0:
			traitor["won" if l["ending"].get("traitor_won", false) else "lost"] += 1
	_p("선언 방식: %s" % _fmt(reasons, {"vote": "투표", "forced": "작전일 임박", "exposed": "노출 한계"}))
	var tl := PackedStringArray()
	for t in targets:
		tl.append("%s %d판 (성공 %d)" % [data.text["strikes"].get(t, {}).get("name", t), targets[t][0], targets[t][1]])
	_p("목표: %s" % (", ".join(tl) if not tl.is_empty() else "-"))
	if traitor["won"] + traitor["lost"] > 0:
		_p("변절자: %d승 %d패" % [traitor["won"], traitor["lost"]])

	# ---- 생각 시간
	_p("")
	_p("## 생각 시간 (사람 차례)")
	_p("")
	var secs := []
	var undos := 0
	var by_act := {1: [], 2: []}
	for l in logs:
		for t in l.get("turns", []):
			secs.append(float(t["seconds"]))
			undos += int(t.get("undos", 0))
			by_act[int(t.get("act", 1))].append(float(t["seconds"]))
	if not secs.is_empty():
		secs.sort()
		_p("차례 %d번 · 중앙값 %.0f초 · 상위 10%% %.0f초 · 가장 긴 차례 %.0f초 · 되돌리기 %d번" % [
			secs.size(), secs[secs.size() / 2], secs[int(secs.size() * 0.9)], secs[-1], undos])
		for a in by_act:
			if not by_act[a].is_empty():
				var s := 0.0
				for x in by_act[a]:
					s += x
				_p("%d막 평균 %.0f초 (%d번)" % [a, s / by_act[a].size(), by_act[a].size()])

	# ---- 설문
	var answers := []
	for l in logs:
		answers.append_array(l.get("survey", []))
	_p("")
	_p("## 설문 (%d명)" % answers.size())
	if not answers.is_empty():
		_p("")
		_p("| 질문 | 평균 (1~5) | 응답 |")
		_p("|---|---|---|")
		for q in PlaytestLog.SCALES:
			var vals := answers.filter(func(a): return a.has(q[0])).map(func(a): return float(a[q[0]]))
			var s := 0.0
			for v in vals:
				s += v
			_p("| %s | %s | %d |" % [q[1], "%.1f" % (s / vals.size()) if not vals.is_empty() else "-", vals.size()])
		var lens := {}
		for a in answers:
			if a.has("length"):
				var t: String = PlaytestLog.LENGTH[int(a["length"]) - 1]
				lens[t] = int(lens.get(t, 0)) + 1
		_p("")
		_p("판 길이: %s" % _fmt(lens, {}))
		var names := {}
		for r in PlaytestLog.RULES:
			names[r[0]] = r[1]
		for g in [["confusing", "헷갈린 규칙"], ["cut", "빼도 될 규칙"]]:
			var cnt := {}
			for a in answers:
				for k in a.get(g[0], []):
					cnt[k] = int(cnt.get(k, 0)) + 1
			_p("%s: %s" % [g[1], _fmt(cnt, names)])
		for t in [["best", "가장 재미있던 순간"], ["worst", "답답하거나 지루했던 순간"], ["other", "그 밖에"]]:
			var lines := answers.filter(func(a): return str(a.get(t[0], "")) != "")
			if lines.is_empty():
				continue
			_p("")
			_p("**%s**" % t[1])
			for a in lines:
				_p("- %s: %s" % [a.get("who", "?"), str(a[t[0]]).replace("\n", " ")])

	# ---- 재생 검증
	_p("")
	_p("## 재생 검증")
	_p("")
	var ok := 0
	var bad := PackedStringArray()
	for l in finished:
		var r := _replay(l, data)
		if r == "":
			ok += 1
		else:
			bad.append("%s: %s" % [l.get("file", "?"), r])
	_p("시드와 액션으로 다시 둔 결과가 같은 판: %d / %d" % [ok, finished.size()])
	for b in bad:
		_p("- 다름: " + b)
	_finish(md)


func _replay(l: Dictionary, data: GameData) -> String:
	var cfg: Dictionary = l.get("cfg", {})
	if not cfg.has("defs"):
		return "설정 없음"
	var g := GameRules.from_cfg(cfg, data, int(l["seed"]))
	for a in l.get("actions", []):
		if not g.apply(_action(a)):
			return "액션 거부 %s" % [a]
	if g.ending.get("id", "") != l["ending"]["id"] or g.score != int(l["final"]["score"]) or g.rounds_left != int(l["final"]["days_left"]):
		return "결말이 다름 (%s %d)" % [g.ending.get("id", ""), g.score]
	return ""


func _action(a: Dictionary) -> Dictionary:
	## JSON에서 읽은 액션을 엔진 형식으로 (칸은 Vector2i, 정수는 int)
	var out := {}
	for k in a:
		var v = a[k]
		if v is Array and v.size() == 2 and k in ["to", "cell", "pos"]:
			v = Vector2i(int(v[0]), int(v[1]))
		elif v is float and v == floorf(v):
			v = int(v)
		out[k] = v
	return out


func _fmt(cnt: Dictionary, names: Dictionary) -> String:
	if cnt.is_empty():
		return "-"
	var keys := cnt.keys()
	keys.sort_custom(func(a, b): return cnt[a] > cnt[b])
	return ", ".join(keys.map(func(k): return "%s %d" % [names.get(k, k), cnt[k]]))


func _finish(md: String) -> void:
	if md != "":
		var f := FileAccess.open(md, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_out) + "\n")
	quit()
