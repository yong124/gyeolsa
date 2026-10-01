class_name RulesV2
extends RefCounted
## 「결사 / 광복 IF」 v2 규칙 엔진 (2단계 a: 하루 흐름 · 팀 주사위 · 지도 · 경찰 · 공개 미션).
##
## - 수치·카드·캐릭터는 전부 GameDataV2(data/v2/*.json)에서 읽는다. 카드 id나 캐릭터 id를 코드에 쓰지 않는다.
##   카드 효과는 `op`, 캐릭터·아이템 특성은 `stat` 이름, 미션은 `types[...].condition.kind`로 움직인다.
## - 모든 조작은 apply(action) 한 곳으로. 모든 액션은 "player" 키를 가진다.
##   계획 단계(plan)는 누구나, 낮(turn)은 차례인 요원만, 선택(choice)은 선택을 맡은 요원만 보낼 수 있다.
## - 난수는 전부 rng 하나. 같은 시드 + actions = 같은 판.
## - legal_actions()는 apply가 받아들이는 액션과 정확히 같다.
##
## 액션
##   {"type": "take_die", "player", "die": 인덱스}       (plan) 팀 주사위를 내 이동 주사위로
##   {"type": "release_die", "player"}                    (plan) 가진 주사위를 내려놓음
##   {"type": "start_day", "player"}                      (plan) 하루 시작 (감옥 밖 요원 모두 주사위를 가졌을 때)
##   {"type": "begin_turn", "player"}                     (day) 내 차례를 시작 (자유 순서)
##   {"type": "step", "player", "to": Vector2i}           (turn) 한 칸 이동
##   {"type": "end_move", "player"}                       (turn) 남은 칸을 버리고 멈춤
##   {"type": "escape", "player"}                         (turn, 갇힘) 탈옥 판정
##   {"type": "end_turn", "player"}                       (turn, 갇힘) 차례 포기
##   {"type": "use_item", "player", "index"}              (plan: 아침 아이템 / turn) 아이템 사용
##   {"type": "ability", "player", "target"?}             캐릭터 능력 (하루 1회)
##   {"type": "give_item", "player", "index", "to"}       가까운 동료에게 아이템 건네기
##   {"type": "decoy", "player", "from"}                  동료를 쫓는 경찰을 내 쪽으로
##   {"type": "use_spare", "player", "die", "use": "move"|"escape"|"reroll"}  예비 주사위
##   {"type": "choose", "player", "value"}                (choice) 선택지 응답
##
## 단계(phase): morning(자동) → plan → day ⇄ turn (+ choice) → (밤) → morning … → over

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 1막 효과 op는 모두 이 엔진이 처리한다. 아래는 아직 안 만든 단계의 효과 (로그만 남기는 훅).
## interrogate는 _interrogate(p) 훅을 부른다 (3단계).
const OPS_STAGE3 := ["persuade", "interrogate_discard"]
const OPS_STAGE4 := ["search", "scene_check_mod_today", "threat_flip", "check_or_jail", "refill_supply"]
## 선택 응답을 효과의 인자로 되돌려 주는 pending 종류 (pending["key"]가 인자 이름)
const PICK_KINDS := ["pick_player", "pick_cell", "pick_die", "pick_tile", "pick_item", "pick_value", "pick_bury"]

var data: GameDataV2
var rng := RandomNumberGenerator.new()

# ---- 상태
var players: Array = []
var leader := 0
var day := 1
var rounds_total := 10
var rounds_left := 10
var act := 1
var phase := "morning"
var current := -1
var steps_left := 0
var board := {}                 # Vector2i -> {"type", "used", "flags": []}
var tile_deck: Array = []
var police := {}                # 요원 id -> {"pos", "summon_turn"}
var exposure := 0
var intel := {}                 # 거점 id -> int
var ready := 0
var threat_deck: Array = []
var threat_discard: Array = []
var threat_today := ""
var mission_deck: Array = []
var mission_discard: Array = []
var mission_row: Array = []
var event_deck: Array = []
var event_discard: Array = []
var item_deck: Array = []
var item_discard: Array = []
var bomb_supply := 0
var team_dice: Array = []       # [{"value", "owner", "spare_used"}]
var dice_extra_tomorrow := 0
var dice_reroll_tomorrow := false   # 내일 아침 팀 주사위를 한 번 더 굴림 (team_dice_reroll_all when: tomorrow)
var today := {}
var pending := {}
var launch_info := {}
var ending := {}
var check := {}                 # 지금 진행 중인 판정
var morning_step := 0
var last_roll: Array = []

var actions: Array = []
var events: Array = []
var log_lines: Array = []
var history: Array = []


# ================================================================ 초기화

static func new_game(characters: Array, seed_value := -1) -> RulesV2:
	## characters: 캐릭터 id 목록 (요원 이름은 캐릭터 이름을 쓴다)
	var g := RulesV2.new()
	var gd := GameDataV2.load_default()
	var defs := []
	for c in characters:
		defs.append({"name": gd.character(c).get("name", c), "character": c})
	g.setup(defs, seed_value, gd)
	return g


func setup(player_defs: Array, seed_value: int = -1, game_data: GameDataV2 = null) -> void:
	## player_defs: [{"name": String, "character": 캐릭터 id}, ...]
	data = game_data if game_data else GameDataV2.load_default()
	if seed_value < 0:
		# 무작위 판도 시드를 명시해 둔다 (기록 재생용 · JSON에서도 정확한 32비트 값)
		var r := RandomNumberGenerator.new()
		r.randomize()
		seed_value = r.randi()
	rng.seed = seed_value
	var R: Dictionary = data.rules
	board = {}
	board[data.start] = _new_tile("start")
	for b in data.bases:
		board[b] = _new_tile("base")
	tile_deck = []
	var tiles: Dictionary = R["tiles"]
	for t in tiles:
		if str(t).begins_with("_"):
			continue
		for i in int(tiles[t]):
			tile_deck.append(t)
	_shuffle(tile_deck)
	threat_deck = data.threat_deck(1)
	_shuffle(threat_deck)
	threat_discard = []
	threat_today = ""
	mission_deck = _expand(data.missions.get("missions", []))
	mission_discard = []
	mission_row = []
	event_deck = _expand(data.events.get("events", []))
	event_discard = []
	item_deck = _expand(data.items.get("items", []))
	item_discard = []
	bomb_supply = int(R["bomb_supply"])
	players = []
	for i in player_defs.size():
		var d: Dictionary = player_defs[i]
		players.append({
			"id": i, "name": d.get("name", "요원 %d" % (i + 1)), "character": d["character"],
			"pos": data.start, "jailed": false, "jail_count": 0,
			"items": [], "bombs": 0, "move_mod_next": 0, "skip_dice_tomorrow": false,
			"die": -1, "die_raw": -1, "done_today": false, "turns": 0,
			"ability_day": -1, "item_uses": 0, "grants": [], "flags": {},
			"stats": {"missions": 0, "rescues": 0, "escapes": 0, "jailed": 0, "checkpoints": 0,
				"assassinations": 0, "items": 0, "abilities": 0, "gives": 0},
		})
	police = {}
	intel = {}
	for id in GameDataV2.BASE_IDS:
		intel[id] = 0
	exposure = 0
	ready = 0
	rounds_total = int(R["rounds"])
	rounds_left = rounds_total
	act = 1
	day = 1
	leader = 0
	current = -1
	steps_left = 0
	team_dice = []
	dice_extra_tomorrow = 0
	dice_reroll_tomorrow = false
	today = _new_today()
	pending = {}
	launch_info = {}
	ending = {}
	check = {}
	last_roll = []
	actions.clear()
	events.clear()
	log_lines.clear()
	history.clear()
	_log("작전 개시. %d일 안에 결행을 준비하십시오." % rounds_total)
	_begin_morning(true)


func _new_tile(type: String) -> Dictionary:
	return {"type": type, "used": false, "flags": []}


func _new_today() -> Dictionary:
	return {"dice_mod": 0, "police_speed": 0, "escape_mod": 0, "scene_mod": 0, "move_today": {}, "assassin_wins": [], "ends": {}}


func _expand(defs: Array) -> Array:
	var out := []
	for d in defs:
		for i in int(d.get("count", 1)):
			out.append(d["id"])
	_shuffle(out)
	return out


# ================================================================ 조회 (UI·AI 공용)

func cur() -> Dictionary:
	return players[current] if current >= 0 else {}


func char_def(p: Dictionary) -> Dictionary:
	return data.character(p["character"])


func item_def(id: String) -> Dictionary:
	return data.item(id)


func mission_def(id: String) -> Dictionary:
	return data.mission(id)


func mission_type_def(type: String) -> Dictionary:
	return data.missions.get("types", {}).get(type, {})


func date_label() -> String:
	return "%d일째" % day


func tile_type(c: Vector2i) -> String:
	return board[c]["type"] if board.has(c) else ""


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < data.size and c.y < data.size


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func base_index_at(c: Vector2i) -> int:
	return data.bases.find(c)


func base_name(bi: int) -> String:
	return data.base_names[bi]


func alert_level() -> int:
	## 경계 단계 1~. 노출이 문턱을 넘을 때마다 오른다.
	var lv := 1
	for t in data.rules["exposure"]["thresholds"]:
		if exposure >= int(t):
			lv += 1
	return lv


func police_speed() -> int:
	var pol: Dictionary = data.rules["police"]
	var by_alert: Array = pol["speed_by_alert"]
	var base: int = int(by_alert[mini(alert_level(), by_alert.size()) - 1])
	return maxi(int(pol["min_speed"]), base + int(today.get("police_speed", 0)))


func hand_limit(p: Dictionary) -> int:
	return int(data.rules["hand_limit"]) + stat(p, "hand_limit")


func bomb_slots(p: Dictionary) -> int:
	return int(data.rules["bomb_slots"]) + stat(p, "bomb_slots")


func check_target(name: String) -> int:
	return int(data.rules["checks"][name])


func tomorrow_threat() -> String:
	## 덱 맨 위(내일 위협). 덱이 비면 버린 더미가 섞여 올라오므로 "" (정 인쇄공 미리 보기용)
	return threat_deck[-1] if not threat_deck.is_empty() else ""


func threat_preview(n := -1) -> Array:
	## 내일부터 뒤집힐 위협 카드 id를 위에서부터 n장 (정 인쇄공 threat_peek: 정보만 볼 뿐 순서는 못 바꿈).
	## n이 음수이면 요원들이 가진 threat_peek 값 중 가장 큰 수. 덱이 모자라면 있는 만큼만.
	if n < 0:
		n = 0
		for q in players:
			n = maxi(n, stat(q, "threat_peek"))
	var out := []
	for i in n:
		var idx := threat_deck.size() - 1 - i
		if idx < 0:
			break
		out.append(threat_deck[idx])
	return out


func leader_player() -> Dictionary:
	return players[leader]


