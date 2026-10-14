class_name RulesSagaV2
extends RulesMissionsV2
## 규칙 엔진 4층: 결행 순간 · 개인 사연.


# ================================================================ 결행

func _launch(reason: String, target := "", tied: Array = []) -> void:
	## 결행 선언. target이 정해져 있으면 그곳, 아니면 후보(tied, 없으면 첩보가 가장 많은 거점) 중에서 정한다.
	## 후보가 여럿이면 그날의 리더가 고른다.
	launch_info = {"reason": reason, "day": day, "rounds_left": rounds_left, "ready": ready,
		"exposure": exposure, "alert": alert_level(), "intel": intel.duplicate(), "target": "",
		"benefits": [], "benefit_left": maxi(0, ready - int(data.rules["launch_min"]))}
	_record("결행 선언 (%s)" % {"vote": "투표", "forced": "작전일 임박"}.get(reason, reason), "good")
	if target != "":
		_finish_launch(target)
		return
	var cands: Array = tied if not tied.is_empty() else launch_target_preview()
	if cands.size() == 1:
		_finish_launch(cands[0])
		return
	var opts := []
	for id in cands:
		opts.append({"value": id, "label": data.base_names[data.base_index(id)]})
	_ask(players[leader], "strike_target", "표가 같은 거점이 여럿입니다. 리더가 결행할 곳을 고릅니다.", opts, {})


func _finish_launch(base_id: String) -> void:
	## 목표가 정해지면 결행 순간의 처리(사연 → 결행 혜택 → 사연 남기기)를 한다.
	launch_info["target"] = base_id
	launch_step = 1
	launch_i = 0
	_launch_continue()


# ================================================================ 3단계: 개인 사연

func _next_voter(after: int) -> int:
	return after + 1 if after + 1 < players.size() else -1


func _pile_names() -> Array:
	var out := []
	for k in data.sagas.get("piles", {}):
		if not str(k).begins_with("_"):
			out.append(k)
	return out


func _setup_saga_decks() -> void:
	saga_decks = {}
	saga_discard = []
	var piles: Dictionary = data.sagas.get("piles", {})
	for name in _pile_names():
		var deck := []
		for c in data.sagas.get("sagas", []):
			if c.get("branch", "") in piles[name]:
				deck.append(c["id"])
		_shuffle(deck)
		saga_decks[name] = deck


func _draw_saga(pile: String, p: Dictionary) -> String:
	## 더미 맨 위 한 장. redraw_for에 내 캐릭터가 있으면 뺀 카드를 더미 맨 아래로 보내고 다시 받는다.
	var deck: Array = saga_decks.get(pile, [])
	var skipped := 0
	while not deck.is_empty():
		var id: String = deck.pop_back()
		if p["character"] in data.saga(id).get("redraw_for", []) and skipped < deck.size():
			deck.insert(0, id)
			skipped += 1
			continue
		return id
	return ""


func _deal_sagas() -> void:
	var per := int(data.rules["saga"]["deal_per_pile"])
	for p in players:
		var got := []
		for pile in _pile_names():
			for k in per:
				var id := _draw_saga(pile, p)
				if id != "":
					p["sagas"].append(id)
					got.append(id)
		_push({"kind": "saga_dealt", "player": p["id"], "sagas": got.duplicate(), "secret": true})


# ---------------------------------------------------------------- 조회 (6절)

func saga_cards(pid: int) -> Array:
	## 본인: 들고 있는 사연
	return players[pid]["sagas"].duplicate()


func public_saga(pid: int) -> String:
	## 공개: 이룬 사연. 없으면 ""
	return players[pid]["saga_done"]


func _kept_or_first(p: Dictionary) -> String:
	if p["saga_kept"] != "":
		return p["saga_kept"]
	return p["sagas"][0] if not p["sagas"].is_empty() else ""


