class_name ScreenActionsV2
extends RefCounted
## 행동 단추판 (아래 독 가운데): 「행동 먼저」 단추 격자 · 주사위 · 보조 단추 · 주사위 메뉴 · 못 하는 이유 · 상태 줄.
## 상태는 화면(GameScreenV2)에 두고, 이 파일은 화면을 scr로 받아 그 일만 한다 (지시서 Z4).

var scr: GameScreenV2   # 이 모듈이 맡은 화면
var _menu: Control = null         # 주사위 행동 메뉴 (바깥을 누르면 닫힘)
const SECONDARY_MAX := 2          # 행동 패널의 보조 버튼 수 (나머지는 「더 보기」). 셋이면 글자가 잘림 (U1)


func _init(screen: GameScreenV2) -> void:
	scr = screen


# ================================================================ 행동 패널

func refresh_actions() -> void:
	UiKit.clear(scr._dice_row)
	UiKit.clear(scr._act_row)
	scr._shown_actions = []
	scr._primary_action = {}
	var me: Dictionary = scr.game.players[scr.human]
	var legal := scr.game.legal_actions()
	var mine := legal.filter(func(a): return int(a.get("player", -1)) == scr.human)
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
	match scr.game.phase:
		"plan":
			title = "아 침 계 획"
			hint = "오늘의 작전 주사위 · 주사위 1개 = 행동 1개 · 큰 눈을 이동에 쓸지, 판정에 남길지 정하세요"
			primary = _take_type(others, "start_day")
			if scr._remote != null:
				# 온라인: 「하루 시작」은 사람마다 누르고, 모두 누르면 서버가 시작한다
				var wait: Array = scr._remote_info.get("waiting_day", [])
				primary = {"type": "start_day", "player": scr.human} if scr.human in wait or wait.is_empty() else {}
				if not scr.human in wait and not wait.is_empty():
					hint = "준비 완료 · %d명을 기다리는 중" % wait.size()
			else:
				extra_btns.append(_order_toggle())
		"day":
			title = "누 가 먼 저 ?"
			if scr.game.can_begin_turn(me):
				hint = "자유 순서 · 다음 차례를 고르세요 (내 차례 또는 동료 한 명)"
				primary = _take_type(others, "begin_turn")
				if scr._remote == null:
					extra_btns.append(_order_toggle())
				for x in legal:
					if scr._remote != null:
						break   # 온라인: 동료 차례는 그 사람(또는 서버 AI)이 시작한다
					if x["type"] == "begin_turn" and int(x["player"]) != scr.human:
						var xa: Dictionary = x
						extra_btns.append({"text": "%s 차례" % scr._text.name(int(x["player"])), "icon": "swap", "action": xa,
							"cb": func(): scr._act(xa), "tip": "이 동료가 지금 차례를 진행합니다."})
			else:
				hint = "동료들이 움직이는 중입니다."
		"turn":
			if scr.game.current == scr.human:
				title = "내 차 례"
				if me["jailed"]:
					hint = "감옥 · 주사위로 탈옥 판정 %d 이상 · 면회 온 동료와 주사위를 주고받을 수 있습니다" % scr.game.check_target("escape")
				elif scr.game.steps_left > 0:
					hint = "이동 %d칸 남음 · 보드에서 칸을 누르면 그 길로 걸어갑니다 · 이동을 마치면 다른 행동을 고를 수 있습니다" % scr.game.steps_left
				elif not scr.game.my_dice(scr.human).is_empty():
					hint = "주사위 1개 = 행동 1개 · 주사위를 눌러 이동·판정·건네기·정찰·숨기를 고르세요 · 다 하면 「차례 마치기」"
				else:
					hint = "주사위를 다 썼습니다 · 「차례 마치기」"
				if scr.game.act == 2:
					hint += " · 장면 자리(금색 점선)에서 바치기 · 판정"
				if scr.game.counter_active():
					hint += " · 반격! 자리에 선 요원이 작전 판정 %d에 성공해야 오늘 밤 버틴 날로 칩니다" % int(scr.game.data.rules["counter"]["target"])
				if scr.game.steps_left == 0:
					primary = _best_check(mine)
					if primary.is_empty():
						primary = GameAIV2._work_action(scr.game, me, mine)
					if primary.is_empty():
						for t in ["scene_pay"]:
							primary = _take_die_type(mine, t)
							if not primary.is_empty():
								break
				if primary.is_empty() and scr.game.steps_left == 0 and not me["jailed"]:
					primary = _best_move_die(mine)
				if not primary.is_empty():
					others.append(primary)   # 아래에서 주 단추로 빠진다
				for t in ["end_move", "end_turn"]:
					if primary.is_empty():
						primary = _take_type(others, t)
				others.sort_custom(func(x, y): return _rank(x) < _rank(y))
			else:
				title = "동 료 차 례"
				hint = "%s의 차례입니다." % scr._text.name(scr.game.current)
		"choice":
			title = "선 택"
			hint = "%s가 고르는 중입니다." % scr._text.name(int(scr.game.pending["player"])) if int(scr.game.pending["player"]) != scr.human else "선택 창에서 고르세요."
		"over":
			title = "작 전 종 료"
	if scr._playing:
		hint = "…"
	scr._act_title.text = title
	scr._act_hint.text = hint
	scr._act_hint.tooltip_text = hint
	scr._status_lbl.text = _status_line()
	scr._preview.preview_idle()
	scr._coach.tip_check()
	if scr.game.phase == "turn" and scr.game.current == scr.human and scr.game.steps_left == 0 and not scr._playing and not scr._auto:
		_build_verbs(mine, primary, others)
		scr._fit_right.call_deferred()
		return
	scr._verb = ""
	# 주 버튼
	var pb := UiKit.button("", func(): pass, 21, "primary")
	pb.custom_minimum_size = Vector2(290, 54)
	pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pb.add_theme_constant_override("icon_max_width", 26)
	pb.add_theme_constant_override("h_separation", 10)
	if not primary.is_empty() and not scr._playing:
		pb.text = scr._text.label(primary) if primary["type"] != "move_die" else "주사위 %d로 이동" % scr.game.die_value(int(primary["die"]))
		pb.icon = UiKit.ui_icon(_icon(primary) + "_light")
		var pa: Dictionary = primary
		scr._primary_action = pa
		pb.pressed.connect(func(): scr._press(pa))
		scr._shown_actions.append(primary)
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
	scr._hover_lift(pb)
	scr._act_row.add_child(pb)
	# 보조 버튼
	var secs := []
	if not scr._playing:
		for x in extra_btns:
			secs.append(x)
	if not scr._playing:
		for a in others:
			if a == primary:
				continue
			var aa: Dictionary = a
			secs.append({"text": scr._text.label(a), "icon": _icon(a), "cb": func(): scr._press(aa), "action": a})
	for i in mini(secs.size(), SECONDARY_MAX):
		scr._act_row.add_child(_sec_btn(secs[i]))
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
				scr._shown_actions.append(rest[i]["action"])
		pm.id_pressed.connect(func(id): rest[id]["cb"].call())
		scr._act_row.add_child(more)
	else:
		for i in range(secs.size(), SECONDARY_MAX):
			var blank := UiKit.button("", func(): pass, 12, "paper")
			blank.disabled = true
			blank.custom_minimum_size = Vector2(0, 54)
			blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scr._act_row.add_child(blank)
	scr._fit_right.call_deferred()


