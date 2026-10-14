extends "res://tests/mechanics/mech_turns.gd"
## 규칙 시험 6층: C단계 미션 마커 · 새 타일 · 일제 동향


# ================================================================== C단계: 미션 마커 · 새 타일 · 일제 동향

func _run_c_tests() -> void:
	_test_c_data()
	_test_c_placement()
	_test_c_assassinate()
	_test_c_infiltrate()
	_test_c_bomb()
	_test_c_work()
	_test_c_contact()
	_test_c_lurk()
	_test_c_tiles()
	_test_c_ops()
	_test_c_morning()
	_test_c_launch_cleanup()
	_test_c_save()


func _test_c_data() -> void:
	var gd := GameDataV2.load_default()
	var by_type := {}
	for c in gd.missions["missions"]:
		by_type[c["type"]] = int(by_type.get(c["type"], 0)) + 1
	ok(by_type == {"assassin": 3, "infiltrate": 3, "bomb": 2, "work": 5, "contact": 3, "lurk": 3, "coop": 3},
		"데이터: 미션 22장 (암살 3 · 잠입 3 · 폭파 2 · 공작 5 · 연락 3 · 잠복 3 · 협동 3)")
	ok(gd.missions["ops"].size() == 4 and gd.op_deck().size() == 4, "데이터: 일제 작전 4장")
	var want := {"normal": 42, "event": 16, "item": 18, "check": 6, "supply": 5, "alley": 6, "watchtower": 4, "tavern": 3}
	var same := true
	for t in want:
		if int(gd.rules["tiles"].get(t, -1)) != int(want[t]):
			same = false
	ok(same and not gd.rules["tiles"].has("market"), "데이터: 타일 구성 길 42 · 이벤트 16 · 아이템 18 · 검문소 6 · 보급 5 · 골목 6 · 감시탑 4 · 주막 3 (장터 4장은 아이템으로)")
	ok(not gd.rules["tiles"].has("assassin") and not gd.rules["tiles"].has("sabotage") and not gd.rules["tiles"].has("bomb"), "데이터: 암살·방해·폭파 타일이 없음")
	var g := _new(CH)
	ok(g.tile_deck.size() == 100, "타일 더미는 100장")
	ok(gd.threat_deck(1).size() == 21 and gd.threat_deck(2).size() == 11, "데이터: 1막 위협 덱 21장 (일제 작전 3장을 뺌), 2막 11장")
	ok(gd.rules["ops"]["days"] == [2, 4, 6, 8] or gd.rules["ops"]["days"] == [2.0, 4.0, 6.0, 8.0], "데이터: 일제 작전은 2·4·6·8일째")
	ok(g.card_def("m_mp_captain").get("condition", {}).get("kind", "") == "assassinate" and g.card_def("op_spy_raid").get("type", "") == "op", "카드 조회: 미션과 일제 작전")
	# 돈이 드는 곳은 뺐다: 무기 조달 · 정보원 사례금이 없다
	ok(not g.card_def("m_mp_captain")["condition"].has("gear") and not g.card_def("m_police_chief")["condition"].has("informer_cost") and not g.card_def("m_informant")["condition"].has("informer_cost"), "단순화: 무기 조달 · 정보원 사례금 없음")


func _test_c_placement() -> void:
	var g := _new(CH)
	var hq := _base(g, "police_hq")
	var good := true
	var covered := false
	for k in 30:
		g.markers = []
		g.mission_state = {}
		g.mission_row = []
		_mission(g, "m_police_chief")
		var t: Dictionary = g.markers_of("m_police_chief", "target")[0]
		var inf: Dictionary = g.markers_of("m_police_chief", "informer")[0]
		var dt: int = absi(t["pos"].x - hq.x) + absi(t["pos"].y - hq.y)
		var di: int = absi(inf["pos"].x - START.x) + absi(inf["pos"].y - START.y)
		if dt < 2 or dt > 3 or di < 2 or di > 4 or t["pos"] == inf["pos"] or t["pos"] in g.data.bases or inf["pos"] in g.data.bases \
				or t["pos"] == START or inf["pos"] == START or not g.in_bounds(t["pos"]) or not g.in_bounds(inf["pos"]):
			good = false
		if not g.board.has(t["pos"]):
			covered = true
	ok(good, "마커 배치: 경찰서 2~3칸(거점 기준)·정보원 시내 2~4칸(출발점 기준), 거점·출발점·다른 마커 칸은 피함 (30번)")
	ok(covered, "마커 배치: 덮인 칸(아직 안 뒤집힌 칸)에도 놓음")
	# 같은 카드의 마커 셋(전단 살포)은 서로 다른 칸
	g.markers = []
	g.mission_state = {}
	g.mission_row = []
	_mission(g, "m_leaflets")
	var cells := g.markers_of("m_leaflets", "work").map(func(m): return m["pos"])
	var ring := cells.all(func(c): return absi(c.x - START.x) + absi(c.y - START.y) >= 2 and absi(c.y - START.y) + absi(c.x - START.x) <= 5)
	ok(cells.size() == 3 and ring and cells[0] != cells[1] and cells[1] != cells[2] and cells[0] != cells[2], "마커 배치: 전단 살포는 시내 2~5칸에 서로 다른 칸 셋")
	# 금지 칸: 요원·경찰이 있는 칸, 다른 마커가 있는 칸
	var c1 := Vector2i(7, 5)
	g.players[1]["pos"] = c1
	ok(g._marker_blocked(c1) and not g._marker_blocked(c1, 1), "마커 금지 칸: 요원이 있는 칸 (밀려 났을 때는 허용)")
	g.police[2] = {"pos": Vector2i(3, 5), "summon_turn": 0}
	ok(g._marker_blocked(Vector2i(3, 5)) and g._marker_blocked(g.data.start) and g._marker_blocked(g.data.bases[0]), "마커 금지 칸: 경찰이 있는 칸, 출발점, 거점")
	ok(g._marker_blocked(cells[0]) and g._marker_blocked(cells[0], 1), "마커 금지 칸: 다른 마커가 있는 칸")
	# 후보 칸이 모자라면 겹치지 않게 놓다가, 하나도 없으면 기준 칸
	g.markers = []
	g.police.clear()
	g.players[1]["pos"] = START
	var spec := {"role": "target", "around": "barracks", "min": 1, "max": 1}
	var seen := {}
	for k in 4:
		var c := g._marker_pos(spec)
		seen[c] = true
		g.markers.append({"uid": 900 + k, "id": "x", "role": "target", "pos": c, "move": 0, "spec": 0})
	ok(seen.size() == 4, "마커 배치: 후보가 4칸뿐이면 겹치지 않고 네 칸에 하나씩")
	ok(g._marker_pos(spec) == _base(g, "barracks"), "마커 배치: 후보가 하나도 없으면 기준 칸에 둠 (안전장치)")
	# 고정 칸(at): 잠입은 거점 자체, 경찰서 문서는 경찰서 → 출발점
	g.markers = []
	g.mission_state = {}
	g.mission_row = []
	_mission(g, "m_police_docs")
	ok(g.markers_of("m_police_docs", "pickup")[0]["pos"] == hq and g.markers_of("m_police_docs", "dropoff")[0]["pos"] == START, "마커 배치: at이면 그 칸 (문서 탈취: 경찰서에서 받고 출발점에 줌)")


