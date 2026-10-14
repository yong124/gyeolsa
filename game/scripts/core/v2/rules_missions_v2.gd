class_name RulesMissionsV2
extends RulesEffectsV2
## 규칙 엔진 3층: 미션 · 일제 작전 (보드 위 마커).


# ================================================================ 미션 · 일제 작전 (보드 위 마커)
##
## 미션 카드와 일제 작전 카드는 보드에 마커를 놓는다 (markers). 종류는 condition.kind로 움직인다:
##   assassinate 표적 칸에서 작전 판정(mission_check) · infiltrate 거점에 들어감 · bomb 폭탄을 들고 마커 칸에 들어감 ·
##   work 마커 칸에서 바치기(work_give) · contact 받기 마커를 지나 주기 마커에 들어감 · lurk 마커 곁에서 쫓기지 않고 차례를 마침.
## 카드마다의 진행(바친 눈, 잠복 날, 든 요원, 동선 파악)은 mission_state[id]에 있다.

func _center(id: String) -> Vector2i:
	## 마커를 놓는 기준 칸: 거점 id 또는 start
	return data.start if id == "start" else _base_cell(id)


func _marker_blocked(c: Vector2i, level := 0) -> bool:
	## 마커를 놓거나 옮길 수 없는 칸: 거점, 출발점, 다른 마커가 있는 칸, (level 0) 요원·경찰이 있는 칸. 덮인 칸은 괜찮다.
	if c == data.start or c in data.bases or not marker_at(c).is_empty():
		return true
	if level == 0:
		if police_on(c):
			return true
		for q in players:
			if q["pos"] == c:
				return true
	return false


func _marker_pos(spec: Dictionary) -> Vector2i:
	## 마커 하나를 놓을 칸: at이면 그 칸, around이면 그곳에서 min~max칸(맨해튼) 떨어진 칸 중 게임이 무작위로 고름
	if spec.has("at"):
		return _center(str(spec["at"]))
	var ctr := _center(str(spec["around"]))
	for level in 2:
		var cands := []
		for x in data.size:
			for y in data.size:
				var c := Vector2i(x, y)
				var d := _manhattan(c, ctr)
				if d >= int(spec["min"]) and d <= int(spec["max"]) and not _marker_blocked(c, level):
					cands.append(c)
		if not cands.is_empty():
			return cands[rng.randi_range(0, cands.size() - 1)]
	return ctr


func _in_region(c: Vector2i, spec: Dictionary) -> bool:
	if not spec.has("around"):
		return false
	var d := _manhattan(c, _center(str(spec["around"])))
	return d >= int(spec["min"]) and d <= int(spec["max"])


func _place_card(id: String) -> void:
	## 미션·일제 작전 카드가 나오면 진행 상태를 만들고 마커를 놓는다
	var card: Dictionary = data.marker_card(id)
	var cond: Dictionary = card.get("condition", {})
	var left := []
	if str(cond.get("kind", "")) == "work" and str(cond.get("mode", "")) == "combo":
		for v in cond["values"]:
			left.append(int(v))
	mission_state[id] = {"placed": day, "days": int(card["deadline"]) if card.has("deadline") else -1,
		"informed": false, "holder": -1, "picked_day": -1, "chased": false,
		"sum": 0, "need": int(cond.get("target", 0)), "left": left, "by": [], "work_days": [], "reduced": false,
		"lurk": 0, "lurk_day": -1, "lurk_pids": [], "doubled": false}
	var k := 0
	for spec in card.get("markers", []):
		for n in int(spec.get("count", 1)):
			marker_seq += 1
			markers.append({"uid": marker_seq, "id": id, "role": str(spec["role"]), "pos": _marker_pos(spec),
				"move": int(spec.get("move", 0)), "spec": k})
		k += 1
	_push({"kind": "markers", "id": id, "placed": true})


func _remove_card(id: String) -> void:
	## 이루었거나 놓쳤거나 막은 카드의 마커와 진행을 치우고 버린다
	markers = markers.filter(func(m): return m["id"] != id)
	mission_state.erase(id)
	mission_row.erase(id)
	op_row.erase(id)
	if data.is_op(id):
		op_discard.append(id)
	else:
		mission_discard.append(id)
	_push({"kind": "markers", "id": id, "placed": false})


# ---------------------------------------------------------------- 아침: 일제 작전 · 표적 이동 · 기한

