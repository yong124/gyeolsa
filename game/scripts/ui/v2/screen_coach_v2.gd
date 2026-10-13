class_name ScreenCoachV2
extends RefCounted
## 실전 첫 판 쪽지 (지시서 T2): 처음 나오는 순간 한두 줄을 화면 가장자리에 띄운다. 판을 멈추지 않고, 7초 뒤나 누르면 사라진다.
## 한 번 본 쪽지는 다시 안 띄운다(Prefs.v2_notes_seen). 「자세히」는 도움말의 그 탭을 연다. 문장은 data/v2/help.json의 notes.
## 상태는 화면(GameScreenV2)에 두고, 이 파일은 화면을 scr로 받아 그 일만 한다 (지시서 Z4).

const SHOW_SECONDS := 7.0

var scr: GameScreenV2   # 이 모듈이 맡은 화면
var _queue: Array = []            # 띄울 차례를 기다리는 쪽지 키
var _cur := ""                    # 지금 떠 있는 쪽지 키
var _token := 0                   # 7초 타이머가 낡은 쪽지를 지우지 않게
var _head: Label
var _more: Button
var _was_alert := 1               # 경계 단계가 오르는 순간을 알아보려고
var _seen_chased_ally := false


func _init(screen: GameScreenV2) -> void:
	scr = screen


# ---- 쪽지 상자

func build_tip() -> void:
	scr._tip = PanelContainer.new()
	var st := Style.flat(Color("#fff2c8"), Style.GOLD, 2, 2, 8)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 10
	scr._tip.add_theme_stylebox_override("panel", st)
	scr._tip.visible = false
	scr._tip.z_index = 20
	scr._tip.resized.connect(place_tip)
	# 오른쪽 레일 폭(좁음)에 맞춰 위: 「알아 두기」 · 단추, 아래: 글
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	scr._tip.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	_head = UiKit.title("알아 두기", 15, Style.SEAL)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_head)
	_more = UiKit.button("자세히", func(): _open_help(), 12, "paper")
	h.add_child(_more)
	h.add_child(UiKit.button("확인", func(): _hide(), 12, "paper"))
	h.add_child(UiKit.button("끄기", func():
		Prefs.v2_tips = false
		Prefs.save()
		_queue.clear()
		_hide(), 12, "paper"))
	scr._tip_lbl = UiKit.text("", 15, Style.INK, false, 700)
	scr._tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scr._tip_lbl.custom_minimum_size = Vector2(GameScreenV2.RAIL_W - 24, 0)
	v.add_child(scr._tip_lbl)
	scr.add_child(scr._tip)


func place_tip() -> void:
	## 쪽지는 오른쪽 레일 아래(독 바로 위)에 붙인다 (글이 길어져도 아래를 맞춤, 보드를 가리지 않음)
	if scr._frame == null or scr._tip == null:
		return
	scr._tip.position = Vector2(scr.size.x - 20 - GameScreenV2.RAIL_W, scr.size.y - 12 - GameScreenV2.DOCK_H - 8 - scr._tip.size.y)


func _def(key: String) -> Dictionary:
	for n in scr.game.data.help.get("notes", []):
		if str(n.get("key", "")) == key:
			return n
	return {}


func _enabled() -> bool:
	return Prefs.v2_tips and scr._tutor == null and not scr._auto


func note(key: String) -> void:
	## 이 쪽지를 띄울 차례에 넣는다 (이미 본 것 · 줄 선 것 · 훈련에서 배운 것은 넣지 않는다)
	if not _enabled() or key == "" or key == _cur or _queue.has(key) or Prefs.v2_notes_seen.has(key):
		return
	var d := _def(key)
	if d.is_empty() or (d.has("taught") and Prefs.v2_trainings.has(str(d["taught"]))):
		return
	_queue.append(key)


func on_event(e: Dictionary) -> void:
	## 엔진 이벤트가 연출 줄에 들어갈 때: 처음 나오는 일이면 쪽지를 줄 세운다 (띄우는 것은 연출이 끝난 뒤)
	if not _enabled():
		return
	match str(e.get("kind", "")):
		"op_appear":
			note("op")
		"trend":
			if int(e.get("value", 0)) > 0:
				note("trend")
		"alert":
			if int(e.get("level", 0)) > 1:
				note("alert")
		"jail":
			note("jail" if int(e.get("player", -1)) == scr.human else "ally_jail")
		"card":
			if str(e.get("deck", "")) == "event":
				note("event")
			elif str(e.get("deck", "")) == "threat":
				note("first_morning")   # 위협 카드가 뒤집힐 때 바로 (위협 효과로 고르기 창이 먼저 뜨면 설명이 그 뒤에 나오던 문제)


func tip_check() -> void:
	## 화면이 갱신될 때마다: 상태로 알 수 있는 쪽지를 줄 세우고, 떠 있는 것이 없으면 하나 띄운다
	if scr._auto or scr._playing or not scr._started or scr._tutor != null:
		return
	if _enabled():
		_state_notes()
	_show_next()


func _state_notes() -> void:
	var g := scr.game
	var me: Dictionary = g.players[scr.human]
	var my_turn: bool = g.phase == "turn" and g.current == scr.human
	if g.phase == "plan":
		note("first_morning")
		if not g.saga_cards(scr.human).is_empty():
			note("saga")
	if my_turn:
		note("ability")
		if tile_is(me["pos"], "check"):
			note("checkpoint")
		if g.act == 2:
			note("intel_token")
	if not me["items"].is_empty():
		note("item")
	if g.act == 1:
		for k in g.intel:
			if int(g.intel[k]) > 0:
				note("intel")
				break
	if g.counter_active():
		note("counter")
	if g.phase == "choice" and int(g.pending.get("player", -1)) == scr.human and str(g.pending.get("kind", "")) == "launch_benefit":
		note("perk")
	if me["jailed"]:
		note("jail")
	for q in g.players:
		if int(q["id"]) != scr.human and q["jailed"]:
			note("ally_jail")
	if g.alert_level() > _was_alert:
		note("alert")
	_was_alert = g.alert_level()


func tile_is(c: Vector2i, type: String) -> bool:
	return scr.game.tile_type(c) == type


func _show_next() -> void:
	if scr._tip == null or scr._tip.visible or _queue.is_empty() or not _enabled():
		return
	var key: String = _queue.pop_front()
	if Prefs.v2_notes_seen.has(key):
		_show_next()
		return
	var d := _def(key)
	if d.is_empty():
		return
	_cur = key
	Prefs.v2_notes_seen.append(key)
	Prefs.save()
	scr._tip_lbl.text = scr.game.data.help_text(str(d.get("text", "")))
	_more.visible = str(d.get("tab", "")) != ""
	scr._tip.visible = true
	scr._tip.reset_size()
	place_tip()
	_token += 1
	var mine := _token
	scr.get_tree().create_timer(SHOW_SECONDS).timeout.connect(func():
		if mine == _token and scr._tip != null and scr._tip.visible:
			_hide())


func _hide() -> void:
	_token += 1
	_cur = ""
	if scr._tip != null:
		scr._tip.visible = false
	if not _queue.is_empty():
		scr.get_tree().create_timer(0.6).timeout.connect(func(): _show_next())   # 다음 쪽지는 잠깐 뒤에


func _open_help() -> void:
	var tab := str(_def(_cur).get("tab", ""))
	_hide()
	scr._show_rules(tab)
