extends SceneTree
## 저장·불러오기 검증: 게임 도중 저장한 상태를 불러와 같은 AI로 이어 가면 원본과 결과가 똑같아야 한다.
## 실행: godot --headless --path game --script res://tests/save_test.gd -- [판수]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 50
	var data := GameData.load_default()
	var failures := 0
	for i in games:
		var a := GameRules.new()
		a.setup([{"faction": "kb"}, {"faction": "uy"}, {"faction": "ub"}, {"faction": "kb"}], 500000 + i, data)
		# 무작위 지점까지 진행 후 저장 (파일에 썼다 읽어 직렬화까지 검증)
		var cut := 30 + (i * 37) % 200
		for k in cut:
			if a.phase == "over":
				break
			a.apply(GameAI.decide(a))
		var f := FileAccess.open("user://save_test.dat", FileAccess.WRITE)
		f.store_var(a.save_state())
		f.close()
		f = FileAccess.open("user://save_test.dat", FileAccess.READ)
		var st: Dictionary = f.get_var()
		f.close()
		var b := GameRules.new()
		b.load_state(st, data)
		while a.phase != "over":
			var act := GameAI.decide(a)
			var act_b := GameAI.decide(b)
			if str(act) != str(act_b):
				failures += 1
				push_error("판 %d: 불러온 게임의 AI 판단이 다름 %s vs %s" % [i, act, act_b])
				break
			a.apply(act)
			b.apply(act_b)
		if a.score != b.score or a.log_lines.size() != b.log_lines.size() or a.date_label() != b.date_label():
			failures += 1
			push_error("판 %d: 결과 다름 (광복 %d/%d, 로그 %d/%d)" % [i, a.score, b.score, a.log_lines.size(), b.log_lines.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_test.dat"))
	print("저장·불러오기 검증 %d판, 실패 %d건" % [games, failures])
	quit(1 if failures > 0 else 0)
