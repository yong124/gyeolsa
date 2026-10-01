class_name ActionBar
extends PanelContainer
## 행동 영역: "지금 할 일" 한 줄 + 붉은 주 행동 버튼 하나 + 보조 행동(능력·건네기·미끼·미션 교체) 아이콘 버튼.

signal primary
signal undo
signal ability
signal give
signal decoy
signal swap

var _doing: Label
var _moves: Control
var _hint: Label
var _btn: Button
var _undo: Button
var _key: Label
var _sec := {}           # name -> Button
var _used_stamp: Control
var _steps := 0
var _steps_max := 0


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	_doing = UiKit.title("", 16, Style.INK)
	top.add_child(_doing)
	_moves = Control.new()
	_moves.custom_minimum_size = Vector2(0, 18)
	_moves.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_moves.draw.connect(_draw_moves)
	top.add_child(_moves)
	_undo = UiKit.button("↶ 되돌리기", func(): undo.emit(), 12, "paper")
	_undo.custom_minimum_size = Vector2(82, 28)
	_undo.tooltip_text = "효과가 없었던 마지막 이동 한 칸을 되돌립니다."
	top.add_child(_undo)
	_hint = UiKit.text("", 13, Style.INK_2, false)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_btn = UiKit.button("", func(): primary.emit(), 21, "primary")
	_btn.custom_minimum_size = Vector2(270, 62)
	_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_btn.expand_icon = false
	_btn.add_theme_constant_override("icon_max_width", 26)
	_btn.add_theme_constant_override("h_separation", 10)
	row.add_child(_btn)
	_key = UiKit.label("Space", 11, Color("#fff5e6"))
	var ks := Style.flat(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), 1, 3, 0)
	ks.content_margin_left = 5
	ks.content_margin_right = 5
	_key.add_theme_stylebox_override("normal", ks)
	_btn.add_child(_key)
	_key.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_key.position.x -= 12
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for spec in [["ability", "능력"], ["give", "건네기"], ["decoy", "미끼"], ["swap", "주사위로 이동"]]:
		var n: String = spec[0]
		var b := UiKit.button(spec[1], func(): emit_signal(n), 12, "paper")
		b.icon = UiKit.ui_icon(n)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62)
		b.clip_text = true
		row.add_child(b)
		_sec[n] = b
	_used_stamp = UiKit.stamp("사용함", 12, Style.SEAL, -12)
	_used_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sec["ability"].add_child(_used_stamp)
	_used_stamp.position = Vector2(14, 22)
	_used_stamp.visible = false


func set_ability(name: String, desc: String) -> void:
	_sec["ability"].text = name
	_sec["ability"].tooltip_text = "세력 능력: %s\n%s\n(하루 1회)" % [name, desc]
	_sec["give"].tooltip_text = "옆 칸에 있는 동료에게 아이템을 건넵니다. (아이템 사용 1회로 셈)"
	_sec["decoy"].tooltip_text = "근처의 동료를 쫓는 경찰을 내 쪽으로 끌어옵니다.\n끌어온 경찰은 이번 차례 끝에 바로 움직입니다."
	_sec["swap"].tooltip_text = "결행 판정 대신 주사위를 굴려 이동합니다."


func refresh(s: Dictionary) -> void:
	## s: {doing, hint, primary_text, primary_icon, primary_on, key, steps, steps_max,
	##     undo_on, ability_on, ability_used, give_on, decoy_on, swap_on, swap_visible}
	_doing.text = s.get("doing", "")
	_hint.text = s.get("hint", "")
	_hint.tooltip_text = _hint.text
	_btn.text = s.get("primary_text", "")
	var ic: String = s.get("primary_icon", "")
	_btn.icon = UiKit.ui_icon(ic + "_light") if ic != "" else null
	_btn.disabled = not s.get("primary_on", false)
	_undo.visible = s.get("undo_on", false)
	_key.visible = s.get("key", false) and not _btn.disabled
	_steps = s.get("steps", 0)
	_steps_max = s.get("steps_max", 0)
	_moves.custom_minimum_size.x = _steps_max * 19
	_moves.queue_redraw()
	_sec["ability"].disabled = not s.get("ability_on", false)
	_used_stamp.visible = s.get("ability_used", false)
	_sec["give"].disabled = not s.get("give_on", false)
	_sec["decoy"].disabled = not s.get("decoy_on", false)
	_sec["decoy"].text = s.get("decoy_label", "미끼")
	_sec["decoy"].tooltip_text = "가까운 요원 한 명에게 경찰을 붙입니다. (차례당 1회, 3칸 안)" if s.get("decoy_label", "") == "밀고" \
		else "근처의 동료를 쫓는 경찰을 내 쪽으로 끌어옵니다.\n끌어온 경찰은 이번 차례 끝에 바로 움직입니다."
	_sec["swap"].disabled = not s.get("swap_on", false)
	_sec["swap"].text = s.get("swap_label", "주사위로 이동")
	_sec["swap"].visible = s.get("swap_visible", true)


func _draw_moves() -> void:
	for i in _steps_max:
		var c := Vector2(9 + i * 19, 9)
		if i < _steps:
			_moves.draw_circle(c, 7, Style.GOLD)
			_moves.draw_arc(c, 7, 0, TAU, 20, Color("#7a5a1e"), 2.0, true)
		else:
			_moves.draw_arc(c, 6, 0, TAU, 20, Color(Style.INK_2, 0.4), 1.5, true)
