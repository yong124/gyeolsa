class_name ScreenCoachV2
extends RefCounted
## 훈련 작전 · 첫 판 안내: 할 일 상자, 단계별 안내 말풍선, 첫 판 도움말.
## 상태는 화면(GameScreenV2)에 두고, 이 파일은 화면을 scr로 받아 그 일만 한다 (지시서 Z4).

var scr: GameScreenV2   # 이 모듈이 맡은 화면
const TRAINING_STEPS := [
	# [키, 제목, 글] — 조건은 _training_due()에서 본다. 앞 단계를 넘긴 뒤에 다음 단계가 뜬다(조건이 맞을 때)
	["morning", "아침 · 작전 주사위", "아침마다 요원마다 작전 주사위를 2개 굴립니다(2막은 3개). 주사위 1개 = 행동 1개입니다. 위쪽 붉은 칸은 오늘 뒤집힌 일제 위협, 오른쪽 「공개 미션 줄」은 누구든 이룰 수 있는 미션입니다. 준비가 되면 「하루 시작」을 누르세요."],
	["day", "낮 · 순서는 자유", "요원마다 하루에 한 차례씩 합니다. 순서는 자유입니다. 「내 차례 시작」으로 먼저 하거나, 동료를 먼저 보낼 수 있습니다."],
	["turn", "내 차례 · 행동을 고르세요", "아래 행동 단추(이동 · 작전 판정 · 바치기 …)를 누르고, 반짝이는 주사위 중 쓸 눈을 누르세요. ★은 추천 수입니다(스페이스). 이동은 눈만큼 걷고, 작전 판정은 「낸 눈 + 새 주사위 1개」가 목표 이상이면 성공입니다. 큰 눈을 어디에 쓸지가 이 게임의 고민입니다."],
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
var _tip_step: Label              # 훈련 작전 안내의 단계 번호
var _tip_title: Label             # 훈련 작전 안내의 제목
var _tasks := {}                  # U4: 훈련 할 일 키 -> 했는가


func _init(screen: GameScreenV2) -> void:
	scr = screen


# ---- 첫 판 안내 말풍선

func build_tasks() -> void:
	## U4: 훈련 「할 일」 — 직접 한 번씩 해 보면 ✓ (왼쪽 레일, 동료 아래)
	var panel := PanelContainer.new()
	var st := Style.flat(Color("#fff8e6", 0.95), Style.GOLD, 2, 4, 8)
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr._left.add_child(panel)   # 왼쪽 레일 동료 아래 (보드를 가리지 않게)
	scr._task_box = VBoxContainer.new()
	scr._task_box.add_theme_constant_override("separation", 2)
	panel.add_child(scr._task_box)
	for t in scr._ui()["training_tasks"]:
		_tasks[t["id"]] = false
	_refresh_tasks()


func _refresh_tasks() -> void:
	if scr._task_box == null:
		return
	UiKit.clear(scr._task_box)
	scr._task_box.add_child(UiKit.title("훈련 · 직접 해 보기", 14, Style.SEAL_DARK))
	for t in scr._ui()["training_tasks"]:
		var done: bool = _tasks.get(t["id"], false)
		scr._task_box.add_child(UiKit.text(("✓ " if done else "☐ ") + str(t["label"]), 13, Style.GOOD if done else Style.INK, false, 700))
	place_tasks.call_deferred()


func place_tasks() -> void:
	## 할 일 상자는 왼쪽 레일 안에 있어 자리를 따로 정하지 않는다
	pass


func task_done(key: String) -> void:
	if not scr._training or _tasks.get(key, true):
		return
	_tasks[key] = true
	Sfx.play("success")
	scr._fx.toast("훈련 · %s ✓" % str(scr._ui()["training_tasks"].filter(func(t): return t["id"] == key)[0]["label"]).split(" (")[0], "good")
	_refresh_tasks()


func training_force_chase() -> void:
	## 미션까지 해 봤는데 아직 쫓겨 본 적이 없으면, 내 차례가 시작될 때 경찰을 한 번 붙여 대응을 해 보게 한다 (훈련 전용)
	if not scr._training or _tasks.get("police", true) or not _tasks.get("mission", false):
		return
	var me: Dictionary = scr.game.players[scr.human]
	if scr.game.phase != "turn" or scr.game.current != scr.human or me["jailed"] or scr.game.police.has(scr.human) or scr.game.act != 1:
		return
	if scr.game.steps_left > 0 or scr.game.my_dice(scr.human).size() < 2:
		return
	scr.game._summon(me)
	scr.game.events.clear()
	scr._board.sync_from_game()
	scr._fx.toast("훈련 · 경찰이 붙었습니다! 골목 · 주막에서 숨거나, 멀리 달아나 따돌려 보세요", "bad")


func build_tip() -> void:
	scr._tip = PanelContainer.new()
	var st := Style.flat(Color("#fff2c8"), Style.GOLD, 2, 2, 8)
	scr._tip.add_theme_stylebox_override("panel", st)
	scr._tip.visible = false
	scr._tip.z_index = 20
	scr._tip.resized.connect(place_tip)
	if scr._training:
		# 훈련 작전: 제목 · 몇 번째 단계 · 두세 줄 설명 · 「알겠습니다」
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 12
		st.content_margin_bottom = 12
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		scr._tip.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		_tip_title = UiKit.title("", 19, Style.SEAL_DARK)
		_tip_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_tip_title)
		_tip_step = UiKit.text("", 12, Style.INK_3, false, 700)
		head.add_child(_tip_step)
		scr._tip_lbl = UiKit.text("", 15, Style.INK, false, 600)
		scr._tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(scr._tip_lbl)
		var ok := UiKit.button("알겠습니다", func():
			scr._tip.visible = false
			tip_check(), 14, "primary")
		ok.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(ok)
		scr.add_child(scr._tip)
		return
	# 오른쪽 레일 폭(좁음)에 맞춰 위: 「안내」 · 단추, 아래: 글 (옆으로 늘어놓으면 글이 세로로 길어짐)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 10
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	scr._tip.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var ht := UiKit.title("안내", 15, Style.SEAL)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ht)
	h.add_child(UiKit.button("확인", func(): scr._tip.visible = false, 12, "paper"))
	h.add_child(UiKit.button("안내 끄기", func():
		Prefs.v2_tips = false
		Prefs.save()
		scr._tip.visible = false, 12, "paper"))
	scr._tip_lbl = UiKit.text("", 14, Style.INK, false, 700)
	scr._tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scr._tip_lbl.custom_minimum_size = Vector2(GameScreenV2.RAIL_W - 24, 0)
	v.add_child(scr._tip_lbl)
	scr.add_child(scr._tip)


