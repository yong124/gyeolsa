extends "res://tests/mechanics/mech_act2.gd"
## 규칙 시험 5층: A단계(변절 뺌) · B단계(주사위 1개 = 행동 1개) · E단계(결행 · 2막)


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
	# 아침 순서: 위협 → 일제 작전 → 표적 이동·기한 → 투표 → 미션 줄 → 주사위. 선택이 끼지 않은 아침은 7에서 끝남
	var gm := _new(CH)
	gm.act = 1
	gm.phase = "morning"
	gm.morning_step = 1
	gm.threat_deck = ["calm_day"]
	gm.ready = 0
	gm._morning_continue()
	ok(gm.morning_step == 7 and gm.phase == "plan" and not gm.op_dice.is_empty(), "아침 순서: 위협 → 일제 작전 → 표적 이동·기한 → 투표 → 미션 줄 → 주사위 여섯 단계 (morning_step 7에서 끝)")


# ------------------------------------------------------------------ B단계: 주사위 1개 = 행동 1개 (11·12단계)

func _run_b_tests() -> void:
	_test_b_action_economy()
	_test_b_cells_and_police_block()
	_test_b_effect_once_per_cell()
	_test_b_walk_distance()
	_test_b_police_summon()
	_test_b_hide()
	_test_b_gives_and_visit()
	_test_b_market_and_misc()
	_test_b_save_resume()


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
	if g.walk_dist(Vector2i(2, 2), near) >= 3:
		ok(g.police.has(0) and g.police[0]["pos"] == near, "경찰 등장: 새로 붙으면 요원에게서 가장 가까운 거점에 나타남")
	else:
		ok(g.police.has(0) and g.walk_dist(Vector2i(2, 2), g.police[0]["pos"]) == 3, "경찰 등장: 거점이 가까우면 3칸 떨어져 나타남")
	# 거점 안에서 붙으면 그 거점이 아니라 3칸 떨어진 칸에 나타난다 (들어가자마자 잡히지 않게)
	var gb := _new(CH)
	_flat(gb)
	var bcell: Vector2i = gb.data.bases[0]
	gb.players[0]["pos"] = bcell
	gb._summon(gb.players[0])
	ok(gb.police.has(0) and gb.police[0]["pos"] != bcell and gb.walk_dist(bcell, gb.police[0]["pos"]) == 3,
		"경찰 등장: 거점 안의 요원에게 붙은 경찰은 3칸 떨어져 나타남")
	ok(gb.police_spawn_cell(Vector2i(0, 0)) == gb.data.bases[gb._nearest_base(Vector2i(0, 0))] 		or gb.walk_dist(Vector2i(0, 0), gb.data.bases[gb._nearest_base(Vector2i(0, 0))]) < 3, "경찰 등장: 먼 요원에게는 거점에서 나타남")
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

func _test_b_market_and_misc() -> void:
	# 면회는 뺐다: 갇힌 요원과는 옆 칸에서도 주사위를 주고받지 않는다 (탈옥은 자기 주사위로)
	var g := _new(CH)
	var base: Vector2i = g.data.bases[2]
	var next: Vector2i = base + Vector2i(0, -1)
	_lay(g, [next])
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = base
	g.players[0]["pos"] = next
	_turn(g, 0, 0)
	_spare(g, 6, 0)
	ok(g.give_die_targets(g.players[0]).is_empty(), "면회 없음: 옆 칸에 와도 갇힌 요원에게 주사위를 건넬 수 없음")
	var gm := g
	# 삭제: 전차 · 보석 · 장터 팔기 (v2에 없음)
	var real := GameDataV2.load_default()
	ok(not real.rules["tiles"].has("tram") and not real.rules["tiles"].has("tram_stop") and not real.rules.has("bail") and not real.rules.has("sell"),
		"삭제: 전차 정류장 타일 · 보석 · 장터 팔기는 데이터에 없음")
	ok(not real.rules["tiles"].has("market") and not real.rules.has("funds") and not real.rules.has("market") and not real.rules.has("checkpoint"),
		"단순화: 장터 타일 · 군자금 · 검문소 뇌물은 데이터에 없음")
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


# ------------------------------------------------------------------ E단계: 결행·2막 (12단계 4·5절)

