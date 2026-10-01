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
	_run_3_tests()
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
		# 3단계: 무작위로 받은 사연·심문 카드는 치운다 (시험이 필요한 만큼 직접 꾸민다)
		q["sagas"] = []
		q["saga_done"] = ""
		q["saga_kept"] = ""
		q["saga_track"] = {}
		q["interro"] = []
		q["traitor"] = false
		q["jailed_day"] = -99
	g.saga_rewards = []
	g.traitor_id = -1
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
	ok(g.players[0]["interro"].size() == 1 and g.players[1]["interro"].is_empty(), "위협 회유 공작: 고립된 요원이 심문 카드 1장")

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
	g.players[1]["interro"] = ["held", "shaken"]
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.players[1]["interro"].size() == 1, "능력 연락망: 3칸 안 동료의 심문 카드 1장 설득")
	_cov("ability", "jeong")
	g = _new(["jeong", "han", "oh", "seo"])
	g.players[3]["pos"] = Vector2i(9, 9)
	g.players[3]["interro"] = ["held"]
	g.players[1]["interro"] = ["held"]
	_turn(g, 0, 2)
	ok(not g.can_use_ability(g.players[0], 3) and g.can_use_ability(g.players[0], 1), "능력 연락망: 3칸 밖 동료는 안 됨")
	g = _new(["seo", "han", "oh", "park"])
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[1]["interro"] = ["held"]
	g.players[2]["interro"] = ["held"]
	_turn(g, 0, 2)
	ok(not g.can_use_ability(g.players[0], 1) and g.can_use_ability(g.players[0], 2), "능력 다방 밀담: 같은 칸 동료만")
	ok(g.apply({"type": "ability", "player": 0, "target": 2}) and g.pending.get("kind", "") == "persuade_look", "능력 다방 밀담: 쓰면 카드를 보고 버릴지 묻는다")
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
	g.players[0]["interro"] = ["held", "shaken"]
	_fx(g, 0, [{"op": "persuade", "range": 3, "mode": "random"}, {"op": "interrogate_discard", "who": "self", "count": 1, "mode": "random"}])
	ok(g.players[0]["interro"].size() == 1, "효과 persuade(대상 없음)는 아무 일 없고 interrogate_discard는 1장을 버림")
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


# ================================================================== 3단계: 개인 사연 · 심문 · 설득 · 변절

func _run_3_tests() -> void:
	_test_saga_deal()
	_test_saga_cards()
	_test_saga_boundaries()
	_test_grant_scope()
	_test_interrogation()
	_test_persuasion()
	_test_launch_moment()
	_test_traitor_check()
	_test_traitor_turn()
	_test_traitor_day()
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
	g.apply({"type": "end_move", "player": pid})


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
		g.apply({"type": "end_move", "player": pid})