func _test_c_assassinate() -> void:
	var gd := _mission_gd(0, 7)
	var g := _new(CH, gd)
	_flat(g)
	_mission(g, "m_police_chief", {"target": Vector2i(5, 7), "informer": Vector2i(0, 5)})
	_turn(g, 0, 4)
	_step(g, 0, Vector2i(5, 6), false)
	ok(g.steps_left == 3 and g.phase == "turn", "암살: 표적이 아닌 칸은 그냥 지나감")
	_step(g, 0, Vector2i(5, 7), false)
	ok(g.steps_left == 0 and g.phase == "turn" and g.ready == 0 and g.exposure == 0, "암살: 표적 칸에 들어가면 이동이 멈추고 판정은 자동으로 하지 않음 (걸음이 남아도)")
	ok(not _mcheck_none(g, 0), "암살: 주사위가 없으면 판정 행동이 없음")
	_mcheck(g, 0)
	_cov("mission", "m_police_chief")
	ok(g.ready == 2 and g.intel["police_hq"] == 3, "암살: 이루면 결행 준비 +2, 경찰서 첩보 +2 (+보너스 1: 쫓기지 않고 이룸)")
	ok(g.exposure == 1 and g.police.has(0), "암살: 시끄러움 — 노출 +1, 경찰이 붙음")
	ok(g.mission_row.is_empty() and g.markers.is_empty() and g.mission_state.is_empty() and g.mission_discard == ["m_police_chief"], "암살: 이룬 미션의 마커는 사라지고 카드는 버려짐")
	ok(g.players[0]["stats"]["assassinations"] == 1 and g.players[0]["stats"]["missions"] == 1, "암살: 통계에 셈")
	# 쫓기는 중에 이루면 보너스 없음
	var g1 := _new(CH, gd)
	_flat(g1)
	_mission(g1, "m_police_chief", {"target": Vector2i(5, 6)})
	g1.police[0] = {"pos": _base(g1, "barracks"), "summon_turn": 0}
	_turn(g1, 0, 2)
	_step(g1, 0, Vector2i(5, 6), false)
	_mcheck(g1, 0)
	ok(g1.ready == 2 and g1.intel["police_hq"] == 2, "암살 보너스: 쫓기는 상태에서 이루면 첩보 +1이 없음")
	# 실패 → 회피 판정(강제) → 실패하면 투옥
	var gd2 := _mission_gd(99, 99)
	var g2 := _new(CH, gd2)
	_flat(g2)
	_mission(g2, "m_police_chief", {"target": Vector2i(5, 6)})
	_turn(g2, 0, 2)
	_step(g2, 0, Vector2i(5, 6), false)
	_mcheck(g2, 0)
	ok(g2.players[0]["jailed"] and g2.players[0]["jail_count"] == 1 and g2.exposure == 1, "암살 실패: 회피도 실패하면 투옥 (노출 +1)")
	ok(g2.ready == 0 and g2.mission_row == ["m_police_chief"] and g2.markers_of("m_police_chief", "target").size() == 1, "암살 실패: 미션과 마커는 그대로")
	# 실패 → 회피 성공 → 같은 차례에 다른 주사위로 다시
	var gd3 := _mission_gd(99, 0)
	var g3 := _new(CH, gd3)
	_flat(g3)
	_mission(g3, "m_police_chief", {"target": Vector2i(5, 6)})
	_turn(g3, 0, 2)
	_step(g3, 0, Vector2i(5, 6), false)
	_mcheck(g3, 0)
	ok(not g3.players[0]["jailed"] and g3.police.has(0) and g3.ready == 0 and g3.phase == "turn" and g3.current == 0, "암살 실패: 회피에 성공하면 경찰만 붙고 차례가 이어짐")
	ok(g3.apply({"type": "mission_check", "player": 0, "die": _spare(g3, 5, 0), "cell": Vector2i(5, 6)}), "암살 실패: 회피에 성공하면 다른 주사위로 다시 판정할 수 있음")
	# 표적 칸을 지나가는 이동은 그 칸에서 멈춘다
	var g4 := _new(CH, gd)
	_flat(g4)
	_mission(g4, "m_police_chief", {"target": Vector2i(5, 7)})
	_turn(g4, 0, 6)
	_step(g4, 0, Vector2i(5, 6), false)
	_step(g4, 0, Vector2i(5, 7), false)
	ok(g4.steps_left == 0 and g4.players[0]["pos"] == Vector2i(5, 7), "암살: 표적 칸은 걸음이 남아도 이동이 멈춤")
	var g4b := _new(CH, gd)
	_flat(g4b)
	_mission(g4b, "m_police_chief", {"target": Vector2i(5, 7)})
	g4b.phase = "day"
	_turn(g4b, 0, 6)
	var route: Dictionary = g4b.path_to(g4b.players[0], Vector2i(5, 9))
	var via: Array = route["path"].duplicate()
	ok(not (Vector2i(5, 7) in via and via.find(Vector2i(5, 7)) < via.size() - 1), "길 찾기: 표적 칸은 멈추는 칸이라 그 칸을 지나가는 길은 짜지 않음")

	# 정보원: 들르면 동선 파악 — 표적이 멈추고 판정이 2 쉬워짐
	var g5 := _new(CH, gd)
	_flat(g5)
	_mission(g5, "m_police_chief", {"target": Vector2i(5, 8), "informer": Vector2i(5, 6)})
	_turn(g5, 0, 4)
	_step(g5, 0, Vector2i(5, 6), false)
	ok(g5.phase == "turn" and g5.mission_state["m_police_chief"]["informed"] and g5.markers_of("m_police_chief", "informer").is_empty() and g5.steps_left == 3, "정보원: 들르면 동선 파악 (마커는 사라지고 이동은 계속)")
	var before: Vector2i = g5.markers_of("m_police_chief", "target")[0]["pos"]
	var moved := false
	for k in 10:
		g5._move_markers()
		if g5.markers_of("m_police_chief", "target")[0]["pos"] != before:
			moved = true
	ok(not moved, "정보원: 동선을 알아내면 표적이 더는 움직이지 않음")
	var prev := g5.check_preview(g5.players[0], {"type": "mission_check", "cell": Vector2i(5, 8)})
	ok(prev["target"] == 0 and prev["bonus"] == 2, "정보원: 판정이 2 쉬워짐 (보정 +2)")
	var g5b := _new(CH, gd)
	_flat(g5b)
	_mission(g5b, "m_police_chief", {"target": Vector2i(5, 8)})
	ok(g5b.check_preview(g5b.players[0], {"type": "mission_check", "cell": Vector2i(5, 8)})["bonus"] == 0, "정보원: 안 들르면 보정 없음 (대조)")

	# 표적 이동: 매일 아침 지역 안에서 무작위로 1칸 (밀정 처단은 2칸), 금지 칸으로는 안 감
	var g6 := _new(CH, gd)
	_flat(g6)
	g6.markers = []
	g6.mission_state = {}
	g6.mission_row = []
	_mission(g6, "m_police_chief")
	var inside := true
	var steps_ok := true
	var changed := false
	var tgt: Dictionary = g6.markers_of("m_police_chief", "target")[0]
	for k in 40:
		var from: Vector2i = tgt["pos"]
		g6._move_markers()
		var to: Vector2i = tgt["pos"]
		var d := absi(to.x - from.x) + absi(to.y - from.y)
		if d > 1:
			steps_ok = false
		if d == 1:
			changed = true
		var dh := absi(to.x - _base(g6, "police_hq").x) + absi(to.y - _base(g6, "police_hq").y)
		if dh < 2 or dh > 3 or to == START or to in g6.data.bases:
			inside = false
	ok(changed and steps_ok and inside, "표적 이동: 순사 부장은 매일 1칸, 경찰서 2~3칸 안에서 무작위로 (40번)")
	var g7 := _new(CH, gd)
	_flat(g7)
	g7.markers = []
	g7.mission_state = {}
	g7.mission_row = []
	_mission(g7, "m_informant")
	var t7: Dictionary = g7.markers_of("m_informant", "target")[0]
	var far := false
	var in7 := true
	for k in 40:
		var f7: Vector2i = t7["pos"]
		g7._move_markers()
		var d7 := absi(t7["pos"].x - f7.x) + absi(t7["pos"].y - f7.y)
		if d7 == 2:
			far = true
		if d7 > 2:
			in7 = false
		var ds := absi(t7["pos"].x - START.x) + absi(t7["pos"].y - START.y)
		if ds < 3 or ds > 5:
			in7 = false
	ok(far and in7, "표적 이동: 밀정 처단은 매일 2칸, 시내 3~5칸 안")
	# 요원이 선 칸으로는 표적이 들어오지 않는다
	var g8 := _new(CH, gd)
	_flat(g8)
	g8.markers = []
	g8.mission_state = {}
	g8.mission_row = []
	_mission(g8, "m_police_chief", {"target": Vector2i(5, 3)})
	var ring_cells := []
	for x in 11:
		for y in 11:
			var c := Vector2i(x, y)
			if absi(c.x - _base(g8, "police_hq").x) + absi(c.y - _base(g8, "police_hq").y) in [2, 3] and c != START:
				ring_cells.append(c)
	var occupied := false
	for k in 30:
		g8.players[1]["pos"] = Vector2i(6, 3)
		g8._move_markers()
		if g8.markers_of("m_police_chief", "target")[0]["pos"] == Vector2i(6, 3):
			occupied = true
	ok(not occupied, "표적 이동: 요원이 있는 칸에는 들어오지 않음")

	# 헌병 대위: 무기 조달은 뺐다 (아이템이 있어도 판정 직전에 묻지 않음)
	var gdg := _mission_gd(9, 7)
	var gz := _new(CH, gdg)
	_flat(gz)
	gz.players[0]["items"] = ["train_ticket"]
	_mission(gz, "m_mp_captain", {"target": Vector2i(5, 6)})
	_turn(gz, 0, 2)
	_step(gz, 0, Vector2i(5, 6), false)
	_mcheck(gz, 0)
	ok(gz.phase != "choice" and gz.players[0]["items"].size() == 1, "헌병 대위: 아이템이 있어도 묻지 않고 바로 판정")
	# 의병이 이루면 준비 +1
	var gdz := _mission_gd(0, 7)
	var gb := _new(CH, gdz)
	_flat(gb)
	_mission(gb, "m_mp_captain", {"target": Vector2i(5, 6)})
	gb.players[3]["pos"] = START
	_turn(gb, 3, 2)
	_step(gb, 3, Vector2i(5, 6), false)
	_mcheck(gb, 3)
	_cov("mission", "m_mp_captain")
	ok(gb.ready == 3 and gb.intel["barracks"] == 2 and gb.exposure == 1, "헌병 대위: 의병(김개똥)이 이루면 결행 준비 +2 +1, 군영 첩보 +2")
	var gc := _new(CH, gdz)
	_flat(gc)
	_mission(gc, "m_mp_captain", {"target": Vector2i(5, 6)})
	_turn(gc, 0, 2)
	_step(gc, 0, Vector2i(5, 6), false)
	_mcheck(gc, 0)
	ok(gc.ready == 2, "헌병 대위: 의병이 아니면 결행 준비 +2만 (대조)")
	# 밀정 처단: 기한이 2일 이상 남았을 때 이루면 노출 −1 더, 나를 쫓는 경찰 제거
	var gi := _new(CH, gdz)
	_flat(gi)
	gi.exposure = 3
	_mission(gi, "m_informant", {"target": Vector2i(5, 6)})
	_turn(gi, 0, 2)
	_step(gi, 0, Vector2i(5, 6), false)
	_mcheck(gi, 0)
	_cov("mission", "m_informant")
	ok(gi.exposure == 2 and not gi.police.has(0) and gi.ready == 2, "밀정 처단: 노출 −1 −1(기한 2일 이상) +1(시끄러움), 쫓던 경찰 제거, 결행 준비 +2")
	var gj := _new(CH, gdz)
	_flat(gj)
	gj.exposure = 3
	_mission(gj, "m_informant", {"target": Vector2i(5, 6)})
	gj.mission_state["m_informant"]["days"] = 1
	_turn(gj, 0, 2)
	_step(gj, 0, Vector2i(5, 6), false)
	_mcheck(gj, 0)
	ok(gj.exposure == 3, "밀정 처단: 기한이 1일 남았으면 노출 보너스가 없음")