func saga_progress(pid: int) -> Dictionary:
	## 본인: {사연 id: {"have": n, "need": m}}. 결행 갈래는 0/1
	var p: Dictionary = players[pid]
	var out := {}
	for id in p["sagas"]:
		var cond := _saga_cond(id)
		var tr: Dictionary = p["saga_track"].get(id, {})
		var need := 1
		var have := 0
		match str(cond.get("kind", "")):
			"visit_base_adjacent":
				need = int(cond.get("count", 1))
				have = tr.get("bases", []).size()
			"touch_edge", "end_turn_at_start", "rolled_value", "give_dice", "shake_police", "pass_checkpoint", \
					"chased_turns_row", "coop_missions", "work_give", "escapes", "jailed", "visit_jailed":
				need = int(cond.get("count", 1))
				have = int(tr.get("n", 0))
			"visit_tile":
				need = int(cond.get("count", 1))
				have = tr.get("cells", []).size()
			"hold_items":
				need = int(cond.get("count", 1))
				have = mini(p["items"].size(), need)
			"same_cell_allies":
				need = int(cond.get("count", 1))
				have = tr.get("allies", []).size()
			"same_cell_turns":
				need = int(cond.get("count", 1))
				for k in tr.get("with", {}):
					have = maxi(have, int(tr["with"][k]))
			"never_jailed_until_launch":
				have = 1 if p["jail_count"] == 0 and int(p["stats"].get("shakes", 0)) >= int(cond.get("shaken", 0)) else 0
		if p["saga_done"] == id:
			have = need
		out[id] = {"have": mini(have, need), "need": need}
	return out


func saga_result(pid: int) -> Dictionary:
	## 판 끝 조회 (4단계 엔딩): 남긴 사연(없으면 들고 있던 첫 장), 이뤘는가
	var p: Dictionary = players[pid]
	return {"saga": _kept_or_first(p), "done": p["saga_done"] != ""}


func epilogue_key(pid: int, team_won: bool) -> String:
	## 후일담 키: win_done / win_fail / lose_done / lose_fail
	var p: Dictionary = players[pid]
	return "%s_%s" % ["win" if team_won else "lose", "done" if p["saga_done"] != "" else "fail"]


# ---------------------------------------------------------------- 사연 조건 세기 (2절)

func _saga_cond(id: String) -> Dictionary:
	var c = data.saga(id).get("condition", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}


func _saga_conds(id: String) -> Array:
	## 사연의 조건 하나, 그리고 「또는」(or)으로 이어 붙인 조건
	var c := _saga_cond(id)
	var out := [c]
	if typeof(c.get("or", null)) == TYPE_DICTIONARY:
		out.append(c["or"])
	return out


func _saga_check_at(id: String) -> String:
	## hold_items를 언제 세는가: 사연 카드의 check_at ("launch"면 결행 순간에만), 없으면 아이템을 얻는 즉시
	return str(data.saga(id).get("check_at", _saga_cond(id).get("check_at", "")))


func _saga_track(p: Dictionary, id: String) -> Dictionary:
	if not p["saga_track"].has(id):
		p["saga_track"][id] = {}
	return p["saga_track"][id]


func _bump(tr: Dictionary, key := "n", by := 1) -> int:
	tr[key] = int(tr.get(key, 0)) + by
	return tr[key]


func _saga_reset(p: Dictionary, kind: String) -> void:
	for id in p["sagas"]:
		if str(_saga_cond(id).get("kind", "")) == kind:
			_saga_track(p, id)["n"] = 0


func _saga_note(p: Dictionary, kind: String, ctx := {}) -> void:
	## 사연 조건을 세는 한 곳. 사연 id는 보지 않고 condition.kind만 본다.
	_saga_note_multi(p, [kind], ctx)


func _saga_note_multi(p: Dictionary, kinds: Array, ctx: Dictionary) -> void:
	## 들고 있는 순서대로 세고, 이룬 카드가 나오면 거기서 멈춘다 (두 장이 동시에 이뤄지면 앞 카드만)
	if p["saga_done"] != "":
		return
	for id in p["sagas"]:
		for cond in _saga_conds(id):
			if not str(cond.get("kind", "")) in kinds:
				continue
			if _saga_count(p, id, cond, ctx):
				_saga_complete(p, id)
				return