func _morning_ops() -> void:
	## 1막 rules.ops.days일째 아침: 일제 작전 카드 1장을 뒤집어 마커를 놓고 동향을 1 올린다
	if act != 1:
		return
	var due := false
	for d in data.rules["ops"]["days"]:
		if int(d) == day:
			due = true
	if not due:
		return
	if op_deck.is_empty():
		op_deck = op_discard
		op_discard = []
		_shuffle(op_deck)
	if op_deck.is_empty():
		return
	var id: String = op_deck.pop_back()
	op_row.append(id)
	_place_card(id)
	trend = mini(trend + 1, int(data.rules["ops"]["trend_max"]))
	var card: Dictionary = data.op_card(id)
	_log("[일제 작전] %s — %s (일제 동향 %d)" % [card.get("name", id), card.get("how", ""), trend])
	_record("일제 작전: %s" % card.get("name", id), "warn")
	stats["ops_seen"] += 1
	_banner("일제 작전: %s" % card.get("name", id), "warn")
	_push({"kind": "op_appear", "id": id})
	_push({"kind": "trend", "value": trend})


func _trend_penalty() -> Array:
	## 지금 동향에서 못 막았을 때 카드의 벌칙에 더 붙는 효과 (rules.ops.penalties 중 min이 동향 이하인 가장 큰 칸)
	var out: Array = []
	for row in data.rules["ops"]["penalties"]:
		if trend >= int(row["min"]):
			out = row["effects"].duplicate(true)
	return out


func _trend_reinforce() -> int:
	## 결행할 때의 동향이 정하는 2막 위협 덱의 증원 카드 장수
	var n := 0
	for row in data.rules["ops"]["reinforce_by_trend"]:
		if trend >= int(row["min"]):
			n = int(row["count"])
	return n


func _morning_markers() -> void:
	## 1막 아침: 움직이는 표적을 옮기고, 기한이 있는 카드의 남은 날을 1 줄이고, 0이 된 것은 놓친 것으로 처리한다.
	## 오늘 새로 나온 카드는 오늘 줄이지 않는다.
	if act != 1:
		return
	_move_markers()
	var ids := []
	ids.append_array(mission_row)
	ids.append_array(op_row)
	for id in ids:
		var st: Dictionary = mission_state.get(id, {})
		if int(st.get("days", -1)) < 0 or int(st.get("placed", -1)) == day:
			continue
		st["days"] = int(st["days"]) - 1
		if int(st["days"]) <= 0:
			expire_queue.append(id)
	if not expire_queue.is_empty():
		_morning_expire()


func _move_markers() -> void:
	## 움직이는 표적(move > 0)을 매일 아침 지역 안에서 무작위로 옮긴다. 정보원으로 동선을 알아낸 표적은 멈춘다.
	for m in markers:
		if int(m["move"]) <= 0 or str(m["role"]) != "target":
			continue
		if bool(mission_state.get(m["id"], {}).get("informed", false)):
			continue
		var spec: Dictionary = data.marker_card(str(m["id"])).get("markers", [])[int(m["spec"])]
		var from: Vector2i = m["pos"]
		for k in int(m["move"]):
			var opts := []
			for d in DIRS:
				var n: Vector2i = m["pos"] + d
				if in_bounds(n) and not _marker_blocked(n) and _in_region(n, spec):
					opts.append(n)
			if opts.is_empty():
				break
			m["pos"] = opts[rng.randi_range(0, opts.size() - 1)]
		if m["pos"] != from:
			_push({"kind": "marker_moved", "id": m["id"], "from": from, "to": m["pos"]})


func _morning_expire() -> void:
	## 기한이 다 된 카드를 하나씩 놓친 것으로 처리한다 (벌칙에 선택이 끼면 멈췄다 이어 감). 일제 작전은 동향이 1 더 오른다.
	if expire_queue.is_empty():
		_morning_continue()
		return
	var id: String = expire_queue.pop_front()
	var card: Dictionary = data.marker_card(id)
	var is_op := data.is_op(id)
	var cell: Vector2i = data.start
	var at := markers_of(id)
	if not at.is_empty():
		cell = at[0]["pos"]
	var effects: Array = card.get("missed", []).duplicate(true)
	if is_op:
		effects.append_array(_trend_penalty())
	_log("%s 「%s」을(를) 놓쳤습니다!%s" % ["일제 작전" if is_op else "미션", card.get("name", id), (" (일제 동향 %d)" % trend) if is_op else ""])
	_record("%s 「%s」 놓침" % ["일제 작전" if is_op else "미션", card.get("name", id)], "bad")
	_banner("%s 놓침" % card.get("name", id), "bad")
	_push({"kind": "op_missed" if is_op else "mission_missed", "id": id})
	if is_op:
		trend = mini(trend + 1, int(data.rules["ops"]["trend_max"]))
		_push({"kind": "trend", "value": trend})
	_remove_card(id)
	_run_effects(players[leader], effects, {"then": "morning_expire", "source": "mission", "cell": cell})