func _test_c_infiltrate() -> void:
	var gd := _mission_gd()
	var g := _new(CH, gd)
	_flat(g)
	var prison := _base(g, "prison")
	_mission(g, "m_bribe_guard")
	ok(g.markers_of("m_bribe_guard", "base")[0]["pos"] == prison, "잠입: 마커는 그 거점 자체")
	g.players[1]["jailed"] = true
	g.players[1]["pos"] = prison
	g.players[0]["pos"] = prison + Vector2i(0, -1)
	_turn(g, 0, 3)
	_step(g, 0, prison, false)
	_cov("mission", "m_bribe_guard")
	ok(g.ready == 2 and g.intel["prison"] == 1 and g.players[1]["jailed"], "간수 매수: 결행 준비 +2, 형무소 첩보 +1 (갇힌 동료는 그대로)")
	ok(g.mission_row.is_empty() and g.police.has(0) and g.exposure == 0, "잠입: 이루면 경찰이 붙음 (시끄럽지 않음: 노출은 그대로)")
	# 최 훈장: 잠입 미션의 첩보 +1
	var g5 := _new(["choi", "han", "oh", "seo"], gd)
	_flat(g5)
	_mission(g5, "m_bribe_guard")
	g5.players[0]["pos"] = prison + Vector2i(0, -1)
	_turn(g5, 0, 3)
	_step(g5, 0, prison, false)
	ok(g5.intel["prison"] == 2, "최 훈장: 잠입 미션의 첩보 +1")
	# 총독부 설계도: 결행 장면 판정 +2 권리 한 장, 결행 대상이 총독부면 한 장 더 (결행 때)
	for target in ["gg", "prison"]:
		var gb := _new(CH, gd)
		_flat(gb)
		var gg: Vector2i = _base(gb, "gg")
		_mission(gb, "m_gg_blueprint")
		gb.players[0]["pos"] = gg + Vector2i(0, -1)
		_turn(gb, 0, 3)
		_step(gb, 0, gg, false)
		_cov("mission", "m_gg_blueprint")
		var grants: int = gb.players[0]["grants"].filter(func(x): return x["kind"] == "check_bonus" and x["scope"] == "strike").size()
		ok(gb.ready == 1 and gb.intel["gg"] == 1 and grants == 1 and gb.bonus_wait.size() == 1, "총독부 설계도: 결행 준비 +1, 첩보 +1, 결행 장면 판정 +2 권리 1장 (보너스는 결행 때 판정)")
		gb.phase = "day"
		gb.current = -1
		gb.launch_info = {"target": target, "reason": "test", "day": gb.day, "rounds_left": gb.rounds_left}
		gb._begin_act2()
		var after: int = gb.players[0]["grants"].filter(func(x): return x["kind"] == "check_bonus" and x["scope"] == "strike").size()
		ok(after == (2 if target == "gg" else 1) and gb.bonus_wait.is_empty(), "총독부 설계도: 결행 대상이 %s이면 권리 %d장" % [target, 2 if target == "gg" else 1])
	# 경찰서 문서 탈취: 경찰서에서 문서를 들고 출발점까지 (연락과 같은 방식)
	var gd2 := _mission_gd()
	var gc := _new(CH, gd2)
	_flat(gc)
	var hq := _base(gc, "police_hq")
	_mission(gc, "m_police_docs")
	gc.players[0]["pos"] = hq + Vector2i(0, 1)
	_turn(gc, 0, 3)
	_step(gc, 0, hq, false)
	ok(gc.mission_state["m_police_docs"]["holder"] == 0 and gc.police.has(0) and gc.mission_row == ["m_police_docs"], "문서 탈취: 경찰서에 들어가면 문서를 들고 (경찰이 붙음), 아직 이루지 않음")
	gc.police.erase(0)   # 경찰을 따돌렸다고 치고
	gc.players[0]["pos"] = Vector2i(5, 6)
	gc.players[0]["done_today"] = false
	gc.phase = "day"
	_turn(gc, 0, 1)
	_step(gc, 0, START, false)
	_cov("mission", "m_police_docs")
	ok(gc.mission_row.is_empty() and gc.ready == 3 and gc.intel["police_hq"] == 2, "문서 탈취: 출발점에 닿으면 이룸 — 결행 준비 +2, 경찰서 첩보 +2, 쫓기지 않고 나오면 결행 준비 +1")
	var gd3 := _mission_gd()
	var gh := _new(CH, gd3)
	_flat(gh)
	_mission(gh, "m_police_docs")
	gh.players[0]["pos"] = hq + Vector2i(0, 1)
	_turn(gh, 0, 3)
	_step(gh, 0, hq, false)
	gh.players[0]["pos"] = Vector2i(5, 6)
	gh.players[0]["done_today"] = false
	gh.phase = "day"
	_turn(gh, 0, 1)
	_step(gh, 0, START, false)
	ok(gh.ready == 2, "문서 탈취: 쫓기는 채로 나오면 보너스 없음")
	var gj := _new(CH, gd3)
	_flat(gj)
	_mission(gj, "m_police_docs")
	gj.players[0]["pos"] = hq + Vector2i(0, 1)
	_turn(gj, 0, 3)
	_step(gj, 0, hq, false)
	gj._jail(gj.players[0])
	ok(gj.mission_state["m_police_docs"]["holder"] == -1 and gj.mission_row == ["m_police_docs"], "문서 탈취: 든 요원이 잡히면 문서는 경찰서(받기 마커)로 돌아감")


func _test_c_bomb() -> void:
	var g := _new(CH)
	_flat(g)
	_mission(g, "m_rail_bomb", {"target": Vector2i(5, 7)})
	g.players[0]["bombs"] = 1
	_turn(g, 0, 4)
	_step(g, 0, Vector2i(5, 6), false)
	_step(g, 0, Vector2i(5, 7), false)
	_cov("mission", "m_rail_bomb")
	ok(g.players[0]["bombs"] == 0 and g.ready == 2 and g.intel["barracks"] == 1 and g.exposure == 1, "폭파: 폭탄을 들고 마커 칸에 들어가면 이룸 — 폭탄 1개, 결행 준비 +2, 군영 첩보 +1, 노출 +1")
	ok(g.police.has(0) and g.mission_row.is_empty() and g.markers.is_empty() and g.steps_left == 0, "폭파: 시끄러움(경찰이 붙음), 마커는 사라지고 이동은 멈춤")
	# 망보기: 옆 칸에 다른 요원이 있으면 경찰이 안 붙음
	var g2 := _new(CH)
	_flat(g2)
	_mission(g2, "m_rail_bomb", {"target": Vector2i(5, 7)})
	g2.players[0]["bombs"] = 1
	g2.players[1]["pos"] = Vector2i(6, 7)
	_turn(g2, 0, 4)
	_step(g2, 0, Vector2i(5, 6), false)
	_step(g2, 0, Vector2i(5, 7), false)
	ok(g2.exposure == 1 and not g2.police.has(0) and g2.ready == 2, "폭파 보너스: 다른 요원이 옆 칸에 있으면(망보기) 경찰이 안 붙음 (노출은 오름)")
	ok(not g2.players[0]["flags"].get("entry_no_police", false), "폭파 보너스: 「경찰이 안 붙음」이 다음 거점 진입까지 남지 않음")
	# 폭탄이 없으면 그냥 지나가는 칸
	var g3 := _new(CH)
	_flat(g3)
	_mission(g3, "m_rail_bomb", {"target": Vector2i(5, 7)})
	_turn(g3, 0, 4)
	_step(g3, 0, Vector2i(5, 6), false)
	_step(g3, 0, Vector2i(5, 7), false)
	ok(g3.ready == 0 and g3.steps_left == 2 and g3.mission_row == ["m_rail_bomb"], "폭파: 폭탄이 없으면 그냥 지나가는 칸 (멈추지 않음)")
	# 전신선 폭파: 모든 경찰 2칸 물러남, 내일 위협을 덱 밑으로, 쫓기지 않고 이루면 준비 +1
	var g4 := _new(CH)
	_flat(g4)
	_mission(g4, "m_telegraph_bomb", {"target": Vector2i(5, 7)})
	g4.players[0]["bombs"] = 1
	g4.players[1]["pos"] = Vector2i(2, 5)
	g4.police[1] = {"pos": Vector2i(3, 5), "summon_turn": 0}
	g4.threat_deck = ["calm_day", "curfew", "monsoon"]
	_turn(g4, 0, 4)
	_step(g4, 0, Vector2i(5, 6), false)
	_step(g4, 0, Vector2i(5, 7), false)
	_cov("mission", "m_telegraph_bomb")
	ok(g4.ready == 2 and g4.intel["police_hq"] == 1, "전신선 폭파: 결행 준비 +1 +1(쫓기지 않고 이룸), 경찰서 첩보 +1")
	ok(g4.police.has(1) and g4.walk_dist(g4.police[1]["pos"], g4.players[1]["pos"]) == 3, "전신선 폭파: 모든 경찰이 2칸 물러남 (동료를 쫓던 경찰: 1칸 → 3칸)")
	ok(g4.threat_deck[0] == "monsoon" or g4.threat_deck[-1] != "monsoon", "전신선 폭파: 내일 위협(덱 맨 위)이 덱 맨 아래로")
	ok(g4.threat_deck == ["monsoon", "calm_day", "curfew"], "전신선 폭파: 위협 덱 순서 확인")
	# 보급: 멈추면 폭탄을 얻음
	var g5 := _new(CH)
	_flat(g5)
	_tile(g5, Vector2i(5, 6), "supply")
	var supply_before := g5.bomb_supply
	_turn(g5, 0, 1)
	_step(g5, 0, Vector2i(5, 6))
	ok(g5.players[0]["bombs"] == 1 and g5.bomb_supply == supply_before - 1, "보급: 멈추면 폭탄을 얻음")
	var g6 := _new(["seok", "han", "oh", "seo"])
	_flat(g6)
	g6.players[0]["bombs"] = 1
	_tile(g6, Vector2i(5, 6), "supply")
	_turn(g6, 0, 1)
	_step(g6, 0, Vector2i(5, 6))
	ok(g6.players[0]["bombs"] == 2, "석 기술자: 폭탄 칸이 둘이라 두 번째도 얻음")
	var g7 := _new(CH)
	_flat(g7)
	g7.players[0]["bombs"] = 1
	_tile(g7, Vector2i(5, 6), "supply")
	_turn(g7, 0, 1)
	_step(g7, 0, Vector2i(5, 6))
	ok(g7.players[0]["bombs"] == 1, "보급: 폭탄 칸이 찼으면 더 못 가짐")


