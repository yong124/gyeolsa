class_name ScreenPreviewV2
extends RefCounted
## 선택 미리보기 띠 (U1): 갈 곳 · 얻는 것 · 위험. 칸이나 행동에 마우스를 올리면 바뀐다.
## 상태는 화면(GameScreenV2)에 두고, 이 파일은 화면을 scr로 받아 그 일만 한다 (지시서 Z4).

var scr: GameScreenV2   # 이 모듈이 맡은 화면


func _init(screen: GameScreenV2) -> void:
	scr = screen


# ---------------------------------------------------------------- 선택 미리보기 띠 (U1)

func _set_preview(where: String, gain: String, risk: String) -> void:
	if scr._pv_labels.size() < 3:
		return
	var vals := [where, gain, risk]
	for i in 3:
		var l: Label = scr._pv_labels[i]
		l.text = vals[i] if vals[i] != "" else "—"
		l.tooltip_text = vals[i]
		l.add_theme_color_override("font_color", Style.INK_3 if vals[i] == "" else (Style.SEAL_DARK if i == 2 else Style.INK))


func _my_turn() -> bool:
	return scr.game.phase == "turn" and scr.game.current == scr.human


func preview_idle() -> void:
	## 아무것도 가리키지 않을 때: 지금 내 상황
	if scr._pv_box == null:
		return
	scr._pv_box.visible = scr.game.phase != "over"
	if not scr._pv_box.visible:
		return
	var me: Dictionary = scr.game.players[scr.human]
	var risk := ""
	if scr.game.police.has(scr.human):
		risk = "경찰이 %d칸 뒤에서 쫓는 중 (차례 끝에 %d칸 다가옴)" % [scr.game.walk_dist(me["pos"], scr.game.police[scr.human]["pos"]), scr.game.police_speed()]
	elif me["jailed"]:
		risk = "감옥 — 탈옥 판정 또는 동료의 구출"
	if scr.game.phase == "plan":
		_set_preview("주사위를 이동 · 판정 중 어디에 쓸지", "큰 눈은 멀리 · 판정은 큰 눈이 유리", risk)
	elif not _my_turn():
		# 동료 차례 · 낮 순서 · 선택: 누가 무엇을 하는지와 내 다음 차례
		var who := ""
		if scr.game.phase == "turn" and scr.game.current >= 0:
			who = "%s의 차례" % scr._text.name(scr.game.current)
		elif scr.game.phase == "choice":
			who = "%s가 고르는 중" % scr._text.name(int(scr.game.pending.get("player", -1)))
		else:
			who = "낮 · 차례 순서 정하기"
		var mine := scr.game.my_dice(scr.human).map(func(i): return str(scr.game.die_value(i)))
		var next := "내 주사위 %s — 내 차례에 씀" % " · ".join(mine) if not mine.is_empty() and not me["done_today"] else ("오늘 내 차례는 끝" if me["done_today"] else "칸을 가리키면 그 칸의 정보")
		_set_preview(who, next, risk)
	elif scr.game.steps_left > 0:
		_set_preview("걷는 중: %d칸 남음" % scr.game.steps_left, "칸을 가리키면 그 칸의 보상", risk)
	else:
		_set_preview("주사위 %d개 남음 — 주사위를 가리켜 보세요" % scr.game.my_dice(scr.human).size(), "칸 · 주사위를 가리키면 여기에", risk)


func _cell_gain_risk(c: Vector2i) -> Array:
	## 칸 하나의 [이름, 얻는 것, 위험]
	var me: Dictionary = scr.game.players[scr.human]
	var gain := []
	var risk := []
	var name := "덮인 칸"
	if not scr.game.board.has(c):
		risk.append("무엇이 나올지 모름")
	else:
		var t := scr.game.tile_type(c)
		name = scr.game.tile_label(t)
		var bi := scr.game.data.bases.find(c)
		if bi >= 0:
			name = scr.game.data.base_names[bi]
			var bid: String = scr.game.data.base_ids[bi]
			for id in scr.game.mission_row:
				var cond := scr.game.card_cond(str(id))
				if str(cond.get("kind", "")) == "infiltrate" and str(cond.get("base", "")) == bid:
					gain.append("잠입: " + str(scr.game.card_def(str(id)).get("name", "")))
			for q in scr.game.players:
				if q["jailed"] and q["pos"] == c and q["id"] != scr.human:
					gain.append("%s 구출" % scr._text.name(int(q["id"])))
			if scr.game.act == 1:
				risk.append("들어가면 경찰이 붙음 (3칸 떨어져)")
		elif not scr.game.board[c].get("used", false):
			var fx: Dictionary = scr.game.data.rules.get("tile_effects", {}).get(t, {})
			if fx.has("text") and t != "check":
				gain.append(str(fx["text"]).split(".")[0].split(" (")[0])
		if t == "check":
			risk.append("검문: 회피 %d 이상, 실패하면 경찰" % scr.game.check_target("evade"))
	for m in scr.game.markers_at(c):
		var id := str(m["id"])
		if scr.game.data.is_op(id):
			gain.append("일제 작전 막기: " + str(scr.game.card_def(id).get("name", "")))
		else:
			gain.append("%s — %s" % [scr.game.card_def(id).get("name", ""), scr.game.card_def(id).get("text", "")])
	for pid in scr.game.police:
		if pid != scr.human and scr.game.walk_dist(c, scr.game.police[pid]["pos"]) <= 1:
			risk.append("경찰 곁")
			break
	if scr.game.police.has(scr.human):
		risk.append("나를 쫓는 경찰까지 %d칸" % scr.game.walk_dist(c, scr.game.police[scr.human]["pos"]))
	return [name, " · ".join(gain), " · ".join(risk)]


