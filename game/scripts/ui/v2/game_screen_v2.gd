class_name GameScreenV2
extends Control
## v2 게임 화면 (M 재배치): 위쪽 띠 + 왼쪽 레일(동료 · 작전 기록) + 가운데 보드 + 오른쪽 레일(미션 줄/결행 장면 · 일제 작전)
## + 아래 독(나 · 행동 · 손패).
##
## 흐름: 엔진에 액션 → 엔진이 쌓은 events를 연출 큐에 넣음 → 하나씩 재생(await)
##      → 큐가 비면 화면을 실제 상태와 맞추고 → 사람 입력을 기다리거나 AI가 한 수를 둔다.
## 버튼은 모두 엔진의 legal_actions()에서 만든다. 그래서 화면이 규칙과 어긋나지 않는다.

signal back_to_title
signal finished

const GAP := 8.0
const AI_DELAY := 0.28
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
var _cur_cat := "anim"            # U4: 지금 재생 중인 연출의 종류 (기다림 측정)
var wait_stats := {}              # U4: 한 판 동안 종류별로 흐른 시간(초) {"내 입력", "AI 생각", "컷신", "배너", "말 움직임", "안내"}
var _training := false            # 훈련 작전 (안내 단계, 저장하지 않음)
var _task_box: VBoxContainer
var _was_chased := false
var _remote: NetClientV2 = null   # 온라인: 판정은 서버가, 이 화면은 서버가 보낸 보기만 그린다
var _remote_queue: Array = []     # 연출 중에 온 서버 보기 (차례로 반영)
var _remote_info := {}            # 서버가 덧붙인 정보 (아침에 기다리는 자리, AI가 맡은 자리)
var _saved_day := -1              # 이 날 아침에 자동 저장했는가
var _right_h := 0.0               # 아래 독이 받은 높이
var _left_h := 0.0                # 왼쪽 레일이 받은 높이 (작전 기록 띠 위까지)
var _rail_h := 0.0                # 오른쪽 레일이 받은 높이

var _board: BoardViewV2
var _frame: PanelContainer
var _tilt: TiltBoardV2 = null     # M2: 기운 보드 (설정 「보드 입체」를 끄면 없음)
var _top: TopBarV2
var _right: HBoxContainer         # 아래 독 (나 · 행동 · 손패)
var _left: VBoxContainer          # 왼쪽 레일 (동료)
var _rail: VBoxContainer          # 오른쪽 레일 (미션 줄 · 일제 작전 / 결행 장면)
var _me_box: VBoxContainer        # 독의 「나」
const DOCK_H := 198.0
## M3 행동 먼저: [키, 단추 글, 엔진 액션 종류들, _why_not_rows의 이름]
const LEFT_W := 330.0
const RAIL_W := 384.0
var _roster_box: VBoxContainer
var _rows: Array = []
var _mid_title: Label
var _mid_hint: Label
var _mid_box: Container
var _ops_row: VBoxContainer
var _hand_hint: Label
var _hand_row: HBoxContainer
var _act_title: Label
var _act_hint: Label
var _dice_row: HBoxContainer
var _act_row: HBoxContainer
var _status_lbl: Label            # 남은 주사위 · 공짜 행동(아이템·능력) 상태
var _pv_labels: Array = []        # U1 선택 미리보기 띠: [갈 곳, 얻는 것, 위험] 본문 Label
var _pv_box: HBoxContainer
var _roster_open := false         # U1: 동료 상세를 펼쳤는가 (기본은 접힌 한 줄)
var _roster_btn: Button
var _tip: PanelContainer          # 첫 판 안내 말풍선
var _tip_lbl: Label
var _tip_key := ""
var _tips_seen := {}
var _ticker: LogTickerV2
var _fx: FxLayer
var _cine: CinemaV2              # 컷신 · 화면 효과 (V 연출)
var _atmos: AtmosV2              # 보드 분위기: 빛 · 날씨 (V 연출)
var _ended := false               # 끝 연출(만세 · 흑백)을 이미 했는가
var _mission_cards := {}          # 미션 id → 미션 줄 카드 (이루면 그 카드에 도장)
var _choice: Overlay
var _peek: CardPeekV2   # 마우스를 올리면 뜨는 큰 카드
var _shown_actions: Array = []    # 지금 화면에 단추로 나온 액션 (시험용)
var _primary_action: Dictionary = {}  # 주 버튼 액션 (스페이스)
var _verb := ""                   # M3: 고른 행동 (주사위를 고르기를 기다림)
var _verb_acts: Array = []
# Z4: 역할별 모듈 (상태는 이 화면에 있고, 모듈은 화면을 받아 그 일만 한다)
var _text: ScreenTextV2           # 문장: 이름 · 조건 · 행동 이름 · 카드 설명
var _actions: ScreenActionsV2     # 행동 단추판 · 주사위 · 메뉴
var _preview: ScreenPreviewV2     # 선택 미리보기 띠
var _coach: ScreenCoachV2         # 훈련 · 첫 판 안내
var _playback: ScreenPlaybackV2   # 이벤트 연출 재생


