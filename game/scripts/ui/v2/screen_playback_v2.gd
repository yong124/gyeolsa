class_name ScreenPlaybackV2
extends RefCounted
## 이벤트 연출 재생: 엔진이 낸 이벤트 하나를 말 움직임 · 배너 · 컷신 · 효과음으로 보여 준다. 빠르기 · 연출 설정 · 기다림 측정.
## 상태는 화면(GameScreenV2)에 두고, 이 파일은 화면을 scr로 받아 그 일만 한다 (지시서 Z4).

var scr: GameScreenV2   # 이 모듈이 맡은 화면
var _last_exposure := -1          # 노출이 오를 때만 붉은 비네트
var _banner_seen := {}            # U4: 같은 배너가 몇 번 나왔나 (세 번 넘으면 기록 띠로만)
var _cine_seen := {}              # U4: 컷신 종류별 본 횟수 (설정 「연출: 처음만」)


func _init(screen: GameScreenV2) -> void:
	scr = screen


func mult() -> float:
	if scr._fast:
		return 0.35
	if scr.game != null and scr.game.current >= 0 and scr.game.current != scr.human and scr.game.phase in ["turn", "choice"]:
		return maxf(0.05, float(Prefs.SPEEDS[Prefs.speed]["mult"]))   # 동료 차례: 설정의 빠르기 (즉시 = 거의 0)
	return 1.0


func _cine_ok(kind: String, m: float) -> bool:
	## 이 컷신을 크게 보여 줄까 (설정 「연출」: 0 전부 · 1 처음만 · 2 줄임). 아니면 배너 · 알림으로 대신한다
	var n := int(_cine_seen.get(kind, 0))
	_cine_seen[kind] = n + 1
	if m < 0.1:
		return false
	match Prefs.v2_cine:
		1:
			return n == 0
		2:
			return false
	return true


func cutin(pid: int, m: float, line := "") -> void:
	## 캐릭터 컷인: 초상 + 이름 + 대사(없으면 능력 이름). 내 요원은 왼쪽에서, 동료는 오른쪽에서
	var p: Dictionary = scr.game.players[pid]
	var ch: Dictionary = scr.game.char_def(p)
	if line == "":
		line = str(ch.get("quote", ch.get("ability_text", "")))
	await scr._cine.cutin(ArtV2.get_tex("char", str(p["character"])), str(ch.get("name", "")), line, Style.seat(pid), m, pid == scr.human)


func write_waits() -> void:
	## U4: 사람 판(자동 · 원격 제외)이 끝나면 기다린 시간을 남긴다 (user://playtests/v2_waits_*.json)
	if scr._auto or not Prefs.playtest:
		return
	var out := scr.wait_stats.duplicate()
	out.erase("_ai_steps")
	var rec := {"time": Time.get_datetime_string_from_system(), "days": scr.game.day, "ending": str(scr.game.ending.get("id", "")),
		"training": scr._training, "online": scr._remote != null, "cine": Prefs.v2_cine, "speed": Prefs.speed, "seconds": out}
	DirAccess.make_dir_recursive_absolute("user://playtests")
	var f := FileAccess.open("user://playtests/v2_waits_%d.json" % int(Time.get_unix_time_from_system()), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rec, "	"))


func event_cat(kind: String) -> String:
	if kind in ["jail", "scene", "scene_break", "launch", "op_appear", "saga_done", "card", "dice", "over"]:
		return "컷신"
	if kind in ["banner", "morning", "threat"]:
		return "배너"
	return "말 움직임"


# ================================================================ 연출

