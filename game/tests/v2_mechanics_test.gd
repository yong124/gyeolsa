extends SceneTree
## v2 엔진 규칙 하나씩 확인 (2a 규칙 + 2b 카드 효과). 상태를 직접 꾸며 놓고 결과를 본다.
## 판정이 필요한 곳은 별도 GameDataV2 복사본의 판정 목표를 0(무조건 성공)이나 99(무조건 실패)로 바꿔 쓴다.
## 실행: godot --headless --path game --script res://tests/v2_mechanics_test.gd

var passed := 0
var failed := 0

const START := Vector2i(5, 5)


func _init() -> void:
	_test_fixture_in_sync()
	_test_plan_dice()
	_test_gaeddong_dice()
	_test_free_order_and_night()
	_test_vote()
	_test_checkpoint()
	_test_checkpoint_auto_and_smoke()
	_test_rescue()
	_test_hideout()
	_test_missions_double()
	_test_missions_types()
	_test_police_and_jail()
	_test_escape_and_spare()
	_test_alert_dispatch()
	_test_hand_limit_and_draw_pick()
	_test_stat_sum()
	_test_threat_pick_leader()
	_test_coop_actions()
	_test_curfew_min1()
	_test_mission_row_feasible()
	_run_2b_tests()
	_run_3_tests()
	_run_4_tests()
	_run_a_tests()
	_run_b_tests()
	print("v2 규칙 시험: 통과 %d, 실패 %d" % [passed, failed])
	quit(1 if failed > 0 else 0)


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
	g.op_dice = []
	g.today = g._new_today()
	g.pending = {}
	g.check = {}
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


func _vote_all(g: RulesV2, votes: Array) -> void:
	for v in votes:
		if g.phase != "choice" or g.pending.get("kind") != "launch_vote":
			return
		g.apply({"type": "choose", "player": g.pending["player"], "value": v})


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
	ok(g7.act == 2 and g7.phase == "plan" and g7.launch_info.get("reason") == "forced", "투표: 남은 날이 기준 이하면 투표 없이 강제 결행")
	# 목표: 첩보가 가장 많은 거점
	var g8 := _new(["park", "han", "oh", "seo"])
	g8.intel["gg"] = 2
	g8.intel["prison"] = 1
	g8.rounds_left = 2
	g8.phase = "morning"
	g8.morning_step = 2
	g8._morning_continue()
	ok(g8.launch_info.get("target") == "gg", "결행: 첩보가 가장 많은 거점이 목표")
	# 동점이면 리더가 고른다
	var g9 := _new(["park", "han", "oh", "seo"])
	g9.intel["gg"] = 2
	g9.intel["prison"] = 2
	g9.leader = 3
	g9.rounds_left = 2
	g9.phase = "morning"
	g9.morning_step = 2
	g9._morning_continue()
	ok(g9.phase == "choice" and g9.pending["kind"] == "strike_target" and g9.pending["player"] == 3, "결행: 첩보가 같으면 리더가 목표를 고름")
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


func _test_rescue() -> void:
	var g := _new(["han", "park", "oh", "seo"])
	var base: Vector2i = g.data.bases[0]
	var q: Dictionary = g.players[1]
	q["jailed"] = true
	q["pos"] = base
	var next: Vector2i = base + Vector2i(0, 1)
	_tile(g, next, "normal")
	g.players[0]["pos"] = next
	_turn(g, 0, 3)
	_step(g, 0, base)
	ok(not q["jailed"], "구출: 같은 거점에 들어가면 갇힌 동료가 풀려남")
	ok(g.players[0]["stats"]["rescues"] == 1, "구출: 구출 수가 오름")
	ok(q["move_mod_next"] == 2, "구출: 한 간호장교가 구출하면 동료의 다음 이동 +2")
	ok(g.police.has(0) and not g.police.has(1), "구출: 거점에 들어간 요원에게 경찰이 붙고 구출된 동료에게는 안 붙음")
	ok(g.players[0]["done_today"], "구출: 거점에 들어가면 이동이 끝남")
	# 거점 진입 예외: 지속 stat / 권리
	var g2 := _new(["han", "park", "oh", "seo"])
	g2.players[0]["flags"]["entry_no_police"] = true
	g2.players[0]["pos"] = next
	_tile(g2, next, "normal")
	_turn(g2, 0, 3)
	_step(g2, 0, base)
	ok(not g2.police.has(0), "거점: 이번 진입에 경찰이 안 붙는 권리를 쓰면 경찰이 안 붙음")
	# 구출 안 되는 다른 거점
	var g3 := _new(["han", "park", "oh", "seo"])
	g3.players[1]["jailed"] = true
	g3.players[1]["pos"] = g3.data.bases[1]
	_tile(g3, base + Vector2i(0, 1), "normal")
	g3.players[0]["pos"] = base + Vector2i(0, 1)
	_turn(g3, 0, 3)
	_step(g3, 0, base)
	ok(g3.players[1]["jailed"], "구출: 다른 거점에 갇힌 동료는 안 풀림")


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


func _test_missions_double() -> void:
	var gd := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 0)
	var g := _new(["park", "han", "oh", "seo"], gd)
	g.mission_row = ["m_police_chief", "m_mp_captain", "m_bribe_guard"]
	_tile(g, Vector2i(5, 6), "assassin")
	_turn(g, 0, 4)
	_step(g, 0, Vector2i(5, 6), false)
	ok(g.steps_left == 0 and g.phase == "turn" and g.ready == 0 and g.exposure == 0, "암살: 표적 칸에 들어가면 이동이 멈추고 판정은 자동으로 하지 않음")
	ok(not _mcheck_none(g, 0), "암살: 주사위가 없으면 판정 행동이 없음")
	_mcheck(g, 0)
	ok(g.ready == 4, "미션 두 장 동시: 암살 두 장을 한 번에 이루면 결행 준비 +2 +2")
	ok(g.intel["police_hq"] == 1 and g.intel["barracks"] == 1, "미션 두 장 동시: 두 장의 첩보를 모두 받음")
	ok(g.mission_row == ["m_bribe_guard"], "미션 두 장 동시: 이룬 미션만 줄에서 빠짐")
	ok(g.exposure == 1, "미션 두 장 동시: 시끄러움(노출 +1)은 한 번")
	ok(g.police.has(0), "암살: 성공하면 경찰이 붙음")
	_end(g, 0)
	ok(g.players[0]["done_today"] and g.mission_discard.size() == 2, "암살: 차례를 마치고 이룬 카드는 버려짐")
	# 암살 실패 → 회피 판정 → 실패하면 투옥
	var gd2 := _gd(func(d):
		d.missions["types"]["assassin"]["condition"]["target"] = 99
		d.rules["checks"]["evade"] = 99)
	var g2 := _new(["park", "han", "oh", "seo"], gd2)
	g2.mission_row = ["m_police_chief"]
	_tile(g2, Vector2i(5, 6), "assassin")
	_turn(g2, 0, 4)
	_step(g2, 0, Vector2i(5, 6), false)
	_mcheck(g2, 0)
	ok(g2.players[0]["jailed"] and g2.players[0]["jail_count"] == 1, "암살: 실패하고 회피도 실패하면 투옥")
	ok(g2.ready == 0 and g2.mission_row == ["m_police_chief"], "암살: 실패하면 미션은 그대로")
	ok(g2.exposure == 1, "암살: 투옥되면 노출 +1")
	# 암살 실패 → 회피 성공
	var gd3 := _gd(func(d):
		d.missions["types"]["assassin"]["condition"]["target"] = 99
		d.rules["checks"]["evade"] = 0)
	var g3 := _new(["park", "han", "oh", "seo"], gd3)
	g3.mission_row = ["m_police_chief"]
	_tile(g3, Vector2i(5, 6), "assassin")
	_turn(g3, 0, 4)
	_step(g3, 0, Vector2i(5, 6), false)
	_mcheck(g3, 0)
	ok(not g3.players[0]["jailed"] and g3.police.has(0) and g3.ready == 0, "암살: 실패해도 회피에 성공하면 경찰만 붙음")
	ok(g3.phase == "turn" and g3.current == 0 and g3.players[0]["pos"] == Vector2i(5, 6), "암살: 회피에 성공하면 같은 차례에 그 자리에서 이어 감")
	var again := _spare(g3, 5, 0)
	ok(g3.apply({"type": "mission_check", "player": 0, "die": again, "cell": Vector2i(5, 6)}), "암살: 회피에 성공하면 같은 차례에 다른 주사위로 다시 판정할 수 있음")
	# 줄에 암살 미션이 없으면 아무 일 없음
	var g4 := _new(["park", "han", "oh", "seo"], gd)
	g4.mission_row = ["m_bribe_guard"]
	_tile(g4, Vector2i(5, 6), "assassin")
	_turn(g4, 0, 4)
	_step(g4, 0, Vector2i(5, 6))
	ok(g4.phase == "turn" and g4.steps_left == 3 and g4.ready == 0 and g4.exposure == 0, "미션: 줄에 그 종류가 없으면 타일에 들어가도 아무 일 없음")


func _test_missions_types() -> void:
	# 잠입: 그 거점에 들어감
	var g := _new(["park", "han", "oh", "seo"])
	g.mission_row = ["m_bribe_guard", "m_police_docs"]
	var prison: Vector2i = g.data.bases[2]
	_tile(g, prison + Vector2i(0, -1), "normal")
	g.players[0]["pos"] = prison + Vector2i(0, -1)
	_turn(g, 0, 3)
	_step(g, 0, prison)
	ok(g.ready == 1 and g.intel["prison"] == 1, "잠입: 그 거점에 들어가면 결행 준비 +1, 형무소 첩보 +1")
	ok(g.mission_row == ["m_police_docs"] and g.police.has(0), "잠입: 다른 거점 미션은 그대로, 경찰이 붙음")
	# 최 훈장: 잠입 첩보 +1
	var g2 := _new(["choi", "han", "oh", "seo"])
	g2.mission_row = ["m_bribe_guard"]
	_tile(g2, prison + Vector2i(0, -1), "normal")
	g2.players[0]["pos"] = prison + Vector2i(0, -1)
	_turn(g2, 0, 3)
	_step(g2, 0, prison)
	ok(g2.intel["prison"] == 2, "최 훈장: 잠입 미션의 첩보 +1")
	# 폭파: 폭탄을 가지고 폭파 타일에
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.mission_row = ["m_rail_bomb"]
	g3.players[0]["bombs"] = 1
	_tile(g3, Vector2i(5, 6), "bomb")
	_turn(g3, 0, 3)
	_step(g3, 0, Vector2i(5, 6))
	ok(g3.players[0]["bombs"] == 0 and g3.ready == 1 and g3.intel["barracks"] == 1 and g3.exposure == 1, "폭파: 폭탄 1개 사용, 결행 준비 +1, 군영 첩보 +1, 노출 +1")
	var g4 := _new(["park", "han", "oh", "seo"])
	g4.mission_row = ["m_rail_bomb"]
	_tile(g4, Vector2i(5, 6), "bomb")
	_turn(g4, 0, 3)
	_step(g4, 0, Vector2i(5, 6))
	ok(g4.ready == 0 and g4.phase == "turn", "폭파: 폭탄이 없으면 그냥 지나가는 칸")
	# 보급 타일
	var g5 := _new(["park", "han", "oh", "seo"])
	_tile(g5, Vector2i(5, 6), "supply")
	var supply_before := g5.bomb_supply
	_turn(g5, 0, 1)
	_step(g5, 0, Vector2i(5, 6))
	ok(g5.players[0]["bombs"] == 1 and g5.bomb_supply == supply_before - 1, "보급: 멈추면 폭탄을 얻음")
	var g6 := _new(["seok", "han", "oh", "seo"])
	g6.players[0]["bombs"] = 1
	_tile(g6, Vector2i(5, 6), "supply")
	_turn(g6, 0, 1)
	_step(g6, 0, Vector2i(5, 6))
	ok(g6.players[0]["bombs"] == 2, "석 기술자: 폭탄 칸이 둘이라 두 번째도 얻음")
	var g7 := _new(["park", "han", "oh", "seo"])
	g7.players[0]["bombs"] = 1
	_tile(g7, Vector2i(5, 6), "supply")
	_turn(g7, 0, 1)
	_step(g7, 0, Vector2i(5, 6))
	ok(g7.players[0]["bombs"] == 1, "보급: 폭탄 칸이 찼으면 더 못 가짐")
	# 방해: 회피 판정 7
	var gd := _gd(func(d): d.missions["types"]["sabotage"]["condition"]["target"] = 0)
	var g8 := _new(["park", "han", "oh", "seo"], gd)
	g8.mission_row = ["m_leaflets"]
	g8.exposure = 2
	_tile(g8, Vector2i(5, 6), "sabotage")
	_turn(g8, 0, 3)
	_step(g8, 0, Vector2i(5, 6), false)
	_mcheck(g8, 0)
	ok(g8.ready == 1 and g8.exposure == 1 and g8.mission_row.is_empty() and not g8.police.has(0), "방해: 성공하면 결행 준비 +1, 노출 -1 (전단 살포), 경찰 안 붙음")
	var gd2 := _gd(func(d): d.missions["types"]["sabotage"]["condition"]["target"] = 99)
	var g9 := _new(["park", "han", "oh", "seo"], gd2)
	g9.mission_row = ["m_leaflets"]
	_tile(g9, Vector2i(5, 6), "sabotage")
	_turn(g9, 0, 3)
	_step(g9, 0, Vector2i(5, 6), false)
	_mcheck(g9, 0)
	ok(g9.ready == 0 and g9.police.has(0) and g9.mission_row.size() == 1, "방해: 실패하면 경찰이 붙고 미션은 그대로")
	# 이루면 아이템 한 장 (쌀 창고 열기)
	var g10 := _new(["park", "han", "oh", "seo"], gd)
	g10.mission_row = ["m_open_rice"]
	_tile(g10, Vector2i(5, 6), "sabotage")
	_turn(g10, 0, 3)
	_step(g10, 0, Vector2i(5, 6), false)
	_mcheck(g10, 0)
	ok(g10.players[0]["items"].size() == 1, "쌀 창고 열기: 이루면 아이템 1장")
	# 누구든 이룰 수 있다
	var g11 := _new(["park", "han", "oh", "seo"])
	g11.mission_row = ["m_police_docs"]
	var hq: Vector2i = g11.data.bases[1]
	_tile(g11, hq + Vector2i(0, 1), "normal")
	g11.players[2]["pos"] = hq + Vector2i(0, 1)
	_turn(g11, 2, 3)
	_step(g11, 2, hq)
	ok(g11.mission_row.is_empty() and g11.players[2]["stats"]["missions"] == 1, "공개 미션: 누구든 이룰 수 있음")


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
	# 건네기 · 한도
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.players[1]["pos"] = Vector2i(5, 6)
	g3.players[0]["items"] = ["train_ticket"]
	g3.players[1]["items"] = ["smoke_bomb", "safety_pin"]
	_turn(g3, 0, 0)
	ok(g3.give_options(g3.players[0]).is_empty(), "건네기: 주사위가 없으면 아이템을 건넬 수 없음 (건네기는 행동)")
	var gv := _spare(g3, 2, 0)
	ok(not g3.apply({"type": "give_item", "player": 0, "index": 0, "to": 1}), "건네기: 주사위를 내지 않고는 못 건넴")
	ok(g3.apply({"type": "give_item", "player": 0, "die": gv, "index": 0, "to": 1}), "건네기: 옆 칸 동료에게 건넴")
	ok(g3.op_dice[gv]["used"], "건네기: 주사위 하나를 씀 (눈은 상관없음)")
	ok(g3.phase == "choice" and g3.pending["player"] == 1 and g3.pending["kind"] == "discard", "건네기: 받은 쪽이 한도를 넘으면 그 요원이 버릴 카드를 고름")
	ok(not g3.apply({"type": "choose", "player": 0, "value": 0}), "건네기: 선택은 맡은 요원만 보낼 수 있음")
	_answer(g3, 0)
	ok(g3.phase == "turn" and g3.players[0]["item_uses"] == 0, "건네기: 아이템 사용 횟수에는 세지 않음 (공짜 아이템 1장은 그대로)")
	ok(g3.give_options(g3.players[0]).is_empty(), "건네기: 주사위를 다 쓰면 더 못 건넴")
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
	# 망원경이 암살 판정에 더해짐 (목표 9, 보정 +1)
	var gd := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 14)
	var g3 := _new(["oh", "han", "park", "seo"], gd)
	g3.players[0]["items"] = ["telescope"]
	g3.mission_row = ["m_police_chief"]
	_tile(g3, Vector2i(5, 6), "assassin")
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
	ok(g11.threat_today != "" and g11.threat_deck.size() + g11.threat_discard.size() == 24 and g11.threat_discard.size() == 1, "아침: 위협 카드 한 장을 뒤집어 버린 더미로")


func _test_coop_actions() -> void:
	# 미끼
	var g := _new(["park", "han", "oh", "seo"])
	g.players[1]["pos"] = Vector2i(5, 7)
	g.police[1] = {"pos": Vector2i(5, 8), "summon_turn": 0}
	for y in range(6, 10):
		_tile(g, Vector2i(5, y), "normal")
	_turn(g, 0, 0)
	ok(g.decoy_options(g.players[0]).is_empty(), "미끼: 주사위가 없으면 못 함 (미끼는 행동)")
	var dd := _spare(g, 2, 0)
	ok(not g.apply({"type": "decoy", "player": 0, "from": 1}), "미끼: 주사위를 내지 않고는 못 함")
	ok(g.apply({"type": "decoy", "player": 0, "die": dd, "from": 1}), "미끼: 3칸 안 동료를 쫓던 경찰을 나에게로")
	ok(g.op_dice[dd]["used"], "미끼: 주사위 하나를 씀")
	ok(g.police.has(0) and not g.police.has(1) and g.police[0]["pos"] == Vector2i(5, 8), "미끼: 경찰이 내게 붙고 그 자리 그대로")
	ok(not g.apply({"type": "decoy", "player": 0, "die": _spare(g, 2, 0), "from": 1}), "미끼: 이미 쫓기는 중이거나 대상이 없으면 불가")
	# 거리 밖: 깔린 칸을 따라 걷는 거리로 잼
	var g2 := _new(["park", "han", "oh", "seo"])
	for y in range(6, 10):
		_tile(g2, Vector2i(5, y), "normal")
	g2.police[1] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g2, 0, 0)
	_spare(g2, 2, 0)
	ok(g2.decoy_options(g2.players[0]).is_empty(), "미끼: 거리가 멀면 불가 (걸어서 4칸)")
	var g2b := _new(["park", "han", "oh", "seo"])
	for c in [Vector2i(5, 4), Vector2i(5, 3)]:
		_tile(g2b, c, "normal")
	g2b.police[1] = {"pos": Vector2i(5, 3), "summon_turn": 0}
	_turn(g2b, 0, 0)
	_spare(g2b, 2, 0)
	ok(not g2b.decoy_options(g2b.players[0]).is_empty(), "미끼: 걸어서 2칸이면 가능")
	var g2c := _new(["park", "han", "oh", "seo"])
	_tile(g2c, Vector2i(5, 3), "normal")
	g2c.police[1] = {"pos": Vector2i(5, 3), "summon_turn": 0}
	_turn(g2c, 0, 0)
	_spare(g2c, 2, 0)
	ok(g2c.decoy_options(g2c.players[0]).is_empty(), "미끼: 직선으로는 2칸이어도 깔린 길이 이어지지 않으면 걸어서 닿지 않아 불가")
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


func _test_mission_row_feasible() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	g.tile_deck = ["normal"]
	g.mission_row = ["m_police_chief", "m_bribe_guard"]
	g.phase = "morning"
	g.morning_step = 4
	g._fill_mission_row()
	ok(not g.mission_row.has("m_police_chief"), "미션 줄: 남은 타일로 이룰 수 없는 암살 미션은 아침에 빠짐")
	ok(g.mission_row.has("m_bribe_guard") and g.mission_row.size() == int(g.data.rules["mission_row"]), "미션 줄: 이룰 수 있는 것은 남고 줄이 3장으로 채워짐")
	for id in g.mission_row:
		var t: String = g.data.mission(id).get("type")
		ok(t in ["infiltrate", "coop"], "미션 줄: 새로 채운 것도 이룰 수 있는 종류 (%s)" % id)


# ================================================================== 2b: 카드 효과 시험

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


func _run_2b_tests() -> void:
	_test_threat_cards()
	_test_event_cards()
	_test_item_cards()
	_test_traits()
	_test_abilities()
	_test_coop_missions()
	_test_ops_misc()
	_test_coverage()


# ------------------------------------------------------------------ 위협 카드 (1막 13종)

