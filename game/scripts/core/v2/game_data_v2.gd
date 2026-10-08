class_name GameDataV2
extends RefCounted
## data/v2/*.json을 읽어 v2 규칙 엔진·UI에 제공한다. 보드(크기 · 거점 · 지도 · 타일 그림)는 board.json.
## 효과·조건 어휘는 v2_구현/1단계_데이터.md 3절과 같다. validate()가 오타·장수 누락을 잡는다.

const DIR := "res://data/v2/"

## 3-1. 대상 (who, target)
const KNOWN_TARGETS := ["self", "ally", "ally_same_cell", "ally_adjacent", "ally_in_range", "all", "allies",
	"isolated", "wanted", "nearest_to_base", "all_jailed", "saga_partner", "everyone"]
## 3-2. 효과 op
const KNOWN_OPS := ["police_dispatch", "police_attach", "police_advance", "police_remove", "police_push",
	"police_send_far", "checkpoint_place", "dice_mod_today", "police_speed_today", "exposure",
	"free_all_jailed", "escape_mod_today", "scene_check_mod_today", "search", "intel",
	"ready", "draw_item", "gain_bomb", "discard_item", "move_mod_next", "move_today",
	"dice_extra_tomorrow", "fewer_dice_tomorrow", "die_reroll", "die_adjust", "die_set",
	"threat_bury", "grant_once", "give_die", "place_tile", "extra_step",
	"mark_tile", "move_to_ally", "pull_ally", "give_item", "send_item",
	"checkpoint_pass", "refill_supply", "choice", "if_players",
	"if", "threat_flip", "check_or_jail", "entry_no_police",
	"no_reinforce", "intel_token_bonus", "threat_look_discard", "police_back", "threat_peek_bonus", "event_card", "funds", "funds_half"]
## if op의 cond
const KNOWN_IF_CONDS := ["chased", "not_chased"]
## 능력 사용 조건 (ability.requires)
const KNOWN_REQUIRES := ["near_tile", "base_in_range"]
## 능력 사용 비용 (ability.cost): 없으면 공짜, "die"는 작전 주사위 하나를 낸다
const KNOWN_COSTS := ["die"]
## 3-3. 장면·협동 조건 kind
const KNOWN_SCENE_CONDITIONS := ["enter_base", "deliver_bomb", "check", "check_pair", "dice", "pay_item", "pay_bomb", "people", "hold",
	"jailed_here", "any_of", "all_of", "sequence", "pay_funds"]
## 3-3b. 미션·일제 작전 조건 kind (condition.kind). 협동은 cover_entry · people · opposite_edges
const KNOWN_MISSION_KINDS := ["assassinate", "infiltrate", "bomb", "work", "contact", "lurk", "cover_entry", "people", "opposite_edges"]
## 마커 역할 (markers[].role)과 놓을 자리의 기준 (around · at은 거점 id 또는 start)
const KNOWN_MARKER_ROLES := ["target", "informer", "base", "pickup", "dropoff", "work", "spot"]
const MARKER_CENTERS := ["barracks", "police_hq", "prison", "gg", "start"]
## 공작 방식: 합 N · 눈 조합 · 마커마다 하나
const KNOWN_WORK_MODES := ["sum", "combo", "each"]
## 미션 보너스 조건 (bonus.if.kind)
const KNOWN_BONUS_CONDS := ["not_chased", "faction", "days_left", "rescued_this_turn", "ally_adjacent", "same_day",
	"contributors", "carrier_clean", "launch_target"]
## 3-4. 사연 조건 kind
const KNOWN_SAGA_CONDITIONS := ["end_turn_near_base", "visit_base_adjacent", "touch_edge", "end_turn_at_start",
	"visit_tile", "hold_items", "rolled_value", "give_dice", "shake_police", "pass_checkpoint",
	"never_jailed_until_launch", "chased_turns_row", "rescue_or_escape", "same_cell_turns",
	"coop_missions", "give_items", "strike_final_by_me", "present_at_final", "strike_entry_by_me", "mission_done_by_me", "funds_earned", "work_give"]
## 3-5. 캐릭터 특성·아이템 지속 효과 stat
const KNOWN_STATS := ["evade_auto", "escape_bonus", "rescued_move_bonus", "assassin_rerolls", "bomb_slots",
	"work_reduce", "work_exposure", "market_item_cost", "market_bomb_cost", "move_min3", "hand_limit", "item_draw_choice",
	"mission_intel_bonus", "threat_peek", "block_police_with_evade", "end_move_hop_to_ally",
	"spare_die_bonus", "assassin_bonus", "evade_bonus", "move_bonus", "base_no_police", "assassin_adjacent"]
## where는 이 값 말고 거점 id도 쓸 수 있다.
const KNOWN_WHERE := ["inside", "adjacent", "inside_or_adjacent"]

const EPILOGUE_KEYS := ["win_done", "win_fail", "lose_done", "lose_fail"]

static var _cache: GameDataV2

var rules: Dictionary
var threats: Dictionary
var missions: Dictionary
var events: Dictionary
var items: Dictionary
var scenes: Dictionary
var endings: Dictionary
var sagas: Dictionary
var characters: Dictionary
var ui: Dictionary                # 화면 구성 (ui.json: 행동 단추 · 미션 그림 · 마커 글자 · 날씨 · 훈련 할 일)
var online: Dictionary            # 온라인 방 설정 (online.json, 없으면 빈 사전 → 코드의 기본값)

## 보드 (board.json). base_ids[i] · bases[i] · base_names[i]는 같은 거점이다
var board := {}
var base_ids: Array[String] = []
var tile_art := {}                # 타일 종류 -> {"texture", "used_texture"}
var size := 11
var start := Vector2i(5, 5)
var bases: Array[Vector2i] = []
var base_names: Array[String] = []

var _dir := DIR
var _missing: Array[String] = []
var _unreadable: Array[String] = []
var _missions := {}
var _ops := {}
var _events := {}
var _items := {}
var _sagas := {}
var _characters := {}
var _todos: Array[String] = []


static func load_default() -> GameDataV2:
	if _cache == null:
		_cache = GameDataV2.new()
		_cache.load_dir(DIR)
	return _cache