func spare_dice() -> Array:
	## 지금 쓸 수 있는 예비 주사위의 인덱스 (하루가 시작된 뒤, 아무도 안 가졌고 아직 안 쓴 것)
	var out := []
	if not phase in ["day", "turn", "choice"]:
		return out
	for i in team_dice.size():
		if team_dice[i]["owner"] == -1 and not team_dice[i]["spare_used"]:
			out.append(i)
	return out


func die_index_of(pid: int) -> int:
	for i in team_dice.size():
		if team_dice[i]["owner"] == pid:
			return i
	return -1


func occupied_by_other(p: Dictionary, c: Vector2i) -> bool:
	## 다른 요원이 서 있는 칸 (출발점·거점은 예외). 경찰 칸은 지나갈 수 있다.
	if c == data.start or c in data.bases:
		return false
	for q in players:
		if q["id"] != p["id"] and q["pos"] == c and not q["jailed"]:
			return true
	return false


func missions_in_row(type: String) -> Array:
	var out := []
	for id in mission_row:
		if data.mission(id).get("type", "") == type:
			out.append(id)
	return out


func mission_tile(type: String) -> String:
	## 이 종류 미션이 이뤄지는 타일 종류 (types에 tile이 있으면 그것, 없으면 종류 이름이 곧 타일 이름)
	var t: Dictionary = mission_type_def(type)
	var cond = t.get("condition", null)
	if typeof(cond) == TYPE_DICTIONARY and cond.has("tile"):
		return str(cond["tile"])
	return str(t.get("tile", type))


func _cond_kind(type: String) -> String:
	var cond = mission_type_def(type).get("condition", null)
	return str(cond.get("kind", "")) if typeof(cond) == TYPE_DICTIONARY else ""


func mission_feasible(id: String, simulate_bombs := true) -> bool:
	## 남은 타일(깔린 것 + 더미)로 이룰 수 있는 미션인가
	var m: Dictionary = data.mission(id)
	var type: String = m.get("type", "")
	var kind := _cond_kind(type)
	if kind == "" or kind == "enter_base":
		if type == "coop":
			var cc := _coop_cond(id)
			if str(cc.get("kind", "")) == "same_day_assassin":
				var at := _assassin_type()
				return at != "" and _tile_count(mission_tile(at)) >= int(cc.get("count", 2))
		return true
	var tile := mission_tile(type)
	if kind == "deliver_bomb":
		if not _tile_available(tile):
			return false
		if simulate_bombs:
			var holds := false
			for q in players:
				if q["bombs"] > 0:
					holds = true
			if not holds and not (bomb_supply > 0 and _tile_available("supply")):
				return false
		return true
	if kind == "check":
		return _tile_available(tile)
	return true


func _tile_count(tile: String) -> int:
	## 깔린 칸과 더미에 있는 그 종류 타일의 수
	var n := tile_deck.count(tile)
	for c in board:
		if board[c]["type"] == tile:
			n += 1
	return n


func _coop_cond(id: String) -> Dictionary:
	## 카드가 직접 갖는 협동 조건 (types가 아니라 카드에 있는 condition)
	var c = data.mission(id).get("condition", null)
	return c if typeof(c) == TYPE_DICTIONARY else {}


func _coop_ids(kind: String) -> Array:
	var out := []
	for id in mission_row:
		if str(_coop_cond(id).get("kind", "")) == kind:
			out.append(id)
	return out


func _assassin_type() -> String:
	## 암살 판정(check == "assassin")으로 이뤄지는 미션 종류 이름 (데이터에서 찾음)
	var types: Dictionary = data.missions.get("types", {})
	for t in types:
		var cond = types[t].get("condition", null)
		if typeof(cond) == TYPE_DICTIONARY and cond.get("kind", "") == "check" and cond.get("check", "") == "assassin":
			return str(t)
	return ""


func _tile_available(tile: String) -> bool:
	if tile in tile_deck:
		return true
	for c in board:
		if board[c]["type"] == tile:
			return true
	return false


# ---- 보정치 (캐릭터 특성 + 가진 지속 아이템)

func _mods_of(p: Dictionary) -> Array:
	var mods: Array = []
	mods.append_array(char_def(p).get("trait", {}).get("mods", []))
	for id in p["items"]:
		mods.append_array(item_def(id).get("mods", []))
	return mods


func stat(p: Dictionary, key: String, type := "") -> int:
	## 캐릭터 특성과 가진 아이템의 mods를 합산. mods에 type이 있으면(예: mission_intel_bonus) 같은 type만 센다.
	var v := 0
	for m in _mods_of(p):
		if m.get("stat", "") != key:
			continue
		if type != "" and m.has("type") and m["type"] != type:
			continue
		v += int(m["value"])
	return v


func flag(p: Dictionary, key: String) -> bool:
	return stat(p, key) > 0


# ---- 이동 · 길

func can_step(p: Dictionary, to: Vector2i) -> bool:
	if phase != "turn" or steps_left <= 0 or p["id"] != current or p["jailed"]:
		return false
	if not in_bounds(to) or _manhattan(to, p["pos"]) != 1:
		return false
	if occupied_by_other(p, to):
		return false
	if not board.has(to):
		return not tile_deck.is_empty()
	return true   # 검문소는 들어가려 할 때 회피 판정


func legal_steps(p: Dictionary) -> Array:
	var out := []
	for d in DIRS:
		if can_step(p, p["pos"] + d):
			out.append(p["pos"] + d)
	return out


func _stop_tiles(p: Dictionary) -> Array:
	## 지금 줄에 있는 미션 때문에 들어가면 이동이 끝나는 타일 종류
	var out := []
	for id in mission_row:
		var type: String = data.mission(id).get("type", "")
		var kind := _cond_kind(type)
		if kind == "check" or (kind == "deliver_bomb" and p["bombs"] > 0):
			var tile := mission_tile(type)
			if not tile in out:
				out.append(tile)
	if not _coop_ids("same_day_assassin").is_empty() and _assassin_type() != "":
		var at := mission_tile(_assassin_type())
		if not at in out:
			out.append(at)
	return out


func path_to(p: Dictionary, goal: Vector2i) -> Dictionary:
	## 현재 위치에서 goal까지의 최단 경로 (이동 미리보기용).
	## {"path": [칸...], "steps": int, "reachable": bool, "reason": String, "checks": int, "unknown": int}
	var start: Vector2i = p["pos"]
	var out := {"path": [], "steps": 0, "reachable": false, "reason": "", "checks": 0, "unknown": 0}
	if goal == start or not in_bounds(goal):
		return out
	if occupied_by_other(p, goal):
		out["reason"] = "다른 요원이 있는 칸"
		return out
	var stops := _stop_tiles(p)
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == goal:
			break
		# 이동이 끝나는 칸은 지나갈 수 없다 (목적지로만)
		if c != start and (tile_type(c) == "base" or tile_type(c) in stops or not board.has(c)):
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not in_bounds(n):
				continue
			if occupied_by_other(p, n):
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


func police_danger(p: Dictionary) -> Dictionary:
	## 이번 차례 끝에 나를 쫓는 경찰이 닿을 수 있는 칸 (깔린 타일 기준)
	var out := {}
	if not police.has(p["id"]) or p["jailed"]:
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


func _check_chance(need: int) -> float:
	var sides := int(data.rules["die_sides"])
	var dice := int(data.rules["check_dice"])
	var total := 0
	var ok := 0
	var counts := {0: 1}
	for i in dice:
		var nxt := {}
		for s in counts:
			for f in range(1, sides + 1):
				nxt[s + f] = nxt.get(s + f, 0) + counts[s]
		counts = nxt
	for s in counts:
		total += counts[s]
		if s >= need:
			ok += counts[s]
	return float(ok) / float(maxi(total, 1))


func escape_chance(p: Dictionary) -> float:
	return _check_chance(check_target("escape") - stat(p, "escape_bonus") - int(today.get("escape_mod", 0)) \
		- int(p["flags"].get("escape_add", 0)))


func evade_chance(p: Dictionary) -> float:
	if flag(p, "evade_auto"):
		return 1.0
	return _check_chance(check_target("evade") - stat(p, "evade_bonus"))


func launch_target_preview() -> Array:
	## 지금 결행하면 목표가 될 거점 id들 (첩보가 가장 많은 곳, 동점이면 여럿)
	var best := -1
	for id in intel:
		best = maxi(best, int(intel[id]))
	var out := []
	for id in GameDataV2.BASE_IDS:
		if int(intel[id]) == best:
			out.append(id)
	return out


# ================================================================ 액션: 판정 함수 (apply와 legal_actions가 함께 씀)

func _int_of(v) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and v == floorf(v):
		return int(v)
	return -999999


