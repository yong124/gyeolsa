class_name ScreenTextV2
extends RefCounted
## 화면 문장: 요원 이름 · 조건 · 행동 이름 · 카드 설명(큰 카드 미리보기용 사전). 판 상태를 읽기만 한다.
## 상태는 화면(GameScreenV2)에 두고, 이 파일은 화면을 scr로 받아 그 일만 한다 (지시서 Z4).

var scr: GameScreenV2   # 이 모듈이 맡은 화면


func _init(screen: GameScreenV2) -> void:
	scr = screen


func grant_text(g: Dictionary) -> Array:
	## 한 번 쓰는 권리 [짧은 이름, 설명]
	var scope: String = {"strike": " (결행 장면 판정에서만)", "final": " (마지막 장면 판정에서만)"}.get(str(g.get("scope", "any")), "")
	match str(g.get("kind", "")):
		"check_bonus": return ["판정 +%d" % int(g.get("value", 0)), "다음 판정에 +%d%s" % [int(g.get("value", 0)), scope]]
		"reroll": return ["다시 굴리기", "실패한 판정을 한 번 다시 굴림%s" % scope]
		"evade_auto": return ["회피 자동 성공", "다음 회피 판정이 자동으로 성공"]
		"escape_instant": return ["즉시 탈옥", "갇히면 바로 탈출"]
	return [str(g.get("kind", "")), str(g.get("kind", ""))]


func scene_kind(i: int) -> String:
	## 장면 줄의 종류 이름: 진입 → 중간 → 경비 강화 → 마지막
	if i == 0:
		return "진입"
	if i == scr.game.scenes.size() - 1:
		return "마지막"
	for c in scr.game.data.scenes.get("reinforce", []):
		if c.get("id", "") == str(scr.game.scenes[i]):
			return "경비 강화"
	return "중간"


func scene_card_dict(id: String) -> Dictionary:
	var strike: Dictionary = scr.game.data.strike(str(scr.game.launch_info.get("target", "")))
	for c in [strike.get("entry", {}), strike.get("final", {})] + strike.get("middle", []) + scr.game.data.scenes.get("reinforce", []):
		if c.get("id", "") == id:
			return c
	return {}


func spaced(s: String) -> String:
	## "잠입" → "잠 입" (v1 카드 띠 글자 모양)
	if s.length() > 4:
		return s
	return " ".join(Array(s.split("")))


# ================================================================ 문장

func name(pid: int) -> String:
	return TextV2.agent_full(scr.game, pid)


func _where_text(w: String) -> String:
	if w in scr.game.data.base_ids:
		return "거점 안"
	return {"inside": "거점 안", "adjacent": "거점 옆 칸", "inside_or_adjacent": "거점 안이나 옆 칸"}.get(w, w)


func cond_text(c: Dictionary, card := {}) -> String:
	## 장면 조건을 문장으로 (데이터의 kind만 보고 만든다)
	var where := _where_text(str(c.get("where", card.get("where", "inside"))))
	match str(c.get("kind", "")):
		"check":
			var nm: String = {"generic": "판정", "lock": "자물쇠 판정", "assassin": "암살 판정", "evade": "회피 판정"}.get(str(c.get("check", "")), "판정")
			return "%s에서 %s %d 이상" % [where, nm, int(c.get("target", scr.game.data.rules["checks"].get(str(c.get("check", "")), 9)))]
		"check_pair":
			return "서로 다른 %d명이 같은 날 %s에서 각각 작전 판정 %d 이상" % [int(c.get("count", 2)), where, int(c.get("target", 7))]
		"dice":
			return "%s에서 아침 주사위 합 %d 이상을 바침" % [where, int(c.get("sum", 0))]
		"pay_item":
			return "%s에서 아이템 %d장을 바침" % [where, int(c.get("count", 1))]
		"pay_bomb":
			return "%s에서 폭탄 %d개를 바침%s" % [where, int(c.get("count", 1)), " (나눠 바쳐도 됨)" if c.get("split", false) else ""]
		"people":
			return "%d명이 같은 날 %s에서 차례를 마침" % [int(c.get("count", 2)), where]
		"pay_funds":
			return "%s에서 군자금 %d을 내고 매수 (마지막 장면은 매수할 수 없음)" % [where, int(c.get("count", 1))]
		"hold":
			return "%d명이 %s에서 %d밤을 넘김" % [int(c.get("count", 1)), where, int(c.get("days", 1))]
		"jailed_here":
			return "결행 거점 감옥에 요원이 갇혀 있음"
		"sequence":
			var steps := []
			for i in c.get("steps", []).size():
				steps.append("%d단계 %s" % [i + 1, cond_text(c["steps"][i], card)])
			return " → ".join(steps)
		"any_of":
			var parts := []
			for o in c.get("options", []):
				parts.append(cond_text(o, card))
			return " 또는 ".join(parts)
		"all_of":
			var parts2 := []
			for o in c.get("options", []):
				parts2.append(cond_text(o, card))
			return " 그리고 ".join(parts2)
	return str(c.get("kind", ""))


