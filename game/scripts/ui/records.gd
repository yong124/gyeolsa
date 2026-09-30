class_name Records
extends RefCounted
## 작전 기록과 도전 과제 (user://records.json). 판이 끝날 때 record()로 갱신한다.
## 도전 과제의 조건은 data/achievements.json에 있다.

const PATH := "user://records.json"

static var disabled := false     # 캡처 도구·자동 진행에서는 기록하지 않는다
static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		_data = {"games": 0, "endings": {}, "factions": {}, "best_days_left": -1, "best_score": 0,
			"scenarios_won": {}, "daily": {}, "unlocked": {}, "tutorial_done": false}
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data.merge(parsed, true)
	return _data


static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data(), "\t"))


static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func daily_seed(date: String) -> int:
	return int(date.replace("-", ""))


static func record(game: GameRules, meta: Dictionary) -> Array:
	## 한 판의 결과를 기록하고, 이번에 새로 달성한 도전 과제 목록을 돌려준다.
	if disabled:
		return []
	var d := data()
	var cfg: Dictionary = meta.get("cfg", {})
	var me: Dictionary = game.players[0]
	var won: bool = game.ending.get("id", "") == "victory"
	if meta.get("tutorial", false):
		d["tutorial_done"] = true
	else:
		d["games"] = int(d["games"]) + 1
		var e: String = game.ending.get("id", "")
		d["endings"][e] = int(d["endings"].get(e, 0)) + 1
		var fs: Dictionary = d["factions"].get(me["faction"], {"games": 0, "wins": 0})
		fs["games"] = int(fs["games"]) + 1
		if won:
			fs["wins"] = int(fs["wins"]) + 1
			d["best_days_left"] = maxi(int(d["best_days_left"]), game.rounds_left)
		d["factions"][me["faction"]] = fs
		d["best_score"] = maxi(int(d["best_score"]), int(me["stats"]["points"]))
		var sc: String = cfg.get("scenario", "")
		if won and sc != "" and sc != "daily":
			d["scenarios_won"][sc] = true
		if sc == "daily":
			var date: String = cfg.get("date", today())
			d["daily"][date] = maxi(int(d["daily"].get(date, -1)), game.score)
	var fresh := []
	for a in game.data.achievements.get("list", []):
		if d["unlocked"].has(a["id"]):
			continue
		if _met(a.get("when", {}), game, meta, d):
			d["unlocked"][a["id"]] = today()
			fresh.append(a)
	_save()
	return fresh


static func _met(when: Dictionary, game: GameRules, meta: Dictionary, d: Dictionary) -> bool:
	var cfg: Dictionary = meta.get("cfg", {})
	var st: Dictionary = game.players[0]["stats"]
	var tutorial: bool = meta.get("tutorial", false)
	for k in when:
		var v = when[k]
		var ok := true
		match k:
			"tutorial": ok = tutorial == bool(v)
			"ending": ok = not tutorial and game.ending.get("id", "") == v
			"my_jailed_max": ok = int(st["jailed"]) <= int(v)
			"days_left_min": ok = game.rounds_left >= int(v)
			"my_rescues_min": ok = not tutorial and int(st["rescues"]) >= int(v)
			"my_points_min": ok = not tutorial and int(st["points"]) >= int(v)
			"players_min": ok = game.players.size() >= int(v)
			"difficulty": ok = int(cfg.get("difficulty", 0)) == int(v) and cfg.get("scenario", "") == ""
			"scenario": ok = cfg.get("scenario", "") == v
			"factions_won":
				var n := 0
				for f in d["factions"]:
					if int(d["factions"][f].get("wins", 0)) > 0:
						n += 1
				ok = n >= int(v)
			"scenarios_won": ok = d["scenarios_won"].size() >= int(v)
			"games_min": ok = int(d["games"]) >= int(v)
		if not ok:
			return false
	return true
