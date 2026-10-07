class_name AtmosV2
extends Control
## 보드 분위기 (V 연출): 보드 위에 겹쳐 그린다. 누를 수 없음.
## - 빛: 아침은 따뜻한 새벽빛, 낮은 그대로, 2막(결행)은 밤 — 푸른 어둠과 가장자리 그늘
## - 날씨: 오늘의 위협에 따라 비(장맛비) · 탐조등(통금 · 경계령) · 붉은 깜빡임(공습경보 · 비상 소집)
## 상태는 set_state()로 받는다. 그림은 _draw로만 그린다(그림 파일 없음).

const WEATHER := {"monsoon": "rain", "curfew": "light", "special_alert": "light", "full_alert": "light",
	"air_raid": "siren", "emergency_muster": "siren", "blockade": "light"}

var _tint := Color(0, 0, 0, 0)
var _tint_to := Color(0, 0, 0, 0)
var _night := 0.0          # 2막 밤 그늘 (0~1)
var _night_to := 0.0
var _weather := ""
var _t := 0.0
var _drops: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for i in 90:
		_drops.append(Vector2(randf(), randf()))


func set_state(phase: String, act: int, threat_id: String) -> void:
	if act == 2:
		_tint_to = Color("#0b1630", 0.30)
		_night_to = 1.0
	elif phase == "plan":
		_tint_to = Color("#ffb347", 0.10)   # 새벽빛
		_night_to = 0.0
	else:
		_tint_to = Color(0, 0, 0, 0)
		_night_to = 0.0
	_weather = WEATHER.get(threat_id, "")


func _process(delta: float) -> void:
	_t += delta
	_tint = _tint.lerp(_tint_to, minf(1.0, delta * 1.5))
	_night = lerpf(_night, _night_to, minf(1.0, delta * 1.5))
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _tint.a > 0.005:
		draw_rect(r, _tint)
	if _night > 0.01:
		# 밤: 가장자리 그늘 (안쪽은 밝게 남겨 보드가 읽히게)
		var band := minf(size.x, size.y) * 0.18
		for i in 6:
			var d := band * i / 6.0
			draw_rect(Rect2(Vector2(d, d), size - Vector2(d, d) * 2), Color(0.02, 0.03, 0.08, 0.22 * _night * (1.0 - i / 6.0)), false, band / 6.0 + 1.0)
	match _weather:
		"rain":
			for p in _drops:
				var x := fposmod(p.x * size.x + _t * 60.0, size.x)
				var y := fposmod(p.y * size.y + _t * 520.0 * (0.8 + p.x * 0.4), size.y)
				draw_line(Vector2(x, y), Vector2(x - 4, y + 16), Color(0.85, 0.9, 1.0, 0.35), 1.2)
			draw_rect(r, Color(0.2, 0.25, 0.35, 0.10))
		"light":
			# 탐조등: 아래 모서리에서 보드를 천천히 훑는 빛줄기
			var o := Vector2(size.x * 0.5, size.y + 40)
			var ang := -PI / 2 + sin(_t * 0.5) * 0.75
			var spread := 0.11
			var far := size.length()
			var a := o + Vector2(cos(ang - spread), sin(ang - spread)) * far
			var b := o + Vector2(cos(ang + spread), sin(ang + spread)) * far
			draw_rect(r, Color(0.02, 0.03, 0.06, 0.16))
			draw_colored_polygon(PackedVector2Array([o, a, b]), Color(1.0, 0.97, 0.8, 0.13))
		"siren":
			var p := 0.5 + 0.5 * sin(_t * 5.0)
			draw_rect(r, Color(0.8, 0.1, 0.08, 0.10 * p))