func funds_price() -> int:
	## 지금 장면의 매수 값 (군자금)
	for leaf in scr.game._scene_leaves(scr.game.current_scene().get("condition", {})):
		if str(leaf["cond"].get("kind", "")) == "pay_funds":
			return int(leaf["cond"].get("count", 0))
	return 0


func chance(a: Dictionary) -> int:
	## 작전 판정 행동의 성공 확률 (%)
	var c: Dictionary = scr.game.check_preview(scr.game.players[scr.human], a)
	return roundi(scr.game.check_chance(c, scr.game.die_value(int(a["die"]))) * 100.0)


func label(a: Dictionary) -> String:
	var me: Dictionary = scr.game.players[scr.human]
	match a["type"]:
		"start_day": return "하루 시작"
		"begin_turn": return "내 차례 시작"
		"end_move": return "이동 마치기"
		"end_turn": return "차례 마치기"
		"escape": return "탈옥 판정 (주사위 %d · 성공 %d%%)" % [scr.game.die_value(int(a["die"])), chance(a)]
		"mission_check": return "표적 판정 (주사위 %d · 성공 %d%%)" % [scr.game.die_value(int(a["die"])), chance(a)]
		"work_give":
			var wm := scr.game.marker_at(me["pos"])
			return "공작 바치기: 주사위 %d → 「%s」" % [scr.game.die_value(int(a["die"])), scr.game.card_def(str(wm.get("id", ""))).get("name", "")]
		"counter_check": return "반격 막기 (주사위 %d · 성공 %d%%)" % [scr.game.die_value(int(a["die"])), chance(a)]
		"hide": return "숨기 (주사위 %d)" % scr.game.die_value(int(a["die"]))
		"scout": return "정찰 (주사위 %d: %d칸 안의 덮인 칸 %d곳)" % [scr.game.die_value(int(a["die"])), scr.game.die_value(int(a["die"])), int(scr.game.data.rules["scout"]["count"])]
		"market":
			var offer := {}
			for o in scr.game.data.rules["market"]["offers"]:
				if str(o["id"]) == str(a["offer"]):
					offer = o
			return "장터: %s 사기 (군자금 %d · 주사위 %d)" % [offer.get("name", ""), scr.game.market_cost(me, offer), scr.game.die_value(int(a["die"]))]
		"use_item":
			return "[%s] 사용" % scr.game.item_def(str(me["items"][int(a["index"])])).get("name", "")
		"ability":
			var ab := scr.game.ability_def(me)
			if a.has("target"):
				return "능력 「%s」 → %s" % [ab.get("name", ""), name(int(a["target"]))]
			if a.has("die"):
				return "능력 「%s」 (주사위 %d를 냄)" % [ab.get("name", ""), scr.game.die_value(int(a["die"]))]
			return "능력 「%s」" % ab.get("name", "")
		"give_item":
			return "[%s] → %s 건네기 (주사위 %d)" % [scr.game.item_def(str(me["items"][int(a["index"])])).get("name", ""), name(int(a["to"])), scr.game.die_value(int(a["die"]))]
		"decoy":
			return "미끼: %s의 경찰을 내 쪽으로 (주사위 %d)" % [name(int(a["from"])), scr.game.die_value(int(a["die"]))]
		"move_die":
			var mv := scr.game.move_value(me, int(a["die"]))
			return "주사위 %d로 이동 (+%d칸)" % [scr.game.die_value(int(a["die"])), mv]
		"give_die":
			return "주사위 %d → %s에게 건네기" % [scr.game.die_value(int(a["die"])), name(int(a["target"]))]
		"scene_check":
			return "장면 판정 (주사위 %d · 성공 %d%%)" % [scr.game.die_value(int(a["die"])), chance(a)]
		"scene_pay":
			match a["what"]:
				"die": return "주사위 %d 장면에 바치기" % scr.game.die_value(int(a["die"]))
				"item": return "[%s] 바치기 (주사위 %d를 냄)" % [scr.game.item_def(str(me["items"][int(a["index"])])).get("name", ""), scr.game.die_value(int(a["with"]))]
				"bomb": return "폭탄 바치기 (주사위 %d를 냄)" % scr.game.die_value(int(a["with"]))
				"funds": return "장면 매수 (군자금 %d · 주사위 %d를 냄)" % [funds_price(), scr.game.die_value(int(a["with"]))]
		"use_intel":
			return "첩보 토큰: 판정 +%d" % int(scr.game.data.rules["intel_token"]["check_bonus"]) if a["mode"] == "check" \
				else "첩보 토큰: 주사위 조건 −%d" % int(scr.game.data.rules["intel_token"]["dice_reduce"])
	return str(a["type"])


