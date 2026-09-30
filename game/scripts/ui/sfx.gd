extends Node
## 효과음 재생 (autoload "Sfx"). Sfx.play("dice")

const NAMES := ["dice", "step", "flip", "card", "success", "fail", "whistle", "day", "alert", "click", "score"]
const POOL := 8

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


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
