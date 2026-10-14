class_name RulesAct2V2
extends RulesSagaV2
## 규칙 엔진 5층: 2막 장면 · 반격 · 엔딩.


# ================================================================ 2막 장면 · 엔딩

func _scene_card(id: String) -> Dictionary:
	var strike: Dictionary = data.strike(str(launch_info.get("target", "")))
	for card in [strike.get("entry", {}), strike.get("final", {})] + strike.get("middle", []) + data.scenes.get("reinforce", []):
		if card.get("id", "") == id:
			return card
	return {}


func current_scene() -> Dictionary:
	if act != 2 or scene_index >= scenes.size():
		return {}
	var card := _scene_card(str(scenes[scene_index])).duplicate(true)
	card["index"] = scene_index
	card["total"] = scenes.size()
	card["state"] = scene_state.duplicate(true)
	return card


func _scene_where(cond: Dictionary) -> String:
	return str(cond.get("where", current_scene().get("where", "inside")))


func _scene_at(p: Dictionary, cond: Dictionary, jailed_check := false) -> bool:
	var base := _base_cell(str(launch_info.get("target", "")))
	if p["jailed"]:
		return jailed_check and p["pos"] == base
	var d := _manhattan(p["pos"], base)
	var where := _scene_where(cond)
	if where in data.base_ids:
		return d == 0
	match where:
		"inside": return d == 0
		"adjacent": return d == 1
		"inside_or_adjacent": return d <= 1
	return false


func scene_place_cells() -> Array:
	var out := []
	if current_scene().is_empty():
		return out
	for y in data.size:
		for x in data.size:
			var cell := Vector2i(x, y)
			var probe := {"pos": cell, "jailed": false}
			if _scene_at(probe, {}):
				out.append(cell)
	return out


func _scene_leaves(cond: Dictionary, path := "") -> Array:
	var out := []
	var kind := str(cond.get("kind", ""))
	if kind in ["any_of", "all_of"]:
		for i in cond.get("options", []).size():
			out.append_array(_scene_leaves(cond["options"][i], "%s/%d" % [path, i]))
	elif kind == "sequence":
		## 단계는 차례로: 아직 못 끝낸 첫 단계(다 끝났으면 마지막 단계)의 조건만 지금 할 수 있다
		var steps: Array = cond.get("steps", [])
		for i in steps.size():
			var sp := "%s/%d" % [path, i]
			if i == steps.size() - 1 or not _scene_complete(steps[i], sp):
				out.append_array(_scene_leaves(steps[i], sp))
				break
	else:
		out.append({"cond": cond, "path": path})
	return out


func _scene_part(path: String) -> Dictionary:
	if path == "":
		if not scene_state.has("paid_dice"):
			scene_state.merge({"paid_dice": 0, "paid_items": 0, "paid_bombs": 0,
				"hold_days": 0, "pair_ok": [], "people": [], "dice_reduce": 0, "done": false})
		return scene_state
	if not scene_state.has("parts"):
		scene_state["parts"] = {}
	if not scene_state["parts"].has(path):
		scene_state["parts"][path] = {"paid_dice": 0, "paid_items": 0, "paid_bombs": 0,
			"hold_days": 0, "pair_ok": [], "people": [], "dice_reduce": 0, "done": false}
	return scene_state["parts"][path]


func _scene_part_read(path: String) -> Dictionary:
	return scene_state if path == "" else scene_state.get("parts", {}).get(path, {})


func _scene_complete(cond: Dictionary, path := "") -> bool:
	var kind := str(cond.get("kind", ""))
	if kind == "sequence":
		var steps: Array = cond.get("steps", [])
		for i in steps.size():
			if not _scene_complete(steps[i], "%s/%d" % [path, i]):
				return false
		return not steps.is_empty()
	if kind in ["any_of", "all_of"]:
		var options: Array = cond.get("options", [])
		if options.is_empty():
			return false
		for i in options.size():
			var done := _scene_complete(options[i], "%s/%d" % [path, i])
			if kind == "any_of" and done:
				return true
			if kind == "all_of" and not done:
				return false
		return kind == "all_of"
	var state := _scene_part_read(path)
	match kind:
		"check": return bool(state.get("done", false))
		"check_pair": return state.get("pair_ok", []).size() >= int(cond.get("count", 1))
		"dice": return int(state.get("paid_dice", 0)) >= maxi(0, int(cond.get("sum", 0)) - int(state.get("dice_reduce", 0)))
		"pay_item": return int(state.get("paid_items", 0)) >= int(cond.get("count", 1))
		"pay_bomb": return int(state.get("paid_bombs", 0)) >= int(cond.get("count", 1))
		"people": return state.get("people", []).size() >= int(cond.get("count", 1))
		"hold": return int(state.get("hold_days", 0)) >= int(cond.get("days", 1))
		"jailed_here":
			var base := _base_cell(str(launch_info.get("target", "")))
			for q in players:
				if q["jailed"] and q["pos"] == base:
					return true
	return false


