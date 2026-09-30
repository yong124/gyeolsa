class_name GameRules
extends RefCounted
## 「광복 IF(결사)」 규칙 엔진. 화면과 분리된 순수 게임 로직.
##
## - 수치·카드·세력은 GameData(data/*.json)에서 읽는다.
## - 모든 조작은 apply(action) 한 곳으로 들어온다. 온라인 멀티는 같은 시드로 엔진을 만들고
##   액션만 주고받으면 된다.
##
## 액션
##   {"type": "roll"}                      이동 주사위 굴리기
##   {"type": "swap_mission"}              미션 교체 (차례 종료)
##   {"type": "escape"}                    탈옥 판정
##   {"type": "step", "to": Vector2i}      한 칸 이동
##   {"type": "end_move"}                  이동 종료
##   {"type": "use_item", "index": int}    아이템 사용
##   {"type": "choose", "value": Variant}  선택지 응답
##   {"type": "ability"}                   세력 능력 (하루 1회, 대상은 선택지로)
##   {"type": "give_item", "index": int, "to": int}  옆 칸 동료에게 아이템 건네기
##   {"type": "decoy", "from": int}        동료를 쫓는 경찰을 내 쪽으로 끌어오기
##
## 단계(phase): start → move → (choice) → 다음 플레이어 start … → over

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var data: GameData
var rng := RandomNumberGenerator.new()

# 설정 (setup 전에 바꾼다)
var use_stations := true
var cards_enabled := true            # false면 이벤트·아이템 타일 효과 없음 (밸런스 검증용)
var rounds_override := {}            # {인원: 작전 일수} 테스트용

# 상태
var board := {}                      # Vector2i -> {"type": String, "used": bool}
var tile_deck: Array = []
var event_deck: Array = []
var event_discard: Array = []
var item_deck: Array = []
var item_discard: Array = []
var mission_deck: Array = []
var mission_discard: Array = []
var occupation_deck: Array = []
var occupation_discard: Array = []
var police_bonus_today := 0           # 일제 동향 "특별 경계령"
var bomb_supply := 0
var players: Array = []              # Array[Dictionary]
var police := {}                     # player_id -> {"pos": Vector2i, "summon_turn": int}
var score := 0
var goal := 10
var rounds_total := 10
var rounds_left := 10
var current := 0
var phase := "start"                 # start | move | choice | over
var steps_left := 0
var item_uses := 0
var last_roll: Array = []
var pending := {}                    # 선택지 (kind, player, prompt, options, then, rest, resume_phase)
var ending := {}

var _evade_ctx := ""
var _check_target := Vector2i(-1, -1)
var _cur_event := ""
var _target := -1                      # 세력 능력의 대상 (플레이어 또는 경찰 주인 id)

var history: Array = []              # 작전 연표 [{"date", "text", "tone"}] (엔딩 보고서용)
var scenario := {}                   # 튜토리얼 등 특수 시나리오 설정 (setup 전에 지정)

var log_lines: Array = []            # 누적 로그
var events: Array = []               # UI 알림 큐 (UI가 꺼내 간다)


# ================================================================ 초기화

func setup(player_defs: Array, seed_value: int = -1, game_data: GameData = null) -> void:
	## player_defs: [{"name": String, "faction": 세력 키, "ai": bool}, ...]
	data = game_data if game_data else GameData.load_default()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	board.clear()
	board[data.start] = {"type": "start", "used": false}
	for b in data.bases:
		board[b] = {"type": "base", "used": false}
	if use_stations:
		for s in data.stations:
			board[s] = {"type": "station", "used": false}
	tile_deck = []
	for t in data.balance["tiles"]:
		for i in int(data.tile(t)["count"]):
			tile_deck.append(t)
	_shuffle(tile_deck)
	event_deck = _expand(data.cards["events"])
	item_deck = _expand(data.cards["items"])
	event_discard = []
	item_discard = []
	mission_deck = _new_missions()
	mission_discard = []
	occupation_deck = _expand(data.cards.get("occupation", [])) if data.balance["occupation"]["enabled"] else []
	occupation_discard = []
	police_bonus_today = 0
	bomb_supply = int(data.balance["bomb_supply"])
	players = []
	for i in player_defs.size():
		var d: Dictionary = player_defs[i]
		players.append({
			"id": i, "name": d.get("name", "요원 %d" % (i + 1)), "faction": d["faction"],
			"ai": d.get("ai", true), "pos": data.start, "started": false, "jailed": false,
			"mission": {}, "items": [], "bombs": 0, "move_mod": 0, "pending_police": false,
			"skip_next": false, "on_tram": false, "turns": 0,
			"ability_day": -1, "decoys": 0,
			"stats": {"missions": 0, "points": 0, "rescues": 0, "jailed": 0, "escapes": 0, "items": 0, "abilities": 0},
		})
	# 시나리오: 타일 더미 맨 위 순서와 첫 미션을 고정한다 (튜토리얼)
	if scenario.has("tile_order_top"):
		# pop_back으로 뽑으므로 거꾸로 붙여야 목록 순서대로 나온다
		var top: Array = scenario["tile_order_top"].duplicate()
		top.reverse()
		for t in top:
			tile_deck.erase(t)
		tile_deck.append_array(top)
	for p in players:
		p["mission"] = _draw_mission()
	var firsts: Array = scenario.get("first_missions", [])
	for i in mini(firsts.size(), players.size()):
		players[i]["mission"] = firsts[i].duplicate()
	for key in scenario.get("start_items", {}):
		players[int(key)]["items"] = scenario["start_items"][key].duplicate()
		for id in players[int(key)]["items"]:
			item_deck.erase(id)
	history.clear()
	police.clear()
	score = 0
	goal = int(scenario.get("goal", data.goal_for(players.size())))
	rounds_total = int(scenario.get("rounds", rounds_override.get(players.size(), data.rounds_for(players.size()))))
	rounds_left = rounds_total
	current = 0
	phase = "start"
	pending = {}
	ending = {}
	log_lines.clear()
	events.clear()
	_log("%s 작전 개시. 8월 15일 전까지 광복수치 %d을(를) 채우십시오." % [date_label(), goal])
	_begin_turn()


func _expand(defs: Array) -> Array:
	var out := []
	for d in defs:
		for i in int(d["count"]):
			out.append(d["id"])
	_shuffle(out)
	return out


