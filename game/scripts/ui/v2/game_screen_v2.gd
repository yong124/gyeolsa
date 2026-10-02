class_name GameScreenV2
extends Control
## v2 게임 화면 (v1 화면 모양): 상단 바 + 보드 + 오른쪽 열(요원 명부 · 공개 미션 줄/결행 장면 · 내 손패 · 행동) + 작전 기록.
##
## 흐름: 엔진에 액션 → 엔진이 쌓은 events를 연출 큐에 넣음 → 하나씩 재생(await)
##      → 큐가 비면 화면을 실제 상태와 맞추고 → 사람 입력을 기다리거나 AI가 한 수를 둔다.
## 버튼은 모두 엔진의 legal_actions()에서 만든다. 그래서 화면이 규칙과 어긋나지 않는다.

signal back_to_title
signal finished

const GAP := 8.0
const AI_DELAY := 0.28
const SECONDARY_MAX := 3          # 행동 패널의 보조 버튼 수 (나머지는 「더 보기」)
const MISSION_ART := {"assassin": "res://assets/tiles/assassin.png", "infiltrate": "res://assets/tiles/base.png",
	"bomb": "res://assets/tiles/bomb.png", "sabotage": "res://assets/tiles/sabotage.png", "coop": "res://assets/tiles/start.png"}
const SAGA_COL := Color("#6b4f8a")
const BOMB_COL := Color("#b86a1e")

var game: RulesV2
var human := 0
var meta := {}

var _queue: Array = []
var _playing := false
var _started := false
var _paused := false
var _fast := false
var _ai_timer := 0.0
var _ai_waiting := false
var _walk: Array = []
var _let_allies := false          # 낮: 사람이 "동료 먼저"를 눌러 둔 상태
var _auto := false                # 자동 진행 (내 자리도 AI가 둠, 화면 확인·캡처용)

var _board: BoardViewV2
var _frame: PanelContainer
var _top: TopBarV2
var _right: VBoxContainer
var _roster_box: VBoxContainer
var _rows: Array = []
var _mid_title: Label
var _mid_hint: Label
var _mid_box: Container
var _hand_hint: Label
var _hand_row: HBoxContainer
var _act_title: Label
var _act_hint: Label
var _dice_row: HBoxContainer
var _act_row: HBoxContainer
var _ticker: LogTickerV2
var _fx: FxLayer
var _choice: Overlay
var _peek: CardPeekV2   # 마우스를 올리면 뜨는 큰 카드
var _shown_actions: Array = []    # 지금 화면에 단추로 나온 액션 (시험용)
var _primary_action: Dictionary = {}  # 주 버튼 액션 (스페이스)


func _init(g: RulesV2, human_id := 0, meta_info := {}) -> void:
	game = g
	human = human_id
	meta = meta_info
	_auto = bool(meta.get("autoplay", false))
	_fast = _auto


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	_board.sync_from_game()
	_refresh()
	Music.play("main")
	_started = true
	_pump()


func _mult() -> float:
	return 0.35 if _fast else 1.0


# ================================================================ 구성

func _build() -> void:
	_peek = CardPeekV2.new()
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top = TopBarV2.new(game)
	_top.menu_pressed.connect(_pause)
	add_child(_top)

	_frame = PanelContainer.new()
	var fs := Style.flat(Color("#3b2a1c"), Color("#5a4330"), 2, 3, 9)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 18
	fs.shadow_offset = Vector2(0, 8)
	_frame.add_theme_stylebox_override("panel", fs)
	add_child(_frame)
	_board = BoardViewV2.new()
	_board.cell_clicked.connect(_on_cell)
	_frame.add_child(_board)
	_board.setup(game, human)

	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", int(GAP))
	add_child(_right)

	# 요원 명부
	var roster := _panel("요 원 명 부", "마우스를 올리면 특성 · 능력")
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 4)
	roster[1].add_child(_roster_box)
	for p in game.players:
		_rows.append(_make_row(p))

	# 공개 미션 줄 / 결행 장면
	var mid := _panel("", "")
	_mid_title = mid[2]
	_mid_hint = mid[3]
	_mid_box = HBoxContainer.new()
	_mid_box.add_theme_constant_override("separation", 8)
	mid[1].add_child(_mid_box)

	# 내 손패
	var hand := _panel("내 손 패", "")
	_hand_hint = hand[3]
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 8)
	hand[1].add_child(_hand_row)

	# 행동
	var act := _panel("", "")
	act[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	_act_title = act[2]
	_act_hint = act[3]
	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 10)
	act[1].add_child(_dice_row)
	_act_row = HBoxContainer.new()
	_act_row.add_theme_constant_override("separation", 9)
	act[1].add_child(_act_row)

	_ticker = LogTickerV2.new(game)
	add_child(_ticker)
	add_child(_ticker.drawer)

	_fx = FxLayer.new()
	add_child(_fx)
	_choice = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	add_child(_choice)
	add_child(_peek)
	_peek.attach(_top._threat, _threat_info)


func _panel(title: String, hint: String) -> Array:
	## 종이 패널: [패널, 본문 VBox, 제목 Label, 안내 Label]
	var panel := PanelContainer.new()
	var ps := Style.paper(12)
	ps.content_margin_top = 6
	ps.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", ps)
	_right.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UiKit.title(title, 16, Style.INK_2)
	head.add_child(t)
	var h := UiKit.text(hint, 11, Style.INK_3, false)
	h.size_flags_vertical = Control.SIZE_SHRINK_END
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.clip_text = true
	h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(h)
	v.add_child(head)
	return [panel, v, t, h]


func _layout() -> void:
	var w := size.x
	var h := size.y
	_top.position = Vector2(20, 10)
	_top.size = Vector2(w - 40, 56)
	var top_y := 78.0
	var side := floorf(minf(h - top_y - 12, w * 0.52))
	_frame.position = Vector2(20, top_y)
	_frame.size = Vector2(side, side)
	var rx := 20 + side + 18
	var tick_h := 40.0
	_right.position = Vector2(rx, top_y)
	_right.size = Vector2(w - rx - 20, h - top_y - 12 - tick_h - GAP)
	_ticker.position = Vector2(rx, h - 12 - tick_h)
	_ticker.size = Vector2(w - rx - 20, tick_h)
	var dy := top_y + h * 0.18
	_ticker.drawer.position = Vector2(rx, dy)
	_ticker.drawer.size = Vector2(w - rx - 20, h - 12 - tick_h - 8 - dy)
	_fx.focus_center = _frame.position + _frame.size / 2.0
	_fx.board_rect = Rect2(_frame.position, _frame.size)


# ================================================================ 요원 명부