func _cell_of(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and v.size() == 2:
		return Vector2i(_int_of(v[0]), _int_of(v[1]))
	return Vector2i(-999999, -999999)


func can_take_die(p: Dictionary, i: int) -> bool:
	if phase != "plan" or p["skip_dice_tomorrow"]:
		return false
	if i < 0 or i >= team_dice.size():
		return false
	return team_dice[i]["owner"] == -1


func can_release_die(p: Dictionary) -> bool:
	return phase == "plan" and die_index_of(p["id"]) >= 0


func can_start_day() -> bool:
	if phase != "plan":
		return false
	for q in players:
		if q["jailed"] or q["skip_dice_tomorrow"]:
			continue
		if die_index_of(q["id"]) < 0:
			return false
	return true


func can_begin_turn(p: Dictionary) -> bool:
	return phase == "day" and not p["done_today"]


func can_end_move(p: Dictionary) -> bool:
	return phase == "turn" and p["id"] == current and not p["jailed"]


func can_end_turn(p: Dictionary) -> bool:
	return phase == "turn" and p["id"] == current and p["jailed"]


func can_escape(p: Dictionary) -> bool:
	return phase == "turn" and p["id"] == current and p["jailed"]


func can_use_item(p: Dictionary, index: int) -> bool:
	if index < 0 or index >= p["items"].size():
		return false
	if p["item_uses"] >= int(data.rules["item_uses_per_turn"]):
		return false
	return _item_usable_now(p, p["items"][index])


func _item_usable_now(p: Dictionary, id: String) -> bool:
	var it: Dictionary = item_def(id)
	if not it.has("effects"):
		return false   # 지속 카드는 가지고만 있으면 된다
	if not _cost_ok(p, it["effects"], 1):
		return false
	match str(it.get("when", "")):
		"morning":
			return phase == "plan"
		"turn":
			return phase == "turn" and p["id"] == current and not p["jailed"]
		"jailed":
			return phase == "turn" and p["id"] == current and p["jailed"]
	return false   # react_evade는 회피 판정 직전에 묻는다


func _cost_ok(p: Dictionary, effects: Array, items_used: int) -> bool:
	## 효과가 아이템을 내야 하는데(버리기·건네기·보내기) 낼 아이템이 모자라면 못 쓴다.
	## items_used: 이 효과 자신이 이미 손에서 빠지는 아이템 수 (아이템 카드를 쓸 때 1)
	var have: int = p["items"].size() - items_used
	for e in effects:
		match str(e.get("op", "")):
			"discard_item":
				if have < int(e.get("count", 1)):
					return false
			"give_item", "send_item":
				if have < 1:
					return false
	return true


func ability_def(p: Dictionary) -> Dictionary:
	return char_def(p).get("ability", {})


func ability_targets(p: Dictionary) -> Array:
	## 능력을 쓸 수 있는 대상. 대상이 필요 없는 능력(self)이면 [-1] (target 없이 보냄). 못 쓰면 [].
	var a: Dictionary = ability_def(p)
	if a.is_empty() or p["ability_day"] == day or p["jailed"]:
		return []
	match str(a.get("when", "")):
		"morning":
			if phase != "plan":
				return []
		"turn":
			if phase != "turn" or p["id"] != current:
				return []
		_:
			return []
	if not _cost_ok(p, a.get("effects", []), 0):
		return []
	var req: Dictionary = a.get("requires", {})
	if req.has("near_tile"):
		var near := false
		for d in DIRS:
			if tile_type(p["pos"] + d) == str(req["near_tile"]):
				near = true
		if not near:
			return []
	var kind: String = str(a.get("target", "self"))
	if kind == "self":
		return [-1]
	var out := []
	for q in players:
		if q["id"] == p["id"] or q["jailed"]:
			continue
		var d := _manhattan(q["pos"], p["pos"])
		match kind:
			"ally":
				out.append(q["id"])
			"ally_adjacent":
				if d <= 1:
					out.append(q["id"])
			"ally_same_cell":
				if d == 0:
					out.append(q["id"])
			"ally_in_range":
				if d <= int(a.get("range", 1)):
					out.append(q["id"])
	return out


func can_use_ability(p: Dictionary, target: int) -> bool:
	return target in ability_targets(p)


func give_options(p: Dictionary) -> Array:
	## 건넬 수 있는 (아이템, 동료) 조합 [{"index", "to"}]
	var out := []
	if phase != "turn" or p["id"] != current or p["jailed"]:
		return out
	var coop: Dictionary = data.rules["coop"]
	if bool(coop["give_counts_as_item_use"]) and p["item_uses"] >= int(data.rules["item_uses_per_turn"]):
		return out
	for q in players:
		if q["id"] == p["id"] or q["jailed"] or _manhattan(q["pos"], p["pos"]) > int(coop["give_range"]):
			continue
		for i in p["items"].size():
			out.append({"index": i, "to": q["id"]})
	return out


func decoy_options(p: Dictionary) -> Array:
	## 미끼로 끌어올 수 있는 경찰 [요원 id]
	var out := []
	if phase != "turn" or p["id"] != current or p["jailed"] or police.has(p["id"]):
		return out
	var coop: Dictionary = data.rules["coop"]
	if int(p["flags"].get("decoys", 0)) >= int(coop["decoy_per_turn"]):
		return out
	for pid in police:
		if pid != p["id"] and _manhattan(police[pid]["pos"], p["pos"]) <= int(coop["decoy_range"]):
			out.append(pid)
	return out


func can_use_spare(p: Dictionary, die: int, use: String) -> bool:
	if not die in spare_dice():
		return false
	match use:
		"move":
			return phase == "turn" and p["id"] == current and not p["jailed"]
		"escape":
			return phase == "turn" and p["id"] == current and p["jailed"]
		"reroll":
			return phase == "choice" and pending.get("kind", "") == "reroll" and pending["player"] == p["id"]
	return false


func _valid_choice(p: Dictionary, value) -> bool:
	if phase != "choice" or pending.get("player", -1) != p["id"]:
		return false
	for o in pending.get("options", []):
		if typeof(o["value"]) == typeof(value) and o["value"] == value:
			return true
	return false


func legal_actions() -> Array:
	## 지금 받아들일 수 있는 액션 전부
	var out := []
	if phase == "over":
		return out
	match phase:
		"choice":
			var pid: int = pending["player"]
			for o in pending["options"]:
				out.append({"type": "choose", "player": pid, "value": o["value"]})
			if pending.get("kind", "") == "reroll":
				for i in spare_dice():
					out.append({"type": "use_spare", "player": pid, "die": i, "use": "reroll"})
		"plan":
			for p in players:
				for i in team_dice.size():
					if can_take_die(p, i):
						out.append({"type": "take_die", "player": p["id"], "die": i})
				if can_release_die(p):
					out.append({"type": "release_die", "player": p["id"]})
				for ii in p["items"].size():
					if can_use_item(p, ii):
						out.append({"type": "use_item", "player": p["id"], "index": ii})
				_append_ability_actions(out, p)
			if can_start_day():
				out.append({"type": "start_day", "player": 0})
		"day":
			for p in players:
				if can_begin_turn(p):
					out.append({"type": "begin_turn", "player": p["id"]})
		"turn":
			var p: Dictionary = players[current]
			for to in legal_steps(p):
				out.append({"type": "step", "player": current, "to": to})
			if can_end_move(p):
				out.append({"type": "end_move", "player": current})
			if can_end_turn(p):
				out.append({"type": "end_turn", "player": current})
			if can_escape(p):
				out.append({"type": "escape", "player": current})
			for ii in p["items"].size():
				if can_use_item(p, ii):
					out.append({"type": "use_item", "player": current, "index": ii})
			_append_ability_actions(out, p)
			for o in give_options(p):
				out.append({"type": "give_item", "player": current, "index": o["index"], "to": o["to"]})
			for from in decoy_options(p):
				out.append({"type": "decoy", "player": current, "from": from})
			for i in spare_dice():
				for use in ["move", "escape"]:
					if can_use_spare(p, i, use):
						out.append({"type": "use_spare", "player": current, "die": i, "use": use})
	return out


func _append_ability_actions(out: Array, p: Dictionary) -> void:
	for t in ability_targets(p):
		var a := {"type": "ability", "player": p["id"]}
		if t >= 0:
			a["target"] = t
		out.append(a)


# ================================================================ 액션 처리

func apply(action: Dictionary) -> bool:
	var ok := _apply(action)
	if ok:
		actions.append(action.duplicate(true))
	return ok


func _apply(a: Dictionary) -> bool:
	if phase == "over":
		return false
	var pid := _int_of(a.get("player", null))
	if pid < 0 or pid >= players.size():
		return false
	var p: Dictionary = players[pid]
	match str(a.get("type", "")):
		"choose":
			if not a.has("value") or not _valid_choice(p, a["value"]):
				return false
			_resolve_choice(a["value"])
		"take_die":
			var i := _int_of(a.get("die", null))
			if not can_take_die(p, i):
				return false
			_take_die(p, i)
		"release_die":
			if not can_release_die(p):
				return false
			_release_die(p)
		"start_day":
			if not can_start_day():
				return false
			_start_day()
		"begin_turn":
			if not can_begin_turn(p):
				return false
			_begin_turn(p)
		"step":
			var to := _cell_of(a.get("to", null))
			if not can_step(p, to):
				return false
			_do_step(p, to)
		"end_move":
			if not can_end_move(p):
				return false
			_resolve_stop(p)
		"end_turn":
			if not can_end_turn(p):
				return false
			_log("%s: 옥중에서 때를 기다립니다." % p["name"])
			_finish_turn(p)
		"escape":
			if not can_escape(p):
				return false
			_begin_escape(p)
		"use_item":
			var idx := _int_of(a.get("index", null))
			if not can_use_item(p, idx):
				return false
			_use_item(p, idx)
		"ability":
			var t := -1
			if a.has("target"):
				t = _int_of(a["target"])
				if t < 0:
					return false
			if not can_use_ability(p, t):
				return false
			_use_ability(p, t)
		"give_item":
			var gi := _int_of(a.get("index", null))
			var to_id := _int_of(a.get("to", null))
			var found := false
			for o in give_options(p):
				if o["index"] == gi and o["to"] == to_id:
					found = true
			if not found:
				return false
			_give_item(p, gi, players[to_id])
		"decoy":
			var from := _int_of(a.get("from", null))
			if not from in decoy_options(p):
				return false
			_decoy(p, from)
		"use_spare":
			var di := _int_of(a.get("die", null))
			var use := str(a.get("use", ""))
			if not can_use_spare(p, di, use):
				return false
			_use_spare(p, di, use)
		_:
			return false
	return true


# ================================================================ 하루 흐름: 아침

func _begin_morning(first: bool) -> void:
	if first:
		leader = 0
		day = 1
	else:
		leader = (leader + 1) % players.size()
		day += 1
	today = _new_today()
	for q in players:
		q["die"] = -1
		q["die_raw"] = -1
		q["done_today"] = false
		q["item_uses"] = 0
	team_dice = []
	phase = "morning"
	current = -1
	_log("── %s 아침 (남은 %d일) · 리더 %s ──" % [date_label(), rounds_left, players[leader]["name"]])
	_push({"kind": "morning", "day": day, "leader": leader})
	morning_step = 1
	_morning_continue()


func _morning_continue() -> void:
	## 아침 순서(기획서 19.3): 위협 → 투표 → 변절 확인 → 미션 줄 → 팀 주사위. 선택이 끼면 멈췄다 이어간다.
	while morning_step <= 5 and phase == "morning":
		var s := morning_step
		morning_step += 1
		match s:
			1: _morning_threat()
			2: _morning_vote()
			3: _morning_traitor_check()
			4: _fill_mission_row()
			5: _morning_dice()


func _morning_threat() -> void:
	if threat_deck.is_empty():
		threat_deck = threat_discard
		threat_discard = []
		_shuffle(threat_deck)
	if threat_deck.is_empty():
		return
	var id: String = threat_deck.pop_back()
	threat_discard.append(id)
	threat_today = id
	var card: Dictionary = data.threat(id)
	_log("[일제 위협] %s - %s" % [card.get("name", id), card.get("text", "")])
	_record("위협: %s" % card.get("name", id), "warn")
	_push({"kind": "card", "deck": "threat", "id": id, "player": -1})
	_push({"kind": "threat", "id": id})
	_run_effects(players[leader], card.get("effects", []), {"then": "morning", "source": "threat"})


func _morning_vote() -> void:
	var R: Dictionary = data.rules
	if rounds_left <= int(R["forced_launch_days_left"]):
		_log("작전일이 코앞입니다. 더 기다릴 수 없습니다!")
		_launch("forced")
		return
	if ready >= int(R["launch_min"]):
		var tg := launch_target_preview()
		var names := []
		for id in tg:
			names.append(data.base_names[data.base_index(id)])
		var prompt := "결행하시겠습니까? 목표: %s (첩보 %d) · 결행 준비 %d · 경계 %d단계 · 남은 %d일" % [
			" / ".join(names), intel[tg[0]], ready, alert_level(), rounds_left]
		_ask(players[0], "launch_vote", prompt,
			[{"value": true, "label": "결행한다"}, {"value": false, "label": "하루 더 준비한다"}], {"then": "morning"})
		pending["votes"] = []


func _morning_traitor_check() -> void:
	## 훅 (3단계): 변절 확인
	pass


func _fill_mission_row() -> void:
	# 남은 타일로 이룰 수 없는 미션은 줄에서 뺀다
	var keep := []
	for id in mission_row:
		if mission_feasible(id):
			keep.append(id)
		else:
			mission_discard.append(id)
			_log("남은 타일로 이룰 수 없는 미션 「%s」을(를) 줄에서 뺐습니다." % data.mission(id).get("name", id))
	mission_row = keep
	var want := int(data.rules["mission_row"])
	var guard := mission_deck.size() + mission_discard.size() + 1
	while mission_row.size() < want and guard > 0:
		guard -= 1
		if mission_deck.is_empty():
			mission_deck = mission_discard
			mission_discard = []
			_shuffle(mission_deck)
			if mission_deck.is_empty():
				break
		var id: String = mission_deck.pop_back()
		if not mission_feasible(id):
			mission_discard.append(id)
			continue
		mission_row.append(id)
		_push({"kind": "card", "deck": "mission", "id": id, "player": -1})
	_log("공개 미션: %s" % ", ".join(mission_row.map(func(i): return data.mission(i).get("name", i))))


func _roll_die() -> int:
	return rng.randi_range(1, int(data.rules["die_sides"]))


func _morning_dice() -> void:
	var n: int = players.size() + int(data.rules["team_dice_extra"]) + dice_extra_tomorrow
	dice_extra_tomorrow = 0
	team_dice = []
	var vals := []
	for i in n:
		var v := _roll_die()
		team_dice.append({"value": v, "owner": -1, "spare_used": false})
		vals.append(v)
	if dice_reroll_tomorrow:
		dice_reroll_tomorrow = false
		vals = []
		for i in n:
			var v2 := _roll_die()
			team_dice[i]["value"] = v2
			vals.append(v2)
		_log("팀 주사위를 전부 다시 굴렸습니다.")
	_log("팀 주사위 %d개: %s" % [n, " ".join(vals.map(func(x): return str(x)))])
	_push({"kind": "dice_rolled", "values": vals})
	phase = "plan"
	current = -1


# ================================================================ 계획

func _effective_die(p: Dictionary, raw: int) -> int:
	return maxi(raw, stat(p, "move_min3"))


func _take_die(p: Dictionary, i: int) -> void:
	var old := die_index_of(p["id"])
	if old >= 0:
		team_dice[old]["owner"] = -1
	team_dice[i]["owner"] = p["id"]
	p["die_raw"] = int(team_dice[i]["value"])
	p["die"] = _effective_die(p, p["die_raw"])
	_log("%s: 주사위 %d을(를) 가져갑니다." % [p["name"], p["die_raw"]] if p["die"] == p["die_raw"] \
		else "%s: 주사위 %d을(를) 가져갑니다 (%d로 셉니다)." % [p["name"], p["die_raw"], p["die"]])
	_push({"kind": "die_taken", "player": p["id"], "die": i})


func _release_die(p: Dictionary) -> void:
	var i := die_index_of(p["id"])
	team_dice[i]["owner"] = -1
	p["die"] = -1
	p["die_raw"] = -1
	_push({"kind": "die_released", "player": p["id"], "die": i})


func _start_day() -> void:
	# 갇힌 요원이 가진 주사위는 예비로 돌아간다 (옥중 연락)
	for q in players:
		if q["jailed"]:
			var i := die_index_of(q["id"])
			if i >= 0:
				team_dice[i]["owner"] = -1
			q["die"] = -1
			q["die_raw"] = -1
		q["skip_dice_tomorrow"] = false
	phase = "day"
	current = -1
	_log("하루가 시작됩니다. 남은 주사위는 예비입니다.")
	_push({"kind": "day_start", "day": day})


# ================================================================ 낮: 차례

func _begin_turn(p: Dictionary) -> void:
	phase = "turn"
	current = p["id"]
	p["turns"] += 1
	p["flags"]["decoys"] = 0
	p["flags"]["escape_add"] = 0
	_push({"kind": "turn", "player": p["id"]})
	if p["jailed"]:
		steps_left = 0
		_log("%s: 감옥에서 차례를 맞았습니다." % p["name"])
		return
	var base := 0
	if p["die"] >= 0:
		base = maxi(int(data.rules["min_die"]), p["die"] + int(today.get("dice_mod", 0)))
	var steps: int = base + p["move_mod_next"] + int(today["move_today"].get(p["id"], 0)) + stat(p, "move_bonus")
	p["move_mod_next"] = 0
	steps_left = maxi(steps, 0)
	_log("%s: 이동 %d칸" % [p["name"], steps_left])


func _finish_turn(p: Dictionary) -> void:
	if phase == "over":
		return
	p["done_today"] = true
	p["flags"]["escape_add"] = 0
	p["flags"].erase("entry_no_police")     # 한 차례 안에만 쓰는 권리
	p["flags"]["checkpoint_pass"] = 0
	steps_left = 0
	phase = "day"
	current = -1
	if _coop_turn_end(p):
		return   # 협동 미션 보상을 처리하는 중 (끝나면 _after_turn으로 이어짐)
	_after_turn()


func _after_turn() -> void:
	if phase == "over":
		return
	for q in players:
		if not q["done_today"]:
			return
	_night()


func _night() -> void:
	_push({"kind": "night", "day": day})
	if _coop_night():
		return   # 협동 미션 보상을 처리하는 중 (끝나면 _night_end로 이어짐)
	_night_end()


func _night_end() -> void:
	rounds_left -= 1
	if rounds_left <= 0:
		rounds_left = 0
		_game_over("time")
		return
	_begin_morning(false)


func _game_over(reason: String) -> void:
	phase = "over"
	pending = {}
	ending = {"id": reason, "reason": reason}
	_record("작전 종료 (%s)" % reason, "info")
	_log("작전 종료 (%s)." % reason)
	_push({"kind": "over"})


# ================================================================ 이동

func _do_step(p: Dictionary, to: Vector2i) -> void:
	if not board.has(to):
		var t: String = tile_deck.pop_back()
		board[to] = _new_tile(t)
		_push({"kind": "reveal", "pos": to, "tile": t})
		if t == "check":
			_log("%s: 검문소가 나타났습니다! 이동이 끝납니다." % p["name"])
			steps_left = 0
			_resolve_stop(p)
			return
	if board[to]["type"] == "check":
		_enter_checkpoint(p, to)
		return
	_arrive(p, to)


func _enter_checkpoint(p: Dictionary, to: Vector2i) -> void:
	if int(p["flags"].get("checkpoint_pass", 0)) > 0:
		p["flags"]["checkpoint_pass"] = int(p["flags"]["checkpoint_pass"]) - 1
		_log("%s: 통행증으로 검문소를 그냥 지나갑니다." % p["name"])
		_arrive(p, to)
		return
	_log("%s: 검문소 통과를 시도합니다." % p["name"])
	_start_check(p, "evade", "checkpoint", {"cell": to})


func _arrive(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to})
	steps_left -= 1
	var t: String = board[to]["type"]
	if t == "base":
		steps_left = 0
		_enter_base(p)
		return
	if _try_missions(p, t):
		return
	_after_step(p)


