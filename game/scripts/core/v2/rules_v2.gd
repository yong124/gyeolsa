class_name RulesV2
extends RulesAct2V2
## 「결사 / 광복 IF」 v2 규칙 엔진.
##
## - 수치·카드·캐릭터는 전부 GameDataV2(data/v2/*.json)에서 읽는다. 카드 id나 캐릭터 id를 코드에 쓰지 않는다.
##   카드 효과는 `op`, 캐릭터·아이템 특성은 `stat` 이름, 미션은 `types[...].condition.kind`로 움직인다.
## - 모든 조작은 apply(action) 한 곳으로. 모든 액션은 "player" 키를 가진다.
##   계획 단계(plan)는 누구나, 낮(turn)은 차례인 요원만, 선택(choice)은 선택을 맡은 요원만 보낼 수 있다.
## - 난수는 전부 rng 하나. 같은 시드 + actions = 같은 판.
## - legal_actions()는 apply가 받아들이는 액션과 정확히 같다.
##
## 낮 (11·12단계): 주사위 1개 = 행동 1개. 차례를 시작하면 「행동 고르기」가 이어지고, end_turn으로 마친다.
##   행동(주사위 하나를 낸다): move_die · mission_check · work_give · escape · scene_check · scene_pay · give_die · hide
##   공짜(주사위 없이): use_item(차례에 1장) · ability(하루 1번, cost "die"인 능력은 주사위를 냄) · use_intel · end_move · end_turn
##
## 액션
##   {"type": "start_day", "player"}                      (plan) 하루 시작 (아침 능력·아이템을 쓴 뒤)
##   {"type": "begin_turn", "player"}                     (day) 내 차례를 시작 (자유 순서, 한 번에 한 요원)
##   {"type": "move_die", "player", "die"}                (turn) 주사위 하나로 그 눈만큼 걷기 시작 (걷는 중에는 다른 행동 못 함)
##   {"type": "step", "player", "to": Vector2i}           (turn) 한 칸 이동 (경찰이 있는 칸은 못 들어감)
##   {"type": "end_move", "player"}                       (turn, 이동 중) 남은 칸을 버리고 멈춤. 멈춘 칸의 효과를 받는다 (같은 칸은 한 차례에 한 번)
##   {"type": "mission_check", "player", "die", "cell"}   (turn) 암살 표적 마커(옆 칸이면 저격수 오)에서 작전 판정: 낸 눈 + 새 주사위
##   {"type": "work_give", "player", "die"}               (turn) 내 칸의 공작 마커에 주사위를 바침 (합 · 눈 조합 · 마커마다 하나)
##   {"type": "escape", "player", "die"}                  (turn, 갇힘) 탈옥 작전 판정
##   {"type": "scene_check", "player", "die"}             (2막 turn) 장면 작전 판정
##   {"type": "scene_pay", "player", "what", "die"?, "index"?, "with"?}  (2막 turn) 장면에 바침 (아이템·폭탄은 with로 주사위 하나를 냄)
##   {"type": "give_die", "player", "die", "target"}      (turn) 같은 칸 동료에게 이 주사위를 줌 (하루 give_per_day번, 차례를 마친 요원 · 갇힌 요원과는 안 됨)
##   {"type": "hide", "player", "die"}                    (turn) 숨기: 이번 차례 끝에 내 경찰이 다가오지 않음 (rules.hide의 칸에서만)
##   {"type": "end_turn", "player"}                       (turn) 차례 마치기: 「차례를 마치면」 효과 → 내 경찰 이동 → 끝
##   {"type": "use_item", "player", "index"}              (plan: 아침 아이템 / turn) 아이템 사용 (차례에 1장)
##   {"type": "ability", "player", "target"?, "die"?}     캐릭터 능력 (하루 1회)
##   {"type": "use_intel", "player", "mode": "check"|"dice"}  (2막 turn) 첩보 토큰 사용
##   {"type": "choose", "player", "value"}                (choice) 선택지 응답
##
## 선택(choice)의 종류에는 saga_keep(결행 순간에 남길 사연, 비밀)도 있다.
## 작전 판정(암살·탈옥·장면)은 행동이라 늘 주사위 하나를 낸다 (낸 눈 + op_check_dice개). 주사위 없이 하는 판정은 없다.
## 실패해도 다른 주사위로 또 판정할 수 있다 (또 한 행동). 강제 판정(회피·검문·수색)은 주사위 없이 2d6.
##
## 작전 주사위 (7단계, Dead of Winter식): 아침에 요원마다 personal_dice개(2막은 + act2_personal_dice_extra, S단계부터 0)를 굴린다.
## 모두 공개. 행동 하나에 하나씩 쓰고, 남은 것은 밤에 사라진다.
##
## 단계(phase): morning(자동) → plan → day ⇄ turn (+ choice) → (밤) → morning … → over
##
## 파일 구성: 엔진은 층마다 한 파일이고, 위 층이 아래 층을 상속한다. 바깥에서는 늘 RulesV2만 쓴다.
##   rules_base_v2.gd     상태 · 조회 · 판정 함수(무엇을 할 수 있나) · 저장 · 유틸
##   rules_effects_v2.gd  효과 해석기 · 선택 응답 · 아이템 · 능력 · 경찰 · 감옥 · 노출 · 탈옥
##   rules_missions_v2.gd 미션 · 일제 작전 (보드 위 마커)
##   rules_saga_v2.gd     결행 순간 · 개인 사연
##   rules_act2_v2.gd     2막 장면 · 반격 · 엔딩
##   rules_v2.gd (여기)   초기화 · apply · 하루 흐름 · 이동 · 판정 · 흐름의 갈림길(_continue · _resolve_choice)
## 아래 층이 위 층의 함수를 불러야 할 때는 rules_base_v2.gd 맨 끝 「위 층이 채우는 고리」에 자리를 잡아 둔다.

# ================================================================ 초기화

static func new_game(characters: Array, seed_value := -1) -> RulesV2:
	## characters: 캐릭터 id 목록 (요원 이름은 캐릭터 이름을 쓴다)
	var g := RulesV2.new()
	var gd := GameDataV2.load_default()
	var defs := []
	for c in characters:
		defs.append({"name": gd.character(c).get("name", c), "character": c})
	g.setup(defs, seed_value, gd)
	return g


