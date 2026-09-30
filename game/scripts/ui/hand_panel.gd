class_name HandPanel
extends PanelContainer
## 내 손패: 미션 카드 · 아이템 카드 · 폭탄 슬롯. 쓸 수 있는 아이템은 금색 테두리로 떠오르고 누르면 사용한다.

signal use_item(index: int)

const CARD := Vector2(118, 172)
const LIFT := 12.0

var game: GameRules
var human := 0
var _row: HBoxContainer
var _sig := ""
var _hint: Label
var _card := CARD


func _init(g: GameRules, human_id: int) -> void:
	game = g
	human = human_id


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiKit.title("내 손 패", 16, Style.INK_2))
	_hint = UiKit.text("", 11, Style.INK_3, false)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_hint)
	v.add_child(head)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	v.add_child(_row)


func refresh(my_turn: bool) -> void:
	var me: Dictionary = game.players[human]
	var usable := []
	for i in me["items"].size():
		usable.append(my_turn and game.item_def(me["items"][i]).has("use") and game.can_use_item(me, i))
	var targets_found := not game.mission_targets(me).is_empty()
	var sig := str([me["mission"], me["items"], me["bombs"], usable, targets_found, me["jailed"]])
	if sig == _sig:
		return
	_sig = sig
	UiKit.clear(_row)
	_hint.text = "빛나는 카드를 눌러 사용" if usable.has(true) else "카드에 마우스를 올리면 설명"
	_row.add_child(_holder(_mission_card(me, targets_found), false, -1))
	var sep := ColorRect.new()
	sep.color = Color(Style.INK, 0.16)
	sep.custom_minimum_size = Vector2(1, _card.y - 20)
	sep.size_flags_vertical = Control.SIZE_SHRINK_END
	_row.add_child(sep)
	for i in me["items"].size():
		var d := game.item_def(me["items"][i])
		var kind := "소모" if d.get("kind") == "consumable" else "지속"
		var c := CardView.face("아 이 템 · %s" % kind, Style.ITEM, load(d.get("image", "res://assets/tiles/item.png")),
			d["name"], d["effect_text"], _card.x, _card.y)
		c.tooltip_text = "%s\n\n%s%s" % [d["text"], d["effect_text"], "\n\n▶ 눌러서 사용" if usable[i] else ""]
		_row.add_child(_holder(c, usable[i], i))
	for k in range(me["items"].size(), game.data.balance["hand_limit"]):
		_row.add_child(_slot("아이템 칸\n비어 있음"))
	if me["bombs"] > 0:
		var bomb := TextureRect.new()
		bomb.texture = load("res://assets/cards/bomb.png")
		bomb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bomb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		bomb.custom_minimum_size = _card
		bomb.tooltip_text = "폭탄 ×%d\n%s" % [me["bombs"], game.item_def("bomb")["effect_text"]]
		_row.add_child(_holder(bomb, false, -1))
	else:
		_row.add_child(_slot("폭탄 슬롯\n비어 있음"))


func _mission_card(me: Dictionary, found: bool) -> Control:
	var t: String = me["mission"].get("type", "")
	if t == "":
		return _slot("미션 없음")
	var m := game.data.mission(t)
	var art_path := "res://assets/tiles/%s.png" % m.get("tile", "base")
	var target := ""
	if me["mission"].has("base"):
		target = "목표 %s\n" % game.data.base_names[me["mission"]["base"]]
	elif not found:
		target = "목표 미발견\n"
	var desc := "%s성공 시 광복 +%d" % [target, int(m.get("reward", 1))]
	var c := CardView.face("미 션", Style.MISSION, load(art_path), m["name"], desc, _card.x, _card.y)
	var eff: String = m.get("effect_text", "")
	if me["mission"].has("base"):
		eff = eff.replace("{base}", game.data.base_names[me["mission"]["base"]])
	var base_name: String = game.data.base_names[me["mission"]["base"]] if me["mission"].has("base") else ""
	c.tooltip_text = "%s\n\n%s%s" % [m.get("text", "").replace("{base}", base_name), eff,
		"" if found else "\n\n아직 목표 타일이 깔리지 않았습니다. 새 길을 열어 찾으세요."]
	return c


func _slot(t: String) -> Control:
	var c := Slot.new()
	c.text = t
	c.custom_minimum_size = _card
	var h := Control.new()
	h.custom_minimum_size = _card + Vector2(0, LIFT)
	h.add_child(c)
	c.position = Vector2(0, LIFT)
	return h


func _holder(card: Control, usable: bool, index: int) -> Control:
	## 카드를 살짝 띄울 수 있게 감싼다. 쓸 수 있으면 금색 테두리 + 누르면 사용
	var h := Control.new()
	h.custom_minimum_size = _card + Vector2(0, LIFT)
	h.add_child(card)
	card.position = Vector2(0, LIFT)
	card.size = _card
	if usable:
		var glow := Glow.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(glow)
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.position.y = LIFT * 0.4
		card.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				use_item.emit(index))
	var base_y := card.position.y
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(func():
		card.create_tween().tween_property(card, "position:y", 0.0, 0.12))
	card.mouse_exited.connect(func():
		card.create_tween().tween_property(card, "position:y", base_y, 0.12))
	return h


class Slot extends Control:
	var text := ""

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
		for i in 4:
			draw_dashed_line(pts[i], pts[i + 1], Color(Style.INK_2, 0.45), 1.5, 6.0)
		var font := Style.sans(600)
		var lines := text.split("\n")
		for k in lines.size():
			var w := font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2((size.x - w) / 2, size.y / 2 - 4 + k * 17), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.INK_3)


class Glow extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var a := 0.65 + 0.35 * sin(_t * 4.0)
		draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(Style.GOLD_HI, a), false, 3.0)
		var font := Style.sans(800)
		var r := Rect2(size.x / 2 - 22, size.y - 12, 44, 20)
		draw_rect(r, Style.GOLD)
		draw_string(font, r.position + Vector2(9, 15), "사용", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.INK)
