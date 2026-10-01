class_name CardPeekV2
extends PanelContainer
## 마우스를 올리면 옆에 뜨는 큰 카드: 작은 카드에서 잘린 설명을 다 보여 준다.
## attach(컨트롤, 정보)로 붙인다. 정보는 사전이거나 사전을 돌려주는 Callable(올릴 때마다 새로 만듦).
## 정보: band(띠 글), color(띠 색), art(Texture2D), name, sub, sections [[제목, 본문, (색)]...]

const W := 320.0

var _owner: Control
var _pinned := false   # 캡처용: 마우스가 없어도 띄워 둠
var _band: Label
var _art: TextureRect
var _name: Label
var _sub: Label
var _body: VBoxContainer


func _ready() -> void:
	top_level = true
	z_index = 50
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := Style.flat(Color("#f6efdd"), Color("#bba57c"), 1, 6, 0)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	st.shadow_offset = Vector2(0, 6)
	st.content_margin_bottom = 12
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(W, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	_band = Label.new()
	_band.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_theme_font_size_override("font_size", 14)
	_band.add_theme_font_override("font", Style.sans(800))
	_band.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(_band)
	var m := UiKit.margin(14)
	m.add_theme_constant_override("margin_top", 2)
	v.add_child(m)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	m.add_child(inner)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	inner.add_child(head)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.custom_minimum_size = Vector2(64, 64)
	head.add_child(_art)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 2)
	head.add_child(hv)
	_name = UiKit.title("", 20, Style.INK, 900)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(_name)
	_sub = UiKit.text("", 12, Style.INK_3)
	hv.add_child(_sub)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	inner.add_child(_body)
	for c in [v, m, inner, head, hv, _band, _art, _name, _sub, _body]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func attach(ctrl: Control, info) -> void:
	ctrl.tooltip_text = ""
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	ctrl.mouse_entered.connect(func(): show_for(ctrl, info.call() if info is Callable else info))


func show_for(ctrl: Control, info: Dictionary, pin := false) -> void:
	if info.is_empty():
		return
	_owner = ctrl
	_pinned = pin
	var col: Color = info.get("color", Style.INK_2)
	var bs := Style.flat(col, Color.TRANSPARENT, 0, 0, 5)
	bs.corner_radius_top_left = 5
	bs.corner_radius_top_right = 5
	_band.add_theme_stylebox_override("normal", bs)
	_band.text = str(info.get("band", ""))
	_art.texture = info.get("art", null)
	_art.visible = _art.texture != null
	_name.text = str(info.get("name", ""))
	_sub.text = str(info.get("sub", ""))
	_sub.visible = _sub.text != ""
	UiKit.clear(_body)
	for s in info.get("sections", []):
		if str(s[1]).strip_edges() == "":
			continue
		var line := ColorRect.new()
		line.color = Color(Style.INK, 0.12)
		line.custom_minimum_size = Vector2(0, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(line)
		if str(s[0]) != "":
			var h := UiKit.text(str(s[0]), 12, s[2] if s.size() > 2 else Style.INK_3, false, 800)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_body.add_child(h)
		var b := UiKit.text(str(s[1]), 15, Style.INK)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(W - 30, 0)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(b)
	visible = true
	_place()


func _place() -> void:
	## 줄바꿈 글의 높이는 한 프레임 뒤에야 맞게 나오므로 기다렸다가 크기를 다시 잰다
	modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(_owner):
		return
	size = Vector2(W, 0)
	reset_size()
	var r := _owner.get_global_rect()
	var vp := get_viewport_rect().size
	var s := size
	var x := r.position.x - s.x - 14   # 오른쪽 열의 카드면 왼쪽(보드 위)에
	if x < 8:
		x = r.end.x + 14
	var y := clampf(r.get_center().y - s.y / 2.0, 8, vp.y - s.y - 8)
	global_position = Vector2(clampf(x, 8, vp.x - s.x - 8), y)
	modulate.a = 1.0


func _process(_d: float) -> void:
	if not visible or _pinned:
		return
	if not is_instance_valid(_owner) or not _owner.is_visible_in_tree() \
			or not _owner.get_global_rect().grow(2).has_point(_owner.get_global_mouse_position()):
		visible = false
		_owner = null
