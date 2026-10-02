extends SceneTree
## v2 데이터 검증: data/v2/*.json의 오타·누락·장수를 확인하고 카드 종류별 장수와 _todo를 출력한다.
## 실행: godot --headless --path game --script res://tests/v2_data_test.gd


func _init() -> void:
	var data := GameDataV2.load_default()
	var errs := data.validate()
	for e in errs:
		print("오류: ", e)
	print("--- 카드 장수 ---")
	print("위협 1막 %d장 / 2막 %d장" % [data.threat_deck(1).size(), data.threat_deck(2).size()])
	print("미션 %d장" % data.missions.get("missions", []).size())
	print("이벤트 %d종 %d장" % [data.events.get("events", []).size(), _sum(data.events.get("events", []))])
	print("아이템 %d종 %d장" % [data.items.get("items", []).size(), _sum(data.items.get("items", []))])
	var s: Dictionary = data.scenes.get("strikes", {})
	print("결행 %d곳, 경비 강화 %d장" % [s.size(), data.scenes.get("reinforce", []).size()])
	print("엔딩 %d종, 결행별 성공 문장 %d개" % [4, data.endings.get("strikes", {}).size()])
	for id in GameDataV2.BASE_IDS:
		if not data.endings.get("strikes", {}).has(id):
			errs.append("엔딩에 결행 거점 %s가 없습니다." % id)
	print("사연 %d장" % data.sagas.get("sagas", []).size())
	print("캐릭터 %d명" % data.characters.get("characters", []).size())
	var todos := data.todos()
	print("--- _todo 경고 %d건 ---" % todos.size())
	for t in todos:
		print("경고: ", t)
	print("v2 데이터 검증: %s" % ("통과" if errs.is_empty() else "%d건 오류" % errs.size()))
	quit(1 if not errs.is_empty() else 0)


func _sum(cards: Array) -> int:
	var n := 0
	for c in cards:
		n += int(c.get("count", 1))
	return n