func _test_c_work() -> void:
	# 전단 살포: 마커마다 주사위 하나 (눈 상관없음), 하루 만에 셋 다 하면 보너스
	var g := _new(CH)
	_flat(g)
	g.exposure = 3
	_mission(g, "m_leaflets")
	var cells: Array = g.markers_of("m_leaflets", "work").map(func(m): return m["pos"])
	_at(g, 0, cells[0])
	ok(_give_die_to(g, 0, 1), "공작(마커마다 하나): 눈이 1이어도 바칠 수 있음")
	ok(g.markers_of("m_leaflets", "work").size() == 2 and g.mission_row == ["m_leaflets"], "공작(마커마다 하나): 바친 마커만 사라지고 미션은 이어짐")
	ok(not g.apply({"type": "work_give", "player": 0, "die": _spare(g, 3, 0)}), "공작(마커마다 하나): 이미 바친 자리에는 또 바칠 수 없음")
	_end(g, 0)
	_at(g, 1, cells[1])
	_give_die_to(g, 1, 6)
	_end(g, 1)
	_at(g, 2, cells[2])
	_give_die_to(g, 2, 2)
	_cov("mission", "m_leaflets")
	ok(g.mission_row.is_empty() and g.markers.is_empty() and g.ready == 2 and g.exposure == 1, "전단 살포: 하루 만에 셋 다 하면 노출 −2, 결행 준비 +1 +1")
	var g2 := _new(CH)
	_flat(g2)
	g2.exposure = 3
	_mission(g2, "m_leaflets")
	var cells2: Array = g2.markers_of("m_leaflets", "work").map(func(m): return m["pos"])
	_at(g2, 0, cells2[0])
	_give_die_to(g2, 0, 4)
	_end(g2, 0)
	g2.day = 2
	_at(g2, 1, cells2[1])
	_give_die_to(g2, 1, 4)
	_end(g2, 1)
	_at(g2, 2, cells2[2])
	_give_die_to(g2, 2, 4)
	ok(g2.mission_row.is_empty() and g2.ready == 1 and g2.exposure == 1, "전단 살포: 이틀에 걸쳐 하면 보너스 없음 (노출 −2, 결행 준비 +1)")

	# 쌀 창고 열기: 합 8, 여러 요원이 나눠 바치면 보너스
	var g3 := _new(CH)
	_flat(g3)
	g3.exposure = 3
	_mission(g3, "m_open_rice", {"work": Vector2i(5, 7)})
	_at(g3, 0, Vector2i(5, 7))
	_give_die_to(g3, 0, 5)
	ok(g3.mission_state["m_open_rice"]["sum"] == 5 and g3.card_status("m_open_rice") == "바친 합 5 / 8", "공작(합): 바친 눈이 쌓임")
	_end(g3, 0)
	g3.day = 2
	_at(g3, 1, Vector2i(5, 7))
	_give_die_to(g3, 1, 4)
	_cov("mission", "m_open_rice")
	ok(g3.mission_row.is_empty() and g3.players[1]["items"].size() == 1 and g3.exposure == 1 and g3.ready == 1, "쌀 창고 열기: 두 요원이 나눠 바치면 아이템 1장(마지막에 바친 요원), 노출 −1에 −1 더, 결행 준비 +1")
	ok(g3.players[0]["items"].is_empty(), "쌀 창고 열기: 아이템은 마지막에 바친 요원만")
	var g4 := _new(CH)
	_flat(g4)
	_mission(g4, "m_open_rice", {"work": Vector2i(5, 7)})
	_at(g4, 0, Vector2i(5, 7))
	_give_die_to(g4, 0, 6)
	_give_die_to(g4, 0, 2)
	ok(g4.mission_row.is_empty() and g4.players[0]["items"].size() == 1, "쌀 창고 열기: 한 요원이 혼자 채우면 보너스 없이 아이템 1장")
	ok(not g4.apply({"type": "work_give", "player": 0, "die": _spare(g4, 3, 0)}), "공작: 이룬 뒤에는 바칠 수 없음 (마커가 사라짐)")

	# 징용 명단 불태우기: 눈 조합 1·3·5 — 필요한 눈만 바칠 수 있고, 여러 날·여러 요원이 나눠도 됨
	var g5 := _new(CH)
	_flat(g5)
	g5.exposure = 3
	_mission(g5, "m_burn_conscript", {"work": Vector2i(5, 7)})
	_at(g5, 0, Vector2i(5, 7))
	var d2 := _spare(g5, 2, 0)
	ok(not g5.apply({"type": "work_give", "player": 0, "die": d2}), "공작(조합): 필요 없는 눈(2)은 바칠 수 없음")
	var legal_before := g5.legal_actions().filter(func(a): return a["type"] == "work_give")
	ok(legal_before.is_empty(), "공작(조합): 필요한 눈이 없으면 바치기 행동이 없음")
	_give_die_to(g5, 0, 3)
	ok(g5.mission_state["m_burn_conscript"]["left"] == [1, 5] and g5.card_status("m_burn_conscript") == "남은 눈 1·5", "공작(조합): 바친 눈(3)은 조합에서 빠짐")
	ok(not g5.apply({"type": "work_give", "player": 0, "die": _spare(g5, 3, 0)}), "공작(조합): 같은 눈을 두 번은 안 됨")
	_give_die_to(g5, 0, 1)
	_end(g5, 0)
	_at(g5, 1, Vector2i(5, 7))
	_give_die_to(g5, 1, 5)
	_cov("mission", "m_burn_conscript")
	ok(g5.mission_row.is_empty() and g5.intel["prison"] == 2 and g5.ready == 1 and g5.exposure == 2, "징용 명단 불태우기: 1·3·5를 채우면 형무소 첩보 +2, 결행 준비 +1, 하루 만에 끝내면 노출 −1")
	# 문 선전대원: 조합에서 눈 하나를 빼고, 이루면 노출 −1
	var g6 := _new(["mun", "han", "oh", "seo"])
	_flat(g6)
	g6.exposure = 3
	_mission(g6, "m_burn_conscript", {"work": Vector2i(5, 7)})
	_at(g6, 0, Vector2i(5, 7))
	_give_die_to(g6, 0, 3)
	ok(g6.mission_state["m_burn_conscript"]["left"] == [1], "특성 문 선전대원(work_reduce): 조합에서 눈 하나를 빼고 시작 (남은 눈 1)")
	_give_die_to(g6, 0, 1)
	ok(g6.mission_row.is_empty() and g6.exposure == 1, "특성 문 선전대원(work_exposure): 공작을 이루면 노출 −1 (+같은 날 −1)")
	var g7 := _new(["mun", "han", "oh", "seo"])
	_flat(g7)
	_mission(g7, "m_open_rice", {"work": Vector2i(5, 7)})
	_at(g7, 0, Vector2i(5, 7))
	_give_die_to(g7, 0, 6)
	ok(g7.mission_row.is_empty(), "특성 문 선전대원: 합 공작은 합이 2 줄어 6으로 이룸")
	_cov("trait", "mun")
	# 암호 해독: 2·4·6
	var g8 := _new(CH)
	_flat(g8)
	_mission(g8, "m_decode", {"work": Vector2i(5, 7)})
	_at(g8, 0, Vector2i(5, 7))
	for v in [6, 2, 4]:
		_give_die_to(g8, 0, v)
	_cov("mission", "m_decode")
	ok(g8.mission_row.is_empty() and g8.intel["gg"] == 3 and g8.ready == 1, "암호 해독: 2·4·6을 채우면 총독부 첩보 +2 (+쫓기지 않는 요원이 마지막 눈을 바치면 +1), 결행 준비 +1")
	var g9 := _new(CH)
	_flat(g9)
	g9.police[0] = {"pos": _base(g9, "barracks"), "summon_turn": 0}
	_mission(g9, "m_decode", {"work": Vector2i(5, 7)})
	_at(g9, 0, Vector2i(5, 7))
	for v in [6, 2, 4]:
		_give_die_to(g9, 0, v)
	ok(g9.intel["gg"] == 2, "암호 해독: 쫓기는 요원이 마지막 눈을 바치면 첩보 보너스 없음")
	# 바칠 곳이 아닌 데서는 바칠 수 없다
	var ga := _new(CH)
	_flat(ga)
	_mission(ga, "m_open_rice", {"work": Vector2i(5, 7)})
	_at(ga, 0, Vector2i(5, 6))
	ok(not ga.apply({"type": "work_give", "player": 0, "die": _spare(ga, 5, 0)}), "공작: 마커 칸이 아닌 곳에서는 바칠 수 없음")
	# 감옥·걷는 중에는 바칠 수 없다
	ga.players[0]["pos"] = Vector2i(5, 7)
	ga.players[0]["jailed"] = true
	ok(not ga.apply({"type": "work_give", "player": 0, "die": _spare(ga, 5, 0)}), "공작: 갇힌 요원은 바칠 수 없음")


