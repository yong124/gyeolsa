extends SceneTree
## 규칙 시험 1층: 도우미 · 1막 기본 규칙 (계획 · 투표 · 검문 · 은신처 · 경찰 · 감옥 · 탈옥 · 손패)
## 규칙 시험은 층마다 한 파일이고 위 층이 아래 층을 상속한다. 실행은 늘 tests/v2_mechanics_test.gd(맨 위 층)로 한다.


var passed := 0
var failed := 0

const START := Vector2i(5, 5)


# ------------------------------------------------------------------ 도우미

func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)


## 규칙 시험은 고정 수치 사본(tests/fixtures/v2_base, 4단계 끝의 데이터)으로 돈다.
## 밸런스 조정으로 data/v2의 수치가 바뀌어도 규칙 시험의 기대값은 그대로다.
## 카드를 더하거나 빼면 이 사본도 함께 맞춘다 (진짜 데이터의 검증은 v2_data_test가 한다).
const BASE_DIR := "res://tests/fixtures/v2_base/"
static var _fixed_cache: GameDataV2


static func _fixed_data() -> GameDataV2:
	if _fixed_cache == null:
		_fixed_cache = GameDataV2.new()
		_fixed_cache.load_dir(BASE_DIR)
	return _fixed_cache


func _ids(v, out: Array) -> void:
	## JSON 안의 모든 "id" 값을 모은다
	if v is Dictionary:
		if v.has("id"):
			out.append(str(v["id"]))
		for k in v:
			_ids(v[k], out)
	elif v is Array:
		for x in v:
			_ids(x, out)


func _test_fixture_in_sync() -> void:
	## 고정 수치 사본과 진짜 데이터의 카드 구성(id)이 같아야 "빠짐없이" 검사가 진짜 카드를 덮는다
	var real := GameDataV2.load_default()
	var fixed := _fixed_data()
	for name in ["threats", "missions", "events", "items", "scenes", "sagas", "characters"]:
		var a := []
		var b := []
		_ids(real.get(name), a)
		_ids(fixed.get(name), b)
		a.sort()
		b.sort()
		ok(a == b, "고정 수치 사본: %s 카드 구성이 진짜 데이터와 같음" % name)


func _gd(tweak: Callable = Callable()) -> GameDataV2:
	var gd := GameDataV2.new()
	gd.load_dir(BASE_DIR)
	if tweak.is_valid():
		tweak.call(gd)
	return gd


func _new(chars: Array, gd: GameDataV2 = null, seed_value := 1) -> RulesV2:
	var g := RulesV2.new()
	var defs := []
	for c in chars:
		defs.append({"name": "요원 " + c, "character": c})
	g.setup(defs, seed_value, gd if gd else _fixed_data())
	return _blank(g)


func _blank(g: RulesV2) -> RulesV2:
	## 아침 흐름(위협·투표)이 만든 것을 모두 치우고 빈 판 위에서 시작한다
	var guard := 0
	while g.phase == "choice" and guard < 50:
		guard += 1
		g.apply({"type": "choose", "player": g.pending["player"], "value": g.pending["options"][0]["value"]})
	g.police.clear()
	g.exposure = 0
	g.ready = 0
	g.mission_row = []
	g.markers = []
	g.mission_state = {}
	g.op_row = []
	g.expire_queue = []
	g.trend = 0
	g.peek_bonus = 0
	g.bonus_wait = []
	g.op_dice = []
	g.today = g._new_today()
	g.pending = {}
	g.check = {}
	for c in g.board:   # 아침 흐름(예: 위협 「검문소 증설」)이 더미에서 꺼내 깐 타일은 더미로 돌려놓는다
		var tt := str(g.board[c]["type"])
		if not tt in ["start", "base"]:
			g.tile_deck.append(tt)
	g.board = {}
	g.board[g.data.start] = g._new_tile("start")
	for b in g.data.bases:
		g.board[b] = g._new_tile("base")
	g.phase = "day"
	g.current = -1
	g.steps_left = 0
	for q in g.players:
		q["pos"] = g.data.start
		q["jailed"] = false
		q["dice_next"] = 0
		q["gives_today"] = 0
		q["done_today"] = false
		q["item_uses"] = 0
		q["items"] = []
		q["bombs"] = 0
		q["grants"] = []
		q["flags"] = {}
		q["turns"] = 1
		# 3단계: 무작위로 받은 사연은 치운다 (시험이 필요한 만큼 직접 꾸민다)
		q["sagas"] = []
		q["saga_done"] = ""
		q["saga_kept"] = ""
		q["saga_track"] = {}
		q["jailed_day"] = -99
	g.saga_rewards = []
	return g


func _tile(g: RulesV2, cell: Vector2i, type: String) -> void:
	g.board[cell] = g._new_tile(type)


func _spare(g: RulesV2, value: int, owner := -1) -> int:
	## 작전 주사위 하나를 준다 (owner를 안 주면 지금 차례인 요원, 없으면 0번). 그 인덱스를 돌려준다.
	if owner < 0:
		owner = g.current if g.current >= 0 else 0
	g.op_dice.append({"value": value, "owner": owner, "used": false})
	return g.op_dice.size() - 1


func _turn(g: RulesV2, pid: int, die: int) -> bool:
	## 차례를 시작하고, die > 0이면 그 눈의 주사위를 주어 곧바로 이동에 쓴다 (옛 「이동 주사위」와 같은 셈)
	var p: Dictionary = g.players[pid]
	g.phase = "day"
	if not g.apply({"type": "begin_turn", "player": pid}):
		return false
	if die > 0 and not p["jailed"] and g.phase == "turn":
		var i := _spare(g, die, pid)
		g.apply({"type": "move_die", "player": pid, "die": i})
	return true


func _end(g: RulesV2, pid: int) -> bool:
	## 이동을 멈추고 (걷는 중이면) 차례를 마친다. 선택이 열리면 거기서 멈춘다 (답한 뒤 다시 _end).
	var did := false
	if g.apply({"type": "end_move", "player": pid}):
		did = true
	if g.phase == "turn" and g.steps_left == 0 and g.apply({"type": "end_turn", "player": pid}):
		did = true
	return did


func _step(g: RulesV2, pid: int, to: Vector2i, finish := true) -> bool:
	## 한 칸 걷는다. 걸음이 다해 멈췄으면 (finish) 곧바로 차례도 마친다 (옛 시험의 「이동 = 차례」 셈).
	## 멈춘 뒤 다른 행동을 이어 하는 시험은 finish를 false로 준다.
	var moved := g.apply({"type": "step", "player": pid, "to": to})
	if moved and finish and g.phase == "turn" and g.current == pid and g.steps_left == 0:
		_end(g, pid)
	return moved


