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

var actions: Array = []              # 받아들인 액션 전부 (시드 + 이 목록으로 판을 그대로 재생할 수 있다)
var launch_info := {}                 # 결행 선언 {"reason", "days_left", "score", "intel"} (플레이테스트 기록용)
var history: Array = []              # 작전 연표 [{"date", "text", "tone"}] (엔딩 보고서용)
var scenario := {}                   # 튜토리얼 등 특수 시나리오 설정 (setup 전에 지정)

var log_lines: Array = []            # 누적 로그
var events: Array = []               # UI 알림 큐 (UI가 꺼내 간다)
var act := 1                         # 2막 구조: 1 정찰, 2 결행 (기획서 16장)
var exposure := 0                    # 노출 트랙 (1막의 경계 단계를 정한다)
var intel: Array = []                # 거점별 첩보 마커 수
var strike := {}                     # 결행 사건 {"id", "base", "kind", "need", "progress", "threshold", "bonus"}
var undo_steps: Array = []           # 효과 없이 지나간 공개 칸의 이동 경로


# ================================================================ 초기화

static func from_cfg(cfg: Dictionary, game_data: GameData, seed_value := -1) -> GameRules:
	## 새 작전 설정(cfg: defs, difficulty, scenario, seed)으로 판을 만든다.
	## 메뉴에서 시작할 때와 플레이테스트 기록을 재생할 때 같은 방식을 쓴다.
	var g := GameRules.new()
	var defs: Array = cfg["defs"].duplicate(true)
	var diff: int = int(cfg.get("difficulty", 0))
	if diff != 0:
		g.rounds_override = {defs.size(): game_data.rounds_for(defs.size()) + diff}
	var sc: String = cfg.get("scenario", "")
	if sc != "" and sc != "daily":
		g.scenario = game_data.special_op(sc).get("scenario", {}).duplicate(true)
	g.setup(defs, seed_value if seed_value >= 0 else int(cfg.get("seed", -1)), game_data)
	return g


func setup(player_defs: Array, seed_value: int = -1, game_data: GameData = null) -> void:
	## player_defs: [{"name": String, "faction": 세력 키, "ai": bool}, ...]
	data = game_data if game_data else GameData.load_default()
	if seed_value < 0:
		# 무작위 판도 시드를 명시해 둔다 (기록 재생용 · JSON에서도 정확한 32비트 값)
		var r := RandomNumberGenerator.new()
		r.randomize()
		seed_value = r.randi()
	rng.seed = seed_value
	board.clear()
	board[data.start] = {"type": "start", "used": false}
	for b in data.bases:
		board[b] = {"type": "base", "used": false}
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
			"ai": d.get("ai", true), "personality": d.get("personality", ""),
			"pos": data.start, "started": false, "jailed": false,
			"mission": {}, "items": [], "bombs": 0, "move_mod": 0, "pending_police": false,
			"skip_next": false, "turns": 0,
			"ability_day": -1, "decoys": 0, "traitor": false, "informed": false,
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
	# 시나리오: 감옥에서 시작 (특수 작전 "서대문 탈출")
	for idx in scenario.get("start_jailed", []):
		var jp: Dictionary = players[int(idx)]
		jp["started"] = true
		jp["jailed"] = true
		jp["pos"] = data.bases[int(scenario.get("jail_base", 0))]
	history.clear()
	actions.clear()
	launch_info = {}
	police.clear()
	score = 0
	goal = int(scenario.get("goal", data.goal_for(players.size())))
	rounds_total = int(scenario.get("rounds", rounds_override.get(players.size(), data.rounds_for(players.size(), two_act()))))
	rounds_left = rounds_total
	current = 0
	phase = "start"
	pending = {}
	ending = {}
	log_lines.clear()
	events.clear()
	undo_steps.clear()
	act = 1
	exposure = 0
	intel = []
	for b in data.bases:
		intel.append(0)
	strike = {}
	# 시나리오: 1막을 중간부터 시작 (2막 훈련)
	score = int(scenario.get("start_score", 0))
	exposure = int(scenario.get("start_exposure", 0))
	var si: Array = scenario.get("start_intel", [])
	for i in mini(si.size(), intel.size()):
		intel[i] = int(si[i])
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


