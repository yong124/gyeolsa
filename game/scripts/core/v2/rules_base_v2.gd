class_name RulesBaseV2
extends RefCounted
## 규칙 엔진 1층: 상태 · 조회 · 판정 함수(무엇을 할 수 있나) · 저장 · 유틸.
## 엔진은 층마다 한 파일이고 위 층이 아래 층을 상속한다: 기반 → 효과 → 미션 → 사연 · 결행 → 2막 → RulesV2(흐름).
## 바깥에서는 늘 RulesV2만 쓴다. 설명은 rules_v2.gd 맨 위.


const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

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
var rigged_rolls: Array = []   # 튜토리얼 전용: 앞에서부터 꺼내 쓰는 정해 둔 주사위 눈 (SAVE_FIELDS에 없음 · 저장 · 시험 판에서는 늘 비어 있음)
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
var op_dice: Array = []         # 오늘의 작전 주사위 [{"value", "owner", "used"}] (owner는 건네받으면 바뀜)
var today := {}
var pending := {}
var launch_info := {}
var ending := {}
var scenes: Array = []
var scene_index := 0
var scene_state := {}
var intel_tokens := 0
var search_queue: Array = []
var effect_wait: Array = []
var check := {}                 # 지금 진행 중인 판정
var morning_step := 0
var last_roll: Array = []
var saga_decks := {}            # 더미 이름 -> 남은 사연 id (맨 위 = 맨 뒤)
var saga_discard: Array = []
var saga_rewards: Array = []    # 이룬 사연의 보상 대기열 [{"player", "id"}] (안전한 자리에서 처리)
var launch_step := 0            # 결행 순간 처리 단계 (아침의 morning_step처럼 이어 감)
var launch_i := 0               # 결행 순간 사연 남기기에서 다음에 처리할 요원
var human := -1                 # 사람이 맡은 요원 (-1이면 AI끼리). 결행 혜택은 사람이 고르고, 사람이 없으면 리더가 고른다
var vote_state := {}            # 결행 투표 중: {"forced", "order", "votes": {요원: 찬반}, "targets": {요원: 거점}} (모두 낼 때까지 비공개)
var counter := {}               # 반격: {"day", "blocked"} (버티기 장면이 펼쳐진 날)
var counter_queue: Array = []   # 밤에 반격 회피 판정을 기다리는 요원
var markers: Array = []         # 보드 위 마커 [{"uid", "id", "role", "pos", "move", "spec"}] (미션·일제 작전)
var mission_state := {}         # 마커가 놓인 카드(미션·일제 작전) id -> 진행 {"days", "sum", "left", "holder", "lurk", ...}
var op_row: Array = []          # 마커가 놓여 있는 일제 작전 카드
var op_deck: Array = []         # 일제 작전 덱 (맨 위 = 맨 뒤)
var op_discard: Array = []
var trend := 0                  # 일제 동향 0~rules.ops.trend_max
var peek_bonus := 0             # 위협 덱을 더 미리 보는 장수 (「경찰서 감시」 보상, 이번 판 동안)
var bonus_wait: Array = []      # 결행 때 판정하는 미션 보너스 [{"player", "base", "reward"}]
var expire_queue: Array = []    # 아침에 기한이 다 된 카드 (벌칙 처리 대기)
var marker_seq := 0

var actions: Array = []
var events: Array = []
var log_lines: Array = []
var history: Array = []
var stats := {"ops_seen": 0, "ops_blocked": 0, "max_exposure": 0}   # 팀 기록 (엔딩 요약용, 규칙에는 영향 없음)
var _dist_cache := {}           # 걸어서 잰 거리 (깔린 칸이 늘면 비움, 저장하지 않음)
var _dist_cache_size := -1


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
		n += peek_bonus
	var out := []
	for i in n:
		var idx := threat_deck.size() - 1 - i
		if idx < 0:
			break
		out.append(threat_deck[idx])
	return out


func leader_player() -> Dictionary:
	return players[leader]


func my_dice(pid: int) -> Array:
	## 이 요원이 지금 가진 (아직 안 쓴) 작전 주사위의 인덱스
	var out := []
	for i in op_dice.size():
		if int(op_dice[i]["owner"]) == pid and not op_dice[i]["used"]:
			out.append(i)
	return out


func die_value(i: int) -> int:
	return int(op_dice[i]["value"]) if i >= 0 and i < op_dice.size() else 0


