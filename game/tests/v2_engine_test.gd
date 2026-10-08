extends SceneTree
## v2 엔진 시험: 합법 액션만 무작위로 고르는 봇으로 2막과 엔딩까지 둔다.
## 확인: legal_actions()와 apply의 일치 · 잘못된 액션 거부 · 불변식 · 재생 · 저장/불러오기 · 끝남.
## 3단계: 사연 · 결행 순간 선택 · 투옥 압수.
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
		"missions": {}, "missed": 0, "ops_blocked": 0, "ops_missed": 0, "ops_seen": 0, "checks": 0, "rescues": 0, "escapes": 0, "launched": 0,
		"saga_done": 0, "saga_dealt": {}, "saga_hit": {}, "confiscated": 0,
		"keeps": 0, "saga_players": 0, "endings": {}, "scene_breaks": {}, "scene_shown": {},
		"target_breaks": {}, "target_games": {}, "act2_days": 0}
	var plain_games := 0
	var fast_stats := {"days": 0, "forced": 0, "vote": 0, "stub": 0, "stub3": 0, "stub4": 0, "other": 0, "jailed": 0, "actions": 0,
		"missions": {}, "missed": 0, "ops_blocked": 0, "ops_missed": 0, "ops_seen": 0, "checks": 0, "rescues": 0, "escapes": 0, "launched": 0,
		"saga_done": 0, "saga_dealt": {}, "saga_hit": {}, "confiscated": 0,
		"keeps": 0, "saga_players": 0, "endings": {}, "scene_breaks": {}, "scene_shown": {},
		"target_breaks": {}, "target_games": {}, "act2_days": 0}
	for i in games:
		var bot := RandomNumberGenerator.new()
		bot.seed = 910000 + i
		var pool := char_ids.duplicate()
		var chars := []
		for k in 4:
			chars.append(pool.pop_at(bot.randi_range(0, pool.size() - 1)))
		# 5판에 한 판은 처음부터 2막인 판 (2막의 하루 규칙을 봇으로 일찍 시험, 통계에는 넣지 않음)
		var fast := i % 5 == 4
		if not fast:
			plain_games += 1
		_play(i, chars, 5000 + i, bot, data, fast_stats if fast else stats, fast)
	# 2·3인 판: 사연이 켜져 있어야 한다
	var small := {"days": 0, "forced": 0, "vote": 0, "stub": 0, "stub3": 0, "stub4": 0, "other": 0, "jailed": 0, "actions": 0,
		"missions": {}, "missed": 0, "ops_blocked": 0, "ops_missed": 0, "ops_seen": 0, "checks": 0, "rescues": 0, "escapes": 0, "launched": 0,
		"saga_done": 0, "saga_dealt": {}, "saga_hit": {}, "confiscated": 0,
		"keeps": 0, "saga_players": 0, "endings": {}, "scene_breaks": {}, "scene_shown": {},
		"target_breaks": {}, "target_games": {}, "act2_days": 0}
	var small_games := maxi(games / 10, 6)
	for i in small_games:
		var bot2 := RandomNumberGenerator.new()
		bot2.seed = 730000 + i
		var pool2 := char_ids.duplicate()
		var chars2 := []
		for k in 2 + i % 2:
			chars2.append(pool2.pop_at(bot2.randi_range(0, pool2.size() - 1)))
		_play(1000 + i, chars2, 8000 + i, bot2, data, small)
	if int(small["saga_players"]) > 0 and int(small["keeps"]) + int(small["saga_done"]) < int(small["saga_players"]):
		_fail("2·3인 판: 사연을 이루거나 남긴 요원이 %d명뿐 (전체 %d명)" % [int(small["keeps"]) + int(small["saga_done"]), small["saga_players"]])
	print("--- v2 엔진 시험 요약 (%d판) ---" % games)
	var launched: int = stats["launched"]
	var fast_launched: int = fast_stats["launched"]
	if launched > 0:
		print("결행까지 평균 %.2f일 · 강제 결행 %d/%d (%.0f%%) · 투표 결행 %d" % [
			float(stats["days"]) / launched, stats["forced"], launched, 100.0 * stats["forced"] / launched, stats["vote"]])
	print("끝난 판 %d/%d · 평균 액션 %.0f · 투옥 %d · 구출 %d · 탈옥 %d" % [launched, plain_games, float(stats["actions"]) / maxi(plain_games, 1),
		stats["jailed"], stats["rescues"], stats["escapes"]])
	print("미션 성공(종류별): ", stats["missions"], " · 놓친 미션 ", stats["missed"], " · 일제 작전 ", stats["ops_seen"], "번 (막음 ", stats["ops_blocked"], " · 놓침 ", stats["ops_missed"], ")")
	print("판당 이룬 사연 %.2f · 판당 압수당한 아이템 %.2f장" % [
		float(stats["saga_done"]) / maxi(plain_games, 1), float(stats["confiscated"]) / maxi(plain_games, 1)])
	print("2막 직행 시험 %d판 (2막으로 꾸밈): 끝난 판 %d · 평균 액션 %.0f · 투옥 %d" % [games - plain_games, fast_launched,
		float(fast_stats["actions"]) / maxi(games - plain_games, 1), fast_stats["jailed"]])
	var rows := []
	var sids: Array = stats["saga_dealt"].keys()
	sids.sort()
	for id in sids:
		rows.append("%s %d/%d(%.0f%%)" % [id, int(stats["saga_hit"].get(id, 0)), stats["saga_dealt"][id],
			100.0 * int(stats["saga_hit"].get(id, 0)) / maxi(int(stats["saga_dealt"][id]), 1)])
	print("사연별 이룬 비율: ", " · ".join(rows))
	print("2·3인 판 %d판: 이룬 사연 %d" % [small_games, small["saga_done"]])
	for id in ["victory", "fail_final", "fail_middle", "history"]:
		print("엔딩 %s: %d/%d (%.1f%%)" % [id, int(stats["endings"].get(id, 0)), plain_games,
			100.0 * int(stats["endings"].get(id, 0)) / maxi(plain_games, 1)])
	print("2막 평균 %.2f일" % (float(stats["act2_days"]) / maxi(stats["launched"], 1)))
	for id in GameDataV2.load_default().base_ids:
		print("결행 거점 %s: 돌파 장면 평균 %.2f장 (%d판)" % [id,
			float(stats["target_breaks"].get(id, 0)) / maxi(int(stats["target_games"].get(id, 0)), 1), stats["target_games"].get(id, 0)])
	var scene_ids: Array = stats["scene_shown"].keys()
	scene_ids.sort()
	for id in scene_ids:
		print("장면 %s: %d/%d (%.1f%%)" % [id, int(stats["scene_breaks"].get(id, 0)), int(stats["scene_shown"][id]),
			100.0 * int(stats["scene_breaks"].get(id, 0)) / maxi(int(stats["scene_shown"][id]), 1)])
	print("(2b 미구현) 호출 %d회 · (3단계 미구현) %d회 · (4단계 미구현) %d회" % [stats["stub"], stats["stub3"], stats["stub4"]])
	if int(stats["stub"]) > 0:
		_fail("1막 플레이에서 (2b 미구현) 효과가 %d번 불림" % stats["stub"])
	if int(stats["stub3"]) > 0 or int(stats["stub4"]) > 0:
		_fail("미구현 효과가 호출됨")
	for m in messages.slice(0, 20):
		print("FAIL: ", m)
	print("v2 엔진 시험: 실패 %d건" % failures)
	quit(1 if failures > 0 else 0)


