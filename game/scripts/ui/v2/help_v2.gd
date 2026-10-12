class_name HelpV2
extends RefCounted
## 도움말 「?」 창 (지시서 T2): 탭 = 행동 · 미션 · 타일 · 판정 · 경찰 · 결행. 글은 data/v2/help.json (규칙서 문장을 줄인 것).
## 위쪽 띠의 「?」, 일시정지 메뉴, 타이틀 메뉴, 첫 판 쪽지의 「자세히」가 같은 창을 연다.


static func panel(data: GameDataV2, close: Callable, tab_id := "") -> Control:
	var tabs: Array = data.help.get("tabs", [])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var panel := UiKit.paper_panel(22)
	panel.custom_minimum_size = Vector2(720, 0)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := UiKit.title("도움말", Style.FS_H3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.button("닫기", close, 15, "paper"))
	if tabs.is_empty():
		box.add_child(UiKit.text("도움말 데이터가 없습니다.", Style.FS_BODY))
		return panel
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	box.add_child(row)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var btns := {}
	var show := func(id: String):
		for k in btns:
			Style.style_button(btns[k], "primary" if k == id else "tab")
		_fill(body, data, id)
	var first := tab_id if tabs.any(func(t): return str(t["id"]) == tab_id) else str(tabs[0]["id"])
	for t in tabs:
		var tid := str(t["id"])
		var b := UiKit.button(str(t["title"]), func(): show.call(tid), 15, "tab")
		b.custom_minimum_size = Vector2(0, 34)
		btns[tid] = b
		row.add_child(b)
	show.call(first)
	return panel


static func _fill(body: VBoxContainer, data: GameDataV2, id: String) -> void:
	UiKit.clear(body)
	for t in data.help.get("tabs", []):
		if str(t["id"]) != id:
			continue
		var intro := UiKit.text(data.help_text(str(t.get("intro", ""))), 15, Style.INK_2, true, 700)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(intro)
		for it in t.get("items", []):
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			body.add_child(line)
			if it.has("tile") and ResourceLoader.exists("res://assets/tiles/%s.png" % it["tile"]):
				var tex := TextureRect.new()
				tex.texture = load("res://assets/tiles/%s.png" % it["tile"])
				tex.custom_minimum_size = Vector2(52, 52)
				tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				line.add_child(tex)
			var name_lbl := UiKit.text(str(it["name"]), 16, Style.SEAL, false, 900)
			name_lbl.custom_minimum_size = Vector2(96, 0)
			name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(name_lbl)
			var txt := UiKit.text(data.help_text(str(it["text"])), 15, Style.INK, true, 600)
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(txt)
		return