func _scene_reveal() -> void:
	var card := current_scene()
	_push({"kind": "scene", "index": scene_index, "id": card["id"]})
	_log("장면 %d/%d: %s" % [scene_index + 1, scenes.size(), card["name"]])
	_banner("장면: %s" % card["name"], "info")
	if scene_index == scenes.size() - 1:
		_saga_final_reveal()
	_scene_auto_break()
	_counter_refresh()


func _scene_auto_break() -> void:
	var guard := scenes.size()
	while phase != "over" and act == 2 and scene_index < scenes.size() and guard > 0:
		guard -= 1
		if not _scene_complete(current_scene().get("condition", {})):
			break
		_scene_break(-1)


func _scene_break(by_pid: int) -> void:
	var card := current_scene()
	var id := str(card["id"])
	_push({"kind": "scene_break", "index": scene_index, "id": id, "player": by_pid})
	_banner("%s 돌파!" % card["name"], "good")
	_record("장면 돌파: %s" % card["name"], "good")
	_log("장면 돌파: %s" % card["name"])
	var kind := "entry" if scene_index == 0 else "final" if scene_index == scenes.size() - 1 else "middle"
	var present := []
	var base := _base_cell(str(launch_info.get("target", "")))
	for q in players:
		if not q["jailed"] and q["pos"] == base:
			present.append(q["id"])
	saga_strike_event(kind, by_pid, {"strike": launch_info["target"], "present": present})
	if kind == "final":
		_end_game(true)
		return
	scene_index += 1
	scene_state = {}
	_scene_reveal()


func _scene_check_leaf(p: Dictionary) -> Dictionary:
	if act != 2 or not _acting(p):
		return {}
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		var kind := str(leaf["cond"].get("kind", ""))
		if kind in ["check", "check_pair"] and not _scene_complete(leaf["cond"], str(leaf["path"])) \
				and _scene_at(p, leaf["cond"], true):
			if kind == "check_pair" and p["id"] in _scene_part_read(str(leaf["path"])).get("pair_ok", []):
				continue   # 이미 성공한 요원이 또 해도 두 명으로 치지 않는다
			return leaf
	return {}


func _scene_can_check(p: Dictionary) -> bool:
	return not _scene_check_leaf(p).is_empty() and not my_dice(p["id"]).is_empty()


func scene_check_target(cond: Dictionary) -> int:
	## 장면 판정 목표: 카드 목표 + 오늘 보정 − 이 장면에서 실패한 만큼 (rules.scenes.fail_ease씩, 최대 fail_ease_max)
	var name := str(cond.get("check", "generic"))
	var base := (int(cond["target"]) if cond.has("target") else check_target(name)) + int(today.get("scene_mod", 0))
	return base - scene_fail_ease()


func scene_fail_ease() -> int:
	## 「포위망이 좁혀진다」: 지금 장면에서 판정에 실패한 횟수만큼 목표가 내려간 양 (장면을 넘기면 0)
	var sc: Dictionary = data.rules.get("scenes", {})
	return mini(int(scene_state.get("fails", 0)) * int(sc.get("fail_ease", 0)), int(sc.get("fail_ease_max", 0)))


func _scene_check(p: Dictionary, die: int) -> void:
	var leaf := _scene_check_leaf(p)
	var cond: Dictionary = leaf["cond"]
	var name := str(cond.get("check", "generic"))
	var target := scene_check_target(cond)
	var bonus := int(p["flags"].get("intel_check", 0))
	p["flags"]["intel_check"] = 0
	_start_check(p, name, "scene", {"target": target, "scene_path": leaf["path"], "scene_id": scenes[scene_index], "intel_bonus": bonus,
		"die_i": die})


