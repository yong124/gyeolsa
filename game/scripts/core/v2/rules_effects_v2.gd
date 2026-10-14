class_name RulesEffectsV2
extends RulesBaseV2
## 규칙 엔진 2층: 효과 해석기 · 선택 응답 · 아이템 · 능력 · 경찰 · 감옥 · 노출 · 탈옥.


# ================================================================ 탈옥

func _begin_escape(p: Dictionary, die: int) -> void:
	_log("%s: 탈옥을 시도합니다." % p["name"])
	_start_check(p, "escape", "escape", {"die_i": die})


# ================================================================ 경찰 · 감옥 · 노출

func _summon(p: Dictionary, here := false) -> void:
	## 경찰이 이 요원에게 붙는다 (붙은 다음 차례부터 움직임). 새 경찰은 그 요원에게서 가장 가까운 거점에 나타나고
	## (거점이 spawn_min_distance칸보다 가까우면 그만큼 떨어진 칸, police_spawn_cell)
	## (here이면 그 자리), 이미 쫓기는 요원에게 또 붙으면 새 말을 놓지 않고 쫓던 경찰이 2칸 떨어진 곳으로 옮겨 온다.
	if p["jailed"]:
		return
	if _block_police(p):
		return
	if police.has(p["id"]):
		police[p["id"]] = {"pos": _near_cell(p["pos"], police[p["id"]]["pos"], int(data.rules["police"]["rejoin_distance"])),
			"summon_turn": p["turns"]}
		_log("%s: 쫓던 경찰이 가까이 다시 자리를 잡았습니다." % p["name"])
	elif police.size() < int(data.rules["police"]["pieces"]):
		var at: Vector2i = p["pos"] if here else police_spawn_cell(p["pos"])
		police[p["id"]] = {"pos": at, "summon_turn": p["turns"]}
		_log("%s: 경찰이 붙었습니다!" % p["name"])
	_push({"kind": "police"})


func police_spawn_cell(pos: Vector2i) -> Vector2i:
	## 새 경찰이 나타날 칸: 가장 가까운 거점. 다만 그 거점이 요원과 spawn_min_distance칸보다 가까우면
	## (거점 안이나 거점 곁) 요원에게서 그만큼 떨어진, 그 거점 쪽 칸에 나타난다 (들어가자마자 잡히지 않게)
	var base: Vector2i = data.bases[_nearest_base(pos)]
	var min_d := int(data.rules["police"].get("spawn_min_distance", 0))
	if min_d <= 0 or walk_dist(pos, base) >= min_d:
		return base
	return _near_cell(pos, base, min_d)


func _near_cell(center: Vector2i, toward: Vector2i, dist: int) -> Vector2i:
	## center에서 깔린 칸을 따라 dist칸 떨어진 칸 중 toward에 가장 가까운 칸 (없으면 더 가까운 칸, 그래도 없으면 center)
	var d: Dictionary = _dist_from(center)
	for want in range(dist, -1, -1):
		var best := center
		var best_d := 99999
		var found := false
		for c in d:
			if int(d[c]) != want or police_on(c):
				continue
			var k := walk_dist(c, toward)
			if k < best_d or (k == best_d and (c.x < best.x or (c.x == best.x and c.y < best.y))):
				best = c
				best_d = k
				found = true
		if found:
			return best
	return center


func _block_police(p: Dictionary) -> bool:
	## block_police_with_evade: 내게 경찰이 붙을 때 회피 판정을 해서 성공하면 붙지 않는다.
	## (곧바로 끝나는 판정: 다시 굴리기 선택은 없고, 타고난 회피 자동 성공·회피 보정은 따른다)
	if not flag(p, "block_police_with_evade"):
		return false
	var ok := false
	if flag(p, "evade_auto"):
		ok = true
	else:
		var r := _d2()
		var bonus := stat(p, "evade_bonus")
		var target := check_target("evade")
		ok = r + bonus >= target
		_push({"kind": "dice", "what": "회피", "dice": last_roll.duplicate(), "bonus": bonus, "target": target,
			"player": p["id"], "ok": ok})
		_log("%s: 경찰을 따돌리려 회피 판정 %d%s (목표 %d) → %s" % [p["name"], r,
			(" %+d" % bonus) if bonus != 0 else "", target, "성공" if ok else "실패"])
	if ok:
		_log("%s: 경찰이 붙는 것을 막았습니다." % p["name"])
		_banner("경찰을 따돌렸다", "good", p)
	return ok


func _jail(p: Dictionary) -> void:
	var best: Vector2i = data.bases[_nearest_base(p["pos"])]
	var from: Vector2i = p["pos"]
	p["pos"] = best
	p["jailed"] = true
	p["jail_count"] += 1
	p["stats"]["jailed"] += 1
	_police_off(p["id"], "jail")
	_saga_note(p, "jailed")
	_drop_contacts(p)
	_saga_reset(p, "chased_turns_row")
	var name := base_name(data.bases.find(best))
	_record("%s — %s 감옥에 투옥" % [p["name"], name], "bad")
	_banner("%s 투옥!" % p["name"], "bad", p)
	_log("%s: %s 감옥에 투옥되었습니다!" % [p["name"], name])
	_push({"kind": "jail", "player": p["id"], "from": from, "to": best})
	_expose(int(data.rules["exposure"]["on_jail"]))
	_on_jailed(p)
	if act == 2 and phase != "over":
		_scene_auto_break()


func _on_jailed(p: Dictionary) -> void:
	## 투옥되면 갇힌 날과 풀려날 날을 적고, 들고 있던 아이템을 압수당한다(rules.jail.confiscate_items, 폭탄은 압수하지 않는다).
	## 풀려날 날 (rules.jail.release_next_morning): 낮에 갇히면 다음 날 아침, 밤에 갇히면 그다음 날 아침. 갇힌 날의 남은 차례만 잃는다
	p["jailed_day"] = day
	p["release_day"] = day + (2 if bool(today.get("night", false)) else 1)
	_confiscate(p, int(data.rules["jail"]["confiscate_items"]))


func release_day(p: Dictionary) -> int:
	## 갇힌 요원이 아침에 풀려나는 날 (B단계 이전 저장에는 없으니 갇힌 다음 날)
	return int(p.get("release_day", int(p.get("jailed_day", day)) + 1))


func _release(p: Dictionary) -> void:
	## 아침 석방: 갇힌 거점에서 그대로 나온다. 탈옥과 달리 경찰이 붙지 않는다
	p["jailed"] = false
	p["flags"]["escape_add"] = 0
	_record("%s — 석방" % p["name"], "info")
	_log("%s: 아침이 되어 감옥에서 풀려났습니다 (경찰은 붙지 않음)." % p["name"])
	_push({"kind": "free", "player": p["id"]})