func _test_threat_cards() -> void:
	var g := _new(CH)
	_threat(g, "surprise_search")
	_cov("threat", "surprise_search")
	ok(g.police.size() == 1 and g.police.values()[0]["pos"] in g.data.bases, "위협 기습 수색: 무작위 거점에서 경찰 한 명이 출동해 요원을 쫓음")

	g = _new(CH)
	_threat(g, "mp_reinforce")
	_cov("threat", "mp_reinforce")
	var cells := []
	for pid in g.police:
		cells.append(g.police[pid]["pos"])
	ok(g.police.size() == 2 and cells[0] != cells[1], "위협 헌병대 증파: 서로 다른 두 거점에서 출동")

	g = _new(CH)
	g.players[2]["jail_count"] = 2
	_threat(g, "arrest_order")
	_cov("threat", "arrest_order")
	ok(g.police.size() == 1 and g.police.has(2), "위협 체포령: 수배된 요원(투옥 최다)에게 경찰이 붙음")

	g = _new(CH)
	g.players[0]["pos"] = Vector2i(3, 3)
	g.players[1]["pos"] = Vector2i(5, 5)
	g.players[2]["pos"] = Vector2i(5, 5)
	g.players[3]["pos"] = Vector2i(9, 9)
	_threat(g, "tailing")
	_cov("threat", "tailing")
	ok(g.police.size() == 1 and g.police.has(3) and g.police[3]["pos"] == Vector2i(9, 9), "위협 미행: 고립된 요원에게 경찰이 붙음")

	g = _new(CH)
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9)])
	g.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_threat(g, "mp_patrol")
	_cov("threat", "mp_patrol")
	ok(g.police[0]["pos"] == Vector2i(5, 7), "위협 헌병 순찰: 추격 중인 경찰이 2칸 다가옴")
	_threat(g, "mp_patrol")
	ok(g.players[0]["jailed"] and not g.police.has(0), "위협 헌병 순찰: 따라잡으면 체포되어 투옥")

	g = _new(CH)
	g.players[0]["pos"] = Vector2i(3, 3)
	g.players[1]["jail_count"] = 1
	var checks_before := g.tile_deck.count("check")
	_threat(g, "checkpoint_add")
	_cov("threat", "checkpoint_add")
	var check_cells := []
	for c in g.board:
		if g.board[c]["type"] == "check":
			check_cells.append(c)
	ok(check_cells.size() == 2 and g.tile_deck.count("check") == checks_before - 2, "위협 검문 강화: 검문소 두 개가 깔리고 더미에서 빠짐")
	var near_iso := false
	var near_wanted := false
	for c in check_cells:
		near_iso = near_iso or _adj(c, Vector2i(3, 3))
		near_wanted = near_wanted or _adj(c, Vector2i(5, 5))
	ok(near_iso and near_wanted, "위협 검문 강화: 고립된 요원 옆과 수배된 요원 옆에 하나씩")

	g = _new(CH)
	_threat(g, "curfew")
	_cov("threat", "curfew")
	_turn(g, 0, 4)
	ok(g.today["dice_mod"] == -1 and g.steps_left == 3, "위협 통금령: 오늘 이동 주사위 -1")

	g = _new(CH)
	var sp0 := g.police_speed()
	_threat(g, "special_alert")
	_cov("threat", "special_alert")
	ok(g.police_speed() == sp0 + 1, "위협 특별 경계: 오늘 경찰 이동 +1")

	g = _new(CH)
	_threat(g, "monsoon")
	_cov("threat", "monsoon")
	ok(g.today["dice_mod"] == -1 and g.police_speed() == int(g.data.rules["police"]["speed_by_alert"][0]) - 1, "위협 장마: 이동 주사위 -1, 경찰 이동 -1")

	g = _new(CH)
	_threat(g, "air_raid")
	_cov("threat", "air_raid")
	ok(g.police_speed() == int(g.data.rules["police"]["speed_by_alert"][0]) - 1 and g.today["dice_mod"] == 0, "위협 공습경보: 경찰 이동 -1")
	g.today["police_speed"] = -99
	ok(g.police_speed() == int(g.data.rules["police"]["min_speed"]), "경찰 이동은 최소값 아래로 안 내려감")

	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[0]["items"] = ["train_ticket", "telescope"]
	g.players[1]["items"] = ["train_ticket"]
	_threat(g, "house_search")
	_cov("threat", "house_search")
	ok(g.phase == "choice" and g.pending["kind"] == "discard" and g.pending["player"] == 0, "위협 가택 수색: 고립된 요원이 버릴 아이템을 고름")
	_answer(g, 1)
	ok(g.players[0]["items"] == ["train_ticket"] and g.item_discard == ["telescope"] and g.players[1]["items"] == ["train_ticket"] and g.phase == "day",
		"위협 가택 수색: 고른 아이템 1장만 버려지고 다른 요원은 그대로")
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[0]["items"] = ["telescope"]
	_threat(g, "house_search")
	ok(g.phase == "day" and g.players[0]["items"].is_empty() and g.item_discard == ["telescope"], "위협 가택 수색: 아이템이 한 장이면 묻지 않고 버림")
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	_threat(g, "house_search")
	ok(g.phase == "day" and g.item_discard.is_empty() and g.exposure == 0 and g.police.is_empty(), "위협 가택 수색: 버릴 아이템이 없으면 아무 일 없음 (군자금은 아직 없음)")
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[0]["jailed"] = true
	g.players[0]["pos"] = g.data.bases[0]
	g.players[0]["items"] = ["telescope"]
	g.players[1]["pos"] = Vector2i(5, 5)
	g.players[2]["pos"] = Vector2i(5, 5)
	g.players[3]["pos"] = Vector2i(5, 5)
	_threat(g, "house_search")
	ok(g.players[0]["items"].is_empty(), "위협 가택 수색: 감옥에 있는 요원도 대상 (include_jailed)")
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[3]["pos"] = Vector2i(8, 8)
	g.players[0]["items"] = ["telescope"]
	g.players[3]["items"] = ["train_ticket"]
	_threat(g, "house_search")
	ok(g.phase == "choice" and g.pending["kind"] == "pick_player" and g.pending["player"] == g.leader, "위협 가택 수색: 고립된 요원이 동점이면 리더가 고름")
	_answer(g, 3)
	ok(g.players[3]["items"].is_empty() and g.players[0]["items"] == ["telescope"], "위협 가택 수색: 리더가 고른 요원이 버림")

	g = _new(CH)
	g.exposure = 3
	_threat(g, "calm_day")
	_cov("threat", "calm_day")
	ok(g.exposure == 2, "위협 평온한 하루: 노출 -1")

	g = _new(CH)
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = g.data.bases[2]
	g.players[3]["jailed"] = true
	g.players[3]["pos"] = g.data.bases[0]
	_threat(g, "prison_riot")
	_cov("threat", "prison_riot")
	ok(not g.players[1]["jailed"] and not g.players[3]["jailed"] and g.police.is_empty(), "위협 감옥 폭동: 감옥 전원 탈출, 경찰은 안 붙음")


# ------------------------------------------------------------------ 이벤트 카드 (10종)

func _test_event_cards() -> void:
	var g := _new(CH)
	g.players[0]["pos"] = Vector2i(3, 3)
	_event(g, 0, "print_shop")
	_cov("event", "print_shop")
	ok(g.intel["barracks"] == 1, "이벤트 지하 인쇄소: 가장 가까운 거점 첩보 +1")

	# 뒷골목: 실제 이동 흐름 (이벤트 타일 → 옆 빈칸에 타일 → 한 칸 더)
	g = _new(CH)
	g.event_deck = ["back_alley"]
	_tile(g, Vector2i(5, 6), "event")
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(5, 6))
	_cov("event", "back_alley")
	ok(g.phase == "choice" and g.pending["kind"] == "pick_cell" and g.pending["options"].size() == 3, "이벤트 뒷골목: 타일을 깔 옆 빈칸을 고름")
	ok(_answer(g, Vector2i(5, 7)) and g.board.has(Vector2i(5, 7)) and g.board[Vector2i(5, 7)]["type"] == "normal", "이벤트 뒷골목: 고른 칸에 일반 타일")
	ok(g.phase == "turn" and g.steps_left == 1 and not g.players[0]["done_today"], "이벤트 뒷골목: 한 칸 더 갈 수 있음 (차례가 안 끝남)")
	_step(g, 0, Vector2i(5, 7))
	ok(g.players[0]["done_today"] and g.players[0]["pos"] == Vector2i(5, 7), "이벤트 뒷골목: 그 칸으로 가면 이동이 끝남")

	g = _new(CH)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[0]["pos"] = Vector2i(5, 6)
	_event(g, 0, "hideout")
	_cov("event", "hideout")
	ok(g.board[Vector2i(5, 6)]["flags"].has("hideout"), "이벤트 은신처: 이 칸이 은신처가 됨")

	g = _new(CH)
	g.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_event(g, 0, "into_crowd")
	_cov("event", "into_crowd")
	ok(not g.police.has(0) and g.exposure == 0, "이벤트 군중 속으로: 쫓기는 중이면 경찰 제거")
	g = _new(CH)
	g.exposure = 2
	_event(g, 0, "into_crowd")
	ok(g.exposure == 1, "이벤트 군중 속으로: 쫓기지 않으면 노출 -1")

	g = _new(CH)
	_event(g, 0, "secret_letter")
	_cov("event", "secret_letter")
	ok(g.players[0]["items"].size() == 1, "이벤트 밀서: 아이템 1장")

	g = _new(CH)
	_event(g, 0, "informer")
	_cov("event", "informer")
	ok(g.police.has(0) and g.police[0]["pos"] == g.players[0]["pos"], "이벤트 밀고자: 이 자리에 경찰이 나타남")

	g = _new(CH)
	g.players[0]["pos"] = Vector2i(5, 5)
	_event(g, 0, "cop_eye")
	_cov("event", "cop_eye")
	var cc := []
	for c in g.board:
		if g.board[c]["type"] == "check":
			cc.append(c)
	ok(cc.size() == 1 and _adj(cc[0], Vector2i(5, 5)), "이벤트 순사의 눈초리: 옆 빈칸 하나에 검문소")

	g = _new(CH)
	_event(g, 0, "student")
	_cov("event", "student")
	_answer(g, 0)
	ok(g.exposure == 1 and g.players[0]["items"].size() == 1, "이벤트 쫓기는 학생: 숨겨 주면 노출 +1, 아이템 1장")
	g = _new(CH)
	_event(g, 0, "student")
	_answer(g, 1)
	ok(g.exposure == 0 and g.players[0]["items"].is_empty(), "이벤트 쫓기는 학생: 외면하면 아무 일 없음")

	# 인력거: 동료를 고르고 그 옆 칸으로 (노출 +1)
	g = _new(CH)
	_lay(g, [Vector2i(5, 8), Vector2i(5, 7)])
	g.players[1]["pos"] = Vector2i(5, 8)
	_event(g, 0, "rickshaw")
	_cov("event", "rickshaw")
	_answer(g, 0)
	ok(g.phase == "choice" and g.pending["kind"] == "pick_player" and g.pending["player"] == 0, "이벤트 인력거: 찾아갈 동료를 고름")
	_answer(g, 1)
	ok(g.players[0]["pos"] == Vector2i(5, 7) and g.exposure == 1 and g.phase == "day", "이벤트 인력거: 동료의 옆 칸으로 바로 이동, 노출 +1")
	g = _new(CH)
	_event(g, 0, "rickshaw")
	_answer(g, 1)
	ok(g.players[0]["pos"] == Vector2i(5, 5) and g.exposure == 0, "이벤트 인력거: 보내면 아무 일 없음")

	g = _new(CH)
	_event(g, 0, "old_comrade")
	_cov("event", "old_comrade")
	ok(g.phase == "choice" and g.pending["kind"] == "effect_choice" and g.pending["player"] == 0 and g.pending["options"].size() == 2,
		"이벤트 옛 동지와의 재회: 아이템 1장 / 내일 주사위 +1을 고름")
	_answer(g, 0)
	ok(g.players[0]["items"].size() == 1 and g.players[0]["dice_next"] == 0 and g.phase == "day", "이벤트 옛 동지와의 재회: 아이템을 고르면 1장")
	g = _new(CH)
	_event(g, 0, "old_comrade")
	_answer(g, 1)
	ok(g.players[0]["items"].is_empty() and g.players[0]["dice_next"] == 1 and g.players[1]["dice_next"] == 0, "이벤트 옛 동지와의 재회: 내일 주사위를 고르면 내 몫만 +1")
	g._morning_dice()
	ok(g.my_dice(0).size() == int(g.data.rules["personal_dice"]) + 1 and g.my_dice(1).size() == int(g.data.rules["personal_dice"]) and g.players[0]["dice_next"] == 0,
		"이벤트 옛 동지와의 재회: 내일 아침 내 주사위가 하나 더 (다음 아침에 쓰고 지움)")
	var g3 := _new(["park", "han", "oh"])
	_event(g3, 0, "old_comrade")
	ok(g3.phase == "choice" and g3.pending["options"].size() == 2, "이벤트 옛 동지와의 재회: 인원과 상관없이 같은 선택")


# ------------------------------------------------------------------ 아이템 카드 (10종)

func _test_item_cards() -> void:
	var g := _new(CH)
	g.players[0]["items"] = ["train_ticket"]
	_turn(g, 0, 2)
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 승차권: 내 차례에 씀")
	_cov("item", "train_ticket")
	ok(g.steps_left == 5 and g.item_discard.has("train_ticket") and g.players[0]["items"].is_empty(), "아이템 승차권: 오늘 이동 +3, 카드는 버려짐")
	g.players[0]["items"] = ["train_ticket"]
	ok(not g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템: 한 차례에 한 번만 (이미 씀)")

	g = _new(CH)
	g.phase = "plan"
	_spare(g, 3, 0)
	_spare(g, 6, 0)
	_spare(g, 2, 1)
	g.players[0]["items"] = ["pocket_watch"]
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 회중시계: 아침(계획)에 씀")
	_cov("item", "pocket_watch")
	var vals := []
	for o in g.pending["options"]:
		vals.append(o["value"])
	ok(g.pending["kind"] == "pick_die" and "0:1" in vals and "0:-1" in vals and not "1:1" in vals and not "2:1" in vals and not "2:-1" in vals,
		"아이템 회중시계: 내 주사위와 ±1을 고름 (6은 +1 불가, 남의 주사위는 아님)")
	_answer(g, "0:1")
	ok(g.op_dice[0]["value"] == 4 and g.phase == "plan", "아이템 회중시계: 내 주사위 하나의 눈 +1")
	g = _new(CH)
	g.players[0]["items"] = ["pocket_watch"]
	_turn(g, 0, 2)
	ok(not g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 회중시계: 낮에는 못 씀")

	var gd := _gd(func(d): d.rules["checks"]["evade"] = 99)
	g = _new(CH, gd)
	_tile(g, Vector2i(5, 6), "check")
	g.players[0]["items"] = ["smoke_bomb"]
	_turn(g, 0, 4)
	_step(g, 0, Vector2i(5, 6))
	_answer(g, true)
	_cov("item", "smoke_bomb")
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.exposure == 0, "아이템 연막탄: 회피 자동 성공")

	var gd_e := _gd(func(d): d.rules["checks"]["escape"] = 99)
	g = _new(CH, gd_e)
	g.players[0]["jailed"] = true
	g.players[0]["pos"] = g.data.bases[2]
	g.players[0]["items"] = ["safety_pin"]
	_turn(g, 0, 0)
	var pin_die := _spare(g, 2, 0)
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 옷핀: 갇혔을 때 씀")
	_cov("item", "safety_pin")
	ok(g.apply({"type": "escape", "player": 0, "die": pin_die}) and not g.players[0]["jailed"], "아이템 옷핀: 판정 없이 바로 탈출 (탈옥 목표 99여도)")
	g = _new(CH)
	g.players[0]["items"] = ["safety_pin"]
	_turn(g, 0, 2)
	ok(not g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 옷핀: 갇히지 않았으면 못 씀")

	# 위조 통행증: 거점 진입
	g = _new(CH)
	var base: Vector2i = g.data.bases[0]
	_tile(g, base + Vector2i(1, 0), "normal")
	g.players[0]["pos"] = base + Vector2i(1, 0)
	g.players[0]["items"] = ["forged_pass"]
	_turn(g, 0, 3)
	g.apply({"type": "use_item", "player": 0, "index": 0})
	_cov("item", "forged_pass")
	ok(g.phase == "choice" and g.pending["kind"] == "effect_choice" and g.pending["options"].size() == 2, "아이템 위조 통행증: 거점 진입 / 검문소를 고름")
	_answer(g, 0)
	_step(g, 0, base)
	ok(not g.police.has(0) and g.players[0]["done_today"], "아이템 위조 통행증: 거점에 들어가도 경찰이 안 붙음")
	# 위조 통행증: 검문소
	g = _new(CH, gd)
	_tile(g, Vector2i(5, 6), "check")
	g.players[0]["items"] = ["forged_pass"]
	_turn(g, 0, 4)
	g.apply({"type": "use_item", "player": 0, "index": 0})
	_answer(g, 1)
	_step(g, 0, Vector2i(5, 6))
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.exposure == 0 and not g.police.has(0) and g.steps_left == 3, "아이템 위조 통행증: 검문소를 판정 없이 통과 (회피 99여도)")
	ok(g.players[0]["flags"]["checkpoint_pass"] == 0, "아이템 위조 통행증: 한 번만 통과 (권리는 쓰면 사라짐)")

	# 암호 수첩
	g = _new(CH)
	g.phase = "plan"
	g.threat_deck = ["curfew", "calm_day", "air_raid"]
	g.players[0]["items"] = ["cipher_book"]
	g.apply({"type": "use_item", "player": 0, "index": 0})
	_cov("item", "cipher_book")
	ok(g.threat_deck == ["air_raid", "curfew", "calm_day"] and g.tomorrow_threat() == "calm_day", "아이템 암호 수첩: 내일 위협 카드가 덱 맨 아래로")

	# 전보: 거리 상관없이 동료에게 아이템 하나
	g = _new(CH)
	g.players[3]["pos"] = Vector2i(9, 9)
	g.players[0]["items"] = ["telegram", "smoke_bomb"]
	_turn(g, 0, 2)
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 전보: 보낼 아이템이 있으면 씀")
	_cov("item", "telegram")
	ok(g.pending["kind"] == "pick_player", "아이템 전보: 받을 동료를 고름")
	_answer(g, 3)
	ok(g.players[0]["items"].is_empty() and g.players[3]["items"] == ["smoke_bomb"] and g.phase == "turn", "아이템 전보: 먼 동료에게 아이템이 감")
	g = _new(CH)
	g.players[0]["items"] = ["telegram"]
	_turn(g, 0, 2)
	ok(not g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 전보: 보낼 다른 아이템이 없으면 못 씀")

	# 동지들의 엄호
	g = _new(CH)
	g.police[1] = {"pos": Vector2i(7, 7), "summon_turn": 0}
	g.police[2] = {"pos": Vector2i(8, 8), "summon_turn": 0}
	g.players[0]["items"] = ["comrade_cover"]
	_turn(g, 0, 2)
	g.apply({"type": "use_item", "player": 0, "index": 0})
	_cov("item", "comrade_cover")
	ok(g.police.is_empty() and g.players[0]["dice_next"] == -1, "아이템 동지들의 엄호: 모든 경찰 제거, 내일 내 주사위 1개 덜")
	g._morning_dice()
	ok(g.my_dice(0).size() == int(g.data.rules["personal_dice"]) - 1 and g.my_dice(1).size() == int(g.data.rules["personal_dice"]),
		"아이템 동지들의 엄호: 내일 아침 그 요원만 주사위를 덜 굴림")

	# 망원경: 암살 판정 +1
	var gda := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 99)
	g = _new(CH, gda)
	g.mission_row = ["m_police_chief"]
	_tile(g, Vector2i(5, 6), "assassin")
	g.players[0]["items"] = ["telescope"]
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6), false)
	_mcheck(g, 0)
	_cov("item", "telescope")
	ok(_last_dice(g, "암살").get("bonus", -1) == 1, "아이템 망원경: 암살 판정 +1")
	# 양장: 회피 판정 +2
	g = _new(CH, gd)
	_tile(g, Vector2i(5, 6), "check")
	g.players[0]["items"] = ["western_suit"]
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6))
	_cov("item", "western_suit")
	ok(_last_dice(g, "회피").get("bonus", -1) == 2, "아이템 양장: 회피 판정 +2")


# ------------------------------------------------------------------ 캐릭터 특성

func _character_with_mods(char_id: String, mods: Array) -> GameDataV2:
	return _gd(func(d): d.character(char_id)["trait"]["mods"] = mods)


