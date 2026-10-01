extends SceneTree
## AI 합법성·결정성·저장 재개·선택 응답을 확인한다.

const ACTION_CAP := 6000

var errors := []


func _init() -> void:
	var data := GameDataV2.load_default()
	var ids: Array = data.characters.get("characters", []).map(func(c): return c["id"])
	var source := FileAccess.get_file_as_string("res://scripts/core/v2/rules_v2.gd")
	var re := RegEx.new()
	re.compile("_ask\\([^,]+,\\s*\"([^\"]+)\"")
	var found := {}
	for hit in re.search_all(source):
		found[hit.get_string(1)] = true
	for kind in found:
		if not kind in GameAIV2.CHOICE_KINDS:
			errors.append("선택 종류 미대응: " + kind)
	for kind in GameAIV2.CHOICE_KINDS:
		if not kind in found and not kind in RulesV2.PICK_KINDS:
			errors.append("엔진에 없는 선택 종류: " + kind)
	var traitors := 0
	var ambush := 0
	var informs := 0
	var choices := {}
	var total := 0
	for i in 220:
		var n := 4 if i < 200 else 2 + i % 2
		var select := RandomNumberGenerator.new()
		select.seed = 780000 + i
		var pool := ids.duplicate()
		var chars := []
		for j in n:
			chars.append(pool.pop_at(select.randi_range(0, pool.size() - 1)))
		var defs := []
		for id in chars:
			defs.append({"name": data.character(str(id)).get("name", str(id)), "character": id})
		var g := RulesV2.new()
		g.setup(defs, 780000 + i, data)
		var saved: RulesV2 = null
		var step := 0
		while g.phase != "over" and step < ACTION_CAP:
			var legal := g.legal_actions()
			if legal.is_empty():
				errors.append("%d판: 합법 액션 없음" % i)
				break
			if g.phase == "choice":
				choices[str(g.pending.get("kind", ""))] = true
			var a := GameAIV2.decide(g, GameAIV2.next_actor(g))
			if not a in legal:
				errors.append("%d판: AI가 합법 액션 밖을 선택" % i)
				break
			if saved == null and step == 25:
				saved = RulesV2.new()
				saved.load_state(g.save_state(), data)
			if not g.apply(a):
				errors.append("%d판: 엔진이 AI 액션을 거부" % i)
				break
			if saved != null and not saved.apply(a.duplicate(true)):
				errors.append("%d판: 불러온 판이 액션을 거부" % i)
				break
			step += 1
			for e in g.events:
				if e.get("kind", "") == "ambush":
					ambush += 1
				if e.get("kind", "") == "inform":
					informs += 1
		if g.phase != "over":
			errors.append("%d판: 멈춤 (%s, %d동작)" % [i, g.phase, step])
			continue
		total += 1
		if g.traitor_id >= 0:
			traitors += 1
		if saved != null and str(saved.save_state()) != str(g.save_state()):
			errors.append("%d판: 저장 뒤 이어 둔 결과 불일치" % i)
		var replay := RulesV2.new()
		replay.setup(defs, 780000 + i, data)
		for a in g.actions:
			if not replay.apply(a.duplicate(true)):
				errors.append("%d판: 재생 액션 거부" % i)
				break
		if str(replay.save_state()) != str(g.save_state()):
			errors.append("%d판: 재생 결과 불일치" % i)
	if GameAIV2.fallback_count != 0:
		errors.append("AI 대체 액션 %d회" % GameAIV2.fallback_count)
	if traitors < 3:
		errors.append("변절 판이 %d판뿐" % traitors)
	if ambush == 0 or informs == 0:
		errors.append("변절 행동 부족: 기습 %d · 밀고 %d" % [ambush, informs])
	print("v2 AI 시험: 4인 200판 · 2·3인 20판 · 완료 %d/220 · 변절 %d · 기습 %d · 밀고 %d · 선택 %d종 · 대체 %d · 실패 %d" % [
		total, traitors, ambush, informs, choices.size(), GameAIV2.fallback_count, errors.size()])
	for msg in errors.slice(0, 20):
		print("실패: ", msg)
	quit(1 if not errors.is_empty() else 0)