func load_dir(dir: String) -> void:
	if not dir.ends_with("/"):
		dir += "/"
	_dir = dir
	_missing.clear()
	_unreadable.clear()
	rules = _read("rules.json")
	threats = _read("threats.json")
	missions = _read("missions.json")
	events = _read("events.json")
	items = _read("items.json")
	scenes = _read("scenes.json")
	endings = _read("endings.json")
	sagas = _read("sagas.json")
	characters = _read("characters.json")
	online = _read_optional("online.json")
	ui = _read("ui.json")
	_load_board()
	_missions = _index(missions.get("missions", []))
	_ops = _index(missions.get("ops", []))
	_events = _index(events.get("events", []))
	_items = _index(items.get("items", []))
	_sagas = _index(sagas.get("sagas", []))
	_characters = _index(characters.get("characters", []))


func _load_board() -> void:
	board = _read("board.json")
	size = int(board.get("size", size))
	var st: Array = board.get("start", [start.x, start.y])
	start = Vector2i(int(st[0]), int(st[1]))
	bases.clear()
	base_names.clear()
	base_ids.clear()
	for b in board.get("bases", []):
		base_ids.append(str(b.get("id", "")))
		bases.append(Vector2i(int(b["pos"][0]), int(b["pos"][1])))
		base_names.append(str(b.get("name", "")))
	tile_art = board.get("tile_art", {})


func map_info() -> Dictionary:
	## 지도 그림과 칸 맞춤 {"image", "px", "origin", "cell"}
	return board.get("map", {})


# ------------------------------------------------------------------ 조회

func threat_deck(act: int) -> Array:
	## count만큼 펼친 위협 카드 id 목록 (섞지 않음)
	var out := []
	for c in threats.get("act%d" % act, []):
		for i in int(c.get("count", 1)):
			out.append(c["id"])
	return out


func threat(id: String) -> Dictionary:
	for act in ["act1", "act2"]:
		for c in threats.get(act, []):
			if c.get("id") == id:
				return c
	return {}


func mission(id: String) -> Dictionary:
	return _missions.get(id, {})


func op_card(id: String) -> Dictionary:
	## 일제 작전 카드
	return _ops.get(id, {})


func is_op(id: String) -> bool:
	return _ops.has(id)


func marker_card(id: String) -> Dictionary:
	## 보드에 마커를 놓는 카드 (미션 또는 일제 작전)
	return _missions[id] if _missions.has(id) else _ops.get(id, {})


func op_deck() -> Array:
	## 일제 작전 카드 id 목록 (섞지 않음)
	var out := []
	for c in missions.get("ops", []):
		out.append(c["id"])
	return out


func event(id: String) -> Dictionary:
	return _events.get(id, {})


func item(id: String) -> Dictionary:
	return _items.get(id, {})


func saga(id: String) -> Dictionary:
	return _sagas.get(id, {})


func character(id: String) -> Dictionary:
	return _characters.get(id, {})


func strike(base_id: String) -> Dictionary:
	return scenes.get("strikes", {}).get(base_id, {})


func base_index(base_id: String) -> int:
	## 거점 문자열 id -> 보드의 거점 번호. 모르는 id면 -1
	return base_ids.find(base_id)


func todos() -> Array[String]:
	## 마지막 validate()가 모은 _todo 경고
	return _todos


# ------------------------------------------------------------------ 검증

func validate() -> Array[String]:
	## 데이터 오타·누락·장수 불일치를 메시지 목록으로 돌려준다. 빈 배열이면 정상.
	## _todo가 달린 카드는 오류가 아니라 todos()에 모인다.
	var errs: Array[String] = []
	_todos.clear()
	for p in _missing:
		errs.append("파일 없음: " + p)
	for p in _unreadable:
		errs.append("파일을 읽을 수 없음: " + p)
	_validate_board(errs)
	_validate_rules(errs)
	_validate_vote_ai(errs)
	_validate_ui(errs)
	_validate_threats(errs)
	_validate_missions(errs)
	_validate_events(errs)
	_validate_items(errs)
	_validate_scenes(errs)
	_validate_endings(errs)
	_validate_sagas(errs)
	_validate_characters(errs)
	for name in ["board", "ui", "rules", "threats", "missions", "events", "items", "scenes", "endings", "sagas", "characters"]:
		_collect_todos(get(name), name)
	return errs


func _validate_board(errs: Array[String]) -> void:
	if size < 5:
		errs.append("board.size가 너무 작습니다 (%d)." % size)
	var inside := func(c: Vector2i) -> bool: return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size
	if not inside.call(start):
		errs.append("board.start %s가 보드 밖입니다." % start)
	if base_ids.size() != 4:
		errs.append("[장수] 거점: %d곳 (기준 4곳, 결행 장면 · 엔딩이 넷을 기대함)" % base_ids.size())
	var seen := {}
	for i in base_ids.size():
		var id := base_ids[i]
		if id == "" or base_names[i] == "":
			errs.append("board.bases[%d]: id와 name이 있어야 합니다." % i)
		if seen.has(id):
			errs.append("board.bases: 거점 id %s가 겹칩니다." % id)
		seen[id] = true
		if not inside.call(bases[i]) or bases[i] == start:
			errs.append("거점 %s: 칸 %s가 보드 밖이거나 시작 칸입니다." % [id, bases[i]])
		if bases.count(bases[i]) > 1:
			errs.append("거점 %s: 다른 거점과 칸이 겹칩니다." % id)
	var m: Dictionary = map_info()
	for k in ["image", "px", "origin", "cell"]:
		if not m.has(k):
			errs.append("board.map.%s가 없습니다." % k)
	if m.has("image") and not ResourceLoader.exists(str(m["image"])):
		errs.append("board.map.image 그림이 없습니다: %s" % m["image"])
	for t in tile_art:
		if t.begins_with("_"):
			continue
		var a = tile_art[t]
		if typeof(a) != TYPE_DICTIONARY or str(a.get("texture", "")) == "":
			errs.append("board.tile_art.%s: texture가 있어야 합니다." % t)
			continue
		for k in ["texture", "used_texture"]:
			if a.has(k) and not ResourceLoader.exists("res://assets/tiles/%s.png" % a[k]):
				errs.append("board.tile_art.%s: 그림 assets/tiles/%s.png이 없습니다." % [t, a[k]])