func _scene_check_result(p: Dictionary, c: Dictionary, ok: bool) -> void:
	if str(c.get("scene_id", "")) != str(scenes[scene_index]):
		return
	if ok:
		var path := str(c["scene_path"])
		var part := _scene_part(path)
		var cond: Dictionary = _scene_cond_at(path)
		if cond.get("kind", "") == "check_pair":
			if not p["id"] in part["pair_ok"]:
				part["pair_ok"].append(p["id"])
		else:
			part["done"] = true
		if _scene_complete(current_scene()["condition"]):
			_scene_break(p["id"])
	else:
		var before := scene_fail_ease()
		scene_state["fails"] = int(scene_state.get("fails", 0)) + 1
		if scene_fail_ease() > before:
			_log("포위망이 좁혀집니다: 이 장면의 판정 목표 −%d." % scene_fail_ease())
		_run_effects(p, current_scene().get("on_fail", []), {"then": "scene_check_done"})


func _finish_scene_check(_p: Dictionary) -> void:
	pass


func _scene_cond_at(path: String) -> Dictionary:
	var cond: Dictionary = current_scene().get("condition", {})
	for index in path.split("/", false):
		cond = cond["steps"][int(index)] if cond.has("steps") else cond.get("options", [])[int(index)]
	return cond


func _scene_pay_leaf(p: Dictionary, what: String, index: int) -> Dictionary:
	if act != 2 or not _acting(p) or p["jailed"]:
		return {}
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		var cond: Dictionary = leaf["cond"]
		var kind := str(cond.get("kind", ""))
		if _scene_complete(cond, str(leaf["path"])) or not _scene_at(p, cond):
			continue
		if what == "die" and kind == "dice" and index in my_dice(p["id"]):
			return leaf
		if what == "item" and kind == "pay_item" and index >= 0 and index < p["items"].size() and not my_dice(p["id"]).is_empty():
			return leaf
		if what == "bomb" and kind == "pay_bomb":
			var need := int(cond.get("count", 1)) if not cond.get("split", false) else 1
			if p["bombs"] >= need and not my_dice(p["id"]).is_empty():
				return leaf
	return {}


func _scene_can_pay(p: Dictionary, what: String, index: int) -> bool:
	return not _scene_pay_leaf(p, what, index).is_empty()


func _scene_pay(p: Dictionary, what: String, index: int, spend := -1) -> void:
	## 바치기 행동. 주사위를 바칠 때는 그 눈이 합에 더해지고, 아이템·폭탄을 바칠 때는 주사위 하나(spend, 눈은 상관없음)를 낸다.
	var leaf := _scene_pay_leaf(p, what, index)
	var cond: Dictionary = leaf["cond"]
	var part := _scene_part(str(leaf["path"]))
	match what:
		"die":
			part["paid_dice"] = int(part["paid_dice"]) + die_value(index)
			_use_die(p, index, "scene")
		"item":
			_use_die(p, spend, "scene")
			item_discard.append(p["items"].pop_at(index))
			part["paid_items"] = int(part["paid_items"]) + 1
		"bomb":
			_use_die(p, spend, "scene")
			var n := 1 if cond.get("split", false) else int(cond.get("count", 1))
			p["bombs"] -= n
			bomb_supply += n
			part["paid_bombs"] = int(part["paid_bombs"]) + n
	_log("%s: 장면에 %s을(를) 바쳤습니다." % [p["name"], {"die": "주사위", "item": "아이템", "bomb": "폭탄"}[what]])
	_scene_auto_break_by(p["id"])


func _scene_auto_break_by(pid: int) -> void:
	if _scene_complete(current_scene().get("condition", {})):
		_scene_break(pid)


func _scene_can_intel(p: Dictionary, mode: String) -> bool:
	if act != 2 or not _acting(p) or intel_tokens <= 0:
		return false
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		if _scene_complete(leaf["cond"], str(leaf["path"])):
			continue
		if mode == "check" and leaf["cond"].get("kind", "") in ["check", "check_pair"]:
			return true
		if mode == "dice" and leaf["cond"].get("kind", "") == "dice":
			return true
	return false


func _scene_use_intel(p: Dictionary, mode: String) -> void:
	intel_tokens -= 1
	if mode == "check":
		p["flags"]["intel_check"] = int(p["flags"].get("intel_check", 0)) + int(data.rules["intel_token"]["check_bonus"])
	else:
		for leaf in _scene_leaves(current_scene().get("condition", {})):
			if leaf["cond"].get("kind", "") == "dice" and not _scene_complete(leaf["cond"], str(leaf["path"])):
				var part := _scene_part(str(leaf["path"]))
				part["dice_reduce"] = int(part["dice_reduce"]) + int(data.rules["intel_token"]["dice_reduce"])
				break
		_scene_auto_break_by(p["id"])
	_log("%s: 첩보 토큰을 썼습니다." % p["name"])