func rule_on(id: String) -> bool:
	## 규칙 끄기 (scenario.off): 규칙 정돈 실험용. ability, give, decoy, items, events, occupation, exposure, vote
	return not id in scenario.get("off", [])


func two_act() -> bool:
	## 2막 구조를 쓰는 판인가 (튜토리얼·특수 작전은 기존 규칙)
	return bool(data.balance.get("two_act", {}).get("enabled", false)) and bool(scenario.get("two_act", true))


func _ta() -> Dictionary:
	return data.balance.get("two_act", {})


func exposure_max() -> int:
	return int(_ta().get("exposure", {}).get("max", 9))


func launch_min() -> int:
	if scenario.has("launch_min"):
		return int(scenario["launch_min"])
	return data.by_players(_ta().get("launch_min_by_players", {}), players.size(), 5)


func strike_def(id: String) -> Dictionary:
	for d in _ta().get("strikes", []):
		if d["id"] == id:
			return d
	return {}


func strike_for_base(bi: int) -> Dictionary:
	for d in _ta().get("strikes", []):
		if int(d["base"]) == bi:
			return d
	return {}


func strike_base() -> Vector2i:
	return data.bases[int(strike["base"])] if not strike.is_empty() else Vector2i(-1, -1)


func can_strike(p: Dictionary) -> bool:
	## 결행 판정(자물쇠·암살)을 지금 할 수 있는가
	if act != 2 or strike.is_empty() or phase != "start" or p["id"] != current:
		return false
	if not strike["kind"] in ["lockpick", "assassin"] or p["pos"] != strike_base():
		return false
	return strike["kind"] == "lockpick" or not p["jailed"]


func hold_count() -> int:
	var n := 0
	for q in players:
		if q["started"] and not q["jailed"] and not q["traitor"] and q["pos"] == strike_base():
			n += 1
	return n


func traitor_id() -> int:
	## 변절한 요원 (없으면 -1)
	for q in players:
		if q["traitor"]:
			return q["id"]
	return -1


func traitor_mode() -> bool:
	## 이 판의 결행에 변절자가 나오는가 (기획서 16.10: 4인에서만)
	if not two_act():
		return false
	for n in _ta().get("traitor", {}).get("players", []):
		if int(n) == players.size():   # JSON 숫자는 실수로 읽히므로 정수로 비교
			return true
	return false


func inform_options(p: Dictionary) -> Array:
	## 변절자의 밀고: 가까운 요원에게 경찰을 붙인다 [{"target", "label"}]
	if not p["traitor"] or p["id"] != current or p["informed"] or not phase in ["start", "move"]:
		return []
	var rng_max: int = int(_ta().get("traitor", {}).get("inform_range", 3))
	var out := []
	for q in players:
		if q["traitor"] or q["jailed"] or not q["started"] or police.has(q["id"]):
			continue
		if _manhattan(q["pos"], p["pos"]) <= rng_max:
			out.append({"target": q["id"], "label": "%s (%d칸)" % [q["name"], _manhattan(q["pos"], p["pos"])]})
	return out


func alert_level() -> int:
	## 경계 단계 1~3. 2막 구조에서는 노출 트랙으로, 기존 규칙에서는 날짜로 정한다.
	if two_act():
		if act == 2:
			return int(launch_info.get("alert", 3))   # 결행 때의 경계가 2막 내내 이어진다
		var th: Array = _ta()["exposure"]["thresholds"]
		return 1 + int(exposure >= int(th[0])) + int(exposure >= int(th[1]))
	var elapsed := float(rounds_total - rounds_left) / maxf(rounds_total, 1)
	if elapsed < 1.0 / 3.0:
		return 1
	if elapsed < 2.0 / 3.0:
		return 2
	return 3


func police_speed() -> int:
	var pol: Dictionary = data.balance["police"]
	var sp: int = int(pol["speed_by_alert"][alert_level() - 1]) + police_bonus_today + int(scenario.get("police_speed_mod", 0))
	if act == 2 and traitor_id() < 0:
		sp += int(_ta().get("act2_police_bonus", 0))   # 결행 중 총력 경계 (변절자가 있으면 그가 추가 위협이므로 없음)
	return maxi(1, sp + data.by_players(pol["speed_mod_by_players"], players.size(), 0))