func _test_traits() -> void:
	var g := _new(["yun", "han", "oh", "seo"])
	ok(g.evade_chance(g.players[0]) == 1.0, "특성 윤 소위(evade_auto): 회피 확률 100%")
	_cov("trait", "yun")

	var gd_e := _gd(func(d): d.rules["checks"]["escape"] = 99)
	g = _new(["park", "han", "oh", "seo"], gd_e)
	g.players[0]["jailed"] = true
	g.players[0]["pos"] = g.data.bases[2]
	_turn(g, 0, 0)
	g.apply({"type": "escape", "player": 0, "die": _spare(g, 2, 0)})
	ok(_last_dice(g, "탈옥").get("bonus", -1) == 3, "특성 박 하사(escape_bonus): 탈옥 판정 +3")
	_cov("trait", "park")

	g = _new(["han", "park", "oh", "seo"])
	ok(g.stat(g.players[0], "rescued_move_bonus") == 2, "특성 한 간호장교(rescued_move_bonus): +2 (구출 시험은 2a)")
	_cov("trait", "han")

	var gda := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 99)
	g = _new(["oh", "han", "park", "seo"], gda)
	g.mission_row = ["m_police_chief"]
	_tile(g, Vector2i(5, 6), "assassin")
	_turn(g, 0, 0)
	var ohd := _spare(g, 6, 0)
	ok(g.mission_check_cells(g.players[0]) == [Vector2i(5, 6)], "특성 오 의병(assassin_adjacent): 옆 칸의 암살 표적에서도 판정할 수 있음")
	ok(g.apply({"type": "mission_check", "player": 0, "die": ohd, "cell": Vector2i(5, 6)}) and g.players[0]["pos"] == START and _count_dice(g, "암살") == 1,
		"특성 오 의병: 옆 칸에서 쏜다 (내 자리는 그대로, 실패해도 자동으로 다시 굴리지 않음)")
	var g2 := _new(["park", "han", "oh", "seo"], gda)
	g2.mission_row = ["m_police_chief"]
	_tile(g2, Vector2i(5, 6), "assassin")
	_turn(g2, 0, 0)
	_spare(g2, 6, 0)
	ok(g2.mission_check_cells(g2.players[0]).is_empty(), "특성 오 의병: 다른 요원은 옆 칸에서 판정할 수 없음 (대조)")
	var g2b := _new(["oh", "han", "park", "seo"], gda)
	g2b.mission_row = ["m_leaflets"]
	_tile(g2b, Vector2i(5, 6), "sabotage")
	_turn(g2b, 0, 0)
	_spare(g2b, 6, 0)
	ok(g2b.mission_check_cells(g2b.players[0]).is_empty(), "특성 오 의병: 옆 칸에서는 암살 판정만 (방해는 제자리에서)")
	_cov("trait", "oh")

	g = _new(["seok", "han", "oh", "seo"])
	_fx(g, 0, [{"op": "gain_bomb", "count": 3}])
	ok(g.bomb_slots(g.players[0]) == 2 and g.players[0]["bombs"] == 2, "특성 석 기술자(bomb_slots): 폭탄 2개까지")
	_cov("trait", "seok")

	var gds := _gd(func(d): d.missions["types"]["sabotage"]["condition"]["target"] = 0)
	g = _new(["mun", "han", "oh", "seo"], gds)
	g.mission_row = ["m_burn_conscript"]
	g.exposure = 2
	_tile(g, Vector2i(5, 6), "sabotage")
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6), false)
	_mcheck(g, 0)
	ok(_last_dice(g, "회피").get("bonus", -1) == 2, "특성 문 선전대원(sabotage_bonus): 방해 판정 +2")
	ok(g.exposure == 1 and g.ready == 1 and g.intel["prison"] == 1, "특성 문 선전대원(sabotage_exposure): 방해에 성공하면 노출 -1")
	g2 = _new(["park", "han", "oh", "seo"], gds)
	g2.mission_row = ["m_burn_conscript"]
	g2.exposure = 2
	_tile(g2, Vector2i(5, 6), "sabotage")
	_turn(g2, 0, 2)
	_step(g2, 0, Vector2i(5, 6), false)
	_mcheck(g2, 0)
	ok(g2.exposure == 2, "특성 문 선전대원: 다른 요원은 노출이 그대로 (대조)")
	_cov("trait", "mun")

	g = _new(["gaeddong", "han", "oh", "seo"])
	ok(g.move_value(g.players[0], _spare(g, 1, 0)) == 3 and g.move_value(g.players[0], _spare(g, 2, 0)) == 3 and g.move_value(g.players[0], _spare(g, 5, 0)) == 5, "특성 김개똥(move_min3): 이동에 쓴 1·2는 3")
	_cov("trait", "gaeddong")

	g = _new(["makrye", "han", "oh", "seo"])
	g.item_deck = ["telescope", "western_suit", "train_ticket"]
	ok(g.hand_limit(g.players[0]) == int(g.data.rules["hand_limit"]) + 1, "특성 주모 막례(hand_limit): 손패 +1")
	_fx(g, 0, [{"op": "draw_item", "count": 1}])
	ok(g.phase == "choice" and g.pending["kind"] == "draw_pick" and g.pending["options"].size() == 2, "특성 주모 막례(item_draw_choice): 아이템을 2장 보고 1장 고름")
	_answer(g, 0)
	ok(g.players[0]["items"].size() == 1 and g.item_discard.size() == 1, "특성 주모 막례: 남은 1장은 버림")
	_cov("trait", "makrye")

	g = _new(["choi", "han", "oh", "seo"])
	g.mission_row = ["m_bribe_guard"]
	var prison: Vector2i = g.data.bases[2]
	_tile(g, prison + Vector2i(0, -1), "normal")
	g.players[0]["pos"] = prison + Vector2i(0, -1)
	_turn(g, 0, 3)
	_step(g, 0, prison)
	ok(g.intel["prison"] == 2, "특성 최 훈장(mission_intel_bonus): 잠입 미션 첩보 +1 더")
	_cov("trait", "choi")

	g = _new(["jeong", "han", "oh", "seo"])
	g.threat_deck = ["curfew", "calm_day", "air_raid"]
	ok(g.threat_preview() == ["air_raid", "calm_day"] and g.threat_preview(1) == ["air_raid"], "특성 정 인쇄공(threat_peek): 내일부터 위협 2장을 미리 봄")
	g.threat_deck = ["curfew"]
	ok(g.threat_preview() == ["curfew"], "특성 정 인쇄공: 덱이 모자라면 있는 만큼만")
	var gn := _new(["park", "han", "oh", "seo"])
	gn.threat_deck = ["curfew", "calm_day"]
	ok(gn.threat_preview().is_empty(), "특성 정 인쇄공: 다른 팀은 미리 볼 수 없음 (대조)")
	_cov("trait", "jeong")

	var gdb0 := _gd(func(d): d.rules["checks"]["evade"] = 0)
	g = _new(["seo", "han", "oh", "park"], gdb0)
	g._summon(g.players[0])
	ok(not g.police.has(0), "특성 서 마담(block_police_with_evade): 회피에 성공하면 경찰이 안 붙음")
	var gdb1 := _gd(func(d): d.rules["checks"]["evade"] = 99)
	g = _new(["seo", "han", "oh", "park"], gdb1)
	g._summon(g.players[0])
	ok(g.police.has(0), "특성 서 마담: 회피에 실패하면 경찰이 붙음")
	_cov("trait", "seo")

	# 이 차장: 차례를 마칠 때 동료가 있는 옆 칸으로 한 칸
	g = _new(["lee", "han", "oh", "seo"])
	_lay(g, [Vector2i(5, 6), Vector2i(5, 4)])
	g.players[1]["pos"] = Vector2i(5, 6)
	_turn(g, 0, 0)
	ok(g.hop_cells(g.players[0]) == [Vector2i(5, 6)], "특성 이 차장(end_move_hop_to_ally): 동료가 있는 옆 칸만 후보 (동료 없는 옆 칸은 아님)")
	g.apply({"type": "end_turn", "player": 0})
	ok(g.phase == "choice" and g.pending["kind"] == "hop" and g.pending["options"].size() == 2, "특성 이 차장: 차례를 마칠 때 동료가 있는 옆 칸으로 옮길지 묻는다")
	_answer(g, Vector2i(5, 6))
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.players[0]["done_today"] and g.phase == "day", "특성 이 차장: 옮기면 동료와 같은 칸에 서고 차례가 끝남")
	g = _new(["lee", "han", "oh", "seo"])
	_lay(g, [Vector2i(5, 6)])
	g.players[1]["pos"] = Vector2i(5, 6)
	_turn(g, 0, 0)
	g.apply({"type": "end_turn", "player": 0})
	_answer(g, "no")
	ok(g.players[0]["pos"] == START and g.players[0]["done_today"], "특성 이 차장: 옮기지 않아도 됨")
	g = _new(["lee", "han", "oh", "seo"])
	_lay(g, [Vector2i(5, 6)])
	g.players[1]["pos"] = Vector2i(5, 6)
	g.police[2] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	_turn(g, 0, 0)
	ok(g.hop_cells(g.players[0]).is_empty(), "특성 이 차장: 경찰이 있는 칸으로는 못 옮김")
	_cov("trait", "lee")

	# 데이터에 직접 넣어 보는 나머지 stat (이 판의 카드에는 아직 없는 것들)
	var gdx := _character_with_mods("park", [{"stat": "move_bonus", "value": 1}, {"stat": "spare_die_bonus", "value": 1},
		{"stat": "base_no_police", "value": 1}, {"stat": "evade_bonus", "value": 2}, {"stat": "assassin_bonus", "value": 3}])
	g = _new(CH, gdx)
	_turn(g, 0, 2)
	ok(g.steps_left == 3, "stat move_bonus: 이동 +1")
	var gb := _new(CH, gdx)
	var b0: Vector2i = gb.data.bases[0]
	_tile(gb, b0 + Vector2i(1, 0), "normal")
	gb.players[0]["pos"] = b0 + Vector2i(1, 0)
	_turn(gb, 0, 2)
	_step(gb, 0, b0)
	ok(not gb.police.has(0), "stat base_no_police: 거점에 들어가도 경찰이 안 붙음")
	ok(gb.stat(gb.players[0], "evade_bonus") == 2 and gb.stat(gb.players[0], "assassin_bonus") == 3, "stat evade_bonus·assassin_bonus: 합산")
	var gdc := _gd(func(d):
		d.rules["checks"]["evade"] = 99
		d.character("park")["trait"]["mods"] = [{"stat": "evade_bonus", "value": 2}])
	g = _new(CH, gdc)
	_tile(g, Vector2i(5, 6), "check")
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6))
	ok(_last_dice(g, "회피").get("bonus", -1) == 2, "stat evade_bonus: 회피 판정에 더해짐")


# ------------------------------------------------------------------ 캐릭터 능력 (12개)

func _test_abilities() -> void:
	# 윤 소위: 아침에 아무 요원의 주사위 하나 다시 굴림
	var g := _new(["yun", "han", "oh", "seo"])
	g.phase = "plan"
	_spare(g, 3, 0)
	_spare(g, 6, 1)
	_spare(g, 2, 2)
	ok(g.apply({"type": "ability", "player": 0}), "능력 무전 지원: 아침(계획)에 씀")
	ok(g.phase == "choice" and g.pending["kind"] == "pick_die" and g.pending["options"].size() == 3, "능력 무전 지원: 다른 요원의 주사위까지 골라 다시 굴림")
	_answer(g, 2)
	ok(_log_has(g, "요원 oh의 주사위을(를) 다시 굴려") and g.phase == "plan" and g.players[0]["ability_day"] == g.day, "능력 무전 지원: 고른 주사위를 다시 굴림")
	_cov("ability", "yun")

	# 박 하사: 동료의 오늘 이동 +1
	g = _new(["park", "han", "oh", "seo"])
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.today["move_today"][1] == 1, "능력 전령: 동료의 오늘 이동 +1")
	g.phase = "day"
	g.current = -1
	_turn(g, 1, 2)
	ok(g.steps_left == 3, "능력 전령: 그 동료가 차례를 시작하면 이동이 3칸")
	_cov("ability", "park")

	# 한 간호장교: 같은 칸이나 옆 칸 동료의 다음 판정 +2
	var gd := _gd(func(d): d.rules["checks"]["evade"] = 99)
	g = _new(["han", "park", "oh", "seo"], gd)
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}), "능력 응급 처치: 같은 칸 동료에게")
	ok(g.players[1]["grants"].size() == 1 and g.players[1]["grants"][0]["kind"] == "check_bonus" and g.players[1]["grants"][0]["value"] == 2, "능력 응급 처치: 다음 판정 +2 권리")
	_tile(g, Vector2i(5, 6), "check")
	g.phase = "day"
	g.current = -1
	_turn(g, 1, 3)
	_step(g, 1, Vector2i(5, 6))
	ok(_last_dice(g, "회피").get("bonus", -1) == 2 and g.players[1]["grants"].is_empty(), "능력 응급 처치: 다음 판정에 +2가 더해지고 권리는 사라짐")
	_cov("ability", "han")
	g = _new(["han", "park", "oh", "seo"])
	g.players[1]["pos"] = Vector2i(5, 8)
	_turn(g, 0, 2)
	ok(not g.apply({"type": "ability", "player": 0, "target": 1}), "능력 응급 처치: 멀리 있는 동료는 안 됨")

	# 오 의병: 내 칸의 경찰 1개 제거
	g = _new(["oh", "han", "park", "seo"])
	g.police[1] = {"pos": Vector2i(5, 5), "summon_turn": 0}
	g.police[2] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0}) and not g.police.has(1) and g.police.has(2), "능력 기습: 내 칸의 경찰 1개만 제거")
	_cov("ability", "oh")

	# 석 기술자: 보급 타일 옆, 아이템 1장 버리고 폭탄
	g = _new(["seok", "han", "oh", "seo"])
	_tile(g, Vector2i(5, 6), "supply")
	g.players[0]["items"] = ["train_ticket"]
	_turn(g, 0, 2)
	var sup := g.bomb_supply
	ok(g.apply({"type": "ability", "player": 0}), "능력 급조 폭탄: 보급 타일 옆에서 씀")
	ok(g.players[0]["bombs"] == 1 and g.players[0]["items"].is_empty() and g.item_discard.has("train_ticket") and g.bomb_supply == sup - 1, "능력 급조 폭탄: 아이템 1장을 버리고 폭탄 1개")
	g = _new(["seok", "han", "oh", "seo"])
	_tile(g, Vector2i(5, 6), "supply")
	_turn(g, 0, 2)
	ok(not g.apply({"type": "ability", "player": 0}), "능력 급조 폭탄: 버릴 아이템이 없으면 못 씀")
	_cov("ability", "seok")

	# 문 선전대원: 옆 칸 경찰 2칸 물러남
	g = _new(["mun", "han", "oh", "seo"])
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9)])
	g.police[1] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0}) and g.police[1]["pos"] == Vector2i(5, 8), "능력 군중 동원: 옆 칸 경찰이 2칸 물러남")
	_cov("ability", "mun")

	# 김개똥: 동료를 내 옆 칸으로
	g = _new(["gaeddong", "han", "oh", "seo"])
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(3, 3)
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.players[1]["pos"] == START, "능력 길 안내: 동료를 내 칸으로 데려옴")
	ok(g.phase == "turn" and not g.players[1]["done_today"] and g.exposure == 0, "능력 길 안내: 데려온 칸의 효과는 없음 (차례도 그대로)")
	_cov("ability", "gaeddong")

	# 주모 막례: 아이템을 거저 줌 (사용으로 안 침)
	g = _new(["makrye", "han", "oh", "seo"])
	g.players[0]["items"] = ["telescope"]
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}), "능력 주막 인심: 같은 칸 동료에게")
	ok(g.players[1]["items"] == ["telescope"] and g.players[0]["items"].is_empty() and g.players[0]["item_uses"] == 0, "능력 주막 인심: 아이템이 가고 아이템 사용으로 안 침")
	g = _new(["makrye", "han", "oh", "seo"])
	_turn(g, 0, 2)
	ok(not g.apply({"type": "ability", "player": 0, "target": 1}), "능력 주막 인심: 줄 아이템이 없으면 못 씀")
	_cov("ability", "makrye")

	# 최 훈장: 더미에서 타일을 골라 옆 빈칸에 깔고 더미를 섞음
	g = _new(["choi", "han", "oh", "seo"])
	_turn(g, 0, 2)
	var supply_before := g.tile_deck.count("supply")
	ok(g.apply({"type": "ability", "player": 0}) and g.pending["kind"] == "pick_tile", "능력 마을 사람들: 더미의 타일 종류를 고름")
	ok(_answer(g, "supply") and g.pending["kind"] == "pick_cell" and g.pending["options"].size() == 4, "능력 마을 사람들: 깔 칸을 고름")
	_answer(g, Vector2i(5, 6))
	ok(g.board[Vector2i(5, 6)]["type"] == "supply" and g.tile_deck.count("supply") == supply_before - 1 and _log_has(g, "타일 더미를 다시 섞었습니다") and g.phase == "turn", "능력 마을 사람들: 고른 타일이 깔리고 더미를 섞음")
	_cov("ability", "choi")

	# 정 인쇄공: 3칸 안의 동료에게 내 주사위 하나를 건넴 (하루 건네기 횟수에 안 셈)
	g = _new(["jeong", "han", "oh", "seo"])
	_flat(g)
	g.players[1]["pos"] = Vector2i(5, 7)
	g.players[2]["pos"] = Vector2i(5, 9)
	g.players[3]["pos"] = Vector2i(9, 9)
	var cd1 := _spare(g, 4, 0)
	var cd2 := _spare(g, 2, 0)
	_turn(g, 0, 0)
	ok(g.ability_targets(g.players[0]) == [1], "능력 연락망: 3칸 안의 동료만 대상 (4칸 밖은 안 됨)")
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.phase == "choice" and g.pending["kind"] == "pick_die" and g.pending["options"].size() == 2,
		"능력 연락망: 주사위가 둘이면 건넬 것을 고름")
	ok(_answer(g, cd2) and g.op_dice[cd2]["owner"] == 1 and g.op_dice[cd1]["owner"] == 0 and g.phase == "turn", "능력 연락망: 고른 주사위가 동료 것이 됨")
	ok(g.players[0]["gives_today"] == 0 and g.players[0]["stats"]["gives"] == 1 and g.players[0]["ability_day"] == g.day, "능력 연락망: 하루 건네기 횟수에는 안 세고 통계에는 셈")
	ok(not g.can_use_ability(g.players[0], 1), "능력 연락망: 능력은 하루 한 번")
	_cov("ability", "jeong")
	g = _new(["jeong", "han", "oh", "seo"])
	var one := _spare(g, 5, 0)
	g.players[1]["pos"] = Vector2i(5, 6)
	_flat(g)
	_turn(g, 0, 0)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.phase == "turn" and g.op_dice[one]["owner"] == 1, "능력 연락망: 주사위가 하나뿐이면 묻지 않고 건넴")
	g.players[1]["done_today"] = true
	g.players[1]["jailed"] = false
	var g_late := _new(["jeong", "han", "oh", "seo"])
	_flat(g_late)
	_spare(g_late, 5, 0)
	g_late.players[1]["pos"] = Vector2i(5, 6)
	g_late.players[1]["done_today"] = true
	_turn(g_late, 0, 0)
	ok(not g_late.ability_targets(g_late.players[0]).has(1), "능력 연락망: 이미 차례를 마친 동료에게는 건넬 수 없음")
	g = _new(["jeong", "han", "oh", "seo"])
	_turn(g, 0, 0)
	ok(g.ability_targets(g.players[0]).is_empty(), "능력 연락망: 건넬 주사위가 없으면 쓸 수 없음")
	# 건네기 액션(하루 1번)과 따로 센다
	g = _new(["jeong", "han", "oh", "seo"])
	_spare(g, 3, 0)
	_spare(g, 4, 0)
	_spare(g, 5, 0)
	g.players[2]["pos"] = Vector2i(9, 9)
	g.players[3]["pos"] = Vector2i(9, 9)
	_turn(g, 0, 0)
	g.apply({"type": "ability", "player": 0, "target": 1})
	_answer(g, 0)
	ok(g.apply({"type": "give_die", "player": 0, "die": 1, "target": 1}) and not g.apply({"type": "give_die", "player": 0, "die": 2, "target": 1}),
		"능력 연락망: 건네기 액션은 그대로 하루 1번 (연락망은 그 횟수에 안 들어감)")
	# 감옥의 동료에게도 닿음 (탈옥 판정에 쓰도록)
	g = _new(["jeong", "han", "oh", "seo"])
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = g.data.bases[0]
	g.players[2]["pos"] = Vector2i(9, 9)
	g.players[3]["pos"] = Vector2i(9, 9)
	var jd := _spare(g, 6, 0)
	_flat(g)
	_turn(g, 0, 0)
	ok(g.ability_targets(g.players[0]) == [1] and g.apply({"type": "ability", "player": 0, "target": 1}) and jd in g.my_dice(1), "능력 연락망: 감옥의 동료에게도 건넴")

	# 서 마담: 3칸 안의 거점 하나에 첩보 +1, 노출 +1
	g = _new(["seo", "han", "oh", "park"])
	_flat(g)
	_spare(g, 3, 0)
	_turn(g, 0, 0)
	ok(g.ability_targets(g.players[0]).is_empty(), "능력 다방 밀담: 3칸 안에 거점이 없으면 쓸 수 없음")
	g = _new(["seo", "han", "oh", "park"])
	_flat(g)
	g.players[0]["pos"] = Vector2i(2, 2)
	_turn(g, 0, 0)
	ok(g.ability_targets(g.players[0]).is_empty() and g.legal_actions().filter(func(a): return a["type"] == "ability").is_empty(),
		"능력 다방 밀담: 주사위가 없으면 쓸 수 없음 (주사위 하나를 내는 능력)")
	var sd := _spare(g, 3, 0)
	var sd2 := _spare(g, 5, 0)
	ok(g.ability_targets(g.players[0]) == [-1], "능력 다방 밀담: 거점이 3칸 안에 있으면 쓸 수 있음 (대상 없이)")
	ok(not g.apply({"type": "ability", "player": 0}), "능력 다방 밀담: 주사위를 내지 않고는 못 씀")
	ok(g.apply({"type": "ability", "player": 0, "die": sd}) and g.phase == "turn" and g.intel["barracks"] == 1 and g.exposure == 1 and g.players[0]["ability_day"] == g.day,
		"능력 다방 밀담: 가까운 거점이 하나뿐이면 곧바로 첩보 +1, 노출 +1")
	ok(g.op_dice[sd]["used"] and not g.op_dice[sd2]["used"], "능력 다방 밀담: 주사위 하나를 냄")
	var intel_sum := 0
	for id in g.intel:
		intel_sum += int(g.intel[id])
	ok(intel_sum == 1 and not g.can_use_ability(g.players[0], -1), "능력 다방 밀담: 다른 거점은 그대로, 하루 한 번")
	_cov("ability", "seo")
	g = _new(["seo", "han", "oh", "park"])
	_flat(g)
	g.players[0]["pos"] = Vector2i(3, 2)
	g.exposure = 2
	_turn(g, 0, 0)
	g.apply({"type": "ability", "player": 0, "die": _spare(g, 3, 0)})
	ok(g.exposure == 3 and g.alert_level() == 2 and g.police.size() == 1, "능력 다방 밀담: 노출이 문턱에 닿으면 경계 단계가 오르고 경찰이 출동")
	g = _new(["seo", "han", "oh", "park"])
	_flat(g)
	g.players[0]["pos"] = Vector2i(5, 1)
	_fx(g, 0, [{"op": "intel", "base": "choose", "range": 4, "value": 1}])
	ok(g.phase == "choice" and g.pending["kind"] == "intel_base" and g.pending["options"].size() == 2, "효과 intel(choose + range): 그 안의 거점 둘 중에서 고름")
	_answer(g, "police_hq")
	ok(g.intel["police_hq"] == 1 and g.intel["barracks"] == 0, "효과 intel(choose + range): 고른 거점에 첩보 +1")

	# 이 차장: 이번 차례 검문소 하나를 판정 없이
	g = _new(["lee", "han", "oh", "seo"], gd)
	_tile(g, Vector2i(5, 6), "check")
	_turn(g, 0, 3)
	ok(g.apply({"type": "ability", "player": 0}), "능력 표 검사: 내 차례에 씀")
	_step(g, 0, Vector2i(5, 6))
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.exposure == 0 and g.steps_left == 2, "능력 표 검사: 검문소를 판정 없이 지나감 (회피 99여도)")
	_cov("ability", "lee")


# ------------------------------------------------------------------ 협동 미션 (5종)

func _test_coop_missions() -> void:
	# 엄호 잠입: 한 명이 거점에 들어갈 때 다른 한 명이 옆 칸
	var g := _new(CH)
	var b: Vector2i = g.data.bases[0]
	g.mission_row = ["m_cover_entry"]
	_tile(g, b + Vector2i(1, 0), "normal")
	_tile(g, b + Vector2i(0, 1), "normal")
	g.players[0]["pos"] = b + Vector2i(1, 0)
	g.players[1]["pos"] = b + Vector2i(0, 1)
	_turn(g, 0, 3)
	_step(g, 0, b)
	_cov("coop", "m_cover_entry")
	ok(g.mission_row.is_empty() and g.ready == 1 and g.intel["barracks"] == 2, "협동 엄호 잠입: 결행 준비 +1, 그 거점 첩보 +2")
	ok(not g.police.has(0), "협동 엄호 잠입: 경찰이 붙지 않음")
	g = _new(CH)
	g.mission_row = ["m_cover_entry"]
	_tile(g, b + Vector2i(1, 0), "normal")
	g.players[0]["pos"] = b + Vector2i(1, 0)
	_turn(g, 0, 3)
	_step(g, 0, b)
	ok(g.mission_row == ["m_cover_entry"] and g.police.has(0), "협동 엄호 잠입: 옆 칸에 동료가 없으면 안 이뤄지고 경찰이 붙음")

	# 동시 습격: 같은 날 두 명이 다른 암살 타일에서 성공 (밤에 확인)
	var gda := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 0)
	g = _new(CH, gda)
	g.mission_row = ["m_simul_strike"]
	_tile(g, Vector2i(5, 6), "assassin")
	_tile(g, Vector2i(6, 5), "assassin")
	g.players[2]["done_today"] = true
	g.players[3]["done_today"] = true
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6), false)
	_mcheck(g, 0)
	_end(g, 0)
	ok(g.exposure == 1 and g.ready == 0 and g.players[0]["done_today"] and g.today["assassin_wins"].size() == 1, "협동 동시 습격: 협동 미션만 줄에 있어도 암살 타일에서 판정, 성공하면 노출 +1")
	_turn(g, 1, 2)
	_step(g, 1, Vector2i(6, 5), false)
	_mcheck(g, 1)
	_end(g, 1)
	_cov("coop", "m_simul_strike")
	ok(g.ready == 3 and g.mission_discard.has("m_simul_strike"), "협동 동시 습격: 밤에 이뤄져 결행 준비 +3")
	ok(g.day == 2 and g.phase in ["plan", "choice"], "협동 동시 습격: 밤이 지나 다음 날 아침이 됨")
	# 같은 사람이 같은 타일을 두 번은 안 됨
	g = _new(CH, gda)
	g.mission_row = ["m_simul_strike"]
	_tile(g, Vector2i(5, 6), "assassin")
	for i in [1, 2, 3]:
		g.players[i]["done_today"] = true
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6), false)
	_mcheck(g, 0)
	_end(g, 0)
	ok(g.mission_row.has("m_simul_strike") and g.ready == 0, "협동 동시 습격: 한 명만 성공하면 안 이뤄짐")
	# 암살 타일이 모자라면 줄에서 빠짐
	g = _new(CH)
	g.tile_deck = ["normal"]
	_tile(g, Vector2i(5, 6), "assassin")
	ok(not g.mission_feasible("m_simul_strike") and g.mission_feasible("m_cover_entry"), "협동 동시 습격: 암살 타일이 둘 미만이면 이룰 수 없음")

	# 형무소 면회: 두 명이 같은 날 형무소 옆 칸에서 차례를 마침
	g = _new(CH)
	var pr: Vector2i = g.data.bases[2]
	g.mission_row = ["m_prison_visit"]
	_lay(g, [pr + Vector2i(0, -1), pr + Vector2i(1, 0), pr + Vector2i(0, -2), pr + Vector2i(2, 0)])
	g.players[0]["pos"] = pr + Vector2i(0, -2)
	g.players[1]["pos"] = pr + Vector2i(2, 0)
	_turn(g, 0, 1)
	_step(g, 0, pr + Vector2i(0, -1))
	_cov("coop", "m_prison_visit")
	ok(g.mission_row == ["m_prison_visit"], "협동 형무소 면회: 한 명만으로는 안 이뤄짐")
	_turn(g, 1, 1)
	_step(g, 1, pr + Vector2i(1, 0))
	ok(g.mission_row.is_empty() and g.ready == 1 and g.intel["prison"] == 2, "협동 형무소 면회: 두 명이 옆 칸에서 마치면 형무소 첩보 +2, 결행 준비 +1")

	# 연락선 잇기: 서로 반대쪽 가장자리
	g = _new(CH)
	g.mission_row = ["m_link_line"]
	g.exposure = 2
	_lay(g, [Vector2i(1, 5), Vector2i(0, 5), Vector2i(9, 5), Vector2i(10, 5)])
	g.players[0]["pos"] = Vector2i(1, 5)
	g.players[1]["pos"] = Vector2i(9, 5)
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(0, 5))
	_cov("coop", "m_link_line")
	ok(g.mission_row == ["m_link_line"], "협동 연락선 잇기: 한쪽 가장자리만으로는 안 이뤄짐")
	_turn(g, 1, 1)
	_step(g, 1, Vector2i(10, 5))
	ok(g.mission_row.is_empty() and g.ready == 2 and g.exposure == 1, "협동 연락선 잇기: 반대쪽 가장자리 두 명 → 결행 준비 +2, 노출 -1")
	g = _new(CH)
	g.mission_row = ["m_link_line"]
	_lay(g, [Vector2i(1, 5), Vector2i(0, 5), Vector2i(1, 4), Vector2i(0, 4)])
	g.players[0]["pos"] = Vector2i(1, 5)
	g.players[1]["pos"] = Vector2i(1, 4)
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(0, 5))
	_turn(g, 1, 1)
	_step(g, 1, Vector2i(0, 4))
	ok(g.mission_row == ["m_link_line"], "협동 연락선 잇기: 같은 쪽 가장자리 두 명은 안 됨")

	# 총독부 앞 집회: 총독부 옆 칸 두 명 → 첩보 +2, 결행 준비 +1, 노출 +1
	g = _new(CH)
	var gg: Vector2i = g.data.bases[3]
	g.mission_row = ["m_gg_rally"]
	_lay(g, [gg + Vector2i(0, -1), gg + Vector2i(-1, 0), gg + Vector2i(0, -2), gg + Vector2i(-2, 0)])
	g.players[0]["pos"] = gg + Vector2i(0, -2)
	g.players[1]["pos"] = gg + Vector2i(-2, 0)
	_turn(g, 0, 1)
	_step(g, 0, gg + Vector2i(0, -1))
	_turn(g, 1, 1)
	_step(g, 1, gg + Vector2i(-1, 0))
	_cov("coop", "m_gg_rally")
	ok(g.mission_row.is_empty() and g.ready == 1 and g.intel["gg"] == 2 and g.exposure == 1, "협동 총독부 앞 집회: 첩보 +2, 결행 준비 +1, 노출 +1")
	# 다음 날로 넘어가면 차례 기록이 비워짐
	ok(g.today["ends"].size() == 2, "협동: 오늘 차례를 마친 자리를 기록")