func _day_with(g: RulesV2, dice: Array, picks: Dictionary) -> void:
	## 아침 계획을 꾸며 하루를 시작한다. picks: {요원 id: 주사위 인덱스}, 나머지 요원은 남은 주사위를 아무거나
	g.phase = "plan"
	g.team_dice = []
	for v in dice:
		g.team_dice.append({"value": v, "owner": -1, "spare_used": false})
	for q in g.players:
		q["die"] = -1
		q["die_raw"] = -1
		q["done_today"] = false
	var used := []
	for pid in picks:
		used.append(picks[pid])
	for q in g.players:
		if q["jailed"] or picks.has(q["id"]):
			continue
		for i in dice.size():
			if not i in used:
				picks[q["id"]] = i
				used.append(i)
				break
	for pid in picks:
		g.apply({"type": "take_die", "player": pid, "die": picks[pid]})
	g.apply({"type": "start_day", "player": 0})


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
	ok(g2.interro_deck.size() == 12, "심문 덱: 12장")

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
	var gd := GameDataV2.load_default()
	# 어머니의 소식: 종로경찰서 3칸 안, 쫓기지 않고 차례를 마침
	var g := _new(CH)
	_give(g, 0, ["mother"])
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
	ok(g.players[0]["saga_done"] == "mother" and g.dice_extra_tomorrow == 1, "사연 어머니의 소식: 3칸 안에서 쫓기지 않고 마치면 이룸, 다음 날 팀 주사위 +1")
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
	g.apply({"type": "end_move", "player": 0})
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
	_turn(g, 0, 2)
	g.apply({"type": "give_item", "player": 0, "index": 0, "to": 1})
	ok(g.players[1]["saga_done"] == "financier", "사연 자금책: 동료가 건넨 아이템도 센다")

	# 노름꾼: 굴린 눈 6을 가져간 날 세 번. 내려놓고 다시 가져가도 하루 1번
	g = _new(CH)
	_give(g, 0, ["gambler"])
	g.phase = "plan"
	g.team_dice = [{"value": 6, "owner": -1, "spare_used": false}, {"value": 6, "owner": -1, "spare_used": false},
		{"value": 2, "owner": -1, "spare_used": false}, {"value": 3, "owner": -1, "spare_used": false}, {"value": 4, "owner": -1, "spare_used": false}]
	g.apply({"type": "take_die", "player": 0, "die": 0})
	g.apply({"type": "release_die", "player": 0})
	g.apply({"type": "take_die", "player": 0, "die": 1})
	for i in range(1, 4):
		g.apply({"type": "take_die", "player": i, "die": i + 1})
	g.apply({"type": "start_day", "player": 0})
	ok(g.saga_progress(0)["gambler"] == {"have": 1, "need": 3}, "사연 노름꾼: 6을 내려놓고 다시 가져가도 그날은 1번")
	_day_with(g, [6, 1, 2, 3, 4], {0: 0})
	ok(g.saga_progress(0)["gambler"]["have"] == 2, "사연 노름꾼: 다음 날 6을 가져가면 2번")
	g.players[0]["jailed"] = true
	_day_with(g, [6, 1, 2, 3, 4], {0: 0})
	ok(g.saga_progress(0)["gambler"]["have"] == 2 and g.players[0]["die"] == -1, "사연 노름꾼: 갇혀서 예비로 돌린 주사위는 세지 않음")
	g.players[0]["jailed"] = false
	_day_with(g, [6, 1, 2, 3, 4], {0: 0})
	ok(g.players[0]["saga_done"] == "gambler" and g.pending.get("kind", "") == "pick_die", "사연 노름꾼: 세 번째에 이루고 바꿀 주사위를 고른다")
	_answer(g, 1)
	ok(g.pending["kind"] == "pick_value", "사연 노름꾼: 주사위를 고르면 원하는 눈을 묻는다")
	_answer(g, 4)
	ok(g.team_dice[1]["value"] == 4 and g.phase == "day", "사연 노름꾼: 팀 주사위를 원하는 눈으로 바꿈")
	_cov("saga", "gambler")

	# 욕심 없는 사람: 가장 작은 눈 (같은 눈이 여럿이어도 센다)
	g = _new(CH)
	_give(g, 0, ["no_greed"])
	_give(g, 1, ["no_greed"])
	for d in 3:
		_day_with(g, [1, 1, 3, 4, 5], {0: 0, 1: 1})
	ok(g.saga_progress(0)["no_greed"]["have"] == 3 and g.saga_progress(1)["no_greed"]["have"] == 3, "사연 욕심 없는 사람: 같은 가장 작은 눈이 둘이면 둘 다 센다")
	_day_with(g, [2, 3, 3, 4, 5], {0: 3, 1: 0})   # 0번은 가장 작지 않은 눈, 1번은 가장 작은 눈
	ok(g.players[0]["saga_done"] == "" and g.players[1]["saga_done"] == "no_greed" and g.dice_reroll_tomorrow, "사연 욕심 없는 사람: 네 번째에 이루고 내일 팀 주사위를 전부 다시 굴림")
	_cov("saga", "no_greed")

	# 약속의 반지: 결행 순간 아이템 2장 이상
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["ring"])
	g.players[0]["items"] = ["telegram", "pocket_watch"]
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.players[0]["saga_done"] == "ring" and g.phase == "over", "사연 약속의 반지: 결행 순간 아이템 2장이면 이룸")
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
	for reason in ["jail", "traitor"]:
		g.police[0] = {"pos": Vector2i(0, 10), "summon_turn": 99}
		g._police_off(0, reason)
	ok(g.saga_progress(0)["nemesis"]["have"] == 0, "사연 원수: 투옥·변절로 쫓기를 그만두는 것은 세지 않음")
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
	g.police[1] = {"pos": Vector2i(5, 6), "summon_turn": 0}
	_turn(g, 0, 2)
	g.apply({"type": "decoy", "player": 0, "from": 1})
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
	_walk(g, 0, b0 + Vector2i(1, 0), b0)
	ok(g.players[0]["saga_done"] == "cellmate" and g._grant_index(g.players[0], "escape_instant") >= 0, "사연 옥중 동지: 갇힌 다음 날 안에 구출하면 이루고, 다음 투옥 때 바로 탈출 권리")
	var gde := _gd(func(d): d.rules["checks"]["escape"] = 0)
	g = _new(CH, gde)
	_give(g, 0, ["cellmate"])
	for k in 2:
		g.players[0]["jailed"] = true
		g.players[0]["pos"] = b0
		g.players[0]["done_today"] = false
		_turn(g, 0, 1)
		g.apply({"type": "escape", "player": 0})
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
	ok(g.players[0]["saga_done"] == "sworn_brother" and g._grant_index(g.players[0], "persuade_double") >= 0, "사연 의형제: 같은 동료와 세 번이면 이루고 설득 2장 권리")
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
	_turn(g, 0, 3)
	for k in 2:
		g.players[0]["items"] = ["telegram"]
		g.players[1]["items"] = []
		g.players[0]["item_uses"] = 0
		g.apply({"type": "give_item", "player": 0, "index": 0, "to": 1})
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
	var gd := GameDataV2.load_default()
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

	# 이룸: 공개 알림과 심문 면역
	g = _new(CH)
	_give(g, 0, ["mother", "secret_letter"])
	g.players[0]["interro"] = ["held", "shaken"]
	var discarded: int = g.interro_discard.size()
	g._saga_complete(g.players[0], "secret_letter")
	var pub := false
	for e in g.events:
		if e["kind"] == "saga_done" and e["player"] == 0 and e["id"] == "secret_letter" and not e.has("secret"):
			pub = true
	ok(pub and g.players[0]["saga_done"] == "secret_letter" and "mother" in g.saga_discard, "사연 이룸: 공개 알림, 다른 카드는 버림")
	ok(g.players[0]["interro"].is_empty() and g.interro_discard.size() == discarded + 2, "사연 이룸: 들고 있던 심문 카드를 모두 버림")
	g._jail(g.players[0])
	ok(g.players[0]["interro"].is_empty(), "사연 이룸: 이후 투옥되어도 심문 카드를 받지 않음 (심문 면역)")
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
	_day_with(g, [6, 1, 2, 3, 4], {0: 0})
	ok(g.phase == "choice" and g.pending["kind"] == "pick_die", "사연: 하루를 시작할 때 이뤄 선택이 끼면 멈춤")
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


# ------------------------------------------------------------------ 심문 카드