func _flat(g: RulesV2) -> void:
	## 보드 전체를 깔린 일반 칸으로 만든다 (걸어서 잰 거리가 곧 직선 거리가 됨)
	for y in g.data.size:
		for x in g.data.size:
			var c := Vector2i(x, y)
			if not g.board.has(c):
				g.board[c] = g._new_tile("normal")
	g._dist_cache = {}


func _cc(g: RulesV2, pid: int, die_value := 3) -> bool:
	## 반격을 막는 작전 판정 행동 (주사위 하나를 새로 받아 낸다)
	return g.apply({"type": "counter_check", "player": pid, "die": _spare(g, die_value, pid)})


func _sc(g: RulesV2, pid: int) -> bool:
	## 장면 작전 판정 행동 (주사위 하나를 새로 받아 낸다)
	return g.apply({"type": "scene_check", "player": pid, "die": _spare(g, 3, pid)})


func _mcheck_none(g: RulesV2, pid: int) -> bool:
	## 지금 선 칸에서 할 수 있는 미션 판정 행동이 있는가 (주사위가 남아 있을 때만 있음)
	return g.legal_actions().any(func(a): return a["type"] == "mission_check")


func _mcheck(g: RulesV2, pid: int, die_value := 6) -> bool:
	## 지금 선 칸의 미션 타일에서 작전 판정 행동 (주사위 하나를 새로 받아 낸다)
	var p: Dictionary = g.players[pid]
	var i := _spare(g, die_value, pid)
	return g.apply({"type": "mission_check", "player": pid, "die": i, "cell": p["pos"]})


func _answer(g: RulesV2, value) -> bool:
	return g.apply({"type": "choose", "player": g.pending["player"], "value": value})


# ------------------------------------------------------------------ 시험

func _test_plan_dice() -> void:
	## 7단계 작전 주사위: 아침 굴림 · 이동 · 건네기
	var g := _new(["park", "han", "oh", "seo"])
	var n := int(g.data.rules["personal_dice"])
	g.players[1]["jailed"] = true
	g.players[2]["dice_next"] = 1
	g.players[3]["dice_next"] = -1
	g._morning_dice()
	ok(g.phase == "plan" and g.my_dice(0).size() == n and g.my_dice(1).size() == n, "작전 주사위: 아침에 요원마다 %d개 (갇힌 요원도)" % n)
	ok(g.my_dice(2).size() == n + 1 and g.my_dice(3).size() == n - 1 and g.players[2]["dice_next"] == 0 and g.players[3]["dice_next"] == 0,
		"작전 주사위: 내일 몫 보정(+1, −1)은 그날 아침에 쓰고 지움")
	var all_ok := true
	for d in g.op_dice:
		all_ok = all_ok and int(d["value"]) >= 1 and int(d["value"]) <= int(g.data.rules["die_sides"]) and not d["used"]
	ok(all_ok, "작전 주사위: 눈은 1~6, 아직 안 씀")
	g.act = 2
	g._morning_dice()
	ok(g.my_dice(0).size() == n + int(g.data.rules["act2_personal_dice_extra"]), "작전 주사위: 2막에는 더 굴림")
	g.act = 1
	ok(not g.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)}) and not g.apply({"type": "move_die", "player": 0, "die": g.my_dice(0)[0]}),
		"작전 주사위: 아침 계획 단계에서는 이동 못 함")
	ok(g.apply({"type": "start_day", "player": 2}) and g.phase == "day", "작전 주사위: 아무 요원이나 하루를 시작")
	# 이동: 주사위를 써야 움직이고, 여러 개를 더할 수 있음
	var g2 := _new(["park", "han", "oh", "seo"])
	var a := _spare(g2, 4, 0)
	var b := _spare(g2, 2, 0)
	var c := _spare(g2, 5, 1)
	g2.apply({"type": "begin_turn", "player": 0})
	ok(g2.steps_left == 0 and g2.legal_steps(g2.players[0]).is_empty(), "이동: 차례를 시작해도 주사위를 쓰기 전에는 0칸")
	ok(not g2.apply({"type": "move_die", "player": 0, "die": c}), "이동: 남의 주사위는 못 씀")
	ok(g2.apply({"type": "move_die", "player": 0, "die": a}) and g2.steps_left == 4 and g2.op_dice[a]["used"], "이동: 주사위 4를 쓰면 4칸")
	ok(not g2.apply({"type": "move_die", "player": 0, "die": a}), "이동: 쓴 주사위는 다시 못 씀")
	ok(not g2.apply({"type": "move_die", "player": 0, "die": b}) and g2.steps_left == 4, "이동: 걷는 중에는 다른 주사위를 더 못 씀 (주사위 1개 = 행동 1개)")
	ok(g2.apply({"type": "end_move", "player": 0}) and g2.phase == "turn" and g2.current == 0 and not g2.players[0]["done_today"],
		"이동: 이동을 멈춰도 차례는 계속 (행동 고르기로 돌아옴)")
	ok(g2.apply({"type": "move_die", "player": 0, "die": b}) and g2.steps_left == 2, "이동: 이동 행동을 또 하려면 주사위를 하나 더 씀")
	# 다음 이동 보정은 처음 쓰는 이동 주사위에 붙음
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.players[0]["move_mod_next"] = 2
	var d3 := _spare(g3, 3, 0)
	g3.apply({"type": "begin_turn", "player": 0})
	ok(g3.steps_left == 0, "이동: 보정만으로는 움직이지 않음")
	g3.apply({"type": "move_die", "player": 0, "die": d3})
	ok(g3.steps_left == 5 and g3.players[0]["move_mod_next"] == 0, "이동: 다음 이동 +2는 처음 쓰는 이동 주사위에 붙음")
	# 남은 주사위는 밤이 지나면 사라짐
	var g4 := _new(["park", "han", "oh", "seo"])
	_spare(g4, 6, 0)
	_spare(g4, 6, 0)
	for pid in 4:
		_turn(g4, pid, 1)
		_end(g4, pid)
	ok(g4.day == 2 and (g4.phase != "plan" or g4.my_dice(0).size() == n), "작전 주사위: 쓰지 않은 주사위는 밤에 사라지고 아침에 새로 굴림")
	# 건네기: 같은 칸, 하루 1번
	var g5 := _new(["park", "han", "oh", "seo"])
	var gd0 := _spare(g5, 6, 0)
	var gd1 := _spare(g5, 3, 0)
	g5.players[2]["pos"] = g5.data.bases[0]
	g5.players[3]["pos"] = Vector2i(9, 9)
	g5.apply({"type": "begin_turn", "player": 0})
	var tg := g5.give_die_targets(g5.players[0])
	ok(1 in tg and not 2 in tg and not 3 in tg, "건네기: 같은 칸 동료만 (멀리 있는 요원 제외)")
	ok(g5.apply({"type": "give_die", "player": 0, "die": gd0, "target": 1}) and gd0 in g5.my_dice(1) and not gd0 in g5.my_dice(0),
		"건네기: 주사위가 동료 것이 됨")
	ok(not g5.apply({"type": "give_die", "player": 0, "die": gd1, "target": 1}), "건네기: 하루 1번")
	ok(g5.players[0]["stats"]["gives"] == 1, "건네기: 통계에 셈")