func setup(player_defs: Array, seed_value: int = -1, game_data: GameDataV2 = null) -> void:
	## player_defs: [{"name": String, "character": 캐릭터 id}, ...]
	data = game_data if game_data else GameDataV2.load_default()
	if seed_value < 0:
		# 무작위 판도 시드를 명시해 둔다 (기록 재생용 · JSON에서도 정확한 32비트 값)
		var r := RandomNumberGenerator.new()
		r.randomize()
		seed_value = r.randi()
	rng.seed = seed_value
	var R: Dictionary = data.rules
	board = {}
	board[data.start] = _new_tile("start")
	for b in data.bases:
		board[b] = _new_tile("base")
	tile_deck = []
	var tiles: Dictionary = R["tiles"]
	for t in tiles:
		if str(t).begins_with("_"):
			continue
		for i in int(tiles[t]):
			tile_deck.append(t)
	_shuffle(tile_deck)
	threat_deck = data.threat_deck(1)
	_shuffle(threat_deck)
	threat_discard = []
	threat_today = ""
	mission_deck = _expand(data.missions.get("missions", []))
	mission_discard = []
	mission_row = []
	markers = []
	mission_state = {}
	op_row = []
	op_deck = data.op_deck()
	_shuffle(op_deck)
	op_discard = []
	trend = 0
	peek_bonus = 0
	bonus_wait = []
	expire_queue = []
	marker_seq = 0
	event_deck = _expand(data.events.get("events", []))
	event_discard = []
	item_deck = _expand(data.items.get("items", []))
	item_discard = []
	bomb_supply = int(R["bomb_supply"])
	_setup_saga_decks()
	saga_rewards = []
	launch_step = 0
	launch_i = 0
	vote_state = {}
	counter = {}
	counter_queue = []
	human = -1
	players = []
	for i in player_defs.size():
		var d: Dictionary = player_defs[i]
		if bool(d.get("human", false)):
			human = i
		players.append({
			"id": i, "name": d.get("name", "요원 %d" % (i + 1)), "character": d["character"],
			"pos": data.start, "jailed": false, "jail_count": 0,
			"items": [], "bombs": 0, "move_mod_next": 0, "dice_next": 0, "gives_today": 0,
			"done_today": false, "turns": 0, "fx_cells": [], "hidden": false,
			"ability_day": -1, "item_uses": 0, "grants": [], "flags": {},
			"sagas": [], "saga_done": "", "saga_kept": "", "saga_track": {},
			"jailed_day": -99,
			"stats": {"missions": 0, "escapes": 0, "jailed": 0, "checkpoints": 0,
				"assassinations": 0, "items": 0, "abilities": 0, "gives": 0, "shakes": 0},
		})
	police = {}
	intel = {}
	for id in data.base_ids:
		intel[id] = 0
	exposure = 0
	ready = 0
	rounds_total = int(R["rounds"])
	rounds_left = rounds_total
	act = 1
	day = 1
	leader = 0
	current = -1
	steps_left = 0
	op_dice = []
	today = _new_today()
	pending = {}
	launch_info = {}
	ending = {}
	scenes = []
	scene_index = 0
	scene_state = {}
	intel_tokens = 0
	search_queue = []
	effect_wait = []
	check = {}
	last_roll = []
	_dist_cache = {}
	actions.clear()
	events.clear()
	log_lines.clear()
	history.clear()
	_deal_sagas()
	_log("작전 개시. %d일 안에 결행을 준비하십시오." % rounds_total)
	_begin_morning(true)


# ================================================================ 액션 처리

func apply(action: Dictionary) -> bool:
	if not action in legal_actions():
		return false
	var ok := _apply(action)
	if ok:
		actions.append(action.duplicate(true))
		_counter_refresh()
		_saga_idle_flush()
	return ok


func _apply(a: Dictionary) -> bool:
	if phase == "over":
		return false
	var pid := _int_of(a.get("player", null))
	if pid < 0 or pid >= players.size():
		return false
	var p: Dictionary = players[pid]
	match str(a.get("type", "")):
		"choose":
			if not a.has("value") or not _valid_choice(p, a["value"]):
				return false
			_resolve_choice(a["value"])
		"move_die":
			var i := _int_of(a.get("die", null))
			if not can_move_die(p, i):
				return false
			_move_die(p, i)
		"start_day":
			if not can_start_day():
				return false
			_start_day()
		"begin_turn":
			if not can_begin_turn(p):
				return false
			_begin_turn(p)
		"step":
			var to := _cell_of(a.get("to", null))
			if not can_step(p, to):
				return false
			_do_step(p, to)
		"end_move":
			if not can_end_move(p):
				return false
			_resolve_stop(p)
		"end_turn":
			if not can_end_turn(p):
				return false
			_end_turn(p)
		"escape":
			var ed := _int_of(a.get("die", null))
			if not can_escape(p) or not ed in my_dice(pid):
				return false
			_begin_escape(p, ed)
		"mission_check":
			var md := _int_of(a.get("die", null))
			var mc := _cell_of(a.get("cell", null))
			if not md in my_dice(pid) or not mc in mission_check_cells(p):
				return false
			_begin_mission_check(p, mc, md)
		"work_give":
			var wd := _int_of(a.get("die", null))
			if not can_work_give(p, wd):
				return false
			_work_give(p, wd)
		"counter_check":
			var cd := _int_of(a.get("die", null))
			if not can_counter_check(p) or not cd in my_dice(pid):
				return false
			_start_check(p, "generic", "counter", {"target": int(data.rules["counter"]["target"]), "die_i": cd})
		"hide":
			var hd := _int_of(a.get("die", null))
			if not can_hide(p) or not hd in my_dice(pid):
				return false
			_hide(p, hd)
		"use_item":
			var idx := _int_of(a.get("index", null))
			if not can_use_item(p, idx):
				return false
			_use_item(p, idx)
		"ability":
			var t := -1
			if a.has("target"):
				t = _int_of(a["target"])
				if t < 0:
					return false
			var ad := -1
			if ability_costs_die(p):
				ad = _int_of(a.get("die", null))
				if not ad in my_dice(pid):
					return false
			if not can_use_ability(p, t):
				return false
			_use_ability(p, t, ad)
		"give_die":
			var di := _int_of(a.get("die", null))
			var tgt := _int_of(a.get("target", null))
			if not di in my_dice(pid) or not tgt in give_die_targets(p):
				return false
			_give_die(p, di, players[tgt])
		"scene_check":
			var scd := _int_of(a.get("die", null))
			if not _scene_can_check(p) or not scd in my_dice(pid):
				return false
			_scene_check(p, scd)
		"scene_pay":
			var what := str(a.get("what", ""))
			var index := _int_of(a.get("die", null)) if what == "die" else _int_of(a.get("index", null))
			var spend := _int_of(a.get("with", null)) if what != "die" else -1
			if not _scene_can_pay(p, what, index) or (what != "die" and not spend in my_dice(pid)):
				return false
			_scene_pay(p, what, index, spend)
		"use_intel":
			var mode := str(a.get("mode", ""))
			if not _scene_can_intel(p, mode):
				return false
			_scene_use_intel(p, mode)
		_:
			return false
	return true


# ================================================================ 하루 흐름: 아침

