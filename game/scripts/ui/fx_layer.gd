class_name FxLayer
extends Control
## 화면 위에 겹쳐 그리는 연출: 판정(주사위+도장), 결과 띠, 날짜 넘김, 말풍선, 소식, 경보, 날아가는 점수·카드.
## 모든 함수는 await로 끝날 때까지 기다릴 수 있다. mult는 속도 배율 (0이면 즉시).

const TONES := {
	"good": Color("#2f6b3a"), "bad": Style.SEAL, "warn": Color("#9a5412"),
	"info": Color("#2f4f7a"), "turn": Style.INK,
}
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}
const TOAST_LIFE := 6.0
const TOAST_MAX := 3

var focus_center := Vector2(450, 450)   # 보드 가운데
var board_rect := Rect2(0, 0, 900, 900)

var _dice := {}      # {"values", "title", "sub", "odds", "stamp", "ok", "alpha", "spin", "bounce", "stamp_t"}
var _banner := {}    # {"text", "color", "alpha", "sub"}
var _day := {}       # {"month", "day", "sub", "alpha", "drop"}
var _bubble := {}    # {"at", "text", "color", "alpha"}
var _toasts: Array = []
var _alarm := 0.0
var _stamps: Array = []   # [{"at", "text", "color", "t", "life"}]
var _flyers: Array = []   # [{"from", "to", "t", "dur", "color", "text"}]
var _scraps: Array = []   # 성공 시 흩날리는 종이 조각
var _paper: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper = Style.tex("paper_tile")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(delta: float) -> void:
	var busy := false
	if not _toasts.is_empty():
		for t in _toasts:
			t["age"] += delta
		_toasts = _toasts.filter(func(t): return t["age"] < TOAST_LIFE)
		busy = true
	if _alarm > 0.0:
		_alarm = maxf(0.0, _alarm - delta)
		busy = true
	if not _stamps.is_empty():
		for s in _stamps:
			s["t"] += delta
		_stamps = _stamps.filter(func(s): return s["t"] < s["life"])
		busy = true
	if not _flyers.is_empty():
		for f in _flyers:
			f["t"] += delta
		_flyers = _flyers.filter(func(f): return f["t"] < f["dur"])
		busy = true
	if not _scraps.is_empty():
		for s in _scraps:
			s["t"] += delta
		_scraps = _scraps.filter(func(s): return s["t"] < s["life"])
		busy = true
	if busy or not _dice.is_empty():
		queue_redraw()


# ------------------------------------------------------------------ 짧은 효과

func toast(text: String, tone: String) -> void:
	## 잠시 남는 소식 한 줄 (보드 왼쪽 위)
	_toasts.append({"text": text, "color": TONES.get(tone, Style.INK), "age": 0.0})
	while _toasts.size() > TOAST_MAX:
		_toasts.pop_front()
	queue_redraw()


func alarm(mult: float) -> void:
	## 화면 가장자리가 붉게 번쩍인다 (경찰 출동·체포)
	_alarm = 0.9 * maxf(mult, 0.4)


func fly(from: Vector2, to: Vector2, color: Color, dur: float) -> void:
	_flyers.append({"from": from, "to": to, "t": -randf_range(0.0, 0.12), "dur": maxf(dur, 0.05), "color": color, "text": ""})


func paper_burst(at: Vector2, mult: float) -> void:
	if mult <= 0.0:
		return
	for i in 14:
		_scraps.append({"at": at, "vx": randf_range(-130.0, 130.0), "vy": randf_range(-160.0, -55.0),
			"t": 0.0, "life": 0.9 * mult, "size": randf_range(5.0, 11.0)})
	queue_redraw()


