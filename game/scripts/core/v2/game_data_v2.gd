class_name GameDataV2
extends RefCounted
## data/v2/*.json을 읽어 v2 규칙 엔진·UI에 제공한다. v1 GameData는 건드리지 않고 보드 정보만 읽어 온다.
## 효과·조건 어휘는 v2_구현/1단계_데이터.md 3절과 같다. validate()가 오타·장수 누락을 잡는다.

const DIR := "res://data/v2/"

## 거점 문자열 id. 위치(index)는 v1 balance.json의 bases 순서와 같다.
const BASE_IDS := ["barracks", "police_hq", "prison", "gg"]

## 3-1. 대상 (who, target)
const KNOWN_TARGETS := ["self", "ally", "ally_same_cell", "ally_adjacent", "ally_in_range", "all", "allies",
	"isolated", "wanted", "nearest_to_base", "all_jailed"]
## 3-2. 효과 op
const KNOWN_OPS := ["police_dispatch", "police_attach", "police_advance", "police_remove", "police_push",
	"police_send_far", "checkpoint_place", "dice_mod_today", "police_speed_today", "exposure",
	"free_all_jailed", "escape_mod_today", "scene_check_mod_today", "search", "interrogate", "intel",
	"ready", "draw_item", "gain_bomb", "discard_item", "move_mod_next", "move_today",
	"team_dice_extra_tomorrow", "team_die_reroll", "team_die_adjust", "team_die_set",
	"team_dice_reroll_all", "threat_bury", "grant_once", "persuade", "place_tile", "extra_step",
	"mark_tile", "move_to_ally", "pull_ally", "give_item", "send_item", "skip_dice_tomorrow",
	"checkpoint_pass", "refill_supply", "choice", "if_players",
	"if", "interrogate_discard", "threat_flip", "check_or_jail", "entry_no_police"]
## if op의 cond
const KNOWN_IF_CONDS := ["chased", "not_chased", "has_interrogation"]
## 능력 사용 조건 (ability.requires)
const KNOWN_REQUIRES := ["near_tile"]
## 3-3. 장면·협동 조건 kind
const KNOWN_SCENE_CONDITIONS := ["enter_base", "deliver_bomb", "check", "check_pair", "dice", "pay_item", "pay_bomb", "people", "hold",
	"jailed_here", "any_of", "all_of", "cover_entry", "same_day_assassin", "opposite_edges"]
## 3-4. 사연 조건 kind
const KNOWN_SAGA_CONDITIONS := ["end_turn_near_base", "visit_base_adjacent", "touch_edge", "end_turn_at_start",
	"visit_tile", "hold_items", "take_die", "take_lowest_die", "shake_police", "pass_checkpoint",
	"never_jailed_until_launch", "chased_turns_row", "rescue_or_escape", "same_cell_turns",
	"coop_missions", "give_items", "strike_final_by_me", "present_at_final", "strike_entry_by_me"]
## 3-5. 캐릭터 특성·아이템 지속 효과 stat
const KNOWN_STATS := ["evade_auto", "escape_bonus", "rescued_move_bonus", "assassin_rerolls", "bomb_slots",
	"sabotage_bonus", "sabotage_exposure", "move_min3", "hand_limit", "item_draw_choice",
	"mission_intel_bonus", "threat_peek", "block_police_with_evade", "end_move_hop_to_ally",
	"spare_die_bonus", "assassin_bonus", "evade_bonus", "move_bonus", "base_no_police"]
## where는 이 값 말고 거점 id도 쓸 수 있다.
const KNOWN_WHERE := ["inside", "adjacent", "inside_or_adjacent"]

const EPILOGUE_KEYS := ["win_done", "win_fail", "lose_done", "lose_fail", "traitor"]

static var _cache: GameDataV2

var rules: Dictionary
var threats: Dictionary
var interrogation: Dictionary
var missions: Dictionary
var events: Dictionary
var items: Dictionary
var scenes: Dictionary
var endings: Dictionary
var sagas: Dictionary
var characters: Dictionary

## v1 GameData에서 읽기만 한 보드 정보
var board := {}
var size := 11
var start := Vector2i(5, 5)
var bases: Array[Vector2i] = []
var base_names: Array[String] = []

var _dir := DIR
var _missing: Array[String] = []
var _unreadable: Array[String] = []
var _missions := {}
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
	interrogation = _read("interrogation.json")
	missions = _read("missions.json")
	events = _read("events.json")
	items = _read("items.json")
	scenes = _read("scenes.json")
	endings = _read("endings.json")
	sagas = _read("sagas.json")
	characters = _read("characters.json")
	_load_board()
	_missions = _index(missions.get("missions", []))
	_events = _index(events.get("events", []))
	_items = _index(items.get("items", []))
	_sagas = _index(sagas.get("sagas", []))
	_characters = _index(characters.get("characters", []))


