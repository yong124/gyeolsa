class_name RulesV2
extends RefCounted
## 「결사 / 광복 IF」 v2 규칙 엔진.
##
## - 수치·카드·캐릭터는 전부 GameDataV2(data/v2/*.json)에서 읽는다. 카드 id나 캐릭터 id를 코드에 쓰지 않는다.
##   카드 효과는 `op`, 캐릭터·아이템 특성은 `stat` 이름, 미션은 `types[...].condition.kind`로 움직인다.
## - 모든 조작은 apply(action) 한 곳으로. 모든 액션은 "player" 키를 가진다.
##   계획 단계(plan)는 누구나, 낮(turn)은 차례인 요원만, 선택(choice)은 선택을 맡은 요원만 보낼 수 있다.
## - 난수는 전부 rng 하나. 같은 시드 + actions = 같은 판.
## - legal_actions()는 apply가 받아들이는 액션과 정확히 같다.
##
## 낮 (11·12단계): 주사위 1개 = 행동 1개. 차례를 시작하면 「행동 고르기」가 이어지고, end_turn으로 마친다.
##   행동(주사위 하나를 낸다): move_die · mission_check · work_give · escape · scene_check · scene_pay · give_die · give_item · decoy · hide · scout · market
##   공짜(주사위 없이): use_item(차례에 1장) · ability(하루 1번, cost "die"인 능력은 주사위를 냄) · use_intel · end_move · end_turn
##
## 액션
##   {"type": "start_day", "player"}                      (plan) 하루 시작 (아침 능력·아이템을 쓴 뒤)
##   {"type": "begin_turn", "player"}                     (day) 내 차례를 시작 (자유 순서, 한 번에 한 요원)
##   {"type": "move_die", "player", "die"}                (turn) 주사위 하나로 그 눈만큼 걷기 시작 (걷는 중에는 다른 행동 못 함)
##   {"type": "step", "player", "to": Vector2i}           (turn) 한 칸 이동 (경찰이 있는 칸은 못 들어감)
##   {"type": "end_move", "player"}                       (turn, 이동 중) 남은 칸을 버리고 멈춤. 멈춘 칸의 효과를 받는다 (같은 칸은 한 차례에 한 번)
##   {"type": "mission_check", "player", "die", "cell"}   (turn) 암살 표적 마커(옆 칸이면 저격수 오)에서 작전 판정: 낸 눈 + 새 주사위
##   {"type": "work_give", "player", "die"}               (turn) 내 칸의 공작 마커에 주사위를 바침 (합 · 눈 조합 · 마커마다 하나)
##   {"type": "escape", "player", "die"}                  (turn, 갇힘) 탈옥 작전 판정
##   {"type": "scene_check", "player", "die"}             (2막 turn) 장면 작전 판정
##   {"type": "scene_pay", "player", "what", "die"?, "index"?, "with"?}  (2막 turn) 장면에 바침 (아이템·폭탄은 with로 주사위 하나를 냄)
##   {"type": "give_die", "player", "die", "target"}      (turn) 같은 칸 동료에게 이 주사위를 줌 (하루 give_per_day번, 차례를 마친 요원에게는 안 됨, 갇힌 요원은 옆 칸에서 면회)
##   {"type": "give_item", "player", "die", "index", "to"} (turn) 같은 칸이나 옆 칸 동료에게 아이템 1장
##   {"type": "decoy", "player", "die", "from"}           (turn) 3칸 안 동료를 쫓는 경찰을 내 쪽으로
##   {"type": "hide", "player", "die"}                    (turn) 숨기: 이번 차례 끝에 내 경찰이 다가오지 않음 (rules.hide의 칸에서만)
##   {"type": "scout", "player", "die"}                   (turn) 정찰: 눈만큼 떨어진 덮인 칸 2곳의 타일을 앞면으로 깜 (pick_cell로 고름)
##   {"type": "market", "player", "die", "offer"}         (turn) 장터 칸에서 군자금으로 사기 (offer = rules.market.offers의 id)
##   {"type": "end_turn", "player"}                       (turn) 차례 마치기: 「차례를 마치면」 효과 → 내 경찰 이동 → 끝
##   {"type": "use_item", "player", "index"}              (plan: 아침 아이템 / turn) 아이템 사용 (차례에 1장)
##   {"type": "ability", "player", "target"?, "die"?}     캐릭터 능력 (하루 1회)
##   {"type": "use_intel", "player", "mode": "check"|"dice"}  (2막 turn) 첩보 토큰 사용
##   {"type": "choose", "player", "value"}                (choice) 선택지 응답
##
## 선택(choice)의 종류에는 saga_keep(결행 순간에 남길 사연, 비밀)도 있다.
## 작전 판정(암살·탈옥·장면)은 행동이라 늘 주사위 하나를 낸다 (낸 눈 + op_check_dice개). 주사위 없이 하는 판정은 없다.
## 실패해도 다른 주사위로 또 판정할 수 있다 (또 한 행동). 강제 판정(회피·검문·수색)은 주사위 없이 2d6.
##
## 작전 주사위 (7단계, Dead of Winter식): 아침에 요원마다 personal_dice개(2막 + act2_personal_dice_extra)를 굴린다.
## 모두 공개. 행동 하나에 하나씩 쓰고, 남은 것은 밤에 사라진다.
##
## 단계(phase): morning(자동) → plan → day ⇄ turn (+ choice) → (밤) → morning … → over

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
var funds := 0                  # 군자금 (팀 공용, 0~rules.funds.max)