func move_value(p: Dictionary, i: int) -> int:
	## 이 주사위를 이동에 쓰면 몇 칸인가 (포수의 1·2→3, 오늘 이동 주사위 보정, 무거운 물건 -1, 최소 min_die)
	var raw := maxi(die_value(i), stat(p, "move_min3"))
	return maxi(int(data.rules["min_die"]), raw + int(today.get("dice_mod", 0)) - heavy_count(p))


func police_on(c: Vector2i) -> bool:
	## 경찰 말이 서 있는 칸. 요원은 들어갈 수 없다 (요원끼리는 같은 칸에 설 수 있다).
	for pid in police:
		if police[pid]["pos"] == c:
			return true
	return false


func _dist_from(a: Vector2i) -> Dictionary:
	## a에서 깔린 칸을 따라 걸어 닿는 칸마다의 걸음 수
	if board.size() != _dist_cache_size:
		_dist_cache = {}
		_dist_cache_size = board.size()
	if not _dist_cache.has(a):
		var d := {a: 0}
		var q: Array[Vector2i] = [a]
		var head := 0
		while head < q.size():
			var c: Vector2i = q[head]
			head += 1
			for dir in DIRS:
				var n: Vector2i = c + dir
				if board.has(n) and not d.has(n):
					d[n] = int(d[c]) + 1
					q.append(n)
		_dist_cache[a] = d
	return _dist_cache[a]


func walk_dist(a: Vector2i, b: Vector2i) -> int:
	## 거리는 늘 깔린 칸을 따라 걷는 칸 수 (12단계 2절). 이어지지 않으면 맨해튼 + 100 (아주 먼 것으로 침)
	if a == b:
		return 0
	var d: Dictionary = _dist_from(a)
	return int(d[b]) if d.has(b) else 100 + _manhattan(a, b)


# ---- 미션 · 일제 작전 마커 조회

func card_def(id: String) -> Dictionary:
	## 보드에 마커를 놓는 카드 (미션 또는 일제 작전)
	return data.marker_card(id)


func card_cond(id: String) -> Dictionary:
	var c = data.marker_card(id).get("condition", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}


func markers_at(c: Vector2i) -> Array:
	var out := []
	for m in markers:
		if m["pos"] == c:
			out.append(m)
	return out


func marker_at(c: Vector2i) -> Dictionary:
	for m in markers:
		if m["pos"] == c:
			return m
	return {}


func markers_of(id: String, role := "") -> Array:
	var out := []
	for m in markers:
		if m["id"] == id and (role == "" or m["role"] == role):
			out.append(m)
	return out


func card_days_left(id: String) -> int:
	## 기한까지 남은 날 (기한이 없으면 -1)
	return int(mission_state.get(id, {}).get("days", -1))


func has_bomb_card() -> bool:
	## 폭탄을 들고 가야 하는 미션이 줄에 있는가
	for id in mission_row:
		if str(card_cond(id).get("kind", "")) == "bomb":
			return true
	return false


func heavy_count(p: Dictionary) -> int:
	## 내가 들고 있는 무거운 물건 수 (하나마다 이동 눈 -1)
	var n := 0
	for id in mission_row:
		if bool(card_cond(id).get("heavy", false)) and int(mission_state.get(id, {}).get("holder", -1)) == p["id"]:
			n += 1
	return n


func card_status(id: String) -> String:
	## 지금까지의 진행 한 줄 (화면용). 없으면 ""
	var st: Dictionary = mission_state.get(id, {})
	var cond := card_cond(id)
	match str(cond.get("kind", "")):
		"work":
			match str(cond.get("mode", "")):
				"sum":
					return "바친 합 %d / %d" % [int(st.get("sum", 0)), int(st.get("need", 0))]
				"combo":
					var left := []
					for v in st.get("left", []):
						left.append(str(v))
					return "남은 눈 " + "·".join(left)
				"each":
					return "남은 마커 %d개" % markers_of(id, "work").size()
		"lurk":
			return "잠복 %d / %d일" % [int(st.get("lurk", 0)), int(cond.get("days", 1))]
		"contact":
			var h := int(st.get("holder", -1))
			return josa("%s이(가) 들고 있음" % players[h]["name"]) if h >= 0 else "아직 받지 않음"
		"assassinate":
			return "동선 파악됨 (표적이 멈춤)" if bool(st.get("informed", false)) else ""
	return ""


func _coop_cond(id: String) -> Dictionary:
	## 협동 미션의 조건 (카드의 condition)
	return card_cond(id)


