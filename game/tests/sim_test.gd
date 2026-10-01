extends SceneTree
## AI끼리 여러 판을 끝까지 돌려 오류·교착·불법 액션을 검사하고 인원별 엔딩 확률을 출력한다.
## 실행: godot --headless --path game --script res://tests/sim_test.gd -- [판수] [카드 0/1] [전차역 0/1] [일수 "22,15,11,9,8"]

const STAT_KEYS := ["암살 성공", "정보탈취 성공", "폭파공작 성공", "방해작전 성공", "체포", "[무전 지원] 사용", "[기습] 사용", "[길 안내] 사용", "유인했습니다", "건넸습니다", "순찰에 걸려", "출동해"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 200
	var use_cards := args.size() < 2 or args[1] != "0"
	var rounds := {}
	if args.size() > 3:
		var r := args[3].split(",")
		for k in r.size():
			rounds[k + 2] = int(r[k])
	var data := GameData.load_default()
	var errs := data.validate()
	for e in errs:
		push_error("데이터 오류: " + e)
	print("카드 효과 %s%s" % ["켬" if use_cards else "끔",
		(" / 작전 일수 %s" % rounds) if rounds else ""])
	var keys := data.faction_keys()
	var failures := errs.size()
	for n in range(2, 5):
		var ends := {"victory": 0, "operation": 0, "history": 0}
		var stats := {}
		var jails := 0
		for i in games:
			var g := GameRules.new()
			g.cards_enabled = use_cards
			g.rounds_override = rounds
			var defs := []
			for k in n:
				defs.append({"name": "AI%d" % k, "faction": keys[k % keys.size()], "ai": true})
			g.setup(defs, n * 100000 + i, data)
			var steps := 0
			while g.phase != "over":
				var a := GameAI.decide(g)
				if not g.apply(a):
					push_error("불법 액션: %s (phase=%s, 인원 %d, 판 %d)" % [a, g.phase, n, i])
					failures += 1
					break
				steps += 1
				if steps > 20000:
					push_error("교착: 인원 %d 판 %d" % [n, i])
					failures += 1
					break
			ends[g.ending.get("id", "history")] += 1
			for line in g.log_lines:
				if "투옥되었습니다" in line:
					jails += 1
				for key in STAT_KEYS:
					if key in line:
						stats[key] = stats.get(key, 0) + 1
		print("%d인  대성공 %5.1f%%  실행 %5.1f%%  정사 %5.1f%%  투옥 %.1f" % [n,
			100.0 * ends["victory"] / games, 100.0 * ends["operation"] / games,
			100.0 * ends["history"] / games, float(jails) / games])
		var parts := []
		for k in STAT_KEYS:
			parts.append("%s %.1f" % [k, float(stats.get(k, 0)) / games])
		print("     ", ", ".join(parts))
	print("실패 %d건" % failures)
	quit(1 if failures > 0 else 0)
