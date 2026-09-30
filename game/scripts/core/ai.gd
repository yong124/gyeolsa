class_name GameAI
extends RefCounted
## AI 동료. 현재 상태를 보고 다음 액션 하나를 돌려준다.

const RESCUE_RANGE := 8


static func decide(g: GameRules) -> Dictionary:
	match g.phase:
		"choice":
			return {"type": "choose", "value": _choose(g, g.players[g.pending["player"]])}
		"start":
			return _start(g, g.cur())
		"move":
			return _move(g, g.cur())
	return {}


# ------------------------------------------------------------------ 차례 시작

static func _start(g: GameRules, p: Dictionary) -> Dictionary:
	if p["jailed"]:
		var idx := _usable_item(g, p, ["pin"])
		return {"type": "use_item", "index": idx} if idx >= 0 else {"type": "escape"}
	if not g.mission_feasible(p):
		return {"type": "swap_mission"}
	if g.can_use_ability(p) and ability_pick(g, p) >= 0:
		return {"type": "ability"}
	var decoy := _decoy_pick(g, p)
	if decoy >= 0:
		return {"type": "decoy", "from": decoy}
	var give := _give_pick(g, p)
	if not give.is_empty():
		return give
	if g.police_active(p["id"]):
		var d := _manhattan(g.police[p["id"]]["pos"], p["pos"])
		if d <= g.police_speed() + 2:
			var idx := _usable_item(g, p, ["bribe"])
			if idx >= 0:
				return {"type": "use_item", "index": idx}
	return {"type": "roll"}


# ------------------------------------------------------------------ 이동

static func _move(g: GameRules, p: Dictionary) -> Dictionary:
	var T := targets(g, p)
	# 보급 타일에서 폭탄을 챙기려고 멈춘다
	if g.tile_type(p["pos"]) == "supply" and p["mission"]["type"] == "bomb" \
			and p["bombs"] == 0 and g.bomb_supply > 0:
		return {"type": "end_move"}
	if not T.is_empty():
		var dist := _bfs_dist(g, p, T)
		var idx := _usable_item(g, p, ["ticket"])
		if idx >= 0 and dist > g.steps_left and dist <= g.steps_left + 3:
			return {"type": "use_item", "index": idx}
	var nxt = plan_step(g, p, T)
	if nxt == null or not g.can_step(p, nxt):
		return {"type": "end_move"}
	return {"type": "step", "to": nxt}


static func targets(g: GameRules, p: Dictionary) -> Dictionary:
	var T := g.mission_targets(p)
	for q in g.players:
		if q["jailed"] and q["id"] != p["id"] and _manhattan(q["pos"], p["pos"]) <= RESCUE_RANGE:
			T[q["pos"]] = true
	return T


static func intent(g: GameRules, p: Dictionary) -> String:
	## 차례를 시작할 때 이 동료가 무엇을 하려는지 한 줄로 (말풍선용)
	if p["jailed"]:
		return "탈옥할 틈을 노린다" if not g.has_item(p, "pin") else "옷핀으로 자물쇠를 연다"
	for q in g.players:
		if q["jailed"] and q["id"] != p["id"] and _manhattan(q["pos"], p["pos"]) <= RESCUE_RANGE:
			return "%s을(를) 구하러 간다!" % q["name"].split(" (")[0]
	if g.police_active(p["id"]) and _manhattan(g.police[p["id"]]["pos"], p["pos"]) <= g.police_speed():
		return "경찰이 바짝 붙었다… 서둘러야 해"
	var m: Dictionary = p["mission"]
	var found := not g.mission_targets(p).is_empty()
	match m.get("type", ""):
		"intel":
			return "%s에서 정보를 빼낸다" % g.data.base_names[m["base"]]
		"assassin":
			return "암살 목표에게 간다" if found else "암살 목표를 찾아 골목을 뒤진다"
		"sabotage":
			return "방해작전 지점으로 간다" if found else "방해작전 지점을 찾는다"
		"bomb":
			if p["bombs"] > 0:
				return "폭탄을 들고 폭파 지점으로" if found else "폭파할 곳을 찾는다"
			return "보급소에서 폭탄을 구한다" if found else "보급소를 찾는다"
	return "경성을 살핀다"


static func _passable(g: GameRules, p: Dictionary, c: Vector2i, T: Dictionary) -> bool:
	if not g.in_bounds(c):
		return false
	if g.occupied_by_other(p, c) and not (T.has(c) and g.tile_type(c) == "base"):
		return false
	if not g.board.has(c):
		return not g.tile_deck.is_empty()
	match g.board[c]["type"]:
		"check":
			# 회피가 확실할 때만 검문소를 뚫고 지나간다
			return g.flag(p, "evade_auto") or g.react_item(p, "evade") != ""
		"base":
			return T.has(c)
	return true