func _saga_count(p: Dictionary, id: String, cond: Dictionary, ctx: Dictionary) -> bool:
	## 이 사건을 세어 조건이 채워졌으면 true
	var tr := _saga_track(p, id)
	var count := int(cond.get("count", 1))
	match str(cond.get("kind", "")):
		"mission_done_by_me":
			return str(ctx.get("id", "")) == str(cond.get("mission", ""))
		"mission_kind_by_me":
			return str(ctx.get("mission_kind", "")) == str(cond.get("mission_kind", ""))
		"same_cell_allies":
			var allies: Array = tr.get("allies", [])
			if not int(ctx["with"]) in allies:
				allies.append(int(ctx["with"]))
			tr["allies"] = allies
			return allies.size() >= count
		"end_turn_near_base":
			if walk_dist(p["pos"], _base_cell(str(cond.get("base", "")))) > int(cond.get("range", 0)):
				return false
			return not (bool(cond.get("not_chased", false)) and police.has(p["id"]))
		"visit_base_adjacent":
			var bases: Array = tr.get("bases", [])
			for i in data.bases.size():
				if _manhattan(ctx["cell"], data.bases[i]) == 1 and not i in bases:
					bases.append(i)
			tr["bases"] = bases
			return bases.size() >= count
		"touch_edge":
			var c: Vector2i = ctx["cell"]
			var last := data.size - 1
			if not (c.x == 0 or c.y == 0 or c.x == last or c.y == last):
				return false
			if int(tr.get("turn", -1)) == p["turns"]:
				return false   # 한 차례에 여러 칸을 밟아도 1번
			tr["turn"] = p["turns"]
			return _bump(tr) >= count
		"end_turn_at_start":
			return p["pos"] == data.start and _bump(tr) >= count
		"visit_tile":
			if tile_type(ctx["cell"]) != str(cond.get("tile", "")):
				return false
			var cells: Array = tr.get("cells", [])
			if not ctx["cell"] in cells:
				cells.append(ctx["cell"])
			tr["cells"] = cells
			return cells.size() >= count
		"hold_items":
			if (_saga_check_at(id) == "launch") != bool(ctx.get("launch", false)):
				return false
			return p["items"].size() >= count
		"rolled_value":
			return int(cond.get("value", 6)) in ctx["values"] and _bump(tr) >= count
		"give_dice":
			return _bump(tr) >= count
		"shake_police", "pass_checkpoint", "coop_missions", "work_give", "escapes", "jailed", "visit_jailed":
			return _bump(tr) >= count
		"never_jailed_until_launch":
			return bool(ctx.get("launch", false)) and p["jail_count"] == 0 and int(p["stats"].get("shakes", 0)) >= int(cond.get("shaken", 0))
		"chased_turns_row":
			if not bool(ctx["chased"]):
				if bool(cond.get("row", true)):   # row가 false면 연달아가 아니어도 센다
					tr["n"] = 0
				return false
			return _bump(tr) >= count
		"same_cell_turns":
			var w: Dictionary = tr.get("with", {})
			var k := int(ctx["with"])
			w[k] = int(w.get(k, 0)) + 1
			tr["with"] = w
			if w[k] >= count:
				tr["partner"] = k
				return true
			return false
	return false


func _saga_turn_end(p: Dictionary) -> void:
	## 차례를 마칠 때 세는 조건. 갇힌 채 끝낸 차례는 세지 않고, 쫓기는 연속은 끊는다.
	if p["saga_done"] != "":
		return
	if p["jailed"]:
		_saga_reset(p, "chased_turns_row")
		return
	_saga_note_multi(p, ["end_turn_near_base", "end_turn_at_start", "chased_turns_row"],
		{"chased": police.has(p["id"])})
	for q in players:
		if q["id"] != p["id"] and not q["jailed"] and q["pos"] == p["pos"]:
			_saga_note_multi(p, ["same_cell_turns", "same_cell_allies"], {"with": q["id"]})
	for q in players:
		if q["id"] != p["id"] and q["jailed"] and _manhattan(q["pos"], p["pos"]) <= 1:
			_saga_note(p, "visit_jailed")   # 갇힌 동료의 감옥 안이나 옆 칸에서 차례를 마침 (면회)
			break


func _saga_step_on(p: Dictionary, cell: Vector2i) -> void:
	## 칸을 밟았다 (이동 중 지나가기만 해도, 순간이동도)
	_saga_note_multi(p, ["visit_base_adjacent", "touch_edge", "visit_tile"], {"cell": cell})


