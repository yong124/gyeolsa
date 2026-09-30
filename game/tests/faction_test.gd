extends SceneTree
## 세력 밸런스: 4인을 모두 같은 세력으로 편성해 대성공 엔딩 확률을 비교한다.
## 실행: godot --headless --path game --script res://tests/faction_test.gd -- [판수]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 600
	var data := GameData.load_default()
	for f in data.faction_keys():
		var good := 0
		for i in games:
			var g := GameRules.new()
			g.setup([{"faction": f}, {"faction": f}, {"faction": f}, {"faction": f}], 700000 + i, data)
			while g.phase != "over":
				g.apply(GameAI.decide(g))
			if g.ending["id"] == "victory":
				good += 1
		print("%s x4  대성공 %.1f%%" % [data.faction(f)["name"], 100.0 * good / games])
	quit()
