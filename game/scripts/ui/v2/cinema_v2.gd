class_name CinemaV2
extends Control
## v2 컷신과 화면 효과 (v2_구현/지시서/V_연출.md 2부).
## - cut(): 그림 한 장을 화면 가운데에 크게 (천천히 다가가는 켄 번스, 초상 줄, 도장). 누르면 넘김
## - slides(): 그림 여러 장을 차례로 (오프닝). 「건너뛰기」
## - shake() · vignette() · ink(): 짧은 효과
## 모든 함수는 await로 끝날 때까지 기다릴 수 있다. m은 속도 배율 (0이면 바로 끝).

var _vig := {}       # {"color", "a"} 가장자리 붉은 빛
var _inks: Array = []   # [{"at", "ok", "t", "life", "seed"}]
var _skip := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 45


func _process(delta: float) -> void:
	if _beat:
		_beat_t += delta
		# 쿵-쿵 · 쉼: 1.1초마다 두 번 뛴다
		var ph := fmod(_beat_t, 1.1)
		var a := maxf(0.0, 1.0 - absf(ph - 0.08) / 0.12) + 0.7 * maxf(0.0, 1.0 - absf(ph - 0.32) / 0.12)
		if _vig.is_empty() or _vig.get("beat", false):
			_vig = {"color": Style.SEAL, "a": 0.32 * a, "beat": true}
	if not _confetti.is_empty():
		for p in _confetti:
			p["y"] += p["vy"] * delta
			p["x"] += p["vx"] * delta + sin(p["y"] * 0.02) * 0.6
			p["rot"] += p["spin"] * delta
		_confetti = _confetti.filter(func(p): return p["y"] < size.y + 30)
	if _inks.is_empty() and _vig.is_empty() and _confetti.is_empty():
		return
	for s in _inks:
		s["t"] += delta
	_inks = _inks.filter(func(s): return s["t"] < s["life"])
	queue_redraw()


# ------------------------------------------------------------------ 컷

func cut(opts: Dictionary, m: float) -> void:
	## opts: tex(Texture2D) · title · sub · stamp(글) · stamp_color · portraits([Texture2D]) · hold(초)
	var tex: Texture2D = opts.get("tex", null)
	if tex == null or m <= 0.0:
		return
	_skip = false
	var layer := _backdrop(0.66)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := UiKit.paper_panel(14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var w := minf(size.x * 0.62, 1000.0)
	var h := minf(w * tex.get_height() / float(tex.get_width()), size.y * 0.58)
	var frame := Control.new()   # 그림이 천천히 커져도 틀 밖으로 나가지 않게
	frame.clip_contents = true
	frame.custom_minimum_size = Vector2(w, h)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(frame)
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.size = Vector2(w, h)
	img.pivot_offset = Vector2(w, h) / 2.0
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(img)
	var portraits: Array = opts.get("portraits", [])
	var row := HBoxContainer.new()
	if not portraits.is_empty():
		# 초상 줄: 그림 아래쪽에 겹쳐 차례로 올라온다
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(row)
		var ph := minf(h * 0.42, 150.0)
		row.position = Vector2(0, h - ph - 10)
		row.size = Vector2(w, ph)
		for t in portraits:
			var pr := TextureRect.new()
			pr.texture = t
			pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pr.custom_minimum_size = Vector2(ph * 0.75, ph)
			pr.modulate.a = 0.0
			pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pr)
	var t := UiKit.title(str(opts.get("title", "")), Style.FS_H2, Style.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var sub := str(opts.get("sub", ""))
	if sub != "":
		var sl := UiKit.text(sub, 16, Style.INK_2)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.custom_minimum_size = Vector2(w, 0)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sl)
	var stamp: Control = null
	if str(opts.get("stamp", "")) != "":
		stamp = UiKit.stamp(str(opts["stamp"]), 54, opts.get("stamp_color", Style.SEAL), -12)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.modulate.a = 0.0
		frame.add_child(stamp)
	var hold := float(opts.get("hold", 1.8)) * m
	layer.modulate.a = 0.0
	create_tween().tween_property(layer, "modulate:a", 1.0, 0.25 * m)
	var kb := create_tween()   # 켄 번스: 천천히 다가감
	kb.tween_property(img, "scale", Vector2(1.07, 1.07), hold + 0.6 * m).from(Vector2(1.0, 1.0))
	if not portraits.is_empty():
		var pt := create_tween()
		for pr in row.get_children():
			pt.tween_property(pr, "modulate:a", 1.0, 0.18 * m)
	if stamp != null:
		await _wait(0.45 * m + (0.18 * m * portraits.size()))
		if not _skip:
			await get_tree().process_frame
			stamp.position = Vector2(w * 0.5 - stamp.size.x / 2.0, h * 0.42 - stamp.size.y / 2.0)
			stamp.pivot_offset = stamp.size / 2.0
			Sfx.play("stamp")
			var st := create_tween().set_parallel()
			st.tween_property(stamp, "modulate:a", 1.0, 0.08 * m)
			st.tween_property(stamp, "scale", Vector2(1.0, 1.0), 0.16 * m).from(Vector2(1.8, 1.8)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			shake(self, 6.0, 0.18 * m)
	await _wait(hold)
	var out := create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.2 * m)
	await out.finished
	layer.queue_free()