func _test_gaeddong_dice() -> void:
	var g := _new(["gaeddong", "park", "han", "oh"])
	var i1 := _spare(g, 1, 0)
	var i2 := _spare(g, 2, 0)
	var i4 := _spare(g, 4, 0)
	var j1 := _spare(g, 1, 1)
	ok(g.move_value(g.players[0], i1) == 3 and g.move_value(g.players[0], i2) == 3, "김개똥: 이동에 쓴 1·2는 3")
	ok(g.move_value(g.players[0], i4) == 4, "김개똥: 4는 그대로")
	ok(g.move_value(g.players[1], j1) == 1, "다른 캐릭터: 1은 1")
	g.apply({"type": "begin_turn", "player": 0})
	g.apply({"type": "move_die", "player": 0, "die": i1})
	ok(g.steps_left == 3, "김개똥: 주사위 1로 3칸 이동")
	ok(g.die_value(i1) == 1, "김개똥: 굴린 눈은 1 그대로")


func _test_free_order_and_night() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	_turn(g, 2, 1)
	ok(g.phase == "turn" and g.current == 2, "자유 순서: 2번 요원이 먼저 시작할 수 있음")
	ok(not g.apply({"type": "begin_turn", "player": 0}), "자유 순서: 차례 중에 다른 요원이 시작 못 함")
	ok(not g.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)}), "자유 순서: 차례가 아닌 요원은 이동 못 함")
	ok(not _end(g, 1), "자유 순서: 차례가 아닌 요원은 이동을 못 끝냄")
	_end(g, 2)
	ok(g.phase == "day" and g.players[2]["done_today"], "자유 순서: 이동을 끝내면 낮으로 돌아옴")
	ok(not g.apply({"type": "begin_turn", "player": 2}), "자유 순서: 이미 한 요원은 다시 못 함")
	for pid in [3, 0, 1]:
		_turn(g, pid, 1)
		_end(g, pid)
	ok(g.day == 2 and g.leader == 1 and g.rounds_left == int(g.data.rules["rounds"]) - 1, "밤: 모두 마치면 다음 날 아침 (리더가 옆 사람으로, 남은 날 -1)")
	ok(g.phase in ["plan", "choice"] , "밤: 다음 날 아침이 계획 단계(또는 선택)에 이름")
	# 마지막 날 밤
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.rounds_left = 1
	for pid in 4:
		_turn(g2, pid, 1)
		_end(g2, pid)
	ok(g2.phase == "over" and g2.ending.get("id") == "history", "밤: 1막에서 남은 날이 0이 되면 정사로 끝남")


func _vote_all(g: RulesV2, votes: Array, targets: Array = []) -> void:
	## 투표 선택을 차례로 답한다: 찬반은 votes에서, 대상은 targets에서 (없으면 첫 후보)
	var vi := 0
	var ti := 0
	var guard := 0
	while g.phase == "choice" and g.pending.get("kind") in ["launch_vote", "launch_target"] and guard < 40:
		guard += 1
		var value
		if g.pending["kind"] == "launch_vote":
			value = votes[vi] if vi < votes.size() else true
			vi += 1
		else:
			value = targets[ti] if ti < targets.size() else g.pending["options"][0]["value"]
			ti += 1
		g.apply({"type": "choose", "player": g.pending["player"], "value": value})


func _begin_vote(g: RulesV2) -> void:
	g.ready = int(g.data.rules["launch_min"])
	g.intel["gg"] = 1   # 목표가 하나로 정해지게
	g.phase = "morning"
	g.morning_step = 2
	g._morning_continue()


func _test_vote() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	g.leader = 2
	_begin_vote(g)
	ok(g.phase == "choice" and g.pending["kind"] == "launch_vote" and g.pending["player"] == 0, "투표: 결행 준비가 차면 0번부터 한 표씩 묻는다")
	ok(not g.apply({"type": "choose", "player": 1, "value": true}), "투표: 차례가 아닌 요원의 표는 거부")
	_vote_all(g, [true, false, true, false])
	ok(g.act == 2 and g.phase == "plan" and g.launch_info.get("reason") == "vote", "투표: 동수에서 리더가 찬성이면 결행")
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.leader = 2
	_begin_vote(g2)
	_vote_all(g2, [true, true, false, false])
	ok(g2.phase == "plan" and g2.act == 1, "투표: 동수에서 리더가 반대면 결행 안 함 (아침이 이어져 계획 단계로)")
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.leader = 1
	_begin_vote(g3)
	_vote_all(g3, [false, true, false, true])
	ok(g3.act == 2 and g3.phase == "plan", "투표: 동수 2:2에서 리더(1번)가 찬성이면 결행")
	var g4 := _new(["park", "han", "oh", "seo"])
	_begin_vote(g4)
	_vote_all(g4, [true, true, true, false])
	ok(g4.act == 2 and g4.phase == "plan", "투표: 3:1 과반 찬성이면 결행")
	var g5 := _new(["park", "han", "oh", "seo"])
	_begin_vote(g5)
	_vote_all(g5, [true, false, false, false])
	ok(g5.phase == "plan", "투표: 1:3이면 결행 안 함")
	var g6 := _new(["park", "han", "oh", "seo"])
	g6.ready = 0
	g6.phase = "morning"
	g6.morning_step = 2
	g6._morning_continue()
	ok(g6.phase == "plan", "투표: 결행 준비가 모자라면 투표 없이 넘어감")
	var g7 := _new(["park", "han", "oh", "seo"])
	g7.rounds_left = int(g7.data.rules["forced_launch_days_left"])
	g7.intel["gg"] = 1
	g7.phase = "morning"
	g7.morning_step = 2
	g7._morning_continue()
	ok(g7.phase == "choice" and g7.pending["kind"] == "launch_target" and g7.vote_state["forced"], "투표: 강제 결행은 찬반 없이 대상만 묻는다")
	_vote_all(g7, [])
	ok(g7.act == 2 and g7.phase == "plan" and g7.launch_info.get("reason") == "forced", "투표: 남은 날이 기준 이하면 투표 없이 강제 결행")
	# 목표: 첩보가 가장 많은 거점
	var g8 := _new(["park", "han", "oh", "seo"])
	g8.intel["gg"] = 2
	g8.intel["prison"] = 1
	g8.rounds_left = 2
	g8.phase = "morning"
	g8.morning_step = 2
	g8._morning_continue()
	_vote_all(g8, [])
	ok(g8.launch_info.get("target") == "gg", "결행: 첩보가 가장 많은 거점이 목표 (후보가 하나뿐이면 그곳)")
	# 동점이면 리더가 고른다
	var g9 := _new(["park", "han", "oh", "seo"])
	g9.intel["gg"] = 2
	g9.intel["prison"] = 2
	g9.leader = 3
	g9.rounds_left = 2
	g9.phase = "morning"
	g9.morning_step = 2
	g9._morning_continue()
	_vote_all(g9, [], ["gg", "gg", "prison", "prison"])
	ok(g9.phase == "choice" and g9.pending["kind"] == "strike_target" and g9.pending["player"] == 3, "결행: 대상 표가 같으면 리더가 목표를 고름")
	_answer(g9, "prison")
	ok(g9.act == 2 and g9.launch_info.get("target") == "prison", "결행: 리더가 고른 거점이 목표")