# ------------------------------------------------------------------ 나머지 op

func _test_ops_misc() -> void:
	var g := _new(CH)
	# 2막 효과도 공통 해석기를 통해 실행한다.
	g.bomb_supply = 0
	_fx(g, 0, [{"op": "refill_supply"}, {"op": "scene_check_mod_today", "value": 1}])
	ok(g.bomb_supply == int(g.data.rules["bomb_supply"]) and g.today["scene_mod"] == 1, "2막 효과: 폭탄 보급과 오늘 판정 보정")
	ok(not _log_has(g, "(2b 미구현)"), "훅: (2b 미구현)은 더 이상 없음")

	# police_send_far
	g = _new(CH)
	g.police[0] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	g.players[0]["pos"] = Vector2i(2, 2)
	_fx(g, 0, [{"op": "police_send_far"}])
	ok(g.police[0]["pos"] == g.data.bases[3], "op police_send_far: 나를 쫓는 경찰이 가장 먼 거점으로")

	# police_remove: mine / all
	g = _new(CH)
	g.police[0] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	g.police[1] = {"pos": Vector2i(5, 7), "summon_turn": 0}
	_fx(g, 0, [{"op": "police_remove", "scope": "mine"}])
	ok(not g.police.has(0) and g.police.has(1), "op police_remove(mine): 나를 쫓는 경찰만")

	# move_mod_next / move_today (대상 고르기)
	g = _new(CH)
	_fx(g, 0, [{"op": "move_mod_next", "who": "all", "value": 2}])
	ok(g.players[0]["move_mod_next"] == 2 and g.players[3]["move_mod_next"] == 2, "op move_mod_next(all): 모두의 다음 이동 +2")
	g = _new(CH)
	_fx(g, 0, [{"op": "move_today", "who": "ally", "value": 1}])
	ok(g.phase == "choice" and g.pending["kind"] == "pick_player" and g.pending["player"] == 0 and g.pending["options"].size() == 3, "대상 ally: 동료가 여럿이면 쓰는 사람이 고름")
	_answer(g, 2)
	ok(g.today["move_today"][2] == 1, "op move_today: 고른 동료의 오늘 이동 +1")

	# 대상: wanted · nearest_to_base · all_jailed
	g = _new(CH)
	g.players[1]["pos"] = Vector2i(2, 2)
	g.players[0]["pos"] = Vector2i(8, 8)
	g.players[2]["pos"] = Vector2i(8, 8)
	g.players[3]["pos"] = Vector2i(8, 8)
	g.launch_info = {"target": "barracks"}
	_fx(g, 0, [{"op": "police_attach", "who": "nearest_to_base", "base": "strike_base"}])
	ok(g.police.has(1) and g.police.size() == 1, "대상 nearest_to_base: 결행 거점에 가장 가까운 요원")
	g = _new(CH)
	g.players[2]["jailed"] = true
	g.players[3]["jailed"] = true
	ok(g._who_pick(g.players[0], "all_jailed", {}) == [2, 3], "대상 all_jailed: 감옥에 있는 요원 모두")

	# discard_item: 여러 장 중에서 고름
	g = _new(CH)
	g.players[0]["items"] = ["telescope", "western_suit"]
	_fx(g, 0, [{"op": "discard_item", "count": 1}, {"op": "ready", "value": 1}])
	ok(g.phase == "choice" and g.pending["kind"] == "discard", "op discard_item: 여러 장이면 버릴 카드를 고름")
	_answer(g, 1)
	ok(g.players[0]["items"] == ["telescope"] and g.ready == 1, "op discard_item: 고른 카드를 버리고 나머지 효과를 이어감")

	# give_item: 받는 손패가 넘치면 받는 사람이 버림 (손패 한도 2)
	g = _new(CH)
	g.players[0]["items"] = ["telescope"]
	g.players[1]["items"] = ["western_suit", "train_ticket"]
	_fx(g, 0, [{"op": "give_item", "range": 1, "free": true}], "ability", {"target": 1})
	ok(g.phase == "choice" and g.pending["kind"] == "discard" and g.pending["player"] == 1, "op give_item: 받는 사람의 손패가 넘치면 그 사람이 버릴 카드를 고름")
	_answer(g, 0)
	ok(g.players[1]["items"].size() == 2 and g.players[0]["items"].is_empty(), "op give_item: 한도에 맞춰짐")

	# send_item: 갇힌 동료에게도
	g = _new(CH)
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = g.data.bases[2]
	g.players[0]["items"] = ["safety_pin"]
	_fx(g, 0, [{"op": "send_item"}])
	ok(g.phase == "choice" and g.pending["options"].size() == 3, "op send_item: 갇힌 동료도 받을 수 있음")
	_answer(g, 1)
	ok(g.players[1]["items"] == ["safety_pin"], "op send_item: 갇힌 동료에게 옷핀을 보냄")

	# die_set · dice_extra_tomorrow · fewer_dice_tomorrow
	g = _new(CH)
	_spare(g, 3, 0)
	_spare(g, 4, 1)
	_fx(g, 0, [{"op": "die_set"}])
	ok(g.pending.get("kind", "") == "pick_value", "op die_set: 내 주사위가 하나뿐이면 곧바로 눈을 묻는다")
	_answer(g, 6)
	ok(g.op_dice[0]["value"] == 6 and g.op_dice[1]["value"] == 4, "op die_set: 내 주사위 하나를 원하는 눈으로 (남의 주사위는 그대로)")
	_fx(g, 0, [{"op": "dice_extra_tomorrow", "count": 1}])
	_fx(g, 1, [{"op": "fewer_dice_tomorrow", "count": 1}])
	_fx(g, 0, [{"op": "dice_extra_tomorrow", "who": "all", "count": 1}])
	ok(g.players[0]["dice_next"] == 2 and g.players[1]["dice_next"] == 0 and g.players[2]["dice_next"] == 1,
		"op dice_extra_tomorrow · fewer_dice_tomorrow: 내일 아침 몫을 늘리고 줄임 (who all 포함)")
	g._morning_dice()
	var pdn := int(g.data.rules["personal_dice"])
	ok(g.my_dice(0).size() == pdn + 2 and g.my_dice(1).size() == pdn and g.my_dice(2).size() == pdn + 1 and g.players[0]["dice_next"] == 0,
		"다음 날 아침: 늘린 만큼 더 굴리고 보정은 지움")
	g = _new(CH)
	_spare(g, 1, 1)
	_spare(g, 5, 0)
	_fx(g, 0, [{"op": "die_reroll", "scope": "any"}])
	ok(g.pending.get("kind", "") == "pick_die" and g.pending["options"].size() == 2, "op die_reroll(scope any): 아무 요원의 주사위를 고름")
	_answer(g, 0)
	ok(_log_has(g, "의 주사위을(를) 다시 굴려"), "op die_reroll: 고른 주사위를 다시 굴림")

	# threat_bury peek
	g = _new(CH)
	g.threat_deck = ["curfew", "calm_day"]
	_fx(g, 0, [{"op": "threat_bury", "peek": true}])
	ok(g.phase == "choice" and g.pending["kind"] == "pick_bury", "op threat_bury(peek): 보고 고름")
	_answer(g, false)
	ok(g.threat_deck == ["curfew", "calm_day"], "op threat_bury(peek): 그대로 둘 수 있음")
	_fx(g, 0, [{"op": "threat_bury", "peek": true}])
	_answer(g, true)
	ok(g.threat_deck == ["calm_day", "curfew"], "op threat_bury(peek): 맨 아래로 보냄")

	# place_tile(normal) 이 칸이 모자랄 때
	g = _new(CH)
	_lay(g, [Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6)])
	_fx(g, 0, [{"op": "place_tile", "type": "normal", "near": "self"}])
	ok(g.phase == "day" and _log_has(g, "타일을 깔 옆 빈칸이 없습니다"), "op place_tile: 옆 빈칸이 없으면 아무 일 없음")

	# 판정 보정 grant: reroll 권리
	# 효과 선택 후에도 합법 액션과 apply 일치
	g = _new(CH)
	g.players[0]["items"] = ["telegram", "smoke_bomb"]
	_turn(g, 0, 2)
	g.apply({"type": "use_item", "player": 0, "index": 0})
	var legal := g.legal_actions()
	var all_ok := true
	for a in legal:
		var c := RulesV2.new()
		c.load_state(g.save_state(), g.data)
		all_ok = all_ok and c.apply(a.duplicate(true))
	ok(not legal.is_empty() and all_ok, "선택: 대상 고르기 선택도 legal_actions와 apply가 같음")


# ------------------------------------------------------------------ 전부 시험했는가

func _test_coverage() -> void:
	var gd := _fixed_data()
	for c in gd.threats.get("act1", []):
		ok(covered.has("threat:" + c["id"]), "빠짐없이: 위협 %s" % c["id"])
	for c in gd.events.get("events", []):
		ok(covered.has("event:" + c["id"]), "빠짐없이: 이벤트 %s" % c["id"])
	for c in gd.items.get("items", []):
		ok(covered.has("item:" + c["id"]), "빠짐없이: 아이템 %s" % c["id"])
	for c in gd.characters.get("characters", []):
		ok(covered.has("trait:" + c["id"]), "빠짐없이: 특성 %s" % c["id"])
		ok(covered.has("ability:" + c["id"]), "빠짐없이: 능력 %s" % c["id"])
	for c in gd.missions.get("missions", []):
		if c["type"] == "coop":
			ok(covered.has("coop:" + c["id"]), "빠짐없이: 협동 미션 %s" % c["id"])


# ================================================================== 3단계: 개인 사연

func _run_3_tests() -> void:
	_test_saga_deal()
	_test_saga_cards()
	_test_saga_boundaries()
	_test_grant_scope()
	_test_launch_moment()
	_test_stage3_queries()
	_test_saga_coverage()


func _give(g: RulesV2, pid: int, ids: Array) -> void:
	var q: Dictionary = g.players[pid]
	q["sagas"] = ids.duplicate()
	q["saga_done"] = ""
	q["saga_kept"] = ""
	q["saga_track"] = {}


func _flush(g: RulesV2) -> void:
	## 직접 부른 내부 함수가 쌓은 보상을 처리한다 (apply 끝에서 자동으로 불리는 것과 같다)
	g._saga_idle_flush()


func _end_here(g: RulesV2, pid: int) -> void:
	## 이 자리에서 차례를 마친다
	g.players[pid]["done_today"] = false
	_turn(g, pid, 1)
	_end(g, pid)


func _walk(g: RulesV2, pid: int, from: Vector2i, to: Vector2i, die := 2, finish := true) -> void:
	## from에서 to로 한 칸 가고 (끝낼 수 있으면) 차례를 마친다
	if not g.board.has(from):
		_tile(g, from, "normal")
	if not g.board.has(to):
		_tile(g, to, "normal")
	g.players[pid]["pos"] = from
	g.players[pid]["done_today"] = false
	_turn(g, pid, die)
	_step(g, pid, to)
	if finish and g.phase == "turn" and g.current == pid:
		_end(g, pid)


func _answer_all(g: RulesV2, idx := 0) -> int:
	## 열린 선택을 모두 첫 번째(또는 idx번째) 선택지로 답한다. 답한 횟수를 돌려준다.
	var n := 0
	while g.phase == "choice" and n < 12:
		var opts: Array = g.pending["options"]
		_answer(g, opts[mini(idx, opts.size() - 1)]["value"])
		n += 1
	return n


func _base(g: RulesV2, id: String) -> Vector2i:
	return g.data.bases[g.data.base_index(id)]


func _launch_game(chars: Array, target: String, gd: GameDataV2 = null) -> RulesV2:
	## 결행 순간 시험용: 첩보가 target에만 있는 판 (다른 요원은 이미 이룰 수 있는 사연 하나씩)
	var g := _new(chars, gd)
	for id in GameDataV2.BASE_IDS:
		g.intel[id] = 0
	g.intel[target] = 3
	g.leader = 0
	return g


# ------------------------------------------------------------------ 나눠 주기

func _test_saga_deal() -> void:
	var g := RulesV2.new_game(CH, 77)
	var all_ok := true
	var total := 0
	for q in g.players:
		all_ok = all_ok and q["sagas"].size() == 2
		var branches := []
		for id in q["sagas"]:
			branches.append(g.data.saga(id)["branch"])
		all_ok = all_ok and (branches[0] in ["place", "own"]) and (branches[1] in ["risk", "bond", "strike"])
		total += q["sagas"].size()
	ok(all_ok, "사연 나눠 주기: 요원마다 가 더미 1장 + 나 더미 1장")
	var left := 0
	for k in g.saga_decks:
		left += g.saga_decks[k].size()
	ok(left + total == 20 and g.saga_discard.is_empty(), "사연 나눠 주기: 카드 20장이 모두 덱과 손에 있음")
	ok(g.saga_decks["a"].size() == 9 - 4 and g.saga_decks["b"].size() == 11 - 4, "사연 나눠 주기: 더미 가 5장, 나 7장이 남음")
	var dealt := 0
	for e in g.events:
		if e["kind"] == "saga_dealt":
			dealt += 1
			if not (e.get("secret", false) and e["sagas"].size() == 2):
				all_ok = false
	ok(dealt == 4 and all_ok, "사연 나눠 주기: saga_dealt 알림은 비밀(secret)이고 2장을 담음")
	# 인원과 상관없이 사연은 켜짐
	var g2 := RulesV2.new_game(["park", "han"], 5)
	ok(g2.players[0]["sagas"].size() == 2 and g2.players[1]["sagas"].size() == 2, "사연 나눠 주기: 2인 판에서도 사연을 받음")

	# redraw_for: 주모 막례는 자금책·스승의 부탁을 받지 않는다
	var bad := 0
	for s in 40:
		var gm := RulesV2.new_game(["makrye", "han", "oh", "park"], 300 + s)
		for id in gm.players[0]["sagas"]:
			if "makrye" in gm.data.saga(id).get("redraw_for", []):
				bad += 1
		var cnt := gm.saga_discard.size()
		for k in gm.saga_decks:
			cnt += gm.saga_decks[k].size()
		for q in gm.players:
			cnt += q["sagas"].size()
		if cnt != 20:
			bad += 100
	ok(bad == 0, "사연 다시 받기: 40판 동안 주모 막례는 redraw_for 카드를 받지 않고 카드도 늘 20장")
	var gr := _new(CH)
	gr.saga_decks = {"a": ["gambler", "financier"], "b": []}
	var got: String = gr._draw_saga("a", _with_char(gr, "makrye"))
	ok(got == "gambler" and gr.saga_decks["a"] == ["financier"], "사연 다시 받기: 뺀 카드는 더미 맨 아래로")
	var gr2 := _new(CH)
	gr2.saga_decks = {"a": ["financier", "masters_request"], "b": []}
	var got2: String = gr2._draw_saga("a", _with_char(gr2, "makrye"))
	ok(got2 != "" and gr2.saga_decks["a"].size() == 1, "사연 다시 받기: 모두 뺄 카드뿐이면 마지막은 그대로 받음")


func _with_char(g: RulesV2, char_id: String) -> Dictionary:
	return {"character": char_id}


# ------------------------------------------------------------------ 사연 20장 각각