func fly_card(from: Vector2, to: Vector2, text: String, dur: float) -> void:
	## 작은 카드가 목적지로 날아가며 줄어든다
	_flyers.append({"from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.05), "color": Style.PAPER, "text": text})
	await get_tree().create_timer(dur).timeout


func stamp_at(at: Vector2, text: String, color: Color, mult: float) -> void:
	## 보드 위 한 지점에 도장이 쾅 찍힌다
	if mult <= 0.0:
		return
	_stamps.append({"at": at, "text": text, "color": color, "t": 0.0, "life": 1.3 * mult})
	await get_tree().create_timer(0.55 * mult).timeout


func bubble(at: Vector2, text: String, color: Color, mult: float) -> void:
	## 말 머리 위 말풍선 (동료의 의도)
	if mult <= 0.0:
		return
	_bubble = {"at": at, "text": text, "color": color, "alpha": 0.0}
	var tw := create_tween()
	tw.tween_method(func(a: float):
		_bubble["alpha"] = a
		queue_redraw(), 0.0, 1.0, 0.15 * mult)
	await tw.finished
	await get_tree().create_timer(1.1 * mult).timeout
	await _fade(_bubble, 0.2 * mult)
	_bubble = {}
	queue_redraw()


# ------------------------------------------------------------------ 판정

static func success_chance(target: int, bonus: int) -> float:
	var ok := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b + bonus >= target:
				ok += 1
	return ok / 36.0


func roll_dice(e: Dictionary, mult: float) -> void:
	var values: Array = e["dice"]
	var what: String = e["what"]
	var judged: bool = e.has("target")
	var title := "%s 판정" % what if judged else "%s 주사위" % what
	var sub := ""
	var odds := -1.0
	if judged:
		var bonus: int = e.get("bonus", 0)
		odds = success_chance(e["target"], bonus)
		sub = "목표 %d 이상%s · 성공 확률 %d%%" % [e["target"], (" (보정 %+d)" % bonus) if bonus else "", roundi(odds * 100)]
	if mult <= 0.0:
		return
	Sfx.play("dice", 0.08)
	_dice = {"values": values.map(func(_v): return 1), "title": title, "sub": sub, "odds": odds, "stamp": "",
		"ok": true, "alpha": 1.0, "spin": 0.0, "bounce": 0.0, "stamp_t": 0.0}
	var frames := 9
	for i in frames:
		_dice["values"] = values.map(func(_v): return randi_range(1, 6))
		_dice["spin"] = randf_range(-0.5, 0.5) * (1.0 - float(i) / frames)
		_dice["bounce"] = absf(sin(i * 1.3)) * 26.0 * (1.0 - float(i) / frames)
		queue_redraw()
		await get_tree().create_timer(0.055 * mult).timeout
	_dice["values"] = values
	_dice["spin"] = 0.0
	_dice["bounce"] = 0.0
	var total := 0
	for v in values:
		total += v
	if judged:
		var bonus2: int = int(e.get("bonus", 0))
		var ok: bool = total + bonus2 >= int(e["target"])
		_dice["stamp"] = "성 공" if ok else "실 패"
		_dice["ok"] = ok
		_dice["title"] = "%s · 합계 %d%s" % [title, total + bonus2, (" (%d%+d)" % [total, bonus2]) if bonus2 else ""]
		var played := int(e.get("played", 0))
		if not e.has("played"):
			pass   # v1: 합계만
		elif played > 0 and values.size() >= 2:
			var rolled := []
			for k in range(1, values.size()):
				rolled.append(str(values[k]))
			_dice["title"] = "%s · 낸 눈 %d + 굴린 눈 %s%s = %d / 목표 %d" % [title, played, "+".join(rolled), (" %+d" % bonus2) if bonus2 else "", total + bonus2, int(e["target"])]
		else:
			_dice["title"] = "%s · 주사위 합 %d%s / 목표 %d" % [title, total, (" %+d" % bonus2) if bonus2 else "", int(e["target"])]
	elif e.has("result"):
		_dice["stamp"] = "%d 칸" % e["result"]
		_dice["ok"] = true
		_dice["title"] = "이동 %d칸" % e["result"]
	var tw := create_tween()
	tw.tween_method(func(t: float): _dice["stamp_t"] = t, 0.0, 1.0, 0.18 * mult)
	queue_redraw()
	await get_tree().create_timer(0.8 * mult).timeout
	await _fade(_dice, 0.2 * mult)
	_dice = {}
	queue_redraw()


# ------------------------------------------------------------------ 결과 띠

func banner(text: String, tone: String, mult: float, sub := "") -> void:
	if mult <= 0.0:
		return
	_banner = {"text": text, "color": TONES.get(tone, Style.INK), "alpha": 0.0, "sub": sub}
	var tw := create_tween()
	tw.tween_method(func(a: float):
		_banner["alpha"] = a
		queue_redraw(), 0.0, 1.0, 0.12 * mult)
	await tw.finished
	# 읽을 시간: 빠르기 설정과 상관없이 글 길이만큼은 머문다 (「빠르게」에서 0.3초 만에 사라져 못 읽던 문제)
	var read := clampf(0.6 + 0.06 * text.length() + 0.045 * sub.length(), 1.0, 3.2)
	await get_tree().create_timer(maxf(0.75 * mult, read)).timeout
	await _fade(_banner, 0.2 * mult)
	_banner = {}
	queue_redraw()


# ------------------------------------------------------------------ 날짜 넘김

func day(e: Dictionary, mult: float) -> void:
	if mult <= 0.0:
		return
	Sfx.play("day")
	_day = {"month": e.get("month_label", ""), "day": str(e.get("day_num", "")),
		"sub": "경계 %d단계 · 경찰 이동 %d칸" % [e["alert"], e["police_speed"]],
		"sub2": "8월 15일까지 %d일" % e["days_left"], "alpha": 0.0, "drop": 1.0,
		"dispatch": e.get("dispatch", ""), "typed": 0.0}
	var tw := create_tween().set_parallel()
	tw.tween_method(func(a: float):
		_day["alpha"] = a
		queue_redraw(), 0.0, 1.0, 0.25 * mult)
	tw.tween_method(func(d: float): _day["drop"] = d, 1.0, 0.0, 0.35 * mult).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	if _day["dispatch"] != "":
		# 아침 무전: 한 글자씩 타자기로 찍힌다
		var ty := create_tween()
		ty.tween_method(func(t: float):
			_day["typed"] = t
			queue_redraw(), 0.0, 1.0, 0.9 * mult)
		for k in 4:
			Sfx.play("click", 0.2, 0.25)
			await get_tree().create_timer(0.2 * mult).timeout
		await ty.finished
		await get_tree().create_timer(0.9 * mult).timeout
	else:
		await get_tree().create_timer(0.9 * mult).timeout
	await _fade(_day, 0.3 * mult)
	_day = {}
	queue_redraw()


func _fade(state: Dictionary, dur: float) -> void:
	if dur <= 0.0:
		return
	var tw := create_tween()
	tw.tween_method(func(a: float):
		state["alpha"] = a
		queue_redraw(), 1.0, 0.0, dur)
	await tw.finished


# ------------------------------------------------------------------ 그리기

func _draw() -> void:
	if _alarm > 0.0:
		_draw_alarm()
	if not _day.is_empty():
		_draw_day()
	if not _banner.is_empty():
		_draw_banner()
	if not _dice.is_empty():
		_draw_dice()
	if not _bubble.is_empty():
		_draw_bubble()
	for s in _stamps:
		var t: float = s["t"]
		var k := clampf(t / 0.16, 0.0, 1.0)
		var a := clampf((s["life"] - t) / 0.3, 0.0, 1.0)
		_draw_stamp(s["at"], s["text"], s["color"], 40, lerpf(2.2, 1.0, k), a * k, -0.2)
	for f in _flyers:
		_draw_flyer(f)
	for s in _scraps:
		var t: float = s["t"]
		var at: Vector2 = s["at"] + Vector2(s["vx"] * t, s["vy"] * t + 250.0 * t * t)
		var a := 1.0 - t / float(s["life"])
		draw_rect(Rect2(at, Vector2(s["size"], s["size"] * 0.55)), Color(Style.PAPER_HI, a))
	_draw_toasts()


func _paper_rect(r: Rect2, alpha := 1.0) -> void:
	draw_rect(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.35 * alpha))
	draw_texture_rect(_paper, r, true, Color(1, 1, 1, alpha))
	draw_rect(r, Color(Style.INK_2, 0.35 * alpha), false, 1.0)


func _text(font: Font, t: String, at: Vector2, fs: int, col: Color, center := true) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w / 2.0 if center else 0.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_stamp(at: Vector2, text: String, col: Color, fs: int, scl: float, a: float, rot: float) -> void:
	var font := Style.serif(900)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(at, rot, Vector2(scl, scl))
	var r := Rect2(-w / 2 - 16, -fs * 0.8, w + 32, fs * 1.4)
	draw_rect(r, Color(col, 0.07 * a))
	draw_rect(r, Color(col, 0.9 * a), false, 4.0)
	draw_rect(r.grow(6), Color(col, 0.75 * a), false, 1.8)
	draw_string(font, Vector2(-w / 2, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.92 * a))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_alarm() -> void:
	var a := clampf(_alarm, 0.0, 1.0) * (0.6 + 0.4 * sin(_alarm * 18.0))
	var steps := 10
	for i in steps:
		var w := 70.0 * (1.0 - float(i) / steps)
		var c := Color(0.75, 0.05, 0.03, 0.06 * a)
		draw_rect(Rect2(0, 0, w, size.y), c)
		draw_rect(Rect2(size.x - w, 0, w, size.y), c)
		draw_rect(Rect2(0, 0, size.x, w), c)
		draw_rect(Rect2(0, size.y - w, size.x, w), c)


func _draw_day() -> void:
	var a: float = _day["alpha"]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.03, 0.02, 0.66 * a))
	var pw := 300.0
	var ph := 330.0
	var drop: float = _day["drop"]
	var c := size / 2.0 + Vector2(0, -drop * 160 - 20)
	draw_set_transform(c, -0.04 + drop * 0.1, Vector2.ONE)
	var r := Rect2(-pw / 2, -ph / 2, pw, ph)
	_paper_rect(r, a)
	draw_rect(Rect2(r.position, Vector2(pw, 56)), Color(Style.SEAL, a))
	for k in 6:
		draw_circle(r.position + Vector2(40 + k * 44, 10), 5, Color(0.1, 0.07, 0.05, a))
	var sf := Style.serif(900)
	_text(Style.sans(800), "1945년  %s" % _day["month"], Vector2(0, r.position.y + 42), 22, Color(1, 0.96, 0.9, a))
	_text(sf, _day["day"], Vector2(0, r.position.y + 210), 150, Color(Style.INK, a))
	_text(Style.sans(700), _day["sub"], Vector2(0, r.end.y - 50), 16, Color(Style.INK_2, a))
	_text(Style.sans(800), _day["sub2"], Vector2(0, r.end.y - 22), 16, Color(Style.SEAL, a))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if _day["dispatch"] != "" and _day["typed"] > 0.0:
		# 전보 띠
		var full: String = _day["dispatch"]
		var shown := full.substr(0, int(ceil(full.length() * _day["typed"])))
		var font := Style.serif(700)
		var fs := 20
		var w := font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 120
		var strip := Rect2(size.x / 2 - w / 2, size.y / 2 + ph / 2 + 4, w, 50)
		draw_rect(Rect2(strip.position + Vector2(0, 5), strip.size), Color(0, 0, 0, 0.4 * a))
		draw_rect(strip, Color(Style.INK, 0.95 * a))
		draw_rect(strip.grow(-4), Color(Style.GOLD, 0.6 * a), false, 1.0)
		draw_string(Style.sans(800), strip.position + Vector2(18, 31), "무전", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Style.SEAL.lightened(0.3), a))
		draw_string(font, strip.position + Vector2(66, 33), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Style.ON_DARK_ACCENT, a))