func _validate_ui(errs: Array[String]) -> void:
	var verbs: Array = ui.get("verbs", [])
	if verbs.is_empty():
		errs.append("ui.verbs가 비었습니다.")
	var ids := {}
	for v in verbs:
		var id := str(v.get("id", ""))
		if id == "" or str(v.get("label", "")) == "" or (v.get("actions", []) as Array).is_empty():
			errs.append("ui.verbs: 단추마다 id · label · actions가 있어야 합니다 (%s)." % id)
		if ids.has(id):
			errs.append("ui.verbs: id %s가 겹칩니다." % id)
		ids[id] = true
		if not str(v.get("jailed", "")) in ["", "only", "allowed"]:
			errs.append("ui.verbs.%s: jailed는 only · allowed 중 하나여야 합니다." % id)
		for a in v.get("acts", []):
			if not int(a) in [1, 2]:
				errs.append("ui.verbs.%s: acts는 1 · 2만 됩니다." % id)
	var art: Dictionary = ui.get("mission_art", {})
	for k in ["coop", "op"]:
		if not art.has(k):
			errs.append("ui.mission_art.%s(기본 그림)가 없습니다." % k)
	for k in art:
		if not k.begins_with("_") and not ResourceLoader.exists(str(art[k])):
			errs.append("ui.mission_art.%s: 그림이 없습니다 (%s)." % [k, art[k]])
	var glyph: Dictionary = ui.get("marker_glyph", {})
	var names: Dictionary = ui.get("marker_names", {})
	for r in KNOWN_MARKER_ROLES:
		if str(glyph.get(r, "")) == "":
			errs.append("ui.marker_glyph.%s(마커 글자)가 없습니다." % r)
		if str(names.get(r, "")) == "":
			errs.append("ui.marker_names.%s(마커 이름)가 없습니다." % r)
	var weather: Dictionary = ui.get("weather", {})
	for t in weather:
		if t.begins_with("_"):
			continue
		if threat(t).is_empty():
			errs.append("ui.weather: 위협 카드 %s가 없습니다." % t)
		if not str(weather[t]) in ["rain", "light", "siren"]:
			errs.append("ui.weather.%s: 날씨는 rain · light · siren 중 하나입니다." % t)
	for t in ui.get("training_tasks", []):
		if str(t.get("id", "")) == "" or str(t.get("label", "")) == "":
			errs.append("ui.training_tasks: 할 일마다 id와 label이 있어야 합니다.")


func _validate_vote_ai(errs: Array[String]) -> void:
	var v = rules.get("launch", {}).get("vote", null)
	if typeof(v) != TYPE_DICTIONARY or not v.has("pass_ratio") or not v.has("tie"):
		errs.append("rules.launch.vote에 pass_ratio와 tie가 있어야 합니다.")
	else:
		if float(v["pass_ratio"]) <= 0.0 or float(v["pass_ratio"]) >= 1.0:
			errs.append("rules.launch.vote.pass_ratio는 0과 1 사이여야 합니다.")
		if not str(v["tie"]) in ["leader", "fail", "pass"]:
			errs.append("rules.launch.vote.tie는 leader · fail · pass 중 하나여야 합니다.")
	var ai: Dictionary = rules.get("ai", {})
	for k in ["act2_days_per_scene", "saga_value"]:
		if float(ai.get(k, 0.0)) <= 0.0:
			errs.append("rules.ai.%s가 없거나 0 이하입니다." % k)
	var r = ai.get("rescue", null)
	if typeof(r) != TYPE_DICTIONARY or float(r.get("value", 0.0)) <= 0.0 or int(r.get("range", 0)) <= 0:
		errs.append("rules.ai.rescue에 value와 range(양수)가 있어야 합니다.")
	var per = ai.get("persona", null)
	if typeof(per) != TYPE_DICTIONARY or not per.has("support"):
		errs.append("rules.ai.persona에 support(기본 성향)가 있어야 합니다.")
	else:
		for k in per:
			if not k.begins_with("_") and (not per[k].has("risk") or not per[k].has("vote")):
				errs.append("rules.ai.persona.%s에 risk와 vote가 있어야 합니다." % k)
	for c in characters.get("characters", []):
		var pk := str(c.get("persona", ""))
		if pk != "" and typeof(per) == TYPE_DICTIONARY and not per.has(pk):
			errs.append("요원 %s: 성향 %s가 rules.ai.persona에 없습니다." % [c.get("id", "?"), pk])


