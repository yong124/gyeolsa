class_name EndingScreenV2
extends Control
## v2 엔딩: 결말 문장 + 요원별 후일담 (4단계 ending 딕셔너리를 그대로 보여 준다).

signal to_menu
signal replay

var game: RulesV2
var human := 0


func _init(g: RulesV2, human_id := 0) -> void:
	game = g
	human = human_id


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := UiKit.paper_panel(34)
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var e: Dictionary = game.ending
	var won: bool = e.get("won", false)
	Music.play("ending")
	v.add_child(UiKit.stamp("대 성 공" if won else "작 전 종 료", 26, Style.GOOD if won else Style.SEAL, -6))
	v.add_child(UiKit.title(str(e.get("title", "")), Style.FS_H1))
	var strike: Dictionary = game.data.strike(str(e.get("target", "")))
	if not strike.is_empty():
		v.add_child(UiKit.text("결행: %s · 장면 %d / %d" % [strike.get("name", ""), int(e.get("scene_index", 0)) + (1 if won else 0), game.scenes.size()], 16, Style.INK_3))
	v.add_child(UiKit.text(str(e.get("text", "")), Style.FS_LEAD, Style.INK))
	v.add_child(UiKit.hsep())
	v.add_child(UiKit.title("요원들의 후일담", Style.FS_H3))
	for ep in e.get("epilogues", []):
		var pid := int(ep["player"])
		var p: Dictionary = game.players[pid]
		var s: Dictionary = game.data.saga(str(ep.get("saga", "")))
		var head := "%s%s — 사연 「%s」 %s" % ["(나) " if pid == human else "", game.char_def(p).get("name", ""), s.get("name", ""),
			"이룸" if ep.get("done", false) else "못 이룸"]
		v.add_child(UiKit.title(head, 17, Style.INK))
		v.add_child(UiKit.text(str(ep.get("text", "")), 16, Style.INK_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(UiKit.button("다시 하기", func(): replay.emit(), 18, "primary"))
	row.add_child(UiKit.button("메인 메뉴", func(): to_menu.emit(), 18, "paper"))