func _run_e_tests() -> void:
	_test_e_vote()
	_test_e_benefits()
	_test_e_counter()
	_test_e_flag_and_pair()
	_test_e_jail_at_strike()
	_test_e_data()


func _set_intel(g: RulesV2, values: Dictionary) -> void:
	for id in GameDataV2.load_default().base_ids:
		g.intel[id] = int(values.get(id, 0))


func _test_e_vote() -> void:
	# 후보: 첩보 2 이상. 없으면 첩보가 가장 높은 거점(동점이면 모두)
	var g := _new(CH)
	_set_intel(g, {"barracks": 1, "prison": 2, "gg": 3})
	ok(g.launch_candidates() == ["prison", "gg"], "대상 후보: 첩보 2 이상인 거점")
	_set_intel(g, {"barracks": 1, "police_hq": 1})
	ok(g.launch_candidates() == ["barracks", "police_hq"], "대상 후보: 없으면 첩보가 가장 높은 거점 (동점이면 모두)")
	_set_intel(g, {})
	ok(g.launch_candidates().size() == 4, "대상 후보: 첩보가 모두 0이면 네 곳 모두")
	# 투표는 비공개: 모두 낼 때까지 공개하지 않는다
	var g2 := _new(CH)
	g2.leader = 2
	_set_intel(g2, {"prison": 2, "gg": 2})
	g2.ready = int(g2.data.rules["launch_min"])
	g2.phase = "morning"
	g2.morning_step = 2
	g2._morning_continue()
	g2.events.clear()
	ok(g2.pending["kind"] == "launch_vote" and g2.pending.get("secret", false) and g2.pending["player"] == 0, "투표: 먼저 찬반을 묻고 (비공개) 0번부터")
	_answer(g2, true)
	ok(g2.pending["kind"] == "launch_target" and g2.pending["player"] == 0 and g2.pending["options"].map(func(o): return o["value"]) == ["prison", "gg"],
		"투표: 이어서 대상을 묻는다 (후보만 선택지)")
	var revealed := g2.events.any(func(e): return e["kind"] == "vote_reveal")
	_answer(g2, "gg")
	ok(not revealed and g2.pending["player"] == 1 and not g2.events.any(func(e): return e["kind"] == "vote_reveal"), "투표: 한 요원이 내도 다른 요원 표는 공개되지 않음")
	_vote_all(g2, [true, true, false], ["prison", "gg", "gg"])
	var rev: Array = g2.events.filter(func(e): return e["kind"] == "vote_reveal")
	ok(rev.size() == 1 and rev[0]["votes"].size() == 4 and rev[0]["targets"].size() == 4 and not rev[0]["forced"], "투표: 모두 낸 뒤 한꺼니 공개 (vote_reveal에 네 명의 표)")
	ok(g2.act == 2 and g2.launch_info["target"] == "gg", "투표: 과반 찬성이면 결행, 가장 많은 표를 받은 곳(gg 3표)이 대상")
	# 동수(대상 표)는 리더가 정한다
	var g3 := _new(CH)
	g3.leader = 3
	_set_intel(g3, {"prison": 2, "gg": 2})
	g3.ready = int(g3.data.rules["launch_min"])
	g3.phase = "morning"
	g3.morning_step = 2
	g3._morning_continue()
	_vote_all(g3, [true, true, true, true], ["gg", "gg", "prison", "prison"])
	ok(g3.pending["kind"] == "strike_target" and g3.pending["player"] == 3 and g3.pending["options"].size() == 2, "투표: 대상 표가 같으면 리더가 정함")
	_answer(g3, "prison")
	ok(g3.launch_info["target"] == "prison", "투표: 리더가 고른 곳이 대상")
	# 반대가 많으면 결행하지 않지만 표는 공개된다
	var g4 := _new(CH)
	_set_intel(g4, {"prison": 2})
	g4.ready = int(g4.data.rules["launch_min"])
	g4.phase = "morning"
	g4.morning_step = 2
	g4._morning_continue()
	g4.events.clear()
	_vote_all(g4, [true, false, false, false])
	ok(g4.act == 1 and g4.phase == "plan" and g4.events.any(func(e): return e["kind"] == "vote_reveal") and g4.vote_state.is_empty(), "투표: 반대가 많으면 결행하지 않음 (표는 공개, 아침이 이어짐)")
	# 강제 결행: 찬반 없이 대상만
	var g5 := _new(CH)
	g5.rounds_left = int(g5.data.rules["forced_launch_days_left"])
	_set_intel(g5, {"prison": 3, "gg": 3, "police_hq": 1})
	g5.phase = "morning"
	g5.morning_step = 2
	g5._morning_continue()
	var kinds := []
	var guard := 0
	while g5.phase == "choice" and g5.pending.get("kind") == "launch_target" and guard < 10:
		kinds.append(g5.pending["kind"])
		_answer(g5, "gg")
		guard += 1
	ok(kinds.size() == 4 and g5.act == 2 and g5.launch_info["reason"] == "forced" and g5.launch_info["target"] == "gg", "투표: 강제 결행은 찬반 없이 대상 투표만 (네 명 모두)")
	# 연습 모드: 사람이 먼저 내고 AI 표와 함께 공개된다
	var gh := _new(CH)
	gh.human = 2
	_set_intel(gh, {"prison": 2, "gg": 2})
	gh.ready = int(gh.data.rules["launch_min"])
	gh.phase = "morning"
	gh.morning_step = 2
	gh._morning_continue()
	var order := []
	var gd2 := 0
	while gh.phase == "choice" and gh.pending.get("kind") in ["launch_vote", "launch_target"] and gd2 < 20:
		gd2 += 1
		if not gh.pending["player"] in order:
			order.append(gh.pending["player"])
		_answer(gh, gh.pending["options"][0]["value"])
	ok(order == [2, 0, 1, 3], "투표: 사람(2번)이 먼저 내고 나머지는 번호순")
	# 저장·불러오기: 투표 도중에도 이어진다
	var g6 := _new(CH)
	_set_intel(g6, {"prison": 2, "gg": 2})
	g6.ready = int(g6.data.rules["launch_min"])
	g6.phase = "morning"
	g6.morning_step = 2
	g6._morning_continue()
	_answer(g6, true)
	_answer(g6, "gg")
	var clone := RulesV2.new()
	clone.load_state(g6.save_state(), g6.data)
	_vote_all(g6, [true, true, true], ["gg", "gg", "gg"])
	_vote_all(clone, [true, true, true], ["gg", "gg", "gg"])
	ok(g6.launch_info["target"] == "gg" and str(clone.launch_info) == str(g6.launch_info), "투표: 도중에 저장한 판도 같은 결과")