func _test_saga_cards() -> void:
	var gd := _fixed_data()
	# 어머니의 소식: 종로경찰서 3칸 안, 쫓기지 않고 차례를 마침
	var g := _new(CH)
	_give(g, 0, ["mother"])
	_flat(g)
	var hq := _base(g, "police_hq")
	g.players[0]["pos"] = hq + Vector2i(-2, 1)
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "" and g.players[0]["sagas"] == ["mother"], "사연 어머니의 소식: 쫓기는 채로는 안 이뤄짐")
	g.police.clear()
	g.players[0]["pos"] = hq + Vector2i(-3, 1)
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "", "사연 어머니의 소식: 4칸 떨어진 곳에서는 안 이뤄짐")
	g.players[0]["pos"] = hq + Vector2i(-2, 1)
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "mother" and g.players[0]["dice_next"] == 1, "사연 어머니의 소식: 3칸 안에서 쫓기지 않고 마치면 이룸, 다음 날 내 주사위 +1")
	_cov("saga", "mother")

	# 기록자: 서로 다른 거점 세 곳의 옆 칸
	g = _new(CH)
	_give(g, 0, ["recorder"])
	_walk(g, 0, Vector2i(3, 1), Vector2i(2, 1))
	_walk(g, 0, Vector2i(1, 3), Vector2i(1, 2))   # 같은 거점(일본군영)의 다른 옆 칸
	ok(g.saga_progress(0)["recorder"] == {"have": 1, "need": 3}, "사연 기록자: 같은 거점의 옆 칸을 또 밟아도 1곳")
	_walk(g, 0, Vector2i(7, 1), Vector2i(8, 1))
	ok(g.players[0]["saga_done"] == "", "사연 기록자: 두 곳으로는 안 이뤄짐")
	_walk(g, 0, Vector2i(3, 9), Vector2i(2, 9), 2, false)
	ok(g.players[0]["saga_done"] == "recorder" and g.phase == "choice" and g.pending["kind"] == "intel_base", "사연 기록자: 세 곳을 밟으면 이루고 첩보를 쌓을 거점을 묻는다 (이동 중에도)")
	_answer(g, "gg")
	ok(g.intel["gg"] == 1 and g.phase == "turn", "사연 기록자: 보상 첩보 +1 뒤 이동으로 돌아옴")
	_cov("saga", "recorder")

	# 밀서 전달: 가장자리에 닿은 차례 수 (한 차례에 여러 칸이어도 1번)
	g = _new(CH)
	_give(g, 0, ["secret_letter"])
	g.exposure = 4
	g.players[0]["pos"] = Vector2i(1, 5)
	_tile(g, Vector2i(1, 5), "normal")
	_lay(g, [Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7)])
	g.players[0]["done_today"] = false
	_turn(g, 0, 3)
	_step(g, 0, Vector2i(0, 5))
	_step(g, 0, Vector2i(0, 6))
	_step(g, 0, Vector2i(0, 7))
	_end(g, 0)
	ok(g.saga_progress(0)["secret_letter"] == {"have": 1, "need": 2}, "사연 밀서 전달: 한 차례에 가장자리 여러 칸을 밟아도 1번")
	_walk(g, 0, Vector2i(0, 7), Vector2i(0, 8))
	ok(g.players[0]["saga_done"] == "secret_letter" and g.exposure == 2, "사연 밀서 전달: 두 번째 차례에 이룸, 노출 -2")
	_cov("saga", "secret_letter")

	# 피난민 안내: 출발점에서 차례를 두 번 마침
	g = _new(CH)
	_give(g, 0, ["refugee_guide"])
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "", "사연 피난민 안내: 한 번으로는 안 이뤄짐")
	var top: String = g.threat_deck[-1]
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "refugee_guide" and g.pending.get("kind", "") == "pick_bury", "사연 피난민 안내: 두 번째에 이루고 위협 덱 맨 위를 본다")
	_answer(g, true)
	ok(g.threat_deck[0] == top, "사연 피난민 안내: 맨 위 위협 카드를 맨 아래로 보냄")
	_cov("saga", "refugee_guide")

	# 보급선 잇기: 서로 다른 보급 타일 세 칸 (지나가기만 해도)
	g = _new(CH)
	_give(g, 0, ["supply_line"])
	_lay(g, [Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8)], "supply")
	_tile(g, Vector2i(4, 5), "normal")
	g.players[0]["pos"] = Vector2i(4, 5)
	g.players[0]["done_today"] = false
	_turn(g, 0, 4)
	_step(g, 0, Vector2i(4, 6))
	ok(g.saga_progress(0)["supply_line"]["have"] == 1 and g.phase == "turn", "사연 보급선 잇기: 지나가기만 해도 보급 타일을 밟은 것으로 셈")
	g.players[0]["pos"] = Vector2i(4, 5)
	g._saga_step_on(g.players[0], Vector2i(4, 6))
	ok(g.saga_progress(0)["supply_line"]["have"] == 1, "사연 보급선 잇기: 같은 칸을 또 밟아도 1칸")
	g._saga_step_on(g.players[0], Vector2i(4, 7))
	g._saga_step_on(g.players[0], Vector2i(4, 8))
	_flush(g)
	ok(g.players[0]["saga_done"] == "supply_line" and g.players[0]["bombs"] == 1, "사연 보급선 잇기: 세 칸을 밟으면 이루고 폭탄 1개")
	_cov("saga", "supply_line")

	# 자금책: 한도를 넘어도 되니, 버릴 카드를 묻기 전에 센다
	g = _new(CH)
	_give(g, 0, ["financier"])
	g.players[0]["items"] = ["train_ticket", "pocket_watch"]
	_fx(g, 0, [{"op": "draw_item", "count": 1}])
	ok(g.players[0]["saga_done"] == "financier" and g.phase == "choice" and g.pending["kind"] == "discard", "사연 자금책: 한도를 넘는 세 번째 아이템이 들어온 순간 이룸 (버릴 카드를 묻기 전)")
	var asked := _answer_all(g)
	ok(g.phase == "day" and g.players[0]["items"].size() == 2 and g.saga_rewards.is_empty(), "사연 자금책: 한도로 버린 뒤 보상(아이템 2장)도 받고 끝남 (%d번 답)" % asked)
	_cov("saga", "financier")
	# 건네받은 아이템도 센다
	g = _new(CH)
	_give(g, 1, ["financier"])
	g.players[1]["items"] = ["train_ticket", "pocket_watch"]
	g.players[0]["items"] = ["telegram"]
	g.players[0]["pos"] = Vector2i(5, 6)
	_turn(g, 0, 0)
	g.apply({"type": "give_item", "player": 0, "die": _spare(g, 2, 0), "index": 0, "to": 1})
	ok(g.players[1]["saga_done"] == "financier", "사연 자금책: 동료가 건넨 아이템도 센다")

	# 노름꾼: 굴린 눈 6을 가져간 날 세 번. 내려놓고 다시 가져가도 하루 1번
	g = _new(CH)
	_give(g, 0, ["gambler"])
	g._saga_note_multi(g.players[0], ["rolled_value"], {"values": [6, 6]})
	ok(g.saga_progress(0)["gambler"] == {"have": 1, "need": 3}, "사연 노름꾼: 한 아침에 6이 둘이어도 1번")
	g._saga_note_multi(g.players[0], ["rolled_value"], {"values": [2, 5]})
	ok(g.saga_progress(0)["gambler"]["have"] == 1, "사연 노름꾼: 6이 없는 아침은 세지 않음")
	var before: int = g.saga_progress(0)["gambler"]["have"]
	g._morning_dice()
	var rolled: Array = g.my_dice(0).map(func(i): return g.die_value(i))
	ok(g.saga_progress(0)["gambler"]["have"] == before + (1 if 6 in rolled else 0), "사연 노름꾼: 아침 굴림이 그대로 셈 (%s)" % str(rolled))
	g.op_dice = []
	g.phase = "day"
	g.players[0]["saga_track"]["gambler"] = {"n": 2}
	_spare(g, 2, 0)
	_spare(g, 5, 1)
	g._saga_note_multi(g.players[0], ["rolled_value"], {"values": [3, 6]})
	g._saga_idle_flush()
	ok(g.players[0]["saga_done"] == "gambler" and g.pending.get("kind", "") == "pick_value", "사연 노름꾼: 세 번째에 이루고 (내 주사위가 하나라) 원하는 눈을 묻는다")
	_answer(g, 4)
	ok(g.op_dice[0]["value"] == 4 and g.op_dice[1]["value"] == 5 and g.phase == "day", "사연 노름꾼: 내 주사위를 원하는 눈으로 바꿈")
	_cov("saga", "gambler")

	# 욕심 없는 사람: 동료에게 주사위를 세 번 건넴
	g = _new(CH)
	_give(g, 0, ["no_greed"])
	for k in 3:
		g.phase = "day"
		g.current = -1
		g.players[0]["done_today"] = false
		g.players[0]["gives_today"] = 0
		var gi := _spare(g, 2, 0)
		g.apply({"type": "begin_turn", "player": 0})
		g.apply({"type": "give_die", "player": 0, "die": gi, "target": 1})
		_end(g, 0)
		if k == 1:
			ok(g.saga_progress(0)["no_greed"]["have"] == 2 and g.players[0]["saga_done"] == "", "사연 욕심 없는 사람: 건넬 때마다 셈")
	ok(g.players[0]["saga_done"] == "no_greed" and g.players[2]["dice_next"] == 1 and g.players[0]["dice_next"] == 1,
		"사연 욕심 없는 사람: 세 번째에 이루고 내일 아침 모두 주사위 1개 더")
	_cov("saga", "no_greed")

	# 약속의 반지: 결행 순간 아이템 2장 이상
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["ring"])
	g.players[0]["items"] = ["telegram", "pocket_watch"]
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.players[0]["saga_done"] == "ring" and g.act == 2, "사연 약속의 반지: 결행 순간 아이템 2장이면 이룸")
	ok(g._grant_index(g.players[0], "check_bonus") == -1 and g._grant_index(g.players[0], "check_bonus", true) >= 0, "사연 약속의 반지: 보상은 결행 장면 판정 +2 (1막 판정에서는 안 쓰임)")
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["ring"])
	g.players[0]["items"] = ["telegram"]
	g._launch("forced")
	ok(g.players[0]["saga_done"] == "" and g.players[0]["saga_kept"] != "ring", "사연 약속의 반지: 아이템이 1장이면 못 이루고 결행 뒤에도 못 이루는 카드라 남지 않음")
	_cov("saga", "ring")

	# 원수: 쫓던 경찰을 투옥 말고 다른 이유로 세 번 그만 쫓게 함
	g = _new(CH)
	_give(g, 0, ["nemesis"])
	for reason in ["jail"]:
		g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
		g._police_off(0, reason)
	ok(g.saga_progress(0)["nemesis"]["have"] == 0, "사연 원수: 투옥으로 쫓기를 그만두는 것은 세지 않음")
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	g._police_off(0, "shake")
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	g._police_off(0, "removed")
	ok(g.saga_progress(0)["nemesis"]["have"] == 2, "사연 원수: 따돌림·제거는 셈")
	g.police[1] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	_tile(g, g.players[0]["pos"], "normal")
	g.board[g.players[0]["pos"]]["flags"].append("hideout")
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "nemesis" and g.police.is_empty(), "사연 원수: 은신처로 세 번째를 채우면 이루고 경찰 하나(여기선 남은 경찰 전부)를 제거")
	_cov("saga", "nemesis")
	# 미끼: 경찰이 동료에게서 떠나는 쪽이 센다
	g = _new(CH)
	_give(g, 1, ["nemesis"])
	_tile(g, Vector2i(5, 6), "normal")
	g.police[1] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	_turn(g, 0, 0)
	g.apply({"type": "decoy", "player": 0, "die": _spare(g, 2, 0), "from": 1})
	ok(g.saga_progress(1)["nemesis"]["have"] == 1 and g.saga_progress(0).is_empty(), "사연 원수: 미끼 작전으로 경찰이 떠난 동료가 센다")

	# 불나방: 검문소를 판정 성공으로 세 번 (통행권으로 지나간 것은 세지 않음)
	var gdc := _gd(func(d): d.rules["checks"]["evade"] = 0)
	g = _new(CH, gdc)
	_give(g, 0, ["moth"])
	g.item_deck.append("smoke_bomb")
	_tile(g, Vector2i(5, 6), "normal")
	_tile(g, Vector2i(5, 7), "check")
	g.players[0]["flags"]["checkpoint_pass"] = 1
	_walk(g, 0, Vector2i(5, 6), Vector2i(5, 7), 3)
	ok(g.saga_progress(0)["moth"]["have"] == 0, "사연 불나방: 통행권으로 그냥 지나간 검문소는 세지 않음")
	for k in 3:
		_walk(g, 0, Vector2i(5, 6), Vector2i(5, 7), 3)
	ok(g.players[0]["saga_done"] == "moth" and "smoke_bomb" in g.players[0]["items"], "사연 불나방: 판정에 성공해 세 번 지나가면 이루고 연막탄 1장")
	_cov("saga", "moth")

	# 살아서 돌아간다: 결행 순간까지 한 번도 안 잡힘
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["survivor"])
	_give(g, 1, ["survivor"])
	g.players[1]["jail_count"] = 1
	for i in range(2, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.players[0]["saga_done"] == "survivor" and g.players[1]["saga_done"] == "", "사연 살아서 돌아간다: 결행까지 안 잡혔으면 이루고, 한 번이라도 잡혔으면 못 이룸")
	ok(g._grant_index(g.players[0], "evade_auto") >= 0, "사연 살아서 돌아간다: 회피 자동 성공 한 번")
	_cov("saga", "survivor")

	# 도망자: 쫓기는 채로 (갇히지 않고) 차례를 연속 세 번
	g = _new(CH)
	_give(g, 0, ["fugitive"])
	g.players[0]["pos"] = Vector2i(2, 2)
	for k in 2:
		g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
		_end_here(g, 0)
	ok(g.saga_progress(0)["fugitive"]["have"] == 2, "사연 도망자: 쫓기는 채로 차례를 두 번 마침")
	g.police.clear()
	_end_here(g, 0)
	ok(g.saga_progress(0)["fugitive"]["have"] == 0, "사연 도망자: 쫓기지 않고 마치면 연속이 끊김")
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	_end_here(g, 0)
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	_end_here(g, 0)
	g._jail(g.players[0])
	ok(g.saga_progress(0)["fugitive"]["have"] == 0, "사연 도망자: 투옥되면 연속이 끊김")
	g.players[0]["jailed"] = false
	g.players[0]["pos"] = Vector2i(2, 2)
	for k in 3:
		g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
		_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "fugitive" and g.police[0]["pos"] == _base(g, "gg"), "사연 도망자: 세 번 연속이면 이루고 쫓던 경찰이 가장 먼 거점으로 돌아감")
	_cov("saga", "fugitive")

	# 옥중 동지: 갇힌 날이나 다음 날 안에 구출, 또는 탈옥 두 번
	g = _new(CH)
	_give(g, 0, ["cellmate"])
	var b0 := _base(g, "barracks")
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = b0
	g.players[1]["jailed_day"] = g.day - 2
	_walk(g, 0, b0 + Vector2i(1, 0), b0)
	ok(g.players[0]["saga_done"] == "" and not g.players[1]["jailed"], "사연 옥중 동지: 이틀 전에 갇힌 동료를 구출하면 안 이뤄짐")
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = b0
	g.players[1]["jailed_day"] = g.day - 1
	g.police.clear()
	_walk(g, 0, b0 + Vector2i(1, 0), b0)
	ok(g.players[0]["saga_done"] == "cellmate" and g._grant_index(g.players[0], "escape_instant") >= 0, "사연 옥중 동지: 갇힌 다음 날 안에 구출하면 이루고, 다음 투옥 때 바로 탈출 권리")
	var gde := _gd(func(d): d.rules["checks"]["escape"] = 0)
	g = _new(CH, gde)
	_give(g, 0, ["cellmate"])
	for k in 2:
		g.players[0]["jailed"] = true
		g.players[0]["pos"] = b0
		g.players[0]["done_today"] = false
		_turn(g, 0, 0)
		g.apply({"type": "escape", "player": 0, "die": _spare(g, 1, 0)})
	ok(g.players[0]["saga_done"] == "cellmate", "사연 옥중 동지: 탈옥에 두 번 성공해도 이룸")
	_cov("saga", "cellmate")

	# 의형제: 같은 동료와 같은 칸에서 세 번 (동료별로 따로 셈)
	g = _new(CH)
	_give(g, 0, ["sworn_brother"])
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[0]["pos"] = Vector2i(5, 6)
	_tile(g, Vector2i(5, 6), "normal")
	_end_here(g, 0)
	_end_here(g, 0)
	g.players[1]["pos"] = Vector2i(6, 5)
	g.players[2]["pos"] = Vector2i(5, 6)
	_end_here(g, 0)
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "" and g.saga_progress(0)["sworn_brother"] == {"have": 2, "need": 3}, "사연 의형제: 동료가 바뀌면 따로 셈 (2번 + 2번은 안 이뤄짐)")
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[2]["pos"] = Vector2i(5, 7)
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "sworn_brother" and g.players[0]["grants"].is_empty() and g.players[2]["grants"].is_empty(), "사연 의형제: 같은 동료와 세 번이면 이룸 (보상은 나나 다른 동료가 아니라 그 동료에게)")
	var sg: Array = g.players[1]["grants"]
	ok(sg.size() == 1 and sg[0]["kind"] == "check_bonus" and sg[0]["value"] == 2 and sg[0]["scope"] == "any", "사연 의형제: 그 동료에게 다음 판정 +2 권리")
	_cov("saga", "sworn_brother")
	# 갇힌 동료는 같은 칸에 있어도 세지 않음, 갇힌 차례도 세지 않음
	g = _new(CH)
	_give(g, 0, ["sworn_brother"])
	g.players[0]["pos"] = Vector2i(5, 6)
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[1]["jailed"] = true
	_end_here(g, 0)
	ok(g.saga_progress(0)["sworn_brother"]["have"] == 0, "사연: 갇힌 동료와는 같은 칸이어도 세지 않음")
	g = _new(CH)
	_give(g, 0, ["mother"])
	g.players[0]["pos"] = _base(g, "police_hq")
	g.players[0]["jailed"] = true
	_turn(g, 0, 1)
	g.apply({"type": "end_turn", "player": 0})
	ok(g.players[0]["saga_done"] == "", "사연: 갇힌 채 끝낸 차례는 '차례를 마침' 조건에 넣지 않음")
	g.players[0]["jailed"] = false
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "mother", "사연: 갇히지 않고 마친 차례는 셈 (같은 자리)")

	# 이름 없는 영웅: 협동 미션에 참여한 요원마다 1번
	g = _new(CH)
	_give(g, 0, ["nameless_hero"])
	_give(g, 1, ["nameless_hero"])
	var pr := _base(g, "prison")
	for k in 2:
		g.mission_row = ["m_prison_visit"]
		g.today["ends"] = {0: pr + Vector2i(1, 0), 1: pr + Vector2i(0, -1)}
		g._complete_missions(g.players[0], ["m_prison_visit"], {"then": "resume", "source": "mission"})
	_flush(g)
	ok(g.players[0]["saga_done"] == "nameless_hero" and g.players[1]["saga_done"] == "nameless_hero", "사연 이름 없는 영웅: 협동 미션을 채운 요원 모두에게 1번씩 셈")
	ok(g.phase == "choice" and g.pending["kind"] == "pick_player", "사연 이름 없는 영웅: 보상으로 도울 동료를 고른다")
	_answer(g, 2)
	_answer_all(g)
	ok(g._grant_index(g.players[2], "check_bonus", true) >= 0 and g._grant_index(g.players[2], "check_bonus") == -1, "사연 이름 없는 영웅: 동료의 결행 판정 +2 한 번 (결행 장면에서만)")
	_cov("saga", "nameless_hero")

	# 스승의 부탁: 동료에게 아이템을 세 번 (건네기 액션과 효과 모두)
	g = _new(CH)
	_give(g, 0, ["masters_request"])
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[2]["pos"] = Vector2i(9, 5)
	g.players[3]["pos"] = Vector2i(1, 5)
	_turn(g, 0, 0)
	for k in 2:
		g.players[0]["items"] = ["telegram"]
		g.players[1]["items"] = []
		g.players[0]["item_uses"] = 0
		g.apply({"type": "give_item", "player": 0, "die": _spare(g, 2, 0), "index": 0, "to": 1})
	ok(g.saga_progress(0)["masters_request"]["have"] == 2, "사연 스승의 부탁: give_item 액션을 셈")
	g.players[0]["items"] = ["telegram"]
	g.players[1]["items"] = []
	_fx(g, 0, [{"op": "give_item", "range": 1, "free": true}])
	_flush(g)
	ok(g.players[0]["saga_done"] == "masters_request", "사연 스승의 부탁: 효과 give_item도 셈")
	ok(g.players[0]["move_mod_next"] == 0 and g.players[1]["move_mod_next"] == 1 and g.players[2]["move_mod_next"] == 1 and g.players[3]["move_mod_next"] == 1, "사연 스승의 부탁: 동료 모두 다음 이동 +1 (본인 제외)")
	_cov("saga", "masters_request")

	# 4단계 훅: 결행 갈래
	g = _new(CH)
	_give(g, 0, ["sibling_revenge"])
	_give(g, 1, ["sibling_revenge"])
	g.saga_strike_event("final", 0, {"strike": "police_hq", "present": [0, 1]})
	ok(g.players[0]["saga_done"] == "", "사연 동생의 원수: 결행 목표가 군영이 아니면 이루지 못함")
	g.saga_strike_event("final", 1, {"strike": "barracks", "present": [0, 1]})
	ok(g.players[0]["saga_done"] == "" and g.players[1]["saga_done"] == "sibling_revenge", "사연 동생의 원수: 군영의 마지막 장면을 내가 돌파해야 이룸")
	ok(g._grant_index(g.players[1], "reroll") >= 0, "사연 동생의 원수: 판정 다시 굴리기 한 번")
	_cov("saga", "sibling_revenge")
	g = _new(CH)
	_give(g, 0, ["last_telegram"])
	_give(g, 1, ["last_telegram"])
	g.saga_strike_event("entry", 0, {"strike": "barracks", "present": [0]})
	ok(g.players[0]["saga_done"] == "", "사연 마지막 전보: 진입 장면 돌파로는 안 이뤄짐")
	g.saga_strike_event("final", 2, {"strike": "barracks", "present": [0]})
	ok(g.players[0]["saga_done"] == "last_telegram" and g.players[1]["saga_done"] == "", "사연 마지막 전보: 마지막 장면을 돌파할 때 결행 거점에 있던 요원만 이룸 (보상 없음)")
	_cov("saga", "last_telegram")
	g = _new(CH)
	_give(g, 0, ["first_step"])
	_give(g, 1, ["first_step"])
	g.saga_strike_event("final", 0, {"strike": "barracks", "present": [0]})
	g.saga_strike_event("middle", 0, {"strike": "barracks", "present": [0]})
	ok(g.players[0]["saga_done"] == "", "사연 첫걸음: 마지막·중간 장면으로는 안 이뤄짐")
	g.saga_strike_event("entry", 0, {"strike": "barracks", "present": [0]})
	ok(g.players[0]["saga_done"] == "first_step" and g.players[1]["saga_done"] == "" and g._grant_index(g.players[0], "check_bonus", true) >= 0, "사연 첫걸음: 진입 장면을 내가 돌파하면 이룸, 장면 판정 +2 한 번")
	_cov("saga", "first_step")


func _test_saga_coverage() -> void:
	var gd := _fixed_data()
	for c in gd.sagas.get("sagas", []):
		ok(covered.has("saga:" + c["id"]), "빠짐없이: 사연 %s" % c["id"])


# ------------------------------------------------------------------ 경계 사례

func _test_saga_boundaries() -> void:
	# 사연 두 장이 동시에 이뤄지면 손에 든 순서상 앞 카드만
	var g := _new(CH)
	_give(g, 0, ["refugee_guide", "fugitive"])
	g.players[0]["saga_track"]["refugee_guide"] = {"n": 1}
	g.players[0]["saga_track"]["fugitive"] = {"n": 2}
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "refugee_guide" and g.players[0]["sagas"] == ["refugee_guide"] and "fugitive" in g.saga_discard, "사연 두 장 동시 충족: 앞 카드만 이루고 나머지는 버림")
	g = _new(CH)
	_give(g, 0, ["fugitive", "refugee_guide"])
	g.players[0]["saga_track"]["refugee_guide"] = {"n": 1}
	g.players[0]["saga_track"]["fugitive"] = {"n": 2}
	g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
	_end_here(g, 0)
	ok(g.players[0]["saga_done"] == "fugitive" and "refugee_guide" in g.saga_discard, "사연 두 장 동시 충족: 순서가 바뀌면 앞 카드가 바뀜")
	# 이룬 사람은 더 세지 않는다
	var before: Dictionary = g.players[0]["saga_track"].duplicate(true)
	g._saga_note(g.players[0], "end_turn_at_start")
	ok(g.players[0]["saga_track"] == before and g.saga_rewards.size() <= 1, "사연: 이룬 요원은 더 세지 않음")

	# 이룸: 공개 알림
	g = _new(CH)
	_give(g, 0, ["mother", "secret_letter"])
	g._saga_complete(g.players[0], "secret_letter")
	var pub := false
	for e in g.events:
		if e["kind"] == "saga_done" and e["player"] == 0 and e["id"] == "secret_letter" and not e.has("secret"):
			pub = true
	ok(pub and g.players[0]["saga_done"] == "secret_letter" and "mother" in g.saga_discard, "사연 이룸: 공개 알림, 다른 카드는 버림")
	ok(g.history.any(func(h): return "사연" in h["text"] and "달성" in h["text"]), "사연 이룸: 연표에 남김")

	# 이어서 진행: 차례 끝에서 이뤄 선택이 끼어도 하루가 이어진다
	g = _new(CH)
	_give(g, 0, ["refugee_guide"])
	for i in range(1, 4):
		g.players[i]["done_today"] = true
	g.players[0]["saga_track"]["refugee_guide"] = {"n": 1}
	_end_here(g, 0)
	ok(g.phase == "choice" and g.pending["kind"] == "pick_bury" and g.players[0]["done_today"], "사연: 마지막 차례에서 이뤄 선택이 끼면 밤으로 넘어가기 전에 멈춤")
	var day_before := g.day
	_answer(g, false)
	ok(g.day == day_before + 1, "사연: 다음 날 아침이 됨 (day %d → %d)" % [day_before, g.day])

	# 아침(start_day)에서 이뤄도 이어서 진행
	g = _new(CH)
	_give(g, 0, ["gambler"])
	g.players[0]["saga_track"]["gambler"] = {"n": 2}
	g.phase = "plan"
	_spare(g, 6, 0)
	_spare(g, 1, 0)
	g._saga_note_multi(g.players[0], ["rolled_value"], {"values": [6, 1]})
	g.apply({"type": "start_day", "player": 0})
	ok(g.phase == "choice" and g.pending["kind"] == "pick_die", "사연: 아침 굴림으로 이뤄 선택이 끼면 멈춤")
	_answer(g, 0)
	_answer(g, 3)
	ok(g.phase == "day" and g.can_begin_turn(g.players[0]), "사연: 선택이 끝나면 낮으로 돌아와 차례를 시작할 수 있음")

	# saga_feasible: 데이터의 kind로만 판정
	g = _new(CH)
	g.launch_info = {"target": "police_hq"}
	var p0: Dictionary = g.players[0]
	ok(not g.saga_feasible(p0, "survivor") and not g.saga_feasible(p0, "ring"), "이룰 수 있는가: 결행 순간에만 세는 조건은 결행이 지나면 불가")
	ok(not g.saga_feasible(p0, "sibling_revenge") and g.saga_feasible(p0, "last_telegram") and g.saga_feasible(p0, "first_step"), "이룰 수 있는가: 군영이 아닌 결행의 「동생의 원수」는 불가, 나머지 결행 갈래는 가능")
	g.launch_info = {"target": "barracks"}
	ok(g.saga_feasible(p0, "sibling_revenge"), "이룰 수 있는가: 목표가 군영이면 「동생의 원수」 가능")
	g.tile_deck = []
	for c in g.board.keys():
		if g.board[c]["type"] == "supply":
			g.board.erase(c)
	ok(not g.saga_feasible(p0, "supply_line"), "이룰 수 있는가: 보급 타일이 남지 않으면 「보급선 잇기」 불가")
	_lay(g, [Vector2i(3, 3), Vector2i(3, 4)], "supply")
	ok(not g.saga_feasible(p0, "supply_line"), "이룰 수 있는가: 남은 보급 타일 2칸으로는 3칸을 못 채움")
	p0["saga_track"]["supply_line"] = {"cells": [Vector2i(7, 7)]}
	ok(g.saga_feasible(p0, "supply_line"), "이룰 수 있는가: 이미 밟은 1칸 + 남은 2칸이면 가능")
	ok(g.saga_feasible(p0, "mother") and g.saga_feasible(p0, "financier") and g.saga_feasible(p0, "gambler"), "이룰 수 있는가: 그 밖에는 가능")