func _test_interrogation() -> void:
	var g := _new(CH)
	g.interro_deck = ["held", "shaken"]
	g.day = 3
	g._jail(g.players[0])
	ok(g.players[0]["interro"] == ["shaken"] and g.players[0]["jailed_day"] == 3, "심문: 투옥되면 카드 1장을 받고 갇힌 날을 적음")
	var pub := false
	var sec := false
	for e in g.events:
		if e["kind"] == "interrogation" and e["player"] == 0 and e["count"] == 1 and not e.has("card"):
			pub = true
		if e["kind"] == "interrogation_card" and e["player"] == 0 and e.get("secret", false) and e["card"] == "shaken":
			sec = true
	ok(pub and sec, "심문: 장수는 공개 알림, 카드 내용은 secret 알림")
	ok(g.interrogation_count(0) == 1 and g.shaken_count(0) == 1 and g._cond_holds(g.players[0], "has_interrogation") and not g._cond_holds(g.players[1], "has_interrogation"), "심문: interrogation_count·shaken_count·has_interrogation")

	var g3 := _new(["park", "han", "oh"])
	g3._jail(g3.players[0])
	ok(g3.players[0]["interro"].is_empty() and g3.players[0]["jailed_day"] == g3.day, "심문: 3인 판에서는 카드를 받지 않음 (갇힌 날은 적음)")
	var g2 := _new(["park", "han"])
	g2._jail(g2.players[0])
	ok(g2.players[0]["interro"].is_empty(), "심문: 2인 판에서도 받지 않음")

	g = _new(CH)
	g.players[0]["saga_done"] = "mother"
	g._jail(g.players[0])
	ok(g.players[0]["interro"].is_empty(), "심문: 사연을 이룬 요원은 받지 않음")
	g.traitor_id = 3
	g._jail(g.players[1])
	ok(g.players[1]["interro"].is_empty(), "심문: 이미 변절자가 나왔으면 아무도 받지 않음")
	g = _new(CH)
	g.interro_deck = []
	g.interro_discard = []
	g._jail(g.players[0])
	ok(g.players[0]["interro"].is_empty(), "심문: 덱과 버린 더미가 모두 비면 받지 않음")
	g.interro_discard = ["held", "held"]
	g._jail(g.players[0])
	ok(g.players[0]["interro"] == ["held"] and g.interro_discard.is_empty() and g.interro_deck.size() == 1, "심문: 덱이 비면 버린 더미를 섞어 씀")

	# 「회유 공작」 대상: 고립된 요원, 사연을 이룬 요원은 뺌, 변절자는 늘 뺌
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[0]["saga_done"] = "mother"
	_threat(g, "persuasion_plot")
	ok(g.players[0]["interro"].is_empty() and g.phase == "choice" and g.pending["kind"] == "pick_player" and g.pending["player"] == g.leader, "회유 공작: 사연을 이룬 요원은 빼고, 동점이면 리더가 고름")
	_answer(g, 2)
	ok(g.players[2]["interro"].size() == 1 and g.players[1]["interro"].is_empty(), "회유 공작: 리더가 고른 요원이 심문 카드 1장")
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[0]["traitor"] = true
	g.traitor_id = 0
	_threat(g, "persuasion_plot")
	ok(g.players[0]["interro"].is_empty(), "회유 공작: 변절자는 늘 뺌")
	g = _new(CH)
	g.players[0]["pos"] = Vector2i(2, 2)
	g.players[0]["jailed"] = true
	_threat(g, "persuasion_plot")
	ok(g.players[0]["interro"].size() == 1, "회유 공작: 감옥에 있는 요원도 대상 (include_jailed)")

	# 이벤트 「옛 동지와의 재회」: 심문 카드가 있으면 1장 버림, 없으면 아이템
	g = _new(CH)
	g.players[0]["interro"] = ["held", "shaken"]
	_event(g, 0, "old_comrade")
	ok(g.players[0]["interro"].size() == 1 and g.players[0]["items"].is_empty(), "이벤트 옛 동지와의 재회: 심문 카드가 있으면 1장을 버림 (interrogate_discard)")
	var evs := []
	for e in g.events:
		if e["kind"] == "interrogation_discard":
			evs.append(e)
	ok(evs.size() == 1 and evs[0].get("secret", false) and evs[0]["cards"].size() == 1, "이벤트 옛 동지와의 재회: 버린 카드 내용은 secret 알림")
	g = _new(CH)
	g.players[0]["interro"] = ["held", "held"]
	_fx(g, 0, [{"op": "interrogate_discard", "who": "self", "count": 5, "mode": "random"}])
	ok(g.players[0]["interro"].is_empty() and g.interro_discard.size() >= 2, "효과 interrogate_discard: 모자라면 있는 만큼만")

	# 4인이 아니면 효과가 아무 일도 안 함
	g3 = _new(["park", "han", "oh"])
	_fx(g3, 0, [{"op": "interrogate", "who": "self"}])
	ok(g3.players[0]["interro"].is_empty(), "효과 interrogate: 3인 판에서는 카드를 받지 않음")


# ------------------------------------------------------------------ 설득

func _test_persuasion() -> void:
	var g := _new(CH)
	g.players[1]["interro"] = ["held", "shaken", "held"]
	_spare(g, 3)
	_spare(g, 5)
	_turn(g, 0, 2)
	var legal := g.legal_actions()
	var found := 0
	for a in legal:
		if a["type"] == "use_spare" and a["use"] == "persuade":
			found += 1
			if a["target"] != 1:
				found += 100
	ok(found == 2 and g.persuade_targets(g.players[0]) == [1], "설득: 같은 칸 동료에게 예비 주사위마다 설득 액션이 나옴")
	ok(not g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "persuade"}) and not g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "persuade", "target": 2}), "설득: 대상이 없거나 심문 카드가 없는 동료는 거부")
	var dis: int = g.interro_discard.size()
	ok(g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "persuade", "target": 1}), "설득: 예비 주사위로 설득")
	ok(g.players[1]["interro"].size() == 2 and g.interro_discard.size() == dis + 1 and g.team_dice[0]["spare_used"], "설득: 심문 카드 1장이 버려지고 주사위가 쓰임")
	ok(not g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "persuade", "target": 1}), "설득: 쓴 예비 주사위는 못 씀 (하루 한 번)")
	var pe := {}
	var sec := false
	for e in g.events:
		if e["kind"] == "persuade":
			pe = e
		if e["kind"] == "persuade_cards" and e.get("secret", false) and e["player"] == 1:
			sec = true
	ok(pe.get("player", -1) == 0 and pe.get("target", -1) == 1 and pe.get("discarded", -1) == 1 and sec, "설득: 알림 persuade(공개)와 버린 카드 내용(secret)")
	ok(g.apply({"type": "use_spare", "player": 0, "die": 1, "use": "persuade", "target": 1}) and g.players[1]["interro"].size() == 1, "설득: 다른 예비 주사위로 한 번 더")
	ok(g.persuade_targets(g.players[0]) == [1], "설득: 카드가 남은 동료는 계속 대상")

	# 거리: 옆 칸은 안 됨 / 감옥 면회는 됨 / 변절자·갇힌 본인은 안 됨
	g = _new(CH)
	g.players[1]["interro"] = ["held"]
	g.players[1]["pos"] = Vector2i(5, 6)
	_spare(g, 3)
	_turn(g, 0, 2)
	ok(g.persuade_targets(g.players[0]).is_empty(), "설득: 옆 칸 동료는 안 됨 (rules.persuade.range 0)")
	var gr := _gd(func(d): d.rules["persuade"]["range"] = 1)
	var g1 := _new(CH, gr)
	g1.players[1]["interro"] = ["held"]
	g1.players[1]["pos"] = Vector2i(5, 6)
	_spare(g1, 3)
	_turn(g1, 0, 2)
	ok(g1.persuade_targets(g1.players[0]) == [1], "설득: rules.persuade.range를 1로 바꾸면 옆 칸도 됨")
	g = _new(CH)
	var b0 := _base(g, "barracks")
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = b0
	g.players[1]["interro"] = ["shaken"]
	g.players[0]["pos"] = b0
	_spare(g, 4)
	_turn(g, 0, 2)
	ok(g.persuade_targets(g.players[0]) == [1], "설득: 그 거점 칸에 서면 감옥에 있는 동료도 같은 칸 (면회)")
	g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "persuade", "target": 1})
	ok(g.players[1]["interro"].is_empty(), "설득: 면회로 감옥의 동료 심문 카드를 버림")
	g = _new(CH)
	g.players[1]["interro"] = ["held"]
	g.players[1]["traitor"] = true
	g.traitor_id = 1
	_spare(g, 3)
	_turn(g, 0, 2)
	ok(g.persuade_targets(g.players[0]).is_empty(), "설득: 변절자는 대상이 아님")
	g = _new(CH)
	g.players[1]["interro"] = ["held"]
	g.players[0]["jailed"] = true
	_spare(g, 3)
	_turn(g, 0, 2)
	ok(g.persuade_targets(g.players[0]).is_empty(), "설득: 갇힌 요원은 설득하지 못함")
	_persuade_off_three()

	# 능력 「연락망」: 심문 카드가 있는 동료만 대상
	g = _new(["jeong", "han", "oh", "seo"])
	g.players[1]["pos"] = Vector2i(5, 7)
	_turn(g, 0, 2)
	ok(g.ability_targets(g.players[0]).is_empty(), "능력 연락망: 심문 카드를 가진 동료가 없으면 쓸 수 없음")
	g.players[1]["interro"] = ["held"]
	g.players[3]["interro"] = ["held"]
	g.players[3]["pos"] = Vector2i(5, 9)
	ok(g.ability_targets(g.players[0]) == [1], "능력 연락망: 3칸 안이고 카드가 있는 동료만")

	# 능력 「다방 밀담」: 보고, 버리거나 돌려줌
	g = _new(["seo", "han", "oh", "park"])
	g.players[1]["interro"] = ["held", "shaken"]
	_turn(g, 0, 2)
	ok(g.apply({"type": "ability", "player": 0, "target": 1}) and g.phase == "choice" and g.pending["kind"] == "persuade_look", "능력 다방 밀담: 대상의 카드 1장을 보고 버릴지 묻는다")
	var names := []
	for c in g.data.interrogation["cards"]:
		names.append(c["name"])
	var prompt := str(g.pending["prompt"])
	ok(g.pending.get("secret", false) and names.any(func(n): return n in prompt), "능력 다방 밀담: 프롬프트에 카드 이름이 있어 pending은 secret")
	ok(g.pending["options"] == [{"value": true, "label": "버린다"}, {"value": false, "label": "돌려준다"}], "능력 다방 밀담: 선택지는 버린다/돌려준다")
	var legal2 := g.legal_actions()
	ok(legal2.size() == 2 and legal2[0]["type"] == "choose", "능력 다방 밀담: 선택 중 합법 액션은 답 둘")
	_answer(g, false)
	ok(g.players[1]["interro"].size() == 2 and g.phase == "turn", "능력 다방 밀담: 돌려주면 대상 손에 그대로")
	g = _new(["seo", "han", "oh", "park"])
	g.players[1]["interro"] = ["held", "shaken"]
	_turn(g, 0, 2)
	g.apply({"type": "ability", "player": 0, "target": 1})
	var seen_card: String = g.pending["card"]
	_answer(g, true)
	ok(g.players[1]["interro"].size() == 1 and g.interro_discard.has(seen_card) and g.phase == "turn", "능력 다방 밀담: 버리면 그 카드가 버린 더미로")

	# 「의형제」 권리: 다음 설득에서 2장
	g = _new(CH)
	g.players[0]["grants"] = [{"kind": "persuade_double", "value": 1, "scope": "any"}]
	g.players[1]["interro"] = ["held", "shaken", "held", "held"]
	_spare(g, 2)
	_spare(g, 3)
	_turn(g, 0, 2)
	g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "persuade", "target": 1})
	ok(g.players[1]["interro"].size() == 2 and g.players[0]["grants"].is_empty(), "사연 의형제 권리: 설득 한 번에 심문 카드 2장을 버리고 권리를 씀")
	g.apply({"type": "use_spare", "player": 0, "die": 1, "use": "persuade", "target": 1})
	ok(g.players[1]["interro"].size() == 1, "사연 의형제 권리: 권리는 한 번뿐, 다음 설득은 1장")

	# 설득 효과를 거치지 않는 액션은 서로 영향 없음 (이동 예비 주사위는 그대로)
	g = _new(CH)
	_spare(g, 4)
	_turn(g, 0, 1)
	ok(g.apply({"type": "use_spare", "player": 0, "die": 0, "use": "move"}) and g.steps_left == 5, "예비 주사위: 기존 이동 사용은 target 없이 그대로")