func _coop_ids(kind: String) -> Array:
	## 줄에 있는 이 kind의 협동 미션
	var out := []
	for id in mission_row:
		if str(card_cond(id).get("kind", "")) == kind:
			out.append(id)
	return out


func _stop_cells(p: Dictionary) -> Array:
	## 마커 때문에 들어가면 이동이 끝나는 칸: 암살 표적, 폭탄을 들었으면 폭파 지점, 물건을 들었으면 주기 마커
	var out := []
	for m in markers:
		var kind := str(card_cond(str(m["id"])).get("kind", ""))
		match str(m["role"]):
			"target":
				if kind == "assassinate" or (kind == "bomb" and p["bombs"] > 0):
					out.append(m["pos"])
			"dropoff":
				if int(mission_state.get(m["id"], {}).get("holder", -1)) == p["id"]:
					out.append(m["pos"])
	return out


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
	if police_on(to):
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


func path_to(p: Dictionary, goal: Vector2i) -> Dictionary:
	## 현재 위치에서 goal까지의 최단 경로 (이동 미리보기용).
	## {"path": [칸...], "steps": int, "reachable": bool, "reason": String, "checks": int, "unknown": int}
	var start: Vector2i = p["pos"]
	var out := {"path": [], "steps": 0, "reachable": false, "reason": "", "checks": 0, "unknown": 0}
	if goal == start or not in_bounds(goal):
		return out
	if police_on(goal):
		out["reason"] = "경찰이 있는 칸"
		return out
	var stops := _stop_cells(p)
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == goal:
			break
		# 이동이 끝나는 칸은 지나갈 수 없다 (목적지로만)
		if c != start and (tile_type(c) == "base" or c in stops or not board.has(c)):
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not in_bounds(n):
				continue
			if police_on(n):
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


func reach_cells(p: Dictionary, steps: int) -> Dictionary:
	## 이 걸음 수로 닿을 수 있는 칸 {칸: 걸음 수} (이동 미리 보기용 조회). 멈추는 칸(거점·마커·덮인 칸)은 닿을 뿐 지나가지 못하고,
	## 경찰이 있는 칸은 못 들어간다.
	var dist := {}
	if p["jailed"] or steps <= 0:
		return dist
	var stops := _stop_cells(p)
	dist[p["pos"]] = 0
	var q: Array[Vector2i] = [p["pos"]]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var d: int = dist[c]
		if d >= steps:
			continue
		if c != p["pos"] and (tile_type(c) == "base" or c in stops or not board.has(c)):
			continue
		for dir in DIRS:
			var n: Vector2i = c + dir
			if dist.has(n) or not in_bounds(n) or police_on(n):
				continue
			if not board.has(n) and tile_deck.is_empty():
				continue
			dist[n] = d + 1
			q.append(n)
	dist.erase(p["pos"])
	return dist


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
	## 첩보가 가장 많은 거점 (동점이면 여럿)
	var best := -1
	for id in intel:
		best = maxi(best, int(intel[id]))
	var out := []
	for id in data.base_ids:
		if int(intel[id]) == best:
			out.append(id)
	return out


func launch_candidates() -> Array:
	## 결행 대상 후보: 첩보가 rules.launch.target_min_intel 이상인 거점. 없으면 첩보가 가장 높은 거점.
	var out := []
	for id in data.base_ids:
		if int(intel[id]) >= int(data.rules["launch"]["target_min_intel"]):
			out.append(id)
	return out if not out.is_empty() else launch_target_preview()


func benefit_chooser() -> int:
	## 결행 혜택을 고르는 요원: 사람이 있으면 사람 (리더가 아니어도), 없으면 리더
	return human if human >= 0 and human < players.size() else leader


func benefits_left() -> Array:
	## 아직 안 고른 결행 혜택 (rules.launch.benefits 중 켜져 있는 것)
	var out := []
	for b in data.rules["launch"]["benefits"]:
		if bool(b.get("enabled", true)) and not str(b["id"]) in launch_info.get("benefits", []):
			out.append(b)
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


func can_start_day() -> bool:
	return phase == "plan"


func _acting(p: Dictionary) -> bool:
	## 지금 행동 고르기 중인 요원인가 (이동 중이 아님)
	return phase == "turn" and p["id"] == current and steps_left <= 0


func can_move_die(p: Dictionary, i: int) -> bool:
	return _acting(p) and not p["jailed"] and i in my_dice(p["id"])


