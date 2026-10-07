class_name SettingsPanel
extends PanelContainer
## 설정 창: 전체화면, 음량, AI 속도, 연출 줄이기. 바꾸는 즉시 적용·저장한다.

signal closed


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.paper(28))
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(540, 0)
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	v.add_child(UiKit.label("환 경 설 정", Style.FS_SMALL, Style.SEAL))
	v.add_child(UiKit.title("설정", Style.FS_H2))
	v.add_child(UiKit.hsep())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)

	grid.add_child(_key("전체화면"))
	var fs := CheckBox.new()
	fs.button_pressed = Prefs.fullscreen
	fs.toggled.connect(func(on):
		Prefs.fullscreen = on
		Prefs.apply_video()
		Prefs.save())
	grid.add_child(fs)

	grid.add_child(_key("배경음"))
	grid.add_child(_slider(Prefs.bgm_volume, func(x):
		Prefs.bgm_volume = x
		Music.refresh_volume()))

	grid.add_child(_key("효과음"))
	grid.add_child(_slider(Prefs.sfx_volume, func(x):
		Prefs.sfx_volume = x
		Sfx.play("click")))

	grid.add_child(_key("연출"))
	var cm := OptionButton.new()
	for nm in ["컷신 전부", "같은 컷신은 처음만", "컷신 줄임 (배너만)"]:
		cm.add_item(nm)
	cm.select(Prefs.v2_cine)
	cm.item_selected.connect(func(i):
		Prefs.v2_cine = i
		Prefs.save())
	grid.add_child(cm)
	grid.add_child(_key("동료 차례 속도"))
	var sp := OptionButton.new()
	for s in Prefs.SPEEDS:
		sp.add_item(s["name"])
	sp.select(Prefs.speed)
	sp.item_selected.connect(func(i):
		Prefs.speed = i
		Prefs.save())
	grid.add_child(sp)

	grid.add_child(_key("연출 줄이기"))
	var rm := CheckBox.new()
	rm.text = "내 행동 연출도 빠르게"
	rm.button_pressed = Prefs.reduce_motion
	rm.toggled.connect(func(on):
		Prefs.reduce_motion = on
		Prefs.save())
	grid.add_child(rm)

	grid.add_child(_key("플레이테스트"))
	var pt := HBoxContainer.new()
	pt.add_theme_constant_override("separation", 10)
	var pc := CheckBox.new()
	pc.text = "기록과 판 끝 설문"
	pc.button_pressed = Prefs.playtest
	pc.toggled.connect(func(on):
		Prefs.playtest = on
		Prefs.save())
	pt.add_child(pc)
	pt.add_child(UiKit.button("기록 폴더 열기", func(): OS.shell_open(PlaytestLog.folder()), 14, "paper"))
	grid.add_child(pt)

	v.add_child(UiKit.hsep())
	var close := UiKit.button("닫기", func(): closed.emit(), 18, "primary")
	close.custom_minimum_size = Vector2(0, 48)
	v.add_child(close)


func _key(t: String) -> Label:
	return UiKit.title(t, 17, Style.INK_2, 700)


func _slider(value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(260, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(on_change)
	s.drag_ended.connect(func(_c): Prefs.save())
	return s