func tile_type(c: Vector2i) -> String:
	return board[c]["type"] if board.has(c) else ""


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < data.size and c.y < data.size


func occupied_by_other(p: Dictionary, c: Vector2i) -> bool:
	## 다른 요원이 서 있는 칸 (스타트 칸·감옥·결행 거점은 예외). 경찰 칸은 지나갈 수 있다.
	## 변절자는 요원이 있는 칸에 들어갈 수 있다 (기습 체포).
	if c == data.start or (act == 2 and c == strike_base()) or p.get("traitor", false):
		return false
	for q in players:
		if q["id"] != p["id"] and q["started"] and q["pos"] == c and not q["jailed"]:
			return true
	return false


func can_step(p: Dictionary, to: Vector2i) -> bool:
	if p.get("traitor", false) and not board.has(to):
		return false   # 변절자는 이미 깔린 길로만 다닌다
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


func can_undo_step() -> bool:
	if phase != "move" or undo_steps.is_empty():
		return false
	var last: Dictionary = undo_steps[-1]
	return current == last["player"] and cur()["pos"] == last["to"] and steps_left == last["steps_left"] - 1


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
	var t: String = p["mission"].get("type", "")
	if t == "" or t == "intel":
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
			if not board.has(n) and (tile_deck.is_empty() or p.get("traitor", false)):
				continue   # 새 길을 깔 수 없음 (타일 소진 · 변절자는 깔린 길로만)
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
	if a.is_empty() or p["id"] != current or p["jailed"] or p["traitor"] or not rule_on("ability"):
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
	if p["id"] != current or p["jailed"] or p["traitor"] or not phase in ["start", "move"] or not rule_on("give"):
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
	if p["id"] != current or p["jailed"] or p["traitor"] or not phase in ["start", "move"] or not rule_on("decoy"):
		return []
	if p["decoys"] >= int(coop["decoy_per_turn"]) or police.has(p["id"]):
		return []
	var out := []
	for pid in police:
		if pid != p["id"] and _manhattan(police[pid]["pos"], p["pos"]) <= int(coop["decoy_range"]):
			out.append({"from": pid, "label": "%s을(를) 쫓는 경찰" % players[pid]["name"]})
	return out


func _allies(p: Dictionary) -> Array:
	return players.filter(func(q): return q["id"] != p["id"] and q["started"] and not q["jailed"] and not q["traitor"])


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
	var ok := _apply(action)
	if ok:
		actions.append(action.duplicate(true))
	return ok


func _apply(action: Dictionary) -> bool:
	if phase == "over":
		return false
	var p := cur()
	match action.get("type", ""):
		"roll":
			if phase != "start" or p["jailed"]:
				return false
			_roll_move(p)
		"escape":
			if phase != "start" or not p["jailed"]:
				return false
			_try_escape(p)
		"strike":
			if not can_strike(p):
				return false
			_do_strike(p)
		"inform":
			var ok := false
			for o in inform_options(p):
				if o["target"] == action.get("target"):
					ok = true
			if not ok:
				return false
			var q: Dictionary = players[int(action["target"])]
			p["informed"] = true
			_log("%s: %s의 행방을 헌병대에 밀고했습니다!" % [p["name"], q["name"]])
			_banner("밀고!", "bad", p)
			_summon(q)
		"step":
			var to: Vector2i = action["to"]
			if not can_step(p, to):
				return false
			var from: Vector2i = p["pos"]
			var remaining := steps_left
			var known := board.has(to)
			var event_count := events.size()
			var log_count := log_lines.size()
			_do_step(p, to)
			if known and phase == "move" and p["pos"] == to and steps_left == remaining - 1 \
					and events.size() == event_count + 1 and events[-1]["kind"] == "move" \
					and log_lines.size() == log_count:
				undo_steps.append({"player": current, "from": from, "to": to, "steps_left": remaining})
			else:
				undo_steps.clear()
		"undo_step":
			if not can_undo_step():
				return false
			var last: Dictionary = undo_steps.pop_back()
			p["pos"] = last["from"]
			steps_left = last["steps_left"]
			_push({"kind": "move", "player": p["id"], "from": last["to"], "to": last["from"]})
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
	if not action["type"] in ["step", "undo_step"]:
		undo_steps.clear()
	return true