func _test_c_contact() -> void:
	# 비밀 문서 전달: 받기 마커를 지나가며 들고, 주기 마커에 들어가면 이룸
	var g := _new(CH)
	_flat(g)
	_mission(g, "m_secret_docs", {"pickup": Vector2i(5, 8), "dropoff": Vector2i(5, 6)})
	_turn(g, 0, 6)
	_step(g, 0, Vector2i(5, 6), false)
	ok(g.mission_row == ["m_secret_docs"] and g.mission_state["m_secret_docs"]["holder"] == -1, "연락: 물건을 들기 전에 주기 마커에 가도 이루지 않음")
	_step(g, 0, Vector2i(5, 7), false)
	_step(g, 0, Vector2i(5, 8), false)
	ok(g.mission_state["m_secret_docs"]["holder"] == 0 and g.steps_left == 3, "연락: 받기 마커를 지나가면 물건을 듦 (멈추지 않고 이동 계속)")
	ok(g.card_status("m_secret_docs") == "%s이(가) 들고 있음" % g.players[0]["name"], "연락: 진행 표시 (든 요원)")
	_step(g, 0, Vector2i(5, 7), false)
	_step(g, 0, Vector2i(5, 6), false)
	_cov("mission", "m_secret_docs")
	ok(g.mission_row.is_empty() and g.ready == 3 and g.intel["gg"] == 2 and g.steps_left == 0, "비밀 문서 전달: 이룸 — 결행 준비 +2, 총독부 첩보 +2, 한 번도 안 쫓기면 결행 준비 +1")
	ok(g.exposure == 0 and not g.police.has(0), "연락: 시끄럽지 않음")
	# 쫓기는 채로 차례를 마치면 보너스가 없음
	var g2 := _new(CH)
	_flat(g2)
	_mission(g2, "m_secret_docs", {"pickup": Vector2i(5, 8), "dropoff": Vector2i(5, 6)})
	_turn(g2, 0, 3)
	_step(g2, 0, Vector2i(5, 6), false)
	_step(g2, 0, Vector2i(5, 7), false)
	_step(g2, 0, Vector2i(5, 8), false)
	g2.police[0] = {"pos": Vector2i(5, 4), "summon_turn": 0}
	_end(g2, 0)
	ok(g2.police.has(0) and g2.mission_state["m_secret_docs"]["chased"], "연락: 물건을 든 요원이 쫓기는 채로 차례를 마치면 기록")
	g2.players[0]["done_today"] = false
	g2.police.erase(0)
	_turn(g2, 0, 3)
	_step(g2, 0, Vector2i(5, 7), false)
	_step(g2, 0, Vector2i(5, 6), false)
	ok(g2.mission_row.is_empty() and g2.ready == 2, "연락: 한 번이라도 쫓겼으면 보너스 없음")
	# 잡히면 물건은 받기 마커로 돌아감
	var g3 := _new(CH)
	_flat(g3)
	_mission(g3, "m_secret_docs", {"pickup": Vector2i(5, 8), "dropoff": Vector2i(5, 6)})
	_turn(g3, 0, 3)
	_step(g3, 0, Vector2i(5, 6), false)
	_step(g3, 0, Vector2i(5, 7), false)
	_step(g3, 0, Vector2i(5, 8), false)
	ok(g3.mission_state["m_secret_docs"]["holder"] == 0, "연락: 물건을 듦")
	g3._jail(g3.players[0])
	ok(g3.mission_state["m_secret_docs"]["holder"] == -1 and g3.markers_of("m_secret_docs", "pickup")[0]["pos"] == Vector2i(5, 8), "연락: 든 요원이 잡히면 물건은 받기 마커로 돌아감")
	g3.players[1]["pos"] = Vector2i(5, 9)
	_turn(g3, 1, 1)
	_step(g3, 1, Vector2i(5, 8), false)
	ok(g3.mission_state["m_secret_docs"]["holder"] == 1, "연락: 다른 요원이 받기 마커에서 이어 받을 수 있음")
	# 이미 누가 들고 있으면 다른 요원이 지나가도 못 받음
	g3.players[2]["pos"] = Vector2i(5, 9)
	_turn(g3, 2, 1)
	_step(g3, 2, Vector2i(5, 8), false)
	ok(g3.mission_state["m_secret_docs"]["holder"] == 1, "연락: 이미 든 사람이 있으면 못 받음")

	# 무기 운반: 무거움 — 든 요원은 이동 눈 −1
	var g4 := _new(CH)
	_flat(g4)
	_mission(g4, "m_arms_run", {"pickup": Vector2i(5, 7), "dropoff": Vector2i(5, 9)})
	_turn(g4, 0, 4)
	_step(g4, 0, Vector2i(5, 6), false)
	ok(g4.heavy_count(g4.players[0]) == 0, "무거운 물건: 들기 전에는 보통")
	_step(g4, 0, Vector2i(5, 7), false)
	ok(g4.heavy_count(g4.players[0]) == 1, "무거운 물건: 든 요원은 무거운 물건 1개")
	var dv := _spare(g4, 4, 0)
	var d1 := _spare(g4, 1, 0)
	ok(g4.move_value(g4.players[0], dv) == 3 and g4.move_value(g4.players[0], d1) == 1, "무거운 물건: 이동 눈 −1 (최소 1)")
	ok(g4.move_value(g4.players[1], _spare(g4, 4, 1)) == 4, "무거운 물건: 안 든 요원은 그대로 (대조)")
	# 무기 운반을 이룸: 나른 요원 폭탄 2개(손 한도까지), 하루 만에 나르면 폭탄 +1
	var g5 := _new(["seok", "han", "oh", "seo"])
	_flat(g5)
	_mission(g5, "m_arms_run", {"pickup": Vector2i(5, 6), "dropoff": Vector2i(5, 7)})
	_turn(g5, 0, 3)
	_step(g5, 0, Vector2i(5, 6), false)
	_step(g5, 0, Vector2i(5, 7), false)
	_cov("mission", "m_arms_run")
	ok(g5.mission_row.is_empty() and g5.ready == 1 and g5.players[0]["bombs"] == 2, "무기 운반: 결행 준비 +1, 폭탄은 손 한도(석 기술자 2개)까지")
	var g6 := _new(CH)
	_flat(g6)
	_mission(g6, "m_arms_run", {"pickup": Vector2i(5, 6), "dropoff": Vector2i(5, 7)})
	_turn(g6, 0, 3)
	_step(g6, 0, Vector2i(5, 6), false)
	_step(g6, 0, Vector2i(5, 7), false)
	ok(g6.players[0]["bombs"] == 1, "무기 운반: 손 한도(1개)를 넘는 폭탄은 보급에 남음")
	ok(g6.bomb_supply == int(g6.data.rules["bomb_supply"]) - 1, "무기 운반: 못 받은 폭탄은 보급으로")

	# 군영 보급 장부: 군영에 들어가야 받음 (경찰이 붙음), 같은 날 받고 주면 보너스
	var g7 := _new(CH)
	_flat(g7)
	var bk := _base(g7, "barracks")
	_mission(g7, "m_supply_ledger", {"dropoff": bk + Vector2i(1, 0)})
	g7.players[0]["pos"] = bk + Vector2i(2, 0)
	_turn(g7, 0, 3)
	_step(g7, 0, bk + Vector2i(1, 0), false)
	ok(g7.mission_state["m_supply_ledger"]["holder"] == -1, "군영 보급 장부: 군영 밖에서는 받지 못함")
	_step(g7, 0, bk, false)
	ok(g7.mission_state["m_supply_ledger"]["holder"] == 0 and g7.police.has(0), "군영 보급 장부: 군영에 들어가면 장부를 받음 (경찰이 붙음)")
	g7.players[0]["pos"] = bk + Vector2i(2, 0)
	g7.players[0]["done_today"] = false
	g7.phase = "day"
	g7.police.erase(0)
	_turn(g7, 0, 3)
	_step(g7, 0, bk + Vector2i(1, 0), false)
	_cov("mission", "m_supply_ledger")
	ok(g7.mission_row.is_empty() and g7.ready == 3 and g7.intel["barracks"] == 2, "군영 보급 장부: 주기 마커에 들어가면 이룸 — 결행 준비 +2, 군영 첩보 +2, 같은 날 받고 주면 +1")
	# 기한: 놓치면 노출 +1, 마커와 물건이 함께 사라짐
	var g8 := _new(CH)
	_flat(g8)
	_mission(g8, "m_secret_docs")
	g8.day = 1
	g8._morning_markers()
	ok(g8.card_days_left("m_secret_docs") == 5, "기한: 오늘 나온 카드는 오늘 줄이지 않음")
	for d in [2, 3, 4, 5]:
		g8.day = d
		g8._morning_markers()
	ok(g8.card_days_left("m_secret_docs") == 1 and g8.mission_row == ["m_secret_docs"], "기한: 아침마다 1씩 줆 (5일 → 1일)")
	g8.day = 6
	g8._morning_markers()
	ok(g8.mission_row.is_empty() and g8.markers.is_empty() and g8.mission_state.is_empty() and g8.exposure == 1 and g8.mission_discard.has("m_secret_docs"), "기한: 0이 되면 놓침 — 줄에서 빠지고 마커가 사라지고 노출 +1")


