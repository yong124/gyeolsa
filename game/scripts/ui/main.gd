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
	if "server" in args:
		# 온라인 서버 (헤드리스): Godot --headless --path game -- server [port=8910]
		var srv := NetServerV2.new()
		for a in args:
			if a.begins_with("port="):
				srv.port = int(a.substr(5))
		add_child(srv)
		return
	if "v2uitest" in args:
		add_child(load("res://tests/v2_ui_test.gd").new())   # v2 화면 시험 (개발용)
	elif "tour" in args:
		add_child(load("res://tools/tour.gd").new())   # 개발용 화면 캡처 (빌드에는 없음)
	elif "v2" in args:
		_show_v2_setup()   # 새 규칙 v2 바로 시작 (게임_실행_v2.bat)
	elif "autostart" in args:
		var title := TitleScreen.new(data)
		var cfg := {"defs": title.make_players(4, 0), "difficulty": 0}
		title.free()
		_start(cfg, "autoplay" in args)
	elif OS.has_feature("web"):
		_web_gate()   # 웹: 첫 클릭 전에는 소리를 내지 않는다 (브라우저 자동재생 제한) · 휴대폰이면 안내
	elif not Prefs.intro_seen:
		_show_intro()
	else:
		_show_title()


func _after_gate() -> void:
	if not Prefs.intro_seen:
		_show_intro()
	else:
		_show_title()