func _fail(msg: String) -> void:
	failures += 1
	if messages.size() < 200:
		messages.append(msg)


func _mk(chars: Array, seed_value: int, fast := false) -> RulesV2:
	## fast: 처음부터 2막(act 2)인 판 (2막의 하루 규칙을 봇으로 일찍 시험)
	var g := RulesV2.new_game(chars, seed_value)
	if fast:
		g.launch_info = {"target": GameDataV2.load_default().base_ids[0], "reason": "test", "day": g.day}
		g._begin_act2()
	return g


func _strip(st: Dictionary) -> Dictionary:
	var s := st.duplicate(true)
	for k in ["log_lines", "history", "events"]:
		s.erase(k)
	return s


func _play(idx: int, chars: Array, seed_value: int, bot: RandomNumberGenerator, data: GameDataV2, stats: Dictionary, fast := false) -> void:
	var g := _mk(chars, seed_value, fast)
	var tag := "판 %d (%s)%s" % [idx, ",".join(chars), " 2막 직행" if fast else ""]
	for q in g.players:
		for id in q["sagas"]:
			stats["saga_dealt"][id] = int(stats["saga_dealt"].get(id, 0)) + 1
		stats["saga_players"] += 1
	var turn_seen := {}
	var shown := {}
	var broken := {}
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
			if e["kind"] == "scene":
				shown[e["id"]] = true
			elif e["kind"] == "scene_break":
				broken[e["id"]] = true
			if e["kind"] == "mission_done":
				var t: String = data.mission(e["id"]).get("type", "?")
				stats["missions"][t] = int(stats["missions"].get(t, 0)) + 1
			elif e["kind"] == "mission_missed":
				stats["missed"] += 1
			elif e["kind"] == "op_appear":
				stats["ops_seen"] += 1
			elif e["kind"] == "op_blocked":
				stats["ops_blocked"] += 1
			elif e["kind"] == "op_missed":
				stats["ops_missed"] += 1
			elif e["kind"] == "rescue":
				stats["rescues"] += 1
			elif e["kind"] == "confiscate":
				stats["confiscated"] += e["items"].size()
			elif e["kind"] == "saga_kept":
				stats["keeps"] += 1
		g.events.clear()
		if clone != null:
			clone.events.clear()
	# 끝남
	var end_id: String = g.ending.get("id", "")
	if not end_id in ["victory", "fail_final", "fail_middle", "history"]:
		_fail("%s: 알 수 없는 결말 '%s'" % [tag, end_id])
	stats["endings"][end_id] = int(stats["endings"].get(end_id, 0)) + 1
	if g.act == 2:
		stats["launched"] += 1
		stats["days"] += int(g.launch_info.get("day", 0))
		if g.launch_info.get("reason", "") == "forced":
			stats["forced"] += 1
		else:
			stats["vote"] += 1
		stats["act2_days"] += g.day - int(g.launch_info.get("day", g.day)) + 1
		var target := str(g.launch_info.get("target", ""))
		stats["target_games"][target] = int(stats["target_games"].get(target, 0)) + 1
		stats["target_breaks"][target] = int(stats["target_breaks"].get(target, 0)) + broken.size()
	for id in shown:
		stats["scene_shown"][id] = int(stats["scene_shown"].get(id, 0)) + 1
	for id in broken:
		stats["scene_breaks"][id] = int(stats["scene_breaks"].get(id, 0)) + 1
	stats["actions"] += steps
	for q in g.players:
		stats["jailed"] += int(q["stats"]["jailed"])
		stats["escapes"] += int(q["stats"]["escapes"])
		if q["saga_done"] != "":
			stats["saga_done"] += 1
			stats["saga_hit"][q["saga_done"]] = int(stats["saga_hit"].get(q["saga_done"], 0)) + 1
		# 끝났을 때 (이룬 사람을 뺀) 모두가 사연을 하나씩 품고 있어야 한다
		if not fast and g.act == 2 and q["saga_done"] == "" and q["sagas"].size() > 1:
			_fail("%s: 결행이 끝났는데 요원 %s가 사연을 %d장 들고 있음" % [tag, q["name"], q["sagas"].size()])
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
	var r := _mk(chars, seed_value, fast)
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
		{"type": "move_die", "player": 0, "die": 99},
		{"type": "move_die", "player": 99, "die": 0},
		{"type": "give_die", "player": 0, "die": 0, "target": 0},
		{"type": "choose", "player": (maxi(g.pending.get("player", 0), 0) + 1) % n, "value": 0},
		{"type": "choose", "player": 0, "value": "없는 값"},
		{"type": "fly", "player": 0},
		{"type": "use_item", "player": 0, "index": 9},
		{"type": "give_item", "player": 0, "index": 0, "to": 0},
		{"type": "decoy", "player": 0, "from": 0},
		{"type": "persuade", "player": 0, "die": 0, "target": 1},
		{"type": "inform", "player": 0, "target": 1},
		{"type": "escape", "player": (maxi(g.current, 0) + 1) % n},
		{"type": "start_day"},
	]
	if g.phase == "turn":
		cands.append({"type": "begin_turn", "player": 0})
		cands.append({"type": "start_day", "player": 0})
	if g.phase == "plan":
		cands.append({"type": "step", "player": 0, "to": Vector2i(5, 6)})
		cands.append({"type": "begin_turn", "player": 0})
		cands.append({"type": "move_die", "player": 0, "die": 0})
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
	# 작전 주사위: 주인은 요원, 눈은 1~면 수, 쓴 주사위는 남은 주사위에 없음
	for i in g.op_dice.size():
		var d: Dictionary = g.op_dice[i]
		if int(d["owner"]) < 0 or int(d["owner"]) >= g.players.size():
			_fail("%s: 주인 없는 작전 주사위 %d" % [tag, i])
		if int(d["value"]) < 1 or int(d["value"]) > int(R["die_sides"]):
			_fail("%s: 주사위 눈이 범위 밖 %s" % [tag, d])
		if d["used"] and i in g.my_dice(int(d["owner"])):
			_fail("%s: 쓴 주사위가 남은 주사위에 들어감" % tag)
	for q in g.players:
		if int(q["gives_today"]) > int(R["give_per_day"]):
			_fail("%s: 하루 건네기 횟수 초과" % tag)
	if g.act == 2:
		if g.scene_index < 0 or g.scene_index >= g.scenes.size():
			_fail("%s: 장면 번호가 범위를 벗어남" % tag)
		if g.intel_tokens < 0:
			_fail("%s: 첩보 토큰이 음수" % tag)
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
	if g.funds < 0 or g.funds > int(R["funds"]["max"]):
		_fail("%s: 군자금 %d" % [tag, g.funds])
	for q in g.players:
		if int(q["funds_earned"]) < 0:
			_fail("%s: 번 군자금이 음수" % tag)
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
	_check_stage3(g, tag)
	_check_markers(g, tag)