func _persuade_off_three() -> void:
	var g3 := _new(["park", "han", "oh"])
	g3.players[1]["interro"] = ["held"]
	_spare(g3, 3)
	_turn(g3, 0, 2)
	ok(g3.persuade_targets(g3.players[0]).is_empty(), "설득: 3인 판에서는 설득 액션이 없음")
	var any := false
	for a in g3.legal_actions():
		if a.get("use", "") == "persuade":
			any = true
	ok(not any, "설득: 3인 판의 합법 액션에 persuade가 없음")


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
	ok(g.phase == "over" and g.players[0]["saga_kept"] == "mother" and g.players[0]["sagas"] == ["mother"] and "secret_letter" in g.saga_discard, "결행 순간: 고른 사연을 남기고 나머지는 버림, 판이 끝남")
	var kept_events := 0
	for e in g.events:
		if e["kind"] == "saga_kept":
			kept_events += 1
			if not e.get("secret", false):
				kept_events += 100
	ok(kept_events == 4 and g.ending["id"] == "launch_stub", "결행 순간: saga_kept 알림(secret)과 launch_stub 결말")
	clone.apply({"type": "choose", "player": 0, "value": "mother"})
	ok(clone.phase == "over" and clone.players[0]["saga_kept"] == "mother" and str(clone.players[3]["sagas"]) == str(g.players[3]["sagas"]), "결행 순간: 선택 중 저장·불러오기한 판도 같은 결말")

	# 이룰 수 있는 카드가 하나면 자동으로
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["sibling_revenge", "mother"])
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.phase == "over" and g.players[0]["saga_kept"] == "mother" and "sibling_revenge" in g.saga_discard, "결행 순간: 군영이 아닌 결행의 「동생의 원수」는 후보에서 빠져 나머지를 자동으로 남김")
	g = _launch_game(CH, "barracks")
	_give(g, 0, ["sibling_revenge", "mother"])
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.phase == "choice" and g.pending["options"].size() == 2, "결행 순간: 목표가 군영이면 「동생의 원수」도 후보")
	_answer(g, "sibling_revenge")
	ok(g.phase == "over" and g.players[0]["saga_kept"] == "sibling_revenge", "결행 순간: 군영 결행에서 「동생의 원수」를 남김")

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
	ok(g.phase == "over" and g.players[0]["saga_kept"] == "mother" and g.players[0]["sagas"] == ["mother"], "결행 순간: 둘 다 못 이루면 새로 뽑아 이룰 수 있는 카드를 남김")
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
	ok(order == [0, 1, 3] and g.phase == "over", "결행 순간: 선택은 요원 번호순 (0, 1, 3번)")

	# 사연을 이룬 요원은 묻지 않음 / 보상 선택이 끼어도 이어짐
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["survivor"])
	_give(g, 1, ["ring"])
	g.players[1]["items"] = ["telegram", "pocket_watch"]
	for i in range(2, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.phase == "over" and g.players[0]["saga_done"] == "survivor" and g.players[1]["saga_done"] == "ring" and g.players[0]["saga_kept"] == "survivor", "결행 순간: 이룬 사연은 곧 남긴 사연")

	# 투표 결행도 같은 순서를 거침 + 동수는 리더
	g = _new(CH)
	g.ready = g.data.rules["launch_min"]
	g.intel["gg"] = 2
	for i in 4:
		_give(g, i, ["last_telegram"])
	_begin_vote(g)
	_vote_all(g, [true, true, false, false])
	ok(g.phase == "over" and g.players[0]["saga_kept"] == "last_telegram", "결행 순간: 투표 결행에서도 사연을 남김")