# ================================================================ 차례 흐름

func _begin_turn() -> void:
	if phase == "over":
		return
	var p := cur()
	p["turns"] += 1
	p["decoys"] = 0
	p["informed"] = false
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
	if act == 1 and not p["jailed"] and not p["traitor"] and not p["mission"].is_empty():
		var tries := 0
		while not mission_feasible(p) and tries < 3:
			tries += 1
			mission_discard.append(p["mission"])
			p["mission"] = _draw_mission()
			_log("%s: 남은 타일로는 이룰 수 없는 미션이라 새 미션을 받았습니다 → %s" % [p["name"], mission_label(p["mission"])])


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
		if two_act() and act == 2 and strike["kind"] == "hold" and hold_count() >= int(strike["need"]):
			_win_strike(players[0])
			return
		if two_act() and act == 1:
			_expose(int(_ta()["exposure"]["per_day"]))
		_push({"kind": "day", "date": date_label(), "alert": alert_level(), "days_left": rounds_left,
			"police_speed": police_speed()})
		_log("── %s (경계 %d단계) ──" % [date_label(), alert_level()])
		if two_act() and act == 2:
			_strike_morning()
		else:
			_draw_occupation()
		if phase == "over":
			return
		if two_act() and act == 1:
			phase = "start"
			if rounds_left <= int(_ta().get("forced_days_left", 2)):
				_log("작전일이 코앞입니다. 더 기다릴 수 없습니다!")
				_launch("forced", "begin_turn")
			elif score >= launch_min() and rule_on("vote"):
				_start_vote()
			if phase == "choice":
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
		"begin_turn":
			phase = "start"
			_begin_turn()
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
	if p["traitor"]:
		_traitor_step(p, to)
		return
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
	var at_strike := act == 2 and not strike.is_empty() and bi == int(strike["base"])
	if at_strike and strike["kind"] == "bomb" and p["bombs"] > 0:
		p["bombs"] -= 1
		strike["progress"] += 1
		_log("%s: 폭탄 설치! (%d / %d)" % [p["name"], strike["progress"], strike["need"]])
		_banner("폭탄 설치 %d / %d" % [strike["progress"], strike["need"]], "good", p)
		_push({"kind": "strike_progress"})
		if int(strike["progress"]) >= int(strike["need"]):
			_win_strike(p)
			return
	if at_strike and strike["kind"] in ["bomb", "hold"]:
		_log("%s: 결행 중인 거점에 숨어들었습니다." % p["name"])
	elif flag(p, "base_no_police"):
		_log("%s: 위장 신분증 덕분에 경찰이 오지 않았습니다." % p["name"])
	else:
		_summon(p)
	_post_move(p)


func _resolve_stop(p: Dictionary) -> void:
	## 이동을 마친 칸의 효과 (변절자는 칸 효과를 받지 않는다)
	if phase == "over":
		return
	if p["traitor"]:
		_post_move(p)
		return
	var tile: Dictionary = board.get(p["pos"], {})
	var t: String = tile.get("type", "")
	if t in ["event", "item"] and not tile["used"]:
		tile["used"] = true
		if cards_enabled and rule_on("events" if t == "event" else "items"):
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
				if two_act() and act == 1:
					_expose(int(_ta()["exposure"]["loud"]))
				_summon(p)
				steps_left = 0
				_resolve_stop(p)
			return
		"assassin", "strike":
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
	var m: Dictionary = p["mission"]
	var pts := int(data.mission(m["type"]).get("reward", 1))
	p["stats"]["missions"] += 1
	p["stats"]["points"] += pts
	_record("%s — %s 성공 (광복 +%d)" % [p["name"], mission_label(m), pts], "good")
	mission_discard.append(m)
	if two_act() and act == 1:
		# 1막: 첩보 마커 (정보탈취는 그 거점, 나머지는 가장 가까운 거점) · 시끄러운 작전은 노출 +1
		var bi: int = int(m["base"]) if m["type"] == "intel" else _nearest_base(p["pos"])
		intel[bi] += 1
		_log("%s: %s의 첩보를 얻었습니다 (첩보 %d)" % [p["name"], data.base_names[bi], intel[bi]])
		_push({"kind": "intel", "base": bi, "player": p["id"]})
		if m["type"] in ["assassin", "bomb"]:
			_expose(int(_ta()["exposure"]["loud"]))
	p["mission"] = {} if act == 2 else _draw_mission()
	_add_score(p, pts)
	if phase != "over" and not p["mission"].is_empty():
		_log("%s의 새 미션: %s" % [p["name"], mission_label(p["mission"])])