func _benefit_ids(g: RulesV2) -> Array:
	return g.pending["options"].map(func(o): return o["value"])


func _test_e_benefits() -> void:
	var g := _launch_game(CH, "gg")
	g.ready = int(g.data.rules["launch_min"])
	g._launch("forced", "gg")
	ok(g.act == 2 and not g.launch_info["benefits"].size() > 0, "혜택: 결행 준비가 문턱(3)이면 혜택이 없음")
	# 3을 넘는 1점마다 하나, 같은 것은 한 번
	var g2 := _launch_game(CH, "gg")
	g2.ready = int(g2.data.rules["launch_min"]) + 2
	g2.exposure = 6
	g2._launch("forced", "gg")
	ok(g2.phase == "choice" and g2.pending["kind"] == "launch_benefit" and g2.pending["player"] == g2.leader, "혜택: 사람이 없으면 리더가 고름")
	ok(_benefit_ids(g2) == ["no_reinforce", "dice_plus", "intel_tokens", "threat_look"], "혜택: 목록은 데이터대로 (네 가지)")
	_answer(g2, "no_reinforce")
	ok(g2.pending["kind"] == "launch_benefit" and not "no_reinforce" in _benefit_ids(g2), "혜택: 둘째는 같은 것을 못 고름")
	_answer(g2, "intel_tokens")
	ok(g2.act == 2 and g2.launch_info["benefits"] == ["no_reinforce", "intel_tokens"], "혜택: 준비 5는 혜택 2개")
	ok(g2.scenes.size() == 4, "혜택 경비 강화 빼기: 경계 3단계여도 경비 강화 장면이 없음 (4장)")
	ok(g2.intel_tokens == 3 + 2, "혜택 첩보 토큰 +2: 첩보 3 + 2")
	# 경비 강화 빼기가 없으면 경계 3단계는 2장이 더 들어간다 (대조)
	var g3 := _launch_game(CH, "gg")
	g3.exposure = 6
	g3._launch("forced", "gg")
	ok(g3.scenes.size() == 6, "혜택: 고르지 않으면 경계 3단계 경비 강화 2장 (대조)")
	# 사람이 있으면 사람이 고른다 (리더가 아니어도)
	var g4 := _launch_game(CH, "gg")
	g4.human = 2
	g4.ready = int(g4.data.rules["launch_min"]) + 1
	g4._launch("forced", "gg")
	ok(g4.pending["kind"] == "launch_benefit" and g4.pending["player"] == 2 and g4.leader == 0, "혜택: 사람 요원이 리더가 아니어도 사람이 고름")
	_answer(g4, "dice_plus")
	ok(g4.act == 2 and g4.players.all(func(q): return q["dice_next"] == 1), "혜택 첫날 주사위 +1: 모든 요원의 다음 굴림 +1 (갇힌 요원 포함)")
	# 위협 덱 보기: 맨 위 2장을 보고 1장을 버림
	var g5 := _launch_game(CH, "gg")
	g5.human = 1
	g5.ready = int(g5.data.rules["launch_min"]) + 1
	g5._launch("forced", "gg")
	_answer(g5, "threat_look")
	ok(g5.phase == "choice" and g5.pending["kind"] == "threat_look" and g5.pending["player"] == 1 and g5.pending["options"].size() == 2, "혜택 위협 덱 보기: 맨 위 2장 중 버릴 한 장을 사람이 고름")
	var top: String = g5.threat_deck[-1]
	var second: String = g5.threat_deck[-2]
	var size_before := g5.threat_deck.size()
	_answer(g5, 1)
	ok(g5.threat_deck.size() == size_before - 1 and g5.threat_deck[-1] == top and second in g5.threat_discard and g5.act == 2 and g5.scenes.size() > 0,
		"혜택 위협 덱 보기: 고른 카드를 버리고 2막 장면을 깔기 계속")
	# 점수가 혜택보다 많으면 있는 만큼만
	var g6 := _launch_game(CH, "gg")
	g6.ready = int(g6.data.rules["launch_min"]) + 6
	g6._launch("forced", "gg")
	var picked := 0
	var guard := 0
	while g6.phase == "choice" and g6.pending.get("kind") == "launch_benefit" and guard < 10:
		_answer(g6, _benefit_ids(g6)[0])
		picked += 1
		guard += 1
	if g6.phase == "choice" and g6.pending.get("kind") == "threat_look":
		_answer(g6, 0)
	ok(picked == 4 and g6.act == 2, "혜택: 혜택 수(4)보다 점수가 많으면 있는 만큼만 고름")
	# AI: 경계 2단계 이상이면 경비 강화 빼기, 그다음 첩보 토큰, 주사위 +1 순
	var g7 := _launch_game(CH, "gg")
	g7.ready = int(g7.data.rules["launch_min"]) + 2
	g7.exposure = 3
	g7._launch("forced", "gg")
	var c1 := GameAIV2.decide(g7, g7.pending["player"])
	_answer(g7, c1["value"])
	var c2 := GameAIV2.decide(g7, g7.pending["player"])
	ok(c1["value"] == "no_reinforce" and c2["value"] == "intel_tokens", "혜택 AI: 경계 2단계면 경비 강화 빼기 → 첩보 토큰")
	_answer(g7, c2["value"])
	var g8 := _launch_game(CH, "gg")
	g8.ready = int(g8.data.rules["launch_min"]) + 2
	g8._launch("forced", "gg")
	var d1 := GameAIV2.decide(g8, g8.pending["player"])
	_answer(g8, d1["value"])
	var d2 := GameAIV2.decide(g8, g8.pending["player"])
	ok(d1["value"] == "intel_tokens" and d2["value"] == "dice_plus", "혜택 AI: 경계 1단계면 첩보 토큰 → 첫날 주사위 +1 (경비 강화 빼기는 뒤로)")
	# AI 대상 투표: 첩보 + 사연과 맞는 정도 + 거리
	var g9 := _new(CH)
	_set_intel(g9, {"prison": 3, "gg": 3})
	g9.players[0]["pos"] = g9.data.bases[2]
	var at_prison := GameAIV2._best_target(g9, g9.players[0])
	g9.players[0]["pos"] = g9.data.bases[3]
	var at_gg := GameAIV2._best_target(g9, g9.players[0])
	ok(at_prison == "prison" and at_gg == "gg", "대상 AI: 첩보가 같으면 가까운 거점")
	_set_intel(g9, {"prison": 3, "gg": 2})
	g9.players[0]["pos"] = Vector2i(5, 5)
	ok(GameAIV2._best_target(g9, g9.players[0]) == "prison", "대상 AI: 거리가 같으면 첩보가 높은 거점")
	var gdd := _gd(func(d):
		for c in d.sagas["sagas"]:
			if c["id"] == "sibling_revenge":
				c["condition"] = {"kind": "strike_final_by_me", "strike": "gg"})
	var g10 := _new(CH, gdd)
	_set_intel(g10, {"prison": 3, "gg": 3})
	g10.players[0]["pos"] = Vector2i(5, 5)
	g10.players[0]["sagas"] = ["sibling_revenge"]
	ok(GameAIV2._best_target(g10, g10.players[0]) == "gg", "대상 AI: 내 사연과 맞는 거점에 가점 (rules.ai.launch_target.saga)")
	g10.ready = int(g10.data.rules["launch_min"]) + int(g10.data.rules["ai"]["vote_ready_margin"])
	g10.intel["gg"] = 0
	g10.intel["prison"] = 0
	g10.phase = "morning"
	g10.morning_step = 2
	g10._morning_continue()
	var yes := GameAIV2.decide(g10, 0)
	ok(yes["value"] == true, "투표 AI: 첩보가 모자라도 준비가 문턱 + 1이면 결행 혜택을 노려 찬성")


