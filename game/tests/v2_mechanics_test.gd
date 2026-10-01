extends SceneTree
## v2 엔진 규칙 하나씩 확인 (2a 규칙 + 2b 카드 효과). 상태를 직접 꾸며 놓고 결과를 본다.
## 판정이 필요한 곳은 별도 GameDataV2 복사본의 판정 목표를 0(무조건 성공)이나 99(무조건 실패)로 바꿔 쓴다.
## 실행: godot --headless --path game --script res://tests/v2_mechanics_test.gd

var passed := 0
var failed := 0

const START := Vector2i(5, 5)


func _init() -> void:
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


func _gd(tweak: Callable = Callable()) -> GameDataV2:
	var gd := GameDataV2.new()
	gd.load_dir(GameDataV2.DIR)
	if tweak.is_valid():
		tweak.call(gd)
	return gd


func _new(chars: Array, gd: GameDataV2 = null, seed_value := 1) -> RulesV2:
	var g := RulesV2.new()
	var defs := []
	for c in chars:
		defs.append({"name": "요원 " + c, "character": c})
	g.setup(defs, seed_value, gd if gd else GameDataV2.load_default())
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
	g.team_dice = []
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
		q["die"] = -1
		q["die_raw"] = -1
		q["done_today"] = false
		q["item_uses"] = 0
		q["items"] = []
		q["bombs"] = 0
		q["grants"] = []
		q["flags"] = {}
		q["turns"] = 1
	return g


func _tile(g: RulesV2, cell: Vector2i, type: String) -> void:
	g.board[cell] = g._new_tile(type)


func _spare(g: RulesV2, value: int) -> void:
	g.team_dice.append({"value": value, "owner": -1, "spare_used": false})


func _turn(g: RulesV2, pid: int, die: int) -> bool:
	var p: Dictionary = g.players[pid]
	p["die"] = die
	p["die_raw"] = die
	g.phase = "day"
	return g.apply({"type": "begin_turn", "player": pid})


func _step(g: RulesV2, pid: int, to: Vector2i) -> bool:
	return g.apply({"type": "step", "player": pid, "to": to})


func _answer(g: RulesV2, value) -> bool:
	return g.apply({"type": "choose", "player": g.pending["player"], "value": value})


# ------------------------------------------------------------------ 시험

func _test_plan_dice() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	g.phase = "plan"
	g.team_dice = [{"value": 6, "owner": -1, "spare_used": false}, {"value": 2, "owner": -1, "spare_used": false},
		{"value": 4, "owner": -1, "spare_used": false}, {"value": 5, "owner": -1, "spare_used": false},
		{"value": 3, "owner": -1, "spare_used": false}]
	ok(g.apply({"type": "take_die", "player": 0, "die": 0}), "계획: 0번 요원이 6을 가져감")
	ok(not g.apply({"type": "take_die", "player": 1, "die": 0}), "계획: 남이 가진 주사위는 못 가짐")
	ok(g.apply({"type": "take_die", "player": 1, "die": 1}), "계획: 1번 요원이 2를 가져감")
	ok(g.apply({"type": "take_die", "player": 0, "die": 2}), "계획: 가진 주사위를 내려놓고 바꿈")
	ok(g.team_dice[0]["owner"] == -1 and g.team_dice[2]["owner"] == 0 and g.players[0]["die"] == 4, "계획: 바꾸면 이전 주사위는 비고 값이 4로 바뀜")
	ok(g.apply({"type": "take_die", "player": 1, "die": 0}), "계획: 풀려난 6을 다른 사람이 가져감")
	ok(not g.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)}), "계획: 계획 단계에서는 이동 못 함")
	ok(not g.apply({"type": "start_day", "player": 0}), "계획: 주사위를 못 가진 요원이 있으면 하루를 시작 못 함")
	g.players[3]["jailed"] = true
	g.apply({"type": "take_die", "player": 2, "die": 3})
	ok(g.can_start_day(), "계획: 갇힌 요원은 주사위가 없어도 하루를 시작할 수 있음")
	ok(g.apply({"type": "release_die", "player": 2}) and not g.can_start_day(), "계획: 내려놓으면 다시 시작 못 함")
	g.apply({"type": "take_die", "player": 2, "die": 3})
	g.apply({"type": "take_die", "player": 3, "die": 4})
	g.apply({"type": "release_die", "player": 3})
	ok(g.apply({"type": "start_day", "player": 3}), "계획: 아무 요원이나 하루 시작을 보낼 수 있음")
	ok(g.phase == "day" and g.spare_dice() == [1, 4], "계획: 아무도 안 가진 주사위는 모두 예비가 됨")
	# 갇힌 요원이 가진 주사위는 예비로 돌아간다
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.phase = "plan"
	g2.team_dice = [{"value": 6, "owner": -1, "spare_used": false}, {"value": 2, "owner": -1, "spare_used": false},
		{"value": 4, "owner": -1, "spare_used": false}, {"value": 5, "owner": -1, "spare_used": false},
		{"value": 3, "owner": -1, "spare_used": false}]
	g2.players[3]["jailed"] = true
	for i in 4:
		g2.apply({"type": "take_die", "player": i, "die": i})
	g2.apply({"type": "start_day", "player": 0})
	ok(g2.spare_dice().size() == 2 and g2.players[3]["die"] == -1, "계획: 갇힌 요원이 가졌던 주사위는 예비로 돌아옴")
	# 못 받는 요원
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.phase = "plan"
	_spare(g3, 3)
	g3.players[1]["skip_dice_tomorrow"] = true
	ok(not g3.apply({"type": "take_die", "player": 1, "die": 0}), "계획: 오늘 주사위를 못 받는 요원은 못 가짐")