func _make_row(p: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var pid: int = p["id"]
	_peek.attach(panel, func(): return _char_info(game.players[pid]))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var bar := ColorRect.new()
	bar.color = Style.seat(p["id"])
	bar.custom_minimum_size = Vector2(5, 0)
	h.add_child(bar)
	var face := AgentPanel.Face.new()
	face.tex = _board.faction_texture(str(game.char_def(p).get("faction", "")))
	face.ring = Style.seat(p["id"])
	face.custom_minimum_size = Vector2(36, 36)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 6)
	var ch: Dictionary = game.char_def(p)
	var name := UiKit.title("나" if p["id"] == human else str(ch.get("name", "")), 15, Style.INK)
	nh.add_child(name)
	var fac: String = str(game.data.characters.get("factions", {}).get(ch.get("faction", ""), {}).get("name", ""))
	var sub := UiKit.text(fac + (" · " + str(ch.get("name", "")) if p["id"] == human else ""), 12, Style.INK_3, false)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	nh.add_child(sub)
	v.add_child(nh)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 5)
	chips.clip_contents = true
	v.add_child(chips)
	var stamp := UiKit.stamp("차 례", 13)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(stamp)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	h.add_child(pad)
	_roster_box.add_child(panel)
	return {"panel": panel, "face": face, "name": name, "sub": sub, "bar": bar, "chips": chips, "stamp": stamp, "sig": "", "cur": null}



func _refresh_roster() -> void:
	for p in game.players:
		var row: Dictionary = _rows[p["id"]]
		var is_cur: bool = p["id"] == game.current and game.phase in ["turn", "choice"]
		if row["cur"] != is_cur:
			row["cur"] = is_cur
			var st := Style.row(Color("#fff8e1", 0.8) if is_cur else Color(1, 1, 1, 0.26),
				Style.GOLD if is_cur else Color(Style.INK, 0.14), 2 if is_cur else 1)
			st.content_margin_left = 0
			st.content_margin_top = 4
			st.content_margin_bottom = 4
			row["panel"].add_theme_stylebox_override("panel", st)
			row["stamp"].visible = is_cur
		var ring: Color = Style.seat(p["id"])
		var face: AgentPanel.Face = row["face"]
		if face.jailed != p["jailed"] or face.ring != ring:
			face.jailed = p["jailed"]
			face.ring = ring
			face.queue_redraw()
		row["bar"].color = ring
		var chips := _chips(p)
		var sig := str(chips)
		if sig != row["sig"]:
			row["sig"] = sig
			UiKit.clear(row["chips"])
			for c in chips:
				row["chips"].add_child(_chip(c))


func _chips(p: Dictionary) -> Array:
	## [표시 글, 아이콘 글자, 색, 설명, 흐리게?]
	var out := []
	var me: bool = p["id"] == human
	if p["id"] == game.leader:
		out.append(["리더", "★", Style.INK_2, "오늘의 리더: 의견이 갈리면 정합니다 (누가 먼저, 결행 투표 동수, 동점 대상).", false])
	if p["jailed"]:
		out.append(["감옥 · %s" % game.base_name(game.data.bases.find(p["pos"])), "!", Style.SEAL, "감옥에 갇혀 있습니다. 차례마다 탈옥을 시도하거나, 동료가 그 거점에 들어오면 구출됩니다.", false])
	if game.police.has(p["id"]):
		out.append(["추격당함", "!", Style.SEAL, "경찰이 이 요원을 쫓고 있습니다. 차례가 끝날 때 다가오고, 같은 칸이 되면 체포됩니다.", false])
	var dv: Array = game.my_dice(p["id"]).map(func(i): return str(game.die_value(i)))
	if not dv.is_empty():
		out.append(["주사위 " + "·".join(dv), "⚄", Style.INK_2, "오늘 남은 작전 주사위: 이동, 작전 판정, 장면 바치기, 건네기에 씁니다.", false])
	if not p["items"].is_empty():
		var names: Array = p["items"].map(func(id): return str(game.item_def(str(id)).get("name", "")))
		out.append([", ".join(names) if me else "아이템", str(p["items"].size()), Style.ITEM, "아이템: " + ", ".join(names), false])
	if p["bombs"] > 0:
		out.append(["폭탄", str(p["bombs"]), BOMB_COL, "폭탄: 폭파 미션이나 장면에 씁니다.", false])
	if p["saga_done"] != "":
		out.append(["사연 이룸 · %s" % game.data.saga(p["saga_done"]).get("name", ""), "✓", SAGA_COL, str(game.data.saga(p["saga_done"]).get("story", "")), false])
	elif me:
		out.append(["사연 %d장 (비밀)" % game.saga_cards(human).size(), "?", SAGA_COL, "내 사연은 손패에서 봅니다.", false])
	if p["done_today"] and game.phase in ["day", "turn", "choice"]:
		out.append(["차례 마침", "✓", Style.INK_3, "오늘 차례를 마쳤습니다.", true])
	return out


func _chip(c: Array) -> Control:
	var col: Color = c[2]
	var used: bool = c[4]
	var panel := PanelContainer.new()
	var st := Style.flat(Color(col, 0.9) if not used else Color(Style.INK, 0.06), col.darkened(0.25) if not used else Color(Style.INK, 0.2), 1, 9, 0)
	st.content_margin_left = 3
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", st)
	panel.tooltip_text = c[3]
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	panel.add_child(h)
	var dot := Label.new()
	dot.text = c[1]
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.custom_minimum_size = Vector2(16, 16)
	dot.add_theme_font_size_override("font_size", 10)
	dot.add_theme_font_override("font", Style.sans(800))
	dot.add_theme_color_override("font_color", Color.WHITE if not used else Style.INK_3)
	dot.add_theme_stylebox_override("normal", Style.flat(col.darkened(0.35) if not used else Color(Style.INK, 0.1), Color.TRANSPARENT, 0, 8, 0))
	h.add_child(dot)
	var l := UiKit.label(c[0], 12, Color.WHITE if not used else Style.INK_3)
	l.add_theme_font_override("font", Style.sans(700))
	h.add_child(l)
	return panel


# ================================================================ 공개 미션 줄 / 결행 장면