func _build_verbs(mine: Array, primary: Dictionary, others: Array) -> void:
	## M3 행동 먼저: 행동 단추판(두 줄) + 오른쪽에 차례 마치기 · 더 보기(아이템 · 능력 등)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr._act_row.add_child(grid)
	var why := {}
	for r in _why_not_rows(mine):
		why[str(r[0])] = str(r[1])
	var me: Dictionary = scr.game.players[scr.human]
	for vb in scr._ui()["verbs"]:
		var key: String = vb["id"]
		var types: Array = vb["actions"]
		var acts: Array = mine.filter(func(a): return a["type"] in types)
		var jail := str(vb.get("jailed", ""))
		if jail == "only" and not me["jailed"]:
			continue
		if me["jailed"] and not jail in ["only", "allowed"]:
			continue
		if vb.has("acts") and not scr.game.act in (vb["acts"] as Array).map(func(x): return int(x)):
			continue
		var on := scr._verb == key
		var rec := not primary.is_empty() and primary in acts
		var b := UiKit.button(str(vb["label"]), func(): pick_verb(key, acts), 14, "primary" if on else "paper")
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if acts.is_empty():
			b.disabled = true
			var reason := str(why.get(str(vb["why"]), ""))
			if key == "check" and scr.game.act == 2:
				reason = str(why.get("장면 판정·바치기", reason))
			b.tooltip_text = "지금은 못 함" + (": " + reason if reason != "" else "")
		else:
			b.tooltip_text = hint(acts[0])
			var first: Dictionary = acts[0]
			if rec:
				first = primary
				b.text = str(vb["label"]) + " ★"
				b.tooltip_text = "추천 · " + scr._text.label(primary) + "\n" + b.tooltip_text
			b.mouse_entered.connect(func(): hover_action(first))
			b.mouse_exited.connect(func():
				if scr._verb == "":
					scr._board.reach = {}
					scr._board.queue_redraw())
			for a in acts:
				scr._shown_actions.append(a)
		scr._hover_lift(b)
		grid.add_child(b)
	if not primary.is_empty():
		scr._primary_action = primary   # 스페이스 = 추천 수
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(150, 0)
	scr._act_row.add_child(col)
	var rest := []
	for a in others:
		if _die_of(a) >= 0 or a == primary:
			continue
		if a["type"] == "end_turn":
			var aa: Dictionary = a
			var eb := UiKit.button("차례 마치기", func(): scr._press(aa), 15, "dark")
			eb.custom_minimum_size = Vector2(0, 40)
			col.add_child(eb)
			scr._shown_actions.append(a)
		else:
			rest.append(a)
	if not primary.is_empty() and _die_of(primary) < 0 and primary["type"] != "end_turn":
		rest.push_front(primary)
	elif not primary.is_empty() and primary["type"] == "end_turn":
		var pa: Dictionary = primary
		var eb2 := UiKit.button("차례 마치기", func(): scr._press(pa), 15, "dark")
		eb2.custom_minimum_size = Vector2(0, 40)
		col.add_child(eb2)
		scr._shown_actions.append(primary)
	if not rest.is_empty():
		var more := MenuButton.new()
		more.text = "아이템 · 능력 (%d)" % rest.size()
		more.flat = false
		Style.style_button(more, "paper")
		more.custom_minimum_size = Vector2(0, 40)
		var pm := more.get_popup()
		for i in rest.size():
			pm.add_item(scr._text.label(rest[i]), i)
			scr._shown_actions.append(rest[i])
		pm.id_pressed.connect(func(id): scr._press(rest[id]))
		col.add_child(more)
	if scr._verb != "":
		scr._act_hint.text = "「%s」 — 쓸 주사위를 누르세요 (반짝이는 주사위)" % str(scr._ui()["verbs"].filter(func(v): return v["id"] == scr._verb)[0]["label"])