func _test_gaeddong_dice() -> void:
	var g := _new(["gaeddong", "park", "han", "oh"])
	g.phase = "plan"
	for v in [1, 2, 4, 6, 3]:
		_spare(g, v)
	g.apply({"type": "take_die", "player": 0, "die": 0})
	ok(g.players[0]["die"] == 3 and g.players[0]["die_raw"] == 1, "김개똥: 1을 가져가면 3 (굴린 눈은 1 그대로)")
	g.apply({"type": "take_die", "player": 0, "die": 1})
	ok(g.players[0]["die"] == 3 and g.players[0]["die_raw"] == 2, "김개똥: 2도 3")
	g.apply({"type": "take_die", "player": 0, "die": 2})
	ok(g.players[0]["die"] == 4, "김개똥: 4는 그대로")
	g.apply({"type": "take_die", "player": 1, "die": 0})
	ok(g.players[1]["die"] == 1, "다른 캐릭터: 1은 1")
	# 이동 칸 수
	var g2 := _new(["gaeddong", "park", "han", "oh"])
	g2.phase = "plan"
	for v in [1, 5, 5, 5, 5]:
		_spare(g2, v)
	for i in 4:
		g2.apply({"type": "take_die", "player": i, "die": i if i > 0 else 0})
	g2.apply({"type": "start_day", "player": 0})
	g2.apply({"type": "begin_turn", "player": 0})
	ok(g2.steps_left == 3, "김개똥: 주사위 1을 가져가면 3칸 이동")


