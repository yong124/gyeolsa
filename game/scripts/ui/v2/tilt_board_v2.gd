class_name TiltBoardV2
extends Control
## 기운 보드 (지시서 M2): 보드(틀 포함)를 화면 밖 SubViewport에 지금처럼 2D로 그리고,
## 그 그림을 위가 좁은 사다리꼴에 원근 그대로 비춘다(호모그래피 셰이더). 말(요원 · 경찰)은 보드 그림에서 빼고
## 이 위에 똑바로 세워 그린다. 입력은 화면 좌표 → 보드 좌표로 거꾸로 바꿔 SubViewport에 넘긴다.

const VP_SIDE := 880                 # 보드를 그리는 해상도 (화면에 비출 때 줄어듦)
const TOP_RATIO := 0.74              # 위 변 / 아래 변 (약 30° 눕힘)
const HEIGHT_RATIO := 0.76           # 높이 / 아래 변
const THICK := 16.0                  # 판의 두께 (아래 옆면)

var vp: SubViewport
var frame: Control
var board: BoardViewV2
var tilt := true
var quad: PackedVector2Array = []    # 화면 위 네 꼭짓점 (이 Control 기준): 왼위 · 오른위 · 오른아래 · 왼아래
var _h := []                         # 정방향 (uv → 화면) 3×3
var _inv := []                       # 역방향 (화면 → uv) 3×3
var _surface: ColorRect
var _pieces: Control
var _mat: ShaderMaterial


