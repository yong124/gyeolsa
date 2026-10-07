class_name GameAIV2
extends RefCounted
## 공개 정보와 자신의 사연만 사용해 합법 액션을 고른다.

const ACT2_DAYS_PER_SCENE := 0.8
## 사연 목표의 가치 (미션은 2~3). 팀 일보다 앞서지 않게 조금 낮게 둔다 (기획서 19.7)
const SAGA_VALUE := 2.2
## 갇힌 동료를 구하러 가는 가치와 거리 한도
const RESCUE_VALUE := 3.5
const RESCUE_RANGE := 8
const PERSONA := {
	"bold": {"risk": 0.35, "vote": 0.7},
	"careful": {"risk": 1.4, "vote": 1.2},
	"support": {"risk": 0.8, "vote": 1.0},
}
const CHOICE_KINDS := ["launch_vote", "launch_target", "launch_benefit", "threat_look", "strike_target", "saga_keep", "reroll", "react_evade", "mission_gear", "informer_pay", "bribe",
	"discard", "draw_pick", "effect_choice", "pick_player", "pick_cell", "pick_die", "pick_tile", "pick_item",
	"pick_value", "pick_bury", "hop", "intel_base"]

static var fallback_count := 0


static func next_actor(g: RulesV2) -> int:
	if g.phase == "choice":
		return int(g.pending.get("player", -1))
	if g.phase == "turn":
		return g.current
	var legal := g.legal_actions()
	if legal.is_empty():
		return -1
	if g.phase == "plan":
		for a in legal:
			if not _morning_fix(g, g.players[int(a["player"])], a).is_empty():
				return int(a["player"])
		return int(g.leader)
	if g.phase == "day":
		var best := -1
		var best_score := -999.0
		for a in legal:
			var p: Dictionary = g.players[int(a["player"])]
			var score := 0.0
			if p["jailed"]:
				score += 10.0
			if g.police.has(p["id"]):
				score += 5.0
			if g.act == 2:
				score += 3.0
			if g.stat(p, "end_move_hop_to_ally") > 0:
				score -= 2.0
			score += _donor_bonus(g, p)
			score -= float(p["id"]) * 0.01
			if score > best_score:
				best_score = score
				best = int(p["id"])
		return best
	return int(legal[0].get("player", -1))


static func _donor_bonus(g: RulesV2, p: Dictionary) -> float:
	## 같은 칸에 아직 차례를 안 한 동료가 있고 내 주사위가 더 많으면 먼저 한다 (남는 주사위를 건네 줄 수 있다).
	## 주사위를 받을 요원은 그만큼 나중에 한다.
	var mine: int = g.my_dice(p["id"]).size()
	for q in g.players:
		if q["id"] != p["id"] and not q["done_today"] and not q["jailed"] and q["pos"] == p["pos"] and mine > g.my_dice(q["id"]).size():
			return 1.5
	return 0.0


static func decide(g: RulesV2, pid: int, persona := "") -> Dictionary:
	var legal := g.legal_actions()
	if legal.is_empty():
		return {}
	if pid < 0 or pid >= g.players.size():
		pid = int(legal[0]["player"])
	var own := []
	for a in legal:
		if int(a["player"]) == pid:
			own.append(a)
	if own.is_empty():
		pid = int(legal[0]["player"])
		own = legal
	var p: Dictionary = g.players[pid]
	if persona == "":
		persona = str(g.char_def(p).get("persona", "support"))
	var policy: Dictionary = PERSONA.get(persona, PERSONA["support"])
	var picked: Dictionary = {}
	match g.phase:
		"choice": picked = _choice(g, p, own, policy)
		"plan": picked = _plan(g, p, own)
		"day": picked = _find(own, "begin_turn")
		"turn": picked = _turn(g, p, own, policy)
	if picked in legal:
		return picked
	if picked.is_empty() and g.phase == "plan":
		return {}
	fallback_count += 1
	for t in ["end_move", "end_turn", "start_day", "begin_turn", "choose"]:
		var a := _find(own, t)
		if not a.is_empty():
			return a
	return own[0]


static func _find(actions: Array, kind: String) -> Dictionary:
	for a in actions:
		if a["type"] == kind:
			return a
	return {}