func _init(g: RulesV2, human_id := 0, meta_info := {}) -> void:
	game = g
	human = human_id
	game.human = human_id   # 결행 혜택은 사람이 고른다
	meta = meta_info
	_auto = bool(meta.get("autoplay", false))
	_training = bool(meta.get("training", false))
	_remote = meta.get("remote", null)
	if _remote != null:
		_remote.game_updated.connect(_on_remote_update)
		_remote.server_error.connect(func(msg): _fx.toast(msg, "bad"))
		_remote.closed.connect(func(): _fx.toast("서버와 연결이 끊겼습니다. 메뉴로 나가 다시 들어오면 자리를 돌려받습니다.", "bad"))
	_fast = _auto
	_text = ScreenTextV2.new(self)
	_actions = ScreenActionsV2.new(self)
	_preview = ScreenPreviewV2.new(self)
	_coach = ScreenCoachV2.new(self)
	_playback = ScreenPlaybackV2.new(self)


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


func _ui() -> Dictionary:
	## 화면 구성 데이터 (data/v2/ui.json)
	return game.data.ui


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
	_board.cell_hovered.connect(_preview.preview_cell)
	_frame.add_child(_board)
	_board.setup(game, human)
	if Prefs.v2_tilt:
		_tilt = TiltBoardV2.new()
		add_child(_tilt)
		_tilt.setup(_frame, _board)

	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 6)
	add_child(_left)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 6)
	add_child(_rail)
	_right = HBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	add_child(_right)

	# 왼쪽 레일: 동료 (나는 아래 독에)
	var roster := _panel("동 료", "누르면 특성 · 능력", _left)
	_roster_open = true
	_roster_btn = UiKit.button("", func(): pass, 11, "tab")
	_roster_btn.visible = false
	roster[2].get_parent().add_child(_roster_btn)
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 4)
	roster[1].add_child(_roster_box)
	for p in game.players:
		_rows.append(_make_row(p))

	# 오른쪽 레일: 공개 미션 줄 / 결행 장면 + 일제 작전
	var mid := _panel("", "", _rail)
	_mid_title = mid[2]
	_mid_hint = mid[3]
	_mid_box = VBoxContainer.new()
	_mid_box.add_theme_constant_override("separation", 6)
	mid[1].add_child(_mid_box)
	_ops_row = VBoxContainer.new()
	_ops_row.add_theme_constant_override("separation", 5)
	mid[1].add_child(_ops_row)

	# 아래 독: 나
	var mep := _panel("", "", _right)
	mep[0].custom_minimum_size = Vector2(300, 0)
	mep[2].get_parent().visible = false
	_me_box = VBoxContainer.new()
	_me_box.add_theme_constant_override("separation", 4)
	mep[1].add_child(_me_box)

	# 아래 독: 행동 (미리보기 띠 · 주사위 · 단추)
	var act := _panel("", "", _right)
	act[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_act_title = act[2]
	_act_hint = act[3]
	_pv_box = HBoxContainer.new()
	_pv_box.add_theme_constant_override("separation", 6)
	act[1].add_child(_pv_box)
	for head in ["갈 곳", "얻는 것", "위험"]:
		var cell := PanelContainer.new()
		var cs := Style.flat(Color("#fff8e6") if head != "위험" else Color("#fbeee6"), Color(Style.SEAL if head == "위험" else Style.GOLD, 0.55), 1, 4, 0)
		cs.content_margin_left = 7
		cs.content_margin_right = 7
		cs.content_margin_top = 2
		cs.content_margin_bottom = 2
		cell.add_theme_stylebox_override("panel", cs)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = 1.4 if head == "얻는 것" else 1.0
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -2)
		cell.add_child(cv)
		cv.add_child(UiKit.text(head, 10, Style.SEAL if head == "위험" else Style.INK_3, false, 800))
		var body := UiKit.text("", 12, Style.INK, false, 700)
		body.clip_text = true
		body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		body.custom_minimum_size = Vector2(40, 0)
		cv.add_child(body)
		_pv_labels.append(body)
		_pv_box.add_child(cell)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 12)
	act[1].add_child(arow)
	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 8)
	arow.add_child(_dice_row)
	_act_row = HBoxContainer.new()
	_act_row.add_theme_constant_override("separation", 7)
	_act_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_act_row.custom_minimum_size = Vector2(0, 85)   # 행동 단추판(두 줄) 높이로 고정: 동료 차례에도 독이 비어 보이지 않게
	arow.add_child(_act_row)
	_status_lbl = UiKit.text("", 11, Style.INK_2, false, 700)
	act[1].add_child(_status_lbl)

	# 아래 독: 손패 (사연 · 아이템 · 폭탄)
	var hand := _panel("내 손 패", "", _right)
	_hand_hint = hand[3]
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 6)
	hand[1].add_child(_hand_row)

	_ticker = LogTickerV2.new(game)
	add_child(_ticker)
	add_child(_ticker.drawer)

	_atmos = AtmosV2.new()
	if _tilt != null:
		_tilt.vp.add_child(_atmos)   # 기운 보드: 분위기(빛 · 비 · 탐조등)도 보드 그림 안에 그려 함께 눕힌다
	else:
		add_child(_atmos)
	_fx = FxLayer.new()
	add_child(_fx)
	_cine = CinemaV2.new()
	add_child(_cine)
	_choice = Overlay.new(Color(0.03, 0.02, 0.01, 0.62))
	add_child(_choice)
	add_child(_peek)
	_peek.attach(_top._threat, _text.threat_info)
	_coach.build_tip()
	if _training:
		_coach.build_focus()
	if _training:
		_coach.build_tasks()