# ---------------------------------------------------------------- 마커 칸에 들어갈 때

func _marker_arrive(p: Dictionary, cell: Vector2i) -> bool:
	## 방금 들어간 칸의 마커. 암살 표적 칸에서는 이동이 멈춘다 (판정은 따로 행동으로). 정보원에 들르면 동선을 알아내고(공짜),
	## 받기 마커를 지나가면 물건을 들고, 폭탄을 들고 폭파 지점에 들어가거나 물건을 들고 주기 마커에 들어가면 이룬다.
	## 미션을 이뤄 보상 처리를 시작했으면 true.
	var done := []
	var stop := false
	for m in markers_at(cell):
		var id := str(m["id"])
		var kind := str(card_cond(id).get("kind", ""))
		match str(m["role"]):
			"target":
				if kind == "assassinate":
					stop = true
				elif kind == "bomb" and p["bombs"] > 0 and not id in done:
					p["bombs"] -= 1
					_log("%s: 폭탄을 설치했습니다!" % p["name"])
					done.append(id)
			"informer":
				_use_informer(p, m)
			"pickup":
				_pickup(p, m)
			"dropoff":
				if int(mission_state.get(id, {}).get("holder", -1)) == p["id"] and not id in done:
					done.append(id)
	if not done.is_empty():
		steps_left = 0
		_complete_missions(p, done, {"then": "stop", "source": "mission"})
		return true
	if stop:
		steps_left = 0
	return false


func _use_informer(p: Dictionary, m: Dictionary) -> void:
	## 정보원 마커에 들름: 표적의 동선을 알아내 표적이 멈추고 판정이 쉬워진다. 마커는 사라진다.
	var id := str(m["id"])
	var st: Dictionary = mission_state.get(id, {})
	if st.is_empty() or bool(st["informed"]):
		return
	st["informed"] = true
	markers = markers.filter(func(x): return x["uid"] != m["uid"])
	_log("%s: 정보원에게서 「%s」 표적의 동선을 알아냈습니다. 표적이 멈추고 판정이 쉬워집니다." % [p["name"], card_def(id).get("name", id)])
	_banner("동선 파악!", "info", p)
	_push({"kind": "informed", "id": id, "player": p["id"]})


func _pickup(p: Dictionary, m: Dictionary) -> void:
	## 받기 마커를 지나감: 물건을 든다 (이미 누가 들고 있으면 안 됨)
	var id := str(m["id"])
	var st: Dictionary = mission_state.get(id, {})
	if st.is_empty() or int(st["holder"]) >= 0:
		return
	st["holder"] = p["id"]
	st["picked_day"] = day
	st["chased"] = false
	_log("%s: 「%s」의 물건을 들었습니다%s." % [p["name"], card_def(id).get("name", id), " (무거움: 이동 눈 -1)" if bool(card_cond(id).get("heavy", false)) else ""])
	_banner("물건을 들었다", "info", p)
	_push({"kind": "pickup", "id": id, "player": p["id"]})


func _drop_contacts(p: Dictionary) -> void:
	## 투옥되면 든 물건은 받기 마커로 돌아간다
	for id in mission_row:
		var st: Dictionary = mission_state.get(id, {})
		if int(st.get("holder", -1)) == p["id"]:
			st["holder"] = -1
			st["picked_day"] = -1
			_log("%s: 들고 있던 「%s」의 물건이 받기 마커로 돌아갔습니다." % [p["name"], card_def(id).get("name", id)])
			_push({"kind": "item_lost", "id": id, "player": p["id"]})


# ---------------------------------------------------------------- 공작 · 판정