static func plan_step(g: GameRules, p: Dictionary, T: Dictionary) -> Variant:
	## 가장 가까운 목표로 가는 첫 걸음. 목표가 없으면 가장 가까운 미탐색 칸으로.
	var start: Vector2i = p["pos"]
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	var head := 0
	var found = null
	var first_empty = null
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c != start and T.has(c):
			found = c
			break
		if c != start and first_empty == null and not g.board.has(c):
			first_empty = c
		for d in GameRules.DIRS:
			var n: Vector2i = c + d
			if not prev.has(n) and _passable(g, p, n, T):
				prev[n] = c
				q.append(n)
	if found == null and T.has(start):
		# 현재 칸이 목표면 옆 칸으로 나갔다가 다시 들어온다
		for d in GameRules.DIRS:
			var n: Vector2i = start + d
			if g.board.has(n) and _passable(g, p, n, {}) and g.can_step(p, n):
				return n
	var goal = found if found != null else first_empty
	if goal == null:
		return null
	var c: Vector2i = goal
	while prev[c] != start:
		c = prev[c]
	return c


static func _bfs_dist(g: GameRules, p: Dictionary, T: Dictionary) -> int:
	var start: Vector2i = p["pos"]
	var dist := {start: 0}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c != start and T.has(c):
			return dist[c]
		for d in GameRules.DIRS:
			var n: Vector2i = c + d
			if not dist.has(n) and _passable(g, p, n, T):
				dist[n] = dist[c] + 1
				q.append(n)
	return 999


# ------------------------------------------------------------------ 선택지

static func _choose(g: GameRules, p: Dictionary) -> Variant:
	var pd := g.pending
	var opts: Array = pd["options"]
	match pd["kind"]:
		"discard":
			# 가치(ai_value)가 가장 낮은 카드를 버린다
			var best = opts[0]["value"]
			var best_v := 999
			for o in opts:
				var v: int = g.item_def(p["items"][o["value"]]).get("ai_value", 3)
				if v < best_v:
					best_v = v
					best = o["value"]
			return best
		"ability_target":
			return ability_pick(g, p)
		"react_evade":
			return true
		"react_event":
			return bool(g.event_def(g.current_event()).get("bad", false))
		"tram_ride":
			var T := targets(g, p)
			if T.is_empty():
				return false
			var here := _min_dist(p["pos"], T)
			for s in g.data.stations:
				if s != p["pos"] and _min_dist(s, T) + 3 < here - g.steps_left:
					return true
			return false
		"tram_dest":
			var T := targets(g, p)
			var best = opts[0]["value"]
			var bd := 999
			for o in opts:
				var d := _min_dist(g.data.stations[o["value"]], T) if not T.is_empty() else g.rng.randi_range(0, 9)
				if d < bd:
					bd = d
					best = o["value"]
			return best
	return opts[0]["value"]


# ------------------------------------------------------------------ 협력 행동 · 세력 능력

static func ability_pick(g: GameRules, p: Dictionary) -> int:
	## 능력을 쓸 대상. 쓸 가치가 없으면 -1
	var opts := g.ability_targets(p)
	if opts.is_empty():
		return -1
	match g.ability_def(p).get("target", ""):
		"ally":
			# 무전 지원: 목표에서 가장 먼 동료
			var best := -1
			var bd := -1
			for o in opts:
				var q: Dictionary = g.players[o["value"]]
				var d := _min_dist(q["pos"], targets(g, q))
				if d > bd:
					bd = d
					best = o["value"]
			return best
		"police_near":
			# 기습: 내 경찰을 먼저, 없으면 활성 경찰
			for o in opts:
				if o["value"] == p["id"]:
					return o["value"]
			for o in opts:
				if g.police_active(o["value"]):
					return o["value"]
			return opts[0]["value"]
		"ally_pullable":
			# 길 안내: 데려오면 목표에 2칸 이상 가까워지는 동료
			for o in opts:
				var q: Dictionary = g.players[o["value"]]
				var T := targets(g, q)
				if not T.is_empty() and _min_dist(p["pos"], T) + 2 <= _min_dist(q["pos"], T):
					return o["value"]
	return -1


static func _decoy_pick(g: GameRules, p: Dictionary) -> int:
	## 동료가 곧 잡힐 것 같고 나는 안전할 때 경찰을 끌어온다
	for o in g.decoy_options(p):
		var pid: int = o["from"]
		if not g.police_active(pid):
			continue
		var pol: Vector2i = g.police[pid]["pos"]
		var ally_d := _manhattan(pol, g.players[pid]["pos"])
		var my_d := _manhattan(pol, p["pos"])
		if ally_d <= g.police_speed() and my_d >= 2:
			return pid
	return -1


static func _give_pick(g: GameRules, p: Dictionary) -> Dictionary:
	## 손이 꽉 찼고 옆 동료 손이 비었으면 가치가 낮은 아이템을 건넨다
	if p["items"].size() < int(g.data.balance["hand_limit"]):
		return {}
	for o in g.give_options(p):
		if g.players[o["to"]]["items"].is_empty():
			var worst := 0
			for i in p["items"].size():
				if g.item_def(p["items"][i]).get("ai_value", 3) < g.item_def(p["items"][worst]).get("ai_value", 3):
					worst = i
			if o["index"] == worst:
				return {"type": "give_item", "index": o["index"], "to": o["to"]}
	return {}


# ------------------------------------------------------------------ 유틸

static func _usable_item(g: GameRules, p: Dictionary, ids: Array) -> int:
	for i in p["items"].size():
		if p["items"][i] in ids and g.can_use_item(p, i):
			return i
	return -1


static func _min_dist(a: Vector2i, T: Dictionary) -> int:
	var best := 999
	for c in T:
		best = mini(best, _manhattan(a, c))
	return best


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
