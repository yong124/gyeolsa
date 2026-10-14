extends "res://tests/mechanics/mech_base.gd"
## 규칙 시험 2층: 카드 효과 (위협 · 이벤트 · 아이템 · 캐릭터 특성 · 능력 · 협동 · 나머지 op)


# ================================================================== 2b: 카드 효과 시험

func _run_2b_tests() -> void:
	_test_threat_cards()
	_test_event_cards()
	_test_item_cards()
	_test_traits()
	_test_abilities()
	_test_coop_missions()
	_test_ops_misc()
	_test_d_threats()
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
	ok(g.phase == "choice" and g.pending["kind"] == "effect_choice", "이벤트 밀서: 아이템 1장 또는 노출 −1 중 고름")
	_answer(g, 0)
	ok(g.players[0]["items"].size() == 1, "이벤트 밀서: 아이템 1장")
	g = _new(CH)
	g.exposure = 2
	_event(g, 0, "secret_letter")
	_answer(g, 1)
	ok(g.exposure == 1 and g.players[0]["items"].is_empty(), "이벤트 밀서: 노출 −1")

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
	var gda := _mission_gd(99, 7)
	g = _new(CH, gda)
	_flat(g)
	_mission(g, "m_police_chief", {"target": Vector2i(5, 6)})
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
	ok(g.stat(g.players[0], "mission_intel_bonus", "contact") == 1 and g.stat(g.players[0], "mission_intel_bonus", "lurk") == 0, "특성 한 간호장교: 연락 미션의 첩보 +1 (다른 종류는 0)")
	_cov("trait", "han")

	var gda := _mission_gd(99, 0)
	g = _new(["oh", "han", "park", "seo"], gda)
	_flat(g)
	_mission(g, "m_police_chief", {"target": Vector2i(5, 6)})
	_turn(g, 0, 0)
	var ohd := _spare(g, 6, 0)
	ok(g.mission_check_cells(g.players[0]) == [Vector2i(5, 6)], "특성 오 의병(assassin_adjacent): 옆 칸의 암살 표적에서도 판정할 수 있음")
	ok(g.apply({"type": "mission_check", "player": 0, "die": ohd, "cell": Vector2i(5, 6)}) and g.players[0]["pos"] == START and _count_dice(g, "암살") == 1,
		"특성 오 의병: 옆 칸에서 쏜다 (내 자리는 그대로, 실패해도 자동으로 다시 굴리지 않음)")
	var g2 := _new(["park", "han", "oh", "seo"], gda)
	_flat(g2)
	_mission(g2, "m_police_chief", {"target": Vector2i(5, 6)})
	_turn(g2, 0, 0)
	_spare(g2, 6, 0)
	ok(g2.mission_check_cells(g2.players[0]).is_empty(), "특성 오 의병: 다른 요원은 옆 칸에서 판정할 수 없음 (대조)")
	var g2b := _new(["oh", "han", "park", "seo"], gda)
	_flat(g2b)
	_mission(g2b, "op_spy_raid", {"target": Vector2i(5, 6)})
	_turn(g2b, 0, 0)
	_spare(g2b, 6, 0)
	ok(g2b.mission_check_cells(g2b.players[0]).is_empty(), "특성 오 의병: 옆 칸에서는 암살 판정만 (밀정 침투 같은 작전 판정은 제자리에서)")
	_cov("trait", "oh")

	g = _new(["seok", "han", "oh", "seo"])
	_fx(g, 0, [{"op": "gain_bomb", "count": 3}])
	ok(g.bomb_slots(g.players[0]) == 2 and g.players[0]["bombs"] == 2, "특성 석 기술자(bomb_slots): 폭탄 2개까지")
	_cov("trait", "seok")

	g = _new(["mun", "han", "oh", "seo"])
	_flat(g)
	g.exposure = 3
	_mission(g, "m_burn_conscript", {"work": Vector2i(5, 7)})
	_at(g, 0, Vector2i(5, 7))
	_give_die_to(g, 0, 3)
	ok(g.mission_state["m_burn_conscript"]["left"] == [1], "특성 문 선전대원(work_reduce): 공작의 조합에서 눈 하나를 뺌 (3을 바치면 남은 눈은 1뿐)")
	_give_die_to(g, 0, 1)
	ok(g.mission_row.is_empty() and g.exposure == 1, "특성 문 선전대원(work_exposure): 공작을 이루면 노출 −1 (하루 만에 끝낸 보너스 −1과 함께 −2)")
	g2 = _new(["mun", "han", "oh", "seo"])
	_flat(g2)
	_mission(g2, "m_open_rice", {"work": Vector2i(5, 7)})
	_at(g2, 0, Vector2i(5, 7))
	_give_die_to(g2, 0, 6)
	ok(g2.mission_row.is_empty(), "특성 문 선전대원: 합 공작은 바칠 합이 2 줄어 6으로 이룸")
	g2 = _new(["park", "han", "oh", "seo"])
	_flat(g2)
	g2.exposure = 3
	_mission(g2, "m_burn_conscript", {"work": Vector2i(5, 7)})
	_at(g2, 0, Vector2i(5, 7))
	_give_die_to(g2, 0, 3)
	ok(g2.mission_state["m_burn_conscript"]["left"] == [1, 5], "특성 문 선전대원: 다른 요원은 조합이 그대로 (대조)")
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
	ok(_log_has(g, "요원 oh의 주사위를 다시 굴려") and g.phase == "plan" and g.players[0]["ability_day"] == g.day, "능력 무전 지원: 고른 주사위를 다시 굴림")
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