func _after_step(p: Dictionary) -> void:
	if phase == "over":
		return
	if steps_left <= 0:
		_resolve_stop(p)


func _enter_base(p: Dictionary) -> void:
	var bi := base_index_at(p["pos"])
	_log("%s: %s에 들어갔습니다. 이동이 끝납니다." % [p["name"], base_name(bi)])
	for q in players:
		if q["jailed"] and q["pos"] == p["pos"] and q["id"] != p["id"]:
			q["jailed"] = false
			q["move_mod_next"] += stat(p, "rescued_move_bonus")
			p["stats"]["rescues"] += 1
			_log("%s: %s을(를) 구출했습니다!" % [p["name"], q["name"]])
			_record("%s — %s 구출" % [p["name"], q["name"]], "good")
			_banner("%s 구출!" % q["name"], "good", p)
			_push({"kind": "rescue", "player": p["id"], "rescued": q["id"]})
	var ids := []
	for id in mission_row:
		var m: Dictionary = data.mission(id)
		if _cond_kind(m.get("type", "")) == "enter_base" and str(m.get("base", "")) == GameDataV2.BASE_IDS[bi]:
			ids.append(id)
	var ctx := {"then": "base_finish", "entered_base": bi}
	ids.append_array(_coop_enter_base(p, bi))
	if not ids.is_empty():
		_complete_missions(p, ids, ctx)
	else:
		_base_finish(p, ctx)


func _base_finish(p: Dictionary, _ctx: Dictionary) -> void:
	if phase == "over":
		return
	if flag(p, "base_no_police"):
		_log("%s: 경찰이 오지 않았습니다." % p["name"])
	elif p["flags"].get("entry_no_police", false):
		p["flags"].erase("entry_no_police")
		_log("%s: 이번에는 경찰이 붙지 않았습니다." % p["name"])
	else:
		_summon(p)
	_post_move(p)


func _resolve_stop(p: Dictionary) -> void:
	## 이동을 마친 칸의 효과
	if phase == "over":
		return
	steps_left = 0
	var tile: Dictionary = board.get(p["pos"], {})
	var t: String = tile.get("type", "")
	_check_hideout(p)
	if t == "event" and not tile["used"]:
		tile["used"] = true
		tile["type"] = "normal"
		if _draw_event(p):
			return
	elif t == "item" and not tile["used"]:
		tile["used"] = true
		tile["type"] = "normal"
		_run_effects(p, [{"op": "draw_item", "count": 1}], {"then": "post_move", "source": "tile"})
		return
	elif t == "supply":
		_run_effects(p, [{"op": "gain_bomb", "count": 1}], {"then": "post_move", "source": "tile"})
		return
	_finish_move(p)


func _check_hideout(p: Dictionary) -> void:
	var tile: Dictionary = board.get(p["pos"], {})
	if tile.get("flags", []).has(str(data.rules["hideout_flag"])) and police.has(p["id"]):
		police.erase(p["id"])
		_log("%s: 은신처에 숨어 추적하던 경찰을 따돌렸습니다." % p["name"])
		_push({"kind": "police"})


func _draw_event(p: Dictionary) -> bool:
	## 이벤트 카드 한 장. 효과를 처리하기 시작했으면 true (이어서 알아서 post_move로 간다)
	var id := _draw_from(event_deck, event_discard)
	if id == "":
		return false
	event_discard.append(id)
	var ev: Dictionary = data.event(id)
	_log("%s: 이벤트 [%s] - %s" % [p["name"], ev.get("name", id), ev.get("text", "")])
	_push({"kind": "card", "deck": "event", "id": id, "player": p["id"]})
	_run_effects(p, ev.get("effects", []), {"then": "post_move", "source": "event"})
	return true