func play_event(e: Dictionary) -> void:
	var m := mult()
	var k: String = e["kind"]
	match k:
		"move":
			scr._board.note_arrived(e["to"])
			scr._board.note_footprint(e["from"], int(e["player"]))
			Sfx.play("step", 0.1, 0.5)
			await scr._board.animate_move(int(e["player"]), e["from"], e["to"], 0.13 * m)
		"reveal":
			if bool(e.get("scouted", false)):
				scr._board.note_scouted(e["pos"])
			Sfx.play("flip", 0.1, 0.6)
			scr._fx.paper_burst(scr._cell_screen(e["pos"]), m * 0.6)
			await scr._board.reveal(e["pos"], 0.22 * m)
		"police":
			if scr._board.police_changed(e["police_snap"]):
				await scr._board.animate_police(e["police_snap"], 0.28 * m)
		"dice":
			if int(e.get("player", -1)) >= 0 and (int(e.get("target", 0)) >= 10 or (scr.game.act == 2 and scr.game.scene_index == scr.game.scenes.size() - 1)):
				await cutin(int(e["player"]), m)
			await scr._fx.roll_dice(e, m)
			scr._cine.ink(scr._fx.focus_center, bool(e.get("ok", false)), m)
		"banner":
			var bt := str(e["text"])
			_banner_seen[bt] = int(_banner_seen.get(bt, 0)) + 1
			if int(_banner_seen[bt]) <= 3 or int(e.get("player", -1)) == scr.human:
				await scr._fx.banner(bt, str(e["tone"]), m)   # 넷째부터(동료 일)는 기록 띠로만
		"morning":
			Sfx.play("day")
			await scr._fx.banner("%d일째 아침" % int(e["day"]), "info", m, "리더: %s · 남은 날 %d" % [scr._text.name(int(e["leader"])), scr.game.rounds_left])
		"threat":
			var t: Dictionary = scr.game.data.threat(str(e["id"]))
			Sfx.play("alert")
			await scr._fx.banner("일제 위협 · " + str(t.get("name", "")), "bad" if t.get("tone", "bad") == "bad" else "info", m, str(t.get("text", "")))
		"jail":
			await scr._board.animate_move(int(e["player"]), e["from"], e["to"], 0.25 * m)
			scr._cine.shake(scr._board_node(), 7.0, 0.3 * m)
			if int(e["player"]) == scr.human:
				Sfx.play("whistle")
				Sfx.play("clang")
				var jp: Dictionary = scr.game.players[scr.human]
				if _cine_ok("jail", m):
					await scr._cine.cut({"tex": ArtV2.get_tex("cut", "jail", ArtV2.get_tex("threat", "prison")), "title": "투옥 · " + scr.game.base_name(scr.game.data.bases.find(jp["pos"])) + " 감옥",
						"sub": "탈옥 판정을 하거나 동료가 구하러 올 때까지 기다린다", "stamp": "투 옥", "hold": 1.4}, m)
				else:
					await scr._fx.banner("투옥 · " + scr.game.base_name(scr.game.data.bases.find(jp["pos"])) + " 감옥", "bad", m)
		"mission_done":
			if int(e.get("player", -1)) == scr.human:
				scr._coach.task_done("mission")
			Sfx.play("score")
			var mc: Control = scr._mission_cards.get(str(e["id"]), null)
			if mc != null and is_instance_valid(mc):
				var at := mc.get_global_rect().get_center() - scr.global_position
				scr._fx.paper_burst(at, m)
				scr._fx.stamp_at(at, "성 공", Style.GOOD, m)
			if str(scr.game.mission_def(str(e["id"])).get("type", "")) == "bomb":
				scr._cine.shake(scr._board_node(), 9.0, 0.35 * m)
			scr._fx.toast("미션 성공 · %s (%s)" % [scr.game.mission_def(str(e["id"])).get("name", ""), scr._text.name(int(e["player"]))], "good")
		"saga_done":
			Sfx.play("success")
			await cutin(int(e["player"]), m, "사연 「%s」을(를) 이루다" % scr.game.data.saga(str(e["id"])).get("name", ""))
			scr._fx.toast("사연을 이룸 · %s — %s" % [scr._text.name(int(e["player"])), scr.game.data.saga(str(e["id"])).get("name", "")], "good")
		"scene":
			var card: Dictionary = scr.game.current_scene()
			var stex := ArtV2.get_tex("scene", str(e.get("id", "")))
			if stex != null and _cine_ok("scene", m):
				await scr._cine.cut({"tex": stex, "title": "장면 %d/%d · %s" % [int(e["index"]) + 1, scr.game.scenes.size(), card.get("name", "")],
					"sub": scr._text.cond_text(card.get("condition", {}), card), "hold": 1.5}, m)
			else:
				await scr._fx.banner("장면 %d/%d · %s" % [int(e["index"]) + 1, scr.game.scenes.size(), card.get("name", "")], "info", m, scr._text.cond_text(card.get("condition", {}), card))
		"scene_break":
			Sfx.play("success")
			var bcard := scr._text.scene_card_dict(str(e.get("id", "")))
			if not _cine_ok("scene_break", m):
				await scr._fx.banner(str(bcard.get("name", "")) + " 돌파", "good", m)
			else:
				await scr._cine.cut({"tex": ArtV2.get_tex("scene", str(e.get("id", ""))), "title": str(bcard.get("name", "")) + " 돌파",
					"stamp": "돌 파", "stamp_color": Style.GOOD, "hold": 0.9}, m)
		"launch":
			Music.play("tension")
			var st: Dictionary = scr.game.data.strike(str(e.get("target", "")))
			var faces := []
			for q in scr.game.players:
				var ft := ArtV2.get_tex("char", str(q["character"]))
				if ft != null:
					faces.append(ft)
			await scr._cine.cut({"tex": ArtV2.get_tex("strike", str(e.get("target", ""))), "title": "결행 · " + str(st.get("name", "")),
				"sub": "오늘 밤, 들이친다", "portraits": faces, "stamp": "결 행", "hold": 2.2}, m)
			await scr._cine.ink_wipe(m)
		"op_appear":
			Sfx.play("alert")
			var oc: Dictionary = scr.game.data.op_card(str(e["id"]))
			var osub := "%s\n막는 법: %s · 기한 %d일 · %s" % [oc.get("where", ""), oc.get("how", ""), int(oc.get("deadline", 0)), oc.get("missed_text", "")]
			var otex := ArtV2.get_tex("op", str(e["id"]))
			if otex != null and _cine_ok("op", m):
				scr._cine.vignette(Style.SEAL, 0.5, 0.9 * m)
				await scr._cine.cut({"tex": otex, "title": "일제 작전 · " + str(oc.get("name", "")), "sub": osub, "hold": 1.6}, m)
			else:
				await scr._fx.banner("일제 작전 · " + str(oc.get("name", "")), "bad", m, osub)
		"op_blocked":
			Sfx.play("success")
			scr._fx.toast("일제 작전 저지 · %s (%s)" % [scr.game.data.op_card(str(e["id"])).get("name", ""), scr._text.name(int(e["player"]))], "good")
		"op_missed", "mission_missed":
			Sfx.play("fail")
		"ready":
			# 결행 준비 칸이 찰 때: 위쪽 띠의 준비 칸에서 불꽃
			var g: Control = scr._top._gauge
			if g != null and is_instance_valid(g):
				var at := g.get_global_rect().get_center() - scr.global_position
				scr._fx.paper_burst(at, m)
				scr._fx.paper_burst(at + Vector2(0, 6), m)
				Sfx.play("spark")
		"exposure":
			if _last_exposure >= 0 and int(e["value"]) > _last_exposure:
				scr._cine.vignette(Style.SEAL, 0.55, 1.1 * m)
			_last_exposure = int(e["value"])
		"marker_moved":
			scr._board.note_marker_moved(str(e["id"]), e["from"], e["to"])
		"informed":
			Sfx.play("click")
			scr._fx.toast("정보원 · %s의 표적이 멈췄습니다 (판정이 쉬워짐)" % scr.game.card_def(str(e["id"])).get("name", ""), "good")
		"pickup":
			Sfx.play("click")
			scr._fx.toast("%s: 물건을 들었습니다 · %s" % [scr._text.name(int(e["player"])), scr.game.card_def(str(e["id"])).get("name", "")], "info")
		"item_lost":
			Sfx.play("fail")
			scr._fx.toast("%s: 잡혀서 물건이 받기 마커로 돌아갔습니다" % scr._text.name(int(e["player"])), "bad")
		"work_give":
			Sfx.play("click")
		"tile_fx":
			Sfx.play("click")
		"funds":
			if int(e.get("change", 0)) != 0:
				Sfx.play("score" if int(e["change"]) > 0 else "fail")
				scr._fx.toast("군자금 %+d (지금 %d)" % [int(e["change"]), int(e["value"])], "good" if int(e["change"]) > 0 else "bad")
				if int(e["change"]) <= -2 and str(e.get("why", "")) in ["lose", "cap"]:
					await scr._fx.banner("군자금 %d을 잃었다" % -int(e["change"]), "bad", m, "지금 군자금 %d" % int(e["value"]))
		"trend":
			Sfx.play("alert")
			var pen := scr.game._trend_penalty()
			scr._fx.toast("일제 동향 %d / %d — 못 막으면 추가 벌칙: %s" % [int(e["value"]), int(scr.game.data.rules["ops"]["trend_max"]), scr._text.fx_text(pen)], "bad")
		"market_buy":
			Sfx.play("click")
		"bribe":
			Sfx.play("click")
		"vote_reveal":
			Sfx.play("click")
			var yes := 0
			for pid in e["votes"]:
				yes += 1 if e["votes"][pid] else 0
			var tally := {}
			for pid in e["targets"]:
				tally[e["targets"][pid]] = int(tally.get(e["targets"][pid], 0)) + 1
			var tparts := []
			for id in tally:
				tparts.append("%s %d표" % [scr.game.base_name(scr.game.data.base_index(str(id))), int(tally[id])])
			var who := []
			for pid in e["targets"]:
				who.append("%s → %s%s" % [scr._text.name(int(pid)), scr.game.base_name(scr.game.data.base_index(str(e["targets"][pid]))),
					"" if e["forced"] else (" (찬성)" if e["votes"].get(pid, false) else " (반대)")])
			await scr._fx.banner("강제 결행 · 대상 투표" if e["forced"] else "결행 투표 공개", "info", m,
				"%s%s\n%s" % ["" if e["forced"] else "찬성 %d · 반대 %d · " % [yes, e["votes"].size() - yes], ", ".join(tparts), " · ".join(who)])
		"counter":
			Sfx.play("alert")
			await scr._fx.banner("반격!", "bad", m, "오늘 이 장면 자리에서 작전 판정 %d에 성공해야 합니다" % int(scr.game.data.rules["counter"]["target"]))
		"counter_blocked":
			Sfx.play("success")
		"benefit":
			var bn := str(e["id"])
			for b in scr.game.data.rules["launch"]["benefits"]:
				if str(b["id"]) == bn:
					scr._fx.toast("결행 혜택 · %s" % b.get("name", ""), "good")
		"confiscate":
			Sfx.play("fail")
			var lost: Array = e["items"].map(func(id): return str(scr.game.item_def(str(id)).get("name", "")))
			scr._fx.toast("%s: 투옥되어 아이템 압수 · %s" % [scr._text.name(int(e["player"])), ", ".join(lost)], "bad")
		"card":
			if str(e.get("deck", "")) == "item" and int(e.get("player", -1)) == scr.human and str(e.get("id", "")) != "bomb":
				scr._fx.toast("아이템 획득 · %s" % scr.game.item_def(str(e["id"])).get("name", ""), "info")
				scr._fx.fly_card(scr._fx.focus_center, scr._hand_row.get_global_rect().get_center() - scr.global_position, str(scr.game.item_def(str(e["id"])).get("name", "")), 0.5 * m)
			elif str(e.get("deck", "")) == "event":
				var ev: Dictionary = scr.game.data.event(str(e["id"]))
				scr._fx.toast("이벤트 · %s — %s" % [ev.get("name", ""), ev.get("text", "")], "info")
				if int(e.get("player", -1)) == scr.human and _cine_ok("event", m):
					await scr._cine.cut({"tex": ArtV2.get_tex("event", str(e["id"])), "title": "이벤트 · " + str(ev.get("name", "")), "sub": str(ev.get("text", "")), "hold": 1.2}, m)
		"dice_rolled":
			Sfx.play("dice", 0.1, 0.6)
		"die_given":
			if int(e["target"]) == scr.human:
				scr._fx.toast("%s이(가) 주사위 %d을(를) 건넸습니다" % [scr._text.name(int(e["player"])), int(e["value"])], "good")
	if e.has("players_snap"):
		scr._board.apply_players_snap(e["players_snap"])
	if k in ["morning", "threat", "dice_rolled", "die_used", "die_given", "day_start", "mission_done", "launch", "scene", "scene_break", "confiscate",
			"saga_done", "jail", "rescue", "intel", "ready", "exposure", "turn", "night", "markers", "trend", "op_appear", "op_blocked", "op_missed",
			"mission_missed", "pickup", "item_lost", "work_give", "lurk", "informed", "marker_moved", "funds", "market_buy", "bribe"]:
		scr._refresh_panels()
	scr._ticker.refresh()