func _begin_morning(first: bool) -> void:
	if first:
		leader = 0
		day = 1
	else:
		leader = (leader + 1) % players.size()
		day += 1
	today = _new_today()
	for q in players:
		q["done_today"] = false
		q["item_uses"] = 0
		q["gives_today"] = 0
		q["fx_cells"] = []
		q["hidden"] = false
		if q["jailed"] and bool(data.rules["jail"].get("release_next_morning", false)) and day >= release_day(q):
			_release(q)
	op_dice = []
	phase = "morning"
	current = -1
	_log("── %s 아침 (남은 %d일) · 리더 %s ──" % [date_label(), rounds_left, players[leader]["name"]])
	_push({"kind": "morning", "day": day, "leader": leader})
	morning_step = 1
	_morning_continue()


func _morning_continue() -> void:
	## 아침 순서(규칙서): 위협 → 일제 작전(짝수 날) → 표적 이동·기한 → 투표 → 미션 줄 → 작전 주사위. 선택이 끼면 멈췄다 이어간다.
	## 일제 작전, 표적 이동·기한, 투표, 미션 줄은 1막에서만 한다.
	while morning_step <= 6 and phase == "morning":
		var s := morning_step
		morning_step += 1
		match s:
			1: _morning_threat()
			2: _morning_ops()
			3: _morning_markers()
			4:
				if act == 1:
					_morning_vote()
			5:
				if act == 1:
					_fill_mission_row()
				else:
					_counter_refresh()
			6: _morning_dice()


func _morning_threat() -> void:
	_flip_threat({"then": "morning", "source": "threat"})


func _flip_threat(ctx: Dictionary) -> void:
	if threat_deck.is_empty():
		threat_deck = threat_discard
		threat_discard = []
		_shuffle(threat_deck)
	if threat_deck.is_empty():
		_continue(players[leader], ctx)
		return
	var id: String = threat_deck.pop_back()
	threat_discard.append(id)
	threat_today = id
	var card: Dictionary = data.threat(id)
	_log("[일제 위협] %s - %s" % [card.get("name", id), card.get("text", "")])
	_record("위협: %s" % card.get("name", id), "warn")
	_push({"kind": "card", "deck": "threat", "id": id, "player": -1})
	_push({"kind": "threat", "id": id})
	_run_effects(players[leader], card.get("effects", []), ctx)


func _morning_vote() -> void:
	var R: Dictionary = data.rules
	if rounds_left <= int(R["forced_launch_days_left"]):
		_log("작전일이 코앞입니다. 더 기다릴 수 없습니다! 결행 대상을 정합니다.")
		_start_vote(true)
		return
	if ready >= int(R["launch_min"]):
		_start_vote(false)


func _start_vote(forced: bool) -> void:
	## 결행 투표: 요원마다 찬반(강제 결행이면 대상만)과 대상을 비공개로 고르고, 모두 낸 뒤 한꺼번에 공개한다.
	var order: Array = players.map(func(q): return q["id"])
	if human >= 0 and human < players.size():
		order.erase(human)
		order.push_front(human)   # 연습 모드: 사람이 먼저 내고 AI 표와 함께 공개된다
	vote_state = {"forced": forced, "order": order, "votes": {}, "targets": {}}
	_vote_next()


func _vote_next() -> void:
	var forced: bool = vote_state["forced"]
	for pid in vote_state["order"]:
		var q: Dictionary = players[pid]
		if not forced and not vote_state["votes"].has(pid):
			var prompt := "결행하시겠습니까? 결행 준비 %d · 경계 %d단계 · 남은 %d일 (표는 모두 낸 뒤 공개됩니다)" % [ready, alert_level(), rounds_left]
			_ask(q, "launch_vote", prompt, [{"value": true, "label": "결행한다"}, {"value": false, "label": "하루 더 준비한다"}], {"then": "morning"})
			pending["secret"] = true
			return
		if not vote_state["targets"].has(pid):
			var opts := []
			for id in launch_candidates():
				opts.append({"value": id, "label": "%s · 첩보 %d" % [data.base_names[data.base_index(id)], int(intel[id])]})
			var tp := "결행할 거점을 고릅니다. 첩보 %d 이상인 곳이 후보입니다." % int(data.rules["launch"]["target_min_intel"])
			_ask(q, "launch_target", tp, opts, {"then": "morning"})
			pending["secret"] = true
			return
	_vote_resolve()


func _vote_resolve() -> void:
	var vs := vote_state
	vote_state = {}
	var forced: bool = vs["forced"]
	var votes: Dictionary = vs["votes"]
	var targets: Dictionary = vs["targets"]
	_push({"kind": "vote_reveal", "forced": forced, "votes": votes.duplicate(), "targets": targets.duplicate()})
	var tally := {}
	for pid in targets:
		tally[targets[pid]] = int(tally.get(targets[pid], 0)) + 1
	var parts := []
	for id in tally:
		parts.append("%s %d표" % [data.base_names[data.base_index(id)], tally[id]])
	if not forced:
		var yes := 0
		for pid in votes:
			if votes[pid]:
				yes += 1
		_log("결행 투표: 찬성 %d, 반대 %d · 대상 %s" % [yes, votes.size() - yes, ", ".join(parts)])
		if not vote_passes(yes, votes.size(), bool(votes.get(leader, false))):
			_log("결행을 하루 미루고 준비를 계속합니다.")
			_morning_continue()
			return
	else:
		_log("강제 결행 대상 투표: %s" % ", ".join(parts))
	var best := 0
	for id in tally:
		best = maxi(best, int(tally[id]))
	var top := []
	for id in data.base_ids:
		if int(tally.get(id, 0)) == best:
			top.append(id)
	_launch("forced" if forced else "vote", "", top)


func vote_passes(yes: int, total: int, leader_yes: bool) -> bool:
	## 결행 투표 통과 (rules.launch.vote): 찬성 비율이 pass_ratio를 넘으면 통과, 딱 같으면 tie 규칙 (leader = 리더가 찬성했으면 통과 · pass · fail)
	var v: Dictionary = data.rules["launch"]["vote"]
	var need := float(v["pass_ratio"]) * float(total)
	if float(yes) > need:
		return true
	if not is_equal_approx(float(yes), need):
		return false
	match str(v["tie"]):
		"pass":
			return true
		"leader":
			return leader_yes
	return false


func _fill_mission_row() -> void:
	## 공개 미션이 줄 수만큼 되도록 채우고, 새 미션의 마커를 보드에 놓는다
	var want := int(data.rules["mission_row"])
	var guard := mission_deck.size() + mission_discard.size() + 1
	while mission_row.size() < want and guard > 0:
		guard -= 1
		if mission_deck.is_empty():
			mission_deck = mission_discard
			mission_discard = []
			_shuffle(mission_deck)
			if mission_deck.is_empty():
				break
		var id: String = mission_deck.pop_back()
		mission_row.append(id)
		_place_card(id)
		_push({"kind": "card", "deck": "mission", "id": id, "player": -1})
	_log("공개 미션: %s" % ", ".join(mission_row.map(func(i): return data.mission(i).get("name", i))))


