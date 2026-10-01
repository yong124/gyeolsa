extends SceneTree
## v2 엔진(2a·2b) 시험: 합법 액션만 무작위로 고르는 봇으로 판을 끝까지 둔다.
## 확인: legal_actions()와 apply의 일치 · 잘못된 액션 거부 · 불변식 · 재생 · 저장/불러오기 · 끝남.
## 실행: godot --headless --path game --script res://tests/v2_engine_test.gd [-- 판수]

const ACTION_CAP := 6000
const FULL_CHECK_EVERY := 40      # 이 간격마다 합법 액션 전부를 복제본에 시험 적용해 본다

var failures := 0
var messages: Array = []


func _init() -> void:
	var games := 200
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			games = int(a)
	var data := GameDataV2.load_default()
	var char_ids: Array = data.characters["characters"].map(func(c): return c["id"])
	var stats := {"days": 0, "forced": 0, "vote": 0, "stub": 0, "stub3": 0, "stub4": 0, "other": 0, "jailed": 0, "actions": 0,
		"missions": {}, "checks": 0, "rescues": 0, "escapes": 0, "launched": 0}
	for i in games:
		var bot := RandomNumberGenerator.new()
		bot.seed = 910000 + i
		var pool := char_ids.duplicate()
		var chars := []
		for k in 4:
			chars.append(pool.pop_at(bot.randi_range(0, pool.size() - 1)))
		_play(i, chars, 5000 + i, bot, data, stats)
	print("--- v2 엔진 시험 요약 (%d판) ---" % games)
	var launched: int = stats["launched"]
	if launched > 0:
		print("결행까지 평균 %.2f일 · 강제 결행 %d/%d (%.0f%%) · 투표 결행 %d" % [
			float(stats["days"]) / launched, stats["forced"], launched, 100.0 * stats["forced"] / launched, stats["vote"]])
	print("끝난 판 %d/%d · 평균 액션 %.0f · 투옥 %d · 구출 %d · 탈옥 %d" % [launched, games, float(stats["actions"]) / games,
		stats["jailed"], stats["rescues"], stats["escapes"]])
	print("미션 성공(종류별): ", stats["missions"])
	print("(2b 미구현) 호출 %d회 · (3단계 미구현) %d회 · (4단계 미구현) %d회" % [stats["stub"], stats["stub3"], stats["stub4"]])
	if int(stats["stub"]) > 0:
		_fail("1막 플레이에서 (2b 미구현) 효과가 %d번 불림" % stats["stub"])
	for m in messages.slice(0, 20):
		print("FAIL: ", m)
	print("v2 엔진 시험: 실패 %d건" % failures)
	quit(1 if failures > 0 else 0)


func _fail(msg: String) -> void:
	failures += 1
	if messages.size() < 200:
		messages.append(msg)


func _strip(st: Dictionary) -> Dictionary:
	var s := st.duplicate(true)
	for k in ["log_lines", "history", "events"]:
		s.erase(k)
	return s


