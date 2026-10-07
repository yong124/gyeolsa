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
	"bomb": "res://assets/tiles/bomb.png", "work": "res://assets/tiles/sabotage.png", "contact": "res://assets/tiles/station.png",
	"lurk": "res://assets/tiles/check.png", "coop": "res://assets/tiles/start.png", "op": "res://assets/tiles/assassin.png"}
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
var _ai_first := true             # 낮의 순서: AI 동료가 먼저 하고 내가 마지막에 한다 (토글)
var _auto := false                # 자동 진행 (내 자리도 AI가 둠, 화면 확인·캡처용)
var _training := false            # 훈련 작전 (안내 단계, 저장하지 않음)
var _saved_day := -1              # 이 날 아침에 자동 저장했는가
var _right_h := 0.0               # 오른쪽 패널이 받은 높이 (작전 기록 띠 위까지)

var _board: BoardViewV2
var _frame: PanelContainer
var _top: TopBarV2
var _right: VBoxContainer
var _roster_box: VBoxContainer
var _rows: Array = []
var _mid_title: Label
var _mid_hint: Label
var _mid_box: Container
var _ops_row: HBoxContainer
var _hand_hint: Label
var _hand_row: HBoxContainer
var _act_title: Label
var _act_hint: Label
var _dice_row: HBoxContainer
var _act_row: HBoxContainer
var _status_lbl: Label            # 남은 주사위 · 공짜 행동(아이템·능력) 상태
var _menu: Control = null         # 주사위 행동 메뉴 (바깥을 누르면 닫힘)
var _tip: PanelContainer          # 첫 판 안내 말풍선
var _tip_lbl: Label
var _tip_title: Label             # 훈련 작전 안내의 제목
var _tip_step: Label              # 훈련 작전 안내의 단계 번호
var _tip_key := ""
var _tips_seen := {}
var _ticker: LogTickerV2
var _fx: FxLayer
var _cine: CinemaV2              # 컷신 · 화면 효과 (V 연출)
var _atmos: AtmosV2              # 보드 분위기: 빛 · 날씨 (V 연출)
var _ended := false               # 끝 연출(만세 · 흑백)을 이미 했는가
var _mission_cards := {}          # 미션 id → 미션 줄 카드 (이루면 그 카드에 도장)
var _last_exposure := -1          # 노출이 오를 때만 붉은 비네트
var _choice: Overlay
var _peek: CardPeekV2   # 마우스를 올리면 뜨는 큰 카드
var _shown_actions: Array = []    # 지금 화면에 단추로 나온 액션 (시험용)
var _primary_action: Dictionary = {}  # 주 버튼 액션 (스페이스)


func _init(g: RulesV2, human_id := 0, meta_info := {}) -> void:
	game = g
	human = human_id
	game.human = human_id   # 결행 혜택은 사람이 고른다
	meta = meta_info
	_auto = bool(meta.get("autoplay", false))
	_training = bool(meta.get("training", false))
	_fast = _auto


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	_board.sync_from_game()
	_refresh()
	Music.play("main")
	if bool(meta.get("opening", false)) and not _auto:
		meta.erase("opening")   # 이어하기로 다시 열 때는 보이지 않게
		await _cine.slides(opening_slides(), 1.0)
	_started = true
	_pump()


static func opening_slides() -> Array:
	## 오프닝 4컷 (V 연출). 그림이 하나라도 없으면 빈 목록(오프닝 없이 시작)
	var lines := [
		["1945년 8월, 경성.", "해방은 바다 건너에서 오고 있었다. 우리 손으로 문을 열고 싶었다."],
		["광복군, 의용대, 의병, 지하조직.", "서로 다른 넷이 한 방에 모였다."],
		["형무소, 군영, 경찰서, 총독부.", "일제의 심장부 한 곳을 골라 들이친다."],
		["남은 날은 열하루.", "결사(結社)."],
	]
	var out := []
	for i in lines.size():
		var t := ArtV2.get_tex("cut", "opening_%d" % (i + 1))
		if t == null:
			return []
		out.append({"tex": t, "lines": lines[i]})
	return out


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
	_right.add_theme_constant_override("separation", 5)   # 패널 사이 (높이 900에 네 패널이 들어가게)
	add_child(_right)

	# 요원 명부
	var roster := _panel("요 원 명 부", "마우스를 올리면 특성 · 능력")
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 2)
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
	_ops_row = HBoxContainer.new()
	_ops_row.add_theme_constant_override("separation", 8)
	mid[1].add_child(_ops_row)

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
	_status_lbl = UiKit.text("", 12, Style.INK_2, false, 700)
	act[1].add_child(_status_lbl)
	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 10)
	act[1].add_child(_dice_row)
	_act_row = HBoxContainer.new()
	_act_row.add_theme_constant_override("separation", 9)
	act[1].add_child(_act_row)

	_ticker = LogTickerV2.new(game)
	add_child(_ticker)
	add_child(_ticker.drawer)

	_atmos = AtmosV2.new()
	add_child(_atmos)
	_fx = FxLayer.new()
	add_child(_fx)
	_cine = CinemaV2.new()
	add_child(_cine)
	_choice = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	add_child(_choice)
	add_child(_peek)
	_peek.attach(_top._threat, _threat_info)
	_build_tip()


func _panel(title: String, hint: String) -> Array:
	## 종이 패널: [패널, 본문 VBox, 제목 Label, 안내 Label]
	var panel := PanelContainer.new()
	var ps := Style.paper(12)
	ps.content_margin_top = 5
	ps.content_margin_bottom = 3
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
	_right_h = h - top_y - 12 - tick_h - GAP
	_right.size = Vector2(w - rx - 20, _right_h)
	_ticker.position = Vector2(rx, h - 12 - tick_h)
	_ticker.size = Vector2(w - rx - 20, tick_h)
	var dy := top_y + h * 0.18
	_ticker.drawer.position = Vector2(rx, dy)
	_ticker.drawer.size = Vector2(w - rx - 20, h - 12 - tick_h - 8 - dy)
	# 줄바꿈하는 글은 폭이 정해져야 높이가 정해진다 (안 정하면 한 글자 폭으로 재서 화면만큼 길어짐)
	_tip.custom_minimum_size = Vector2(side - 28, 0)
	if _training:
		_tip_lbl.custom_minimum_size = Vector2(side - 28 - 32, 0)
	_tip.reset_size()
	_place_tip()
	_fx.focus_center = _frame.position + _frame.size / 2.0
	_fx.board_rect = Rect2(_frame.position, _frame.size)
	_atmos.position = _frame.position + Vector2(8, 8)
	_atmos.size = _frame.size - Vector2(16, 16)
	call_deferred("_fit_right")


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
	face.tex = ArtV2.get_tex("token", str(p["character"]), _board.faction_texture(str(game.char_def(p).get("faction", ""))))
	face.full = ArtV2.has("token", str(p["character"]))
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
	for g in p["grants"]:
		var gt := _grant_text(g)
		out.append(["권리 · " + gt[0], "권", Style.GOOD, "한 번 쓰는 권리: %s (쓰면 사라집니다)" % gt[1], false])
	for cid in game.mission_row:
		if int(game.mission_state.get(cid, {}).get("holder", -1)) == p["id"]:
			out.append(["물건 · %s" % game.mission_def(str(cid)).get("name", ""), "물", Style.MISSION, "연락 미션의 물건을 들고 있습니다. 주기 마커에 들어가면 미션을 이룹니다. 잡히면 받기 마커로 돌아갑니다.", false])
	if p["saga_done"] != "":
		out.append(["사연 이룸 · %s" % game.data.saga(p["saga_done"]).get("name", ""), "✓", SAGA_COL, str(game.data.saga(p["saga_done"]).get("story", "")), false])
	elif me:
		out.append(["사연 %d장 (비밀)" % game.saga_cards(human).size(), "?", SAGA_COL, "내 사연은 손패에서 봅니다.", false])
	if p["done_today"] and game.phase in ["day", "turn", "choice"]:
		out.append(["차례 마침", "✓", Style.INK_3, "오늘 차례를 마쳤습니다.", true])
	return out