func _scene_by_id(g: RulesV2, strike: String, id: String) -> Dictionary:
	var s: Dictionary = g.data.strike(strike)
	for c in [s["entry"], s["final"]] + s["middle"]:
		if c["id"] == id:
			return c
	return {}


func _test_e_counter() -> void:
	var gd_ok := _gd(func(d): d.rules["checks"]["evade"] = 0)
	var gd_bad := _gd(func(d): d.rules["checks"]["evade"] = 99)
	# 버티기 장면이 펼쳐진 날에는 반격이 걸린다 (장면 id가 아니라 조건 kind로)
	var card: Dictionary = _scene_by_id(_new(CH), "prison", "prison_search")
	var g := _scene_fixture("prison", card)
	g._counter_refresh()
	ok(g.counter_active() and g.counter["day"] == g.day, "반격: 버티기 장면이 펼쳐져 있으면 그날 반격이 걸림")
	var g0 := _scene_fixture("prison", _scene_by_id(_new(CH), "prison", "prison_wall"))
	g0._counter_refresh()
	ok(not g0.counter_active() and g0.counter.is_empty(), "반격: 버티기가 아닌 장면에서는 걸리지 않음")
	var g0b := _scene_fixture("prison", card)
	g0b.phase = "morning"
	g0b.morning_step = 3
	g0b._morning_continue()
	ok(g0b.counter_active(), "반격: 2막 아침에 걸림 (아침 순서의 한 단계)")
	# 막기: 그 자리에 선 요원이 작전 판정 7
	g.players[3]["pos"] = START
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g, 3, 0)
	_spare(g, 6, 3)
	ok(not g.can_counter_check(g.players[3]), "반격: 장면 자리에 서지 않은 요원은 막을 수 없음")
	g.phase = "day"
	g.current = -1
	_turn(g, 0, 0)
	var cdie := _spare(g, 4, 0)
	ok(g.can_counter_check(g.players[0]) and g.apply({"type": "counter_check", "player": 0, "die": cdie}), "반격: 자리에 선 요원은 주사위 하나로 작전 판정 (행동)")
	ok(g.op_dice[cdie]["used"] and g.counter["blocked"] and not g.counter_active(), "반격: 성공하면 막은 것 (주사위를 씀)")
	ok(int(g.check_preview(g.players[0], {"type": "counter_check"})["target"]) == 7, "반격: 판정 목표는 rules.counter.target (7)")
	g._scene_night()
	ok(g.ending.get("won", false), "반격: 막았으면 그날 밤 버틴 날로 세어 돌파 (마지막 장면이라 승리)")
	# 실패해도 다른 주사위로 또 막을 수 있다
	var gr := _scene_fixture("prison", card)
	gr._counter_refresh()
	_turn(gr, 0, 0)
	var f1 := _spare(gr, 1, 0)
	var f2 := _spare(gr, 6, 0)
	gr.players[0]["grants"] = [{"kind": "check_bonus", "value": -99}]
	gr.apply({"type": "counter_check", "player": 0, "die": f1})
	ok(gr.counter_active() and gr.op_dice[f1]["used"], "반격: 실패하면 못 막은 채 (주사위는 씀)")
	gr.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	ok(gr.apply({"type": "counter_check", "player": 0, "die": f2}) and gr.counter["blocked"], "반격: 실패해도 다른 주사위로 또 막을 수 있음")
	# 못 막으면: 그날은 세지 않고, 자리에 선 요원이 회피 판정, 실패하면 투옥
	var gb := _scene_fixture("prison", card)
	gb.data = gd_bad
	gb._counter_refresh()
	gb.players[3]["pos"] = START
	gb._night_end()
	var jailed_n := 0
	for q in gb.players:
		jailed_n += 1 if q["jailed"] else 0
	ok(jailed_n == 3 and not gb.players[3]["jailed"], "반격: 못 막은 밤 자리에 선 요원은 모두 회피 판정, 실패하면 투옥 (자리 밖 요원은 무사)")
	ok(gb.ending.is_empty() and gb.day == 2 and gb.scene_index == 1, "반격: 못 막은 날은 세지 않아 장면이 안 끝나고 다음 날로")
	ok(gb.counter.get("day", -1) == 2 and not gb.counter["blocked"], "반격: 버티기 장면이 그대로면 다음 날 아침에 반격이 다시 걸림")
	var gs := _scene_fixture("prison", card)
	gs.data = gd_ok
	gs._counter_refresh()
	gs._night_end()
	var jailed_s := 0
	for q in gs.players:
		jailed_s += 1 if q["jailed"] else 0
	ok(jailed_s == 0 and gs.ending.is_empty() and gs.day == 2, "반격: 못 막았어도 회피에 성공하면 투옥은 없지만 그날은 세지 않음")
	# 반격이 없는 날(막았거나 걸리지 않음)은 지금처럼 센다
	var gn := _scene_fixture("prison", card)
	gn._scene_night()
	ok(gn.ending.get("won", false), "반격: 걸리지 않은 장면(시험 꾸밈)에서는 예전처럼 밤에 셈")
	# 사람(요원 번호순)과 선택: 회피에 연막탄이 있으면 쓸지 묻는다 (강제 판정 흐름 그대로)
	var gc := _scene_fixture("prison", card)
	gc.data = gd_bad
	gc._counter_refresh()
	gc.players[0]["items"] = ["smoke_bomb"]
	for i in [1, 2, 3]:
		gc.players[i]["pos"] = START
	gc._night_end()
	ok(gc.phase == "choice" and gc.pending["kind"] == "react_evade" and gc.pending["player"] == 0, "반격: 회피 판정 직전에 연막탄을 쓸지 물음")
	_answer(gc, true)
	ok(not gc.players[0]["jailed"] and gc.day == 2, "반격: 연막탄으로 피하면 투옥 없이 밤이 이어짐")
	# 저장·불러오기: 반격 상태가 들어간다
	var gv := _scene_fixture("prison", card)
	gv._counter_refresh()
	var cl := RulesV2.new()
	cl.load_state(gv.save_state(), gv.data)
	ok(cl.counter_active() and str(cl.counter) == str(gv.counter), "반격: 저장·불러오기에 들어감")