func _panel(title: String, hint: String, parent: Container) -> Array:
	## 종이 패널: [패널, 본문 VBox, 제목 Label, 안내 Label]
	var panel := PanelContainer.new()
	var ps := Style.paper(12)
	ps.content_margin_top = 5
	ps.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", ps)
	parent.add_child(panel)
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
	var dock_y := h - 12 - DOCK_H
	var tick_h := 40.0
	# 왼쪽 레일 + 작전 기록 띠
	_left.position = Vector2(20, top_y)
	_left_h = dock_y - 8 - tick_h - 6 - top_y
	_left.size = Vector2(LEFT_W, _left_h)
	_ticker.position = Vector2(20, dock_y - 8 - tick_h)
	_ticker.size = Vector2(LEFT_W, tick_h)
	_ticker.drawer.position = Vector2(20, top_y)
	_ticker.drawer.size = Vector2(LEFT_W + 120, dock_y - 8 - tick_h - 8 - top_y)
	# 오른쪽 레일
	_rail.position = Vector2(w - 20 - RAIL_W, top_y)
	_rail_h = dock_y - 8 - top_y
	_rail.size = Vector2(RAIL_W, _rail_h)
	# 아래 독
	_right.position = Vector2(20, dock_y)
	_right_h = DOCK_H
	_right.size = Vector2(w - 40, DOCK_H)
	# 가운데 보드
	var x0 := 20 + LEFT_W + 28
	var x1 := w - 20 - RAIL_W - 20
	var side := floorf(minf(dock_y - 8 - top_y, x1 - x0))
	if _tilt != null:
		_tilt.place(Rect2(x0, top_y - 4, x1 - x0, dock_y - 4 - top_y))
	else:
		_frame.position = Vector2(x0 + (x1 - x0 - side) / 2.0, top_y)
		_frame.size = Vector2(side, side)
	var br := _board_rect()
	side = br.size.x
	# 줄바꿈하는 글은 폭이 정해져야 높이가 정해진다 (안 정하면 한 글자 폭으로 재서 화면만큼 길어짐)
	_tip.custom_minimum_size = Vector2(RAIL_W, 0)   # 안내는 오른쪽 레일 아래 빈자리에 (보드를 가리지 않게)
	if _training:
		_tip_lbl.custom_minimum_size = Vector2(RAIL_W - 32, 0)
	_tip.reset_size()
	_coach.place_tip()
	if _task_box != null:
		_coach.place_tasks.call_deferred()
	_fx.focus_center = br.get_center()
	_fx.board_rect = br
	if _tilt != null:
		_atmos.position = Vector2(8, 8)
		_atmos.size = Vector2(TiltBoardV2.VP_SIDE - 16, TiltBoardV2.VP_SIDE - 16)
	else:
		_atmos.position = br.position + Vector2(8, 8)
		_atmos.size = br.size - Vector2(16, 16)
	_fit_right.call_deferred()