func _grant_text(g: Dictionary) -> Array:
	## 한 번 쓰는 권리 [짧은 이름, 설명]
	var scope: String = {"strike": " (결행 장면 판정에서만)", "final": " (마지막 장면 판정에서만)"}.get(str(g.get("scope", "any")), "")
	match str(g.get("kind", "")):
		"check_bonus": return ["판정 +%d" % int(g.get("value", 0)), "다음 판정에 +%d%s" % [int(g.get("value", 0)), scope]]
		"reroll": return ["다시 굴리기", "실패한 판정을 한 번 다시 굴림%s" % scope]
		"evade_auto": return ["회피 자동 성공", "다음 회피 판정이 자동으로 성공"]
		"escape_instant": return ["즉시 탈옥", "갇히면 바로 탈출"]
	return [str(g.get("kind", "")), str(g.get("kind", ""))]


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
	_mission_cards = {}
	if game.act == 1:
		_mid_title.text = "공 개 미 션 줄"
		_mid_hint.text = "누구든 이루면 결행 준비가 오릅니다 · 이룬 자리에 새 미션"
		for id in game.mission_row:
			var m: Dictionary = game.mission_def(str(id))
			var type := str(m.get("type", ""))
			var td: Dictionary = game.mission_type_def(type)
			var coop := type == "coop"
			var band := "%s · +%d" % [_spaced(str(td.get("name", "미션"))), int(m.get("ready", 0))]
			var desc := ""   # 설명은 마우스를 올리면 큰 카드로. 줄에는 진행 상황만
			var days := game.card_days_left(str(id))
			if days >= 0:
				band += " · %d일" % days
			var status := game.card_status(str(id))
			if status != "":
				desc = status
			var card := CardView.face(band, Color("#2f7f7a") if coop else Style.MISSION, _mission_art(type),
				str(m.get("name", "")), desc, 164, 92, false, 0.40, true)
			_peek.attach(card, _mission_info(str(id)))
			_mid_box.add_child(card)
			_mission_cards[str(id)] = card
		if game.mission_row.is_empty():
			_mid_box.add_child(UiKit.text("아침에 미션 줄을 채웁니다.", 14, Style.INK_3))
		_refresh_ops()
		return
	_ops_row.visible = false
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
			v.add_child(UiKit.text("지금 장면 %d / %d · %s" % [i + 1, game.scenes.size(), _scene_kind(i)], 11, Style.INK_3, false))
			v.add_child(UiKit.title(str(card.get("name", "")), 17, Style.INK))
			v.add_child(UiKit.text(_cond_text(card.get("condition", {}), card), 12, Style.INK_2))
			if game.act == 2 and int(game.counter.get("day", -1)) == game.day:
				var blocked: bool = bool(game.counter.get("blocked", false))
				v.add_child(UiKit.text("반격 막음 — 오늘 밤 버틴 날로 셈" if blocked else "반격! 이 자리에서 작전 판정 %d에 성공해야 오늘 밤 버틴 날로 셈 (못 막으면 자리에 선 요원은 회피 판정, 실패하면 투옥)" % int(game.data.rules["counter"]["target"]),
					12, Style.GOOD if blocked else Style.SEAL, false, 800))
			var need := game.scene_need()
			var parts := []
			for key in need:
				parts.append("%s %d" % [{"dice": "주사위 합", "item": "아이템", "bomb": "폭탄", "check_pair": "판정 성공", "people": "사람", "hold": "밤", "funds": "군자금"}.get(key, key), int(need[key])])
			if not parts.is_empty():
				v.add_child(UiKit.text("남은 것: " + ", ".join(parts), 12, Style.GOOD, false, 800))
		else:
			var known := last   # 마지막 장면은 공개된 카드 (결행마다 고정)
			box.add_theme_stylebox_override("panel", Style.flat(Color("#e4d6b4"), Style.SEAL if last else Color("#bba57c"), 2 if last else 1, 2, 6))
			box.custom_minimum_size = Vector2(76, 58)
			v.add_child(_center_lbl(UiKit.title(str(card.get("name", "")) if known else "?", 14, Style.SEAL if last else Style.INK_3)))
			v.add_child(_center_lbl(UiKit.text(_scene_kind(i), 11, Style.SEAL if last else Style.INK_3, false)))
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		_peek.attach(box, _scene_info(card, i))
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mid_box.add_child(box)


func _refresh_ops() -> void:
	## 일제 작전 줄: 마커가 놓인 작전 (이름 · 남은 날 · 못 막으면)
	UiKit.clear(_ops_row)
	_ops_row.visible = not game.op_row.is_empty()
	if game.op_row.is_empty():
		return
	_ops_row.add_child(UiKit.title("일제 작전", 13, Style.SEAL))
	for id in game.op_row:
		var oc: Dictionary = game.data.op_card(str(id))
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", Style.flat(Color("#fbe9e4"), Style.SEAL, 2, 2, 5))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		chip.add_child(v)
		v.add_child(UiKit.title("%s · %d일" % [oc.get("name", ""), game.card_days_left(str(id))], 13, Style.SEAL))
		var how := str(oc.get("how", ""))
		var status := game.card_status(str(id))
		v.add_child(UiKit.text(how + ((" · " + status) if status != "" else ""), 11, Style.INK_2, false))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_peek.attach(chip, _op_info(str(id)))
		_ops_row.add_child(chip)


func _scene_kind(i: int) -> String:
	## 장면 줄의 종류 이름: 진입 → 중간 → 경비 강화 → 마지막
	if i == 0:
		return "진입"
	if i == game.scenes.size() - 1:
		return "마지막"
	for c in game.data.scenes.get("reinforce", []):
		if c.get("id", "") == str(game.scenes[i]):
			return "경비 강화"
	return "중간"


func _cutin(pid: int, m: float, line := "") -> void:
	## 캐릭터 컷인: 초상 + 이름 + 대사(없으면 능력 이름). 내 요원은 왼쪽에서, 동료는 오른쪽에서
	var p: Dictionary = game.players[pid]
	var ch: Dictionary = game.char_def(p)
	if line == "":
		line = str(ch.get("quote", ch.get("ability_text", "")))
	await _cine.cutin(ArtV2.get_tex("char", str(p["character"])), str(ch.get("name", "")), line, Style.seat(pid), m, pid == human)


func _hover_lift(b: Control) -> void:
	## 손맛: 마우스를 올리면 단추가 살짝 커진다 (컨테이너가 위치를 정하므로 크기로만)
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2(1.04, 1.04), 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))


func _mission_art(type: String) -> Texture2D:
	## 미션 종류 그림 (없으면 예전 타일 그림)
	return ArtV2.get_tex("mission", type, load(MISSION_ART.get(type, MISSION_ART["coop"])))


func _saga_art() -> Texture2D:
	return ArtV2.get_tex("", "saga_back", load("res://assets/cards/event_back.png"))


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
	var H := 92.0    # 손패는 이름만 보이면 된다 (설명은 마우스를 올리면 큰 카드)
	var prog := game.saga_progress(human)
	for id in game.saga_cards(human):
		var s: Dictionary = game.data.saga(str(id))
		var pr: Dictionary = prog.get(id, {"have": 0, "need": 1})
		var done: bool = me["saga_done"] == id
		var band := "사 연" if game.act == 1 or done else "남긴 사연"
		var dots := ""
		for i in int(pr["need"]):
			dots += "●" if i < int(pr["have"]) else "○"
		band += " " + dots   # 진행은 띠에 (조건 글은 마우스를 올리면 큰 카드)
		var card := CardView.face(band, SAGA_COL, _saga_art(), str(s.get("name", "")), "", W, H, false, 0.36, true)
		_peek.attach(card, _saga_info(str(id), pr, done))
		if not done:
			var tag := UiKit.stamp("비밀", 10, SAGA_COL, 12)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(tag)
			tag.position = Vector2(W - 34, 24)
		_hand_row.add_child(card)
	for i in me["items"].size():
		var it: Dictionary = game.item_def(str(me["items"][i]))
		var item_id := str(me["items"][i])
		var card := CardView.face("아 이 템", Style.ITEM, ArtV2.get_tex("item", item_id, load("res://assets/cards/item_back.png")), str(it.get("name", "")), "", W, H, false, 0.36, true)
		_peek.attach(card, {"band": "아 이 템", "color": Style.ITEM, "art": load("res://assets/cards/item_back.png"), "illus": ArtV2.get_tex("item", item_id), "name": str(it.get("name", "")),
			"sections": [["효과", str(it.get("text", ""))], ["", "같은 칸 동료에게 줄 수 있습니다." + (" 2막 장면에 아이템으로 바칠 수도 있습니다." if game.act == 2 else "")]]})
		_hand_row.add_child(card)
	for i in me["bombs"]:
		var card := CardView.face("폭 탄", BOMB_COL, load("res://assets/cards/bomb.png"), "폭탄", "", W, H, false, 0.36, true)
		_peek.attach(card, {"band": "폭 탄", "color": BOMB_COL, "art": load("res://assets/cards/bomb.png"), "name": "폭탄",
			"sections": [["쓰는 곳", "1막: 폭파 미션의 마커 칸까지 들고 가면 미션을 이룹니다.\n2막: 폭탄을 요구하는 장면에 바칩니다."]]})
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
	var extra_btns: Array = []    # [{"text", "cb", "tip", "action"?}] — 액션이 아닌 단추 (순서 정하기)
	for a in mine:
		if a["type"] in ["step", "choose"] or _die_of(a) >= 0:
			continue   # 주사위로 하는 일은 주사위를 눌러서
		others.append(a)
	match game.phase:
		"plan":
			title = "아 침 계 획"
			hint = "오늘의 작전 주사위 · 주사위 1개 = 행동 1개 · 큰 눈을 이동에 쓸지, 판정에 남길지 정하세요"
			primary = _take_type(others, "start_day")
			extra_btns.append(_order_toggle())
		"day":
			title = "누 가 먼 저 ?"
			if game.can_begin_turn(me):
				hint = "자유 순서 · 다음 차례를 고르세요 (내 차례 또는 동료 한 명)"
				primary = _take_type(others, "begin_turn")
				extra_btns.append(_order_toggle())
				for x in legal:
					if x["type"] == "begin_turn" and int(x["player"]) != human:
						var xa: Dictionary = x
						extra_btns.append({"text": "%s 차례" % _name(int(x["player"])), "icon": "swap", "action": xa,
							"cb": func(): _act(xa), "tip": "이 동료가 지금 차례를 진행합니다."})
			else:
				hint = "동료들이 움직이는 중입니다."
		"turn":
			if game.current == human:
				title = "내 차 례"
				if me["jailed"]:
					hint = "감옥 · 주사위로 탈옥 판정 %d 이상 · 면회 온 동료와 주사위를 주고받을 수 있습니다" % game.check_target("escape")
				elif game.steps_left > 0:
					hint = "이동 %d칸 남음 · 보드에서 칸을 누르면 그 길로 걸어갑니다 · 이동을 마치면 다른 행동을 고를 수 있습니다" % game.steps_left
				elif not game.my_dice(human).is_empty():
					hint = "주사위 1개 = 행동 1개 · 주사위를 눌러 이동·판정·건네기·정찰·숨기를 고르세요 · 다 하면 「차례 마치기」"
				else:
					hint = "주사위를 다 썼습니다 · 「차례 마치기」"
				if game.act == 2:
					hint += " · 장면 자리(금색 점선)에서 바치기 · 판정"
				if game.counter_active():
					hint += " · 반격! 자리에 선 요원이 작전 판정 %d에 성공해야 오늘 밤 버틴 날로 칩니다" % int(game.data.rules["counter"]["target"])
				if game.steps_left == 0:
					primary = _best_check(mine)
					if primary.is_empty():
						primary = GameAIV2._work_action(game, me, mine)
					if primary.is_empty():
						for t in ["scene_pay"]:
							primary = _take_die_type(mine, t)
							if not primary.is_empty():
								break
				if primary.is_empty() and game.steps_left == 0 and not me["jailed"]:
					primary = _best_move_die(mine)
				if not primary.is_empty():
					others.append(primary)   # 아래에서 주 단추로 빠진다
				for t in ["end_move", "end_turn"]:
					if primary.is_empty():
						primary = _take_type(others, t)
				others.sort_custom(func(x, y): return _rank(x) < _rank(y))
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
	_status_lbl.text = _status_line()
	_tip_check()
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
		pb.pressed.connect(func(): _press(pa))
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
	_hover_lift(pb)
	_act_row.add_child(pb)
	# 보조 버튼
	var secs := []
	if not _playing:
		for x in extra_btns:
			secs.append(x)
	if not _playing:
		for a in others:
			if a == primary:
				continue
			var aa: Dictionary = a
			secs.append({"text": _label(a), "icon": _icon(a), "cb": func(): _press(aa), "action": a})
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
	call_deferred("_fit_right")