static func _choice(g: RulesV2, p: Dictionary, legal: Array, policy: Dictionary) -> Dictionary:
	var kind := str(g.pending.get("kind", ""))
	var best: Dictionary = legal[0]
	var best_score := -1.0e20
	for a in legal:
		var v = a.get("value")
		var score := 0.0
		match kind:
			"launch_vote":
				var target := _best_target(g, p)
				var needed := float(4 + g.alert_level() - 1) * ACT2_DAYS_PER_SCENE * float(policy["vote"])
				# 첩보가 쌓였거나, 준비가 넉넉해 결행 혜택을 받을 수 있거나, 2막에 쓸 날이 빠듯해지면 찬성 (기다려도 날만 줄어듦)
				var margin := int(g.data.rules["ai"]["vote_ready_margin"])
				var ready_now := int(g.intel.get(target, 0)) >= int(g.data.rules["launch"]["target_min_intel"]) or g.ready >= int(g.data.rules["launch_min"]) + margin
				var no_slack := float(g.rounds_left) <= needed + 1.0 or g.rounds_left <= g.rounds_total * 0.55
				var yes := ready_now or no_slack
				score = 10.0 if bool(v) == yes else 0.0
			"launch_target":
				score = _target_score(g, p, str(v))
			"launch_benefit":
				score = _benefit_score(g, str(v))
			"threat_look":
				score = _threat_harm(g, int(v))
			"strike_target", "intel_base":
				score = float(g.intel.get(str(v), 0)) * 2.0 - float(_dist(p["pos"], g.data.bases[g.data.base_index(str(v))])) * 0.1
			"saga_keep":
				var prog: Dictionary = g.saga_progress(p["id"]).get(str(v), {"have": 0, "need": 1})
				score = float(prog["have"]) / float(maxi(1, prog["need"]))
				var cond: Dictionary = g.data.saga(str(v)).get("condition", {})
				if cond.get("strike", "") == g.launch_info.get("target", ""):
					score += 0.5
				# 결행 사연은 진행도가 늘 0이지만 2막에서 이룰 수 있다: 진행이 절반이 안 되는 다른 사연보다는 낫게 본다
				if str(cond.get("kind", "")) in ["strike_entry_by_me", "strike_final_by_me", "present_at_final"]:
					score = maxf(score, 0.5)
			"reroll":
				score = _check_option_score(g, p, str(v))
			"react_evade": score = 10.0 if bool(v) else 0.0
			"mission_gear": score = _gear_score(g, p, int(v))
			"informer_pay": score = _informer_score(g, p, bool(v))
			"bribe": score = _bribe_score(g, p, bool(v))
			"discard": score = -float(g.item_def(str(p["items"][int(v)])).get("ai_value", 3))
			"draw_pick": score = float(g.item_def(str(g.pending.get("cards", [])[int(v)])).get("ai_value", 3))
			"pick_bury": score = 10.0 if bool(v) else 0.0
			"pick_die":
				if typeof(v) == TYPE_INT and int(v) < g.op_dice.size():
					score = -float(g.die_value(int(v)))   # 다시 굴릴 주사위: 가장 낮은 눈
				elif typeof(v) == TYPE_STRING and ":" in str(v):
					var sel: PackedStringArray = str(v).split(":")
					score = float(g.die_value(int(sel[0]))) * signf(float(sel[1]))   # 눈 고치기: 높은 눈을 더 높게
			"pick_value": score = float(v) if typeof(v) == TYPE_INT else 0.0
			"pick_player":
				if typeof(v) == TYPE_INT and int(v) < g.players.size():
					score = -float(_dist(g.players[int(v)]["pos"], p["pos"]))
			"pick_cell":
				if v is Vector2i:
					score = -float(_dist(v, _goal(g, p, policy)))
			"hop":
				# 동료 곁으로 한 칸: 가려는 곳에 더 가까워질 때만
				var goal_h := _goal(g, p, policy)
				score = -float(_dist(v, goal_h)) if v is Vector2i else -float(_dist(p["pos"], goal_h)) + 0.01
			"pick_tile":
				if int(g.scene_need().get("bomb", 0)) > 0 and g.tile_has_op(str(v), "gain_bomb"):
					score = 3.0
				elif int(g.scene_need().get("item", 0)) > 0 and str(v) == "item":
					score = 2.0
				else:
					score = 1.0 if g.tile_has_op(str(v), "draw_item") else 0.0
			"effect_choice": score = _effects_value(g, p, g.pending.get("effects", [])[int(v)]) if typeof(v) == TYPE_INT else 0.0
			_:
				if typeof(v) == TYPE_BOOL:
					score = 1.0 if bool(v) else 0.0
		if score > best_score:
			best_score = score
			best = a
	return best


static func _target_score(g: RulesV2, p: Dictionary, base_id: String) -> float:
	## 결행 대상 점수 = 첩보 + 내 사연과 맞는 정도 + 거기까지의 거리 (가중치는 rules.ai.launch_target)
	var w: Dictionary = g.data.rules["ai"]["launch_target"]
	var match_saga := 0.0
	for id in g.saga_cards(p["id"]):
		for cond in g._saga_conds(str(id)):
			if str(cond.get("strike", "")) == base_id:
				match_saga = 1.0
	var d := _dist(p["pos"], g.data.bases[g.data.base_index(base_id)])
	return float(g.intel.get(base_id, 0)) * float(w["intel"]) + match_saga * float(w["saga"]) - float(d) * float(w["distance"])


static func _best_target(g: RulesV2, p: Dictionary) -> String:
	var best := ""
	var best_score := -1.0e20
	for id in g.launch_candidates():
		var sc := _target_score(g, p, str(id))
		if sc > best_score:
			best_score = sc
			best = str(id)
	return best


static func _benefit_score(g: RulesV2, id: String) -> float:
	## 결행 혜택: 경계 2단계 이상이면 경비 강화 빼기가 먼저, 그다음 첩보 토큰, 첫날 주사위, 위협 덱 보기 (효과 op만 본다)
	var v := 0.0
	for b in g.data.rules["launch"]["benefits"]:
		if str(b["id"]) != id:
			continue
		for e in b.get("effects", []):
			match str(e.get("op", "")):
				"no_reinforce": v += 4.0 if g.alert_level() >= 2 else 0.5
				"intel_token_bonus": v += 3.0
				"dice_extra_tomorrow": v += 2.0
				"threat_look_discard": v += 1.0
				_: v += 0.2
	return v


static func _threat_harm(g: RulesV2, i: int) -> float:
	## 2막 위협 덱 맨 위 i번째 카드를 버릴 값: 해로운(tone bad) 카드, 효과가 많은 카드일수록 높다
	var idx := g.threat_deck.size() - 1 - i
	if idx < 0 or idx >= g.threat_deck.size():
		return 0.0
	var card: Dictionary = g.data.threat(str(g.threat_deck[idx]))
	return (2.0 if str(card.get("tone", "bad")) == "bad" else 0.0) + float(card.get("effects", []).size())


static func _funds_cfg(g: RulesV2) -> Dictionary:
	return g.data.rules["ai"]["funds"]


static func _funds_threat_left(g: RulesV2) -> bool:
	## 군자금을 빼앗는 위협(가택 수색·자금 동결)이 덱에 남았는가 — 남았으면 쌓기보다 쓴다
	for id in g.threat_deck:
		for e in g.data.threat(str(id)).get("effects", []):
			if str(e.get("op", "")) == "funds_half" or (str(e.get("op", "")) == "funds" and int(e.get("value", 0)) < 0):
				return true
	return false


static func _funds_spare(g: RulesV2) -> int:
	## 써도 되는 군자금 (남겨 둘 몫을 뺀 값)
	return g.funds - (0 if _funds_threat_left(g) else int(_funds_cfg(g)["reserve"]))


