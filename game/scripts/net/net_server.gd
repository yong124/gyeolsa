class_name NetServerV2
extends Node
## 온라인 서버 (헤드리스): 방을 만들고, 판을 서버에서 돌리고, 사람마다 볼 수 있는 것만 보낸다.
## 실행: Godot --headless --path game -- server [port=8910]
## 규약: v2_구현/온라인_규약.md. 메시지는 Dictionary를 var_to_bytes로 묶은 WebSocket 바이너리 패킷.
## 서버 → 클라이언트 패킷은 앞 1바이트가 방식이다: 0 = 그대로, 1 = 원래 크기(4바이트) + zstd 압축 (Z5).
## 요원은 늘 4명이다. 빈자리 · 끊긴 자리는 서버의 AI(GameAIV2)가 둔다.

const VERSION := 2   # 2: 서버 패킷 머리 바이트 · 압축, 작전 기록은 새 줄만 (Z5)
const PACK_RAW := 0
const PACK_ZSTD := 1
const PACK_MIN := 512          # 이보다 작은 메시지는 압축하지 않는다
const PACK_MAX := 1 << 23      # 풀었을 때 이보다 크면 받지 않는다
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # 헷갈리는 0 O 1 I 뺌
const AI_STEP := 0.45          # AI 한 수 사이 간격(초): 사람이 따라 볼 수 있게
const HUMAN_IDLE := 150.0      # 사람 자리가 이만큼 아무것도 안 하면 AI가 한 수 대신 둔다
const DAY_WAIT := 60.0         # 아침: 다들 「하루 시작」을 누를 때까지 기다리는 최대 시간
const DROP_GRACE := 20.0       # 끊긴 자리를 AI가 맡기까지
# 보안 (지시서 Z1): 상한 · 빈도 제한
const MAX_PEERS := 256         # 동시 접속 상한
const MAX_ROOMS := 128         # 방 상한
const MSG_PER_SEC := 30        # 연결당 초당 메시지 상한 (넘으면 끊음)
const INBOUND_BYTES := 1 << 16 # 받는 버퍼 64KB (메시지 하나가 이보다 크면 받지 않음)
const HELLO_TIMEOUT := 10.0    # 인사(hello) 없이 이만큼 지나면 끊음
const BAD_CODE_LIMIT := 10     # 없는 방 코드를 이만큼 틀리면 끊음 (방 코드 맞히기 막기)
const NAME_MAX := 12
const ROOM_NAME_MAX := 16      # 방 이름 글자 수
const LIST_MAX := 50           # 공개 방 목록에 한 번에 보내는 방 수

var port := 8910
var _tcp := TCPServer.new()
var _peers := {}     # peer id -> {"ws": WebSocketPeer, "name", "token", "room", "seat"}
var _rooms := {}     # code -> 방 (아래 _new_room)
var _next_peer := 1
var _rng := RandomNumberGenerator.new()
var quiet := false   # 시험: 서버 로그 끄기
var ai_step := AI_STEP   # 시험에서는 0으로
var _crypto := Crypto.new()
# online.json에서 읽는 값 (없으면 위 상수)
var human_idle := HUMAN_IDLE
var day_wait := DAY_WAIT
var drop_grace := DROP_GRACE
var room_close_after := 120.0
var max_peers := MAX_PEERS
var max_rooms := MAX_ROOMS
var msg_per_sec := MSG_PER_SEC
var inbound_bytes := INBOUND_BYTES
var hello_timeout := HELLO_TIMEOUT
var bad_code_limit := BAD_CODE_LIMIT
var name_max := NAME_MAX
var _data: GameDataV2         # 판 데이터 (한 번만 읽음)


func _ready() -> void:
	_rng.randomize()
	_data = GameDataV2.load_default()
	_apply_config(_data.online)
	var err := _tcp.listen(port)
	_log("서버 시작 · 포트 %d · %s" % [port, "ok" if err == OK else "실패 %d" % err])


func _apply_config(o: Dictionary) -> void:
	## online.json → 서버 값 (시험이 ai_step을 0으로 둔 경우는 그대로)
	if o.is_empty():
		return
	if ai_step == AI_STEP:
		ai_step = float(o.get("ai_step", ai_step))
	human_idle = float(o.get("human_idle", human_idle))
	day_wait = float(o.get("day_wait", day_wait))
	drop_grace = float(o.get("drop_grace", drop_grace))
	room_close_after = float(o.get("room_close_after", room_close_after))
	var l: Dictionary = o.get("limits", {})
	max_peers = int(l.get("max_peers", max_peers))
	max_rooms = int(l.get("max_rooms", max_rooms))
	msg_per_sec = int(l.get("msg_per_sec", msg_per_sec))
	inbound_bytes = int(l.get("inbound_bytes", inbound_bytes))
	hello_timeout = float(l.get("hello_timeout", hello_timeout))
	bad_code_limit = int(l.get("bad_code_limit", bad_code_limit))
	name_max = int(l.get("name_max", name_max))