func _board_rect() -> Rect2:
	## 보드가 화면에서 차지하는 사각형 (기운 보드면 그 그림의 바깥 사각형)
	if _tilt != null:
		return _tilt.screen_rect()
	return Rect2(_frame.position, _frame.size)


func _cell_screen(c: Vector2i) -> Vector2:
	## 칸 가운데의 화면 좌표 (연출을 칸 위에 띄울 때)
	if _tilt != null:
		return _tilt.cell_to_screen(Vector2(c))
	return _frame.position + _board.position + _board.cell_center(c)


func _board_node() -> Control:
	return _tilt if _tilt != null else _frame


# ================================================================ 요원 명부

func _make_row(p: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var pid: int = p["id"]
	_peek.attach(panel, func(): return _text.char_info(game.players[pid]))
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
	var sub_text := fac + (" · " + str(ch.get("name", "")) if p["id"] == human else "")
	if _remote != null and p["id"] != human and str(p["name"]) != str(ch.get("name", "")):
		sub_text += " · %s (사람)" % p["name"]   # 온라인: 다른 사람이 맡은 자리
	var sub := UiKit.text(sub_text, 12, Style.INK_3, false)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	nh.add_child(sub)
	v.add_child(nh)
	var chips := HFlowContainer.new()   # 레일이 좁아 칩은 줄을 바꿔 가며 놓는다
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 3)
	v.add_child(chips)
	var mini := HBoxContainer.new()   # 접힌 줄: 이름 옆에 아이콘만
	mini.add_theme_constant_override("separation", 3)
	mini.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mini.alignment = BoxContainer.ALIGNMENT_END
	nh.add_child(mini)
	var stamp := UiKit.stamp("차 례", 13)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(stamp)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	h.add_child(pad)
	_roster_box.add_child(panel)
	panel.visible = pid != human   # 나는 아래 독에서 본다
	return {"panel": panel, "face": face, "name": name, "sub": sub, "bar": bar, "chips": chips, "mini": mini, "stamp": stamp, "sig": "", "cur": null}



