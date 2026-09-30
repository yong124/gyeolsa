class_name LogTicker
extends PanelContainer
## 작전 기록: 평소엔 최근 소식 한 줄, "작전 기록"을 누르면 위로 서랍이 열려 전체 기록을 보여 준다.

var game: GameRules
var drawer: PanelContainer      # 게임 화면이 원하는 위치에 붙인다
var _date: Label
var _line: RichTextLabel
var _log: RichTextLabel
var _count := 0
var _btn: Button


func _init(g: GameRules) -> void:
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
	_btn = UiKit.button(Loc.t("작전 기록 ▴"), toggle, 12, "dark")
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
	var dt := UiKit.label(Loc.t("작전 기록"), 18, Style.ON_DARK_TITLE)
	dt.add_theme_font_override("font", Style.serif(800))
	dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dt)
	dh.add_child(UiKit.button(Loc.t("닫기"), toggle, 12, "dark"))
	dv.add_child(dh)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	dv.add_child(_log)


func toggle() -> void:
	drawer.visible = not drawer.visible
	_btn.text = Loc.t("작전 기록 ▾") if drawer.visible else Loc.t("작전 기록 ▴")
	Sfx.play("click")


static func _has_any(s: String, words: Array) -> bool:
	for w in words:
		if w in s:
			return true
	return false


static func tone_of(line: String) -> Color:
	# 로그에는 어조 정보가 없어 낱말로 가른다 (한국어·영어)
	var low := line.to_lower()
	if _has_any(low, ["광복", "성공", "구출", "liberation", "success", "rescue"]):
		return Style.GOOD_ON_DARK
	if _has_any(low, ["체포", "투옥", "실패", "arrest", "jail", "fail"]):
		return Style.BAD_ON_DARK
	if _has_any(low, ["경찰", "검문", "police", "checkpoint"]):
		return UiKit.COL_WARN
	if line.begins_with("──") or line.begins_with("["):
		return Style.ON_DARK_ACCENT
	return Color("#d8cbb4")


func refresh() -> void:
	_date.text = game.date_label()
	while _count < game.log_lines.size():
		var line: String = game.log_lines[_count]
		var col := tone_of(line)
		if line.begins_with("──"):
			_log.append_text("\n[color=#%s][b]%s[/b][/color]\n" % [col.to_html(false), line.strip_edges().trim_prefix("──").trim_suffix("──").strip_edges()])
		else:
			_log.append_text("[color=#%s]%s[/color]\n" % [col.to_html(false), line])
		_count += 1
		if not line.begins_with("──"):
			_line.text = "▸ [color=#%s]%s[/color]" % [col.to_html(false), _emph(line)]


func _emph(line: String) -> String:
	## "이름: 내용" 에서 이름을 굵게
	var i := line.find(": ")
	if i > 0 and i < 24:
		return "[b]%s[/b]  %s" % [line.substr(0, i).split(" (")[0], line.substr(i + 2)]
	return line