func _inert_tile(c: Vector2i) -> bool:
	## 깔려 있고, 옮겨 가 서도 아무 효과가 없는 칸 (거점·검문소·미션 타일은 아님)
	if not board.has(c):
		return false
	var t: String = board[c]["type"]
	if t == "base" or t == "check":
		return false
	for type in data.missions.get("types", {}):
		if mission_tile(type) == t and _cond_kind(type) in ["check", "deliver_bomb"]:
			return false
	return true


func _teleport(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to, "jump": true})


func hop_cells(p: Dictionary) -> Array:
	## end_move_hop_to_ally: 한 칸 옮겨 동료 옆에 설 수 있는 깔린 빈칸
	var out := []
	for d in DIRS:
		var n: Vector2i = p["pos"] + d
		if not _inert_tile(n) or occupied_by_other(p, n):
			continue
		for q in players:
			if q["id"] != p["id"] and not q["jailed"] and _manhattan(q["pos"], n) == 1:
				out.append(n)
				break
	return out


func _end_move_hop(p: Dictionary) -> bool:
	## 이동이 끝날 때 동료 옆 깔린 빈칸으로 한 칸 옮길지 묻는다 (end_move_hop_to_ally). 물었으면 true.
	if phase == "over" or p["jailed"] or not flag(p, "end_move_hop_to_ally"):
		return false
	var cells := hop_cells(p)
	if cells.is_empty():
		return false
	var opts := [{"value": "no", "label": "그대로 있는다"}]
	for c in cells:
		opts.append({"value": c, "label": "(%d, %d)칸으로 옮긴다" % [c.x, c.y]})
	_ask(p, "hop", "동료 옆으로 한 칸 옮기시겠습니까?", opts, {})
	return true


func _finish_move(p: Dictionary) -> void:
	## 이동과 도착 효과가 끝난 뒤: 한 칸 더 갈 수 있으면 계속, 아니면 (이 차장 도약) → 경찰 이동 → 차례 종료
	if phase == "turn" and steps_left > 0 and not p["jailed"] and p["id"] == current:
		return
	if _end_move_hop(p):
		return
	_post_move(p)


func _post_move(p: Dictionary) -> void:
	## 이동과 도착 효과가 모두 끝난 뒤: 경찰 이동 → 차례 종료
	if phase == "over":
		return
	_police_act(p)
	_finish_turn(p)


# ================================================================ 판정

func _start_check(p: Dictionary, name: String, ctx: String, extra: Dictionary = {}) -> void:
	## name: rules.checks의 판정 이름. 보정은 stat "<name>_bonus" (+ 미션 종류별 보정)
	var target: int = int(extra.get("target", check_target(name)))
	var bonus: int = stat(p, name + "_bonus")
	if extra.has("type_bonus") and str(extra["type_bonus"]) != name:
		bonus += stat(p, str(extra["type_bonus"]) + "_bonus")
	if name == "escape":
		bonus += int(today.get("escape_mod", 0)) + int(p["flags"].get("escape_add", 0))
	check = {"what": name, "ctx": ctx, "player": p["id"], "target": target, "bonus": bonus,
		"auto_rerolls": stat(p, name + "_rerolls"), "dice": [], "total": 0}
	for k in extra:
		check[k] = extra[k]
	# 한 번 쓰는 권리: 판정 보정 (이번 판정에 자동으로 더함)
	var gi := _grant_index(p, "check_bonus")
	if gi >= 0:
		check["bonus"] += int(p["grants"][gi].get("value", 0))
		p["grants"].remove_at(gi)
	if name == "escape" and _grant_index(p, "escape_instant") >= 0:
		p["grants"].remove_at(_grant_index(p, "escape_instant"))
		_log("%s: 한 번 쓰는 권리로 곧바로 탈출합니다." % p["name"])
		_check_done(p, true)
		return
	if name == "evade":
		if flag(p, "evade_auto"):
			_log("%s: 타고난 은신술로 회피에 성공합니다." % p["name"])
			_check_done(p, true)
			return
		var egi := _grant_index(p, "evade_auto")
		if egi >= 0:
			p["grants"].remove_at(egi)
			_log("%s: 회피에 자동으로 성공합니다." % p["name"])
			_check_done(p, true)
			return
		var react := _react_item(p, "react_evade")
		if react != "":
			_ask(p, "react_evade", "회피 판정입니다. [%s]을(를) 쓰시겠습니까?" % item_def(react)["name"],
				[{"value": true, "label": "%s 사용" % item_def(react)["name"]}, {"value": false, "label": "주사위로 판정"}], {})
			pending["item"] = react
			return
	_check_roll(p)


func _react_item(p: Dictionary, when: String) -> String:
	for id in p["items"]:
		var it: Dictionary = item_def(id)
		if it.get("when", "") == when and it.has("effects"):
			return id
	return ""


func _grant_index(p: Dictionary, kind: String) -> int:
	for i in p["grants"].size():
		if p["grants"][i].get("kind", "") == kind:
			return i
	return -1


func _d2() -> int:
	var dice: Array = []
	var sum := 0
	for i in int(data.rules["check_dice"]):
		var d := _roll_die()
		dice.append(d)
		sum += d
	last_roll = dice
	return sum


func _check_roll(p: Dictionary) -> void:
	var c := check
	var r := _d2()
	c["dice"] = last_roll.duplicate()
	c["total"] = r + int(c["bonus"])
	var ok: bool = c["total"] >= int(c["target"])
	var label := _check_label(c)
	_push({"kind": "dice", "what": label, "dice": c["dice"], "bonus": c["bonus"], "target": c["target"],
		"player": p["id"], "ok": ok})
	_log("%s: %s 판정 %d%s (목표 %d) → %s" % [p["name"], label, r,
		(" %+d" % c["bonus"]) if c["bonus"] != 0 else "", c["target"], "성공" if ok else "실패"])
	if ok:
		_check_done(p, true)
		return
	if int(c["auto_rerolls"]) > 0:
		c["auto_rerolls"] = int(c["auto_rerolls"]) - 1
		_log("%s: 타고난 솜씨로 다시 굴립니다." % p["name"])
		_check_roll(p)
		return
	var spares := spare_dice()
	var gi := _grant_index(p, "reroll")
	if spares.is_empty() and gi < 0:
		_check_done(p, false)
		return
	var opts := [{"value": "no", "label": "그대로 실패로 한다"}]
	if gi >= 0:
		opts.append({"value": "grant", "label": "다시 굴릴 권리를 쓴다"})
	_ask(p, "reroll", "%s 판정에 실패했습니다. 다시 굴리겠습니까?" % label, opts, {})
	pending["spares"] = spares


func _check_label(c: Dictionary) -> String:
	return {"evade": "회피", "assassin": "암살", "escape": "탈옥", "sabotage": "방해"}.get(c["what"], str(c["what"]))


func _check_done(p: Dictionary, ok: bool) -> void:
	var c := check
	check = {}
	match str(c["ctx"]):
		"checkpoint":
			if ok:
				_log("%s: 검문소를 무사히 통과했습니다." % p["name"])
				_banner("검문소 통과", "info", p)
				p["stats"]["checkpoints"] += 1
				_arrive(p, c["cell"])
			else:
				_log("%s: 검문에 걸렸습니다! 이동이 끝납니다." % p["name"])
				_banner("검문에 걸렸다!", "bad", p)
				_expose(int(data.rules["exposure"]["on_checkpoint_fail"]))
				_summon(p)
				_resolve_stop(p)
		"mission_check":
			_mission_check_result(p, c, ok)
		"mission_evade":
			# 미션 판정에 실패해 도망치는 중: 성공하면 경찰이 붙고, 실패하면 투옥
			if ok:
				_summon(p)
			else:
				_jail(p)
			_resolve_stop(p)
		"escape":
			p["flags"]["escape_add"] = 0
			if ok:
				p["jailed"] = false
				p["stats"]["escapes"] += 1
				_log("%s: 탈옥 성공!" % p["name"])
				_banner("탈옥 성공!", "good", p)
				_summon(p)
			else:
				_log("%s: 탈옥 실패." % p["name"])
			_finish_turn(p)


# ================================================================ 공개 미션

func _try_missions(p: Dictionary, tile: String) -> bool:
	## 방금 들어간 칸이 줄에 있는 미션의 타일이면 처리하고 true (이동이 끝남)
	var by_kind := {}
	for id in mission_row:
		var type: String = data.mission(id).get("type", "")
		var kind := _cond_kind(type)
		if (kind == "check" or kind == "deliver_bomb") and mission_tile(type) == tile:
			by_kind[id] = kind
	# 암살 타일에서 성공해야 이뤄지는 협동 미션(same_day_assassin)이 줄에 있으면, 그 타일에서도 판정을 한다
	var assassin_type := _assassin_type()
	var coop_check: bool = assassin_type != "" and mission_tile(assassin_type) == tile \
		and not _coop_ids("same_day_assassin").is_empty()
	if by_kind.is_empty() and not coop_check:
		return false
	var check_ids := []
	var bomb_ids := []
	for id in by_kind:
		if by_kind[id] == "check":
			check_ids.append(id)
		else:
			bomb_ids.append(id)
	if not bomb_ids.is_empty() and p["bombs"] > 0:
		steps_left = 0
		p["bombs"] -= 1
		_log("%s: 폭탄을 설치했습니다!" % p["name"])
		_complete_missions(p, bomb_ids, {"then": "stop", "source": "mission"})
		return true
	if check_ids.is_empty() and not coop_check:
		return false   # 폭탄이 없으면 그냥 지나가는 칸
	steps_left = 0
	var type: String = data.mission(check_ids[0]).get("type", "") if not check_ids.is_empty() else assassin_type
	var cond: Dictionary = mission_type_def(type)["condition"]
	var name: String = str(cond["check"])
	_start_check(p, name, "mission_check", {"ids": check_ids, "target": int(cond.get("target", check_target(name))),
		"type_bonus": type, "tile_type": tile, "mission_type": type})
	return true


func _mission_check_result(p: Dictionary, c: Dictionary, ok: bool) -> void:
	## 미션 판정 결과. 회피(evade)로 하는 미션은 실패가 곧 경찰, 그 밖의 판정(암살 등)은
	## 성공하면 소란이 나서 경찰이 붙고 실패하면 회피 판정으로 도망쳐야 한다.
	var risky: bool = c["what"] != "evade"
	if ok:
		if risky:
			p["stats"]["assassinations"] += 1
			today["assassin_wins"].append({"player": p["id"], "cell": p["pos"]})
			_summon(p)
		_complete_missions(p, c["ids"], {"then": "stop", "source": "mission"}, str(c.get("mission_type", "")))
	elif risky:
		_log("%s: 실패! 회피 판정으로 빠져나가야 합니다." % p["name"])
		_banner("%s 실패 — 탈출하라!" % _check_label(c), "bad", p)
		_start_check(p, "evade", "mission_evade")
	else:
		_log("%s: 실패했습니다." % p["name"])
		_banner("%s 실패" % _check_label(c), "bad", p)
		_summon(p)
		_resolve_stop(p)