func _work_give(p: Dictionary, die: int) -> void:
	## 공작 마커에 주사위 하나를 바친다 (판정 없음). 합 N은 눈을 더하고, 조합은 필요한 눈 하나를 채우고,
	## 마커마다 하나는 이 마커를 치운다. 문 선전대원(work_reduce)은 카드마다 한 번 바칠 것을 줄인다.
	var m := marker_at(p["pos"])
	var id := str(m["id"])
	var st: Dictionary = mission_state[id]
	var cond := card_cond(id)
	var v := die_value(die)
	_use_die(p, die, "work")
	if not p["id"] in st["by"]:
		st["by"].append(p["id"])
	if not day in st["work_days"]:
		st["work_days"].append(day)
	var cutn := stat(p, "work_reduce")
	var done := false
	match str(cond.get("mode", "")):
		"sum":
			if cutn > 0 and not st["reduced"]:
				st["reduced"] = true
				st["need"] = maxi(0, int(st["need"]) - cutn)
				_log("%s: 공작에서 바칠 합이 %d 줄었습니다." % [p["name"], cutn])
			st["sum"] = int(st["sum"]) + v
			done = int(st["sum"]) >= int(st["need"])
		"combo":
			st["left"].erase(v)
			if cutn > 0 and not st["reduced"] and not st["left"].is_empty():
				st["reduced"] = true
				var big: int = st["left"].max()
				st["left"].erase(big)
				_log("%s: 공작에서 바칠 눈 %d이(가) 줄었습니다." % [p["name"], big])
			done = st["left"].is_empty()
		"each":
			markers = markers.filter(func(x): return x["uid"] != m["uid"])
			done = markers_of(id, "work").is_empty()
	var status := card_status(id)
	_log("%s: 「%s」에 주사위 %d을(를) 바쳤습니다.%s" % [p["name"], card_def(id).get("name", id), v, (" (%s)" % status) if status != "" and not done else ""])
	_push({"kind": "work_give", "id": id, "player": p["id"], "value": v})
	_saga_note(p, "work_give")
	if done:
		_complete_missions(p, [id], {"then": "resume", "source": "mission"})


func _begin_mission_check(p: Dictionary, cell: Vector2i, die: int) -> void:
	## 표적 마커에서 작전 판정 행동 (낸 눈 + 새 주사위). 동선을 알아냈으면 판정이 쉽다.
	var m := marker_at(cell)
	var id := str(m["id"])
	var cond := card_cond(id)
	var extra := {"ids": [id], "target": int(cond["target"]), "cell": cell, "die_i": die,
		"intel_bonus": int(cond.get("informed_bonus", 0)) if bool(mission_state.get(id, {}).get("informed", false)) else 0}
	_start_check(p, str(cond["check"]), "mission_check", extra)


func _mission_check_result(p: Dictionary, c: Dictionary, ok: bool) -> void:
	## 표적 마커 판정 결과. 성공하면 미션을 이루고 (시끄러운 미션은 경찰이 붙음), 실패하면 회피 판정(강제)으로 빠져나가야 한다.
	var id := str(c["ids"][0])
	var cond := card_cond(id)
	if ok:
		if str(cond.get("check", "")) == "assassin":
			p["stats"]["assassinations"] += 1
		_complete_missions(p, c["ids"], {"then": "resume", "source": "mission"})
	elif bool(cond.get("risky", true)):
		_log("%s: 실패! 회피 판정으로 빠져나가야 합니다." % p["name"])
		_banner("%s 실패 — 탈출하라!" % _check_label(c), "bad", p)
		_start_check(p, "evade", "mission_evade")
	else:
		_log("%s: 실패했습니다." % p["name"])
		_banner("%s 실패" % _check_label(c), "bad", p)
		_summon(p)
		_finish_move(p)


# ---------------------------------------------------------------- 이룸 · 막음

func _bonus_holds(p: Dictionary, id: String, cond: Dictionary) -> bool:
	## 미션 보너스 조건 (규칙서 부록 · 미션). 이루는 순간, 경찰이 붙기 전에 확인한다.
	var st: Dictionary = mission_state.get(id, {})
	match str(cond.get("kind", "")):
		"not_chased":
			return not police.has(p["id"])
		"faction":
			return str(char_def(p).get("faction", "")) == str(cond.get("faction", ""))
		"days_left":
			return card_days_left(id) >= int(cond.get("min", 1))
		"ally_adjacent":
			for q in players:
				if q["id"] != p["id"] and not q["jailed"] and _manhattan(q["pos"], p["pos"]) <= 1:
					return true
			return false
		"same_day":
			if str(card_cond(id).get("kind", "")) == "contact":
				return int(st.get("picked_day", -1)) == day
			return st.get("work_days", []).size() <= 1
		"contributors":
			return st.get("by", []).size() >= int(cond.get("min", 2))
		"carrier_clean":
			return not bool(st.get("chased", false)) and not police.has(p["id"])
	return false