# ------------------------------------------------------------------ 변절 확인과 돌아섬

func _test_traitor_check() -> void:
	var g := _new(CH)
	g.players[0]["interro"] = ["shaken", "held", "held"]
	g._traitor_check("launch")
	ok(g.traitor_id == -1, "변절 확인: 흔들렸다 1장은 기준 미달")
	g.players[0]["interro"] = ["shaken", "shaken"]
	g._traitor_check("launch")
	ok(g.traitor_id == 0 and g.players[0]["traitor"] and g.is_traitor(0), "변절 확인: 흔들렸다 2장이면 변절 (shaken 필드로 셈)")
	g.players[1]["interro"] = ["shaken", "shaken"]
	g._traitor_check("launch")
	ok(g.traitor_id == 0 and not g.players[1]["traitor"], "변절 확인: 한 판에 변절자는 1명")

	# 동점 처리: 심문 카드 수 → 투옥 횟수 → rng
	g = _new(CH)
	g.players[0]["interro"] = ["shaken", "shaken"]
	g.players[1]["interro"] = ["shaken", "shaken", "held"]
	g._traitor_check("launch")
	ok(g.traitor_id == 1, "변절 동점 1단계: 심문 카드가 가장 많은 사람")
	g = _new(CH)
	g.players[0]["interro"] = ["shaken", "shaken", "held"]
	g.players[1]["interro"] = ["shaken", "shaken", "held"]
	g.players[1]["jail_count"] = 2
	g.players[0]["jail_count"] = 1
	g._traitor_check("launch")
	ok(g.traitor_id == 1, "변절 동점 2단계: 투옥 횟수가 가장 많은 사람")
	var picks := []
	for s in [3, 3, 4, 5]:
		var gg := _new(CH, null, s)
		gg.players[0]["interro"] = ["shaken", "shaken"]
		gg.players[1]["interro"] = ["shaken", "shaken"]
		gg._traitor_check("launch")
		picks.append(gg.traitor_id)
	ok(picks[0] == picks[1] and picks[0] in [0, 1] and picks[2] in [0, 1] and picks[3] in [0, 1], "변절 동점 3단계: rng로 고르고 같은 시드면 같은 사람")
	var seen := {}
	for s in 40:
		var gs := _new(CH, null, 100 + s)
		gs.players[0]["interro"] = ["shaken", "shaken"]
		gs.players[1]["interro"] = ["shaken", "shaken"]
		gs._traitor_check("launch")
		seen[gs.traitor_id] = true
	ok(seen.size() == 2, "변절 동점 3단계: 시드에 따라 두 사람이 모두 뽑힘")
	# 사연을 이룬 요원은 후보가 아님
	g = _new(CH)
	g.players[0]["interro"] = ["shaken", "shaken", "held"]
	g.players[0]["saga_done"] = "mother"
	g.players[1]["interro"] = ["shaken", "shaken"]
	g._traitor_check("launch")
	ok(g.traitor_id == 1, "변절 확인: 사연을 이룬 요원은 후보에서 뺌")
	# 3인에서는 꺼짐
	var g3 := _new(["park", "han", "oh"])
	g3.players[0]["interro"] = ["shaken", "shaken"]
	g3._traitor_check("launch")
	ok(g3.traitor_id == -1, "변절 확인: 3인 판에서는 꺼져 있음")
	# 아침: 1막은 아무것도 안 하고 2막에서만
	g = _new(CH)
	g.players[0]["interro"] = ["shaken", "shaken"]
	g._morning_traitor_check()
	ok(g.traitor_id == -1, "변절 확인: 1막 아침에는 아무것도 하지 않음")
	g.act = 2
	g._morning_traitor_check()
	ok(g.traitor_id == 0, "변절 확인: 2막 아침에 확인")
	# 결행 순간 확인 (끝까지)
	g = _launch_game(CH, "police_hq")
	_give(g, 0, ["mother", "secret_letter"])
	g.players[2]["interro"] = ["shaken", "shaken"]
	_give(g, 1, ["last_telegram"])
	_give(g, 2, ["gambler", "nemesis"])
	_give(g, 3, ["last_telegram"])
	g._launch("forced")
	_answer(g, "mother")
	_answer(g, "gambler")
	ok(g.phase == "over" and g.traitor_id == 2 and g.ending.get("traitor", -1) == 2, "변절 확인: 결행 순간(사연 남기기 뒤)에 변절자가 정해짐")
	var te := {}
	for e in g.events:
		if e["kind"] == "traitor":
			te = e
	ok(te.get("player", -1) == 2 and te.get("saga", "") == "gambler" and te.get("lure", "") == g.data.saga("gambler")["lure"], "변절: 남긴 사연의 회유 문구가 알림에 담김")
	ok(g.log_lines.any(func(l): return g.data.saga("gambler")["lure"] in str(l) and "돌아섰" in str(l)) and g.history.any(func(h): return "변절" in h["text"]), "변절: 로그와 연표에 회유 문구를 남김")
	ok(g.public_saga(2) == "gambler" and g.players[2]["traitor"], "변절: 사연이 공개됨 (public_saga)")


