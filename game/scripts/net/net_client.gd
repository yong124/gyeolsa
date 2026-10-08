class_name NetClientV2
extends Node
## 온라인 클라이언트 연결: 서버와 메시지를 주고받고 신호로 알린다. 화면(OnlineScreenV2 · GameScreenV2)이 이 신호를 듣는다.
## 판 상태는 서버가 보낸 「보기」(NetViewV2)를 로컬 RulesV2에 읽어 화면만 그린다.

signal connected
signal failed(msg: String)
signal room_changed(room: Dictionary)
signal game_started(seat: int, view: Dictionary, names: Array)
signal game_updated(view: Dictionary, events: Array, info: Dictionary)
signal server_error(msg: String)
signal closed

const DEFAULT_URL := "ws://127.0.0.1:8910"   # online.json이 없을 때


static func default_url() -> String:
	## 기본 서버 주소 (online.json): 웹판은 server_url_web(wss://), 데스크톱판은 server_url_desktop
	var o: Dictionary = GameDataV2.load_default().online
	if OS.has_feature("web"):
		return str(o.get("server_url_web", ""))
	return str(o.get("server_url_desktop", DEFAULT_URL))


static func web_online_ready() -> bool:
	## 웹판에서 온라인을 열 수 있는가: wss:// 주소가 있어야 한다 (https 페이지는 ws://에 못 붙음)
	return default_url().begins_with("wss://")

var url := DEFAULT_URL
var player_name := "요원"
var token := ""
var room: Dictionary = {}
var seat := -1
var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _opened := false


func open(server_url: String, name: String, resume_token := "") -> void:
	url = server_url.strip_edges()
	player_name = name
	token = resume_token
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 22
	_ws.outbound_buffer_size = 1 << 20
	_opened = false
	var err := _ws.connect_to_url(url)
	if err != OK:
		failed.emit("서버에 연결할 수 없습니다 (%s)." % url)


func close() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send({"t": "leave"})
		_ws.close()


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		_ws.send(var_to_bytes(msg))


func act(a: Dictionary) -> void:
	send({"t": "act", "a": a})


func _process(_d: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _opened:
			_opened = true
			send({"t": "hello", "name": player_name, "token": token, "ver": NetServerV2.VERSION})
		while _ws.get_available_packet_count() > 0:
			var m = bytes_to_var(_ws.get_packet())
			if m is Dictionary:
				_on_msg(m)
	elif st == WebSocketPeer.STATE_CLOSED and _state != WebSocketPeer.STATE_CLOSED:
		if not _opened:
			failed.emit("서버에 연결할 수 없습니다 (%s). 주소를 확인하거나 서버가 켜져 있는지 확인하세요." % url)
		else:
			closed.emit()
	_state = st


func _on_msg(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"welcome":
			token = str(m.get("token", ""))
			connected.emit()
		"room":
			room = m
			seat = int(m.get("you", -1))
			room_changed.emit(m)
		"start":
			seat = int(m["seat"])
			game_started.emit(seat, m["view"], m.get("names", []))
		"update":
			game_updated.emit(m["view"], m.get("events", []), m.get("info", {}))
		"error":
			server_error.emit(str(m.get("msg", "")))