func _test_checkpoint() -> void:
	var gd := _gd(func(d): d.rules["checks"]["evade"] = 99)
	var g := _new(["park", "han", "oh", "seo"], gd)
	_tile(g, Vector2i(5, 6), "check")
	_turn(g, 0, 4)
	ok(_step(g, 0, Vector2i(5, 6)), "검문: 검문소로 들어가려 하면 받아들여짐")
	ok(g.players[0]["pos"] == START, "검문: 실패하면 검문소 앞에 머묾")
	ok(g.exposure == 1, "검문: 실패하면 노출 +1")
	ok(g.police.has(0), "검문: 실패하면 경찰이 붙음")
	ok(g.players[0]["done_today"] and g.phase == "day", "검문: 실패하면 이동이 끝남")
	# 성공
	var gd2 := _gd(func(d): d.rules["checks"]["evade"] = 0)
	var g2 := _new(["park", "han", "oh", "seo"], gd2)
	_tile(g2, Vector2i(5, 6), "check")
	_turn(g2, 0, 4)
	_step(g2, 0, Vector2i(5, 6))
	ok(g2.players[0]["pos"] == Vector2i(5, 6) and g2.exposure == 0 and g2.steps_left == 3 and g2.phase == "turn", "검문: 성공하면 통과해 계속 이동")
	# 새로 나온 검문소는 그 앞에서 멈춤
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.tile_deck = ["normal", "check"]
	_turn(g3, 0, 4)
	_step(g3, 0, Vector2i(5, 6))
	ok(g3.board[Vector2i(5, 6)]["type"] == "check" and g3.players[0]["pos"] == START and g3.players[0]["done_today"], "검문: 새로 나온 검문소는 그 앞에서 이동이 끝남")
	# 검문 회피는 강제 판정: 주사위를 고르지 않고, 실패해도 주사위로 다시 하지 않음
	var gd4 := _gd(func(d): d.rules["checks"]["evade"] = 99)
	var g4 := _new(["park", "han", "oh", "seo"], gd4)
	_tile(g4, Vector2i(5, 6), "check")
	var k4 := _spare(g4, 3, 0)
	_turn(g4, 0, 4)
	_step(g4, 0, Vector2i(5, 6))
	ok(g4.phase == "day" and g4.players[0]["done_today"] and g4.exposure == 1, "검문: 강제 판정은 주사위를 묻지 않고 실패로 처리")
	ok(not g4.op_dice[k4]["used"], "검문: 남은 주사위는 그대로")


func _test_checkpoint_auto_and_smoke() -> void:
	var gd := _gd(func(d): d.rules["checks"]["evade"] = 99)
	var g := _new(["yun", "han", "oh", "seo"], gd)
	_tile(g, Vector2i(5, 6), "check")
	_turn(g, 0, 4)
	_step(g, 0, Vector2i(5, 6))
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.exposure == 0, "윤 소위: 회피는 자동 성공 (검문소 통과)")
	# 연막탄: 회피할 때 쓸지 묻는다
	var g2 := _new(["park", "han", "oh", "seo"], gd)
	_tile(g2, Vector2i(5, 6), "check")
	g2.players[0]["items"] = ["smoke_bomb"]
	_turn(g2, 0, 4)
	_step(g2, 0, Vector2i(5, 6))
	ok(g2.phase == "choice" and g2.pending["kind"] == "react_evade", "연막탄: 회피 판정 직전에 쓸지 묻는다")
	_answer(g2, true)
	ok(g2.players[0]["pos"] == Vector2i(5, 6) and g2.players[0]["items"].is_empty() and g2.item_discard.has("smoke_bomb"), "연막탄: 쓰면 회피에 자동 성공하고 카드는 버려짐")
	var g3 := _new(["park", "han", "oh", "seo"], gd)
	_tile(g3, Vector2i(5, 6), "check")
	g3.players[0]["items"] = ["smoke_bomb"]
	_turn(g3, 0, 4)
	_step(g3, 0, Vector2i(5, 6))
	_answer(g3, false)
	ok(g3.players[0]["pos"] == START and g3.players[0]["items"].size() == 1, "연막탄: 안 쓰면 주사위로 판정 (카드 그대로)")
	ok(not g3.apply({"type": "use_item", "player": 0, "index": 0}), "연막탄: 아무 때나 꺼내 쓸 수는 없음")


func _test_hideout() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	var cell := Vector2i(5, 6)
	_tile(g, cell, "normal")
	g.board[cell]["flags"].append("hideout")
	_tile(g, Vector2i(5, 7), "normal")
	_tile(g, Vector2i(5, 8), "normal")
	_tile(g, Vector2i(5, 9), "normal")
	g.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g, 0, 1)
	_step(g, 0, cell)
	ok(not g.police.has(0), "은신처: 은신처 칸에서 차례를 마치면 쫓던 경찰이 사라짐")
	var g2 := _new(["park", "han", "oh", "seo"])
	_tile(g2, cell, "normal")
	_tile(g2, Vector2i(5, 7), "normal")
	_tile(g2, Vector2i(5, 8), "normal")
	_tile(g2, Vector2i(5, 9), "normal")
	g2.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g2, 0, 1)
	_step(g2, 0, cell)
	ok(g2.police.has(0), "은신처: 일반 칸에서는 경찰이 사라지지 않음 (대조)")
	# mark_tile 효과로 표시
	var g3 := _new(["park", "han", "oh", "seo"])
	_tile(g3, cell, "normal")
	g3.players[0]["pos"] = cell
	g3._run_effects(g3.players[0], [{"op": "mark_tile", "flag": "hideout"}], {"then": "resume"})
	ok(g3.board[cell]["flags"].has("hideout"), "은신처: mark_tile이 칸에 표시를 남김")