func _validate_rules(errs: Array[String]) -> void:
	var tile_total := 0
	var tiles: Dictionary = rules.get("tiles", {})
	for t in tiles:
		if not t.begins_with("_"):
			tile_total += int(tiles[t])
	var cells := size * size - 1 - bases.size()
	if tile_total > cells:
		errs.append("타일 %d장이 빈칸 %d칸보다 많습니다." % [tile_total, cells])
	if tiles.is_empty() or tile_total != 100:
		errs.append("[장수] 타일: %d장 (기준 100장)" % tile_total)
	_validate_tile_effects(errs, tiles)
	_validate_ops_rules(errs)
	var hide = rules.get("hide", null)
	if typeof(hide) != TYPE_DICTIONARY or typeof(hide.get("tiles", null)) != TYPE_ARRAY or typeof(hide.get("flags", null)) != TYPE_ARRAY:
		errs.append("rules.hide에 tiles와 flags(목록)가 있어야 합니다.")
	var scout = rules.get("scout", null)
	if typeof(scout) != TYPE_DICTIONARY or int(scout.get("count", 0)) < 1:
		errs.append("rules.scout.count는 1 이상이어야 합니다.")
	var market = rules.get("market", null)
	if typeof(market) != TYPE_DICTIONARY or typeof(market.get("tile", null)) != TYPE_STRING or typeof(market.get("offers", null)) != TYPE_ARRAY or market["offers"].is_empty():
		errs.append("rules.market에 tile(문자열)과 offers(목록)가 있어야 합니다.")
	else:
		var oseen := {}
		for o in market["offers"]:
			var ow := "장터 %s" % o.get("id", "?")
			if str(o.get("id", "")) == "" or oseen.has(o.get("id")):
				errs.append("%s: id가 비었거나 겹칩니다." % ow)
			oseen[o.get("id")] = true
			if int(o.get("cost", 0)) < 1 or str(o.get("name", "")) == "":
				errs.append("%s: name과 cost(1 이상)가 있어야 합니다." % ow)
			if o.has("cost_stat") and not o["cost_stat"] in KNOWN_STATS:
				errs.append("%s: 알 수 없는 cost_stat '%s'" % [ow, o["cost_stat"]])
			if not str(o.get("needs", "")) in ["", "item_slot", "bomb_slot"]:
				errs.append("%s: 알 수 없는 needs '%s'" % [ow, o.get("needs")])
			_check_effects(errs, ow, o.get("effects", []))
	var fnd = rules.get("funds", null)
	if typeof(fnd) != TYPE_DICTIONARY or int(fnd.get("max", 0)) < 1 or int(fnd.get("start", -1)) < 0 or int(fnd.get("start", 0)) > int(fnd.get("max", 0)) or int(fnd.get("exposure_cap_loss", -1)) < 0:
		errs.append("rules.funds에 start(0 이상, max 이하), max(1 이상), exposure_cap_loss(0 이상)가 있어야 합니다.")
	var ckp = rules.get("checkpoint", null)
	if typeof(ckp) != TYPE_DICTIONARY or int(ckp.get("bribe", 0)) < 1:
		errs.append("rules.checkpoint.bribe(검문소 뇌물 값, 1 이상)가 있어야 합니다.")
	var launch = rules.get("launch", null)
	if typeof(launch) != TYPE_DICTIONARY or int(launch.get("target_min_intel", 0)) < 1 or typeof(launch.get("benefits", null)) != TYPE_ARRAY:
		errs.append("rules.launch에 target_min_intel(1 이상)과 benefits(목록)가 있어야 합니다.")
	else:
		var bseen := {}
		for b in launch["benefits"]:
			var bwho := "결행 혜택 %s" % b.get("id", "?")
			if str(b.get("id", "")) == "" or bseen.has(b.get("id")):
				errs.append("%s: id가 비었거나 겹칩니다." % bwho)
			bseen[b.get("id")] = true
			for k in ["name", "text"]:
				if str(b.get(k, "")).strip_edges() == "":
					errs.append("%s: %s가 비었습니다." % [bwho, k])
			_check_effects(errs, bwho, b.get("effects", []))
	var cnt = rules.get("counter", null)
	if typeof(cnt) != TYPE_DICTIONARY or int(cnt.get("target", 0)) < 1:
		errs.append("rules.counter.target(1 이상)이 있어야 합니다.")
	var ai_r = rules.get("ai", null)
	if typeof(ai_r) != TYPE_DICTIONARY or typeof(ai_r.get("launch_target", null)) != TYPE_DICTIONARY:
		errs.append("rules.ai.launch_target(가중치)이 있어야 합니다.")
	var police_r = rules.get("police", {})
	if int(police_r.get("escape_distance", 0)) < 1 or int(police_r.get("rejoin_distance", 0)) < 1:
		errs.append("rules.police에 escape_distance와 rejoin_distance(1 이상)가 있어야 합니다.")


func _validate_tile_effects(errs: Array[String], tiles: Dictionary) -> void:
	var te = rules.get("tile_effects", null)
	if typeof(te) != TYPE_DICTIONARY:
		errs.append("rules.tile_effects(타일 효과)가 있어야 합니다.")
		return
	for t in te:
		if t.begins_with("_"):
			continue
		var who := "타일 효과 %s" % t
		if not tiles.has(t):
			errs.append("%s: rules.tiles에 없는 타일 종류입니다." % who)
		var def = te[t]
		if typeof(def) != TYPE_DICTIONARY:
			errs.append("%s: 객체가 아닙니다." % who)
			continue
		for k in def:
			if not k in ["on_stop", "on_turn_end", "needs", "once_per_day", "once", "text"]:
				errs.append("%s: 알 수 없는 키 '%s'" % [who, k])
		if def.has("once") and not tiles.has(def["once"]):
			errs.append("%s: once '%s'는 rules.tiles에 없는 타일 종류입니다." % [who, def["once"]])
		if def.has("needs") and not def["needs"] in ["ally_here"]:
			errs.append("%s: 알 수 없는 needs '%s'" % [who, def["needs"]])
		for k in ["on_stop", "on_turn_end"]:
			if def.has(k):
				if typeof(def[k]) != TYPE_ARRAY:
					errs.append("%s: %s는 효과 목록이어야 합니다." % [who, k])
				else:
					_check_effects(errs, who + " " + k, def[k])


func _validate_ops_rules(errs: Array[String]) -> void:
	var o = rules.get("ops", null)
	if typeof(o) != TYPE_DICTIONARY:
		errs.append("rules.ops(일제 동향)가 있어야 합니다.")
		return
	if typeof(o.get("days", null)) != TYPE_ARRAY or o["days"].is_empty():
		errs.append("rules.ops.days(일제 작전이 나오는 날 목록)가 있어야 합니다.")
	if int(o.get("trend_max", 0)) < 1:
		errs.append("rules.ops.trend_max는 1 이상이어야 합니다.")
	if typeof(o.get("block", null)) != TYPE_ARRAY:
		errs.append("rules.ops.block(작전을 막았을 때 효과 목록)이 있어야 합니다.")
	else:
		_check_effects(errs, "rules.ops.block", o["block"])
	var pen = o.get("penalties", null)
	if typeof(pen) != TYPE_ARRAY or pen.is_empty():
		errs.append("rules.ops.penalties(동향 단계별 추가 벌칙)가 있어야 합니다.")
	else:
		var last := -1
		for i in pen.size():
			var row = pen[i]
			if typeof(row) != TYPE_DICTIONARY or typeof(row.get("effects", null)) != TYPE_ARRAY:
				errs.append("rules.ops.penalties[%d]: min과 effects가 있어야 합니다." % i)
				continue
			if int(row.get("min", -1)) <= last or (i == 0 and int(row.get("min", -1)) != 0):
				errs.append("rules.ops.penalties[%d]: min은 0에서 시작해 커져야 합니다." % i)
			last = int(row.get("min", -1))
			_check_effects(errs, "rules.ops.penalties[%d]" % i, row["effects"])
	var rb = o.get("reinforce_by_trend", null)
	if typeof(rb) != TYPE_ARRAY:
		errs.append("rules.ops.reinforce_by_trend(동향별 증원 장수)가 있어야 합니다.")
	else:
		for row in rb:
			if typeof(row) != TYPE_DICTIONARY or int(row.get("count", 0)) < 1 or int(row.get("min", -1)) < 0:
				errs.append("rules.ops.reinforce_by_trend: min(0 이상)과 count(1 이상)가 있어야 합니다.")