func _play(idx: int, chars: Array, seed_value: int, bot: RandomNumberGenerator, data: GameDataV2, stats: Dictionary) -> void:
	var g := RulesV2.new_game(chars, seed_value)
	var tag := "판 %d (%s)" % [idx, ",".join(chars)]
	var turn_seen := {}
	var steps := 0
	var cut := 40 + (idx * 53) % 400
	var clone: RulesV2 = null
	while g.phase != "over":
		if steps >= ACTION_CAP:
			_fail("%s: 액션 %d개를 넘도록 끝나지 않음 (phase %s, day %d)" % [tag, ACTION_CAP, g.phase, g.day])
			return
		var legal := g.legal_actions()
		if legal.is_empty():
			_fail("%s: 합법 액션이 없는데 판이 안 끝남 (phase %s, current %d, pending %s)" % [tag, g.phase, g.current, g.pending.get("kind", "")])
			return
		if steps % FULL_CHECK_EVERY == 0:
			_check_all_legal(g, legal, tag)
		_check_invalid(g, legal, bot, tag)
		var act: Dictionary = legal[bot.randi_range(0, legal.size() - 1)]
		if clone == null and steps == cut:
			clone = RulesV2.new()
			clone.load_state(g.save_state(), data)
		if clone != null:
			var cl := clone.legal_actions()
			if str(cl) != str(legal):
				_fail("%s: 불러온 엔진의 합법 액션이 다름" % tag)
				return
			if not clone.apply(act.duplicate(true)):
				_fail("%s: 불러온 엔진이 액션을 거부 %s" % [tag, act])
				return
		if not g.apply(act):
			_fail("%s: 합법 액션을 거부함 %s (phase %s)" % [tag, act, g.phase])
			return
		steps += 1
		_check_invariants(g, tag, turn_seen)
		for e in g.events:
			if e["kind"] == "mission_done":
				var t: String = data.mission(e["id"]).get("type", "?")
				stats["missions"][t] = int(stats["missions"].get(t, 0)) + 1
			elif e["kind"] == "rescue":
				stats["rescues"] += 1
		g.events.clear()
		if clone != null:
			clone.events.clear()
	# 끝남
	var end_id: String = g.ending.get("id", "")
	if not end_id in ["launch_stub", "time"]:
		_fail("%s: 알 수 없는 결말 '%s'" % [tag, end_id])
	if end_id == "launch_stub":
		stats["launched"] += 1
		stats["days"] += int(g.launch_info.get("day", 0))
		if g.launch_info.get("reason", "") == "forced":
			stats["forced"] += 1
		else:
			stats["vote"] += 1
	stats["actions"] += steps
	for q in g.players:
		stats["jailed"] += int(q["stats"]["jailed"])
		stats["escapes"] += int(q["stats"]["escapes"])
	for l in g.log_lines:
		if str(l).begins_with("(2b 미구현)") or str(l).begins_with("(알 수 없는 효과)"):
			stats["stub"] += 1
		elif str(l).begins_with("(3단계 미구현)"):
			stats["stub3"] += 1
		elif str(l).begins_with("(4단계 미구현)"):
			stats["stub4"] += 1
	# 저장/불러오기: 중간에 복제한 엔진과 끝 상태가 같아야 한다
	if clone != null:
		if str(_strip(clone.save_state())) != str(_strip(g.save_state())):
			_fail("%s: 저장·불러오기 뒤 끝 상태가 다름" % tag)
	# 재생: 같은 시드 + 액션 = 같은 판
	var r := RulesV2.new_game(chars, seed_value)
	for a in g.actions:
		if not r.apply(a.duplicate(true)):
			_fail("%s: 재생 중 액션 거부 %s" % [tag, a])
			return
	if str(_strip(r.save_state())) != str(_strip(g.save_state())):
		_fail("%s: 재생한 끝 상태가 다름" % tag)
	if r.log_lines != g.log_lines:
		_fail("%s: 재생한 로그가 다름" % tag)


func _check_all_legal(g: RulesV2, legal: Array, tag: String) -> void:
	var st := g.save_state()
	for a in legal:
		var c := RulesV2.new()
		c.load_state(st, g.data)
		if not c.apply(a.duplicate(true)):
			_fail("%s: 합법 액션을 복제본이 거부 %s (phase %s)" % [tag, a, g.phase])