func _test_traitor_turn() -> void:
	var g := _new(CH)
	var p: Dictionary = g.players[3]   # 김개똥 (move_min3)
	var b0 := _base(g, "barracks")
	_give(g, 3, ["gambler", "mother"])
	p["saga_kept"] = "mother"
	p["jailed"] = true
	p["pos"] = b0
	p["bombs"] = 1
	p["items"] = ["telegram", "pocket_watch"]
	p["interro"] = ["shaken", "shaken"]
	p["grants"] = [{"kind": "evade_auto", "value": 1, "scope": "any"}]
	g.police[3] = {"pos": Vector2i(5, 5), "summon_turn": 0}
	var supply: int = g.bomb_supply
	var idis: int = g.item_discard.size()
	var sdis: int = g.interro_discard.size()
	ok(g.stat(p, "move_min3") > 0, "변절 전: 김개똥의 특성이 있음")
	g._turn_traitor(p, "launch")
	ok(p["traitor"] and g.traitor_id == 3 and not p["jailed"] and p["pos"] == b0, "돌아섬: 감옥에서 풀려나고 자리는 그 거점 칸")
	ok(not g.police.has(3), "돌아섬: 쫓던 경찰이 사라짐")
	ok(p["bombs"] == 0 and g.bomb_supply == supply + 1, "돌아섬: 들고 있던 폭탄은 보급으로")
	ok(p["items"].is_empty() and g.item_discard.size() == idis + 2, "돌아섬: 아이템은 버린 더미로")
	ok(p["interro"].is_empty() and g.interro_discard.size() == sdis + 2 and p["grants"].is_empty(), "돌아섬: 심문 카드와 한 번 쓰는 권리를 내려놓음")
	ok(g.stat(p, "move_min3") == 0 and not g.flag(p, "move_min3"), "돌아섬: 특성 값이 0 (stat·flag)")
	ok(g.ability_targets(p).is_empty() and g.can_use_item(p, 0) == false, "돌아섬: 능력과 아이템을 쓸 수 없음")
	var te := {}
	for e in g.events:
		if e["kind"] == "traitor":
			te = e
	ok(te.get("lure", "") == g.data.saga("mother")["lure"] and te.get("saga", "") == "mother", "돌아섬: 남긴 사연의 회유 문구 (알림)")
	ok(g.log_lines.any(func(l): return str(l).begins_with("\"" + g.data.saga("mother")["lure"] + "\" — ") and "돌아섰습니다" in str(l)), "돌아섬: 회유 문구 — 이름이 돌아섰습니다!")
	# 경찰은 변절자를 쫓지 않음
	g._summon(p)
	_fx(g, 3, [{"op": "police_attach", "who": "self"}])
	ok(not g.police.has(3), "돌아섬: 경찰이 변절자에게 붙지 않음 (_summon, police_attach)")
	g._dispatch_from(0)
	ok(g.police.size() == 1 and not g.police.has(3), "돌아섬: 출동한 경찰은 변절자가 아닌 요원을 쫓음")
	g.police.clear()
	for i in 3:
		g.players[i]["jailed"] = true
	g._dispatch_from(1)
	ok(g.police.is_empty(), "돌아섬: 남은 요원이 변절자뿐이면 출동해도 쫓을 사람이 없음")
	# 사연을 남기지 않은 변절자는 첫 장
	g = _new(CH)
	_give(g, 1, ["nemesis", "supply_line"])
	g._turn_traitor(g.players[1], "morning")
	ok(g.public_saga(1) == "nemesis", "돌아섬: 남긴 사연이 없으면 들고 있던 첫 장의 회유 문구")
	# 투표에서는 빠진다
	ok(g._next_voter(-1) == 0 and g._next_voter(0) == 2 and g._next_voter(3) == -1, "변절자는 투표하지 않음 (_next_voter)")


