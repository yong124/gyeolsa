class_name GameData
extends RefCounted
## data/*.json을 읽어 규칙 엔진·AI·UI에 제공한다. 게임 수치와 카드는 전부 여기서 나온다.

const DATA_DIR := "res://data/"

## 규칙 엔진이 아는 효과 연산 / 보정 / 조건 이름. validate()가 오타를 잡는 데 쓴다.
const KNOWN_OPS := ["add_steps", "remove_my_police", "remove_all_police", "skip_next_turn",
	"police_next_turn", "free_all_jailed", "escape_jail", "move_mod", "draw_item", "discard_item",
	"add_score", "summon_police", "target_move_mod", "remove_target_police", "pull_target"]
const KNOWN_WORLD_OPS := ["place_checkpoints", "raid_police", "police_advance", "all_move_mod",
	"police_speed_today", "exposure"]
const KNOWN_TARGETS := ["ally", "ally_pullable", "police_near"]
const KNOWN_STATS := ["move_bonus", "move_min", "assassin_bonus", "assassin_threshold",
	"assassin_rerolls", "evade_bonus", "evade_auto", "evade_auto_after_assassin",
	"escape_bonus", "base_no_police"]
const KNOWN_CONDITIONS := ["alert_max", "alert_min", "jailed", "has_my_police", "any_police",
	"other_items_min"]
const KNOWN_REACTS := {"evade": ["auto_success"], "event": ["cancel_event"]}
const KNOWN_SCENARIO := ["rounds", "goal", "police_speed_mod", "start_jailed", "jail_base", "start_items",
	"first_missions", "tile_order_top", "two_act"]
const KNOWN_ACHIEVEMENT := ["ending", "my_jailed_max", "days_left_min", "my_rescues_min", "my_points_min",
	"players_min", "difficulty", "tutorial", "scenario", "factions_won", "scenarios_won", "games_min"]

static var _cache: GameData

var balance: Dictionary
var factions: Dictionary
var cards: Dictionary
var text: Dictionary
var scenarios: Dictionary        # 특수 작전 (scenarios.json)
var achievements: Dictionary     # 도전 과제 (achievements.json)

var size := 11
var start := Vector2i(5, 5)
var bases: Array[Vector2i] = []
var base_names: Array[String] = []
var stations: Array[Vector2i] = []

var _items := {}
var _events := {}
var _missions := {}
var _occupation := {}


static func load_default() -> GameData:
	if _cache == null:
		_cache = GameData.new()
		_cache.load_dir(DATA_DIR)
	return _cache


func load_dir(dir: String) -> void:
	balance = _read(dir + "balance.json")
	factions = _read(dir + "factions.json")
	cards = _read(dir + "cards.json")
	text = _read(dir + "text.json")
	scenarios = _read(dir + "scenarios.json") if FileAccess.file_exists(dir + "scenarios.json") else {}
	achievements = _read(dir + "achievements.json") if FileAccess.file_exists(dir + "achievements.json") else {}
	for k in factions.keys():
		if k.begins_with("_"):
			factions.erase(k)
	var b: Dictionary = balance["board"]
	size = int(b["size"])
	start = _v(b["start"])
	bases.clear()
	base_names.clear()
	for e in b["bases"]:
		bases.append(_v(e["pos"]))
		base_names.append(e["name"])
	stations.clear()
	for s in b["stations"]:
		stations.append(_v(s))
	_items.clear()
	for it in cards["items"]:
		_items[it["id"]] = it
	_items["bomb"] = cards["bomb"]
	_events.clear()
	for e in cards["events"]:
		_events[e["id"]] = e
	_missions.clear()
	for m in cards["missions"]:
		_missions[m["type"]] = m
	_occupation.clear()
	for o in cards.get("occupation", []):
		_occupation[o["id"]] = o


# ------------------------------------------------------------------ 조회

func item(id: String) -> Dictionary:
	return _items.get(id, {})


func event(id: String) -> Dictionary:
	return _events.get(id, {})


func occupation(id: String) -> Dictionary:
	return _occupation.get(id, {})


func mission(type: String) -> Dictionary:
	return _missions.get(type, {})


func faction(key: String) -> Dictionary:
	return factions.get(key, {})


func faction_keys() -> Array:
	return factions.keys()


func tile(type: String) -> Dictionary:
	return balance["tiles"].get(type, {})


func tile_name(type: String) -> String:
	return tile(type).get("name", type)


func check(kind: String) -> int:
	return int(balance["checks"][kind])


func by_players(table: Dictionary, n: int, fallback: int) -> int:
	return int(table.get(str(n), fallback))


func rounds_for(n: int, two_act := true) -> int:
	## 작전 일수. 2막 구조 판은 따로 정한 일수를 쓴다 (기획서 16장)
	var ta: Dictionary = balance.get("two_act", {})
	if two_act and ta.get("enabled", false) and ta.has("rounds_by_players"):
		return by_players(ta["rounds_by_players"], n, 10)
	return by_players(balance["calendar"]["rounds_by_players"], n, 10)


