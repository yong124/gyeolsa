class_name LogTickerV2
extends PanelContainer
## v2 작전 기록 (v1 LogTicker 모양): 평소엔 최근 소식 한 줄, "작전 기록"을 누르면 위로 서랍이 열린다.

var game: RulesV2
var drawer: PanelContainer
var _date: Label
var _line: RichTextLabel
var _log: RichTextLabel
var _count := 0
var _btn: Button


func _init(g: RulesV2) -> void:
	game = g


func _ready() -> void:
	var st := Style.flat(Color(0, 0, 0, 0.5), Color(Style.ON_DARK, 0.15), 1, 3, 6)
	st.content_margin_left = 10
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(0, 38)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	_date = UiKit.label("", 12, Style.ON_DARK_ACCENT)
	_date.add_theme_font_override("font", Style.serif(700))
	var ds := Style.flat(Color.TRANSPARENT, Color("#7a6440"), 1, 2, 0)
	ds.content_margin_left = 6
	ds.content_margin_right = 6
	_date.add_theme_stylebox_override("normal", ds)
	_date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_date)
	_line = RichTextLabel.new()
	_line.bbcode_enabled = true
	_line.fit_content = true
	_line.scroll_active = false
	_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line.clip_contents = true
	_line.add_theme_font_size_override("normal_font_size", 14)
	_line.add_theme_font_size_override("bold_font_size", 14)
	_line.add_theme_font_override("bold_font", Style.sans(800))
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_line)
	_btn = UiKit.button("작전 기록 ▴", toggle, 12, "dark")
	_btn.custom_minimum_size = Vector2(96, 28)
	_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_btn)

	drawer = PanelContainer.new()
	drawer.add_theme_stylebox_override("panel", Style.ink(14))
	drawer.visible = false
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	drawer.add_child(dv)
	var dh := HBoxContainer.new()
	var dt := UiKit.label("작전 기록", 18, Style.ON_DARK_TITLE)
	dt.add_theme_font_override("font", Style.serif(800))
	dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dt)
	dh.add_child(UiKit.button("닫기", toggle, 12, "dark"))
	dv.add_child(dh)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	dv.add_child(_log)


func toggle() -> void:
	drawer.visible = not drawer.visible
	_btn.text = "작전 기록 ▾" if drawer.visible else "작전 기록 ▴"
	Sfx.play("click")


func refresh() -> void:
	_date.text = game.date_label()
	while _count < game.log_lines.size():
		var line: String = game.log_lines[_count]
		var col := LogTicker.tone_of(line)
		if line.begins_with("──"):
			_log.append_text("\n[color=#%s][b]%s[/b][/color]\n" % [col.to_html(false), line.strip_edges().trim_prefix("──").trim_suffix("──").strip_edges()])
		else:
			_log.append_text("[color=#%s]%s[/color]\n" % [col.to_html(false), line])
		_count += 1
		if not line.begins_with("──"):
			_line.text = "▸ [color=#%s]%s[/color]" % [col.to_html(false), _emph(line)]


func _emph(line: String) -> String:
	var i := line.find(": ")
	if i > 0 and i < 24:
		return "[b]%s[/b]  %s" % [line.substr(0, i), line.substr(i + 2)]
	return line