func _exit_tree() -> void:
	_tcp.stop()


func _log(s: String) -> void:
	if not quiet:
		print("[server] ", s)


# ------------------------------------------------------------------ 연결

func _process(delta: float) -> void:
	var now := _now()
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		if _peers.size() >= max_peers:
			conn.disconnect_from_host()   # 가득 참: 받지 않는다
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = inbound_bytes
		ws.outbound_buffer_size = 1 << 22
		ws.accept_stream(conn)
		_peers[_next_peer] = {"ws": ws, "name": "", "token": "", "room": "", "seat": -1,
			"hello": false, "born": now, "win": now, "msgs": 0, "bad_codes": 0}
		_next_peer += 1
	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not p["hello"] and now - float(p["born"]) > hello_timeout:
					_kick(id, "인사 없이 오래 머묾")
					continue
				while ws.get_available_packet_count() > 0:
					if now - float(p["win"]) >= 1.0:
						p["win"] = now
						p["msgs"] = 0
					p["msgs"] = int(p["msgs"]) + 1
					if int(p["msgs"]) > msg_per_sec:
						_kick(id, "메시지가 너무 잦음")
						break
					var msg = bytes_to_var(ws.get_packet())   # 객체는 풀지 않는다 (기본값)
					if msg is Dictionary:
						_on_msg(id, msg)
					if not _peers.has(id):
						break
			WebSocketPeer.STATE_CLOSED:
				_on_drop(id)
				_peers.erase(id)
	for code in _rooms.keys():
		_tick_room(_rooms[code], delta)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _kick(id: int, why: String) -> void:
	## 규칙을 어긴 연결을 끊는다 (판 중이면 그 자리는 끊긴 자리처럼 AI가 맡음)
	if not _peers.has(id):
		return
	_log("연결 %d 끊음: %s" % [id, why])
	var ws: WebSocketPeer = _peers[id]["ws"]
	ws.close(1008, why)


static func clean_name(raw: String, max_len := NAME_MAX) -> String:
	## 이름: 제어 문자 · 서식 문자([ ] 같은 BBCode)를 빼고 12자까지
	var out := ""
	for ch in raw.strip_edges():
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or ch in ["[", "]", "{", "}", "<", ">", "\\"]:
			continue
		out += ch
	out = out.strip_edges().left(max_len)
	return out if out != "" else "요원"


func _new_token() -> String:
	return _crypto.generate_random_bytes(16).hex_encode()   # 암호용 난수 128비트


