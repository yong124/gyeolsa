class_name NetViewV2
extends RefCounted
## 온라인: 서버의 판 상태에서 한 사람이 볼 수 있는 것만 남긴다 (설계 12단계 6.5, 지시서 H1 3절 「보기 거르기」).
## 숨기는 것: 다른 사람의 사연(이루기 전), 덱 순서, 공개 전의 투표, 난수 상태, 행동 기록(선택 값이 들어 있음).
## 클라이언트는 이 보기를 RulesV2.load_state()로 읽어 화면만 그린다(판정은 서버가 한다).

const DECKS := ["tile_deck", "mission_deck", "event_deck", "item_deck", "op_deck",
	"mission_discard", "event_discard", "item_discard", "op_discard", "threat_discard", "saga_discard"]
const HIDDEN := "?"


static func view_for(game: RulesV2, pid: int, log_from := 0) -> Dictionary:
	## log_from: 이 사람이 이미 받은 작전 기록 줄 수. 그 뒤의 새 줄만 담는다 (Z5: 기록이 보기의 절반을 차지함)
	var st := game.save_state()
	st["log_from"] = log_from
	st["log_lines"] = (st.get("log_lines", []) as Array).slice(log_from)
	st.erase("rng_seed")
	st.erase("rng_state")
	st["actions"] = []   # 선택 값(남긴 사연 등)이 들어 있다
	st["human"] = pid
	# 덱: 장수만 남기고 내용은 숨긴다
	for k in DECKS:
		if st.get(k) is Array:
			st[k] = _blank(st[k])
	# 위협 덱: 요원들이 미리 볼 수 있는 장수(threat_preview)만 남긴다. 덱 맨 위는 배열의 끝
	var peek := game.threat_preview().size()
	var td: Array = st.get("threat_deck", [])
	for i in td.size():
		if i < td.size() - peek:
			td[i] = HIDDEN
	# 사연 더미
	var sd = st.get("saga_decks")
	if sd is Dictionary:
		for k in sd:
			if sd[k] is Array:
				sd[k] = _blank(sd[k])
	elif sd is Array:
		st["saga_decks"] = _blank(sd)
	# 다른 사람의 사연: 장수만 (이룬 사연은 공개)
	for q in st["players"]:
		if int(q["id"]) == pid:
			continue
		q["sagas"] = (q["sagas"] as Array).map(func(s): return s if str(s) == str(q["saga_done"]) else HIDDEN)
		if str(q["saga_kept"]) != str(q["saga_done"]):
			q["saga_kept"] = HIDDEN if str(q["saga_kept"]) != "" else ""
		q["saga_track"] = {}
	# 공개 전 투표: 낸 사람만 보이고 무엇을 냈는지는 숨긴다 (내 표는 보임)
	var vs = st.get("vote_state")
	if vs is Dictionary and not vs.is_empty():
		for key in ["votes", "targets"]:
			var d: Dictionary = vs.get(key, {})
			for voter in d.keys():
				if int(voter) != pid:
					d[voter] = HIDDEN
	# 남의 선택 창: 모양은 두고(클라이언트 코드가 읽음), 비밀이 든 선택(남길 사연 · 위협 덱 보기)만 보기 값을 숨긴다
	var pend = st.get("pending")
	if pend is Dictionary and not pend.is_empty() and int(pend.get("player", -1)) != pid \
			and str(pend.get("kind", "")) in ["saga_keep", "threat_look"]:
		pend["prompt"] = ""
		pend["options"] = (pend.get("options", []) as Array).map(func(o):
			return {"value": HIDDEN, "label": HIDDEN} if o is Dictionary else HIDDEN)
	return st


static func events_for(events: Array, pid: int) -> Array:
	## 연출 이벤트: 남의 비밀 이벤트(사연 받기 · 사연 남기기)는 뺀다
	var out := []
	for e in events:
		if bool(e.get("secret", false)) and int(e.get("player", -1)) != pid:
			continue
		out.append(e)
	return out


static func _find(v, secret: Dictionary, path: String) -> Array:
	## 보기 안에서 비밀 문자열이 그대로 나오는 곳의 경로 (시험용)
	var out := []
	if v is Dictionary:
		for k in v:
			if secret.has(str(k)):
				out.append("%s의 키 %s" % [path, k])
			out.append_array(_find(v[k], secret, "%s.%s" % [path, k]))
	elif v is Array:
		for i in v.size():
			out.append_array(_find(v[i], secret, "%s[%d]" % [path, i]))
	elif v is String and secret.has(v):
		out.append("%s = %s (요원 %d의 사연)" % [path, v, secret[v]])
	return out


static func _blank(a: Array) -> Array:
	var out := []
	out.resize(a.size())
	out.fill(HIDDEN)
	return out


static func leaks(view: Dictionary, game: RulesV2, pid: int) -> Array:
	## 시험용: 보기에 남아 있으면 안 되는 비밀이 있는가 (남의 이루지 않은 사연 id, 덱 순서)
	var found := []
	if str(view.get("phase", "")) == "over":
		return found   # 판이 끝나면 후일담에서 모두의 사연을 함께 본다 (의도된 공개)
	var secret := {}
	for q in game.players:
		if int(q["id"]) == pid:
			continue
		for s in q["sagas"]:
			if str(s) != str(q["saga_done"]):
				secret[str(s)] = int(q["id"])
	for hit in _find(view, secret, "보기"):
		found.append(hit)
	for k in ["mission_deck", "event_deck", "item_deck"]:
		var real: Array = game.get(k)
		if real.size() >= 3 and (view.get(k, []) as Array).slice(0, 3) == real.slice(0, 3):
			found.append("덱 순서 " + k)
	return found
