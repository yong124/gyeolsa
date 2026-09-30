extends SceneTree
## 데이터 검증: data/*.json의 오타·누락·알 수 없는 효과 이름을 찾는다.
## 실행: godot --headless --path game --script res://tests/data_test.gd


func _init() -> void:
	var data := GameData.load_default()
	var errs := data.validate()
	for e in errs:
		print("오류: ", e)
	print("데이터 검증: %s (아이템 %d종, 이벤트 %d종, 세력 %d개)" % [
		"통과" if errs.is_empty() else "%d건 오류" % errs.size(),
		data.cards["items"].size(), data.cards["events"].size(), data.faction_keys().size()])
	quit(1 if not errs.is_empty() else 0)