func _test_traitor_day() -> void:
	var g := _new(CH)
	g.act = 2
	g.players[3]["traitor"] = true
	g.traitor_id = 3
	ok(not g.can_begin_turn(g.players[3]) and g.can_begin_turn(g.players[0]), "변절자의 하루: 다른 요원이 남았으면 변절자는 차례를 시작할 수 없음")
	var legal := g.legal_actions()
	ok(not legal.any(func(a): return a["type"] == "begin_turn" and a["player"] == 3), "변절자의 하루: legal_actions에도 변절자의 begin_turn이 없음")
	g.players[0]["done_today"] = true
	g.players[1]["done_today"] = true
	ok(not g.apply({"type": "begin_turn", "player": 3}), "변절자의 하루: 둘이 마쳐도 한 명이 남으면 거부")
	g.players[2]["done_today"] = true
	ok(g.can_begin_turn(g.players[3]) and g.apply({"type": "begin_turn", "player": 3}), "변절자의 하루: 변절자가 아닌 요원이 모두 마친 뒤에야 차례 (마지막 차례 강제)")
	g.apply({"type": "end_move", "player": 3})
	ok(g.phase != "turn", "변절자의 하루: 차례를 마칠 수 있음")

	# 아침: 변절자도 팀 주사위 하나를 가져가고, 예비 주사위는 못 씀
	g = _new(CH)
	g.act = 2
	g.players[3]["traitor"] = true
	g.traitor_id = 3
	g.phase = "plan"
	for v in [1, 2, 4, 6, 3]:
		_spare(g, v)
	g.apply({"type": "take_die", "player": 3, "die": 0})
	ok(g.players[3]["die"] == 1 and g.players[3]["die_raw"] == 1, "변절자의 하루: 아침에 팀 주사위를 가져가며 김개똥 특성(1→3)은 없음")
	g.phase = "day"
	_turn_noprep(g, 3)
	ok(not g.spare_dice().is_empty() and not g.legal_actions().any(func(a): return a["type"] == "use_spare"), "변절자의 하루: 예비 주사위를 쓸 수 없음")

	# 이미 깔린 칸으로만, 검문 없이, 칸 효과 없이
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	var t: Dictionary = g.players[3]
	_lay(g, [Vector2i(5, 6)], "event")
	_tile(g, Vector2i(6, 5), "check")
	_tile(g, Vector2i(4, 5), "supply")
	_turn_traitor_day(g, 3, 4)
	var steps: Array = g.legal_steps(t)
	ok(Vector2i(5, 6) in steps and Vector2i(6, 5) in steps and Vector2i(4, 5) in steps and steps.size() == 3, "변절자의 하루: 깔린 칸으로만 갈 수 있음 (빈 칸으로는 안 감)")
	var tile_before: int = g.tile_deck.size()
	var ev_before: int = g.event_deck.size()
	ok(_step(g, 3, Vector2i(6, 5)), "변절자의 하루: 검문소에도 들어감")
	ok(_count_dice(g, "회피") == 0 and g.exposure == 0 and t["pos"] == Vector2i(6, 5) and g.phase == "turn", "변절자의 하루: 검문 판정이 없음")
	_tile(g, Vector2i(6, 5), "normal")
	g.board[Vector2i(5, 6)]["type"] = "event"
	t["pos"] = Vector2i(5, 5)
	_step(g, 3, Vector2i(5, 6))
	g.apply({"type": "end_move", "player": 3})
	ok(g.event_deck.size() == ev_before and not g.board[Vector2i(5, 6)]["used"] and g.tile_deck.size() == tile_before, "변절자의 하루: 이벤트 칸 효과를 받지 않고 새 타일도 깔지 않음")
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	_tile(g, Vector2i(5, 6), "supply")
	_turn_traitor_day(g, 3, 3)
	_step(g, 3, Vector2i(5, 6))
	g.apply({"type": "end_move", "player": 3})
	ok(g.players[3]["bombs"] == 0 and g.bomb_supply == int(g.data.rules["bomb_supply"]), "변절자의 하루: 보급 칸에서 폭탄을 받지 않음")
	# 거점: 진입 효과·구출·경찰 없음
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	var b0 := _base(g, "barracks")
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = b0
	g.players[3]["pos"] = b0 + Vector2i(1, 0)
	_tile(g, b0 + Vector2i(1, 0), "normal")
	g.mission_row = []
	_turn_traitor_day(g, 3, 3)
	_step(g, 3, b0)
	ok(g.players[1]["jailed"] and not g.police.has(3) and g.players[3]["pos"] == b0, "변절자의 하루: 거점에 들어가도 구출·진입 효과·경찰이 없음")
	ok(g.phase == "turn" and g.steps_left == 2, "변절자의 하루: 거점 진입으로 이동이 끝나지는 않음 (칸 효과 없음)")
	# 미션 타일
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	var amis := ""
	for m in g.data.missions["missions"]:
		if m["type"] == "assassin":
			amis = m["id"]
			break
	g.mission_row = [amis]
	_tile(g, Vector2i(5, 6), "assassin")
	_turn_traitor_day(g, 3, 3)
	_step(g, 3, Vector2i(5, 6))
	ok(g.phase == "turn" and g.mission_row == [amis] and g.check.is_empty(), "변절자의 하루: 미션 타일에서 판정도 미션도 없음")

	# 기습: 요원이 있는 칸에 들어가면 이동이 끝나고 그 요원이 회피 판정, 실패하면 투옥 (심문 카드 없음)
	var gfail := _gd(func(d): d.rules["checks"]["evade"] = 99)
	g = _traitor_game(["park", "han", "oh", "gaeddong"], gfail)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(5, 6)
	_turn_traitor_day(g, 3, 4)
	_step(g, 3, Vector2i(5, 6))
	ok(g.players[1]["jailed"] and g.players[1]["jail_count"] == 1 and g.players[1]["interro"].is_empty(), "기습 실패: 요원이 투옥되고 이미 변절자가 있으므로 심문 카드는 받지 않음")
	ok(g.phase != "turn" and _count_dice(g, "회피") == 1, "기습: 이동이 끝나고(남은 칸 버림) 회피 판정 한 번")
	var gok := _gd(func(d): d.rules["checks"]["evade"] = 0)
	g = _traitor_game(["park", "han", "oh", "gaeddong"], gok)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(5, 6)
	_turn_traitor_day(g, 3, 4)
	_step(g, 3, Vector2i(5, 6))
	ok(not g.players[1]["jailed"] and g.phase != "turn", "기습 성공(회피): 요원은 무사하고 변절자의 차례는 끝남")
	g = _traitor_game(["park", "yun", "oh", "gaeddong"], gfail)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(5, 6)
	_turn_traitor_day(g, 3, 4)
	_step(g, 3, Vector2i(5, 6))
	ok(not g.players[1]["jailed"] and _count_dice(g, "회피") == 0, "기습: 윤 소위는 회피가 자동 성공")
	g = _traitor_game(["park", "han", "oh", "gaeddong"], gfail)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[1]["grants"] = [{"kind": "evade_auto", "value": 1, "scope": "any"}]
	_turn_traitor_day(g, 3, 4)
	_step(g, 3, Vector2i(5, 6))
	ok(not g.players[1]["jailed"] and g.players[1]["grants"].is_empty(), "기습: 회피 자동 성공 권리가 통함")
	# 같은 칸에 요원이 여럿이면 리더가 대상을 고름
	g = _traitor_game(["park", "han", "oh", "gaeddong"], gfail)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[2]["pos"] = Vector2i(5, 6)
	g.leader = 2
	_turn_traitor_day(g, 3, 4)
	_step(g, 3, Vector2i(5, 6))
	ok(g.phase == "choice" and g.pending["kind"] == "ambush_target" and g.pending["player"] == 2 and g.pending["options"].size() == 2, "기습: 같은 칸에 요원이 여럿이면 리더가 대상을 고름")
	var la := g.legal_actions()
	ok(la.size() == 2 and la[0]["player"] == 2, "기습: 선택 중 합법 액션은 리더의 두 답")
	_answer(g, 1)
	ok(g.players[1]["jailed"] and not g.players[2]["jailed"] and g.phase != "turn", "기습: 고른 요원만 판정을 받음")
	# 변절자는 갇힌 요원이 있는 칸이나 요원이 없는 칸에서는 기습하지 않음
	g = _traitor_game(["park", "han", "oh", "gaeddong"], gfail)
	_tile(g, Vector2i(5, 6), "normal")
	g.players[1]["pos"] = Vector2i(5, 6)
	g.players[1]["jailed"] = true
	_turn_traitor_day(g, 3, 4)
	_step(g, 3, Vector2i(5, 6))
	ok(g.phase == "turn" and _count_dice(g, "회피") == 0, "기습: 갇힌 요원이 있는 칸에서는 기습이 없음")

	# 밀고: 3칸 안, 차례에 한 번, 경찰이 붙음
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	g.players[0]["pos"] = Vector2i(5, 6)
	g.players[1]["pos"] = Vector2i(5, 9)
	g.players[2]["pos"] = Vector2i(5, 8)
	_turn_traitor_day(g, 3, 4)
	ok(g.inform_targets(g.players[3]) == [0, 2], "밀고: 거리 3 안의 요원만 대상 (4칸 밖은 안 됨)")
	ok(not g.apply({"type": "inform", "player": 3, "target": 1}), "밀고: 범위 밖 요원은 거부")
	ok(g.legal_actions().any(func(a): return a["type"] == "inform" and a["target"] == 0), "밀고: legal_actions에 나옴")
	ok(g.apply({"type": "inform", "player": 3, "target": 0}) and g.police.has(0) and g.police[0]["pos"] == g.players[0]["pos"], "밀고: 그 요원에게 경찰이 붙음")
	ok(g.inform_targets(g.players[3]).is_empty() and not g.apply({"type": "inform", "player": 3, "target": 2}), "밀고: 차례에 한 번뿐")
	g._begin_turn(g.players[3])
	ok(g.inform_targets(g.players[3]) == [2], "밀고: 다음 차례에 다시 쓸 수 있고, 이미 쫓기는 요원은 대상이 아님")
	g.police[2] = {"pos": Vector2i(0, 0), "summon_turn": 0}
	ok(g.inform_targets(g.players[3]).is_empty(), "밀고: 이미 경찰이 붙은 요원은 안 됨")
	var gb := _gd(func(d): d.rules["checks"]["evade"] = 0)
	g = _traitor_game(["park", "seo", "oh", "gaeddong"], gb)
	_turn_traitor_day(g, 3, 4)
	g.apply({"type": "inform", "player": 3, "target": 1})
	ok(not g.police.has(1), "밀고: 서 마담의 경찰 막기가 그대로 통함")
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	g.players[1]["jailed"] = true
	_turn_traitor_day(g, 3, 4)
	ok(not 1 in g.inform_targets(g.players[3]), "밀고: 갇힌 요원은 대상이 아님")
	ok(g.inform_targets(g.players[0]).is_empty(), "밀고: 변절자만 쓸 수 있음")

	# 쓸 수 없는 것: 아이템, 건네기, 미끼, 능력, 설득, 예비 주사위
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	g.players[3]["items"] = ["telegram", "pocket_watch"]
	g.police[0] = {"pos": Vector2i(5, 5), "summon_turn": 0}
	g.players[1]["interro"] = ["held"]
	_spare(g, 3)
	_turn_traitor_day(g, 3, 4)
	var types := {}
	for a in g.legal_actions():
		types[a["type"]] = true
	ok(types.keys().all(func(k): return k in ["step", "end_move", "inform"]), "변절자의 하루: 합법 액션은 이동·멈춤·밀고뿐 (%s)" % str(types.keys()))
	ok(not g.apply({"type": "use_item", "player": 3, "index": 0}) and not g.apply({"type": "give_item", "player": 3, "index": 0, "to": 0}) \
		and not g.apply({"type": "decoy", "player": 3, "from": 0}) and not g.apply({"type": "use_spare", "player": 3, "die": 0, "use": "move"}) \
		and not g.apply({"type": "use_spare", "player": 3, "die": 0, "use": "persuade", "target": 1}), "변절자의 하루: 아이템·건네기·미끼·예비 주사위·설득은 거부")
	# 경찰은 변절자의 차례 끝에 움직이지 않는다
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	var pos0: Vector2i = g.players[3]["pos"]
	_turn_traitor_day(g, 3, 2)
	g.apply({"type": "end_move", "player": 3})
	ok(g.police.is_empty() and not g.players[3]["jailed"], "변절자의 하루: 쫓는 경찰이 없으니 차례 끝에 아무 일도 없음")
	# 같은 칸: 변절자는 다른 요원과 같은 칸에 설 수 있고, 다른 요원도 변절자 칸에 들어갈 수 있음
	g = _traitor_game(["park", "han", "oh", "gaeddong"])
	_tile(g, Vector2i(5, 6), "normal")
	_tile(g, Vector2i(5, 7), "normal")
	g.players[0]["pos"] = Vector2i(5, 6)
	g.players[3]["pos"] = Vector2i(5, 7)
	ok(not g.occupied_by_other(g.players[3], Vector2i(5, 6)), "변절자의 하루: 다른 요원과 같은 칸에 설 수 있음")
	ok(g.occupied_by_other(g.players[1], Vector2i(5, 6)) and not g.occupied_by_other(g.players[1], Vector2i(5, 7)), "변절자가 선 칸은 다른 요원의 이동을 막지 않음 (요원이 선 칸은 막음)")