func _refresh_me() -> void:
	## 아래 독의 나: 초상 · 이름 · 칩 (지금 상태)
	if _me_box == null:
		return
	UiKit.clear(_me_box)
	var p: Dictionary = game.players[human]
	var ch: Dictionary = game.char_def(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_me_box.add_child(row)
	var face := TextureRect.new()
	face.texture = ArtV2.get_tex("char", str(p["character"]), ArtV2.get_tex("token", str(p["character"])))
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size = Vector2(78, 104)
	if p["jailed"]:
		face.modulate = Color(0.6, 0.58, 0.55)
	row.add_child(face)
	_peek.attach(face, func(): return _text.char_info(game.players[human]))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var is_cur: bool = game.current == human and game.phase in ["turn", "choice"]
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 6)
	nh.add_child(UiKit.title(str(ch.get("name", "")), 19, Style.INK))
	if is_cur:
		nh.add_child(UiKit.stamp("내 차례", 11))
	v.add_child(nh)
	var fac: String = str(game.data.characters.get("factions", {}).get(ch.get("faction", ""), {}).get("name", ""))
	v.add_child(UiKit.text(fac + " · " + str(ch.get("trait_text", "")), 11, Style.INK_3, false))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 3)
	v.add_child(flow)
	for c in _chips(p):
		if str(c[0]).begins_with("사연"):
			continue   # 사연은 손패에
		flow.add_child(_chip(c))


func _refresh_roster() -> void:
	for p in game.players:
		var row: Dictionary = _rows[p["id"]]
		var is_cur: bool = p["id"] == game.current and game.phase in ["turn", "choice"]
		# 접힘(U1): 펼치지 않았으면 지금 차례인 요원(없으면 나)만 칩을 다 보이고, 나머지는 한 줄에 아이콘만
		var focus: bool = is_cur or (p["id"] == human and not (game.current >= 0 and game.phase in ["turn", "choice"]))
		var full: bool = true   # 레일에는 자리가 넉넉해 늘 펼친다 (focus는 지금 차례 강조에만)
		if row["cur"] != is_cur or row.get("full") != full:
			row["cur"] = is_cur
			row["full"] = full
			row["chips"].visible = full
			row["mini"].visible = not full
			row["face"].custom_minimum_size = Vector2(36, 36) if full else Vector2(26, 26)
			row["sig"] = ""
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
			UiKit.clear(row["mini"])
			for c in chips:
				if full:
					row["chips"].add_child(_chip(c))
				else:
					row["mini"].add_child(_chip_mini(c))


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
		var gt := _text.grant_text(g)
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


