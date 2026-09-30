class_name SaveGame
extends RefCounted
## 이어하기용 자동 저장. 매일 아침(날짜 전환)과 메인 메뉴로 나갈 때 저장한다.

const PATH := "user://save.dat"

static var disabled := false   # 캡처 도구 등에서 실제 저장을 건드리지 않게


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func write(game: GameRules, meta: Dictionary) -> void:
	if disabled:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("저장 실패: %s" % FileAccess.get_open_error())
		return
	f.store_var({"meta": meta, "state": game.save_state()})


static func read(data: GameData) -> Dictionary:
	## {"game": GameRules, "meta": Dictionary}. 없거나 깨졌으면 빈 사전
	if not exists():
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or not d.has("state"):
		return {}
	var g := GameRules.new()
	g.load_state(d["state"], data)
	return {"game": g, "meta": d.get("meta", {})}


static func summary() -> String:
	## 메뉴에 보여 줄 한 줄 요약
	if not exists():
		return ""
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or not d.has("state"):
		return ""
	var st: Dictionary = d["state"]
	return "%d인 작전 · 광복 %d/%d · 남은 %d일" % [st["players"].size(), st["score"], st["goal"], st["rounds_left"]]


static func erase() -> void:
	if disabled:
		return
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
