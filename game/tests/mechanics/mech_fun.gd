extends "res://tests/mechanics/mech_missions.gd"
## 규칙 시험 7층: S단계 재미 개선 (감옥 아침 석방 · 2막 실패 누적 · 남은 주사위 → 첩보 토큰 · 새 사연 조건)


func _run_s_tests() -> void:
	_test_s_jail_release()
	_test_s_scene_fail_ease()
	_test_s_leftover_intel()
	_test_s_scene_targets()
	_test_s_saga_vocab()
	_test_s_saga_jail_kinds()


func _jail_gd(more: Callable = Callable()) -> GameDataV2:
	## 고정 사본에 S단계 감옥 규칙을 켠다
	return _gd(func(d):
		d.rules["jail"]["release_next_morning"] = true
		d.rules["jail"]["confiscate_items"] = 0
		if more.is_valid():
			more.call(d))


func _test_s_jail_release() -> void:
	# 낮에 갇히면 다음 날 아침에 풀려난다 (경찰은 붙지 않고, 아이템은 그대로)
	var g := _new(CH, _jail_gd())
	g.players[0]["items"] = ["train_ticket"]
	g._jail(g.players[0])
	var base: Vector2i = g.players[0]["pos"]
	ok(g.players[0]["jailed"] and g.release_day(g.players[0]) == g.day + 1, "감옥: 낮에 갇히면 다음 날 아침에 풀려날 날로 적음")
	ok(g.players[0]["items"] == ["train_ticket"] and g.item_discard.is_empty(), "감옥: 압수 0이면 아이템을 그대로 들고 있음")
	g._begin_morning(false)
	ok(not g.players[0]["jailed"] and g.players[0]["pos"] == base and not g.police.has(0), "감옥: 다음 날 아침 갇힌 거점에서 풀려나고 경찰은 붙지 않음")
	ok(_log_has(g, "풀려났습니다") and g.history.any(func(h): return "석방" in str(h["text"])), "감옥: 석방을 기록과 작전 기록에 남김")
	ok(g.players[0]["stats"]["escapes"] == 0, "감옥: 아침 석방은 탈옥으로 세지 않음 (옥중 동지 사연)")
	# 밤에 갇히면 하루를 더 갇힌다
	var n := _new(CH, _jail_gd())
	n.today["night"] = true
	n._jail(n.players[1])
	ok(n.release_day(n.players[1]) == n.day + 2, "감옥: 밤에 갇히면 그다음 날 아침에 풀려날 날로 적음")
	n._begin_morning(false)
	ok(n.players[1]["jailed"], "감옥: 밤에 갇힌 요원은 다음 날 아침에는 아직 갇혀 있음")
	n._begin_morning(false)
	ok(not n.players[1]["jailed"], "감옥: 밤에 갇힌 요원은 그다음 날 아침에 풀려남")
	# 그날 바로 나오는 탈옥은 그대로 (성공하면 경찰이 붙음)
	var e := _new(CH, _jail_gd(func(d): d.rules["checks"]["escape"] = 0))
	e._jail(e.players[0])
	_turn(e, 0, 0)
	var i := _spare(e, 3, 0)
	ok(e.apply({"type": "escape", "player": 0, "die": i}) and not e.players[0]["jailed"] and e.police.has(0), "감옥: 탈옥에 성공하면 그날 바로 나오고 경찰이 붙음")
	ok(e.players[0]["stats"]["escapes"] == 1, "감옥: 탈옥 성공은 탈옥으로 셈")
	# 스위치를 끄면 예전처럼 아침에 풀려나지 않는다 (고정 사본의 기본)
	var off := _new(CH)
	off._jail(off.players[0])
	off._begin_morning(false)
	ok(off.players[0]["jailed"], "감옥: release_next_morning이 꺼져 있으면 아침에 풀려나지 않음")
	# 진짜 데이터는 켜져 있고 압수가 없다
	var real := GameDataV2.load_default()
	ok(bool(real.rules["jail"]["release_next_morning"]) and int(real.rules["jail"]["confiscate_items"]) == 0, "데이터: 감옥은 아침 석방 · 압수 없음")


