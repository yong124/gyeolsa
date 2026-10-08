extends SceneTree
## GameDataV2.validate() 자체 시험: 작은 정상 예시는 장수 불일치만, 틀린 예시는 오류를 잡아야 한다.
## 실행: godot --headless --path game --script res://tests/v2_validator_selftest.gd

var _fail := 0


func _init() -> void:
	# 정상 예시: [장수] 오류만 있어야 한다 (예시가 작으니 장수는 당연히 모자람)
	var good := GameDataV2.new()
	good.load_dir("res://tests/fixtures/v2/")
	var errs := good.validate()
	var other: Array[String] = []
	var count_errs := 0
	for e in errs:
		if e.begins_with("[장수]"):
			count_errs += 1
		else:
			other.append(e)
	print("정상 예시: 장수 불일치 %d건 (예상된 것), 그 밖의 오류 %d건" % [count_errs, other.size()])
	for e in other:
		print("  예상 밖 오류: ", e)
	_check(other.is_empty(), "정상 예시에 장수 외 오류가 없다")
	_check(count_errs > 0, "장수 불일치가 보고된다")
	_check(good.todos().size() == 1, "_todo 경고 1건 (실제 %d건)" % good.todos().size())
	_check(good.threat_deck(1).size() == 3, "threat_deck(1)은 count를 펼쳐 3장")
	_check(good.mission("coop_a").get("type") == "coop", "mission() 조회")
	_check(good.event("hide").has("effects"), "event() 조회")
	_check(good.item("smoke").get("count") == 2, "item() 조회")
	_check(good.saga("ring").get("act") == 2, "saga() 조회")
	_check(good.character("seo").get("gender") == "f", "character() 조회")
	_check(good.strike("prison").get("name") == "형무소 해방", "strike() 조회")
	_check(good.board["bases"].size() == 4 and good.base_index("gg") == 3, "보드 정보와 거점 번호")

	# Z3: 보드 · 화면 구성 · 투표 · AI 값의 오류를 잡는다 (정상 예시를 하나씩 망가뜨려 본다)
	_check(_breaks(func(d): d.base_ids[1] = d.base_ids[0], "거점 id barracks가 겹칩니다"), "board.json 거점 id 중복을 잡는다")
	_check(_breaks(func(d): d.bases[2] = d.start, "시작 칸입니다"), "board.json 거점이 시작 칸이면 잡는다")
	_check(_breaks(func(d): d.tile_art["normal"] = {"texture": "없는그림"}, "board.tile_art.normal"), "board.json 없는 타일 그림을 잡는다")
	_check(_breaks(func(d): d.rules["launch"]["vote"]["tie"] = "coin", "tie는"), "투표 동률 규칙 오타를 잡는다")
	_check(_breaks(func(d): d.rules["ai"]["persona"].erase("support"), "persona에 support"), "AI 기본 성향이 없으면 잡는다")
	_check(_breaks(func(d): d.ui["verbs"][0]["jailed"] = "maybe", "jailed는"), "ui.json 단추 jailed 오타를 잡는다")
	_check(_breaks(func(d): d.ui["marker_glyph"].erase("target"), "marker_glyph.target"), "ui.json 마커 글자 빠짐을 잡는다")
	_check(_breaks(func(d): d.ui["weather"] = {"no_such": "rain"}, "위협 카드 no_such"), "ui.json 날씨가 없는 위협을 가리키면 잡는다")

	# 틀린 예시: 파일은 위협만 있다. 오타 op·어휘 밖 who·중복 id·중첩 오타·파일 없음을 잡아야 한다.
	var bad := GameDataV2.new()
	bad.load_dir("res://tests/fixtures/v2_bad/")
	var berrs := bad.validate()
	for e in berrs:
		print("  (틀린 예시) ", e)
	_check(_has(berrs, "알 수 없는 op 'police_dispach'"), "op 오타를 잡는다")
	_check(_has(berrs, "알 수 없는 who 'nobody'"), "어휘 밖 who를 잡는다")
	_check(_has(berrs, "중복"), "id 중복을 잡는다")
	_check(_has(berrs, "알 수 없는 op 'no_such_op'"), "choice 안쪽 오타를 잡는다")
	_check(_has(berrs, "파일 없음: res://tests/fixtures/v2_bad/events.json"), "없는 파일을 오류로 기록한다")

	# B단계 어휘: 능력의 cost, police_attach의 at, rules의 hide·scout·market·police
	var real := GameDataV2.new()
	real.load_dir("res://data/v2/")
	_check(real.validate().is_empty(), "진짜 데이터는 오류 없음")
	var r1 := GameDataV2.new()
	r1.load_dir("res://data/v2/")
	for c in r1.characters["characters"]:
		if c["id"] == "seo":
			c["ability"]["cost"] = "coin"
	_check(_has(r1.validate(), "알 수 없는 cost 'coin'"), "능력의 알 수 없는 cost를 잡는다")
	var r2 := GameDataV2.new()
	r2.load_dir("res://data/v2/")
	for ev in r2.events["events"]:
		if ev["id"] == "informer":
			ev["effects"][0]["at"] = "there"
	_check(_has(r2.validate(), "police_attach의 알 수 없는 at 'there'"), "police_attach의 알 수 없는 at을 잡는다")
	var r3 := GameDataV2.new()
	r3.load_dir("res://data/v2/")
	r3.rules.erase("hide")
	r3.rules["scout"]["count"] = 0
	r3.rules["market"] = {"tile": 3}
	r3.rules["police"]["rejoin_distance"] = 0
	var e3 := r3.validate()
	_check(_has(e3, "rules.hide") and _has(e3, "rules.scout.count") and _has(e3, "rules.market") and _has(e3, "rejoin_distance"), "rules의 hide·scout·market·police 값 누락을 잡는다")
	var r4 := GameDataV2.new()
	r4.load_dir("res://data/v2/")
	r4.characters["characters"][0]["trait"] = {"mods": [{"stat": "no_such_stat", "value": 1}]}
	_check(_has(r4.validate(), "알 수 없는 stat 'no_such_stat'"), "특성의 알 수 없는 stat을 잡는다")
	var r5 := GameDataV2.new()
	r5.load_dir("res://data/v2/")
	r5.rules["launch"]["benefits"][0]["effects"] = [{"op": "no_such_benefit"}]
	r5.rules["launch"]["benefits"].append(r5.rules["launch"]["benefits"][1].duplicate())
	r5.rules.erase("counter")
	var e5 := r5.validate()
	_check(_has(e5, "알 수 없는 op 'no_such_benefit'") and _has(e5, "겹칩니다") and _has(e5, "rules.counter"), "결행 혜택의 오타 op·중복 id·반격 값 누락을 잡는다")
	var r6 := GameDataV2.new()
	r6.load_dir("res://data/v2/")
	for c in r6.sagas["sagas"]:
		if c["id"] == "sibling_revenge":
			c["condition"]["or"]["mission"] = "m_nobody"
	for st in r6.scenes["strikes"].values():
		if st is Dictionary and st.has("final") and st["final"]["condition"].get("kind", "") == "sequence":
			st["final"]["condition"]["steps"] = [st["final"]["condition"]["steps"][0]]
	var e6 := r6.validate()
	_check(_has(e6, "미션 'm_nobody'가 없습니다") and _has(e6, "sequence에는 단계"), "사연의 or 조건 미션 id와 장면 sequence 단계 수를 잡는다")
	_check("sequence" in GameDataV2.KNOWN_SCENE_CONDITIONS and "mission_done_by_me" in GameDataV2.KNOWN_SAGA_CONDITIONS and "everyone" in GameDataV2.KNOWN_TARGETS, "새 어휘(sequence, mission_done_by_me, everyone)")
	# C단계 어휘: 미션 마커 · 조건 · 보너스 · 일제 동향 · 타일 효과
	var m1 := GameDataV2.new()
	m1.load_dir("res://data/v2/")
	m1.mission("m_police_chief")["markers"][0]["role"] = "nobody"
	m1.mission("m_leaflets")["markers"] = []
	m1.mission("m_rail_bomb")["bonus"]["if"]["kind"] = "lucky"
	m1.mission("m_decode")["condition"]["mode"] = "pile"
	m1.mission("m_secret_docs").erase("missed")
	m1.mission("m_mp_captain")["condition"]["gear"]["cost"] = "gold"
	m1.mission("m_informant")["condition"]["kind"] = "dance"
	m1.mission("m_gg_blueprint")["bonus"]["if"]["base"] = "moon"
	var em := m1.validate()
	_check(_has(em, "알 수 없는 마커 role 'nobody'") and _has(em, "work 조건에는 work 마커가 있어야") and _has(em, "bonus.if의 kind가 어휘에 없습니다")
		and _has(em, "알 수 없는 공작 방식 'pile'") and _has(em, "기한이 있으면 놓쳤을 때(missed)") and _has(em, "gear에는 cost({item, funds})")
		and _has(em, "알 수 없는 조건 kind 'dance'") and _has(em, "launch_target 보너스에는 base"), "미션 마커·조건·보너스·기한·돈 대신 아이템의 오타와 누락을 잡는다")
	var m2 := GameDataV2.new()
	m2.load_dir("res://data/v2/")
	m2.missions["ops"][0]["markers"][0]["at"] = "start"
	m2.missions["ops"][1].erase("deadline")
	m2.missions["ops"][2]["type"] = "coop"
	m2.missions["ops"][3]["markers"][0]["around"] = "moon"
	m2.mission("m_cover_entry")["markers"] = [{"role": "spot", "at": "start"}]
	var e2 := m2.validate()
	_check(_has(e2, "at이나 around 중 하나만") and _has(e2, "일제 작전에는 deadline이 있어야") and _has(e2, "type은 op여야") and _has(e2, "거점 id나 start가 아닙니다") and _has(e2, "협동 미션에는 마커가 없습니다"),
		"일제 작전의 마커·기한·종류와 협동 미션의 마커를 잡는다")
	var m3 := GameDataV2.new()
	m3.load_dir("res://data/v2/")
	m3.rules.erase("ops")
	m3.rules["tile_effects"]["alley"]["on_stop"] = [{"op": "no_such_tile_op"}]
	m3.rules["tile_effects"]["tavern"]["needs"] = "lonely"
	m3.rules["tile_effects"]["watchtower"]["on_turn_end"] = "oops"
	m3.rules["tile_effects"]["nowhere"] = {"on_stop": []}
	m3.rules["tiles"]["normal"] = 40
	var e3c := m3.validate()
	_check(_has(e3c, "rules.ops(일제 동향)") and _has(e3c, "알 수 없는 op 'no_such_tile_op'") and _has(e3c, "알 수 없는 needs 'lonely'") and _has(e3c, "on_turn_end는 효과 목록")
		and _has(e3c, "rules.tiles에 없는 타일 종류") and _has(e3c, "[장수] 타일: 98장"), "타일 효과와 일제 동향 규칙·타일 장수의 오타와 누락을 잡는다")
	var m4 := GameDataV2.new()
	m4.load_dir("res://data/v2/")
	m4.rules["ops"]["penalties"][0]["min"] = 1
	m4.rules["ops"]["reinforce_by_trend"] = [{"min": 3}]
	m4.rules["ops"]["block"] = [{"op": "no_such_block"}]
	var e4 := m4.validate()
	_check(_has(e4, "min은 0에서 시작해") and _has(e4, "reinforce_by_trend") and _has(e4, "알 수 없는 op 'no_such_block'"), "동향 벌칙 단계표·증원표·막았을 때 효과의 오류를 잡는다")
	var m5 := GameDataV2.new()
	m5.load_dir("res://data/v2/")
	m5.threats["act1"][0]["count"] = 9
	_check(_has(m5.validate(), "[장수] 위협 act1"), "1막 위협 덱 장수(21장)를 확인한다")
	# D단계 어휘: 군자금 op · 장터 · 뇌물 · 매수 · 번 군자금 사연
	var f1 := GameDataV2.new()
	f1.load_dir("res://data/v2/")
	f1.rules["market"]["offers"][0]["cost_stat"] = "no_such_stat"
	f1.rules["market"]["offers"][1]["needs"] = "wallet"
	f1.rules["market"]["offers"].append(f1.rules["market"]["offers"][0].duplicate())
	f1.rules["funds"]["start"] = 11
	f1.rules["checkpoint"]["bribe"] = 0
	var ef := f1.validate()
	_check(_has(ef, "알 수 없는 cost_stat 'no_such_stat'") and _has(ef, "알 수 없는 needs 'wallet'") and _has(ef, "id가 비었거나 겹칩니다") and _has(ef, "rules.funds에") and _has(ef, "rules.checkpoint.bribe"),
		"장터 값 stat·조건·중복 id와 군자금·뇌물 값의 오류를 잡는다")
	var f2 := GameDataV2.new()
	f2.load_dir("res://data/v2/")
	f2.mission("m_mp_captain")["condition"]["gear"]["cost"] = {"coin": 1}
	f2.mission("m_informant")["condition"]["informer_cost"] = {"funds": 0}
	f2.threats["act1"][0]["effects"] = [{"op": "funds", "value": 0}]
	f2.threats["act1"][1]["effects"] = [{"op": "funds", "value": -2, "short": [{"op": "no_such_short"}]}]
	var ff := f2.validate()
	_check(_has(ff, "gear의 알 수 없는 cost 'coin'") and _has(ff, "informer_cost에는 funds") and _has(ff, "funds에는 value(0이 아님)") and _has(ff, "알 수 없는 op 'no_such_short'"),
		"돈 대신 아이템(gear) 값·정보원 값·funds op의 오류를 잡는다")
	var f3 := GameDataV2.new()
	f3.load_dir("res://data/v2/")
	var last: Dictionary = f3.strike("prison")["final"]
	last["condition"] = {"kind": "any_of", "options": [last["condition"], {"kind": "pay_funds", "count": 2}]}
	f3.endings["funds_left"]["text"] = "남은 군자금"
	var e3f := f3.validate()
	_check(_has(e3f, "마지막 장면은 매수(pay_funds)할 수 없습니다") and _has(e3f, "funds_left: text에 {n}"), "마지막 장면의 매수와 후일담 문장의 {n} 빠짐을 잡는다")
	_check("funds" in GameDataV2.KNOWN_OPS and "funds_half" in GameDataV2.KNOWN_OPS and "pay_funds" in GameDataV2.KNOWN_SCENE_CONDITIONS and "funds_earned" in GameDataV2.KNOWN_SAGA_CONDITIONS
		and "market_item_cost" in GameDataV2.KNOWN_STATS, "새 어휘(funds · funds_half · pay_funds · funds_earned · 장터 값 stat)가 등록돼 있다")
	_check("work" in GameDataV2.KNOWN_MISSION_KINDS and "contact" in GameDataV2.KNOWN_MISSION_KINDS and "target" in GameDataV2.KNOWN_MARKER_ROLES
		and "launch_target" in GameDataV2.KNOWN_BONUS_CONDS and "combo" in GameDataV2.KNOWN_WORK_MODES, "새 어휘(미션 kind·마커 역할·공작 방식·보너스 조건)가 등록돼 있다")
	_check("police_back" in GameDataV2.KNOWN_OPS and "threat_peek_bonus" in GameDataV2.KNOWN_OPS and "event_card" in GameDataV2.KNOWN_OPS
		and "work_reduce" in GameDataV2.KNOWN_STATS and not "sabotage_bonus" in GameDataV2.KNOWN_STATS, "새 op(police_back·threat_peek_bonus·event_card)와 stat(work_reduce·work_exposure)이 등록돼 있고 방해 stat은 없다")
	_check("assassin_adjacent" in GameDataV2.KNOWN_STATS and "die" in GameDataV2.KNOWN_COSTS, "새 어휘(assassin_adjacent, cost die)가 등록돼 있다")

	print("v2 검증기 자체 시험: %s" % ("통과" if _fail == 0 else "%d건 실패" % _fail))
	quit(1 if _fail > 0 else 0)


func _has(errs: Array[String], part: String) -> bool:
	for e in errs:
		if part in e:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print("%s %s" % ["  ok  " if ok else " FAIL ", what])


func _breaks(mutate: Callable, expect: String) -> bool:
	## 정상 예시를 새로 읽어 mutate로 망가뜨리고, expect가 든 오류가 나오는가
	var d := GameDataV2.new()
	d.load_dir("res://tests/fixtures/v2/")
	mutate.call(d)
	for e in d.validate():
		if expect in e:
			return true
	return false