func _check_invalid(g: RulesV2, legal: Array, bot: RandomNumberGenerator, tag: String) -> void:
	## 잘못된 액션은 거부되고 상태를 바꾸지 않아야 한다
	var n := g.players.size()
	var cands: Array = [
		{"type": "step", "player": (maxi(g.current, 0) + 1) % n, "to": Vector2i(5, 6)},
		{"type": "step", "player": 0, "to": Vector2i(99, 99)},
		{"type": "begin_turn", "player": bot.randi_range(0, n - 1), "bogus": true} if g.phase != "day" else {"type": "begin_turn", "player": 99},
		{"type": "take_die", "player": 0, "die": 99},
		{"type": "take_die", "player": 99, "die": 0},
		{"type": "release_die"},
		{"type": "choose", "player": (maxi(g.pending.get("player", 0), 0) + 1) % n, "value": 0},
		{"type": "choose", "player": 0, "value": "없는 값"},
		{"type": "fly", "player": 0},
		{"type": "use_item", "player": 0, "index": 9},
		{"type": "give_item", "player": 0, "index": 0, "to": 0},
		{"type": "decoy", "player": 0, "from": 0},
		{"type": "use_spare", "player": 0, "die": 99, "use": "move"},
		{"type": "escape", "player": (maxi(g.current, 0) + 1) % n},
		{"type": "start_day"},
	]
	if g.phase == "turn":
		cands.append({"type": "begin_turn", "player": 0})
		cands.append({"type": "take_die", "player": 0, "die": 0})
		cands.append({"type": "start_day", "player": 0})
	if g.phase == "plan":
		cands.append({"type": "step", "player": 0, "to": Vector2i(5, 6)})
		cands.append({"type": "begin_turn", "player": 0})
	var before := str(_strip(g.save_state())) if g.actions.size() % 60 == 0 else ""
	var acts := g.actions.size()
	for a in cands:
		var is_legal := false
		for l in legal:
			if str(l) == str(a):
				is_legal = true
		if is_legal:
			continue
		if g.apply(a.duplicate(true)):
			_fail("%s: 잘못된 액션을 받아들임 %s (phase %s)" % [tag, a, g.phase])
			return
	if g.actions.size() != acts:
		_fail("%s: 거부한 액션이 기록됨" % tag)
	if before != "" and before != str(_strip(g.save_state())):
		_fail("%s: 거부한 액션이 상태를 바꿈" % tag)


func _check_invariants(g: RulesV2, tag: String, turn_seen: Dictionary) -> void:
	var R: Dictionary = g.data.rules
	# 칸이 보드 안
	for q in g.players:
		if not g.in_bounds(q["pos"]):
			_fail("%s: 요원 %s가 보드 밖 %s" % [tag, q["name"], q["pos"]])
		if q["jailed"] and not q["pos"] in g.data.bases:
			_fail("%s: 갇힌 요원이 거점이 아닌 곳에 있음" % tag)
	for c in g.board:
		if not g.in_bounds(c):
			_fail("%s: 보드 밖 타일 %s" % [tag, c])
	# 주사위는 한 사람에 하나
	var owners := {}
	for i in g.team_dice.size():
		var o: int = g.team_dice[i]["owner"]
		if o >= 0:
			if owners.has(o):
				_fail("%s: 요원 %d이 주사위를 둘 이상 가짐" % [tag, o])
			owners[o] = i
			if g.players[o]["die_raw"] != g.team_dice[i]["value"]:
				_fail("%s: 요원 %d의 주사위 값이 어긋남" % [tag, o])
	# 경찰 ≤ 말 수, 미션 줄 ≤ 3, 손패 ≤ 한도
	if g.police.size() > int(R["police"]["pieces"]):
		_fail("%s: 경찰 %d개" % [tag, g.police.size()])
	for pid in g.police:
		if g.players[pid]["jailed"]:
			_fail("%s: 갇힌 요원을 경찰이 쫓음" % tag)
	if g.mission_row.size() > int(R["mission_row"]):
		_fail("%s: 미션 줄 %d장" % [tag, g.mission_row.size()])
	var discarding: bool = g.phase == "choice" and g.pending.get("kind", "") == "discard"
	for q in g.players:
		if q["items"].size() > g.hand_limit(q) and not (discarding and g.pending["player"] == q["id"]):
			_fail("%s: 요원 %s의 손패 %d장 (한도 %d)" % [tag, q["name"], q["items"].size(), g.hand_limit(q)])
		if q["bombs"] > g.bomb_slots(q):
			_fail("%s: 폭탄이 칸 수를 넘음" % tag)
	if g.exposure < 0 or g.exposure > int(R["exposure"]["max"]):
		_fail("%s: 노출 %d" % [tag, g.exposure])
	# 하루에 요원마다 차례 한 번
	for e in g.events:
		if e["kind"] == "turn":
			var key := "%d:%d" % [g.day, e["player"]]
			if turn_seen.has(key):
				_fail("%s: %d일째 요원 %d의 차례가 두 번" % [tag, g.day, e["player"]])
			turn_seen[key] = true
	if g.phase == "turn" and g.current < 0:
		_fail("%s: turn인데 current가 없음" % tag)
	if g.phase == "day" and g.current != -1:
		_fail("%s: day인데 current가 있음" % tag)