func _confiscate(p: Dictionary, n: int) -> void:
	## 아이템을 무작위로 n장 빼앗아 버림 더미로 보낸다 (없으면 아무 일도 없음)
	var taken := []
	for k in n:
		if p["items"].is_empty():
			break
		var id: String = p["items"].pop_at(rng.randi_range(0, p["items"].size() - 1))
		item_discard.append(id)
		taken.append(id)
		_log("%s: 아이템 [%s]을(를) 압수당했습니다." % [p["name"], item_def(id)["name"]])
	if not taken.is_empty():
		_push({"kind": "confiscate", "player": p["id"], "items": taken.duplicate()})


func _police_act(p: Dictionary) -> void:
	if not police_active(p["id"]) or p["jailed"]:
		return
	_police_approach(p, police_speed())


func _police_approach(p: Dictionary, sp: int) -> void:
	## 이 요원을 쫓는 경찰이 sp칸 다가온다 (따라잡으면 체포, 너무 멀면 따돌림)
	if not police.has(p["id"]) or p["jailed"]:
		return
	var pol: Dictionary = police[p["id"]]
	var path = tile_path(pol["pos"], p["pos"])
	if path == null:
		_police_off(p["id"], "shake")
		_push({"kind": "police"})
		return
	if path.size() <= sp:
		pol["pos"] = p["pos"]
		_log("%s: 경찰에게 체포되었습니다!" % p["name"])
		_push({"kind": "catch", "player": p["id"]})
		_jail(p)
		return
	pol["pos"] = path[sp - 1]
	_push({"kind": "police"})
	if path.size() - sp > int(data.rules["police"]["escape_distance"]):
		_police_off(p["id"], "shake")
		_log("%s: 경찰을 따돌렸습니다." % p["name"])
		_push({"kind": "police"})


func _expose(n: int) -> void:
	if n == 0:
		return
	var before := alert_level()
	exposure = clampi(exposure + n, 0, int(data.rules["exposure"]["max"]))
	stats["max_exposure"] = maxi(int(stats.get("max_exposure", 0)), exposure)
	_push({"kind": "exposure", "value": exposure})
	var after := alert_level()
	if after > before:
		_log("노출 %d — 경계가 %d단계로 올랐습니다!" % [exposure, after])
		_banner("경계 %d단계" % after, "warn")
		_push({"kind": "alert", "level": after})
		for k in after - before:
			_dispatch_from(rng.randi_range(0, data.bases.size() - 1))


func _nearest_base(c: Vector2i) -> int:
	var best := 0
	var bd := 999999
	for i in data.bases.size():
		var d := walk_dist(c, data.bases[i])
		if d < bd:
			bd = d
			best = i
	return best


func _dispatch_from(bi: int) -> void:
	## 거점 bi에서 경찰이 출동해, 아직 쫓기지 않는 가장 가까운 요원을 쫓는다
	var base: Vector2i = data.bases[bi]
	var best := {}
	for q in players:
		if q["jailed"] or police.has(q["id"]):
			continue
		if best.is_empty() or walk_dist(q["pos"], base) < walk_dist(best["pos"], base):
			best = q
	if not best.is_empty() and police.size() < int(data.rules["police"]["pieces"]):
		police[best["id"]] = {"pos": base, "summon_turn": best["turns"]}
		_log("%s에서 경찰이 출동해 %s을(를) 쫓습니다!" % [base_name(bi), best["name"]])
		_push({"kind": "police"})


# ================================================================ 아이템 · 능력 · 협력

func _draw_from(deck: Array, discard: Array) -> String:
	if deck.is_empty():
		deck.append_array(discard)
		discard.clear()
		_shuffle(deck)
	return deck.pop_back() if not deck.is_empty() else ""


func _take_item(p: Dictionary, id: String) -> bool:
	## 아이템 한 장을 손에 넣는다. 한도를 넘어 버릴 카드를 물었으면 true
	p["items"].append(id)
	_log("%s: 아이템 [%s] 획득" % [p["name"], item_def(id)["name"]])
	_push({"kind": "card", "deck": "item", "id": id, "player": p["id"]})
	_saga_note(p, "hold_items")   # 한도를 넘어 버릴 카드를 묻기 전에 센다
	if p["items"].size() > hand_limit(p):
		_ask_discard(p)
		return true
	return false


func _ask_discard(p: Dictionary) -> void:
	var opts := []
	for i in p["items"].size():
		opts.append({"value": i, "label": item_def(p["items"][i])["name"]})
	_ask(p, "discard", "아이템은 %d장까지 가질 수 있습니다. 버릴 카드를 고릅니다." % hand_limit(p), opts, {"then": "resume"})


func _use_item(p: Dictionary, idx: int) -> void:
	var id: String = p["items"][idx]
	var it: Dictionary = item_def(id)
	p["items"].remove_at(idx)
	item_discard.append(id)
	p["item_uses"] += 1
	p["stats"]["items"] += 1
	_log("%s: [%s] 사용" % [p["name"], it["name"]])
	_push({"kind": "item_used", "id": id, "player": p["id"]})
	_run_effects(p, it.get("effects", []), {"then": "resume", "source": "item", "item": id})


func _use_ability(p: Dictionary, target: int, die := -1) -> void:
	var a: Dictionary = ability_def(p)
	p["ability_day"] = day
	if die >= 0:
		_use_die(p, die, "ability")
	p["stats"]["abilities"] += 1
	_log("%s: 능력 「%s」 사용" % [p["name"], a.get("name", "")])
	_banner(str(a.get("name", "")), "info", p)
	_push({"kind": "ability", "player": p["id"]})
	_run_effects(p, a.get("effects", []), {"then": "resume", "source": "ability", "target": target})


func _hide(p: Dictionary, die: int) -> void:
	## 숨기: 이번 차례 끝에 나를 쫓는 경찰이 다가오지 않는다
	_use_die(p, die, "hide")
	p["hidden"] = true
	_log("%s: 몸을 숨겼습니다. 이번 차례 끝에 경찰이 다가오지 못합니다." % p["name"])
	_banner("숨기", "info", p)


# ================================================================ 효과 해석기