func _test_police_and_jail() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	for y in range(5, 9):
		_tile(g, Vector2i(5, y), "normal") if y > 5 else null
	g.police[0] = {"pos": Vector2i(5, 8), "summon_turn": 0}
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(5, 6))
	ok(g.players[0]["jailed"] and g.players[0]["jail_count"] == 1, "경찰: 쫓는 경찰이 닿으면 체포되어 투옥")
	ok(g.players[0]["pos"] in g.data.bases and not g.police.has(0), "경찰: 투옥되면 거점 감옥으로 가고 경찰은 사라짐")
	ok(g.exposure == 1, "경찰: 투옥되면 노출 +1")
	# 따돌림
	var g2 := _new(["park", "han", "oh", "seo"])
	for y in range(6, 10):
		_tile(g2, Vector2i(5, y), "normal")
	for x in range(5, 10):
		_tile(g2, Vector2i(x, 9), "normal")
	g2.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g2, 0, 1)
	_step(g2, 0, Vector2i(5, 6))
	ok(g2.police.has(0) and not g2.players[0]["jailed"], "경찰: 멀면 따라붙기만 함")
	var g3 := _new(["park", "han", "oh", "seo"])
	for y in range(5, 10):
		_tile(g3, Vector2i(5, y), "normal")
	for x in range(5, 10):
		_tile(g3, Vector2i(x, 9), "normal")
	_tile(g3, Vector2i(5, 4), "normal")
	g3.police[0] = {"pos": Vector2i(9, 9), "summon_turn": 0}
	_turn(g3, 0, 1)
	_end(g3, 0)
	# 거리 9, 속도 2 → 7 남음 > 3 → 따돌림
	ok(not g3.police.has(0), "경찰: 거리가 멀어지면 따돌림")
	# 붙은 차례에는 안 움직임
	var g4 := _new(["park", "han", "oh", "seo"])
	_tile(g4, Vector2i(5, 6), "normal")
	g4.police[0] = {"pos": Vector2i(5, 6), "summon_turn": g4.players[0]["turns"] + 1}
	_turn(g4, 0, 1)
	_end(g4, 0)
	ok(not g4.players[0]["jailed"], "경찰: 방금 붙은 경찰은 이번 차례에 움직이지 않음 (summon_turn)")
	# 경찰 속도
	var g5 := _new(["park", "han", "oh", "seo"])
	g5.exposure = 0
	ok(g5.police_speed() == 2, "경찰 속도: 경계 1단계는 2칸")
	g5.today["police_speed"] = -5
	ok(g5.police_speed() == 1, "경찰 속도: 오늘 효과를 더해도 최소 1")
	g5.today["police_speed"] = 0
	g5.exposure = 6
	ok(g5.alert_level() == 3 and g5.police_speed() == 4, "경계: 노출 6이면 3단계, 경찰 4칸")


func _test_escape_and_spare() -> void:
	var gd := _gd(func(d): d.rules["checks"]["escape"] = 0)
	var g := _new(["park", "han", "oh", "seo"], gd)
	g.players[0]["jailed"] = true
	g.players[0]["pos"] = g.data.bases[0]
	var e0 := _spare(g, 3, 0)
	g.apply({"type": "begin_turn", "player": 0})
	ok(g.phase == "turn" and g.steps_left == 0, "탈옥: 갇힌 요원의 차례는 이동 없이 시작")
	ok(not g.apply({"type": "step", "player": 0, "to": g.data.bases[0] + Vector2i(1, 0)}), "탈옥: 갇힌 요원은 이동 못 함")
	ok(not g.apply({"type": "move_die", "player": 0, "die": e0}), "탈옥: 갇힌 요원은 이동 행동도 못 함")
	ok(not g.apply({"type": "escape", "player": 0}), "탈옥: 주사위를 내지 않고는 판정하지 못함")
	ok(g.apply({"type": "escape", "player": 0, "die": e0}) and g.op_dice[e0]["used"], "탈옥: 작전 판정은 주사위 하나를 내는 행동")
	ok(not g.players[0]["jailed"] and g.police.has(0), "탈옥: 성공하면 풀려나 경찰이 붙음")
	ok(g.phase == "turn" and g.current == 0 and not g.players[0]["done_today"], "탈옥: 성공해도 차례는 이어짐 (남은 주사위로 더 할 수 있음)")
	_end(g, 0)
	ok(g.players[0]["done_today"], "탈옥: 차례 마치기로 끝")
	var gd2 := _gd(func(d): d.rules["checks"]["escape"] = 99)
	var g2 := _new(["park", "han", "oh", "seo"], gd2)
	g2.players[0]["jailed"] = true
	g2.players[0]["pos"] = g2.data.bases[0]
	var f1 := _spare(g2, 3, 0)
	var f2 := _spare(g2, 4, 0)
	g2.apply({"type": "begin_turn", "player": 0})
	g2.apply({"type": "escape", "player": 0, "die": f1})
	ok(g2.players[0]["jailed"] and g2.phase == "turn" and not g2.players[0]["done_today"], "탈옥: 실패하면 그대로 갇힘 (차례는 이어짐)")
	ok(g2.apply({"type": "escape", "player": 0, "die": f2}) and g2.op_dice[f2]["used"], "탈옥: 실패해도 다른 주사위로 또 판정할 수 있음 (또 한 행동)")
	ok(not g2.apply({"type": "escape", "player": 0, "die": f1}), "탈옥: 쓴 주사위로는 못 함")
	ok(not g2.legal_actions().any(func(a): return a["type"] == "escape"), "탈옥: 주사위가 없으면 판정할 수 없음")
	var g3 := _new(["park", "han", "oh", "seo"], gd2)
	g3.players[0]["jailed"] = true
	g3.players[0]["pos"] = g3.data.bases[0]
	g3.apply({"type": "begin_turn", "player": 0})
	ok(g3.apply({"type": "end_turn", "player": 0}) and g3.players[0]["done_today"], "탈옥: 포기하고 차례를 마칠 수 있음")
	# 작전 판정은 낸 눈 + 새 주사위 1개 (목표 10, 박 하사 +3 → 눈 6 + 1d6 + 3 ≥ 10이라 늘 성공)
	var gd3 := _gd(func(d): d.rules["checks"]["escape"] = 10)
	var g4 := _new(["park", "han", "oh", "seo"], gd3)
	g4.players[0]["jailed"] = true
	g4.players[0]["pos"] = g4.data.bases[0]
	var six := _spare(g4, 6, 0)
	var two := _spare(g4, 2, 0)
	g4.apply({"type": "begin_turn", "player": 0})
	var acts := g4.legal_actions().filter(func(a): return a["type"] == "escape")
	ok(acts.size() == 2 and g4.phase == "turn", "작전 판정: 주사위마다 탈옥 행동이 하나씩 (선택 창은 없음)")
	var pv := g4.check_preview(g4.players[0], {"type": "escape", "die": six})
	ok(int(pv["target"]) == 10 and int(pv["bonus"]) == 3, "작전 판정: check_preview는 목표와 보정(박 하사 +3)")
	ok(absf(g4.check_chance(pv, 6) - 1.0) < 0.001 and g4.check_chance(pv, 2) < 0.7, "작전 판정: check_chance (눈 6이면 확실, 눈 2면 아님)")
	g4.apply({"type": "escape", "player": 0, "die": six})
	ok(not g4.players[0]["jailed"] and g4.op_dice[six]["used"] and not g4.op_dice[two]["used"], "작전 판정: 고른 주사위만 쓰고 눈 6 + 1d6 + 3 ≥ 10이라 성공")
	var last_dice: Array = []
	for e in g4.events:
		if e.get("kind", "") == "dice":
			last_dice = e["dice"]
	ok(last_dice.size() == 1 + int(g4.data.rules["op_check_dice"]) and int(last_dice[0]) == 6, "작전 판정: 굴림 기록은 [낸 눈, 새 주사위]")
	# 다시 굴릴 권리가 있으면 실패 뒤에 쓸지 묻는다
	var g5 := _new(["han", "oh", "seo", "mun"], gd2)
	g5.players[0]["jailed"] = true
	g5.players[0]["pos"] = g5.data.bases[0]
	g5.players[0]["grants"] = [{"kind": "reroll", "value": 0, "scope": "any"}]
	var r1 := _spare(g5, 3, 0)
	g5.apply({"type": "begin_turn", "player": 0})
	g5.apply({"type": "escape", "player": 0, "die": r1})
	ok(g5.phase == "choice" and g5.pending["kind"] == "reroll" and g5.pending["options"].map(func(o): return o["value"]) == ["no", "grant"],
		"다시 하기: 실패하면 다시 굴릴 권리를 쓸지 묻는다 (주사위로 다시 하는 선택지는 없음)")
	_answer(g5, "grant")
	ok(g5.players[0]["grants"].is_empty() and g5.players[0]["jailed"] and g5.phase == "turn", "다시 하기: 권리를 쓰고 다시 판정 (목표 99라 실패, 차례는 이어짐)")
	ok(g5.legal_actions().filter(func(a): return a["type"] == "choose").is_empty(), "작전 판정: check_die 선택 창은 없음")