func _coop_participants(id: String, p: Dictionary, ctx: Dictionary) -> Array:
	## 협동 미션을 이룰 때 그 조건을 채운 요원 (협동 미션이 아니면 [])
	var cond := _coop_cond(id)
	var out := []
	match str(cond.get("kind", "")):
		"cover_entry":
			out.append(p["id"])
			var bi := int(ctx.get("entered_base", -1))
			if bi >= 0:
				for q in players:
					if q["id"] != p["id"] and not q["jailed"] \
							and _manhattan(q["pos"], data.bases[bi]) == 1:
						out.append(q["id"])
		"people":
			for pid in today["ends"]:
				if not players[pid]["jailed"] and _where_match(today["ends"][pid], cond):
					out.append(pid)
		"opposite_edges":
			var last := data.size - 1
			var ends: Dictionary = today["ends"]
			for a in ends:
				for b in ends:
					if a == b or players[a]["jailed"] or players[b]["jailed"]:
						continue
					var ca: Vector2i = ends[a]
					var cb: Vector2i = ends[b]
					if (ca.x == 0 and cb.x == last) or (ca.y == 0 and cb.y == last):
						for x in [a, b]:
							if not x in out:
								out.append(x)
	return out


# ---------------------------------------------------------------- 이룸 · 보상 (2-3)

func _saga_complete(p: Dictionary, id: String) -> void:
	## 사연을 이룬다. 상태는 곧바로 바꾸고, 보상은 대기열에 넣어 안전한 자리에서 처리한다.
	if p["saga_done"] != "":
		return
	p["saga_done"] = id
	p["saga_kept"] = id
	for other in p["sagas"]:
		if other != id:
			saga_discard.append(other)
	p["sagas"] = [id]
	var sd: Dictionary = data.saga(id)
	_log("%s: 개인 사연 「%s」을(를) 이루었습니다! (%s)" % [p["name"], sd.get("name", id), sd.get("reward_text", "")])
	_record("%s — 사연 「%s」 달성" % [p["name"], sd.get("name", id)], "good")
	_banner("사연 「%s」 달성!" % sd.get("name", id), "good", p)
	_push({"kind": "saga_done", "player": p["id"], "id": id})
	saga_rewards.append({"player": p["id"], "id": id})


func _saga_flush(next: Dictionary) -> bool:
	## 대기 중인 보상을 하나 시작한다. 시작했으면 true (보상이 끝난 뒤 _continue의 "saga"가 남은 보상을 이어 처리하고
	## 마지막에 next로 이어 간다). 보상이 없으면 false: 부른 쪽이 직접 이어 간다.
	while not saga_rewards.is_empty():
		var r: Dictionary = saga_rewards.pop_front()
		var reward: Array = data.saga(r["id"]).get("reward", [])
		if reward.is_empty():
			continue
		_run_effects(players[int(r["player"])], reward,
			{"then": "saga", "source": "saga", "saga": r["id"], "next": next})
		return true
	return false


func _saga_idle_flush() -> void:
	## 액션 하나를 마친 뒤 (판이 입력을 기다리는 자리): 쌓인 보상을 처리한다. 선택이 열려 있으면 그 선택이 끝난 뒤.
	if saga_rewards.is_empty() or phase in ["choice", "over", "morning"]:
		return
	_saga_flush({"then": "resume"})


func saga_strike_event(kind: String, by_pid: int, ctx: Dictionary) -> void:
	## 4단계 훅: 결행 장면을 돌파했다. kind: "entry" | "final" | "middle", ctx: {"strike", "present": [요원 id]}
	for p in players:
		if p["saga_done"] != "":
			continue
		var hit := false
		for id in p["sagas"]:
			for cond in _saga_conds(id):
				match str(cond.get("kind", "")):
					"strike_entry_by_me":
						hit = hit or (kind == "entry" and by_pid == p["id"])
					"present_at_entry":
						hit = hit or (kind == "entry" and not p["jailed"] and _manhattan(p["pos"], _base_cell(str(ctx.get("strike", "")))) <= 1)
					"strike_final_by_me":
						hit = hit or (kind == "final" and by_pid == p["id"] \
							and (str(cond.get("strike", "")) == "" or str(ctx.get("strike", "")) == str(cond["strike"])))
			if hit:
				_saga_complete(p, id)
				break
	_saga_idle_flush()


func _saga_final_reveal() -> void:
	## 마지막 장면이 펼쳐질 때 결행 거점 안에 있던 요원의 사연 (present_at_final)
	var base := _base_cell(str(launch_info.get("target", "")))
	for p in players:
		if p["saga_done"] != "" or p["jailed"] or p["pos"] != base:
			continue
		var hit := false
		for id in p["sagas"]:
			for cond in _saga_conds(id):
				hit = hit or str(cond.get("kind", "")) == "present_at_final"
			if hit:
				_saga_complete(p, id)
				break


# ---------------------------------------------------------------- 결행 순간 (4절)

