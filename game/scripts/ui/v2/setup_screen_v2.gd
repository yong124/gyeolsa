class_name SetupScreenV2
extends Control
## v2 시작: 캐릭터 카드 2장을 무작위로 받아 1장을 고른다 (기획서 19.14). 동료 3명은 나머지에서 무작위.

signal start_requested(defs: Array, seed_value: int)
signal back_requested

var _data: GameDataV2
var _rng := RandomNumberGenerator.new()
var _offer: Array = []
var _box: VBoxContainer


func _init() -> void:
	_data = GameDataV2.load_default()
	_rng.randomize()


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
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)
	_deal()


func _deal() -> void:
	var ids: Array = _data.characters.get("characters", []).map(func(c): return c["id"])
	_offer = []
	while _offer.size() < 2:
		var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
		if not id in _offer:
			_offer.append(id)
	_show()


func _show() -> void:
	UiKit.clear(_box)
	_box.add_child(UiKit.title("새 규칙 v2 (시험판) — 요원 고르기", Style.FS_H2))
	_box.add_child(UiKit.text("캐릭터 카드 2장 중 1장을 고르세요. 동료 셋은 나머지 캐릭터 중에서 무작위로 정해집니다. 4인 기준 규칙입니다.", Style.FS_BODY, Style.INK_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_box.add_child(row)
	for id in _offer:
		row.add_child(_card(str(id)))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	_box.add_child(bottom)
	bottom.add_child(UiKit.button("← 메뉴로", func(): back_requested.emit(), 15, "tab"))


func _card(id: String) -> Control:
	var c: Dictionary = _data.character(id)
	var fac: Dictionary = _data.characters.get("factions", {}).get(c.get("faction", ""), {})
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.flat(Color("#f6efdd"), Style.INK_3, 2, 4, 16))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var path := "res://assets/ui/faction_%s.png" % c.get("faction", "")
	if ResourceLoader.exists(path):
		head.add_child(UiKit.icon(load(path), Vector2(72, 72)))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UiKit.title(str(c.get("name", "")), Style.FS_H3))
	hv.add_child(UiKit.text("%s · %s" % [fac.get("name", ""), c.get("origin", "")], 14, Style.INK_3))
	v.add_child(UiKit.text("특성 (늘): " + str(c.get("trait_text", "")), 15))
	v.add_child(UiKit.text("능력 (하루 1번): " + str(c.get("ability_text", "")), 15))
	v.add_child(UiKit.button("이 요원으로 시작", func(): _start(id), 18, "primary"))
	return p


func _start(id: String) -> void:
	var ids: Array = _data.characters.get("characters", []).map(func(c): return c["id"])
	ids.erase(id)
	var picks := [id]
	while picks.size() < int(_data.rules["players"]):
		var k := _rng.randi_range(0, ids.size() - 1)
		picks.append(ids[k])
		ids.remove_at(k)
	var defs := []
	for i in picks.size():
		var c: Dictionary = _data.character(str(picks[i]))
		defs.append({"name": "나" if i == 0 else str(c.get("name", "")), "character": picks[i]})
	start_requested.emit(defs, _rng.randi())
