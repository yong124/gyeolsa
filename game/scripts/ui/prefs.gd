extends Node
## 전역 설정 (autoload "Prefs"). user://settings.cfg에 저장한다.

const PATH := "user://settings.cfg"
const SPEEDS := [
	{"name": "느리게", "mult": 1.6},
	{"name": "보통", "mult": 1.0},
	{"name": "빠르게", "mult": 0.45},
	{"name": "즉시", "mult": 0.0},
]

var speed := 2
var sfx_volume := 0.8
var bgm_volume := 0.5
var fullscreen := false
var reduce_motion := false     # 연출 줄이기: 내 행동도 빠르게
var intro_seen := false
var tutorial_done := false
var v2_cine := 0               # 연출: 0 전부 · 1 처음만 (같은 컷신은 처음 한 번) · 2 줄임 (컷신 대신 배너) (U4)
var v2_roster_open := false    # 요원 명부: 동료 상세를 펼쳐 둘지 (U1)
var v2_tips := true           # v2 첫 판 안내 말풍선 (첫 판이 끝나면 꺼짐, 일시정지 메뉴에서 켜고 끌 수 있음)
var v2_training_done := false  # v2 훈련 작전을 끝까지 했는가 (타이틀 「처음이라면 추천」)
var online_url := ""           # 온라인 서버 주소 (비면 NetClientV2.DEFAULT_URL)
var online_name := ""          # 온라인에서 쓸 내 이름
var playtest := true           # 플레이테스트 기록·설문 (user://playtests)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		speed = clampi(int(cfg.get_value("game", "speed", speed)), 0, SPEEDS.size() - 1)
		intro_seen = bool(cfg.get_value("game", "intro_seen", intro_seen))
		tutorial_done = bool(cfg.get_value("game", "tutorial_done", tutorial_done))
		reduce_motion = bool(cfg.get_value("game", "reduce_motion", reduce_motion))
		playtest = bool(cfg.get_value("game", "playtest", playtest))
		v2_tips = bool(cfg.get_value("game", "v2_tips", v2_tips))
		v2_roster_open = bool(cfg.get_value("game", "v2_roster_open", v2_roster_open))
		v2_cine = clampi(int(cfg.get_value("game", "v2_cine", v2_cine)), 0, 2)
		v2_training_done = bool(cfg.get_value("game", "v2_training_done", v2_training_done))
		online_url = str(cfg.get_value("online", "url", online_url))
		online_name = str(cfg.get_value("online", "name", online_name))
		sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
		bgm_volume = float(cfg.get_value("audio", "bgm", bgm_volume))
		fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	apply_video()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "speed", speed)
	cfg.set_value("game", "intro_seen", intro_seen)
	cfg.set_value("game", "tutorial_done", tutorial_done)
	cfg.set_value("game", "reduce_motion", reduce_motion)
	cfg.set_value("game", "playtest", playtest)
	cfg.set_value("game", "v2_tips", v2_tips)
	cfg.set_value("game", "v2_roster_open", v2_roster_open)
	cfg.set_value("game", "v2_cine", v2_cine)
	cfg.set_value("game", "v2_training_done", v2_training_done)
	cfg.set_value("online", "url", online_url)
	cfg.set_value("online", "name", online_name)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func mult() -> float:
	return SPEEDS[speed]["mult"]


func my_mult() -> float:
	## 내 행동 연출 배율 (연출 줄이기를 켜면 빠르게)
	return 0.5 if reduce_motion else 1.0


func speed_name() -> String:
	return SPEEDS[speed]["name"]


func cycle_speed() -> void:
	speed = (speed + 1) % SPEEDS.size()
	save()