func _effect(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 효과 하나를 실행한다. 선택지를 띄워 멈췄으면 true.
	var op: String = str(e.get("op", ""))
	match op:
		"police_dispatch":
			_op_police_dispatch(p, e, ctx)
		"event_card":
			_op_event_card(p, queue)
		"police_back":
			_op_police_back(p, e)
		"threat_peek_bonus":
			peek_bonus += int(e.get("value", 1))
			_log("이번 판 동안 위협 카드를 %d장 더 미리 봅니다." % int(e.get("value", 1)))
		"police_attach":
			return _op_police_attach(p, e, queue)
		"exposure":
			_expose(int(e.get("value", 0)))
		"intel":
			return _op_intel(p, e, ctx)
		"ready":
			_add_ready(int(e.get("value", 0)))
		"draw_item":
			return _op_draw_item(p, e, queue)
		"gain_bomb":
			_op_gain_bomb(p, e)
		"choice":
			return _op_choice(p, e)
		"if":
			var cond_ok := _cond_holds(p, str(e.get("cond", "")))
			var branch: Array = e.get("then", []) if cond_ok else e.get("else", [])
			for i in range(branch.size() - 1, -1, -1):
				queue.push_front(branch[i])
		"if_players":
			var hit := false
			for n in e.get("players", []):
				if int(n) == players.size():
					hit = true
			var br: Array = e.get("then", []) if hit else e.get("else", [])
			for i in range(br.size() - 1, -1, -1):
				queue.push_front(br[i])
		"grant_once":
			return _op_grant_once(p, e, ctx, queue)
		"mark_tile":
			_op_mark_tile(p, e)
		"give_die":
			return _op_give_die(p, e, ctx, queue)
		"no_reinforce":
			launch_info["no_reinforce"] = true
			_log("경비 강화 장면이 들어가지 않습니다.")
		"intel_token_bonus":
			intel_tokens += int(e.get("value", 1))
			_log("첩보 토큰 %+d (토큰 %d)." % [int(e.get("value", 1)), intel_tokens])
		"threat_look_discard":
			return _op_threat_look(e)
		"scene_check_mod_today":
			today["scene_mod"] = int(today.get("scene_mod", 0)) + int(e.get("value", 0))
			_log("오늘 장면 판정 목표 %+d." % int(e.get("value", 0)))
		"refill_supply":
			bomb_supply = int(data.rules["bomb_supply"])
			_log("폭탄 보급을 다시 채웠습니다.")
		"police_advance":
			_op_police_advance(e)
		"police_remove":
			_op_police_remove(p, e)
		"police_push":
			_op_police_push(p, e)
		"police_send_far":
			_op_police_send_far(p)
		"checkpoint_place":
			return _op_checkpoint_place(p, e, ctx, queue)
		"dice_mod_today":
			today["dice_mod"] = int(today.get("dice_mod", 0)) + int(e.get("value", 0))
			_log("오늘 이동에 쓰는 주사위 %+d (최소 %d)." % [int(e.get("value", 0)), int(data.rules["min_die"])])
		"police_speed_today":
			today["police_speed"] = int(today.get("police_speed", 0)) + int(e.get("value", 0))
			_log("오늘 경찰 이동 %+d." % int(e.get("value", 0)))
		"escape_mod_today":
			today["escape_mod"] = int(today.get("escape_mod", 0)) + int(e.get("value", 0))
			_log("오늘 탈옥 판정 %+d." % int(e.get("value", 0)))
		"free_all_jailed":
			_op_free_all_jailed(p)
		"discard_item":
			return _op_discard_item(p, e, queue)
		"move_mod_next", "move_today":
			return _op_move(p, e, ctx, queue)
		"dice_extra_tomorrow", "fewer_dice_tomorrow":
			var ids = _resolve_who(p, e, ctx, queue, str(e.get("who", "self")))
			if ids == null:
				return true
			var dn := int(e.get("count", 1)) * (1 if e["op"] == "dice_extra_tomorrow" else -1)
			for id in ids:
				players[id]["dice_next"] = int(players[id]["dice_next"]) + dn
				_log("%s: 내일 아침 주사위 %+d개." % [players[id]["name"], dn])
		"die_reroll", "die_adjust", "die_set":
			return _op_die(p, e, queue)
		"threat_bury":
			return _op_threat_bury(p, e, queue)
		"place_tile":
			return _op_place_tile(p, e, queue)
		"extra_step":
			if p["id"] == current and phase == "turn":
				steps_left += int(e.get("steps", 1))
				_log("%s: %d칸 더 갈 수 있습니다." % [p["name"], int(e.get("steps", 1))])
		"move_to_ally":
			return _op_move_to_ally(p, e, ctx, queue)
		"pull_ally":
			return _op_pull_ally(p, e, ctx, queue)
		"give_item":
			return _op_transfer_item(p, e, ctx, queue, str(e.get("who", "ally_in_range")), false, bool(e.get("free", false)))
		"send_item":
			return _op_transfer_item(p, e, ctx, queue, "ally", true, true)
		"checkpoint_pass":
			p["flags"]["checkpoint_pass"] = int(p["flags"].get("checkpoint_pass", 0)) + int(e.get("count", 1))
			_log("%s: 이번 차례에 검문소 %d곳을 판정 없이 지나갈 수 있습니다." % [p["name"], int(e.get("count", 1))])
		"entry_no_police":
			p["flags"]["entry_no_police"] = true
			_log("%s: 이번 거점 진입에는 경찰이 붙지 않습니다." % p["name"])
		_:
			_log("(알 수 없는 효과) %s" % op)
	return false


func _cond_holds(p: Dictionary, cond: String) -> bool:
	match cond:
		"chased":
			return police.has(p["id"])
		"not_chased":
			return not police.has(p["id"])
	return false


# ---- 2a 효과들

func _op_police_dispatch(_p: Dictionary, e: Dictionary, ctx: Dictionary = {}) -> void:
	var count: int = int(e.get("count", 1))
	var from: String = str(e.get("from", "random_base"))
	var distinct: bool = bool(e.get("distinct", false))
	var used := []
	for k in count:
		var bi := -1
		if from == "random_base":
			var pool := []
			for i in data.bases.size():
				if not (distinct and i in used):
					pool.append(i)
			if pool.is_empty():
				return
			bi = pool[rng.randi_range(0, pool.size() - 1)]
		elif from == "strike_base":
			bi = data.base_index(str(launch_info.get("target", "")))
		elif from == "marker":
			bi = _nearest_base(ctx["cell"] if ctx.has("cell") else data.start)
		else:
			bi = data.base_index(from)
		if bi < 0:
			_log("경찰 출동 거점을 찾지 못했습니다: %s" % from)
			return
		used.append(bi)
		_dispatch_from(bi)


func _who_pick(p: Dictionary, who: String, e: Dictionary) -> Array:
	## 대상 요원 id 목록 (동점이면 여럿 — 호출한 쪽이 리더에게 묻는다)
	var include_jailed: bool = bool(e.get("include_jailed", false))
	match who:
		"self":
			return [p["id"]]
		"player":
			return [int(e["pid"])]
		"all":
			return players.filter(func(q): return not q["jailed"]).map(func(q): return q["id"])
		"everyone":
			return players.map(func(q): return q["id"])
		"allies":
			return players.filter(func(q): return q["id"] != p["id"]).map(func(q): return q["id"])
		"all_jailed":
			return players.filter(func(q): return q["jailed"]).map(func(q): return q["id"])
		"nearest_to_base":
			var bi := _resolve_base_ref(str(e.get("base", "strike_base")))
			if bi < 0:
				return []
			var near_d := 9999
			var near_ids := []
			for q in players:
				if (q["jailed"] and not include_jailed):
					continue
				var dd := walk_dist(q["pos"], data.bases[bi])
				if dd < near_d:
					near_d = dd
					near_ids = [q["id"]]
				elif dd == near_d:
					near_ids.append(q["id"])
			return near_ids
		"isolated":
			var best := -1
			var ids := []
			for q in players:
				if (q["jailed"] and not include_jailed):
					continue
				var near := 9999
				for r in players:
					if r["id"] != q["id"]:
						near = mini(near, walk_dist(q["pos"], r["pos"]))
				if near > best:
					best = near
					ids = [q["id"]]
				elif near == best:
					ids.append(q["id"])
			return ids
		"wanted":
			var most := -1
			var ids2 := []
			for q in players:
				if (q["jailed"] and not include_jailed):
					continue
				if q["jail_count"] > most:
					most = q["jail_count"]
					ids2 = [q["id"]]
				elif q["jail_count"] == most:
					ids2.append(q["id"])
			return ids2
	return []


func _op_police_attach(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	var ids = _resolve_who(p, e, {}, queue, str(e.get("who", "self")))
	if ids == null:
		return true
	for id in ids:
		_log("%s: 경찰이 나타나 쫓기 시작합니다!" % players[id]["name"])
		_summon(players[id], str(e.get("at", "")) == "here")
	return false


func _ask_leader_pick(e: Dictionary, ids: Array, queue: Array, who := "") -> bool:
	## 동점은 그날의 리더가 고른다. 고른 뒤 같은 효과를 그 요원으로(e["pid"]) 다시 처리한다.
	## 무엇을 고르는지(기준 · 받는 효과)를 함께 적는다 (처음 하는 사람이 맥락 없이 고르지 않게)
	var crit: String = _TIE_WHO.get(who, "대상")
	var what: String = _TIE_WHAT.get(str(e.get("op", "")), "고른 요원이 이 효과를 받습니다")
	var prompt := "%s이(가) 여럿입니다. 리더가 한 명을 고릅니다. %s." % [crit, what]
	return _ask_pick(players[leader], e, queue, "pid", "pick_player", prompt, _player_options(ids))


func _player_options(ids: Array) -> Array:
	var opts := []
	for id in ids:
		opts.append({"value": id, "label": players[id]["name"]})
	return opts


func _ask_pick(asker: Dictionary, e: Dictionary, queue: Array, key: String, kind: String, prompt: String,
		options: Array) -> bool:
	## 효과 e에 필요한 값(key)을 asker에게 묻는다. 고르면 e에 key를 채워 같은 효과를 다시 처리한다. 항상 true.
	queue.push_front(e.duplicate())
	_ask(asker, kind, prompt, options, {})
	pending["key"] = key
	return true


func _resolve_base_ref(ref: String) -> int:
	## "strike_base"(결행 거점) 또는 거점 id → 거점 번호 (없으면 -1)
	if ref == "strike_base":
		return data.base_index(str(launch_info.get("target", "")))
	return data.base_index(ref)


func _ally_candidates(p: Dictionary, who: String, e: Dictionary, include_jailed := false) -> Array:
	var out := []
	for q in players:
		if q["id"] == p["id"] or (q["jailed"] and not include_jailed):
			continue
		var d := walk_dist(q["pos"], p["pos"])
		match who:
			"ally":
				out.append(q["id"])
			"ally_same_cell":
				if d == 0:
					out.append(q["id"])
			"ally_adjacent":
				if d <= 1:
					out.append(q["id"])
			"ally_in_range":
				if d <= int(e.get("range", 1)):
					out.append(q["id"])
	return out


func _resolve_who(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array, who: String, include_jailed := false) -> Variant:
	## 효과의 대상 요원 id 목록. 고를 사람이 필요해 물었으면 null (호출한 효과는 true를 돌려주고 멈춘다).
	## - 동료 고르기(ally*): 능력이면 능력에서 고른 대상, 아니면 쓰는 사람이 고름
	## - 동점(isolated · wanted · nearest_to_base): 그날의 리더가 고름
	if e.has("pid"):
		return [int(e["pid"])]
	if who == "saga_partner":
		## 사연이 기억해 둔 동료 (같은 칸에서 세 번 마친 상대). 감옥에 있어도 받는다.
		var partner := int(p["saga_track"].get(str(ctx.get("saga", "")), {}).get("partner", -1))
		return [partner] if partner >= 0 and partner != p["id"] else []
	if who.begins_with("ally"):
		var t := int(ctx.get("target", -1))
		if ctx.get("source", "") == "ability" and t >= 0 and t < players.size():
			return [t]
		var cands := _ally_candidates(p, who, e, include_jailed)
		if cands.size() <= 1:
			return cands
		_ask_pick(p, e, queue, "pid", "pick_player", "대상 동료를 고릅니다.", _player_options(cands))
		return null
	var ids := _who_pick(p, who, e)
	if ids.size() > 1 and who in ["isolated", "wanted", "nearest_to_base"]:
		_ask_leader_pick(e, ids, queue, who)
		return null
	return ids


func _resolve_base(p: Dictionary, base, ctx: Dictionary) -> int:
	var b: String = str(base)
	if b == "entered" and ctx.has("entered_base"):
		return int(ctx["entered_base"])
	if b == "nearest" or b == "entered":
		return _nearest_base(p["pos"])
	if b == "highest":
		var top := -1
		for id in data.base_ids:
			top = maxi(top, int(intel[id]))
		var tops := []
		for id in data.base_ids:
			if int(intel[id]) == top:
				tops.append(id)
		return data.base_index(tops[0] if tops.size() == 1 else tops[rng.randi_range(0, tops.size() - 1)])
	return data.base_index(b)


func _op_intel(p: Dictionary, e: Dictionary, ctx: Dictionary) -> bool:
	var v: int = int(e.get("value", 1))
	if str(e.get("base", "nearest")) == "choose":
		var opts := []
		var near_ids := _bases_in_range(p["pos"], int(e["range"])) if e.has("range") else data.base_ids.duplicate()
		if near_ids.is_empty():
			return false
		if near_ids.size() == 1 and e.has("range"):
			_add_intel(data.base_index(str(near_ids[0])), v)
			return false
		for id in near_ids:
			opts.append({"value": id, "label": data.base_names[data.base_index(id)]})
		_ask(p, "intel_base", "첩보를 쌓을 거점을 고릅니다.", opts, ctx)
		pending["amount"] = v
		return true
	var bi := _resolve_base(p, e.get("base", "nearest"), ctx)
	if bi >= 0:
		_add_intel(bi, v)
	return false


func _add_intel(bi: int, v: int) -> void:
	var id: String = data.base_ids[bi]
	intel[id] = maxi(0, int(intel[id]) + v)
	_log("%s 첩보 %+d (첩보 %d)" % [base_name(bi), v, intel[id]])
	_push({"kind": "intel", "base": id, "value": v})


func _add_ready(v: int) -> void:
	ready = maxi(0, ready + v)
	_log("결행 준비 %+d (결행 준비 %d)" % [v, ready])
	_push({"kind": "ready", "value": ready})


func _op_gain_bomb(p: Dictionary, e: Dictionary) -> void:
	for k in int(e.get("count", 1)):
		if p["bombs"] < bomb_slots(p) and bomb_supply > 0:
			bomb_supply -= 1
			p["bombs"] += 1
			_log("%s: 폭탄을 얻었습니다." % p["name"])
			_push({"kind": "card", "deck": "item", "id": "bomb", "player": p["id"]})


func _op_draw_item(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	var count: int = int(e.get("count", 1))
	if count > 1:
		var rest_e: Dictionary = e.duplicate()
		rest_e["count"] = count - 1
		queue.push_front(rest_e)
	var peek: int = maxi(int(e.get("choose_from", 0)), stat(p, "item_draw_choice"))
	if e.has("item"):
		var want: String = str(e["item"])
		var from_deck: int = item_deck.find(want)
		if from_deck >= 0:
			item_deck.remove_at(from_deck)
			return _take_item(p, want)
		return false
	var cards := []
	for i in maxi(peek, 1):
		var id := _draw_from(item_deck, item_discard)
		if id == "":
			break
		cards.append(id)
	if cards.is_empty():
		_log("아이템 카드가 모두 떨어졌습니다.")
		return false
	if cards.size() == 1:
		return _take_item(p, cards[0])
	var opts := []
	for i in cards.size():
		opts.append({"value": i, "label": item_def(cards[i])["name"]})
	_ask(p, "draw_pick", "아이템 %d장 중 1장을 고릅니다 (나머지는 버립니다)." % cards.size(), opts, {})
	pending["cards"] = cards
	return true


func _op_choice(p: Dictionary, e: Dictionary) -> bool:
	var opts := []
	var effs := []
	var options: Array = e.get("options", [])
	for i in options.size():
		opts.append({"value": i, "label": options[i].get("label", "")})
		effs.append(options[i].get("effects", []))
	_ask(p, "effect_choice", "고릅니다.", opts, {})
	pending["effects"] = effs
	return true


static func grant_label(g: Dictionary) -> String:
	## 한 번 쓰는 권리의 화면 이름 (기록에 kind id가 그대로 나오지 않게)
	match str(g.get("kind", "")):
		"check_bonus": return "판정 +%d" % int(g.get("value", 0))
		"reroll": return "다시 굴리기"
		"evade_auto": return "회피 자동 성공"
		"escape_instant": return "즉시 탈옥"
	return "권리"


func _op_grant_once(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 한 번 쓰는 권리를 준다 (판정에서 자동으로 쓰임). who: self | 동료 고르기(능력이면 능력의 대상)
	var ids = _resolve_who(p, e, ctx, queue, str(e.get("who", "self")))
	if ids == null:
		return true
	if ids.is_empty():
		_log("한 번 쓰는 권리를 줄 대상이 없습니다.")
	for id in ids:
		var q: Dictionary = players[id]
		q["grants"].append({"kind": e.get("kind", ""), "value": int(e.get("value", 0)), "scope": e.get("scope", "any")})
		_log("%s: 한 번 쓰는 권리를 얻었습니다 (%s)." % [q["name"], grant_label(e)])
	return false


func _op_mark_tile(p: Dictionary, e: Dictionary) -> void:
	var f: String = str(e.get("flag", ""))
	var tile: Dictionary = board.get(p["pos"], {})
	if tile.is_empty() or f == "":
		return
	if not tile["flags"].has(f):
		tile["flags"].append(f)
	_log("%s: 이 칸에 표시를 남겼습니다 (%s)." % [p["name"], f])


# ---- 2b 효과들

func _op_police_advance(e: Dictionary) -> void:
	var steps: int = int(e.get("steps", 1))
	_log("추격 중인 경찰이 모두 %d칸 다가옵니다!" % steps)
	for pid in police.keys():
		if police.has(pid):
			_police_approach(players[pid], steps)
	_push({"kind": "police"})


func _police_ids_sorted() -> Array:
	var ids := police.keys()
	ids.sort()
	return ids


func _op_police_remove(p: Dictionary, e: Dictionary) -> void:
	match str(e.get("scope", "mine")):
		"mine":
			if police.has(p["id"]):
				_police_off(p["id"], "removed")
				_log("%s: 쫓던 경찰이 사라졌습니다." % p["name"])
		"all":
			if not police.is_empty():
				for pid in _police_ids_sorted():
					_police_off(pid, "removed")
				_log("모든 경찰이 물러났습니다.")
		"cell":
			var pick := -1
			if police.has(p["id"]) and police[p["id"]]["pos"] == p["pos"]:
				pick = p["id"]
			else:
				for pid in _police_ids_sorted():
					if police[pid]["pos"] == p["pos"]:
						pick = pid
						break
			if pick >= 0:
				_police_off(pick, "removed")
				_log("%s: 이 칸의 경찰을 제압했습니다." % p["name"])
			else:
				_log("%s: 이 칸에는 경찰이 없습니다." % p["name"])
	_push({"kind": "police"})


func _op_police_push(p: Dictionary, e: Dictionary) -> void:
	## 내 옆 칸(같은 칸 포함)의 경찰 1개를 steps칸 물러나게 한다 (나에게서 멀어지는 쪽으로)
	var pick := -1
	if police.has(p["id"]) and _manhattan(police[p["id"]]["pos"], p["pos"]) <= 1:
		pick = p["id"]
	else:
		for pid in _police_ids_sorted():
			if _manhattan(police[pid]["pos"], p["pos"]) <= 1:
				pick = pid
				break
	if pick < 0:
		_log("%s: 옆 칸에 경찰이 없습니다." % p["name"])
		return
	var pos: Vector2i = police[pick]["pos"]
	for i in int(e.get("steps", 1)):
		var best := pos
		var bd := _manhattan(pos, p["pos"])
		for d in DIRS:
			var n: Vector2i = pos + d
			if board.has(n) and _manhattan(n, p["pos"]) > bd:
				best = n
				bd = _manhattan(n, p["pos"])
		pos = best
	police[pick]["pos"] = pos
	_log("%s: 경찰이 물러났습니다." % p["name"])
	_push({"kind": "police"})



func _op_event_card(p: Dictionary, queue: Array) -> void:
	## 이벤트 카드 한 장을 뽑아 그 효과를 이어서 처리한다 (이벤트 타일)
	var id := _draw_from(event_deck, event_discard)
	if id == "":
		return
	event_discard.append(id)
	var ev: Dictionary = data.event(id)
	_log("%s: 이벤트 [%s] - %s" % [p["name"], ev.get("name", id), ev.get("text", "")])
	_push({"kind": "card", "deck": "event", "id": id, "player": p["id"]})
	var fx: Array = ev.get("effects", [])
	for n in range(fx.size() - 1, -1, -1):
		queue.push_front(fx[n])


func tile_has_op(t: String, op: String) -> bool:
	## 이 종류 타일에서 이동을 마칠 때 받는 효과(rules.tile_effects)에 이 op가 있는가 (보급 = gain_bomb, 아이템 = draw_item)
	for fe in data.rules.get("tile_effects", {}).get(t, {}).get("on_stop", []):
		if str(fe.get("op", "")) == op:
			return true
	return false


func _op_police_back(p: Dictionary, e: Dictionary) -> void:
	## 경찰을 steps칸 물러나게 한다 (scope mine: 나를 쫓는 경찰, all: 모든 경찰). 깔린 칸을 따라 쫓는 요원에게서 멀어지는 쪽으로
	## 가고, 따돌림 거리를 넘으면 사라진다 (골목 타일, 전신선 폭파)
	var owners := []
	if str(e.get("scope", "mine")) == "all":
		owners = _police_ids_sorted()
	elif police.has(p["id"]):
		owners = [p["id"]]
	if owners.is_empty():
		_log("%s: 물러날 경찰이 없습니다." % p["name"])
		return
	for pid in owners:
		var target: Vector2i = players[pid]["pos"]
		var pos: Vector2i = police[pid]["pos"]
		var d: Dictionary = _dist_from(target)
		for i in int(e.get("steps", 1)):
			var best := pos
			var bd := int(d.get(pos, 0))
			for dir in DIRS:
				var n: Vector2i = pos + dir
				if d.has(n) and int(d[n]) > bd and not police_on(n):
					best = n
					bd = int(d[n])
			pos = best
		police[pid]["pos"] = pos
		_log("%s를 쫓던 경찰이 물러났습니다." % players[pid]["name"])
		if walk_dist(pos, target) > int(data.rules["police"]["escape_distance"]):
			_police_off(pid, "shake")
			_log("%s: 경찰을 따돌렸습니다." % players[pid]["name"])
	_push({"kind": "police"})


func _op_police_send_far(p: Dictionary) -> void:
	if not police.has(p["id"]):
		return
	var far := 0
	var fd := -1
	for i in data.bases.size():
		var d := _manhattan(data.bases[i], p["pos"])
		if d > fd:
			fd = d
			far = i
	police[p["id"]]["pos"] = data.bases[far]
	_log("%s: 쫓던 경찰이 %s로 돌아갔습니다." % [p["name"], base_name(far)])
	_push({"kind": "police"})


func _free_neighbors(c: Vector2i) -> Array:
	## 아직 타일이 안 깔린 옆 칸
	var out := []
	for d in DIRS:
		var n: Vector2i = c + d
		if in_bounds(n) and not board.has(n):
			out.append(n)
	return out


func _lay_tile(c: Vector2i, type: String) -> void:
	## 더미에서 그 종류 한 장을 빼 (있으면) c에 깐다
	tile_deck.erase(type)
	board[c] = _new_tile(type)
	_push({"kind": "reveal", "pos": c, "tile": type})
	_log("%s 타일이 (%d, %d)에 깔렸습니다." % [tile_label(type), c.x, c.y])


func tile_label(type: String) -> String:
	return str(data.rules.get("tile_names", {}).get(type, type))


func _op_checkpoint_place(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## near의 옆 빈칸에 검문소를 깐다 (빈칸이 여럿이면 무작위)
	var near := str(e.get("near", "self"))
	var cells := []
	if near == "strike_base":
		var bi := _resolve_base_ref("strike_base")
		if bi >= 0:
			cells.append(data.bases[bi])
	else:
		var ids = _resolve_who(p, e, ctx, queue, near)
		if ids == null:
			return true
		for id in ids:
			cells.append(players[id]["pos"])
	for k in int(e.get("count", 1)):
		for c in cells:
			var free := _free_neighbors(c)
			if free.is_empty():
				_log("검문소를 깔 빈칸이 없습니다.")
				continue
			_lay_tile(free[rng.randi_range(0, free.size() - 1)], "check")
	return false


func _op_free_all_jailed(p: Dictionary) -> void:
	var any := false
	for q in players:
		if q["jailed"]:
			q["jailed"] = false
			any = true
			_log("%s: 감옥에서 풀려났습니다 (경찰은 붙지 않음)." % q["name"])
			_push({"kind": "free", "player": q["id"]})
	if any:
		_banner("감옥 폭동! 모두 탈출", "good", p)


func _op_discard_item(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	## 아이템을 버린다 (여러 장이면 하나씩 고름, 한 장뿐이면 그대로). who가 있으면 그 요원이 버린다 (가택 수색).
	if e.has("who") and not e.has("pid"):
		var ids = _resolve_who(p, e, {}, queue, str(e["who"]), bool(e.get("include_jailed", false)))
		if ids == null:
			return true
		if ids.is_empty():
			return false
		if ids.size() > 1 and str(e["who"]) in ["all", "everyone"]:
			for k in range(ids.size() - 1, 0, -1):
				var more: Dictionary = e.duplicate()
				more["pid"] = ids[k]
				queue.push_front(more)
		e = e.duplicate()
		e["pid"] = ids[0]
	var holder: Dictionary = players[int(e["pid"])] if e.has("pid") else p
	var count: int = int(e.get("count", 1))
	if count > 1:
		var rest_e: Dictionary = e.duplicate()
		rest_e["count"] = count - 1
		queue.push_front(rest_e)
	p = holder
	if p["items"].is_empty():
		_log("%s: 버릴 아이템이 없습니다." % p["name"])
		return false
	if p["items"].size() == 1:
		var id: String = p["items"].pop_back()
		item_discard.append(id)
		_log("%s: [%s]을(를) 버렸습니다." % [p["name"], item_def(id)["name"]])
		return false
	var opts := []
	for i in p["items"].size():
		opts.append({"value": i, "label": item_def(p["items"][i])["name"]})
	_ask(p, "discard", "버릴 아이템을 고릅니다.", opts, {})
	return true


func _op_threat_look(e: Dictionary) -> bool:
	## 2막 위협 덱 맨 위 count장을 보고 1장을 버린다 (결행 혜택)
	var n := mini(int(e.get("count", 2)), threat_deck.size())
	if n <= 0:
		return false
	var opts := []
	for i in n:
		var id: String = threat_deck[threat_deck.size() - 1 - i]
		opts.append({"value": i, "label": "%s — %s" % [data.threat(id).get("name", id), data.threat(id).get("text", "")]})
	_ask(players[benefit_chooser()], "threat_look", "2막 위협 맨 위 %d장입니다. 버릴 한 장을 고릅니다." % n, opts, {})
	return true


func _op_give_die(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 내 작전 주사위 하나를 동료에게 건넨다 (능력의 대상, 또는 who). 하루 건네기 횟수에는 세지 않는다.
	var ids = _resolve_who(p, e, ctx, queue, str(e.get("who", "ally_in_range")), true)
	if ids == null:
		return true
	var mine := my_dice(p["id"])
	ids = ids.filter(func(id): return not players[id]["done_today"])   # 이미 차례를 마친 요원에게는 주사위를 건넬 수 없다
	if ids.is_empty() or mine.is_empty():
		_log("%s: 건넬 상대나 주사위가 없습니다." % p["name"])
		return false
	if mine.size() > 1 and not e.has("die"):
		var opts := []
		for i in mine:
			opts.append({"value": i, "label": "주사위 %d" % die_value(i)})
		return _ask_pick(p, e, queue, "die", "pick_die", "%s에게 건넬 주사위를 고릅니다." % players[ids[0]]["name"], opts)
	var di: int = int(e["die"]) if e.has("die") else mine[0]
	if not di in mine:
		return false
	_give_die(p, di, players[ids[0]], false)
	return false


func _op_move(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## move_mod_next: 다음 이동 ±, move_today: 오늘 이동 ± (지금 이동 중이면 남은 칸에 바로 더함)
	var ids = _resolve_who(p, e, ctx, queue, str(e.get("who", "self")))
	if ids == null:
		return true
	var v: int = int(e.get("value", 0))
	for id in ids:
		var q: Dictionary = players[id]
		if str(e["op"]) == "move_mod_next":
			q["move_mod_next"] += v
			_log("%s: 다음 이동 %+d." % [q["name"], v])
		else:
			if phase == "turn" and id == current:
				# 지금 차례인 요원: 걷는 중이면 남은 칸에 바로, 아니면 다음 이동 행동에 붙는다
				if steps_left > 0:
					steps_left = maxi(steps_left + v, 0)
				else:
					q["flags"]["move_extra"] = int(q["flags"].get("move_extra", 0)) + v
			else:
				today["move_today"][id] = int(today["move_today"].get(id, 0)) + v
			_log("%s: 오늘 이동 %+d." % [q["name"], v])
	return false


func _op_die(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	## die_reroll(count, scope) · die_adjust(value ±) · die_set: 작전 주사위 하나를 골라 손봄.
	## scope "own"(기본: 내 주사위) 또는 "any"(아무 요원의 주사위)
	var op := str(e["op"])
	var cand := []
	for i in op_dice.size():
		if not op_dice[i]["used"] and (str(e.get("scope", "own")) == "any" or int(op_dice[i]["owner"]) == p["id"]):
			cand.append(i)
	if cand.is_empty():
		_log("손볼 주사위가 없습니다.")
		return false
	var sides := int(data.rules["die_sides"])
	if op == "die_adjust":
		if not e.has("sel"):
			var mag := absi(int(e.get("value", 1)))
			var opts := []
			for i in cand:
				for sign in [1, -1]:
					var nv: int = die_value(i) + sign * mag
					if nv >= 1 and nv <= sides:
						opts.append({"value": "%d:%d" % [i, sign * mag], "label": "%s: %d → %d" % [_die_owner_label(i), die_value(i), nv]})
			if opts.is_empty():
				return false
			return _ask_pick(p, e, queue, "sel", "pick_die", "어느 주사위를 어떻게 바꾸겠습니까?", opts)
		var parts: PackedStringArray = str(e["sel"]).split(":")
		var di := int(parts[0])
		op_dice[di]["value"] = clampi(die_value(di) + int(parts[1]), 1, sides)
		_log("%s의 눈이 %d이(가) 되었습니다." % [_die_owner_label(di), die_value(di)])
		_push_dice()
		return false
	if not e.has("die"):
		if cand.size() == 1:
			e = e.duplicate()
			e["die"] = cand[0]
		else:
			var dopts := []
			for i in cand:
				dopts.append({"value": i, "label": "%s: %d" % [_die_owner_label(i), die_value(i)]})
			return _ask_pick(p, e, queue, "die", "pick_die", "어느 주사위를 고르시겠습니까?", dopts)
	var i2 := int(e["die"])
	if op == "die_set":
		if not e.has("val"):
			var vopts := []
			for v in range(1, sides + 1):
				vopts.append({"value": v, "label": "눈 %d" % v})
			return _ask_pick(p, e, queue, "val", "pick_value", "원하는 눈을 고릅니다.", vopts)
		op_dice[i2]["value"] = clampi(int(e["val"]), 1, sides)
		_log("%s의 눈을 %d(으)로 정했습니다." % [_die_owner_label(i2), die_value(i2)])
		_push_dice()
		return false
	op_dice[i2]["value"] = _roll_die()
	_log("%s을(를) 다시 굴려 %d이(가) 나왔습니다." % [_die_owner_label(i2), die_value(i2)])
	_push_dice()
	var left: int = int(e.get("count", 1)) - 1
	if left > 0:
		var e3: Dictionary = e.duplicate()
		e3.erase("die")
		e3["count"] = left
		queue.push_front(e3)
	return false


func _die_owner_label(i: int) -> String:
	return "%s의 주사위" % players[int(op_dice[i]["owner"])]["name"]


func _push_dice() -> void:
	_push({"kind": "dice_rolled", "values": op_dice.map(func(d): return d["value"]),
		"owners": op_dice.map(func(d): return d["owner"]), "again": true})


func _op_threat_bury(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	## 내일 위협 카드(덱 맨 위)를 덱 맨 아래로. peek이면 먼저 보고 묻는다.
	if threat_deck.size() < 2:
		_log("내일 위협을 바꿀 수 없습니다.")
		return false
	if bool(e.get("peek", false)) and not e.has("bury"):
		var top: String = threat_deck[-1]
		return _ask_pick(p, e, queue, "bury", "pick_bury", "내일 위협은 「%s」입니다. 덱 맨 아래로 보내시겠습니까?" % data.threat(top).get("name", top),
			[{"value": true, "label": "맨 아래로 보낸다"}, {"value": false, "label": "그대로 둔다"}])
	if e.has("bury") and not bool(e["bury"]):
		return false
	var c: String = threat_deck.pop_back()
	threat_deck.push_front(c)
	_log("%s: 내일 위협 카드를 덱 맨 아래로 보냈습니다." % p["name"])
	return false


func _tile_type_options() -> Array:
	var types := []
	for t in tile_deck:
		if not t in types:
			types.append(t)
	types.sort()
	var opts := []
	for t in types:
		opts.append({"value": t, "label": "%s (%d장)" % [tile_label(t), tile_deck.count(t)]})
	return opts


func _op_place_tile(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	## 내 옆 빈칸에 타일을 깐다. type: normal | choose(더미에서 종류를 골라 깔고 shuffle_after면 더미를 섞음)
	var type := str(e.get("type", "normal"))
	if type == "choose" and not e.has("tile"):
		var opts := _tile_type_options()
		if opts.is_empty():
			_log("더미에 타일이 없습니다.")
			return false
		return _ask_pick(p, e, queue, "tile", "pick_tile", "더미에서 깔 타일을 고릅니다.", opts)
	var kind: String = str(e["tile"]) if type == "choose" else type
	var free := _free_neighbors(p["pos"])
	if free.is_empty():
		_log("%s: 타일을 깔 옆 빈칸이 없습니다." % p["name"])
		return false
	if free.size() > 1 and not e.has("cell"):
		var copts := []
		for c in free:
			copts.append({"value": c, "label": "(%d, %d)" % [c.x, c.y]})
		return _ask_pick(p, e, queue, "cell", "pick_cell", "타일을 깔 칸을 고릅니다.", copts)
	var cell: Vector2i = e["cell"] if e.has("cell") else free[0]
	if board.has(cell) or _manhattan(cell, p["pos"]) != 1:
		return false
	_lay_tile(cell, kind)
	if bool(e.get("shuffle_after", false)):
		_shuffle(tile_deck)
		_log("타일 더미를 다시 섞었습니다.")
	return false


func _adjacent_landing_cells(p: Dictionary, anchor: Vector2i) -> Array:
	## p가 anchor 옆(거리 1)에 설 수 있는 깔린 빈칸
	var out := []
	for d in DIRS:
		var n: Vector2i = anchor + d
		if _inert_tile(n) and not police_on(n):
			out.append(n)
	return out


func _op_move_to_ally(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 동료 하나를 골라 그 옆 칸(adjacent)이나 그 칸으로 바로 옮겨 간다
	var ids = _resolve_who(p, e, ctx, queue, "ally")
	if ids == null:
		return true
	if ids.is_empty():
		_log("%s: 찾아갈 동료가 없습니다." % p["name"])
		return false
	var q: Dictionary = players[ids[0]]
	var cells: Array
	if bool(e.get("adjacent", false)):
		cells = _adjacent_landing_cells(p, q["pos"])
	else:
		cells = [q["pos"]] if not police_on(q["pos"]) else []
	if cells.is_empty():
		_log("%s: %s 곁에 설 자리가 없습니다." % [p["name"], q["name"]])
		return false
	if cells.size() > 1 and not e.has("cell"):
		var opts := []
		for c in cells:
			opts.append({"value": c, "label": "(%d, %d)" % [c.x, c.y]})
		return _ask_pick(p, e, queue, "cell", "pick_cell", "%s 곁의 어느 칸으로 가겠습니까?" % q["name"], opts)
	var to: Vector2i = e["cell"] if e.has("cell") else cells[0]
	if not to in cells:
		return false
	_teleport(p, to)
	_log("%s: %s 곁으로 단숨에 이동했습니다." % [p["name"], q["name"]])
	return false


func _op_pull_ally(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 동료 하나를 내 칸으로 데려온다 (데려온 칸의 효과는 없다)
	var ids = _resolve_who(p, e, ctx, queue, "ally")
	if ids == null:
		return true
	if ids.is_empty():
		return false
	var q: Dictionary = players[ids[0]]
	if q["pos"] == p["pos"]:
		_log("%s: %s은(는) 이미 같은 칸에 있습니다." % [p["name"], q["name"]])
		return false
	_teleport(q, p["pos"])
	_log("%s: %s을(를) 내 칸으로 데려왔습니다." % [p["name"], q["name"]])
	return false


func _op_transfer_item(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array, who: String,
		include_jailed: bool, free: bool) -> bool:
	## give_item(range) · send_item: 아이템 한 장을 동료에게. 받는 쪽 손패가 넘치면 받는 사람이 버릴 카드를 고른다.
	var ids = _resolve_who(p, e, ctx, queue, who, include_jailed)
	if ids == null:
		return true
	if ids.is_empty() or p["items"].is_empty():
		_log("%s: 건넬 상대나 아이템이 없습니다." % p["name"])
		return false
	var q: Dictionary = players[ids[0]]
	if p["items"].size() > 1 and not e.has("item"):
		var opts := []
		for i in p["items"].size():
			opts.append({"value": i, "label": item_def(p["items"][i])["name"]})
		return _ask_pick(p, e, queue, "item", "pick_item", "%s에게 줄 아이템을 고릅니다." % q["name"], opts)
	var idx: int = int(e["item"]) if e.has("item") else 0
	if idx < 0 or idx >= p["items"].size():
		return false
	var id: String = p["items"][idx]
	p["items"].remove_at(idx)
	q["items"].append(id)
	if not free and bool(data.rules["coop"]["give_counts_as_item_use"]):
		p["item_uses"] += 1
	p["stats"]["gives"] += 1
	_saga_note(q, "hold_items")
	_log("%s: [%s]을(를) %s에게 건넸습니다." % [p["name"], item_def(id)["name"], q["name"]])
	if q["items"].size() > hand_limit(q):
		_ask_discard(q)
		return true
	return false


# ================================================================ 선택

func _ask(p: Dictionary, kind: String, prompt: String, options: Array, ctx: Dictionary) -> void:
	for o in options:
		if typeof(o) == TYPE_DICTIONARY and o.get("label") is String:
			o["label"] = josa(o["label"])
	pending = {"kind": kind, "player": p["id"], "prompt": josa(prompt), "options": options,
		"ctx": ctx, "rest": [], "resume_phase": phase}
	phase = "choice"
	_push({"kind": "choice", "player": p["id"]})



# ================================================================ 아래 층에서도 쓰는 도움 함수

func _give_die(p: Dictionary, i: int, q: Dictionary, counts_daily := true) -> void:
	## counts_daily가 false이면 하루 건네기 횟수(gives_today)에 세지 않는다 (정 인쇄공 「연락망」)
	op_dice[i]["owner"] = q["id"]
	if counts_daily:
		p["gives_today"] = int(p["gives_today"]) + 1
	p["stats"]["gives"] += 1
	_log("%s: %s에게 주사위 %d을(를) 건넸습니다." % [p["name"], q["name"], die_value(i)])
	_push({"kind": "die_given", "player": p["id"], "target": q["id"], "die": i, "value": die_value(i)})
	_saga_note(p, "give_dice", {"target": q["id"]})


func _teleport(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to, "jump": true})
	_saga_step_on(p, to)


func _grant_index(p: Dictionary, kind: String, scene := false) -> int:
	## scope "strike" 권리는 결행 장면 판정(scene == true)에서만 쓰인다. 1막 판정은 "any"만.
	for i in p["grants"].size():
		var g: Dictionary = p["grants"][i]
		if g.get("kind", "") != kind:
			continue
		if str(g.get("scope", "any")) == "strike" and not scene:
			continue
		if str(g.get("scope", "any")) == "final" and not (scene and act == 2 and scene_index == scenes.size() - 1):
			continue
		return i
	return -1


func _police_off(pid: int, reason: String) -> void:
	## 경찰이 이 요원을 그만 쫓는다. reason: jail | shake | hideout | removed
	## 투옥이 아닌 이유(따돌림·은신처·제거)는 「원수」 사연의 shake_police로 센다.
	if not police.has(pid):
		return
	police.erase(pid)
	if reason != "jail":
		players[pid]["stats"]["shakes"] = int(players[pid]["stats"].get("shakes", 0)) + 1
		_saga_note(players[pid], "shake_police")


# ---------------------------------------------------------------- 사연 나눠 주기