# ------------------------------------------------------------------ 협동 미션 (3종)

func _test_coop_missions() -> void:
	# 엄호 잠입: 한 명이 거점에 들어갈 때 다른 한 명이 옆 칸
	var g := _new(CH)
	var b: Vector2i = g.data.bases[0]
	_mission(g, "m_cover_entry")
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
	_mission(g, "m_cover_entry")
	_tile(g, b + Vector2i(1, 0), "normal")
	g.players[0]["pos"] = b + Vector2i(1, 0)
	_turn(g, 0, 3)
	_step(g, 0, b)
	ok(g.mission_row == ["m_cover_entry"] and g.police.has(0), "협동 엄호 잠입: 옆 칸에 동료가 없으면 안 이뤄지고 경찰이 붙음")
	ok(g.markers.is_empty(), "협동: 마커가 없음")

	# 형무소 면회: 두 명이 같은 날 형무소 옆 칸에서 차례를 마침
	g = _new(CH)
	var pr: Vector2i = g.data.bases[2]
	_mission(g, "m_prison_visit")
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
	_mission(g, "m_link_line")
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
	_mission(g, "m_link_line")
	_lay(g, [Vector2i(1, 5), Vector2i(0, 5), Vector2i(1, 4), Vector2i(0, 4)])
	g.players[0]["pos"] = Vector2i(1, 5)
	g.players[1]["pos"] = Vector2i(1, 4)
	_turn(g, 0, 1)
	_step(g, 0, Vector2i(0, 5))
	_turn(g, 1, 1)
	_step(g, 1, Vector2i(0, 4))
	ok(g.mission_row == ["m_link_line"], "협동 연락선 잇기: 같은 쪽 가장자리 두 명은 안 됨")
	ok(g.today["ends"].size() == 2, "협동: 오늘 차례를 마친 자리를 기록")
	# 규칙서에서 빠진 협동 미션
	ok(g.data.mission("m_simul_strike").is_empty() and g.data.mission("m_gg_rally").is_empty(), "삭제: 동시 습격·총독부 앞 집회는 빠짐")


# ------------------------------------------------------------------ 나머지 op

func _test_ops_misc() -> void:
	var g := _new(CH)
	# 2막 효과도 공통 해석기를 통해 실행한다.
	g.bomb_supply = 0
	_fx(g, 0, [{"op": "refill_supply"}, {"op": "scene_check_mod_today", "value": 1}])
	ok(g.bomb_supply == int(g.data.rules["bomb_supply"]) and g.today["scene_mod"] == 1, "2막 효과: 폭탄 보급과 오늘 판정 보정")
	ok(not _log_has(g, "(알 수 없는 효과)"), "2막 효과: 해석기가 모르는 효과 없음")

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
	ok(_log_has(g, "의 주사위를 다시 굴려"), "op die_reroll: 고른 주사위를 다시 굴림")

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


# ------------------------------------------------------------------ 여러 층이 함께 쓰는 시험

func _test_d_threats() -> void:
	var gd := GameDataV2.load_default()
	var cards := {}
	for id in gd.threat_deck(1):
		cards[id] = int(cards.get(id, 0)) + 1
	ok(int(cards.get("calm_day", 0)) == 1 and not cards.has("fund_freeze") and int(cards.get("checkpoint_add", 0)) == 3 and gd.threat_deck(1).size() == 21, "1막 위협 덱: 평온한 하루 1 · 자금 동결 대신 검문소 증설 3장 (21장 그대로)")