func _traitor_game(chars: Array, gd: GameDataV2 = null) -> RulesV2:
	## 2막 하루: 마지막 요원이 변절자, 나머지는 이미 차례를 마침 (done_today). 변절자의 차례는 _turn_traitor_day로 시작.
	var g := _new(chars, gd)
	g.act = 2
	g.rounds_left = 1   # 변절자의 차례가 끝나면 밤에 판이 끝남 (다음 날 아침 효과가 시험을 흐리지 않게)
	g.players[3]["traitor"] = true
	g.traitor_id = 3
	return g


func _turn_traitor_day(g: RulesV2, pid: int, die: int) -> void:
	for q in g.players:
		if q["id"] != pid:
			q["done_today"] = true
	g.players[pid]["done_today"] = false
	g.players[pid]["die"] = die
	g.players[pid]["die_raw"] = die
	g.phase = "day"
	g.apply({"type": "begin_turn", "player": pid})


func _turn_noprep(g: RulesV2, pid: int) -> void:
	_turn_traitor_day(g, pid, 2)


# ------------------------------------------------------------------ 조회

func _test_stage3_queries() -> void:
	var g := _new(CH)
	_give(g, 0, ["mother", "secret_letter"])
	g.players[0]["interro"] = ["held", "shaken", "shaken"]
	ok(g.interrogation_count(0) == 3 and g.shaken_count(0) == 2 and g.saga_cards(0) == ["mother", "secret_letter"], "조회: interrogation_count · shaken_count · saga_cards")
	ok(g.public_saga(0) == "" and g.saga_result(0) == {"saga": "mother", "done": false, "traitor": false}, "조회: 이루기 전에는 public_saga가 비고 saga_result는 들고 있던 첫 장")
	ok(g.epilogue_key(0, true) == "win_fail" and g.epilogue_key(0, false) == "lose_fail", "조회: 못 이룬 후일담 키")
	g._saga_complete(g.players[0], "secret_letter")
	ok(g.public_saga(0) == "secret_letter" and g.saga_result(0) == {"saga": "secret_letter", "done": true, "traitor": false}, "조회: 이룬 사연은 공개")
	ok(g.epilogue_key(0, true) == "win_done" and g.epilogue_key(0, false) == "lose_done", "조회: 이룬 후일담 키")
	g._turn_traitor(g.players[1], "launch")
	ok(g.epilogue_key(1, true) == "traitor" and g.epilogue_key(1, false) == "traitor" and g.saga_result(1)["traitor"], "조회: 변절자는 늘 traitor 키")
	g = _new(CH)
	_give(g, 0, ["moth", "no_greed"])
	g.players[0]["saga_track"]["moth"] = {"n": 2}
	g.players[0]["items"] = ["telegram"]
	_give(g, 1, ["financier", "sibling_revenge"])
	g.players[1]["items"] = ["telegram", "pocket_watch", "train_ticket"]
	var pr: Dictionary = g.saga_progress(0)
	ok(pr["moth"] == {"have": 2, "need": 3} and pr["no_greed"] == {"have": 0, "need": 4}, "조회: saga_progress {have, need}")
	var pr1: Dictionary = g.saga_progress(1)
	ok(pr1["financier"] == {"have": 3, "need": 3} and pr1["sibling_revenge"] == {"have": 0, "need": 1}, "조회: 아이템 수는 현재 값, 결행 갈래는 0/1")
	# 저장·불러오기: 새 상태가 모두 들어 있음
	g._jail(g.players[2])
	_give(g, 3, ["mother"])
	g._saga_complete(g.players[3], "mother")
	g.traitor_id = 1
	var st: Dictionary = g.save_state()
	var g2 := RulesV2.new()
	g2.load_state(st, g.data)
	ok(str(g2.save_state()) == str(st), "저장: 사연·심문·변절 상태를 저장하고 불러오면 같음")
	for k in ["saga_decks", "saga_discard", "interro_deck", "interro_discard", "traitor_id", "saga_rewards", "launch_step", "launch_i"]:
		ok(st.has(k), "저장: SAVE_FIELDS에 %s" % k)