var actions: Array = []
var events: Array = []
var log_lines: Array = []
var history: Array = []
var _dist_cache := {}           # 걸어서 잰 거리 (깔린 칸이 늘면 비움, 저장하지 않음)
var _dist_cache_size := -1


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
	markers = []
	mission_state = {}
	op_row = []
	op_deck = data.op_deck()
	_shuffle(op_deck)
	op_discard = []
	trend = 0
	peek_bonus = 0
	bonus_wait = []
	expire_queue = []
	marker_seq = 0
	funds = int(R["funds"]["start"])
	event_deck = _expand(data.events.get("events", []))
	event_discard = []
	item_deck = _expand(data.items.get("items", []))
	item_discard = []
	bomb_supply = int(R["bomb_supply"])
	_setup_saga_decks()
	saga_rewards = []
	launch_step = 0
	launch_i = 0
	vote_state = {}
	counter = {}
	counter_queue = []
	human = -1
	players = []
	for i in player_defs.size():
		var d: Dictionary = player_defs[i]
		if bool(d.get("human", false)):
			human = i
		players.append({
			"id": i, "name": d.get("name", "요원 %d" % (i + 1)), "character": d["character"],
			"pos": data.start, "jailed": false, "jail_count": 0,
			"items": [], "bombs": 0, "move_mod_next": 0, "dice_next": 0, "gives_today": 0,
			"done_today": false, "turns": 0, "fx_cells": [], "hidden": false,
			"ability_day": -1, "item_uses": 0, "grants": [], "flags": {},
			"sagas": [], "saga_done": "", "saga_kept": "", "saga_track": {},
			"jailed_day": -99, "funds_earned": 0,
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
	op_dice = []
	today = _new_today()
	pending = {}
	launch_info = {}
	ending = {}
	scenes = []
	scene_index = 0
	scene_state = {}
	intel_tokens = 0
	search_queue = []
	effect_wait = []
	check = {}
	last_roll = []
	_dist_cache = {}
	actions.clear()
	events.clear()
	log_lines.clear()
	history.clear()
	_deal_sagas()
	_log("작전 개시. %d일 안에 결행을 준비하십시오." % rounds_total)
	_begin_morning(true)


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
			return ("%s이(가) 들고 있음" % players[h]["name"]) if h >= 0 else "아직 받지 않음"
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
	for id in GameDataV2.BASE_IDS:
		if int(intel[id]) == best:
			out.append(id)
	return out


func launch_candidates() -> Array:
	## 결행 대상 후보: 첩보가 rules.launch.target_min_intel 이상인 거점. 없으면 첩보가 가장 높은 거점.
	var out := []
	for id in GameDataV2.BASE_IDS:
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


func _give_reach(p: Dictionary, q: Dictionary) -> int:
	## 건네기가 닿는 거리 (칸). 갇힌 요원과는 옆 칸(면회)까지, 아니면 give_range (같은 칸)
	return 1 if p["jailed"] or q["jailed"] else int(data.rules["give_range"])


func give_die_targets(p: Dictionary) -> Array:
	## 주사위를 건넬 수 있는 동료. 차례를 마친 요원에게는 안 되고, 하루 give_per_day번.
	var out := []
	if not _acting(p) or int(p["gives_today"]) >= int(data.rules["give_per_day"]) or my_dice(p["id"]).is_empty():
		return out
	for q in players:
		if q["id"] != p["id"] and not q["done_today"] and _manhattan(q["pos"], p["pos"]) <= _give_reach(p, q):
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


func scout_cells(p: Dictionary, die: int) -> Array:
	## 정찰로 앞면으로 깔 수 있는 덮인 칸: 눈만큼 떨어진 곳까지
	var out := []
	if not _acting(p) or p["jailed"] or not die in my_dice(p["id"]) or tile_deck.is_empty():
		return out
	var r := die_value(die)
	for x in range(p["pos"].x - r, p["pos"].x + r + 1):
		for y in range(p["pos"].y - r, p["pos"].y + r + 1):
			var c := Vector2i(x, y)
			if in_bounds(c) and not board.has(c) and _manhattan(c, p["pos"]) <= r:
				out.append(c)
	return out


func market_cost(p: Dictionary, offer: Dictionary) -> int:
	## 장터에서 이 요원이 내는 값 (주모 막례 아이템 1, 석 기술자 폭탄 2: 요원 특성의 cost_stat)
	var c := int(offer["cost"])
	if offer.has("cost_stat"):
		c += stat(p, str(offer["cost_stat"]))
	return maxi(1, c)


func market_offers(p: Dictionary) -> Array:
	## 지금 살 수 있는 것 (군자금이 되고 손패·폭탄 칸에 자리가 있을 때)
	var out := []
	for o in data.rules["market"]["offers"]:
		if funds < market_cost(p, o):
			continue
		match str(o.get("needs", "")):
			"item_slot":
				if p["items"].size() >= hand_limit(p):
					continue
			"bomb_slot":
				if p["bombs"] >= bomb_slots(p) or bomb_supply <= 0:
					continue
		out.append(o)
	return out


func can_market(p: Dictionary) -> bool:
	## 장터 칸에서 주사위가 있고 살 것이 있을 때
	var tile := str(data.rules["market"]["tile"])
	return tile != "" and _acting(p) and not p["jailed"] and tile_type(p["pos"]) == tile and not my_dice(p["id"]).is_empty() and not market_offers(p).is_empty()


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


func ability_targets(p: Dictionary) -> Array:
	## 능력을 쓸 수 있는 대상. 대상이 필요 없는 능력(self)이면 [-1] (target 없이 보냄). 못 쓰면 [].
	var a: Dictionary = ability_def(p)
	if a.is_empty() or p["ability_day"] == day or p["jailed"]:
		return []
	if str(a.get("cost", "")) == "die" and (steps_left > 0 or my_dice(p["id"]).is_empty()):
		return []   # 주사위를 내는 능력은 이동 중에는 못 쓴다
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
	if req.has("base_in_range") and _bases_in_range(p["pos"], int(req["base_in_range"])).is_empty():
		return []
	var kind: String = str(a.get("target", "self"))
	if kind == "self":
		return [-1]
	var gives_die := _has_op(a.get("effects", []), "give_die")   # 주사위 건네기는 감옥의 동료에게도 닿는다 (차례를 마친 요원에게는 안 됨)
	var out := []
	for q in players:
		if q["id"] == p["id"] or (q["jailed"] and not gives_die) or (gives_die and q["done_today"]):
			continue
		var d := walk_dist(q["pos"], p["pos"])
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


func ability_costs_die(p: Dictionary) -> bool:
	return str(ability_def(p).get("cost", "")) == "die"


func give_options(p: Dictionary) -> Array:
	## 건넬 수 있는 (아이템, 동료) 조합 [{"index", "to"}]. 같은 칸이나 옆 칸 동료에게, 갇힌 동료와는 옆 칸(면회)에서.
	## 행동이라 주사위 하나를 내야 한다 (눈은 상관없음).
	var out := []
	if not _acting(p) or my_dice(p["id"]).is_empty():
		return out
	var coop: Dictionary = data.rules["coop"]
	if bool(coop["give_counts_as_item_use"]) and p["item_uses"] >= int(data.rules["item_uses_per_turn"]):
		return out
	for q in players:
		if q["id"] == p["id"] or _manhattan(q["pos"], p["pos"]) > int(coop["give_range"]):
			continue
		for i in p["items"].size():
			out.append({"index": i, "to": q["id"]})
	return out


func decoy_options(p: Dictionary) -> Array:
	## 미끼로 끌어올 수 있는 경찰 [요원 id]. 행동이라 주사위 하나를 내야 한다.
	var out := []
	if not _acting(p) or p["jailed"] or police.has(p["id"]) or my_dice(p["id"]).is_empty():
		return out
	var coop: Dictionary = data.rules["coop"]
	if int(p["flags"].get("decoys", 0)) >= int(coop["decoy_per_turn"]):
		return out
	for pid in police:
		if pid != p["id"] and walk_dist(police[pid]["pos"], p["pos"]) <= int(coop["decoy_range"]):
			out.append(pid)
	return out


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
		"plan":
			for p in players:
				for ii in p["items"].size():
					if can_use_item(p, ii):
						out.append({"type": "use_item", "player": p["id"], "index": ii})
				_append_ability_actions(out, p)
			if can_start_day():
				for p in players:
					out.append({"type": "start_day", "player": p["id"]})
		"day":
			for p in players:
				if can_begin_turn(p):
					out.append({"type": "begin_turn", "player": p["id"]})
		"turn":
			out.append_array(_turn_actions(players[current]))
	return out


func _turn_actions(p: Dictionary) -> Array:
	## 지금 행동 고르기(또는 이동 중)인 요원이 할 수 있는 것
	var out := []
	var pid: int = p["id"]
	var moving: bool = steps_left > 0 and not p["jailed"]
	if moving:
		for to in legal_steps(p):
			out.append({"type": "step", "player": pid, "to": to})
		out.append({"type": "end_move", "player": pid})
	else:
		out.append({"type": "end_turn", "player": pid})
	for ii in p["items"].size():
		if can_use_item(p, ii):
			out.append({"type": "use_item", "player": pid, "index": ii})
	_append_ability_actions(out, p)
	if moving:
		return out   # 걷는 동안에는 공짜 행동(아이템·능력)만 더 할 수 있다
	var dice := my_dice(pid)
	for i in dice:
		if can_move_die(p, i):
			out.append({"type": "move_die", "player": pid, "die": i})
		if can_escape(p):
			out.append({"type": "escape", "player": pid, "die": i})
		if can_hide(p):
			out.append({"type": "hide", "player": pid, "die": i})
		if can_market(p):
			for o in market_offers(p):
				out.append({"type": "market", "player": pid, "die": i, "offer": str(o["id"])})
		if not scout_cells(p, i).is_empty():
			out.append({"type": "scout", "player": pid, "die": i})
		for c in mission_check_cells(p):
			out.append({"type": "mission_check", "player": pid, "die": i, "cell": c})
		if can_work_give(p, i):
			out.append({"type": "work_give", "player": pid, "die": i})
		for o in give_options(p):
			out.append({"type": "give_item", "player": pid, "die": i, "index": o["index"], "to": o["to"]})
		for from in decoy_options(p):
			out.append({"type": "decoy", "player": pid, "die": i, "from": from})
		for t in give_die_targets(p):
			out.append({"type": "give_die", "player": pid, "die": i, "target": t})
	out.append_array(scene_options(p))
	return out


func _append_ability_actions(out: Array, p: Dictionary) -> void:
	for t in ability_targets(p):
		var a := {"type": "ability", "player": p["id"]}
		if t >= 0:
			a["target"] = t
		if ability_costs_die(p):
			for i in my_dice(p["id"]):
				var b := a.duplicate()
				b["die"] = i
				out.append(b)
		else:
			out.append(a)


# ================================================================ 액션 처리

func apply(action: Dictionary) -> bool:
	if not action in legal_actions():
		return false
	var ok := _apply(action)
	if ok:
		actions.append(action.duplicate(true))
		_counter_refresh()
		_saga_idle_flush()
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
		"move_die":
			var i := _int_of(a.get("die", null))
			if not can_move_die(p, i):
				return false
			_move_die(p, i)
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
			_end_turn(p)
		"escape":
			var ed := _int_of(a.get("die", null))
			if not can_escape(p) or not ed in my_dice(pid):
				return false
			_begin_escape(p, ed)
		"mission_check":
			var md := _int_of(a.get("die", null))
			var mc := _cell_of(a.get("cell", null))
			if not md in my_dice(pid) or not mc in mission_check_cells(p):
				return false
			_begin_mission_check(p, mc, md)
		"work_give":
			var wd := _int_of(a.get("die", null))
			if not can_work_give(p, wd):
				return false
			_work_give(p, wd)
		"counter_check":
			var cd := _int_of(a.get("die", null))
			if not can_counter_check(p) or not cd in my_dice(pid):
				return false
			_start_check(p, "generic", "counter", {"target": int(data.rules["counter"]["target"]), "die_i": cd})
		"hide":
			var hd := _int_of(a.get("die", null))
			if not can_hide(p) or not hd in my_dice(pid):
				return false
			_hide(p, hd)
		"scout":
			var sd := _int_of(a.get("die", null))
			if scout_cells(p, sd).is_empty():
				return false
			_scout(p, sd)
		"market":
			var kd := _int_of(a.get("die", null))
			var offer := str(a.get("offer", ""))
			if not can_market(p) or not kd in my_dice(pid) or not offer in market_offers(p).map(func(o): return str(o["id"])):
				return false
			_market(p, kd, offer)
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
			var ad := -1
			if ability_costs_die(p):
				ad = _int_of(a.get("die", null))
				if not ad in my_dice(pid):
					return false
			if not can_use_ability(p, t):
				return false
			_use_ability(p, t, ad)
		"give_item":
			var gi := _int_of(a.get("index", null))
			var to_id := _int_of(a.get("to", null))
			var gd := _int_of(a.get("die", null))
			var found := false
			for o in give_options(p):
				if o["index"] == gi and o["to"] == to_id:
					found = true
			if not found or not gd in my_dice(pid):
				return false
			_use_die(p, gd, "give")
			_give_item(p, gi, players[to_id])
		"decoy":
			var from := _int_of(a.get("from", null))
			var dd := _int_of(a.get("die", null))
			if not from in decoy_options(p) or not dd in my_dice(pid):
				return false
			_use_die(p, dd, "decoy")
			_decoy(p, from)
		"give_die":
			var di := _int_of(a.get("die", null))
			var tgt := _int_of(a.get("target", null))
			if not di in my_dice(pid) or not tgt in give_die_targets(p):
				return false
			_give_die(p, di, players[tgt])
		"scene_check":
			var scd := _int_of(a.get("die", null))
			if not _scene_can_check(p) or not scd in my_dice(pid):
				return false
			_scene_check(p, scd)
		"scene_pay":
			var what := str(a.get("what", ""))
			var index := _int_of(a.get("die", null)) if what == "die" else _int_of(a.get("index", null))
			var spend := _int_of(a.get("with", null)) if what != "die" else -1
			if not _scene_can_pay(p, what, index) or (what != "die" and not spend in my_dice(pid)):
				return false
			_scene_pay(p, what, index, spend)
		"use_intel":
			var mode := str(a.get("mode", ""))
			if not _scene_can_intel(p, mode):
				return false
			_scene_use_intel(p, mode)
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
		q["done_today"] = false
		q["item_uses"] = 0
		q["gives_today"] = 0
		q["fx_cells"] = []
		q["hidden"] = false
	op_dice = []
	phase = "morning"
	current = -1
	_log("── %s 아침 (남은 %d일) · 리더 %s ──" % [date_label(), rounds_left, players[leader]["name"]])
	_push({"kind": "morning", "day": day, "leader": leader})
	morning_step = 1
	_morning_continue()


func _morning_continue() -> void:
	## 아침 순서(규칙서): 위협 → 일제 작전(짝수 날) → 표적 이동·기한 → 투표 → 미션 줄 → 작전 주사위. 선택이 끼면 멈췄다 이어간다.
	## 일제 작전, 표적 이동·기한, 투표, 미션 줄은 1막에서만 한다.
	while morning_step <= 6 and phase == "morning":
		var s := morning_step
		morning_step += 1
		match s:
			1: _morning_threat()
			2: _morning_ops()
			3: _morning_markers()
			4:
				if act == 1:
					_morning_vote()
			5:
				if act == 1:
					_fill_mission_row()
				else:
					_counter_refresh()
			6: _morning_dice()


func _morning_threat() -> void:
	_flip_threat({"then": "morning", "source": "threat"})


func _flip_threat(ctx: Dictionary) -> void:
	if threat_deck.is_empty():
		threat_deck = threat_discard
		threat_discard = []
		_shuffle(threat_deck)
	if threat_deck.is_empty():
		_continue(players[leader], ctx)
		return
	var id: String = threat_deck.pop_back()
	threat_discard.append(id)
	threat_today = id
	var card: Dictionary = data.threat(id)
	_log("[일제 위협] %s - %s" % [card.get("name", id), card.get("text", "")])
	_record("위협: %s" % card.get("name", id), "warn")
	_push({"kind": "card", "deck": "threat", "id": id, "player": -1})
	_push({"kind": "threat", "id": id})
	_run_effects(players[leader], card.get("effects", []), ctx)


func _morning_vote() -> void:
	var R: Dictionary = data.rules
	if rounds_left <= int(R["forced_launch_days_left"]):
		_log("작전일이 코앞입니다. 더 기다릴 수 없습니다! 결행 대상을 정합니다.")
		_start_vote(true)
		return
	if ready >= int(R["launch_min"]):
		_start_vote(false)


func _start_vote(forced: bool) -> void:
	## 결행 투표: 요원마다 찬반(강제 결행이면 대상만)과 대상을 비공개로 고르고, 모두 낸 뒤 한꺼번에 공개한다.
	var order: Array = players.map(func(q): return q["id"])
	if human >= 0 and human < players.size():
		order.erase(human)
		order.push_front(human)   # 연습 모드: 사람이 먼저 내고 AI 표와 함께 공개된다
	vote_state = {"forced": forced, "order": order, "votes": {}, "targets": {}}
	_vote_next()


func _vote_next() -> void:
	var forced: bool = vote_state["forced"]
	for pid in vote_state["order"]:
		var q: Dictionary = players[pid]
		if not forced and not vote_state["votes"].has(pid):
			var prompt := "결행하시겠습니까? 결행 준비 %d · 경계 %d단계 · 남은 %d일 (표는 모두 낸 뒤 공개됩니다)" % [ready, alert_level(), rounds_left]
			_ask(q, "launch_vote", prompt, [{"value": true, "label": "결행한다"}, {"value": false, "label": "하루 더 준비한다"}], {"then": "morning"})
			pending["secret"] = true
			return
		if not vote_state["targets"].has(pid):
			var opts := []
			for id in launch_candidates():
				opts.append({"value": id, "label": "%s · 첩보 %d" % [data.base_names[data.base_index(id)], int(intel[id])]})
			var tp := "결행할 거점을 고르세요. 첩보 %d 이상인 곳이 후보입니다." % int(data.rules["launch"]["target_min_intel"])
			_ask(q, "launch_target", tp, opts, {"then": "morning"})
			pending["secret"] = true
			return
	_vote_resolve()


func _vote_resolve() -> void:
	var vs := vote_state
	vote_state = {}
	var forced: bool = vs["forced"]
	var votes: Dictionary = vs["votes"]
	var targets: Dictionary = vs["targets"]
	_push({"kind": "vote_reveal", "forced": forced, "votes": votes.duplicate(), "targets": targets.duplicate()})
	var tally := {}
	for pid in targets:
		tally[targets[pid]] = int(tally.get(targets[pid], 0)) + 1
	var parts := []
	for id in tally:
		parts.append("%s %d표" % [data.base_names[data.base_index(id)], tally[id]])
	if not forced:
		var yes := 0
		for pid in votes:
			if votes[pid]:
				yes += 1
		_log("결행 투표: 찬성 %d, 반대 %d · 대상 %s" % [yes, votes.size() - yes, ", ".join(parts)])
		var lead_vote: bool = bool(votes.get(leader, false))
		if not (yes * 2 > votes.size() or (yes * 2 == votes.size() and lead_vote)):
			_log("결행을 하루 미루고 준비를 계속합니다.")
			_morning_continue()
			return
	else:
		_log("강제 결행 대상 투표: %s" % ", ".join(parts))
	var best := 0
	for id in tally:
		best = maxi(best, int(tally[id]))
	var top := []
	for id in GameDataV2.BASE_IDS:
		if int(tally.get(id, 0)) == best:
			top.append(id)
	_launch("forced" if forced else "vote", "", top)


func _fill_mission_row() -> void:
	## 공개 미션이 줄 수만큼 되도록 채우고, 새 미션의 마커를 보드에 놓는다
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
		mission_row.append(id)
		_place_card(id)
		_push({"kind": "card", "deck": "mission", "id": id, "player": -1})
	_log("공개 미션: %s" % ", ".join(mission_row.map(func(i): return data.mission(i).get("name", i))))


func _roll_die() -> int:
	return rng.randi_range(1, int(data.rules["die_sides"]))


func _morning_dice() -> void:
	## 요원마다 작전 주사위를 굴린다 (갇힌 요원도). 내일 몫 보정(dice_next)은 여기서 쓰고 지운다.
	op_dice = []
	var parts := []
	var n0 := int(data.rules["personal_dice"]) + (int(data.rules["act2_personal_dice_extra"]) if act == 2 else 0)
	for q in players:
		var n := maxi(0, n0 + int(q["dice_next"]))
		q["dice_next"] = 0
		var vals := []
		for k in n:
			var v := _roll_die()
			op_dice.append({"value": v, "owner": q["id"], "used": false})
			vals.append(v)
		parts.append("%s %s" % [q["name"], " ".join(vals.map(func(x): return str(x))) if not vals.is_empty() else "없음"])
		_saga_note_multi(q, ["rolled_value"], {"values": vals})
	_log("작전 주사위: " + " · ".join(parts))
	_push({"kind": "dice_rolled", "values": op_dice.map(func(d): return d["value"]),
		"owners": op_dice.map(func(d): return d["owner"])})
	phase = "plan"
	current = -1


# ================================================================ 계획

func _start_day() -> void:
	phase = "day"
	current = -1
	_log("하루가 시작됩니다.")
	_push({"kind": "day_start", "day": day})


func _use_die(p: Dictionary, i: int, use: String) -> void:
	op_dice[i]["used"] = true
	_push({"kind": "die_used", "player": p["id"], "die": i, "value": die_value(i), "use": use})


func _move_die(p: Dictionary, i: int) -> void:
	## 이동 행동: 주사위 하나의 눈만큼 걷는다. 보정(오늘 이동 +, 다음 이동 +)은 그 차례의 첫 이동 행동에 붙는다.
	var mv := move_value(p, i)
	var extra := int(p["flags"].get("move_extra", 0)) + int(p["move_mod_next"])
	p["flags"]["move_extra"] = 0
	p["move_mod_next"] = 0
	_use_die(p, i, "move")
	steps_left = maxi(mv + extra, 1)
	_log("%s: 주사위 %d로 이동 %d칸%s" % [p["name"], die_value(i), steps_left,
		(" (보정 %+d)" % extra) if extra != 0 else ""])


func _give_die(p: Dictionary, i: int, q: Dictionary, counts_daily := true) -> void:
	## counts_daily가 false이면 하루 건네기 횟수(gives_today)에 세지 않는다 (정 인쇄공 「연락망」)
	op_dice[i]["owner"] = q["id"]
	if counts_daily:
		p["gives_today"] = int(p["gives_today"]) + 1
	p["stats"]["gives"] += 1
	_log("%s: %s에게 주사위 %d을(를) 건넸습니다." % [p["name"], q["name"], die_value(i)])
	_push({"kind": "die_given", "player": p["id"], "target": q["id"], "die": i, "value": die_value(i)})
	_saga_note(p, "give_dice", {"target": q["id"]})


# ================================================================ 낮: 차례

func _begin_turn(p: Dictionary) -> void:
	phase = "turn"
	current = p["id"]
	p["turns"] += 1
	p["flags"]["decoys"] = 0
	p["flags"]["escape_add"] = 0
	p["flags"].erase("intel_check")
	p["fx_cells"] = []
	p["hidden"] = false
	steps_left = 0
	_push({"kind": "turn", "player": p["id"]})
	if p["jailed"]:
		_log("%s: 감옥에서 차례를 맞았습니다." % p["name"])
		return
	# 오늘 이동 보정은 이 차례의 첫 이동 행동에 붙는다 (다음 이동 보정 move_mod_next도 그때 함께 붙음)
	p["flags"]["move_extra"] = int(today["move_today"].get(p["id"], 0)) + stat(p, "move_bonus")


func _end_turn(p: Dictionary) -> void:
	## 차례 마치기: (이 차장 한 칸) → 「차례를 마치면」 효과(은신처) → 내 경찰 이동 (숨기를 했으면 안 움직임) → 끝
	steps_left = 0
	if p["jailed"]:
		_log("%s: 옥중에서 때를 기다립니다." % p["name"])
	elif _end_hop(p):
		return   # 선택이 끝나면 _end_turn_continue로 이어진다
	_end_turn_continue(p)


func _end_turn_continue(p: Dictionary) -> void:
	if phase == "over":
		return
	if not p["jailed"]:
		_turn_end_tile(p)
		_check_hideout(p)
		if p["hidden"]:
			_log("%s: 몸을 숨겨 경찰이 다가오지 못했습니다." % p["name"])
		else:
			_police_act(p)
	_finish_turn(p)


func _finish_turn(p: Dictionary) -> void:
	if phase == "over":
		return
	p["done_today"] = true
	p["hidden"] = false
	if act == 2 and not p["jailed"]:
		_scene_turn_end(p)
		if phase == "over":
			return
	p["flags"]["escape_add"] = 0
	p["flags"].erase("entry_no_police")     # 한 차례 안에만 쓰는 권리
	p["flags"]["checkpoint_pass"] = 0
	steps_left = 0
	phase = "day"
	current = -1
	_saga_turn_end(p)
	if _turn_end_missions(p):
		return   # 협동·잠복 미션 보상을 처리하는 중 (끝나면 _after_turn으로 이어짐)
	_after_turn()


func _after_turn() -> void:
	if phase == "over":
		return
	if _saga_flush({"then": "after_turn"}):
		return   # 이룬 사연의 보상 처리 중 (끝나면 다시 이어짐)
	for q in players:
		if not q["done_today"]:
			return
	_night()


func _night() -> void:
	_push({"kind": "night", "day": day})
	_night_end()


func _night_end() -> void:
	if _saga_flush({"then": "night_end"}):
		return
	if act == 2:
		if _scene_night():
			return   # 반격 회피 판정 처리 중 (끝나면 _counter_next가 이어 감)
		if phase == "over":
			return
	_night_after_scene()


func _night_after_scene() -> void:
	rounds_left -= 1
	if rounds_left <= 0:
		rounds_left = 0
		_end_game(false)
		return
	_begin_morning(false)


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
	var bribe := int(data.rules["checkpoint"]["bribe"])
	if funds >= bribe and evade_chance(p) < 1.0 and _grant_index(p, "evade_auto") < 0:
		_ask(p, "bribe", "검문소입니다. 판정(회피 %d) 대신 군자금 %d을 내고 지나갈 수 있습니다. (지금 %d)" % [check_target("evade"), bribe, funds],
			[{"value": true, "label": "뇌물 (군자금 %d)" % bribe}, {"value": false, "label": "판정으로 지나간다"}], {})
		pending["cell"] = to
		return
	_log("%s: 검문소 통과를 시도합니다." % p["name"])
	_start_check(p, "evade", "checkpoint", {"cell": to})


func _arrive(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to})
	steps_left -= 1
	_saga_step_on(p, to)
	var t: String = board[to]["type"]
	if t == "base":
		steps_left = 0
		_enter_base(p)
		return
	if _marker_arrive(p, to):
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
		if q["jailed"] and q["pos"] == p["pos"] and q["id"] != p["id"] \
				and not (act == 2 and p["pos"] == _base_cell(str(launch_info.get("target", "")))):
			q["jailed"] = false
			q["move_mod_next"] += stat(p, "rescued_move_bonus")
			p["stats"]["rescues"] += 1
			p["flags"]["rescued_turn"] = p["turns"]
			_saga_note(p, "rescue_or_escape", {"what": "rescue", "rescued": q["id"]})
			_log("%s: %s을(를) 구출했습니다!" % [p["name"], q["name"]])
			_record("%s — %s 구출" % [p["name"], q["name"]], "good")
			_banner("%s 구출!" % q["name"], "good", p)
			_push({"kind": "rescue", "player": p["id"], "rescued": q["id"]})
	for m in markers_at(p["pos"]):
		if str(m["role"]) == "pickup":
			_pickup(p, m)
	var ids := []
	for id in mission_row:
		var cond := card_cond(id)
		if str(cond.get("kind", "")) == "infiltrate" and str(cond.get("base", "")) == GameDataV2.BASE_IDS[bi]:
			ids.append(id)
	var ctx := {"then": "base_finish", "entered_base": bi}
	ids.append_array(_coop_enter_base(p, bi))
	if ids.is_empty():
		_base_finish(p, ctx)
		return
	for id in ids:
		var gear = card_cond(id).get("gear")
		if typeof(gear) == TYPE_DICTIONARY and gear_affordable(p, gear):
			_ask_gear(p, gear, {"kind": "base", "ids": ids, "ctx": ctx})
			return
	_complete_missions(p, ids, ctx)


func _base_finish(p: Dictionary, _ctx: Dictionary) -> void:
	if phase == "over":
		return
	if act == 2 and p["pos"] == _base_cell(str(launch_info.get("target", ""))):
		_log("%s: 결행 거점에서는 경찰이 붙지 않았습니다." % p["name"])
	elif flag(p, "base_no_police"):
		_log("%s: 경찰이 오지 않았습니다." % p["name"])
	elif p["flags"].get("entry_no_police", false):
		p["flags"].erase("entry_no_police")
		_log("%s: 이번에는 경찰이 붙지 않았습니다." % p["name"])
	else:
		_summon(p)
	_finish_move(p)


func _resolve_stop(p: Dictionary) -> void:
	## 이동을 마친 칸의 효과. 같은 칸의 효과는 한 차례에 한 번만 받는다.
	if phase == "over":
		return
	steps_left = 0
	var cell: Vector2i = p["pos"]
	if cell in p["fx_cells"]:
		_finish_move(p)
		return
	p["fx_cells"].append(cell)
	var tile: Dictionary = board.get(cell, {})
	var fx: Dictionary = data.rules.get("tile_effects", {}).get(str(tile.get("type", "")), {})
	if fx.has("on_stop") and not (fx.has("once") and bool(tile.get("used", false))):
		if fx.has("once"):
			tile["used"] = true
			tile["type"] = str(fx["once"])
		_run_effects(p, fx["on_stop"], {"then": "post_move", "source": "tile"})
		return
	_finish_move(p)


func _turn_end_tile(p: Dictionary) -> void:
	## 차례를 마친 칸의 타일 효과 (rules.tile_effects의 on_turn_end): 주막은 같은 칸에 동료가 있으면 하루 한 번 노출 -1
	var t := tile_type(p["pos"])
	var fx: Dictionary = data.rules.get("tile_effects", {}).get(t, {})
	if not fx.has("on_turn_end"):
		return
	if str(fx.get("needs", "")) == "ally_here":
		var any := false
		for q in players:
			if q["id"] != p["id"] and not q["jailed"] and q["pos"] == p["pos"]:
				any = true
		if not any:
			return
	if bool(fx.get("once_per_day", false)):
		if today["once"].has(t):
			return
		today["once"][t] = true
	_log("%s: %s 칸의 효과를 받습니다." % [p["name"], tile_label(t)])
	_push({"kind": "tile_fx", "player": p["id"], "tile": t})
	_run_effects(p, fx["on_turn_end"], {"then": "resume", "source": "tile"})


func _check_hideout(p: Dictionary) -> void:
	var tile: Dictionary = board.get(p["pos"], {})
	if tile.get("flags", []).has(str(data.rules["hideout_flag"])) and police.has(p["id"]):
		_police_off(p["id"], "hideout")
		_log("%s: 은신처에 숨어 추적하던 경찰을 따돌렸습니다." % p["name"])
		_push({"kind": "police"})


func _inert_tile(c: Vector2i) -> bool:
	## 깔려 있고, 옮겨 가 서도 아무 효과가 없는 칸 (거점·검문소·마커가 있는 칸은 아님)
	if not board.has(c):
		return false
	var t: String = board[c]["type"]
	if t == "base" or t == "check":
		return false
	return markers_at(c).is_empty()


func _teleport(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to, "jump": true})
	_saga_step_on(p, to)


