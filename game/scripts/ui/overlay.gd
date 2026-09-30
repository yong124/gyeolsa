class_name Overlay
extends Control
## 화면 전체를 덮는 반투명 층. 내용물은 content에 넣는다.

signal clicked

var content: CenterContainer
var _shade: ColorRect


func _init(dim: Color = Color(0, 0, 0, 0.45)) -> void:
	visible = false
	_shade = ColorRect.new()
	_shade.color = dim
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	content = CenterContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)


func _ready() -> void:
	# 앵커는 트리에 들어온 뒤에 잡아야 부모 크기를 따라간다
	for c in [self, _shade, content]:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicked.emit()


func show_with(node: Control) -> void:
	UiKit.clear(content)
	content.add_child(node)
	visible = true