func _refresh_mid() -> void:
	UiKit.clear(_mid_box)
	if game.act == 1:
		_mid_title.text = "공 개 미 션 줄"
		_mid_hint.text = "누구든 이루면 결행 준비가 오릅니다 · 이룬 자리에 새 미션"
		for id in game.mission_row:
			var m: Dictionary = game.mission_def(str(id))
			var type := str(m.get("type", ""))
			var td: Dictionary = game.mission_type_def(type)
			var coop := td.get("ready") == null
			var ready := int(m.get("ready", td.get("ready", 0)))
			var band := "%s%s" % [_spaced(str(td.get("name", "미션"))), (" · +%d" % ready) if not coop else ""]
			var desc := str(m.get("text", ""))
			if not coop:
				desc = "%s\n%s" % [td.get("how", ""), desc]
			var card := CardView.face(band, Color("#2f7f7a") if coop else Style.MISSION, load(MISSION_ART.get(type, MISSION_ART["coop"])),
				str(m.get("name", "")), desc, 164, 112)
			_peek.attach(card, _mission_info(str(id)))
			_mid_box.add_child(card)
		if game.mission_row.is_empty():
			_mid_box.add_child(UiKit.text("아침에 미션 줄을 채웁니다.", 14, Style.INK_3))
		return
	var strike: Dictionary = game.data.strike(str(game.launch_info.get("target", "")))
	_mid_title.text = "결 행 · %s" % _spaced(str(strike.get("name", "")))
	_mid_hint.text = "장면을 하나씩 돌파 · 마지막을 뚫으면 대성공"
	for i in game.scenes.size():
		if i > 0:
			_mid_box.add_child(UiKit.text("▸", 14, Style.INK_3, false))
		var last := i == game.scenes.size() - 1
		var card := _scene_card_dict(str(game.scenes[i]))
		var box := PanelContainer.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		box.add_child(v)
		if i < game.scene_index:
			box.add_theme_stylebox_override("panel", Style.flat(Style.MISSION, Style.MISSION.darkened(0.3), 1, 2, 6))
			v.add_child(_center_lbl(UiKit.title(str(card.get("name", "")), 14, Color.WHITE)))
			v.add_child(_center_lbl(UiKit.text("돌파", 11, Color.WHITE, false)))
			box.custom_minimum_size = Vector2(76, 58)
		elif i == game.scene_index:
			box.add_theme_stylebox_override("panel", Style.flat(Color("#fff8e6"), Style.GOLD, 3, 2, 8))
			box.custom_minimum_size = Vector2(270, 0)
			v.add_child(UiKit.text("지금 장면 %d / %d" % [i + 1, game.scenes.size()], 11, Style.INK_3, false))
			v.add_child(UiKit.title(str(card.get("name", "")), 17, Style.INK))
			v.add_child(UiKit.text(_cond_text(card.get("condition", {}), card), 12, Style.INK_2))
			var need := game.scene_need()
			var parts := []
			for key in need:
				parts.append("%s %d" % [{"dice": "주사위 합", "item": "아이템", "bomb": "폭탄", "check_pair": "판정 성공", "people": "사람", "hold": "밤"}.get(key, key), int(need[key])])
			if not parts.is_empty():
				v.add_child(UiKit.text("남은 것: " + ", ".join(parts), 12, Style.GOOD, false, 800))
		else:
			var known := last   # 마지막 장면은 공개된 카드 (결행마다 고정)
			box.add_theme_stylebox_override("panel", Style.flat(Color("#e4d6b4"), Style.SEAL if last else Color("#bba57c"), 2 if last else 1, 2, 6))
			box.custom_minimum_size = Vector2(76, 58)
			v.add_child(_center_lbl(UiKit.title(str(card.get("name", "")) if known else "?", 14, Style.SEAL if last else Style.INK_3)))
			v.add_child(_center_lbl(UiKit.text("마지막" if last else "중간", 11, Style.SEAL if last else Style.INK_3, false)))
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		_peek.attach(box, _scene_info(card, i))
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mid_box.add_child(box)


func _scene_card_dict(id: String) -> Dictionary:
	var strike: Dictionary = game.data.strike(str(game.launch_info.get("target", "")))
	for c in [strike.get("entry", {}), strike.get("final", {})] + strike.get("middle", []) + game.data.scenes.get("reinforce", []):
		if c.get("id", "") == id:
			return c
	return {}