func _chip_mini(c: Array) -> Control:
	## 접힌 줄의 칩: 아이콘 글자만 (설명은 풍선)
	var col: Color = c[2]
	var used: bool = c[4]
	var dot := Label.new()
	dot.text = c[1]
	dot.tooltip_text = "%s — %s" % [c[0], c[3]]
	dot.mouse_filter = Control.MOUSE_FILTER_STOP
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.custom_minimum_size = Vector2(18, 18)
	dot.add_theme_font_size_override("font_size", 10)
	dot.add_theme_font_override("font", Style.sans(800))
	dot.add_theme_color_override("font_color", Color.WHITE if not used else Style.INK_3)
	dot.add_theme_stylebox_override("normal", Style.flat(col.darkened(0.2) if not used else Color(Style.INK, 0.1), Color.TRANSPARENT, 0, 9, 0))
	return dot


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
			var band := "%s · +%d" % [_text.spaced(str(td.get("name", "미션"))), int(m.get("ready", 0))]
			var desc := ""   # 설명은 마우스를 올리면 큰 카드로. 줄에는 진행 상황만
			var days := game.card_days_left(str(id))
			if days >= 0:
				band += " · %d일" % days
			var status := game.card_status(str(id))
			desc = status if status != "" else str(m.get("text", ""))   # U1: 진행이 없으면 보상을 한 줄로
			var card := _rail_card(band, Color("#2f7f7a") if coop else Style.MISSION, _mission_art(type, str(id)),
				str(m.get("name", "")), desc)
			_peek.attach(card, _text.mission_info(str(id)))
			_mid_box.add_child(card)
			_mission_cards[str(id)] = card
		if game.mission_row.is_empty():
			_mid_box.add_child(UiKit.text("아침에 미션 줄을 채웁니다.", 14, Style.INK_3))
		_refresh_ops()
		return
	_ops_row.visible = false
	var strike: Dictionary = game.data.strike(str(game.launch_info.get("target", "")))
	_mid_title.text = "결 행 · %s" % _text.spaced(str(strike.get("name", "")))
	_mid_hint.text = "장면을 하나씩 돌파 · 마지막을 뚫으면 대성공"
	for i in game.scenes.size():
		var last := i == game.scenes.size() - 1
		var card := _text.scene_card_dict(str(game.scenes[i]))
		var box := PanelContainer.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		box.add_child(v)
		if i < game.scene_index:
			box.add_theme_stylebox_override("panel", Style.flat(Style.MISSION, Style.MISSION.darkened(0.3), 1, 2, 6))
			v.add_child(_center_lbl(UiKit.title(str(card.get("name", "")), 14, Color.WHITE)))
			v.add_child(_center_lbl(UiKit.text("돌파", 11, Color.WHITE, false)))
			box.custom_minimum_size = Vector2(0, 30)
		elif i == game.scene_index:
			box.add_theme_stylebox_override("panel", Style.flat(Color("#fff8e6"), Style.GOLD, 3, 2, 8))
			v.add_child(UiKit.text("지금 장면 %d / %d · %s" % [i + 1, game.scenes.size(), _text.scene_kind(i)], 11, Style.INK_3, false))
			v.add_child(UiKit.title(str(card.get("name", "")), 17, Style.INK))
			v.add_child(UiKit.text(_text.cond_text(card.get("condition", {}), card), 12, Style.INK_2))
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
			box.custom_minimum_size = Vector2(0, 30)
			v.add_child(_center_lbl(UiKit.title(str(card.get("name", "")) if known else "?", 14, Style.SEAL if last else Style.INK_3)))
			v.add_child(_center_lbl(UiKit.text(_text.scene_kind(i), 11, Style.SEAL if last else Style.INK_3, false)))
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		_peek.attach(box, _text.scene_info(card, i))
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mid_box.add_child(box)


func _rail_card(band: String, col: Color, art: Texture2D, name: String, desc: String) -> PanelContainer:
	## 오른쪽 레일의 카드 한 줄: 그림 · 띠(종류) · 이름 · 진행이나 보상
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.card_paper(0))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var img := TextureRect.new()
	img.texture = art
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.custom_minimum_size = Vector2(76, 76)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(img)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var b := UiKit.label(band, 11, Color.WHITE)
	b.add_theme_font_override("font", Style.sans(800))
	var bs := Style.flat(col, Color.TRANSPARENT, 0, 3, 0)
	bs.content_margin_left = 6
	bs.content_margin_right = 6
	b.add_theme_stylebox_override("normal", bs)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(b)
	var t := UiKit.title(name, 17, Style.INK)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(t)
	if desc != "":
		var d := UiKit.text(desc, 12, Style.GOOD, false, 700)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.max_lines_visible = 2
		v.add_child(d)
	return card


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
		chip.add_theme_stylebox_override("panel", Style.flat(Color("#fbe9e4"), Style.SEAL, 2, 3, 7))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		chip.add_child(v)
		v.add_child(UiKit.title("%s · %d일" % [oc.get("name", ""), game.card_days_left(str(id))], 13, Style.SEAL))
		var how := str(oc.get("how", ""))
		var status := game.card_status(str(id))
		var hl := UiKit.text(how + ((" · " + status) if status != "" else ""), 12, Style.INK_2, false)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hl)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_peek.attach(chip, _text.op_info(str(id)))
		_ops_row.add_child(chip)


func _hover_lift(b: Control) -> void:
	## 손맛: 마우스를 올리면 단추가 살짝 커진다 (컨테이너가 위치를 정하므로 크기로만)
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2(1.04, 1.04), 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))