func right_overflow() -> float:
	## 오른쪽 패널이 받은 높이보다 얼마나 넘치는가 (양수면 작전 기록 띠를 가림, tests/v2_ui_test.gd)
	return _right.get_combined_minimum_size().y - _right_h   # size는 최소 크기까지 늘어나므로 받은 높이와 견준다


func layout_report() -> String:
	## 오른쪽 패널별 최소 높이 (넘침을 찾을 때, tests/v2_ui_test.gd)
	var parts := []
	for c in _right.get_children():
		if c is Control and c.visible:
			parts.append("%.0f" % c.get_combined_minimum_size().y)
	var tip := _dice_row.get_node_or_null("DiceTip")
	return "패널 %s · 주사위 줄 %.0f · 행동 줄 %.0f · 안내 %s · 상태 %s" % [" / ".join(parts), _dice_row.get_combined_minimum_size().y,
		_act_row.get_combined_minimum_size().y, tip != null and tip.visible, _status_lbl.visible]


func _fit_right() -> void:
	## 넘치면 덜 중요한 줄부터 숨긴다: 고정 안내 → 상태 줄
	var tip := _dice_row.get_node_or_null("DiceTip")
	for c in [tip, _status_lbl]:
		if c == null:
			continue
		c.visible = true
	await get_tree().process_frame   # 다시 보인 줄의 최소 크기가 반영된 뒤에 잰다
	var over := right_overflow()
	if over > 0.0 and tip != null and is_instance_valid(tip):
		# 고정 안내는 주사위 줄 안에 있어 주사위(44 + 이름표) 높이보다 큰 만큼만 줄어든다
		var dice_h: float = _dice_row.get_child(0).get_combined_minimum_size().y if _dice_row.get_child_count() > 1 else 0.0
		over -= maxf(0.0, tip.get_combined_minimum_size().y - dice_h)
		tip.visible = false
	if over > 0.0:
		over -= _status_lbl.get_combined_minimum_size().y + 4
		_status_lbl.visible = false
	await get_tree().process_frame
	_right.size = Vector2(_right.size.x, _right_h)   # 숨긴 만큼 다시 줄인다


func _sec_btn(s: Dictionary) -> Button:
	var b := UiKit.button(s["text"], s["cb"], 12, "paper")
	if s.get("icon", "") != "":
		b.icon = UiKit.ui_icon(s["icon"])
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 22)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT   # 아이콘을 글자 옆에 (위에 두면 행동 줄이 74px로 높아져 패널이 넘침)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 54)
	b.clip_text = true
	b.tooltip_text = s.get("tip", s["text"])
	if s.has("action"):
		_shown_actions.append(s["action"])
	_hover_lift(b)
	return b


func _take_type(list: Array, t: String) -> Dictionary:
	for a in list:
		if a["type"] == t:
			return a
	return {}


func _order_toggle() -> Dictionary:
	## 낮의 순서: AI 동료가 먼저 / 내가 먼저 (한 번에 한 요원씩)
	return {"text": "동료 먼저 하게 함" if _ai_first else "동료 기다리게 하기", "icon": "swap", "tip": "누르면 바뀝니다. 동료 먼저 하게 함: 동료가 모두 차례를 마친 뒤 내가 합니다. 동료 기다리게 하기: 다음 차례를 내가 고릅니다 (내가 먼저 해서 주사위를 건네거나 길을 열 수 있음).",
		"cb": func():
			_ai_first = not _ai_first
			_after_queue()}


func _die_of(a: Dictionary) -> int:
	## 주사위 하나를 내는 행동이면 그 주사위 번호, 아니면 -1 (아이템·폭탄을 바칠 때는 with)
	if a.has("die"):
		return int(a["die"])
	if a.has("with"):
		return int(a["with"])
	return -1


func _rank(a: Dictionary) -> int:
	## 보조 단추 순서: 마치기 → 능력·아이템 → 나머지
	match a["type"]:
		"end_move", "end_turn": return 0
		"ability", "use_item": return 1
	return 2


func _best_check(mine: Array) -> Dictionary:
	## 주 단추용: 판정 행동 중 성공 확률이 가장 높은 것 (미션 → 탈옥 → 장면)
	for t in ["counter_check", "mission_check", "escape", "scene_check"]:
		var best: Dictionary = GameAIV2._check_action(game, game.players[human], mine, t)
		if not best.is_empty():
			return best
	return {}