func setup(f: Control, b: BoardViewV2) -> void:
	frame = f
	board = b
	b.draw_pieces = false
	vp = SubViewport.new()
	vp.size = Vector2i(VP_SIDE, VP_SIDE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.gui_embed_subwindows = true
	add_child(vp)
	if f.get_parent() != null:
		f.get_parent().remove_child(f)
	vp.add_child(f)
	f.position = Vector2.ZERO
	f.size = Vector2(VP_SIDE, VP_SIDE)
	_surface = ColorRect.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D board_tex : filter_linear;
uniform mat3 inv;
uniform vec2 rect_size;
uniform vec2 offset;
void fragment() {
	vec2 p = UV * rect_size + offset;
	vec3 q = inv * vec3(p, 1.0);
	vec2 uv = q.xy / q.z;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(board_tex, uv);
	}
}
"""
	_mat.shader = sh
	_mat.set_shader_parameter("board_tex", vp.get_texture())
	_surface.material = _mat
	add_child(_surface)
	_pieces = Control.new()
	_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pieces.draw.connect(_draw_pieces)
	add_child(_pieces)
	mouse_filter = Control.MOUSE_FILTER_STOP


func place(r: Rect2) -> void:
	## r: 보드가 들어갈 화면 영역 (이 Control의 부모 기준). 그 안에 사다리꼴을 가운데 맞춘다
	position = r.position
	size = r.size
	var wb := minf(r.size.x, (r.size.y - THICK - 10.0) / HEIGHT_RATIO)
	if not tilt:
		wb = minf(r.size.x, r.size.y)
	var wt := wb * (TOP_RATIO if tilt else 1.0)
	var hq := wb * (HEIGHT_RATIO if tilt else 1.0)
	var cx := r.size.x / 2.0
	var y0 := (r.size.y - hq - (THICK if tilt else 0.0)) / 2.0
	quad = PackedVector2Array([Vector2(cx - wt / 2, y0), Vector2(cx + wt / 2, y0), Vector2(cx + wb / 2, y0 + hq), Vector2(cx - wb / 2, y0 + hq)])
	_h = _square_to_quad(quad)
	_inv = _invert(_h)
	var bb := bbox()
	_surface.position = bb.position
	_surface.size = bb.size
	_mat.set_shader_parameter("rect_size", bb.size)
	_mat.set_shader_parameter("offset", bb.position)
	var m: Array = _inv
	_mat.set_shader_parameter("inv", Basis(Vector3(m[0], m[3], m[6]), Vector3(m[1], m[4], m[7]), Vector3(m[2], m[5], m[8])))
	_pieces.position = Vector2.ZERO
	_pieces.size = size
	queue_redraw()


func bbox() -> Rect2:
	## 보드 그림이 차지하는 사각형 (이 Control 기준)
	if quad.is_empty():
		return Rect2(Vector2.ZERO, size)
	var mn := quad[0]
	var mx := quad[0]
	for p in quad:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)


func screen_rect() -> Rect2:
	## 보드 그림이 차지하는 사각형 (부모 기준) — 배너 · 안내 · 분위기 층 자리
	var bb := bbox()
	return Rect2(position + bb.position, bb.size)


# ---------------------------------------------------------------- 투영

func _square_to_quad(q: PackedVector2Array) -> Array:
	## 단위 정사각형 (0,0)(1,0)(1,1)(0,1) → 사각형 q의 투영 변환 (Heckbert)
	var x0 := q[0].x
	var y0 := q[0].y
	var x1 := q[1].x
	var y1 := q[1].y
	var x2 := q[2].x
	var y2 := q[2].y
	var x3 := q[3].x
	var y3 := q[3].y
	var dx1 := x1 - x2
	var dx2 := x3 - x2
	var dx3 := x0 - x1 + x2 - x3
	var dy1 := y1 - y2
	var dy2 := y3 - y2
	var dy3 := y0 - y1 + y2 - y3
	var g := 0.0
	var hh := 0.0
	if absf(dx3) > 1e-6 or absf(dy3) > 1e-6:
		var den := dx1 * dy2 - dx2 * dy1
		g = (dx3 * dy2 - dx2 * dy3) / den
		hh = (dx1 * dy3 - dx3 * dy1) / den
	var a := x1 - x0 + g * x1
	var b := x3 - x0 + hh * x3
	var d := y1 - y0 + g * y1
	var e := y3 - y0 + hh * y3
	return [a, b, x0, d, e, y0, g, hh, 1.0]


func _invert(m: Array) -> Array:
	var a: float = m[0]
	var b: float = m[1]
	var c: float = m[2]
	var d: float = m[3]
	var e: float = m[4]
	var f: float = m[5]
	var g: float = m[6]
	var h: float = m[7]
	var i: float = m[8]
	var A := e * i - f * h
	var B := -(d * i - f * g)
	var C := d * h - e * g
	var det := a * A + b * B + c * C
	if absf(det) < 1e-9:
		return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	var inv := [A, -(b * i - c * h), b * f - c * e,
		B, a * i - c * g, -(a * f - c * d),
		C, -(a * h - b * g), a * e - b * d]
	for k in 9:
		inv[k] = float(inv[k]) / det
	return inv


func _apply(m: Array, p: Vector2) -> Vector2:
	var w: float = m[6] * p.x + m[7] * p.y + m[8]
	return Vector2((m[0] * p.x + m[1] * p.y + m[2]) / w, (m[3] * p.x + m[4] * p.y + m[5]) / w)


func uv_to_local(uv: Vector2) -> Vector2:
	return _apply(_h, uv)


func local_to_uv(p: Vector2) -> Vector2:
	return _apply(_inv, p)


func board_to_local(p: Vector2) -> Vector2:
	## 보드 Control 좌표 → 이 Control 좌표
	return uv_to_local((board.position + p) / float(VP_SIDE))


func cell_to_screen(c: Vector2) -> Vector2:
	## 칸 가운데 → 부모(게임 화면) 좌표
	return position + board_to_local(board.cell_rect_f(c).get_center())


# ---------------------------------------------------------------- 그리기

func _process(_delta: float) -> void:
	if _pieces != null:
		_pieces.queue_redraw()


func _draw() -> void:
	if quad.is_empty():
		return
	# 책상 위 그림자와 판의 두께 (아래 옆면)
	var sh := PackedVector2Array()
	for p in quad:
		sh.append(p + Vector2(0, THICK + 22))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	if tilt:
		var side := PackedVector2Array([quad[3], quad[2], quad[2] + Vector2(0, THICK), quad[3] + Vector2(0, THICK)])
		draw_colored_polygon(side, Color("#3a281a"))
		draw_line(quad[3] + Vector2(0, THICK), quad[2] + Vector2(0, THICK), Color("#22170f"), 2.0)


func _draw_pieces() -> void:
	## 서 있는 말: 칸의 바닥점에 그림자, 그 위로 초상 동그라미. 먼 줄일수록 작게
	if board == null or board.game == null or quad.is_empty():
		return
	var g: RulesV2 = board.game
	var font := Style.sans(800)
	# 경찰 (먼 것부터)
	var order := []
	for pid in board.vis_police:
		order.append(["p", pid, board.vis_police[pid]["pos"]])
	var stacks := {}
	for id in board.vis_players:
		var key: Vector2 = board.vis_players[id].round()
		stacks[key] = stacks.get(key, []) + [id]
	for key in stacks:
		var group: Array = stacks[key]
		for i in group.size():
			order.append(["a", group[i], board.vis_players[group[i]], i, group.size()])
	# 먼 줄부터, 한 칸 안에서는 뒤 줄(앞 번호)부터 그린다
	order.sort_custom(func(x, y): return float(x[2].y) + (0.001 * float(x[3]) if x[0] == "a" else 0.0) < float(y[2].y) + (0.001 * float(y[3]) if y[0] == "a" else 0.0))
	for it in order:
		var r: Rect2 = board.cell_rect_f(it[2])
		var cw: float = board_to_local(Vector2(r.end.x, r.get_center().y)).x - board_to_local(Vector2(r.position.x, r.get_center().y)).x
		var foot: Vector2 = board_to_local(Vector2(r.get_center().x, r.position.y + r.size.y * 0.72))
		if it[0] == "p":
			var v: Dictionary = board.vis_police[it[1]]
			var alpha: float = v["alpha"] * (1.0 if v["active"] else 0.7)
			var rad := cw * 0.30
			foot += Vector2(cw * 0.24, -cw * 0.10)
			_shadow(foot, rad, alpha)
			var ctr := foot - Vector2(0, rad * 1.05)
			if v["active"]:
				var pulse: float = 0.5 + 0.5 * sin(board._pulse * 5.0 + float(it[1]))
				_pieces.draw_circle(ctr, rad + 5 + pulse * 4, Color(Style.SEAL, 0.25 * alpha))
			_pieces.draw_circle(ctr, rad + 3, Color(Style.SEAL if v["active"] else Color("#8a6d3b"), alpha))
			_pieces.draw_circle(ctr, rad, Color(0.12, 0.1, 0.09, alpha))
			_pieces.draw_texture_rect(board._police_tex, Rect2(ctr - Vector2(rad, rad), Vector2(rad, rad) * 2), false, Color(1, 1, 1, alpha))
			_pieces.draw_circle(ctr + Vector2(rad * 0.72, rad * 0.72), rad * 0.26, Color(Style.seat(int(it[1])), alpha))
			continue
		var id: int = it[1]
		var p: Dictionary = g.players[id]
		var n: int = it[4]
		var slot: int = it[3]
		var rad := cw * (0.36 if n == 1 else 0.25 if n == 2 else 0.22)
		if n > 1:
			# 한 칸에 여럿: 둘이면 나란히, 셋 이상이면 뒤 줄 · 앞 줄 (뒤 줄을 먼저 그림)
			var per := n if n <= 2 else int(ceil(n / 2.0))
			var row := slot / per
			var col := slot % per
			var in_row := mini(per, n - row * per)
			var rows := int(ceil(float(n) / per))
			foot += Vector2((col - (in_row - 1) / 2.0) * cw * 0.46, (row - (rows - 1)) * cw * 0.26)
		var jailed: bool = board.vis_jailed.get(id, false)
		var is_cur: bool = id == g.current and g.phase in ["turn", "choice"]
		var lift := float(board._move_lift.get(id, 0.0))
		if is_cur:
			lift += 3.0 + 3.0 * sin(board._pulse * 3.5)
		var alpha := 0.6 if jailed else 1.0
		_shadow(foot, rad, alpha)
		var ctr := foot - Vector2(0, rad * 1.15 + lift)
		var ring: Color = Style.seat(id)
		if is_cur:
			_pieces.draw_circle(ctr, rad + cw * 0.1, Color(Style.GOLD_HI, 0.45 + 0.2 * sin(board._pulse * 4.0)))
		# 받침 (아래로 조금 두께)
		_pieces.draw_circle(ctr + Vector2(0, rad * 0.16), rad + 4, Color(ring.darkened(0.45), alpha))
		_pieces.draw_circle(ctr, rad + 4, Color(ring, alpha))
		_pieces.draw_circle(ctr, rad + 1, Color(Style.PAPER_HI, alpha))
		var cid := str(p["character"])
		var tex: Texture2D = ArtV2.get_tex("token", cid, board._faction_tex.get(str(g.char_def(p).get("faction", ""))))
		if tex != null:
			var ir := rad if ArtV2.has("token", cid) else rad * 0.8
			_pieces.draw_texture_rect(tex, Rect2(ctr - Vector2(ir, ir), Vector2(ir, ir) * 2), false, Color(1, 1, 1, alpha))
		if jailed:
			for k in 4:
				var x := ctr.x - rad * 0.75 + k * rad * 0.5
				_pieces.draw_line(Vector2(x, ctr.y - rad - 2), Vector2(x, ctr.y + rad + 2), Color(0.1, 0.08, 0.06), 3.0)
		if n > 1:
			if slot == n - 1:
				_group_tag(it[2], cw, foot, rad, g)   # 여럿이 한 칸이면 이름표는 하나로 (맨 앞 말 위)
			continue
		if id == board.human_id or is_cur:
			var tag: String = TextV2.agent_tag(g, id, board.human_id)
			var fs := maxi(10, int(cw * 0.15))
			var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
			var tr := Rect2(ctr.x - w / 2, ctr.y - rad - fs * 1.45, w, fs * 1.3)
			_pieces.draw_rect(tr, ring)
			_pieces.draw_rect(tr, Color(Style.PAPER_HI, 0.9), false, 1.5)
			_pieces.draw_string(font, tr.position + Vector2(5, fs * 1.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _group_tag(cell: Vector2, cw: float, foot: Vector2, rad: float, g: RulesV2) -> void:
	## 한 칸에 모인 말들의 이름표 하나: 「나 외 N명」 또는 「N명」 (누가 있는지는 풍선 · 동료 레일에서)
	var ids := []
	for id in board.vis_players:
		if board.vis_players[id].round() == cell.round():
			ids.append(id)
	var mine: bool = board.human_id in ids
	var tag := ("나 외 %d명" % (ids.size() - 1)) if mine else "%d명" % ids.size()
	var font := Style.sans(800)
	var fs := maxi(10, int(cw * 0.15))
	var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
	var top := foot.y - rad * 2.3 - cw * 0.3 - fs * 1.4
	var tr := Rect2(foot.x - w / 2, top, w, fs * 1.3)
	_pieces.draw_rect(tr, Style.seat(board.human_id) if mine else Style.INK)
	_pieces.draw_rect(tr, Color(Style.PAPER_HI, 0.9), false, 1.5)
	_pieces.draw_string(font, tr.position + Vector2(5, fs * 1.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _shadow(foot: Vector2, rad: float, alpha: float) -> void:
	_pieces.draw_set_transform(foot, 0.0, Vector2(1.0, 0.38))
	_pieces.draw_circle(Vector2.ZERO, rad * 1.05, Color(0.08, 0.05, 0.02, 0.42 * alpha))
	_pieces.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 입력

func _gui_input(event: InputEvent) -> void:
	## 화면 좌표 → 보드 좌표로 바꿔 보드의 입력 처리에 바로 넘긴다 (SubViewport의 GUI를 거치지 않음)
	if not (event is InputEventMouse) or board == null:
		return
	var uv := local_to_uv(event.position)
	var inside := uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0
	var e2: InputEventMouse = event.duplicate()
	e2.position = (uv * float(VP_SIDE) - board.position) if inside else Vector2(-50, -50)
	e2.global_position = e2.position
	board._gui_input(e2)
	tooltip_text = board.tooltip_text if inside else ""   # 칸 풍선 도움말 (보드가 정한 글을 그대로)
	accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and board != null:
		var e := InputEventMouseMotion.new()
		e.position = Vector2(-50, -50)
		e.global_position = e.position
		board._gui_input(e)