func _add_score(p: Dictionary, pts: int) -> void:
	score = mini(goal, score + pts)
	_push({"kind": "score", "score": score, "player": p["id"]})
	_log("광복 +%d → 광복수치 %d / %d" % [pts, score, goal])
	if score >= goal and not two_act():
		_game_over("goal")


func _game_over(reason: String) -> void:
	phase = "over"
	pending = {}
	ending = data.ending_for(score, goal)
	if two_act() and ending["id"] == "victory" and reason != "strike":
		# 2막 구조에서 대성공은 결행 목표를 달성해야만 나온다
		ending = data.text["endings"]["operation"].duplicate()
		ending["id"] = "operation"
	if reason == "strike":
		ending = data.text["endings"]["victory"].duplicate()
		ending["id"] = "victory"
		ending["strike"] = strike["id"]
		ending["text"] = data.text.get("strikes", {}).get(strike["id"], {}).get("ending", ending["text"])
	ending["reason"] = reason
	if traitor_id() >= 0:
		ending["traitor"] = traitor_id()
		ending["traitor_won"] = reason != "strike"
	_record("작전 종료 — %s" % ending["name"], "good" if ending["id"] == "victory" else "info")
	_log("작전 종료 (%s). 최종 광복수치 %d → %s" % ["목표 달성" if reason in ["goal", "strike"] else "8월 15일", score, ending["name"]])
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
	if not data.balance["occupation"]["enabled"] or not rule_on("occupation"):
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
				_dispatch_from(rng.randi_range(0, data.bases.size() - 1))
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
		"exposure":
			_expose(int(e["value"]))
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
		"launch_vote":
			var votes: Array = pd["votes"] + [bool(value)]
			var nxt: int = pd["player"] + 1
			if nxt < players.size():
				_ask(players[nxt], "launch_vote", pd["prompt"], pd["options"], pd["then"])
				pending["votes"] = votes
				pending["resume_phase"] = pd["resume_phase"]
				return
			var yes := votes.count(true)
			_log("결행 투표: 찬성 %d, 반대 %d" % [yes, votes.size() - yes])
			if yes * 2 > votes.size() or (yes * 2 == votes.size() and votes[0]):
				_launch("vote", pd["then"])
				if phase == "choice":
					return
			else:
				_log("결행을 하루 미루고 준비를 계속합니다.")
			_continue(p, pd["then"])
		"strike_target":
			_start_strike(int(value))
			_continue(p, pd["then"])
		"react_event":
			if value:
				_consume(p, pd["item"])
				event_discard.append(_cur_event)
				_log("%s: [%s]으로 이벤트를 무효로 했습니다." % [p["name"], item_def(pd["item"])["name"]])
				_post_move(p)
			else:
				_apply_event(p)


# ================================================================ 2막: 노출 · 결행

func _expose(n: int) -> void:
	## 노출 트랙을 움직인다 (1막에서만)
	if not two_act() or act != 1 or n == 0 or not rule_on("exposure"):
		return
	var before := alert_level()
	exposure = clampi(exposure + n, 0, int(_ta()["exposure"]["max"]))
	_push({"kind": "exposure", "value": exposure})
	if alert_level() > before:
		_log("노출 %d — 경계가 %d단계로 올랐습니다!" % [exposure, alert_level()])
		_banner("경계 %d단계" % alert_level(), "warn")
		_dispatch_from(rng.randi_range(0, data.bases.size() - 1))   # 경계가 오르면 무작위 거점에서 출동
		_push({"kind": "police"})


func _nearest_base(c: Vector2i) -> int:
	var best := 0
	var bd := 999
	for i in data.bases.size():
		var d := _manhattan(c, data.bases[i])
		if d < bd:
			bd = d
			best = i
	return best