func _take_die_type(list: Array, t: String) -> Dictionary:
	for a in list:
		if a["type"] == t and a.get("what", "die") == "die":
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
		"start_day", "move_die", "scene_check", "use_intel", "mission_check", "counter_check": return "dice"
		"hide": return "escape"
		"give_die": return "give"
		"begin_turn", "end_move", "end_turn", "scene_pay", "work_give": return "end"
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
			if _die_of(a) == i:
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
			die.mouse_entered.connect(func():
				die.hover = true
				Sfx.play("click", 0.3, 0.25)
				die.queue_redraw())
			die.mouse_exited.connect(func():
				die.hover = false
				die.queue_redraw())
			die.tooltip_text = "눌러서: " + " / ".join(acts.map(func(a): return _label(a)))
			var at := acts.duplicate()
			die.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_die_menu(at, i))
			for a in acts:
				_shown_actions.append(a)
		v.add_child(die)
		var l := UiKit.text("씀" if d["used"] else ("이동 %d" % game.move_value(game.players[human], i) if game.phase == "turn" else "내 주사위"), 11, Style.INK_3, false, 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		_dice_row.add_child(v)
	if Prefs.v2_tips or _training:   # 고정 안내는 첫 판과 훈련에서만
		var tip := UiKit.text("주사위 1개 = 행동 1개: 이동(눈만큼) · 작전 판정(눈 + 주사위 1개) · 바치기\n건네기 · 미끼 · 숨기 · 정찰 · 장터 — 주사위를 눌러 고르세요\n남은 주사위는 밤에 사라집니다", 11, Style.INK_3, false)
		tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tip.name = "DiceTip"
		_dice_row.add_child(tip)


func _close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	if _board != null:
		_board.reach = {}


func _die_menu(acts: Array, die := -1) -> void:
	## 주사위를 누르면 그 주사위로 할 수 있는 행동을 미리보기와 함께 보인다. 안 되는 행동은 흐리게, 이유와 함께.
	_close_menu()
	var me: Dictionary = game.players[human]
	var catcher := Control.new()
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_close_menu())
	add_child(catcher)
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu = catcher
	var panel := UiKit.paper_panel(12)
	catcher.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(430, 0)
	panel.add_child(v)
	var dv := game.die_value(die) if die >= 0 else 0
	v.add_child(UiKit.title("주사위 %d — 무엇을 할까요? (주사위 1개 = 행동 1개)" % dv if die >= 0 else "행동 고르기", 15, Style.INK))
	for a in acts:
		var aa: Dictionary = a
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var btn := UiKit.button(_label(aa), func():
			_close_menu()
			_press(aa), 14, "paper")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.mouse_entered.connect(func(): _hover_action(aa))
		btn.mouse_exited.connect(func(): _board.reach = {})
		row.add_child(btn)
		var hint := _hint(aa)
		if hint != "":
			var hl := UiKit.text("   " + hint, 11, Style.INK_3, false)
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(hl)
		v.add_child(row)
	var why := _why_not_rows(acts)
	if not why.is_empty():
		v.add_child(UiKit.text("지금은 안 되는 것", 11, Style.INK_3, false, 700))
	for w in why:
		var l := UiKit.text("   %s — %s" % [w[0], w[1]], 12, Color(Style.INK_3, 0.75), false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	v.add_child(UiKit.text("바깥을 누르면 닫힙니다", 10, Style.INK_3, false))
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var pos := get_global_mouse_position() + Vector2(10, 10)
	var sz := panel.get_combined_minimum_size()
	pos.x = clampf(pos.x, 6.0, size.x - sz.x - 6.0)
	pos.y = clampf(pos.y, 6.0, size.y - sz.y - 6.0)
	panel.position = pos


func _hover_action(a: Dictionary) -> void:
	_board.reach = {}
	if a["type"] == "move_die":
		_board.reach = game.reach_cells(game.players[human], game.move_value(game.players[human], int(a["die"])))
	_board.queue_redraw()


func _work_preview(a: Dictionary) -> String:
	var me: Dictionary = game.players[human]
	var m := game.marker_at(me["pos"])
	if m.is_empty():
		return ""
	var id := str(m["id"])
	var st: Dictionary = game.mission_state.get(id, {})
	var cond := game.card_cond(id)
	var v := game.die_value(int(a["die"]))
	match str(cond.get("mode", "")):
		"sum":
			var now := int(st.get("sum", 0)) + v
			return "합 %d → %d / %d%s" % [int(st.get("sum", 0)), now, int(st.get("need", 0)), " (이룸!)" if now >= int(st.get("need", 0)) else ""]
		"combo":
			var left: Array = st.get("left", []).duplicate()
			left.erase(v)
			return "남은 눈 %s → %s%s" % ["·".join(st.get("left", []).map(func(x): return str(x))), "·".join(left.map(func(x): return str(x))) if not left.is_empty() else "없음", " (이룸!)" if left.is_empty() else ""]
		"each":
			var rest := game.markers_of(id, "work").size() - 1
			return "마커 %d곳 남음%s" % [rest, " (이룸!)" if rest <= 0 else ""]
	return ""


func _hint(a: Dictionary) -> String:
	## 행동의 미리보기와 대가 한 줄
	var me: Dictionary = game.players[human]
	match a["type"]:
		"move_die":
			return "최대 %d칸 걷기 (중간에 멈춰도 됨) — 올려 두면 갈 수 있는 칸이 보드에 밝혀집니다" % game.move_value(me, int(a["die"]))
		"escape", "mission_check", "counter_check", "scene_check":
			var c: Dictionary = game.check_preview(me, a)
			return "낸 눈 %d + 새 주사위 1개 ≥ 목표 %d%s → 성공 %d%%. 실패하면 %s" % [game.die_value(int(a["die"])), int(c["target"]), (" (보정 %+d)" % int(c["bonus"])) if int(c["bonus"]) != 0 else "", _chance(a),
				{"escape": "다른 주사위로 또 시도할 수 있음", "mission_check": "회피 판정(7)을 해야 하고 실패하면 투옥", "counter_check": "다른 주사위로 또 시도할 수 있음", "scene_check": "다른 주사위로 또 시도할 수 있음"}[a["type"]]]
		"work_give":
			return _work_preview(a)
		"scene_pay":
			match a["what"]:
				"die":
					var need := int(game.scene_need().get("dice", 0))
					return "남은 합 %d → %d" % [need, maxi(0, need - game.die_value(int(a["die"])))]
				"funds":
					return "군자금 %d을 내고 장면을 매수 (지금 %d)" % [_funds_price(), game.funds]
				"item":
					return "아이템 1장을 내고 장면 조건을 채움 (주사위 하나도 씀)"
				"bomb":
					return "폭탄을 내고 장면 조건을 채움 (주사위 하나도 씀)"
		"give_die":
			return "하루 한 번. %s은(는) 행동이 하나 늘고 나는 하나 줆" % _name(int(a["target"]))
		"give_item":
			return "아이템 카드를 동료에게 줌 (주사위 하나를 씀)"
		"decoy":
			return "경찰을 내 쪽으로 끌어와 동료를 빼냄 — 대신 내가 쫓김"
		"hide":
			return "이번 차례 끝에 나를 쫓는 경찰이 다가오지 않음"
		"scout":
			return "눈 %d칸 안의 덮인 칸 %d곳을 골라 타일을 미리 깜 (효과는 그 칸에서 멈출 때)" % [game.die_value(int(a["die"])), int(game.data.rules["scout"]["count"])]
		"market":
			return "군자금 %d을 내고 얻음 (지금 %d)" % [_market_cost(a), game.funds]
		"ability":
			return str(game.ability_def(me).get("text", ""))
	return ""


func _market_cost(a: Dictionary) -> int:
	for o in game.data.rules["market"]["offers"]:
		if str(o["id"]) == str(a.get("offer", "")):
			return game.market_cost(game.players[human], o)
	return 0


func _why_not_rows(acts: Array) -> Array:
	## 이 주사위로 지금은 못 하는 행동과 이유 [[이름, 이유]]
	var me: Dictionary = game.players[human]
	var have := {}
	for a in acts:
		have[a["type"]] = true
	var rows := []
	if me["jailed"]:
		if not have.has("escape"):
			rows.append(["탈옥", "주사위가 없음"])
		return rows
	if not have.has("give_die") and not have.has("give_item"):
		if int(me["gives_today"]) >= int(game.data.rules["give_per_day"]):
			rows.append(["건네기", "오늘 이미 건넸음"])
		else:
			rows.append(["건네기", "같은 칸에 아직 차례를 안 한 동료가 없음"])
	if not have.has("hide"):
		rows.append(["숨기", "이미 숨었음" if me["hidden"] else "골목·주막·은신처 칸에서만 숨을 수 있음"])
	if not have.has("scout"):
		rows.append(["정찰", "범위 안에 덮인 칸이 없음"])
	if not have.has("market"):
		var mt := str(game.data.rules["market"]["tile"])
		rows.append(["장터", "장터 칸에서만 살 수 있음" if game.tile_type(me["pos"]) != mt else "군자금이 모자라거나 자리가 없음 (지금 군자금 %d)" % game.funds])
	if not game.police.is_empty() and not have.has("decoy"):
		rows.append(["미끼", "나는 쫓기고 있지 않아야 하고, 3칸 안에 쫓기는 동료가 있어야 함" if not game.police.has(human) else "이미 쫓기는 중이라 미끼를 못 씀"])
	if game.act == 1:
		var has_target := false
		var has_work := false
		for m in game.markers:
			has_target = has_target or (str(m["role"]) == "target" and str(game.card_cond(str(m["id"])).get("kind", "")) == "assassinate")
			has_work = has_work or str(m["role"]) == "work"
		if has_target and not have.has("mission_check"):
			rows.append(["표적 판정", "표적 칸에 서 있어야 함 (저격수 오는 옆 칸도 됨)"])
		if has_work and not have.has("work_give"):
			var here := game.marker_at(me["pos"])
			rows.append(["공작 바치기", "필요한 눈이 아님" if not here.is_empty() and str(here["role"]) == "work" else "공작 마커 칸에 서 있어야 함"])
	elif not have.has("scene_check") and not have.has("scene_pay"):
		rows.append(["장면 판정·바치기", "장면 자리(금색 점선 칸)에 서 있어야 함"])
	return rows


func _status_line() -> String:
	## 남은 주사위, 공짜 행동(아이템 · 능력)을 썼는지
	if game.phase != "turn" or game.current != human:
		return ""
	var me: Dictionary = game.players[human]
	var parts := ["주사위 %d개 남음" % game.my_dice(human).size()]
	parts.append("아이템 %d/%d장 씀 (공짜)" % [int(me["item_uses"]), int(game.data.rules["item_uses_per_turn"])])
	var ab: Dictionary = game.ability_def(me)
	if not ab.is_empty():
		parts.append("능력 「%s」 %s" % [ab.get("name", ""), "오늘 썼음" if me["ability_day"] == game.day else "쓸 수 있음 (공짜)" if not game.ability_targets(me).is_empty() else "지금은 못 씀"])
	if game.heavy_count(me) > 0:
		parts.append("무거운 물건: 이동 눈 −%d" % game.heavy_count(me))
	return " · ".join(parts)


func _press(a: Dictionary) -> void:
	## 단추·단축키로 누른 행동. 주사위가 남았는데 차례를 마치려면 한 번 확인한다.
	if a["type"] == "end_turn" and game.phase == "turn" and game.current == human and not game.players[human]["jailed"] and not game.my_dice(human).is_empty():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var panel := UiKit.paper_panel(22)
		panel.custom_minimum_size = Vector2(480, 0)
		panel.add_child(box)
		box.add_child(UiKit.title("차례를 마칠까요?", Style.FS_H3))
		var dv: Array = game.my_dice(human).map(func(i): return str(game.die_value(i)))
		box.add_child(UiKit.text("주사위 %s이(가) 남았습니다. 남은 주사위는 밤에 사라지고, 나를 쫓는 경찰이 다가옵니다." % ", ".join(dv), Style.FS_BODY))
		box.add_child(UiKit.button("그래도 마친다", func():
			_choice.visible = false
			_act(a), 16, "paper"))
		box.add_child(UiKit.button("계속한다", func(): _choice.visible = false, 16, "paper"))
		_choice.show_with(panel)
		return
	_act(a)


# ---- 첫 판 안내 말풍선

func _build_tip() -> void:
	_tip = PanelContainer.new()
	var st := Style.flat(Color("#fff2c8"), Style.GOLD, 2, 2, 8)
	_tip.add_theme_stylebox_override("panel", st)
	_tip.visible = false
	_tip.z_index = 20
	_tip.resized.connect(_place_tip)
	if _training:
		# 훈련 작전: 제목 · 몇 번째 단계 · 두세 줄 설명 · 「알겠습니다」
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 12
		st.content_margin_bottom = 12
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		_tip.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		_tip_title = UiKit.title("", 19, Style.SEAL_DARK)
		_tip_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_tip_title)
		_tip_step = UiKit.text("", 12, Style.INK_3, false, 700)
		head.add_child(_tip_step)
		_tip_lbl = UiKit.text("", 15, Style.INK, false, 600)
		_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(_tip_lbl)
		var ok := UiKit.button("알겠습니다", func():
			_tip.visible = false
			_tip_check(), 14, "primary")
		ok.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(ok)
		add_child(_tip)
		return
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_tip.add_child(h)
	h.add_child(UiKit.title("안내", 14, Style.SEAL))
	_tip_lbl = UiKit.text("", 14, Style.INK, false, 700)
	_tip_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(_tip_lbl)
	h.add_child(UiKit.button("확인", func(): _tip.visible = false, 12, "paper"))
	h.add_child(UiKit.button("안내 끄기", func():
		Prefs.v2_tips = false
		Prefs.save()
		_tip.visible = false, 12, "paper"))
	add_child(_tip)