func scene_options(p: Dictionary) -> Array:
	var out := []
	if act != 2 or not _acting(p):
		return out
	var dice := my_dice(p["id"])
	if _scene_can_check(p):
		for i in dice:
			out.append({"type": "scene_check", "player": p["id"], "die": i})
	if can_counter_check(p):
		for i in dice:
			out.append({"type": "counter_check", "player": p["id"], "die": i})
	for i in dice:
		if _scene_can_pay(p, "die", i):
			out.append({"type": "scene_pay", "player": p["id"], "what": "die", "die": i})
	for k in p["items"].size():
		if _scene_can_pay(p, "item", k):
			for i in dice:
				out.append({"type": "scene_pay", "player": p["id"], "what": "item", "index": k, "with": i})
	if _scene_can_pay(p, "bomb", -1):
		for i in dice:
			out.append({"type": "scene_pay", "player": p["id"], "what": "bomb", "with": i})
	for mode in ["check", "dice"]:
		if _scene_can_intel(p, mode):
			out.append({"type": "use_intel", "player": p["id"], "mode": mode})
	return out


func _scene_turn_end(p: Dictionary) -> void:
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		if leaf["cond"].get("kind", "") == "people" and _scene_at(p, leaf["cond"]):
			var part := _scene_part(str(leaf["path"]))
			if not p["id"] in part["people"]:
				part["people"].append(p["id"])
	_scene_auto_break_by(p["id"])


func _scene_hold_leaves() -> Array:
	return _scene_leaves(current_scene().get("condition", {})).filter(func(l): return str(l["cond"].get("kind", "")) == "hold")


func counter_active() -> bool:
	## 오늘 반격이 걸려 있고 아직 못 막았는가
	return act == 2 and int(counter.get("day", -1)) == day and not bool(counter.get("blocked", false))


func _counter_refresh() -> void:
	## 「버티기」 장면이 펼쳐진 날에는 반격이 걸린다 (아침, 또는 그날 안에 그 장면이 펼쳐질 때)
	if act != 2 or phase == "over" or int(counter.get("day", -1)) == day or current_scene().is_empty():
		return
	if _scene_hold_leaves().is_empty():
		return
	counter = {"day": day, "blocked": false}
	_log("반격! 오늘 「%s」 자리에서 작전 판정 %d에 성공해야 버틴 날로 칩니다." % [current_scene()["name"], int(data.rules["counter"]["target"])])
	_push({"kind": "counter", "scene": current_scene()["id"]})


func _counter_at(p: Dictionary) -> bool:
	for leaf in _scene_hold_leaves():
		if _scene_at(p, leaf["cond"]):
			return true
	return false


func can_counter_check(p: Dictionary) -> bool:
	## 반격을 막는 작전 판정: 그 장면 자리에 선 요원이 주사위 하나로 (실패하면 다른 주사위로 또)
	return counter_active() and _acting(p) and not p["jailed"] and not my_dice(p["id"]).is_empty() and _counter_at(p)


func _scene_night() -> bool:
	## 밤의 장면 처리. 반격을 못 막았으면 버틴 날을 세지 않고, 자리에 선 요원이 회피 판정을 한다 (처리 중이면 true).
	var attacked := counter_active()
	for leaf in _scene_hold_leaves():
		var count := 0
		for q in players:
			if not q["jailed"] and _scene_at(q, leaf["cond"]):
				count += 1
		if attacked:
			if count > 0:
				_log("반격을 막지 못해 오늘은 버틴 날로 치지 않습니다.")
		elif count >= int(leaf["cond"].get("count", 1)):
			var part := _scene_part(str(leaf["path"]))
			part["hold_days"] = int(part["hold_days"]) + 1
	if attacked:
		counter_queue = []
		for q in players:
			if not q["jailed"] and _counter_at(q):
				counter_queue.append(q["id"])
		if not counter_queue.is_empty():
			_counter_next()
			return true
	_scene_night_finish()
	return false