func hop_cells(p: Dictionary) -> Array:
	## end_move_hop_to_ally: 차례를 마칠 때 한 칸 옮겨 갈 수 있는, 동료가 있는 옆 칸 (깔린 칸, 경찰이 없는 칸)
	var out := []
	for d in DIRS:
		var n: Vector2i = p["pos"] + d
		if not _inert_tile(n) or police_on(n):
			continue
		for q in players:
			if q["id"] != p["id"] and not q["jailed"] and q["pos"] == n:
				out.append(n)
				break
	return out


func _end_hop(p: Dictionary) -> bool:
	## 차례를 마칠 때 동료가 있는 옆 칸으로 한 칸 옮길지 묻는다 (end_move_hop_to_ally). 물었으면 true.
	if phase == "over" or p["jailed"] or not flag(p, "end_move_hop_to_ally"):
		return false
	var cells := hop_cells(p)
	if cells.is_empty():
		return false
	var opts := [{"value": "no", "label": "그대로 있는다"}]
	for c in cells:
		opts.append({"value": c, "label": "(%d, %d)칸 동료 곁으로 옮긴다" % [c.x, c.y]})
	_ask(p, "hop", "동료가 있는 옆 칸으로 한 칸 옮기시겠습니까?", opts, {})
	return true


func _finish_move(p: Dictionary) -> void:
	## 이동 행동 하나가 끝났다 (칸 효과까지). 걸음이 남았으면 계속 걷고, 아니면 행동 고르기로 돌아간다.
	if phase == "turn" and steps_left > 0 and not p["jailed"] and p["id"] == current:
		return
	steps_left = 0