func _test_grant_scope() -> void:
	var gdc := _gd(func(d): d.rules["checks"]["evade"] = 0)
	var g := _new(CH, gdc)
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 2, "scope": "strike"}]
	_tile(g, Vector2i(5, 7), "check")
	_walk(g, 0, Vector2i(5, 6), Vector2i(5, 7), 3)
	ok(_last_dice(g, "회피").get("bonus", -1) == 0 and g.players[0]["grants"].size() == 1, "권리 scope: strike 권리는 1막 판정에 쓰이지 않고 남음")
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 2, "scope": "any"}]
	_walk(g, 0, Vector2i(5, 6), Vector2i(5, 7), 3)
	ok(_last_dice(g, "회피").get("bonus", -1) == 2 and g.players[0]["grants"].is_empty(), "권리 scope: any 권리는 1막 판정에 쓰임")
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 2, "scope": "strike"}, {"kind": "check_bonus", "value": 1, "scope": "any"}]
	ok(g._grant_index(g.players[0], "check_bonus") == 1 and g._grant_index(g.players[0], "check_bonus", true) == 0, "권리 scope: 장면 판정은 strike·any 모두, 1막 판정은 any만 찾음")


# ------------------------------------------------------------------ 결행 순간

func _test_launch_moment() -> void:
	# 사연 남기기: 이룰 수 있는 카드가 둘이면 묻는다 (비밀)
	var g := _launch_game(CH, "police_hq")
	_give(g, 0, ["secret_letter", "mother"])
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.phase == "choice" and g.pending["kind"] == "saga_keep" and g.pending["player"] == 0 and g.pending.get("secret", false), "결행 순간: 이룰 수 있는 사연이 둘이면 saga_keep을 묻는다 (secret)")
	ok(g.launch_step == 2 and g.launch_i == 1, "결행 순간: 단계 launch_step 2, 다음 요원 launch_i 1")
	var opts: Array = g.pending["options"]
	ok(opts.size() == 2 and opts[0]["value"] == "secret_letter" and opts[1]["value"] == "mother", "결행 순간: 선택지는 이룰 수 있는 두 사연")
	# 저장·불러오기: 선택 중에도 이어진다
	var clone := RulesV2.new()
	clone.load_state(g.save_state(), g.data)
	_answer(g, "mother")
	ok(g.act == 2 and g.players[0]["saga_kept"] == "mother" and g.players[0]["sagas"] == ["mother"] and "secret_letter" in g.saga_discard, "결행 순간: 고른 사연을 남기고 나머지는 버림, 2막 시작")
	var kept_events := 0
	for e in g.events:
		if e["kind"] == "saga_kept":
			kept_events += 1
			if not e.get("secret", false):
				kept_events += 100
	ok(kept_events == 4 and g.scenes.size() >= 4, "결행 순간: saga_kept 알림(secret)과 장면 덱")
	clone.apply({"type": "choose", "player": 0, "value": "mother"})
	ok(clone.act == 2 and clone.players[0]["saga_kept"] == "mother" and str(clone.scenes) == str(g.scenes), "결행 순간: 선택 중 저장·불러오기한 판도 같은 장면 덱")

	# 이룰 수 있는 카드가 하나면 자동으로
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["sibling_revenge", "mother"])
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.act == 2 and g.players[0]["saga_kept"] == "mother" and "sibling_revenge" in g.saga_discard, "결행 순간: 군영이 아닌 결행의 「동생의 원수」는 후보에서 빠져 나머지를 자동으로 남김")
	g = _launch_game(CH, "barracks")
	_give(g, 0, ["sibling_revenge", "mother"])
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.phase == "choice" and g.pending["options"].size() == 2, "결행 순간: 목표가 군영이면 「동생의 원수」도 후보")
	_answer(g, "sibling_revenge")
	ok(g.act == 2 and g.players[0]["saga_kept"] == "sibling_revenge", "결행 순간: 군영 결행에서 「동생의 원수」를 남김")

	# 두 장 다 못 이루면 두 더미에서 이룰 수 있는 카드가 나올 때까지 뽑는다
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["sibling_revenge", "survivor"])
	g.players[0]["jail_count"] = 1
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g.saga_decks = {"a": ["mother", "ring"], "b": ["fugitive", "sibling_revenge"]}
	g.saga_discard = []
	g._launch("forced")
	# 더미 a의 맨 위 「약속의 반지」(결행 순간 조건)는 불가 → 버림, 더미 b의 맨 위 「동생의 원수」도 불가 → 버림, 다시 a의 「어머니의 소식」
	ok(g.act == 2 and g.players[0]["saga_kept"] == "mother" and g.players[0]["sagas"] == ["mother"], "결행 순간: 둘 다 못 이루면 새로 뽑아 이룰 수 있는 카드를 남김")
	ok("ring" in g.saga_discard and "sibling_revenge" in g.saga_discard and "survivor" in g.saga_discard and g.saga_decks["b"] == ["fugitive"], "결행 순간: 새로 뽑다 나온 불가 카드와 기존 카드는 버림, 더미 b는 그대로")

	# 요원 번호순으로 묻는다
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["mother", "secret_letter"])
	_give(g, 1, ["fugitive", "nemesis"])
	_give(g, 2, ["last_telegram"])
	_give(g, 3, ["moth", "gambler"])
	g._launch("forced")
	var order := [g.pending["player"]]
	_answer(g, "mother")
	order.append(g.pending["player"])
	_answer(g, "fugitive")
	order.append(g.pending["player"])
	_answer(g, "gambler")
	ok(order == [0, 1, 3] and g.act == 2, "결행 순간: 선택은 요원 번호순 (0, 1, 3번)")

	# 사연을 이룬 요원은 묻지 않음 / 보상 선택이 끼어도 이어짐
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["survivor"])
	_give(g, 1, ["ring"])
	g.players[1]["items"] = ["telegram", "pocket_watch"]
	for i in range(2, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.act == 2 and g.players[0]["saga_done"] == "survivor" and g.players[1]["saga_done"] == "ring" and g.players[0]["saga_kept"] == "survivor", "결행 순간: 이룬 사연은 곧 남긴 사연")

	# 투표 결행도 같은 순서를 거침 + 동수는 리더
	g = _new(CH)
	g.ready = g.data.rules["launch_min"]
	g.intel["gg"] = 2
	for i in 4:
		_give(g, i, ["last_telegram"])
	_begin_vote(g)
	_vote_all(g, [true, true, false, false])
	ok(g.act == 2 and g.players[0]["saga_kept"] == "last_telegram", "결행 순간: 투표 결행에서도 사연을 남김")


# ------------------------------------------------------------------ 조회

func _test_stage3_queries() -> void:
	var g := _new(CH)
	_give(g, 0, ["mother", "secret_letter"])
	ok(g.saga_cards(0) == ["mother", "secret_letter"], "조회: saga_cards")
	ok(g.public_saga(0) == "" and g.saga_result(0) == {"saga": "mother", "done": false}, "조회: 이루기 전에는 public_saga가 비고 saga_result는 들고 있던 첫 장")
	ok(g.epilogue_key(0, true) == "win_fail" and g.epilogue_key(0, false) == "lose_fail", "조회: 못 이룬 후일담 키")
	g._saga_complete(g.players[0], "secret_letter")
	ok(g.public_saga(0) == "secret_letter" and g.saga_result(0) == {"saga": "secret_letter", "done": true}, "조회: 이룬 사연은 공개")
	ok(g.epilogue_key(0, true) == "win_done" and g.epilogue_key(0, false) == "lose_done", "조회: 이룬 후일담 키")
	g = _new(CH)
	_give(g, 0, ["moth", "no_greed"])
	g.players[0]["saga_track"]["moth"] = {"n": 2}
	g.players[0]["items"] = ["telegram"]
	_give(g, 1, ["financier", "sibling_revenge"])
	g.players[1]["items"] = ["telegram", "pocket_watch", "train_ticket"]
	var pr: Dictionary = g.saga_progress(0)
	ok(pr["moth"] == {"have": 2, "need": 3} and pr["no_greed"] == {"have": 0, "need": 3}, "조회: saga_progress {have, need}")
	var pr1: Dictionary = g.saga_progress(1)
	ok(pr1["financier"] == {"have": 3, "need": 3} and pr1["sibling_revenge"] == {"have": 0, "need": 1}, "조회: 아이템 수는 현재 값, 결행 갈래는 0/1")
	# 저장·불러오기: 새 상태가 모두 들어 있음
	g._jail(g.players[2])
	_give(g, 3, ["mother"])
	g._saga_complete(g.players[3], "mother")
	var st: Dictionary = g.save_state()
	var g2 := RulesV2.new()
	g2.load_state(st, g.data)
	ok(str(g2.save_state()) == str(st), "저장: 사연 상태를 저장하고 불러오면 같음")
	for k in ["saga_decks", "saga_discard", "saga_rewards", "launch_step", "launch_i"]:
		ok(st.has(k), "저장: SAVE_FIELDS에 %s" % k)
	for k in ["interro_deck", "interro_discard", "traitor_id"]:
		ok(not st.has(k), "저장: 지운 필드 %s는 없음" % k)


# ------------------------------------------------------------------ 4단계: 장면 · 2막 · 엔딩

func _scene_fixture(target: String, card: Dictionary) -> RulesV2:
	var g := _new(CH)
	g.act = 2
	g.launch_info = {"target": target, "reason": "test", "day": g.day}
	g.scenes = ["앞 장면", card["id"]]
	g.scene_index = 1
	g.scene_state = {}
	g.intel_tokens = 3
	g.phase = "day"
	var where := str(card.get("where", "inside"))
	var at: Vector2i = g._base_cell(target)
	if where == "adjacent":
		at += Vector2i(1, 0)
	for p in g.players:
		p["pos"] = at
		p["sagas"] = ["last_telegram"]
	return g


func _scene_first_leaf(cond: Dictionary) -> Dictionary:
	if str(cond.get("kind", "")) in ["any_of", "all_of"]:
		return _scene_first_leaf(cond.get("options", [])[0])
	return cond


func _run_4_tests() -> void:
	_test_scene_all_cards()
	_test_scene_boundaries()
	_test_act2_launch()
	_test_act2_endings()
	_test_act2_effects()
	_test_act2_edges()
	_test_act2_sagas_and_failures()


func _test_scene_all_cards() -> void:
	var count := 0
	for target in GameDataV2.BASE_IDS:
		var strike: Dictionary = _fixed_data().strike(target)
		var cards: Array = [strike["entry"]] + strike["middle"] + [strike["final"]]
		for card in cards:
			_test_one_scene(target, card)
			count += 1
	for card in _fixed_data().scenes["reinforce"]:
		_test_one_scene(GameDataV2.BASE_IDS[0], card)
		count += 1
	ok(count == 28, "빠짐없이: 결행 장면 24장과 경비 강화 4장")


func _test_one_scene(target: String, card: Dictionary) -> void:
	var g := _scene_fixture(target, card)
	var cond := _scene_first_leaf(card["condition"])
	var kind := str(cond["kind"])
	var at: Vector2i = g._base_cell(target)
	var where := str(cond.get("where", card.get("where", "inside")))
	if where == "adjacent":
		at += Vector2i(1, 0)
	for p in g.players:
		p["pos"] = at
	match kind:
		"check", "check_pair":
			for i in (int(cond.get("count", 1)) if kind == "check_pair" else 1):
				g.players[i]["grants"] = [{"kind": "check_bonus", "value": 99}]
				g.phase = "day"
				g.current = -1
				_turn(g, i, 0)
				_sc(g, i)
		"dice":
			_turn(g, 0, 0)
			for i in 3:
				g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": _spare(g, 6, 0)})
				if g.phase == "over":
					break
		"pay_item":
			g.players[0]["items"] = [g.data.items["items"][0]["id"]]
			_turn(g, 0, 0)
			g.apply({"type": "scene_pay", "player": 0, "what": "item", "index": 0, "with": _spare(g, 2, 0)})
		"pay_bomb":
			g.players[0]["bombs"] = int(cond.get("count", 1))
			_turn(g, 0, 0)
			for i in int(cond.get("count", 1)):
				g.apply({"type": "scene_pay", "player": 0, "what": "bomb", "with": _spare(g, 2, 0)})
				if g.phase == "over":
					break
		"people":
			for i in int(cond.get("count", 1)):
				g.phase = "day"
				g.current = -1
				_turn(g, i, 0)
				_end(g, i)
		"hold":
			for i in int(cond.get("days", 1)):
				g._scene_night()
		"jailed_here":
			g.players[0]["pos"] = g._base_cell(target)
			g.players[0]["jailed"] = true
			g._scene_auto_break()
	ok(g.ending.get("id", "") == "victory", "빠짐없이: 장면 %s 돌파 (%s)" % [card["id"], kind])
	if not card.get("on_fail", []).is_empty() and kind in ["check", "check_pair"]:
		var bad := _scene_fixture(target, card)
		bad.players[0]["pos"] = at
		bad.today["scene_mod"] = 100
		_turn(bad, 0, 0)
		_sc(bad, 0)
		ok(bad.ending.is_empty(), "실패 효과: 장면 %s는 실패해도 돌파하지 않음" % card["id"])


func _test_scene_boundaries() -> void:
	var data := _fixed_data()
	var card: Dictionary = data.strike("prison")["entry"]
	var g := _scene_fixture("prison", card)
	_spare(g, 3, 0)
	_spare(g, 4, 1)
	_spare(g, 4, 0)
	_turn(g, 0, 0)
	ok(not g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": 1}) and not g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": 3}),
		"주사위: 남의 주사위나 이미 쓴 주사위는 바칠 수 없음")
	ok(g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": 0}) and g.ending.is_empty(), "주사위: 한 번 바쳐도 합이 모자라면 남음")
	g._scene_night()
	ok(g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": 2}) and g.ending.get("won", false), "주사위: 여러 날 누적되어 돌파")
	g = _scene_fixture("prison", card)
	_spare(g, 5, 0)
	_turn(g, 0, 0)
	ok(g.apply({"type": "use_intel", "player": 0, "mode": "dice"}) and g.intel_tokens == 2, "첩보: 토큰 하나로 주사위 필요 합을 2 줄임")
	ok(g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": 0}) and g.ending.get("won", false), "첩보: 줄어든 합에 닿으면 돌파")
	card = data.strike("police_hq")["final"]
	g = _scene_fixture("police_hq", card)
	g.data = _gd(func(d): d.scenes["strikes"]["police_hq"]["final"]["condition"]["count"] = 2)
	g.players[0]["bombs"] = 1
	g.players[1]["bombs"] = 1
	_turn(g, 0, 0)
	g.apply({"type": "scene_pay", "player": 0, "what": "bomb", "with": _spare(g, 2, 0)})
	g.phase = "day"
	g.current = -1
	_turn(g, 1, 0)
	ok(g.apply({"type": "scene_pay", "player": 1, "what": "bomb", "with": _spare(g, 2, 1)}) and g.ending.get("won", false), "폭탄: split이면 두 요원이 나눠 바침")
	g = _scene_fixture("police_hq", card.duplicate(true))
	g.data = _gd()
	# 조건의 split을 끄고 한꺼번에 필요한 수를 확인한다.
	g.data.scenes["strikes"]["police_hq"]["final"]["condition"]["count"] = 2
	g.data.scenes["strikes"]["police_hq"]["final"]["condition"]["split"] = false
	g.players[0]["bombs"] = 1
	_turn(g, 0, 0)
	ok(not g.apply({"type": "scene_pay", "player": 0, "what": "bomb", "with": _spare(g, 2, 0)}), "폭탄: split이 없고 수가 모자라면 액션 불가")
	card = data.strike("prison")["middle"][0]
	g = _scene_fixture("prison", card)
	for i in 2:
		g.players[i]["pos"] = g._base_cell("prison")
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.scene_need().get("check_pair", -1) == 1 and not _sc(g, 0), "짝 판정: 같은 요원은 한 차례에 다시 시도할 수 없음")
	g._scene_night()
	ok(g.scene_need().get("check_pair", -1) == 2, "짝 판정: 다음 날에는 기록 초기화")
	g = _scene_fixture("prison", data.strike("prison")["final"])
	g.players[0]["pos"] = g._base_cell("prison")
	g.players[0]["jailed"] = true
	g.players[0]["grants"] = [{"kind": "check_bonus", "scope": "strike", "value": 99}]
	_turn(g, 0, 0)
	ok(_sc(g, 0) and g.ending.get("won", false), "감옥: 결행 거점에 갇혀도 판정 참여·결행 권리 사용")
	ok(not g.apply({"type": "escape", "player": 0}), "감옥: 장면 판정 뒤 탈옥 시도 불가")
	g = _scene_fixture("gg", data.strike("gg")["final"])
	for i in 2:
		g.players[i]["pos"] = g._base_cell("gg")
	g._scene_night()
	ok(g.ending.get("won", false), "버티기: 두 명이 필요한 깃발 돌파")
	g = _scene_fixture("gg", data.strike("gg")["entry"])
	g.players[0]["pos"] = g._base_cell("gg")
	g.players[0]["items"] = [data.items["items"][0]["id"]]
	_turn(g, 0, 0)
	ok(g.apply({"type": "scene_pay", "player": 0, "what": "item", "index": 0, "with": _spare(g, 2, 0)}) and g.ending.get("won", false), "양자택일: 아이템 쪽으로 돌파")


func _test_act2_launch() -> void:
	var g := _new(CH)
	g.intel["police_hq"] = 2
	g.bomb_supply = 0
	g.exposure = 0
	g.launch_info = {"target": "police_hq", "reason": "test", "day": g.day}
	g._begin_act2()
	ok(g.act == 2 and g.scenes.size() == 4 and g.intel_tokens == 2, "결행: 경계 1단계 장면 4장과 첩보 2개")
	ok(g.bomb_supply == int(g.data.rules["bomb_supply"]) and g.mission_row.is_empty() and g.mission_deck.is_empty(), "결행: 경찰서 보급과 미션 줄 정리")
	ok(g.scenes[0] == g.data.strike("police_hq")["entry"]["id"] and g.scenes[-1] == g.data.strike("police_hq")["final"]["id"], "결행: 진입과 마지막 고정")
	for level in [2, 3]:
		g = _new(CH)
		g.exposure = int(g.data.rules["exposure"]["thresholds"][level - 2])
		g.launch_info = {"target": "prison", "reason": "test", "day": g.day}
		g._begin_act2()
		ok(g.scenes.size() == 4 + level - 1, "결행: 경계 %d단계 경비 강화 %d장" % [level, level - 1])
	var top := 0
	for i in g.threat_deck.size():
		if g.data.threat(g.threat_deck[i]).get("deck_place", "") == "top_half":
			top += 1 if i >= g.threat_deck.size() / 2 else -100
	ok(top == 2, "결행: 2막 위협의 top_half 카드가 위쪽 절반")
	var st := g.save_state()
	var clone := RulesV2.new()
	clone.load_state(st, g.data)
	ok(str(clone.save_state()) == str(st), "2막: 장면과 첩보 상태 저장·불러오기")


func _test_act2_endings() -> void:
	for index in [0, 1, 3]:
		var g := _new(CH)
		g.act = 2
		g.launch_info = {"target": "prison", "day": 1}
		g.scenes = ["prison_wall", "prison_keys", "prison_search", "prison_door"]
		g.scene_index = index
		g._end_game(false)
		var want := "history" if index == 0 else "fail_final" if index == 3 else "fail_middle"
		ok(g.ending["id"] == want and g.ending["scene"] == g.scenes[index] and g.ending["epilogues"].size() == 4,
			"엔딩: %s와 요원 4명 후일담" % want)
		ok(g._scene_card(g.scenes[index])["stop_text"] in g.ending["text"], "엔딩: 멈춘 장면 문장 포함")
	var win := _scene_fixture("prison", _fixed_data().strike("prison")["final"])
	win._end_game(true)
	ok(win.ending["id"] == "victory" and win.ending["won"] and win.ending["epilogues"].size() == 4, "엔딩: 승리와 후일담")
	var lose := _scene_fixture("prison", _fixed_data().strike("prison")["final"])
	lose._end_game(false)
	var keys: Array = lose.ending["epilogues"].map(func(e): return e["key"])
	ok(not lose.ending.has("traitor") and not lose.ending.has("traitor_won") and not keys.has("traitor") and not lose.ending["epilogues"][0].has("traitor"),
		"엔딩: 변절 엔딩과 후일담 키가 없음")


func _test_act2_effects() -> void:
	var g := _scene_fixture("prison", _fixed_data().strike("prison")["final"])
	g.players[0]["pos"] = g._base_cell("prison")
	g.today["scene_mod"] = 0
	g._run_effects(g.players[0], [{"op": "scene_check_mod_today", "value": 1}], {"then": "resume"})
	ok(g.today["scene_mod"] == 1, "위협: 비상 소집 판정 목표 +1")
	g._run_effects(g.players[0], [{"op": "threat_flip"}], {"then": "resume"})
	ok(g.threat_discard.size() >= 1, "위협: 추가 카드 즉시 공개")
	g = _scene_fixture("prison", _fixed_data().strike("prison")["final"])
	g.players[0]["pos"] = g._base_cell("prison")
	g.data = _gd(func(d): d.rules["checks"]["evade"] = 99)
	g._run_effects(g.players[0], [{"op": "check_or_jail", "check": "evade"}], {"then": "resume"})
	ok(g.players[0]["jailed"], "위협: check_or_jail 실패 시 투옥")


func _test_act2_edges() -> void:
	var data := _fixed_data()
	var g := _scene_fixture("prison", data.strike("prison")["middle"][0])
	g.players[0]["pos"] = g._base_cell("prison")
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}, {"kind": "check_bonus", "value": 99}]
	_turn(g, 0, 0)
	_sc(g, 0)
	g.players[0]["flags"].erase("scene_tried")
	_sc(g, 0)
	ok(g.scene_need().get("check_pair", -1) == 1, "짝 판정: 같은 요원이 두 번 성공해도 한 명만 기록")
	g = _scene_fixture("police_hq", data.strike("police_hq")["entry"])
	for i in 2:
		g.players[i]["pos"] = g._base_cell("police_hq") + Vector2i(1, 0)
	_turn(g, 0, 0)
	_end(g, 0)
	ok(g.scene_need().get("people", -1) == 1, "인원: 첫 요원만 차례를 마치면 한 명 부족")
	g._scene_night()
	ok(g.scene_need().get("people", -1) == 2, "인원: 밤이 지나면 오늘 기록 초기화")
	g = _scene_fixture("police_hq", data.strike("police_hq")["middle"][3])
	g.players[0]["pos"] = g._base_cell("police_hq")
	g.players[0]["jailed"] = true
	g._scene_auto_break()
	ok(g.ending.get("won", false), "감옥: jailed_here 장면을 열자마자 돌파")
	g = _scene_fixture("prison", data.strike("prison")["entry"])
	g.data = _gd()
	g.data.scenes["strikes"]["prison"]["entry"]["condition"] = {"kind": "all_of", "options": [
		{"kind": "dice", "sum": 3}, {"kind": "pay_item", "count": 1}]}
	_spare(g, 3, 0)
	g.players[0]["items"] = [g.data.items["items"][0]["id"]]
	_turn(g, 0, 0)
	g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": 0})
	ok(g.ending.is_empty(), "모두 만족: 주사위만 채우면 장면이 남음")
	g.apply({"type": "scene_pay", "player": 0, "what": "item", "index": 0, "with": _spare(g, 2, 0)})
	ok(g.ending.get("won", false), "모두 만족: 주사위와 아이템을 채우면 돌파")
	g = _scene_fixture("prison", data.strike("prison")["final"])
	g.players[0]["pos"] = g._base_cell("prison")
	g.players[0]["sagas"] = ["last_telegram"]
	g.players[0]["saga_done"] = "last_telegram"
	g._end_game(false)
	ok(g.ending["epilogues"][0]["key"] == "lose_fail" and data.saga("last_telegram")["epilogue"]["lose_fail"] in g.ending["epilogues"][0]["text"],
		"후일담: 없는 lose_done은 lose_fail 문장으로 대체")
	g = _scene_fixture("prison", data.strike("prison")["final"])
	g.players[0]["pos"] = g._base_cell("prison")
	g.data = _gd()
	g.data.rules["checks"]["evade"] = 99
	g._run_effects(g.players[0], [{"op": "search", "range": 0}], {"then": "resume"})
	ok(g.search_queue.is_empty() and g.effect_wait.is_empty() and not g.police.is_empty(), "위협: 수색 판정 대기열을 요원 번호순으로 끝까지 처리")
	g = _scene_fixture("prison", data.strike("prison")["entry"])
	g.phase = "plan"
	ok(not g.apply({"type": "scene_check", "player": 0, "bogus": true}) and not g.apply({"type": "move_die", "player": 0, "die": 999}),
		"액션: 법적 목록에 없는 형태는 거부")


