extends Node
## 효과음 재생 (autoload "Sfx"). Sfx.play("dice")

const NAMES := ["dice", "step", "flip", "card", "success", "fail", "whistle", "day", "alert", "click", "score",
	"stamp", "whoosh", "boom", "clang", "spark", "cheer", "heart", "rain", "siren"]   # 둘째 줄: V 연출 (tools/gen_sfx.py)
const LOOPS := ["heart", "rain", "siren"]   # 되풀이해 트는 소리 (loop()로 켜고 끔, .wav.import에서 loop_mode=2)
const POOL := 8

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}   # 이름 -> 되풀이 재생기


func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String, pitch_jitter := 0.0, volume := 1.0) -> void:
	if not _streams.has(name) or Prefs.sfx_volume <= 0.0:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = linear_to_db(Prefs.sfx_volume * volume)
	p.play()


func loop(name: String, on: bool, volume := 1.0) -> void:
	## 되풀이 소리 (심장 박동 · 빗소리 · 사이렌). 이미 켜져 있으면 그대로 둔다
	if not on:
		if _loops.has(name):
			_loops[name].stop()
		return
	if not _streams.has(name) or Prefs.sfx_volume <= 0.0:
		return
	if not _loops.has(name):
		var lp := AudioStreamPlayer.new()
		lp.stream = _streams[name]   # 되풀이는 가져오기 설정(edit/loop_mode=2)에 있다
		add_child(lp)
		_loops[name] = lp
	var pl: AudioStreamPlayer = _loops[name]
	pl.volume_db = linear_to_db(Prefs.sfx_volume * volume)
	if not pl.playing:
		pl.play()


func stop_loops() -> void:
	for n in _loops:
		_loops[n].stop()