# ================================================================ 판정

func _start_check(p: Dictionary, name: String, ctx: String, extra: Dictionary = {}) -> void:
	## name: rules.checks의 판정 이름. 보정은 stat "<name>_bonus" (+ 미션 종류별 보정)
	var target: int = int(extra["target"]) if extra.has("target") else check_target(name)
	var bonus: int = stat(p, name + "_bonus")
	bonus += int(extra.get("intel_bonus", 0))
	if extra.has("type_bonus") and str(extra["type_bonus"]) != name:
		bonus += stat(p, str(extra["type_bonus"]) + "_bonus")
	if name == "escape":
		bonus += int(today.get("escape_mod", 0)) + int(p["flags"].get("escape_add", 0))
	check = {"what": name, "ctx": ctx, "player": p["id"], "target": target, "bonus": bonus,
		"auto_rerolls": stat(p, name + "_rerolls"), "dice": [], "total": 0}
	for k in extra:
		check[k] = extra[k]
	if extra.has("die_i"):
		# 작전 판정은 행동이다: 낸 주사위의 눈 + 새 주사위. 보정이나 자동 성공으로 바로 끝나도 주사위는 쓴 것이다.
		var di := int(extra["die_i"])
		check["die_value"] = die_value(di)
		_use_die(p, di, "check")
		_log("%s: 주사위 %d을(를) 내어 %s 판정" % [p["name"], die_value(di), _check_label(check)])
	# 한 번 쓰는 권리: 판정 보정 (이번 판정에 자동으로 더함)
	var gi := _grant_index(p, "check_bonus", ctx == "scene")
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
	if check.has("gear") and gear_affordable(p, check["gear"]):
		_ask_gear(p, check["gear"], {"kind": "check"})
		return
	_check_roll(p)


func check_preview(p: Dictionary, a: Dictionary) -> Dictionary:
	## 작전 판정 행동(mission_check · escape · scene_check)의 목표와 보정 {"target", "bonus"} (성공 확률 미리 보기용).
	## 보정은 특성·아이템·첩보·한 번 쓰는 권리를 더한 값이다.
	var out := {"target": 99, "bonus": 0}
	match str(a.get("type", "")):
		"mission_check":
			var m := marker_at(_cell_of(a.get("cell", null)))
			if m.is_empty():
				return out
			var cond: Dictionary = card_cond(str(m["id"]))
			var name := str(cond["check"])
			out["target"] = int(cond["target"])
			out["bonus"] = stat(p, name + "_bonus") + (int(cond.get("informed_bonus", 0)) if bool(mission_state.get(m["id"], {}).get("informed", false)) else 0)
		"escape":
			out["target"] = check_target("escape")
			out["bonus"] = stat(p, "escape_bonus") + int(today.get("escape_mod", 0)) + int(p["flags"].get("escape_add", 0))
		"counter_check":
			out["target"] = int(data.rules["counter"]["target"])
			out["bonus"] = stat(p, "generic_bonus")
		"scene_check":
			var leaf := _scene_check_leaf(p)
			if leaf.is_empty():
				return out
			var cond2: Dictionary = leaf["cond"]
			var name2 := str(cond2.get("check", "generic"))
			out["target"] = (int(cond2["target"]) if cond2.has("target") else check_target(name2)) + int(today.get("scene_mod", 0))
			out["bonus"] = stat(p, name2 + "_bonus") + int(p["flags"].get("intel_check", 0))
	var gi := _grant_index(p, "check_bonus", str(a.get("type", "")) == "scene_check")
	if gi >= 0:
		out["bonus"] = int(out["bonus"]) + int(p["grants"][gi].get("value", 0))
	return out


func check_chance(c: Dictionary, die := 0) -> float:
	## 이 판정이 성공할 확률 (die > 0이면 그 눈 + op_check_dice개, 아니면 check_dice개)
	var sides := int(data.rules["die_sides"])
	var n := int(data.rules["op_check_dice"]) if die > 0 else int(data.rules["check_dice"])
	var need: int = int(c["target"]) - int(c["bonus"]) - die
	var dist := {0: 1.0}
	for k in n:
		var nd := {}
		for s0 in dist:
			for f in range(1, sides + 1):
				nd[s0 + f] = float(nd.get(s0 + f, 0.0)) + float(dist[s0]) / float(sides)
		dist = nd
	var ok := 0.0
	for s1 in dist:
		if int(s1) >= need:
			ok += float(dist[s1])
	return ok


func _react_item(p: Dictionary, when: String) -> String:
	for id in p["items"]:
		var it: Dictionary = item_def(id)
		if it.get("when", "") == when and it.has("effects"):
			return id
	return ""


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


func _d2(n := -1) -> int:
	var dice: Array = []
	var sum := 0
	for i in (int(data.rules["check_dice"]) if n < 0 else n):
		var d := _roll_die()
		dice.append(d)
		sum += d
	last_roll = dice
	return sum


func _check_roll(p: Dictionary) -> void:
	var c := check
	var dv := int(c.get("die_value", 0))
	var r := 0
	if dv > 0:
		r = dv + _d2(int(data.rules["op_check_dice"]))
		c["dice"] = [dv] + last_roll
	else:
		r = _d2()
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
	var gi := _grant_index(p, "reroll", str(c.get("ctx", "")) == "scene")
	if gi < 0:
		_check_done(p, false)   # 다시 하려면 「다시 굴리기」 권리가 있어야 한다 (작전 판정은 다른 주사위로 새 행동을 할 수 있음)
		return
	_ask(p, "reroll", "%s 판정에 실패했습니다. 다시 굴릴 권리를 쓰시겠습니까?" % label,
		[{"value": "no", "label": "그대로 실패로 한다"}, {"value": "grant", "label": "다시 굴릴 권리를 쓴다"}], {})


func _check_label(c: Dictionary) -> String:
	return {"evade": "회피", "assassin": "암살", "escape": "탈옥", "generic": "작전"}.get(c["what"], str(c["what"]))