func _counter_next() -> void:
	## 반격을 못 막은 밤: 자리에 선 요원이 차례로 회피 판정 (실패하면 투옥)
	if phase == "over":
		return
	if counter_queue.is_empty():
		_scene_night_finish()
		if phase != "over":
			_night_after_scene()
		return
	var pid: int = counter_queue.pop_front()
	if players[pid]["jailed"]:
		_counter_next()
		return
	_log("%s: 반격을 피하려 회피 판정을 합니다." % players[pid]["name"])
	_start_check(players[pid], "evade", "counter_evade")


func _scene_night_finish() -> void:
	if _scene_complete(current_scene().get("condition", {})):
		_scene_break(-1)
	if phase == "over":
		return
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		var part := _scene_part(str(leaf["path"]))
		part["pair_ok"] = []
		part["people"] = []
	for q in players:
		q["flags"].erase("intel_check")
	counter = {}


func scene_need(i := -1) -> Dictionary:
	if act != 2 or scenes.is_empty():
		return {}
	var cond: Dictionary = current_scene().get("condition", {}) if i < 0 else _scene_card(str(scenes[i])).get("condition", {})
	var out := {}
	for leaf in _scene_leaves(cond):
		var c: Dictionary = leaf["cond"]
		var path := str(leaf["path"])
		var part: Dictionary = _scene_part_read(path) if i < 0 or i == scene_index else {}
		match str(c.get("kind", "")):
			"dice": out["dice"] = maxi(0, int(c.get("sum", 0)) - int(part.get("dice_reduce", 0)) - int(part.get("paid_dice", 0)))
			"pay_item": out["item"] = maxi(0, int(c.get("count", 1)) - int(part.get("paid_items", 0)))
			"pay_bomb": out["bomb"] = maxi(0, int(c.get("count", 1)) - int(part.get("paid_bombs", 0)))
			"check_pair": out["check_pair"] = maxi(0, int(c.get("count", 1)) - part.get("pair_ok", []).size())
			"people": out["people"] = maxi(0, int(c.get("count", 1)) - part.get("people", []).size())
			"hold": out["hold"] = maxi(0, int(c.get("days", 1)) - int(part.get("hold_days", 0)))
	return out


func _search_next() -> void:
	if search_queue.is_empty():
		_stage4_resume()
		return
	var pid: int = search_queue.pop_front()
	_start_check(players[pid], "evade", "search")


func _stage4_resume() -> void:
	if effect_wait.is_empty():
		return
	var wait: Dictionary = effect_wait.pop_back()
	_run_effects(players[int(wait["player"])], wait["rest"], wait["ctx"])


func _end_game(won: bool) -> void:
	var target := str(launch_info.get("target", "")) if act == 2 else ""
	var card := current_scene() if act == 2 else {}
	var id := "victory" if won else "history" if act == 1 or scene_index == 0 else "fail_final" if scene_index == scenes.size() - 1 else "fail_middle"
	var key := "operation" if id == "fail_middle" else id
	var def: Dictionary = data.endings.get(key, {})
	var body := str(data.endings.get("strikes", {}).get(target, {}).get("ending", "")) if won else str(def.get("text", ""))
	if not won and not card.is_empty():
		body = str(card.get("stop_text", "")) + "\n" + body
	var epilogues := []
	for p in players:
		var result := saga_result(p["id"])
		var saga_id := str(result.get("saga", ""))
		var epkey := epilogue_key(p["id"], won)
		var saga: Dictionary = data.saga(saga_id)
		var lines: Dictionary = saga.get("epilogue", {})
		var line = lines.get(epkey)
		if line == null:
			epkey = "win_fail" if won else "lose_fail"
			line = lines.get(epkey, "")
		var character: Dictionary = char_def(p)
		var faction := str(data.characters.get("factions", {}).get(character.get("faction", ""), {}).get("name", ""))
		epilogues.append({"player": p["id"], "saga": saga_id, "key": epkey,
			"text": "%s %s — %s" % [faction, character.get("name", p["name"]), str(line)],
			"done": bool(result.get("done", false))})
	ending = {"id": id, "won": won, "target": target, "scene": str(card.get("id", "")),
		"scene_index": scene_index if act == 2 else -1, "title": str(def.get("name", "")), "text": body,
		"epilogues": epilogues}
	phase = "over"
	pending = {}
	_record("작전 종료: %s" % ending["title"], "good" if won else "bad")
	_log("작전 종료: %s" % ending["title"])
	_push({"kind": "over"})