func give_die_targets(p: Dictionary) -> Array:
	## 주사위를 건넬 수 있는 동료 (give_range 안, 보통 같은 칸). 차례를 마친 요원 · 갇힌 요원과는 안 되고, 하루 give_per_day번.
	var out := []
	if not _acting(p) or p["jailed"] or int(p["gives_today"]) >= int(data.rules["give_per_day"]) or my_dice(p["id"]).is_empty():
		return out
	for q in players:
		if q["id"] != p["id"] and not q["done_today"] and not q["jailed"] and _manhattan(q["pos"], p["pos"]) <= int(data.rules["give_range"]):
			out.append(q["id"])
	return out


func can_begin_turn(p: Dictionary) -> bool:
	return phase == "day" and not p["done_today"]


func can_end_move(p: Dictionary) -> bool:
	return phase == "turn" and p["id"] == current and not p["jailed"] and steps_left > 0


func can_end_turn(p: Dictionary) -> bool:
	return _acting(p)


func can_escape(p: Dictionary) -> bool:
	return _acting(p) and p["jailed"] and not my_dice(p["id"]).is_empty()


func _hide_ok(p: Dictionary) -> bool:
	## 숨기는 rules.hide의 타일 종류나 표시(flag)가 있는 칸에서만
	var h: Dictionary = data.rules["hide"]
	if tile_type(p["pos"]) in h["tiles"]:
		return true
	for f in board.get(p["pos"], {}).get("flags", []):
		if f in h["flags"]:
			return true
	return false


func can_hide(p: Dictionary) -> bool:
	return _acting(p) and not p["jailed"] and not p["hidden"] and _hide_ok(p) and not my_dice(p["id"]).is_empty()


func mission_check_cells(p: Dictionary) -> Array:
	## 작전 판정을 할 수 있는 표적 마커 칸: 내 칸, 그리고 옆 칸에서도 암살 판정을 할 수 있는 요원(assassin_adjacent)은 옆 칸의 표적
	var out := []
	if not _acting(p) or p["jailed"] or my_dice(p["id"]).is_empty():
		return out
	var cells := [p["pos"]]
	if flag(p, "assassin_adjacent"):
		for d in DIRS:
			cells.append(p["pos"] + d)
	for c in cells:
		var m := marker_at(c)
		if m.is_empty() or str(m["role"]) != "target":
			continue
		var cond := card_cond(str(m["id"]))
		if str(cond.get("kind", "")) != "assassinate":
			continue
		if c != p["pos"] and str(cond.get("check", "")) != "assassin":
			continue
		out.append(c)
	return out


func work_ok(id: String, value: int) -> bool:
	## 이 공작 카드에 이 눈을 바칠 수 있는가 (합이 남았나 · 조합에 필요한 눈인가 · 마커마다 하나)
	var st: Dictionary = mission_state.get(id, {})
	var cond := card_cond(id)
	if st.is_empty() or str(cond.get("kind", "")) != "work":
		return false
	match str(cond.get("mode", "")):
		"sum":
			return int(st["sum"]) < int(st["need"])
		"combo":
			return value in st["left"]
		"each":
			return true
	return false


func can_work_give(p: Dictionary, die: int) -> bool:
	## 내 칸에 공작 마커가 있고, 이 주사위를 바칠 수 있는가
	if not _acting(p) or p["jailed"] or not die in my_dice(p["id"]):
		return false
	var m := marker_at(p["pos"])
	return not m.is_empty() and str(m["role"]) == "work" and work_ok(str(m["id"]), die_value(die))


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
			"give_die":
				if my_dice(p["id"]).is_empty():
					return false
	return true


func ability_def(p: Dictionary) -> Dictionary:
	return char_def(p).get("ability", {})


func ability_costs_die(p: Dictionary) -> bool:
	return str(ability_def(p).get("cost", "")) == "die"


func _valid_choice(p: Dictionary, value) -> bool:
	if phase != "choice" or pending.get("player", -1) != p["id"]:
		return false
	for o in pending.get("options", []):
		if typeof(o["value"]) == typeof(value) and o["value"] == value:
			return true
	return false


const _TIE_WHO := {"isolated": "동료와 가장 멀리 떨어진(고립된) 요원", "wanted": "가장 많이 갇혔던(수배된) 요원", "nearest_to_base": "거점에 가장 가까운 요원"}
const _TIE_WHAT := {"police_attach": "그 요원에게 경찰이 붙습니다", "checkpoint_place": "그 요원 옆 빈칸에 검문소가 생깁니다",
	"discard_item": "그 요원이 아이템을 버립니다"}