func _check_done(p: Dictionary, ok: bool) -> void:
	var c := check
	check = {}
	match str(c["ctx"]):
		"checkpoint":
			if ok:
				_log("%s: 검문소를 무사히 통과했습니다." % p["name"])
				_banner("검문소 통과", "info", p)
				p["stats"]["checkpoints"] += 1
				_saga_note(p, "pass_checkpoint")
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
			# 미션 판정에 실패해 도망치는 중: 성공하면 경찰이 붙고 (같은 차례에 다른 주사위로 다시 판정할 수 있음), 실패하면 투옥
			if ok:
				_summon(p)
			else:
				_jail(p)
			_finish_move(p)
		"scene":
			_scene_check_result(p, c, ok)
		"counter":
			if ok:
				counter["blocked"] = true
				_log("%s: 반격을 막아 냈습니다!" % p["name"])
				_banner("반격을 막았다", "good", p)
				_push({"kind": "counter_blocked", "player": p["id"]})
			else:
				_log("%s: 반격을 막지 못했습니다." % p["name"])
		"counter_evade":
			if not ok:
				_jail(p)
			_counter_next()
		"search":
			if not ok:
				_summon(p)
			_search_next()
		"check_or_jail":
			if not ok:
				_jail(p)
			_stage4_resume()
		"escape":
			p["flags"]["escape_add"] = 0
			if ok:
				p["jailed"] = false
				p["stats"]["escapes"] += 1
				_saga_note(p, "rescue_or_escape", {"what": "escape"})
				_log("%s: 탈옥 성공!" % p["name"])
				_banner("탈옥 성공!", "good", p)
				_summon(p)
			else:
				_log("%s: 탈옥 실패." % p["name"])


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
	## 방금 들어간 칸의 마커. 암살 표적 칸에서는 이동이 멈춘다 (판정은 따로 행동으로). 정보원에 들르면 동선을 알아내고,
	## 받기 마커를 지나가면 물건을 들고, 폭탄을 들고 폭파 지점에 들어가거나 물건을 들고 주기 마커에 들어가면 이룬다.
	## 미션을 이뤄 보상 처리를 시작했으면 true.
	var done := []
	var stop := false
	var asking := {}
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
				var ic = card_cond(id).get("informer_cost")
				if typeof(ic) != TYPE_DICTIONARY:
					_use_informer(p, m)
				elif funds >= int(ic["funds"]) and not bool(mission_state.get(id, {}).get("informed", false)):
					asking = m
			"pickup":
				_pickup(p, m)
			"dropoff":
				if int(mission_state.get(id, {}).get("holder", -1)) == p["id"] and not id in done:
					done.append(id)
	if not done.is_empty():
		steps_left = 0
		_complete_missions(p, done, {"then": "stop", "source": "mission"})
		return true
	if not asking.is_empty():
		var cost := int(card_cond(str(asking["id"]))["informer_cost"]["funds"])
		_ask(p, "informer_pay", "정보원에게 사례금 군자금 %d을 낼까요? 동선을 알아내면 표적이 멈추고 판정이 쉬워집니다. (지금 %d)" % [cost, funds],
			[{"value": true, "label": "사례금 (군자금 %d)" % cost}, {"value": false, "label": "그냥 지나간다"}], {})
		pending["marker"] = int(asking["uid"])
		pending["stop"] = stop
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


# ---------------------------------------------------------------- 돈 대신 아이템 (gear) · 공작 · 판정

const GEAR_FUNDS := 1000   # 선택지 값: 이 값이면 군자금으로 낸다 (0 이상 1000 미만은 낼 아이템 번호)


func gear_affordable(p: Dictionary, gear: Dictionary) -> bool:
	## 이 값(cost: item 아이템 1장 또는 funds 군자금, 둘 다 있으면 하나를 고름)을 낼 수 있는가
	var c: Dictionary = gear["cost"]
	return (c.has("item") and not p["items"].is_empty()) or (c.has("funds") and funds >= int(c["funds"]))


func _ask_gear(p: Dictionary, gear: Dictionary, flow: Dictionary) -> void:
	## 값(아이템 1장 또는 군자금)을 내고 판정이나 거점 진입에 도움을 받을지 묻는다
	var c: Dictionary = gear["cost"]
	var opts := [{"value": -1, "label": "쓰지 않는다"}]
	if c.has("item"):
		for i in p["items"].size():
			opts.append({"value": i, "label": "[%s]을(를) 버린다" % item_def(p["items"][i])["name"]})
	if c.has("funds") and funds >= int(c["funds"]):
		opts.append({"value": GEAR_FUNDS, "label": "군자금 %d을 낸다 (지금 %d)" % [int(c["funds"]), funds]})
	_ask(p, "mission_gear", str(gear.get("text", "")), opts, {})
	pending["gear"] = gear
	pending["flow"] = flow


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
	if done:
		_complete_missions(p, [id], {"then": "resume", "source": "mission"})


func _begin_mission_check(p: Dictionary, cell: Vector2i, die: int) -> void:
	## 표적 마커에서 작전 판정 행동 (낸 눈 + 새 주사위). 동선을 알아냈으면 판정이 쉽고, 무기 조달(gear)은 판정 직전에 묻는다.
	var m := marker_at(cell)
	var id := str(m["id"])
	var cond := card_cond(id)
	var extra := {"ids": [id], "target": int(cond["target"]), "cell": cell, "die_i": die,
		"intel_bonus": int(cond.get("informed_bonus", 0)) if bool(mission_state.get(id, {}).get("informed", false)) else 0}
	if cond.has("gear"):
		extra["gear"] = cond["gear"]
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
		"rescued_this_turn":
			return int(p["flags"].get("rescued_turn", -1)) == p["turns"]
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
		_saga_note(p, "mission_done_by_me", {"id": id})
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


# ================================================================ 탈옥

func _begin_escape(p: Dictionary, die: int) -> void:
	_log("%s: 탈옥을 시도합니다." % p["name"])
	_start_check(p, "escape", "escape", {"die_i": die})


# ================================================================ 경찰 · 감옥 · 노출

func _summon(p: Dictionary, here := false) -> void:
	## 경찰이 이 요원에게 붙는다 (붙은 다음 차례부터 움직임). 새 경찰은 그 요원에게서 가장 가까운 거점에 나타나고
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
		var at: Vector2i = p["pos"] if here else data.bases[_nearest_base(p["pos"])]
		police[p["id"]] = {"pos": at, "summon_turn": p["turns"]}
		_log("%s: 경찰이 붙었습니다!" % p["name"])
	_push({"kind": "police"})


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
	## 투옥되면 갇힌 날을 적고 (옥중 동지 사연) 들고 있던 아이템을 압수당한다. 폭탄은 압수하지 않는다.
	p["jailed_day"] = day
	_confiscate(p, int(data.rules["jail"]["confiscate_items"]))


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
	var was_max := exposure >= int(data.rules["exposure"]["max"])
	exposure = clampi(exposure + n, 0, int(data.rules["exposure"]["max"]))
	_push({"kind": "exposure", "value": exposure})
	if exposure >= int(data.rules["exposure"]["max"]) and not was_max:
		var cap_loss := int(data.rules["funds"]["exposure_cap_loss"])
		if cap_loss > 0:
			_log("노출이 최대에 닿아 대대적 단속이 벌어졌습니다! 군자금 −%d" % cap_loss)
			_funds_change(-cap_loss, "cap")
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


func _give_item(p: Dictionary, idx: int, q: Dictionary) -> void:
	var id: String = p["items"][idx]
	p["items"].remove_at(idx)
	q["items"].append(id)
	if bool(data.rules["coop"]["give_counts_as_item_use"]):
		p["item_uses"] += 1
	p["stats"]["gives"] += 1
	_saga_note(p, "give_items")
	_saga_note(q, "hold_items")
	_log("%s: [%s]을(를) %s에게 건넸습니다." % [p["name"], item_def(id)["name"], q["name"]])
	if q["items"].size() > hand_limit(q):
		_ask_discard(q)


func _decoy(p: Dictionary, from: int) -> void:
	var pol: Dictionary = police[from]
	_police_off(from, "decoy")
	# 끌어온 경찰은 곧바로 나를 쫓는다 (이번 차례 끝에 움직임)
	police[p["id"]] = {"pos": pol["pos"], "summon_turn": p["turns"] - 1}
	p["flags"]["decoys"] = int(p["flags"].get("decoys", 0)) + 1
	_log("%s: 일부러 모습을 드러내 %s을(를) 쫓던 경찰을 유인했습니다!" % [p["name"], players[from]["name"]])
	_banner("미끼 작전!", "info", p)
	_push({"kind": "police"})


func _hide(p: Dictionary, die: int) -> void:
	## 숨기: 이번 차례 끝에 나를 쫓는 경찰이 다가오지 않는다
	_use_die(p, die, "hide")
	p["hidden"] = true
	_log("%s: 몸을 숨겼습니다. 이번 차례 끝에 경찰이 다가오지 못합니다." % p["name"])
	_banner("숨기", "info", p)


func _scout(p: Dictionary, die: int) -> void:
	## 정찰: 눈만큼 떨어진 곳까지의 덮인 칸 2곳의 타일을 앞면으로 깐다 (효과는 나중에 그 칸에서 이동을 마칠 때 받음)
	var r := die_value(die)
	_use_die(p, die, "scout")
	_log("%s: 주사위 %d로 정찰합니다." % [p["name"], r])
	_run_effects(p, [{"op": "scout_tiles", "range": r, "count": int(data.rules["scout"]["count"])}], {"then": "resume", "source": "scout"})


func _market(p: Dictionary, die: int, offer_id: String) -> void:
	## 장터 행동: 주사위 하나를 내고 군자금으로 아이템이나 폭탄을 산다
	var offer := {}
	for o in data.rules["market"]["offers"]:
		if str(o["id"]) == offer_id:
			offer = o
	var cost := market_cost(p, offer)
	_use_die(p, die, "market")
	_funds_change(-cost, "market")
	_log("%s: 장터에서 군자금 %d으로 %s을(를) 샀습니다." % [p["name"], cost, offer.get("name", "")])
	_push({"kind": "market_buy", "player": p["id"], "offer": offer_id, "cost": cost})
	_run_effects(p, offer.get("effects", []), {"then": "resume", "source": "market"})


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
		if str(e.get("op", "")) in ["search", "check_or_jail", "threat_flip"]:
			effect_wait.append({"player": p["id"], "rest": queue, "ctx": ctx})
			match str(e["op"]):
				"search":
					search_queue = []
					var base := _base_cell(str(launch_info.get("target", "")))
					for q in players:
						if not q["jailed"] and _manhattan(q["pos"], base) <= int(e.get("range", 0)):
							search_queue.append(q["id"])
					_search_next()
				"check_or_jail":
					_start_check(p, str(e.get("check", "evade")), "check_or_jail")
				"threat_flip":
					_flip_threat({"then": "stage4_effect"})
			return
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
		"saga":
			var nxt: Dictionary = ctx.get("next", {"then": "resume"})
			if not _saga_flush(nxt):
				_continue(p, nxt)
		"launch":
			_launch_continue()
		"stage4_effect":
			_stage4_resume()
		"scene_check_done":
			_finish_scene_check(p)
		"act2_scenes":
			_act2_scenes()
		"morning_expire":
			_morning_expire()
		_:
			pass   # "resume": 원래 단계로 돌아가 계속 진행


func _effect(p: Dictionary, e: Dictionary, ctx: Dictionary, queue: Array) -> bool:
	## 효과 하나를 실행한다. 선택지를 띄워 멈췄으면 true.
	var op: String = str(e.get("op", ""))
	match op:
		"police_dispatch":
			_op_police_dispatch(p, e, ctx)
		"event_card":
			_op_event_card(p, queue)
		"funds":
			_op_funds(p, e, queue)
		"funds_half":
			var keep := funds / 2
			_log("군자금이 절반이 되었습니다 (%d → %d)." % [funds, keep])
			_funds_change(keep - funds, "lose")
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
		"scout_tiles":
			return _op_scout(p, e, queue)
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
		_ask_pick(p, e, queue, "pid", "pick_player", "대상 동료를 고르세요.", _player_options(cands))
		return null
	var ids := _who_pick(p, who, e)
	if ids.size() > 1 and who in ["isolated", "wanted", "nearest_to_base"]:
		_ask_leader_pick(e, ids, queue)
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
		for id in GameDataV2.BASE_IDS:
			top = maxi(top, int(intel[id]))
		var tops := []
		for id in GameDataV2.BASE_IDS:
			if int(intel[id]) == top:
				tops.append(id)
		return data.base_index(tops[0] if tops.size() == 1 else tops[rng.randi_range(0, tops.size() - 1)])
	return data.base_index(b)