const TRAINING_STEPS := [
	# [키, 제목, 글] — 조건은 _training_due()에서 본다. 앞 단계를 넘긴 뒤에 다음 단계가 뜬다(조건이 맞을 때)
	["morning", "아침 · 작전 주사위", "아침마다 요원마다 작전 주사위를 2개 굴립니다(2막은 3개). 주사위 1개 = 행동 1개입니다. 위쪽 붉은 칸은 오늘 뒤집힌 일제 위협, 오른쪽 「공개 미션 줄」은 누구든 이룰 수 있는 미션입니다. 준비가 되면 「하루 시작」을 누르세요."],
	["day", "낮 · 순서는 자유", "요원마다 하루에 한 차례씩 합니다. 순서는 자유입니다. 「내 차례 시작」으로 먼저 하거나, 동료를 먼저 보낼 수 있습니다."],
	["turn", "내 차례 · 주사위를 누르세요", "아래 주사위를 누르면 그 주사위로 할 수 있는 일이 뜹니다. 이동은 눈만큼 걷고, 작전 판정은 「낸 눈 + 새 주사위 1개」가 목표 이상이면 성공입니다. 큰 눈을 어디에 쓸지가 이 게임의 고민입니다."],
	["marker", "미션 마커", "보드의 동그란 표지가 미션 마커입니다. 마우스를 올리면 카드가 크게 뜹니다. 암살은 표적 칸에서 판정, 공작은 마커 칸에 주사위 바치기, 잠복은 곁에서 쫓기지 않고 차례 마치기처럼 종류마다 하는 일이 다릅니다. 이루면 결행 준비가 오릅니다."],
	["move", "이동", "보드에서 칸을 누르면 그 길로 걷습니다. 덮인 칸에 들어가면 타일이 뒤집히고, 이동을 마친 칸의 효과(아이템 · 이벤트 · 장터 · 감시탑 …)를 받습니다. 걸음을 다 쓰지 않고 「이동 마치기」를 해도 됩니다."],
	["check", "작전 판정", "지금 작전 판정을 할 수 있습니다. 행동 메뉴에 성공 확률이 나옵니다. 실패하면 남은 주사위로 다시 할 수 있지만, 그것도 행동 하나입니다."],
	["end", "차례 마치기", "주사위를 다 썼습니다. 「차례 마치기」를 누르면 나를 쫓는 경찰이 경계 단계만큼 다가옵니다. 골목 · 은신처 · 주막에서는 「숨기」로 경찰을 멈출 수 있습니다."],
	["chased", "경찰이 붙었습니다", "거점에 들어가거나 암살 · 폭파처럼 시끄러운 일을 하면 경찰이 붙습니다. 따라잡히면 투옥되어 아이템을 압수당하고 노출이 오릅니다. 멀리 떨어지면 따돌립니다. 동료가 「미끼」로 끌어갈 수도 있습니다."],
	["op", "일제 작전", "일제 작전이 떴습니다(오른쪽 붉은 줄). 기한 안에 마커 칸에서 막지 못하면 벌칙을 받고, 일제 동향(위쪽 붉은 칸)이 높을수록 벌칙이 커집니다. 미션과 일제 작전 사이에서 손을 나눠야 합니다."],
	["jail", "투옥", "감옥에서는 주사위로 탈옥 판정을 하거나, 동료가 그 거점에 들어와 구출해 줄 때까지 기다립니다. 거점 옆 칸에 온 동료와는 아이템 · 주사위를 주고받을 수 있습니다(면회)."],
	["vote", "결행 투표", "결행 준비가 찼습니다. 지금 결행하면 2막에 쓸 날이 많고, 하루 더 준비하면 첩보와 결행 혜택이 늘지만 날이 줄어듭니다. 결행하면 첩보가 쌓인 거점 중에서 칠 곳을 고릅니다."],
	["act2", "2막 · 장면 돌파", "결행 거점의 금색 점선이 지금 장면의 자리입니다. 장면 카드의 조건(판정 · 주사위 합 · 같은 날 여러 명 · 버티기)을 채우면 다음 장면이 열리고, 마지막 장면을 돌파하면 승리합니다. 첩보 토큰은 판정 +1이나 주사위 합 −2로 씁니다."],
	["counter", "반격", "버티기 장면에서는 그날 반격이 옵니다. 자리에 선 요원이 작전 판정에 성공해야 오늘 밤을 버틴 날로 칩니다. 못 막으면 자리에 선 요원이 회피 판정을 하고, 실패하면 투옥됩니다."],
]


func _training_due(key: String) -> bool:
	## 훈련 안내 단계가 지금 뜰 때인가
	var me: Dictionary = game.players[human]
	var my_turn: bool = game.phase == "turn" and game.current == human
	match key:
		"morning":
			return game.phase == "plan"
		"day":
			return game.phase == "day" and game.can_begin_turn(me)
		"turn":
			return my_turn and game.steps_left == 0 and not me["jailed"] and not game.my_dice(human).is_empty()
		"marker":
			return my_turn and game.steps_left == 0 and game.act == 1 and not game.markers.is_empty()
		"move":
			return my_turn and game.steps_left > 0
		"check":
			return my_turn and game.legal_actions().any(func(a): return int(a.get("player", -1)) == human and a["type"] in ["mission_check", "scene_check", "counter_check"])
		"end":
			return my_turn and game.steps_left == 0 and game.my_dice(human).is_empty()
		"chased":
			return game.police.has(human)
		"op":
			return not game.op_row.is_empty()
		"jail":
			return me["jailed"]
		"vote":
			return game.phase == "choice" and str(game.pending.get("kind", "")) == "launch_vote"
		"act2":
			return game.act == 2 and my_turn
		"counter":
			return game.counter_active()
	return false


func _training_check() -> void:
	## 훈련 작전: 아직 안 본 단계 중 조건이 맞는 첫 단계를 띄운다 (보고 있는 안내가 있으면 기다림)
	if _tip.visible:
		return
	for s in TRAINING_STEPS:
		if _tips_seen.has(s[0]) or not _training_due(s[0]):
			continue
		_tips_seen[s[0]] = true
		_tip_title.text = s[1]
		_tip_lbl.text = s[2]
		_tip_step.text = "훈련 %d / %d" % [_tips_seen.size(), TRAINING_STEPS.size()]
		_tip.visible = true
		_tip.reset_size()
		_place_tip()
		return


func _place_tip() -> void:
	## 안내는 보드 아래쪽에 붙인다 (글이 길어져 높이가 바뀌어도 보드 안에)
	if _frame == null:
		return
	_tip.position = Vector2(_frame.position.x + 14, _frame.position.y + _frame.size.y - _tip.size.y - 14)


func _tip_check() -> void:
	## 첫 판에 한해 아침 · 낮 · 차례 마치기에서 한 줄 안내 (일시정지 메뉴에서 끌 수 있음). 훈련 작전은 단계 안내
	if _auto or _playing or not _started:
		return
	if _training:
		_training_check()
		return
	if not Prefs.v2_tips:
		return
	var key := ""
	var text := ""
	var me: Dictionary = game.players[human]
	if game.phase == "plan":
		key = "plan"
		text = "아침입니다. 오늘 쓸 작전 주사위가 나왔습니다. 주사위 1개 = 행동 1개이니, 준비가 됐으면 「하루 시작」을 누르세요."
	elif game.phase == "turn" and game.current == human and game.steps_left == 0 and not me["jailed"] and not game.my_dice(human).is_empty():
		key = "turn"
		text = "내 차례입니다. 주사위를 눌러 이동·판정·바치기를 고르세요. 큰 눈은 판정에 남겨 두는 것이 좋습니다."
	elif game.phase == "turn" and game.current == human and game.steps_left == 0 and game.my_dice(human).is_empty():
		key = "end"
		text = "주사위를 다 썼습니다. 「차례 마치기」를 누르면 쫓는 경찰이 다가오고 다음 요원 차례가 됩니다."
	if key == "" or _tips_seen.has(key):
		return
	_tips_seen[key] = true
	_tip_lbl.text = text
	_tip.visible = true
	_tip.reset_size()
	_place_tip()


class DieFace extends Control:
	## 주사위 한 개 (점 눈금 대신 큰 숫자, v1 종이 질감에 맞춘 흰 주사위)
	var value := 1
	var big := true
	var mine := false   # 지금 누를 수 있음
	var taken := false
	var used := false
	var carry := false
	var hover := false

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 6))
		if mine:
			r.position.y -= 9 if hover else 4   # 손맛: 마우스를 올리면 더 들림
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
	_atmos.set_state(game.phase, game.act, game.threat_today)
	_cine.heartbeat(game.act == 2 and game.phase != "over" and not game.scenes.is_empty() and game.scene_index == game.scenes.size() - 1)
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
	if a["type"] == "ability":
		_cutin(int(a["player"]), _mult())
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
	_close_menu()
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


