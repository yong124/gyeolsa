class_name SaveGameV2
extends RefCounted
## v2 이어하기용 자동 저장. 매일 아침(사람이 「하루 시작」을 기다릴 때)과 「저장하고 메인 메뉴로」에서 저장한다.

static var path := "user://save_v2.dat"   # 시험은 다른 파일로 돌린다

static var disabled := false   # 캡처 도구·시험에서 실제 저장을 건드리지 않게


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func write(game: RulesV2, meta: Dictionary) -> void:
	if disabled:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("저장 실패: %s" % FileAccess.get_open_error())
		return
	f.store_var({"meta": meta, "state": game.save_state()})


static func _raw() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or not d.has("state") or typeof(d["state"]) != TYPE_DICTIONARY:
		return {}
	return d


static func read() -> Dictionary:
	## {"game": RulesV2, "meta": Dictionary}. 없거나 깨졌으면 빈 사전 (깨진 저장은 지운다)
	var d := _raw()
	if d.is_empty():
		erase()
		return {}
	var g := RulesV2.new()
	g.load_state(d["state"])
	if g.players.is_empty():
		erase()
		return {}
	return {"game": g, "meta": d.get("meta", {})}


static func summary() -> String:
	## 메뉴에 보여 줄 한 줄 요약
	var d := _raw()
	if d.is_empty():
		return ""
	var st: Dictionary = d["state"]
	var players: Array = st.get("players", [])
	var who := ""
	if not players.is_empty():
		who = str(GameDataV2.load_default().character(str(players[0].get("character", ""))).get("name", ""))
	var stage := "결행 전 · 결행 준비 %d" % int(st.get("ready", 0)) if int(st.get("act", 1)) == 1 \
		else "결행 중 · 장면 %d / %d" % [int(st.get("scene_index", 0)) + 1, (st.get("scenes", []) as Array).size()]
	var s := "%d일째 · %s · 남은 %d일" % [int(st.get("day", 1)), stage, int(st.get("rounds_left", 0))]
	return s if who == "" else "%s · %s" % [who, s]


static func erase() -> void:
	if disabled:
		return
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
