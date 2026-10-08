extends SceneTree
## 온라인 시험 (헤드리스, localhost): 서버 1 + 사람 클라이언트 N(각자 자기 보기만 보고 AI로 둠) + 나머지는 서버 AI.
## 확인: 판이 끝까지 가는가 · 받은 모든 보기에 남의 비밀(사연 · 덱 순서)이 없는가 · 남의 자리 행동은 거절되는가 · 끊겼다 돌아오면 자리를 돌려받는가
## 실행: godot --headless --path game --script res://tests/v2_net_test.gd -- [humans=2] [port=8931]

var failed := 0
var passed := 0
var server: NetServerV2
var clients: Array = []
var views := {}        # 클라이언트 번호 -> 마지막 보기의 RulesV2
var seats := {}
var waiting := {}      # 클라이언트 번호 -> 보낸 행동의 답을 기다리는 중
var leaks := 0
var rejected := 0
var updates := 0


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)


func _initialize() -> void:
	_run()


func _run() -> void:
	var humans := 2
	var port := 8931
	for a in OS.get_cmdline_user_args():
		if a.begins_with("humans="):
			humans = int(a.substr(7))
		elif a.begins_with("port="):
			port = int(a.substr(5))
	server = NetServerV2.new()
	server.port = port
	server.quiet = true
	server.ai_step = 0.0
	root.add_child(server)
	await process_frame
	for i in humans:
		var c := NetClientV2.new()
		root.add_child(c)
		clients.append(c)
		var ci := i
		c.room_changed.connect(func(r): _on_room(ci, r))
		c.game_started.connect(func(seat, view, _names): _on_view(ci, seat, view, []))
		c.game_updated.connect(func(view, ev, _info): _on_view(ci, seats.get(ci, -1), view, ev))
		c.server_error.connect(func(msg):
			if msg.contains("내 요원의 행동만"):
				rejected += 1
			waiting[ci] = false)
		c.open("ws://127.0.0.1:%d" % port, "사람%d" % (i + 1))
	# 방장이 방을 만들고, 나머지가 들어온다
	await _until(func(): return clients[0].token != "")
	clients[0].send({"t": "create"})
	await _until(func(): return clients[0].room.has("code"))
	var code: String = clients[0].room["code"]
	ok(code.length() == 5, "방 코드 5자 (%s)" % code)
	for i in range(1, humans):
		await _until(func(): return clients[i].token != "")
		clients[i].send({"t": "join", "code": code})
	await _until(func(): return clients.all(func(c): return c.seat >= 0))
	# 요원 고르기 (받은 두 장 중 첫 장)
	for c in clients:
		var mine: Dictionary = c.room["seats"][c.seat]
		c.send({"t": "pick", "character": mine["offer"][0]})
	await _until(func(): return clients[0].room["seats"].filter(func(s): return s["human"] and s["character"] != "").size() == humans)
	clients[0].send({"t": "start"})
	await _until(func(): return views.size() == humans)
	ok(true, "시작: 사람 %d명 + AI %d명" % [humans, 4 - humans])
	# 남의 자리 행동은 거절되어야 한다
	var other: int = (int(seats[0]) + 1) % 4
	clients[0].act({"type": "end_turn", "player": other})
	# 판을 끝까지
	var guard := 0
	var dropped := false
	while guard < 60000:
		guard += 1
		await process_frame
		var g: RulesV2 = server._rooms[code]["game"]
		if g.phase == "over":
			break
		# 중간에 한 번: 1번 클라이언트를 끊었다가 같은 토큰으로 다시 붙인다
		if humans > 1 and not dropped and g.day >= 3:
			dropped = true
			var tok: String = clients[1].token
			clients[1]._ws.close()
			for k in 30:
				await process_frame
			clients[1].open("ws://127.0.0.1:%d" % port, "사람2", tok)
			await _until(func(): return clients[1].seat >= 0 and views.has(1))
			ok(clients[1].seat == seats[1], "끊겼다 돌아오면 같은 자리 (%d)" % clients[1].seat)
		for i in clients.size():
			_maybe_act(i)
	var g2: RulesV2 = server._rooms[code]["game"]
	ok(g2.phase == "over", "판이 끝까지 감 (엔딩 %s · %d일째 · 행동 %d)" % [g2.ending.get("id", "-"), g2.day, g2.actions.size()])
	ok(leaks == 0, "받은 보기 %d번에 남의 비밀 없음 (누출 %d)" % [updates, leaks])
	ok(rejected >= 1, "남의 자리 행동은 거절됨")
	await _security(port, code)
	print("v2 온라인 시험: 통과 %d, 실패 %d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _security(port: int, code: String) -> void:
	## 보안 (지시서 Z1): 지어낸 토큰 · 인사 없는 요청 · 메시지 폭탄 · 방 코드 맞히기 · 이름 서식
	# 1. 지어낸 토큰은 받아 주지 않고 서버가 새 토큰을 준다
	var fake := NetClientV2.new()
	root.add_child(fake)
	var welcomed := [false]
	fake.connected.connect(func(): welcomed[0] = true)
	fake.open("ws://127.0.0.1:%d" % port, "가짜", "deadbeefdeadbeef")
	await _until(func(): return welcomed[0])   # 서버의 welcome(토큰)을 받은 뒤에 본다
	ok(fake.token != "deadbeefdeadbeef" and fake.token.length() == 32, "지어낸 토큰은 거절, 서버가 128비트 토큰을 새로 줌")
	ok(fake.seat < 0, "지어낸 토큰으로는 자리를 얻지 못함")
	# 2. 인사 없이 방 만들기는 안 됨
	var rooms_before: int = server._rooms.size()
	var raw := WebSocketPeer.new()
	raw.connect_to_url("ws://127.0.0.1:%d" % port)
	await _until(func():
		raw.poll()
		return raw.get_ready_state() == WebSocketPeer.STATE_OPEN)
	raw.send(var_to_bytes({"t": "create"}))
	for k in 20:
		raw.poll()
		await process_frame
	ok(server._rooms.size() == rooms_before, "인사(hello) 없이는 방을 만들 수 없음")
	# 3. 메시지 폭탄을 보내면 끊긴다
	for k in server.msg_per_sec + 20:
		raw.send(var_to_bytes({"t": "ready", "on": true}))
	var closed := false
	for k in 300:
		raw.poll()
		if raw.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			closed = true
			break
		await process_frame
	ok(closed, "메시지 폭탄을 보낸 연결은 끊김")
	# 4. 방 코드를 계속 틀리면 끊긴다
	var guess := NetClientV2.new()
	root.add_child(guess)
	var guess_closed := [false]
	guess.closed.connect(func(): guess_closed[0] = true)
	guess.open("ws://127.0.0.1:%d" % port, "찍기")
	await _until(func(): return guess.token != "")
	for k in server.bad_code_limit:
		guess.send({"t": "join", "code": "ZZZZ%d" % k})
	await _until(func(): return guess_closed[0], 600)
	ok(guess_closed[0], "없는 방 코드를 %d번 틀리면 끊김" % server.bad_code_limit)
	# 5. 이름의 서식 문자 · 제어 문자는 걸러진다
	var cleaned := NetServerV2.clean_name("[color=red]악당[/color]
<b>")
	ok(not cleaned.contains("[") and not cleaned.contains("]") and not cleaned.contains("<") and not cleaned.contains("
") and cleaned.length() <= 12, "이름의 서식 · 제어 문자 걸러짐 (%s)" % cleaned)


func _until(cond: Callable, limit := 3000) -> void:
	for i in limit:
		if cond.call():
			return
		await process_frame
	failed += 1
	print("FAIL 기다리다 시간 초과")


func _on_room(_ci: int, _r: Dictionary) -> void:
	pass


func _on_view(ci: int, seat: int, view: Dictionary, _ev: Array) -> void:
	seats[ci] = seat
	var g := RulesV2.new()
	g.load_state(view)
	views[ci] = g
	waiting[ci] = false
	updates += 1
	var real: RulesV2 = server._rooms[clients[ci].room.get("code", "")]["game"] if clients[ci].room.has("code") else null
	if real != null:
		var l := NetViewV2.leaks(view, real, seat)
		if not l.is_empty():
			leaks += 1
			print("누출: ", l)


func _maybe_act(ci: int) -> void:
	## 클라이언트가 자기 보기만 보고 둔다 (보낸 뒤에는 답이 올 때까지 기다림)
	if waiting.get(ci, false) or not views.has(ci):
		return
	var g: RulesV2 = views[ci]
	var seat: int = seats[ci]
	var me: Dictionary = g.players[seat]
	var a := {}
	match g.phase:
		"plan":
			a = {"type": "start_day", "player": seat}
		"day":
			if g.can_begin_turn(me):
				a = {"type": "begin_turn", "player": seat}
		"turn":
			if g.current == seat:
				a = GameAIV2.decide(g, seat)
		"choice":
			if int(g.pending.get("player", -1)) == seat:
				a = GameAIV2.decide(g, seat)
	if a.is_empty():
		return
	if a["type"] == "start_day" and g.phase == "plan" and server._rooms.values()[0]["day_ready"].has(seat):
		return
	waiting[ci] = true
	clients[ci].act(a)