static func _gear_score(g: RulesV2, p: Dictionary, index: int) -> float:
	## 아이템 1장이나 군자금을 내고 판정을 쉽게(무기 조달) 하거나 경찰이 안 붙게(간수 매수) 할지. 쓰지 않으면 0점.
	## 성공률이 크게 오를 때만 쓴다 (rules.ai.funds.gear_min_gain).
	if index < 0:
		return 0.0
	var gear: Dictionary = g.pending.get("gear", {})
	var cost := 0.0
	if index >= RulesV2.GEAR_FUNDS:
		cost = float(gear["cost"]["funds"]) * float(_funds_cfg(g)["gear_funds_value"])
		if _funds_spare(g) < int(gear["cost"]["funds"]):
			return -1.0
	else:
		cost = float(g.item_def(str(p["items"][index])).get("ai_value", 3)) * 0.06
	var gain := 0.0
	if gear.has("check_bonus") and not g.check.is_empty():
		var c: Dictionary = g.check.duplicate()
		var die := int(c.get("die_value", 0))
		var before := g.check_chance(c, die)
		c["bonus"] = int(c["bonus"]) + int(gear["check_bonus"])
		gain = g.check_chance(c, die) - before
		if gain < float(_funds_cfg(g)["gear_min_gain"]):
			return -1.0
	elif gear.has("effects"):
		gain = 0.25 if g.alert_level() >= 2 else 0.1   # 경찰이 안 붙으면 이동이 자유롭다
	return gain - cost


static func _informer_score(g: RulesV2, p: Dictionary, pay: bool) -> float:
	## 정보원 사례금: 표적을 멈추고 판정 성공률이 크게 오를 때만
	if not pay:
		return 0.0
	var uid := int(g.pending.get("marker", -1))
	for m in g.markers:
		if int(m["uid"]) == uid:
			var cond: Dictionary = g.card_cond(str(m["id"]))
			if _funds_spare(g) < int(cond["informer_cost"]["funds"]):
				return -1.0
			var gain := _target_chance(g, p, cond, true) - _target_chance(g, p, cond, false)
			if gain < float(_funds_cfg(g)["gear_min_gain"]):
				return -1.0
			return gain - float(_funds_cfg(g)["gear_min_gain"]) + 0.05
	return -1.0


static func _bribe_score(g: RulesV2, p: Dictionary, pay: bool) -> float:
	## 검문소 뇌물: 통과 확률이 낮고 돈이 넉넉할 때
	if not pay:
		return 0.0
	if _funds_spare(g) < int(g.data.rules["checkpoint"]["bribe"]):
		return -1.0
	return float(_funds_cfg(g)["bribe_below"]) - g.evade_chance(p)


static func _effects_value(g: RulesV2, p: Dictionary, effects: Array) -> float:
	## 효과 선택지의 값. 아는 효과(아이템, 내일 주사위)만 값을 매기고, 나머지는 효과 수로 센다.
	## 아이템은 손이 가득 차면 값이 낮고, 내일 주사위는 2막(장면에 바칠 눈이 필요함)에서 더 쓸모 있다.
	var v := 0.0
	for e in effects:
		var n := float(e.get("count", 1))
		match str(e.get("op", "")):
			"draw_item": v += n * (3.0 if p["items"].size() < g.hand_limit(p) else 1.0)
			"dice_extra_tomorrow": v += n * (3.2 if g.act == 2 else 2.5)
			_: v += 0.5
	return v


static func _check_option_score(g: RulesV2, p: Dictionary, v: String) -> float:
	## 실패한 판정을 다시 굴릴 권리를 쓸지: 다시 굴려 성공할 확률이 5%보다 높으면 쓴다
	var c: Dictionary = g.check
	if c.is_empty():
		return 0.0
	if v == "grant":
		return g.check_chance(c, int(c.get("die_value", 0))) + 0.05
	return 0.05


