class_name NetServerV2
extends Node
## 온라인 서버 (헤드리스): 방을 만들고, 판을 서버에서 돌리고, 사람마다 볼 수 있는 것만 보낸다.
## 실행: Godot --headless --path game -- server [port=8910]
## 규약: v2_구현/온라인_규약.md. 메시지는 Dictionary를 var_to_bytes로 묶은 WebSocket 바이너리 패킷.
## 요원은 늘 4명이다. 빈자리 · 끊긴 자리는 서버의 AI(GameAIV2)가 둔다.

const VERSION := 1
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # 헷갈리는 0 O 1 I 뺌
const AI_STEP := 0.45          # AI 한 수 사이 간격(초): 사람이 따라 볼 수 있게
const HUMAN_IDLE := 150.0      # 사람 자리가 이만큼 아무것도 안 하면 AI가 한 수 대신 둔다
const DAY_WAIT := 60.0         # 아침: 다들 「하루 시작」을 누를 때까지 기다리는 최대 시간
const DROP_GRACE := 20.0       # 끊긴 자리를 AI가 맡기까지

var port := 8910
var _tcp := TCPServer.new()
var _peers := {}     # peer id -> {"ws": WebSocketPeer, "name", "token", "room", "seat"}
var _rooms := {}     # code -> 방 (아래 _new_room)
var _next_peer := 1
var _rng := RandomNumberGenerator.new()
var quiet := false   # 시험: 서버 로그 끄기
var ai_step := AI_STEP   # 시험에서는 0으로


func _ready() -> void:
	_rng.randomize()
	var err := _tcp.listen(port)
	_log("서버 시작 · 포트 %d · %s" % [port, "ok" if err == OK else "실패 %d" % err])


func _exit_tree() -> void:
	_tcp.stop()


func _log(s: String) -> void:
	if not quiet:
		print("[server] ", s)


# ------------------------------------------------------------------ 연결

func _process(delta: float) -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 22
		ws.accept_stream(_tcp.take_connection())
		_peers[_next_peer] = {"ws": ws, "name": "", "token": "", "room": "", "seat": -1}
		_next_peer += 1
	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var msg = bytes_to_var(ws.get_packet())
					if msg is Dictionary:
						_on_msg(id, msg)
			WebSocketPeer.STATE_CLOSED:
				_on_drop(id)
				_peers.erase(id)
	for code in _rooms.keys():
		_tick_room(_rooms[code], delta)