func _op_intel(p: Dictionary, e: Dictionary, ctx: Dictionary) -> bool:
	var v: int = int(e.get("value", 1))
	if str(e.get("base", "nearest")) == "choose":
		var opts := []
		var near_ids := _bases_in_range(p["pos"], int(e["range"])) if e.has("range") else GameDataV2.BASE_IDS.duplicate()
		if near_ids.is_empty():
			return false
		if near_ids.size() == 1 and e.has("range"):
			_add_intel(data.base_index(str(near_ids[0])), v)
			return false
		for id in near_ids:
			opts.append({"value": id, "label": data.base_names[data.base_index(id)]})
		_ask(p, "intel_base", "첩보를 쌓을 거점을 고르세요.", opts, ctx)
		pending["amount"] = v
		return true
	var bi := _resolve_base(p, e.get("base", "nearest"), ctx)
	if bi >= 0:
		_add_intel(bi, v)
	return false


func _bases_in_range(c: Vector2i, dist: int) -> Array:
	## c에서 dist칸 안에 있는 거점 id
	var out := []
	for id in GameDataV2.BASE_IDS:
		if walk_dist(c, data.bases[data.base_index(id)]) <= dist:
			out.append(id)
	return out


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


func _funds_change(n: int, why := "") -> int:
	## 군자금을 바꾼다 (0~최대). 실제로 바뀐 몫을 돌려준다.
	var before := funds
	funds = clampi(funds + n, 0, int(data.rules["funds"]["max"]))
	_push({"kind": "funds", "value": funds, "change": funds - before, "why": why})
	return funds - before


func _op_funds(p: Dictionary, e: Dictionary, queue: Array) -> void:
	## 군자금 ±N. 얻으면 그 요원이 번 몫(funds_earned)에 더한다 (earned: false이면 안 셈). 잃을 때 모자라면 0이 되고,
	## short 효과가 있으면 대신 그 효과를 처리한다 (가택 수색: 고립된 요원이 아이템 1장을 버림).
	var v := int(e.get("value", 0))
	if v > 0:
		var got := _funds_change(v, "gain")
		_log("군자금 +%d (군자금 %d)%s" % [got, funds, "" if got == v else " — 최대를 넘는 몫은 버립니다" if got > 0 else " — 이미 최대입니다"])
		if got > 0 and bool(e.get("earned", true)):
			p["funds_earned"] = int(p["funds_earned"]) + got
			_saga_note(p, "funds_earned", {"amount": got})
		return
	var lost := mini(-v, funds)
	_funds_change(-lost, "lose")
	_log("군자금 −%d (군자금 %d)" % [lost, funds])
	if lost < -v and e.has("short"):
		_log("군자금이 모자랍니다.")
		var sh: Array = e["short"]
		for n in range(sh.size() - 1, -1, -1):
			queue.push_front(sh[n])


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
	_ask(p, "discard", "버릴 아이템을 고르세요.", opts, {})
	return true


func _op_scout(p: Dictionary, e: Dictionary, queue: Array) -> bool:
	## 덮인 칸을 range칸 안에서 count곳 골라 더미의 타일을 앞면으로 깐다. 고를 칸이 하나뿐이면 바로 깐다.
	var count := int(e.get("count", 1))
	if count <= 0 or tile_deck.is_empty():
		return false
	var cells := []
	var r := int(e["range"])
	for x in range(p["pos"].x - r, p["pos"].x + r + 1):
		for y in range(p["pos"].y - r, p["pos"].y + r + 1):
			var c := Vector2i(x, y)
			if in_bounds(c) and not board.has(c) and _manhattan(c, p["pos"]) <= r:
				cells.append(c)
	if cells.is_empty():
		_log("%s: 정찰할 덮인 칸이 없습니다." % p["name"])
		return false
	if cells.size() > 1 and not e.has("cell"):
		var opts := []
		for c in cells:
			opts.append({"value": c, "label": "(%d, %d)" % [c.x, c.y]})
		return _ask_pick(p, e, queue, "cell", "pick_cell", "정찰할 덮인 칸을 고르세요.", opts)
	var cell: Vector2i = e["cell"] if e.has("cell") else cells[0]
	if board.has(cell) or _manhattan(cell, p["pos"]) > r:
		return false
	var t: String = tile_deck.pop_back()
	board[cell] = _new_tile(t)
	_dist_cache = {}
	_push({"kind": "reveal", "pos": cell, "tile": t, "scouted": true})
	_log("%s: (%d, %d)칸을 정찰했습니다 — %s" % [p["name"], cell.x, cell.y, tile_label(t)])
	if count > 1:
		var rest_e: Dictionary = e.duplicate()
		rest_e.erase("cell")
		rest_e["count"] = count - 1
		queue.push_front(rest_e)
	return false


func _op_threat_look(e: Dictionary) -> bool:
	## 2막 위협 덱 맨 위 count장을 보고 1장을 버린다 (결행 혜택)
	var n := mini(int(e.get("count", 2)), threat_deck.size())
	if n <= 0:
		return false
	var opts := []
	for i in n:
		var id: String = threat_deck[threat_deck.size() - 1 - i]
		opts.append({"value": i, "label": "%s — %s" % [data.threat(id).get("name", id), data.threat(id).get("text", "")]})
	_ask(players[benefit_chooser()], "threat_look", "2막 위협 맨 위 %d장입니다. 버릴 한 장을 고르세요." % n, opts, {})
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
		return _ask_pick(p, e, queue, "die", "pick_die", "%s에게 건넬 주사위를 고르세요." % players[ids[0]]["name"], opts)
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
			return _ask_pick(p, e, queue, "sel", "pick_die", "어느 주사위를 어떻게 바꿀까요?", opts)
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
			return _ask_pick(p, e, queue, "val", "pick_value", "원하는 눈을 고르세요.", vopts)
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
		return _ask_pick(p, e, queue, "cell", "pick_cell", "%s 곁의 어느 칸으로 갈까요?" % q["name"], opts)
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
	_saga_note(p, "give_items")
	_saga_note(q, "hold_items")
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
			vote_state["votes"][p["id"]] = bool(value)
			_vote_next()
		"launch_target":
			vote_state["targets"][p["id"]] = str(value)
			_vote_next()
		"strike_target":
			_finish_launch(str(value))
		"launch_benefit":
			_take_benefit(str(value))
			_launch_continue()
		"threat_look":
			var idx := threat_deck.size() - 1 - int(value)
			if idx >= 0 and idx < threat_deck.size():
				var gone: String = threat_deck.pop_at(idx)
				threat_discard.append(gone)
				_log("2막 위협 「%s」을(를) 버렸습니다." % data.threat(gone).get("name", gone))
			_run_effects(actor, pd["rest"], pd["ctx"])
		"saga_keep":
			_keep_saga(p, str(value))
			_launch_continue()
		"informer_pay":
			if bool(value):
				for m in markers:
					if int(m["uid"]) == int(pd["marker"]):
						_funds_change(-int(card_cond(str(m["id"]))["informer_cost"]["funds"]), "informer")
						_use_informer(p, m)
						break
			if bool(pd.get("stop", false)):
				steps_left = 0
			_after_step(p)
		"bribe":
			if bool(value):
				_funds_change(-int(data.rules["checkpoint"]["bribe"]), "bribe")
				_log("%s: 군자금 %d을 내고 검문소를 지나갑니다." % [p["name"], int(data.rules["checkpoint"]["bribe"])])
				_push({"kind": "bribe", "player": p["id"]})
				_arrive(p, pd["cell"])
			else:
				_log("%s: 검문소 통과를 시도합니다." % p["name"])
				_start_check(p, "evade", "checkpoint", {"cell": pd["cell"]})
		"mission_gear":
			var gear: Dictionary = pd["gear"]
			var flow: Dictionary = pd["flow"]
			if int(value) >= 0:
				if int(value) >= GEAR_FUNDS:
					_funds_change(-int(gear["cost"]["funds"]), "gear")
					_log("%s: 군자금 %d을 냈습니다 — %s" % [p["name"], int(gear["cost"]["funds"]), gear.get("text", "")])
				else:
					var gid: String = p["items"][int(value)]
					p["items"].remove_at(int(value))
					item_discard.append(gid)
					_log("%s: [%s]을(를) 버렸습니다 — %s" % [p["name"], item_def(gid)["name"], gear.get("text", "")])
				if gear.has("check_bonus") and not check.is_empty():
					check["bonus"] = int(check["bonus"]) + int(gear["check_bonus"])
				for ge in gear.get("effects", []):
					_effect(p, ge, {"then": "resume"}, [])
			if str(flow["kind"]) == "check":
				_check_roll(p)
			else:
				_complete_missions(p, flow["ids"], flow["ctx"])
		"reroll":
			if str(value) == "grant":
				var gi := _grant_index(players[check["player"]], "reroll", str(check.get("ctx", "")) == "scene")
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
			_end_turn_continue(p)
		"intel_base":
			_add_intel(data.base_index(str(value)), int(pd["amount"]))
			_run_effects(actor, pd["rest"], pd["ctx"])


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
	_ask(players[leader], "strike_target", "표가 같은 거점이 여럿입니다. 리더가 결행할 곳을 고르세요.", opts, {})


func _finish_launch(base_id: String) -> void:
	## 목표가 정해지면 결행 순간의 처리(사연 → 결행 혜택 → 사연 남기기)를 한다.
	launch_info["target"] = base_id
	launch_step = 1
	launch_i = 0
	_launch_continue()


# ================================================================ 3단계: 개인 사연

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


func _next_voter(after: int) -> int:
	return after + 1 if after + 1 < players.size() else -1


func _police_off(pid: int, reason: String) -> void:
	## 경찰이 이 요원을 그만 쫓는다. reason: jail | shake | hideout | removed | decoy
	## 투옥이 아닌 이유(따돌림·은신처·제거·미끼)는 「원수」 사연의 shake_police로 센다.
	if not police.has(pid):
		return
	police.erase(pid)
	if reason != "jail":
		_saga_note(players[pid], "shake_police")


# ---------------------------------------------------------------- 사연 나눠 주기

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
					"chased_turns_row", "coop_missions", "give_items", "funds_earned":
				need = int(cond.get("count", 1))
				have = int(tr.get("n", 0))
			"visit_tile":
				need = int(cond.get("count", 1))
				have = tr.get("cells", []).size()
			"hold_items":
				need = int(cond.get("count", 1))
				have = mini(p["items"].size(), need)
			"rescue_or_escape":
				need = int(cond.get("escapes", 1))
				have = int(tr.get("n", 0))
			"same_cell_turns":
				need = int(cond.get("count", 1))
				for k in tr.get("with", {}):
					have = maxi(have, int(tr["with"][k]))
			"never_jailed_until_launch":
				have = 1 if p["jail_count"] == 0 else 0
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
		"funds_earned":
			return _bump(tr, "n", int(ctx.get("amount", 0))) >= count
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
		"shake_police", "pass_checkpoint", "coop_missions", "give_items":
			return _bump(tr) >= count
		"never_jailed_until_launch":
			return bool(ctx.get("launch", false)) and p["jail_count"] == 0
		"chased_turns_row":
			if not bool(ctx["chased"]):
				tr["n"] = 0
				return false
			return _bump(tr) >= count
		"rescue_or_escape":
			if str(ctx.get("what", "")) == "rescue":
				var q: Dictionary = players[int(ctx["rescued"])]
				return q["jailed_day"] >= 0 and day - q["jailed_day"] <= int(cond.get("rescue_within_days", 1))
			return _bump(tr) >= int(cond.get("escapes", 2))
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
			_saga_note(p, "same_cell_turns", {"with": q["id"]})


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
	_ask(who, "launch_benefit", "결행 혜택을 고르세요 (%d개 남음, 같은 것은 한 번만)." % int(launch_info["benefit_left"]), opts, {"then": "launch"})
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
		"mission_done_by_me":
			return act == 1
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


