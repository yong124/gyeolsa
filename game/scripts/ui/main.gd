extends Control
## 화면 흐름: (첫 실행) 도입부 → 메인 메뉴 → 새 작전 / 이어하기 / 튜토리얼 → 게임 → 엔딩 → 메뉴·다시 하기
##
## 테스트용 실행 인자: godot --path game -- autostart [autoplay]
##   autostart  메뉴를 건너뛰고 기본 설정으로 바로 시작
##   autoplay   내 자리도 AI가 조작 (화면 확인·녹화용)

var data: GameData
var _screen: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_window().theme = Style.theme()
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	data = GameData.load_default()
	for err in data.validate():
		push_error("데이터 오류: " + err)
	var args := OS.get_cmdline_user_args()
	if "tour" in args:
		add_child(load("res://tools/tour.gd").new())   # 개발용 화면 캡처 (빌드에는 없음)
	elif "autostart" in args:
		var title := TitleScreen.new(data)
		var cfg := {"defs": title.make_players(4, 0), "stations": true, "difficulty": 0}
		title.free()
		_start(cfg, "autoplay" in args)
	elif not Prefs.intro_seen:
		_show_intro()
	else:
		_show_title()


func _show_intro() -> void:
	var intro := IntroScreen.new(data)
	intro.finished.connect(func():
		Prefs.intro_seen = true
		Prefs.save()
		_show_title())
	_swap(intro)


func _show_title() -> void:
	var title := TitleScreen.new(data)
	title.start_requested.connect(func(cfg): _start(cfg))
	title.continue_requested.connect(_continue)
	title.tutorial_requested.connect(_start_tutorial)
	title.intro_requested.connect(_show_intro)
	_swap(title)


func _start(cfg: Dictionary, autoplay := false) -> void:
	var defs: Array = cfg["defs"].duplicate(true)
	if autoplay:
		defs[0]["ai"] = true
		Records.disabled = true
	var game := GameRules.new()
	game.use_stations = cfg.get("stations", true)
	var diff: int = cfg.get("difficulty", 0)
	if diff != 0:
		game.rounds_override = {defs.size(): data.rounds_for(defs.size()) + diff}
	var sc: String = cfg.get("scenario", "")
	if sc != "" and sc != "daily":
		game.scenario = data.special_op(sc).get("scenario", {}).duplicate(true)
	game.setup(defs, int(cfg.get("seed", -1)), data)
	if not autoplay:
		SaveGame.erase()
	_open_game(game, {"cfg": cfg, "tutorial": false}, not autoplay)


func _continue() -> void:
	var r := SaveGame.read(data)
	if r.is_empty():
		_show_title()
		return
	_open_game(r["game"], r["meta"], false)


func _start_tutorial() -> void:
	var sc: Dictionary = data.text["tutorial"]["scenario"]
	var game := GameRules.new()
	game.scenario = {}
	for k in ["goal", "rounds", "first_missions", "start_items", "tile_order_top", "two_act"]:
		if sc.has(k):
			game.scenario[k] = sc[k]
	game.setup(sc["players"].duplicate(true), int(sc.get("seed", 1945)), data)
	_open_game(game, {"tutorial": true}, false)


func _open_game(game: GameRules, meta: Dictionary, briefing: bool) -> void:
	var screen := GameScreen.new(game, 0, meta, briefing)
	screen.back_to_title.connect(_show_title)
	screen.finished.connect(func(): _show_ending(game, meta))
	_swap(screen)


func _show_ending(game: GameRules, meta: Dictionary) -> void:
	var tutorial: bool = meta.get("tutorial", false)
	if tutorial:
		Prefs.tutorial_done = true
		Prefs.save()
	var fresh := Records.record(game, meta)
	var e := EndingScreen.new(game, tutorial, fresh)
	e.to_menu.connect(_show_title)
	e.replay.connect(func(): _start(meta["cfg"]))
	_swap(e)


func _swap(screen: Control) -> void:
	if _screen:
		_screen.queue_free()
	_screen = screen
	add_child(screen)


func _exit_tree() -> void:
	# 테스트(autoplay) 확인용: 종료 시점 상태를 출력
	if "autoplay" in OS.get_cmdline_user_args() and (_screen is GameScreen or _screen is EndingScreen):
		var g: GameRules = _screen.game
		print("[autoplay] 화면=%s phase=%s 날짜=%s 광복=%d/%d 로그=%d줄 엔딩=%s" % [_screen.get_class() if not _screen is EndingScreen else "엔딩", g.phase, g.date_label(), g.score, g.goal,
			g.log_lines.size(), g.ending.get("name", "-")])