func _dispatch_from(bi: int) -> void:
	## 거점 bi에서 경찰이 출동해, 아직 쫓기지 않는 가장 가까운 요원을 쫓는다
	var base: Vector2i = data.bases[bi]
	var best := {}
	for q in players:
		if not q["started"] or q["jailed"] or q["traitor"] or police.has(q["id"]):
			continue
		if best.is_empty() or _manhattan(q["pos"], base) < _manhattan(best["pos"], base):
			best = q
	if not best.is_empty() and police.size() < int(data.balance["police"]["pieces"]):
		police[best["id"]] = {"pos": base, "summon_turn": best["turns"]}
		_log("%s에서 경찰이 출동해 %s을(를) 쫓습니다!" % [data.base_names[bi], best["name"]])


func _start_vote() -> void:
	## 매일 아침 결행 투표 (0번부터 차례로 한 표씩). 과반 찬성이면 결행, 동수면 0번(방장)의 표를 따른다.
	var top := 0
	for i in intel.size():
		if intel[i] > intel[top]:
			top = i
	var sd := strike_for_base(top)
	var name: String = data.text.get("strikes", {}).get(sd.get("id", ""), {}).get("name", "")
	var prompt := "결행하시겠습니까? 목표: %s — %s (첩보 %d) · 결행 준비 %d · 경계 %d단계 · 남은 %d일" % [
		data.base_names[top], name, intel[top], score, alert_level(), rounds_left]
	_ask(players[0], "launch_vote", prompt,
		[{"value": true, "label": "결행한다"}, {"value": false, "label": "하루 더 준비한다"}], "begin_turn")
	pending["votes"] = []


func _launch(reason: String, then: String) -> void:
	## 결행 선언: 첩보가 가장 많은 거점이 목표. 동수면 방장이 고른다.
	launch_info = {"reason": reason, "days_left": rounds_left, "score": score, "intel": intel.duplicate(),
		"exposure": exposure, "alert": alert_level()}
	act = 2
	var best := -1
	for v in intel:
		best = maxi(best, int(v))
	var tied := []
	for i in intel.size():
		if int(intel[i]) == best:
			tied.append(i)
	_record("결행 선언 (%s)" % {"vote": "투표", "forced": "작전일 임박"}.get(reason, reason), "good")
	if tied.size() == 1:
		_start_strike(tied[0])
		return
	var opts := []
	for i in tied:
		var sd := strike_for_base(i)
		opts.append({"value": i, "label": "%s — %s" % [data.base_names[i], data.text.get("strikes", {}).get(sd.get("id", ""), {}).get("name", "")]})
	_ask(players[0], "strike_target", "첩보가 같은 거점이 여럿입니다. 어디를 결행할까요?", opts, then)


func _start_strike(bi: int) -> void:
	var d := strike_for_base(bi)
	if traitor_mode() and traitor_id() < 0:
		_turn_traitor()
	var n := players.size() - (1 if traitor_id() >= 0 else 0)   # 결행에 나서는 요원 수
	var iv: int = int(intel[bi])
	var step: int = maxi(1, int(d.get("intel_step", 1)))
	strike = {"id": d["id"], "base": bi, "kind": d["kind"], "progress": 0, "need": 1, "threshold": 0, "bonus": 0}
	match d["kind"]:
		"assassin":
			strike["need"] = int(d["need"])
			strike["threshold"] = maxi(int(d["min_threshold"]), int(d["threshold"]) - iv / step)
		"bomb":
			strike["need"] = maxi(int(d["min_need"]), int(d["need"]) - iv / step)
			bomb_supply += int(strike["need"]) + 1   # 결행용 폭탄 보충 (하나 여유)
		"lockpick":
			strike["need"] = int(d["need"])
			strike["threshold"] = int(d["threshold"])
			strike["bonus"] = mini(int(d["max_bonus"]), iv / step)
		"hold":
			strike["need"] = mini(n, maxi(int(d["min_need"]), (n - 1) - iv / step))
	# 경계가 높을 때 결행하면 거점 경비가 삼엄하다: 판정 목표 +(경계-1), 경계 3이면 필요 횟수 +1
	var pen: int = alert_level() - 1 if two_act() else 0
	strike["alert"] = alert_level()
	match d["kind"]:
		"assassin", "lockpick":
			strike["threshold"] = mini(12, int(strike["threshold"]) + pen)
		"bomb":
			strike["need"] = int(strike["need"]) + (1 if pen >= 2 else 0)
		"hold":
			strike["need"] = mini(n, int(strike["need"]) + (1 if pen >= 2 else 0))
	if scenario.has("strike_need"):
		strike["need"] = int(scenario["strike_need"])   # 훈련용
	var info: Dictionary = data.text.get("strikes", {}).get(d["id"], {})
	_log("결행! %s — %s" % [data.base_names[bi], info.get("name", "")])
	_push({"kind": "card", "deck": "strike", "id": d["id"], "player": -1})
	_banner("결행! %s" % info.get("name", ""), "good")