func _test_alert_dispatch() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	g._expose(2)
	ok(g.exposure == 2 and g.police.is_empty(), "경계: 문턱 아래에서는 경찰 출동 없음")
	g._expose(1)
	ok(g.alert_level() == 2 and g.police.size() == 1, "경계: 노출이 문턱을 넘으면 경계가 오르고 경찰이 출동")
	g._expose(-1)
	ok(g.alert_level() == 1, "노출: 줄어들면 경계도 내려감")
	g._expose(99)
	ok(g.exposure == int(g.data.rules["exposure"]["max"]), "노출: 최대치를 넘지 않음")
	# 출동: 가장 가까운 요원
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.players[2]["pos"] = g2.data.bases[0] + Vector2i(1, 0)
	g2._run_effects(g2.players[0], [{"op": "police_dispatch", "from": "barracks", "count": 1}], {"then": "resume"})
	ok(g2.police.has(2) and g2.police[2]["pos"] == g2.data.bases[0], "경찰 출동: 거점에서 가장 가까운 요원을 쫓음")
	var g3 := _new(["park", "han", "oh", "seo"])
	g3._run_effects(g3.players[0], [{"op": "police_dispatch", "from": "random_base", "count": 2, "distinct": true}], {"then": "resume"})
	ok(g3.police.size() == 2, "경찰 출동: 두 곳에서 두 명을 쫓음")


func _test_hand_limit_and_draw_pick() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	var p: Dictionary = g.players[0]
	ok(g.hand_limit(p) == 2, "손패: 기본 한도 2장")
	g._run_effects(p, [{"op": "draw_item", "count": 3}], {"then": "resume"})
	ok(g.phase == "choice" and g.pending["kind"] == "discard" and p["items"].size() == 3, "손패: 한도를 넘으면 버릴 카드를 고르는 선택")
	_answer(g, 0)
	ok(g.phase == "day" and p["items"].size() == 2 and g.item_discard.size() == 1, "손패: 버리고 나면 한도 안")
	# 주모 막례
	var g2 := _new(["makrye", "han", "oh", "seo"])
	var m: Dictionary = g2.players[0]
	ok(g2.hand_limit(m) == 3, "주모 막례: 손패 3장")
	var discard_before := g2.item_discard.size()
	g2._run_effects(m, [{"op": "draw_item", "count": 1}], {"then": "resume"})
	ok(g2.phase == "choice" and g2.pending["kind"] == "draw_pick" and g2.pending["cards"].size() == 2, "주모 막례: 아이템을 뽑을 때 2장 보고 1장 고름")
	var chosen: String = g2.pending["cards"][1]
	_answer(g2, 1)
	ok(m["items"] == [chosen] and g2.item_discard.size() == discard_before + 1, "주모 막례: 고른 1장은 손에, 남은 1장은 버려짐")
	# 사용
	var g4 := _new(["park", "han", "oh", "seo"])
	g4.players[0]["items"] = ["train_ticket", "forged_pass"]
	_turn(g4, 0, 2)
	ok(g4.apply({"type": "use_item", "player": 0, "index": 1}), "아이템: 내 차례에 소모 카드를 씀 (위조 통행증: 선택 효과)")
	ok(g4.phase == "choice" and g4.pending["kind"] == "effect_choice", "아이템: 고르는 효과는 선택을 연다")
	_answer(g4, 0)
	ok(g4.phase == "turn" and g4.players[0]["items"] == ["train_ticket"] and g4.item_discard.has("forged_pass"), "아이템: 쓴 카드는 버려짐")
	ok(not g4.apply({"type": "use_item", "player": 0, "index": 0}), "아이템: 차례(하루)당 사용 횟수 1회")
	# 아침 아이템
	var g5 := _new(["park", "han", "oh", "seo"])
	g5.phase = "plan"
	g5.players[1]["items"] = ["pocket_watch", "train_ticket"]
	ok(g5.apply({"type": "use_item", "player": 1, "index": 0}), "아이템: 아침 카드는 계획 단계에서 씀")
	ok(not g5.apply({"type": "use_item", "player": 1, "index": 0}), "아이템: 차례용 카드는 계획 단계에서 못 씀")