func _mission_art(type: String, id := "") -> Texture2D:
	## 미션 그림: 카드마다 그림(art/mission/{카드 id})이 있으면 그것, 없으면 종류 그림, 그것도 없으면 예전 타일 그림
	var fallback := ArtV2.get_tex("mission", type, load(str(_ui()["mission_art"].get(type, _ui()["mission_art"]["coop"]))))
	return ArtV2.get_tex("mission", id, fallback) if id != "" else fallback


func _saga_art() -> Texture2D:
	return ArtV2.get_tex("", "saga_back", load("res://assets/cards/event_back.png"))


func _center_lbl(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# ================================================================ 내 손패

func _refresh_hand() -> void:
	UiKit.clear(_hand_row)
	var me: Dictionary = game.players[human]
	var W := 98.0
	var H := 112.0   # 손패는 이름만 보이면 된다 (설명은 마우스를 올리면 큰 카드)
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
		_peek.attach(card, _text.saga_info(str(id), pr, done))
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


func right_overflow() -> float:
	## 오른쪽 패널이 받은 높이보다 얼마나 넘치는가 (양수면 작전 기록 띠를 가림, tests/v2_ui_test.gd)
	# size는 최소 크기까지 늘어나므로 받은 높이와 견준다. 레일 둘과 독 중 가장 많이 넘친 것
	return maxf(_right.get_combined_minimum_size().y - _right_h,
		maxf(_left.get_combined_minimum_size().y - _left_h, _rail.get_combined_minimum_size().y - _rail_h))


func layout_report() -> String:
	## 오른쪽 패널별 최소 높이 (넘침을 찾을 때, tests/v2_ui_test.gd)
	var parts := []
	for box in [_left, _rail, _right]:
		parts.append("%.0f/%.0f" % [box.get_combined_minimum_size().y, {_left: _left_h, _rail: _rail_h, _right: _right_h}[box]])
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
	_left.size = Vector2(_left.size.x, _left_h)
	_rail.size = Vector2(_rail.size.x, _rail_h)


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


class DieFace extends Control:
	## 주사위 한 개 (점 눈금 대신 큰 숫자, v1 종이 질감에 맞춘 흰 주사위)
	var value := 1
	var big := true
	var mine := false   # 지금 누를 수 있음
	var taken := false
	var used := false
	var carry := false
	var hover := false
	var pick := false   # M3: 고른 행동에 쓸 수 있는 주사위 (반짝)

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 6))
		if pick:
			draw_rect(r.grow(6), Color(Style.GOLD_HI, 0.55))
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
	_refresh_me()
	if _training:
		var chased := game.police.has(human)
		if _was_chased and not chased and not game.players[human]["jailed"]:
			_coach.task_done("police")   # 따돌렸거나 동료가 미끼로 떼어 냄
		_was_chased = chased
		_coach.training_force_chase()
		_was_chased = game.police.has(human)
	_atmos.set_state(game.phase, game.act, game.threat_today)
	_cine.heartbeat(game.act == 2 and game.phase != "over" and not game.scenes.is_empty() and game.scene_index == game.scenes.size() - 1)
	_top.refresh()
	_refresh_roster()
	_refresh_mid()
	_refresh_hand()
	_actions.refresh_actions()
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
	_verb = ""
	_verb_acts = []
	a = a.duplicate()
	a["player"] = int(a.get("player", human))
	Sfx.play("click")
	if _remote != null:
		_remote.act(a)
		if a["type"] == "start_day":
			_fx.toast("준비 완료 · 다른 사람이 「하루 시작」을 누르기를 기다립니다", "info")
		return
	if a["type"] == "ability":
		_playback.cutin(int(a["player"]), _playback.mult())
	if game.apply(a):
		if int(a["player"]) == human:
			match str(a["type"]):
				"move_die": _coach.task_done("move")
				"mission_check", "work_give": _coach.task_done("mission")
				"hide", "decoy": _coach.task_done("police")
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
	_actions.close_menu()
	_playing = true
	_board.interactive = false
	_actions.refresh_actions()
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		_cur_cat = _playback.event_cat(str(e.get("kind", "")))
		await _playback.play_event(e)
	_cur_cat = "anim"
	_playing = false
	_board.sync_from_game()
	_board.interactive = true
	_refresh()
	_after_queue()