func _load_board() -> void:
	var v1 := GameData.load_default()
	size = v1.size
	start = v1.start
	bases = v1.bases.duplicate()
	base_names = v1.base_names.duplicate()
	board = {"size": size, "start": start, "bases": bases, "base_names": base_names}


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
	return BASE_IDS.find(base_id)


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
	_validate_rules(errs)
	_validate_threats(errs)
	_validate_interrogation(errs)
	_validate_missions(errs)
	_validate_events(errs)
	_validate_items(errs)
	_validate_scenes(errs)
	_validate_endings(errs)
	_validate_sagas(errs)
	_validate_characters(errs)
	for name in ["rules", "threats", "interrogation", "missions", "events", "items", "scenes", "endings", "sagas", "characters"]:
		_collect_todos(get(name), name)
	return errs


func _validate_rules(errs: Array[String]) -> void:
	var tile_total := 0
	var tiles: Dictionary = rules.get("tiles", {})
	for t in tiles:
		if not t.begins_with("_"):
			tile_total += int(tiles[t])
	var cells := size * size - 1 - bases.size()
	if tile_total > cells:
		errs.append("타일 %d장이 빈칸 %d칸보다 많습니다." % [tile_total, cells])


func _validate_threats(errs: Array[String]) -> void:
	var seen := {}
	for act in [["act1", 24], ["act2", 11]]:
		var cards: Array = threats.get(act[0], [])
		_check_count(errs, "위협 " + act[0], _sum_count(cards), act[1], not threats.is_empty())
		for c in cards:
			var who: String = "위협 %s" % c.get("id", "?")
			_check_card(errs, who, c, seen, true)
			_check_effects(errs, who, c.get("effects", []))


func _validate_interrogation(errs: Array[String]) -> void:
	var cards: Array = interrogation.get("cards", [])
	var seen := {}
	var shaken := 0
	for c in cards:
		_check_card(errs, "심문 %s" % c.get("id", "?"), c, seen, true)
		if c.get("shaken", false):
			shaken += int(c.get("count", 1))
	if not interrogation.is_empty():
		_check_count(errs, "심문 카드", _sum_count(cards), 12, true)
		# "흔들렸다" 장수는 밸런스 레버라 정해 두지 않는다 (변절 빈도로 맞춤). 두 종류가 다 있어야만 한다.
		if shaken <= 0 or shaken >= _sum_count(cards):
			errs.append("[장수] 심문 카드: 버텼다와 흔들렸다가 모두 있어야 합니다 (흔들렸다 %d장)" % shaken)


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
		if intel != null and not intel in ["nearest", "entered"] and not intel in BASE_IDS:
			errs.append("%s: intel '%s'는 거점 id가 아닙니다." % [who, intel])
		if c.has("base") and not c["base"] in BASE_IDS:
			errs.append("%s: base '%s'는 거점 id가 아닙니다." % [who, c["base"]])
		_check_effects(errs, who, c.get("rewards", []))
		_check_scene_cond(errs, who, c.get("condition"))
	for t in types:
		if not t.begins_with("_") and typeof(types[t]) == TYPE_DICTIONARY:
			_check_scene_cond(errs, "미션 종류 " + t, types[t].get("condition"))
	if not missions.is_empty():
		_check_count(errs, "미션", cards.size(), 20, true)
		_check_count(errs, "협동 미션", coop, 5, true)


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
		_check_count(errs, "아이템 장수", _sum_count(cards), 15, true)


func _validate_scenes(errs: Array[String]) -> void:
	var seen := {}
	var strikes: Dictionary = scenes.get("strikes", {})
	for base_id in strikes:
		if base_id.begins_with("_"):
			continue
		var who: String = "결행 " + base_id
		if not base_id in BASE_IDS:
			errs.append("%s: 거점 id가 아닙니다." % who)
		var s: Dictionary = strikes[base_id]
		if str(s.get("name", "")).strip_edges() == "":
			errs.append("%s: name이 비었습니다." % who)
		if s.has("base") and not s["base"] in BASE_IDS:
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
	for id in BASE_IDS:
		var entry: Dictionary = strikes.get(id, {})
		for key in ["name", "ending"]:
			if str(entry.get(key, "")).strip_edges() == "":
				errs.append("엔딩 %s: %s이 비었습니다." % [id, key])
	for id in ["victory", "fail_final", "operation", "history", "traitor_won"]:
		var entry: Dictionary = endings.get(id, {})
		var keys := ["text"] if id == "traitor_won" else ["name"] if id == "victory" else ["name", "text"]
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
		if op == "police_dispatch" and e.has("from"):
			if not e["from"] in ["random_base", "strike_base"] and not e["from"] in BASE_IDS:
				errs.append("%s: police_dispatch의 알 수 없는 from '%s'" % [who, e["from"]])
		if op == "intel" and e.has("base"):
			if not e["base"] in ["nearest", "choose", "entered"] and not e["base"] in BASE_IDS:
				errs.append("%s: intel의 알 수 없는 base '%s'" % [who, e["base"]])
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
			if cond.has(k) and not cond[k] in BASE_IDS:
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
	if known == KNOWN_SCENE_CONDITIONS and cond.has("base") and not cond["base"] in BASE_IDS and cond["base"] != "card":
		errs.append("%s: 조건의 base '%s'는 거점 id가 아닙니다." % [who, cond["base"]])
	if kind == "any_of" or kind == "all_of":
		for o in cond.get("options", []):
			_check_cond(errs, who, o, known)


func _where_ok(w) -> bool:
	return w in KNOWN_WHERE or w in BASE_IDS


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