func _test_e_flag_and_pair() -> void:
	var gd_ok := _gd(func(d): d.rules["checks"]["evade"] = 0)
	var flag: Dictionary = _scene_by_id(_new(CH), "gg", "gg_flag")
	ok(flag["condition"]["kind"] == "sequence" and flag["condition"]["steps"].size() == 2, "깃발: 장면 하나가 두 단계 (sequence)")
	var g := _scene_fixture("gg", flag)
	g.data = gd_ok
	var need := g.scene_need()
	ok(not need.has("hold") and not g.counter_active(), "깃발: 첫 단계(깃발 올리기)에는 버티기도 반격도 없음")
	g._counter_refresh()
	ok(g.counter.is_empty(), "깃발: 첫 단계에서는 반격이 걸리지 않음")
	g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g, 0, 0)
	ok(g.apply({"type": "scene_check", "player": 0, "die": _spare(g, 3, 0)}) and g.ending.is_empty(), "깃발: 깃발 올리기(판정 9)에 성공해도 아직 안 끝남")
	ok(g.scene_need().get("hold", -1) == 1 and g.counter_active(), "깃발: 두 번째 단계 「지키기」(2명 1일 버팀)가 열리고 반격이 걸림")
	var steps_leaf := g._scene_leaves(g.current_scene()["condition"])
	ok(steps_leaf.size() == 1 and steps_leaf[0]["cond"]["kind"] == "hold" and steps_leaf[0]["cond"]["days"] == 1 and steps_leaf[0]["cond"]["count"] == 2, "깃발: 지키기는 2명이 하루")
	g.phase = "day"
	g.current = -1
	g._scene_night()
	ok(g.ending.is_empty(), "깃발: 반격을 막지 못하면 하루를 버텨도 세지 않아 안 끝남")
	ok(g.day == 2, "깃발: 못 막은 밤이 지나 다음 날 (회피 판정은 성공)")
	g.threat_deck = []
	g.threat_discard = []
	g.phase = "day"
	g.current = -1
	g._counter_refresh()
	g.players[1]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g, 1, 0)
	_cc(g, 1)
	g._scene_night()
	ok(g.ending.get("won", false), "깃발: 반격을 막고 2명이 하루를 지키면 마지막 장면 돌파 (대성공)")
	# 지키는 단계에 한 명뿐이면 안 됨
	var g2 := _scene_fixture("gg", flag)
	g2.data = gd_ok
	g2.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_turn(g2, 0, 0)
	g2.apply({"type": "scene_check", "player": 0, "die": _spare(g2, 3, 0)})
	for i in [1, 2, 3]:
		g2.players[i]["pos"] = START
	g2.counter["blocked"] = true
	g2._scene_night()
	ok(g2.ending.is_empty(), "깃발: 막았어도 자리에 한 명뿐이면 버틴 날이 아님")
	# 두 명 판정: 서로 다른 두 요원이 같은 날 각각 작전 판정 7
	var data := _fixed_data()
	var all_seven := true
	var count := 0
	var cards: Array = data.scenes["reinforce"].duplicate()
	for strike in GameDataV2.load_default().base_ids:
		var s: Dictionary = data.strike(strike)
		cards.append_array([s["entry"], s["final"]] + s["middle"])
	for c in cards:
		if true:
			var stack: Array = [c["condition"]]
			while not stack.is_empty():
				var cond: Dictionary = stack.pop_back()
				stack.append_array(cond.get("options", []))
				if cond.get("kind", "") == "check_pair":
					count += 1
					all_seven = all_seven and int(cond.get("target", 0)) == 7 and cond.get("check", "") == "generic" and int(cond.get("count", 0)) == 2
	ok(count == 4 and all_seven, "두 명 판정: 서로 다른 두 요원이 각각 작전 판정 7 (4곳 모두 target 7)")
	var guards := _scene_fixture("prison", _scene_by_id(_new(CH), "prison", "prison_guards"))
	_turn(guards, 0, 0)
	ok(int(guards.check_preview(guards.players[0], {"type": "scene_check"})["target"]) == 7, "두 명 판정: 작전 판정 목표 7")
	for i in 2:
		guards.players[i]["grants"] = [{"kind": "check_bonus", "value": 99}]
	_sc(guards, 0)
	ok(not _sc(guards, 0) and guards.ending.is_empty(), "두 명 판정: 같은 요원이 또 성공해도 한 명으로만 셈")
	guards.phase = "day"
	guards.current = -1
	_turn(guards, 1, 0)
	_sc(guards, 1)
	ok(guards.ending.get("won", false), "두 명 판정: 서로 다른 두 요원이 같은 날 성공하면 돌파")


