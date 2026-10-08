class_name TutorialV2
extends RefCounted
## 튜토리얼 (지시서 T): data/v2/tutorial.json의 레슨을 한 판 위에서 차례로 진행한다.
## 단계마다 판을 정해 두고(setup), 화면을 어둡게 한 뒤 한 곳만 밝혀(target) 그 일만 하게 한다(do).
## 동료는 레슨 중에 차례를 바로 넘기고(투표는 찬성), 사람의 뜻밖의 선택 창은 「고르세요」로 밝힌다.

signal finished(skipped: bool)

var scr: GameScreenV2
var cfg: Dictionary               # tutorial.json
var steps: Array = []             # 펼친 단계 [{"lesson", "li", "si", ...단계}]
var i := 0                        # 지금 단계
var _started_step := -1           # setup을 한 단계
var _did := false                 # 이 단계의 do를 했는가
var _turn_seen := false           # 이 단계에서 내 차례였던 적이 있는가 (차례 마치기를 다른 길로 했을 때)
var _vote_target := ""            # 결행 대상 (동료도 같은 곳에 표)
var spot: Spotlight
var active := true


func _init(screen: GameScreenV2) -> void:
	scr = screen
	cfg = screen.game.data.tutorial
	var lessons: Array = cfg.get("lessons", [])
	for li in lessons.size():
		var l: Dictionary = lessons[li]
		var ls: Array = l.get("steps", [])
		for si in ls.size():
			var s: Dictionary = (ls[si] as Dictionary).duplicate()
			s["lesson"] = str(l.get("title", ""))
			s["li"] = li
			s["si"] = si
			s["ln"] = ls.size()
			steps.append(s)


static func new_game(data: GameDataV2) -> RulesV2:
	## 튜토리얼 판: 정한 시드 · 요원 (나는 0번)
	var t: Dictionary = data.tutorial
	var defs := []
	for id in t.get("characters", []):
		defs.append({"name": "나" if defs.is_empty() else str(data.character(str(id)).get("name", "")), "character": str(id)})
	var g := RulesV2.new()
	g.setup(defs, int(t.get("seed", 1945)), data)
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
	if not active:
		return
	var guard := 0
	while active and i < steps.size() and guard < 8:
		guard += 1
		var s := step()
		if _started_step != i:
			if not _when_ok(s):
				return
			_started_step = i
			_did = false
			_turn_seen = false
			_setup(s.get("setup", []))
		if _done(s):
			_next()
			continue
		return
	if i >= steps.size():
		_finish(false)


func _next() -> void:
	i += 1
	_did = false
	if i >= steps.size():
		_finish(false)


func on_action(a: Dictionary) -> void:
	## 화면이 사람의 행동을 엔진에 넣은 뒤
	if not active or int(a.get("player", -1)) != scr.human:
		return
	var s := step()
	if s.is_empty() or _started_step != i:
		return
	if str(a["type"]) == str(s.get("do", "")):
		_did = true
	if str(a["type"]) == "choose" and str(scr.game.pending.get("kind", "")) == "launch_target":
		pass
	if str(a["type"]) == "choose" and str(s.get("target", "")).begins_with("choice:"):
		var v := str(a.get("value", ""))
		if v in scr.game.data.base_ids:
			_vote_target = v


func press_next() -> void:
	## 말풍선의 「다음」
	var s := step()
	if str(s.get("do", "")) == "next":
		_did = true
		update()
		scr._refresh()


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
	return true


func skip() -> void:
	_finish(true)