# ================================================================ 저장 · 불러오기

const SAVE_FIELDS := ["players", "leader", "day", "rounds_total", "rounds_left", "act", "phase", "current",
	"steps_left", "board", "tile_deck", "police", "exposure", "intel", "ready", "threat_deck", "threat_discard",
	"threat_today", "mission_deck", "mission_discard", "mission_row", "event_deck", "event_discard",
	"item_deck", "item_discard", "bomb_supply", "op_dice", "today", "pending",
	"launch_info", "ending", "scenes", "scene_index", "scene_state", "intel_tokens", "search_queue", "effect_wait",
	"check", "morning_step", "last_roll", "saga_decks", "saga_discard",
	"saga_rewards", "launch_step", "launch_i", "human", "vote_state", "counter", "counter_queue",
	"markers", "mission_state", "op_row", "op_deck", "op_discard", "trend", "peek_bonus", "bonus_wait", "expire_queue", "marker_seq",
	"actions", "log_lines", "history", "stats"]


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
	if st.has("rng_seed"):   # 온라인 보기(NetViewV2)에는 난수 상태가 없다
		rng.seed = st["rng_seed"]
	if st.has("rng_state"):
		rng.state = st["rng_state"]
	events.clear()
	_dist_cache = {}
	for q in players:   # B단계 이전에 저장한 판에는 차례 상태가 없다
		if not q.has("fx_cells"):
			q["fx_cells"] = []
		if not q.has("hidden"):
			q["hidden"] = false


# ================================================================ 유틸

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _log(s: String) -> void:
	log_lines.append(josa(s))


# ---- 조사: 「%s이(가)」처럼 이름 · 숫자 뒤에 붙는 조사를 앞 글자의 받침에 맞춰 고른다

const _JOSA_PAIRS := [["이(가)", "이", "가"], ["을(를)", "을", "를"], ["은(는)", "은", "는"], ["과(와)", "과", "와"], ["와(과)", "과", "와"]]
const _JOSA_SKIP := "」』]）)\"'›》"
## 숫자를 읽을 때 마지막 소리의 받침: 0 영 · 1 일(ㄹ) · 3 삼 · 6 육 · 7 칠(ㄹ) · 8 팔(ㄹ)은 받침, 2 · 4 · 5 · 9는 없음
const _DIGIT_FINAL := {"0": 21, "1": 8, "2": 0, "3": 16, "4": 0, "5": 0, "6": 1, "7": 8, "8": 8, "9": 0}


static func _final_of(text: String, end: int) -> int:
	## text[end - 1]부터 거꾸로 닫는 괄호 · 따옴표를 건너뛰고 본 글자의 받침 번호 (0이면 받침 없음, 8이면 ㄹ, -1이면 알 수 없음)
	var i := end - 1
	while i >= 0 and _JOSA_SKIP.contains(text[i]):
		i -= 1
	if i < 0:
		return -1
	var c := text[i]
	var code := c.unicode_at(0)
	if code >= 0xAC00 and code <= 0xD7A3:
		return (code - 0xAC00) % 28
	if c.is_valid_int():
		if c == "0" and i > 0 and text[i - 1].is_valid_int():
			return 17   # 10 · 20 · 100 …: 십 · 백 · 천은 모두 받침이 있다 (ㄹ은 아님)
		return int(_DIGIT_FINAL[c])
	return -1


static func josa(text: String) -> String:
	## 「석 기술자이(가)」 → 「석 기술자가」, 「주사위 3이(가)」 → 「주사위 3이」, 「6(으)로」 → 「6으로」. 앞 글자를 모르면 그대로 둔다
	if not "(" in text:
		return text
	for pair in _JOSA_PAIRS:
		var at := text.find(pair[0])
		while at >= 0:
			var f := _final_of(text, at)
			if f >= 0:
				text = text.substr(0, at) + (pair[1] if f > 0 else pair[2]) + text.substr(at + pair[0].length())
				at = text.find(pair[0], at + 1)
			else:
				at = text.find(pair[0], at + pair[0].length())
	var ro := text.find("(으)로")
	while ro >= 0:
		var f2 := _final_of(text, ro)
		if f2 >= 0:
			text = text.substr(0, ro) + ("으로" if f2 > 0 and f2 != 8 else "로") + text.substr(ro + 4)
			ro = text.find("(으)로", ro + 1)
		else:
			ro = text.find("(으)로", ro + 4)
	return text


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