func _draw_banner() -> void:
	var a: float = _banner["alpha"]
	var col: Color = _banner["color"]
	var font := Style.serif(900)
	var fs := 34
	var tw := font.get_string_size(_banner["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := clampf(tw + 90, 360, board_rect.size.x - 40)
	var has_sub: bool = _banner["sub"] != ""
	var h := 84.0 if has_sub else 70.0
	var r := Rect2(focus_center.x - w / 2, focus_center.y - h / 2, w, h)
	_paper_rect(r, a)
	draw_rect(Rect2(r.position, Vector2(8, h)), Color(col, a))
	draw_rect(Rect2(Vector2(r.end.x - 8, r.position.y), Vector2(8, h)), Color(col, a))
	if has_sub:
		_text(Style.sans(700), _banner["sub"], Vector2(focus_center.x, r.position.y + 24), 14, Color(Style.INK_3, a))
	var size_fit := fs if tw < w - 40 else int(fs * (w - 40) / tw)
	_text(font, _banner["text"], Vector2(focus_center.x, r.end.y - (20 if has_sub else 22)), size_fit, Color(col, a))


func _draw_bubble() -> void:
	var a: float = _bubble["alpha"]
	var font := Style.sans(700)
	var fs := 16
	var text: String = _bubble["text"]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 30
	var tip: Vector2 = _bubble["at"] + Vector2(0, -30)
	var box := Rect2(tip + Vector2(-w / 2.0, -48), Vector2(w, 36))
	box.position.x = clampf(box.position.x, board_rect.position.x + 6, board_rect.end.x - w - 6)
	box.position.y = maxf(box.position.y, board_rect.position.y + 6)
	var col: Color = _bubble["color"]
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-8, -13), tip + Vector2(8, -13), tip]), Color(Style.PAPER_HI, a))
	_paper_rect(box, a)
	draw_rect(Rect2(box.position, Vector2(5, box.size.y)), Color(col, a))
	draw_string(font, box.position + Vector2(15, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Style.INK, a))


