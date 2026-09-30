extends SceneTree
## 경로 미리보기(path_to) 검증: 계산한 경로를 실제로 한 칸씩 걸을 수 있는가.
## 실행: godot --headless --path game --script res://tests/path_test.gd -- [판수]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 100
	var data := GameData.load_default()
	var checked := 0
	var walked := 0
	var failures := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in games:
		var g := GameRules.new()
		g.setup([{"faction": "kb"}, {"faction": "uy"}, {"faction": "ub"}, {"faction": "kb"}], 900000 + i, data)
		var guard := 0
		while g.phase != "over" and guard < 20000:
			guard += 1
			var p := g.cur()
			# 이동 단계마다 1/3 확률로: 무작위 목적지까지 경로를 계산해 그대로 걸어 본다
			if g.phase == "move" and rng.randf() < 0.33:
				var goal := Vector2i(rng.randi_range(0, g.data.size - 1), rng.randi_range(0, g.data.size - 1))
				var r := g.path_to(p, goal)
				if r["reachable"]:
					checked += 1
					var path: Array = r["path"]
					if not g.can_step(p, path[0]):
						failures += 1
						push_error("첫 걸음 불가: %s → %s (판 %d)" % [p["pos"], path, i])
					for c in path:
						if g.phase != "move" or g.current != p["id"]:
							break  # 검문소 공개·미션·선택지 등으로 이동이 끝남 (정상)
						if not g.can_step(p, c):
							failures += 1
							push_error("경로 중간 불가: %s at %s (판 %d)" % [path, c, i])
							break
						g.apply({"type": "step", "to": c})
					if g.phase == "move" and g.current == p["id"] and p["pos"] == goal:
						walked += 1
					continue
			if not g.apply(GameAI.decide(g)):
				failures += 1
				push_error("AI 액션 거부 (판 %d)" % i)
				break
	print("경로 검증 %d건, 목적지 도착 %d건, 실패 %d건" % [checked, walked, failures])
	quit(1 if failures > 0 else 0)