func _send(id: int, msg: Dictionary) -> void:
	if not _peers.has(id):
		return
	var ws: WebSocketPeer = _peers[id]["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(var_to_bytes(msg))


func _err(id: int, text: String) -> void:
	_send(id, {"t": "error", "msg": text})


# ------------------------------------------------------------------ 메시지

func _on_msg(id: int, m: Dictionary) -> void:
	var p: Dictionary = _peers[id]
	match str(m.get("t", "")):
		"hello":
			if int(m.get("ver", 0)) != VERSION:
				_err(id, "게임 버전이 서버와 다릅니다. 새로 받아 주세요.")
				return
			p["name"] = str(m.get("name", "요원")).strip_edges().left(12)
			if p["name"] == "":
				p["name"] = "요원"
			p["token"] = str(m.get("token", ""))
			if p["token"] == "":
				p["token"] = "%08x%08x" % [_rng.randi(), _rng.randi()]
			_send(id, {"t": "welcome", "token": p["token"], "ver": VERSION})
			_try_resume(id)
		"create":
			if p["room"] != "":
				return
			var code := _new_code()
			_rooms[code] = _new_room(code)
			_log("방 %s 만듦 (%s)" % [code, p["name"]])
			_join(id, code)
		"join":
			var code := str(m.get("code", "")).to_upper().strip_edges()
			if not _rooms.has(code):
				_err(id, "그런 방이 없습니다: " + code)
				return
			_join(id, code)
		"pick":
			_pick(id, str(m.get("character", "")))
		"ready":
			var r := _room_of(id)
			if r.is_empty() or r["game"] != null:
				return
			r["seats"][p["seat"]]["ready"] = bool(m.get("on", true))
			_send_room(r)
		"start":
			_start(id)
		"act":
			_act(id, m.get("a", {}))
		"leave":
			_leave(id)


func _room_of(id: int) -> Dictionary:
	var code: String = _peers.get(id, {}).get("room", "")
	return _rooms.get(code, {})


func _new_code() -> String:
	while true:
		var s := ""
		for i in 5:
			s += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not _rooms.has(s):
			return s
	return ""


func _new_room(code: String) -> Dictionary:
	var seats := []
	for i in 4:
		seats.append({"peer": -1, "name": "", "token": "", "human": false, "ready": false, "character": "", "offer": [],
			"dropped_at": -1.0, "idle": 0.0})
	return {"code": code, "host": -1, "seats": seats, "game": null, "ai_timer": 0.0, "day_ready": {}, "day_wait": 0.0,
		"closed_for": 0.0}


func _join(id: int, code: String) -> void:
	var r: Dictionary = _rooms[code]
	var p: Dictionary = _peers[id]
	if r["game"] != null:
		_err(id, "이미 시작한 방입니다. 끊긴 사람만 같은 이름으로 다시 들어올 수 있습니다.")
		return
	var seat := -1
	for i in 4:
		if not r["seats"][i]["human"]:
			seat = i
			break
	if seat < 0:
		_err(id, "방이 가득 찼습니다 (4명).")
		return
	var s: Dictionary = r["seats"][seat]
	s["peer"] = id
	s["name"] = p["name"]
	s["token"] = p["token"]
	s["human"] = true
	s["ready"] = false
	s["character"] = ""
	s["offer"] = _deal_offer(r)
	p["room"] = code
	p["seat"] = seat
	if r["host"] < 0:
		r["host"] = seat
	_send_room(r)


func _deal_offer(r: Dictionary) -> Array:
	## 요원 카드 2장: 다른 사람에게 이미 간 카드와 겹치지 않게
	var used := []
	for s in r["seats"]:
		used.append_array(s["offer"])
	var ids: Array = GameDataV2.load_default().characters.get("characters", []).map(func(c): return str(c["id"]))
	ids = ids.filter(func(x): return not x in used)
	var out := []
	while out.size() < 2 and not ids.is_empty():
		var k := _rng.randi_range(0, ids.size() - 1)
		out.append(ids[k])
		ids.remove_at(k)
	return out


func _pick(id: int, ch: String) -> void:
	var r := _room_of(id)
	if r.is_empty() or r["game"] != null:
		return
	var s: Dictionary = r["seats"][_peers[id]["seat"]]
	if ch in s["offer"]:
		s["character"] = ch
		_send_room(r)


func _send_room(r: Dictionary) -> void:
	for i in 4:
		var s: Dictionary = r["seats"][i]
		if not s["human"] or s["peer"] < 0:
			continue
		var seats := []
		for j in 4:
			var o: Dictionary = r["seats"][j]
			seats.append({"name": o["name"], "human": o["human"], "ready": o["ready"], "character": o["character"],
				"offer": o["offer"] if j == i else [], "online": o["peer"] >= 0})
		_send(s["peer"], {"t": "room", "code": r["code"], "host": r["host"], "you": i, "seats": seats})


func _leave(id: int) -> void:
	var r := _room_of(id)
	if r.is_empty():
		return
	var seat: int = _peers[id]["seat"]
	var s: Dictionary = r["seats"][seat]
	_peers[id]["room"] = ""
	_peers[id]["seat"] = -1
	if r["game"] == null:
		s["human"] = false
		s["peer"] = -1
		s["name"] = ""
		s["offer"] = []
		s["character"] = ""
		s["ready"] = false
		_pass_host(r)
		_send_room(r)
	else:
		s["peer"] = -1
		s["dropped_at"] = 0.0   # 판 중에 나가면 바로 AI가 맡는다
		s["human"] = false
		_pass_host(r)
		_broadcast(r, [])


func _pass_host(r: Dictionary) -> void:
	if r["host"] >= 0 and r["seats"][r["host"]]["human"]:
		return
	r["host"] = -1
	for i in 4:
		if r["seats"][i]["human"]:
			r["host"] = i
			return


func _on_drop(id: int) -> void:
	var r := _room_of(id)
	if r.is_empty():
		return
	var seat: int = _peers[id]["seat"]
	if r["game"] == null:
		_leave(id)
		return
	var s: Dictionary = r["seats"][seat]
	s["peer"] = -1
	s["dropped_at"] = Time.get_ticks_msec() / 1000.0
	_log("방 %s 자리 %d 끊김" % [r["code"], seat])


func _try_resume(id: int) -> void:
	## 끊겼던 사람이 같은 토큰으로 돌아오면 자리를 돌려준다
	var p: Dictionary = _peers[id]
	for code in _rooms:
		var r: Dictionary = _rooms[code]
		if r["game"] == null:
			continue
		for i in 4:
			var s: Dictionary = r["seats"][i]
			if s["token"] == p["token"] and s["peer"] < 0:
				s["peer"] = id
				s["human"] = true
				s["dropped_at"] = -1.0
				s["idle"] = 0.0
				p["room"] = code
				p["seat"] = i
				_log("방 %s 자리 %d 돌아옴" % [code, i])
				var g: RulesV2 = r["game"]
				_send(id, {"t": "start", "seat": i, "view": NetViewV2.view_for(g, i), "names": _names(r)})
				return


# ------------------------------------------------------------------ 판

func _start(id: int) -> void:
	var r := _room_of(id)
	if r.is_empty() or r["game"] != null:
		return
	if _peers[id]["seat"] != r["host"]:
		_err(id, "방장만 시작할 수 있습니다.")
		return
	for s in r["seats"]:
		if s["human"] and s["character"] == "":
			_err(id, "아직 요원을 고르지 않은 사람이 있습니다.")
			return
	var data := GameDataV2.load_default()
	var taken := []
	for s in r["seats"]:
		if s["character"] != "":
			taken.append(s["character"])
	var pool: Array = data.characters.get("characters", []).map(func(c): return str(c["id"])).filter(func(x): return not x in taken)
	var defs := []
	for i in 4:
		var s: Dictionary = r["seats"][i]
		if s["character"] == "":
			var k := _rng.randi_range(0, pool.size() - 1)
			s["character"] = pool[k]
			pool.remove_at(k)
			s["name"] = str(data.character(s["character"]).get("name", "AI"))
		defs.append({"name": s["name"], "character": s["character"]})
	var g := RulesV2.new()
	g.setup(defs, _rng.randi())
	g.human = r["host"]   # 결행 혜택은 방장이 고른다 (엔진 규칙: 사람 한 명)
	r["game"] = g
	g.events.clear()
	_log("방 %s 시작" % r["code"])
	for i in 4:
		var s: Dictionary = r["seats"][i]
		if s["human"] and s["peer"] >= 0:
			_send(s["peer"], {"t": "start", "seat": i, "view": NetViewV2.view_for(g, i), "names": _names(r)})


func _names(r: Dictionary) -> Array:
	var out := []
	for s in r["seats"]:
		out.append({"name": s["name"], "human": s["human"]})
	return out


func _is_ai(r: Dictionary, seat: int) -> bool:
	## 사람이 없거나, 끊긴 지 DROP_GRACE초가 지난 자리는 AI가 둔다
	var s: Dictionary = r["seats"][seat]
	if not s["human"]:
		return true
	if s["peer"] < 0 and s["dropped_at"] >= 0.0:
		return Time.get_ticks_msec() / 1000.0 - s["dropped_at"] >= DROP_GRACE
	return false


func _act(id: int, a) -> void:
	var r := _room_of(id)
	if r.is_empty() or r["game"] == null or not a is Dictionary:
		return
	var g: RulesV2 = r["game"]
	var seat: int = _peers[id]["seat"]
	a = (a as Dictionary).duplicate()
	r["seats"][seat]["idle"] = 0.0
	if str(a.get("type", "")) == "start_day":
		# 아침: 사람이 모두 「하루 시작」을 누르면 시작한다 (누가 리더든)
		r["day_ready"][seat] = true
		_broadcast(r, [])
		_maybe_start_day(r)
		return
	if int(a.get("player", -1)) != seat:
		_err(id, "내 요원의 행동만 할 수 있습니다.")
		return
	if not g.apply(a):
		_err(id, "지금은 할 수 없는 행동입니다.")
		_send(id, {"t": "update", "view": NetViewV2.view_for(g, seat), "events": [], "info": _info(r)})
		return
	var ev := g.events.duplicate()
	g.events.clear()
	_broadcast(r, ev)


func _maybe_start_day(r: Dictionary) -> void:
	var g: RulesV2 = r["game"]
	if g.phase != "plan":
		return
	for i in 4:
		if not _is_ai(r, i) and not r["day_ready"].has(i):
			return
	for x in g.legal_actions():
		if x["type"] == "start_day":
			g.apply(x)
			break
	r["day_ready"] = {}
	r["day_wait"] = 0.0
	var ev := g.events.duplicate()
	g.events.clear()
	_broadcast(r, ev)


func _info(r: Dictionary) -> Dictionary:
	var waiting := []
	var g: RulesV2 = r["game"]
	if g != null and g.phase == "plan":
		for i in 4:
			if not _is_ai(r, i) and not r["day_ready"].has(i):
				waiting.append(i)
	var ai := []
	for i in 4:
		if _is_ai(r, i):
			ai.append(i)
	return {"waiting_day": waiting, "ai": ai}


func _broadcast(r: Dictionary, ev: Array) -> void:
	var g: RulesV2 = r["game"]
	if g == null:
		return
	var info := _info(r)
	for i in 4:
		var s: Dictionary = r["seats"][i]
		if s["peer"] >= 0:
			_send(s["peer"], {"t": "update", "view": NetViewV2.view_for(g, i), "events": NetViewV2.events_for(ev, i), "info": info})


func _ai_actor(r: Dictionary) -> int:
	## 지금 서버의 AI가 둘 자리 (없으면 -1)
	var g: RulesV2 = r["game"]
	match g.phase:
		"choice":
			var pid := int(g.pending.get("player", -1))
			return pid if pid >= 0 and _is_ai(r, pid) else -1
		"turn":
			return g.current if _is_ai(r, g.current) else -1
		"day":
			for x in g.legal_actions():   # AI 자리가 먼저 차례를 한다 (연습 모드와 같음)
				if x["type"] == "begin_turn" and _is_ai(r, int(x["player"])):
					return int(x["player"])
			return -1
		"plan":
			for q in g.players:   # 아침 능력 · 아이템
				if _is_ai(r, q["id"]):
					var a := GameAIV2.decide(g, q["id"])
					if not a.is_empty() and int(a.get("player", -1)) == q["id"] and a["type"] in ["use_item", "ability"]:
						return q["id"]
			return -1
	return -1


func _tick_room(r: Dictionary, delta: float) -> void:
	var g: RulesV2 = r["game"]
	if g == null or g.phase == "over":
		var anyone := false
		for s in r["seats"]:
			anyone = anyone or s["peer"] >= 0
		r["closed_for"] = 0.0 if anyone else r["closed_for"] + delta
		if r["closed_for"] > 120.0:
			_log("방 %s 닫음" % r["code"])
			_rooms.erase(r["code"])
		return
	r["ai_timer"] -= delta
	if r["ai_timer"] > 0.0:
		return
	var pid := _ai_actor(r)
	if pid >= 0:
		var a: Dictionary
		if g.phase == "day":
			a = {"type": "begin_turn", "player": pid}
		else:
			a = GameAIV2.decide(g, pid)
		if not a.is_empty() and g.apply(a):
			var ev := g.events.duplicate()
			g.events.clear()
			_broadcast(r, ev)
		r["ai_timer"] = ai_step
		return
	# 사람 차례: 오래 아무것도 안 하면 AI가 한 수 대신 둔다 (판이 멈추지 않게)
	var who := -1
	if g.phase == "turn":
		who = g.current
	elif g.phase == "choice":
		who = int(g.pending.get("player", -1))
	if who >= 0:
		var s: Dictionary = r["seats"][who]
		s["idle"] += delta + ai_step
		if s["idle"] > HUMAN_IDLE:
			s["idle"] = 0.0
			var a := GameAIV2.decide(g, who)
			if not a.is_empty() and g.apply(a):
				var ev := g.events.duplicate()
				g.events.clear()
				_broadcast(r, ev)
	if g.phase == "plan":
		if _info(r)["waiting_day"].is_empty():
			_maybe_start_day(r)
		else:
			r["day_wait"] += delta + ai_step
			if r["day_wait"] > DAY_WAIT:
				for i in _info(r)["waiting_day"]:
					r["day_ready"][i] = true
				_maybe_start_day(r)
	r["ai_timer"] = ai_step