func _complete_missions(p: Dictionary, ids: Array, ctx: Dictionary, loud_type := "") -> void:
	## 한 번의 행동으로 채운 미션들을 모두 이룬다. 보상은 효과 목록으로 만들어 해석기에 넘긴다.
	## loud_type: 줄의 미션은 못 이뤘어도 이 종류의 판정에 성공했을 때 시끄러움을 셈 (협동 미션만 있는 암살 타일)
	var effects := []
	var loud := false
	if ids.is_empty() and loud_type != "" and bool(mission_type_def(loud_type).get("loud", false)):
		loud = true
	for id in ids:
		var m: Dictionary = data.mission(id)
		var type: String = m.get("type", "")
		var td: Dictionary = mission_type_def(type)
		mission_row.erase(id)
		mission_discard.append(id)
		p["stats"]["missions"] += 1
		_log("%s: 미션 「%s」 성공!" % [p["name"], m.get("name", id)])
		_record("%s — %s 성공" % [p["name"], m.get("name", id)], "good")
		_banner("%s 성공!" % m.get("name", id), "good", p)
		_push({"kind": "mission_done", "id": id, "player": p["id"]})
		var rd = m["ready"] if m.has("ready") else td.get("ready", null)
		if rd != null and int(rd) != 0:
			effects.append({"op": "ready", "value": int(rd)})
		var bonus := stat(p, "mission_intel_bonus", type)
		if bonus > 0 and m.get("intel", null) != null:
			effects.append({"op": "intel", "base": m["intel"], "value": bonus})
		var ex := stat(p, type + "_exposure")   # 예: 문 선전대원의 sabotage_exposure −1 (방해 성공 시 노출)
		if ex != 0:
			effects.append({"op": "exposure", "value": ex})
		effects.append_array(m.get("rewards", []))
		var ld = m["loud"] if m.has("loud") else td.get("loud", false)
		if ld != null and bool(ld):
			loud = true
	if loud:
		effects.append({"op": "exposure", "value": int(data.rules["exposure"]["loud"])})
	_run_effects(p, effects, ctx)


func _base_cell(base_id: String) -> Vector2i:
	var bi := data.base_index(base_id)
	return data.bases[bi] if bi >= 0 else Vector2i(-999, -999)


func _where_match(c: Vector2i, cond: Dictionary) -> bool:
	## 협동 조건의 where(+ base): 그 거점의 안 / 옆 칸 / 안이거나 옆 칸. where가 거점 id면 그 거점 안.
	var where := str(cond.get("where", "inside"))
	var base_id := str(cond.get("base", ""))
	if where in GameDataV2.BASE_IDS:
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


func _coop_turn_end(p: Dictionary) -> bool:
	## 협동 미션 — 차례 끝에 확인 (people, opposite_edges). 보상 처리를 시작했으면 true.
	if not p["jailed"]:
		today["ends"][p["id"]] = p["pos"]
	var ids := []
	for id in mission_row:
		var cond := _coop_cond(id)
		match str(cond.get("kind", "")):
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


func _coop_night() -> bool:
	## 협동 미션 — 밤에 확인 (same_day_assassin: 오늘 서로 다른 두 사람이 서로 다른 암살 타일에서 성공). 처리를 시작했으면 true.
	var ids := []
	for id in _coop_ids("same_day_assassin"):
		var need := int(_coop_cond(id).get("count", 2))
		var who := {}
		var cells := {}
		for w in today["assassin_wins"]:
			who[w["player"]] = true
			cells[w["cell"]] = true
		if who.size() >= need and cells.size() >= need:
			ids.append(id)
	if ids.is_empty():
		return false
	var wins: Array = today["assassin_wins"]
	var p: Dictionary = players[int(wins[-1]["player"])]
	_complete_missions(p, ids, {"then": "night_end", "source": "mission"})
	return true


# ================================================================ 탈옥

func _begin_escape(p: Dictionary) -> void:
	_log("%s: 탈옥을 시도합니다." % p["name"])
	_start_check(p, "escape", "escape")


# ================================================================ 경찰 · 감옥 · 노출

func _summon(p: Dictionary) -> void:
	## 경찰이 이 요원에게 붙는다 (붙은 다음 차례부터 움직임)
	if p["jailed"]:
		return
	if _block_police(p):
		return
	if police.has(p["id"]):
		police[p["id"]] = {"pos": p["pos"], "summon_turn": p["turns"]}
		_log("%s: 경찰이 다시 위치를 잡았습니다." % p["name"])
	elif police.size() < int(data.rules["police"]["pieces"]):
		police[p["id"]] = {"pos": p["pos"], "summon_turn": p["turns"]}
		_log("%s: 경찰이 붙었습니다!" % p["name"])
	_push({"kind": "police"})


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
	var best: Vector2i = data.bases[0]
	var bd := 999
	for b in data.bases:
		var d := _manhattan(b, p["pos"])
		if d < bd:
			bd = d
			best = b
	var from: Vector2i = p["pos"]
	p["pos"] = best
	p["jailed"] = true
	p["jail_count"] += 1
	p["stats"]["jailed"] += 1
	police.erase(p["id"])
	var name := base_name(data.bases.find(best))
	_record("%s — %s 감옥에 투옥" % [p["name"], name], "bad")
	_banner("%s 투옥!" % p["name"], "bad", p)
	_log("%s: %s 감옥에 투옥되었습니다!" % [p["name"], name])
	_push({"kind": "jail", "player": p["id"], "from": from, "to": best})
	_expose(int(data.rules["exposure"]["on_jail"]))
	_on_jailed(p)


func _on_jailed(_p: Dictionary) -> void:
	## 훅 (3단계): 투옥되면 심문 카드
	pass


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
		police.erase(p["id"])
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
		police.erase(p["id"])
		_log("%s: 경찰을 따돌렸습니다." % p["name"])
		_push({"kind": "police"})


func _expose(n: int) -> void:
	if n == 0:
		return
	var before := alert_level()
	exposure = clampi(exposure + n, 0, int(data.rules["exposure"]["max"]))
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
		if q["jailed"] or police.has(q["id"]):
			continue
		if best.is_empty() or _manhattan(q["pos"], base) < _manhattan(best["pos"], base):
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
	if p["items"].size() > hand_limit(p):
		_ask_discard(p)
		return true
	return false


func _ask_discard(p: Dictionary) -> void:
	var opts := []
	for i in p["items"].size():
		opts.append({"value": i, "label": item_def(p["items"][i])["name"]})
	_ask(p, "discard", "아이템은 %d장까지 가질 수 있습니다. 버릴 카드를 고르세요." % hand_limit(p), opts, {"then": "resume"})


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


func _use_ability(p: Dictionary, target: int) -> void:
	var a: Dictionary = ability_def(p)
	p["ability_day"] = day
	p["stats"]["abilities"] += 1
	_log("%s: 능력 「%s」 사용" % [p["name"], a.get("name", "")])
	_banner(str(a.get("name", "")), "info", p)
	_push({"kind": "ability", "player": p["id"]})
	_run_effects(p, a.get("effects", []), {"then": "resume", "source": "ability", "target": target})


func _give_item(p: Dictionary, idx: int, q: Dictionary) -> void:
	var id: String = p["items"][idx]
	p["items"].remove_at(idx)
	q["items"].append(id)
	if bool(data.rules["coop"]["give_counts_as_item_use"]):
		p["item_uses"] += 1
	p["stats"]["gives"] += 1
	_log("%s: [%s]을(를) %s에게 건넸습니다." % [p["name"], item_def(id)["name"], q["name"]])
	if q["items"].size() > hand_limit(q):
		_ask_discard(q)


func _decoy(p: Dictionary, from: int) -> void:
	var pol: Dictionary = police[from]
	police.erase(from)
	# 끌어온 경찰은 곧바로 나를 쫓는다 (이번 차례 끝에 움직임)
	police[p["id"]] = {"pos": pol["pos"], "summon_turn": p["turns"] - 1}
	p["flags"]["decoys"] = int(p["flags"].get("decoys", 0)) + 1
	_log("%s: 일부러 모습을 드러내 %s을(를) 쫓던 경찰을 유인했습니다!" % [p["name"], players[from]["name"]])
	_banner("미끼 작전!", "info", p)
	_push({"kind": "police"})


func _use_spare(p: Dictionary, die: int, use: String) -> void:
	var d: Dictionary = team_dice[die]
	d["spare_used"] = true
	match use:
		"move":
			var mv: int = int(d["value"]) + stat(p, "spare_die_bonus")
			steps_left += mv
			_log("%s: 예비 주사위 %d로 이동을 %d칸 늘립니다 (남은 이동 %d)." % [p["name"], d["value"], mv, steps_left])
		"escape":
			var ev: int = int(d["value"]) + stat(p, "spare_die_bonus")
			p["flags"]["escape_add"] = int(p["flags"].get("escape_add", 0)) + ev
			_log("%s: 예비 주사위 %d를 탈옥 판정에 보탭니다 (+%d)." % [p["name"], d["value"], ev])
		"reroll":
			_log("%s: 예비 주사위를 써서 판정을 다시 굴립니다." % p["name"])
			var pd := pending
			pending = {}
			phase = pd["resume_phase"]
			_check_roll(players[check["player"]])


# ================================================================ 효과 해석기

func _run_effects(p: Dictionary, effects: Array, ctx: Dictionary) -> void:
	## 효과 목록을 차례로 처리한다. 선택이 필요하면 pending을 열고 멈췄다가,
	## 선택이 끝나면 남은 효과(rest)와 이어서 계속한다. 다 끝나면 ctx["then"]으로 이어간다.
	ctx["actor"] = p["id"]
	var queue: Array = effects.duplicate()
	while not queue.is_empty():
		if phase == "over":
			return
		var e: Dictionary = queue.pop_front()
		if _effect(p, e, ctx, queue):
			pending["rest"] = queue
			pending["ctx"] = ctx
			return
	_continue(p, ctx)


func _continue(p: Dictionary, ctx: Dictionary) -> void:
	if phase == "over":
		return
	match str(ctx.get("then", "resume")):
		"morning":
			_morning_continue()
		"post_move":
			_finish_move(p)
		"after_turn":
			_after_turn()
		"night_end":
			_night_end()
		"stop":
			_resolve_stop(p)
		"base_finish":
			_base_finish(p, ctx)
		_:
			pass   # "resume": 원래 단계로 돌아가 계속 진행


