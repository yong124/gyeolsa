class_name OnlineScreenV2
extends Control
## 온라인 로비: 서버에 붙고 → 방 만들기 / 코드로 참가 → 방(자리 4개 · 요원 고르기 · 준비 · 방장 시작).
## 판이 시작되면 game_ready를 보내고, main이 GameScreenV2를 원격 모드로 연다.

signal back_requested
signal game_ready(seat: int, view: Dictionary)

var client: NetClientV2
var _box: VBoxContainer
var _status: Label
var _url: LineEdit
var _name: LineEdit
var _code: LineEdit
var _ready_on := false


func _init(c: NetClientV2) -> void:
	client = c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := UiKit.paper_panel(30)
	panel.custom_minimum_size = Vector2(980, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)
	client.connected.connect(_show_choose)
	client.failed.connect(func(msg): _show_connect(msg))
	client.room_changed.connect(_show_room)
	client.server_error.connect(func(msg): _set_status(msg, true))
	client.closed.connect(func(): _show_connect("서버와 연결이 끊겼습니다."))
	client.game_started.connect(func(seat, view, _names): game_ready.emit(seat, view))
	if client.is_open() and not client.room.is_empty():
		_show_room(client.room)
	elif client.is_open():
		_show_choose()
	else:
		_show_connect("")


func _head(t: String, sub: String) -> void:
	UiKit.clear(_box)
	_box.add_child(UiKit.title(t, Style.FS_H2))
	if sub != "":
		_box.add_child(UiKit.text(sub, Style.FS_BODY, Style.INK_2))


func _set_status(t: String, bad := false) -> void:
	if is_instance_valid(_status):
		_status.text = t
		_status.add_theme_color_override("font_color", Style.SEAL if bad else Style.INK_3)


func _field(label: String, value: String, ph: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiKit.text(label, 16, Style.INK_2)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = ph
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 40)
	row.add_child(e)
	_box.add_child(row)
	return e


func _show_connect(msg: String) -> void:
	_head("온라인 결사", "사람끼리 한 판. 방을 만들어 코드를 알려 주거나, 받은 코드로 들어갑니다. 빈자리는 AI 동료가 맡습니다.")
	_url = _field("서버 주소", Prefs.online_url, NetClientV2.DEFAULT_URL)
	_name = _field("내 이름", Prefs.online_name, "요원 이름 (12자까지)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	row.add_child(UiKit.button("서버에 연결", func():
		Prefs.online_url = _url.text.strip_edges()
		Prefs.online_name = _name.text.strip_edges()
		Prefs.save()
		_set_status("연결하는 중…")
		client.open(Prefs.online_url if Prefs.online_url != "" else NetClientV2.DEFAULT_URL, Prefs.online_name if Prefs.online_name != "" else "요원"), 18, "primary"))
	row.add_child(UiKit.button("← 메뉴로", func(): back_requested.emit(), 15, "tab"))
	_status = UiKit.text(msg, 14, Style.SEAL if msg != "" else Style.INK_3)
	_box.add_child(_status)
	_box.add_child(UiKit.text("서버는 「Godot --headless --path game -- server」로 켭니다 (기본 포트 8910). 웹판에서는 wss:// 주소가 필요합니다.", 12, Style.INK_3))