# ================================================================ 2막 장면 · 엔딩

func _scene_card(id: String) -> Dictionary:
	var strike: Dictionary = data.strike(str(launch_info.get("target", "")))
	for card in [strike.get("entry", {}), strike.get("final", {})] + strike.get("middle", []) + data.scenes.get("reinforce", []):
		if card.get("id", "") == id:
			return card
	return {}


func current_scene() -> Dictionary:
	if act != 2 or scene_index >= scenes.size():
		return {}
	var card := _scene_card(str(scenes[scene_index])).duplicate(true)
	card["index"] = scene_index
	card["total"] = scenes.size()
	card["state"] = scene_state.duplicate(true)
	return card


func _scene_where(cond: Dictionary) -> String:
	return str(cond.get("where", current_scene().get("where", "inside")))


func _scene_at(p: Dictionary, cond: Dictionary, jailed_check := false) -> bool:
	var base := _base_cell(str(launch_info.get("target", "")))
	if p["jailed"]:
		return jailed_check and p["pos"] == base
	var d := _manhattan(p["pos"], base)
	var where := _scene_where(cond)
	if where in GameDataV2.BASE_IDS:
		return d == 0
	match where:
		"inside": return d == 0
		"adjacent": return d == 1
		"inside_or_adjacent": return d <= 1
	return false


func scene_place_cells() -> Array:
	var out := []
	if current_scene().is_empty():
		return out
	for y in data.size:
		for x in data.size:
			var cell := Vector2i(x, y)
			var probe := {"pos": cell, "jailed": false}
			if _scene_at(probe, {}):
				out.append(cell)
	return out


func _scene_leaves(cond: Dictionary, path := "") -> Array:
	var out := []
	var kind := str(cond.get("kind", ""))
	if kind in ["any_of", "all_of"]:
		for i in cond.get("options", []).size():
			out.append_array(_scene_leaves(cond["options"][i], "%s/%d" % [path, i]))
	elif kind == "sequence":
		## 단계는 차례로: 아직 못 끝낸 첫 단계(다 끝났으면 마지막 단계)의 조건만 지금 할 수 있다
		var steps: Array = cond.get("steps", [])
		for i in steps.size():
			var sp := "%s/%d" % [path, i]
			if i == steps.size() - 1 or not _scene_complete(steps[i], sp):
				out.append_array(_scene_leaves(steps[i], sp))
				break
	else:
		out.append({"cond": cond, "path": path})
	return out


func _scene_part(path: String) -> Dictionary:
	if path == "":
		if not scene_state.has("paid_dice"):
			scene_state.merge({"paid_dice": 0, "paid_items": 0, "paid_bombs": 0, "paid_funds": 0,
				"hold_days": 0, "pair_ok": [], "people": [], "dice_reduce": 0, "done": false})
		return scene_state
	if not scene_state.has("parts"):
		scene_state["parts"] = {}
	if not scene_state["parts"].has(path):
		scene_state["parts"][path] = {"paid_dice": 0, "paid_items": 0, "paid_bombs": 0, "paid_funds": 0,
			"hold_days": 0, "pair_ok": [], "people": [], "dice_reduce": 0, "done": false}
	return scene_state["parts"][path]


func _scene_part_read(path: String) -> Dictionary:
	return scene_state if path == "" else scene_state.get("parts", {}).get(path, {})


func _scene_complete(cond: Dictionary, path := "") -> bool:
	var kind := str(cond.get("kind", ""))
	if kind == "sequence":
		var steps: Array = cond.get("steps", [])
		for i in steps.size():
			if not _scene_complete(steps[i], "%s/%d" % [path, i]):
				return false
		return not steps.is_empty()
	if kind in ["any_of", "all_of"]:
		var options: Array = cond.get("options", [])
		if options.is_empty():
			return false
		for i in options.size():
			var done := _scene_complete(options[i], "%s/%d" % [path, i])
			if kind == "any_of" and done:
				return true
			if kind == "all_of" and not done:
				return false
		return kind == "all_of"
	var state := _scene_part_read(path)
	match kind:
		"check": return bool(state.get("done", false))
		"check_pair": return state.get("pair_ok", []).size() >= int(cond.get("count", 1))
		"dice": return int(state.get("paid_dice", 0)) >= maxi(0, int(cond.get("sum", 0)) - int(state.get("dice_reduce", 0)))
		"pay_item": return int(state.get("paid_items", 0)) >= int(cond.get("count", 1))
		"pay_bomb": return int(state.get("paid_bombs", 0)) >= int(cond.get("count", 1))
		"pay_funds": return int(state.get("paid_funds", 0)) >= int(cond.get("count", 1))
		"people": return state.get("people", []).size() >= int(cond.get("count", 1))
		"hold": return int(state.get("hold_days", 0)) >= int(cond.get("days", 1))
		"jailed_here":
			var base := _base_cell(str(launch_info.get("target", "")))
			for q in players:
				if q["jailed"] and q["pos"] == base:
					return true
	return false


func _scene_reveal() -> void:
	var card := current_scene()
	_push({"kind": "scene", "index": scene_index, "id": card["id"]})
	_log("장면 %d/%d: %s" % [scene_index + 1, scenes.size(), card["name"]])
	_banner("장면: %s" % card["name"], "info")
	if scene_index == scenes.size() - 1:
		_saga_final_reveal()
	_scene_auto_break()
	_counter_refresh()


func _scene_auto_break() -> void:
	var guard := scenes.size()
	while phase != "over" and act == 2 and scene_index < scenes.size() and guard > 0:
		guard -= 1
		if not _scene_complete(current_scene().get("condition", {})):
			break
		_scene_break(-1)


func _scene_break(by_pid: int) -> void:
	var card := current_scene()
	var id := str(card["id"])
	_push({"kind": "scene_break", "index": scene_index, "id": id, "player": by_pid})
	_banner("%s 돌파!" % card["name"], "good")
	_record("장면 돌파: %s" % card["name"], "good")
	_log("장면 돌파: %s" % card["name"])
	var kind := "entry" if scene_index == 0 else "final" if scene_index == scenes.size() - 1 else "middle"
	var present := []
	var base := _base_cell(str(launch_info.get("target", "")))
	for q in players:
		if not q["jailed"] and q["pos"] == base:
			present.append(q["id"])
	saga_strike_event(kind, by_pid, {"strike": launch_info["target"], "present": present})
	if kind == "final":
		_end_game(true)
		return
	scene_index += 1
	scene_state = {}
	_scene_reveal()


func _scene_check_leaf(p: Dictionary) -> Dictionary:
	if act != 2 or not _acting(p):
		return {}
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		var kind := str(leaf["cond"].get("kind", ""))
		if kind in ["check", "check_pair"] and not _scene_complete(leaf["cond"], str(leaf["path"])) \
				and _scene_at(p, leaf["cond"], true):
			if kind == "check_pair" and p["id"] in _scene_part_read(str(leaf["path"])).get("pair_ok", []):
				continue   # 이미 성공한 요원이 또 해도 두 명으로 치지 않는다
			return leaf
	return {}


func _scene_can_check(p: Dictionary) -> bool:
	return not _scene_check_leaf(p).is_empty() and not my_dice(p["id"]).is_empty()


func _scene_check(p: Dictionary, die: int) -> void:
	var leaf := _scene_check_leaf(p)
	var cond: Dictionary = leaf["cond"]
	var name := str(cond.get("check", "generic"))
	var target := (int(cond["target"]) if cond.has("target") else check_target(name)) + int(today.get("scene_mod", 0))
	var bonus := int(p["flags"].get("intel_check", 0))
	p["flags"]["intel_check"] = 0
	_start_check(p, name, "scene", {"target": target, "scene_path": leaf["path"], "scene_id": scenes[scene_index], "intel_bonus": bonus,
		"die_i": die})


func _scene_check_result(p: Dictionary, c: Dictionary, ok: bool) -> void:
	if str(c.get("scene_id", "")) != str(scenes[scene_index]):
		return
	if ok:
		var path := str(c["scene_path"])
		var part := _scene_part(path)
		var cond: Dictionary = _scene_cond_at(path)
		if cond.get("kind", "") == "check_pair":
			if not p["id"] in part["pair_ok"]:
				part["pair_ok"].append(p["id"])
		else:
			part["done"] = true
		if _scene_complete(current_scene()["condition"]):
			_scene_break(p["id"])
	else:
		_run_effects(p, current_scene().get("on_fail", []), {"then": "scene_check_done"})


func _finish_scene_check(_p: Dictionary) -> void:
	pass


func _scene_cond_at(path: String) -> Dictionary:
	var cond: Dictionary = current_scene().get("condition", {})
	for index in path.split("/", false):
		cond = cond["steps"][int(index)] if cond.has("steps") else cond.get("options", [])[int(index)]
	return cond


func _scene_pay_leaf(p: Dictionary, what: String, index: int) -> Dictionary:
	if act != 2 or not _acting(p) or p["jailed"]:
		return {}
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		var cond: Dictionary = leaf["cond"]
		var kind := str(cond.get("kind", ""))
		if _scene_complete(cond, str(leaf["path"])) or not _scene_at(p, cond):
			continue
		if what == "die" and kind == "dice" and index in my_dice(p["id"]):
			return leaf
		if what == "item" and kind == "pay_item" and index >= 0 and index < p["items"].size() and not my_dice(p["id"]).is_empty():
			return leaf
		if what == "bomb" and kind == "pay_bomb":
			var need := int(cond.get("count", 1)) if not cond.get("split", false) else 1
			if p["bombs"] >= need and not my_dice(p["id"]).is_empty():
				return leaf
		if what == "funds" and kind == "pay_funds" and scene_index < scenes.size() - 1 and funds >= int(cond.get("count", 1)) and not my_dice(p["id"]).is_empty():
			return leaf   # 마지막 장면은 매수할 수 없다
	return {}


func _scene_can_pay(p: Dictionary, what: String, index: int) -> bool:
	return not _scene_pay_leaf(p, what, index).is_empty()


func _scene_pay(p: Dictionary, what: String, index: int, spend := -1) -> void:
	## 바치기 행동. 주사위를 바칠 때는 그 눈이 합에 더해지고, 아이템·폭탄을 바칠 때는 주사위 하나(spend, 눈은 상관없음)를 낸다.
	var leaf := _scene_pay_leaf(p, what, index)
	var cond: Dictionary = leaf["cond"]
	var part := _scene_part(str(leaf["path"]))
	match what:
		"die":
			part["paid_dice"] = int(part["paid_dice"]) + die_value(index)
			_use_die(p, index, "scene")
		"item":
			_use_die(p, spend, "scene")
			item_discard.append(p["items"].pop_at(index))
			part["paid_items"] = int(part["paid_items"]) + 1
		"bomb":
			_use_die(p, spend, "scene")
			var n := 1 if cond.get("split", false) else int(cond.get("count", 1))
			p["bombs"] -= n
			bomb_supply += n
			part["paid_bombs"] = int(part["paid_bombs"]) + n
		"funds":
			_use_die(p, spend, "scene")
			_funds_change(-int(cond.get("count", 1)), "scene")
			part["paid_funds"] = int(cond.get("count", 1))
	_log("%s: 장면에 %s을(를) 바쳤습니다." % [p["name"], {"die": "주사위", "item": "아이템", "bomb": "폭탄", "funds": "군자금"}[what]])
	_scene_auto_break_by(p["id"])