func _test_s_scene_fail_ease() -> void:
	# 같은 장면에서 판정에 실패할 때마다 목표 −fail_ease (최대 fail_ease_max), 장면을 넘기면 처음으로
	var gd := _gd(func(d):
		d.rules["scenes"]["fail_ease"] = 1
		d.rules["scenes"]["fail_ease_max"] = 2)
	var card: Dictionary = gd.strike("police_hq")["middle"].filter(func(c): return str(c["condition"].get("kind", "")) == "check")[0]
	var g := _scene_fixture("police_hq", card)
	g.data = gd
	var cond: Dictionary = card["condition"]
	var t0 := g.scene_check_target(cond)
	var fail := {"scene_id": card["id"], "scene_path": ""}
	g._scene_check_result(g.players[0], fail, false)
	ok(g.scene_check_target(cond) == t0 - 1 and _log_has(g, "포위망이 좁혀집니다"), "2막 실패 누적: 한 번 실패하면 목표 −1")
	g._scene_check_result(g.players[1], fail, false)
	g._scene_check_result(g.players[2], fail, false)
	ok(g.scene_check_target(cond) == t0 - 2, "2막 실패 누적: 최대 −2에서 멈춤")
	_turn(g, 3, 0)
	var i := _spare(g, 4, 3)
	ok(int(g.check_preview(g.players[3], {"type": "scene_check", "player": 3, "die": i})["target"]) == t0 - 2, "2막 실패 누적: 판정 미리보기(확률 표시)에도 반영")
	g.scenes.append(card["id"])   # 마지막 장면이 아니어야 다음 장면으로 넘어간다
	g._scene_break(0)
	ok(g.scene_index == 2 and g.scene_fail_ease() == 0 and not g.scene_state.has("fails"), "2막 실패 누적: 장면을 넘기면 처음으로")
	var off := _scene_fixture("police_hq", card)
	off._scene_check_result(off.players[0], fail, false)
	ok(off.scene_fail_ease() == 0, "2막 실패 누적: fail_ease가 없으면 목표 그대로 (고정 사본)")


func _test_s_leftover_intel() -> void:
	# 2막 밤: 쓰지 않은 주사위 per개마다 첩보 토큰 1, 가진 토큰은 max_tokens까지
	var gd := _gd(func(d): d.rules["leftover_to_intel"] = {"act": 2, "per": 2, "max_tokens": 3})
	var g := _new(CH, gd)
	g.act = 2
	g.intel_tokens = 0
	g.op_dice = []
	for v in [1, 2, 3, 4, 5]:
		g.op_dice.append({"value": v, "owner": 0, "used": false})
	g.op_dice.append({"value": 6, "owner": 1, "used": true})
	g._leftover_to_intel()
	ok(g.intel_tokens == 2 and _log_has(g, "첩보 토큰 +2"), "남은 주사위: 쓰지 않은 5개 → 첩보 토큰 +2 (2개당 1)")
	ok(g.events.any(func(e): return e["kind"] == "leftover_intel" and int(e["tokens"]) == 2), "남은 주사위: 화면 알림 leftover_intel")
	g._leftover_to_intel()
	ok(g.intel_tokens == 3, "남은 주사위: 가진 토큰은 3개까지만")
	var a1 := _new(CH, gd)
	a1.intel_tokens = 0
	a1.op_dice = [{"value": 3, "owner": 0, "used": false}, {"value": 3, "owner": 1, "used": false}]
	a1._leftover_to_intel()
	ok(a1.intel_tokens == 0, "남은 주사위: 1막에는 바꾸지 않음")
	var real := GameDataV2.load_default()
	ok(int(real.rules["leftover_to_intel"]["act"]) == 2 and int(real.rules["scenes"]["fail_ease"]) == 1, "데이터: 2막 남은 주사위 규칙 · 실패 누적이 켜져 있음")


func _test_s_scene_targets() -> void:
	# 검증기: 주사위로 닿을 수 없는 장면 판정 목표를 잡는다 (낸 눈 + op_check_dice개 = 최대 12)
	var d := GameDataV2.new()
	d.load_dir("res://data/v2/")
	ok(d.validate().is_empty(), "검증기: 진짜 데이터의 장면 판정 목표는 모두 주사위로 닿음")
	d.strike("police_hq")["middle"][0]["condition"] = {"kind": "check", "check": "generic", "target": 13}
	ok(d.validate().any(func(e): return "판정 목표 13" in e), "검증기: 판정 목표 13(최대 12 넘음)을 잡는다")


func _saga_gd(id: String, cond: Dictionary) -> GameDataV2:
	## 고정 사본의 사연 하나의 조건을 바꾼다 (새 어휘 시험용)
	return _gd(func(d): d.saga(id)["condition"] = cond)