func _test_free_order_and_night() -> void:
	var g := _new(["park", "han", "oh", "seo"])
	_turn(g, 2, 1)
	ok(g.phase == "turn" and g.current == 2, "자유 순서: 2번 요원이 먼저 시작할 수 있음")
	ok(not g.apply({"type": "begin_turn", "player": 0}), "자유 순서: 차례 중에 다른 요원이 시작 못 함")
	ok(not g.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)}), "자유 순서: 차례가 아닌 요원은 이동 못 함")
	ok(not g.apply({"type": "end_move", "player": 1}), "자유 순서: 차례가 아닌 요원은 이동을 못 끝냄")
	g.apply({"type": "end_move", "player": 2})
	ok(g.phase == "day" and g.players[2]["done_today"], "자유 순서: 이동을 끝내면 낮으로 돌아옴")
	ok(not g.apply({"type": "begin_turn", "player": 2}), "자유 순서: 이미 한 요원은 다시 못 함")
	for pid in [3, 0, 1]:
		_turn(g, pid, 1)
		g.apply({"type": "end_move", "player": pid})
	ok(g.day == 2 and g.leader == 1 and g.rounds_left == 9, "밤: 모두 마치면 다음 날 아침 (리더가 옆 사람으로, 남은 날 -1)")
	ok(g.phase in ["plan", "choice"] , "밤: 다음 날 아침이 계획 단계(또는 선택)에 이름")
	# 마지막 날 밤
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.rounds_left = 1
	for pid in 4:
		_turn(g2, pid, 1)
		g2.apply({"type": "end_move", "player": pid})
	ok(g2.phase == "over" and g2.ending.get("id") == "time", "밤: 남은 날이 0이 되면 time으로 끝남")


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
	ok(g.phase == "over" and g.ending.get("id") == "launch_stub" and g.launch_info.get("reason") == "vote", "투표: 동수에서 리더가 찬성이면 결행")
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.leader = 2
	_begin_vote(g2)
	_vote_all(g2, [true, true, false, false])
	ok(g2.phase == "plan" and g2.act == 1, "투표: 동수에서 리더가 반대면 결행 안 함 (아침이 이어져 계획 단계로)")
	var g3 := _new(["park", "han", "oh", "seo"])
	g3.leader = 1
	_begin_vote(g3)
	_vote_all(g3, [false, true, false, true])
	ok(g3.phase == "over", "투표: 동수 2:2에서 리더(1번)가 찬성이면 결행")
	var g4 := _new(["park", "han", "oh", "seo"])
	_begin_vote(g4)
	_vote_all(g4, [true, true, true, false])
	ok(g4.phase == "over", "투표: 3:1 과반 찬성이면 결행")
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
	ok(g7.phase == "over" and g7.launch_info.get("reason") == "forced", "투표: 남은 날이 기준 이하면 투표 없이 강제 결행")
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
	ok(g9.phase == "over" and g9.launch_info.get("target") == "prison", "결행: 리더가 고른 거점이 목표")


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
	# 판정 실패 뒤 예비 주사위로 다시 굴리기 선택
	var gd4 := _gd(func(d): d.rules["checks"]["evade"] = 99)
	var g4 := _new(["park", "han", "oh", "seo"], gd4)
	_tile(g4, Vector2i(5, 6), "check")
	_spare(g4, 3)
	g4.phase = "day"
	_turn(g4, 0, 4)
	_step(g4, 0, Vector2i(5, 6))
	ok(g4.phase == "choice" and g4.pending["kind"] == "reroll" and g4.pending["spares"] == [0], "다시 굴리기: 실패하면 예비 주사위로 다시 굴릴지 묻는다")
	ok(g4.apply({"type": "use_spare", "player": 0, "die": 0, "use": "reroll"}), "다시 굴리기: 예비 주사위를 써서 다시 굴림")
	ok(g4.team_dice[0]["spare_used"], "다시 굴리기: 예비 주사위는 한 번만 (사용 표시)")
	ok(g4.phase == "day" and g4.players[0]["done_today"], "다시 굴리기: 또 실패하고 수단이 없으면 실패로 처리")
	var g5 := _new(["park", "han", "oh", "seo"], gd4)
	_tile(g5, Vector2i(5, 6), "check")
	_spare(g5, 3)
	_turn(g5, 0, 4)
	_step(g5, 0, Vector2i(5, 6))
	_answer(g5, "no")
	ok(g5.phase == "day" and g5.exposure == 1, "다시 굴리기: 고르지 않으면 실패로 처리")


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
	_step(g, 0, Vector2i(5, 6))
	ok(g.ready == 4, "미션 두 장 동시: 암살 두 장을 한 번에 이루면 결행 준비 +2 +2")
	ok(g.intel["police_hq"] == 1 and g.intel["barracks"] == 1, "미션 두 장 동시: 두 장의 첩보를 모두 받음")
	ok(g.mission_row == ["m_bribe_guard"], "미션 두 장 동시: 이룬 미션만 줄에서 빠짐")
	ok(g.exposure == 1, "미션 두 장 동시: 시끄러움(노출 +1)은 한 번")
	ok(g.police.has(0), "암살: 성공하면 경찰이 붙음")
	ok(g.players[0]["done_today"] and g.mission_discard.size() == 2, "암살: 이동이 끝나고 이룬 카드는 버려짐")
	# 암살 실패 → 회피 판정 → 실패하면 투옥
	var gd2 := _gd(func(d):
		d.missions["types"]["assassin"]["condition"]["target"] = 99
		d.rules["checks"]["evade"] = 99)
	var g2 := _new(["park", "han", "oh", "seo"], gd2)
	g2.mission_row = ["m_police_chief"]
	_tile(g2, Vector2i(5, 6), "assassin")
	_turn(g2, 0, 4)
	_step(g2, 0, Vector2i(5, 6))
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
	_step(g3, 0, Vector2i(5, 6))
	ok(not g3.players[0]["jailed"] and g3.police.has(0) and g3.ready == 0, "암살: 실패해도 회피에 성공하면 경찰만 붙음")
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
	_step(g8, 0, Vector2i(5, 6))
	ok(g8.ready == 1 and g8.exposure == 1 and g8.mission_row.is_empty() and not g8.police.has(0), "방해: 성공하면 결행 준비 +1, 노출 -1 (전단 살포), 경찰 안 붙음")
	var gd2 := _gd(func(d): d.missions["types"]["sabotage"]["condition"]["target"] = 99)
	var g9 := _new(["park", "han", "oh", "seo"], gd2)
	g9.mission_row = ["m_leaflets"]
	_tile(g9, Vector2i(5, 6), "sabotage")
	_turn(g9, 0, 3)
	_step(g9, 0, Vector2i(5, 6))
	ok(g9.ready == 0 and g9.police.has(0) and g9.mission_row.size() == 1, "방해: 실패하면 경찰이 붙고 미션은 그대로")
	# 이루면 아이템 한 장 (쌀 창고 열기)
	var g10 := _new(["park", "han", "oh", "seo"], gd)
	g10.mission_row = ["m_open_rice"]
	_tile(g10, Vector2i(5, 6), "sabotage")
	_turn(g10, 0, 3)
	_step(g10, 0, Vector2i(5, 6))
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
	g3.apply({"type": "end_move", "player": 0})
	# 거리 9, 속도 2 → 7 남음 > 3 → 따돌림
	ok(not g3.police.has(0), "경찰: 거리가 멀어지면 따돌림")
	# 붙은 차례에는 안 움직임
	var g4 := _new(["park", "han", "oh", "seo"])
	_tile(g4, Vector2i(5, 6), "normal")
	g4.police[0] = {"pos": Vector2i(5, 6), "summon_turn": g4.players[0]["turns"] + 1}
	_turn(g4, 0, 1)
	g4.apply({"type": "end_move", "player": 0})
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
	g.apply({"type": "begin_turn", "player": 0})
	ok(g.phase == "turn" and g.steps_left == 0, "탈옥: 갇힌 요원의 차례는 이동 없이 시작")
	ok(not g.apply({"type": "step", "player": 0, "to": g.data.bases[0] + Vector2i(1, 0)}), "탈옥: 갇힌 요원은 이동 못 함")
	ok(g.apply({"type": "escape", "player": 0}), "탈옥: 탈옥 판정을 시도")
	ok(not g.players[0]["jailed"] and g.police.has(0) and g.players[0]["done_today"], "탈옥: 성공하면 풀려나 경찰이 붙고 차례가 끝남")
	var gd2 := _gd(func(d): d.rules["checks"]["escape"] = 99)
	var g2 := _new(["park", "han", "oh", "seo"], gd2)
	g2.players[0]["jailed"] = true
	g2.players[0]["pos"] = g2.data.bases[0]
	g2.apply({"type": "begin_turn", "player": 0})
	g2.apply({"type": "escape", "player": 0})
	ok(g2.players[0]["jailed"] and g2.players[0]["done_today"], "탈옥: 실패하면 그대로 갇히고 차례가 끝남")
	var g3 := _new(["park", "han", "oh", "seo"], gd2)
	g3.players[0]["jailed"] = true
	g3.players[0]["pos"] = g3.data.bases[0]
	g3.apply({"type": "begin_turn", "player": 0})
	ok(g3.apply({"type": "end_turn", "player": 0}) and g3.players[0]["done_today"], "탈옥: 포기하고 차례를 마칠 수 있음")
	# 예비 주사위를 탈옥 판정에 보탬 (목표 9, 박 하사 +3, 예비 6 → 6+3+6 = 15 필요 없이 2d6 최소 2 + 9 ≥ 9)
	var gd3 := _gd(func(d): d.rules["checks"]["escape"] = 11)
	var g4 := _new(["park", "han", "oh", "seo"], gd3)
	g4.players[0]["jailed"] = true
	g4.players[0]["pos"] = g4.data.bases[0]
	_spare(g4, 6)
	g4.apply({"type": "begin_turn", "player": 0})
	ok(g4.apply({"type": "use_spare", "player": 0, "die": 0, "use": "escape"}), "예비 주사위: 탈옥 판정에 보탤 수 있음")
	ok(not g4.apply({"type": "use_spare", "player": 0, "die": 0, "use": "escape"}), "예비 주사위: 한 번 쓴 것은 다시 못 씀")
	g4.apply({"type": "escape", "player": 0})
	ok(not g4.players[0]["jailed"], "예비 주사위: 보탠 눈이 판정에 더해져 (목표 11, 박 하사 +3, 예비 6, 2d6 최소 2) 반드시 성공")
	# 이동에 더함
	var g5 := _new(["park", "han", "oh", "seo"])
	_spare(g5, 5)
	_turn(g5, 0, 2)
	ok(g5.steps_left == 2, "예비 주사위: 이동 2칸")
	ok(g5.apply({"type": "use_spare", "player": 0, "die": 0, "use": "move"}) and g5.steps_left == 7, "예비 주사위: 이동에 눈만큼 더함")
	ok(not g5.apply({"type": "use_spare", "player": 0, "die": 0, "use": "move"}), "예비 주사위: 각각 하루 한 번")
	ok(not g5.apply({"type": "use_spare", "player": 0, "die": 0, "use": "escape"}), "예비 주사위: 갇히지 않았으면 탈옥에 못 씀")
	# 남이 가진 주사위는 예비가 아님
	var g6 := _new(["park", "han", "oh", "seo"])
	g6.team_dice = [{"value": 4, "owner": 1, "spare_used": false}]
	_turn(g6, 0, 2)
	ok(g6.spare_dice().is_empty() and not g6.apply({"type": "use_spare", "player": 0, "die": 0, "use": "move"}), "예비 주사위: 남이 가진 주사위는 쓸 수 없음")


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
	_turn(g3, 0, 2)
	ok(g3.apply({"type": "give_item", "player": 0, "index": 0, "to": 1}), "건네기: 옆 칸 동료에게 건넴")
	ok(g3.phase == "choice" and g3.pending["player"] == 1 and g3.pending["kind"] == "discard", "건네기: 받은 쪽이 한도를 넘으면 그 요원이 버릴 카드를 고름")
	ok(not g3.apply({"type": "choose", "player": 0, "value": 0}), "건네기: 선택은 맡은 요원만 보낼 수 있음")
	_answer(g3, 0)
	ok(g3.phase == "turn" and g3.players[0]["item_uses"] == 1, "건네기: 아이템 사용 1회로 셈")
	ok(g3.give_options(g3.players[0]).is_empty(), "건네기: 사용 횟수를 넘으면 더 못 건넴")
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
	ok(g.stat(g.players[1], "assassin_rerolls") == 1 and g.stat(g.players[1], "assassin_bonus") == 1, "stat: 특성과 지속 아이템을 합산 (저격수 오 + 망원경)")
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
	_step(g3, 0, Vector2i(5, 6))
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
	_turn(g, 0, 2)
	ok(g.apply({"type": "decoy", "player": 0, "from": 1}), "미끼: 3칸 안 동료를 쫓던 경찰을 나에게로")
	ok(g.police.has(0) and not g.police.has(1) and g.police[0]["pos"] == Vector2i(5, 8), "미끼: 경찰이 내게 붙고 그 자리 그대로")
	ok(not g.apply({"type": "decoy", "player": 0, "from": 1}), "미끼: 이미 쫓기는 중이거나 대상이 없으면 불가")
	# 거리 밖
	var g2 := _new(["park", "han", "oh", "seo"])
	g2.police[1] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g2, 0, 2)
	ok(g2.decoy_options(g2.players[0]).is_empty(), "미끼: 거리가 멀면 불가")
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
	_threat(g, "persuasion_plot")
	_cov("threat", "persuasion_plot")
	ok(_log_has(g, "(3단계 미구현) 심문: %s" % g.players[0]["name"]), "위협 회유 공작: 고립된 요원에게 심문 훅이 불림 (3단계)")

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
	ok(g.players[0]["items"].size() == 1, "이벤트 옛 동지와의 재회 (4인, 심문 카드 없음): 아이템 1장")
	var g3 := _new(["park", "han", "oh"])
	_event(g3, 0, "old_comrade")
	ok(g3.players[0]["items"].size() == 1, "이벤트 옛 동지와의 재회 (3인): 아이템 1장")


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
	g.team_dice = [{"value": 3, "owner": -1, "spare_used": false}, {"value": 6, "owner": -1, "spare_used": false},
		{"value": 2, "owner": -1, "spare_used": false}]
	g.players[0]["items"] = ["pocket_watch"]
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 회중시계: 아침(계획)에 씀")
	_cov("item", "pocket_watch")
	var vals := []
	for o in g.pending["options"]:
		vals.append(o["value"])
	ok(g.pending["kind"] == "pick_die" and "0:1" in vals and "0:-1" in vals and not "1:1" in vals, "아이템 회중시계: 주사위와 ±1을 고름 (6은 +1 불가)")
	_answer(g, "0:1")
	ok(g.team_dice[0]["value"] == 4 and g.phase == "plan", "아이템 회중시계: 팀 주사위 하나의 눈 +1")
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
	_turn(g, 0, 2)
	ok(g.apply({"type": "use_item", "player": 0, "index": 0}), "아이템 옷핀: 갇혔을 때 씀")
	_cov("item", "safety_pin")
	ok(g.apply({"type": "escape", "player": 0}) and not g.players[0]["jailed"], "아이템 옷핀: 판정 없이 바로 탈출 (탈옥 목표 99여도)")
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
	ok(g.police.is_empty() and g.players[0]["skip_dice_tomorrow"], "아이템 동지들의 엄호: 모든 경찰 제거, 내일 내 몫 주사위 없음")
	g.phase = "plan"
	g.team_dice = [{"value": 3, "owner": -1, "spare_used": false}]
	ok(not g.can_take_die(g.players[0], 0) and g.can_take_die(g.players[1], 0), "아이템 동지들의 엄호: 내일 아침 그 요원은 주사위를 못 가짐")

	# 망원경: 암살 판정 +1
	var gda := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 99)
	g = _new(CH, gda)
	g.mission_row = ["m_police_chief"]
	_tile(g, Vector2i(5, 6), "assassin")
	g.players[0]["items"] = ["telescope"]
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6))
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
	_turn(g, 0, 2)
	g.apply({"type": "escape", "player": 0})
	ok(_last_dice(g, "탈옥").get("bonus", -1) == 3, "특성 박 하사(escape_bonus): 탈옥 판정 +3")
	_cov("trait", "park")

	g = _new(["han", "park", "oh", "seo"])
	ok(g.stat(g.players[0], "rescued_move_bonus") == 2, "특성 한 간호장교(rescued_move_bonus): +2 (구출 시험은 2a)")
	_cov("trait", "han")

	var gda := _gd(func(d): d.missions["types"]["assassin"]["condition"]["target"] = 99)
	g = _new(["oh", "han", "park", "seo"], gda)
	g.mission_row = ["m_police_chief"]
	_tile(g, Vector2i(5, 6), "assassin")
	_turn(g, 0, 2)
	_step(g, 0, Vector2i(5, 6))
	ok(_count_dice(g, "암살") == 2, "특성 오 의병(assassin_rerolls): 암살 실패하면 자동으로 한 번 더 굴림")
	var g2 := _new(["park", "han", "oh", "seo"], gda)
	g2.mission_row = ["m_police_chief"]
	_tile(g2, Vector2i(5, 6), "assassin")
	_turn(g2, 0, 2)
	_step(g2, 0, Vector2i(5, 6))
	ok(_count_dice(g2, "암살") == 1, "특성 오 의병: 다른 요원은 한 번만 굴림 (대조)")
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
	_step(g, 0, Vector2i(5, 6))
	ok(_last_dice(g, "회피").get("bonus", -1) == 2, "특성 문 선전대원(sabotage_bonus): 방해 판정 +2")
	ok(g.exposure == 1 and g.ready == 1 and g.intel["prison"] == 1, "특성 문 선전대원(sabotage_exposure): 방해에 성공하면 노출 -1")
	g2 = _new(["park", "han", "oh", "seo"], gds)
	g2.mission_row = ["m_burn_conscript"]
	g2.exposure = 2
	_tile(g2, Vector2i(5, 6), "sabotage")
	_turn(g2, 0, 2)
	_step(g2, 0, Vector2i(5, 6))
	ok(g2.exposure == 2, "특성 문 선전대원: 다른 요원은 노출이 그대로 (대조)")
	_cov("trait", "mun")

	g = _new(["gaeddong", "han", "oh", "seo"])
	ok(g._effective_die(g.players[0], 1) == 3 and g._effective_die(g.players[0], 2) == 3 and g._effective_die(g.players[0], 5) == 5, "특성 김개똥(move_min3): 1·2는 3")
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

	# 이 차장: 동료 옆 빈칸으로 한 칸
	g = _new(["lee", "han", "oh", "seo"])
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7)])
	g.players[1]["pos"] = Vector2i(5, 8)
	_lay(g, [Vector2i(5, 8)])
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(5, 6))
	ok(g.phase == "choice" and g.pending["kind"] == "hop" and g.pending["options"].size() == 2, "특성 이 차장(end_move_hop_to_ally): 이동이 끝나면 동료 옆 빈칸으로 옮길지 묻는다")
	_answer(g, Vector2i(5, 7))
	ok(g.players[0]["pos"] == Vector2i(5, 7) and g.players[0]["done_today"], "특성 이 차장: 옮기면 동료 옆에 서고 차례가 끝남")
	g = _new(["lee", "han", "oh", "seo"])
	_lay(g, [Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8)])
	g.players[1]["pos"] = Vector2i(5, 8)
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(5, 6))
	_answer(g, "no")
	ok(g.players[0]["pos"] == Vector2i(5, 6) and g.players[0]["done_today"], "특성 이 차장: 옮기지 않아도 됨")
	_cov("trait", "lee")

	# 데이터에 직접 넣어 보는 나머지 stat (이 판의 카드에는 아직 없는 것들)
	var gdx := _character_with_mods("park", [{"stat": "move_bonus", "value": 1}, {"stat": "spare_die_bonus", "value": 1},
		{"stat": "base_no_police", "value": 1}, {"stat": "evade_bonus", "value": 2}, {"stat": "assassin_bonus", "value": 3}])
	g = _new(CH, gdx)
	_turn(g, 0, 2)
	ok(g.steps_left == 3, "stat move_bonus: 이동 +1")
	_spare(g, 4)
	ok(g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "move"}) and g.steps_left == 8, "stat spare_die_bonus: 예비 주사위 +1 (4 → 5)")
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
	# 윤 소위: 아침에 팀 주사위 하나 다시 굴림
	var g := _new(["yun", "han", "oh", "seo"])
	g.phase = "plan"
	g.team_dice = [{"value": 3, "owner": -1, "spare_used": false}, {"value": 6, "owner": -1, "spare_used": false},
		{"value": 2, "owner": -1, "spare_used": false}]
	ok(g.apply({"type": "ability", "player": 0}), "능력 무전 지원: 아침(계획)에 씀")
	ok(g.phase == "choice" and g.pending["kind"] == "pick_die" and g.pending["options"].size() == 3, "능력 무전 지원: 다시 굴릴 주사위를 고름")
	_answer(g, 1)
	ok(_log_has(g, "팀 주사위 2을(를) 다시 굴려") and g.phase == "plan" and g.players[0]["ability_day"] == g.day, "능력 무전 지원: 고른 주사위를 다시 굴림")
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
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.players[1]["pos"] == Vector2i(5, 6), "능력 길 안내: 동료를 내 옆 칸으로 데려옴")
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

	# 정 인쇄공 · 서 마담: 설득은 3단계 (능력은 쓸 수 있고 효과만 훅)
	g = _new(["jeong", "han", "oh", "seo"])
	g.players[1]["pos"] = Vector2i(5, 7)
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and _log_has(g, "(3단계 미구현) persuade"), "능력 연락망: 3칸 안 동료 (설득은 3단계 훅)")
	_cov("ability", "jeong")
	g = _new(["jeong", "han", "oh", "seo"])
	g.players[3]["pos"] = Vector2i(9, 9)
	_turn(g, 0, 2)
	ok(not g.can_use_ability(g.players[0], 3) and g.can_use_ability(g.players[0], 1), "능력 연락망: 3칸 밖 동료는 안 됨")
	g = _new(["seo", "han", "oh", "park"])
	g.players[1]["pos"] = Vector2i(5, 6)
	_turn(g, 0, 2)
	ok(not g.can_use_ability(g.players[0], 1) and g.can_use_ability(g.players[0], 2), "능력 다방 밀담: 같은 칸 동료만")
	ok(g.apply({"type": "ability", "player": 0, "target": 2}) and _log_has(g, "(3단계 미구현) persuade"), "능력 다방 밀담: 쓰면 설득 훅 (3단계)")
	_cov("ability", "seo")

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
	_step(g, 0, Vector2i(5, 6))
	ok(g.exposure == 1 and g.ready == 0 and g.players[0]["done_today"] and g.today["assassin_wins"].size() == 1, "협동 동시 습격: 협동 미션만 줄에 있어도 암살 타일에서 판정, 성공하면 노출 +1")
	_turn(g, 1, 2)
	_step(g, 1, Vector2i(6, 5))
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
	_step(g, 0, Vector2i(5, 6))
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
	# 3·4단계 훅 이름
	_fx(g, 0, [{"op": "search", "range": 1}, {"op": "refill_supply"}, {"op": "threat_flip"}, {"op": "check_or_jail", "check": "evade"}, {"op": "scene_check_mod_today", "value": 1}])
	ok(_log_has(g, "(4단계 미구현) search") and _log_has(g, "(4단계 미구현) refill_supply") and _log_has(g, "(4단계 미구현) threat_flip") \
		and _log_has(g, "(4단계 미구현) check_or_jail") and _log_has(g, "(4단계 미구현) scene_check_mod_today"), "훅: 4단계 효과는 (4단계 미구현)으로 로그만")
	_fx(g, 0, [{"op": "persuade", "range": 3, "mode": "random"}, {"op": "interrogate_discard", "who": "self", "count": 1, "mode": "random"}])
	ok(_log_has(g, "(3단계 미구현) persuade") and _log_has(g, "(3단계 미구현) interrogate_discard"), "훅: 3단계 효과는 (3단계 미구현)으로 로그만")
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

	# team_die_set · team_dice_extra_tomorrow · team_dice_reroll_all
	g = _new(CH)
	g.team_dice = [{"value": 3, "owner": 0, "spare_used": false}, {"value": 4, "owner": -1, "spare_used": false}]
	g.players[0]["die_raw"] = 3
	g.players[0]["die"] = 3
	_fx(g, 0, [{"op": "team_die_set"}])
	_answer(g, 0)
	_answer(g, 6)
	ok(g.team_dice[0]["value"] == 6 and g.players[0]["die"] == 6 and g.players[0]["die_raw"] == 6, "op team_die_set: 고른 주사위가 원하는 눈이 되고 가진 사람의 값도 바뀜")
	_fx(g, 0, [{"op": "team_dice_extra_tomorrow", "count": 1}, {"op": "team_dice_reroll_all", "when": "tomorrow"}])
	ok(g.dice_extra_tomorrow == 1 and g.dice_reroll_tomorrow, "op team_dice_extra_tomorrow · team_dice_reroll_all(tomorrow): 내일로 미룸")
	g._begin_morning(false)
	while g.phase == "choice":
		_answer(g, g.pending["options"][0]["value"])
	ok(g.team_dice.size() == 4 + int(g.data.rules["team_dice_extra"]) + 1 and not g.dice_reroll_tomorrow and _log_has(g, "팀 주사위를 전부 다시 굴렸습니다"), "다음 날 아침: 주사위가 하나 늘고 전부 다시 굴림")
	g = _new(CH)
	g.team_dice = [{"value": 3, "owner": -1, "spare_used": false}, {"value": 4, "owner": -1, "spare_used": false}]
	_fx(g, 0, [{"op": "team_dice_reroll_all"}])
	ok(_log_has(g, "팀 주사위를 전부 다시 굴렸습니다"), "op team_dice_reroll_all: 지금 전부 다시 굴림")

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
	var gd := GameDataV2.load_default()
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