func _training_due(key: String) -> bool:
	## 훈련 안내 단계가 지금 뜰 때인가
	var me: Dictionary = scr.game.players[scr.human]
	var my_turn: bool = scr.game.phase == "turn" and scr.game.current == scr.human
	match key:
		"morning":
			return scr.game.phase == "plan"
		"day":
			return scr.game.phase == "day" and scr.game.can_begin_turn(me)
		"turn":
			return my_turn and scr.game.steps_left == 0 and not me["jailed"] and not scr.game.my_dice(scr.human).is_empty()
		"marker":
			return my_turn and scr.game.steps_left == 0 and scr.game.act == 1 and not scr.game.markers.is_empty()
		"move":
			return my_turn and scr.game.steps_left > 0
		"check":
			return my_turn and scr.game.legal_actions().any(func(a): return int(a.get("player", -1)) == scr.human and a["type"] in ["mission_check", "scene_check", "counter_check"])
		"end":
			return my_turn and scr.game.steps_left == 0 and scr.game.my_dice(scr.human).is_empty()
		"chased":
			return scr.game.police.has(scr.human)
		"op":
			return not scr.game.op_row.is_empty()
		"jail":
			return me["jailed"]
		"vote":
			return scr.game.phase == "choice" and str(scr.game.pending.get("kind", "")) == "launch_vote"
		"act2":
			return scr.game.act == 2 and my_turn
		"counter":
			return scr.game.counter_active()
	return false


func _training_check() -> void:
	## 훈련 작전: 아직 안 본 단계 중 조건이 맞는 첫 단계를 띄운다 (보고 있는 안내가 있으면 기다림)
	if scr._tip.visible:
		return
	for s in TRAINING_STEPS:
		if scr._tips_seen.has(s[0]) or not _training_due(s[0]):
			continue
		scr._tips_seen[s[0]] = true
		_tip_title.text = s[1]
		scr._tip_lbl.text = s[2]
		_tip_step.text = "훈련 %d / %d" % [scr._tips_seen.size(), TRAINING_STEPS.size()]
		scr._tip.visible = true
		scr._tip.reset_size()
		place_tip()
		return


func place_tip() -> void:
	## 안내는 오른쪽 레일 아래(독 바로 위)에 붙인다 (글이 길어져도 아래를 맞춤, 보드를 가리지 않음)
	if scr._frame == null:
		return
	scr._tip.position = Vector2(scr.size.x - 20 - GameScreenV2.RAIL_W, scr.size.y - 12 - GameScreenV2.DOCK_H - 8 - scr._tip.size.y)


func tip_check() -> void:
	## 첫 판에 한해 아침 · 낮 · 차례 마치기에서 한 줄 안내 (일시정지 메뉴에서 끌 수 있음). 훈련 작전은 단계 안내
	if scr._auto or scr._playing or not scr._started:
		return
	if scr._training:
		_training_check()
		return
	if not Prefs.v2_tips:
		return
	var key := ""
	var text := ""
	var me: Dictionary = scr.game.players[scr.human]
	if scr.game.phase == "plan":
		key = "plan"
		text = "아침입니다. 오늘 쓸 작전 주사위가 나왔습니다. 주사위 1개 = 행동 1개이니, 준비가 됐으면 「하루 시작」을 누르세요."
	elif scr.game.phase == "turn" and scr.game.current == scr.human and scr.game.steps_left == 0 and not me["jailed"] and not scr.game.my_dice(scr.human).is_empty():
		key = "turn"
		text = "내 차례입니다. 주사위를 눌러 이동·판정·바치기를 고르세요. 큰 눈은 판정에 남겨 두는 것이 좋습니다."
	elif scr.game.phase == "turn" and scr.game.current == scr.human and scr.game.steps_left == 0 and scr.game.my_dice(scr.human).is_empty():
		key = "end"
		text = "주사위를 다 썼습니다. 「차례 마치기」를 누르면 쫓는 경찰이 다가오고 다음 요원 차례가 됩니다."
	if key == "" or scr._tips_seen.has(key):
		return
	scr._tips_seen[key] = true
	scr._tip_lbl.text = text
	scr._tip.visible = true
	scr._tip.reset_size()
	place_tip()