func _test_stat_sum() -> void:
	var g := _new(["park", "oh", "han", "seo"])
	ok(g.stat(g.players[0], "escape_bonus") == 3, "stat: 박 하사 탈옥 +3 (특성)")
	g.players[1]["items"] = ["telescope"]
	ok(g.stat(g.players[1], "assassin_adjacent") == 1 and g.stat(g.players[1], "assassin_bonus") == 1, "stat: 특성과 지속 아이템을 합산 (저격수 오 + 망원경)")
	g.players[1]["items"] = ["telescope", "western_suit"]
	ok(g.stat(g.players[1], "evade_bonus") == 2, "stat: 양장 회피 +2")
	ok(g.stat(g.players[2], "mission_intel_bonus", "infiltrate") == 0, "stat: 없는 특성은 0")
	var g2 := _new(["choi", "han", "oh", "seo"])
	ok(g2.stat(g2.players[0], "mission_intel_bonus", "infiltrate") == 1 and g2.stat(g2.players[0], "mission_intel_bonus", "bomb") == 0, "stat: type이 있는 특성은 같은 종류만")
	# 망원경이 암살 판정에 더해짐 (목표 14, 보정 +1)
	var gd := _mission_gd(14, 7)
	var g3 := _new(["oh", "han", "park", "seo"], gd)
	_flat(g3)
	g3.players[0]["items"] = ["telescope"]
	_mission(g3, "m_police_chief", {"target": Vector2i(5, 6)})
	_turn(g3, 0, 4)
	_step(g3, 0, Vector2i(5, 6), false)
	_mcheck(g3, 0)
	var last_dice: Dictionary = {}
	for e in g3.events:
		if e["kind"] == "dice" and e["what"] == "암살":
			last_dice = e
	ok(last_dice.get("bonus", 0) == 1 and last_dice.get("target", 0) == 14, "stat: 암살 판정이 망원경 +1을 받음")


func _test_threat_pick_leader() -> void:
	var g := _new(["park", "han", "oh", "gaeddong"])
	g.leader = 2
	g.players[0]["pos"] = Vector2i(5, 5)
	g.players[1]["pos"] = Vector2i(5, 5)
	g.players[2]["pos"] = Vector2i(5, 5)
	g.players[3]["pos"] = Vector2i(5, 5)
	g._run_effects(g.players[2], [{"op": "police_attach", "who": "isolated"}], {"then": "resume"})
	ok(g.phase == "choice" and g.pending["kind"] == "pick_player" and g.pending["player"] == 2, "위협: 고립된 요원이 동점이면 그날의 리더가 고름")
	_answer(g, 3)
	ok(g.police.has(3) and g.police.size() == 1 and g.phase == "day", "위협: 리더가 고른 요원에게 경찰이 붙음")
	# 단독 고립
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.players[0]["pos"] = Vector2i(1, 1)
	g2.players[1]["pos"] = Vector2i(9, 9)
	g2.players[2]["pos"] = Vector2i(9, 8)
	g2.players[3]["pos"] = Vector2i(8, 9)
	g2._run_effects(g2.players[1], [{"op": "police_attach", "who": "isolated"}], {"then": "resume"})
	ok(g2.police.has(0) and g2.phase == "day", "위협: 가장 먼 요원이 하나면 바로 경찰이 붙음")
	# 수배
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.players[1]["jail_count"] = 2
	g3._run_effects(g3.players[0], [{"op": "police_attach", "who": "wanted"}], {"then": "resume"})
	ok(g3.police.has(1) and g3.police.size() == 1, "위협: 수배된 요원(투옥 횟수 최다)에게 경찰이 붙음")
	# 선택 효과 + 이어가기
	var g4 := _new(["park", "han", "oh", "seo"])
	g4._run_effects(g4.players[0], [{"op": "choice", "options": [
		{"label": "숨겨 준다", "effects": [{"op": "exposure", "value": 1}, {"op": "ready", "value": 1}]},
		{"label": "외면한다", "effects": []}]}, {"op": "ready", "value": 10}], {"then": "resume"})
	ok(g4.phase == "choice" and g4.pending["options"].size() == 2, "효과: choice는 선택을 연다")
	_answer(g4, 0)
	ok(g4.exposure == 1 and g4.ready == 11, "효과: 고른 뒤 고른 효과와 남은 효과를 이어서 처리")
	# if / if_players
	var g5 := _new(["park", "han", "oh", "seo"])
	g5._run_effects(g5.players[0], [{"op": "if", "cond": "chased", "then": [{"op": "ready", "value": 1}], "else": [{"op": "ready", "value": 5}]},
		{"op": "if_players", "players": [4], "then": [{"op": "exposure", "value": 1}], "else": []}], {"then": "resume"})
	ok(g5.ready == 5 and g5.exposure == 1, "효과: if(쫓기지 않음)와 if_players(4인)")
	# 오늘 이동 주사위 -1 (효과 해석기)
	var g6 := _new(["park", "han", "oh", "seo"])
	g6._run_effects(g6.players[0], [{"op": "dice_mod_today", "value": -1}], {"then": "resume"})
	ok(g6.today["dice_mod"] == -1, "효과: dice_mod_today는 오늘 이동 주사위를 -1")
	# 이벤트 효과: 군중 속으로
	var g7 := _new(["park", "han", "oh", "seo"])
	g7.exposure = 2
	g7._run_effects(g7.players[0], g7.data.event("into_crowd")["effects"], {"then": "resume"})
	ok(g7.exposure == 1, "이벤트: 군중 속으로 — 쫓기지 않으면 노출 -1")
	var g8 := _new(["park", "han", "oh", "seo"])
	g8._run_effects(g8.players[0], g8.data.event("student")["effects"], {"then": "resume"})
	_answer(g8, 0)
	ok(g8.exposure == 1 and g8.players[0]["items"].size() == 1, "이벤트: 쫓기는 학생 — 숨겨 주면 노출 +1, 아이템 1장")
	# 이벤트 타일: 처음 한 번만, 쓰면 일반 타일
	var g9 := _new(["park", "han", "oh", "seo"])
	_tile(g9, Vector2i(5, 6), "event")
	var deck_before := g9.event_deck.size()
	_turn(g9, 0, 1)
	_step(g9, 0, Vector2i(5, 6))
	ok(g9.event_deck.size() == deck_before - 1 or g9.phase == "choice", "이벤트 타일: 멈추면 이벤트 카드 한 장")
	ok(g9.board[Vector2i(5, 6)]["type"] == "normal" and g9.board[Vector2i(5, 6)]["used"], "이벤트 타일: 쓴 타일은 일반 타일이 됨")
	var g10 := _new(["park", "han", "oh", "seo"])
	_tile(g10, Vector2i(5, 6), "item")
	_turn(g10, 0, 1)
	_step(g10, 0, Vector2i(5, 6))
	ok(g10.players[0]["items"].size() == 1 and g10.board[Vector2i(5, 6)]["type"] == "normal", "아이템 타일: 멈추면 아이템 1장, 타일은 일반 타일")
	# 아침 위협 카드가 실제로 뒤집힘
	var g11 := RulesV2.new_game(["park", "han", "oh", "seo"], 77)
	ok(g11.threat_today != "" and g11.threat_deck.size() + g11.threat_discard.size() == 21 and g11.threat_discard.size() == 1, "아침: 위협 카드 한 장을 뒤집어 버린 더미로")