func strike_goal_text() -> String:
	if strike.is_empty():
		return ""
	var info: Dictionary = data.text.get("strikes", {}).get(strike["id"], {})
	return str(info.get("goal", "")).format({"need": strike["need"], "threshold": strike["threshold"], "bonus": strike["bonus"]})


func _strike_morning() -> void:
	## 2막의 아침: 일제 동향 대신 결행 거점에서 경찰이 출동한다
	var n := 2 if strike["kind"] == "hold" else 1
	for k in n:
		_dispatch_from(int(strike["base"]))
	if strike["kind"] == "bomb":
		police_bonus_today += 1
	_push({"kind": "police"})


func _do_strike(p: Dictionary) -> void:
	## 결행 판정 (형무소 자물쇠 / 군영 사령관 암살)
	if strike["kind"] == "lockpick":
		var r := _d2()
		var bonus: int = int(strike["bonus"])
		var th: int = int(strike["threshold"])
		_push({"kind": "dice", "what": "자물쇠", "dice": last_roll, "bonus": bonus, "target": th})
		if r + bonus >= th:
			strike["progress"] += 1
			_log("%s: 옥문 자물쇠를 풀었습니다! (%d / %d)" % [p["name"], strike["progress"], strike["need"]])
			_banner("자물쇠 %d / %d" % [strike["progress"], strike["need"]], "good", p)
			_push({"kind": "strike_progress"})
			if int(strike["progress"]) >= int(strike["need"]):
				_win_strike(p)
				return
		else:
			# 실패하면 소리가 나서 형무소에서 경찰이 출동한다
			_log("%s: 자물쇠를 풀지 못했습니다. 간수가 소리를 들었습니다!" % p["name"])
			_dispatch_from(int(strike["base"]))
			_push({"kind": "police"})
		_end_turn()
		return
	# 사령관 암살
	var th2: int = int(strike["threshold"])
	var bonus2: int = stat(p, "assassin_bonus", 0)
	var r2 := _d2()
	var dice := last_roll.duplicate()
	var ok := r2 + bonus2 >= th2
	var rerolls: int = stat(p, "assassin_rerolls", 0)
	while not ok and rerolls > 0:
		rerolls -= 1
		r2 = _d2()
		dice = last_roll.duplicate()
		ok = r2 + bonus2 >= th2
	_push({"kind": "dice", "what": "사령관 암살", "dice": dice, "bonus": bonus2, "target": th2})
	if ok:
		strike["progress"] += 1
		_log("%s: 사령관 암살 성공! (%d / %d)" % [p["name"], strike["progress"], strike["need"]])
		_banner("암살 %d / %d" % [strike["progress"], strike["need"]], "good", p)
		_push({"kind": "strike_progress"})
		if int(strike["progress"]) >= int(strike["need"]):
			_win_strike(p)
			return
		_summon(p)
		_post_move(p)
	else:
		_log("%s: 사령관 암살 실패. 회피 판정을 합니다." % p["name"])
		_banner("암살 실패 — 탈출하라!", "bad", p)
		_begin_evade(p, "strike")