func pick_verb(key: String, acts: Array) -> void:
	## 행동을 골랐다: 쓸 수 있는 수가 하나면 바로, 주사위가 여럿이면 주사위를 고르게, 한 주사위에 여럿이면 메뉴
	if acts.is_empty() or scr._playing:
		return
	Sfx.play("click")
	var dice := {}
	for a in acts:
		dice[_die_of(a)] = true
	if acts.size() == 1:
		scr._press(acts[0])
		return
	if dice.size() == 1:
		die_menu(acts, int(dice.keys()[0]))
		return
	scr._verb = "" if scr._verb == key else key
	scr._verb_acts = acts if scr._verb != "" else []
	refresh_actions()
	if scr._verb != "":
		hover_action(acts[acts.size() - 1])


func _sec_btn(s: Dictionary) -> Button:
	var b := UiKit.button(str(s["text"]).replace("능력 「", "").replace("」", ""), s["cb"], 12, "paper")   # 단추에는 짧게 (풍선에 전체)
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
		scr._shown_actions.append(s["action"])
	scr._hover_lift(b)
	return b


func _take_type(list: Array, t: String) -> Dictionary:
	for a in list:
		if a["type"] == t:
			return a
	return {}


func _order_toggle() -> Dictionary:
	## 낮의 순서: AI 동료가 먼저 / 내가 먼저 (한 번에 한 요원씩)
	return {"text": "동료 먼저 하게 함" if scr._ai_first else "동료 기다리게 하기", "icon": "swap", "tip": "누르면 바뀝니다. 동료 먼저 하게 함: 동료가 모두 차례를 마친 뒤 내가 합니다. 동료 기다리게 하기: 다음 차례를 내가 고릅니다 (내가 먼저 해서 주사위를 건네거나 길을 열 수 있음).",
		"cb": func():
			scr._ai_first = not scr._ai_first
			scr._after_queue()}


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
		var best: Dictionary = GameAIV2._check_action(scr.game, scr.game.players[scr.human], mine, t)
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
		if a["type"] == "move_die" and (best.is_empty() or scr.game.die_value(int(a["die"])) > scr.game.die_value(int(best["die"]))):
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
	for i in scr.game.op_dice.size():
		if int(scr.game.op_dice[i]["owner"]) == scr.human:
			idx.append(i)
	if idx.is_empty() or not scr.game.phase in ["plan", "day", "turn", "choice"]:
		scr._dice_row.visible = false
		return
	scr._dice_row.visible = true
	for i in idx:
		var d: Dictionary = scr.game.op_dice[i]
		var acts := []
		for a in mine:
			if _die_of(a) == i:
				acts.append(a)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var die := GameScreenV2.DieFace.new()
		die.value = int(d["value"])
		die.mine = not acts.is_empty() and not scr._playing
		var vacts: Array = scr._verb_acts.filter(func(x): return _die_of(x) == i)
		die.pick = scr._verb != "" and not vacts.is_empty()
		die.used = d["used"]
		die.custom_minimum_size = Vector2(44, 44)
		if die.mine:
			die.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var mv: Array = acts.filter(func(x): return x["type"] == "move_die")
			var first: Dictionary = mv[0] if not mv.is_empty() else acts[0]
			die.mouse_entered.connect(func():
				scr._preview.preview_action(first)
				hover_action(first)
				die.hover = true
				Sfx.play("click", 0.3, 0.25)
				die.queue_redraw())
			die.mouse_exited.connect(func():
				die.hover = false
				die.queue_redraw())
			die.tooltip_text = "눌러서: " + " / ".join(acts.map(func(a): return scr._text.label(a)))
			var at := acts.duplicate()
			if die.pick:
				first = vacts[0]
				die.tooltip_text = "이 주사위로: " + scr._text.label(vacts[0])
			die.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					if not vacts.is_empty() and scr._verb != "":
						if vacts.size() == 1:
							scr._press(vacts[0])
						else:
							die_menu(vacts, i)
					else:
						die_menu(at, i))
			for a in acts:
				scr._shown_actions.append(a)
		v.add_child(die)
		var l := UiKit.text("씀" if d["used"] else ("이동 %d" % scr.game.move_value(scr.game.players[scr.human], i) if scr.game.phase == "turn" else "내 주사위"), 11, Style.INK_3, false, 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		scr._dice_row.add_child(v)
	if false:   # M: 독에는 자리가 없어 고정 안내를 두지 않는다 (훈련 안내 · 미리보기 띠가 대신)
		var tip := UiKit.text("주사위 1개 = 행동 1개: 이동(눈만큼) · 작전 판정(눈 + 주사위 1개) · 바치기\n건네기 · 미끼 · 숨기 · 정찰 · 장터 — 주사위를 눌러 고르세요\n남은 주사위는 밤에 사라집니다", 11, Style.INK_3, false)
		tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tip.name = "DiceTip"
		scr._dice_row.add_child(tip)


func close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	if scr._board != null:
		scr._board.reach = {}


func die_menu(acts: Array, die := -1) -> void:
	## 주사위를 누르면 그 주사위로 할 수 있는 행동을 미리보기와 함께 보인다. 안 되는 행동은 흐리게, 이유와 함께.
	close_menu()
	var me: Dictionary = scr.game.players[scr.human]
	var catcher := Control.new()
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close_menu())
	scr.add_child(catcher)
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu = catcher
	var panel := UiKit.paper_panel(12)
	catcher.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(430, 0)
	panel.add_child(v)
	var dv := scr.game.die_value(die) if die >= 0 else 0
	v.add_child(UiKit.title("주사위 %d — 무엇을 할까요? (주사위 1개 = 행동 1개)" % dv if die >= 0 else "행동 고르기", 15, Style.INK))
	for a in acts:
		var aa: Dictionary = a
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var btn := UiKit.button(scr._text.label(aa), func():
			close_menu()
			scr._press(aa), 14, "paper")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.mouse_entered.connect(func(): hover_action(aa))
		btn.mouse_exited.connect(func(): scr._board.reach = {})
		row.add_child(btn)
		var hint := hint(aa)
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
	await scr.get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var pos := scr.get_global_mouse_position() + Vector2(10, 10)
	var sz := panel.get_combined_minimum_size()
	pos.x = clampf(pos.x, 6.0, scr.size.x - sz.x - 6.0)
	pos.y = clampf(pos.y, 6.0, scr.size.y - sz.y - 6.0)
	panel.position = pos