static func _plan(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	## 아침: 낮은 눈을 다시 굴리는 능력·눈을 고치는 아이템이 쓸모 있으면 쓰고, 아니면 하루를 시작한다
	for a in legal:
		var fix := _morning_fix(g, p, a)
		if not fix.is_empty():
			return fix
	return _find(legal, "start_day")


static func _morning_fix(g: RulesV2, p: Dictionary, a: Dictionary) -> Dictionary:
	if int(a["player"]) != p["id"]:
		return {}
	var effects := []
	if a["type"] == "ability":
		effects = g.ability_def(p).get("effects", [])
	elif a["type"] == "use_item":
		effects = g.item_def(str(p["items"][int(a["index"])])).get("effects", [])
	for e in effects:
		match str(e.get("op", "")):
			"die_reroll":
				for i in g.op_dice.size():
					var d: Dictionary = g.op_dice[i]
					if not d["used"] and int(d["value"]) <= 2 and (str(e.get("scope", "own")) == "any" or int(d["owner"]) == p["id"]):
						return a
			"die_adjust":
				for i in g.my_dice(p["id"]):
					if g.die_value(i) == 5:
						return a
	return {}


static func _turn(g: RulesV2, p: Dictionary, legal: Array, policy: Dictionary) -> Dictionary:
	## 낮의 한 걸음. 주사위 1개 = 행동 1개이므로 하루 계획은 곧 주사위 배분이다:
	## 판정에 남길 큰 눈과 이동에 쓸 눈을 나누고, 남는 주사위는 건네거나 정찰·숨기에 쓰고, 쓸모가 없으면 차례를 마친다.
	if p["jailed"]:
		return _jailed_turn(g, p, legal)
	if g.steps_left > 0:
		return _walk(g, p, legal, policy)
	# 1. 지금 선 자리에서 할 일: 미션 판정, 2막 장면 판정·바치기
	var chk := _check_action(g, p, legal, "mission_check")
	if not chk.is_empty():
		return chk
	var work := _work_action(g, p, legal)
	if not work.is_empty():
		return work
	var pay_die := _scene_pay_die(g, p, legal)
	if not pay_die.is_empty():
		return pay_die
	var pay := _scene_pay_other(g, p, legal)
	if not pay.is_empty():
		return pay
	if g.act == 2:
		var cc := _check_action(g, p, legal, "counter_check")
		if not cc.is_empty():
			return cc   # 반격을 막아야 오늘 버틴 날로 치고 투옥도 피한다
		var sc := _check_action(g, p, legal, "scene_check")
		if not sc.is_empty():
			var intel := _find(legal, "use_intel")
			if not intel.is_empty() and intel.get("mode") == "check" and g.intel_tokens > 0:
				return intel
			return sc
	var buy := _market_action(g, p, legal)
	if not buy.is_empty():
		return buy
	# 2. 공짜로 쓸 것: 사연을 위한 건네기, 능력, 아이템
	if _saga_kind(g, p, "give_dice") and g.my_dice(p["id"]).size() >= 2:
		var gd := _give_die_action(g, p, legal)
		if not gd.is_empty():
			return gd
	if _saga_kind(g, p, "give_items") and p["items"].size() > 0 and not g.my_dice(p["id"]).is_empty():
		var give := _smallest(g, p, legal, "give_item")
		if not give.is_empty():
			return give
	var free := _free_use(g, p, legal, policy)
	if not free.is_empty():
		return free
	# 3. 이동: 가려는 곳에 닿는 눈을 고른다. 갈 길이 덮여 있고 주사위가 넉넉하면 먼저 정찰한다.
	var goal := _goal(g, p, policy)
	if goal != p["pos"] and g.my_dice(p["id"]).size() >= 3 and _dist(p["pos"], goal) >= 3 and g.path_to(p, goal)["path"].is_empty():
		var look := _smallest(g, p, legal, "scout")
		if not look.is_empty():
			return look
	var mv := _move_die(g, p, legal, goal)
	if not mv.is_empty():
		return mv
	# 4. 남는 주사위: 건네기 > 숨기(쫓길 때) > 정찰 > 차례 마치기
	var idle := _give_die_action(g, p, legal)
	if not idle.is_empty():
		return idle
	if g.police.has(p["id"]):
		var hide := _smallest(g, p, legal, "hide")
		if not hide.is_empty():
			return hide
	var scout := _largest(g, p, legal, "scout")
	if not scout.is_empty() and goal != p["pos"]:
		var route: Dictionary = g.path_to(p, goal)
		if route["path"].is_empty() or int(route["unknown"]) > 0:
			return scout   # 가려는 길이 덮여 있을 때만 정찰
	return _find(legal, "end_turn")


static func _jailed_turn(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	for a in legal:
		if a["type"] == "use_item" and str(g.item_def(str(p["items"][int(a["index"])])).get("when", "")) == "jailed":
			return a   # 옷핀: 바로 탈출
	var esc := _check_action(g, p, legal, "escape")
	if not esc.is_empty():
		return esc
	var gd := _give_die_action(g, p, legal)
	if not gd.is_empty():
		return gd
	return _find(legal, "end_turn")


static func _walk(g: RulesV2, p: Dictionary, legal: Array, policy: Dictionary) -> Dictionary:
	## 걷는 중: 보급·아이템 칸에서 필요하면 멈추고, 아니면 가려는 곳에 가까워지는 칸으로
	if g.tile_has_op(g.tile_type(p["pos"]), "gain_bomb") and p["bombs"] < g.bomb_slots(p) and (_bombs_short(g) > 0 or g.has_bomb_card()):
		return _find(legal, "end_move")
	if g.tile_has_op(g.tile_type(p["pos"]), "draw_item") and not g.board[p["pos"]].get("used", false) and int(g.scene_need().get("item", 0)) > 0:
		return _find(legal, "end_move")
	var free := _free_use(g, p, legal, policy)
	if not free.is_empty():
		return free
	var goal := _goal(g, p, policy)
	var now := _dist(p["pos"], goal)
	var best: Dictionary = {}
	var best_score := -1.0e20
	for a in legal:
		if a["type"] != "step":
			continue
		var to: Vector2i = a["to"]
		var score := float(now - _dist(to, goal)) * 10.0
		if g.police_danger(p).has(to):
			score -= float(policy["risk"]) * 4.0
		if g.tile_type(to) == "check":
			score -= (1.0 - g.evade_chance(p)) * float(policy["risk"]) * 4.0
		if not g.board.has(to):
			score += 0.2
		if score > best_score:
			best_score = score
			best = a
	if not best.is_empty() and best_score > 0.0:
		return best
	return _find(legal, "end_move")


static func _free_use(g: RulesV2, p: Dictionary, legal: Array, policy: Dictionary) -> Dictionary:
	## 주사위 없이 쓰는 능력과 아이템: 쓸모가 있을 때만
	var goal := _goal(g, p, policy)
	for a in legal:
		if a["type"] == "ability":
			var effects: Array = g.ability_def(p).get("effects", [])
			for e in effects:
				var op := str(e.get("op", ""))
				if op == "place_tile" and g.act == 2 and int(g.scene_need().get("bomb", 0)) > 0:
					var supply_found := false
					for c in g.board:
						if g.tile_has_op(g.tile_type(c), "gain_bomb"):
							supply_found = true
					if not supply_found:
						return a
				if op == "give_die" and a.has("target") and g.my_dice(p["id"]).size() >= 2 \
						and (g.players[int(a["target"])]["jailed"] or _saga_kind(g, p, "give_dice")):
					return a   # 감옥의 동료가 탈옥 판정에 쓰도록, 또는 주사위를 건네는 사연을 위해
				if op == "intel" and e.get("base", "") == "choose" and g.act == 1 and _exposure_headroom(g) >= 2 \
						and g.my_dice(p["id"]).size() >= 2 and g.die_value(int(a["die"])) <= 3:
					return a   # 낮은 눈 하나로, 경계 단계가 오르기까지 여유가 있을 때만 첩보를 노출과 바꾼다
				if op == "police_remove" and g.police.has(p["id"]):
					return a
				if op == "police_push" and g.police.has(p["id"]):
					return a
				if op == "checkpoint_pass" and _next_check(g, p):
					return a
				if op == "move_today" and a.has("target") and not g.players[int(a["target"])]["done_today"]:
					return a   # 아직 차례를 안 한 동료의 첫 이동을 돕는다
				if op == "grant_once" and g.act == 2 and not _find(legal, "scene_check").is_empty():
					return a
	for a in legal:
		if a["type"] == "use_item":
			var it: Dictionary = g.item_def(str(p["items"][int(a["index"])]))
			for e in it.get("effects", []):
				var op2 := str(e.get("op", ""))
				if op2 == "police_remove" and g.police.has(p["id"]):
					return a
				if op2 == "checkpoint_pass" and _next_check(g, p):
					return a
				if op2 == "threat_bury":
					return a
				if op2 == "move_today" and _dist(p["pos"], goal) > _best_move(g, p, legal):
					return a
	return {}


static func _best_move(g: RulesV2, p: Dictionary, legal: Array) -> int:
	## 지금 가진 주사위 한 개로 갈 수 있는 가장 먼 칸 수
	var best := 0
	for a in legal:
		if a["type"] == "move_die":
			best = maxi(best, g.move_value(p, int(a["die"])))
	return best


static func _check_action(g: RulesV2, p: Dictionary, legal: Array, kind: String) -> Dictionary:
	## 작전 판정 행동: 성공 확률이 가장 높은 주사위로 (같으면 작은 눈)
	var best: Dictionary = {}
	var best_chance := -1.0
	for a in legal:
		if a["type"] != kind:
			continue
		var c: Dictionary = g.check_preview(p, a)
		var chance: float = g.check_chance(c, g.die_value(int(a["die"])))
		if chance > best_chance + 0.0001 or (absf(chance - best_chance) <= 0.0001 and g.die_value(int(a["die"])) < g.die_value(int(best["die"]))):
			best_chance = chance
			best = a
	return best


static func _work_action(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	## 공작 바치기: 합은 남은 몫을 한 번에 채우는 가장 작은 눈(없으면 가장 큰 눈), 조합·마커마다 하나는 가장 작은 눈
	var gives := legal.filter(func(a): return a["type"] == "work_give")
	if gives.is_empty():
		return {}
	gives.sort_custom(func(a, b): return g.die_value(int(a["die"])) < g.die_value(int(b["die"])))
	var id := str(g.marker_at(p["pos"]).get("id", ""))
	var cond: Dictionary = g.card_cond(id)
	if str(cond.get("mode", "")) == "sum":
		var st: Dictionary = g.mission_state.get(id, {})
		var need := int(st.get("need", 0)) - int(st.get("sum", 0))
		for a in gives:
			if g.die_value(int(a["die"])) >= need:
				return a
		return gives.back()
	return gives[0]


static func _market_action(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	## 장터: 손패에 자리가 있고 쓸 곳이 보일 때 산다. 폭탄은 폭탄이 모자란 판에서만, 아이템은 돈이 넉넉할 때(또는 빼앗길 위협이 남았을 때)
	var best: Dictionary = {}
	var best_score := 0.0
	for a in legal:
		if a["type"] != "market":
			continue
		var offer: Dictionary = {}
		for o in g.data.rules["market"]["offers"]:
			if str(o["id"]) == str(a["offer"]):
				offer = o
		var cost := g.market_cost(p, offer)
		var score := 0.0
		var wants_bomb := _bombs_short(g) > 0 or g.has_bomb_card()
		for fx in offer.get("effects", []):
			if str(fx.get("op", "")) == "gain_bomb" and wants_bomb and p["bombs"] == 0:
				score = 2.0
			elif str(fx.get("op", "")) == "draw_item":
				score = 1.0
		if score <= 0.0 or _funds_spare(g) < cost:
			continue
		score -= float(cost) * 0.1
		if score > best_score + 0.0001 or (absf(score - best_score) <= 0.0001 and not best.is_empty() and g.die_value(int(a["die"])) < g.die_value(int(best["die"]))):
			best = a
			best_score = score
	return best


static func _market_targets(g: RulesV2, p: Dictionary) -> Array:
	## 장터까지 갈 만한가: 손패에 자리가 있고 돈이 넉넉할 때
	var cells := []
	if p["items"].size() >= g.hand_limit(p) and p["bombs"] >= g.bomb_slots(p):
		return cells
	var cheapest := 99
	for o in g.data.rules["market"]["offers"]:
		cheapest = mini(cheapest, g.market_cost(p, o))
	if _funds_spare(g) < cheapest:
		return cells
	for c in g.board:
		if g.tile_type(c) == str(g.data.rules["market"]["tile"]) and c != p["pos"]:
			cells.append(c)
	return cells


static func _give_die_action(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	## 남는 주사위를 동료에게: 감옥의 동료(탈옥에 씀)가 먼저, 다음은 아직 차례를 안 한 동료. 가장 큰 눈을 준다.
	var best: Dictionary = {}
	var best_score := -1.0
	for a in legal:
		if a["type"] != "give_die":
			continue
		var q: Dictionary = g.players[int(a["target"])]
		var score := float(g.die_value(int(a["die"]))) + (10.0 if q["jailed"] else 0.0)
		if score > best_score:
			best_score = score
			best = a
	return best


static func _buy_scene_now(g: RulesV2) -> bool:
	## 장면 매수: 2막에서 남은 날이 장면 수에 비해 빠듯할 때
	var left := g.scenes.size() - g.scene_index
	return float(g.rounds_left) <= float(left) * ACT2_DAYS_PER_SCENE + float(_funds_cfg(g)["buy_slack_days"])


static func _scene_pay_other(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	## 아이템·폭탄·군자금 바치기: 행동 하나이므로 가장 작은 눈을 낸다 (군자금 매수는 날이 빠듯할 때만)
	var best: Dictionary = {}
	for a in legal:
		if a["type"] == "scene_pay" and a["what"] == "funds" and not _buy_scene_now(g):
			continue
		if a["type"] == "scene_pay" and a["what"] != "die":
			if best.is_empty() or g.die_value(int(a["with"])) < g.die_value(int(best["with"])):
				best = a
	return best


static func _largest(g: RulesV2, p: Dictionary, legal: Array, type: String) -> Dictionary:
	var best: Dictionary = {}
	for a in legal:
		if a["type"] == type and (best.is_empty() or g.die_value(int(a["die"])) > g.die_value(int(best["die"]))):
			best = a
	return best


static func _move_die(g: RulesV2, p: Dictionary, legal: Array, goal: Vector2i) -> Dictionary:
	## 이동 행동의 주사위 고르기. 목표에서 작전 판정을 할 것 같으면 가장 큰 눈은 판정용으로 남긴다.
	## 한 주사위로 닿으면 닿는 것 중 가장 작은 눈, 아니면 남길 것을 뺀 가장 큰 눈 (닿을 때까지 이동 행동을 되풀이).
	var path: Dictionary = g.path_to(p, goal)
	var need: int = int(path["steps"]) if not path["path"].is_empty() else _dist(p["pos"], goal)
	if need <= 0:
		return {}
	var moves := legal.filter(func(a): return a["type"] == "move_die")
	if moves.is_empty():
		return {}
	moves.sort_custom(func(a, b): return g.die_value(int(a["die"])) < g.die_value(int(b["die"])))
	if _check_ahead(g, p, goal) and moves.size() >= 2:
		moves.pop_back()   # 가장 큰 눈은 판정에 남긴다
	var extra: int = int(p["flags"].get("move_extra", 0)) + int(p["move_mod_next"])
	for a in moves:
		if g.move_value(p, int(a["die"])) + extra >= need:
			return a
	return moves.back()


static func _check_ahead(g: RulesV2, p: Dictionary, goal: Vector2i) -> bool:
	## 목표 칸에서 작전 판정(암살 표적 마커, 2막 장면 판정)을 하게 되는가
	if g.act == 2:
		return g.scene_need().has("check_pair") or _scene_has_check(g)
	var m: Dictionary = g.marker_at(goal)
	return not m.is_empty() and str(m["role"]) == "target" and str(g.card_cond(str(m["id"])).get("kind", "")) == "assassinate"


static func _scene_has_check(g: RulesV2) -> bool:
	var stack: Array = [g.current_scene().get("condition", {})]
	while not stack.is_empty():
		var c: Dictionary = stack.pop_back()
		if str(c.get("kind", "")) == "check":
			return true
		stack.append_array(c.get("options", []))
		stack.append_array(c.get("steps", []))
	return false


static func _scene_pay_die(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	## 장면 주사위 합: 남은 합을 한 번에 채우는 가장 작은 눈, 아니면 가장 큰 눈
	var need := int(g.scene_need().get("dice", 0))
	if need <= 0:
		return {}
	var pays := legal.filter(func(a): return a["type"] == "scene_pay" and a["what"] == "die")
	if pays.is_empty():
		return {}
	pays.sort_custom(func(a, b): return g.die_value(int(a["die"])) < g.die_value(int(b["die"])))
	for a in pays:
		if g.die_value(int(a["die"])) >= need:
			return a
	return pays.back()


static func _smallest(g: RulesV2, p: Dictionary, legal: Array, type: String) -> Dictionary:
	var best: Dictionary = {}
	for a in legal:
		if a["type"] == type and (best.is_empty() or g.die_value(int(a["die"])) < g.die_value(int(best["die"]))):
			best = a
	return best


static func _exposure_headroom(g: RulesV2) -> int:
	## 노출이 오르면 경계 단계가 바뀌는 문턱까지 몇 점 남았나 (문턱을 다 넘었으면 최대치까지)
	for t in g.data.rules["exposure"]["thresholds"]:
		if g.exposure < int(t):
			return int(t) - g.exposure
	return int(g.data.rules["exposure"]["max"]) - g.exposure


static func _goal(g: RulesV2, p: Dictionary, policy: Dictionary) -> Vector2i:
	if g.act == 2:
		if _bomb_runner(g, p):
			var supply := []
			for c in g.board:
				if g.tile_has_op(g.tile_type(c), "gain_bomb") and c != p["pos"]:
					supply.append(c)
			if not supply.is_empty():
				return _nearest(p["pos"], supply)
		# 「마지막 장면을 돌파할 때 결행 거점에 있음」 같은 사연: 마지막 장면이면 거점 안으로
		if g.scene_index == g.scenes.size() - 1 and _saga_kind(g, p, "present_at_final"):
			return g.data.bases[g.data.base_index(str(g.launch_info.get("target", "")))]
		var cells := g.scene_place_cells()
		var open := []
		for c in cells:
			if not g.police_on(c):
				open.append(c)
		return _nearest(p["pos"], open) if not open.is_empty() else p["pos"]
	var best: Vector2i = p["pos"]
	var best_score := -1.0
	for t in _mission_targets(g, p):
		var cells: Array = t[0]
		if cells.is_empty():
			continue
		var near: Vector2i = _nearest(p["pos"], cells)
		var path: Dictionary = g.path_to(p, near)
		var distance := int(path["steps"]) if not path["path"].is_empty() else _dist(p["pos"], near)
		var score: float = float(t[1]) / float(1 + distance)
		if score > best_score:
			best_score = score
			best = near
	for q in g.players:
		if q["jailed"] and q["id"] != p["id"] and not g.police_on(q["pos"]):
			var d := _dist(p["pos"], q["pos"])
			if d <= RESCUE_RANGE and RESCUE_VALUE / float(1 + d) > best_score:
				best_score = RESCUE_VALUE / float(1 + d)
				best = q["pos"]
	for t in _saga_targets(g, p):
		var cells: Array = t[0]
		if cells.is_empty():
			continue
		var near: Vector2i = _nearest(p["pos"], cells)
		var score: float = float(t[1]) / float(1 + _dist(p["pos"], near))
		if score > best_score:
			best_score = score
			best = near
	if best_score >= 0.0:
		return best
	return g.data.bases[int(p["id"]) % g.data.bases.size()]


static func _fx_value(effects: Array, w: Dictionary) -> float:
	## 효과 목록의 값 (좋은 것은 +, 벌칙은 −). 가중치는 rules.ai.mission
	var v := 0.0
	for e in effects:
		var n := float(e.get("value", e.get("count", 1)))
		match str(e.get("op", "")):
			"ready": v += n * float(w["ready"])
			"intel": v += n * float(w["intel"])
			"exposure": v -= n * float(w["exposure"])
			"draw_item": v += float(e.get("count", 1)) * float(w["item"])
			"gain_bomb": v += float(e.get("count", 1)) * float(w["bomb"])
			"police_remove", "police_back": v += float(w["police"])
			"threat_peek_bonus", "threat_bury": v += float(w["peek"])
			"grant_once": v += float(w["grant"])
			"discard_item": v -= float(e.get("count", 1)) * float(w["item"])
			"police_dispatch": v -= float(w["police"])
	return v


static func _card_value(g: RulesV2, id: String) -> float:
	## 미션·일제 작전의 가치. 미션은 결행 준비와 보상, 일제 작전은 못 막았을 때의 벌칙 크기(동향 단계 포함). 기한이 짧을수록 높다.
	var w: Dictionary = g.data.rules["ai"]["mission"]
	var card: Dictionary = g.card_def(id)
	var v := 0.0
	if g.data.is_op(id):
		v = -float(w["penalty"]) * (_fx_value(card.get("missed", []), w) + _fx_value(g._trend_penalty(), w))
		v += _fx_value(g.data.rules["ops"]["block"], w)
	else:
		v = float(card.get("ready", 0)) * float(w["ready"]) + _fx_value(card.get("rewards", []), w)
		var b = card.get("bonus")
		if typeof(b) == TYPE_DICTIONARY:
			v += 0.5 * _fx_value(b.get("reward", []), w)
		v -= 0.5 * float(w["penalty"]) * _fx_value(card.get("missed", []), w)
	var days := g.card_days_left(id)
	if days > 0:
		v *= 1.0 + float(w["urgent"]) / float(days)
	return maxf(v, 0.3)


static func _target_chance(g: RulesV2, p: Dictionary, cond: Dictionary, informed: bool) -> float:
	## 내 가장 큰 눈으로 표적 판정에 성공할 확률
	var best := 1
	for i in g.my_dice(p["id"]):
		best = maxi(best, g.die_value(i))
	var bonus := g.stat(p, str(cond["check"]) + "_bonus") + (int(cond.get("informed_bonus", 0)) if informed else 0)
	return g.check_chance({"target": int(cond["target"]), "bonus": bonus}, best)


static func _mission_targets(g: RulesV2, p: Dictionary) -> Array:
	## 미션·일제 작전을 하러 갈 칸 후보: [[칸들, 가치]]. 카드 id는 보지 않고 condition.kind와 마커 역할로만 고른다.
	## 연락은 받기 → 주기 두 걸음으로 경로를 짜고, 협동은 요원마다 맡을 자리를 나눠 함께 움직인다.
	var out := []
	var ids := []
	ids.append_array(g.mission_row)
	ids.append_array(g.op_row)
	for id in ids:
		var cond: Dictionary = g.card_cond(str(id))
		var st: Dictionary = g.mission_state.get(id, {})
		var value := _card_value(g, str(id))
		var cells := []
		match str(cond.get("kind", "")):
			"assassinate":
				var targets: Array = g.markers_of(str(id), "target")
				if targets.is_empty():
					continue
				var informers: Array = g.markers_of(str(id), "informer")
				if not informers.is_empty() and _dist(p["pos"], informers[0]["pos"]) <= int(g.data.rules["ai"]["mission"]["informer_detour"]):
					cells.append(informers[0]["pos"])   # 정보원에 먼저 들러 표적을 멈추고 판정을 쉽게 한다
				else:
					cells.append(targets[0]["pos"])
				value *= 0.4 + 0.6 * _target_chance(g, p, cond, bool(st.get("informed", false)))
			"infiltrate":
				var bi: int = g.data.base_index(str(cond.get("base", "")))
				if bi >= 0 and g.data.bases[bi] != p["pos"] and not g.police_on(g.data.bases[bi]):
					cells.append(g.data.bases[bi])
			"bomb":
				var spots: Array = g.markers_of(str(id), "target")
				if spots.is_empty():
					continue
				if p["bombs"] > 0:
					cells.append(spots[0]["pos"])
				elif p["bombs"] < g.bomb_slots(p) and g.bomb_supply > 0:
					for c in g.board:
						if g.tile_has_op(g.tile_type(c), "gain_bomb") and c != p["pos"]:
							cells.append(c)   # 폭탄부터 구하러 간다
					value *= 0.7
			"work":
				for m in g.markers_of(str(id), "work"):
					cells.append(m["pos"])
				var useful := false
				for i in g.my_dice(p["id"]):
					if g.work_ok(str(id), g.die_value(i)):
						useful = true
				if not useful:
					value *= 0.3   # 바칠 눈이 없으면 서둘러 가지 않는다
			"contact":
				var holder := int(st.get("holder", -1))
				if holder == p["id"]:
					for m in g.markers_of(str(id), "dropoff"):
						cells.append(m["pos"])
					value *= 1.5
				elif holder < 0:
					for m in g.markers_of(str(id), "pickup"):
						if m["pos"] != p["pos"] and not g.police_on(m["pos"]):
							cells.append(m["pos"])
			"lurk":
				for m in g.markers_of(str(id), "spot"):
					cells.append(m["pos"])
				if g.police.has(p["id"]):
					value *= 0.2   # 쫓기는 요원은 잠복을 못 센다
			"cover_entry", "people", "opposite_edges":
				cells = _coop_cells(g, p, cond)
		if not cells.is_empty():
			out.append([cells, value])
	var mk := _market_targets(g, p)
	if not mk.is_empty():
		out.append([mk, float(_funds_cfg(g)["market_value"])])
	return out


static func _coop_cells(g: RulesV2, p: Dictionary, cond: Dictionary) -> Array:
	## 협동 미션에서 내가 갈 칸 (맡을 자리가 없으면 []): 거점 옆에서 만나기(people), 반대쪽 가장자리(opposite_edges),
	## 가까운 한 명은 거점에 들어가고 그다음 가까운 한 명은 옆 칸에서 망을 본다(cover_entry)
	var out := []
	var live := g.players.filter(func(q): return not q["jailed"])
	if live.size() < 2 or p["jailed"]:
		return out
	match str(cond.get("kind", "")):
		"people":
			var b: Vector2i = g._base_cell(str(cond.get("base", "")))
			var ranked := live.duplicate()
			ranked.sort_custom(func(x, y): return _dist(x["pos"], b) < _dist(y["pos"], b) or (_dist(x["pos"], b) == _dist(y["pos"], b) and x["id"] < y["id"]))
			var need := int(cond.get("count", 2))
			for k in mini(need, ranked.size()):
				if ranked[k]["id"] == p["id"]:
					for d in RulesV2.DIRS:
						var c: Vector2i = b + d
						if g.in_bounds(c) and not c in g.data.bases:
							out.append(c)
		"opposite_edges":
			var order := live.map(func(q): return int(q["id"]))
			order.sort()
			var last := g.data.size - 1
			if p["id"] == order[0]:
				out.append(Vector2i(0, p["pos"].y))
			elif p["id"] == order[1]:
				out.append(Vector2i(last, p["pos"].y))
		"cover_entry":
			var base: Vector2i = g.data.bases[g._nearest_base(p["pos"])]
			var ranked2 := live.duplicate()
			ranked2.sort_custom(func(x, y): return _dist(x["pos"], base) < _dist(y["pos"], base) or (_dist(x["pos"], base) == _dist(y["pos"], base) and x["id"] < y["id"]))
			var rank := -1
			for k in ranked2.size():
				if ranked2[k]["id"] == p["id"]:
					rank = k
			if rank == 0:
				var covered := false
				for q in live:
					if q["id"] != p["id"] and _dist(q["pos"], base) == 1:
						covered = true
				if covered and not g.police_on(base):
					out.append(base)
			if rank >= 0 and rank <= 1 and out.is_empty():
				for d in RulesV2.DIRS:
					var c2: Vector2i = base + d
					if g.in_bounds(c2) and not c2 in g.data.bases:
						out.append(c2)
	return out


static func _bombs_short(g: RulesV2) -> int:
	## 2막에서 지금 장면과 마지막 장면(공개 카드)에 모자란 폭탄 수
	if g.act != 2:
		return 0
	var need := int(g.scene_need().get("bomb", 0))
	if g.scene_index < g.scenes.size() - 1:
		need += int(g.scene_need(g.scenes.size() - 1).get("bomb", 0))
	var have := 0
	for q in g.players:
		have += int(q["bombs"])
	return need - have


static func _bomb_runner(g: RulesV2, p: Dictionary) -> bool:
	## 2막: 지금 장면이나 (공개된) 마지막 장면에 폭탄이 모자라면, 폭탄이 없는 요원 중 보급에 가장 가까운 한 명이 가지러 간다
	if p["bombs"] > 0 or g.bomb_supply <= 0:
		return false
	var short := _bombs_short(g)
	if short <= 0:
		return false
	var supply := []
	for c in g.board:
		if g.tile_has_op(g.tile_type(c), "gain_bomb"):
			supply.append(c)
	if supply.is_empty():
		return false
	var mine := _dist(p["pos"], _nearest(p["pos"], supply))
	var runners := short
	var closer := 0
	for q in g.players:
		if q["id"] == p["id"] or q["jailed"] or q["bombs"] > 0:
			continue
		var d := _dist(q["pos"], _nearest(q["pos"], supply))
		if d < mine or (d == mine and q["id"] < p["id"]):
			closer += 1
	return closer < runners


static func _saga_kind(g: RulesV2, p: Dictionary, kind: String) -> bool:
	if p["saga_done"] != "":
		return false
	for id in g.saga_cards(p["id"]):
		if str(g.data.saga(str(id)).get("condition", {}).get("kind", "")) == kind:
			return true
	return false


static func _saga_targets(g: RulesV2, p: Dictionary) -> Array:
	## 내 사연 조건을 채울 칸 후보: [[칸들], 가치]. 사연 id는 보지 않고 condition.kind로만 고른다.
	var out := []
	if p["saga_done"] != "":
		return out
	var prog: Dictionary = g.saga_progress(p["id"])
	var last := g.data.size - 1
	for id in g.saga_cards(p["id"]):
		var cond: Dictionary = g.data.saga(str(id)).get("condition", {})
		var tr: Dictionary = p["saga_track"].get(id, {})
		var pr: Dictionary = prog.get(id, {"have": 0, "need": 1})
		var value := SAGA_VALUE * (0.6 + 0.4 * float(pr["have"]) / float(maxi(1, pr["need"])))
		var cells := []
		match str(cond.get("kind", "")):
			"end_turn_near_base":
				var b: Vector2i = g.data.bases[g.data.base_index(str(cond.get("base", "")))]
				var r := int(cond.get("range", 0))
				if bool(cond.get("not_chased", false)) and g.police.has(p["id"]):
					continue
				if _dist(p["pos"], b) <= r and p["pos"] != b:
					cells.append(p["pos"])
				else:
					for x in range(b.x - r, b.x + r + 1):
						for y in range(b.y - r, b.y + r + 1):
							var c := Vector2i(x, y)
							if g.in_bounds(c) and c != b and _dist(c, b) <= r and not c in g.data.bases:
								cells.append(c)
			"visit_base_adjacent":
				var done: Array = tr.get("bases", [])
				for i in g.data.bases.size():
					if i in done:
						continue
					for d in RulesV2.DIRS:
						var c: Vector2i = g.data.bases[i] + d
						if g.in_bounds(c) and not c in g.data.bases:
							cells.append(c)
			"touch_edge":
				if int(tr.get("turn", -1)) != p["turns"]:
					var pos: Vector2i = p["pos"]
					for c in [Vector2i(0, pos.y), Vector2i(last, pos.y), Vector2i(pos.x, 0), Vector2i(pos.x, last)]:
						if not c in g.data.bases:
							cells.append(c)
			"end_turn_at_start":
				cells.append(g.data.start)
			"visit_tile", "pass_checkpoint", "hold_items":
				var tile := str(cond.get("tile", ""))
				if cond.get("kind", "") == "pass_checkpoint":
					tile = "check"
				var seen: Array = tr.get("cells", [])
				for c in g.board:
					var hit: bool = g.tile_has_op(g.tile_type(c), "draw_item") if cond.get("kind", "") == "hold_items" else g.tile_type(c) == tile
					if hit and not c in seen and c != p["pos"] and not g.board[c].get("used", false):
						cells.append(c)
			"work_give":
				for m in g.markers:
					if str(m["role"]) == "work" and m["pos"] != p["pos"]:
						cells.append(m["pos"])
			"same_cell_turns", "give_items", "give_dice":
				for q in g.players:
					if q["id"] != p["id"] and not q["jailed"]:
						cells.append(q["pos"])
		if not cells.is_empty():
			out.append([cells, value])
	return out


static func _next_check(g: RulesV2, p: Dictionary) -> bool:
	for c in g.legal_steps(p):
		if g.tile_type(c) == "check":
			return true
	return false


static func _nearest(from: Vector2i, cells: Array) -> Vector2i:
	var best: Vector2i = cells[0]
	for c in cells:
		if _dist(from, c) < _dist(from, best):
			best = c
	return best


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