func _center_lbl(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _spaced(s: String) -> String:
	## "잠입" → "잠 입" (v1 카드 띠 글자 모양)
	if s.length() > 4:
		return s
	return " ".join(Array(s.split("")))


# ================================================================ 내 손패

func _refresh_hand() -> void:
	UiKit.clear(_hand_row)
	var me: Dictionary = game.players[human]
	var W := 112.0
	var H := 108.0
	var prog := game.saga_progress(human)
	for id in game.saga_cards(human):
		var s: Dictionary = game.data.saga(str(id))
		var pr: Dictionary = prog.get(id, {"have": 0, "need": 1})
		var done: bool = me["saga_done"] == id
		var band := "사 연" if game.act == 1 or done else "남 긴 사 연"
		var dots := ""
		for i in int(pr["need"]):
			dots += "●" if i < int(pr["have"]) else "○"
		var card := CardView.face(band, SAGA_COL, load("res://assets/cards/event_back.png"), str(s.get("name", "")),
			"%s\n%s" % [s.get("condition_text", ""), dots], W, H)
		_peek.attach(card, _saga_info(str(id), pr, done))
		if not done:
			var tag := UiKit.stamp("비밀", 10, SAGA_COL, 12)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(tag)
			tag.position = Vector2(W - 34, 24)
		_hand_row.add_child(card)
	for i in me["items"].size():
		var it: Dictionary = game.item_def(str(me["items"][i]))
		var card := CardView.face("아 이 템", Style.ITEM, load("res://assets/cards/item_back.png"), str(it.get("name", "")), str(it.get("text", "")), W, H)
		_peek.attach(card, {"band": "아 이 템", "color": Style.ITEM, "art": load("res://assets/cards/item_back.png"), "name": str(it.get("name", "")),
			"sections": [["효과", str(it.get("text", ""))], ["", "같은 칸 동료에게 줄 수 있습니다." + (" 2막 장면에 아이템으로 바칠 수도 있습니다." if game.act == 2 else "")]]})
		_hand_row.add_child(card)
	for i in me["bombs"]:
		var card := CardView.face("폭 탄", BOMB_COL, load("res://assets/cards/bomb.png"), "폭탄", "폭파 미션이나 장면에 씀", W, H)
		_peek.attach(card, {"band": "폭 탄", "color": BOMB_COL, "art": load("res://assets/cards/bomb.png"), "name": "폭탄",
			"sections": [["쓰는 곳", "1막: 폭파 미션의 목표 타일까지 들고 가면 미션을 이룹니다.\n2막: 폭탄을 요구하는 장면에 바칩니다."]]})
		_hand_row.add_child(card)
	var empty: int = game.hand_limit(me) - me["items"].size()
	for i in mini(empty, 2):
		_hand_row.add_child(_slot("아이템 칸\n비어 있음", W, H))
	_hand_hint.text = "사연은 나만 봅니다" if game.act == 1 else "남긴 사연은 결행 뒤에도 이룰 수 있습니다"


func _slot(text: String, w: float, h: float) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(w, h)
	var st := Style.flat(Color(1, 1, 1, 0.12), Color(Style.INK_3, 0.5), 2, 3, 6)
	p.add_theme_stylebox_override("panel", st)
	var l := UiKit.text(text, 12, Style.INK_3, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


# ================================================================ 행동 패널

func _refresh_actions() -> void:
	UiKit.clear(_dice_row)
	UiKit.clear(_act_row)
	_shown_actions = []
	_primary_action = {}
	var me: Dictionary = game.players[human]
	var legal := game.legal_actions()
	var mine := legal.filter(func(a): return int(a.get("player", -1)) == human)
	_refresh_dice(mine)
	var title := ""
	var hint := ""
	var primary: Dictionary = {}
	var others := []
	var extra_btn: Array = []    # [글, 콜백] — 액션이 아닌 단추 (동료 먼저)
	for a in mine:
		if a["type"] in ["step", "choose"] + ["move_die", "give_die"] or (a["type"] == "scene_pay" and a["what"] == "die"):
			continue   # 주사위로 하는 일은 주사위를 눌러서
		others.append(a)
	match game.phase:
		"plan":
			title = "아 침 계 획"
			hint = "오늘의 작전 주사위 · 큰 눈을 이동에 쓸지, 판정에 남길지 정하세요"
			primary = _take_type(others, "start_day")
		"day":
			title = "누 가 먼 저 ?"
			if game.can_begin_turn(me):
				hint = "자유 순서 · 내가 먼저 할지, 동료에게 먼저 맡길지 고르세요"
				primary = _take_type(others, "begin_turn")
				extra_btn = ["동료 먼저", func():
					_let_allies = true
					_after_queue()]
			else:
				hint = "동료들이 움직이는 중입니다."
		"turn":
			if game.current == human:
				title = "내 차 례"
				if me["jailed"]:
					hint = "감옥 · 탈옥 판정 %d 이상, 또는 동료의 구출을 기다리며 차례 넘기기" % game.check_target("escape")
				elif game.steps_left > 0:
					hint = "이동 %d칸 남음 · 보드에서 칸을 누르면 그 길로 걸어갑니다 · 주사위를 더 써서 늘릴 수도 있습니다" % game.steps_left
				elif not game.my_dice(human).is_empty():
					hint = "주사위를 눌러 이동하거나 쓰세요 · 판정 때는 어느 주사위로 할지 묻습니다"
				else:
					hint = "주사위를 다 썼습니다"
				if game.act == 2:
					hint += " · 장면 자리(금색 점선)에서 바치기 · 판정"
				for t in ["scene_pay", "scene_check", "escape"]:
					primary = _take_type(others, t)
					if not primary.is_empty():
						break
				if primary.is_empty() and game.steps_left == 0 and not me["jailed"]:
					primary = _best_move_die(mine)
					if not primary.is_empty():
						others.append(primary)   # 아래에서 주 단추로 빠진다
				for t in ["end_move", "end_turn"]:
					if primary.is_empty():
						primary = _take_type(others, t)
			else:
				title = "동 료 차 례"
				hint = "%s의 차례입니다." % _name(game.current)
		"choice":
			title = "선 택"
			hint = "%s가 고르는 중입니다." % _name(int(game.pending["player"])) if int(game.pending["player"]) != human else "선택 창에서 고르세요."
		"over":
			title = "작 전 종 료"
	if _playing:
		hint = "…"
	_act_title.text = title
	_act_hint.text = hint
	_act_hint.tooltip_text = hint
	# 주 버튼
	var pb := UiKit.button("", func(): pass, 21, "primary")
	pb.custom_minimum_size = Vector2(290, 54)
	pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pb.add_theme_constant_override("icon_max_width", 26)
	pb.add_theme_constant_override("h_separation", 10)
	if not primary.is_empty() and not _playing:
		pb.text = _label(primary) if primary["type"] != "move_die" else "주사위 %d로 이동" % game.die_value(int(primary["die"]))
		pb.icon = UiKit.ui_icon(_icon(primary) + "_light")
		var pa: Dictionary = primary
		_primary_action = pa
		pb.pressed.connect(func(): _act(pa))
		_shown_actions.append(primary)
		var key := UiKit.label("Space", 11, Color("#fff5e6"))
		var ks := Style.flat(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), 1, 3, 0)
		ks.content_margin_left = 5
		ks.content_margin_right = 5
		key.add_theme_stylebox_override("normal", ks)
		pb.add_child(key)
		key.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		key.position.x -= 12
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		pb.text = "기다리는 중"
		pb.disabled = true
	_act_row.add_child(pb)
	# 보조 버튼
	var secs := []
	if not extra_btn.is_empty() and not _playing:
		secs.append({"text": extra_btn[0], "icon": "swap", "cb": extra_btn[1], "tip": "동료 중 한 명이 먼저 차례를 합니다."})
	if not _playing:
		for a in others:
			if a == primary:
				continue
			var aa: Dictionary = a
			secs.append({"text": _label(a), "icon": _icon(a), "cb": func(): _act(aa), "action": a})
	for i in mini(secs.size(), SECONDARY_MAX):
		_act_row.add_child(_sec_btn(secs[i]))
	if secs.size() > SECONDARY_MAX:
		var more := MenuButton.new()
		more.text = "더 보기 (%d)" % (secs.size() - SECONDARY_MAX)
		more.flat = false
		Style.style_button(more, "paper")
		more.custom_minimum_size = Vector2(0, 54)
		more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pm := more.get_popup()
		var rest: Array = secs.slice(SECONDARY_MAX)
		for i in rest.size():
			pm.add_item(rest[i]["text"], i)
			if rest[i].has("action"):
				_shown_actions.append(rest[i]["action"])
		pm.id_pressed.connect(func(id): rest[id]["cb"].call())
		_act_row.add_child(more)
	else:
		for i in range(secs.size(), SECONDARY_MAX):
			var blank := UiKit.button("", func(): pass, 12, "paper")
			blank.disabled = true
			blank.custom_minimum_size = Vector2(0, 54)
			blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_act_row.add_child(blank)


func _sec_btn(s: Dictionary) -> Button:
	var b := UiKit.button(s["text"], s["cb"], 12, "paper")
	if s.get("icon", "") != "":
		b.icon = UiKit.ui_icon(s["icon"])
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 22)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 54)
	b.clip_text = true
	b.tooltip_text = s.get("tip", s["text"])
	if s.has("action"):
		_shown_actions.append(s["action"])
	return b


func _take_type(list: Array, t: String) -> Dictionary:
	for a in list:
		if a["type"] == t:
			return a
	return {}


func _best_move_die(mine: Array) -> Dictionary:
	## 주 단추용: 가장 큰 눈으로 이동
	var best: Dictionary = {}
	for a in mine:
		if a["type"] == "move_die" and (best.is_empty() or game.die_value(int(a["die"])) > game.die_value(int(best["die"]))):
			best = a
	return best


