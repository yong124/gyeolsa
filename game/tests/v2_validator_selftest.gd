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