func _morning_dice() -> void:
	## 요원마다 작전 주사위를 굴린다 (갇힌 요원도). 내일 몫 보정(dice_next)은 여기서 쓰고 지운다.
	op_dice = []
	var parts := []
	var n0 := int(data.rules["personal_dice"]) + (int(data.rules["act2_personal_dice_extra"]) if act == 2 else 0)
	for q in players:
		var n := maxi(0, n0 + int(q["dice_next"]))
		q["dice_next"] = 0
		var vals := []
		for k in n:
			var v := _roll_die()
			op_dice.append({"value": v, "owner": q["id"], "used": false})
			vals.append(v)
		parts.append("%s %s" % [q["name"], " ".join(vals.map(func(x): return str(x))) if not vals.is_empty() else "없음"])
		_saga_note_multi(q, ["rolled_value"], {"values": vals})
	_log("작전 주사위: " + " · ".join(parts))
	_push({"kind": "dice_rolled", "values": op_dice.map(func(d): return d["value"]),
		"owners": op_dice.map(func(d): return d["owner"])})
	phase = "plan"
	current = -1


# ================================================================ 계획

func _start_day() -> void:
	phase = "day"
	current = -1
	_log("하루가 시작됩니다.")
	_push({"kind": "day_start", "day": day})


func _move_die(p: Dictionary, i: int) -> void:
	## 이동 행동: 주사위 하나의 눈만큼 걷는다. 보정(오늘 이동 +, 다음 이동 +)은 그 차례의 첫 이동 행동에 붙는다.
	var mv := move_value(p, i)
	var extra := int(p["flags"].get("move_extra", 0)) + int(p["move_mod_next"])
	p["flags"]["move_extra"] = 0
	p["move_mod_next"] = 0
	_use_die(p, i, "move")
	steps_left = maxi(mv + extra, 1)
	_log("%s: 주사위 %d로 이동 %d칸%s" % [p["name"], die_value(i), steps_left,
		(" (보정 %+d)" % extra) if extra != 0 else ""])


# ================================================================ 낮: 차례

func _begin_turn(p: Dictionary) -> void:
	phase = "turn"
	current = p["id"]
	p["turns"] += 1
	p["flags"]["escape_add"] = 0
	p["flags"].erase("intel_check")
	p["fx_cells"] = []
	p["hidden"] = false
	steps_left = 0
	_push({"kind": "turn", "player": p["id"]})
	if p["jailed"]:
		_log("%s: 감옥에서 차례를 맞았습니다." % p["name"])
		return
	# 오늘 이동 보정은 이 차례의 첫 이동 행동에 붙는다 (다음 이동 보정 move_mod_next도 그때 함께 붙음)
	p["flags"]["move_extra"] = int(today["move_today"].get(p["id"], 0)) + stat(p, "move_bonus")


func _end_turn(p: Dictionary) -> void:
	## 차례 마치기: (이 차장 한 칸) → 「차례를 마치면」 효과(은신처) → 내 경찰 이동 (숨기를 했으면 안 움직임) → 끝
	steps_left = 0
	if p["jailed"]:
		_log("%s: 옥중에서 때를 기다립니다." % p["name"])
	elif _end_hop(p):
		return   # 선택이 끝나면 _end_turn_continue로 이어진다
	_end_turn_continue(p)


func _end_turn_continue(p: Dictionary) -> void:
	if phase == "over":
		return
	if not p["jailed"]:
		_turn_end_tile(p)
		_check_hideout(p)
		if p["hidden"]:
			_log("%s: 몸을 숨겨 경찰이 다가오지 못했습니다." % p["name"])
		else:
			_police_act(p)
	_finish_turn(p)


func _finish_turn(p: Dictionary) -> void:
	if phase == "over":
		return
	p["done_today"] = true
	p["hidden"] = false
	if act == 2 and not p["jailed"]:
		_scene_turn_end(p)
		if phase == "over":
			return
	p["flags"]["escape_add"] = 0
	p["flags"].erase("entry_no_police")     # 한 차례 안에만 쓰는 권리
	p["flags"]["checkpoint_pass"] = 0
	steps_left = 0
	phase = "day"
	current = -1
	_saga_turn_end(p)
	if _turn_end_missions(p):
		return   # 협동·잠복 미션 보상을 처리하는 중 (끝나면 _after_turn으로 이어짐)
	_after_turn()


func _after_turn() -> void:
	if phase == "over":
		return
	if _saga_flush({"then": "after_turn"}):
		return   # 이룬 사연의 보상 처리 중 (끝나면 다시 이어짐)
	for q in players:
		if not q["done_today"]:
			return
	_night()


func _night() -> void:
	today["night"] = true   # 밤에 갇히면 하루를 더 갇힌다 (_on_jailed)
	_push({"kind": "night", "day": day})
	_leftover_to_intel()
	_night_end()


func leftover_rule() -> Dictionary:
	## rules.leftover_to_intel: {"act", "per", "max_tokens"} (없으면 빈 사전 = 규칙 없음)
	var r = data.rules.get("leftover_to_intel", {})
	return r if typeof(r) == TYPE_DICTIONARY else {}


func _leftover_to_intel() -> void:
	## 밤: 그날 쓰지 않은 작전 주사위 per개마다 첩보 토큰 1 (팀 공용, 가진 토큰은 max_tokens까지). 남긴 주사위가 다음 날의 판정 보정이 된다
	var r := leftover_rule()
	if r.is_empty() or act != int(r.get("act", 2)):
		return
	var left := 0
	for d in op_dice:
		if not d["used"]:
			left += 1
	var gain := mini(left / maxi(1, int(r.get("per", 2))), maxi(0, int(r.get("max_tokens", 0)) - intel_tokens))
	if gain <= 0:
		return
	intel_tokens += gain
	_log("남긴 주사위 %d개 → 첩보 토큰 +%d (토큰 %d)." % [left, gain, intel_tokens])
	_record("남긴 주사위 %d개 → 첩보 토큰 +%d" % [left, gain], "good")
	_push({"kind": "leftover_intel", "dice": left, "tokens": gain})
	_banner("남긴 주사위 → 첩보 토큰 +%d" % gain, "good")


func _night_end() -> void:
	if _saga_flush({"then": "night_end"}):
		return
	if act == 2:
		if _scene_night():
			return   # 반격 회피 판정 처리 중 (끝나면 _counter_next가 이어 감)
		if phase == "over":
			return
	_night_after_scene()


func _night_after_scene() -> void:
	rounds_left -= 1
	if rounds_left <= 0:
		rounds_left = 0
		_end_game(false)
		return
	_begin_morning(false)


