extends Node
## 배경음 (autoload "Music"). Music.play("main") — 두 플레이어를 번갈아 써서 교차 전환한다.

const TRACKS := ["main", "tension", "ending"]
const FADE := 1.6

var current := ""
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _active := 0


func _ready() -> void:
	for n in TRACKS:
		var path := "res://assets/music/%s.wav" % n
		if ResourceLoader.exists(path):
			var st: AudioStreamWAV = load(path)
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
			_streams[n] = st
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80
		add_child(p)
		_players.append(p)


func play(name: String) -> void:
	if name == current or not _streams.has(name):
		return
	current = name
	var old := _players[_active]
	_active = 1 - _active
	var nw := _players[_active]
	nw.stream = _streams[name]
	nw.volume_db = -60
	nw.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(nw, "volume_db", _target_db(), FADE)
	tw.tween_property(old, "volume_db", -60.0, FADE)
	tw.chain().tween_callback(old.stop)


func refresh_volume() -> void:
	if current != "":
		_players[_active].volume_db = _target_db()


func _target_db() -> float:
	return linear_to_db(maxf(Prefs.bgm_volume, 0.0001))