func goal_for(n: int) -> int:
	return by_players(balance["goal_by_players"], n, 10)


func ending_for(score: int, goal: int) -> Dictionary:
	var id := "history"
	for e in balance["endings"]:
		var need: int = goal if int(e["min_score"]) < 0 else int(e["min_score"])
		if score >= need:
			id = e["id"]
	var out: Dictionary = text["endings"][id].duplicate()
	out["id"] = id
	return out


func special_ops() -> Array:
	return scenarios.get("list", [])


func special_op(id: String) -> Dictionary:
	for s in special_ops():
		if s["id"] == id:
			return s
	return {}


# ------------------------------------------------------------------ 검증

func validate() -> Array[String]:
	## 데이터 오타·누락을 찾아 메시지 목록으로 돌려준다. 빈 배열이면 정상.
	var errs: Array[String] = []
	var tile_total := 0
	for t in balance["tiles"]:
		tile_total += int(balance["tiles"][t]["count"])
	var cells := size * size - 1 - bases.size() - stations.size()
	if tile_total > cells:
		errs.append("타일 %d장이 빈칸 %d칸보다 많습니다." % [tile_total, cells])
	for s in special_ops():
		for k in s.get("scenario", {}):
			if not k in KNOWN_SCENARIO:
				errs.append("특수 작전 %s: 알 수 없는 설정 '%s'" % [s.get("id"), k])
		if int(s.get("players", 0)) < 2 or int(s.get("players", 0)) > 6:
			errs.append("특수 작전 %s: 인원은 2~6명" % s.get("id"))
	for a in achievements.get("list", []):
		for k in a.get("when", {}):
			if not k in KNOWN_ACHIEVEMENT:
				errs.append("도전 과제 %s: 알 수 없는 조건 '%s'" % [a.get("id"), k])
	for f in factions:
		_check_mods(errs, "세력 " + f, factions[f].get("modifiers", []))
		var a: Dictionary = factions[f].get("active", {})
		if not a.is_empty():
			_check_effects(errs, "세력 능력 " + f, a.get("effects", []))
			if not a.get("target", "") in KNOWN_TARGETS:
				errs.append("세력 능력 %s: 알 수 없는 target '%s'" % [f, a.get("target")])
	for id in _occupation:
		for e in _occupation[id].get("effects", []):
			if not e.get("op") in KNOWN_WORLD_OPS:
				errs.append("일제 동향 %s: 알 수 없는 op '%s'" % [id, e.get("op")])
	for id in _items:
		var it: Dictionary = _items[id]
		_check_mods(errs, "아이템 " + id, it.get("modifiers", []))
		if it.has("use"):
			var u: Dictionary = it["use"]
			_check_effects(errs, "아이템 " + id, u.get("effects", []))
			_check_cond(errs, "아이템 " + id, u.get("requires", {}))
			for ph in u.get("phases", []):
				if not ph in ["start", "move"]:
					errs.append("아이템 %s: 사용 단계 '%s'는 start/move만 가능합니다." % [id, ph])
		if it.has("react"):
			var r: Dictionary = it["react"]
			if not KNOWN_REACTS.has(r.get("trigger")) or not r.get("effect") in KNOWN_REACTS[r.get("trigger")]:
				errs.append("아이템 %s: 알 수 없는 react %s/%s" % [id, r.get("trigger"), r.get("effect")])
	for id in _events:
		_check_effects(errs, "이벤트 " + id, _events[id].get("effects", []))
	for m in cards["missions"]:
		if not m["type"] in ["assassin", "intel", "bomb", "sabotage"]:
			errs.append("미션 종류 '%s'는 지원하지 않습니다." % m["type"])
	return errs


func _check_mods(errs: Array[String], who: String, mods: Array) -> void:
	for m in mods:
		if not m.get("stat") in KNOWN_STATS:
			errs.append("%s: 알 수 없는 stat '%s'" % [who, m.get("stat")])
		if not m.get("mode", "add") in ["add", "min", "max", "set"]:
			errs.append("%s: 알 수 없는 mode '%s'" % [who, m.get("mode")])
		_check_cond(errs, who, m.get("when", {}))


func _check_effects(errs: Array[String], who: String, effects: Array) -> void:
	for e in effects:
		if not e.get("op") in KNOWN_OPS:
			errs.append("%s: 알 수 없는 op '%s'" % [who, e.get("op")])


func _check_cond(errs: Array[String], who: String, cond: Dictionary) -> void:
	for k in cond:
		if not k in KNOWN_CONDITIONS:
			errs.append("%s: 알 수 없는 조건 '%s'" % [who, k])


# ------------------------------------------------------------------ 유틸

static func _read(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("데이터 파일을 읽을 수 없습니다: " + path)
		return {}
	return parsed


static func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