func _draw_toasts() -> void:
	var y := board_rect.position.y + 14
	var font := Style.sans(600)
	for t in _toasts:
		var a := clampf((TOAST_LIFE - t["age"]) / 1.0, 0.0, 1.0)
		var fs := 14
		var w := font.get_string_size(t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24
		var box := Rect2(Vector2(board_rect.position.x + 16, y), Vector2(w, 28))
		draw_rect(box, Color(Style.INK, 0.88 * a))
		draw_rect(Rect2(box.position, Vector2(4, box.size.y)), Color(t["color"].lightened(0.35), a))
		draw_string(font, box.position + Vector2(13, 19), t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Style.PAPER, a))
		y += 32


func _draw_flyer(f: Dictionary) -> void:
	var t := clampf(f["t"] / f["dur"], 0.0, 1.0)
	if f["t"] < 0.0:
		return
	var e := 1.0 - pow(1.0 - t, 3.0)
	var from: Vector2 = f["from"]
	var to: Vector2 = f["to"]
	var mid := (from + to) / 2.0 + Vector2(0, -minf(160.0, from.distance_to(to) * 0.35))
	var p := from.lerp(mid, e).lerp(mid.lerp(to, e), e)
	if f["text"] == "":
		var r := lerpf(12.0, 7.0, e)
		draw_circle(p + Vector2(0, 3), r, Color(0, 0, 0, 0.3))
		draw_circle(p, r, f["color"])
		draw_circle(p, r * 0.45, Color(1, 1, 1, 0.5))
	else:
		var s := lerpf(1.0, 0.25, e)
		var sz := Vector2(150, 200) * s
		var rr := Rect2(p - sz / 2.0, sz)
		_paper_rect(rr, 1.0 - t * 0.3)
		draw_rect(Rect2(rr.position, Vector2(rr.size.x, 22 * s)), Style.INK)
		if s > 0.45:
			_text(Style.serif(800), f["text"], rr.get_center() + Vector2(0, 8), int(20 * s), Style.INK)