func slides(list: Array, m: float, skip_text := "건너뛰기 ▸") -> void:
	## 전체 화면 그림을 차례로. list: [{"tex", "lines": [두 줄]}]. 아무 데나 누르면 다음, 「건너뛰기」는 끝까지
	if list.is_empty() or m <= 0.0:
		return
	var layer := _backdrop(1.0)
	layer.color = Color("#0f0b08")
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(img)
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()   # 자막이 읽히게 아래쪽을 어둡게
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -170
	var cap := UiKit.text("", 24, Color("#f3e7cf"), false, 700)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cap)
	cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cap.offset_top = -150
	cap.offset_bottom = -40
	var all_skip := [false]
	var sb := UiKit.button(skip_text, func(): all_skip[0] = true, 15, "paper")
	layer.add_child(sb)
	sb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sb.position = Vector2(size.x - 170, 24)
	for s in list:
		if all_skip[0]:
			break
		_skip = false
		img.texture = s["tex"]
		img.pivot_offset = size / 2.0
		cap.text = "\n".join(s.get("lines", []))
		img.modulate.a = 0.0
		cap.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		tw.tween_property(img, "modulate:a", 1.0, 0.6 * m)
		tw.tween_property(img, "scale", Vector2(1.08, 1.08), 5.2 * m).from(Vector2(1.0, 1.0))
		tw.tween_property(cap, "modulate:a", 1.0, 0.8 * m).set_delay(0.4 * m)
		await _wait(4.2 * m, all_skip)
		var out := create_tween().set_parallel()
		out.tween_property(img, "modulate:a", 0.0, 0.4 * m)
		out.tween_property(cap, "modulate:a", 0.0, 0.3 * m)
		await out.finished
	layer.queue_free()


func _backdrop(alpha: float) -> ColorRect:
	var layer := ColorRect.new()
	layer.color = Color(0.03, 0.02, 0.01, alpha)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_skip = true)
	return layer


func _wait(sec: float, also: Array = []) -> void:
	## sec초를 기다리되, 누르면(_skip) 바로 끝난다
	var left := sec
	while left > 0.0 and not _skip and not (not also.is_empty() and also[0]):
		await get_tree().process_frame
		left -= get_process_delta_time()


# ------------------------------------------------------------------ 컷인 · 전환 · 클라이맥스

