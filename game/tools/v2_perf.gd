extends SceneTree
## Z5 성능 측정 (엔진 · AI · 서버): AI 4명 판을 같은 시드로 돌리며 한 수마다 잰다.
## - legal_actions(): 화면이 갱신마다 부르는 합법 액션 목록
## - GameAIV2.decide(): AI 한 수
## - apply(): 엔진이 액션 하나를 처리
## - NetViewV2.view_for(): 서버가 한 사람에게 보낼 보기를 만드는 시간과 그 크기(바이트, var_to_bytes)
## 실행: godot --headless --path game --script res://tools/v2_perf.gd -- games=5 seed=100

var _t := {}   # 이름 -> 잰 값(마이크로초 또는 바이트) 목록


func _init() -> void:
	var games := 5
	var seed := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("games="):
			games = int(a.substr(6))
		elif a.begins_with("seed="):
			seed = int(a.substr(5))
	var data := GameDataV2.load_default()
	var ids := ["yun", "jeong", "gaeddong", "oh"]
	var steps := 0
	var t_all := Time.get_ticks_usec()
	for gi in games:
		var g := RulesV2.new()
		var defs := []
		for id in ids:
			defs.append({"name": str(data.character(id)["name"]), "character": id})
		g.setup(defs, seed + gi, data)
		var guard := 0
		var log_sent := g.log_lines.size()   # 시작 보기는 기록 전부
		while g.phase != "over" and guard < 5000:
			guard += 1
			var act := "act%d" % g.act
			var t0 := Time.get_ticks_usec()
			var legal := g.legal_actions()
			_add("legal_actions " + act, Time.get_ticks_usec() - t0)
			_add("legal 개수 " + act, legal.size())
			var pid := GameAIV2.next_actor(g)
			t0 = Time.get_ticks_usec()
			var a := GameAIV2.decide(g, pid)
			_add("AI decide " + act, Time.get_ticks_usec() - t0)
			# 서버는 수마다 사람 자리에 보기를 보낸다. 0번 자리 몫을 잰다 (Z5 전: 통째 · 압축 없음, 후: 새 기록 줄만 · zstd)
			t0 = Time.get_ticks_usec()
			var full := NetViewV2.view_for(g, 0)
			_add("view_for " + act, Time.get_ticks_usec() - t0)
			_add("보낸 바이트 전 " + act, var_to_bytes({"t": "update", "view": full}).size())
			t0 = Time.get_ticks_usec()
			var pkt := NetServerV2.pack({"t": "update", "view": NetViewV2.view_for(g, 0, log_sent)})
			_add("view+압축 후 " + act, Time.get_ticks_usec() - t0)
			_add("보낸 바이트 후 " + act, pkt.size())
			log_sent = g.log_lines.size()
			t0 = Time.get_ticks_usec()
			if not g.apply(a):
				break
			_add("apply " + act, Time.get_ticks_usec() - t0)
			g.events.clear()
			steps += 1
	var total_ms := (Time.get_ticks_usec() - t_all) / 1000.0
	print("v2 성능: %d판 · 수 %d개 · 전체 %.0fms" % [games, steps, total_ms])
	var keys := _t.keys()
	keys.sort()
	for k in keys:
		var arr: Array = _t[k]
		arr.sort()
		var sum := 0.0
		for x in arr:
			sum += float(x)
		var unit := "B" if "바이트" in k else ("개" if "개수" in k else "µs")
		print("  %-26s 평균 %8.0f%s · 95%% %8.0f · 최대 %8.0f · n=%d" % [k, sum / arr.size(), unit, float(arr[int(arr.size() * 0.95)]), float(arr[-1]), arr.size()])
	quit()


func _add(k: String, v: float) -> void:
	if not _t.has(k):
		_t[k] = []
	_t[k].append(v)