func _validate_threats(errs: Array[String]) -> void:
	var seen := {}
	for act in [["act1", 21], ["act2", 11]]:
		var cards: Array = threats.get(act[0], [])
		_check_count(errs, "위협 " + act[0], _sum_count(cards), act[1], not threats.is_empty())
		for c in cards:
			var who: String = "위협 %s" % c.get("id", "?")
			_check_card(errs, who, c, seen, true)
			_check_effects(errs, who, c.get("effects", []))


func _validate_missions(errs: Array[String]) -> void:
	var cards: Array = missions.get("missions", [])
	var types: Dictionary = missions.get("types", {})
	var seen := {}
	var coop := 0
	for c in cards:
		var who: String = "미션 %s" % c.get("id", "?")
		_check_card(errs, who, c, seen, true)
		if not types.has(c.get("type")):
			errs.append("%s: 알 수 없는 종류 '%s'" % [who, c.get("type")])
		if c.get("type") == "coop":
			coop += 1
		var intel = c.get("intel")
		if intel != null and not intel in ["nearest", "entered"] and not intel in base_ids:
			errs.append("%s: intel '%s'는 거점 id가 아닙니다." % [who, intel])
		_check_marker_card(errs, who, c, false)
	var ops: Array = missions.get("ops", [])
	for c in ops:
		var who: String = "일제 작전 %s" % c.get("id", "?")
		_check_card(errs, who, c, seen, true)
		if c.get("type") != "op":
			errs.append("%s: type은 op여야 합니다." % who)
		_check_marker_card(errs, who, c, true)
	if not missions.is_empty():
		_check_count(errs, "미션", cards.size(), 22, true)
		_check_count(errs, "협동 미션", coop, 3, true)
		_check_count(errs, "일제 작전", ops.size(), 4, true)


func _check_marker_card(errs: Array[String], who: String, c: Dictionary, is_op: bool) -> void:
	## 미션·일제 작전 카드 하나: 조건 · 마커 · 기한 · 놓침 · 보너스 · 보상
	for k in ["where", "how"]:
		if str(c.get(k, "")).strip_edges() == "":
			errs.append("%s: %s가 비었습니다." % [who, k])
	var cond = c.get("condition")
	var kind := ""
	if typeof(cond) != TYPE_DICTIONARY or not cond.get("kind") in KNOWN_MISSION_KINDS:
		errs.append("%s: 알 수 없는 조건 kind '%s'" % [who, cond.get("kind") if typeof(cond) == TYPE_DICTIONARY else cond])
		cond = {}
	else:
		kind = str(cond["kind"])
	if cond.has("where") and not _where_ok(cond["where"]):
		errs.append("%s: 조건의 알 수 없는 where '%s'" % [who, cond["where"]])
	if cond.has("base") and not cond["base"] in base_ids:
		errs.append("%s: 조건의 base '%s'는 거점 id가 아닙니다." % [who, cond["base"]])
	if is_op and kind in ["cover_entry", "people", "opposite_edges"]:
		errs.append("%s: 일제 작전에는 협동 조건을 쓸 수 없습니다." % who)
	# 마커
	var markers = c.get("markers")
	if typeof(markers) != TYPE_ARRAY:
		errs.append("%s: markers(목록)가 있어야 합니다." % who)
		markers = []
	var roles := {}
	for m in markers:
		if typeof(m) != TYPE_DICTIONARY or not m.get("role") in KNOWN_MARKER_ROLES:
			errs.append("%s: 알 수 없는 마커 role '%s'" % [who, m.get("role") if typeof(m) == TYPE_DICTIONARY else m])
			continue
		roles[m["role"]] = int(roles.get(m["role"], 0)) + int(m.get("count", 1))
		if m.has("at") == m.has("around"):
			errs.append("%s: 마커 %s에는 at이나 around 중 하나만 있어야 합니다." % [who, m["role"]])
		for k in ["at", "around"]:
			if m.has(k) and not m[k] in MARKER_CENTERS:
				errs.append("%s: 마커 %s의 %s '%s'는 거점 id나 start가 아닙니다." % [who, m["role"], k, m[k]])
		if m.has("around") and (int(m.get("min", -1)) < 0 or int(m.get("max", -1)) < int(m.get("min", 0))):
			errs.append("%s: 마커 %s의 min·max가 바르지 않습니다." % [who, m["role"]])
		if int(m.get("count", 1)) < 1 or int(m.get("move", 0)) < 0:
			errs.append("%s: 마커 %s의 count(1 이상)나 move(0 이상)가 바르지 않습니다." % [who, m["role"]])
	var need_roles := []
	match kind:
		"assassinate":
			need_roles = ["target"]
			if str(cond.get("check", "")) == "" or int(cond.get("target", 0)) < 1:
				errs.append("%s: assassinate에는 check와 target(1 이상)이 있어야 합니다." % who)
			if roles.has("informer") and int(cond.get("informed_bonus", 0)) < 1:
				errs.append("%s: 정보원 마커가 있으면 informed_bonus(1 이상)가 있어야 합니다." % who)
		"infiltrate":
			need_roles = ["base"]
		"bomb":
			need_roles = ["target"]
		"work":
			need_roles = ["work"]
			var mode := str(cond.get("mode", ""))
			if not mode in KNOWN_WORK_MODES:
				errs.append("%s: 알 수 없는 공작 방식 '%s'" % [who, mode])
			if mode == "sum" and int(cond.get("target", 0)) < 1:
				errs.append("%s: 합 공작에는 target(1 이상)이 있어야 합니다." % who)
			if mode == "combo" and (typeof(cond.get("values", null)) != TYPE_ARRAY or cond["values"].is_empty()):
				errs.append("%s: 조합 공작에는 values(눈 목록)가 있어야 합니다." % who)
		"contact":
			need_roles = ["pickup", "dropoff"]
		"lurk":
			need_roles = ["spot"]
			if int(cond.get("days", 0)) < 1:
				errs.append("%s: lurk에는 days(1 이상)가 있어야 합니다." % who)
	for r in need_roles:
		if not roles.has(r):
			errs.append("%s: %s 조건에는 %s 마커가 있어야 합니다." % [who, kind, r])
	if kind in ["cover_entry", "people", "opposite_edges"] and not markers.is_empty():
		errs.append("%s: 협동 미션에는 마커가 없습니다." % who)
	if kind == "infiltrate" and not str(cond.get("base", "")) in base_ids:
		errs.append("%s: infiltrate에는 base(거점 id)가 있어야 합니다." % who)
	# 기한 · 놓침
	if c.has("deadline"):
		if int(c["deadline"]) < 1:
			errs.append("%s: deadline은 1 이상이어야 합니다." % who)
		if typeof(c.get("missed", null)) != TYPE_ARRAY or c["missed"].is_empty():
			errs.append("%s: 기한이 있으면 놓쳤을 때(missed) 효과가 있어야 합니다." % who)
	elif is_op:
		errs.append("%s: 일제 작전에는 deadline이 있어야 합니다." % who)
	_check_effects(errs, who + " missed", c.get("missed", []))
	if is_op and typeof(c.get("missed", null)) != TYPE_ARRAY:
		errs.append("%s: missed(못 막았을 때 벌칙)가 있어야 합니다." % who)
	# 보너스 · 보상 · 돈 대신 아이템(gear)
	var b = c.get("bonus")
	if b != null:
		if typeof(b) != TYPE_DICTIONARY or typeof(b.get("if", null)) != TYPE_DICTIONARY or not b["if"].get("kind") in KNOWN_BONUS_CONDS:
			errs.append("%s: bonus.if의 kind가 어휘에 없습니다." % who)
		else:
			if b["if"]["kind"] == "launch_target" and not str(b["if"].get("base", "")) in base_ids:
				errs.append("%s: launch_target 보너스에는 base(거점 id)가 있어야 합니다." % who)
			if str(b.get("text", "")).strip_edges() == "":
				errs.append("%s: bonus.text가 비었습니다." % who)
			_check_effects(errs, who + " bonus", b.get("reward", []))
	if not is_op:
		if typeof(c.get("ready", null)) != TYPE_INT and typeof(c.get("ready", null)) != TYPE_FLOAT:
			errs.append("%s: ready(결행 준비 수치)가 있어야 합니다." % who)
		_check_effects(errs, who, c.get("rewards", []))
	var gear = cond.get("gear")
	if gear != null:
		if typeof(gear) != TYPE_DICTIONARY or typeof(gear.get("cost", null)) != TYPE_DICTIONARY or gear["cost"].is_empty() or str(gear.get("text", "")) == "":
			errs.append("%s: gear에는 cost({item, funds})와 text가 있어야 합니다." % who)
		else:
			for k in gear["cost"]:
				if not k in ["item", "funds"] or int(gear["cost"][k]) < 1:
					errs.append("%s: gear의 알 수 없는 cost '%s'" % [who, k])
			if not gear.has("check_bonus") and not gear.has("effects"):
				errs.append("%s: gear에는 check_bonus나 effects가 있어야 합니다." % who)
			_check_effects(errs, who + " gear", gear.get("effects", []))
	var ic = cond.get("informer_cost")
	if ic != null and (typeof(ic) != TYPE_DICTIONARY or int(ic.get("funds", 0)) < 1):
		errs.append("%s: informer_cost에는 funds(1 이상)가 있어야 합니다." % who)