func _icon(a: Dictionary) -> String:
	match a["type"]:
		"start_day", "move_die", "scene_check", "use_intel": return "dice"
		"give_die": return "give"
		"begin_turn", "end_move", "end_turn", "scene_pay": return "end"
		"escape": return "escape"
		"ability": return "ability"
		"give_item": return "give"
		"decoy": return "decoy"
		"use_item": return "swap"
	return "swap"


func _refresh_dice(mine: Array) -> void:
	## 내 작전 주사위. 누르면 그 주사위로 할 수 있는 일(이동·바치기·건네기)이 작은 메뉴로 뜬다.
	var idx: Array = []
	for i in game.op_dice.size():
		if int(game.op_dice[i]["owner"]) == human:
			idx.append(i)
	if idx.is_empty() or not game.phase in ["plan", "day", "turn", "choice"]:
		_dice_row.visible = false
		return
	_dice_row.visible = true
	for i in idx:
		var d: Dictionary = game.op_dice[i]
		var acts := []
		for a in mine:
			if (a["type"] in ["move_die", "give_die"] or (a["type"] == "scene_pay" and a["what"] == "die")) and int(a["die"]) == i:
				acts.append(a)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var die := DieFace.new()
		die.value = int(d["value"])
		die.mine = not acts.is_empty() and not _playing
		die.used = d["used"]
		die.custom_minimum_size = Vector2(44, 44)
		if die.mine:
			die.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			die.tooltip_text = "눌러서: " + " / ".join(acts.map(func(a): return _label(a)))
			var at := acts.duplicate()
			die.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_die_menu(at))
			for a in acts:
				_shown_actions.append(a)
		v.add_child(die)
		var l := UiKit.text("씀" if d["used"] else ("이동 %d" % game.move_value(game.players[human], i) if game.phase == "turn" else "내 주사위"), 11, Style.INK_3, false, 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		_dice_row.add_child(v)
	var tip := UiKit.text("주사위 하나 = 이동(눈만큼) · 작전 판정(눈 + 주사위 1개)\n장면 바치기 · 같은 칸 동료에게 건네기 (하루 1번)\n남은 주사위는 밤에 사라집니다", 11, Style.INK_3, false)
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dice_row.add_child(tip)


func _die_menu(acts: Array) -> void:
	if acts.size() == 1:
		_act(acts[0])
		return
	var pm := PopupMenu.new()
	add_child(pm)
	for k in acts.size():
		pm.add_item(_label(acts[k]), k)
	pm.id_pressed.connect(func(id): _act(acts[id]))
	pm.popup_hide.connect(pm.queue_free)
	pm.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


class DieFace extends Control:
	## 주사위 한 개 (점 눈금 대신 큰 숫자, v1 종이 질감에 맞춘 흰 주사위)
	var value := 1
	var big := true
	var mine := false   # 지금 누를 수 있음
	var taken := false
	var used := false
	var carry := false

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 6))
		if mine:
			r.position.y -= 4
		var a := 0.45 if taken or used else 1.0
		draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0.29, 0.25, 0.2, a))
		draw_rect(r, Color(Color("#fff1e8") if mine else Color.WHITE, a))
		var border := Color("#a83a2c") if mine else (Style.GOLD if carry else Style.INK)
		draw_rect(r, Color(border, a), false, 3.0 if mine or carry else 2.0)
		if mine:
			draw_rect(r.grow(3), Color(Style.GOLD_HI, 0.8), false, 2.0)
		var font := Style.serif(900)
		var fs := int(r.size.y * 0.62)
		var t := str(value)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, r.get_center() + Vector2(-w / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Style.INK, a))


# ================================================================ 화면 갱신

func _refresh() -> void:
	_top.refresh()
	_refresh_roster()
	_refresh_mid()
	_refresh_hand()
	_refresh_actions()
	_ticker.refresh()


func _refresh_panels() -> void:
	## 연출 중에도 정보 패널은 엔진 상태로 맞춘다 (행동 단추는 연출이 끝난 뒤에)
	_top.refresh()
	_refresh_roster()
	_refresh_mid()
	_refresh_hand()


# ================================================================ 진행

func _act(a: Dictionary) -> void:
	if not _started or _playing or _paused or game.phase == "over":
		return
	a = a.duplicate()
	a["player"] = int(a.get("player", human))
	Sfx.play("click")
	if game.apply(a):
		_pump()
	else:
		push_warning("받아들여지지 않은 액션: %s" % str(a))


func _pump() -> void:
	for e in game.events:
		if e["kind"] == "reveal":
			_board.hidden_tiles[e["pos"]] = true
		_queue.append(e)
	game.events.clear()
	if not _playing:
		_play_queue()


func _play_queue() -> void:
	_playing = true
	_board.interactive = false
	_refresh_actions()
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		await _play_event(e)
	_playing = false
	_board.sync_from_game()
	_board.interactive = true
	_refresh()
	_after_queue()


func _after_queue() -> void:
	if game.phase == "over":
		await get_tree().create_timer(0.6).timeout
		finished.emit()
		return
	if not _walk.is_empty():
		if game.phase == "turn" and game.current == human and game.steps_left > 0:
			var nxt: Vector2i = _walk.pop_front()
			if game.can_step(game.players[human], nxt):
				_act({"type": "step", "to": nxt})
				return
		_walk.clear()
	if game.phase == "choice" and int(game.pending["player"]) == human and not _auto:
		_show_choice()
		return
	if _ai_actor() >= 0:
		_ai_waiting = true
		_ai_timer = AI_DELAY * _mult()


func _process(delta: float) -> void:
	if _ai_waiting and not _playing and not _paused:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_waiting = false
			_ai_step()


func _ai_actor() -> int:
	## 지금 AI가 둘 차례면 그 요원 id, 사람이 둘 차례면 -1
	if game.phase == "over":
		return -1
	if _auto:
		return GameAIV2.next_actor(game)
	match game.phase:
		"choice":
			var pid := int(game.pending["player"])
			return -1 if pid == human else pid
		"turn":
			return -1 if game.current == human else game.current
		"plan":
			for p in game.players:
				if p["id"] == human:
					continue
				var a := GameAIV2.decide(game, p["id"])
				if _plan_move_ok(p, a):
					return p["id"]
			return -1
		"day":
			var me: Dictionary = game.players[human]
			if game.can_begin_turn(me) and not _let_allies:
				return -1
			for a in game.legal_actions():
				if a["type"] == "begin_turn" and int(a["player"]) != human:
					return int(a["player"])
			return -1
	return -1


func _plan_move_ok(p: Dictionary, a: Dictionary) -> bool:
	## 아침 계획에서 AI가 둘 만한 수인가: 아침 능력·아이템만 (하루 시작은 사람이 누른다)
	if a.is_empty() or int(a.get("player", -1)) != p["id"]:
		return false
	return a["type"] in ["use_item", "ability"]


