class_name IntroScreen
extends Control
## 도입부: 타이틀 아트가 천천히 다가오는 배경 위로 이야기가 한 장씩 나타난다.
## 클릭·스페이스로 다음 장, ESC나 "건너뛰기"로 끝. 문구는 data/text.json의 "intro".

signal finished

const PAGE_TIME := 4.2

var _pages: Array
var _index := -1
var _art: TextureRect
var _shade: ColorRect
var _caption: Label
var _body: Label
var _hint: Label
var _timer := 0.0
var _busy := false
var _done := false


func _init(data: GameData) -> void:
	_pages = data.text.get("intro", [])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_art = TextureRect.new()
	_art.texture = load("res://assets/ui/title.png")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.modulate = Color(1, 1, 1, 0)
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.pivot_offset = Vector2(800, 450)

	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.62)
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption = UiKit.label("", 20, UiKit.COL_ACCENT)
	_caption.add_theme_font_override("font", Style.sans(700))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_caption)
	_body = UiKit.label("", 40, UiKit.COL_TITLE)
	_body.add_theme_font_override("font", Style.serif(700))
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_body)

	_hint = UiKit.label(Loc.t("클릭하면 다음으로  ·  ESC 건너뛰기"), 14, Color(1, 1, 1, 0.45))
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 50
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var skip := UiKit.button(Loc.t("건너뛰기 ▶"), _finish, 16)
	add_child(skip)
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip.position += Vector2(-150, 24)

	# 배경은 도입부 내내 천천히 확대 (켄 번스 효과)
	var tw := create_tween().set_parallel()
	tw.tween_property(_art, "modulate:a", 1.0, 2.0)
	tw.tween_property(_art, "scale", Vector2(1.12, 1.12), PAGE_TIME * maxf(_pages.size(), 1) + 2.0)
	_next()


func _process(delta: float) -> void:
	if _busy:
		return
	_timer += delta
	if _timer >= PAGE_TIME:
		_next()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _timer > 0.6:
		_next()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_finish()
		elif event.keycode in [KEY_SPACE, KEY_ENTER] and _timer > 0.6:
			_next()


func _next() -> void:
	if _busy:
		return
	_index += 1
	if _index >= _pages.size():
		_finish()
		return
	_busy = true
	_timer = 0.0
	var fade_out := create_tween().set_parallel()
	fade_out.tween_property(_caption, "modulate:a", 0.0, 0.35)
	fade_out.tween_property(_body, "modulate:a", 0.0, 0.35)
	await fade_out.finished
	var page: Dictionary = _pages[_index]
	_caption.text = page.get("caption", "")
	_body.text = page.get("text", "")
	Sfx.play("card", 0.05, 0.5)
	var fade_in := create_tween()
	fade_in.tween_property(_caption, "modulate:a", 1.0, 0.5)
	fade_in.tween_property(_body, "modulate:a", 1.0, 0.8)
	await fade_in.finished
	_busy = false


func _finish() -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	await tw.finished
	finished.emit()