func _validate_events(errs: Array[String]) -> void:
	var cards: Array = events.get("events", [])
	var seen := {}
	for c in cards:
		var who: String = "이벤트 %s" % c.get("id", "?")
		_check_card(errs, who, c, seen, true)
		_check_effects(errs, who, c.get("effects", []))
	if not events.is_empty():
		_check_count(errs, "이벤트 종류", cards.size(), 10, true)
		_check_count(errs, "이벤트 장수", _sum_count(cards), 18, true)


func _validate_items(errs: Array[String]) -> void:
	var cards: Array = items.get("items", [])
	var seen := {}
	for c in cards:
		var who: String = "아이템 %s" % c.get("id", "?")
		_check_card(errs, who, c, seen, true)
		_check_effects(errs, who, c.get("effects", []))
		_check_mods(errs, who, c.get("mods", []))
	if not items.is_empty():
		_check_count(errs, "아이템 종류", cards.size(), 10, true)
		_check_count(errs, "아이템 장수", _sum_count(cards), 14, true)


func _validate_scenes(errs: Array[String]) -> void:
	var seen := {}
	var strikes: Dictionary = scenes.get("strikes", {})
	for base_id in strikes:
		if base_id.begins_with("_"):
			continue
		var who: String = "결행 " + base_id
		if not base_id in base_ids:
			errs.append("%s: 거점 id가 아닙니다." % who)
		var s: Dictionary = strikes[base_id]
		if str(s.get("name", "")).strip_edges() == "":
			errs.append("%s: name이 비었습니다." % who)
		if s.has("base") and not s["base"] in base_ids:
			errs.append("%s: base '%s'는 거점 id가 아닙니다." % [who, s["base"]])
		_check_effects(errs, who + " on_launch", s.get("on_launch", []))
		var cards: Array = []
		if s.get("entry") is Dictionary:
			cards.append(s["entry"])
		else:
			errs.append("[장수] %s: 진입 장면이 없습니다." % who)
		cards.append_array(s.get("middle", []))
		if s.get("final") is Dictionary:
			cards.append(s["final"])
			if _has_kind(s["final"].get("condition"), "pay_funds"):
				errs.append("%s: 마지막 장면은 매수(pay_funds)할 수 없습니다." % who)
		else:
			errs.append("[장수] %s: 마지막 장면이 없습니다." % who)
		_check_count(errs, who + " 중간 장면", s.get("middle", []).size(), 4, true)
		for c in cards:
			_check_scene_card(errs, who, c, seen)
	if not scenes.is_empty():
		_check_count(errs, "결행 거점", strikes.keys().filter(func(k): return not k.begins_with("_")).size(), 4, true)
		var reinforce: Array = scenes.get("reinforce", [])
		_check_count(errs, "경비 강화", reinforce.size(), 4, true)
		for c in reinforce:
			_check_scene_card(errs, "경비 강화", c, seen)