func _launch_continue() -> void:
	## 결행 순간의 순서: 결행 때 세는 조건 → 결행 혜택 고르기 → 사연 남기기 → 2막. 선택이 끼면 멈췄다 이어 간다.
	while launch_step < 4 and phase != "over":
		match launch_step:
			1:
				launch_step = 2
				for q in players:
					_saga_note_multi(q, ["never_jailed_until_launch", "hold_items"], {"launch": true})
				if _saga_flush({"then": "launch"}):
					return
			2:
				if _launch_benefit_next():
					return
				launch_step = 3
				launch_i = 0
			3:
				if _launch_keep_next():
					return
				launch_step = 4
	if launch_step >= 4 and phase != "over":
		_begin_act2()


func _launch_benefit_next() -> bool:
	## 준비가 launch_min을 넘은 점수마다 혜택 하나 (같은 것은 한 번만). 선택을 물었으면 true.
	if int(launch_info.get("benefit_left", 0)) <= 0:
		return false
	var avail := benefits_left()
	if avail.is_empty():
		return false
	var opts := []
	for b in avail:
		opts.append({"value": str(b["id"]), "label": "%s — %s" % [b.get("name", ""), b.get("text", "")]})
	var who: Dictionary = players[benefit_chooser()]
	_ask(who, "launch_benefit", "결행 혜택을 고릅니다 (%d개 남음, 같은 것은 한 번만)." % int(launch_info["benefit_left"]), opts, {"then": "launch"})
	return true


func _take_benefit(id: String) -> void:
	launch_info["benefits"].append(id)
	launch_info["benefit_left"] = int(launch_info["benefit_left"]) - 1
	var name := id
	for b in data.rules["launch"]["benefits"]:
		if str(b["id"]) == id:
			name = str(b.get("name", id))
	_log("결행 혜택: %s" % name)
	_push({"kind": "benefit", "id": id})


func _benefit_effects() -> Array:
	var out := []
	for id in launch_info.get("benefits", []):
		for b in data.rules["launch"]["benefits"]:
			if str(b["id"]) == str(id):
				out.append_array(b.get("effects", []))
	return out


func saga_feasible(p: Dictionary, id: String) -> bool:
	## 결행 뒤에도 이룰 수 있는 사연인가 (데이터의 kind로만 판정, 「또는」 조건 중 하나라도 되면 됨)
	for cond in _saga_conds(id):
		if _saga_cond_feasible(p, id, cond):
			return true
	return false


func _saga_cond_feasible(p: Dictionary, id: String, cond: Dictionary) -> bool:
	match str(cond.get("kind", "")):
		"mission_done_by_me", "mission_kind_by_me":
			return act == 1
		"strike_entry_by_me", "present_at_entry":
			return act == 1 or scene_index == 0
		"never_jailed_until_launch":
			return false   # 결행 순간에만 세는 조건은 그 순간이 지나면 못 이룬다
		"hold_items":
			return _saga_check_at(id) != "launch"
		"strike_final_by_me":
			var s := str(cond.get("strike", ""))
			return s == "" or s == str(launch_info.get("target", ""))
		"visit_tile":
			var tile := str(cond.get("tile", ""))
			var seen: Array = p["saga_track"].get(id, {}).get("cells", [])
			var left := tile_deck.count(tile)
			for c in board:
				if board[c]["type"] == tile and not c in seen:
					left += 1
			return seen.size() + left >= int(cond.get("count", 1))
	return true


func _launch_keep_next() -> bool:
	## 결행의 날 가슴에 품고 갈 사연을 요원 번호순으로 정한다. 선택을 물었으면 true.
	while launch_i < players.size():
		var q: Dictionary = players[launch_i]
		launch_i += 1
		if q["saga_done"] != "":
			continue
		var cands := []
		for id in q["sagas"]:
			if saga_feasible(q, id):
				cands.append(id)
		if cands.size() >= 2:
			var opts := []
			for id in cands:
				opts.append({"value": id, "label": data.saga(id).get("name", id)})
			_ask(q, "saga_keep", "결행의 날입니다. 어느 사연을 품고 가시겠습니까? (이룰 수 있는 사연만 고를 수 있습니다)", opts, {})
			pending["secret"] = true
			return true
		if cands.size() == 1:
			_keep_saga(q, cands[0])
		else:
			_redraw_feasible_saga(q)
	return false