func _test_act2_sagas_and_failures() -> void:
	var data := _fixed_data()
	var g := _scene_fixture("prison", data.strike("prison")["entry"])
	g.scenes = [data.strike("prison")["entry"]["id"], data.strike("prison")["final"]["id"]]
	g.scene_index = 0
	g.players[0]["sagas"] = ["first_step"]
	_turn(g, 0, 0)
	g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": _spare(g, 6, 0)})
	g.apply({"type": "scene_pay", "player": 0, "what": "die", "die": _spare(g, 1, 0)})
	ok(g.scene_index == 1 and g.players[0]["saga_done"] == "first_step", "사연 훅: 실제 진입 장면 돌파로 첫걸음 이룸")
	g = _scene_fixture("barracks", data.strike("barracks")["final"])
	g.players[0]["pos"] = g._base_cell("barracks")
	g.players[0]["sagas"] = ["sibling_revenge"]
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.ending.get("won", false) and g.players[0]["saga_done"] == "sibling_revenge", "사연 훅: 실제 군영 마지막 장면 돌파로 동생의 원수 이룸")
	g = _scene_fixture("prison", data.strike("prison")["final"])
	g.players[0]["pos"] = g._base_cell("prison")
	g.players[1]["pos"] = g._base_cell("prison")
	g.players[1]["sagas"] = ["last_telegram"]
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.ending.get("won", false) and g.players[1]["saga_done"] == "last_telegram", "사연 훅: 마지막 장면 현장에 있던 동료가 마지막 전보를 이룸")
	g = _scene_fixture("prison", data.strike("prison")["middle"][0])
	g.players[0]["pos"] = g._base_cell("prison")
	g.today["scene_mod"] = 100
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.police.has(0), "실패 효과: 간수 제압 실패 시 그 요원에게 경찰")
	g = _scene_fixture("prison", data.strike("prison")["middle"][3])
	g.players[0]["pos"] = g._base_cell("prison")
	g.today["scene_mod"] = 100
	g.threat_deck = g.data.threat_deck(2)
	var before := g.threat_discard.size()
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.threat_discard.size() == before + 1, "실패 효과: 비상종 실패 시 위협 한 장 추가 공개")
	g = _scene_fixture("prison", data.strike("prison")["middle"][3])
	g.data = _gd()
	g.data.rules["checks"]["evade"] = 99
	g.players[0]["pos"] = g._base_cell("prison")
	g.today["scene_mod"] = 100
	g.threat_deck = ["sweep"]
	g.threat_discard = []
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.threat_discard == ["sweep"] and g.effect_wait.is_empty() and g.search_queue.is_empty(),
		"실패 효과: 비상종이 수색을 뒤집어도 중첩 효과 대기열을 마침")
	g = _scene_fixture("barracks", data.strike("barracks")["final"])
	g.players[0]["pos"] = g._base_cell("barracks")
	g.today["scene_mod"] = 100
	g.data = _gd()
	g.data.rules["checks"]["evade"] = 99
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.players[0]["jailed"], "실패 효과: 사령관실 실패 뒤 회피에도 실패하면 투옥")


# ================================================================== A단계: 변절을 빼고 바뀐 규칙

func _run_a_tests() -> void:
	_test_jail_confiscate()
	_test_informer_bounty()
	_test_removed_things()


func _test_jail_confiscate() -> void:
	# 투옥되면 노출 +1에 더해 들고 있던 아이템 1장을 무작위로 압수 (폭탄은 그대로)
	var g := _new(CH)
	g.players[0]["items"] = ["train_ticket", "telescope"]
	g.players[0]["bombs"] = 1
	g._jail(g.players[0])
	var left: Array = g.players[0]["items"]
	var gone := "telescope" if left == ["train_ticket"] else "train_ticket"
	ok(g.players[0]["jailed"] and left.size() == 1 and g.item_discard == [gone] and g.exposure == int(g.data.rules["exposure"]["on_jail"]),
		"투옥 압수: 노출이 오르고 아이템 1장이 버림 더미로 감")
	ok(g.players[0]["bombs"] == 1, "투옥 압수: 폭탄은 압수하지 않음")
	var ev := {}
	for e in g.events:
		if e["kind"] == "confiscate":
			ev = e
	ok(ev.get("player", -1) == 0 and ev.get("items", []) == [gone] and _log_has(g, "압수당했습니다"), "투옥 압수: 알림 confiscate와 로그")
	ok(g.players[0]["jailed_day"] == g.day, "투옥 압수: 갇힌 날은 그대로 적음")
	g = _new(CH)
	g.players[0]["bombs"] = 1
	g._jail(g.players[0])
	ok(g.players[0]["jailed"] and g.players[0]["items"].is_empty() and g.item_discard.is_empty() and g.players[0]["bombs"] == 1 and g.exposure == 1,
		"투옥 압수: 아이템이 없으면 노출만 오르고 아무것도 잃지 않음")
	ok(not g.events.any(func(e): return e["kind"] == "confiscate"), "투옥 압수: 아이템이 없으면 알림도 없음")
	g = _new(CH)
	g.players[0]["items"] = ["telescope"]
	g._jail(g.players[0])
	ok(g.players[0]["items"].is_empty() and g.item_discard == ["telescope"], "투옥 압수: 한 장뿐이면 그 한 장")
	# 무작위: 시드에 따라 두 장 모두 압수될 수 있고, 같은 시드는 같은 결과
	var seen := {}
	for sd in 30:
		var gs := _new(CH, null, 200 + sd)
		gs.players[0]["items"] = ["train_ticket", "telescope"]
		gs._jail(gs.players[0])
		seen[gs.item_discard[0]] = true
	ok(seen.size() == 2, "투옥 압수: 무작위 (시드에 따라 두 장 모두 압수됨)")
	var a1 := _new(CH, null, 7)
	a1.players[0]["items"] = ["train_ticket", "telescope"]
	a1._jail(a1.players[0])
	var a2 := _new(CH, null, 7)
	a2.players[0]["items"] = ["train_ticket", "telescope"]
	a2._jail(a2.players[0])
	ok(a1.item_discard == a2.item_discard, "투옥 압수: 같은 시드면 같은 카드")
	# 장수는 데이터 수치
	var gd2 := _gd(func(d): d.rules["jail"]["confiscate_items"] = 2)
	g = _new(CH, gd2)
	g.players[0]["items"] = ["train_ticket", "telescope"]
	g._jail(g.players[0])
	ok(g.players[0]["items"].is_empty() and g.item_discard.size() == 2, "투옥 압수: rules.jail.confiscate_items를 2로 바꾸면 2장")
	# 체포로 투옥돼도, 판정에 실패해 투옥돼도 같다
	g = _new(CH)
	_lay(g, [Vector2i(5, 6)])
	g.players[0]["items"] = ["telescope"]
	g.police[0] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	g._police_approach(g.players[0], 2)
	ok(g.players[0]["jailed"] and g.players[0]["items"].is_empty(), "투옥 압수: 경찰에게 체포되어도 압수")
	var gdf := _gd(func(d): d.rules["checks"]["evade"] = 99)
	g = _new(CH, gdf)
	g.players[0]["items"] = ["telescope"]
	g.players[0]["bombs"] = 1
	_turn(g, 0, 0)
	g._start_check(g.players[0], "evade", "mission_evade")
	ok(g.players[0]["jailed"] and g.players[0]["items"].is_empty() and g.players[0]["bombs"] == 1, "투옥 압수: 미션 판정에 실패해 투옥되어도 압수, 폭탄은 그대로")
	# 투옥된 뒤에 동료에게 받은 아이템은 압수당하지 않는다 (압수는 투옥되는 순간뿐)
	g = _new(CH)
	g._jail(g.players[0])
	g.players[0]["items"] = ["telescope"]
	ok(g.players[0]["items"] == ["telescope"] and g.item_discard.is_empty(), "투옥 압수: 투옥된 뒤에 받은 아이템은 그대로")


func _test_informer_bounty() -> void:
	# 2막 위협 「밀고 포상금」: 노출 +1, 결행 거점에서 경찰이 출동해 가장 가까운 요원을 쫓음
	var g := _new(CH)
	g.launch_info = {"target": "prison", "day": 1}
	var base := _base(g, "prison")
	g.players[2]["pos"] = base + Vector2i(1, 0)
	_threat(g, "informer_bounty")
	ok(g.exposure == 1 and g.police.size() == 1 and g.police.has(2) and g.police[2]["pos"] == base, "위협 밀고 포상금: 노출 +1, 결행 거점에서 가장 가까운 요원에게 경찰이 출동")
	ok(g.alert_level() == 1, "위협 밀고 포상금: 노출 +1만으로는 경계 단계가 오르지 않음 (0 → 1)")
	_threat(g, "informer_bounty")
	ok(g.exposure == 2 and g.police.size() == 2 and g.police.has(0), "위협 밀고 포상금: 이미 쫓기는 요원은 건너뛰고 다음으로 가까운 요원")
	g = _new(CH)
	g.launch_info = {"target": "prison", "day": 1}
	g.players[2]["pos"] = _base(g, "prison")
	g.players[2]["jailed"] = true
	_threat(g, "informer_bounty")
	ok(g.police.size() == 1 and not g.police.has(2), "위협 밀고 포상금: 갇힌 요원은 쫓지 않음")
	g = _new(CH)
	g.launch_info = {"target": "prison", "day": 1}
	g.exposure = 2
	_threat(g, "informer_bounty")
	ok(g.exposure == 3 and g.alert_level() == 2 and g.police.size() == 2, "위협 밀고 포상금: 노출이 문턱에 닿으면 경계 출동이 하나 더")
	var gd := GameDataV2.load_default()
	ok(gd.threat("informer_bounty").get("deck_place", "") == "top_half" and gd.threat_deck(2).count("informer_bounty") == 2 and gd.threat_deck(1).count("house_search") == 3,
		"위협: 가택 수색은 1막 3장, 밀고 포상금은 2막 2장 (위쪽 절반)")


func _test_removed_things() -> void:
	# 변절·심문·설득이 데이터와 엔진에서 모두 사라졌는가
	var real := GameDataV2.load_default()
	ok(not FileAccess.file_exists("res://data/v2/interrogation.json") and not real.rules.has("traitor") and not real.rules.has("persuade")
		and not real.endings.has("traitor_won"), "삭제: interrogation.json · rules.traitor · rules.persuade · endings.traitor_won")
	var lure := 0
	var tr_ep := 0
	for c in real.sagas["sagas"]:
		lure += 1 if c.has("lure") else 0
		tr_ep += 1 if c["epilogue"].has("traitor") else 0
	ok(lure == 0 and tr_ep == 0, "삭제: 사연의 lure와 후일담 traitor")
	ok(not "persuade" in GameDataV2.KNOWN_OPS and not "interrogate" in GameDataV2.KNOWN_OPS and not "interrogate_discard" in GameDataV2.KNOWN_OPS
		and not "has_interrogation" in GameDataV2.KNOWN_IF_CONDS and not "traitor" in GameDataV2.EPILOGUE_KEYS, "삭제: 검증기 어휘에서 지운 op·cond·후일담 키")
	ok(real.threat("persuasion_plot").is_empty() and real.threat("persuasion_plot2").is_empty(), "삭제: 회유 공작 위협")
	var g := _new(CH)
	ok(not g.players[0].has("traitor") and not g.players[0].has("interro") and not "traitor_id" in g.save_state(), "삭제: 요원 상태에 traitor·interro가 없음")
	ok(not g.apply({"type": "persuade", "player": 0, "die": 0, "target": 1}) and not g.apply({"type": "inform", "player": 0, "target": 1}), "삭제: persuade·inform 액션은 거부")
	ok(g._next_voter(-1) == 0 and g._next_voter(2) == 3 and g._next_voter(3) == -1, "투표: 모든 요원이 번호순으로 투표 (_next_voter)")
	# 아침 순서: 위협 → 투표 → 미션 줄 → 주사위 (변절 확인 자리가 없어짐). 선택이 끼지 않은 아침은 5에서 끝남
	var gm := _new(CH)
	gm.act = 1
	gm.phase = "morning"
	gm.morning_step = 1
	gm.threat_deck = ["calm_day"]
	gm.ready = 0
	gm._morning_continue()
	ok(gm.morning_step == 5 and gm.phase == "plan" and not gm.op_dice.is_empty(), "아침 순서: 위협 → 투표 → 미션 줄 → 주사위 네 단계 (morning_step 5에서 끝)")


# ------------------------------------------------------------------ B단계: 주사위 1개 = 행동 1개 (11·12단계)

func _run_b_tests() -> void:
	_test_b_action_economy()
	_test_b_cells_and_police_block()
	_test_b_effect_once_per_cell()
	_test_b_walk_distance()
	_test_b_police_summon()
	_test_b_hide()
	_test_b_scout()
	_test_b_gives_and_visit()
	_test_b_market_and_misc()
	_test_b_save_resume()


func _legal_types(g: RulesV2) -> Array:
	var out := []
	for a in g.legal_actions():
		if not a["type"] in out:
			out.append(a["type"])
	return out


func _test_b_action_economy() -> void:
	var g := _new(CH)
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7)])
	_turn(g, 0, 0)
	var t0 := _legal_types(g)
	ok("end_turn" in t0 and not "move_die" in t0 and not "end_move" in t0, "행동 경제: 주사위가 없으면 이동 행동이 없고 차례 마치기만 남음")
	var a := _spare(g, 3, 0)
	var b := _spare(g, 4, 0)
	# 공짜: 아이템은 차례에 1장, 능력은 하루 1번 (주사위를 쓰지 않음)
	g.players[0]["items"] = ["train_ticket", "train_ticket"]
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}) and not g.op_dice[a]["used"] and not g.op_dice[b]["used"], "행동 경제: 아이템 쓰기는 공짜 (주사위를 쓰지 않음)")
	ok(not g.apply({"type": "use_item", "player": 0, "index": 0}), "행동 경제: 아이템은 차례에 1장")
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and not g.op_dice[a]["used"], "행동 경제: 능력 쓰기는 공짜 (하루 1번)")
	ok(not g.apply({"type": "ability", "player": 0, "target": 1}), "행동 경제: 능력은 하루 1번")
	# 보정은 그 차례의 첫 이동 행동에만 붙는다
	ok(g.apply({"type": "move_die", "player": 0, "die": a}) and g.op_dice[a]["used"] and g.steps_left == 6, "행동 경제: 이동 행동은 주사위 하나를 씀 (승차권 +3은 첫 이동 행동에)")
	var t2 := _legal_types(g)
	ok("step" in t2 and "end_move" in t2 and not "move_die" in t2 and not "end_turn" in t2 and not "give_die" in t2,
		"행동 경제: 걷는 동안에는 다른 행동을 못 함 (걸음·이동 마치기뿐)")
	_step(g, 0, Vector2i(5, 6), false)
	ok(g.apply({"type": "end_move", "player": 0}) and g.phase == "turn" and g.current == 0 and g.steps_left == 0, "행동 경제: 이동을 멈추면 행동 고르기로 돌아옴")
	ok(g.apply({"type": "move_die", "player": 0, "die": b}) and g.steps_left == 4, "행동 경제: 두 번째 이동 행동에는 보정이 없음 (주사위 4 = 4칸)")
	g.apply({"type": "end_move", "player": 0})
	ok(not g.players[0]["done_today"] and "end_turn" in _legal_types(g), "행동 경제: 차례는 「차례 마치기」를 해야 끝남")
	var c := _spare(g, 5, 0)
	ok(g.apply({"type": "end_turn", "player": 0}) and g.players[0]["done_today"] and g.phase == "day" and not g.op_dice[c]["used"],
		"행동 경제: 주사위가 남아 있어도 차례를 마칠 수 있음 (남은 주사위는 그대로)")
	ok(not g.apply({"type": "move_die", "player": 0, "die": c}), "행동 경제: 차례를 마친 뒤에는 행동 불가")
	# 남은 주사위는 밤에 사라지고 아침에 새로 굴림
	var n := int(g.data.rules["personal_dice"])
	for pid in [1, 2, 3]:
		_turn(g, pid, 0)
		g.apply({"type": "end_turn", "player": pid})
	ok(g.day == 2 and g.op_dice.size() <= 4 * (n + 1) and not c in g.my_dice(0), "행동 경제: 쓰지 않은 주사위는 밤에 사라짐")


func _test_b_cells_and_police_block() -> void:
	# 요원끼리는 같은 칸에 들어가고 머물 수 있다
	var g := _new(CH)
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(6, 6)])
	_turn(g, 0, 1)
	ok(_step(g, 0, Vector2i(5, 6)), "같은 칸: 첫 요원이 칸에 들어감")
	_turn(g, 1, 1)
	ok(_step(g, 1, Vector2i(5, 6)) and g.players[1]["pos"] == g.players[0]["pos"], "같은 칸: 다른 요원이 같은 칸에 들어가 머물 수 있음")
	_turn(g, 2, 2)
	ok(_step(g, 2, Vector2i(5, 6), false) and _step(g, 2, Vector2i(5, 7), false), "같은 칸: 동료가 선 칸을 지나갈 수도 있음")
	g.apply({"type": "end_move", "player": 2})
	# 경찰이 있는 칸에는 들어갈 수 없다
	g.police[3] = {"pos": Vector2i(6, 6), "summon_turn": 9}
	_turn(g, 0, 0)
	g.players[0]["done_today"] = false
	_spare(g, 3, 0)
	g.apply({"type": "end_turn", "player": 0})
	var gp := _new(CH)
	_lay(gp, [Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6)])
	gp.police[3] = {"pos": Vector2i(6, 6), "summon_turn": 9}
	gp.players[0]["pos"] = Vector2i(5, 6)
	_turn(gp, 0, 3)
	ok(not gp.can_step(gp.players[0], Vector2i(6, 6)) and not _step(gp, 0, Vector2i(6, 6), false), "경찰 칸: 경찰이 있는 칸에는 들어갈 수 없음")
	var path := gp.path_to(gp.players[0], Vector2i(7, 6))
	ok(not path["reachable"] or not Vector2i(6, 6) in path["path"], "경찰 칸: 길 찾기도 경찰 칸을 지나지 않음")
	ok(not gp.path_to(gp.players[0], Vector2i(6, 6))["reachable"] and gp.path_to(gp.players[0], Vector2i(6, 6))["reason"] == "경찰이 있는 칸", "경찰 칸: 목적지가 경찰 칸이면 갈 수 없음")
	# 경찰이 있는 거점에는 들어갈 수 없고, 경찰이 떠나면 들어감
	var base: Vector2i = gp.data.bases[0]
	var gb := _new(CH)
	_tile(gb, base + Vector2i(1, 0), "normal")
	gb.players[0]["pos"] = base + Vector2i(1, 0)
	gb.police[2] = {"pos": base, "summon_turn": 9}
	_turn(gb, 0, 2)
	ok(not gb.can_step(gb.players[0], base), "경찰 칸: 경찰이 선 거점에도 들어갈 수 없음")
	gb.police.clear()
	ok(gb.can_step(gb.players[0], base), "경찰 칸: 경찰이 떠나면 거점에 들어갈 수 있음")


func _test_b_effect_once_per_cell() -> void:
	# 같은 칸의 효과는 한 차례에 한 번만 (보급 타일에서 나갔다 들어와도 폭탄은 한 번)
	var g := _new(["seok", "han", "oh", "park"])
	_tile(g, Vector2i(5, 6), "supply")
	var before := g.bomb_supply
	_turn(g, 0, 1)
	ok(_step(g, 0, Vector2i(5, 6), false), "칸 효과: 보급 칸에 들어감")
	ok(g.players[0]["bombs"] == 1 and g.bomb_supply == before - 1 and Vector2i(5, 6) in g.players[0]["fx_cells"], "칸 효과: 멈추면 폭탄 1개 (받은 칸이 기록됨)")
	var d1 := _spare(g, 1, 0)
	g.apply({"type": "move_die", "player": 0, "die": d1})
	_step(g, 0, START, false)
	var d2 := _spare(g, 1, 0)
	g.apply({"type": "move_die", "player": 0, "die": d2})
	_step(g, 0, Vector2i(5, 6), false)
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.players[0]["bombs"] == 1 and g.bomb_supply == before - 1,
		"칸 효과: 다른 칸에 갔다 다시 같은 칸에서 멈춰도 그 차례에는 효과가 없음 (폭탄 칸이 2개여도 1개)")
	g.apply({"type": "end_turn", "player": 0})
	ok(g.players[0]["fx_cells"].size() == 2, "칸 효과: 받은 칸 목록은 차례가 끝나도 남음 (다음 차례 시작에 지움)")
	g.phase = "day"
	g.players[0]["done_today"] = false
	g.apply({"type": "begin_turn", "player": 0})
	ok(g.players[0]["fx_cells"].is_empty(), "칸 효과: 다음 차례가 시작되면 목록이 비어 새로 받을 수 있음")
	# 이동 행동을 두 번 하면 다른 칸의 효과는 두 번 받는다 (이벤트·아이템 칸)
	var g2 := _new(CH)
	_tile(g2, Vector2i(5, 6), "item")
	_tile(g2, Vector2i(5, 7), "item")
	g2.item_deck = ["train_ticket", "telescope"]
	_turn(g2, 0, 1)
	_step(g2, 0, Vector2i(5, 6), false)
	g2.apply({"type": "end_move", "player": 0})
	var more := _spare(g2, 1, 0)
	g2.apply({"type": "move_die", "player": 0, "die": more})
	_step(g2, 0, Vector2i(5, 7), false)
	g2.apply({"type": "end_move", "player": 0})
	ok(g2.players[0]["items"].size() == 2, "칸 효과: 이동 행동을 두 번 하면 다른 칸의 효과를 두 번 받음")


