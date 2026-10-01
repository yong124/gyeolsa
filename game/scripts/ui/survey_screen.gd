class_name SurveyScreen
extends Control
## 플레이테스트 설문: 판이 끝난 뒤 한 사람씩 답한다. 답은 그 판의 기록 파일(PlaytestLog)에 붙는다.

signal finished

var _log: Dictionary
var _seats: Array     # 사람 자리 [{"id", "name"}]
var _ans := {}
var _body: VBoxContainer
var _who: OptionButton
var _texts := {}
var _checks := {}     # "confusing" / "cut" → {rule key: CheckBox}
var _seg := {}        # 질문 키 → [Button]


func _init(log: Dictionary, seats: Array) -> void:
	_log = log
	_seats = seats


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Style.DESK
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var pad := MarginContainer.new()
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 30)
	center.add_child(pad)
	var d := UiKit.dossier(820, "작전 후 설문", "플 레 이 테 스 트")
	pad.add_child(d[0])
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	d[1].add_child(_body)
	_build()


func _build() -> void:
	UiKit.clear(_body)
	_ans = {}
	_texts.clear()
	_checks.clear()
	_seg.clear()
	var answered: int = _log.get("survey", []).size()
	_body.add_child(UiKit.text("솔직하게 답해 주세요. 답은 이 컴퓨터의 기록 파일에만 저장됩니다.%s" % (
		"  (지금까지 %d명 응답)" % answered if answered > 0 else ""), 15, Style.INK_3))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_key("응답자"))
	_who = OptionButton.new()
	for s in _seats:
		_who.add_item(s["name"])
	_who.add_item("구경한 사람")
	_who.select(mini(answered, _seats.size()))
	row.add_child(_who)
	_body.add_child(row)
	_body.add_child(UiKit.hsep())

	for q in PlaytestLog.SCALES:
		_body.add_child(_key(q[1]))
		_body.add_child(_scale(q[0], ["1 전혀", "2", "3", "4", "5 매우"]))
	_body.add_child(_key("판 길이는?"))
	_body.add_child(_scale("length", PlaytestLog.LENGTH))
	_body.add_child(UiKit.hsep())

	_body.add_child(_key("헷갈렸던 규칙 (여러 개 고를 수 있음)"))
	_body.add_child(_rule_grid("confusing"))
	_body.add_child(_key("빼도 재미가 줄지 않을 것 같은 규칙"))
	_body.add_child(_rule_grid("cut"))
	_body.add_child(UiKit.hsep())

	for t in [["best", "가장 재미있었던 순간"], ["worst", "가장 답답하거나 지루했던 순간"], ["other", "그 밖에 하고 싶은 말"]]:
		_body.add_child(_key(t[1]))
		var e := TextEdit.new()
		e.custom_minimum_size = Vector2(0, 64)
		e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		_body.add_child(e)
		_texts[t[0]] = e

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var next := UiKit.button("저장하고 다음 사람", func():
		_save()
		_build(), 18, "paper")
	var done := UiKit.button("저장하고 끝내기", func():
		_save()
		finished.emit(), 18, "primary")
	var skip := UiKit.button("건너뛰기", func(): finished.emit(), 16, "tab")
	for b in [done, next, skip]:
		b.custom_minimum_size = Vector2(0, 50)
		buttons.add_child(b)
	_body.add_child(buttons)


func _key(t: String) -> Label:
	return UiKit.title(t, 17, Style.INK, 700)


func _scale(key: String, labels: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	_seg[key] = []
	for i in labels.size():
		var val := i + 1
		var b := UiKit.button(labels[i], func():
			Sfx.play("click")
			_ans[key] = val
			for x in _seg[key]:
				Style.style_button(x, "primary" if x.get_meta("val") == val else "paper"), 15, "paper")
		b.set_meta("val", val)
		b.custom_minimum_size = Vector2(96, 38)
		h.add_child(b)
		_seg[key].append(b)
	return h


func _rule_grid(group: String) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	_checks[group] = {}
	for r in PlaytestLog.RULES:
		var c := CheckBox.new()
		c.text = r[1]
		c.focus_mode = Control.FOCUS_NONE
		c.add_theme_color_override("font_color", Style.INK)
		c.add_theme_color_override("font_pressed_color", Style.SEAL_DARK)
		g.add_child(c)
		_checks[group][r[0]] = c
	return g


func _save() -> void:
	var a := _ans.duplicate()
	var sel := _who.selected
	a["seat"] = _seats[sel]["id"] if sel < _seats.size() else -1
	a["who"] = _who.get_item_text(sel)
	for g in _checks:
		var picked := []
		for k in _checks[g]:
			if _checks[g][k].button_pressed:
				picked.append(k)
		a[g] = picked
	for k in _texts:
		a[k] = _texts[k].text.strip_edges()
	a["time"] = Time.get_datetime_string_from_system(false, true)
	PlaytestLog.add_survey(_log, a)