func _check_markers(g: RulesV2, tag: String) -> void:
	## C단계 불변식: 마커는 줄에 있는 카드의 것 · 보드 안 · 칸이 겹치지 않음 · 진행 상태가 줄과 맞음 · 동향 범위
	var rows := g.mission_row + g.op_row
	if g.act == 2 and (not g.markers.is_empty() or not rows.is_empty() or not g.mission_state.is_empty()):
		_fail("%s: 2막인데 1막 미션·마커가 남음" % tag)
	for id in rows:
		if not g.mission_state.has(id):
			_fail("%s: 줄의 카드 %s에 진행 상태가 없음" % [tag, id])
	for id in g.mission_state:
		if not id in rows:
			_fail("%s: 줄에 없는 카드 %s의 진행 상태가 남음" % [tag, id])
	if g.op_row.size() > g.data.op_deck().size():
		_fail("%s: 일제 작전이 너무 많음" % tag)
	var seen := {}
	for m in g.markers:
		if not str(m["id"]) in rows:
			_fail("%s: 줄에 없는 카드의 마커 %s" % [tag, m["id"]])
		if not g.in_bounds(m["pos"]):
			_fail("%s: 마커가 보드 밖 %s" % [tag, m["pos"]])
		var spec: Dictionary = g.data.marker_card(str(m["id"])).get("markers", [])[int(m["spec"])]
		if not spec.has("at"):
			if m["pos"] == g.data.start or m["pos"] in g.data.bases:
				_fail("%s: 마커가 거점·출발점 위에 있음 %s" % [tag, m["pos"]])
			if seen.has(m["pos"]):
				_fail("%s: 마커 두 개가 같은 칸 %s" % [tag, m["pos"]])
			seen[m["pos"]] = true
		if str(m["role"]) not in GameDataV2.KNOWN_MARKER_ROLES:
			_fail("%s: 알 수 없는 마커 역할 %s" % [tag, m["role"]])
	if g.trend < 0 or g.trend > int(g.data.rules["ops"]["trend_max"]):
		_fail("%s: 일제 동향 %d" % [tag, g.trend])
	for id in g.mission_state:
		var st: Dictionary = g.mission_state[id]
		var h := int(st["holder"])
		if h >= 0 and (h >= g.players.size() or g.players[h]["jailed"]):
			_fail("%s: 갇혔거나 없는 요원이 물건을 들고 있음" % tag)
		if int(st["days"]) == 0 or int(st["days"]) < -1:
			_fail("%s: 카드 %s의 남은 날이 %d" % [tag, id, int(st["days"])])


func _check_stage3(g: RulesV2, tag: String) -> void:
	## 3단계 불변식: 사연 0~2장 · 이룬 사연과 남긴 사연이 같음 · 사연 카드 보존
	var in_hands := 0
	for q in g.players:
		if q["sagas"].size() > 2:
			_fail("%s: 요원 %s의 사연이 %d장" % [tag, q["name"], q["sagas"].size()])
		in_hands += q["sagas"].size()
		if q["saga_done"] != "" and q["saga_done"] != q["saga_kept"]:
			_fail("%s: 이룬 사연과 남긴 사연이 다름" % tag)
	var deck_total := 0
	for k in g.saga_decks:
		deck_total += g.saga_decks[k].size()
	var saga_all: int = g.data.sagas["sagas"].size()
	if deck_total + g.saga_discard.size() + in_hands != saga_all:
		_fail("%s: 사연 카드 수가 어긋남 (덱 %d + 버림 %d + 손 %d != %d)" % [tag, deck_total, g.saga_discard.size(), in_hands, saga_all])