func _keep_saga(q: Dictionary, id: String) -> void:
	for other in q["sagas"]:
		if other != id:
			saga_discard.append(other)
	q["sagas"] = [id]
	q["saga_kept"] = id
	_log("%s: 결행을 앞두고 사연을 품었습니다." % q["name"])
	_push({"kind": "saga_kept", "player": q["id"], "id": id, "secret": true})


func _redraw_feasible_saga(q: Dictionary) -> void:
	## 이룰 수 있는 카드가 없으면 두 더미에서 이룰 수 있는 카드가 나올 때까지 뽑아 1장을 자동으로 남긴다 (나온 다른 카드는 버림)
	saga_discard.append_array(q["sagas"])
	q["sagas"] = []
	var names := _pile_names()
	var guard := 0
	while guard < 100:
		guard += 1
		var any := false
		for pile in names:
			var deck: Array = saga_decks.get(pile, [])
			if deck.is_empty():
				continue
			any = true
			var id: String = deck.pop_back()
			if saga_feasible(q, id):
				q["sagas"] = [id]
				_keep_saga(q, id)
				return
			saga_discard.append(id)
		if not any:
			break
	_log("%s: 품을 사연이 남지 않았습니다." % q["name"])


func _begin_act2() -> void:
	## 결행 혜택의 선택이 끼는 동안에는 아직 1막 상태(act 1)이고, 장면을 깔 때 act를 2로 바꾼다 (_act2_scenes)
	var target := str(launch_info["target"])
	threat_deck = data.threat_deck(2)
	var extra := _trend_reinforce()
	launch_info["trend"] = trend
	launch_info["reinforce"] = extra
	if extra > 0:
		for card in data.threats.get("act2", []):
			if bool(card.get("trend_extra", false)):
				for i in extra:
					threat_deck.append(card["id"])
				break
		_log("일제 동향 %d — 2막 위협 덱에 증원 %d장을 더 섞습니다." % [trend, extra])
	threat_discard = []
	_shuffle(threat_deck)
	var priority := []
	for id in threat_deck:
		if data.threat(id).get("deck_place", "") == "top_half":
			priority.append(id)
	for id in priority:
		threat_deck.erase(id)
		var lower := (threat_deck.size() + priority.size()) / 2
		threat_deck.insert(rng.randi_range(lower, threat_deck.size()), id)
	mission_row = []
	mission_deck = []
	mission_discard = []
	markers = []
	mission_state = {}
	op_row = []
	expire_queue = []
	intel_tokens = int(intel.get(target, 0))
	launch_info["no_reinforce"] = false
	_log("결행! 목표: %s" % base_name(data.base_index(target)))
	_record("결행: %s" % base_name(data.base_index(target)), "good")
	_banner("결행!", "good")
	_push({"kind": "launch", "reason": launch_info.get("reason", ""), "target": target})
	# 결행 혜택의 효과 (경비 강화 빼기·첩보 토큰·주사위·위협 덱 보기)를 먼저 적용한 뒤 장면을 깐다
	var wait_fx := []
	for w in bonus_wait:
		if str(w["base"]) == target:
			for re in w["reward"]:
				var one: Dictionary = re.duplicate(true)
				if str(one.get("op", "")) == "grant_once":
					one["who"] = "player"
					one["pid"] = int(w["player"])
				wait_fx.append(one)
	bonus_wait = []
	_run_effects(players[leader], wait_fx + _benefit_effects(), {"then": "act2_scenes", "source": "launch"})


func _act2_scenes() -> void:
	act = 2
	var target := str(launch_info["target"])
	var strike: Dictionary = data.strike(target)
	var middle: Array = strike.get("middle", []).duplicate()
	_shuffle(middle)
	scenes = [strike["entry"]["id"]]
	for i in mini(int(data.rules["scenes"]["middle_draw"]), middle.size()):
		scenes.append(middle[i]["id"])
	var reinforce: Array = data.scenes.get("reinforce", []).duplicate()
	_shuffle(reinforce)
	var n := int(data.rules["scenes"]["reinforce_by_alert"].get(str(alert_level()), 0))
	if bool(launch_info.get("no_reinforce", false)):
		n = 0
	for i in mini(n, reinforce.size()):
		scenes.insert(rng.randi_range(1, scenes.size()), reinforce[i]["id"])
	scenes.append(strike["final"]["id"])
	scene_index = 0
	scene_state = {}
	counter = {}
	_scene_reveal()
	_run_effects(players[leader], strike.get("on_launch", []), {"then": "morning", "source": "launch"})