func _validate_endings(errs: Array[String]) -> void:
	var strikes: Dictionary = endings.get("strikes", {})
	for id in base_ids:
		var entry: Dictionary = strikes.get(id, {})
		for key in ["name", "ending"]:
			if str(entry.get(key, "")).strip_edges() == "":
				errs.append("엔딩 %s: %s이 비었습니다." % [id, key])
	if str(endings.get("funds_left", {}).get("text", "")).find("{n}") < 0:
		errs.append("엔딩 funds_left: text에 {n}(남은 군자금)이 있어야 합니다.")
	for id in ["victory", "fail_final", "operation", "history"]:
		var entry: Dictionary = endings.get(id, {})
		var keys := ["name"] if id == "victory" else ["name", "text"]
		for key in keys:
			if str(entry.get(key, "")).strip_edges() == "":
				errs.append("엔딩 %s: %s이 비었습니다." % [id, key])


func _check_scene_card(errs: Array[String], group: String, c: Dictionary, seen: Dictionary) -> void:
	var who: String = "%s 장면 %s" % [group, c.get("id", "?")]
	_check_card(errs, who, c, seen, false)
	var w = c.get("where")
	if w != null and not _where_ok(w):
		errs.append("%s: 알 수 없는 where '%s'" % [who, w])
	_check_scene_cond(errs, who, c.get("condition"))
	_check_effects(errs, who + " on_fail", c.get("on_fail", []))


func _validate_sagas(errs: Array[String]) -> void:
	var cards: Array = sagas.get("sagas", [])
	var seen := {}
	var piles: Dictionary = sagas.get("piles", {})
	var in_pile := {}
	for p in piles:
		if not p.begins_with("_"):
			in_pile[p] = 0
	for c in cards:
		var who: String = "사연 %s" % c.get("id", "?")
		_check_card(errs, who, c, seen, false)
		for p in piles:
			if not p.begins_with("_") and c.get("branch") in piles[p]:
				in_pile[p] += 1
		_check_saga_cond(errs, who, c.get("condition"))
		_check_effects(errs, who + " reward", c.get("reward", []))
		for ch in c.get("redraw_for", []):
			if not _characters.has(ch):
				errs.append("%s: redraw_for의 캐릭터 '%s'가 없습니다." % [who, ch])
		var ep = c.get("epilogue")
		if typeof(ep) != TYPE_DICTIONARY:
			errs.append("%s: epilogue가 없습니다." % who)
		else:
			for k in EPILOGUE_KEYS:
				if not ep.has(k):
					errs.append("%s: epilogue에 '%s'가 없습니다." % [who, k])
	if not sagas.is_empty():
		_check_count(errs, "사연", cards.size(), 20, true)
		_check_count(errs, "사연 더미 a", in_pile.get("a", 0), 9, true)
		_check_count(errs, "사연 더미 b", in_pile.get("b", 0), 11, true)


func _validate_characters(errs: Array[String]) -> void:
	var cards: Array = characters.get("characters", [])
	var factions: Dictionary = characters.get("factions", {})
	var seen := {}
	var per_faction := {}
	var female := 0
	for c in cards:
		var who: String = "캐릭터 %s" % c.get("id", "?")
		_check_card(errs, who, c, seen, false)
		if not factions.has(c.get("faction")):
			errs.append("%s: 알 수 없는 소속 '%s'" % [who, c.get("faction")])
		per_faction[c.get("faction")] = per_faction.get(c.get("faction"), 0) + 1
		if c.get("gender") == "f":
			female += 1
		var trait_d = c.get("trait", {})
		if typeof(trait_d) == TYPE_DICTIONARY:
			_check_mods(errs, who, trait_d.get("mods", []))
		var ab = c.get("ability", {})
		if typeof(ab) == TYPE_DICTIONARY and not ab.is_empty():
			if ab.has("target") and not ab["target"] in KNOWN_TARGETS:
				errs.append("%s: 능력의 알 수 없는 target '%s'" % [who, ab["target"]])
			for k in ab.get("requires", {}):
				if not k in KNOWN_REQUIRES:
					errs.append("%s: 능력의 알 수 없는 requires '%s'" % [who, k])
			if ab.has("cost") and not ab["cost"] in KNOWN_COSTS:
				errs.append("%s: 능력의 알 수 없는 cost '%s'" % [who, ab["cost"]])
			_check_effects(errs, who + " 능력", ab.get("effects", []))
	if not characters.is_empty():
		_check_count(errs, "캐릭터", cards.size(), 12, true)
		_check_count(errs, "여성 캐릭터", female, 4, true)
		for f in factions:
			if not f.begins_with("_"):
				_check_count(errs, "소속 " + f, per_faction.get(f, 0), 3, true)


# ------------------------------------------------------------------ 검증 부품

func _check_count(errs: Array[String], what: String, got: int, want: int, enabled: bool) -> void:
	if enabled and got != want:
		errs.append("[장수] %s: %d장 (기준 %d장)" % [what, got, want])


func _sum_count(cards: Array) -> int:
	var n := 0
	for c in cards:
		n += int(c.get("count", 1))
	return n


func _check_card(errs: Array[String], who: String, c: Dictionary, seen: Dictionary, need_text: bool) -> void:
	var id = c.get("id", "")
	if str(id) == "":
		errs.append("%s: id가 비었습니다." % who)
	elif seen.has(id):
		errs.append("%s: id '%s'가 중복됩니다." % [who, id])
	seen[id] = true
	if str(c.get("name", "")).strip_edges() == "":
		errs.append("%s: name이 비었습니다." % who)
	if need_text and str(c.get("text", "")).strip_edges() == "":
		errs.append("%s: text가 비었습니다." % who)


