extends SceneTree
## 규칙 정돈용 측정 (테스트가 아니라 보고서): AI끼리 두어
##  1) 규칙마다 한 판에 몇 번 쓰이는지 (행동·카드·판정)
##  2) 규칙을 하나씩 끄면(scenario.off) 승률·판 길이가 얼마나 바뀌는지 (같은 시드끼리 비교)
## 를 잰다. 많이 쓰이지도 않고 꺼도 결과가 거의 안 바뀌는 규칙이 걷어낼 후보다.
## AI 기준 수치이므로 사람 플레이테스트 결과와 함께 봐야 한다.
## 실행: godot --headless --path game --script res://tests/rule_audit.gd [-- 판수] [md=파일]

const OFFS := ["ability", "give", "decoy", "items", "events", "occupation", "exposure", "vote"]
const OFF_NAMES := {"ability": "세력 능력", "give": "건네기", "decoy": "미끼", "items": "아이템 타일",
	"events": "이벤트 타일", "occupation": "일제 동향", "exposure": "노출(경계 상승)", "vote": "결행 투표(자동 결행만)"}

var _out: PackedStringArray = []


func _p(s := "") -> void:
	print(s)
	_out.append(s)


func _run(data: GameData, n: int, seed_value: int, off: String) -> Dictionary:
	var order: Array = data.text["agents"]["order"]
	var defs := []
	for s in n:
		var d := {"name": "요원 %d" % s, "faction": data.faction_keys()[s % 3], "ai": true}
		if s > 0:
			d["personality"] = order[(s - 1) % order.size()]
		defs.append(d)
	var g := GameRules.new()
	if off != "":
		g.scenario = {"off": [off]}
	g.setup(defs, seed_value, data)
	var c := {}   # 이 판에서 센 것
	var guard := 0
	while g.phase != "over" and guard < 20000:
		guard += 1
		var a := GameAI.decide(g)
		var key: String = a["type"]
		if key == "use_item":
			key = "item:" + g.cur()["items"][int(a["index"])]
		elif key == "choose":
			key = "choose:%s=%s" % [g.pending.get("kind", ""), a["value"]]
		if not g.apply(a):
			c["_rejected"] = 1
			break
		if key != "step":
			c[key] = int(c.get(key, 0)) + 1
		for e in g.events:
			match e["kind"]:
				"card":
					var k := "card:%s:%s" % [e["deck"], e["id"]]
					c[k] = int(c.get(k, 0)) + 1
				"dice":
					if e.has("target"):
						var k2 := "dice:" + str(e["what"])
						c[k2] = int(c.get(k2, 0)) + 1
		g.events.clear()
	var jailed := 0
	var rescues := 0
	for p in g.players:
		jailed += int(p["stats"]["jailed"])
		rescues += int(p["stats"]["rescues"])
	return {"win": g.ending.get("id", "") == "victory", "days": g.rounds_total - g.rounds_left,
		"launch": g.launch_info.duplicate(), "jailed": jailed, "rescues": rescues, "count": c}


func _init() -> void:
	var data := GameData.load_default()
	var games := 200
	var md := ""
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			games = int(a)
		elif a.begins_with("md="):
			md = a.substr(3)
	_p("# 규칙 사용 빈도와 영향 (AI %d판 × 인원별)" % games)

	# ---- 1) 기준 판: 사용 빈도
	var base := {}
	for n in [2, 3, 4]:
		base[n] = []
		for i in games:
			base[n].append(_run(data, n, 50000 + i, ""))
	_p("")
	_p("## 기준 (규칙 전부 켬)")
	_p("")
	_p("| 인원 | 대성공 | 결행 비율 | 결행 방식 (투표/임박/노출) | 결행 때 남은 날 | 판 길이(일) | 투옥/판 | 구출/판 |")
	_p("|---|---|---|---|---|---|---|---|")
	for n in [2, 3, 4]:
		var rs: Array = base[n]
		var launched := rs.filter(func(r): return not r["launch"].is_empty())
		var reasons := {"vote": 0, "forced": 0, "exposed": 0}
		var ld := 0.0
		for r in launched:
			reasons[r["launch"]["reason"]] = int(reasons.get(r["launch"]["reason"], 0)) + 1
			ld += float(r["launch"]["days_left"])
		_p("| %d인 | %.0f%% | %.0f%% | %d / %d / %d | %.1f | %.1f | %.2f | %.2f |" % [n, _rate(rs, "win"), 100.0 * launched.size() / rs.size(),
			reasons["vote"], reasons["forced"], reasons["exposed"], ld / maxi(launched.size(), 1), _avg(rs, "days"), _avg(rs, "jailed"), _avg(rs, "rescues")])

	# 한 판에 몇 번 (3인 기준, 전체 요원 합)
	var tot := {}
	for r in base[3]:
		for k in r["count"]:
			tot[k] = int(tot.get(k, 0)) + int(r["count"][k])
	_p("")
	_p("## 한 판에 몇 번 쓰이나 (3인, 요원 전체 합)")
	for group in [["행동", ["roll", "escape", "ability", "give", "decoy", "strike", "end_move", "undo_step"]],
			["아이템 사용", "item:"], ["이벤트 카드", "card:event:"], ["아이템 카드", "card:item:"], ["일제 동향", "card:occupation:"],
			["판정", "dice:"], ["선택", "choose:"]]:
		var keys := []
		if group[1] is Array:
			keys = group[1]
		else:
			for k in tot:
				if str(k).begins_with(group[1]):
					keys.append(k)
			keys.sort_custom(func(a, b): return tot[a] > tot[b])
		var parts := PackedStringArray()
		for k in keys:
			parts.append("%s %.2f" % [str(k).trim_prefix(group[1] if group[1] is String else ""), float(tot.get(k, 0)) / games])
		_p("")
		_p("**%s**: %s" % [group[0], ", ".join(parts)])

	# ---- 2) 하나씩 끄기
	_p("")
	_p("## 규칙을 하나씩 끄면 (같은 시드끼리 비교, 대성공 %p 변화 / 판 길이 변화)")
	_p("")
	_p("| 끈 규칙 | 2인 | 3인 | 4인 | 평균 변화 | 판 길이 |")
	_p("|---|---|---|---|---|---|")
	for off in OFFS:
		var cells := PackedStringArray()
		var dsum := 0.0
		var lsum := 0.0
		for n in [2, 3, 4]:
			var rs := []
			for i in games:
				rs.append(_run(data, n, 50000 + i, off))
			var d := _rate(rs, "win") - _rate(base[n], "win")
			dsum += d
			lsum += _avg(rs, "days") - _avg(base[n], "days")
			cells.append("%+.0f" % d)
		_p("| %s | %s | %+.1f%%p | %+.1f일 |" % [OFF_NAMES[off], " | ".join(cells), dsum / 3.0, lsum / 3.0])
	_p("")
	_p("표본 오차: 판수 %d에서 승률 차이의 표준오차는 약 ±%.0f%%p (같은 시드 비교라 실제로는 더 작다)" % [games, 100.0 * sqrt(0.5) / sqrt(games)])
	if md != "":
		var f := FileAccess.open(md, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_out) + "\n")
	quit()


func _rate(rs: Array, k: String) -> float:
	return 100.0 * rs.filter(func(r): return r[k]).size() / maxi(rs.size(), 1)


func _avg(rs: Array, k: String) -> float:
	var s := 0.0
	for r in rs:
		s += float(r[k])
	return s / maxi(rs.size(), 1)