func _show_choose() -> void:
	_head("방 고르기", "%s 님, 연결되었습니다." % client.player_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	row.add_child(UiKit.button("방 만들기", func():
		_set_status("방을 만드는 중…")
		client.send({"t": "create"}), 18, "primary"))
	_code = LineEdit.new()
	_code.placeholder_text = "참가 코드 5자"
	_code.max_length = 5
	_code.custom_minimum_size = Vector2(200, 44)
	row.add_child(_code)
	row.add_child(UiKit.button("코드로 참가", func():
		_set_status("들어가는 중…")
		client.send({"t": "join", "code": _code.text.strip_edges().to_upper()}), 18, "paper"))
	row.add_child(UiKit.button("← 메뉴로", func():
		client.close()
		back_requested.emit(), 15, "tab"))
	_status = UiKit.text("", 14, Style.INK_3)
	_box.add_child(_status)


func _show_room(r: Dictionary) -> void:
	var me := int(r.get("you", -1))
	var host := int(r.get("host", -1))
	var data := GameDataV2.load_default()
	_head("방 %s" % r["code"], "이 코드를 같이 할 사람에게 알려 주세요. 사람이 없는 자리는 AI 동료가 맡습니다.")
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 12)
	_box.add_child(crow)
	crow.add_child(UiKit.title(" ".join(str(r["code"]).split("")), 44, Style.SEAL, 900))
	crow.add_child(UiKit.button("코드 복사", func():
		DisplayServer.clipboard_set(str(r["code"]))
		_set_status("복사했습니다."), 14, "paper"))
	# 자리 4개
	var seats: Array = r["seats"]
	for i in seats.size():
		var s: Dictionary = seats[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var ch := str(s.get("character", ""))
		var face := ArtV2.get_tex("token", ch) if ch != "" else null
		if face != null:
			row.add_child(UiKit.icon(face, Vector2(40, 40)))
		else:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(40, 40)
			row.add_child(gap)
		var who := "AI 동료 (시작할 때 정해짐)"
		if s["human"]:
			who = "%s%s%s" % [s["name"], " (방장)" if i == host else "", " · 나" if i == me else ""]
			if not s.get("online", true):
				who += " · 연결 끊김"
		var nm := UiKit.title(who, 18, Style.INK if s["human"] else Style.INK_3)
		nm.custom_minimum_size = Vector2(380, 0)
		row.add_child(nm)
		var info := "요원 고르는 중" if s["human"] and ch == "" else (str(data.character(ch).get("name", "")) if ch != "" else "")
		var il := UiKit.text(info, 15, Style.INK_2)
		il.autowrap_mode = TextServer.AUTOWRAP_OFF
		il.custom_minimum_size = Vector2(220, 0)
		row.add_child(il)
		if s["human"] and s.get("ready", false):
			row.add_child(UiKit.stamp("준 비", 12, Style.GOOD, -4))
		_box.add_child(row)
	# 내 요원 고르기
	var mine: Dictionary = seats[me] if me >= 0 else {}
	var offer: Array = mine.get("offer", [])
	if not offer.is_empty():
		_box.add_child(UiKit.hsep())
		_box.add_child(UiKit.text("내 요원 카드 두 장 중 한 사람:", 15, Style.INK_2))
		var orow := HBoxContainer.new()
		orow.add_theme_constant_override("separation", 16)
		_box.add_child(orow)
		for id in offer:
			var c: Dictionary = data.character(str(id))
			var cid := str(id)
			var picked := str(mine.get("character", "")) == cid
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", Style.flat(Color("#fff6dd") if picked else Color("#f6efdd"), Style.SEAL if picked else Style.INK_3, 3 if picked else 1, 4, 10))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			card.add_child(h)
			var pt := ArtV2.get_tex("char", cid)
			if pt != null:
				h.add_child(UiKit.icon(pt, Vector2(72, 96)))
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(v)
			v.add_child(UiKit.title(str(c.get("name", "")), 18))
			var ab := UiKit.text("능력: " + str(c.get("ability_text", "")), 13, Style.INK_2)
			ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(ab)
			v.add_child(UiKit.button("고름" if picked else "이 요원", func(): client.send({"t": "pick", "character": cid}), 14, "primary" if not picked else "paper"))
			orow.add_child(card)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	_box.add_child(brow)
	_ready_on = bool(mine.get("ready", false))
	brow.add_child(UiKit.button("준비 취소" if _ready_on else "준비", func(): client.send({"t": "ready", "on": not _ready_on}), 16, "paper"))
	if me == host:
		var all_picked := seats.all(func(s): return not s["human"] or str(s.get("character", "")) != "")
		var sb := UiKit.button("시작" if all_picked else "시작 (모두 요원을 고르면)", func(): client.send({"t": "start"}), 18, "primary")
		sb.disabled = not all_picked
		brow.add_child(sb)
	else:
		brow.add_child(UiKit.text("방장이 시작하기를 기다립니다.", 14, Style.INK_3))
	brow.add_child(UiKit.button("방 나가기", func():
		client.send({"t": "leave"})
		client.room = {}
		_show_choose(), 14, "tab"))
	_status = UiKit.text("", 14, Style.INK_3)
	_box.add_child(_status)