func _save_now() -> void:
	## 이어하기 저장: 훈련·자동 진행 판과 끝난 판은 저장하지 않는다. 연출 중에는 엔진이 입력을 기다리는 상태가 아닐 수 있어 건너뛴다
	if _training or _auto or game.phase == "over" or _playing:
		return
	SaveGameV2.write(game, meta)


func _after_queue() -> void:
	if game.phase == "over":
		if Prefs.v2_tips and not _tips_seen.is_empty():
			Prefs.v2_tips = false   # 안내는 첫 판에 한해
			Prefs.save()
		if _ended:
			return
		_ended = true   # 끝 연출은 한 번만
		_cine.heartbeat(false)
		if not _auto:
			if bool(game.ending.get("won", false)):
				await _cine.victory(1.0)
			else:
				await _cine.defeat(1.0)
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
	if game.phase == "plan" and _saved_day != game.day and _ai_actor() < 0:
		_saved_day = game.day   # 매일 아침 「하루 시작」을 기다릴 때 자동 저장
		_save_now()
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
			if game.can_begin_turn(me) and not _let_allies and not _ai_first:
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
	if a["type"] == "ability" and not _auto:
		_cutin(int(a["player"]), _mult())
	if game.apply(a):
		_pump()


# ================================================================ 연출

func _play_event(e: Dictionary) -> void:
	var m := _mult()
	var k: String = e["kind"]
	match k:
		"move":
			_board.note_arrived(e["to"])
			_board.note_footprint(e["from"], int(e["player"]))
			Sfx.play("step", 0.1, 0.5)
			await _board.animate_move(int(e["player"]), e["from"], e["to"], 0.13 * m)
		"reveal":
			if bool(e.get("scouted", false)):
				_board.note_scouted(e["pos"])
			Sfx.play("flip", 0.1, 0.6)
			_fx.paper_burst(_board.position + _board.cell_center(e["pos"]) + _frame.position, m * 0.6)
			await _board.reveal(e["pos"], 0.22 * m)
		"police":
			if _board.police_changed(e["police_snap"]):
				await _board.animate_police(e["police_snap"], 0.28 * m)
		"dice":
			if int(e.get("player", -1)) >= 0 and (int(e.get("target", 0)) >= 10 or (game.act == 2 and game.scene_index == game.scenes.size() - 1)):
				await _cutin(int(e["player"]), m)
			await _fx.roll_dice(e, m)
			_cine.ink(_fx.focus_center, bool(e.get("ok", false)), m)
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
			_cine.shake(_frame, 7.0, 0.3 * m)
			if int(e["player"]) == human:
				Sfx.play("whistle")
				var jp: Dictionary = game.players[human]
				await _cine.cut({"tex": ArtV2.get_tex("cut", "jail", ArtV2.get_tex("threat", "prison")), "title": "투옥 · " + game.base_name(game.data.bases.find(jp["pos"])) + " 감옥",
					"sub": "탈옥 판정을 하거나 동료가 구하러 올 때까지 기다린다", "stamp": "투 옥", "hold": 1.4}, m)
		"mission_done":
			Sfx.play("score")
			var mc: Control = _mission_cards.get(str(e["id"]), null)
			if mc != null and is_instance_valid(mc):
				var at := mc.get_global_rect().get_center() - global_position
				_fx.paper_burst(at, m)
				_fx.stamp_at(at, "성 공", Style.GOOD, m)
			if str(game.mission_def(str(e["id"])).get("type", "")) == "bomb":
				_cine.shake(_frame, 9.0, 0.35 * m)
			_fx.toast("미션 성공 · %s (%s)" % [game.mission_def(str(e["id"])).get("name", ""), _name(int(e["player"]))], "good")
		"saga_done":
			Sfx.play("success")
			await _cutin(int(e["player"]), m, "사연 「%s」을(를) 이루다" % game.data.saga(str(e["id"])).get("name", ""))
			_fx.toast("사연을 이룸 · %s — %s" % [_name(int(e["player"])), game.data.saga(str(e["id"])).get("name", "")], "good")
		"scene":
			var card: Dictionary = game.current_scene()
			var stex := ArtV2.get_tex("scene", str(e.get("id", "")))
			if stex != null:
				await _cine.cut({"tex": stex, "title": "장면 %d/%d · %s" % [int(e["index"]) + 1, game.scenes.size(), card.get("name", "")],
					"sub": _cond_text(card.get("condition", {}), card), "hold": 1.5}, m)
			else:
				await _fx.banner("장면 %d/%d · %s" % [int(e["index"]) + 1, game.scenes.size(), card.get("name", "")], "info", m, _cond_text(card.get("condition", {}), card))
		"scene_break":
			Sfx.play("success")
			var bcard := _scene_card_dict(str(e.get("id", "")))
			await _cine.cut({"tex": ArtV2.get_tex("scene", str(e.get("id", ""))), "title": str(bcard.get("name", "")) + " 돌파",
				"stamp": "돌 파", "stamp_color": Style.GOOD, "hold": 0.9}, m)
		"launch":
			Music.play("tension")
			var st: Dictionary = game.data.strike(str(e.get("target", "")))
			var faces := []
			for q in game.players:
				var ft := ArtV2.get_tex("char", str(q["character"]))
				if ft != null:
					faces.append(ft)
			await _cine.cut({"tex": ArtV2.get_tex("strike", str(e.get("target", ""))), "title": "결행 · " + str(st.get("name", "")),
				"sub": "오늘 밤, 들이친다", "portraits": faces, "stamp": "결 행", "hold": 2.2}, m)
			await _cine.ink_wipe(m)
		"op_appear":
			Sfx.play("alert")
			var oc: Dictionary = game.data.op_card(str(e["id"]))
			var osub := "%s\n막는 법: %s · 기한 %d일 · %s" % [oc.get("where", ""), oc.get("how", ""), int(oc.get("deadline", 0)), oc.get("missed_text", "")]
			var otex := ArtV2.get_tex("op", str(e["id"]))
			if otex != null:
				_cine.vignette(Style.SEAL, 0.5, 0.9 * m)
				await _cine.cut({"tex": otex, "title": "일제 작전 · " + str(oc.get("name", "")), "sub": osub, "hold": 1.6}, m)
			else:
				await _fx.banner("일제 작전 · " + str(oc.get("name", "")), "bad", m, osub)
		"op_blocked":
			Sfx.play("success")
			_fx.toast("일제 작전 저지 · %s (%s)" % [game.data.op_card(str(e["id"])).get("name", ""), _name(int(e["player"]))], "good")
		"op_missed", "mission_missed":
			Sfx.play("fail")
		"ready":
			# 결행 준비 칸이 찰 때: 위쪽 띠의 준비 칸에서 불꽃
			var g: Control = _top._gauge
			if g != null and is_instance_valid(g):
				var at := g.get_global_rect().get_center() - global_position
				_fx.paper_burst(at, m)
				_fx.paper_burst(at + Vector2(0, 6), m)
		"exposure":
			if _last_exposure >= 0 and int(e["value"]) > _last_exposure:
				_cine.vignette(Style.SEAL, 0.55, 1.1 * m)
			_last_exposure = int(e["value"])
		"marker_moved":
			_board.note_marker_moved(str(e["id"]), e["from"], e["to"])
		"informed":
			Sfx.play("click")
			_fx.toast("정보원 · %s의 표적이 멈췄습니다 (판정이 쉬워짐)" % game.card_def(str(e["id"])).get("name", ""), "good")
		"pickup":
			Sfx.play("click")
			_fx.toast("%s: 물건을 들었습니다 · %s" % [_name(int(e["player"])), game.card_def(str(e["id"])).get("name", "")], "info")
		"item_lost":
			Sfx.play("fail")
			_fx.toast("%s: 잡혀서 물건이 받기 마커로 돌아갔습니다" % _name(int(e["player"])), "bad")
		"work_give":
			Sfx.play("click")
		"tile_fx":
			Sfx.play("click")
		"funds":
			if int(e.get("change", 0)) != 0:
				Sfx.play("score" if int(e["change"]) > 0 else "fail")
				_fx.toast("군자금 %+d (지금 %d)" % [int(e["change"]), int(e["value"])], "good" if int(e["change"]) > 0 else "bad")
				if int(e["change"]) <= -2 and str(e.get("why", "")) in ["lose", "cap"]:
					await _fx.banner("군자금 %d을 잃었다" % -int(e["change"]), "bad", m, "지금 군자금 %d" % int(e["value"]))
		"trend":
			Sfx.play("alert")
			var pen := game._trend_penalty()
			_fx.toast("일제 동향 %d / %d — 못 막으면 추가 벌칙: %s" % [int(e["value"]), int(game.data.rules["ops"]["trend_max"]), _fx_text(pen)], "bad")
		"market_buy":
			Sfx.play("click")
		"bribe":
			Sfx.play("click")
		"vote_reveal":
			Sfx.play("click")
			var yes := 0
			for pid in e["votes"]:
				yes += 1 if e["votes"][pid] else 0
			var tally := {}
			for pid in e["targets"]:
				tally[e["targets"][pid]] = int(tally.get(e["targets"][pid], 0)) + 1
			var tparts := []
			for id in tally:
				tparts.append("%s %d표" % [game.base_name(game.data.base_index(str(id))), int(tally[id])])
			var who := []
			for pid in e["targets"]:
				who.append("%s → %s%s" % [_name(int(pid)), game.base_name(game.data.base_index(str(e["targets"][pid]))),
					"" if e["forced"] else (" (찬성)" if e["votes"].get(pid, false) else " (반대)")])
			await _fx.banner("강제 결행 · 대상 투표" if e["forced"] else "결행 투표 공개", "info", m,
				"%s%s\n%s" % ["" if e["forced"] else "찬성 %d · 반대 %d · " % [yes, e["votes"].size() - yes], ", ".join(tparts), " · ".join(who)])
		"counter":
			Sfx.play("alert")
			await _fx.banner("반격!", "bad", m, "오늘 이 장면 자리에서 작전 판정 %d에 성공해야 합니다" % int(game.data.rules["counter"]["target"]))
		"counter_blocked":
			Sfx.play("success")
		"benefit":
			var bn := str(e["id"])
			for b in game.data.rules["launch"]["benefits"]:
				if str(b["id"]) == bn:
					_fx.toast("결행 혜택 · %s" % b.get("name", ""), "good")
		"confiscate":
			Sfx.play("fail")
			var lost: Array = e["items"].map(func(id): return str(game.item_def(str(id)).get("name", "")))
			_fx.toast("%s: 투옥되어 아이템 압수 · %s" % [_name(int(e["player"])), ", ".join(lost)], "bad")
		"card":
			if str(e.get("deck", "")) == "item" and int(e.get("player", -1)) == human and str(e.get("id", "")) != "bomb":
				_fx.toast("아이템 획득 · %s" % game.item_def(str(e["id"])).get("name", ""), "info")
				_fx.fly_card(_fx.focus_center, _hand_row.get_global_rect().get_center() - global_position, str(game.item_def(str(e["id"])).get("name", "")), 0.5 * m)
			elif str(e.get("deck", "")) == "event":
				var ev: Dictionary = game.data.event(str(e["id"]))
				_fx.toast("이벤트 · %s — %s" % [ev.get("name", ""), ev.get("text", "")], "info")
				if int(e.get("player", -1)) == human:
					await _cine.cut({"tex": ArtV2.get_tex("event", str(e["id"])), "title": "이벤트 · " + str(ev.get("name", "")), "sub": str(ev.get("text", "")), "hold": 1.2}, m)
		"dice_rolled":
			Sfx.play("dice", 0.1, 0.6)
		"die_given":
			if int(e["target"]) == human:
				_fx.toast("%s이(가) 주사위 %d을(를) 건넸습니다" % [_name(int(e["player"])), int(e["value"])], "good")
	if e.has("players_snap"):
		_board.apply_players_snap(e["players_snap"])
	if k in ["morning", "threat", "dice_rolled", "die_used", "die_given", "day_start", "mission_done", "launch", "scene", "scene_break", "confiscate",
			"saga_done", "jail", "rescue", "intel", "ready", "exposure", "turn", "night", "markers", "trend", "op_appear", "op_blocked", "op_missed",
			"mission_missed", "pickup", "item_lost", "work_give", "lurk", "informed", "marker_moved", "funds", "market_buy", "bribe"]:
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
			_press(_primary_action)


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
			return "서로 다른 %d명이 같은 날 %s에서 각각 작전 판정 %d 이상" % [int(c.get("count", 2)), where, int(c.get("target", 7))]
		"dice":
			return "%s에서 아침 주사위 합 %d 이상을 바침" % [where, int(c.get("sum", 0))]
		"pay_item":
			return "%s에서 아이템 %d장을 바침" % [where, int(c.get("count", 1))]
		"pay_bomb":
			return "%s에서 폭탄 %d개를 바침%s" % [where, int(c.get("count", 1)), " (나눠 바쳐도 됨)" if c.get("split", false) else ""]
		"people":
			return "%d명이 같은 날 %s에서 차례를 마침" % [int(c.get("count", 2)), where]
		"pay_funds":
			return "%s에서 군자금 %d을 내고 매수 (마지막 장면은 매수할 수 없음)" % [where, int(c.get("count", 1))]
		"hold":
			return "%d명이 %s에서 %d밤을 넘김" % [int(c.get("count", 1)), where, int(c.get("days", 1))]
		"jailed_here":
			return "결행 거점 감옥에 요원이 갇혀 있음"
		"sequence":
			var steps := []
			for i in c.get("steps", []).size():
				steps.append("%d단계 %s" % [i + 1, _cond_text(c["steps"][i], card)])
			return " → ".join(steps)
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