func _new_missions() -> Array:
	var out := []
	var order := range(data.bases.size())
	_shuffle(order)
	for m in data.cards["missions"]:
		for i in int(m["count"]):
			var card := {"type": m["type"]}
			if m["type"] == "intel":
				card["base"] = order[i % order.size()]
			out.append(card)
	_shuffle(out)
	return out


# ================================================================ 조회

func cur() -> Dictionary:
	return players[current]


func item_def(id: String) -> Dictionary:
	return data.item(id)


func event_def(id: String) -> Dictionary:
	return data.event(id)


func current_event() -> String:
	return _cur_event


func mission_label(m: Dictionary) -> String:
	var t: String = m.get("type", "")
	if t == "":
		return "-"
	var name: String = data.mission(t).get("name", t)
	if t == "intel":
		return "%s - %s" % [name, data.base_names[m["base"]]]
	return name


func has_item(p: Dictionary, id: String) -> bool:
	return id in p["items"]


func date_label() -> String:
	var d := date_of(rounds_left)
	return "%d월 %d일" % [d.x, d.y]


func date_of(days_left: int) -> Vector2i:
	## 남은 일수 → (월, 일). 0이면 작전 종료일(8월 15일)
	var cal: Dictionary = data.balance["calendar"]
	var day := int(cal["end_day"]) - days_left
	var month := int(cal["end_month"])
	while day < 1:
		month -= 1
		day += [31, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
	return Vector2i(month, day)


func today_occupation() -> String:
	## 오늘 아침 뽑힌 일제 동향 카드 id (없으면 "")
	return occupation_discard[-1] if not occupation_discard.is_empty() else ""


func alert_level() -> int:
	## 경계 단계 1~3. 작전 기간을 셋으로 나눠 날짜가 지날수록 오른다.
	var elapsed := float(rounds_total - rounds_left) / maxf(rounds_total, 1)
	if elapsed < 1.0 / 3.0:
		return 1
	if elapsed < 2.0 / 3.0:
		return 2
	return 3


func police_speed() -> int:
	var pol: Dictionary = data.balance["police"]
	var sp: int = int(pol["speed_by_alert"][alert_level() - 1]) + police_bonus_today
	return maxi(1, sp + data.by_players(pol["speed_mod_by_players"], players.size(), 0))


func tile_type(c: Vector2i) -> String:
	return board[c]["type"] if board.has(c) else ""


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < data.size and c.y < data.size


func occupied_by_other(p: Dictionary, c: Vector2i) -> bool:
	## 다른 요원이 서 있는 칸 (스타트 칸·감옥은 예외). 경찰 칸은 지나갈 수 있다.
	if c == data.start:
		return false
	for q in players:
		if q["id"] != p["id"] and q["started"] and q["pos"] == c and not q["jailed"]:
			return true
	return false


func can_step(p: Dictionary, to: Vector2i) -> bool:
	if phase != "move" or steps_left <= 0 or p["id"] != current:
		return false
	if not in_bounds(to) or absi(to.x - p["pos"].x) + absi(to.y - p["pos"].y) != 1:
		return false
	if occupied_by_other(p, to) and tile_type(to) != "base":
		return false
	if not board.has(to):
		return not tile_deck.is_empty()
	return true  # 검문소는 들어가려 할 때 회피 판정


func legal_steps(p: Dictionary) -> Array:
	var out := []
	for d in DIRS:
		if can_step(p, p["pos"] + d):
			out.append(p["pos"] + d)
	return out


func can_use_item(p: Dictionary, index: int) -> bool:
	if p["id"] != current or not phase in ["start", "move"]:
		return false
	if index < 0 or index >= p["items"].size():
		return false
	if item_uses >= int(data.balance["item_uses_per_turn"]):
		return false
	var use: Dictionary = item_def(p["items"][index]).get("use", {})
	if use.is_empty() or not phase in use.get("phases", []):
		return false
	var req: Dictionary = use.get("requires", {})
	if not req.has("jailed") and p["jailed"]:
		return false
	return _cond_ok(p, req)


func mission_feasible(p: Dictionary) -> bool:
	var t: String = p["mission"]["type"]
	if t == "intel":
		return true
	if t == "bomb" and p["bombs"] == 0 and bomb_supply <= 0:
		return false
	if tile_deck.is_empty():
		var want: String = data.mission(t).get("tile", t)
		if t == "bomb" and p["bombs"] == 0:
			want = "supply"
		for c in board:
			if board[c]["type"] == want:
				return true
		return false
	return true


# ================================================================ 판단 정보 (UI·AI 공용 조회)

func mission_targets(p: Dictionary) -> Dictionary:
	## 지금 미션을 위해 가야 할 칸들 (아직 지도에 없으면 빈 사전)
	var T := {}
	var m: Dictionary = p["mission"]
	var want := ""
	match m.get("type", ""):
		"intel":
			T[data.bases[m["base"]]] = true
		"bomb":
			if p["bombs"] > 0:
				want = "bomb"
			elif bomb_supply > 0:
				want = "supply"
		var t:
			want = data.mission(t).get("tile", "")
	if want != "":
		for c in board:
			if board[c]["type"] == want:
				T[c] = true
	return T


func _stops_here(p: Dictionary, c: Vector2i) -> bool:
	## 이 칸에 들어가면 이동이 끝나는가 (거점, 수행 가능한 미션 타일)
	var t := tile_type(c)
	if t == "base":
		return true
	var m: String = p["mission"].get("type", "")
	if t != "" and t == data.mission(m).get("tile", ""):
		return m != "bomb" or p["bombs"] > 0
	return false


func path_to(p: Dictionary, goal: Vector2i) -> Dictionary:
	## 현재 위치에서 goal까지의 최단 경로 (이동 미리보기용).
	## {"path": [칸...], "steps": int, "reachable": bool, "reason": String, "checks": int, "unknown": int}
	var start: Vector2i = p["pos"]
	var out := {"path": [], "steps": 0, "reachable": false, "reason": "", "checks": 0, "unknown": 0}
	if goal == start or not in_bounds(goal):
		return out
	if occupied_by_other(p, goal) and tile_type(goal) != "base":
		out["reason"] = "다른 요원이 있는 칸"
		return out
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == goal:
			break
		# 이동이 끝나는 칸은 지나갈 수 없다 (목적지로만)
		if c != start and (_stops_here(p, c) or not board.has(c)):
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not in_bounds(n):
				continue
			if occupied_by_other(p, n) and tile_type(n) != "base":
				continue
			if not board.has(n) and tile_deck.is_empty():
				continue
			prev[n] = c
			q.append(n)
	if not prev.has(goal):
		out["reason"] = "갈 수 없는 칸"
		return out
	var path: Array[Vector2i] = [goal]
	while prev[path[-1]] != start:
		path.append(prev[path[-1]])
	path.reverse()
	out["path"] = path
	out["steps"] = path.size()
	for c in path:
		if tile_type(c) == "check":
			out["checks"] += 1
		if not board.has(c):
			out["unknown"] += 1
	out["reachable"] = path.size() <= steps_left
	if not out["reachable"]:
		out["reason"] = "이동력 부족 (%d칸 필요)" % path.size()
	return out


func police_danger(p: Dictionary) -> Dictionary:
	## 이번 차례 끝에 나를 쫓는 경찰이 닿을 수 있는 칸 (깔린 타일 기준)
	var out := {}
	if not police_active(p["id"]) or p["jailed"]:
		return out
	var start: Vector2i = police[p["id"]]["pos"]
	var sp := police_speed()
	var dist := {start: 0}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		out[c] = true
		if dist[c] >= sp:
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if board.has(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return out


func escape_chance(p: Dictionary) -> float:
	var need := data.check("escape") - int(stat(p, "escape_bonus", 0))
	var ok := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b >= need:
				ok += 1
	return ok / 36.0


func evade_chance(p: Dictionary) -> float:
	if flag(p, "evade_auto"):
		return 1.0
	var need := data.check("evade") - int(stat(p, "evade_bonus", 0))
	var ok := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b >= need:
				ok += 1
	return ok / 36.0


# ================================================================ 협력 행동 · 세력 능력 (조회)

func ability_def(p: Dictionary) -> Dictionary:
	return data.faction(p["faction"]).get("active", {})


func can_use_ability(p: Dictionary) -> bool:
	var a := ability_def(p)
	if a.is_empty() or p["id"] != current or p["jailed"]:
		return false
	if not phase in a.get("phases", ["start", "move"]) or p["ability_day"] == rounds_left:
		return false
	return not ability_targets(p).is_empty()


func ability_targets(p: Dictionary) -> Array:
	## 능력을 쓸 수 있는 대상 목록 [{"value": id, "label": String}]
	var a := ability_def(p)
	var out := []
	match a.get("target", ""):
		"ally":
			for q in _allies(p):
				out.append({"value": q["id"], "label": q["name"]})
		"ally_pullable":
			if _free_adjacent(p, p["pos"]) != Vector2i(-1, -1):
				for q in _allies(p):
					if _manhattan(q["pos"], p["pos"]) > 1:
						out.append({"value": q["id"], "label": q["name"]})
		"police_near":
			for pid in police:
				if _manhattan(police[pid]["pos"], p["pos"]) <= int(a.get("range", 1)):
					out.append({"value": pid, "label": "%s을(를) 쫓는 경찰" % players[pid]["name"]})
	return out


func give_options(p: Dictionary) -> Array:
	## 건넬 수 있는 (아이템, 동료) 조합 [{"index", "to", "label"}]
	var coop: Dictionary = data.balance["cooperation"]
	if p["id"] != current or p["jailed"] or not phase in ["start", "move"]:
		return []
	if coop["give_counts_as_item_use"] and item_uses >= int(data.balance["item_uses_per_turn"]):
		return []
	var out := []
	for q in _allies(p):
		if _manhattan(q["pos"], p["pos"]) > int(coop["give_range"]):
			continue
		for i in p["items"].size():
			out.append({"index": i, "to": q["id"],
				"label": "%s → %s" % [item_def(p["items"][i])["name"], q["name"]]})
	return out


func decoy_options(p: Dictionary) -> Array:
	## 미끼로 끌어올 수 있는 경찰 [{"from", "label"}]
	var coop: Dictionary = data.balance["cooperation"]
	if p["id"] != current or p["jailed"] or not phase in ["start", "move"]:
		return []
	if p["decoys"] >= int(coop["decoy_per_turn"]) or police.has(p["id"]):
		return []
	var out := []
	for pid in police:
		if pid != p["id"] and _manhattan(police[pid]["pos"], p["pos"]) <= int(coop["decoy_range"]):
			out.append({"from": pid, "label": "%s을(를) 쫓는 경찰" % players[pid]["name"]})
	return out


func _allies(p: Dictionary) -> Array:
	return players.filter(func(q): return q["id"] != p["id"] and q["started"] and not q["jailed"])


func _free_adjacent(p: Dictionary, c: Vector2i) -> Vector2i:
	## c 옆의 깔린 빈칸 (검문소·거점 제외). 없으면 (-1, -1)
	for d in DIRS:
		var n := c + d
		if board.has(n) and not board[n]["type"] in ["check", "base"] and not occupied_by_other(p, n):
			return n
	return Vector2i(-1, -1)


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# ================================================================ 보정치 (세력 + 지속 아이템)

func stat(p: Dictionary, key: String, base = 0):
	## 세력과 가진 아이템의 modifiers를 합산한다. mode: add(기본) / min / max / set
	var v = base
	var mods: Array = data.faction(p["faction"]).get("modifiers", []).duplicate()
	for id in p["items"]:
		mods.append_array(item_def(id).get("modifiers", []))
	for m in mods:
		if m["stat"] != key or not _cond_ok(p, m.get("when", {})):
			continue
		match m.get("mode", "add"):
			"add": v += int(m["value"])
			"min": v = mini(v, int(m["value"]))
			"max": v = maxi(v, int(m["value"]))
			"set": v = int(m["value"])
	return v


func flag(p: Dictionary, key: String) -> bool:
	return stat(p, key, 0) > 0


func _cond_ok(p: Dictionary, cond: Dictionary) -> bool:
	for k in cond:
		var want = cond[k]
		match k:
			"alert_max":
				if alert_level() > int(want): return false
			"alert_min":
				if alert_level() < int(want): return false
			"jailed":
				if p["jailed"] != bool(want): return false
			"has_my_police":
				if police.has(p["id"]) != bool(want): return false
			"any_police":
				if police.is_empty() == bool(want): return false
			"other_items_min":
				if p["items"].size() - 1 < int(want): return false
	return true


# ================================================================ 액션

func apply(action: Dictionary) -> bool:
	if phase == "over":
		return false
	var p := cur()
	match action.get("type", ""):
		"roll":
			if phase != "start" or p["jailed"]:
				return false
			_roll_move(p)
		"swap_mission":
			if phase != "start" or p["jailed"]:
				return false
			mission_discard.append(p["mission"])
			p["mission"] = _draw_mission()
			_log("%s: 미션을 교체했습니다 → %s" % [p["name"], mission_label(p["mission"])])
			_end_turn()
		"escape":
			if phase != "start" or not p["jailed"]:
				return false
			_try_escape(p)
		"step":
			var to: Vector2i = action["to"]
			if not can_step(p, to):
				return false
			_do_step(p, to)
		"end_move":
			if phase != "move":
				return false
			steps_left = 0
			_resolve_stop(p)
		"use_item":
			var idx: int = action["index"]
			if not can_use_item(p, idx):
				return false
			_use_item(p, idx)
		"choose":
			if phase != "choice" or not _valid_choice(action["value"]):
				return false
			_resolve_choice(action["value"])
		"ability":
			if not can_use_ability(p):
				return false
			var a := ability_def(p)
			_ask(p, "ability_target", "[%s] %s — 대상을 고르세요." % [a["name"], a["desc"]],
				ability_targets(p) + [{"value": -1, "label": "취소"}], "resume")
		"give_item":
			var found := false
			for o in give_options(p):
				if o["index"] == action.get("index") and o["to"] == action.get("to"):
					found = true
			if not found:
				return false
			_give_item(p, int(action["index"]), players[int(action["to"])])
		"decoy":
			var found := false
			for o in decoy_options(p):
				if o["from"] == action.get("from"):
					found = true
			if not found:
				return false
			_decoy(p, int(action["from"]))
		_:
			return false
	return true


# ================================================================ 차례 흐름

func _begin_turn() -> void:
	if phase == "over":
		return
	var p := cur()
	p["turns"] += 1
	p["decoys"] = 0
	item_uses = 0
	steps_left = 0
	last_roll = []
	if not p["started"]:
		p["started"] = true
		p["pos"] = data.start
	_push({"kind": "turn", "player": p["id"]})
	if p["skip_next"]:
		p["skip_next"] = false
		_log("%s: 현지지원 요청으로 이번 차례를 쉽니다." % p["name"])
		_end_turn()
		return
	if p["pending_police"]:
		p["pending_police"] = false
		if not p["jailed"]:
			_log("%s: 불시검문! 경찰이 나타났습니다." % p["name"])
			_summon(p)
	phase = "start"
	if p["on_tram"] and not p["jailed"]:
		p["on_tram"] = false
		var opts := []
		for i in data.stations.size():
			var s: Vector2i = data.stations[i]
			if s == p["pos"] or not occupied_by_other(p, s):
				opts.append({"value": i, "label": "전차 역 %s" % _dir_name(s)})
		_ask(p, "tram_dest", "어느 전차 역에서 내리겠습니까?", opts, "start")


func _end_turn() -> void:
	if phase == "over":
		return
	current = (current + 1) % players.size()
	if current == 0:
		rounds_left -= 1
		if rounds_left <= 0:
			rounds_left = 0
			_game_over("time")
			return
		police_bonus_today = 0
		_push({"kind": "day", "date": date_label(), "alert": alert_level(), "days_left": rounds_left,
			"police_speed": police_speed()})
		_log("── %s (경계 %d단계) ──" % [date_label(), alert_level()])
		_draw_occupation()
		if phase == "over":
			return
	phase = "start"
	_begin_turn()


func _post_move(p: Dictionary) -> void:
	## 이동과 도착 효과가 모두 끝난 뒤: 경찰 이동 → 차례 종료
	if phase == "over":
		return
	_police_act(p)
	_end_turn()


func _continue(p: Dictionary, then: String) -> void:
	match then:
		"post_move": _post_move(p)
		"end_turn": _end_turn()
		"after_step": _after_step(p)
		_: pass  # "resume"/"start": 원래 단계로 돌아가 계속 진행


func _dir_name(s: Vector2i) -> String:
	if s.y == 0: return "(북)"
	if s.y == data.size - 1: return "(남)"
	if s.x == 0: return "(서)"
	return "(동)"


# ================================================================ 이동

func _roll_move(p: Dictionary) -> void:
	var d := rng.randi_range(1, 6)
	last_roll = [d]
	var steps: int = maxi(d, stat(p, "move_min", 0)) + stat(p, "move_bonus", 0) + p["move_mod"]
	p["move_mod"] = 0
	steps_left = maxi(steps, 0)
	phase = "move"
	_push({"kind": "dice", "what": "이동", "dice": [d], "result": steps_left})
	_log("%s: 주사위 %d → 이동 %d칸" % [p["name"], d, steps_left])
	if steps_left == 0:
		_resolve_stop(p)


func _do_step(p: Dictionary, to: Vector2i) -> void:
	if not board.has(to):
		var t: String = tile_deck.pop_back()
		board[to] = {"type": t, "used": false}
		_push({"kind": "reveal", "pos": to, "tile": t})
		if t == "check":
			_log("%s: 검문소가 나타났습니다! 이동이 끝납니다." % p["name"])
			steps_left = 0
			_resolve_stop(p)
			return
	if board[to]["type"] == "check":
		_check_target = to
		_log("%s: 검문소 통과를 시도합니다." % p["name"])
		_begin_evade(p, "checkpoint")
		return
	_arrive(p, to)


func _arrive(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to})
	steps_left -= 1
	var t: String = board[to]["type"]
	if t == "base":
		_enter_base(p)
		return
	if _try_mission(p):
		return
	if t == "station":
		_ask(p, "tram_ride", "전차에 타겠습니까? (이동 종료, 다음 차례에 원하는 역에서 출발)",
			[{"value": true, "label": "탑승"}, {"value": false, "label": "지나가기"}], "after_step")
		return
	_after_step(p)


func _after_step(p: Dictionary) -> void:
	if phase == "over":
		return
	if steps_left <= 0:
		_resolve_stop(p)
	else:
		phase = "move"


func _enter_base(p: Dictionary) -> void:
	var bi := data.bases.find(p["pos"])
	_log("%s: %s에 들어갔습니다. 이동이 끝납니다." % [p["name"], data.base_names[bi]])
	var rescued_summon: bool = data.balance["police"]["rescued_player_summons"]
	for q in players:
		if q["jailed"] and q["pos"] == p["pos"] and q["id"] != p["id"]:
			q["jailed"] = false
			_log("%s: %s을(를) 구출했습니다!" % [p["name"], q["name"]])
			p["stats"]["rescues"] += 1
			_record("%s — %s 구출" % [p["name"], q["name"]], "good")
			_banner("%s 구출!" % q["name"], "good", p)
			if rescued_summon:
				_summon(q)
	var m: Dictionary = p["mission"]
	if m.get("type") == "intel" and m["base"] == bi:
		_log("%s: 정보탈취 성공!" % p["name"])
		_banner("정보탈취 성공!", "good", p)
		_finish_mission(p)
		if phase == "over":
			return
	if flag(p, "base_no_police"):
		_log("%s: 위장 신분증 덕분에 경찰이 오지 않았습니다." % p["name"])
	else:
		_summon(p)
	_post_move(p)


func _resolve_stop(p: Dictionary) -> void:
	## 이동을 마친 칸의 효과
	if phase == "over":
		return
	var tile: Dictionary = board.get(p["pos"], {})
	var t: String = tile.get("type", "")
	if t in ["event", "item"] and not tile["used"]:
		tile["used"] = true
		if cards_enabled:
			if t == "event":
				_draw_event(p)
				return
			if _draw_item(p, "post_move"):
				return
	elif t == "supply" and bomb_supply > 0 and p["bombs"] == 0:
		bomb_supply -= 1
		p["bombs"] = 1
		_log("%s: 보급 타일에서 폭탄을 얻었습니다." % p["name"])
		_push({"kind": "card", "deck": "item", "id": "bomb", "player": p["id"]})
	_post_move(p)


# ================================================================ 미션 · 판정

func _try_mission(p: Dictionary) -> bool:
	## 방금 들어간 칸에서 미션을 수행했으면 true (이동 종료)
	var t := tile_type(p["pos"])
	var m: String = p["mission"].get("type", "")
	if t != data.mission(m).get("tile", ""):
		return false
	match m:
		"assassin":
			_do_assassin(p)
		"sabotage":
			_log("%s: 방해작전 개시! 회피 판정을 합니다." % p["name"])
			_begin_evade(p, "sabotage")
		"bomb":
			if p["bombs"] == 0:
				return false
			p["bombs"] -= 1
			_log("%s: 폭파공작 성공!" % p["name"])
			_banner("폭파공작 성공!", "good", p)
			_finish_mission(p)
			if phase == "over":
				return true
			_summon(p)
			_post_move(p)
	return true


func _do_assassin(p: Dictionary) -> void:
	var th: int = stat(p, "assassin_threshold", data.check("assassin"))
	var bonus: int = stat(p, "assassin_bonus", 0)
	var r := _d2()
	var dice := last_roll.duplicate()
	var ok := r + bonus >= th
	var rerolls: int = stat(p, "assassin_rerolls", 0)
	while not ok and rerolls > 0:
		rerolls -= 1
		var r2 := _d2()
		_log("%s: 암살 판정 %d 실패 → 다시 굴림 %d" % [p["name"], r + bonus, r2 + bonus])
		dice = last_roll.duplicate()
		r = r2
		ok = r + bonus >= th
	_push({"kind": "dice", "what": "암살", "dice": dice, "bonus": bonus, "target": th})
	if ok:
		_log("%s: 암살 성공! (%d, 목표 %d 이상)" % [p["name"], r + bonus, th])
		_banner("암살 성공!", "good", p)
		_finish_mission(p)
		if phase == "over":
			return
		_summon(p)
		_post_move(p)
	else:
		_log("%s: 암살 실패 (%d, 목표 %d 이상). 회피 판정을 합니다." % [p["name"], r + bonus, th])
		_banner("암살 실패 — 탈출하라!", "bad", p)
		_begin_evade(p, "assassin")


func _begin_evade(p: Dictionary, ctx: String) -> void:
	_evade_ctx = ctx
	if flag(p, "evade_auto"):
		_log("%s: %s의 은신술로 회피 성공." % [p["name"], data.faction(p["faction"])["name"]])
		_evade_result(p, true)
		return
	if ctx == "assassin" and flag(p, "evade_auto_after_assassin"):
		_log("%s: 먼 거리에서 저격해 무사히 빠져나왔습니다." % p["name"])
		_evade_result(p, true)
		return
	var react := react_item(p, "evade")
	if react != "":
		_ask(p, "react_evade", item_def(react)["react"]["prompt"],
			[{"value": true, "label": "%s 사용" % item_def(react)["name"]}, {"value": false, "label": "주사위로 판정"}],
			"resume")
		pending["item"] = react
		return
	_roll_evade(p)


func _roll_evade(p: Dictionary) -> void:
	var bonus: int = stat(p, "evade_bonus", 0)
	var th := data.check("evade")
	var r := _d2()
	_push({"kind": "dice", "what": "회피", "dice": last_roll, "bonus": bonus, "target": th})
	var ok := r + bonus >= th
	_log("%s: 회피 판정 %d%s → %s" % [p["name"], r, (" %+d" % bonus) if bonus else "", "성공" if ok else "실패"])
	_evade_result(p, ok)


func _evade_result(p: Dictionary, ok: bool) -> void:
	match _evade_ctx:
		"checkpoint":
			phase = "move"
			if ok:
				_log("%s: 검문소를 무사히 통과했습니다." % p["name"])
				_banner("검문소 통과", "info", p)
				_arrive(p, _check_target)
			else:
				_log("%s: 검문에 걸렸습니다! 이동이 끝납니다." % p["name"])
				_banner("검문에 걸렸다!", "bad", p)
				_summon(p)
				steps_left = 0
				_resolve_stop(p)
			return
		"assassin":
			if ok:
				_summon(p)
			else:
				_jail(p)
		"sabotage":
			if ok:
				_log("%s: 방해작전 성공!" % p["name"])
				_banner("방해작전 성공!", "good", p)
				_finish_mission(p)
				if phase == "over":
					return
			else:
				_log("%s: 방해작전 실패." % p["name"])
				_banner("방해작전 실패", "bad", p)
				_summon(p)
	_post_move(p)


func _try_escape(p: Dictionary) -> void:
	var r := _d2()
	var bonus: int = stat(p, "escape_bonus", 0)
	var th := data.check("escape")
	_push({"kind": "dice", "what": "탈옥", "dice": last_roll, "bonus": bonus, "target": th})
	if r + bonus >= th:
		_log("%s: 탈옥 성공! (%d%s)" % [p["name"], r, (" %+d" % bonus) if bonus else ""])
		p["stats"]["escapes"] += 1
		_banner("탈옥 성공!", "good", p)
		p["jailed"] = false
		_summon(p)
	else:
		_log("%s: 탈옥 실패 (%d%s)" % [p["name"], r, (" %+d" % bonus) if bonus else ""])
	_end_turn()


func _draw_mission() -> Dictionary:
	if mission_deck.is_empty():
		mission_deck = mission_discard
		mission_discard = []
		_shuffle(mission_deck)
		if mission_deck.is_empty():
			mission_deck = _new_missions()
	return mission_deck.pop_back()


func _finish_mission(p: Dictionary) -> void:
	var pts := int(data.mission(p["mission"]["type"]).get("reward", 1))
	p["stats"]["missions"] += 1
	p["stats"]["points"] += pts
	_record("%s — %s 성공 (광복 +%d)" % [p["name"], mission_label(p["mission"]), pts], "good")
	mission_discard.append(p["mission"])
	p["mission"] = _draw_mission()
	_add_score(p, pts)
	if phase != "over":
		_log("%s의 새 미션: %s" % [p["name"], mission_label(p["mission"])])


func _add_score(p: Dictionary, pts: int) -> void:
	score = mini(goal, score + pts)
	_push({"kind": "score", "score": score, "player": p["id"]})
	_log("광복 +%d → 광복수치 %d / %d" % [pts, score, goal])
	if score >= goal:
		_game_over("goal")


func _game_over(reason: String) -> void:
	phase = "over"
	pending = {}
	ending = data.ending_for(score, goal)
	ending["reason"] = reason
	_record("작전 종료 — %s" % ending["name"], "good" if ending["id"] == "victory" else "info")
	_log("작전 종료 (%s). 최종 광복수치 %d → %s" % ["목표 달성" if reason == "goal" else "8월 15일", score, ending["name"]])
	_push({"kind": "over"})


# ================================================================ 카드

func _draw_from(deck: Array, discard: Array) -> String:
	if deck.is_empty():
		deck.append_array(discard)
		discard.clear()
		_shuffle(deck)
	return deck.pop_back() if not deck.is_empty() else ""


func _draw_item(p: Dictionary, then: String) -> bool:
	## 아이템 1장. 소지 한도를 넘어 버릴 카드를 물었으면 true
	var id := _draw_from(item_deck, item_discard)
	if id == "":
		_log("아이템 카드가 모두 떨어졌습니다.")
		return false
	_log("%s: 아이템 [%s] 획득" % [p["name"], item_def(id)["name"]])
	_push({"kind": "card", "deck": "item", "id": id, "player": p["id"]})
	p["items"].append(id)
	if p["items"].size() > int(data.balance["hand_limit"]):
		_ask_discard(p, "아이템은 %d장까지 가질 수 있습니다. 버릴 카드를 고르세요." % data.balance["hand_limit"], then)
		return true
	return false


func _draw_event(p: Dictionary) -> void:
	_cur_event = _draw_from(event_deck, event_discard)
	if _cur_event == "":
		_post_move(p)
		return
	var e := event_def(_cur_event)
	_log("%s: 이벤트 [%s] - %s" % [p["name"], e["name"], e["effect_text"]])
	_push({"kind": "card", "deck": "event", "id": _cur_event, "player": p["id"]})
	var react := react_item(p, "event")
	if react != "":
		_ask(p, "react_event", "[%s] %s" % [e["name"], item_def(react)["react"]["prompt"]],
			[{"value": true, "label": "%s 사용" % item_def(react)["name"]}, {"value": false, "label": "그대로 진행"}],
			"post_move")
		pending["item"] = react
		return
	_apply_event(p)


func _apply_event(p: Dictionary) -> void:
	event_discard.append(_cur_event)
	_run_effects(p, event_def(_cur_event).get("effects", []), "post_move")


func react_item(p: Dictionary, trigger: String) -> String:
	for id in p["items"]:
		if item_def(id).get("react", {}).get("trigger", "") == trigger:
			return id
	return ""


func _use_item(p: Dictionary, idx: int) -> void:
	var id: String = p["items"][idx]
	var use: Dictionary = item_def(id)["use"]
	item_uses += 1
	_log("%s: [%s] 사용" % [p["name"], item_def(id)["name"]])
	p["stats"]["items"] += 1
	_push({"kind": "item_used", "id": id, "player": p["id"]})
	var then := "end_turn" if use.get("ends_turn", false) else "resume"
	var keep_idx := idx
	if use.get("consume", false):
		p["items"].remove_at(idx)
		item_discard.append(id)
		keep_idx = -1
	if int(use.get("cost", {}).get("discard_other", 0)) > 0:
		_ask_discard(p, "[%s] 대가로 버릴 아이템을 고르세요." % item_def(id)["name"], then, keep_idx)
		pending["rest"] = use.get("effects", [])
		return
	_run_effects(p, use.get("effects", []), then)


func _ask_discard(p: Dictionary, prompt: String, then: String, exclude: int = -1) -> void:
	var opts := []
	for i in p["items"].size():
		if i != exclude:
			opts.append({"value": i, "label": item_def(p["items"][i])["name"]})
	_ask(p, "discard", prompt, opts, then)


func _discard(p: Dictionary, index: int) -> void:
	var id: String = p["items"][index]
	p["items"].remove_at(index)
	item_discard.append(id)
	_log("%s: [%s]을(를) 버렸습니다." % [p["name"], item_def(id)["name"]])


# ================================================================ 효과 연산 (data의 "op")

func _run_effects(p: Dictionary, effects: Array, then: String) -> void:
	for i in effects.size():
		if phase == "over":
			return
		if _effect(p, effects[i], then):
			pending["rest"] = effects.slice(i + 1)
			return
	_continue(p, then)


func _effect(p: Dictionary, e: Dictionary, then: String) -> bool:
	## 효과 하나를 실행한다. 선택지를 띄워 멈췄으면 true.
	match e["op"]:
		"add_steps":
			steps_left += int(e["value"])
			_log("%s: 이동 %+d (남은 이동 %d)" % [p["name"], e["value"], steps_left])
		"move_mod":
			p["move_mod"] += int(e["value"])
		"remove_my_police":
			if police.erase(p["id"]):
				_log("%s: 추적하던 경찰을 따돌렸습니다." % p["name"])
		"remove_all_police":
			police.clear()
			_log("모든 경찰이 사라졌습니다.")
		"skip_next_turn":
			p["skip_next"] = true
		"police_next_turn":
			p["pending_police"] = true
		"summon_police":
			_summon(p)
		"free_all_jailed":
			for q in players:
				if q["jailed"]:
					q["jailed"] = false
					_log("%s: 혼란을 틈타 탈옥했습니다." % q["name"])
		"escape_jail":
			p["jailed"] = false
			_log("%s: 탈옥했습니다!" % p["name"])
			if e.get("summon", true):
				_summon(p)
		"add_score":
			_add_score(p, int(e["value"]))
		"target_move_mod":
			var q: Dictionary = players[_target]
			q["move_mod"] += int(e["value"])
			_log("%s: 다음 차례 이동 %+d" % [q["name"], e["value"]])
		"remove_target_police":
			if police.erase(_target):
				_log("%s: %s을(를) 쫓던 경찰을 기습해 쓰러뜨렸습니다!" % [p["name"], players[_target]["name"]])
		"pull_target":
			var q: Dictionary = players[_target]
			var cell := _free_adjacent(q, p["pos"])
			if cell.x >= 0:
				var from: Vector2i = q["pos"]
				q["pos"] = cell
				_push({"kind": "move", "player": q["id"], "from": from, "to": cell, "teleport": true})
				_log("%s: %s을(를) 골목길로 안내해 데려왔습니다." % [p["name"], q["name"]])
		"draw_item":
			return _draw_item(p, then)
		"discard_item":
			if p["items"].size() == 1:
				_discard(p, 0)
			elif p["items"].size() > 1:
				_ask_discard(p, "버릴 아이템을 고르세요.", then)
				return true
		_:
			push_error("알 수 없는 효과 연산: %s" % e["op"])
	return false


# ================================================================ 협력 행동 · 일제 동향 (실행)

func _give_item(p: Dictionary, idx: int, q: Dictionary) -> void:
	var id: String = p["items"][idx]
	p["items"].remove_at(idx)
	q["items"].append(id)
	if data.balance["cooperation"]["give_counts_as_item_use"]:
		item_uses += 1
	_log("%s: [%s]을(를) %s에게 건넸습니다." % [p["name"], item_def(id)["name"], q["name"]])
	if q["items"].size() > int(data.balance["hand_limit"]):
		_ask_discard(q, "%s: 아이템이 너무 많습니다. 버릴 카드를 고르세요." % q["name"], "resume")


func _decoy(p: Dictionary, from: int) -> void:
	var pol: Dictionary = police[from]
	police.erase(from)
	# 끌어온 경찰은 곧바로 나를 쫓는다 (이번 차례 끝에 움직임)
	police[p["id"]] = {"pos": pol["pos"], "summon_turn": p["turns"] - 1}
	p["decoys"] += 1
	_log("%s: 일부러 모습을 드러내 %s을(를) 쫓던 경찰을 유인했습니다!" % [p["name"], players[from]["name"]])
	_banner("미끼 작전!", "info", p)
	_push({"kind": "police"})


func _draw_occupation() -> void:
	if not data.balance["occupation"]["enabled"]:
		return
	var id := _draw_from(occupation_deck, occupation_discard)
	if id == "":
		return
	occupation_discard.append(id)
	var card := data.occupation(id)
	_log("[일제 동향] %s - %s" % [card["name"], card["effect_text"]])
	_record("일제 동향: %s" % card["name"], "warn")
	_push({"kind": "card", "deck": "occupation", "id": id, "player": -1})
	for e in card.get("effects", []):
		_world_effect(e)
		if phase == "over":
			return


func _world_effect(e: Dictionary) -> void:
	## 특정 요원이 아닌 판 전체에 걸리는 효과 (일제 동향 덱)
	var active := players.filter(func(q): return q["started"] and not q["jailed"])
	match e["op"]:
		"place_checkpoints":
			var candidates := active.duplicate()
			_shuffle(candidates)
			var placed := 0
			for q in candidates:
				if placed >= int(e["value"]):
					break
				var cells := []
				for d in DIRS:
					var n: Vector2i = q["pos"] + d
					if in_bounds(n) and not board.has(n):
						cells.append(n)
				if not cells.is_empty():
					var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
					board[c] = {"type": "check", "used": false}
					_push({"kind": "reveal", "pos": c, "tile": "check"})
					placed += 1
		"raid_police":
			for k in int(e["value"]):
				var base: Vector2i = data.bases[rng.randi_range(0, data.bases.size() - 1)]
				var best := {}
				for q in active:
					if police.has(q["id"]):
						continue
					if best.is_empty() or _manhattan(q["pos"], base) < _manhattan(best["pos"], base):
						best = q
				if not best.is_empty() and police.size() < int(data.balance["police"]["pieces"]):
					police[best["id"]] = {"pos": base, "summon_turn": best["turns"]}
					_log("%s에서 경찰이 출동해 %s을(를) 쫓습니다!" % [data.base_names[data.bases.find(base)], best["name"]])
		"police_advance":
			for pid in police.keys():
				var q: Dictionary = players[pid]
				if q["jailed"]:
					continue
				var path = tile_path(police[pid]["pos"], q["pos"])
				if path == null:
					continue
				var steps := int(e["value"])
				if path.size() <= steps:
					_log("%s: 순찰에 걸려 체포되었습니다!" % q["name"])
					_jail(q)
				else:
					police[pid]["pos"] = path[steps - 1]
		"all_move_mod":
			for q in players:
				q["move_mod"] += int(e["value"])
		"police_speed_today":
			police_bonus_today += int(e["value"])
		_:
			push_error("알 수 없는 일제 동향 효과: %s" % e["op"])
	_push({"kind": "police"})


# ================================================================ 선택지

func _ask(p: Dictionary, kind: String, prompt: String, options: Array, then: String) -> void:
	pending = {"kind": kind, "player": p["id"], "prompt": prompt, "options": options,
		"then": then, "rest": [], "resume_phase": phase}
	phase = "choice"
	_push({"kind": "choice", "player": p["id"]})


func _valid_choice(value) -> bool:
	for o in pending.get("options", []):
		if o["value"] == value:
			return true
	return false


func _resolve_choice(value) -> void:
	var pd := pending
	pending = {}
	var p: Dictionary = players[pd["player"]]
	phase = pd["resume_phase"]
	match pd["kind"]:
		"discard":
			_discard(p, int(value))
			_run_effects(p, pd["rest"], pd["then"])
		"tram_dest":
			var from: Vector2i = p["pos"]
			p["pos"] = data.stations[int(value)]
			_push({"kind": "move", "player": p["id"], "from": from, "to": p["pos"], "teleport": true})
			_log("%s: 전차를 타고 %s 역에 내렸습니다." % [p["name"], _dir_name(p["pos"])])
		"tram_ride":
			if value:
				p["on_tram"] = true
				_log("%s: 전차에 탔습니다. 다음 차례에 원하는 역에서 출발합니다." % p["name"])
				steps_left = 0
				_post_move(p)
			else:
				_after_step(p)
		"ability_target":
			if int(value) >= 0:
				p["ability_day"] = rounds_left
				p["stats"]["abilities"] += 1
				_target = int(value)
				_log("%s: [%s] 사용" % [p["name"], ability_def(p)["name"]])
				_banner(ability_def(p)["name"], "info", p)
				_push({"kind": "ability", "player": p["id"]})
				_run_effects(p, ability_def(p).get("effects", []), "resume")
		"react_evade":
			if value:
				_consume(p, pd["item"])
				_log("%s: [%s]! 회피 성공." % [p["name"], item_def(pd["item"])["name"]])
				_evade_result(p, true)
			else:
				_roll_evade(p)
		"react_event":
			if value:
				_consume(p, pd["item"])
				event_discard.append(_cur_event)
				_log("%s: [%s]으로 이벤트를 무효로 했습니다." % [p["name"], item_def(pd["item"])["name"]])
				_post_move(p)
			else:
				_apply_event(p)


func _consume(p: Dictionary, id: String) -> void:
	p["items"].erase(id)
	item_discard.append(id)


# ================================================================ 경찰 · 감옥

func _summon(p: Dictionary) -> void:
	if police.has(p["id"]):
		police[p["id"]] = {"pos": p["pos"], "summon_turn": p["turns"]}
		_log("%s: 경찰이 다시 위치를 잡았습니다." % p["name"])
	elif police.size() < int(data.balance["police"]["pieces"]):
		police[p["id"]] = {"pos": p["pos"], "summon_turn": p["turns"]}
		_log("%s: 일본 경찰이 소환되었습니다!" % p["name"])
	_push({"kind": "police"})


func _jail(p: Dictionary) -> void:
	var best: Vector2i = data.bases[0]
	var bd := 999
	for b in data.bases:
		var d: int = absi(b.x - p["pos"].x) + absi(b.y - p["pos"].y)
		if d < bd:
			bd = d
			best = b
	var from: Vector2i = p["pos"]
	p["pos"] = best
	p["jailed"] = true
	p["stats"]["jailed"] += 1
	_record("%s — %s 감옥에 투옥" % [p["name"], data.base_names[data.bases.find(best)]], "bad")
	police.erase(p["id"])
	_banner("%s 투옥!" % p["name"], "bad", p)
	_log("%s: %s 감옥에 투옥되었습니다!" % [p["name"], data.base_names[data.bases.find(best)]])
	_push({"kind": "jail", "player": p["id"], "from": from, "to": best})


func tile_path(a: Vector2i, b: Vector2i) -> Variant:
	## 깔린 타일만 따라가는 a→b 최단 경로 (a 제외). 갈 수 없으면 null.
	if a == b:
		return []
	var prev := {a: a}
	var q: Array[Vector2i] = [a]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not board.has(n):
				continue
			prev[n] = c
			if n == b:
				var path: Array[Vector2i] = [n]
				while prev[path[-1]] != a:
					path.append(prev[path[-1]])
				path.reverse()
				return path
			q.append(n)
	return null


func police_active(pid: int) -> bool:
	return police.has(pid) and players[pid]["turns"] > police[pid]["summon_turn"]


func _police_act(p: Dictionary) -> void:
	if not police_active(p["id"]) or p["jailed"]:
		return
	var pol: Dictionary = police[p["id"]]
	var path = tile_path(pol["pos"], p["pos"])
	if path == null:
		police.erase(p["id"])
		return
	var sp := police_speed()
	if path.size() <= sp:
		pol["pos"] = p["pos"]
		_log("%s: 경찰에게 체포되었습니다!" % p["name"])
		_push({"kind": "catch", "player": p["id"]})
		_jail(p)
		return
	pol["pos"] = path[sp - 1]
	_push({"kind": "police"})
	if path.size() - sp > int(data.balance["police"]["escape_distance"]):
		police.erase(p["id"])
		_log("%s: 경찰을 따돌렸습니다." % p["name"])
		_push({"kind": "police"})


# ================================================================ 저장 · 불러오기

const SAVE_FIELDS := ["use_stations", "cards_enabled", "board", "tile_deck", "event_deck", "event_discard",
	"item_deck", "item_discard", "mission_deck", "mission_discard", "occupation_deck", "occupation_discard",
	"police_bonus_today", "bomb_supply", "players", "police", "score", "goal", "rounds_total", "rounds_left",
	"current", "phase", "steps_left", "item_uses", "last_roll", "pending", "ending", "history", "scenario",
	"_evade_ctx", "_check_target", "_cur_event", "_target", "log_lines"]


func save_state() -> Dictionary:
	## 게임 전체 상태 (난수 상태 포함). FileAccess.store_var로 그대로 저장할 수 있다.
	var out := {"version": 1, "rng_seed": rng.seed, "rng_state": rng.state}
	for f in SAVE_FIELDS:
		out[f] = get(f)
	return out.duplicate(true)


func load_state(st: Dictionary, game_data: GameData = null) -> void:
	data = game_data if game_data else GameData.load_default()
	for f in SAVE_FIELDS:
		if st.has(f):
			set(f, st[f].duplicate(true) if st[f] is Array or st[f] is Dictionary else st[f])
	rng.seed = st["rng_seed"]
	rng.state = st["rng_state"]
	events.clear()


# ================================================================ 유틸

func _d2() -> int:
	var a := rng.randi_range(1, 6)
	var b := rng.randi_range(1, 6)
	last_roll = [a, b]
	return a + b


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _log(s: String) -> void:
	log_lines.append(s)


func _push(e: Dictionary) -> void:
	## UI 알림. 연출용으로 그 시점의 요원·경찰 위치를 함께 담는다.
	var ps := {}
	for q in players:
		ps[q["id"]] = {"pos": q["pos"], "jailed": q["jailed"], "started": q["started"]}
	var pol := {}
	for pid in police:
		pol[pid] = {"pos": police[pid]["pos"], "active": police_active(pid)}
	e["players_snap"] = ps
	e["police_snap"] = pol
	events.append(e)


func _record(text: String, tone: String) -> void:
	history.append({"date": date_label(), "text": text, "tone": tone})


func _banner(text: String, tone: String, p: Dictionary = {}) -> void:
	## 화면 가운데 결과 배너. tone: good / bad / warn / info
	_push({"kind": "banner", "text": text, "tone": tone, "player": p.get("id", -1)})