func _draw_dice() -> void:
	var a: float = _dice["alpha"]
	var values: Array = _dice["values"]
	var sw := minf(460.0, board_rect.size.x - 60)
	var strip := Rect2(focus_center.x - sw / 2, board_rect.end.y - 118, sw, 92)
	# 주사위 (띠 위에서 튀며 굴러간다)
	var ds := 84.0
	var gap := 30.0
	var total_w := values.size() * ds + (values.size() - 1) * gap
	var x0 := focus_center.x - total_w / 2.0
	for i in values.size():
		var ctr := Vector2(x0 + i * (ds + gap) + ds / 2.0, strip.position.y - 64 - _dice["bounce"] * (1.0 if i == 0 else 0.7))
		var rot: float = _dice["spin"] * (1 if i == 0 else -1) + (-0.14 if i == 0 else 0.12)
		draw_set_transform(ctr, rot, Vector2.ONE)
		var r := Rect2(-ds / 2, -ds / 2, ds, ds)
		draw_rect(Rect2(r.position + Vector2(4, 10), r.size), Color(0, 0, 0, 0.4 * a))
		draw_rect(r, Color(0.96, 0.93, 0.86, a))
		draw_rect(Rect2(r.position + Vector2(0, ds - 7), Vector2(ds, 7)), Color(0.8, 0.75, 0.64, a))
		draw_rect(Rect2(r.position + Vector2(ds - 6, 0), Vector2(6, ds)), Color(0.84, 0.79, 0.68, a))
		for pip in PIPS[int(values[i])]:
			draw_circle(pip * ds * 0.27, ds * 0.085, Color(0.72, 0.12, 0.1, a) if int(values[i]) == 1 else Color(0.13, 0.1, 0.08, a))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# 판정 띠
	_paper_rect(strip, a)
	_text(Style.serif(800), _dice["title"], Vector2(focus_center.x, strip.position.y + 34), 22, Color(Style.INK, a))
	if _dice["sub"] != "":
		_text(Style.sans(600), _dice["sub"], Vector2(focus_center.x, strip.position.y + 58), 14, Color(Style.INK_2, a))
	if _dice["odds"] >= 0.0:
		var bar := Rect2(strip.position.x + 40, strip.end.y - 18, strip.size.x - 80, 7)
		draw_rect(bar, Color(0, 0, 0, 0.12 * a))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _dice["odds"], bar.size.y)), Color(Style.SEAL, a))
	# 결과 도장
	if _dice["stamp"] != "":
		var k: float = _dice["stamp_t"]
		var col: Color = Style.SEAL if _dice["ok"] else Style.INK
		_draw_stamp(Vector2(strip.end.x - 70, strip.position.y - 24), _dice["stamp"], col, 38, lerpf(2.0, 1.0, k), a * k, -0.22)