func _test_c_lurk() -> void:
	# 경찰서 감시: 마커 칸이나 옆 칸에서 쫓기지 않고 차례를 마친 날이 2일 (요원이 바뀌어도 됨, 같은 날은 한 번)
	var g := _new(CH)
	_flat(g)
	_mission(g, "m_police_watch", {"spot": Vector2i(5, 7)})
	_at(g, 0, Vector2i(5, 6))
	_end(g, 0)
	ok(g.mission_state["m_police_watch"]["lurk"] == 1 and g.card_status("m_police_watch") == "잠복 1 / 2일", "잠복: 옆 칸에서 쫓기지 않고 차례를 마치면 1일")
	_at(g, 1, Vector2i(5, 7))
	_end(g, 1)
	ok(g.mission_state["m_police_watch"]["lurk"] == 1, "잠복: 같은 날 다른 요원이 해도 1일 (같은 날은 한 번)")
	_at(g, 2, Vector2i(5, 9))
	_end(g, 2)
	ok(g.mission_state["m_police_watch"]["lurk"] == 1, "잠복: 마커에서 2칸 떨어지면 안 셈")
	g.day = 2
	g.police[3] = {"pos": Vector2i(5, 4), "summon_turn": 0}
	_at(g, 3, Vector2i(5, 8))
	_end(g, 3)
	ok(g.police.has(3) and g.mission_state["m_police_watch"]["lurk"] == 1, "잠복: 쫓기는 요원은 안 셈")
	g.police.erase(3)
	g.players[1]["done_today"] = false
	_at(g, 1, Vector2i(5, 7))
	_end(g, 1)
	_cov("mission", "m_police_watch")
	ok(not "m_police_watch" in g.mission_row and g.ready == 1 and g.intel["police_hq"] == 2, "경찰서 감시: 요원이 바뀌어도 2일이 차면 이룸 — 결행 준비 +1, 경찰서 첩보 +2")
	ok(g.peek_bonus == 1 and g.threat_preview().size() == 1, "경찰서 감시: 이번 판 동안 위협을 1장 더 미리 봄")
	var gj := _new(["jeong", "han", "oh", "seo"])
	gj.peek_bonus = 1
	ok(gj.threat_preview().size() == 3, "경찰서 감시: 정 인쇄공 특성(2장)과 겹치면 +1장 (3장)")
	# 갇힌 요원은 안 셈
	var g2 := _new(CH)
	_flat(g2)
	_mission(g2, "m_police_watch", {"spot": Vector2i(5, 7)})
	_at(g2, 0, Vector2i(5, 7))
	g2.players[0]["jailed"] = true
	_end(g2, 0)
	ok(g2.mission_state["m_police_watch"]["lurk"] == 0, "잠복: 갇힌 요원은 안 셈")
	# 총독부 동태 파악: 두 요원이 같은 날 하면 그날은 2일
	var g3 := _new(CH)
	_flat(g3)
	_mission(g3, "m_gg_watch", {"spot": Vector2i(5, 7)})
	_at(g3, 0, Vector2i(5, 6))
	_end(g3, 0)
	ok(g3.mission_state["m_gg_watch"]["lurk"] == 1, "총독부 동태 파악: 한 요원이면 1일")
	_at(g3, 0, Vector2i(5, 6))   # 같은 요원이 또 해도 안 됨 (이미 차례를 마쳤으므로 다른 요원)
	_at(g3, 1, Vector2i(4, 7))
	_end(g3, 1)
	_cov("mission", "m_gg_watch")
	ok(g3.mission_row.is_empty() and g3.intel["gg"] == 2 and g3.ready == 1, "총독부 동태 파악: 두 요원이 같은 날 하면 그날은 2일로 쳐 이룸 — 총독부 첩보 +2, 결행 준비 +1")
	# 쌀 공출(일제 작전): 1일이면 막음
	var g4 := _new(CH)
	_flat(g4)
	g4.exposure = 2
	_mission(g4, "op_rice_levy", {"spot": Vector2i(5, 7)})
	_at(g4, 0, Vector2i(5, 8))
	_end(g4, 0)
	_cov("mission", "op_rice_levy")
	ok(g4.op_row.is_empty() and g4.exposure == 1 and g4.ready == 0, "쌀 공출: 마커 곁에서 쫓기지 않고 차례를 마치면 막음 — 노출 −1")


func _test_c_tiles() -> void:
	# 골목: 이동을 마치면 나를 쫓는 경찰이 2칸 물러남, 5칸 넘게 벌어지면 따돌림, 숨기 가능
	var g := _new(CH)
	_flat(g)
	_tile(g, Vector2i(5, 6), "alley")
	g.players[0]["pos"] = START
	g.police[0] = {"pos": Vector2i(5, 8), "summon_turn": 0}
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(5, 6), false)
	ok(g.police.has(0) and g.walk_dist(g.police[0]["pos"], Vector2i(5, 6)) == 4, "골목: 이동을 마치면 나를 쫓는 경찰이 2칸 물러남 (2칸 → 4칸)")
	var g2 := _new(CH)
	_flat(g2)
	_tile(g2, Vector2i(5, 6), "alley")
	g2.police[0] = {"pos": Vector2i(9, 6), "summon_turn": 0}
	_turn(g2, 0, 1)
	_step(g2, 0, Vector2i(5, 6), false)
	ok(not g2.police.has(0), "골목: 5칸 넘게 벌어지면 따돌림 (경찰이 사라짐)")
	var g3 := _new(CH)
	_flat(g3)
	_tile(g3, Vector2i(5, 6), "alley")
	g3.police[1] = {"pos": Vector2i(5, 8), "summon_turn": 0}
	_turn(g3, 0, 1)
	_step(g3, 0, Vector2i(5, 6), false)
	ok(g3.police[1]["pos"] == Vector2i(5, 8), "골목: 다른 요원을 쫓는 경찰은 안 물러남")
	# 같은 칸의 효과는 한 차례에 한 번 — 골목에서 나갔다 들어와도 또 밀어내지 않음
	var g4 := _new(CH)
	_flat(g4)
	_tile(g4, Vector2i(5, 6), "alley")
	g4.police[0] = {"pos": Vector2i(5, 9), "summon_turn": 0}
	_turn(g4, 0, 1)
	_step(g4, 0, Vector2i(5, 6), false)
	var pos1: Vector2i = g4.police[0]["pos"]
	g4.apply({"type": "move_die", "player": 0, "die": _spare(g4, 1, 0)})
	g4.apply({"type": "step", "player": 0, "to": START})
	g4.apply({"type": "move_die", "player": 0, "die": _spare(g4, 1, 0)})
	g4.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)})
	ok(not g4.police.has(0) or g4.police[0]["pos"] == pos1, "골목: 같은 칸의 효과는 한 차례에 한 번 (나갔다 들어와도 또 밀지 않음)")
	_tile(g, Vector2i(5, 7), "alley")
	g.players[0]["pos"] = Vector2i(5, 7)
	g.players[0]["hidden"] = false
	g.players[0]["done_today"] = false
	g.phase = "day"
	_turn(g, 0, 0)
	_spare(g, 3, 0)
	ok(g.can_hide(g.players[0]), "골목: 숨기 가능")

	# 감시탑: 이동을 마치면 노출 +1, 지나가기만 하면 괜찮음
	var g5 := _new(CH)
	_flat(g5)
	_tile(g5, Vector2i(5, 6), "watchtower")
	_turn(g5, 0, 2)
	_step(g5, 0, Vector2i(5, 6), false)
	ok(g5.exposure == 0 and g5.steps_left == 1, "감시탑: 지나가기만 하면 노출은 그대로")
	_step(g5, 0, Vector2i(5, 7), false)
	ok(g5.exposure == 0, "감시탑: 지나간 뒤 다른 칸에서 멈추면 노출 없음")
	var g6 := _new(CH)
	_flat(g6)
	_tile(g6, Vector2i(5, 6), "watchtower")
	_turn(g6, 0, 1)
	_step(g6, 0, Vector2i(5, 6), false)
	ok(g6.exposure == 1, "감시탑: 이동을 마치면 노출 +1")

	# 주막: 동료와 같은 칸에서 차례를 마치면 노출 −1 (하루 한 번), 숨기 가능
	var g9 := _new(CH)
	_flat(g9)
	g9.exposure = 2
	_tile(g9, Vector2i(5, 6), "tavern")
	g9.players[0]["pos"] = Vector2i(5, 6)
	g9.players[1]["pos"] = Vector2i(5, 6)
	g9.players[2]["pos"] = Vector2i(5, 6)
	_turn(g9, 0, 0)
	_end(g9, 0)
	ok(g9.exposure == 1, "주막: 동료와 같은 칸에서 차례를 마치면 노출 −1")
	_turn(g9, 1, 0)
	_end(g9, 1)
	ok(g9.exposure == 1, "주막: 하루 한 번만")
	g9.today = g9._new_today()
	g9.players[2]["done_today"] = false
	_turn(g9, 2, 0)
	_end(g9, 2)
	ok(g9.exposure == 0, "주막: 다음 날에는 또 받음")
	var g10 := _new(CH)
	_flat(g10)
	g10.exposure = 2
	_tile(g10, Vector2i(5, 6), "tavern")
	g10.players[0]["pos"] = Vector2i(5, 6)
	_turn(g10, 0, 0)
	_end(g10, 0)
	ok(g10.exposure == 2, "주막: 혼자서는 효과 없음")
	var g11 := _new(CH)
	_flat(g11)
	g11.exposure = 2
	_tile(g11, Vector2i(5, 6), "tavern")
	g11.players[0]["pos"] = Vector2i(5, 6)
	g11.players[1]["pos"] = Vector2i(5, 6)
	g11.players[1]["jailed"] = true
	_turn(g11, 0, 0)
	_end(g11, 0)
	ok(g11.exposure == 2, "주막: 갇힌 동료는 셈하지 않음")
	var g12 := _new(CH)
	_flat(g12)
	_tile(g12, Vector2i(5, 6), "tavern")
	g12.players[0]["pos"] = Vector2i(5, 6)
	_turn(g12, 0, 0)
	_spare(g12, 3, 0)
	ok(g12.can_hide(g12.players[0]), "주막: 숨기 가능")
	var g13 := _new(CH)
	_flat(g13)
	g13.players[0]["pos"] = Vector2i(5, 6)
	_turn(g13, 0, 0)
	_spare(g13, 3, 0)
	ok(not g13.can_hide(g13.players[0]), "숨기: 일반 칸에서는 못 함 (대조)")
	# 최 훈장 「마을 사람들」: 새 타일도 더미에서 골라 깔 수 있음
	var g14 := _new(["choi", "han", "oh", "seo"])
	_flat(g14)
	var labels := g14._tile_type_options().map(func(o): return str(o["label"]))
	ok(labels.any(func(l): return "골목" in l) and labels.any(func(l): return "주막" in l), "최 훈장 마을 사람들: 더미에서 골목·주막 같은 새 타일도 고를 수 있음")
	# 이벤트 「뒷골목 발견」·「순사의 눈」은 새 타일 구성에서도 돈다 (더미의 길·검문소를 한 장 꺼내 깐다)
	var g15 := _new(CH)
	var normals := g15.tile_deck.count("normal")
	var checks := g15.tile_deck.count("check")
	_event(g15, 0, "back_alley")
	_answer_all(g15)
	ok(g15.tile_deck.count("normal") == normals - 1 and normals == 42, "이벤트 뒷골목 발견: 새 구성(길 42장)에서도 길 타일을 더미에서 한 장 꺼내 깜")
	var g16 := _new(CH)
	_event(g16, 0, "cop_eye")
	_answer_all(g16)
	ok(g16.tile_deck.count("check") == checks - 1 and checks == 6, "이벤트 순사의 눈: 새 구성(검문소 6장)에서도 검문소를 한 장 깜")


