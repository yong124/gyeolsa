class_name AgentFaceV2
extends Control
## 요원 원형 초상 (좌석 색 테두리, 감옥이면 창살)
var tex: Texture2D
var ring := Color.WHITE
var jailed := false
var full := false   # 동그랗게 자른 초상: 테두리 안을 가득 채운다 (v2 요원 초상)

func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.25))
	draw_circle(c, r, ring)
	draw_circle(c, r - 3.5, Style.PAPER_HI)
	var ir := (r - 3.5) * (1.0 if full else 0.82)
	draw_texture_rect(tex, Rect2(c - Vector2(ir, ir), Vector2(ir, ir) * 2), false, Color(1, 1, 1, 0.55 if jailed else 1.0))
	if jailed:
		for k in 4:
			var x := c.x - r * 0.6 + k * r * 0.4
			draw_line(Vector2(x, c.y - r * 0.85), Vector2(x, c.y + r * 0.85), Color(0.12, 0.1, 0.08, 0.9), 2.5)