func _effect(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 효과 하나를 실행한다. 선택지를 띄워 멈췄으면 true.
	var op: String = str(e.get("op", ""))
	match op:
		"police_dispatch":
			_op_police_dispatch(p, e)
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
		"interrogate":
			return _op_interrogate(p, e, queue)
		"persuade", "interrogate_discard":
			_op_stub_stage3(op)
		"search", "scene_check_mod_today", "threat_flip", "check_or_jail", "refill_supply":
			_op_stub_stage4(op)
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
			_log("오늘 모든 이동 주사위 %+d (최소 %d)." % [int(e.get("value", 0)), int(data.rules["min_die"])])
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
		"team_dice_extra_tomorrow":
			dice_extra_tomorrow += int(e.get("count", 1))
			_log("내일 아침 팀 주사위가 %d개 늘어납니다." % int(e.get("count", 1)))
		"team_die_reroll", "team_die_adjust", "team_die_set":
			return _op_team_die(p, e, queue)
		"team_dice_reroll_all":
			_op_team_dice_reroll_all(e)
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
		"skip_dice_tomorrow":
			var ids = _resolve_who(p, e, ctx, queue, str(e.get("who", "self")))
			if ids == null:
				return true
			for id in ids:
				players[id]["skip_dice_tomorrow"] = true
				_log("%s: 내일 아침에는 주사위를 받지 못합니다." % players[id]["name"])
		"checkpoint_pass":
			p["flags"]["checkpoint_pass"] = int(p["flags"].get("checkpoint_pass", 0)) + int(e.get("count", 1))
			_log("%s: 이번 차례에 검문소 %d곳을 판정 없이 지나갈 수 있습니다." % [p["name"], int(e.get("count", 1))])
		"entry_no_police":
			p["flags"]["entry_no_police"] = true
			_log("%s: 이번 거점 진입에는 경찰이 붙지 않습니다." % p["name"])
		_:
			_log("(알 수 없는 효과) %s" % op)
	return false


func _op_stub_stage3(op: String) -> void:
	## 3단계(변절·설득)에서 구현할 효과
	_log("(3단계 미구현) %s" % op)


func _op_stub_stage4(op: String) -> void:
	## 4단계(2막 장면)에서 구현할 효과
	_log("(4단계 미구현) %s" % op)


func _interrogate(p: Dictionary) -> void:
	## 훅 (3단계): 심문 카드 1장
	_log("(3단계 미구현) 심문: %s" % p["name"])


func _cond_holds(p: Dictionary, cond: String) -> bool:
	match cond:
		"chased":
			return police.has(p["id"])
		"not_chased":
			return not police.has(p["id"])
		"has_interrogation":
			return false   # 훅 (3단계): 심문 카드가 있는가
	return false


# ---- 2a 효과들

func _op_police_dispatch(_p: Dictionary, e: Dictionary) -> void:
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
		else:
			bi = data.base_index(from)
		if bi < 0:
			_log("(4단계 미구현) police_dispatch from=%s (결행 거점 없음)" % from)
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
		"all_jailed":
			return players.filter(func(q): return q["jailed"]).map(func(q): return q["id"])
		"nearest_to_base":
			var bi := _resolve_base_ref(str(e.get("base", "strike_base")))
			if bi < 0:
				return []
			var near_d := 9999
			var near_ids := []
			for q in players:
				if q["jailed"] and not include_jailed:
					continue
				var dd := _manhattan(q["pos"], data.bases[bi])
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
				if q["jailed"] and not include_jailed:
					continue
				var near := 9999
				for r in players:
					if r["id"] != q["id"]:
						near = mini(near, _manhattan(q["pos"], r["pos"]))
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
				if q["jailed"] and not include_jailed:
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
		_summon(players[id])
	return false


func _ask_leader_pick(e: Dictionary, ids: Array, queue: Array) -> bool:
	## 동점은 그날의 리더가 고른다. 고른 뒤 같은 효과를 그 요원으로(e["pid"]) 다시 처리한다.
	return _ask_pick(players[leader], e, queue, "pid", "pick_player", "동점입니다. 리더가 대상을 고르세요.", _player_options(ids))


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
		var d := _manhattan(q["pos"], p["pos"])
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
	if who.begins_with("ally"):
		var t := int(ctx.get("target", -1))
		if ctx.get("source", "") == "ability" and t >= 0 and t < players.size():
			return [t]
		var cands := _ally_candidates(p, who, e, include_jailed)
		if cands.size() <= 1:
			return cands
		_ask_pick(p, e, queue, "pid", "pick_player", "대상 동료를 고르세요.", _player_options(cands))
		return null
	var ids := _who_pick(p, who, e)
	if ids.size() > 1 and who in ["isolated", "wanted", "nearest_to_base"]:
		_ask_leader_pick(e, ids, queue)
		return null
	return ids


func _op_interrogate(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	var ids = _resolve_who(p, e, {}, queue, str(e.get("who", "self")))
	if ids == null:
		return true
	for id in ids:
		_interrogate(players[id])
	return false


func _resolve_base(p: Dictionary, base, ctx: Dictionary) -> int:
	var b: String = str(base)
	if b == "entered" and ctx.has("entered_base"):
		return int(ctx["entered_base"])
	if b == "nearest" or b == "entered":
		return _nearest_base(p["pos"])
	return data.base_index(b)


func _op_intel(p: Dictionary, e: Dictionary, ctx: Dictionary) -> bool:
	var v: int = int(e.get("value", 1))
	if str(e.get("base", "nearest")) == "choose":
		var opts := []
		for id in GameDataV2.BASE_IDS:
			opts.append({"value": id, "label": data.base_names[data.base_index(id)]})
		_ask(p, "intel_base", "첩보를 쌓을 거점을 고르세요.", opts, ctx)
		pending["amount"] = v
		return true
	var bi := _resolve_base(p, e.get("base", "nearest"), ctx)
	if bi >= 0:
		_add_intel(bi, v)
	return false


func _add_intel(bi: int, v: int) -> void:
	var id: String = GameDataV2.BASE_IDS[bi]
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
	_ask(p, "draw_pick", "아이템 %d장 중 1장을 고르세요 (나머지는 버립니다)." % cards.size(), opts, {})
	pending["cards"] = cards
	return true


func _op_choice(p: Dictionary, e: Dictionary) -> bool:
	var opts := []
	var effs := []
	var options: Array = e.get("options", [])
	for i in options.size():
		opts.append({"value": i, "label": options[i].get("label", "")})
		effs.append(options[i].get("effects", []))
	_ask(p, "effect_choice", "고르세요.", opts, {})
	pending["effects"] = effs
	return true


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
		_log("%s: 한 번 쓰는 권리를 얻었습니다 (%s)." % [q["name"], e.get("kind", "")])
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
				police.erase(p["id"])
				_log("%s: 쫓던 경찰이 사라졌습니다." % p["name"])
		"all":
			if not police.is_empty():
				police.clear()
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
				police.erase(pick)
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
	## 비용: 아이템을 버린다 (여러 장이면 하나씩 고름, 한 장뿐이면 그대로)
	var count: int = int(e.get("count", 1))
	if count > 1:
		var rest_e: Dictionary = e.duplicate()
		rest_e["count"] = count - 1
		queue.push_front(rest_e)
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
	_ask(p, "discard", "버릴 아이템을 고르세요.", opts, {})
	return true


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
			today["move_today"][id] = int(today["move_today"].get(id, 0)) + v
			if phase == "turn" and id == current:
				steps_left = maxi(steps_left + v, 0)
			_log("%s: 오늘 이동 %+d." % [q["name"], v])
	return false


func _die_options(include_values := false) -> Array:
	var opts := []
	for i in team_dice.size():
		var d: Dictionary = team_dice[i]
		var own := " (%s)" % players[d["owner"]]["name"] if d["owner"] >= 0 else ""
		opts.append({"value": i, "label": "주사위 %d: %d%s" % [i + 1, d["value"], own]})
	return opts


func _set_die_value(i: int, v: int) -> void:
	team_dice[i]["value"] = v
	var o: int = team_dice[i]["owner"]
	if o >= 0:
		players[o]["die_raw"] = v
		players[o]["die"] = _effective_die(players[o], v)


func _op_team_die(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	## team_die_reroll(count) · team_die_adjust(value ±) · team_die_set: 팀 주사위 하나를 골라 손봄
	var op := str(e["op"])
	if team_dice.is_empty():
		_log("손볼 팀 주사위가 없습니다.")
		return false
	var sides := int(data.rules["die_sides"])
	if op == "team_die_adjust":
		if not e.has("sel"):
			var mag := absi(int(e.get("value", 1)))
			var opts := []
			for i in team_dice.size():
				for sign in [1, -1]:
					var nv: int = int(team_dice[i]["value"]) + sign * mag
					if nv >= 1 and nv <= sides:
						opts.append({"value": "%d:%d" % [i, sign * mag],
							"label": "주사위 %d: %d → %d" % [i + 1, team_dice[i]["value"], nv]})
			if opts.is_empty():
				return false
			return _ask_pick(p, e, queue, "sel", "pick_die", "어느 주사위를 어떻게 바꿀까요?", opts)
		var parts: PackedStringArray = str(e["sel"]).split(":")
		var di := int(parts[0])
		_set_die_value(di, clampi(int(team_dice[di]["value"]) + int(parts[1]), 1, sides))
		_log("팀 주사위 %d의 눈이 %d이(가) 되었습니다." % [di + 1, team_dice[di]["value"]])
		return false
	if not e.has("die"):
		if team_dice.size() == 1:
			e = e.duplicate()
			e["die"] = 0
		else:
			return _ask_pick(p, e, queue, "die", "pick_die", "어느 주사위를 고르시겠습니까?", _die_options())
	var i2 := int(e["die"])
	if op == "team_die_set":
		if not e.has("val"):
			var vopts := []
			for v in range(1, sides + 1):
				vopts.append({"value": v, "label": "눈 %d" % v})
			return _ask_pick(p, e, queue, "val", "pick_value", "원하는 눈을 고르세요.", vopts)
		_set_die_value(i2, clampi(int(e["val"]), 1, sides))
		_log("팀 주사위 %d의 눈을 %d(으)로 정했습니다." % [i2 + 1, team_dice[i2]["value"]])
		return false
	var nv2 := _roll_die()
	_set_die_value(i2, nv2)
	_log("팀 주사위 %d을(를) 다시 굴려 %d이(가) 나왔습니다." % [i2 + 1, nv2])
	_push({"kind": "dice_rolled", "values": team_dice.map(func(d): return d["value"])})
	var left: int = int(e.get("count", 1)) - 1
	if left > 0:
		var e3: Dictionary = e.duplicate()
		e3.erase("die")
		e3["count"] = left
		queue.push_front(e3)
	return false


func _op_team_dice_reroll_all(e: Dictionary) -> void:
	if str(e.get("when", "")) == "tomorrow":
		dice_reroll_tomorrow = true
		_log("내일 아침 팀 주사위를 전부 다시 굴립니다.")
		return
	for i in team_dice.size():
		_set_die_value(i, _roll_die())
	_log("팀 주사위를 전부 다시 굴렸습니다.")
	_push({"kind": "dice_rolled", "values": team_dice.map(func(d): return d["value"])})


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
		return _ask_pick(p, e, queue, "tile", "pick_tile", "더미에서 깔 타일을 고르세요.", opts)
	var kind: String = str(e["tile"]) if type == "choose" else type
	var free := _free_neighbors(p["pos"])
	if free.is_empty():
		_log("%s: 타일을 깔 옆 빈칸이 없습니다." % p["name"])
		return false
	if free.size() > 1 and not e.has("cell"):
		var copts := []
		for c in free:
			copts.append({"value": c, "label": "(%d, %d)" % [c.x, c.y]})
		return _ask_pick(p, e, queue, "cell", "pick_cell", "타일을 깔 칸을 고르세요.", copts)
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
		if _inert_tile(n) and not occupied_by_other(p, n):
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
		cells = [q["pos"]] if not occupied_by_other(p, q["pos"]) else []
	if cells.is_empty():
		_log("%s: %s 곁에 설 자리가 없습니다." % [p["name"], q["name"]])
		return false
	if cells.size() > 1 and not e.has("cell"):
		var opts := []
		for c in cells:
			opts.append({"value": c, "label": "(%d, %d)" % [c.x, c.y]})
		return _ask_pick(p, e, queue, "cell", "pick_cell", "%s 곁의 어느 칸으로 갈까요?" % q["name"], opts)
	var to: Vector2i = e["cell"] if e.has("cell") else cells[0]
	if not to in cells:
		return false
	_teleport(p, to)
	_log("%s: %s 곁으로 단숨에 이동했습니다." % [p["name"], q["name"]])
	return false


func _op_pull_ally(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 동료 하나를 내 옆 칸으로 데려온다
	var ids = _resolve_who(p, e, ctx, queue, "ally")
	if ids == null:
		return true
	if ids.is_empty():
		return false
	var q: Dictionary = players[ids[0]]
	var cells := []
	for c in _adjacent_landing_cells(q, p["pos"]):
		if c != q["pos"]:
			cells.append(c)
	if cells.is_empty():
		_log("%s: %s을(를) 데려올 옆 칸이 없습니다." % [p["name"], q["name"]])
		return false
	if cells.size() > 1 and not e.has("cell"):
		var opts := []
		for c in cells:
			opts.append({"value": c, "label": "(%d, %d)" % [c.x, c.y]})
		return _ask_pick(p, e, queue, "cell", "pick_cell", "%s을(를) 어느 칸으로 데려올까요?" % q["name"], opts)
	var to: Vector2i = e["cell"] if e.has("cell") else cells[0]
	if not to in cells:
		return false
	_teleport(q, to)
	_log("%s: %s을(를) 곁으로 데려왔습니다." % [p["name"], q["name"]])
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
		return _ask_pick(p, e, queue, "item", "pick_item", "%s에게 줄 아이템을 고르세요." % q["name"], opts)
	var idx: int = int(e["item"]) if e.has("item") else 0
	if idx < 0 or idx >= p["items"].size():
		return false
	var id: String = p["items"][idx]
	p["items"].remove_at(idx)
	q["items"].append(id)
	if not free and bool(data.rules["coop"]["give_counts_as_item_use"]):
		p["item_uses"] += 1
	p["stats"]["gives"] += 1
	_log("%s: [%s]을(를) %s에게 건넸습니다." % [p["name"], item_def(id)["name"], q["name"]])
	if q["items"].size() > hand_limit(q):
		_ask_discard(q)
		return true
	return false


# ================================================================ 선택

func _ask(p: Dictionary, kind: String, prompt: String, options: Array, ctx: Dictionary) -> void:
	pending = {"kind": kind, "player": p["id"], "prompt": prompt, "options": options,
		"ctx": ctx, "rest": [], "resume_phase": phase}
	phase = "choice"
	_push({"kind": "choice", "player": p["id"]})


func _resolve_choice(value) -> void:
	var pd := pending
	pending = {}
	var p: Dictionary = players[pd["player"]]
	var actor: Dictionary = players[int(pd.get("ctx", {}).get("actor", pd["player"]))]
	phase = pd["resume_phase"]
	match str(pd["kind"]):
		"launch_vote":
			var votes: Array = pd["votes"] + [bool(value)]
			_push({"kind": "vote", "player": p["id"], "value": bool(value)})
			var nxt: int = pd["player"] + 1
			if nxt < players.size():
				_ask(players[nxt], "launch_vote", pd["prompt"], pd["options"], pd["ctx"])
				pending["votes"] = votes
				pending["resume_phase"] = pd["resume_phase"]
				return
			var yes := votes.count(true)
			_log("결행 투표: 찬성 %d, 반대 %d" % [yes, votes.size() - yes])
			# 과반 찬성이면 결행. 동수면 리더의 표를 따른다.
			if yes * 2 > votes.size() or (yes * 2 == votes.size() and votes[leader]):
				_launch("vote")
				return
			_log("결행을 하루 미루고 준비를 계속합니다.")
			_morning_continue()
		"strike_target":
			_finish_launch(str(value))
		"reroll":
			if str(value) == "grant":
				var gi := _grant_index(players[check["player"]], "reroll")
				if gi >= 0:
					players[check["player"]]["grants"].remove_at(gi)
				_log("%s: 다시 굴릴 권리를 씁니다." % p["name"])
				_check_roll(players[check["player"]])
			else:
				_check_done(players[check["player"]], false)
		"react_evade":
			if bool(value):
				var id: String = pd["item"]
				var idx: int = p["items"].find(id)
				if idx >= 0:
					p["items"].remove_at(idx)
					item_discard.append(id)
				_log("%s: [%s] 사용" % [p["name"], item_def(id)["name"]])
				_push({"kind": "item_used", "id": id, "player": p["id"]})
				# 효과(보통 회피 자동 성공 권리)를 적용한 뒤, 권리가 생겼으면 판정이 자동 성공
				for e in item_def(id).get("effects", []):
					_effect(p, e, {"then": "resume"}, [])
				var egi := _grant_index(p, "evade_auto")
				if egi >= 0:
					p["grants"].remove_at(egi)
					_log("%s: 회피에 성공합니다." % p["name"])
					_check_done(p, true)
				else:
					_check_roll(p)
			else:
				_check_roll(p)
		"discard":
			var id2: String = p["items"][int(value)]
			p["items"].remove_at(int(value))
			item_discard.append(id2)
			_log("%s: [%s]을(를) 버렸습니다." % [p["name"], item_def(id2)["name"]])
			_run_effects(actor, pd["rest"], pd["ctx"])
		"draw_pick":
			var cards: Array = pd["cards"]
			var chosen: String = cards[int(value)]
			for i in cards.size():
				if i != int(value):
					item_discard.append(cards[i])
			if _take_item(p, chosen):
				pending["rest"] = pd["rest"]
				pending["ctx"] = pd["ctx"]
				return
			_run_effects(actor, pd["rest"], pd["ctx"])
		"effect_choice":
			var picked: Array = pd["effects"][int(value)]
			_run_effects(actor, picked + pd["rest"], pd["ctx"])
		"pick_player", "pick_cell", "pick_die", "pick_tile", "pick_item", "pick_value", "pick_bury":
			if not pd["rest"].is_empty():
				pd["rest"][0][str(pd.get("key", "pid"))] = value
			_run_effects(actor, pd["rest"], pd["ctx"])
		"hop":
			if value is Vector2i:
				_teleport(p, value)
				_log("%s: 동료 곁으로 한 칸 옮겼습니다." % p["name"])
				_check_hideout(p)
			_post_move(p)
		"intel_base":
			_add_intel(data.base_index(str(value)), int(pd["amount"]))
			_run_effects(actor, pd["rest"], pd["ctx"])


# ================================================================ 결행

func _launch(reason: String) -> void:
	## 결행 선언: 첩보가 가장 많은 거점이 목표. 동점이면 그날의 리더가 고른다.
	launch_info = {"reason": reason, "day": day, "rounds_left": rounds_left, "ready": ready,
		"exposure": exposure, "alert": alert_level(), "intel": intel.duplicate(), "target": ""}
	_record("결행 선언 (%s)" % {"vote": "투표", "forced": "작전일 임박"}.get(reason, reason), "good")
	var tied := launch_target_preview()
	if tied.size() == 1:
		_finish_launch(tied[0])
		return
	var opts := []
	for id in tied:
		opts.append({"value": id, "label": data.base_names[data.base_index(id)]})
	_ask(players[leader], "strike_target", "첩보가 같은 거점이 여럿입니다. 리더가 결행할 곳을 고르세요.", opts, {})


func _finish_launch(base_id: String) -> void:
	## 4단계에서 2막으로 이어짐: 지금은 여기서 판을 끝낸다.
	launch_info["target"] = base_id
	act = 2
	phase = "over"
	pending = {}
	current = -1
	ending = {"id": "launch_stub", "target": base_id, "reason": launch_info.get("reason", "")}
	_log("결행! 목표: %s" % base_name(data.base_index(base_id)))
	_banner("결행!", "good")
	_push({"kind": "launch", "reason": launch_info.get("reason", ""), "target": base_id})
	_push({"kind": "over"})


# ================================================================ 저장 · 불러오기

const SAVE_FIELDS := ["players", "leader", "day", "rounds_total", "rounds_left", "act", "phase", "current",
	"steps_left", "board", "tile_deck", "police", "exposure", "intel", "ready", "threat_deck", "threat_discard",
	"threat_today", "mission_deck", "mission_discard", "mission_row", "event_deck", "event_discard",
	"item_deck", "item_discard", "bomb_supply", "team_dice", "dice_extra_tomorrow", "dice_reroll_tomorrow", "today", "pending",
	"launch_info", "ending", "check", "morning_step", "last_roll", "actions", "log_lines", "history"]


func save_state() -> Dictionary:
	## 게임 전체 상태 (난수 상태 포함). FileAccess.store_var로 그대로 저장할 수 있다.
	var out := {"version": 2, "rng_seed": rng.seed, "rng_state": rng.state}
	for f in SAVE_FIELDS:
		out[f] = get(f)
	return out.duplicate(true)


func load_state(st: Dictionary, game_data: GameDataV2 = null) -> void:
	data = game_data if game_data else GameDataV2.load_default()
	for f in SAVE_FIELDS:
		if st.has(f):
			set(f, st[f].duplicate(true) if st[f] is Array or st[f] is Dictionary else st[f])
	rng.seed = st["rng_seed"]
	rng.state = st["rng_state"]
	events.clear()


# ================================================================ 유틸

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
		ps[q["id"]] = {"pos": q["pos"], "jailed": q["jailed"]}
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