func _check_effects(errs: Array[String], who: String, effects: Array) -> void:
	## 중첩 효과(choice·if_players)까지 따라 들어간다.
	for e in effects:
		if typeof(e) != TYPE_DICTIONARY:
			errs.append("%s: 효과가 객체가 아닙니다." % who)
			continue
		var op = e.get("op")
		if not op in KNOWN_OPS:
			errs.append("%s: 알 수 없는 op '%s'" % [who, op])
		for k in ["who", "target"]:
			if e.has(k) and not e[k] in KNOWN_TARGETS:
				errs.append("%s: %s의 알 수 없는 %s '%s'" % [who, op, k, e[k]])
		if op == "police_attach" and e.has("at") and e["at"] != "here":
			errs.append("%s: police_attach의 알 수 없는 at '%s'" % [who, e["at"]])
		if op == "police_dispatch" and e.has("from"):
			if not e["from"] in ["random_base", "strike_base", "marker"] and not e["from"] in base_ids:
				errs.append("%s: police_dispatch의 알 수 없는 from '%s'" % [who, e["from"]])
		if op == "intel" and e.has("base"):
			if not e["base"] in ["nearest", "choose", "entered", "highest"] and not e["base"] in base_ids:
				errs.append("%s: intel의 알 수 없는 base '%s'" % [who, e["base"]])
		if op == "funds" and int(e.get("value", 0)) == 0:
			errs.append("%s: funds에는 value(0이 아님)가 있어야 합니다." % who)
		if e.has("short"):
			_check_effects(errs, who + " short", e["short"])
		if op == "draw_item" and e.has("item") and not _items.has(e["item"]):
			errs.append("%s: draw_item의 아이템 '%s'가 없습니다." % [who, e["item"]])
		if op == "choice":
			for o in e.get("options", []):
				_check_effects(errs, who + " 선택", o.get("effects", []))
		elif op == "if_players" or op == "if":
			if op == "if" and not e.get("cond") in KNOWN_IF_CONDS:
				errs.append("%s: if의 알 수 없는 cond '%s'" % [who, e.get("cond")])
			_check_effects(errs, who, e.get("then", []))
			_check_effects(errs, who, e.get("else", []))


func _check_mods(errs: Array[String], who: String, mods: Array) -> void:
	for m in mods:
		if typeof(m) != TYPE_DICTIONARY or not m.get("stat") in KNOWN_STATS:
			errs.append("%s: 알 수 없는 stat '%s'" % [who, m.get("stat") if typeof(m) == TYPE_DICTIONARY else m])


func _check_scene_cond(errs: Array[String], who: String, cond) -> void:
	_check_cond(errs, who, cond, KNOWN_SCENE_CONDITIONS)


func _check_saga_cond(errs: Array[String], who: String, cond) -> void:
	_check_cond(errs, who, cond, KNOWN_SAGA_CONDITIONS)
	if typeof(cond) == TYPE_DICTIONARY:
		for k in ["base", "strike"]:
			if cond.has(k) and not cond[k] in base_ids:
				errs.append("%s: 조건의 %s '%s'는 거점 id가 아닙니다." % [who, k, cond[k]])


func _check_cond(errs: Array[String], who: String, cond, known: Array) -> void:
	## any_of/all_of 안쪽 조건까지 검사한다. 조건이 없거나(null) 문장뿐이면 넘어간다.
	if typeof(cond) != TYPE_DICTIONARY or cond.is_empty():
		return
	var kind = cond.get("kind")
	if not kind in known:
		errs.append("%s: 알 수 없는 조건 kind '%s'" % [who, kind])
	if cond.has("where") and not _where_ok(cond["where"]):
		errs.append("%s: 조건의 알 수 없는 where '%s'" % [who, cond["where"]])
	if known == KNOWN_SCENE_CONDITIONS and cond.has("base") and not cond["base"] in base_ids and cond["base"] != "card":
		errs.append("%s: 조건의 base '%s'는 거점 id가 아닙니다." % [who, cond["base"]])
	if kind == "any_of" or kind == "all_of":
		for o in cond.get("options", []):
			_check_cond(errs, who, o, known)
	if kind == "sequence":
		if cond.get("steps", []).size() < 2:
			errs.append("%s: sequence에는 단계(steps)가 둘 이상 있어야 합니다." % who)
		for o in cond.get("steps", []):
			_check_cond(errs, who, o, known)
	if known == KNOWN_SAGA_CONDITIONS:
		if kind == "mission_done_by_me" and not _missions.has(str(cond.get("mission", ""))):
			errs.append("%s: mission_done_by_me의 미션 '%s'가 없습니다." % [who, cond.get("mission", "")])
		if cond.has("or"):
			_check_cond(errs, who, cond["or"], known)


func _has_kind(cond, kind: String) -> bool:
	if typeof(cond) != TYPE_DICTIONARY:
		return false
	if cond.get("kind") == kind:
		return true
	for o in cond.get("options", []) + cond.get("steps", []):
		if _has_kind(o, kind):
			return true
	return false


func _where_ok(w) -> bool:
	return w in KNOWN_WHERE or w in base_ids


func _collect_todos(node, path: String) -> void:
	## 모든 카드를 훑어 _todo가 달린 것을 경고 목록에 모은다.
	if typeof(node) == TYPE_DICTIONARY:
		if node.has("_todo"):
			_todos.append("%s: %s" % [path, node["_todo"]])
		for k in node:
			var child = node[k]
			if typeof(child) == TYPE_DICTIONARY or typeof(child) == TYPE_ARRAY:
				var label: String = str(k)
				if typeof(child) == TYPE_DICTIONARY and child.has("id"):
					label = str(child["id"])
				_collect_todos(child, path + "/" + label)
	elif typeof(node) == TYPE_ARRAY:
		for i in node.size():
			var child = node[i]
			var label := str(i)
			if typeof(child) == TYPE_DICTIONARY and child.has("id"):
				label = str(child["id"])
			_collect_todos(child, path + "/" + label)


# ------------------------------------------------------------------ 유틸

func _read_optional(file: String) -> Dictionary:
	## 없어도 되는 파일 (없으면 빈 사전)
	if not FileAccess.file_exists(_dir + file):
		return {}
	return _read(file)


func _read(file: String) -> Dictionary:
	var path := _dir + file
	if not FileAccess.file_exists(path):
		_missing.append(path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_unreadable.append(path)
		return {}
	return parsed


static func _index(cards: Array) -> Dictionary:
	var out := {}
	for c in cards:
		if typeof(c) == TYPE_DICTIONARY and c.has("id"):
			out[c["id"]] = c
	return out