func cutin(tex: Texture2D, name: String, line: String, color: Color, m: float, from_left := true) -> void:
	## 캐릭터 컷인: 비스듬한 띠 위로 초상이 쓱 들어오고 이름 · 대사 한 줄. 게임은 멈추지 않는다(누르지 않아도 됨)
	if tex == null or m <= 0.0:
		return
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bh := 190.0
	var y := size.y * 0.30
	var band := Polygon2D.new()   # 비스듬한 좌석 색 띠
	var sk := 40.0
	band.polygon = PackedVector2Array([Vector2(0, y + sk), Vector2(size.x, y), Vector2(size.x, y + bh - sk), Vector2(0, y + bh)])
	band.color = Color(color.darkened(0.35), 0.92)
	holder.add_child(band)
	var edge := Line2D.new()
	edge.points = PackedVector2Array([Vector2(0, y + sk), Vector2(size.x, y)])
	edge.width = 4.0
	edge.default_color = Style.GOLD_HI
	holder.add_child(edge)
	var face := TextureRect.new()
	face.texture = tex
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.size = Vector2(bh * 1.05, bh * 1.4)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(face)
	var nm := UiKit.title(name, 34, Color("#fff4dc"), 900)
	var ln := UiKit.text("「" + line + "」", 20, Color("#f3e7cf"), false, 700)
	for l in [nm, ln]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(l)
	var fx_ := size.x * 0.18 if from_left else size.x * 0.82 - face.size.x
	var tx := fx_ + face.size.x + 24 if from_left else fx_ - 560
	face.position = Vector2(fx_ + (-size.x * 0.6 if from_left else size.x * 0.6), y + bh - face.size.y)
	nm.position = Vector2(tx, y + 40)
	ln.position = Vector2(tx, y + 92)
	holder.modulate.a = 0.0
	Sfx.play("whoosh", 0.08)
	var tw := create_tween().set_parallel()
	tw.tween_property(holder, "modulate:a", 1.0, 0.12 * m)
	tw.tween_property(face, "position:x", fx_, 0.28 * m).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await tw.finished
	await get_tree().create_timer(1.0 * m).timeout
	var out := create_tween().set_parallel()
	out.tween_property(holder, "modulate:a", 0.0, 0.2 * m)
	out.tween_property(face, "position:x", fx_ + (size.x * 0.4 if from_left else -size.x * 0.4), 0.2 * m)
	await out.finished
	holder.queue_free()


func ink_wipe(m: float) -> void:
	## 화면 전환: 먹이 한가운데서 번져 화면을 덮었다가 걷힌다 (2막 진입)
	if m <= 0.0:
		return
	var r := [0.0]
	var cover := Control.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var full := size.length() * 0.6
	Sfx.play("boom")
	cover.draw.connect(func():
		var c := size / 2.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		cover.draw_circle(c, r[0], Color("#120d09"))
		for k in 24:   # 가장자리 먹 방울
			var ang := k * TAU / 24.0 + rng.randf() * 0.2
			cover.draw_circle(c + Vector2(cos(ang), sin(ang)) * r[0] * rng.randf_range(0.95, 1.12), r[0] * rng.randf_range(0.05, 0.12), Color("#120d09")))
	var tw := create_tween()
	tw.tween_method(func(v: float):
		r[0] = v
		cover.queue_redraw(), 0.0, full, 0.5 * m).set_ease(Tween.EASE_IN)
	await tw.finished
	await get_tree().create_timer(0.25 * m).timeout
	var tw2 := create_tween()
	tw2.tween_property(cover, "modulate:a", 0.0, 0.45 * m)
	await tw2.finished
	cover.queue_free()


var _beat := false
var _beat_t := 0.0


func heartbeat(on: bool) -> void:
	## 마지막 장면: 가장자리가 심장 박동처럼 두 번씩 뛴다 (끌 때까지)
	_beat = on
	Sfx.loop("heart", on, 0.7)
	if not on and _vig.get("beat", false):
		_vig = {}
	queue_redraw()