# ================================================================ 큰 카드 (마우스 올림)

func char_info(p: Dictionary) -> Dictionary:
	var ch: Dictionary = scr.game.char_def(p)
	var fac: String = str(scr.game.data.characters.get("factions", {}).get(ch.get("faction", ""), {}).get("name", ""))
	var secs := [["특성 (늘)", str(ch.get("trait_text", ""))], ["능력 (하루 1번)", str(ch.get("ability_text", ""))]]
	for c in scr._chips(p):
		if c[0] == "리더" or c[0] == "추격당함" or str(c[0]).begins_with("감옥"):
			secs.append([str(c[0]), str(c[3]), Style.SEAL if c[2] == Style.SEAL else Style.INK_3])
	var band := "나" if p["id"] == scr.human else "동 료"
	return {"band": band, "color": Style.seat(p["id"]),
		"art": scr._board.faction_texture(str(ch.get("faction", ""))), "illus": ArtV2.get_tex("char", str(p["character"])), "name": str(ch.get("name", "")),
		"sub": "%s · %s" % [fac, ch.get("origin", "")], "sections": secs}


func mission_info(id: String) -> Dictionary:
	var m: Dictionary = scr.game.mission_def(id)
	var type := str(m.get("type", ""))
	var td: Dictionary = scr.game.mission_type_def(type)
	var coop := type == "coop"
	var secs := [["이루는 법", str(m.get("how", ""))], ["자리", str(m.get("where", ""))]]
	var b = m.get("bonus")
	if typeof(b) == TYPE_DICTIONARY:
		secs.append(["보너스", str(b.get("text", "")), Style.GOOD])
	var days := scr.game.card_days_left(id)
	if days >= 0:
		secs.append(["기한", "남은 %d일 · %s" % [days, m.get("missed_text", "")], Style.SEAL])
	var status := scr.game.card_status(id)
	if status != "":
		secs.append(["진행", status, Style.GOOD])
	secs.append(["보상", str(m.get("text", ""))])
	if coop:
		secs.append(["협동 미션", "두 명이 함께 채웁니다. 결행 준비 +%d" % int(m.get("ready", 0))])
	else:
		secs.append(["결행 준비", "+%d · 결행 준비가 %d가 되면 아침마다 결행 투표가 열립니다." % [int(m.get("ready", 0)), int(scr.game.data.rules["launch_min"])]])
	if bool(m.get("loud", td.get("loud", false))):
		secs.append(["시끄러움", "이루면 노출 +1, 경찰이 붙습니다.", Style.SEAL])
	return {"band": "미 션 · " + str(td.get("name", "")), "color": Color("#2f7f7a") if coop else Style.MISSION,
		"art": scr._mission_art(type), "illus": ArtV2.get_tex("mission", type), "name": str(m.get("name", "")), "sections": secs}


func fx_text(effects: Array) -> String:
	var parts := []
	for e in effects:
		match str(e.get("op", "")):
			"exposure": parts.append("노출 %+d" % int(e["value"]))
			"police_dispatch": parts.append("가까운 거점에서 경찰이 출동해 가장 가까운 요원을 쫓음")
			"ready": parts.append("결행 준비 %+d" % int(e["value"]))
	return ", ".join(parts) if not parts.is_empty() else "없음"