# ================================================================ 아래 층에서도 쓰는 도움 함수

func _new_tile(type: String) -> Dictionary:
	return {"type": type, "used": false, "flags": []}


func _new_today() -> Dictionary:
	return {"dice_mod": 0, "police_speed": 0, "escape_mod": 0, "scene_mod": 0, "move_today": {}, "ends": {}, "once": {}}


func _expand(defs: Array) -> Array:
	var out := []
	for d in defs:
		for i in int(d.get("count", 1)):
			out.append(d["id"])
	_shuffle(out)
	return out


func _roll_die() -> int:
	if not rigged_rolls.is_empty():
		return int(rigged_rolls.pop_front())   # 튜토리얼이 정해 둔 굴림 (저장하지 않음, 평소엔 비어 있음)
	return rng.randi_range(1, int(data.rules["die_sides"]))


func _use_die(p: Dictionary, i: int, use: String) -> void:
	op_dice[i]["used"] = true
	_push({"kind": "die_used", "player": p["id"], "die": i, "value": die_value(i), "use": use})


func _inert_tile(c: Vector2i) -> bool:
	## 깔려 있고, 옮겨 가 서도 아무 효과가 없는 칸 (거점·검문소·마커가 있는 칸은 아님)
	if not board.has(c):
		return false
	var t: String = board[c]["type"]
	if t == "base" or t == "check":
		return false
	return markers_at(c).is_empty()


func _d2(n := -1) -> int:
	var dice: Array = []
	var sum := 0
	for i in (int(data.rules["check_dice"]) if n < 0 else n):
		var d := _roll_die()
		dice.append(d)
		sum += d
	last_roll = dice
	return sum


func _check_label(c: Dictionary) -> String:
	return {"evade": "회피", "assassin": "암살", "escape": "탈옥", "generic": "작전"}.get(c["what"], str(c["what"]))


func _base_cell(base_id: String) -> Vector2i:
	var bi := data.base_index(base_id)
	return data.bases[bi] if bi >= 0 else Vector2i(-999, -999)


func _bases_in_range(c: Vector2i, dist: int) -> Array:
	## c에서 dist칸 안에 있는 거점 id
	var out := []
	for id in data.base_ids:
		if walk_dist(c, data.bases[data.base_index(id)]) <= dist:
			out.append(id)
	return out


func _has_op(effects: Array, op: String) -> bool:
	## 효과 목록(안쪽 then·else·choice 포함)에 이 op가 있는가
	for e in effects:
		if str(e.get("op", "")) == op:
			return true
		if _has_op(e.get("then", []), op) or _has_op(e.get("else", []), op):
			return true
		for o in e.get("options", []):
			if _has_op(o.get("effects", []), op):
				return true
	return false



# ================================================================ 위 층이 채우는 고리

## 아래 층이 부르지만 몸통은 위 층에 있는 함수. 여기 것은 자리만 잡고, 위 층이 같은 모양으로 덮어쓴다.

## → rules_v2.gd
func _morning_continue() -> void:
	pass


## → rules_v2.gd
func _night_after_scene() -> void:
	pass


## → rules_v2.gd
func _finish_move(_p: Dictionary) -> void:
	pass


## → rules_v2.gd
func _start_check(_p: Dictionary, _name: String, _ctx: String, _extra: Dictionary = {}) -> void:
	pass


## → rules_missions_v2.gd
func _drop_contacts(_p: Dictionary) -> void:
	pass


## → rules_v2.gd
func _run_effects(_p: Dictionary, _effects: Array, _ctx: Dictionary) -> void:
	pass


## → rules_saga_v2.gd
func _saga_reset(_p: Dictionary, _kind: String) -> void:
	pass


## → rules_saga_v2.gd
func _saga_note(_p: Dictionary, _kind: String, _ctx := {}) -> void:
	pass


## → rules_saga_v2.gd
func _saga_step_on(_p: Dictionary, _cell: Vector2i) -> void:
	pass


## → rules_saga_v2.gd
func _coop_participants(_id: String, _p: Dictionary, _ctx: Dictionary) -> Array:
	return []


## → rules_act2_v2.gd
func _scene_reveal() -> void:
	pass


## → rules_act2_v2.gd
func _scene_auto_break() -> void:
	pass