func _test_e_jail_at_strike() -> void:
	var gd := _gd(func(d): d.rules["checks"]["escape"] = 0)
	var base := Vector2i(0, 0)
	var g := _scene_fixture("prison", _scene_by_id(_new(CH), "prison", "prison_wall"))
	g.data = gd
	base = g._base_cell("prison")
	var next := base + Vector2i(0, -1)
	_tile(g, next, "normal")
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = base
	g.players[0]["pos"] = next
	g.players[2]["pos"] = START
	g.players[3]["pos"] = START
	_turn(g, 0, 2)
	_step(g, 0, base, false)
	ok(g.players[0]["pos"] == base and g.players[1]["jailed"], "감옥: 동료가 거점에 들어와도 풀려나지 않음 (구출은 뺐다)")
	# 탈옥은 된다
	g.phase = "day"
	g.current = -1
	_turn(g, 1, 0)
	var ed := _spare(g, 2, 1)
	ok(g.apply({"type": "escape", "player": 1, "die": ed}) and not g.players[1]["jailed"], "결행 거점 감옥: 탈옥 판정으로는 풀려남")
	# 1막에도 구출은 없다
	var g3 := _new(CH)
	var b3: Vector2i = g3.data.bases[2]
	_tile(g3, b3 + Vector2i(0, -1), "normal")
	g3.players[1]["jailed"] = true
	g3.players[1]["pos"] = b3
	g3.players[0]["pos"] = b3 + Vector2i(0, -1)
	_turn(g3, 0, 2)
	_step(g3, 0, b3, false)
	ok(g3.players[1]["jailed"], "감옥: 1막에도 거점에 들어간 동료가 구해 내지 않음 (탈옥 판정으로만)")
	# 장면 「지하 유치장」: 결행 거점에 갇힌 동료가 있으면 돌파
	var cells := _scene_fixture("police_hq", _scene_by_id(_new(CH), "police_hq", "police_cells"))
	cells.players[1]["jailed"] = true
	cells.players[1]["pos"] = cells._base_cell("police_hq")
	cells._scene_auto_break()
	ok(cells.ending.get("won", false), "결행 거점 감옥: 장면 「지하 유치장」은 갇힌 동료가 있으면 돌파")
	# 밀고 포상금: 출동한 경찰이 결행 거점에서 가장 가까운 요원을 쫓는다
	var gp := _new(CH)
	gp.act = 2
	gp.launch_info = {"target": "gg", "reason": "test", "day": 1}
	var gg: Vector2i = gp._base_cell("gg")
	_flat(gp)
	gp.players[2]["pos"] = gg + Vector2i(-1, 0)
	gp.police.clear()
	_threat(gp, "informer_bounty")
	ok(gp.police.has(2) and gp.police[2]["pos"] == gg and gp.exposure >= 1, "밀고 포상금: 노출 +1, 결행 거점에서 경찰이 출동해 가장 가까운 요원을 쫓음")


