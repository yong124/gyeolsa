class_name TutorialV2
extends RefCounted
## 튜토리얼 (지시서 T2): data/v2/tutorial.json의 훈련 하나를 새 판 위에서 진행한다.
## 단계마다 먼저 해 보게 하고(do) 그다음 한 줄로 풀어 준다. 할 일 단계는 화면을 어둡게 하고 한 곳만 밝혀 그것만 누르게,
## 보기 단계(watch)는 연출이 끝난 뒤에 그 자리만 밝히며 어둡게 하지 않는다. 훈련이 끝나면 완료 화면(배운 것 3줄).
## 동료는 훈련 중에 차례를 바로 넘기고(투표는 찬성), 단계에 ally 대본이 있으면 그 행동을 먼저 한다.

signal finished(result: String)   # "skip" 건너뜀 · "menu" 메뉴로 · "next" 다음 훈련 · "real" 실전 시작

const BUBBLE_W := 460.0

var scr: GameScreenV2
var cfg: Dictionary               # tutorial.json
var ti := 0                       # 지금 훈련 번호
var training: Dictionary = {}     # 지금 훈련
var steps: Array = []             # 펼친 단계 [{...단계, "si", "ln"}]
var i := 0                        # 지금 단계
var _started_step := -1           # setup을 한 단계
var _first_step := -1             # setup_first를 한 단계
var _did := false                 # 이 단계의 do를 했는가
var _turn_seen := false           # 이 단계에서 내 차례였던 적이 있는가 (차례 마치기를 다른 길로 했을 때)
var _vote_target := ""            # 결행 대상 (동료도 같은 곳에 표)
var _evs := {}                    # 지금 단계 동안 나온 엔진 이벤트 종류 -> 횟수
var _evs_prev := {}               # 앞 단계 동안 나온 이벤트 (앞 단계의 행동이 일으킨 일을 보기 단계가 알아보게)
var _bad_say := ""                # 고르기에서 나쁜 눈을 눌렀을 때의 되묻는 말
var _complete: Control = null     # 완료 화면
var _ally_moved := false          # 동료 시범 이동: 이 단계에서 이동 주사위를 냈는가
var _hud_done := false            # 위쪽 띠의 보일 칸을 정했는가
var spot: Spotlight
var active := true


func _init(screen: GameScreenV2, training_index := 0) -> void:
	scr = screen
	cfg = screen.game.data.tutorial
	var list: Array = cfg.get("trainings", [])
	ti = clampi(training_index, 0, maxi(0, list.size() - 1))
	training = list[ti] if not list.is_empty() else {}
	var ls: Array = training.get("steps", [])
	for si in ls.size():
		var s: Dictionary = (ls[si] as Dictionary).duplicate()
		s["si"] = si
		s["ln"] = ls.size()
		steps.append(s)


static func count(data: GameDataV2) -> int:
	return (data.tutorial.get("trainings", []) as Array).size()


static func new_game(data: GameDataV2, index := 0) -> RulesV2:
	## 훈련 판: 훈련마다 정한 시드 · 요원 (나는 0번). 앞 훈련의 결과에 기대지 않는다
	var t: Dictionary = data.tutorial
	var list: Array = t.get("trainings", [])
	var tr: Dictionary = list[clampi(index, 0, list.size() - 1)] if not list.is_empty() else {}
	var defs := []
	for id in tr.get("characters", t.get("characters", [])):
		defs.append({"name": "나" if defs.is_empty() else str(data.character(str(id)).get("name", "")), "character": str(id)})
	var g := RulesV2.new()
	g.setup(defs, int(tr.get("seed", t.get("seed", 1945))), data)
	return g


func build() -> void:
	spot = Spotlight.new()
	spot.tut = self
	scr.add_child(spot)


func step() -> Dictionary:
	return steps[i] if active and i < steps.size() else {}


# ---------------------------------------------------------------- 진행

func update() -> void:
	## 화면이 갱신될 때마다: 단계 시작 조건이 맞으면 판을 정하고, 해 놓은 일이면 다음 단계로
	if not active or _complete != null:
		return
	if not _hud_done:
		_hud_done = true
		_apply_hud()
	var guard := 0
	while active and i < steps.size() and guard < 8:
		guard += 1
		var s := step()
		if _first_step != i:
			_first_step = i
			_setup(s.get("setup_first", []))   # 이 단계가 되자마자 (when을 기다리지 않고) 판을 바꿈
		if _started_step != i:
			if not _when_ok(s):
				return
			_started_step = i
			_did = false
			_turn_seen = false
			_setup(s.get("setup", []))
		if str(s.get("do", "")) == "complete":
			_show_complete()
			return
		if _done(s):
			_next()
			continue
		return


func _next() -> void:
	i += 1
	_did = false
	_bad_say = ""
	_ally_moved = false
	_evs_prev = _evs
	_evs = {}