func preview_cell(c: Vector2i) -> void:
	if c.x < 0 or scr.game.phase == "over":
		preview_idle()
		return
	if not _my_turn():
		var inf := _cell_gain_risk(c)
		_set_preview(inf[0], inf[1], inf[2])
		return
	var info := _cell_gain_risk(c)
	var where: String = info[0]
	var me: Dictionary = scr.game.players[scr.human]
	if scr.game.steps_left > 0:
		var pth := scr.game.path_to(me, c)
		if not pth.is_empty() and pth["reachable"]:
			where += " · %d걸음" % (pth["path"] as Array).size()
		elif c != me["pos"]:
			where += " · 이번엔 못 감"
	elif scr._board.reach.has(c):
		where += " · %d걸음" % int(scr._board.reach[c])
	_set_preview(where, info[1], info[2])


func preview_action(a: Dictionary) -> void:
	## 주사위 · 행동 단추를 가리켰을 때
	if not _my_turn():
		return
	var me: Dictionary = scr.game.players[scr.human]
	match a["type"]:
		"move_die":
			var n := scr.game.move_value(me, int(a["die"]))
			var cells := scr.game.reach_cells(me, n)
			var gains := []
			var checks := 0
			for c in cells:
				for m in scr.game.markers_at(c):
					var nm := str(scr.game.card_def(str(m["id"])).get("name", ""))
					if not nm in gains:
						gains.append(nm)
				if scr.game.tile_type(c) == "check":
					checks += 1
			var risk := []
			if checks > 0:
				risk.append("검문소 %d곳 (회피 %d)" % [checks, scr.game.check_target("evade")])
			if scr.game.police.has(scr.human):
				risk.append("경찰 %d칸 뒤 · 차례 끝에 %d칸" % [scr.game.walk_dist(me["pos"], scr.game.police[scr.human]["pos"]), scr.game.police_speed()])
			_set_preview("최대 %d칸 · 닿는 칸 %d곳" % [n, cells.size()], ("닿는 마커: " + ", ".join(gains)) if not gains.is_empty() else "닿는 곳에 미션 마커 없음", " · ".join(risk))
		"escape", "mission_check", "counter_check", "scene_check":
			var info := _cell_gain_risk(me["pos"])
			var fail: String = {"escape": "실패해도 다른 주사위로 또", "mission_check": "실패하면 회피 7, 그것도 실패하면 투옥", "counter_check": "실패해도 다른 주사위로 또", "scene_check": "실패해도 다른 주사위로 또"}[a["type"]]
			_set_preview("제자리 판정 · 성공 %d%%" % scr._text.chance(a), info[1] if a["type"] == "mission_check" else scr._actions.hint(a).split(" → ")[0], fail)
		_:
			_set_preview(scr._text.label(a), scr._actions.hint(a), "")


func work_preview(a: Dictionary) -> String:
	var me: Dictionary = scr.game.players[scr.human]
	var m := scr.game.marker_at(me["pos"])
	if m.is_empty():
		return ""
	var id := str(m["id"])
	var st: Dictionary = scr.game.mission_state.get(id, {})
	var cond := scr.game.card_cond(id)
	var v := scr.game.die_value(int(a["die"]))
	match str(cond.get("mode", "")):
		"sum":
			var now := int(st.get("sum", 0)) + v
			return "합 %d → %d / %d%s" % [int(st.get("sum", 0)), now, int(st.get("need", 0)), " (이룸!)" if now >= int(st.get("need", 0)) else ""]
		"combo":
			var left: Array = st.get("left", []).duplicate()
			left.erase(v)
			return "남은 눈 %s → %s%s" % ["·".join(st.get("left", []).map(func(x): return str(x))), "·".join(left.map(func(x): return str(x))) if not left.is_empty() else "없음", " (이룸!)" if left.is_empty() else ""]
		"each":
			var rest := scr.game.markers_of(id, "work").size() - 1
			return "마커 %d곳 남음%s" % [rest, " (이룸!)" if rest <= 0 else ""]
	return ""