func _finish(skipped: bool) -> void:
	if not active:
		return
	active = false
	Prefs.v2_training_done = true
	Prefs.save()
	if is_instance_valid(spot):
		spot.queue_free()
	finished.emit(skipped)


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
	for o in ops:
		match str(o.get("op", "")):
			"calm":
				g.police = {}   # 레슨이 흔들리지 않게: 경찰 · 위협 효과를 지운다
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
						m["pos"] = _cell(o.get("cell"), m["pos"])
						break
			"police_on_me":
				if not g.police.has(scr.human):
					g._summon(g.players[scr.human])
			"today_threat":
				g.threat_today = str(o.get("id", ""))   # 오늘 위협을 보이는 카드로 맞춤 (효과는 다시 내지 않음)
			"funds":
				g.funds = int(o.get("value", 0))
			"ready":
				g.ready = int(o.get("value", 0))
			"intel":
				g.intel[str(o.get("base", ""))] = int(o.get("value", 0))
	g.events.clear()
	g._dist_cache = {}
	scr._board.sync_from_game()
	scr._refresh_panels()


func _ensure_tile(c: Vector2i) -> void:
	if not scr.game.board.has(c):
		scr.game.board[c] = {"type": "normal", "used": false, "flags": []}


# ---------------------------------------------------------------- 동료

func ally_action(pid: int) -> Dictionary:
	## 레슨 중 동료: 차례는 바로 넘기고, 결행 투표는 찬성 · 같은 거점. 그 밖의 선택은 AI
	var g := scr.game
	if not active:
		return {}
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


# ---------------------------------------------------------------- 밝힐 곳

func focus() -> Array:
	## [밝힐 곳(화면 좌표, 없으면 빈 Rect2), 말풍선 제목, 글, 「다음」 단추가 있나]
	var none := [Rect2(), "", "", false]
	if not active or scr._playing or scr._paused or not scr._started:
		return none
	var g := scr.game
	var s := step()
	if s.is_empty():
		return none
	var head := "튜토리얼 %d/%d · %s" % [int(s["li"]) + 1, cfg.get("lessons", []).size(), s["lesson"]]
	if _started_step != i:
		# 아직 이 단계의 때가 아님: 사람의 선택 창이 떠 있으면 그것만 밝힌다
		if g.phase == "choice" and int(g.pending.get("player", -1)) == scr.human and scr._choice.visible:
			return [_choice_rect(), head, "하나를 고르세요.", false]
		return none
	if str(s.get("do", "")) != "next" and _did:
		return none
	var t := str(s.get("target", ""))
	if scr._choice != null and scr._choice.visible and not t.begins_with("choice"):
		# 확인 · 선택 창이 떠 있으면 그 창을 밝힌다 (예: 주사위가 남았는데 차례 마치기)
		return [_choice_rect(), head, "창에서 고르세요. 「그래도 마친다」처럼 하려던 일을 이어 가면 됩니다.", false]
	var r := _target_rect(t)
	return [r, head, str(s.get("say", "")), str(s.get("do", "")) == "next"]


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
			for di in f.get("dice", {}):
				var d: Dictionary = g.op_dice[di]
				if (val < 0 or int(d["value"]) == val) and not d["used"] and _ok(f["dice"][di]):
					return f["dice"][di].get_global_rect()
		var vb = f.get("verbs", {}).get(verb)
		return vb.get_global_rect() if _ok(vb) else Rect2()
	if t.begins_with("verb:"):
		var vb2 = f.get("verbs", {}).get(t.substr(5))
		return vb2.get_global_rect() if _ok(vb2) else Rect2()
	if t.begins_with("cell:"):
		var xy := t.substr(5).split(",")
		return _cell_rect(Vector2i(int(xy[0]), int(xy[1])))
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
	var node = {"dock": scr._right, "top": scr._top, "dice": scr._dice_row, "threat": scr._top._threat, "missions": scr._mid_box, "ops": scr._ops_row,
		"hand": scr._hand_row, "allies": scr._left, "ready": scr._top._gauge}.get(t)
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
	if not active or not is_instance_valid(spot):
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
		return true   # 설명 단계: 밝힌 곳은 보여 주기만 (미리 눌러 앞 단계를 건너뛰지 않게) · 「다음」만
	var r: Rect2 = f[0]
	if r.size != Vector2.ZERO and r.grow(4.0).has_point(p):
		return false
	return true