func on_event(e: Dictionary) -> void:
	## 화면이 엔진 이벤트를 연출 줄에 넣을 때 (보기 단계가 「방금 그 일이 있었다」를 알아봄)
	var k := str(e.get("kind", ""))
	_evs[k] = int(_evs.get(k, 0)) + 1


func on_action(a: Dictionary) -> void:
	## 화면이 사람의 행동을 엔진에 넣은 뒤
	if not active or int(a.get("player", -1)) != scr.human:
		return
	var s := step()
	if s.is_empty() or _started_step != i:
		return
	if str(a["type"]) == str(s.get("do", "")):
		_did = true
	if str(a["type"]) == "choose" and str(s.get("target", "")).begins_with("choice:"):
		var v := str(a.get("value", ""))
		if v in scr.game.data.base_ids:
			_vote_target = v


func intercept(a: Dictionary) -> bool:
	## 고르기 단계: 나쁜 눈을 누르면 행동을 넣지 않고 이유를 알려 준 뒤 다시 고르게 한다 (막는 게 아니라 알려 주기). 막았으면 true
	var s := step()
	if not active or s.is_empty() or _started_step != i or not s.has("pick"):
		return false
	if str(a["type"]) != str(s.get("do", "")) or int(a.get("player", scr.human)) != scr.human:
		return false
	var pk: Dictionary = s["pick"]
	if scr.game.die_value(int(a.get("die", -1))) == int(pk.get("good", -1)):
		_bad_say = ""
		return false
	_bad_say = str(pk.get("bad_say", ""))
	scr._actions.close_menu()
	Sfx.play("click")
	return true


func press_next() -> void:
	## 말풍선의 「다음」
	var s := step()
	if str(s.get("do", "")) in ["next", "watch", "briefing"] and _started_step == i:
		_did = true
		update()
		scr._refresh()


func holds() -> bool:
	## 보기 단계의 말풍선이 떠 있는 동안은 동료(AI)가 판을 더 진행하지 않는다
	var s := step()
	return active and not s.is_empty() and str(s.get("do", "")) == "watch" and _started_step == i and not _did


func _done(s: Dictionary) -> bool:
	var d := str(s.get("do", "next"))
	var g := scr.game
	var my_turn: bool = g.phase == "turn" and g.current == scr.human
	if d == "reach":
		var c: Array = s.get("cell", [0, 0])
		return g.players[scr.human]["pos"] == Vector2i(int(c[0]), int(c[1]))
	# 이미 그 일을 한 상태면 넘어간다 (미리 눌렀거나 다른 길로 같은 곳에 왔을 때 멈추지 않게)
	match d:
		"start_day":
			if g.phase in ["day", "turn"]:
				return true
		"begin_turn", "move_die":
			if d == "begin_turn" and my_turn:
				return true
			if d == "move_die" and my_turn and g.steps_left > 0:
				return true
		"end_move":
			if my_turn and g.steps_left == 0:
				return true   # 걸음을 다 써서 이미 이동이 끝났으면
		"end_turn":
			if not my_turn and _turn_seen:
				return true
	if my_turn:
		_turn_seen = true
	return _did


func _when_ok(s: Dictionary) -> bool:
	var w: Dictionary = s.get("when", {})
	var g := scr.game
	if scr._playing:
		return false
	if w.has("phase") and g.phase != str(w["phase"]):
		return false
	if w.has("day") and g.day != int(w["day"]):
		return false
	if w.has("act") and g.act != int(w["act"]):
		return false
	if bool(w.get("me", false)) and not (g.phase == "turn" and g.current == scr.human):
		return false
	if w.has("choice") and not (g.phase == "choice" and int(g.pending.get("player", -1)) == scr.human and str(g.pending.get("kind", "")) == str(w["choice"])):
		return false
	if w.has("police") and bool(w["police"]) != g.police.has(scr.human):
		return false
	if w.has("event") and not (_evs.has(str(w["event"])) or _evs_prev.has(str(w["event"]))):
		return false
	if w.has("done") and not bool(g.players[int(w["done"])]["done_today"]):
		return false
	return true


func skip() -> void:
	_finish("skip")


func _finish(result: String) -> void:
	if not active:
		return
	active = false
	if result == "skip":
		Prefs.v2_training_done = true   # 건너뛰면 더는 처음 켤 때마다 권하지 않는다 (훈련 ✓는 아님)
	Prefs.save()
	if is_instance_valid(spot):
		spot.queue_free()
	if _complete != null and is_instance_valid(_complete):
		_complete.queue_free()
	finished.emit(result)


# ---------------------------------------------------------------- 완료 화면