func _ai_step() -> void:
	var pid := _ai_actor()
	if pid < 0:
		_refresh()
		return
	var a: Dictionary
	if _auto:
		a = GameAIV2.decide(game, pid)
	elif game.phase == "day":
		# 동료끼리의 순서: AI가 정하되 사람은 빼고
		var best := -1
		var nxt := GameAIV2.next_actor(game)
		for x in game.legal_actions():
			if x["type"] == "begin_turn" and int(x["player"]) != human:
				if best < 0 or int(x["player"]) == nxt:
					best = int(x["player"])
		a = {"type": "begin_turn", "player": best}
		_let_allies = false
	else:
		a = GameAIV2.decide(game, pid)
	if a.is_empty():
		return
	if game.apply(a):
		_pump()


# ================================================================ 연출

func _play_event(e: Dictionary) -> void:
	var m := _mult()
	var k: String = e["kind"]
	match k:
		"move":
			Sfx.play("step", 0.1, 0.5)
			await _board.animate_move(int(e["player"]), e["from"], e["to"], 0.13 * m)
		"reveal":
			Sfx.play("flip", 0.1, 0.6)
			await _board.reveal(e["pos"], 0.22 * m)
		"police":
			if _board.police_changed(e["police_snap"]):
				await _board.animate_police(e["police_snap"], 0.28 * m)
		"dice":
			await _fx.roll_dice(e, m)
		"banner":
			await _fx.banner(str(e["text"]), str(e["tone"]), m)
		"morning":
			Sfx.play("day")
			await _fx.banner("%d일째 아침" % int(e["day"]), "info", m, "리더: %s · 남은 날 %d" % [_name(int(e["leader"])), game.rounds_left])
		"threat":
			var t: Dictionary = game.data.threat(str(e["id"]))
			Sfx.play("alert")
			await _fx.banner("일제 위협 · " + str(t.get("name", "")), "bad" if t.get("tone", "bad") == "bad" else "info", m, str(t.get("text", "")))
		"jail":
			await _board.animate_move(int(e["player"]), e["from"], e["to"], 0.25 * m)
		"mission_done":
			Sfx.play("score")
			_fx.toast("미션 성공 · %s (%s)" % [game.mission_def(str(e["id"])).get("name", ""), _name(int(e["player"]))], "good")
		"saga_done":
			Sfx.play("success")
			_fx.toast("사연을 이룸 · %s — %s" % [_name(int(e["player"])), game.data.saga(str(e["id"])).get("name", "")], "good")
		"scene":
			var card: Dictionary = game.current_scene()
			await _fx.banner("장면 %d/%d · %s" % [int(e["index"]) + 1, game.scenes.size(), card.get("name", "")], "info", m, _cond_text(card.get("condition", {}), card))
		"scene_break":
			Sfx.play("success")
		"launch":
			Music.play("tension")
		"confiscate":
			Sfx.play("fail")
			var lost: Array = e["items"].map(func(id): return str(game.item_def(str(id)).get("name", "")))
			_fx.toast("%s: 투옥되어 아이템 압수 · %s" % [_name(int(e["player"])), ", ".join(lost)], "bad")
		"card":
			if str(e.get("deck", "")) == "item" and int(e.get("player", -1)) == human and str(e.get("id", "")) != "bomb":
				_fx.toast("아이템 획득 · %s" % game.item_def(str(e["id"])).get("name", ""), "info")
			elif str(e.get("deck", "")) == "event":
				var ev: Dictionary = game.data.event(str(e["id"]))
				_fx.toast("이벤트 · %s — %s" % [ev.get("name", ""), ev.get("text", "")], "info")
		"dice_rolled":
			Sfx.play("dice", 0.1, 0.6)
		"die_given":
			if int(e["target"]) == human:
				_fx.toast("%s이(가) 주사위 %d을(를) 건넸습니다" % [_name(int(e["player"])), int(e["value"])], "good")
	if e.has("players_snap"):
		_board.apply_players_snap(e["players_snap"])
	if k in ["morning", "threat", "dice_rolled", "die_used", "die_given", "day_start", "mission_done", "launch", "scene", "scene_break", "confiscate",
			"saga_done", "jail", "rescue", "intel", "ready", "exposure", "turn", "night"]:
		_refresh_panels()
	_ticker.refresh()


# ================================================================ 입력

func _on_cell(c: Vector2i) -> void:
	if _playing or _paused:
		return
	# 선택: 칸 고르기
	if game.phase == "choice" and int(game.pending["player"]) == human and game.pending["kind"] in ["pick_cell", "hop"]:
		for o in game.pending["options"]:
			if o["value"] is Vector2i and o["value"] == c:
				_choice.visible = false
				_board.pick_cells = []
				_act({"type": "choose", "value": c})
				return
		return
	if game.phase != "turn" or game.current != human:
		return
	var me: Dictionary = game.players[human]
	if game.can_step(me, c):
		_act({"type": "step", "to": c})
		return
	var path := _board.preview_path()
	if not path.is_empty() and path[-1] == c:
		_walk = path.duplicate()
		var first: Vector2i = _walk.pop_front()
		_act({"type": "step", "to": first})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_pause()
		elif event.keycode == KEY_SPACE and not _primary_action.is_empty() and not _playing and not _paused and not _choice.visible:
			_act(_primary_action)


# ================================================================ 문장

func _name(pid: int) -> String:
	if pid < 0 or pid >= game.players.size():
		return "-"
	var p: Dictionary = game.players[pid]
	return ("나 (%s)" % game.char_def(p).get("name", "")) if pid == human else str(game.char_def(p).get("name", p["name"]))


func _where_text(w: String) -> String:
	if w in GameDataV2.BASE_IDS:
		return "거점 안"
	return {"inside": "거점 안", "adjacent": "거점 옆 칸", "inside_or_adjacent": "거점 안이나 옆 칸"}.get(w, w)