func _test_e_data() -> void:
	var real := GameDataV2.load_default()
	var ids: Array = real.rules["launch"]["benefits"].map(func(b): return b["id"])
	ok(ids == ["no_reinforce", "dice_plus", "intel_tokens", "threat_look"], "데이터: 결행 혜택 4가지 (군자금 혜택은 뺐다)")
	ok(int(real.rules["launch"]["target_min_intel"]) == 2, "데이터: 후보 첩보 문턱 2")
	ok(int(real.rules["counter"]["target"]) == 7, "데이터: 반격 판정 목표 7")
	var w: Dictionary = real.rules["ai"]["launch_target"]
	ok(w.has("intel") and w.has("saga") and w.has("distance"), "데이터: AI 대상 점수식의 가중치 (첩보·사연·거리)")
	var sib: Dictionary = real.saga("sibling_revenge")
	ok(sib["condition"]["kind"] == "strike_final_by_me" and sib["condition"]["or"]["kind"] == "mission_kind_by_me" and sib["condition"]["or"]["mission_kind"] == "assassinate",
		"데이터: 동생의 원수는 암살 미션을 내가 이루거나 마지막 장면을 돌파 (S단계)")
	var lt: Dictionary = real.saga("last_telegram")
	ok(lt["reward"].size() == 1 and lt["reward"][0]["scope"] == "final" and lt["reward"][0]["value"] == 2, "데이터: 마지막 전보의 보상은 마지막 장면 판정 +2 한 번")
	ok(real.validate().is_empty(), "데이터: 새 데이터가 검증기를 통과")