func _test_coop_actions() -> void:
	# 미끼 · 아이템 건네기 · 장터는 뺐다 (규칙 단순화): 그런 행동은 없고 보내도 받지 않는다
	var g := _new(["park", "han", "oh", "seo"])
	g.players[1]["pos"] = Vector2i(5, 7)
	g.police[1] = {"pos": Vector2i(5, 8), "summon_turn": 0}
	for y in range(6, 10):
		_tile(g, Vector2i(5, y), "normal")
	g.players[0]["items"] = ["telescope"]
	_turn(g, 0, 0)
	var dd := _spare(g, 2, 0)
	var types := _legal_types(g)
	ok(not "decoy" in types and not "give_item" in types and not "market" in types, "단순화: 미끼 · 아이템 건네기 · 장터 행동은 없음")
	ok(not g.apply({"type": "decoy", "player": 0, "die": dd, "from": 1}), "단순화: 미끼를 보내도 받지 않음")
	# 능력 하루 한 번
	var g3 := _new(["yun", "han", "oh", "seo"])
	g3.phase = "plan"
	ok(g3.apply({"type": "ability", "player": 0}), "능력: 아침 능력은 계획 단계에서 씀")
	ok(not g3.apply({"type": "ability", "player": 0}), "능력: 하루에 한 번")
	var g4 := _new(["yun", "han", "oh", "seo"])
	_turn(g4, 0, 2)
	ok(not g4.apply({"type": "ability", "player": 0}), "능력: 아침 능력은 낮에 못 씀")
	var g5 := _new(["park", "han", "oh", "seo"])
	_turn(g5, 0, 2)
	ok(g5.apply({"type": "ability", "player": 0, "target": 1}) and g5.players[0]["ability_day"] == g5.day, "능력: 낮 능력은 내 차례에 대상을 골라 씀")
	ok(not g5.apply({"type": "ability", "player": 1, "target": 0}), "능력: 남의 차례에는 못 씀")
	# 급조 폭탄: 보급 타일 옆 칸에서만
	var g6 := _new(["seok", "han", "oh", "seo"])
	_turn(g6, 0, 2)
	ok(not g6.apply({"type": "ability", "player": 0}), "능력: 석 기술자는 보급 타일 옆이 아니면 못 씀")
	_tile(g6, Vector2i(5, 6), "supply")
	ok(not g6.apply({"type": "ability", "player": 0}), "능력: 버릴 아이템이 없으면 못 씀 (급조 폭탄은 아이템 1장이 비용)")
	g6.players[0]["items"] = ["telescope"]
	ok(g6.apply({"type": "ability", "player": 0}), "능력: 보급 타일 옆 칸이고 아이템이 있으면 씀")


func _test_curfew_min1() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	g.today["dice_mod"] = -1
	_turn(g, 0, 1)
	ok(g.steps_left == 1, "오늘 이동 주사위 -1 (통금령)은 최소 1칸")
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.today["dice_mod"] = -1
	_turn(g2, 0, 4)
	ok(g2.steps_left == 3, "오늘 이동 주사위 -1 (통금령): 4 → 3")
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.players[0]["move_mod_next"] = 2
	_turn(g3, 0, 4)
	ok(g3.steps_left == 6 and g3.players[0]["move_mod_next"] == 0, "다음 이동 +2는 한 번 쓰이고 사라짐")


# ------------------------------------------------------------------ 여러 층이 함께 쓰는 도우미

const CH := ["park", "han", "oh", "gaeddong"]
var covered := {}


func _cov(kind: String, id: String) -> void:
	covered["%s:%s" % [kind, id]] = true


func _fx(g: RulesV2, pid: int, effects: Array, source := "test", extra := {}) -> void:
	var ctx := {"then": "resume", "source": source}
	for k in extra:
		ctx[k] = extra[k]
	g._run_effects(g.players[pid], effects, ctx)


func _threat(g: RulesV2, id: String) -> void:
	g.threat_today = id
	_fx(g, g.leader, g.data.threat(id)["effects"], "threat")


func _event(g: RulesV2, pid: int, id: String) -> void:
	_fx(g, pid, g.data.event(id)["effects"], "event")


func _log_has(g: RulesV2, prefix: String) -> bool:
	for l in g.log_lines:
		if prefix in str(l):
			return true
	return false


func _last_dice(g: RulesV2, what: String) -> Dictionary:
	for i in range(g.events.size() - 1, -1, -1):
		if g.events[i]["kind"] == "dice" and g.events[i]["what"] == what:
			return g.events[i]
	return {}


func _count_dice(g: RulesV2, what: String) -> int:
	var n := 0
	for e in g.events:
		if e["kind"] == "dice" and e["what"] == what:
			n += 1
	return n


func _lay(g: RulesV2, cells: Array, type := "normal") -> void:
	for c in cells:
		_tile(g, c, type)


func _count_tiles(g: RulesV2, type: String) -> int:
	var n := 0
	for c in g.board:
		if g.board[c]["type"] == type:
			n += 1
	return n


func _adj(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _legal_types(g: RulesV2) -> Array:
	var out := []
	for a in g.legal_actions():
		if not a["type"] in out:
			out.append(a["type"])
	return out


func _mission_gd(target := 9, evade := 7) -> GameDataV2:
	## 모든 암살형 판정(암살 미션 · 밀정 침투)의 목표를 target (0 = 무조건 성공, 99 = 무조건 실패), 회피 목표를 evade로
	return _gd(func(d):
		for c in d.missions["missions"] + d.missions["ops"]:
			var cond = c.get("condition", {})
			if str(cond.get("kind", "")) == "assassinate":
				cond["target"] = target
		d.rules["checks"]["evade"] = evade
		d.rules["exposure"]["thresholds"] = [8, 9])


func _mission(g: RulesV2, id: String, at := {}) -> void:
	## 미션(일제 작전)을 줄에 올려 마커를 놓는다. at: {역할: 칸} — 그 역할의 첫 마커를 그 칸으로 옮기고 타일을 깐다
	if g.data.is_op(id):
		g.op_row.append(id)
	else:
		g.mission_row.append(id)
	g._place_card(id)
	for role in at:
		var ms := g.markers_of(id, role)
		if ms.is_empty():
			continue
		ms[0]["pos"] = at[role]
		if not g.board.has(at[role]):
			_tile(g, at[role], "normal")
	g._dist_cache = {}


func _give_die_to(g: RulesV2, pid: int, value: int) -> bool:
	## 내 칸의 공작 마커에 주사위 하나(새로 받음)를 바치는 행동
	return g.apply({"type": "work_give", "player": pid, "die": _spare(g, value, pid)})


func _at(g: RulesV2, pid: int, cell: Vector2i, die := 0) -> void:
	## 요원을 그 칸에 세우고 차례를 시작한다 (die > 0이면 그 주사위로 이동을 시작한 상태)
	g.players[pid]["pos"] = cell
	g.players[pid]["done_today"] = false
	if not g.board.has(cell):
		_tile(g, cell, "normal")
	_turn(g, pid, die)
