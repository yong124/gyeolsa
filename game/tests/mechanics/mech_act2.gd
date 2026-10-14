extends "res://tests/mechanics/mech_saga.gd"
## 규칙 시험 4층: 장면 · 2막 · 엔딩


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
	for target in GameDataV2.load_default().base_ids:
		var strike: Dictionary = _fixed_data().strike(target)
		var cards: Array = [strike["entry"]] + strike["middle"] + [strike["final"]]
		for card in cards:
			_test_one_scene(target, card)
			count += 1
	for card in _fixed_data().scenes["reinforce"]:
		_test_one_scene(GameDataV2.load_default().base_ids[0], card)
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
		"sequence":
			g.players[0]["grants"] = [{"kind": "check_bonus", "value": 99}]
			_turn(g, 0, 0)
			_sc(g, 0)
			g.phase = "day"
			g.current = -1
			g.players[1]["grants"] = [{"kind": "check_bonus", "value": 99}]
			_turn(g, 1, 0)
			_cc(g, 1)
			g._scene_night()
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
	g._saga_final_reveal()
	g._saga_idle_flush()
	ok(g.players[1]["saga_done"] == "last_telegram", "사연 훅: 마지막 장면이 펼쳐질 때 현장에 있던 동료가 마지막 전보를 이룸")
	_turn(g, 0, 0)
	_sc(g, 0)
	ok(g.ending.get("won", false), "사연 훅: 그 뒤 마지막 장면 돌파")
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