func _show_complete() -> void:
	if _complete != null:
		return
	var id := str(training.get("id", ""))
	if not Prefs.v2_trainings.has(id):
		Prefs.v2_trainings.append(id)
	if ti == 0:
		Prefs.v2_training_done = true
	Prefs.save()
	Sfx.play("success")
	scr._paused = true   # 완료 화면이 떠 있는 동안 판은 가만히 (스페이스 등이 판에 닿지 않게)
	var last := ti >= count(scr.game.data) - 1
	_complete = CompleteCard.new()
	(_complete as CompleteCard).build(str(training.get("title", "")), training.get("learned", []), last, ti + 1,
		func(r): _finish(r))
	scr.add_child(_complete)


class CompleteCard extends Control:
	## 완료 화면: 종이 카드 + 도장 「완료」, 배운 것 3줄, 단추 「다음 훈련」 · 「실전 시작」 · 「메뉴로」
	var _stamp_t := 0.0

	func build(title: String, learned: Array, last: bool, number: int, choose: Callable) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		z_index = 220
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.015, 0.01, 0.7)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var panel := UiKit.paper_panel(28)
		panel.custom_minimum_size = Vector2(520, 0)
		center.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		panel.add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 14)
		v.add_child(head)
		var t := UiKit.title("훈련 %d · %s" % [number, title], 24, Style.INK, 900)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var st := UiKit.title("완료!", 30, Style.SEAL, 900)
		head.add_child(st)
		v.add_child(UiKit.hsep())
		v.add_child(UiKit.text("배운 것", 14, Style.INK_3, false, 800))
		for l in learned:
			var row := UiKit.text("✓ " + str(l), 18, Style.INK, true, 700)
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(row)
		v.add_child(UiKit.hsep())
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 10)
		v.add_child(btns)
		if not last:
			var nx := UiKit.button("다음 훈련", func(): choose.call("next"), 17, "primary")
			nx.custom_minimum_size = Vector2(0, 52)
			nx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btns.add_child(nx)
		var rl := UiKit.button("실전 시작", func(): choose.call("real"), 22 if last else 17, "primary" if last else "paper")
		rl.custom_minimum_size = Vector2(0, 64 if last else 52)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(rl)
		var mn := UiKit.button("메뉴로", func(): choose.call("menu"), 15, "tab")
		mn.custom_minimum_size = Vector2(0, 52)
		btns.add_child(mn)

	func _process(delta: float) -> void:
		_stamp_t += delta


# ---------------------------------------------------------------- 판 정하기

func _cell(v, fallback: Vector2i) -> Vector2i:
	if str(v) == "me":
		return scr.game.players[scr.human]["pos"]
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return fallback


func _who(v) -> int:
	return scr.human if str(v) == "me" else int(v)