func victory(m: float) -> void:
	## 승리: 태극 색 종이 꽃가루가 쏟아지고 「만 세」
	if m <= 0.0:
		return
	var cols := [Style.SEAL, Color("#1f3f8f"), Color("#f6efdd"), Style.INK]
	for i in 140:
		_confetti.append({"x": randf() * size.x, "y": -randf() * size.y * 0.6, "vy": randf_range(140, 260), "vx": randf_range(-40, 40),
			"rot": randf() * TAU, "spin": randf_range(-6, 6), "w": randf_range(6, 12), "h": randf_range(10, 18), "col": cols[i % cols.size()]})
	var st := UiKit.stamp("만 세", 72, Style.SEAL, -8)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(st)
	await get_tree().process_frame
	st.position = size / 2.0 - st.size / 2.0
	st.pivot_offset = st.size / 2.0
	Sfx.play("stamp")
	Sfx.play("cheer")
	var tw := create_tween().set_parallel()
	tw.tween_property(st, "scale", Vector2(1, 1), 0.25 * m).from(Vector2(2.2, 2.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(st, "modulate:a", 1.0, 0.1 * m).from(0.0)
	await get_tree().create_timer(1.6 * m).timeout
	var out := create_tween()
	out.tween_property(st, "modulate:a", 0.0, 0.3 * m)
	await out.finished
	st.queue_free()


func defeat(m: float) -> void:
	## 실패: 화면이 천천히 흑백으로 바랜다 (엔딩 화면으로 넘어가면 풀림)
	if m <= 0.0:
		return
	var gray := ColorRect.new()
	gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float amount = 0.0;\nvoid fragment() {\n\tvec4 c = texture(screen_tex, SCREEN_UV);\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(c.rgb, vec3(g) * vec3(1.0, 0.97, 0.9), amount), 1.0);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	gray.material = mat
	add_child(gray)
	gray.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("amount", v), 0.0, 1.0, 1.4 * m)
	await tw.finished
	await get_tree().create_timer(0.6 * m).timeout


var _confetti: Array = []


# ------------------------------------------------------------------ 효과

func shake(node: Control, strength: float, dur: float) -> void:
	## node를 짧게 흔든다 (투옥 · 폭파 · 도장)
	if dur <= 0.0 or not is_instance_valid(node):
		return
	var base := node.position
	var tw := create_tween()
	var n := 6
	for i in n:
		var k := 1.0 - float(i) / n
		tw.tween_property(node, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k, dur / n)
	tw.tween_property(node, "position", base, dur / n)


func vignette(color: Color, strength: float, dur: float) -> void:
	## 화면 가장자리가 잠깐 물든다 (노출 상승: 붉게)
	if dur <= 0.0:
		return
	# 이 비네트만의 상태: 다른 비네트 · 심장 박동이 겹쳐 _vig를 바꿔도 서로 깨뜨리지 않게
	var state := {"color": color, "a": 0.0}
	_vig = state
	var tw := create_tween()
	tw.tween_method(func(a: float):
		state["a"] = a
		queue_redraw(), 0.0, strength, dur * 0.3)
	tw.tween_method(func(a: float):
		state["a"] = a
		queue_redraw(), strength, 0.0, dur * 0.7)
	await tw.finished
	if _vig == state:
		_vig = {}
	queue_redraw()


func ink(at: Vector2, ok: bool, m: float) -> void:
	## 판정 결과: 성공이면 먹이 번지는 원, 실패면 금이 가는 선
	if m <= 0.0:
		return
	_inks.append({"at": at, "ok": ok, "t": 0.0, "life": 0.9 * m, "seed": randi()})
	queue_redraw()


func _draw() -> void:
	for p in _confetti:
		draw_set_transform(Vector2(p["x"], p["y"]), p["rot"], Vector2(1, absf(cos(p["rot"] * 1.7)) + 0.2))
		draw_rect(Rect2(-p["w"] / 2.0, -p["h"] / 2.0, p["w"], p["h"]), p["col"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _vig.has("color") and float(_vig.get("a", 0.0)) > 0.0:
		var c: Color = _vig["color"]
		var band := minf(size.x, size.y) * 0.22
		for i in 8:   # 바깥에서 안으로 옅어지는 띠
			var a: float = _vig["a"] * (1.0 - i / 8.0) * 0.95
			var d := band * i / 8.0
			var r := Rect2(Vector2(d, d), size - Vector2(d, d) * 2)
			draw_rect(r, Color(c, a), false, band / 8.0 + 1.0)
	for s in _inks:
		var p: float = s["t"] / s["life"]
		var a := 1.0 - p
		var rng := RandomNumberGenerator.new()
		rng.seed = s["seed"]
		if s["ok"]:
			var r := 40.0 + 120.0 * ease(p, 0.4)
			draw_circle(s["at"], r, Color(Style.INK, 0.18 * a))
			draw_arc(s["at"], r, 0, TAU, 48, Color(Style.SEAL, 0.8 * a), 4.0)
			for k in 10:   # 먹 방울
				var ang := rng.randf() * TAU
				var dist := r * rng.randf_range(0.9, 1.4)
				draw_circle(s["at"] + Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(3, 9) * a, Color(Style.INK, 0.7 * a))
		else:
			for k in 5:   # 금
				var ang := rng.randf() * TAU
				var pts := PackedVector2Array([s["at"]])
				var cur: Vector2 = s["at"]
				for j in 4:
					ang += rng.randf_range(-0.6, 0.6)
					cur += Vector2(cos(ang), sin(ang)) * 30.0 * ease(minf(1.0, p * 3.0), 0.5)
					pts.append(cur)
				draw_polyline(pts, Color(Style.INK, 0.85 * a), 2.5)