func _cond_text(c: Dictionary, card := {}) -> String:
	## 장면 조건을 문장으로 (데이터의 kind만 보고 만든다)
	var where := _where_text(str(c.get("where", card.get("where", "inside"))))
	match str(c.get("kind", "")):
		"check":
			var nm: String = {"generic": "판정", "lock": "자물쇠 판정", "assassin": "암살 판정", "evade": "회피 판정"}.get(str(c.get("check", "")), "판정")
			return "%s에서 %s %d 이상" % [where, nm, int(c.get("target", game.data.rules["checks"].get(str(c.get("check", "")), 9)))]
		"check_pair":
			return "%d명이 같은 날 %s에서 회피 판정 성공" % [int(c.get("count", 2)), where]
		"dice":
			return "%s에서 아침 주사위 합 %d 이상을 바침" % [where, int(c.get("sum", 0))]
		"pay_item":
			return "%s에서 아이템 %d장을 바침" % [where, int(c.get("count", 1))]
		"pay_bomb":
			return "%s에서 폭탄 %d개를 바침%s" % [where, int(c.get("count", 1)), " (나눠 바쳐도 됨)" if c.get("split", false) else ""]
		"people":
			return "%d명이 같은 날 %s에서 차례를 마침" % [int(c.get("count", 2)), where]
		"hold":
			return "%d명이 %s에서 %d밤을 넘김" % [int(c.get("count", 1)), where, int(c.get("days", 1))]
		"jailed_here":
			return "결행 거점 감옥에 요원이 갇혀 있음"
		"any_of":
			var parts := []
			for o in c.get("options", []):
				parts.append(_cond_text(o, card))
			return " 또는 ".join(parts)
		"all_of":
			var parts2 := []
			for o in c.get("options", []):
				parts2.append(_cond_text(o, card))
			return " 그리고 ".join(parts2)
	return str(c.get("kind", ""))


func _label(a: Dictionary) -> String:
	var me: Dictionary = game.players[human]
	match a["type"]:
		"start_day": return "하루 시작"
		"begin_turn": return "내 차례 시작"
		"end_move": return "이동 마치기" if game.steps_left > 0 else "차례 마치기"
		"end_turn": return "차례 넘기기"
		"escape": return "탈옥 시도"
		"use_item":
			return "[%s] 사용" % game.item_def(str(me["items"][int(a["index"])])).get("name", "")
		"ability":
			var ab := game.ability_def(me)
			if a.has("target"):
				return "능력 「%s」 → %s" % [ab.get("name", ""), _name(int(a["target"]))]
			return "능력 「%s」" % ab.get("name", "")
		"give_item":
			return "[%s] → %s 건네기" % [game.item_def(str(me["items"][int(a["index"])])).get("name", ""), _name(int(a["to"]))]
		"decoy":
			return "미끼: %s의 경찰을 내 쪽으로" % _name(int(a["from"]))
		"move_die":
			var mv := game.move_value(me, int(a["die"]))
			return "주사위 %d로 이동 (+%d칸)" % [game.die_value(int(a["die"])), mv]
		"give_die":
			return "주사위 %d → %s에게 건네기" % [game.die_value(int(a["die"])), _name(int(a["target"]))]
		"scene_check":
			return "장면 판정"
		"scene_pay":
			match a["what"]:
				"die": return "주사위 %d 장면에 바치기" % game.die_value(int(a["die"]))
				"item": return "[%s] 바치기" % game.item_def(str(me["items"][int(a["index"])])).get("name", "")
				"bomb": return "폭탄 바치기"
		"use_intel":
			return "첩보 토큰: 판정 +%d" % int(game.data.rules["intel_token"]["check_bonus"]) if a["mode"] == "check" \
				else "첩보 토큰: 주사위 조건 −%d" % int(game.data.rules["intel_token"]["dice_reduce"])
	return str(a["type"])


# ================================================================ 선택 창 · 메뉴

func _show_choice() -> void:
	var pd: Dictionary = game.pending
	var kind: String = pd["kind"]
	if kind in ["pick_cell", "hop"]:
		var cells := []
		for o in pd["options"]:
			if o["value"] is Vector2i:
				cells.append(o["value"])
		_board.pick_cells = cells
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var panel := UiKit.paper_panel(22)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	box.add_child(UiKit.title({"launch_vote": "결행 투표", "saga_keep": "남길 사연", "reroll": "다시 하기", "check_die": "판정 주사위", "discard": "버릴 아이템"}.get(kind, "선택"), Style.FS_H3))
	box.add_child(UiKit.text(str(pd.get("prompt", "")), Style.FS_BODY))
	if kind in ["pick_cell", "hop"]:
		box.add_child(UiKit.text("보드에서 빨간 점선 칸을 눌러도 됩니다.", 14, Style.INK_3))
	for o in pd["options"]:
		var val = o["value"]
		var label := str(o.get("label", str(val)))
		if kind == "saga_keep":
			var s: Dictionary = game.data.saga(str(val))
			label = "%s — %s" % [s.get("name", ""), s.get("condition_text", "")]
		if kind in ["check_die", "reroll"] and not game.check.is_empty():
			var sv := str(val)
			var dv := 0
			if sv.begins_with("die:"):
				dv = game.die_value(int(sv.substr(4)))
			elif sv == "grant":
				dv = int(game.check.get("die_value", 0))
			if sv != "no":
				label += " · 성공 %d%%" % roundi(game.check_chance(game.check, dv) * 100.0)
		var b := UiKit.button(label, func():
			_choice.visible = false
			_board.pick_cells = []
			_act({"type": "choose", "value": val}), 16, "paper")
		box.add_child(b)
	_choice.show_with(panel)


func _pause() -> void:
	if _paused:
		return
	_paused = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var panel := UiKit.paper_panel(24)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("일시 정지", Style.FS_H3))
	box.add_child(UiKit.button("계속하기", func():
		_paused = false
		_choice.visible = false
		_after_queue(), 17, "paper"))
	var fast := CheckButton.new()
	fast.text = "연출 빠르게"
	fast.button_pressed = _fast
	fast.add_theme_color_override("font_color", Style.INK)
	fast.toggled.connect(func(on): _fast = on)
	box.add_child(fast)
	box.add_child(UiKit.button("규칙 요약", func():
		_paused = false
		_show_rules(), 17, "paper"))
	box.add_child(UiKit.button("메인 메뉴로 (이 판은 저장되지 않음)", func():
		_choice.visible = false
		back_to_title.emit(), 17, "paper"))
	_choice.show_with(panel)


func _show_rules() -> void:
	if _paused:
		return
	_paused = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var panel := UiKit.paper_panel(24)
	panel.custom_minimum_size = Vector2(720, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("v2 규칙 요약", Style.FS_H3))
	var lines := [
		"하루: 아침에 위협 카드 → (1막) 결행 투표 → 공개 미션 줄 채우기 → 팀 주사위. 팀 주사위에서 하나씩 골라 오늘 이동으로 씁니다. 남은 주사위는 예비입니다.",
		"차례는 자유 순서입니다. 아직 안 한 사람 중 누구든 합니다. 경찰은 각자 차례 끝에 자기가 쫓는 요원 쪽으로 움직입니다.",
		"1막: 공개 미션을 이뤄 결행 준비를 %d까지 올리면 아침에 결행 투표가 열립니다. 남은 날이 %d일이 되면 강제로 결행합니다." % [int(game.data.rules["launch_min"]), int(game.data.rules["forced_launch_days_left"])],
		"2막: 첩보가 가장 많은 거점을 칩니다. 장면을 하나씩 돌파하고 마지막 장면을 돌파하면 대성공입니다. 첩보는 토큰이 되어 판정 +1 또는 주사위 조건 −2로 씁니다.",
		"개인 사연: 비밀입니다. 이루면 즉시 보상을 받습니다.",
		"투옥: 노출이 오르고, 들고 있던 아이템 1장을 무작위로 압수당합니다 (폭탄은 그대로). 동료가 그 거점에 들어오면 구출됩니다.",
	]
	for l in lines:
		box.add_child(UiKit.text("· " + l, 15))
	box.add_child(UiKit.button("닫기", func():
		_paused = false
		_choice.visible = false
		_after_queue(), 17, "paper"))
	_choice.show_with(panel)


