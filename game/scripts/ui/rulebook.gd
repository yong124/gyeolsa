class_name Rulebook
extends PanelContainer
## 규칙 도감. 규칙 요약(text.json "rules")과 타일·카드·세력 목록(데이터)을 탭으로 보여 준다.
## 카드 문구는 데이터에서 바로 가져오므로 JSON을 고치면 도감도 함께 바뀐다.

signal closed

var _data: GameData


func _init(data: GameData) -> void:
	_data = data


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(26))
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(980, 700)
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.title(Loc.t("규칙 도감"), Style.FS_H2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.button(Loc.t("닫기"), func(): closed.emit(), 16, "paper"))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_page(Loc.t("기본 규칙"), _rules_page()))
	tabs.add_child(_page(Loc.t("타일"), _tiles_page()))
	tabs.add_child(_page(Loc.t("세력"), _factions_page()))
	tabs.add_child(_page(Loc.t("아이템"), _cards_page(_data.cards["items"], true)))
	tabs.add_child(_page(Loc.t("이벤트"), _cards_page(_data.cards["events"], false)))
	tabs.add_child(_page(Loc.t("일제 동향"), _cards_page(_data.cards.get("occupation", []), false)))
	if _data.text.has("figures"):
		tabs.add_child(_page(Loc.t("인물"), _figures_page()))


func _page(name: String, content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := UiKit.margin(14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(content)
	sc.add_child(m)
	return sc


func _col() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	return v


func _rules_page() -> Control:
	var v := _col()
	for r in _data.text.get("rules", []):
		v.add_child(UiKit.title(r["title"], 21, Style.SEAL_DARK))
		v.add_child(UiKit.text(r["text"], 16, Style.INK))
	return v


func _tiles_page() -> Control:
	var v := _col()
	var desc := {
		"normal": Loc.t("아무 일도 없는 길입니다."),
		"event": Loc.t("여기서 멈추면 이벤트 카드를 뽑습니다. 쓰고 나면 일반 타일이 됩니다."),
		"item": Loc.t("여기서 멈추면 아이템 카드를 뽑습니다. 쓰고 나면 일반 타일이 됩니다."),
		"check": Loc.t("들어가려면 회피 판정. 실패하면 이동이 끝나고 경찰이 옵니다. 새로 나오면 그 앞에서 멈춥니다."),
		"supply": Loc.t("여기서 멈추면 폭탄을 얻습니다 (폭탄 슬롯이 비었을 때)."),
		"assassin": Loc.t("암살 미션을 가졌으면 들어가는 순간 암살 판정을 합니다."),
		"sabotage": Loc.t("방해작전 미션을 가졌으면 들어가는 순간 회피 판정을 합니다."),
		"bomb": Loc.t("폭파공작 미션과 폭탄을 가졌으면 들어가는 순간 성공합니다."),
		"base": Loc.t("일본군 거점. 들어가면 이동이 끝나고 경찰이 옵니다. 정보탈취 목표이자 감옥입니다."),
		"station": Loc.t("전차 역. 타면 다음 차례에 원하는 역에서 출발합니다."),
	}
	for t in desc:
		var def := _data.tile(t)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		h.add_child(UiKit.icon(load("res://assets/tiles/%s.png" % def.get("texture", t)), Vector2(64, 64)))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var count := int(def.get("count", 0))
		tv.add_child(UiKit.title(def.get("name", t) + (Loc.t("  (%d장)") % count if count > 0 else Loc.t("  (고정)")), 18, Style.SEAL_DARK))
		tv.add_child(UiKit.text(desc[t], 15, Style.INK))
		h.add_child(tv)
		v.add_child(h)
	return v


func _factions_page() -> Control:
	var v := _col()
	for k in _data.faction_keys():
		var f := _data.faction(k)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		h.add_child(UiKit.icon(load(f["emblem"]), Vector2(72, 72)))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UiKit.title(f["name"], 20, Style.SEAL_DARK))
		tv.add_child(UiKit.text(f["desc"], 15, Style.INK))
		tv.add_child(UiKit.text(Loc.t("특성: ") + f["ability"], 15, Style.GOOD, true, 700))
		var a: Dictionary = f.get("active", {})
		if not a.is_empty():
			tv.add_child(UiKit.text(Loc.t("능력 [%s] (하루 1회): %s") % [a["name"], a["desc"]], 15, Style.ITEM, true, 700))
		h.add_child(tv)
		v.add_child(h)
	return v


func _cards_page(list: Array, is_item: bool) -> Control:
	var v := _col()
	for c in list:
		var head: String = "%s  ×%d" % [c["name"], c["count"]]
		if is_item:
			head += "  (%s)" % (Loc.t("소모") if c.get("kind") == "consumable" else Loc.t("지속"))
		v.add_child(UiKit.title(head, 18, Style.SEAL_DARK))
		v.add_child(UiKit.text(c["text"], 14, Style.INK_3))
		v.add_child(UiKit.text(c["effect_text"], 15, Style.INK))
	return v


func _figures_page() -> Control:
	## 실제 인물 소개 (세력별)
	var v := _col()
	var figs: Dictionary = _data.text["figures"]
	v.add_child(UiKit.text(figs.get("note", ""), 13, Style.INK_3))
	for k in _data.faction_keys():
		var f := _data.faction(k)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(UiKit.icon(load(f["emblem"]), Vector2(36, 36)))
		head.add_child(UiKit.title(f["name"], 20, Style.SEAL_DARK))
		v.add_child(head)
		for p in figs.get("list", []):
			if p.get("faction", "") != k:
				continue
			var box := PanelContainer.new()
			box.add_theme_stylebox_override("panel", Style.flat(Color(1, 1, 1, 0.3), Color(Style.INK, 0.12), 1, 2, 10))
			var bv := VBoxContainer.new()
			bv.add_theme_constant_override("separation", 2)
			var nh := HBoxContainer.new()
			nh.add_theme_constant_override("separation", 10)
			nh.add_child(UiKit.title(p["name"], 18, Style.INK, 900))
			var role := UiKit.text(p.get("role", ""), 13, Style.INK_3, false, 700)
			role.size_flags_vertical = Control.SIZE_SHRINK_END
			nh.add_child(role)
			bv.add_child(nh)
			bv.add_child(UiKit.text(p.get("text", ""), 14, Style.INK_2))
			box.add_child(bv)
			v.add_child(box)
	return v