func _scene_auto_break_by(pid: int) -> void:
	if _scene_complete(current_scene().get("condition", {})):
		_scene_break(pid)


func _scene_can_intel(p: Dictionary, mode: String) -> bool:
	if act != 2 or not _acting(p) or intel_tokens <= 0:
		return false
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		if _scene_complete(leaf["cond"], str(leaf["path"])):
			continue
		if mode == "check" and leaf["cond"].get("kind", "") in ["check", "check_pair"]:
			return true
		if mode == "dice" and leaf["cond"].get("kind", "") == "dice":
			return true
	return false


func _scene_use_intel(p: Dictionary, mode: String) -> void:
	intel_tokens -= 1
	if mode == "check":
		p["flags"]["intel_check"] = int(p["flags"].get("intel_check", 0)) + int(data.rules["intel_token"]["check_bonus"])
	else:
		for leaf in _scene_leaves(current_scene().get("condition", {})):
			if leaf["cond"].get("kind", "") == "dice" and not _scene_complete(leaf["cond"], str(leaf["path"])):
				var part := _scene_part(str(leaf["path"]))
				part["dice_reduce"] = int(part["dice_reduce"]) + int(data.rules["intel_token"]["dice_reduce"])
				break
		_scene_auto_break_by(p["id"])
	_log("%s: 첩보 토큰을 썼습니다." % p["name"])


func scene_options(p: Dictionary) -> Array:
	var out := []
	if act != 2 or not _acting(p):
		return out
	var dice := my_dice(p["id"])
	if _scene_can_check(p):
		for i in dice:
			out.append({"type": "scene_check", "player": p["id"], "die": i})
	if can_counter_check(p):
		for i in dice:
			out.append({"type": "counter_check", "player": p["id"], "die": i})
	for i in dice:
		if _scene_can_pay(p, "die", i):
			out.append({"type": "scene_pay", "player": p["id"], "what": "die", "die": i})
	for k in p["items"].size():
		if _scene_can_pay(p, "item", k):
			for i in dice:
				out.append({"type": "scene_pay", "player": p["id"], "what": "item", "index": k, "with": i})
	if _scene_can_pay(p, "bomb", -1):
		for i in dice:
			out.append({"type": "scene_pay", "player": p["id"], "what": "bomb", "with": i})
	if _scene_can_pay(p, "funds", -1):
		for i in dice:
			out.append({"type": "scene_pay", "player": p["id"], "what": "funds", "with": i})
	for mode in ["check", "dice"]:
		if _scene_can_intel(p, mode):
			out.append({"type": "use_intel", "player": p["id"], "mode": mode})
	return out


func _scene_turn_end(p: Dictionary) -> void:
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		if leaf["cond"].get("kind", "") == "people" and _scene_at(p, leaf["cond"]):
			var part := _scene_part(str(leaf["path"]))
			if not p["id"] in part["people"]:
				part["people"].append(p["id"])
	_scene_auto_break_by(p["id"])


func _scene_hold_leaves() -> Array:
	return _scene_leaves(current_scene().get("condition", {})).filter(func(l): return str(l["cond"].get("kind", "")) == "hold")


func counter_active() -> bool:
	## 오늘 반격이 걸려 있고 아직 못 막았는가
	return act == 2 and int(counter.get("day", -1)) == day and not bool(counter.get("blocked", false))


func _counter_refresh() -> void:
	## 「버티기」 장면이 펼쳐진 날에는 반격이 걸린다 (아침, 또는 그날 안에 그 장면이 펼쳐질 때)
	if act != 2 or phase == "over" or int(counter.get("day", -1)) == day or current_scene().is_empty():
		return
	if _scene_hold_leaves().is_empty():
		return
	counter = {"day": day, "blocked": false}
	_log("반격! 오늘 「%s」 자리에서 작전 판정 %d에 성공해야 버틴 날로 칩니다." % [current_scene()["name"], int(data.rules["counter"]["target"])])
	_push({"kind": "counter", "scene": current_scene()["id"]})


func _counter_at(p: Dictionary) -> bool:
	for leaf in _scene_hold_leaves():
		if _scene_at(p, leaf["cond"]):
			return true
	return false


func can_counter_check(p: Dictionary) -> bool:
	## 반격을 막는 작전 판정: 그 장면 자리에 선 요원이 주사위 하나로 (실패하면 다른 주사위로 또)
	return counter_active() and _acting(p) and not p["jailed"] and not my_dice(p["id"]).is_empty() and _counter_at(p)


func _scene_night() -> bool:
	## 밤의 장면 처리. 반격을 못 막았으면 버틴 날을 세지 않고, 자리에 선 요원이 회피 판정을 한다 (처리 중이면 true).
	var attacked := counter_active()
	for leaf in _scene_hold_leaves():
		var count := 0
		for q in players:
			if not q["jailed"] and _scene_at(q, leaf["cond"]):
				count += 1
		if attacked:
			if count > 0:
				_log("반격을 막지 못해 오늘은 버틴 날로 치지 않습니다.")
		elif count >= int(leaf["cond"].get("count", 1)):
			var part := _scene_part(str(leaf["path"]))
			part["hold_days"] = int(part["hold_days"]) + 1
	if attacked:
		counter_queue = []
		for q in players:
			if not q["jailed"] and _counter_at(q):
				counter_queue.append(q["id"])
		if not counter_queue.is_empty():
			_counter_next()
			return true
	_scene_night_finish()
	return false


func _counter_next() -> void:
	## 반격을 못 막은 밤: 자리에 선 요원이 차례로 회피 판정 (실패하면 투옥)
	if phase == "over":
		return
	if counter_queue.is_empty():
		_scene_night_finish()
		if phase != "over":
			_night_after_scene()
		return
	var pid: int = counter_queue.pop_front()
	if players[pid]["jailed"]:
		_counter_next()
		return
	_log("%s: 반격을 피하려 회피 판정을 합니다." % players[pid]["name"])
	_start_check(players[pid], "evade", "counter_evade")


func _scene_night_finish() -> void:
	if _scene_complete(current_scene().get("condition", {})):
		_scene_break(-1)
	if phase == "over":
		return
	for leaf in _scene_leaves(current_scene().get("condition", {})):
		var part := _scene_part(str(leaf["path"]))
		part["pair_ok"] = []
		part["people"] = []
	for q in players:
		q["flags"].erase("intel_check")
	counter = {}


func scene_need(i := -1) -> Dictionary:
	if act != 2 or scenes.is_empty():
		return {}
	var cond: Dictionary = current_scene().get("condition", {}) if i < 0 else _scene_card(str(scenes[i])).get("condition", {})
	var out := {}
	for leaf in _scene_leaves(cond):
		var c: Dictionary = leaf["cond"]
		var path := str(leaf["path"])
		var part: Dictionary = _scene_part_read(path) if i < 0 or i == scene_index else {}
		match str(c.get("kind", "")):
			"dice": out["dice"] = maxi(0, int(c.get("sum", 0)) - int(part.get("dice_reduce", 0)) - int(part.get("paid_dice", 0)))
			"pay_item": out["item"] = maxi(0, int(c.get("count", 1)) - int(part.get("paid_items", 0)))
			"pay_bomb": out["bomb"] = maxi(0, int(c.get("count", 1)) - int(part.get("paid_bombs", 0)))
			"pay_funds": out["funds"] = maxi(0, int(c.get("count", 1)) - int(part.get("paid_funds", 0)))
			"check_pair": out["check_pair"] = maxi(0, int(c.get("count", 1)) - part.get("pair_ok", []).size())
			"people": out["people"] = maxi(0, int(c.get("count", 1)) - part.get("people", []).size())
			"hold": out["hold"] = maxi(0, int(c.get("days", 1)) - int(part.get("hold_days", 0)))
	return out


func _search_next() -> void:
	if search_queue.is_empty():
		_stage4_resume()
		return
	var pid: int = search_queue.pop_front()
	_start_check(players[pid], "evade", "search")


func _stage4_resume() -> void:
	if effect_wait.is_empty():
		return
	var wait: Dictionary = effect_wait.pop_back()
	_run_effects(players[int(wait["player"])], wait["rest"], wait["ctx"])


func _end_game(won: bool) -> void:
	var target := str(launch_info.get("target", "")) if act == 2 else ""
	var card := current_scene() if act == 2 else {}
	var id := "victory" if won else "history" if act == 1 or scene_index == 0 else "fail_final" if scene_index == scenes.size() - 1 else "fail_middle"
	var key := "operation" if id == "fail_middle" else id
	var def: Dictionary = data.endings.get(key, {})
	var body := str(data.endings.get("strikes", {}).get(target, {}).get("ending", "")) if won else str(def.get("text", ""))
	if not won and not card.is_empty():
		body = str(card.get("stop_text", "")) + "\n" + body
	var epilogues := []
	for p in players:
		var result := saga_result(p["id"])
		var saga_id := str(result.get("saga", ""))
		var epkey := epilogue_key(p["id"], won)
		var saga: Dictionary = data.saga(saga_id)
		var lines: Dictionary = saga.get("epilogue", {})
		var line = lines.get(epkey)
		if line == null:
			epkey = "win_fail" if won else "lose_fail"
			line = lines.get(epkey, "")
		var character: Dictionary = char_def(p)
		var faction := str(data.characters.get("factions", {}).get(character.get("faction", ""), {}).get("name", ""))
		epilogues.append({"player": p["id"], "saga": saga_id, "key": epkey,
			"text": "%s %s — %s" % [faction, character.get("name", p["name"]), str(line)],
			"done": bool(result.get("done", false))})
	var funds_text := ""
	if funds > 0:
		funds_text = str(data.endings.get("funds_left", {}).get("text", "")).replace("{n}", str(funds))
		body += "\n\n" + funds_text
	ending = {"id": id, "won": won, "target": target, "scene": str(card.get("id", "")), "funds_left": funds, "funds_text": funds_text,
		"scene_index": scene_index if act == 2 else -1, "title": str(def.get("name", "")), "text": body,
		"epilogues": epilogues}
	phase = "over"
	pending = {}
	_record("작전 종료: %s" % ending["title"], "good" if won else "bad")
	_log("작전 종료: %s" % ending["title"])
	_push({"kind": "over"})


# ================================================================ 저장 · 불러오기

const SAVE_FIELDS := ["players", "leader", "day", "rounds_total", "rounds_left", "act", "phase", "current",
	"steps_left", "board", "tile_deck", "police", "exposure", "intel", "ready", "threat_deck", "threat_discard",
	"threat_today", "mission_deck", "mission_discard", "mission_row", "event_deck", "event_discard",
	"item_deck", "item_discard", "bomb_supply", "op_dice", "today", "pending",
	"launch_info", "ending", "scenes", "scene_index", "scene_state", "intel_tokens", "search_queue", "effect_wait",
	"check", "morning_step", "last_roll", "saga_decks", "saga_discard",
	"saga_rewards", "launch_step", "launch_i", "human", "vote_state", "counter", "counter_queue",
	"funds", "markers", "mission_state", "op_row", "op_deck", "op_discard", "trend", "peek_bonus", "bonus_wait", "expire_queue", "marker_seq",
	"actions", "log_lines", "history"]


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
	_dist_cache = {}
	for q in players:   # B단계 이전에 저장한 판에는 차례 상태가 없다
		if not q.has("fx_cells"):
			q["fx_cells"] = []
		if not q.has("hidden"):
			q["hidden"] = false
		if not q.has("funds_earned"):
			q["funds_earned"] = 0


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