func _setup(ops: Array) -> void:
	if ops.is_empty():
		return
	var g := scr.game
	var keep_events := false
	for o in ops:
		match str(o.get("op", "")):
			"calm":
				g.police = {}   # 훈련이 흔들리지 않게: 경찰 · 위협 효과를 지운다
				g.today["police_speed"] = 0
				g.today["dice_mod"] = 0
			"threats":
				var ids: Array = o.get("ids", [])
				var deck := ids.duplicate()
				deck.reverse()   # 덱 맨 위는 배열의 끝
				g.threat_deck = deck
			"dice":
				var vals: Array = o.get("values", [])
				var who := _who(o.get("who", "me"))
				if bool(o.get("exact", false)):
					# 그 요원의 안 쓴 주사위를 모두 지우고 정한 눈만 새로 둔다
					g.op_dice = g.op_dice.filter(func(d): return int(d["owner"]) != who or d["used"])
					for v in vals:
						g.op_dice.append({"value": int(v), "owner": who, "used": false})
				else:
					var k := 0
					for d in g.op_dice:
						if int(d["owner"]) == who and not d["used"] and k < vals.size():
							d["value"] = int(vals[k])
							k += 1
					while k < vals.size():   # 모자라면 더한다 (2막 3개 등)
						g.op_dice.append({"value": int(vals[k]), "owner": who, "used": false})
						k += 1
			"pos":
				var c := _cell(o.get("cell"), Vector2i.ZERO)
				_ensure_tile(c)
				g.players[_who(o.get("who", "me"))]["pos"] = c
			"tiles":
				for c in o.get("cells", []):
					var cc := Vector2i(int(c[0]), int(c[1]))
					if not g.board.has(cc):
						g.board[cc] = {"type": str(o.get("type", "normal")), "used": false, "flags": []}
					else:
						g.board[cc]["type"] = str(o.get("type", "normal"))
			"tile_type":
				var c2 := _cell(o.get("cell"), Vector2i.ZERO)
				_ensure_tile(c2)
				g.board[c2]["type"] = str(o.get("type", "normal"))
			"missions":
				for id in g.mission_row.duplicate():
					g._remove_card(id)
				for id in o.get("ids", []):
					g.mission_deck.erase(str(id))
					g.mission_row.append(str(id))
					g._place_card(str(id))
			"marker":
				for m in g.markers:
					if str(m["id"]) == str(o.get("id", "")) and str(m["role"]) == str(o.get("role", "")):
						var mc := _cell(o.get("cell"), m["pos"])
						_ensure_tile(mc)
						m["pos"] = mc
						break
			"police_on_me":
				if not g.police.has(scr.human):
					g._summon(g.players[scr.human])
			"police_set":
				if g.police.has(scr.human):
					var pc := _cell(o.get("cell"), g.police[scr.human]["pos"])
					_ensure_tile(pc)
					g.police[scr.human]["pos"] = pc
					g.police[scr.human]["summon_turn"] = int(g.players[scr.human]["turns"]) - 1   # 바로 움직이는 경찰 (이번 차례 끝에 다가옴)
			"today_threat":
				g.threat_today = str(o.get("id", ""))   # 오늘 위협을 보이는 카드로 맞춤 (효과는 다시 내지 않음)
			"ready":
				g.ready = int(o.get("value", 0))
			"intel":
				g.intel[str(o.get("base", ""))] = int(o.get("value", 0))
			"day":
				var dv := int(o.get("value", g.day))
				g.day = dv
				g.rounds_left = g.rounds_total - dv + 1
			"rig":
				for v in o.get("values", []):
					g.rigged_rolls.append(int(v))
			"work_paid":
				var st: Dictionary = g.mission_state.get(str(o.get("id", "")), {})
				for v in o.get("values", []):
					if st.has("left"):
						st["left"].erase(int(v))
			"tile_deck":
				# 걸어 들어갈 때 뒤집힐 타일: ids 앞부터 차례로 (덱 맨 위는 배열의 끝)
				var td: Array = o.get("ids", []).duplicate()
				td.reverse()
				for t in td:
					g.tile_deck.append(str(t))
			"item_deck":
				# 다음에 뽑힐 아이템: ids 앞부터 차례로
				var idk: Array = o.get("ids", []).duplicate()
				idk.reverse()
				for t in idk:
					g.item_deck.erase(str(t))
					g.item_deck.append(str(t))
			"hand":
				# 손패에 아이템을 넣어 둔다 (앞 훈련에서 얻은 것처럼)
				for t in o.get("ids", []):
					g.item_deck.erase(str(t))
					g.players[_who(o.get("who", "me"))]["items"].append(str(t))
			"no_ops":
				g.op_deck = []   # 짝수 날 아침에도 일제 작전이 나오지 않게
				g.op_discard = []
			"morning":
				# 그날 아침으로 가서 결행 투표를 연다 (준비 · 첩보는 앞에서 정해 둠)
				var md := int(o.get("day", g.day + 1))
				g.day = md - 1
				g.rounds_left = g.rounds_total - md + 1
				g._begin_morning(false)
				keep_events = true
	if not keep_events:
		g.events.clear()
	g._dist_cache = {}
	scr._board.sync_from_game()
	scr._refresh_panels()
	if keep_events:
		scr._pump()   # 아침 연출(위협 카드 · 투표 창)을 보여 준다


func _ensure_tile(c: Vector2i) -> void:
	if not scr.game.board.has(c):
		scr.game.board[c] = {"type": "normal", "used": false, "flags": []}


# ---------------------------------------------------------------- 동료

func ally_action(pid: int) -> Dictionary:
	## 훈련 중 동료: 단계에 ally 대본이 있으면 그 행동을 먼저, 아니면 차례는 바로 넘기고 결행 투표는 찬성 · 같은 거점
	var g := scr.game
	if not active:
		return {}
	var s := step()
	if not s.is_empty() and s.has("ally"):
		var al: Dictionary = s["ally"]
		if int(al.get("who", -1)) == pid and g.phase == "turn" and g.current == pid and str(al.get("do", "")) == "move":
			var mv := _ally_move(pid, al)
			if not mv.is_empty():
				return mv
		elif int(al.get("who", -1)) == pid and g.phase == "turn" and g.current == pid:
			for a in g.legal_actions():
				if int(a.get("player", -1)) != pid or str(a["type"]) != str(al.get("do", "")):
					continue
				if al.has("die") and g.die_value(int(a.get("die", -1))) != int(al["die"]):
					continue
				return a
	match g.phase:
		"turn":
			if g.current == pid:
				for a in g.legal_actions():
					if a["type"] == "end_turn" and int(a["player"]) == pid:
						return a
		"choice":
			match str(g.pending.get("kind", "")):
				"launch_vote":
					return {"type": "choose", "player": pid, "value": true}
				"launch_target":
					var want := _vote_target if _vote_target != "" else "prison"
					for o in g.pending.get("options", []):
						if str(o["value"]) == want:
							return {"type": "choose", "player": pid, "value": o["value"]}
	return {}