# ================================================================ 시험용 조회

func is_idle() -> bool:
	## 연출·AI 대기가 없고 사람 입력을 기다리는 중인가 (tests/v2_ui_test.gd)
	return _started and not _playing and not _ai_waiting and not _paused and game.phase != "over"


func ui_offers(a: Dictionary) -> bool:
	## 이 액션을 사람이 화면에서 할 수 있는가: 보드 클릭 · 주사위 · 선택 창 · 행동 단추(더 보기 포함)
	match a["type"]:
		"step":
			return game.phase == "turn" and game.current == human
		"choose":
			return _choice.visible or not _board.pick_cells.is_empty()
	return a in _shown_actions


func press_allies_first() -> void:
	_let_allies = true
	_after_queue()


func choose_now(value) -> void:
	_choice.visible = false
	_board.pick_cells = []
	_act({"type": "choose", "value": value})


func act_now(a: Dictionary) -> void:
	_act(a)


# ================================================================ 큰 카드 (마우스 올림)

func _char_info(p: Dictionary) -> Dictionary:
	var ch: Dictionary = game.char_def(p)
	var fac: String = str(game.data.characters.get("factions", {}).get(ch.get("faction", ""), {}).get("name", ""))
	var secs := [["특성 (늘)", str(ch.get("trait_text", ""))], ["능력 (하루 1번)", str(ch.get("ability_text", ""))]]
	for c in _chips(p):
		if c[0] == "리더" or c[0] == "추격당함" or str(c[0]).begins_with("감옥"):
			secs.append([str(c[0]), str(c[3]), Style.SEAL if c[2] == Style.SEAL else Style.INK_3])
	var band := "나" if p["id"] == human else "동 료"
	return {"band": band, "color": Style.seat(p["id"]),
		"art": _board.faction_texture(str(ch.get("faction", ""))), "name": str(ch.get("name", "")),
		"sub": "%s · %s" % [fac, ch.get("origin", "")], "sections": secs}


func _mission_info(id: String) -> Dictionary:
	var m: Dictionary = game.mission_def(id)
	var type := str(m.get("type", ""))
	var td: Dictionary = game.mission_type_def(type)
	var coop := td.get("ready") == null
	var ready := int(m.get("ready", td.get("ready", 0)))
	var secs := [["이루는 법", str(m.get("how", td.get("how", "")))], ["보상", str(m.get("text", ""))]]
	if not coop:
		secs.append(["결행 준비", "+%d · 결행 준비가 %d가 되면 아침마다 결행 투표가 열립니다." % [ready, int(game.data.rules["launch_min"])]])
	else:
		secs.append(["협동 미션", "결행 준비는 오르지 않지만 모두에게 도움이 되는 보상을 줍니다."])
	if bool(m.get("loud", td.get("loud", false))):
		secs.append(["시끄러움", "이루면 노출이 오릅니다.", Style.SEAL])
	return {"band": "미 션 · " + str(td.get("name", "")), "color": Color("#2f7f7a") if coop else Style.MISSION,
		"art": load(MISSION_ART.get(type, MISSION_ART["coop"])), "name": str(m.get("name", "")), "sections": secs}


func _scene_info(card: Dictionary, i: int) -> Dictionary:
	var last := i == game.scenes.size() - 1
	var state := "돌파함"
	if i == game.scene_index:
		state = "지금 장면"
	elif i > game.scene_index:
		state = "마지막 장면" if last else "아직 모르는 장면"
	var sub := "%d / %d · %s" % [i + 1, game.scenes.size(), state]
	if i > game.scene_index and not last:
		return {"band": "결 행 장 면", "color": Style.INK_3, "name": "?", "sub": sub,
			"sections": [["", "앞 장면을 돌파하면 뒤집혀 드러납니다."]]}
	var wh := str(card.get("where", ""))
	var where: String = {"adjacent": "거점 옆 칸", "inside": "거점 안", "inside_or_adjacent": "거점 안이나 옆 칸"}.get(wh, wh)
	var secs := [["조건", _cond_text(card.get("condition", {}), card)]]
	if where != "":
		secs.append(["자리", where])
	if i == game.scene_index:
		var need := game.scene_need()
		var parts := []
		for key in need:
			parts.append("%s %d" % [{"dice": "주사위 합", "item": "아이템", "bomb": "폭탄", "check_pair": "판정 성공", "people": "사람", "hold": "밤"}.get(key, key), int(need[key])])
		if not parts.is_empty():
			secs.append(["남은 것", ", ".join(parts), Style.GOOD])
	secs.append(["여기서 멈추면", str(card.get("stop_text", "")), Style.SEAL])
	var col := Style.GOLD
	if last:
		col = Style.SEAL
	elif i < game.scene_index:
		col = Style.MISSION
	return {"band": "결 행 장 면", "color": col, "name": str(card.get("name", "")), "sub": sub, "sections": secs}


func _saga_info(id: String, pr: Dictionary, done: bool) -> Dictionary:
	var s: Dictionary = game.data.saga(id)
	return {"band": "사 연 · 이룸" if done else "사 연 · 비밀", "color": SAGA_COL, "art": load("res://assets/cards/event_back.png"),
		"name": str(s.get("name", "")), "sub": "진행 %d / %d" % [int(pr["have"]), int(pr["need"])],
		"sections": [["", str(s.get("story", ""))], ["조건", str(s.get("condition_text", ""))], ["보상", str(s.get("reward_text", ""))],
			["", "이룬 사연입니다." if done else "나만 봅니다. 이루면 공개됩니다."]]}


func _threat_info() -> Dictionary:
	if game.threat_today == "":
		return {}
	var t: Dictionary = game.data.threat(game.threat_today)
	var secs := [["오늘", str(t.get("text", ""))]]
	var peek := game.threat_preview()
	for k in peek.size():
		var nt: Dictionary = game.data.threat(str(peek[k]))
		secs.append([["내일", "모레", "글피"][mini(k, 2)] + " · " + str(nt.get("name", "")), str(nt.get("text", ""))])
	return {"band": "일 제 위 협", "color": Style.INK, "art": load("res://assets/ui/police.png"), "name": str(t.get("name", "")), "sections": secs}
