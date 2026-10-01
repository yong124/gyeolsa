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
const CHOICE_KINDS := ["launch_vote", "strike_target", "saga_keep", "persuade_look", "ambush_target", "reroll", "react_evade",
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
		var low := 7
		for d in g.team_dice:
			low = mini(low, int(d["value"]))
		if low <= 2:
			for a in legal:
				var actor: Dictionary = g.players[int(a["player"])]
				if a["type"] == "ability":
					for e in g.ability_def(actor).get("effects", []):
						if e.get("op", "") == "team_die_reroll":
							return int(a["player"])
				if a["type"] == "use_item":
					for e in g.item_def(str(actor["items"][int(a["index"])] )).get("effects", []):
						if e.get("op", "") == "team_die_adjust":
							return int(a["player"])
		var chosen := -1
		var farthest := -1
		for p in g.players:
			if not p["jailed"] and not p["skip_dice_tomorrow"] and p["die"] < 0:
				var distance := _dist(p["pos"], _goal(g, p, PERSONA["support"]))
				if distance > farthest:
					farthest = distance
					chosen = int(p["id"])
		if chosen >= 0:
			return chosen
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
			if g.act == 2 and not p["traitor"]:
				score += 3.0
			if p["traitor"]:
				score -= 20.0
			if g.stat(p, "end_move_hop_to_ally") > 0:
				score -= 2.0
			score -= float(p["id"]) * 0.01
			if score > best_score:
				best_score = score
				best = int(p["id"])
		return best
	return int(legal[0].get("player", -1))


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
				var target: String = str(g.launch_target_preview()[0])
				var needed := float(4 + g.alert_level() - 1) * ACT2_DAYS_PER_SCENE * float(policy["vote"])
				# 첩보가 쌓였거나, 2막에 쓸 날이 빠듯해지면 찬성 (기다려도 날만 줄어듦)
				var ready_now := int(g.intel.get(target, 0)) >= 2 or g.ready >= int(g.data.rules["launch_min"]) + 2
				var no_slack := float(g.rounds_left) <= needed + 1.0 or g.rounds_left <= g.rounds_total * 0.55
				var yes := ready_now or no_slack
				score = 10.0 if bool(v) == yes else 0.0
			"strike_target", "intel_base":
				score = float(g.intel.get(str(v), 0)) * 2.0 - float(_dist(p["pos"], g.data.bases[g.data.base_index(str(v))])) * 0.1
			"saga_keep":
				var prog: Dictionary = g.saga_progress(p["id"]).get(str(v), {"have": 0, "need": 1})
				score = float(prog["have"]) / float(maxi(1, prog["need"]))
				var cond: Dictionary = g.data.saga(str(v)).get("condition", {})
				if cond.get("strike", "") == g.launch_info.get("target", ""):
					score += 0.5
			"reroll":
				score = 10.0 if a.get("type") == "use_spare" or str(v) == "grant" else 0.0
			"react_evade": score = 10.0 if bool(v) else 0.0
			"persuade_look":
				var card: Dictionary = g.data.interrogation.get("cards", []).filter(func(c): return c["id"] == g.pending.get("card", "")).front() if not g.data.interrogation.get("cards", []).filter(func(c): return c["id"] == g.pending.get("card", "")).is_empty() else {}
				score = 10.0 if bool(v) == bool(card.get("shaken", false)) else 0.0
			"discard": score = -float(g.item_def(str(p["items"][int(v)])).get("ai_value", 3))
			"draw_pick": score = float(g.item_def(str(g.pending.get("cards", [])[int(v)])).get("ai_value", 3))
			"pick_bury": score = 10.0 if bool(v) else 0.0
			"pick_die": score = -float(g.team_dice[int(v)]["value"]) if typeof(v) == TYPE_INT and int(v) < g.team_dice.size() else 0.0
			"pick_value": score = float(v) if typeof(v) == TYPE_INT else 0.0
			"pick_player", "ambush_target":
				if typeof(v) == TYPE_INT and int(v) < g.players.size():
					score = -float(_dist(g.players[int(v)]["pos"], p["pos"]))
			"pick_cell", "hop":
				if v is Vector2i:
					score = -float(_dist(v, _goal(g, p, policy)))
			"pick_tile":
				if int(g.scene_need().get("bomb", 0)) > 0 and str(v) == "supply":
					score = 3.0
				elif int(g.scene_need().get("item", 0)) > 0 and str(v) == "item":
					score = 2.0
				else:
					score = 1.0 if str(v) == "item" else 0.0
			"effect_choice": score = float(g.pending.get("effects", [])[int(v)].size()) if typeof(v) == TYPE_INT else 0.0
			_:
				if typeof(v) == TYPE_BOOL:
					score = 1.0 if bool(v) else 0.0
		if score > best_score:
			best_score = score
			best = a
	return best


static func _plan(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	var low := 7
	for d in g.team_dice:
		low = mini(low, int(d["value"]))
	if low <= 2:
		for a in legal:
			if a["type"] == "ability":
				for e in g.ability_def(p).get("effects", []):
					if e.get("op", "") == "team_die_reroll":
						return a
			if a["type"] == "use_item":
				for e in g.item_def(str(p["items"][int(a["index"])] )).get("effects", []):
					if e.get("op", "") == "team_die_adjust":
						return a
	if p["die"] < 0 and not p["jailed"] and not p["skip_dice_tomorrow"]:
		var best: Dictionary = {}
		var best_score := -1.0e20
		var need := _dist(p["pos"], _goal(g, p, PERSONA["support"]))
		for a in legal:
			if a["type"] != "take_die":
				continue
			var raw := int(g.team_dice[int(a["die"])]["value"])
			var effective := maxi(raw, g.stat(p, "move_min3"))
			var score := float(mini(effective, need)) * 4.0 - float(maxi(0, effective - need)) * 0.1
			if g.stat(p, "move_min3") > 0:
				score -= float(raw) * 0.3
			for id in g.saga_cards(p["id"]):
				var cond: Dictionary = g.data.saga(str(id)).get("condition", {})
				if cond.get("kind", "") == "take_die" and raw == int(cond.get("value", -1)):
					score += 0.7
				if cond.get("kind", "") == "take_lowest_die" and raw == low:
					score += 0.7
			if score > best_score:
				best_score = score
				best = a
		if not best.is_empty():
			return best
	if g.act == 2 and not p["jailed"] and not p["traitor"]:
		var needed := int(g.scene_need().get("dice", 0))
		if needed > 0 and _dist(p["pos"], _goal(g, p, PERSONA["support"])) <= maxi(3, p["die"]):
			var carry: Dictionary = {}
			for a in legal:
				if a["type"] == "carry_die" and (carry.is_empty() or int(g.team_dice[int(a["die"])]["value"]) > int(g.team_dice[int(carry["die"])]["value"])):
					carry = a
			if not carry.is_empty():
				return carry
	var start := _find(legal, "start_day")
	if not start.is_empty():
		return start
	return legal[0]


static func _turn(g: RulesV2, p: Dictionary, legal: Array, policy: Dictionary) -> Dictionary:
	if p["jailed"]:
		var esc := _find(legal, "escape")
		if not esc.is_empty():
			return esc
		return _find(legal, "end_turn")
	if p["traitor"]:
		return _traitor(g, p, legal)
	if g.tile_type(p["pos"]) == "supply" and p["bombs"] < g.bomb_slots(p) and (_bombs_short(g) > 0 or not g.missions_in_row("bomb").is_empty()):
		return _find(legal, "end_move")
	if g.tile_type(p["pos"]) == "item" and not g.board[p["pos"]].get("used", false) and int(g.scene_need().get("item", 0)) > 0:
		return _find(legal, "end_move")
	for a in legal:
		if a["type"] == "scene_pay":
			if a["what"] != "die" or int(g.scene_need().get("dice", 0)) > 0:
				return a
	if g.act == 2:
		var sc := _find(legal, "scene_check")
		if not sc.is_empty():
			var intel := _find(legal, "use_intel")
			if not intel.is_empty() and intel.get("mode") == "check" and g.intel_tokens > 0:
				return intel
			return sc
	for a in legal:
		if a["type"] == "use_spare" and a.get("use") == "persuade" and g.interrogation_count(int(a["target"])) >= 2:
			return a
	if _saga_kind(g, p, "give_items") and p["items"].size() > 0:
		var give := _find(legal, "give_item")
		if not give.is_empty():
			return give
	for a in legal:
		if a["type"] == "ability":
			var effects: Array = g.ability_def(p).get("effects", [])
			for e in effects:
				if e.get("op", "") == "place_tile" and g.act == 2 and int(g.scene_need().get("bomb", 0)) > 0:
					var supply_found := false
					for c in g.board:
						if g.tile_type(c) == "supply":
							supply_found = true
					if not supply_found:
						return a
				if e.get("op", "") == "persuade" and a.has("target") and g.interrogation_count(int(a["target"])) >= 2:
					return a
				if e.get("op", "") == "police_remove" and g.police.has(p["id"]):
					return a
				if e.get("op", "") == "police_push" and g.police.has(p["id"]):
					return a
				if e.get("op", "") == "checkpoint_pass" and _next_check(g, p):
					return a
				if e.get("op", "") == "move_today" and g.steps_left < _dist(p["pos"], _goal(g, p, policy)):
					return a
				if e.get("op", "") == "grant_once" and g.act == 2 and not _find(legal, "scene_check").is_empty():
					return a
	for a in legal:
		if a["type"] == "use_item":
			var it: Dictionary = g.item_def(str(p["items"][int(a["index"])]))
			for e in it.get("effects", []):
				if e.get("op", "") == "police_remove" and g.police.has(p["id"]):
					return a
				if e.get("op", "") == "checkpoint_pass" and _next_check(g, p):
					return a
				if e.get("op", "") == "threat_bury":
					return a
				if e.get("op", "") == "move_today" and g.steps_left < _dist(p["pos"], _goal(g, p, policy)):
					return a
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
	if not best.is_empty() and (best_score > 0.0 or now > 0 and g.steps_left > 0 and _find(legal, "end_move").is_empty()):
		return best
	if now > 0 and g.steps_left == 0:
		for a in legal:
			if a["type"] == "use_spare" and a.get("use") == "move" and int(g.team_dice[int(a["die"])]["value"]) >= mini(now, 3):
				return a
	var end := _find(legal, "end_move")
	if not end.is_empty():
		return end
	return _find(legal, "end_turn")


static func _traitor(g: RulesV2, p: Dictionary, legal: Array) -> Dictionary:
	var target := -1
	var best := 999
	var base := g.data.bases[g.data.base_index(str(g.launch_info.get("target", "")))]
	for q in g.players:
		if q["traitor"] or q["jailed"]:
			continue
		var d := _dist(q["pos"], base)
		if d < best:
			best = d
			target = int(q["id"])
	for a in legal:
		if a["type"] == "inform" and a["target"] == target:
			return a
	if target >= 0:
		var now := _dist(p["pos"], g.players[target]["pos"])
		for a in legal:
			if a["type"] == "step" and _dist(a["to"], g.players[target]["pos"]) < now:
				return a
	return _find(legal, "end_move")


static func _goal(g: RulesV2, p: Dictionary, policy: Dictionary) -> Vector2i:
	if g.act == 2:
		if _bomb_runner(g, p):
			var supply := []
			for c in g.board:
				if g.tile_type(c) == "supply" and c != p["pos"]:
					supply.append(c)
			if not supply.is_empty():
				return _nearest(p["pos"], supply)
		# 「마지막 장면을 돌파할 때 결행 거점에 있음」 같은 사연: 마지막 장면이면 거점 안으로
		if g.scene_index == g.scenes.size() - 1 and _saga_kind(g, p, "present_at_final"):
			return g.data.bases[g.data.base_index(str(g.launch_info.get("target", "")))]
		var cells := g.scene_place_cells()
		var open := []
		for c in cells:
			if not g.occupied_by_other(p, c):
				open.append(c)
		return _nearest(p["pos"], open) if not open.is_empty() else p["pos"]
	var best: Vector2i = p["pos"]
	var best_score := -1.0
	for id in g.mission_row:
		if not g.mission_feasible(str(id)):
			continue
		var m: Dictionary = g.mission_def(str(id))
		var td: Dictionary = g.mission_type_def(str(m.get("type", "")))
		var cond: Dictionary = m.get("condition", td.get("condition", {}))
		if cond.is_empty():
			continue
		var cells := []
		match str(cond.get("kind", "")):
			"enter_base":
				var bi := g.data.base_index(str(m.get("base", "")))
				if bi >= 0:
					if g.data.bases[bi] != p["pos"]:
						cells.append(g.data.bases[bi])
			"check", "deliver_bomb":
				var tile := g.mission_tile(str(m.get("type", "")))
				for c in g.board:
					if g.tile_type(c) == tile and not g.board[c].get("used", false):
						cells.append(c)
			_:
				pass
		if cells.is_empty():
			continue
		var near: Vector2i = _nearest(p["pos"], cells)
		var path: Dictionary = g.path_to(p, near)
		var distance := int(path["steps"]) if not path["path"].is_empty() else _dist(p["pos"], near)
		var value := 3.0 if cond.get("kind", "") == "enter_base" else 2.0
		if g.intel.get(str(m.get("intel", "")), 0) >= 2:
			value -= 0.5
		var score := value / float(1 + distance)
		if cond.get("kind", "") == "enter_base" and g.data.base_index(str(m.get("base", ""))) == int(p["id"]) % g.data.bases.size():
			score += 0.2
		if score > best_score:
			best_score = score
			best = near
	for q in g.players:
		if q["jailed"] and not q["traitor"] and q["id"] != p["id"]:
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


static func _bombs_short(g: RulesV2) -> int:
	## 2막에서 지금 장면과 마지막 장면(공개 카드)에 모자란 폭탄 수
	if g.act != 2:
		return 0
	var need := int(g.scene_need().get("bomb", 0))
	if g.scene_index < g.scenes.size() - 1:
		need += int(g.scene_need(g.scenes.size() - 1).get("bomb", 0))
	var have := 0
	for q in g.players:
		if not q["traitor"]:
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
		if g.tile_type(c) == "supply":
			supply.append(c)
	if supply.is_empty():
		return false
	var mine := _dist(p["pos"], _nearest(p["pos"], supply))
	var runners := short
	var closer := 0
	for q in g.players:
		if q["id"] == p["id"] or q["traitor"] or q["jailed"] or q["bombs"] > 0:
			continue
		var d := _dist(q["pos"], _nearest(q["pos"], supply))
		if d < mine or (d == mine and q["id"] < p["id"]):
			closer += 1
	return closer < runners


static func _saga_kind(g: RulesV2, p: Dictionary, kind: String) -> bool:
	if p["saga_done"] != "" or p["traitor"]:
		return false
	for id in g.saga_cards(p["id"]):
		if str(g.data.saga(str(id)).get("condition", {}).get("kind", "")) == kind:
			return true
	return false


static func _saga_targets(g: RulesV2, p: Dictionary) -> Array:
	## 내 사연 조건을 채울 칸 후보: [[칸들], 가치]. 사연 id는 보지 않고 condition.kind로만 고른다.
	var out := []
	if p["saga_done"] != "" or p["traitor"]:
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
				elif cond.get("kind", "") == "hold_items":
					tile = "item"
				var seen: Array = tr.get("cells", [])
				for c in g.board:
					if g.tile_type(c) == tile and not c in seen and c != p["pos"] and not g.board[c].get("used", false):
						cells.append(c)
			"same_cell_turns", "give_items":
				for q in g.players:
					if q["id"] != p["id"] and not q["jailed"] and not q["traitor"]:
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