func _ally_move(pid: int, al: Dictionary) -> Dictionary:
	## 동료 시범 이동: 정한 눈의 주사위로 이동하고, path의 칸을 차례로 걷고, 다 걸으면 이동을 마친다. 끝났으면 빈 사전
	var g := scr.game
	var acts := g.legal_actions().filter(func(a): return int(a.get("player", -1)) == pid)
	if g.steps_left == 0 and not _ally_moved:
		for a in acts:
			if str(a["type"]) == "move_die" and g.die_value(int(a["die"])) == int(al.get("die", -1)):
				_ally_moved = true
				return a
		return {}
	if g.steps_left > 0:
		var path: Array = al.get("path", [])
		var pos: Vector2i = g.players[pid]["pos"]
		var k := 0
		for pi in path.size():
			if Vector2i(int(path[pi][0]), int(path[pi][1])) == pos:
				k = pi + 1
		if k < path.size():
			var want := Vector2i(int(path[k][0]), int(path[k][1]))
			for a in acts:
				if str(a["type"]) == "step" and a["to"] == want:
					return a
		for a in acts:
			if str(a["type"]) == "end_move":
				return a
	return {}


# ---------------------------------------------------------------- 보일 것 (단계적 공개)

func verb_shown(key: String) -> bool:
	## 이 훈련에서 행동 단추를 보이는가 (show.verbs가 없으면 전부)
	var sh: Dictionary = training.get("show", {})
	if not active or not sh.has("verbs"):
		return true
	return key in sh["verbs"]


func _apply_hud() -> void:
	## 위쪽 띠: show.hud에 없는 칸은 흐리게 (자리는 그대로 두어 화면이 흔들리지 않게)
	var sh: Dictionary = training.get("show", {})
	if not sh.has("hud"):
		return
	var hud: Array = sh["hud"]
	var top = scr._top
	var parts := {"calendar": top._cal, "ready": top._gauge, "threat": top._threat, "alert": top._alert, "trend": top._trend_box}
	for k in parts:
		var c = parts[k]
		if c is CanvasItem and is_instance_valid(c):
			(c as CanvasItem).modulate.a = 1.0 if k in hud else 0.18


# ---------------------------------------------------------------- 밝힐 곳

func focus() -> Array:
	## [밝힐 곳(화면 좌표, 없으면 빈 Rect2), 머리글, 말풍선 글, 「다음」 단추가 있나, 모드("do" 해 보기 · "next" 읽기 · "watch" 보기)]
	var none := [Rect2(), "", "", false, "do"]
	if not active or _complete != null or scr._playing or scr._paused or not scr._started:
		return none
	var g := scr.game
	var s := step()
	if s.is_empty():
		return none
	var head := "훈련 %d · %s · %d/%d" % [ti + 1, training.get("title", ""), int(s["si"]) + 1, int(s["ln"])]
	if _started_step != i:
		# 아직 이 단계의 때가 아님: 사람의 선택 창이 떠 있으면 그것만 밝힌다
		if g.phase == "choice" and int(g.pending.get("player", -1)) == scr.human and scr._choice.visible:
			return [_choice_rect(), head, "창에서 하나를 고릅니다.", false, "do"]
		return none
	var d := str(s.get("do", ""))
	if d == "briefing":
		return [Rect2(), head, _briefing_text(s), not _did, "briefing"] if not _did else none
	if d != "next" and d != "watch" and _did:
		return none
	if d == "watch" and _did:
		return none
	var t := str(s.get("target", ""))
	if scr._choice != null and scr._choice.visible and not t.begins_with("choice"):
		# 확인 · 선택 창이 떠 있으면 그 창을 밝힌다 (예: 주사위가 남았는데 차례 마치기)
		return [_choice_rect(), head, "창에서 「그래도 마친다」를 고릅니다." if d == "end_turn" else "창에서 하나를 고릅니다.", false, "do"]
	var r := _target_rect(t)
	var say := _bad_say if _bad_say != "" else str(s.get("say", ""))
	return [r, head, say, d == "next" or d == "watch", "next" if d == "next" else ("watch" if d == "watch" else "do")]


func _next_cell(goal: Vector2i) -> Vector2i:
	## 걷는 중: 목표로 가는 다음 옆 칸 (덮인 칸은 한 칸씩 눌러 들어가므로 한 칸만 밝힌다)
	var g := scr.game
	var pos: Vector2i = g.players[scr.human]["pos"]
	if g.steps_left <= 0 or pos == goal:
		return goal
	var best := goal
	var bd := 1 << 20
	for a in g.legal_actions():
		if str(a["type"]) == "step" and int(a.get("player", -1)) == scr.human:
			var to: Vector2i = a["to"]
			var d := absi(to.x - goal.x) + absi(to.y - goal.y)
			if d < bd:
				bd = d
				best = to
	return best


