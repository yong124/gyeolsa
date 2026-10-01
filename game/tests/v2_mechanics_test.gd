extends SceneTree
## v2 엔진 규칙 하나씩 확인 (2a 몫). 상태를 직접 꾸며 놓고 결과를 본다.
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
	var g := _new(["park", "han", "oh", "seo"])
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
	# 2b 미구현은 로그만 남기고 아무 일도 안 함
	var g6 := _new(["park", "han", "oh", "seo"])
	var before := str(g6.save_state()["players"])
	g6._run_effects(g6.players[0], [{"op": "dice_mod_today", "value": -1}], {"then": "resume"})
	ok(g6.log_lines[-1] == "(2b 미구현) dice_mod_today" and str(g6.save_state()["players"]) == before and g6.today["dice_mod"] == 0, "효과: 2b 미구현 op는 로그만 남기고 아무것도 안 함")
	# 이벤트 효과: 군중 속으로 (쫓기는 중이면 경찰 제거 — 2b의 police_remove는 아직)
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
	ok(g6.apply({"type": "ability", "player": 0}), "능력: 보급 타일 옆 칸이면 씀")


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