func hover_action(a: Dictionary) -> void:
	scr._preview.preview_action(a)
	scr._board.reach = {}
	if a["type"] == "move_die":
		scr._board.reach = scr.game.reach_cells(scr.game.players[scr.human], scr.game.move_value(scr.game.players[scr.human], int(a["die"])))
	scr._board.queue_redraw()


func hint(a: Dictionary) -> String:
	## 행동의 미리보기와 대가 한 줄
	var me: Dictionary = scr.game.players[scr.human]
	match a["type"]:
		"move_die":
			return "최대 %d칸 걷기 (중간에 멈춰도 됨) — 올려 두면 갈 수 있는 칸이 보드에 밝혀집니다" % scr.game.move_value(me, int(a["die"]))
		"escape", "mission_check", "counter_check", "scene_check":
			var c: Dictionary = scr.game.check_preview(me, a)
			return "낸 눈 %d + 새 주사위 1개 ≥ 목표 %d%s → 성공 %d%%. 실패하면 %s" % [scr.game.die_value(int(a["die"])), int(c["target"]), (" (보정 %+d)" % int(c["bonus"])) if int(c["bonus"]) != 0 else "", scr._text.chance(a),
				{"escape": "다른 주사위로 또 시도할 수 있음", "mission_check": "회피 판정(7)을 해야 하고 실패하면 투옥", "counter_check": "다른 주사위로 또 시도할 수 있음", "scene_check": "다른 주사위로 또 시도할 수 있음"}[a["type"]]]
		"work_give":
			return scr._preview.work_preview(a)
		"scene_pay":
			match a["what"]:
				"die":
					var need := int(scr.game.scene_need().get("dice", 0))
					return "남은 합 %d → %d" % [need, maxi(0, need - scr.game.die_value(int(a["die"])))]
				"funds":
					return "군자금 %d을 내고 장면을 매수 (지금 %d)" % [scr._text.funds_price(), scr.game.funds]
				"item":
					return "아이템 1장을 내고 장면 조건을 채움 (주사위 하나도 씀)"
				"bomb":
					return "폭탄을 내고 장면 조건을 채움 (주사위 하나도 씀)"
		"give_die":
			return "하루 한 번. %s은(는) 행동이 하나 늘고 나는 하나 줆" % scr._text.name(int(a["target"]))
		"give_item":
			return "아이템 카드를 동료에게 줌 (주사위 하나를 씀)"
		"decoy":
			return "경찰을 내 쪽으로 끌어와 동료를 빼냄 — 대신 내가 쫓김"
		"hide":
			return "이번 차례 끝에 나를 쫓는 경찰이 다가오지 않음"
		"scout":
			return "눈 %d칸 안의 덮인 칸 %d곳을 골라 타일을 미리 깜 (효과는 그 칸에서 멈출 때)" % [scr.game.die_value(int(a["die"])), int(scr.game.data.rules["scout"]["count"])]
		"market":
			return "군자금 %d을 내고 얻음 (지금 %d)" % [_market_cost(a), scr.game.funds]
		"ability":
			return str(scr.game.ability_def(me).get("text", ""))
	return ""