func _test_b_walk_distance() -> void:
	var g := _new(CH)
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7)])
	ok(g.walk_dist(START, Vector2i(5, 7)) == 2 and g.walk_dist(START, Vector2i(7, 7)) == 4, "거리: 깔린 칸을 따라 걷는 칸 수로 잼")
	ok(g.walk_dist(START, Vector2i(6, 5)) >= 100, "거리: 깔린 길이 이어지지 않으면 아주 먼 것으로 침 (직선 1칸이어도)")
	_tile(g, Vector2i(6, 5), "normal")
	ok(g.walk_dist(START, Vector2i(6, 5)) == 1, "거리: 길이 깔리면 가까워짐 (캐시도 갱신됨)")
	# 경찰 따돌림: 다가온 뒤에도 깔린 길로 5칸 넘게 떨어져 있어야
	var gd := _gd()
	ok(int(gd.rules["police"]["escape_distance"]) == 5, "따돌림: 거리 기준은 5칸 (rules.police.escape_distance)")
	var near_far := []
	for pos in [Vector2i(8, 10), Vector2i(7, 10)]:
		var gs := _new(CH)
		for y in range(6, 11):
			_tile(gs, Vector2i(5, y), "normal")
		for x in range(6, 11):
			_tile(gs, Vector2i(x, 10), "normal")
		gs.police[0] = {"pos": pos, "summon_turn": 0}
		_turn(gs, 0, 0)
		gs.apply({"type": "end_turn", "player": 0})
		near_far.append(gs.police.has(0))
	ok(near_far == [false, true], "따돌림: 걸어서 8칸 떨어지면 (경찰 2칸 다가온 뒤 6칸) 따돌리고, 7칸이면 (다가온 뒤 5칸) 못 따돌림")
	# 직선으로는 가까워도 길이 끊겼으면 따돌림
	var gc := _new(CH)
	_tile(gc, Vector2i(5, 6), "normal")
	_tile(gc, Vector2i(5, 8), "normal")
	gc.police[0] = {"pos": Vector2i(5, 8), "summon_turn": 0}
	_turn(gc, 0, 0)
	gc.apply({"type": "end_turn", "player": 0})
	ok(not gc.police.has(0), "따돌림: 깔린 길로 이어지지 않으면 따돌림")


func _test_b_police_summon() -> void:
	# 붙은 경찰은 그 요원에게서 가장 가까운 거점에 나타난다
	var g := _new(CH)
	_flat(g)
	g.players[0]["pos"] = Vector2i(2, 2)
	var near: Vector2i = g.data.bases[g._nearest_base(Vector2i(2, 2))]
	g._summon(g.players[0])
	ok(g.police.has(0) and g.police[0]["pos"] == near, "경찰 등장: 새로 붙으면 요원에게서 가장 가까운 거점에 나타남")
	ok(g.police[0]["summon_turn"] == g.players[0]["turns"], "경찰 등장: 붙은 다음 차례부터 움직임 (summon_turn)")
	# 「이 자리에 나타남」 (밀고자)
	var g2 := _new(CH)
	g2.players[0]["pos"] = Vector2i(5, 8)
	_event(g2, 0, "informer")
	ok(g2.police.has(0) and g2.police[0]["pos"] == Vector2i(5, 8), "경찰 등장: 이벤트 「밀고자」는 그 자리에 나타남 (at here)")
	# 이미 쫓기는 요원에게 또 붙으면 새 말을 놓지 않고, 쫓던 경찰이 2칸 떨어진 곳으로 옮겨 온다
	var g3 := _new(CH)
	_flat(g3)
	g3.players[0]["pos"] = Vector2i(5, 5)
	g3.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	g3._summon(g3.players[0])
	ok(g3.police.size() == 1 and g3.walk_dist(g3.police[0]["pos"], Vector2i(5, 5)) == 2, "경찰 등장: 이미 쫓기는 요원에게 또 붙으면 쫓던 경찰이 2칸 떨어진 곳으로 옮겨 옴 (새 말은 없음)")
	ok(g3.police[0]["pos"] == Vector2i(5, 7), "경찰 등장: 2칸 떨어진 칸 중 원래 위치에 가까운 곳")
	ok(g3.police[0]["summon_turn"] == g3.players[0]["turns"], "경찰 등장: 옮겨 온 차례에는 움직이지 않음")
	# 경찰 말이 모자라면 새 경찰은 나오지 않는다
	var g4 := _new(["park", "han", "oh", "seo"])
	for i in 4:
		g4.police[i] = {"pos": g4.data.bases[0], "summon_turn": 0}
	g4.players[1]["pos"] = Vector2i(5, 5)
	g4.police.erase(1)
	var five := int(g4.data.rules["police"]["pieces"])
	ok(g4.police.size() == five - 1, "경찰 등장: (준비) 말 하나가 남음")
	g4._summon(g4.players[1])
	ok(g4.police.size() == five and g4.police.has(1), "경찰 등장: 말이 남아 있으면 붙음")


func _test_b_hide() -> void:
	var g := _new(CH)
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8)])
	_turn(g, 0, 0)
	_spare(g, 3, 0)
	ok(not g.can_hide(g.players[0]) and not _legal_types(g).has("hide"), "숨기: 일반 칸에서는 못 함")
	var gd := _gd()
	ok(gd.rules["hide"]["tiles"] == ["alley", "tavern"] and gd.rules["hide"]["flags"] == ["hideout"], "숨기: 가능한 칸은 데이터(rules.hide)의 타일 종류와 표시")
	# 골목(타일 종류)에서
	var g2 := _new(CH)
	_lay(g2, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8)])
	_tile(g2, Vector2i(5, 6), "alley")
	g2.players[0]["pos"] = Vector2i(5, 6)
	g2.police[0] = {"pos": Vector2i(5, 7), "summon_turn": 0}
	_turn(g2, 0, 0)
	ok(not g2.can_hide(g2.players[0]), "숨기: 주사위가 없으면 못 함 (행동)")
	var hd := _spare(g2, 2, 0)
	ok(g2.can_hide(g2.players[0]) and g2.apply({"type": "hide", "player": 0, "die": hd}) and g2.op_dice[hd]["used"] and g2.players[0]["hidden"], "숨기: 골목 칸에서 주사위 하나로 숨음")
	ok(not g2.can_hide(g2.players[0]), "숨기: 한 차례에 한 번")
	g2.apply({"type": "end_turn", "player": 0})
	ok(g2.police.has(0) and g2.police[0]["pos"] == Vector2i(5, 7) and not g2.players[0]["jailed"] and not g2.players[0]["hidden"],
		"숨기: 이번 차례 끝에 내 경찰이 다가오지 않음 (체포 안 됨, 표시는 지워짐)")
	# 대조: 숨지 않으면 경찰이 다가와 체포
	var g3 := _new(CH)
	_lay(g3, [Vector2i(5, 6), Vector2i(5, 7)])
	_tile(g3, Vector2i(5, 6), "alley")
	g3.players[0]["pos"] = Vector2i(5, 6)
	g3.police[0] = {"pos": Vector2i(5, 7), "summon_turn": 0}
	_turn(g3, 0, 0)
	g3.apply({"type": "end_turn", "player": 0})
	ok(g3.players[0]["jailed"], "숨기: 숨지 않으면 경찰이 다가와 체포 (대조)")
	# 은신처 표시가 있는 칸, 주막 타일
	var g4 := _new(CH)
	_tile(g4, Vector2i(5, 6), "normal")
	g4.board[Vector2i(5, 6)]["flags"].append("hideout")
	g4.players[0]["pos"] = Vector2i(5, 6)
	_turn(g4, 0, 0)
	_spare(g4, 2, 0)
	ok(g4.can_hide(g4.players[0]), "숨기: 은신처 표시가 있는 칸에서도 할 수 있음")
	var g5 := _new(CH)
	_tile(g5, Vector2i(5, 6), "tavern")
	g5.players[0]["pos"] = Vector2i(5, 6)
	_turn(g5, 0, 0)
	_spare(g5, 2, 0)
	ok(g5.can_hide(g5.players[0]), "숨기: 주막 칸에서도 할 수 있음")
	# 이동 중이거나 갇혀 있으면 못 함
	g5.players[0]["jailed"] = true
	ok(not g5.can_hide(g5.players[0]), "숨기: 갇힌 요원은 못 함")


func _test_b_scout() -> void:
	var g := _new(CH)
	g.tile_deck = ["normal", "normal", "event", "item"]
	_turn(g, 0, 0)
	var d := _spare(g, 2, 0)
	var items_before: int = g.players[0]["items"].size()
	var deck_before := g.tile_deck.size()
	ok(g.apply({"type": "scout", "player": 0, "die": d}) and g.op_dice[d]["used"], "정찰: 주사위 하나를 내는 행동")
	ok(g.phase == "choice" and g.pending["kind"] == "pick_cell", "정찰: 덮인 칸을 골라 달라고 물음")
	var opts: Array = g.pending["options"].map(func(o): return o["value"])
	var inside := true
	for c in opts:
		inside = inside and not g.board.has(c) and absi(c.x - START.x) + absi(c.y - START.y) <= 2
	ok(inside and opts.size() > 4, "정찰: 눈(2)만큼 떨어진 곳까지의 덮인 칸만 후보")
	ok(not Vector2i(5, 8) in opts and not Vector2i(7, 7) in opts and Vector2i(5, 7) in opts and Vector2i(6, 6) in opts, "정찰: 눈 2의 안쪽 (맨해튼 2칸)까지")
	_answer(g, Vector2i(5, 7))
	ok(g.phase == "choice" and g.pending["kind"] == "pick_cell" and not (Vector2i(5, 7) in g.pending["options"].map(func(o): return o["value"])),
		"정찰: 두 번째 칸을 고름 (이미 고른 칸은 후보에서 빠짐)")
	_answer(g, Vector2i(6, 6))
	ok(g.phase == "turn" and g.board.has(Vector2i(5, 7)) and g.board.has(Vector2i(6, 6)) and g.tile_deck.size() == deck_before - 2, "정찰: 두 칸의 타일이 앞면으로 깔리고 더미에서 두 장이 빠짐")
	ok(g.board[Vector2i(5, 7)]["type"] == "item" and g.board[Vector2i(6, 6)]["type"] == "event", "정찰: 더미 맨 위에서부터 한 장씩")
	ok(g.players[0]["items"].size() == items_before and g.event_discard.is_empty() and not g.board[Vector2i(5, 7)]["used"],
		"정찰: 깔기만 할 뿐 효과는 그 칸에서 이동을 마칠 때 받음 (아직 안 받음)")
	_spare(g, 1, 0)
	var mv := _spare(g, 1, 0)
	_tile(g, Vector2i(5, 6), "normal")
	g.apply({"type": "move_die", "player": 0, "die": mv})
	_step(g, 0, Vector2i(5, 6), false)
	g.apply({"type": "end_move", "player": 0})
	var mv2 := _spare(g, 1, 0)
	g.apply({"type": "move_die", "player": 0, "die": mv2})
	_step(g, 0, Vector2i(5, 7), false)
	ok(g.players[0]["items"].size() == items_before + 1, "정찰: 나중에 그 칸에서 이동을 마치면 효과를 받음 (아이템 칸)")
	# 후보가 없거나 더미가 없으면 못 함
	var g2 := _new(CH)
	g2.tile_deck = []
	_turn(g2, 0, 0)
	var d2 := _spare(g2, 3, 0)
	ok(not g2.apply({"type": "scout", "player": 0, "die": d2}), "정찰: 더미가 비면 할 수 없음")
	var g3 := _new(CH)
	g3.tile_deck = ["normal", "normal", "normal"]
	_turn(g3, 0, 0)
	var d3 := _spare(g3, 1, 0)
	g3.apply({"type": "scout", "player": 0, "die": d3})
	ok(g3.pending["options"].size() == 4, "정찰: 눈 1이면 옆 네 칸")
	_answer(g3, Vector2i(5, 6))
	_answer(g3, Vector2i(5, 4))
	_tile(g3, Vector2i(6, 5), "normal")
	_tile(g3, Vector2i(4, 5), "normal")
	var d4 := _spare(g3, 1, 0)
	ok(not g3.apply({"type": "scout", "player": 0, "die": d4}), "정찰: 눈만큼 떨어진 곳에 덮인 칸이 없으면 할 수 없음")
	# 한 곳만 깔 수 있으면 그 한 곳은 묻지 않고 깐다
	var g4 := _new(CH)
	g4.tile_deck = ["normal", "normal"]
	_flat(g4)
	g4.board.erase(Vector2i(5, 6))
	g4._dist_cache = {}
	_turn(g4, 0, 0)
	var d5 := _spare(g4, 1, 0)
	g4.apply({"type": "scout", "player": 0, "die": d5})
	ok(g4.phase == "turn" and g4.board.has(Vector2i(5, 6)) and g4.tile_deck.size() == 1, "정찰: 덮인 칸이 하나뿐이면 묻지 않고 깐다")


func _test_b_gives_and_visit() -> void:
	# 주사위 건네기: 같은 칸 동료에게만, 하루 1번, 차례를 마친 요원에게는 안 됨
	var g := _new(CH)
	_lay(g, [Vector2i(5, 6)])
	g.players[1]["pos"] = START
	g.players[2]["pos"] = Vector2i(5, 6)
	g.players[3]["pos"] = START
	g.players[3]["done_today"] = true
	_turn(g, 0, 0)
	var d1 := _spare(g, 5, 0)
	var d2 := _spare(g, 2, 0)
	var tg := g.give_die_targets(g.players[0])
	ok(tg == [1], "건네기: 주사위는 같은 칸의 아직 차례를 안 한 동료에게만 (옆 칸·차례를 마친 요원은 안 됨)")
	ok(not g.apply({"type": "give_die", "player": 0, "die": d1, "target": 3}) and not g.apply({"type": "give_die", "player": 0, "die": d1, "target": 2}),
		"건네기: 차례를 마친 요원에게는 주사위를 건넬 수 없음")
	ok(g.apply({"type": "give_die", "player": 0, "die": d1, "target": 1}) and d1 in g.my_dice(1), "건네기: 같은 칸 동료에게 주사위를 줌 (받은 쪽은 행동 하나를 더 함)")
	ok(g.give_die_targets(g.players[0]).is_empty() and not g.apply({"type": "give_die", "player": 0, "die": d2, "target": 1}), "건네기: 하루 1번")
	# 아이템은 차례를 마친 요원에게도, 옆 칸 동료에게도 건넬 수 있다 (주사위 하나를 냄)
	var gi := _new(CH)
	_lay(gi, [Vector2i(5, 6)])
	gi.players[0]["items"] = ["telescope"]
	gi.players[1]["pos"] = Vector2i(5, 6)
	gi.players[2]["done_today"] = true
	gi.players[3]["pos"] = Vector2i(9, 9)
	_turn(gi, 0, 0)
	_spare(gi, 3, 0)
	var targets := []
	for o in gi.give_options(gi.players[0]):
		if not o["to"] in targets:
			targets.append(o["to"])
	ok(1 in targets and 2 in targets and not 3 in targets, "건네기: 아이템은 같은 칸이나 옆 칸 동료에게 (차례를 마친 동료도 됨)")


func _test_b_market_and_misc() -> void:
	# 면회: 갇힌 요원은 그 거점 옆 칸의 동료와 아이템·주사위를 주고받는다
	var g := _new(CH)
	var base: Vector2i = g.data.bases[2]
	var next: Vector2i = base + Vector2i(0, -1)
	var far: Vector2i = base + Vector2i(0, -3)
	_lay(g, [next, base + Vector2i(0, -2), far])
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = base
	g.players[0]["pos"] = next
	g.players[2]["pos"] = far
	g.players[0]["items"] = ["telescope"]
	_turn(g, 0, 0)
	var vd := _spare(g, 6, 0)
	ok(g.give_die_targets(g.players[0]) == [1], "면회: 옆 칸에 온 동료는 갇힌 요원에게 주사위를 건넬 수 있음")
	ok(g.give_options(g.players[0]).size() == 1 and g.give_options(g.players[0])[0]["to"] == 1, "면회: 옆 칸에 온 동료는 갇힌 요원에게 아이템을 건넬 수 있음 (먼 동료는 못 함)")
	ok(g.apply({"type": "give_die", "player": 0, "die": vd, "target": 1}) and vd in g.my_dice(1), "면회: 주사위가 갇힌 요원 것이 됨")
	g.apply({"type": "end_turn", "player": 0})
	# 갇힌 요원도 옆 칸에 온 동료에게 건넬 수 있다 (그 동료가 아직 차례를 안 했다면)
	var gj := _new(CH)
	_lay(gj, [next])
	gj.players[1]["jailed"] = true
	gj.players[1]["pos"] = base
	gj.players[0]["pos"] = next
	_turn(gj, 1, 0)
	var jd := _spare(gj, 4, 1)
	ok(gj.give_die_targets(gj.players[1]) == [0], "면회: 갇힌 요원은 옆 칸에 온 동료에게 주사위를 건넬 수 있음")
	gj.players[0]["done_today"] = true
	ok(gj.give_die_targets(gj.players[1]).is_empty() and not gj.apply({"type": "give_die", "player": 1, "die": jd, "target": 0}),
		"면회: 이미 차례를 마친 동료에게는 갇힌 요원도 주사위를 못 건넴")
	# 받은 주사위로 탈옥 판정 (눈 6 + 1d6 ≥ 8이라 박 하사가 아니어도 거의 성공, 목표를 0으로 해서 확인)
	var gd := _gd(func(d): d.rules["checks"]["escape"] = 0)
	var ge := _new(CH, gd)
	_lay(ge, [next])
	ge.players[1]["jailed"] = true
	ge.players[1]["pos"] = base
	var rcv := _spare(ge, 6, 1)
	_turn(ge, 1, 0)
	ok(ge.apply({"type": "escape", "player": 1, "die": rcv}) and not ge.players[1]["jailed"], "면회: 받은 주사위로 탈옥 판정을 할 수 있음")
	# 장터 행동의 틀: 장터 타일에서 주사위 하나, 효과는 데이터(rules.market.effects)
	var gm := _new(CH)
	_tile(gm, Vector2i(5, 6), "market")
	gm.players[0]["pos"] = Vector2i(5, 6)
	_turn(gm, 0, 0)
	ok(not gm.can_market(gm.players[0]), "장터: 주사위가 없으면 못 함")
	var md := _spare(gm, 3, 0)
	ok(gm.can_market(gm.players[0]) and gm.apply({"type": "market", "player": 0, "die": md}) and gm.op_dice[md]["used"], "장터: 장터 타일에서 주사위 하나를 내는 행동")
	var gn := _new(CH)
	_turn(gn, 0, 0)
	_spare(gn, 3, 0)
	ok(not gn.can_market(gn.players[0]) and not _legal_types(gn).has("market"), "장터: 장터 타일이 아니면 못 함")
	ok(str(_gd().rules["market"]["tile"]) == "market", "장터: 타일 종류는 데이터(rules.market.tile)")
	# 삭제: 전차 · 보석 · 장터 팔기 (v2에 없음)
	var real := GameDataV2.load_default()
	ok(not real.rules["tiles"].has("tram") and not real.rules["tiles"].has("tram_stop") and not real.rules.has("bail") and not real.rules.has("sell"),
		"삭제: 전차 정류장 타일 · 보석 · 장터 팔기는 데이터에 없음")
	var types := _legal_types(gm)
	ok(not "tram" in types and not "bail" in types and not "sell" in types, "삭제: 전차·보석·팔기 행동은 없음")
	# 위조 통행증은 1장
	var forged := 0
	for it in real.items["items"]:
		if it["id"] == "forged_pass":
			forged = int(it["count"])
	ok(forged == 1, "아이템: 위조 통행증은 1장")


func _test_b_save_resume() -> void:
	# 새 차례 상태(받은 칸 목록, 숨기)도 저장·불러오기에 들어가고, 이어 두면 같은 판이 된다
	var gd := _fixed_data()
	var g := _new(CH)
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7)])
	_tile(g, Vector2i(5, 7), "alley")
	_turn(g, 0, 0)
	var d := _spare(g, 2, 0)
	_spare(g, 3, 0)
	g.apply({"type": "move_die", "player": 0, "die": d})
	_step(g, 0, Vector2i(5, 6), false)
	_step(g, 0, Vector2i(5, 7), false)
	ok(g.players[0]["fx_cells"] == [Vector2i(5, 7)], "저장: 멈춘 칸이 받은 칸 목록에 오름")
	var st := g.save_state()
	var clone := RulesV2.new()
	clone.load_state(st, gd)
	ok(clone.players[0]["fx_cells"] == [Vector2i(5, 7)] and str(clone.save_state()) == str(g.save_state()), "저장: 받은 칸 목록이 그대로 불러와짐")
	var script := [{"type": "hide", "player": 0, "die": 1}, {"type": "end_turn", "player": 0}]
	var same := true
	for a in script:
		var r1 := g.apply(a.duplicate(true))
		var r2 := clone.apply(a.duplicate(true))
		same = same and r1 == r2 and r1
	ok(same and g.players[0]["done_today"] and str(clone.save_state()) == str(g.save_state()), "저장: 불러온 판도 같은 행동에 같은 결과 (숨기·차례 마치기)")
	ok(g.players[0]["fx_cells"].size() == 1, "저장: 차례를 마친 뒤에도 받은 칸 목록은 남음")
	# 다시보기: 같은 행동 기록을 새 판에 되풀이하면 같은 판이 된다 (AI가 둔 판)
	var data := GameDataV2.load_default()
	var defs := []
	for c in CH:
		defs.append({"name": "요원 " + c, "character": c})
	var a1 := RulesV2.new()
	a1.setup(defs, 4242, data)
	var steps := 0
	while a1.phase != "over" and steps < 700:
		var act := GameAIV2.decide(a1, GameAIV2.next_actor(a1))
		if act.is_empty() or not a1.apply(act):
			break
		steps += 1
	var a2 := RulesV2.new()
	a2.setup(defs, 4242, data)
	var replay_ok := true
	for act in a1.actions:
		if not a2.apply(act.duplicate(true)):
			replay_ok = false
			break
	ok(steps > 100 and replay_ok and str(a2.save_state()) == str(a1.save_state()), "다시보기: 행동 기록을 되풀이하면 같은 상태 (%d 행동)" % steps)