func action_shown(a: Dictionary) -> bool:
	## 이 훈련에서 보일 보조 행동인가: 아이템 · 능력은 show.extras에 있을 때만 (show가 없으면 전부)
	var sh: Dictionary = training.get("show", {})
	if not active or sh.is_empty():
		return true
	if str(a.get("type", "")) in ["use_item", "ability", "use_intel"]:
		return str(a["type"]) in sh.get("extras", [])
	return true


func _briefing_text(s: Dictionary) -> String:
	## 작전 브리핑 카드: 제목과 번호 붙은 짧은 줄 (말풍선 자리에 크게)
	var out := "[font_size=26][b]%s[/b][/font_size]\n" % str(s.get("title", "작전 브리핑"))
	var marks := ["①", "②", "③", "④"]
	var lines: Array = s.get("lines", [])
	for li in lines.size():
		out += "\n%s %s" % [marks[mini(li, 3)], str(lines[li])]
	return out


func _ok(c) -> bool:
	return c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree()


func _target_rect(t: String) -> Rect2:
	var f: Dictionary = scr._actions.focus
	var g := scr.game
	if t == "":
		return Rect2()
	if t == "primary":
		return f["primary"].get_global_rect() if _ok(f.get("primary")) else Rect2()
	if t == "end_turn":
		if _ok(f.get("end_turn")):
			return f["end_turn"].get_global_rect()
		return f["primary"].get_global_rect() if _ok(f.get("primary")) else Rect2()
	if t.begins_with("act:"):
		var parts := t.split(":")
		var verb := parts[1]
		var val := int(parts[2]) if parts.size() > 2 else -1
		if scr._actions._menu != null and _ok(f.get("menu_any")):
			return f["menu_any"].get_global_rect()
		if scr._verb == verb:
			if val < 0:
				return scr._dice_row.get_global_rect() if _ok(scr._dice_row) else Rect2()   # 아무 주사위나 (고르기)
			for di in f.get("dice", {}):
				var d: Dictionary = g.op_dice[di]
				if int(d["value"]) == val and not d["used"] and _ok(f["dice"][di]):
					return f["dice"][di].get_global_rect()
		var vb = f.get("verbs", {}).get(verb)
		return vb.get_global_rect() if _ok(vb) else Rect2()
	if t.begins_with("verb:"):
		var vb2 = f.get("verbs", {}).get(t.substr(5))
		return vb2.get_global_rect() if _ok(vb2) else Rect2()
	if t.begins_with("cell:"):
		var xy := t.substr(5).split(",")
		var goal := Vector2i(int(xy[0]), int(xy[1]))
		var st := step()
		if str(st.get("do", "")) == "reach" and _started_step == i:
			return _cell_rect(_next_cell(goal))
		return _cell_rect(goal)
	if t == "me":
		return _cell_rect(g.players[scr.human]["pos"])
	if t == "police":
		var pp = g.police.get(scr.human, {}).get("pos")
		return _cell_rect(pp) if pp is Vector2i else Rect2()
	if t.begins_with("choice"):
		if not scr._choice.visible:
			return Rect2()
		if t.begins_with("choice:"):
			var b = scr._choice_btns.get(t.substr(7))
			if _ok(b):
				return b.get_global_rect()
		return _choice_rect()
	if t.begins_with("mission:"):
		var card = scr._mission_cards.get(t.substr(8))
		return card.get_global_rect() if _ok(card) else Rect2()
	if t == "board":
		return scr._board_rect()
	if t == "me_card":
		var mc: Control = scr._me_box.get_parent() if scr._me_box.get_parent() is Control else scr._me_box
		return mc.get_global_rect()
	if t == "ability" or t.begins_with("item:"):
		var fb = f.get(t)
		return fb.get_global_rect() if _ok(fb) else Rect2()
	var node = {"dock": scr._right, "top": scr._top, "dice": scr._dice_row, "threat": scr._top._threat, "missions": scr._mid_box, "ops": scr._ops_row,
		"hand": scr._hand_row, "allies": scr._left, "ready": scr._top._gauge, "alert": scr._top._alert, "calendar": scr._top._cal,
		"trend": scr._top._trend_box}.get(t)
	return node.get_global_rect() if _ok(node) else Rect2()


func _choice_rect() -> Rect2:
	for c in scr._choice.get_children():
		if c is PanelContainer or c is CenterContainer:
			var r: Rect2 = (c as Control).get_global_rect()
			if c is CenterContainer and c.get_child_count() > 0:
				r = (c.get_child(0) as Control).get_global_rect()
			return r
	return scr._choice.get_global_rect()