func _funds_price() -> int:
	## 지금 장면의 매수 값 (군자금)
	for leaf in game._scene_leaves(game.current_scene().get("condition", {})):
		if str(leaf["cond"].get("kind", "")) == "pay_funds":
			return int(leaf["cond"].get("count", 0))
	return 0


func _chance(a: Dictionary) -> int:
	## 작전 판정 행동의 성공 확률 (%)
	var c: Dictionary = game.check_preview(game.players[human], a)
	return roundi(game.check_chance(c, game.die_value(int(a["die"]))) * 100.0)


func _label(a: Dictionary) -> String:
	var me: Dictionary = game.players[human]
	match a["type"]:
		"start_day": return "하루 시작"
		"begin_turn": return "내 차례 시작"
		"end_move": return "이동 마치기"
		"end_turn": return "차례 마치기"
		"escape": return "탈옥 판정 (주사위 %d · 성공 %d%%)" % [game.die_value(int(a["die"])), _chance(a)]
		"mission_check": return "표적 판정 (주사위 %d · 성공 %d%%)" % [game.die_value(int(a["die"])), _chance(a)]
		"work_give":
			var wm := game.marker_at(me["pos"])
			return "공작 바치기: 주사위 %d → 「%s」" % [game.die_value(int(a["die"])), game.card_def(str(wm.get("id", ""))).get("name", "")]
		"counter_check": return "반격 막기 (주사위 %d · 성공 %d%%)" % [game.die_value(int(a["die"])), _chance(a)]
		"hide": return "숨기 (주사위 %d)" % game.die_value(int(a["die"]))
		"scout": return "정찰 (주사위 %d: %d칸 안의 덮인 칸 %d곳)" % [game.die_value(int(a["die"])), game.die_value(int(a["die"])), int(game.data.rules["scout"]["count"])]
		"market":
			var offer := {}
			for o in game.data.rules["market"]["offers"]:
				if str(o["id"]) == str(a["offer"]):
					offer = o
			return "장터: %s 사기 (군자금 %d · 주사위 %d)" % [offer.get("name", ""), game.market_cost(me, offer), game.die_value(int(a["die"]))]
		"use_item":
			return "[%s] 사용" % game.item_def(str(me["items"][int(a["index"])])).get("name", "")
		"ability":
			var ab := game.ability_def(me)
			if a.has("target"):
				return "능력 「%s」 → %s" % [ab.get("name", ""), _name(int(a["target"]))]
			if a.has("die"):
				return "능력 「%s」 (주사위 %d를 냄)" % [ab.get("name", ""), game.die_value(int(a["die"]))]
			return "능력 「%s」" % ab.get("name", "")
		"give_item":
			return "[%s] → %s 건네기 (주사위 %d)" % [game.item_def(str(me["items"][int(a["index"])])).get("name", ""), _name(int(a["to"])), game.die_value(int(a["die"]))]
		"decoy":
			return "미끼: %s의 경찰을 내 쪽으로 (주사위 %d)" % [_name(int(a["from"])), game.die_value(int(a["die"]))]
		"move_die":
			var mv := game.move_value(me, int(a["die"]))
			return "주사위 %d로 이동 (+%d칸)" % [game.die_value(int(a["die"])), mv]
		"give_die":
			return "주사위 %d → %s에게 건네기" % [game.die_value(int(a["die"])), _name(int(a["target"]))]
		"scene_check":
			return "장면 판정 (주사위 %d · 성공 %d%%)" % [game.die_value(int(a["die"])), _chance(a)]
		"scene_pay":
			match a["what"]:
				"die": return "주사위 %d 장면에 바치기" % game.die_value(int(a["die"]))
				"item": return "[%s] 바치기 (주사위 %d를 냄)" % [game.item_def(str(me["items"][int(a["index"])])).get("name", ""), game.die_value(int(a["with"]))]
				"bomb": return "폭탄 바치기 (주사위 %d를 냄)" % game.die_value(int(a["with"]))
				"funds": return "장면 매수 (군자금 %d · 주사위 %d를 냄)" % [_funds_price(), game.die_value(int(a["with"]))]
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
	box.add_child(UiKit.title({"launch_vote": "결행 투표", "launch_target": "결행 대상 투표", "strike_target": "결행 대상 (리더)", "launch_benefit": "결행 혜택", "mission_gear": "값을 낼까요?", "informer_pay": "정보원 사례금", "bribe": "검문소 뇌물", "threat_look": "위협 덱 보기", "saga_keep": "남길 사연", "reroll": "다시 하기", "discard": "버릴 아이템"}.get(kind, "선택"), Style.FS_H3))
	box.add_child(UiKit.text(str(pd.get("prompt", "")), Style.FS_BODY))
	if kind in ["pick_cell", "hop"]:
		box.add_child(UiKit.text("보드에서 빨간 점선 칸을 눌러도 됩니다.", 14, Style.INK_3))
	for o in pd["options"]:
		var val = o["value"]
		var label := str(o.get("label", str(val)))
		if kind == "saga_keep":
			var s: Dictionary = game.data.saga(str(val))
			label = "%s — %s" % [s.get("name", ""), s.get("condition_text", "")]
		if kind in ["launch_target", "strike_target"] and str(val) in GameDataV2.BASE_IDS:
			var d := game.walk_dist(game.players[human]["pos"], game.data.bases[game.data.base_index(str(val))])
			label += (" · 거리 %d칸" % d) if d < 100 else (" · 길이 이어지지 않음 (직선 %d칸)" % (d - 100))
		if kind == "reroll" and not game.check.is_empty() and str(val) == "grant":
			label += " · 성공 %d%%" % roundi(game.check_chance(game.check, int(game.check.get("die_value", 0))) * 100.0)
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
	var tips := CheckButton.new()
	tips.text = "첫 판 안내 말풍선"
	tips.button_pressed = Prefs.v2_tips
	tips.add_theme_color_override("font_color", Style.INK)
	tips.toggled.connect(func(on):
		Prefs.v2_tips = on
		Prefs.save()
		if not on:
			_tip.visible = false)
	box.add_child(tips)
	box.add_child(UiKit.button("규칙 요약", func():
		_paused = false
		_show_rules(), 17, "paper"))
	box.add_child(UiKit.button("훈련 그만두고 메인 메뉴로" if _training else "저장하고 메인 메뉴로", func():
		_choice.visible = false
		_save_now()
		back_to_title.emit(), 17, "paper"))
	_choice.show_with(panel)


