extends "res://tests/mechanics/mech_fun.gd"
## v2 엔진 규칙 하나씩 확인 (2a 규칙 + 2b 카드 효과). 상태를 직접 꾸며 놓고 결과를 본다.
## 판정이 필요한 곳은 별도 GameDataV2 복사본의 판정 목표를 0(무조건 성공)이나 99(무조건 실패)로 바꿔 쓴다.
## 실행: godot --headless --path game --script res://tests/v2_mechanics_test.gd
## 규칙 시험은 층마다 한 파일이다 (tests/mechanics/). 이 파일이 맨 위 층으로, 차례를 정해 모두 부른다.


func _init() -> void:
	_test_fixture_in_sync()
	_test_plan_dice()
	_test_gaeddong_dice()
	_test_free_order_and_night()
	_test_vote()
	_test_checkpoint()
	_test_checkpoint_auto_and_smoke()
	_test_hideout()
	_test_police_and_jail()
	_test_escape_and_spare()
	_test_alert_dispatch()
	_test_hand_limit_and_draw_pick()
	_test_stat_sum()
	_test_threat_pick_leader()
	_test_coop_actions()
	_test_curfew_min1()
	_run_2b_tests()
	_run_3_tests()
	_run_4_tests()
	_run_a_tests()
	_run_b_tests()
	_run_e_tests()
	_run_c_tests()
	_run_d_tests()
	_run_t_tests()
	_test_c_coverage()
	_run_s_tests()
	_test_q_save_file()
	print("v2 규칙 시험: 통과 %d, 실패 %d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_q_save_file() -> void:
	## Q2 이어하기: 판 중간(아침)에 파일로 저장 → 읽기 → 같은 AI 수를 이어 두면 끝까지 같다. 팀 기록(stats)도 남는다
	SaveGameV2.path = "user://save_v2_test.dat"
	var g := RulesV2.new()
	var defs := []
	for id in ["park", "jeong", "gaeddong", "oh"]:
		defs.append({"name": id, "character": id})
	g.setup(defs, 4321)
	var guard := 0
	while not (g.phase == "plan" and g.day >= 4) and g.phase != "over" and guard < 5000:
		guard += 1
		g.apply(GameAIV2.decide(g, GameAIV2.next_actor(g)))
	ok(g.phase == "plan", "Q2 저장: 4일째 아침까지 진행")
	SaveGameV2.write(g, {"defs": defs})
	ok(SaveGameV2.exists() and SaveGameV2.summary().contains("4일째"), "Q2 저장: 파일이 생기고 요약에 날짜가 나온다 (%s)" % SaveGameV2.summary())
	var r := SaveGameV2.read()
	ok(not r.is_empty() and r["meta"].get("defs", []).size() == 4, "Q2 저장: 읽으면 판과 meta가 돌아온다")
	var h: RulesV2 = r["game"]
	ok(str(h.save_state()) == str(g.save_state()), "Q2 저장: 읽은 판의 상태가 저장한 판과 같다")
	guard = 0
	while g.phase != "over" and guard < 8000:
		guard += 1
		var a := GameAIV2.decide(g, GameAIV2.next_actor(g))
		g.apply(a)
		h.apply(GameAIV2.decide(h, GameAIV2.next_actor(h)))
	ok(g.phase == "over" and str(h.save_state()) == str(g.save_state()), "Q2 저장: 이어 두면 끝까지 같다 (엔딩 %s)" % g.ending.get("id", "-"))
	ok(int(g.stats["max_exposure"]) >= 0 and int(g.stats["ops_blocked"]) <= int(g.stats["ops_seen"]), "Q5 팀 기록: 막은 일제 작전 ≤ 나온 일제 작전 (%s)" % str(g.stats))
	SaveGameV2.erase()
	ok(not SaveGameV2.exists(), "Q2 저장: 지우면 없어진다")
	var f := FileAccess.open(SaveGameV2.path, FileAccess.WRITE)
	f.store_string("깨진 파일")
	f.close()
	ok(SaveGameV2.read().is_empty() and not SaveGameV2.exists(), "Q2 저장: 깨진 저장은 빈 결과를 주고 지운다")
	# 저장 버전: 같은 자리에 다시 써도 되고(임시 파일 → 이름 바꾸기), 다른 버전의 저장은 이어 하지 않는다
	SaveGameV2.write(g, {"defs": defs})
	SaveGameV2.write(h, {"defs": defs, "again": true})
	ok(SaveGameV2.exists() and SaveGameV2.read()["meta"].get("again", false) and not FileAccess.file_exists(SaveGameV2.path + ".tmp"),
		"저장 버전: 다시 쓰면 새 내용으로 바뀌고 임시 파일이 남지 않는다")
	ok(SaveGameV2.drop_stale() == "", "저장 버전: 지금 버전의 저장은 그대로 둔다")
	var old := FileAccess.open(SaveGameV2.path, FileAccess.WRITE)
	old.store_var({"app": "0.0.1", "meta": {}, "state": g.save_state()})
	old.close()
	ok(not SaveGameV2.exists() and SaveGameV2.summary() != "", "저장 버전: 다른 버전의 저장은 이어하기로 치지 않는다")
	ok(SaveGameV2.drop_stale() == "0.0.1" and not FileAccess.file_exists(SaveGameV2.path), "저장 버전: 다른 버전의 저장은 그 버전을 알리고 지운다")
	old = FileAccess.open(SaveGameV2.path, FileAccess.WRITE)
	old.store_var({"meta": {}, "state": g.save_state()})
	old.close()
	ok(SaveGameV2.read().is_empty() and SaveGameV2.drop_stale() == "", "저장 버전: 버전을 적기 전의 저장은 읽지 않고 지운다")
	old = FileAccess.open(SaveGameV2.path, FileAccess.WRITE)
	old.store_var({"meta": {}, "state": g.save_state()})
	old.close()
	ok(SaveGameV2.drop_stale() == "이전 버전", "저장 버전: 버전을 적기 전의 저장은 「이전 버전」으로 알린다")


# ================================================================== D단계 (군자금은 뺐다: 돈을 주던 미션 · 검문소 · 엔딩)

func _run_t_tests() -> void:
	## T2: 튜토리얼이 쓰는 「정해 둔 굴림」은 평소에는 늘 비어 있고, 저장 · 되살리기에 들어가지 않는다
	var g := _new(CH)
	ok(g.rigged_rolls.is_empty(), "정해 둔 굴림: 새 판에서는 비어 있음")
	g.rigged_rolls = [3, 4]
	ok(g._roll_die() == 3 and g._roll_die() == 4 and g.rigged_rolls.is_empty(), "정해 둔 굴림: 앞에서부터 하나씩 꺼내 씀")
	var r := g._roll_die()
	ok(r >= 1 and r <= 6, "정해 둔 굴림: 다 쓰면 다시 무작위")
	g.rigged_rolls = [2, 5]
	ok(g._d2(2) == 7 and g.last_roll == [2, 5], "정해 둔 굴림: 판정 주사위 2개도 정한 눈으로")
	g.rigged_rolls = [6]
	var st := g.save_state()
	ok(not st.has("rigged_rolls"), "정해 둔 굴림: 저장 상태에 들어가지 않음")
	var g2 := RulesV2.new()
	g2.load_state(st, _fixed_data())
	ok(g2.rigged_rolls.is_empty(), "정해 둔 굴림: 되살린 판에서는 비어 있음")
	var g3 := _new(CH, null, 77)
	var g4 := _new(CH, null, 77)
	g4.rigged_rolls = []
	ok(g3._roll_die() == g4._roll_die(), "정해 둔 굴림: 비어 있으면 같은 시드가 같은 눈 (결정적)")


func _run_d_tests() -> void:
	_test_d_missions()
	_test_d_checkpoint()
	_test_d_ending()
	_test_d_data()


func _test_d_missions() -> void:
	# 부호의 헌금: 잠복 1일 → 아이템 1장, 결행 준비 +1
	var g := _new(CH)
	_flat(g)
	_mission(g, "m_rich_donation", {"spot": Vector2i(5, 7)})
	_at(g, 0, Vector2i(5, 6))
	_end(g, 0)
	_cov("mission", "m_rich_donation")
	ok(g.mission_row.is_empty() and g.ready == 1 and g.players[0]["items"].size() == 1, "부호의 헌금: 잠복 1일이면 아이템 1장, 결행 준비 +1")
	# 독립 공채: 마커 2개에 주사위 하나씩 → 원하는 거점 첩보 +1
	var g2 := _new(CH)
	_flat(g2)
	_mission(g2, "m_bond")
	var cells: Array = g2.markers_of("m_bond", "work").map(func(m): return m["pos"])
	ok(cells.size() == 2 and cells[0] != cells[1], "독립 공채: 마커가 두 곳")
	_at(g2, 0, cells[0])
	_give_die_to(g2, 0, 1)
	ok(g2.mission_row == ["m_bond"], "독립 공채: 한 곳만으로는 안 이뤄짐")
	_end(g2, 0)
	_at(g2, 1, cells[1])
	_give_die_to(g2, 1, 5)
	_cov("mission", "m_bond")
	if g2.phase == "choice" and g2.pending["kind"] == "intel_base":
		_answer(g2, "gg")
	ok(g2.mission_row.is_empty() and g2.ready == 1 and g2.intel["gg"] == 1, "독립 공채: 두 곳에 바치면 원하는 거점 첩보 +1, 결행 준비 +1")
	# 쌀 창고 열기: 혼자 채우면 보너스가 없음
	var g3 := _new(CH)
	_flat(g3)
	_mission(g3, "m_open_rice", {"work": Vector2i(5, 7)})
	g3.exposure = 3
	_at(g3, 0, Vector2i(5, 7))
	_give_die_to(g3, 0, 6)
	_give_die_to(g3, 0, 3)
	ok(g3.mission_row.is_empty() and g3.exposure == 2, "쌀 창고 열기: 한 요원이 혼자 채우면 보너스 없음 (노출 −1만)")


func _test_d_ending() -> void:
	var g := _new(CH)
	g._end_game(false)
	ok(not g.ending.has("funds_left") and not "군자금" in g.ending["text"], "엔딩: 군자금 후일담 줄은 없음 (군자금을 뺐다)")


func _test_d_data() -> void:
	var real := GameDataV2.load_default()
	ok(real.validate().is_empty(), "데이터: 진짜 데이터가 검증기를 통과")
	ok(not real.rules.has("checkpoint") and not real.rules.has("market") and not real.rules.has("funds"), "데이터: 검문소 뇌물 · 장터 · 군자금 값이 없음")
	var makrye: Array = real.character("makrye")["trait"]["mods"]
	var seok: Array = real.character("seok")["trait"]["mods"]
	ok(not makrye.any(func(m): return str(m["stat"]).begins_with("market")) and not seok.any(func(m): return str(m["stat"]).begins_with("market")), "데이터: 주모 막례 · 석 기술자의 장터 값 특성을 뺌")


func _test_d_checkpoint() -> void:
	## 군자금을 뺀 뒤: 검문소는 묻지 않고 바로 회피 판정 (실패하면 노출 +1, 경찰)
	var gd := _gd(func(d): d.rules["checks"]["evade"] = 99)
	var g := _new(CH, gd)
	_flat(g)
	_tile(g, Vector2i(5, 6), "check")
	_turn(g, 0, 2)
	g.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)})
	ok(g.phase != "choice" and g.exposure == 1 and g.police.has(0), "검문소: 뇌물 없이 바로 회피 판정 (실패하면 노출 +1, 경찰)")
	var g5 := _new(CH, gd)
	_flat(g5)
	_tile(g5, Vector2i(5, 6), "check")
	g5.players[0]["flags"]["checkpoint_pass"] = 1
	_turn(g5, 0, 2)
	g5.apply({"type": "step", "player": 0, "to": Vector2i(5, 6)})
	ok(g5.phase != "choice" and g5.exposure == 0 and g5.players[0]["pos"] == Vector2i(5, 6), "검문소: 통행증이 있으면 판정 없이 지나감")