func _test_c_ops() -> void:
	# 일제 검거령: 합 6 바치면 막음 (노출 −1, 동향은 그대로)
	var g := _new(CH)
	_flat(g)
	g.exposure = 3
	g.trend = 2
	_mission(g, "op_roundup", {"work": Vector2i(5, 7)})
	_at(g, 0, Vector2i(5, 7))
	_give_die_to(g, 0, 4)
	ok(g.op_row == ["op_roundup"] and g.card_status("op_roundup") == "바친 합 4 / 6", "일제 검거령: 합 6을 나눠 바칠 수 있음 (진행 표시)")
	_give_die_to(g, 0, 3)
	_cov("mission", "op_roundup")
	ok(g.op_row.is_empty() and g.exposure == 2 and g.trend == 2 and g.ready == 0 and g.op_discard == ["op_roundup"], "일제 검거령: 막으면 노출 −1, 동향은 그대로 (결행 준비는 오르지 않음)")
	ok(g.players[0]["stats"]["missions"] == 0, "일제 작전: 막아도 미션 통계에는 안 셈")
	# 신문 검열: 눈 2·4
	var g2 := _new(CH)
	_flat(g2)
	g2.exposure = 3
	_mission(g2, "op_censorship", {"work": Vector2i(5, 7)})
	_at(g2, 0, Vector2i(5, 7))
	_give_die_to(g2, 0, 4)
	_give_die_to(g2, 0, 2)
	_cov("mission", "op_censorship")
	ok(g2.op_row.is_empty() and g2.exposure == 2, "신문 검열: 눈 2·4를 하나씩 바치면 막음 — 노출 −1")
	# 밀정 침투: 표적 칸에서 작전 판정 7 (시끄럽지 않음), 실패하면 회피 판정
	var gd := _mission_gd(0, 7)
	var g3 := _new(CH, gd)
	_flat(g3)
	g3.exposure = 3
	_mission(g3, "op_spy_raid", {"target": Vector2i(5, 7)})
	_turn(g3, 0, 3)
	_step(g3, 0, Vector2i(5, 6), false)
	_step(g3, 0, Vector2i(5, 7), false)
	ok(g3.steps_left == 0, "밀정 침투: 표적 칸에서 이동이 멈춤")
	_mcheck(g3, 0)
	_cov("mission", "op_spy_raid")
	ok(g3.op_row.is_empty() and g3.exposure == 2 and not g3.police.has(0), "밀정 침투: 작전 판정에 성공하면 막음 — 노출 −1, 시끄럽지 않음(경찰·노출 증가 없음)")
	var gd2 := _mission_gd(99, 99)
	var g4 := _new(CH, gd2)
	_flat(g4)
	_mission(g4, "op_spy_raid", {"target": Vector2i(5, 6)})
	_turn(g4, 0, 2)
	_step(g4, 0, Vector2i(5, 6), false)
	_mcheck(g4, 0)
	ok(g4.players[0]["jailed"] and g4.op_row == ["op_spy_raid"], "밀정 침투: 암살처럼 — 실패하고 회피도 실패하면 투옥")
	ok(_last_dice(g4, "작전").get("target", -1) == 99, "밀정 침투: 판정 이름은 「작전」 (목표 7이 아니라 시험용 수치)")
	var g4b := _new(CH)
	_flat(g4b)
	_mission(g4b, "op_spy_raid", {"target": Vector2i(5, 6)})
	ok(g4b.check_preview(g4b.players[0], {"type": "mission_check", "cell": Vector2i(5, 6)})["target"] == 7, "밀정 침투: 작전 판정 목표 7")
	# 못 막았을 때: 카드의 벌칙 + 동향 단계별 추가 벌칙, 동향 +1
	var gdt := _gd(func(d): d.rules["exposure"]["thresholds"] = [8, 9])
	var expect_exp := {0: 2, 1: 2, 2: 3, 3: 3, 4: 3, 5: 3, 6: 3}
	for tv in [0, 1, 2, 3, 4, 5, 6]:
		var gt := _new(CH, gdt)
		_flat(gt)
		gt.ready = 2
		_mission(gt, "op_roundup", {"work": Vector2i(5, 7)})
		gt.trend = tv
		gt.expire_queue = ["op_roundup"]
		gt._morning_expire()
		var police_n: int = gt.police.size()
		var ready_ok: bool = gt.ready == (1 if tv >= 6 else 2)
		ok(gt.exposure == expect_exp[tv] and (police_n == (1 if tv >= 4 else 0)) and ready_ok and gt.trend == mini(tv + 1, 6) and gt.op_row.is_empty() and gt.markers.is_empty(),
			"동향 %d: 못 막으면 노출 %+d%s%s, 동향 %d" % [tv, expect_exp[tv], ", 경찰 출동" if tv >= 4 else "", ", 결행 준비 −1" if tv >= 6 else "", mini(tv + 1, 6)])
	var gp := _new(CH, gdt)
	_flat(gp)
	_mission(gp, "op_roundup", {"work": Vector2i(5, 7)})
	gp.trend = 4
	gp.expire_queue = ["op_roundup"]
	gp._morning_expire()
	ok(gp.police.size() == 1 and gp.police.values()[0]["pos"] == gp.data.bases[gp._nearest_base(Vector2i(5, 7))], "동향 4: 마커에서 가장 가까운 거점에서 경찰이 출동")
	# 카드별 벌칙
	var gs := _new(CH, gdt)
	_flat(gs)
	gs.intel["prison"] = 2
	gs.intel["gg"] = 1
	_mission(gs, "op_censorship", {"work": Vector2i(5, 7)})
	gs.expire_queue = ["op_censorship"]
	gs._morning_expire()
	ok(gs.intel["prison"] == 1 and gs.intel["gg"] == 1, "신문 검열: 못 막으면 첩보가 가장 높은 거점의 첩보 −1")
	var gr := _new(CH, gdt)
	_flat(gr)
	for i in 3:
		gr.players[i]["items"] = ["train_ticket"]
	_mission(gr, "op_rice_levy", {"spot": Vector2i(5, 7)})
	gr.expire_queue = ["op_rice_levy"]
	gr._morning_expire()
	ok(gr.players[0]["items"].is_empty() and gr.players[1]["items"].is_empty() and gr.players[2]["items"].is_empty() and gr.players[3]["items"].is_empty(), "쌀 공출: 못 막으면 모든 요원이 아이템 1장을 버림")
	var gm := _new(CH, gdt)
	_flat(gm)
	gm.ready = 3
	_mission(gm, "op_spy_raid", {"target": Vector2i(5, 7)})
	gm.expire_queue = ["op_spy_raid"]
	gm._morning_expire()
	ok(gm.ready == 2, "밀정 침투: 못 막으면 결행 준비 −1")
	# 기한: 나온 날은 안 줄고, 날마다 1씩 줄어 0이면 놓침
	var go := _new(CH, gdt)
	_flat(go)
	go.day = 2
	_mission(go, "op_rice_levy", {"spot": Vector2i(5, 7)})
	go._morning_markers()
	ok(go.card_days_left("op_rice_levy") == 2, "일제 작전 기한: 나온 날 아침에는 줄이지 않음")
	go.day = 3
	go._morning_markers()
	ok(go.card_days_left("op_rice_levy") == 1 and go.op_row == ["op_rice_levy"], "일제 작전 기한: 다음 날 아침 1일")
	go.day = 4
	go._morning_markers()
	ok(go.op_row.is_empty() and go.trend == 1, "일제 작전 기한: 0이 되면 놓침 (동향 +1)")


