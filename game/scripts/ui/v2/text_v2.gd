class_name TextV2
extends RefCounted
## 여러 화면(보드 · 기운 보드 · 위 띠 · 판 화면 · 엔딩)이 같이 쓰는 이름 문장 (지시서 Z4: 흩어져 있던 것을 모음).
## 「나」는 판의 사람 자리(RulesV2.human)로 정한다. 온라인에서는 내 자리가 0번이 아닐 수 있다.


static func agent(g: RulesV2, pid: int) -> String:
	## 요원 이름 (예: 「윤 소위」). 없는 자리면 「-」
	if pid < 0 or pid >= g.players.size():
		return "-"
	var p: Dictionary = g.players[pid]
	return str(g.char_def(p).get("name", p["name"]))


static func agent_short(g: RulesV2, pid: int) -> String:
	## 내 자리면 「나」, 아니면 요원 이름
	return "나" if pid == g.human else agent(g, pid)


static func agent_full(g: RulesV2, pid: int) -> String:
	## 내 자리면 「나 (윤 소위)」, 아니면 요원 이름
	return ("나 (%s)" % agent(g, pid)) if pid == g.human and pid >= 0 else agent(g, pid)


static func agent_tag(g: RulesV2, pid: int, me: int) -> String:
	## 보드 말 위 이름표: 「나」 또는 띄어쓰기 없는 이름 (좁은 자리)
	return "나" if pid == me else agent(g, pid).replace(" ", "")


static func marker_role(g: RulesV2, role: String) -> String:
	## 마커 역할 이름 (ui.json marker_names, 예: target → 표적)
	return str(g.data.ui.get("marker_names", {}).get(role, role))