func _test_s_saga_vocab() -> void:
	# mission_kind_by_me: 그 종류의 미션을 내가 이룸
	var g := _new(CH, _saga_gd("first_step", {"kind": "mission_kind_by_me", "mission_kind": "assassinate"}))
	_give(g, 0, ["first_step"])
	g._saga_note(g.players[0], "mission_kind_by_me", {"id": "m_x", "mission_kind": "work"})
	ok(g.players[0]["saga_done"] == "", "사연 mission_kind_by_me: 다른 종류의 미션은 세지 않음")
	g._saga_note(g.players[0], "mission_kind_by_me", {"id": "m_x", "mission_kind": "assassinate"})
	ok(g.players[0]["saga_done"] == "first_step", "사연 mission_kind_by_me: 암살 미션을 이루면 이룸")
	# same_cell_allies: 서로 다른 동료 count명과 같은 칸에서 차례를 마침 (같은 동료를 되풀이하면 한 명)
	var s := _new(CH, _saga_gd("first_step", {"kind": "same_cell_allies", "count": 2}))
	_give(s, 0, ["first_step"])
	for q in s.players:
		q["pos"] = Vector2i(0, 0)
	s.players[0]["pos"] = Vector2i(5, 5)
	s.players[1]["pos"] = Vector2i(5, 5)
	s._saga_turn_end(s.players[0])
	s._saga_turn_end(s.players[0])
	ok(s.players[0]["saga_done"] == "" and s.saga_progress(0)["first_step"]["have"] == 1, "사연 same_cell_allies: 같은 동료와 두 번은 한 명으로 셈")
	s.players[2]["pos"] = Vector2i(5, 5)
	s._saga_turn_end(s.players[0])
	ok(s.players[0]["saga_done"] == "first_step", "사연 same_cell_allies: 서로 다른 동료 두 명이면 이룸")
	# present_at_entry: 진입 장면을 돌파할 때 결행 거점 안이나 옆 칸에 있음 (돌파한 사람이 아니어도)
	var e := _new(CH, _saga_gd("first_step", {"kind": "present_at_entry"}))
	_give(e, 0, ["first_step"])
	_give(e, 1, ["first_step"])
	var base: Vector2i = e._base_cell("prison")
	e.players[0]["pos"] = base + Vector2i(1, 0)
	e.players[1]["pos"] = base + Vector2i(3, 0)
	e.saga_strike_event("entry", 3, {"strike": "prison", "present": []})
	ok(e.players[0]["saga_done"] == "first_step" and e.players[1]["saga_done"] == "", "사연 present_at_entry: 옆 칸이면 이루고 멀면 못 이룸")
	e.saga_strike_event("middle", 3, {"strike": "prison", "present": []})
	ok(e.players[1]["saga_done"] == "", "사연 present_at_entry: 진입 장면이 아니면 세지 않음")
	var real := GameDataV2.load_default()
	ok(real.saga("first_step")["condition"]["kind"] == "present_at_entry" and real.saga("nameless_hero")["condition"]["or"]["kind"] == "same_cell_allies",
		"데이터: 첫걸음 · 이름 없는 영웅의 새 조건")


func _test_s_saga_jail_kinds() -> void:
	# jailed: 감옥에 갇히면 셈 (옥중 동지)
	var g := _new(CH, _saga_gd("first_step", {"kind": "jailed", "count": 1}))
	_give(g, 0, ["first_step"])
	g._jail(g.players[0])
	ok(g.players[0]["saga_done"] == "first_step", "사연 jailed: 감옥에 한 번 갇히면 이룸")
	# never_jailed_until_launch + shaken: 결행까지 안 잡히고 경찰을 한 번 이상 떨쳐 냄
	var v := _new(CH, _saga_gd("first_step", {"kind": "never_jailed_until_launch", "shaken": 1}))
	_give(v, 0, ["first_step"])
	v._saga_note(v.players[0], "never_jailed_until_launch", {"launch": true})
	ok(v.players[0]["saga_done"] == "", "사연 살아서 돌아간다: 경찰을 떨쳐 낸 적이 없으면 못 이룸")
	v.police[0] = {"pos": Vector2i(0, 0), "summon_turn": 0}
	v._police_off(0, "shake")
	v._saga_note(v.players[0], "never_jailed_until_launch", {"launch": true})
	ok(v.players[0]["saga_done"] == "first_step", "사연 살아서 돌아간다: 따돌린 적이 있고 잡힌 적이 없으면 이룸")
	# chased_turns_row + row false: 연달아가 아니어도 셈
	var f := _new(CH, _saga_gd("first_step", {"kind": "chased_turns_row", "count": 2, "row": false}))
	_give(f, 0, ["first_step"])
	f._saga_note(f.players[0], "chased_turns_row", {"chased": true})
	f._saga_note(f.players[0], "chased_turns_row", {"chased": false})
	f._saga_note(f.players[0], "chased_turns_row", {"chased": true})
	ok(f.players[0]["saga_done"] == "first_step", "사연 도망자(row false): 쫓긴 차례가 띄엄띄엄 두 번이어도 이룸")

	# visit_jailed: 갇힌 동료의 감옥 옆 칸에서 차례를 마침 (옥중 동지)
	var m := _new(CH, _saga_gd("first_step", {"kind": "visit_jailed", "count": 1}))
	_give(m, 0, ["first_step"])
	m._jail(m.players[1])
	m.players[0]["pos"] = m.players[1]["pos"] + Vector2i(2, 0)
	m._saga_turn_end(m.players[0])
	ok(m.players[0]["saga_done"] == "", "사연 visit_jailed: 두 칸 떨어지면 못 이룸")
	m.players[0]["pos"] = m.players[1]["pos"] + Vector2i(1, 0)
	m._saga_turn_end(m.players[0])
	ok(m.players[0]["saga_done"] == "first_step", "사연 visit_jailed: 갇힌 동료의 감옥 옆 칸에서 차례를 마치면 이룸")