func _turn_traitor() -> void:
	## 옥중 회유: 가장 많이 투옥된 요원이 변절한다 (같으면 광복 기여가 적은 요원, 그래도 같으면 무작위)
	var cands: Array = players.duplicate()
	_shuffle(cands)
	cands.sort_custom(func(a, b):
		if a["stats"]["jailed"] != b["stats"]["jailed"]:
			return a["stats"]["jailed"] > b["stats"]["jailed"]
		return a["stats"]["points"] < b["stats"]["points"])
	var t: Dictionary = cands[0]
	t["traitor"] = true
	t["jailed"] = false
	t["mission"] = {}
	t["move_mod"] = 0
	t["skip_next"] = false
	bomb_supply += int(t["bombs"])   # 들고 있던 폭탄은 보급으로 돌아간다
	t["bombs"] = 0
	police.erase(t["id"])
	var why := "옥중에서 회유당한" if t["stats"]["jailed"] > 0 else "일제의 협박에 넘어간"
	_log("%s %s이(가) 변절했습니다! 이제 결행을 막으려 합니다." % [why, t["name"]])
	_record("%s 변절" % t["name"], "bad")
	_push({"kind": "traitor", "player": t["id"]})
	_banner("%s 변절!" % t["name"].split(" (")[0], "bad", t)


func _traitor_step(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to})
	steps_left -= 1
	for q in players:
		if q["id"] != p["id"] and q["started"] and not q["jailed"] and q["pos"] == to:
			_traitor_arrest(p, q)
			return
	_after_step(p)


func _traitor_arrest(p: Dictionary, q: Dictionary) -> void:
	## 기습 체포: 요원이 회피 판정에 실패하면 투옥 (광복군의 은신술은 여기서도 통한다)
	_log("%s: %s을(를) 기습했습니다!" % [p["name"], q["name"]])
	_banner("변절자의 기습!", "bad", p)
	var ok := false
	if flag(q, "evade_auto"):
		ok = true
		_log("%s: %s의 은신술로 빠져나왔습니다." % [q["name"], data.faction(q["faction"])["name"]])
	else:
		var bonus: int = stat(q, "evade_bonus", 0)
		var th := data.check("evade")
		var r := _d2()
		_push({"kind": "dice", "what": "회피", "dice": last_roll, "bonus": bonus, "target": th, "player": q["id"]})
		ok = r + bonus >= th
		_log("%s: 회피 판정 %d%s → %s" % [q["name"], r, (" %+d" % bonus) if bonus else "", "성공" if ok else "실패"])
	if not ok:
		p["stats"]["arrests"] = int(p["stats"].get("arrests", 0)) + 1
		_jail(q)
	steps_left = 0
	_post_move(p)


func _win_strike(p: Dictionary) -> void:
	var info: Dictionary = data.text.get("strikes", {}).get(strike["id"], {})
	_record("결행 성공 — %s" % info.get("name", ""), "good")
	_banner("결행 성공!", "good", p)
	_game_over("strike")


func _consume(p: Dictionary, id: String) -> void:
	p["items"].erase(id)
	item_discard.append(id)


# ================================================================ 경찰 · 감옥

func _summon(p: Dictionary) -> void:
	if p["traitor"]:
		return   # 변절자는 일제 편이라 경찰이 쫓지 않는다
	if police.has(p["id"]):
		police[p["id"]] = {"pos": p["pos"], "summon_turn": p["turns"]}
		_log("%s: 경찰이 다시 위치를 잡았습니다." % p["name"])
	elif police.size() < int(data.balance["police"]["pieces"]):
		police[p["id"]] = {"pos": p["pos"], "summon_turn": p["turns"]}
		_log("%s: 일본 경찰이 소환되었습니다!" % p["name"])
	_push({"kind": "police"})


func _jail(p: Dictionary) -> void:
	if p["traitor"]:
		return
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
	if two_act() and act == 1:
		_expose(int(_ta()["exposure"]["loud"]))
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

const SAVE_FIELDS := ["cards_enabled", "board", "tile_deck", "event_deck", "event_discard",
	"item_deck", "item_discard", "mission_deck", "mission_discard", "occupation_deck", "occupation_discard",
	"police_bonus_today", "bomb_supply", "players", "police", "score", "goal", "rounds_total", "rounds_left",
	"current", "phase", "steps_left", "item_uses", "last_roll", "pending", "ending", "history", "scenario",
	"_evade_ctx", "_check_target", "_cur_event", "_target", "log_lines", "undo_steps",
	"act", "exposure", "intel", "strike", "actions", "launch_info"]


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
