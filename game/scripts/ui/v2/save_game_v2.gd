class_name SaveGameV2
extends RefCounted
## v2 이어하기용 자동 저장. 매일 아침(사람이 「하루 시작」을 기다릴 때)과 「저장하고 메인 메뉴로」에서 저장한다.
##
## 저장에는 게임 버전(project.godot의 application/config/version)을 함께 적는다. 버전이 다른 저장은
## 카드 · 규칙이 바뀌었을 수 있어 이어 하지 않는다 (예: 2.2.0에서 위협 카드 fund_freeze가 빠짐).
## 쓰기는 임시 파일에 먼저 쓰고 이름을 바꾼다. 쓰다가 끊겨도 원래 저장이 깨지지 않는다.

static var path := "user://save_v2.dat"   # 시험은 다른 파일로 돌린다

static var disabled := false   # 캡처 도구·시험에서 실제 저장을 건드리지 않게


static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


static func _file_exists() -> bool:
	return FileAccess.file_exists(path)


static func exists() -> bool:
	## 이어 할 수 있는 저장이 있는가 (버전이 다르거나 깨진 저장은 없는 것으로 친다)
	var d := _raw()
	return not d.is_empty() and str(d.get("app", "")) == app_version()


static func drop_stale() -> String:
	## 버전이 다른 저장이 있으면 지우고 그 버전을 돌려준다 (버전을 적기 전의 저장은 「이전 버전」). 없으면 ""
	var d := _raw()
	if d.is_empty() or str(d.get("app", "")) == app_version():
		return ""
	erase()
	var v := str(d.get("app", ""))
	return v if v != "" else "이전 버전"


static func write(game: RulesV2, meta: Dictionary) -> void:
	if disabled:
		return
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("저장 실패: %s" % FileAccess.get_open_error())
		return
	f.store_var({"app": app_version(), "meta": meta, "state": game.save_state()})
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("저장 실패: 이름 바꾸기 %d" % err)


static func _raw() -> Dictionary:
	if not _file_exists():
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or not d.has("state") or typeof(d["state"]) != TYPE_DICTIONARY:
		return {}
	return d


static func read() -> Dictionary:
	## {"game": RulesV2, "meta": Dictionary}. 없거나 깨졌거나 버전이 다르면 빈 사전 (그런 저장은 지운다)
	var d := _raw()
	if d.is_empty() or str(d.get("app", "")) != app_version():
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
	if _file_exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