# ================================================================ 화면: 어둡게 + 한 곳만 밝게 + 말풍선

class Spotlight extends Control:
	var tut
	var _t := 0.0
	var _hole := Rect2()
	var _bubble: PanelContainer
	var _head: Label
	var _say: Label
	var _next: Button
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
		_bubble.custom_minimum_size = Vector2(440, 0)
		_bubble.z_index = 41
		add_child(_bubble)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_bubble.add_child(v)
		_head = UiKit.text("", 13, Style.SEAL, false, 800)
		v.add_child(_head)
		_say = UiKit.text("", 17, Style.INK, true, 600)
		_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_say.custom_minimum_size = Vector2(408, 0)
		v.add_child(_say)
		_next = UiKit.button("다음 ▸", func(): tut.press_next(), 16, "primary")
		_next.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS   # 누르는 순간 (말풍선이 움직여도 놓치지 않게)
		_next.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(_next)
		_skip = UiKit.button("튜토리얼 건너뛰기", func(): _ask_skip(), 12, "tab")
		_skip.z_index = 41
		add_child(_skip)

	func owns(p: Vector2) -> bool:
		return (_bubble.visible and _bubble.get_global_rect().has_point(p)) or _skip.get_global_rect().has_point(p)

	func _ask_skip() -> void:
		if _skip.text == "정말 건너뛸까요? 한 번 더 누르면 메뉴로":
			tut.skip()
			return
		_skip.text = "정말 건너뛸까요? 한 번 더 누르면 메뉴로"

	func _process(delta: float) -> void:
		_t += delta
		var f: Array = tut.focus()
		var on: bool = f[1] != ""
		_bubble.visible = on
		_hole = f[0]
		if on and is_instance_valid(tut.scr._peek):
			tut.scr._peek.visible = false   # 레슨 중에는 큰 카드가 말풍선 · 밝힌 곳을 가리지 않게
		if on:
			var key := str(f[1]) + str(f[2])
			if key != _key:
				_key = key
				_head.text = f[1]
				_say.text = f[2]
				_bubble.reset_size()
			_next.visible = f[3]
			var pk := _key + str(_hole) + str(_bubble.size)
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
		var h := _hole.grow(14.0)
		var cx := clampf(h.get_center().x - b.x / 2.0, 10, size.x - b.x - 10)
		var cy := clampf(h.get_center().y - b.y / 2.0, 10, size.y - b.y - 10)
		var tries := [Vector2(cx, h.end.y), Vector2(cx, h.position.y - b.y), Vector2(h.end.x, cy), Vector2(h.position.x - b.x, cy)]
		if _hole.size.y > size.y * 0.5:
			tries = [Vector2(h.end.x, cy), Vector2(h.position.x - b.x, cy), Vector2(cx, h.end.y), Vector2(cx, h.position.y - b.y)]
		var screen := Rect2(Vector2(8, 8), size - Vector2(16, 16))
		for p in tries:
			if screen.encloses(Rect2(p, b)) and not Rect2(p, b).intersects(_hole.grow(4.0)):
				_bubble.position = p
				return
		_bubble.position = Vector2(cx, 10) if _hole.get_center().y > size.y / 2.0 else Vector2(cx, size.y - b.y - 10)

	func _draw() -> void:
		if not _bubble.visible:
			return
		var dim := Color(0.02, 0.015, 0.01, 0.72)
		if _hole.size == Vector2.ZERO:
			draw_rect(Rect2(Vector2.ZERO, size), dim)
			return
		var h := _hole.grow(6.0)
		draw_rect(Rect2(0, 0, size.x, h.position.y), dim)
		draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), dim)
		draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), dim)
		draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), dim)
		var a := 0.7 + 0.3 * sin(_t * 4.0)
		draw_rect(h, Color(Style.GOLD_HI, a), false, 4.0)
		draw_rect(h.grow(3.0), Color(Style.SEAL, a * 0.8), false, 2.0)
