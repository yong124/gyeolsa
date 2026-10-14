extends "res://tests/mechanics/mech_cards.gd"
## 규칙 시험 3층: 개인 사연 · 결행 순간


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
	for id in GameDataV2.load_default().base_ids:
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
	var gr := _new(CH, _gd(func(d): d.saga("financier")["redraw_for"] = ["makrye"]))
	gr.saga_decks = {"a": ["gambler", "financier"], "b": []}
	var got: String = gr._draw_saga("a", _with_char(gr, "makrye"))
	ok(got == "gambler" and gr.saga_decks["a"] == ["financier"], "사연 다시 받기: 뺀 카드는 더미 맨 아래로")
	var gr2 := _new(CH, _gd(func(d): d.saga("financier")["redraw_for"] = ["makrye"]))
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

	# 자금책: 공작 미션에 주사위를 두 번 바침 → 원하는 거점에 첩보 1개
	g = _new(CH)
	_give(g, 0, ["financier"])
	g._saga_note(g.players[0], "work_give")
	ok(g.players[0]["saga_done"] == "" and g.saga_progress(0)["financier"] == {"have": 1, "need": 2}, "사연 자금책: 한 번으로는 안 이뤄짐 (1 / 2)")
	g._saga_note(g.players[0], "work_give")
	_flush(g)
	ok(g.players[0]["saga_done"] == "financier", "사연 자금책: 공작 미션에 두 번 바치면 이룸")
	if g.phase == "choice" and g.pending["kind"] == "intel_base":
		_answer(g, "gg")
	ok(g.intel["gg"] == 1, "사연 자금책: 보상으로 원하는 거점 첩보 +1")
	_cov("saga", "financier")

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

	# 옥중 동지: 탈옥에 성공한 횟수 (구출은 뺐다)
	var b0 := _base(g, "barracks")
	var gde := _gd(func(d): d.rules["checks"]["escape"] = 0)
	g = _new(CH, gde)
	_give(g, 0, ["cellmate"])
	for k in 2:
		g.players[0]["jailed"] = true
		g.players[0]["pos"] = b0
		g.players[0]["done_today"] = false
		_turn(g, 0, 0)
		g.apply({"type": "escape", "player": 0, "die": _spare(g, 1, 0)})
	ok(g.players[0]["saga_done"] == "cellmate", "사연 옥중 동지: 탈옥에 성공하면 이룸")
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

	# 스승의 부탁: 아이템 타일 두 곳을 밟음 → 동료 모두 다음 이동 +1
	g = _new(CH)
	_give(g, 0, ["masters_request"])
	_lay(g, [Vector2i(4, 6), Vector2i(4, 7)], "item")
	g._saga_step_on(g.players[0], Vector2i(4, 6))
	ok(g.saga_progress(0)["masters_request"]["have"] == 1 and g.players[0]["saga_done"] == "", "사연 스승의 부탁: 아이템 타일 한 곳으로는 안 이뤄짐")
	g._saga_step_on(g.players[0], Vector2i(4, 7))
	_flush(g)
	ok(g.players[0]["saga_done"] == "masters_request", "사연 스승의 부탁: 아이템 타일 두 곳을 밟으면 이룸")
	ok(g.players[0]["move_mod_next"] == 0 and g.players[1]["move_mod_next"] == 1 and g.players[2]["move_mod_next"] == 1 and g.players[3]["move_mod_next"] == 1, "사연 스승의 부탁: 동료 모두 다음 이동 +1 (본인 제외)")
	_cov("saga", "masters_request")

	# 4단계 훅: 결행 갈래
	g = _new(CH)
	_give(g, 0, ["sibling_revenge"])
	_give(g, 1, ["sibling_revenge"])
	g.saga_strike_event("entry", 0, {"strike": "police_hq", "present": [0, 1]})
	ok(g.players[0]["saga_done"] == "", "사연 동생의 원수: 진입 장면 돌파로는 안 이뤄짐")
	g.saga_strike_event("final", 1, {"strike": "police_hq", "present": [0, 1]})
	ok(g.players[0]["saga_done"] == "" and g.players[1]["saga_done"] == "sibling_revenge", "사연 동생의 원수: 어느 결행이든 마지막 장면을 내가 돌파하면 이룸")
	var gm := _new(CH)
	_give(gm, 0, ["sibling_revenge"])
	_give(gm, 1, ["sibling_revenge"])
	gm._saga_note(gm.players[0], "mission_done_by_me", {"id": "m_police_chief"})
	ok(gm.players[0]["saga_done"] == "", "사연 동생의 원수: 다른 미션을 이뤄서는 안 이뤄짐")
	gm._saga_note(gm.players[0], "mission_done_by_me", {"id": "m_mp_captain"})
	ok(gm.players[0]["saga_done"] == "sibling_revenge" and gm.players[1]["saga_done"] == "", "사연 동생의 원수: 「헌병 대위 암살」을 내가 이루면 이룸")
	var gm2 := _new(CH)
	gm2.mission_row = ["m_mp_captain"]
	_give(gm2, 2, ["sibling_revenge"])
	gm2._complete_missions(gm2.players[2], ["m_mp_captain"], {"then": "resume", "source": "mission"})
	ok(gm2.players[2]["saga_done"] == "sibling_revenge", "사연 동생의 원수: 실제 미션 이룸 처리에서도 셈")
	ok(g._grant_index(g.players[1], "reroll") >= 0, "사연 동생의 원수: 판정 다시 굴리기 한 번")
	_cov("saga", "sibling_revenge")
	g = _new(CH)
	_give(g, 0, ["last_telegram"])
	_give(g, 1, ["last_telegram"])
	g.launch_info = {"target": "barracks"}
	g.players[0]["pos"] = g.data.bases[0]
	g.saga_strike_event("final", 2, {"strike": "barracks", "present": [0]})
	ok(g.players[0]["saga_done"] == "", "사연 마지막 전보: 마지막 장면을 돌파할 때가 아니라 펼쳐질 때 센다")
	g._saga_final_reveal()
	g._saga_idle_flush()
	ok(g.players[0]["saga_done"] == "last_telegram" and g.players[1]["saga_done"] == "", "사연 마지막 전보: 마지막 장면이 펼쳐질 때 결행 거점 안에 있던 요원만 이룸")
	ok(g.players[0]["grants"][0]["scope"] == "final" and g.players[0]["grants"][0]["value"] == 2, "사연 마지막 전보: 마지막 장면 판정 +2 한 번 (scope final)")
	ok(g._grant_index(g.players[0], "check_bonus", false) < 0, "사연 마지막 전보: 결행 장면 밖에서는 쓰이지 않음")
	g.act = 2
	g.scenes = ["a", "b", "c"]
	g.scene_index = 1
	ok(g._grant_index(g.players[0], "check_bonus", true) < 0, "사연 마지막 전보: 마지막이 아닌 장면 판정에는 쓰이지 않음")
	g.scene_index = 2
	ok(g._grant_index(g.players[0], "check_bonus", true) >= 0, "사연 마지막 전보: 마지막 장면 판정에 쓰임")
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
	ok(g.saga_feasible(p0, "sibling_revenge") and g.saga_feasible(p0, "last_telegram") and g.saga_feasible(p0, "first_step"), "이룰 수 있는가: 결행 갈래는 어느 결행이든 가능 (동생의 원수는 마지막 장면 돌파)")
	g.launch_info = {"target": "barracks"}
	ok(g.saga_feasible(p0, "sibling_revenge"), "이룰 수 있는가: 목표가 군영이어도 「동생의 원수」 가능")
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
	ok(g.launch_step == 3 and g.launch_i == 1, "결행 순간: 단계 launch_step 3(사연 남기기), 다음 요원 launch_i 1")
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
	_give(g, 0, ["ring", "mother"])
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g._launch("forced")
	ok(g.act == 2 and g.players[0]["saga_kept"] == "mother" and "ring" in g.saga_discard, "결행 순간: 결행 뒤에는 못 이루는 「약속의 반지」는 후보에서 빠져 나머지를 자동으로 남김")
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
	_give(g, 0, ["ring", "survivor"])
	g.players[0]["jail_count"] = 1
	for i in range(1, 4):
		_give(g, i, ["last_telegram"])
	g.saga_decks = {"a": ["mother", "ring"], "b": ["fugitive", "survivor"]}
	g.saga_discard = []
	g._launch("forced")
	# 더미 a의 맨 위 「약속의 반지」(결행 순간 조건)는 불가 → 버림, 더미 b의 맨 위 「동생의 원수」도 불가 → 버림, 다시 a의 「어머니의 소식」
	ok(g.act == 2 and g.players[0]["saga_kept"] == "mother" and g.players[0]["sagas"] == ["mother"], "결행 순간: 둘 다 못 이루면 새로 뽑아 이룰 수 있는 카드를 남김")
	ok("ring" in g.saga_discard and "survivor" in g.saga_discard and g.saga_decks["b"] == ["fugitive"], "결행 순간: 새로 뽑다 나온 불가 카드와 기존 카드는 버림, 더미 b는 그대로")

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
	g.players[1]["saga_track"]["financier"] = {"n": 1}
	var pr: Dictionary = g.saga_progress(0)
	ok(pr["moth"] == {"have": 2, "need": 3} and pr["no_greed"] == {"have": 0, "need": 3}, "조회: saga_progress {have, need}")
	var pr1: Dictionary = g.saga_progress(1)
	ok(pr1["financier"] == {"have": 1, "need": 2} and pr1["sibling_revenge"] == {"have": 0, "need": 1}, "조회: 공작에 바친 횟수는 쌓은 값, 결행 갈래는 0/1")
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