func op_info(id: String) -> Dictionary:
	var oc: Dictionary = scr.game.data.op_card(id)
	var secs := [["막는 법", str(oc.get("how", ""))], ["자리", str(oc.get("where", ""))],
		["기한", "남은 %d일 · %s" % [scr.game.card_days_left(id), oc.get("missed_text", "")], Style.SEAL],
		["지금 동향 %d의 추가 벌칙" % scr.game.trend, fx_text(scr.game._trend_penalty()), Style.SEAL],
		["막으면", "노출 −1 (동향은 내려가지 않음)", Style.GOOD]]
	var status := scr.game.card_status(id)
	if status != "":
		secs.append(["진행", status, Style.GOOD])
	return {"band": "일 제 작 전", "color": Style.SEAL, "art": ArtV2.get_tex("op", id, load(str(scr._ui()["mission_art"]["op"]))), "illus": ArtV2.get_tex("op", id), "name": str(oc.get("name", "")), "sections": secs}


func scene_info(card: Dictionary, i: int) -> Dictionary:
	var last := i == scr.game.scenes.size() - 1
	var state := "돌파함"
	if i == scr.game.scene_index:
		state = "지금 장면"
	elif i > scr.game.scene_index:
		state = "마지막 장면" if last else "아직 모르는 장면"
	var sub := "%d / %d · %s" % [i + 1, scr.game.scenes.size(), state]
	if i > scr.game.scene_index and not last:
		return {"band": "결 행 장 면", "color": Style.INK_3, "name": "?", "sub": sub,
			"sections": [["", "앞 장면을 돌파하면 뒤집혀 드러납니다."]]}
	var wh := str(card.get("where", ""))
	var where: String = {"adjacent": "거점 옆 칸", "inside": "거점 안", "inside_or_adjacent": "거점 안이나 옆 칸"}.get(wh, wh)
	var secs := [["조건", cond_text(card.get("condition", {}), card)]]
	if where != "":
		secs.append(["자리", where])
	if i == scr.game.scene_index:
		var need := scr.game.scene_need()
		var parts := []
		for key in need:
			parts.append("%s %d" % [{"dice": "주사위 합", "item": "아이템", "bomb": "폭탄", "check_pair": "판정 성공", "people": "사람", "hold": "밤", "funds": "군자금"}.get(key, key), int(need[key])])
		if not parts.is_empty():
			secs.append(["남은 것", ", ".join(parts), Style.GOOD])
	secs.append(["여기서 멈추면", str(card.get("stop_text", "")), Style.SEAL])
	var col := Style.GOLD
	if last:
		col = Style.SEAL
	elif i < scr.game.scene_index:
		col = Style.MISSION
	return {"band": "결 행 장 면", "color": col, "illus": ArtV2.get_tex("scene", str(card.get("id", ""))), "name": str(card.get("name", "")), "sub": sub, "sections": secs}


func saga_info(id: String, pr: Dictionary, done: bool) -> Dictionary:
	var s: Dictionary = scr.game.data.saga(id)
	return {"band": "사 연 · 이룸" if done else "사 연 · 비밀", "color": GameScreenV2.SAGA_COL, "art": scr._saga_art(), "illus": ArtV2.get_tex("", "saga_back"),
		"name": str(s.get("name", "")), "sub": "진행 %d / %d" % [int(pr["have"]), int(pr["need"])],
		"sections": [["", str(s.get("story", ""))], ["조건", str(s.get("condition_text", ""))], ["보상", str(s.get("reward_text", ""))],
			["", "이룬 사연입니다." if done else "나만 봅니다. 이루면 공개됩니다."]]}


func threat_info() -> Dictionary:
	if scr.game.threat_today == "":
		return {}
	var t: Dictionary = scr.game.data.threat(scr.game.threat_today)
	var secs := [["오늘", str(t.get("text", ""))]]
	var peek := scr.game.threat_preview()
	for k in peek.size():
		var nt: Dictionary = scr.game.data.threat(str(peek[k]))
		secs.append([["내일", "모레", "글피"][mini(k, 2)] + " · " + str(nt.get("name", "")), str(nt.get("text", ""))])
	return {"band": "일 제 위 협", "color": Style.INK, "art": load("res://assets/ui/police.png"), "illus": ArtV2.get_tex("threat", str(t.get("art", ""))), "name": str(t.get("name", "")), "sections": secs}
