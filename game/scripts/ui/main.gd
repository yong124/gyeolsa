extends Control
## 화면 흐름: (첫 실행) 도입부 → 메인 메뉴 → 바로 시작 / 요원 골라 시작 / 이어하기 / 튜토리얼 / 온라인 → 게임 → 엔딩 → 메뉴·다시 하기
##
## 실행 인자: godot --path game -- v2 (요원 고르기부터) · server [port=] (온라인 서버) · v2uitest · tour (개발용)

var _screen: Control
var _opening_seen := false   # 이번 실행에서 오프닝 4컷을 이미 봤는가 (도입부로 봤으면 판 시작 때 또 틀지 않음)
var _tutorial_forced := false   # 처음 켰을 때 튜토리얼로 한 번 보냈는가


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_window().theme = Style.theme()
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for err in GameDataV2.load_default().validate():
		push_error("v2 데이터 오류: " + err)
	var args := OS.get_cmdline_user_args()
	if "server" in args:
		# 온라인 서버 (헤드리스): Godot --headless --path game -- server [port=8910]
		var srv := NetServerV2.new()
		srv.port = int(GameDataV2.load_default().online.get("port", srv.port))
		if OS.get_environment("PORT").is_valid_int():   # 호스팅(Render 등)이 정해 주는 포트
			srv.port = int(OS.get_environment("PORT"))
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
		_show_v2_setup()   # 요원 고르기부터 (게임_실행_v2.bat)
	elif OS.has_feature("web"):
		if OS.has_feature("web_android") or OS.has_feature("web_ios"):
			_web_gate()   # 휴대폰 · 태블릿만: PC에서 열어 달라는 안내를 먼저
		else:
			_after_gate()   # PC 웹: 바로 첫 화면 (소리는 첫 클릭 때 브라우저가 켬)
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
	# 오프닝 그림을 화면 가득 어둡게 깔고, 그 위에 제목과 「눌러서 시작」
	var art := TextureRect.new()
	art.texture = ArtV2.get_tex("cut", "opening_2", TitleScreen.cover_texture())   # 네 요원이 지도를 펴 놓은 오프닝 그림
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	holder.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.06, 0.04, 0.55)
	holder.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	holder.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := UiKit.paper_panel(40)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	var mark := UiKit.title("結社", 72, Style.SEAL, 900)
	mark.add_theme_font_override("font", Style.serif(900))
	head.add_child(mark)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	var nm := UiKit.title("결 사", 40, Style.INK, 900)
	nm.add_theme_font_override("font", Style.serif(900))
	hv.add_child(nm)
	hv.add_child(UiKit.text("1945년 8월, 경성", 17, Style.INK_3, false, 700))
	v.add_child(UiKit.hsep())
	v.add_child(UiKit.text("네 요원이 일제의 심장부 한 곳을 골라 들이친다.
혼자 또는 온라인 2~4명이 함께하는 협력 보드게임.", Style.FS_LEAD, Style.INK_2))
	var mobile := OS.has_feature("web_android") or OS.has_feature("web_ios")
	if mobile:
		var warn := UiKit.text("이 게임은 PC 브라우저(마우스 · 가로 화면)에 맞춰 만들었습니다. 휴대폰에서는 글자가 작고 누르기 어렵습니다. PC에서 열어 주세요.", 16, Style.SEAL, false, 700)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(warn)
	var go := UiKit.button("눌러서 시작" if not mobile else "그래도 해 보기", func(): _after_gate(), 24, "primary")
	go.custom_minimum_size = Vector2(0, 60)
	v.add_child(go)


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
		_opening_seen = true
		Prefs.intro_seen = true
		Prefs.save()
		_show_title()
		return
	Prefs.intro_seen = true   # 오프닝 그림이 없으면 도입부 없이 메뉴로
	Prefs.save()
	_show_title()


func _show_title() -> void:
	var title := TitleScreen.new()
	title.intro_requested.connect(_show_intro)
	title.v2_requested.connect(_show_v2_setup)
	title.quick_requested.connect(_quick_v2)
	title.continue_v2_requested.connect(_continue_v2)
	title.training_requested.connect(_tutorial_v2)
	title.online_requested.connect(_show_online)
	_swap(title)
	# 완전 처음이면: 첫 화면을 띄운 뒤 그 위에 튜토리얼 창 (튜토리얼을 마칠 때까지, 켤 때마다 한 번). 시험 · 투어 실행에서는 건너뜀
	if not Prefs.v2_training_done and not _tutorial_forced and OS.get_cmdline_user_args().is_empty():
		_tutorial_forced = true
		title.offer_tutorial.call_deferred()


# ================================================================ 게임

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


func _tutorial_v2(index := 0) -> void:
	## 튜토리얼 훈련 (data/v2/tutorial.json): 훈련마다 새 판에서 먼저 해 보고 한 줄로 배운다
	var game := TutorialV2.new_game(GameDataV2.load_default(), index)
	_open_v2(game, {"tutorial": true, "training_index": index})


func _start_v2(defs: Array, seed_value: int) -> void:
	SaveGameV2.erase()
	var game := RulesV2.new()
	game.setup(defs, seed_value)
	_open_v2(game, {"defs": defs, "opening": not _opening_seen})
	_opening_seen = true


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
	screen.tutorial_exit.connect(func(result: String):
		var idx := int(meta.get("training_index", 0))
		if result == "next":
			_tutorial_v2(idx + 1)
		elif result == "real":
			_quick_v2()
		else:
			_show_title())
	screen.finished.connect(func():
		var online: bool = meta.has("remote")
		if not online:
			SaveGameV2.erase()
		var e := EndingScreenV2.new(game, int(meta.get("seat", 0)))
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