func _cell_rect(c: Vector2i) -> Rect2:
	var ctr: Vector2 = scr._cell_screen(c)
	var side := 64.0
	if scr._tilt == null:
		side = scr._board.cell_rect(c).size.x
	return Rect2(ctr - Vector2(side, side) / 2.0, Vector2(side, side))


# ---------------------------------------------------------------- 입력 막기

func block(event: InputEvent) -> bool:
	## 밝힌 곳 · 말풍선 · 건너뛰기 밖의 클릭과 키는 막는다 (Esc는 일시정지라 둔다)
	if not active or not is_instance_valid(spot) or _complete != null:
		return false
	var f := focus()
	if f[1] == "":
		return false
	if event is InputEventKey:
		return event.pressed and event.keycode != KEY_ESCAPE
	if not (event is InputEventMouseButton and event.pressed):
		return false
	var p: Vector2 = (event as InputEventMouseButton).position   # 누른 자리 (화면 좌표)
	if spot.owns(p):
		return false
	if f[3]:
		return true   # 읽기 · 보기 단계: 밝힌 곳은 보여 주기만 (미리 눌러 앞 단계를 건너뛰지 않게) · 「다음」만
	var r: Rect2 = f[0]
	if r.size != Vector2.ZERO and r.grow(4.0).has_point(p):
		return false
	return true


# ================================================================ 화면: 어둡게 + 한 곳만 밝게 + 말풍선