func _complete_missions(p: Dictionary, ids: Array, ctx: Dictionary) -> void:
	## 한 번의 행동으로 채운 미션(과 막은 일제 작전)들을 모두 이룬다. 보너스는 이루는 순간 조건을 확인하고,
	## 시끄러운 미션은 노출 +1에 경찰이 붙는다 (보너스로 「경찰이 붙지 않음」이면 안 붙음). 보상은 효과 목록으로 해석기에 넘긴다.
	var effects := []
	var loud := false
	var no_police := false
	for id in ids:
		var m: Dictionary = data.marker_card(id)
		if data.is_op(id):
			_log("%s: 일제 작전 「%s」을(를) 막았습니다!" % [p["name"], m.get("name", id)])
			_record("%s — 일제 작전 %s 저지" % [p["name"], m.get("name", id)], "good")
			stats["ops_blocked"] += 1
			_banner("%s 저지!" % m.get("name", id), "good", p)
			_push({"kind": "op_blocked", "id": id, "player": p["id"]})
			effects.append_array(data.rules["ops"]["block"].duplicate(true))
			_remove_card(id)
			continue
		var type: String = m.get("type", "")
		var td: Dictionary = mission_type_def(type)
		var bonus_fx := []
		var b = m.get("bonus")
		if typeof(b) == TYPE_DICTIONARY:
			var bc: Dictionary = b["if"]
			if str(bc.get("kind", "")) == "launch_target":
				bonus_wait.append({"player": p["id"], "base": str(bc["base"]), "reward": b["reward"].duplicate(true)})   # 결행 때 판정
			elif _bonus_holds(p, id, bc):
				_log("%s: 보너스! %s" % [p["name"], b.get("text", "")])
				for be in b["reward"]:
					if str(be.get("op", "")) == "entry_no_police":
						no_police = true
					else:
						bonus_fx.append(be)
		for pid in _coop_participants(id, p, ctx):
			_saga_note(players[pid], "coop_missions")
		_remove_card(id)
		p["stats"]["missions"] += 1
		_log("%s: 미션 「%s」 성공!" % [p["name"], m.get("name", id)])
		var done_ctx := {"id": id, "mission_kind": str(card_cond(id).get("kind", ""))}
		_saga_note(p, "mission_done_by_me", done_ctx)
		_saga_note(p, "mission_kind_by_me", done_ctx)
		_record("%s — %s 성공" % [p["name"], m.get("name", id)], "good")
		_banner("%s 성공!" % m.get("name", id), "good", p)
		_push({"kind": "mission_done", "id": id, "player": p["id"]})
		var rd = m["ready"] if m.has("ready") else td.get("ready", null)
		if rd != null and int(rd) != 0:
			effects.append({"op": "ready", "value": int(rd)})
		var bonus := stat(p, "mission_intel_bonus", type)
		if bonus > 0 and m.get("intel", null) != null:
			effects.append({"op": "intel", "base": m["intel"], "value": bonus})
		var ex := stat(p, type + "_exposure")   # 문 선전대원의 work_exposure −1 (공작을 이루면 노출)
		if ex != 0:
			effects.append({"op": "exposure", "value": ex})
		effects.append_array(m.get("rewards", []))
		effects.append_array(bonus_fx)
		var ld = m["loud"] if m.has("loud") else td.get("loud", false)
		if ld != null and bool(ld):
			loud = true
	if loud:
		if no_police:
			_log("%s: 망을 봐 준 동료 덕에 경찰이 붙지 않았습니다." % p["name"])
		else:
			_summon(p)
		effects.append({"op": "exposure", "value": int(data.rules["exposure"]["loud"])})
	_run_effects(p, effects, ctx)