func _show_rules() -> void:
	if _paused:
		return
	_paused = true
	_choice.show_with(rules_panel(game.data, func():
		_paused = false
		_choice.visible = false
		_after_queue()))


static func rules_panel(data: GameDataV2, close: Callable) -> Control:
	## 규칙 요약 창 (게임 안 일시 정지 메뉴와 타이틀이 함께 쓴다)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var panel := UiKit.paper_panel(24)
	panel.custom_minimum_size = Vector2(720, 0)
	panel.add_child(box)
	box.add_child(UiKit.title("규칙 요약", Style.FS_H3))
	var lines := [
		"하루: 아침에 위협 카드 → (1막 짝수 날) 일제 작전 → (1막) 표적 이동·기한 → 결행 투표 → 공개 미션 줄 채우기 → 요원마다 작전 주사위 굴리기 → 낮 → 밤. 남은 주사위는 밤에 사라집니다.",
		"미션은 보드 위 마커로 이뤄집니다: 암살(표적 칸에서 판정, 표적은 매일 움직임) · 잠입(거점에 들어감) · 폭파(폭탄을 들고 마커 칸에) · 공작(마커 칸에서 주사위 바치기) · 연락(받기 → 주기) · 잠복(마커 곁에서 쫓기지 않고 차례를 마침) · 협동. 일제 작전은 기한 안에 막지 못하면 벌칙이 있고, 일제 동향이 높을수록 벌칙이 커집니다.",
		"낮: 요원마다 한 차례씩, 순서는 자유입니다 (한 번에 한 요원). 주사위 1개 = 행동 1개: 이동 · 작전 판정 · 바치기 · 건네기 · 미끼 · 숨기 · 정찰 · 장터. 아이템 1장과 능력 1번은 공짜. 원하면 언제든 「차례 마치기」.",
		"요원끼리는 같은 칸에 설 수 있고, 경찰이 있는 칸에는 못 들어갑니다. 같은 칸의 효과는 한 차례에 한 번만 받습니다. 거리는 깔린 길을 따라 걷는 칸 수입니다. 경찰은 쫓기는 요원이 차례를 마칠 때 다가옵니다 (숨기를 하면 안 옴).",
		"1막: 공개 미션을 이뤄 결행 준비를 %d까지 올리면 아침에 결행 투표가 열립니다. 남은 날이 %d일이 되면 강제로 결행합니다." % [int(data.rules["launch_min"]), int(data.rules["forced_launch_days_left"])],
		"2막: 결행할 때 첩보가 %d 이상인 거점 중에서 대상을 투표로 고르고, 결행 혜택 하나를 받습니다. 장면을 하나씩 돌파하고 마지막 장면을 돌파하면 대성공입니다. 첩보는 토큰이 되어 판정 +1 또는 주사위 조건 −2로 씁니다." % int(data.rules["launch"]["target_min_intel"]),
		"군자금: 팀이 함께 쓰는 돈 (시작 2, 최대 10). 장터(아이템 2 · 폭탄 3), 검문소 뇌물 2, 간수 매수 2, 정보원 1, 무기 조달 2, 장면 매수에 씁니다. 부호의 헌금 · 독립 공채 같은 미션과 이벤트로 얻고, 가택 수색 · 자금 동결 · 노출 9에서 잃습니다. 남으면 후일담에 한 줄 붙습니다.",
		"개인 사연: 비밀입니다. 이루면 즉시 보상을 받습니다.",
		"투옥: 노출이 오르고, 들고 있던 아이템 1장을 무작위로 압수당합니다 (폭탄은 그대로). 동료가 그 거점에 들어오면 구출됩니다.",
	]
	for l in lines:
		box.add_child(UiKit.text("· " + l, 15))
	box.add_child(UiKit.button("닫기", close, 17, "paper"))
	return panel


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
	_ai_first = true
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
		"art": _board.faction_texture(str(ch.get("faction", ""))), "illus": ArtV2.get_tex("char", str(p["character"])), "name": str(ch.get("name", "")),
		"sub": "%s · %s" % [fac, ch.get("origin", "")], "sections": secs}


func _mission_info(id: String) -> Dictionary:
	var m: Dictionary = game.mission_def(id)
	var type := str(m.get("type", ""))
	var td: Dictionary = game.mission_type_def(type)
	var coop := type == "coop"
	var secs := [["이루는 법", str(m.get("how", ""))], ["자리", str(m.get("where", ""))]]
	var b = m.get("bonus")
	if typeof(b) == TYPE_DICTIONARY:
		secs.append(["보너스", str(b.get("text", "")), Style.GOOD])
	var days := game.card_days_left(id)
	if days >= 0:
		secs.append(["기한", "남은 %d일 · %s" % [days, m.get("missed_text", "")], Style.SEAL])
	var status := game.card_status(id)
	if status != "":
		secs.append(["진행", status, Style.GOOD])
	secs.append(["보상", str(m.get("text", ""))])
	if coop:
		secs.append(["협동 미션", "두 명이 함께 채웁니다. 결행 준비 +%d" % int(m.get("ready", 0))])
	else:
		secs.append(["결행 준비", "+%d · 결행 준비가 %d가 되면 아침마다 결행 투표가 열립니다." % [int(m.get("ready", 0)), int(game.data.rules["launch_min"])]])
	if bool(m.get("loud", td.get("loud", false))):
		secs.append(["시끄러움", "이루면 노출 +1, 경찰이 붙습니다.", Style.SEAL])
	return {"band": "미 션 · " + str(td.get("name", "")), "color": Color("#2f7f7a") if coop else Style.MISSION,
		"art": _mission_art(type), "illus": ArtV2.get_tex("mission", type), "name": str(m.get("name", "")), "sections": secs}


func _fx_text(effects: Array) -> String:
	var parts := []
	for e in effects:
		match str(e.get("op", "")):
			"exposure": parts.append("노출 %+d" % int(e["value"]))
			"police_dispatch": parts.append("가까운 거점에서 경찰이 출동해 가장 가까운 요원을 쫓음")
			"ready": parts.append("결행 준비 %+d" % int(e["value"]))
	return ", ".join(parts) if not parts.is_empty() else "없음"


func _op_info(id: String) -> Dictionary:
	var oc: Dictionary = game.data.op_card(id)
	var secs := [["막는 법", str(oc.get("how", ""))], ["자리", str(oc.get("where", ""))],
		["기한", "남은 %d일 · %s" % [game.card_days_left(id), oc.get("missed_text", "")], Style.SEAL],
		["지금 동향 %d의 추가 벌칙" % game.trend, _fx_text(game._trend_penalty()), Style.SEAL],
		["막으면", "노출 −1 (동향은 내려가지 않음)", Style.GOOD]]
	var status := game.card_status(id)
	if status != "":
		secs.append(["진행", status, Style.GOOD])
	return {"band": "일 제 작 전", "color": Style.SEAL, "art": ArtV2.get_tex("op", id, load(MISSION_ART["op"])), "illus": ArtV2.get_tex("op", id), "name": str(oc.get("name", "")), "sections": secs}


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
			parts.append("%s %d" % [{"dice": "주사위 합", "item": "아이템", "bomb": "폭탄", "check_pair": "판정 성공", "people": "사람", "hold": "밤", "funds": "군자금"}.get(key, key), int(need[key])])
		if not parts.is_empty():
			secs.append(["남은 것", ", ".join(parts), Style.GOOD])
	secs.append(["여기서 멈추면", str(card.get("stop_text", "")), Style.SEAL])
	var col := Style.GOLD
	if last:
		col = Style.SEAL
	elif i < game.scene_index:
		col = Style.MISSION
	return {"band": "결 행 장 면", "color": col, "illus": ArtV2.get_tex("scene", str(card.get("id", ""))), "name": str(card.get("name", "")), "sub": sub, "sections": secs}


func _saga_info(id: String, pr: Dictionary, done: bool) -> Dictionary:
	var s: Dictionary = game.data.saga(id)
	return {"band": "사 연 · 이룸" if done else "사 연 · 비밀", "color": SAGA_COL, "art": _saga_art(), "illus": ArtV2.get_tex("", "saga_back"),
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
	return {"band": "일 제 위 협", "color": Style.INK, "art": load("res://assets/ui/police.png"), "illus": ArtV2.get_tex("threat", str(t.get("art", ""))), "name": str(t.get("name", "")), "sections": secs}