func _market_cost(a: Dictionary) -> int:
	for o in scr.game.data.rules["market"]["offers"]:
		if str(o["id"]) == str(a.get("offer", "")):
			return scr.game.market_cost(scr.game.players[scr.human], o)
	return 0


func _why_not_rows(acts: Array) -> Array:
	## 이 주사위로 지금은 못 하는 행동과 이유 [[이름, 이유]]
	var me: Dictionary = scr.game.players[scr.human]
	var have := {}
	for a in acts:
		have[a["type"]] = true
	var rows := []
	if me["jailed"]:
		if not have.has("escape"):
			rows.append(["탈옥", "주사위가 없음"])
		return rows
	if not have.has("give_die") and not have.has("give_item"):
		if int(me["gives_today"]) >= int(scr.game.data.rules["give_per_day"]):
			rows.append(["건네기", "오늘 이미 건넸음"])
		else:
			rows.append(["건네기", "같은 칸에 아직 차례를 안 한 동료가 없음"])
	if not have.has("hide"):
		rows.append(["숨기", "이미 숨었음" if me["hidden"] else "골목·주막·은신처 칸에서만 숨을 수 있음"])
	if not have.has("scout"):
		rows.append(["정찰", "범위 안에 덮인 칸이 없음"])
	if not have.has("market"):
		var mt := str(scr.game.data.rules["market"]["tile"])
		rows.append(["장터", "장터 칸에서만 살 수 있음" if scr.game.tile_type(me["pos"]) != mt else "군자금이 모자라거나 자리가 없음 (지금 군자금 %d)" % scr.game.funds])
	if not scr.game.police.is_empty() and not have.has("decoy"):
		rows.append(["미끼", "나는 쫓기고 있지 않아야 하고, 3칸 안에 쫓기는 동료가 있어야 함" if not scr.game.police.has(scr.human) else "이미 쫓기는 중이라 미끼를 못 씀"])
	if scr.game.act == 1:
		var has_target := false
		var has_work := false
		for m in scr.game.markers:
			has_target = has_target or (str(m["role"]) == "target" and str(scr.game.card_cond(str(m["id"])).get("kind", "")) == "assassinate")
			has_work = has_work or str(m["role"]) == "work"
		if has_target and not have.has("mission_check"):
			rows.append(["표적 판정", "표적 칸에 서 있어야 함 (저격수 오는 옆 칸도 됨)"])
		if has_work and not have.has("work_give"):
			var here := scr.game.marker_at(me["pos"])
			rows.append(["공작 바치기", "필요한 눈이 아님" if not here.is_empty() and str(here["role"]) == "work" else "공작 마커 칸에 서 있어야 함"])
	elif not have.has("scene_check") and not have.has("scene_pay"):
		rows.append(["장면 판정·바치기", "장면 자리(금색 점선 칸)에 서 있어야 함"])
	return rows


func _status_line() -> String:
	## 남은 주사위, 공짜 행동(아이템 · 능력)을 썼는지
	if scr.game.phase != "turn" or scr.game.current != scr.human:
		return ""
	var me: Dictionary = scr.game.players[scr.human]
	var parts := ["주사위 %d개 남음" % scr.game.my_dice(scr.human).size()]
	parts.append("아이템 %d/%d장 씀 (공짜)" % [int(me["item_uses"]), int(scr.game.data.rules["item_uses_per_turn"])])
	var ab: Dictionary = scr.game.ability_def(me)
	if not ab.is_empty():
		parts.append("능력 「%s」 %s" % [ab.get("name", ""), "오늘 썼음" if me["ability_day"] == scr.game.day else "쓸 수 있음 (공짜)" if not scr.game.ability_targets(me).is_empty() else "지금은 못 씀"])
	if scr.game.heavy_count(me) > 0:
		parts.append("무거운 물건: 이동 눈 −%d" % scr.game.heavy_count(me))
	return " · ".join(parts)