class Spotlight extends Control:
	var tut
	var _t := 0.0
	var _hole := Rect2()
	var _avoid := Rect2()         # 말풍선이 가리지 말아야 할 곳 (밝힌 곳 + 떠 있는 선택 창)
	var _mode := "do"
	var _bubble: PanelContainer
	var _head: Label
	var _say: RichTextLabel
	var _next: Button
	var _tag: HBoxContainer
	var _skip: Button
	var _key := ""
	var _placed_for := ""         # 말풍선 자리를 정한 단계 · 밝힌 곳 (바뀔 때만 다시 정함)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 200   # 큰 카드 미리보기 · 선택 창보다 위
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bubble = PanelContainer.new()
		var st := Style.flat(Color("#fff6e0"), Style.SEAL, 3, 6, 16)
		_bubble.add_theme_stylebox_override("panel", st)
		_bubble.custom_minimum_size = Vector2(TutorialV2.BUBBLE_W, 0)
		_bubble.z_index = 41
		add_child(_bubble)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_bubble.add_child(v)
		_head = UiKit.text("", 13, Style.SEAL, false, 800)
		v.add_child(_head)
		_say = RichTextLabel.new()
		_say.bbcode_enabled = true
		_say.fit_content = true
		_say.scroll_active = false
		_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_say.custom_minimum_size = Vector2(TutorialV2.BUBBLE_W - 32.0, 0)
		_say.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_say.add_theme_font_override("normal_font", Style.sans(600))
		_say.add_theme_font_override("bold_font", Style.sans(900))
		_say.add_theme_font_size_override("normal_font_size", 18)
		_say.add_theme_font_size_override("bold_font_size", 18)
		_say.add_theme_color_override("default_color", Style.INK)
		v.add_child(_say)
		_next = UiKit.button("다음 ▶", func(): tut.press_next(), 16, "primary")
		_next.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS   # 누르는 순간 (말풍선이 움직여도 놓치지 않게)
		_next.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(_next)
		_tag = HBoxContainer.new()
		_tag.add_theme_constant_override("separation", 6)
		_tag.size_flags_horizontal = Control.SIZE_SHRINK_END
		_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var finger := Finger.new()
		finger.custom_minimum_size = Vector2(22, 22)
		_tag.add_child(finger)
		_tag.add_child(UiKit.text("직접 해 봅니다", 14, Style.SEAL, false, 800))
		v.add_child(_tag)
		_skip = UiKit.button("훈련 건너뛰기", func(): _ask_skip(), 12, "tab")
		_skip.z_index = 41
		add_child(_skip)

	func owns(p: Vector2) -> bool:
		return (_bubble.visible and _bubble.get_global_rect().has_point(p)) or _skip.get_global_rect().has_point(p)

	func _ask_skip() -> void:
		if _skip.text == "정말 건너뛰겠습니까? 한 번 더 누르면 메뉴로 갑니다":
			tut.skip()
			return
		_skip.text = "정말 건너뛰겠습니까? 한 번 더 누르면 메뉴로 갑니다"

	static func markup(s: String) -> String:
		return s.replace("[b]", "[b][color=#a83a2c]").replace("[/b]", "[/color][/b]")

	func _process(delta: float) -> void:
		_t += delta
		var f: Array = tut.focus()
		var on: bool = f[1] != ""
		_bubble.visible = on
		_hole = f[0]
		_avoid = _hole
		if on and tut.scr._choice != null and tut.scr._choice.visible and _hole.size != Vector2.ZERO:
			_avoid = _hole.merge(tut._choice_rect())   # 선택 창의 다른 단추를 말풍선이 덮지 않게
		_mode = str(f[4])
		if on and is_instance_valid(tut.scr._peek):
			tut.scr._peek.visible = false   # 훈련 중에는 큰 카드가 말풍선 · 밝힌 곳을 가리지 않게
		if on:
			_next.text = "작전 시작 ▶" if _mode == "briefing" else "다음 ▶"
			var bw := 600.0 if _mode == "briefing" else TutorialV2.BUBBLE_W
			if _bubble.custom_minimum_size.x != bw:
				_key = ""   # 폭이 바뀌면 글 높이를 다시 잰다
			_bubble.custom_minimum_size.x = bw
			_say.custom_minimum_size.x = _bubble.custom_minimum_size.x - 32.0
			var key := str(f[1]) + str(f[2]) + str(f[4])
			if key != _key:
				_key = key
				_head.text = f[1]
				_say.text = markup(str(f[2]))
				_bubble.reset_size()
			_next.visible = f[3]
			_tag.visible = _mode == "do"
			_bubble.reset_size()   # 글 높이가 한 프레임 늦게 정해지므로 늘 글에 맞춘다 (남는 빈 공간 없게)
			var pk := _key + str(_avoid) + str(_bubble.size)
			if pk != _placed_for:
				_placed_for = pk
				_place_bubble()
		_skip.position = Vector2(16, size.y - 44)
		queue_redraw()

	func _place_bubble() -> void:
		## 밝힌 곳을 절대 가리지 않게: 아래 → 위 → 오른쪽 → 왼쪽 중 들어가는 곳 (크기는 글이 줄바꿈된 실제 크기)
		var b := _bubble.get_combined_minimum_size().max(_bubble.size)
		if _hole.size == Vector2.ZERO:
			_bubble.position = (size - b) / 2.0
			return
		var h := _avoid.grow(14.0)
		var cx := clampf(h.get_center().x - b.x / 2.0, 10, size.x - b.x - 10)
		var cy := clampf(h.get_center().y - b.y / 2.0, 10, size.y - b.y - 10)
		var tries := [Vector2(cx, h.end.y), Vector2(cx, h.position.y - b.y), Vector2(h.end.x, cy), Vector2(h.position.x - b.x, cy)]
		if _avoid.size.y > size.y * 0.5:
			tries = [Vector2(h.end.x, cy), Vector2(h.position.x - b.x, cy), Vector2(cx, h.end.y), Vector2(cx, h.position.y - b.y)]
		var screen := Rect2(Vector2(8, 8), size - Vector2(16, 16))
		for p in tries:
			if screen.encloses(Rect2(p, b)) and not Rect2(p, b).intersects(_avoid.grow(4.0)):
				_bubble.position = p
				return
		_bubble.position = Vector2(cx, 10) if _avoid.get_center().y > size.y / 2.0 else Vector2(cx, size.y - b.y - 10)

	func _draw() -> void:
		if not _bubble.visible:
			return
		var dim := Color(0.02, 0.015, 0.01, 0.72)
		var a := 0.7 + 0.3 * sin(_t * 4.0)
		if _mode == "watch":
			# 보기 단계는 어둡게 하지 않고 그 자리만 밝힌다
			if _hole.size != Vector2.ZERO:
				var w := _hole.grow(6.0)
				draw_rect(w, Color(Style.GOLD_HI, a), false, 4.0)
				draw_rect(w.grow(3.0), Color(Style.SEAL, a * 0.8), false, 2.0)
			return
		if _hole.size == Vector2.ZERO:
			draw_rect(Rect2(Vector2.ZERO, size), dim)
			return
		var h := _hole.grow(6.0)
		draw_rect(Rect2(0, 0, size.x, h.position.y), dim)
		draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), dim)
		draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), dim)
		draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), dim)
		draw_rect(h, Color(Style.GOLD_HI, a), false, 4.0)
		draw_rect(h.grow(3.0), Color(Style.SEAL, a * 0.8), false, 2.0)


class Finger extends Control:
	## 「해 보세요」 꼬리표의 작은 손가락 (그림 글꼴에 기대지 않고 도형으로)
	func _draw() -> void:
		var ink := Style.SEAL
		draw_rect(Rect2(8, 1, 6, 12), Color("#fff6e0"))
		draw_rect(Rect2(8, 1, 6, 12), ink, false, 2.0)
		draw_rect(Rect2(3, 10, 16, 10), Color("#fff6e0"))
		draw_rect(Rect2(3, 10, 16, 10), ink, false, 2.0)
		draw_line(Vector2(9, 11), Vector2(13, 11), Color("#fff6e0"), 2.0)