# ================================================================ 이동

func _do_step(p: Dictionary, to: Vector2i) -> void:
	if not board.has(to):
		var t: String = tile_deck.pop_back()
		board[to] = _new_tile(t)
		_push({"kind": "reveal", "pos": to, "tile": t})
		if t == "check":
			_log("%s: 검문소가 나타났습니다! 이동이 끝납니다." % p["name"])
			steps_left = 0
			_resolve_stop(p)
			return
	if board[to]["type"] == "check":
		_enter_checkpoint(p, to)
		return
	_arrive(p, to)


func _enter_checkpoint(p: Dictionary, to: Vector2i) -> void:
	if int(p["flags"].get("checkpoint_pass", 0)) > 0:
		p["flags"]["checkpoint_pass"] = int(p["flags"]["checkpoint_pass"]) - 1
		_log("%s: 통행증으로 검문소를 그냥 지나갑니다." % p["name"])
		_arrive(p, to)
		return
	_log("%s: 검문소 통과를 시도합니다." % p["name"])
	_start_check(p, "evade", "checkpoint", {"cell": to})


func _arrive(p: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = p["pos"]
	p["pos"] = to
	_push({"kind": "move", "player": p["id"], "from": from, "to": to})
	steps_left -= 1
	_saga_step_on(p, to)
	var t: String = board[to]["type"]
	if t == "base":
		steps_left = 0
		_enter_base(p)
		return
	if _marker_arrive(p, to):
		return
	_after_step(p)


func _after_step(p: Dictionary) -> void:
	if phase == "over":
		return
	if steps_left <= 0:
		_resolve_stop(p)


func _enter_base(p: Dictionary) -> void:
	var bi := base_index_at(p["pos"])
	_log("%s: %s에 들어갔습니다. 이동이 끝납니다." % [p["name"], base_name(bi)])
	for m in markers_at(p["pos"]):
		if str(m["role"]) == "pickup":
			_pickup(p, m)
	var ids := []
	for id in mission_row:
		var cond := card_cond(id)
		if str(cond.get("kind", "")) == "infiltrate" and str(cond.get("base", "")) == data.base_ids[bi]:
			ids.append(id)
	var ctx := {"then": "base_finish", "entered_base": bi}
	ids.append_array(_coop_enter_base(p, bi))
	if ids.is_empty():
		_base_finish(p, ctx)
		return
	_complete_missions(p, ids, ctx)


func _base_finish(p: Dictionary, _ctx: Dictionary) -> void:
	if phase == "over":
		return
	if act == 2 and p["pos"] == _base_cell(str(launch_info.get("target", ""))):
		_log("%s: 결행 거점에서는 경찰이 붙지 않았습니다." % p["name"])
	elif flag(p, "base_no_police"):
		_log("%s: 경찰이 오지 않았습니다." % p["name"])
	elif p["flags"].get("entry_no_police", false):
		p["flags"].erase("entry_no_police")
		_log("%s: 이번에는 경찰이 붙지 않았습니다." % p["name"])
	else:
		_summon(p)
	_finish_move(p)


func _resolve_stop(p: Dictionary) -> void:
	## 이동을 마친 칸의 효과. 같은 칸의 효과는 한 차례에 한 번만 받는다.
	if phase == "over":
		return
	steps_left = 0
	var cell: Vector2i = p["pos"]
	if cell in p["fx_cells"]:
		_finish_move(p)
		return
	p["fx_cells"].append(cell)
	var tile: Dictionary = board.get(cell, {})
	var fx: Dictionary = data.rules.get("tile_effects", {}).get(str(tile.get("type", "")), {})
	if fx.has("on_stop") and not (fx.has("once") and bool(tile.get("used", false))):
		if fx.has("once"):
			tile["used"] = true
			tile["type"] = str(fx["once"])
		_run_effects(p, fx["on_stop"], {"then": "post_move", "source": "tile"})
		return
	_finish_move(p)


func _turn_end_tile(p: Dictionary) -> void:
	## 차례를 마친 칸의 타일 효과 (rules.tile_effects의 on_turn_end): 주막은 같은 칸에 동료가 있으면 하루 한 번 노출 -1
	var t := tile_type(p["pos"])
	var fx: Dictionary = data.rules.get("tile_effects", {}).get(t, {})
	if not fx.has("on_turn_end"):
		return
	if str(fx.get("needs", "")) == "ally_here":
		var any := false
		for q in players:
			if q["id"] != p["id"] and not q["jailed"] and q["pos"] == p["pos"]:
				any = true
		if not any:
			return
	if bool(fx.get("once_per_day", false)):
		if today["once"].has(t):
			return
		today["once"][t] = true
	_log("%s: %s 칸의 효과를 받습니다." % [p["name"], tile_label(t)])
	_push({"kind": "tile_fx", "player": p["id"], "tile": t})
	_run_effects(p, fx["on_turn_end"], {"then": "resume", "source": "tile"})


func _check_hideout(p: Dictionary) -> void:
	var tile: Dictionary = board.get(p["pos"], {})
	if tile.get("flags", []).has(str(data.rules["hideout_flag"])) and police.has(p["id"]):
		_police_off(p["id"], "hideout")
		_log("%s: 은신처에 숨어 추적하던 경찰을 따돌렸습니다." % p["name"])
		_push({"kind": "police"})


func hop_cells(p: Dictionary) -> Array:
	## end_move_hop_to_ally: 차례를 마칠 때 한 칸 옮겨 갈 수 있는, 동료가 있는 옆 칸 (깔린 칸, 경찰이 없는 칸)
	var out := []
	for d in DIRS:
		var n: Vector2i = p["pos"] + d
		if not _inert_tile(n) or police_on(n):
			continue
		for q in players:
			if q["id"] != p["id"] and not q["jailed"] and q["pos"] == n:
				out.append(n)
				break
	return out


func _end_hop(p: Dictionary) -> bool:
	## 차례를 마칠 때 동료가 있는 옆 칸으로 한 칸 옮길지 묻는다 (end_move_hop_to_ally). 물었으면 true.
	if phase == "over" or p["jailed"] or not flag(p, "end_move_hop_to_ally"):
		return false
	var cells := hop_cells(p)
	if cells.is_empty():
		return false
	var opts := [{"value": "no", "label": "그대로 있는다"}]
	for c in cells:
		opts.append({"value": c, "label": "(%d, %d)칸 동료 곁으로 옮긴다" % [c.x, c.y]})
	_ask(p, "hop", "동료가 있는 옆 칸으로 한 칸 옮기시겠습니까?", opts, {})
	return true


func _finish_move(p: Dictionary) -> void:
	## 이동 행동 하나가 끝났다 (칸 효과까지). 걸음이 남았으면 계속 걷고, 아니면 행동 고르기로 돌아간다.
	if phase == "turn" and steps_left > 0 and not p["jailed"] and p["id"] == current:
		return
	steps_left = 0


# ================================================================ 판정

func _start_check(p: Dictionary, name: String, ctx: String, extra: Dictionary = {}) -> void:
	## name: rules.checks의 판정 이름. 보정은 stat "<name>_bonus" (+ 미션 종류별 보정)
	var target: int = int(extra["target"]) if extra.has("target") else check_target(name)
	var bonus: int = stat(p, name + "_bonus")
	bonus += int(extra.get("intel_bonus", 0))
	if extra.has("type_bonus") and str(extra["type_bonus"]) != name:
		bonus += stat(p, str(extra["type_bonus"]) + "_bonus")
	if name == "escape":
		bonus += int(today.get("escape_mod", 0)) + int(p["flags"].get("escape_add", 0))
	check = {"what": name, "ctx": ctx, "player": p["id"], "target": target, "bonus": bonus,
		"auto_rerolls": stat(p, name + "_rerolls"), "dice": [], "total": 0}
	for k in extra:
		check[k] = extra[k]
	if extra.has("die_i"):
		# 작전 판정은 행동이다: 낸 주사위의 눈 + 새 주사위. 보정이나 자동 성공으로 바로 끝나도 주사위는 쓴 것이다.
		var di := int(extra["die_i"])
		check["die_value"] = die_value(di)
		_use_die(p, di, "check")
		_log("%s: 주사위 %d을(를) 내어 %s 판정" % [p["name"], die_value(di), _check_label(check)])
	# 한 번 쓰는 권리: 판정 보정 (이번 판정에 자동으로 더함)
	var gi := _grant_index(p, "check_bonus", ctx == "scene")
	if gi >= 0:
		check["bonus"] += int(p["grants"][gi].get("value", 0))
		p["grants"].remove_at(gi)
	if name == "escape" and _grant_index(p, "escape_instant") >= 0:
		p["grants"].remove_at(_grant_index(p, "escape_instant"))
		_log("%s: 한 번 쓰는 권리로 곧바로 탈출합니다." % p["name"])
		_check_done(p, true)
		return
	if name == "evade":
		if flag(p, "evade_auto"):
			_log("%s: 타고난 은신술로 회피에 성공합니다." % p["name"])
			_check_done(p, true)
			return
		var egi := _grant_index(p, "evade_auto")
		if egi >= 0:
			p["grants"].remove_at(egi)
			_log("%s: 회피에 자동으로 성공합니다." % p["name"])
			_check_done(p, true)
			return
		var react := _react_item(p, "react_evade")
		if react != "":
			_ask(p, "react_evade", "회피 판정입니다. [%s]을(를) 쓰시겠습니까?" % item_def(react)["name"],
				[{"value": true, "label": "%s 사용" % item_def(react)["name"]}, {"value": false, "label": "주사위로 판정"}], {})
			pending["item"] = react
			return
	_check_roll(p)


func check_preview(p: Dictionary, a: Dictionary) -> Dictionary:
	## 작전 판정 행동(mission_check · escape · scene_check)의 목표와 보정 {"target", "bonus"} (성공 확률 미리 보기용).
	## 보정은 특성·아이템·첩보·한 번 쓰는 권리를 더한 값이다.
	var out := {"target": 99, "bonus": 0}
	match str(a.get("type", "")):
		"mission_check":
			var m := marker_at(_cell_of(a.get("cell", null)))
			if m.is_empty():
				return out
			var cond: Dictionary = card_cond(str(m["id"]))
			var name := str(cond["check"])
			out["target"] = int(cond["target"])
			out["bonus"] = stat(p, name + "_bonus") + (int(cond.get("informed_bonus", 0)) if bool(mission_state.get(m["id"], {}).get("informed", false)) else 0)
		"escape":
			out["target"] = check_target("escape")
			out["bonus"] = stat(p, "escape_bonus") + int(today.get("escape_mod", 0)) + int(p["flags"].get("escape_add", 0))
		"counter_check":
			out["target"] = int(data.rules["counter"]["target"])
			out["bonus"] = stat(p, "generic_bonus")
		"scene_check":
			var leaf := _scene_check_leaf(p)
			if leaf.is_empty():
				return out
			var cond2: Dictionary = leaf["cond"]
			var name2 := str(cond2.get("check", "generic"))
			out["target"] = scene_check_target(cond2)
			out["bonus"] = stat(p, name2 + "_bonus") + int(p["flags"].get("intel_check", 0))
	var gi := _grant_index(p, "check_bonus", str(a.get("type", "")) == "scene_check")
	if gi >= 0:
		out["bonus"] = int(out["bonus"]) + int(p["grants"][gi].get("value", 0))
	return out


func check_chance(c: Dictionary, die := 0) -> float:
	## 이 판정이 성공할 확률 (die > 0이면 그 눈 + op_check_dice개, 아니면 check_dice개)
	var sides := int(data.rules["die_sides"])
	var n := int(data.rules["op_check_dice"]) if die > 0 else int(data.rules["check_dice"])
	var need: int = int(c["target"]) - int(c["bonus"]) - die
	var dist := {0: 1.0}
	for k in n:
		var nd := {}
		for s0 in dist:
			for f in range(1, sides + 1):
				nd[s0 + f] = float(nd.get(s0 + f, 0.0)) + float(dist[s0]) / float(sides)
		dist = nd
	var ok := 0.0
	for s1 in dist:
		if int(s1) >= need:
			ok += float(dist[s1])
	return ok


func _react_item(p: Dictionary, when: String) -> String:
	for id in p["items"]:
		var it: Dictionary = item_def(id)
		if it.get("when", "") == when and it.has("effects"):
			return id
	return ""


func _check_roll(p: Dictionary) -> void:
	var c := check
	var dv := int(c.get("die_value", 0))
	var r := 0
	if dv > 0:
		r = dv + _d2(int(data.rules["op_check_dice"]))
		c["dice"] = [dv] + last_roll
	else:
		r = _d2()
		c["dice"] = last_roll.duplicate()
	c["total"] = r + int(c["bonus"])
	var ok: bool = c["total"] >= int(c["target"])
	var label := _check_label(c)
	_push({"kind": "dice", "what": label, "dice": c["dice"], "bonus": c["bonus"], "target": c["target"],
		"player": p["id"], "ok": ok, "played": dv, "chance": check_chance(c, dv)})
	_log("%s: %s 판정 %d%s (목표 %d) → %s" % [p["name"], label, r,
		(" %+d" % c["bonus"]) if c["bonus"] != 0 else "", c["target"], "성공" if ok else "실패"])
	if ok:
		_check_done(p, true)
		return
	if int(c["auto_rerolls"]) > 0:
		c["auto_rerolls"] = int(c["auto_rerolls"]) - 1
		_log("%s: 타고난 솜씨로 다시 굴립니다." % p["name"])
		_check_roll(p)
		return
	var gi := _grant_index(p, "reroll", str(c.get("ctx", "")) == "scene")
	if gi < 0:
		_check_done(p, false)   # 다시 하려면 「다시 굴리기」 권리가 있어야 한다 (작전 판정은 다른 주사위로 새 행동을 할 수 있음)
		return
	_ask(p, "reroll", "%s 판정에 실패했습니다. 다시 굴릴 권리를 쓰시겠습니까?" % label,
		[{"value": "no", "label": "그대로 실패로 한다"}, {"value": "grant", "label": "다시 굴릴 권리를 쓴다"}], {})


func _check_done(p: Dictionary, ok: bool) -> void:
	var c := check
	check = {}
	match str(c["ctx"]):
		"checkpoint":
			if ok:
				_log("%s: 검문소를 무사히 통과했습니다." % p["name"])
				_banner("검문소 통과", "info", p)
				p["stats"]["checkpoints"] += 1
				_saga_note(p, "pass_checkpoint")
				_arrive(p, c["cell"])
			else:
				_log("%s: 검문에 걸렸습니다! 이동이 끝납니다." % p["name"])
				_banner("검문에 걸렸다!", "bad", p)
				_expose(int(data.rules["exposure"]["on_checkpoint_fail"]))
				_summon(p)
				_resolve_stop(p)
		"mission_check":
			_mission_check_result(p, c, ok)
		"mission_evade":
			# 미션 판정에 실패해 도망치는 중: 성공하면 경찰이 붙고 (같은 차례에 다른 주사위로 다시 판정할 수 있음), 실패하면 투옥
			if ok:
				_summon(p)
			else:
				_jail(p)
			_finish_move(p)
		"scene":
			_scene_check_result(p, c, ok)
		"counter":
			if ok:
				counter["blocked"] = true
				_log("%s: 반격을 막아 냈습니다!" % p["name"])
				_banner("반격을 막았다", "good", p)
				_push({"kind": "counter_blocked", "player": p["id"]})
			else:
				_log("%s: 반격을 막지 못했습니다." % p["name"])
		"counter_evade":
			if not ok:
				_jail(p)
			_counter_next()
		"search":
			if not ok:
				_summon(p)
			_search_next()
		"check_or_jail":
			if not ok:
				_jail(p)
			_stage4_resume()
		"escape":
			p["flags"]["escape_add"] = 0
			if ok:
				p["jailed"] = false
				p["stats"]["escapes"] += 1
				_saga_note(p, "escapes")
				_log("%s: 탈옥 성공!" % p["name"])
				_banner("탈옥 성공!", "good", p)
				_summon(p)
			else:
				_log("%s: 탈옥 실패." % p["name"])



# ================================================================ 흐름의 갈림길 (효과 · 선택 · 판정이 끝나면 이어 갈 곳, 합법 액션 모으기)

func ability_targets(p: Dictionary) -> Array:
	## 능력을 쓸 수 있는 대상. 대상이 필요 없는 능력(self)이면 [-1] (target 없이 보냄). 못 쓰면 [].
	var a: Dictionary = ability_def(p)
	if a.is_empty() or p["ability_day"] == day or p["jailed"]:
		return []
	if str(a.get("cost", "")) == "die" and (steps_left > 0 or my_dice(p["id"]).is_empty()):
		return []   # 주사위를 내는 능력은 이동 중에는 못 쓴다
	match str(a.get("when", "")):
		"morning":
			if phase != "plan":
				return []
		"turn":
			if phase != "turn" or p["id"] != current:
				return []
		_:
			return []
	if not _cost_ok(p, a.get("effects", []), 0):
		return []
	var req: Dictionary = a.get("requires", {})
	if req.has("near_tile"):
		var near := false
		for d in DIRS:
			if tile_type(p["pos"] + d) == str(req["near_tile"]):
				near = true
		if not near:
			return []
	if req.has("base_in_range") and _bases_in_range(p["pos"], int(req["base_in_range"])).is_empty():
		return []
	var kind: String = str(a.get("target", "self"))
	if kind == "self":
		return [-1]
	var gives_die := _has_op(a.get("effects", []), "give_die")   # 주사위 건네기는 감옥의 동료에게도 닿는다 (차례를 마친 요원에게는 안 됨)
	var out := []
	for q in players:
		if q["id"] == p["id"] or (q["jailed"] and not gives_die) or (gives_die and q["done_today"]):
			continue
		var d := walk_dist(q["pos"], p["pos"])
		match kind:
			"ally":
				out.append(q["id"])
			"ally_adjacent":
				if d <= 1:
					out.append(q["id"])
			"ally_same_cell":
				if d == 0:
					out.append(q["id"])
			"ally_in_range":
				if d <= int(a.get("range", 1)):
					out.append(q["id"])
	return out


func can_use_ability(p: Dictionary, target: int) -> bool:
	return target in ability_targets(p)


func legal_actions() -> Array:
	## 지금 받아들일 수 있는 액션 전부
	var out := []
	if phase == "over":
		return out
	match phase:
		"choice":
			var pid: int = pending["player"]
			for o in pending["options"]:
				out.append({"type": "choose", "player": pid, "value": o["value"]})
		"plan":
			for p in players:
				for ii in p["items"].size():
					if can_use_item(p, ii):
						out.append({"type": "use_item", "player": p["id"], "index": ii})
				_append_ability_actions(out, p)
			if can_start_day():
				for p in players:
					out.append({"type": "start_day", "player": p["id"]})
		"day":
			for p in players:
				if can_begin_turn(p):
					out.append({"type": "begin_turn", "player": p["id"]})
		"turn":
			out.append_array(_turn_actions(players[current]))
	return out


func _turn_actions(p: Dictionary) -> Array:
	## 지금 행동 고르기(또는 이동 중)인 요원이 할 수 있는 것
	var out := []
	var pid: int = p["id"]
	var moving: bool = steps_left > 0 and not p["jailed"]
	if moving:
		for to in legal_steps(p):
			out.append({"type": "step", "player": pid, "to": to})
		out.append({"type": "end_move", "player": pid})
	else:
		out.append({"type": "end_turn", "player": pid})
	for ii in p["items"].size():
		if can_use_item(p, ii):
			out.append({"type": "use_item", "player": pid, "index": ii})
	_append_ability_actions(out, p)
	if moving:
		return out   # 걷는 동안에는 공짜 행동(아이템·능력)만 더 할 수 있다
	var dice := my_dice(pid)
	for i in dice:
		if can_move_die(p, i):
			out.append({"type": "move_die", "player": pid, "die": i})
		if can_escape(p):
			out.append({"type": "escape", "player": pid, "die": i})
		if can_hide(p):
			out.append({"type": "hide", "player": pid, "die": i})
		for c in mission_check_cells(p):
			out.append({"type": "mission_check", "player": pid, "die": i, "cell": c})
		if can_work_give(p, i):
			out.append({"type": "work_give", "player": pid, "die": i})
		for t in give_die_targets(p):
			out.append({"type": "give_die", "player": pid, "die": i, "target": t})
	out.append_array(scene_options(p))
	return out


func _append_ability_actions(out: Array, p: Dictionary) -> void:
	for t in ability_targets(p):
		var a := {"type": "ability", "player": p["id"]}
		if t >= 0:
			a["target"] = t
		if ability_costs_die(p):
			for i in my_dice(p["id"]):
				var b := a.duplicate()
				b["die"] = i
				out.append(b)
		else:
			out.append(a)


func _run_effects(p: Dictionary, effects: Array, ctx: Dictionary) -> void:
	## 효과 목록을 차례로 처리한다. 선택이 필요하면 pending을 열고 멈췄다가,
	## 선택이 끝나면 남은 효과(rest)와 이어서 계속한다. 다 끝나면 ctx["then"]으로 이어간다.
	ctx["actor"] = p["id"]
	var queue: Array = effects.duplicate()
	while not queue.is_empty():
		if phase == "over":
			return
		var e: Dictionary = queue.pop_front()
		if str(e.get("op", "")) in ["search", "check_or_jail", "threat_flip"]:
			effect_wait.append({"player": p["id"], "rest": queue, "ctx": ctx})
			match str(e["op"]):
				"search":
					search_queue = []
					var base := _base_cell(str(launch_info.get("target", "")))
					for q in players:
						if not q["jailed"] and _manhattan(q["pos"], base) <= int(e.get("range", 0)):
							search_queue.append(q["id"])
					_search_next()
				"check_or_jail":
					_start_check(p, str(e.get("check", "evade")), "check_or_jail")
				"threat_flip":
					_flip_threat({"then": "stage4_effect"})
			return
		if _effect(p, e, ctx, queue):
			pending["rest"] = queue
			pending["ctx"] = ctx
			return
	_continue(p, ctx)


func _continue(p: Dictionary, ctx: Dictionary) -> void:
	if phase == "over":
		return
	match str(ctx.get("then", "resume")):
		"morning":
			_morning_continue()
		"post_move":
			_finish_move(p)
		"after_turn":
			_after_turn()
		"night_end":
			_night_end()
		"stop":
			_resolve_stop(p)
		"base_finish":
			_base_finish(p, ctx)
		"saga":
			var nxt: Dictionary = ctx.get("next", {"then": "resume"})
			if not _saga_flush(nxt):
				_continue(p, nxt)
		"launch":
			_launch_continue()
		"stage4_effect":
			_stage4_resume()
		"scene_check_done":
			_finish_scene_check(p)
		"act2_scenes":
			_act2_scenes()
		"morning_expire":
			_morning_expire()
		_:
			pass   # "resume": 원래 단계로 돌아가 계속 진행


func _resolve_choice(value) -> void:
	var pd := pending
	pending = {}
	var p: Dictionary = players[pd["player"]]
	var actor: Dictionary = players[int(pd.get("ctx", {}).get("actor", pd["player"]))]
	phase = pd["resume_phase"]
	match str(pd["kind"]):
		"launch_vote":
			vote_state["votes"][p["id"]] = bool(value)
			_vote_next()
		"launch_target":
			vote_state["targets"][p["id"]] = str(value)
			_vote_next()
		"strike_target":
			_finish_launch(str(value))
		"launch_benefit":
			_take_benefit(str(value))
			_launch_continue()
		"threat_look":
			var idx := threat_deck.size() - 1 - int(value)
			if idx >= 0 and idx < threat_deck.size():
				var gone: String = threat_deck.pop_at(idx)
				threat_discard.append(gone)
				_log("2막 위협 「%s」을(를) 버렸습니다." % data.threat(gone).get("name", gone))
			_run_effects(actor, pd["rest"], pd["ctx"])
		"saga_keep":
			_keep_saga(p, str(value))
			_launch_continue()
		"reroll":
			if str(value) == "grant":
				var gi := _grant_index(players[check["player"]], "reroll", str(check.get("ctx", "")) == "scene")
				if gi >= 0:
					players[check["player"]]["grants"].remove_at(gi)
				_log("%s: 다시 굴릴 권리를 씁니다." % p["name"])
				_check_roll(players[check["player"]])
			else:
				_check_done(players[check["player"]], false)
		"react_evade":
			if bool(value):
				var id: String = pd["item"]
				var idx: int = p["items"].find(id)
				if idx >= 0:
					p["items"].remove_at(idx)
					item_discard.append(id)
				_log("%s: [%s] 사용" % [p["name"], item_def(id)["name"]])
				_push({"kind": "item_used", "id": id, "player": p["id"]})
				# 효과(보통 회피 자동 성공 권리)를 적용한 뒤, 권리가 생겼으면 판정이 자동 성공
				for e in item_def(id).get("effects", []):
					_effect(p, e, {"then": "resume"}, [])
				var egi := _grant_index(p, "evade_auto")
				if egi >= 0:
					p["grants"].remove_at(egi)
					_log("%s: 회피에 성공합니다." % p["name"])
					_check_done(p, true)
				else:
					_check_roll(p)
			else:
				_check_roll(p)
		"discard":
			var id2: String = p["items"][int(value)]
			p["items"].remove_at(int(value))
			item_discard.append(id2)
			_log("%s: [%s]을(를) 버렸습니다." % [p["name"], item_def(id2)["name"]])
			_run_effects(actor, pd["rest"], pd["ctx"])
		"draw_pick":
			var cards: Array = pd["cards"]
			var chosen: String = cards[int(value)]
			for i in cards.size():
				if i != int(value):
					item_discard.append(cards[i])
			if _take_item(p, chosen):
				pending["rest"] = pd["rest"]
				pending["ctx"] = pd["ctx"]
				return
			_run_effects(actor, pd["rest"], pd["ctx"])
		"effect_choice":
			var picked: Array = pd["effects"][int(value)]
			_run_effects(actor, picked + pd["rest"], pd["ctx"])
		"pick_player", "pick_cell", "pick_die", "pick_tile", "pick_item", "pick_value", "pick_bury":
			if not pd["rest"].is_empty():
				pd["rest"][0][str(pd.get("key", "pid"))] = value
			_run_effects(actor, pd["rest"], pd["ctx"])
		"hop":
			if value is Vector2i:
				_teleport(p, value)
				_log("%s: 동료 곁으로 한 칸 옮겼습니다." % p["name"])
			_end_turn_continue(p)
		"intel_base":
			_add_intel(data.base_index(str(value)), int(pd["amount"]))
			_run_effects(actor, pd["rest"], pd["ctx"])