func _web_gate() -> void:
	## 웹 첫 화면: 「눌러서 시작」 한 번 (이 클릭으로 브라우저가 소리를 허락함). 휴대폰 · 태블릿이면 PC 안내를 먼저
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(holder)
	var desk := TextureRect.new()
	desk.texture = Style.tex("desk")
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	holder.add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	holder.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := UiKit.paper_panel(36)
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(UiKit.title("결 사", 56, Style.SEAL, 900))
	v.add_child(UiKit.text("1945년 8월, 경성. 네 요원이 일제의 심장부 한 곳을 골라 들이친다.
협력 보드게임 · 1인 + AI 동료 3명", Style.FS_LEAD, Style.INK_2))
	var mobile := OS.has_feature("web_android") or OS.has_feature("web_ios")
	if mobile:
		var warn := UiKit.text("이 게임은 PC 브라우저(마우스 · 가로 화면)에 맞춰 만들었습니다. 휴대폰에서는 글자가 작고 누르기 어렵습니다. PC에서 열어 주세요.", 16, Style.SEAL, false, 700)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(warn)
	var go := UiKit.button("눌러서 시작" if not mobile else "그래도 해 보기", func(): _after_gate(), 22, "primary")
	v.add_child(go)
	v.add_child(UiKit.text("소리가 납니다 · 저장은 이 브라우저에 남습니다", 13, Style.INK_3))


func _show_intro() -> void:
	var slides := GameScreenV2.opening_slides()
	if not slides.is_empty():
		# V 연출: 오프닝 4컷이 있으면 그것을 도입부로
		var holder := Control.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		_swap(holder)
		var cine := CinemaV2.new()
		holder.add_child(cine)
		await get_tree().process_frame
		await cine.slides(slides, 1.0)
		Prefs.intro_seen = true
		Prefs.save()
		_show_title()
		return
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
	title.v2_requested.connect(_show_v2_setup)
	title.quick_requested.connect(_quick_v2)
	title.continue_v2_requested.connect(_continue_v2)
	title.training_requested.connect(_training_v2)
	title.online_requested.connect(_show_online)
	_swap(title)


func _start(cfg: Dictionary, autoplay := false) -> void:
	if autoplay:
		cfg = cfg.duplicate(true)
		for d in cfg["defs"]:
			d["ai"] = true
		Records.disabled = true
	var game := GameRules.from_cfg(cfg, data)
	if not autoplay:
		SaveGame.erase()
	var meta := {"cfg": cfg, "tutorial": false}
	if not autoplay and Prefs.playtest and not PlaytestLog.disabled:
		meta["playtest"] = PlaytestLog.begin(game, cfg)
	_open_game(game, meta, not autoplay)


func _continue() -> void:
	var r := SaveGame.read(data)
	if r.is_empty():
		_show_title()
		return
	if r["meta"].has("playtest"):
		r["meta"]["playtest"]["sessions"] = int(r["meta"]["playtest"].get("sessions", 1)) + 1
	_open_game(r["game"], r["meta"], false)


func _start_tutorial(id := "tutorial") -> void:
	## id: "tutorial"(기본 훈련) · "tutorial2"(2막 훈련) — data/text.json의 같은 이름 항목
	var sc: Dictionary = data.text[id]["scenario"]
	var game := GameRules.new()
	game.scenario = {}
	for k in sc:
		if not k in ["players", "seed"]:
			game.scenario[k] = sc[k]
	game.setup(sc["players"].duplicate(true), int(sc.get("seed", 1945)), data)
	_open_game(game, {"tutorial": true, "tutorial_id": id}, false)


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
	if meta.has("playtest"):
		PlaytestLog.finish(meta["playtest"], game)
	var e := EndingScreen.new(game, tutorial, fresh)
	e.to_menu.connect(func(): _survey_then(game, meta, _show_title))
	e.replay.connect(func(): _survey_then(game, meta, func(): _start(meta["cfg"])))
	_swap(e)


func _survey_then(game: GameRules, meta: Dictionary, next: Callable) -> void:
	## 플레이테스트 기록이 있는 판이면 설문을 먼저 받는다 (한 판에 한 번)
	if not meta.has("playtest") or meta.get("surveyed", false):
		next.call()
		return
	meta["surveyed"] = true
	var seats := []
	for p in game.players:
		if not p["ai"]:
			seats.append({"id": p["id"], "name": p["name"]})
	var s := SurveyScreen.new(meta["playtest"], seats)
	s.finished.connect(next)
	_swap(s)


# ================================================================ v2 (지금 규칙)

const TRAINING_SEED := 19450815
const TRAINING_CHARS := ["park", "jeong", "gaeddong", "oh"]   # 훈련 작전: 나는 박 하사, 판은 늘 같다


func _show_v2_setup() -> void:
	var setup := SetupScreenV2.new()
	setup.back_requested.connect(_show_title)
	setup.start_requested.connect(func(defs, seed_value): _start_v2(defs, seed_value))
	_swap(setup)


func _quick_v2() -> void:
	## 바로 시작: 요원도 결사가 정한다
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_start_v2(SetupScreenV2.make_defs("", rng), rng.randi())


func _training_v2() -> void:
	var data := GameDataV2.load_default()
	var defs := []
	for i in TRAINING_CHARS.size():
		var id: String = TRAINING_CHARS[i]
		defs.append({"name": "나" if i == 0 else str(data.character(id).get("name", "")), "character": id})
	var game := RulesV2.new()
	game.setup(defs, TRAINING_SEED)
	_open_v2(game, {"defs": defs, "training": true, "opening": true})


func _start_v2(defs: Array, seed_value: int) -> void:
	SaveGameV2.erase()
	var game := RulesV2.new()
	game.setup(defs, seed_value)
	_open_v2(game, {"defs": defs, "opening": true})


func _continue_v2() -> void:
	var r := SaveGameV2.read()
	if r.is_empty():
		_show_title()
		return
	_open_v2(r["game"], r["meta"])


var _net: NetClientV2 = null   # 온라인 연결 (화면이 바뀌어도 유지)


func _show_online() -> void:
	if _net == null:
		_net = NetClientV2.new()
		add_child(_net)
	var o := OnlineScreenV2.new(_net)
	o.back_requested.connect(_show_title)
	o.game_ready.connect(func(seat, view):
		var g := RulesV2.new()
		g.load_state(view)
		_open_v2(g, {"remote": _net, "seat": seat}))
	_swap(o)


func _open_v2(game: RulesV2, meta: Dictionary) -> void:
	var screen := GameScreenV2.new(game, int(meta.get("seat", 0)), meta)
	screen.back_to_title.connect(_show_title)
	screen.finished.connect(func():
		var training: bool = meta.get("training", false)
		var online: bool = meta.has("remote")
		if training:
			Prefs.v2_training_done = true
			Prefs.save()
		elif not online:
			SaveGameV2.erase()
		var e := EndingScreenV2.new(game, int(meta.get("seat", 0)), training)
		e.to_menu.connect(func():
			if online:
				_net.close()
			_show_title())
		e.replay.connect(func():
			if online:
				_net.close()   # 온라인: 다시 하기는 새 방에서
				_net.room = {}
				_show_online()
			else:
				_quick_v2())
		_swap(e))
	_swap(screen)


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
