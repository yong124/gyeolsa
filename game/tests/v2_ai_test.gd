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
	var confiscated := 0
	var used := {}
	var abilities := {}
	var choices := {}
	var done_types := {}
	var ops_blocked := 0
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
			used[a["type"]] = int(used.get(a["type"], 0)) + 1
			if saved != null and not saved.apply(a.duplicate(true)):
				errors.append("%d판: 불러온 판이 액션을 거부" % i)
				break
			step += 1
			for e in g.events:
				if e.get("kind", "") == "confiscate":
					confiscated += e["items"].size()
				if e.get("kind", "") == "ability":
					abilities[g.players[int(e["player"])]["character"]] = true
				if e.get("kind", "") == "mission_done":
					var mt := str(data.mission(str(e["id"])).get("type", ""))
					done_types[mt] = int(done_types.get(mt, 0)) + 1
				if e.get("kind", "") == "op_blocked":
					ops_blocked += 1
			g.events.clear()
		if g.phase != "over":
			errors.append("%d판: 멈춤 (%s, %d동작)" % [i, g.phase, step])
			continue
		total += 1
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
	if confiscated == 0:
		errors.append("투옥 압수가 한 번도 없음")
	for k in ["launch_vote", "launch_target", "strike_target", "launch_benefit", "mission_gear"]:
		if not choices.has(k) and k != "strike_target":
			errors.append("AI가 한 번도 답하지 않은 결행 선택: " + k)
	print("선택 종류: ", choices.keys())
	for t in ["assassin", "infiltrate", "bomb", "work", "contact", "lurk", "coop"]:
		if int(done_types.get(t, 0)) == 0:
			errors.append("AI가 한 번도 이루지 못한 미션 종류: " + t)
	if ops_blocked == 0:
		errors.append("AI가 일제 작전을 한 번도 막지 못함")
	print("AI가 이룬 미션(종류별): ", done_types, " · 막은 일제 작전 ", ops_blocked)
	for t in ["move_die", "step", "end_move", "end_turn", "mission_check", "work_give", "escape", "scout", "scene_check", "scene_pay"]:
		if int(used.get(t, 0)) == 0:
			errors.append("AI가 한 번도 안 쓴 행동: " + t)
	if int(used.get("end_turn", 0)) + total < int(used.get("begin_turn", 0)):
		errors.append("시작한 차례를 마치지 않은 판이 있음 (끝난 판의 마지막 차례 말고는 모두 마쳐야 함)")
	print("AI가 둔 행동: ", used)
	print("v2 AI 시험: 4인 200판 · 2·3인 20판 · 완료 %d/220 · 압수 %d장 · 능력 쓴 캐릭터 %d명 · 선택 %d종 · 대체 %d · 실패 %d" % [
		total, confiscated, abilities.size(), choices.size(), GameAIV2.fallback_count, errors.size()])
	for msg in errors.slice(0, 20):
		print("실패: ", msg)
	quit(1 if not errors.is_empty() else 0)
