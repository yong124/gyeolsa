class_name PlaytestLog
extends RefCounted
## 플레이테스트 기록 (user://playtests/*.json). 한 판의 설정·시드·액션 전부·매일 아침 상태·사람의 생각 시간·설문을 남긴다.
## 기록 사전은 meta["playtest"]에 들어 있어서 저장·이어하기를 해도 이어진다.
## 요약: godot --headless --path game --script res://tools/playtest_report.gd [-- 폴더]

static var dir := "user://playtests"   # 캡처 도구는 다른 폴더로 돌린다
const VERSION := "v1.3"

static var disabled := false   # 캡처 도구·자동 진행에서는 남기지 않는다

## 판 끝 설문 (SurveyScreen이 묻고, playtest_report가 모은다)
const SCALES := [
	["fun", "재미있었나요?"],
	["clarity", "규칙이 이해됐나요?"],
	["agency", "내 선택이 결과를 바꿨다고 느꼈나요? (운이 아니라)"],
	["tension", "경찰에 쫓기는 긴장감이 있었나요?"],
	["launch", "결행 시점을 고르는 게 의미 있는 고민이었나요?"],
	["again", "또 하고 싶나요?"],
]
const LENGTH := ["너무 짧다", "적당하다", "너무 길다"]
## 규칙 목록 (헷갈린 규칙 · 빼도 될 규칙에 같이 쓴다)
const RULES := [
	["path", "길 깔기·이동"], ["mission", "미션"], ["dice", "주사위 판정"], ["police", "경찰·검문소"],
	["jail", "감옥·탈옥·구출"], ["items", "아이템"], ["events", "이벤트 카드"], ["occupation", "일제 동향"],
	["ability", "세력 능력"], ["give", "건네기"], ["decoy", "미끼"],
	["exposure", "노출·경계"], ["intel", "첩보"], ["vote", "결행 투표"], ["strike", "결행 목표"], ["traitor", "변절"],
]


static func begin(game: GameRules, cfg: Dictionary) -> Dictionary:
	## 새 판의 기록을 시작한다. 이 사전을 meta["playtest"]에 넣어 둔다.
	var now := Time.get_datetime_dict_from_system()
	var players := []
	for p in game.players:
		players.append({"name": p["name"], "faction": p["faction"], "ai": p["ai"], "personality": p["personality"]})
	return {
		"version": VERSION,
		"file": "%04d%02d%02d_%02d%02d%02d.json" % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]],
		"started": Time.get_datetime_string_from_system(false, true),
		"cfg": _plain(cfg),
		"seed": game.rng.seed,
		"scenario": game.scenario.duplicate(true),
		"two_act": game.two_act(),
		"players": players,
		"rounds_total": game.rounds_total,
		"goal": game.goal,
		"days": [],
		"turns": [],
		"play_seconds": 0.0,
		"sessions": 1,
		"survey": [],
	}


static func day(log: Dictionary, game: GameRules) -> void:
	## 아침마다 판 상태를 한 줄 남긴다
	var jailed := []
	for p in game.players:
		if p["jailed"]:
			jailed.append(p["id"])
	log["days"].append({
		"date": game.date_label(), "days_left": game.rounds_left, "act": game.act,
		"score": game.score, "exposure": game.exposure, "alert": game.alert_level(),
		"intel": game.intel.duplicate(), "police": game.police.size(), "jailed": jailed,
		"strike_progress": int(game.strike.get("progress", 0)),
	})


static func turn(log: Dictionary, game: GameRules, pid: int, seconds: float, undos: int) -> void:
	## 사람이 한 차례에 쓴 시간 (연출 재생 시간은 빼고, 조작할 수 있던 시간만)
	log["turns"].append({"player": pid, "days_left": game.rounds_left, "act": game.act,
		"seconds": snappedf(seconds, 0.1), "undos": undos})
	log["play_seconds"] = float(log["play_seconds"]) + seconds


static func finish(log: Dictionary, game: GameRules, reason := "") -> void:
	## 판이 끝났을 때 (또는 중간에 그만뒀을 때) 결과를 채우고 파일로 쓴다
	log["ended"] = Time.get_datetime_string_from_system(false, true)
	log["ending"] = {"id": game.ending.get("id", reason), "name": game.ending.get("name", ""),
		"reason": game.ending.get("reason", reason), "strike": game.strike.get("id", ""),
		"traitor": int(game.ending.get("traitor", -1)), "traitor_won": game.ending.get("traitor_won", false)}
	log["final"] = {"score": game.score, "days_left": game.rounds_left, "act": game.act, "exposure": game.exposure,
		"strike": game.strike.duplicate(true)}
	log["launch"] = game.launch_info.duplicate(true)
	var stats := []
	for p in game.players:
		stats.append(p["stats"].duplicate())
	log["stats"] = stats
	log["actions"] = game.actions.duplicate(true)
	write(log)


static func add_survey(log: Dictionary, answers: Dictionary) -> void:
	log["survey"].append(answers)
	write(log)


static func write(log: Dictionary) -> void:
	if disabled or log.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open("%s/%s" % [dir, log["file"]], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_plain(log), "\t"))


static func folder() -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	return ProjectSettings.globalize_path(dir)


static func _plain(v):
	## Vector2i 등을 JSON에 쓸 수 있는 값으로 바꾼다
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _plain(v[k])
			return d
		TYPE_ARRAY:
			return v.map(func(x): return _plain(x))
		TYPE_VECTOR2I:
			return [v.x, v.y]
	return v