func _on_remote_update(view: Dictionary, events: Array, info: Dictionary) -> void:
	## 서버가 보낸 보기: 연출 중이면 줄에 세웠다가 차례로 반영한다
	_remote_info = info
	if _playing or not _started:
		_remote_queue.append([view, events])
		return
	_apply_remote(view, events)


func _apply_remote(view: Dictionary, events: Array) -> void:
	var old_log := game.log_lines
	game.load_state(view, game.data)
	# 서버는 새 기록 줄만 보낸다 (log_from = 앞서 받은 줄 수)
	var lf := int(view.get("log_from", 0))
	if lf > 0:
		game.log_lines = old_log.slice(0, lf) + view.get("log_lines", [])
	game.human = human
	game.events = events.duplicate(true)
	_pump()


func _save_now() -> void:
	## 이어하기 저장: 훈련·자동 진행 판과 끝난 판은 저장하지 않는다. 연출 중에는 엔진이 입력을 기다리는 상태가 아닐 수 있어 건너뛴다
	if _training or _auto or _remote != null or game.phase == "over" or _playing:
		return
	SaveGameV2.write(game, meta)


func _after_queue() -> void:
	if not _remote_queue.is_empty():
		var nx: Array = _remote_queue.pop_front()
		_apply_remote(nx[0], nx[1])
		return
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
		_playback.write_waits()
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
	var pid := _ai_actor()
	if pid >= 0:
		_ai_waiting = true
		# 동료의 수(아침 · 낮 순서 포함)는 「동료 차례 속도」를 따른다. 자동 진행의 내 자리는 보통 빠르기
		_ai_timer = AI_DELAY * (_playback.mult() if _fast or pid == human else float(Prefs.SPEEDS[Prefs.speed]["mult"]))


func _process(delta: float) -> void:
	if _started and not _paused and game.phase != "over":
		# U4: 사람이 기다린 시간을 종류별로 잰다 (플레이테스트 기록 · tour measure)
		var cat := "내 입력"
		if _playing:
			cat = _cur_cat
		elif _ai_waiting:
			var mine: bool = (game.phase == "turn" and game.current == human) or (game.phase == "choice" and int(game.pending.get("player", -1)) == human)
			cat = "내 입력" if mine else "AI 생각"   # 자동 진행(측정)에서는 내 자리 AI의 생각을 「내 입력」으로 센다
		if _tip != null and _tip.visible:
			cat = "안내"
		wait_stats[cat] = float(wait_stats.get(cat, 0.0)) + delta
	if _ai_waiting and not _playing and not _paused:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_waiting = false
			_ai_step()


func _ai_actor() -> int:
	## 지금 AI가 둘 차례면 그 요원 id, 사람이 둘 차례면 -1
	if game.phase == "over" or _remote != null:
		return -1   # 온라인: 다른 자리는 서버(사람 · AI)가 둔다
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
	wait_stats["_ai_steps"] = float(wait_stats.get("_ai_steps", 0.0)) + 1.0
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
		_playback.cutin(int(a["player"]), _playback.mult())
	if game.apply(a):
		_pump()


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


func _input(event: InputEvent) -> void:
	## 훈련: 누를 곳이 아닌 클릭을 한 번 막는다 (GUI보다 먼저 받음)
	if _training and _coach.guard_click(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_pause()
		elif event.keycode == KEY_SPACE and not _primary_action.is_empty() and not _playing and not _paused and not _choice.visible:
			_press(_primary_action)


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
		if kind in ["launch_target", "strike_target"] and str(val) in game.data.base_ids:
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
	box.add_child(UiKit.button("방 나가기 (자리는 AI가 맡음)" if _remote != null else ("훈련 그만두고 메인 메뉴로" if _training else "저장하고 메인 메뉴로"), func():
		_choice.visible = false
		if _remote != null:
			_remote.close()
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