func _send(id: int, msg: Dictionary) -> void:
	if not _peers.has(id):
		return
	var ws: WebSocketPeer = _peers[id]["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(pack(msg))


static func pack(msg: Dictionary) -> PackedByteArray:
	## 서버 → 클라이언트 패킷: [방식 1바이트] + (압축이면 원래 크기 4바이트) + 내용
	var raw := var_to_bytes(msg)
	var out := PackedByteArray()
	if raw.size() < PACK_MIN:
		out.append(PACK_RAW)
		out.append_array(raw)
		return out
	out.append(PACK_ZSTD)
	out.resize(5)
	out.encode_u32(1, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func unpack(pkt: PackedByteArray) -> Variant:
	## pack()을 푼다. 모양이 틀리면 null
	if pkt.is_empty():
		return null
	if pkt[0] == PACK_RAW:
		return bytes_to_var(pkt.slice(1))
	if pkt[0] == PACK_ZSTD and pkt.size() > 5:
		var n := pkt.decode_u32(1)
		if n <= 0 or n > PACK_MAX:
			return null
		var raw := pkt.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD)
		return bytes_to_var(raw) if raw.size() == n else null
	return null


func _err(id: int, text: String) -> void:
	_send(id, {"t": "error", "msg": text})


# ------------------------------------------------------------------ 메시지

func _on_msg(id: int, m: Dictionary) -> void:
	var p: Dictionary = _peers[id]
	var t := str(m.get("t", ""))
	if t != "hello" and not p["hello"]:
		_err(id, "먼저 인사(hello)를 보내야 합니다.")
		return
	match t:
		"hello":
			if p["hello"]:
				return   # 한 연결에 인사는 한 번 (토큰 바꿔치기 막기)
			if int(m.get("ver", 0)) != VERSION:
				_err(id, "게임 버전이 서버와 다릅니다. 새로 받아 주세요.")
				return
			p["hello"] = true
			p["name"] = clean_name(str(m.get("name", "요원")), name_max)
			# 토큰은 서버만 만든다. 클라이언트가 보낸 토큰은 끊긴 자리와 맞을 때만 「돌아오기」에 쓴다
			var given := str(m.get("token", "")).left(64)
			p["token"] = given if given != "" and _dropped_seat_with(given) else _new_token()
			_send(id, {"t": "welcome", "token": p["token"], "ver": VERSION})
			_try_resume(id)
		"create":
			if p["room"] != "":
				return
			if _rooms.size() >= max_rooms:
				_err(id, "서버에 방이 가득 찼습니다. 잠시 뒤에 다시 해 주세요.")
				return
			var code := _new_code()
			var room := _new_room(code)
			# 방 이름 (서식 문자는 이름과 같이 거름) · 공개 여부 (비공개는 목록에 안 나오고 코드로만 들어옴)
			var rname := clean_name(str(m.get("name", "")), ROOM_NAME_MAX)
			room["name"] = rname if rname != "" else "%s의 작전" % p["name"]
			room["public"] = bool(m.get("public", true))
			_rooms[code] = room
			_log("방 %s 만듦 (%s · %s)" % [code, p["name"], "공개" if room["public"] else "비공개"])
			_join(id, code)
		"list":
			_send(id, {"t": "rooms", "rooms": public_rooms()})
		"join":
			if p["room"] != "":
				return
			var code := str(m.get("code", "")).to_upper().strip_edges().left(8)
			if not _rooms.has(code):
				p["bad_codes"] = int(p["bad_codes"]) + 1
				if int(p["bad_codes"]) >= bad_code_limit:
					_kick(id, "방 코드를 너무 많이 틀림")
					return
				_err(id, "그런 방이 없습니다.")
				return
			_join(id, code)
		"pick":
			_pick(id, str(m.get("character", "")).left(32))
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


func public_rooms() -> Array:
	## 공개 방 목록: 아직 시작하지 않았고, 공개이고, 사람이 한 명 이상 있고, 빈자리가 있는 방 (먼저 만든 방부터)
	var out := []
	for code in _rooms:
		var r: Dictionary = _rooms[code]
		if r["game"] != null or not bool(r.get("public", false)):
			continue
		var humans := 0
		for s in r["seats"]:
			if s["human"]:
				humans += 1
		if humans == 0 or humans >= 4:
			continue
		out.append({"code": code, "name": str(r.get("name", "")), "humans": humans, "max": 4})
		if out.size() >= LIST_MAX:
			break
	return out


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
	var ids: Array = _data.characters.get("characters", []).map(func(c): return str(c["id"]))
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
		_send(s["peer"], {"t": "room", "code": r["code"], "host": r["host"], "you": i, "seats": seats,
			"name": str(r.get("name", "")), "public": bool(r.get("public", false))})


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


func _dropped_seat_with(token: String) -> bool:
	## 이 토큰을 가진 끊긴 자리가 있는가 (판 중인 방)
	for code in _rooms:
		var r: Dictionary = _rooms[code]
		if r["game"] == null:
			continue
		for s in r["seats"]:
			if s["token"] == token and s["peer"] < 0:
				return true
	return false


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
				s["log_sent"] = g.log_lines.size()   # 돌아온 사람은 기록을 처음부터 받는다
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
	for i in 4:
		var hs: Dictionary = r["seats"][i]
		if hs["human"] and hs["character"] == "":
			_err(id, "아직 요원을 고르지 않은 사람이 있습니다.")
			return
		if hs["human"] and i != r["host"] and not hs["ready"]:
			_err(id, "모두 준비를 눌러야 시작할 수 있습니다.")
			return
	var data := _data
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
	g.setup(defs, _rng.randi(), data)
	g.human = r["host"]   # 결행 혜택은 방장이 고른다 (엔진 규칙: 사람 한 명)
	r["game"] = g
	g.events.clear()
	_log("방 %s 시작" % r["code"])
	for i in 4:
		var s: Dictionary = r["seats"][i]
		if s["human"] and s["peer"] >= 0:
			s["log_sent"] = g.log_lines.size()
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
		return Time.get_ticks_msec() / 1000.0 - s["dropped_at"] >= drop_grace
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
			var lf := mini(int(s.get("log_sent", 0)), g.log_lines.size())   # 이미 보낸 기록 줄은 다시 보내지 않는다
			s["log_sent"] = g.log_lines.size()
			_send(s["peer"], {"t": "update", "view": NetViewV2.view_for(g, i, lf), "events": NetViewV2.events_for(ev, i), "info": info})


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
		if r["closed_for"] > room_close_after:
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
		if s["idle"] > human_idle:
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
			if r["day_wait"] > day_wait:
				for i in _info(r)["waiting_day"]:
					r["day_ready"][i] = true
				_maybe_start_day(r)
	r["ai_timer"] = ai_step