func _where_match(c: Vector2i, cond: Dictionary) -> bool:
	## 협동 조건의 where(+ base): 그 거점의 안 / 옆 칸 / 안이거나 옆 칸. where가 거점 id면 그 거점 안.
	var where := str(cond.get("where", "inside"))
	var base_id := str(cond.get("base", ""))
	if where in data.base_ids:
		return c == _base_cell(where)
	if base_id == "":
		return false
	var d := _manhattan(c, _base_cell(base_id))
	match where:
		"inside":
			return d == 0
		"adjacent":
			return d == 1
		"inside_or_adjacent":
			return d <= 1
	return false


func _coop_enter_base(p: Dictionary, bi: int) -> Array:
	## 협동 미션 — 거점에 들어갈 때 확인 (cover_entry: 다른 한 명이 그 거점 옆 칸). 이뤄진 미션 id 목록.
	var out := []
	for id in _coop_ids("cover_entry"):
		for q in players:
			if q["id"] != p["id"] and not q["jailed"] and _manhattan(q["pos"], data.bases[bi]) == 1:
				out.append(id)
				break
	return out


func _lurk_count(p: Dictionary, id: String, cond: Dictionary, st: Dictionary) -> bool:
	## 잠복: 마커 칸(adjacent이면 옆 칸 포함)에서 쫓기지 않고 차례를 마친 날을 센다. 같은 날은 한 번이고,
	## double_with명이 같은 날 하면 그날은 2일로 친다. 날이 다 차면 true.
	if p["jailed"] or police.has(p["id"]):
		return false
	var spot := markers_of(id, "spot")
	if spot.is_empty():
		return false
	if _manhattan(p["pos"], spot[0]["pos"]) > (1 if bool(cond.get("adjacent", true)) else 0):
		return false
	var first := int(st["lurk_day"]) != day
	if first:
		st["lurk_day"] = day
		st["lurk_pids"] = []
		st["doubled"] = false
		st["lurk"] = int(st["lurk"]) + 1
	if not p["id"] in st["lurk_pids"]:
		st["lurk_pids"].append(p["id"])
		if not first and int(cond.get("double_with", 0)) > 0 and st["lurk_pids"].size() >= int(cond["double_with"]) and not st["doubled"]:
			st["doubled"] = true
			st["lurk"] = int(st["lurk"]) + 1
			_log("두 요원이 같은 날 잠복해 그날은 2일로 칩니다.")
	_log("%s: 「%s」 잠복 %d / %d일" % [p["name"], card_def(id).get("name", id), int(st["lurk"]), int(cond.get("days", 1))])
	_push({"kind": "lurk", "id": id, "player": p["id"]})
	return int(st["lurk"]) >= int(cond.get("days", 1))


func _turn_end_missions(p: Dictionary) -> bool:
	## 차례를 마칠 때: 물건을 든 요원이 쫓기면 기록하고, 잠복 날을 세고, 협동 미션(people · opposite_edges)을 확인한다.
	## 이뤄진 미션(막은 일제 작전)의 보상 처리를 시작했으면 true.
	if not p["jailed"]:
		today["ends"][p["id"]] = p["pos"]
	var ids := []
	for id in mission_row + op_row:
		var cond := card_cond(id)
		var st: Dictionary = mission_state.get(id, {})
		match str(cond.get("kind", "")):
			"contact":
				if int(st.get("holder", -1)) == p["id"] and police.has(p["id"]):
					st["chased"] = true
			"lurk":
				if _lurk_count(p, id, cond, st):
					ids.append(id)
			"people":
				var n := 0
				for pid in today["ends"]:
					if not players[pid]["jailed"] and _where_match(today["ends"][pid], cond):
						n += 1
				if n >= int(cond.get("count", 2)):
					ids.append(id)
			"opposite_edges":
				if _opposite_edges():
					ids.append(id)
	if ids.is_empty():
		return false
	_complete_missions(p, ids, {"then": "after_turn", "source": "mission"})
	return true


func _opposite_edges() -> bool:
	## 오늘 두 명이 보드의 서로 반대쪽 가장자리에서 차례를 마쳤는가
	var last := data.size - 1
	var ends: Dictionary = today["ends"]
	for a in ends:
		for b in ends:
			if a == b or players[a]["jailed"] or players[b]["jailed"]:
				continue
			var ca: Vector2i = ends[a]
			var cb: Vector2i = ends[b]
			if (ca.x == 0 and cb.x == last) or (ca.y == 0 and cb.y == last):
				return true
	return false