func _test_c_morning() -> void:
	# 아침 순서: 위협 → 일제 작전 → 표적 이동·기한 → 투표 → 미션 줄 → 주사위
	var g := _new(CH)
	_flat(g)
	g.act = 1
	g.phase = "morning"
	g.morning_step = 1
	g.day = 2
	g.threat_deck = ["calm_day"]
	g.ready = 0
	g.log_lines.clear()
	_mission(g, "m_police_chief", {"target": Vector2i(5, 3)})
	g.mission_state["m_police_chief"]["placed"] = 1
	g._morning_continue()
	ok(g.morning_step == 7 and g.phase == "plan" and not g.op_dice.is_empty(), "아침 순서: 여섯 단계 (morning_step 7에서 끝)")
	var li := {}
	for i in g.log_lines.size():
		var l := str(g.log_lines[i])
		if l.begins_with("[일제 위협]") and not li.has("threat"):
			li["threat"] = i
		elif l.begins_with("[일제 작전]") and not li.has("op"):
			li["op"] = i
		elif l.begins_with("공개 미션:") and not li.has("row"):
			li["row"] = i
		elif l.begins_with("작전 주사위:") and not li.has("dice"):
			li["dice"] = i
	ok(li.has("threat") and li.has("op") and li.has("row") and li.has("dice") and li["threat"] < li["op"] and li["op"] < li["row"] and li["row"] < li["dice"], "아침 순서: 위협 → 일제 작전 → … → 미션 줄 → 작전 주사위 (로그 순서)")
	ok(g.op_row.size() == 1 and g.trend == 1 and g.markers_of(g.op_row[0]).size() >= 1, "일제 작전: 2일째 아침에 1장 — 마커가 놓이고 동향 +1")
	ok(g.card_days_left("m_police_chief") == 3, "아침: 먼저 나온 미션의 기한이 1 줆 (4일 → 3일)")
	ok(g.mission_row.size() == int(g.data.rules["mission_row"]), "아침: 미션 줄이 채워짐")
	var all_marked := true
	for id in g.mission_row:
		if not g.mission_state.has(id) or (not g.data.mission(id).get("markers", []).is_empty() and g.markers_of(id).is_empty()):
			all_marked = false
	ok(all_marked, "아침: 새로 채운 미션마다 마커가 놓임")
	# 짝수 날만 (2·4·6·8)
	var g2 := _new(CH)
	_flat(g2)
	var ops_days := []
	for d in range(1, 12):
		g2.day = d
		var before := g2.op_row.size() + g2.op_discard.size()
		g2._morning_ops()
		if g2.op_row.size() + g2.op_discard.size() > before:
			ops_days.append(d)
			g2._remove_card(g2.op_row[-1])
	ok(ops_days == [2, 4, 6, 8], "일제 작전: 1막 2·4·6·8일째 아침에만 (실제 %s)" % str(ops_days))
	var seen := {}
	for id in g2.op_discard:
		seen[id] = true
	ok(seen.size() == 4, "일제 작전: 네 번에 서로 다른 네 장이 나옴 (덱 4장)")
	# 동향 최대 6
	var g3 := _new(CH)
	g3.day = 2
	g3.trend = 6
	g3._morning_ops()
	ok(g3.trend == 6, "일제 동향: 최대 6")
	# 2막에는 일제 작전·표적 이동·기한·미션 줄이 없다
	var g4 := _new(CH)
	g4.act = 2
	g4.day = 2
	g4._morning_ops()
	g4._morning_markers()
	ok(g4.op_row.is_empty() and g4.trend == 0, "2막: 아침에 일제 작전이 나오지 않음")
	var g5 := _new(CH)
	g5.act = 2
	g5.phase = "morning"
	g5.morning_step = 1
	g5.day = 4
	g5.threat_deck = ["chaos"]
	g5._morning_continue()
	ok(g5.mission_row.is_empty() and g5.op_row.is_empty() and g5.markers.is_empty() and g5.phase == "plan", "2막: 아침에 미션 줄을 채우지 않고 일제 작전도 없음")
	# 같은 칸 위의 마커는 겹치지 않는다 (줄 4장 채우기를 여러 번)
	var g6 := _new(CH)
	var clash := false
	for k in 12:
		g6.markers = []
		g6.mission_state = {}
		g6.mission_row = []
		g6.mission_deck = g6._expand(g6.data.missions["missions"])
		g6._fill_mission_row()
		var seen_cells := {}
		for m in g6.markers:
			var sp: Dictionary = g6.card_def(str(m["id"])).get("markers", [])[int(m["spec"])]
			if sp.has("at"):
				continue
			if seen_cells.has(m["pos"]):
				clash = true
			seen_cells[m["pos"]] = true
	ok(not clash, "마커: 새로 채운 줄에서 마커끼리 같은 칸에 놓이지 않음 (12번)")


func _test_c_launch_cleanup() -> void:
	var rid := ""
	for card in _fixed_data().threats.get("act2", []):
		if bool(card.get("trend_extra", false)):
			rid = str(card["id"])
	ok(rid != "", "결행: 증원 카드에 trend_extra 표시가 있음")
	var expect := {0: 0, 2: 0, 3: 1, 4: 1, 5: 2, 6: 2}
	for tv in expect:
		var g := _new(CH)
		_flat(g)
		g.trend = tv
		g.exposure = 2
		g.ready = 3
		_mission(g, "m_police_chief")
		_mission(g, "m_leaflets")
		_mission(g, "op_roundup")
		_mission(g, "op_spy_raid")
		g.phase = "day"
		g.current = -1
		g.launch_info = {"target": "prison", "reason": "test", "day": g.day, "rounds_left": g.rounds_left}
		g._begin_act2()
		var n := 0
		for id in g.threat_deck + g.threat_discard:
			if id == rid:
				n += 1
		var base_n := int(_fixed_data().threat(rid).get("count", 1))
		ok(n == base_n + expect[tv], "결행: 동향 %d이면 2막 위협 덱에 증원 %d장 더 (모두 %d장)" % [tv, expect[tv], base_n + expect[tv]])
		if tv == 3:
			ok(g.mission_row.is_empty() and g.op_row.is_empty() and g.markers.is_empty() and g.mission_state.is_empty() and g.expire_queue.is_empty(), "결행: 미션 줄·미션 마커·일제 작전 마커를 모두 치움")
			ok(g.exposure == 2 and g.ready == 3 and g.op_discard.is_empty(), "결행: 치운 것은 못 막은 것으로 치지 않음 (노출·결행 준비·동향 벌칙 없음)")
			ok(g.trend == 3 and g.launch_info["trend"] == 3 and g.launch_info["reinforce"] == 1, "결행: 그때의 동향을 기록해 둠")
			# 2막 아침에는 아무것도 새로 나오지 않는다
			g.day = 4
			g._morning_ops()
			g._morning_markers()
			ok(g.op_row.is_empty() and g.markers.is_empty() and g.trend == 3, "결행 뒤: 일제 작전·표적 이동·기한이 없음")


func _test_c_save() -> void:
	var gd := _mission_gd(9, 7)
	var g := _new(CH, gd)
	_flat(g)
	_mission(g, "m_open_rice", {"work": Vector2i(5, 7)})
	_mission(g, "m_secret_docs", {"pickup": Vector2i(5, 8), "dropoff": Vector2i(5, 6)})
	_mission(g, "op_roundup", {"work": Vector2i(6, 7)})
	_at(g, 0, Vector2i(5, 7))
	_give_die_to(g, 0, 4)
	g.mission_state["m_secret_docs"]["holder"] = 1
	g.trend = 3
	g.peek_bonus = 1
	g.bonus_wait.append({"player": 0, "base": "gg", "reward": [{"op": "ready", "value": 1}]})
	var st := g.save_state()
	var c := RulesV2.new()
	c.load_state(st, gd)
	ok(str(c.save_state()) == str(g.save_state()) and str(c.legal_actions()) == str(g.legal_actions()), "저장·불러오기: 마커·진행·동향·위협 보기가 그대로 (합법 액션도 같음)")
	ok(c.markers.size() == g.markers.size() and c.mission_state["m_open_rice"]["sum"] == 4 and c.mission_state["m_secret_docs"]["holder"] == 1 and c.trend == 3 and c.peek_bonus == 1,
		"저장·불러오기: 마커 수·바친 합·든 요원·동향")
	# 같은 행동을 두 판에 해 보면 같다 (결정적)
	_end(g, 0)
	_end(c, 0)
	ok(str(c.save_state()) == str(g.save_state()), "저장·불러오기: 이어서 같은 행동을 하면 같은 상태")
	# 같은 시드 + 같은 아침 = 같은 마커
	var a := RulesV2.new_game(CH, 4242)
	var b := RulesV2.new_game(CH, 4242)
	_answer_all(a)
	_answer_all(b)
	ok(str(a.markers) == str(b.markers) and a.markers.size() > 0 and a.phase == "plan", "결정적: 같은 시드면 첫 아침 마커 자리가 같음")


func _test_c_coverage() -> void:
	var gd := _fixed_data()
	for c in gd.missions.get("missions", []):
		if c["type"] != "coop":
			ok(covered.has("mission:" + c["id"]), "빠짐없이: 미션 %s 이룸" % c["id"])
	for c in gd.missions.get("ops", []):
		ok(covered.has("mission:" + c["id"]), "빠짐없이: 일제 작전 %s 막음" % c["id"])
