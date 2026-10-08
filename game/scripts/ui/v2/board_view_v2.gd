class_name BoardViewV2
extends Control
## v2 보드판 그리기·애니메이션·칸 클릭 (v1 BoardView를 RulesV2에 맞게 옮긴 것).
##
## 말과 경찰은 게임 상태가 아니라 "보이는 위치"(vis_*)에 그린다. 연출 큐가 이벤트 순서대로
## 이 위치를 움직이고, 연출이 끝나면 sync_from_game()으로 실제 상태와 맞춘다.
## 지도 그림·타일 그림은 board.json(map · tile_art)에서 읽는다.

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)   # U1: 선택 미리보기 띠

const FADE := Color(0.93, 0.88, 0.78, 0.62)   # 빈 땅을 흐리게 덮는 종이색 (U2: 지도 · 격자가 말 · 목표를 묻지 않게 더 흐리게)

var game: RulesV2
var human_id := 0
var hover := Vector2i(-1, -1)
var interactive := true          # 연출 중에는 강조를 끈다
var draw_pieces := true          # 말(요원 · 경찰)을 여기서 그릴지 (기운 보드는 말을 세워 따로 그림, TiltBoardV2)
var pick_cells: Array = []       # 선택(pick_cell·hop) 중 고를 수 있는 칸

var vis_players := {}            # id -> Vector2
var _move_lift := {}
var vis_jailed := {}
var vis_police := {}             # id -> {"pos": Vector2, "active": bool, "alpha": float}
var hidden_tiles := {}
var _reveal := {}
var _pulse := 0.0
var _idle_wait := 0.0             # Z5: 가만히 있을 때 다시 그리기까지 남은 시간
const IDLE_REDRAW := 0.05         # 가만히 있을 때는 초당 20번만 다시 그린다 (반짝임 · 발자국은 느려서 충분). 움직임 · 뒤집기는 트윈이 매 프레임 그린다
var _preview := {}
var reach := {}                  # 이동 미리 보기: 닿을 수 있는 칸 {칸: 걸음 수} (행동 메뉴에서 이동에 올려 놓았을 때)
var scouted := {}                # 정찰로 미리 깐 칸 (아직 아무도 멈추지 않은 곳)
var marker_trails := {}          # 카드 id -> {"from", "to", "age"}: 표적이 움직인 자리 (잠깐 보임)

const TRAIL_SECONDS := 9.0

var _tex := {}
var _faction_tex := {}
var _prints: Array = []   # 먹 발자국 [{"c", "pid", "t"}]
var _police_tex: Texture2D
var _map_tex: Texture2D
var _map := {}


func setup(g: RulesV2, human: int) -> void:
	game = g
	human_id = human
	_map = g.data.map_info()
	_map_tex = load(_map["image"])
	for t in g.data.tile_art:
		var def: Dictionary = g.data.tile_art[t]
		for key in ["texture", "used_texture"]:
			if def.has(key):
				_tex[def[key]] = load("res://assets/tiles/%s.png" % def[key])
	_tex["back"] = load("res://assets/tiles/back.png")
	for t in g.data.rules["tiles"]:
		if not str(t).begins_with("_") and not g.data.tile_art.has(str(t)) and ResourceLoader.exists("res://assets/tiles/%s.png" % t):
			_tex["new:" + str(t)] = load("res://assets/tiles/%s.png" % t)   # 새 타일 그림 (tools/gen_ui_art.py tiles)
	for f in g.data.characters.get("factions", {}):
		if not str(f).begins_with("_"):
			var path := "res://assets/ui/faction_%s.png" % f
			if ResourceLoader.exists(path):
				_faction_tex[f] = load(path)
	_police_tex = load("res://assets/ui/police.png")
	mouse_filter = Control.MOUSE_FILTER_STOP
	sync_from_game()


func faction_texture(f: String) -> Texture2D:
	return _faction_tex.get(f)


func _process(delta: float) -> void:
	_pulse += delta
	for fp in _prints:
		fp["t"] += delta
	_prints = _prints.filter(func(fp): return fp["t"] < 4.0)
	for id in marker_trails.keys():
		marker_trails[id]["age"] = float(marker_trails[id]["age"]) + delta
		if float(marker_trails[id]["age"]) > TRAIL_SECONDS:
			marker_trails.erase(id)
	_idle_wait -= delta
	if game and game.phase != "over" and _idle_wait <= 0.0:
		_idle_wait = IDLE_REDRAW
		queue_redraw()


# ------------------------------------------------------------------ 연출 상태

func sync_from_game() -> void:
	vis_players.clear()
	_move_lift.clear()
	vis_jailed.clear()
	for p in game.players:
		vis_players[p["id"]] = Vector2(p["pos"])
		vis_jailed[p["id"]] = p["jailed"]
	vis_police.clear()
	for pid in game.police:
		vis_police[pid] = {"pos": Vector2(game.police[pid]["pos"]), "active": game.police_active(pid), "alpha": 1.0}
	hidden_tiles.clear()
	_reveal.clear()
	_update_preview()
	queue_redraw()


func note_scouted(c: Vector2i) -> void:
	scouted[c] = true
	queue_redraw()


func note_footprint(c: Vector2i, pid: int) -> void:
	## V 연출: 말이 지나간 칸에 먹 발자국 (몇 초 뒤 사라짐)
	_prints.append({"c": c, "pid": pid, "t": 0.0})
	if _prints.size() > 40:
		_prints.pop_front()


func note_arrived(c: Vector2i) -> void:
	scouted.erase(c)


func note_marker_moved(id: String, from: Vector2i, to: Vector2i) -> void:
	marker_trails[id] = {"from": from, "to": to, "age": 0.0}
	queue_redraw()


func apply_players_snap(snap: Dictionary) -> void:
	for id in snap:
		vis_jailed[id] = snap[id]["jailed"]
	queue_redraw()


func animate_move(id: int, from: Vector2i, to: Vector2i, dur: float) -> void:
	if dur <= 0.0:
		vis_players[id] = Vector2(to)
		_move_lift.erase(id)
		queue_redraw()
		return
	var a := Vector2(from)
	var b := Vector2(to)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		vis_players[id] = a.lerp(b, t)
		_move_lift[id] = sin(t * PI) * 12.0
		queue_redraw(), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_move_lift.erase(id)
	queue_redraw()


func reveal(c: Vector2i, dur: float) -> void:
	hidden_tiles.erase(c)
	if dur <= 0.0:
		queue_redraw()
		return
	_reveal[c] = 0.0
	var tw := create_tween()
	tw.tween_method(func(t: float):
		_reveal[c] = t
		queue_redraw(), 0.0, 1.0, dur)
	await tw.finished
	_reveal.erase(c)
	queue_redraw()


func animate_police(snap: Dictionary, dur: float) -> void:
	var starts := {}
	for pid in snap:
		var target := Vector2(snap[pid]["pos"])
		if vis_police.has(pid):
			starts[pid] = vis_police[pid]["pos"]
		else:
			starts[pid] = target
			vis_police[pid] = {"pos": target, "active": snap[pid]["active"], "alpha": 0.0}
		vis_police[pid]["active"] = snap[pid]["active"]
	var gone := vis_police.keys().filter(func(pid): return not snap.has(pid))
	if dur <= 0.0:
		for pid in gone:
			vis_police.erase(pid)
		for pid in snap:
			vis_police[pid]["pos"] = Vector2(snap[pid]["pos"])
			vis_police[pid]["alpha"] = 1.0
		queue_redraw()
		return
	var tw := create_tween()
	tw.tween_method(func(t: float):
		for pid in snap:
			if vis_police.has(pid):
				vis_police[pid]["pos"] = starts[pid].lerp(Vector2(snap[pid]["pos"]), t)
				vis_police[pid]["alpha"] = maxf(vis_police[pid]["alpha"], t)
		for pid in gone:
			if vis_police.has(pid):
				vis_police[pid]["alpha"] = 1.0 - t
		queue_redraw(), 0.0, 1.0, dur)
	await tw.finished
	for pid in gone:
		vis_police.erase(pid)
	queue_redraw()


func police_changed(snap: Dictionary) -> bool:
	if snap.size() != vis_police.size():
		return true
	for pid in snap:
		if not vis_police.has(pid) or vis_police[pid]["pos"] != Vector2(snap[pid]["pos"]) \
				or vis_police[pid]["active"] != snap[pid]["active"]:
			return true
	return false


# ------------------------------------------------------------------ 좌표

func _scale() -> float:
	return minf(size.x, size.y) / float(_map["px"])


func cell_rect(c: Vector2i) -> Rect2:
	return cell_rect_f(Vector2(c))


func cell_rect_f(c: Vector2) -> Rect2:
	var s := _scale()
	var o: float = _map["origin"]
	var cs: float = _map["cell"]
	return Rect2((o + c.x * cs) * s, (o + c.y * cs) * s, cs * s, cs * s)


func cell_center(c: Vector2i) -> Vector2:
	return cell_rect(c).get_center()


func cell_at(pos: Vector2) -> Vector2i:
	var s := _scale()
	var x := int(floor((pos.x / s - _map["origin"]) / _map["cell"]))
	var y := int(floor((pos.y / s - _map["origin"]) / _map["cell"]))
	var c := Vector2i(x, y)
	return c if game and game.in_bounds(c) else Vector2i(-1, -1)


# ------------------------------------------------------------------ 입력

func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != hover:
			hover = c
			tooltip_text = _tooltip(c)
			if _my_move_turn() and c.x >= 0 and game.can_step(game.players[human_id], c):
				Sfx.play("click", 0.12, 0.22)
			_update_preview()
			cell_hovered.emit(c)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(event.position)
		if c.x >= 0 and interactive:
			cell_clicked.emit(c)


func _my_move_turn() -> bool:
	return interactive and game.phase == "turn" and game.current == human_id \
		and not game.players[human_id]["jailed"] and game.steps_left > 0


func _update_preview() -> void:
	_preview = {}
	if hover.x >= 0 and _my_move_turn():
		_preview = game.path_to(game.players[human_id], hover)


func preview_path() -> Array:
	if _preview.is_empty() or not _preview["reachable"]:
		return []
	return _preview["path"]


func _tooltip(c: Vector2i) -> String:
	if c.x < 0:
		return ""
	if not game.board.has(c) or hidden_tiles.has(c):
		var cover := "미탐색 지역"
		for m in game.markers_at(c):
			cover += "\n" + _marker_text(m)
		return cover
	var t: String = game.board[c]["type"]
	var name := game.tile_label(t)
	var bi := game.data.bases.find(c)
	if bi >= 0:
		var id: String = game.data.base_ids[bi]
		name = "%s (일본군 거점)\n첩보 %d" % [game.data.base_names[bi], int(game.intel.get(id, 0))]
		if game.act == 2 and str(game.launch_info.get("target", "")) == id:
			name += " · 결행 거점"
	if game.board[c].get("used", false):
		name += " (사용함)"
	if t == "check":
		name += "\n들어가려면 회피 판정 (실패하면 경찰이 붙음)"
	if "hideout" in game.board[c].get("flags", []):
		name += "\n은신처: 여기서 차례를 마치면 쫓던 경찰이 사라짐"
	if _can_hide_at(c):
		name += "\n숨기 가능: 주사위 하나로 숨으면 이번 차례 끝에 경찰이 다가오지 않음"
	var fx: Dictionary = game.data.rules.get("tile_effects", {}).get(t, {})
	if fx.has("text"):
		name += "\n" + str(fx["text"])
	for m in game.markers_at(c):
		name += "\n" + _marker_text(m)
	return name


func _marker_text(m: Dictionary) -> String:
	## 마커 한 개의 설명: 어느 미션·작전의 무엇인가, 남은 날, 진행
	var id := str(m["id"])
	var card: Dictionary = game.card_def(id)
	var role := TextV2.marker_role(game, str(m["role"]))
	var s := "%s · %s %s" % ["일제 작전" if game.data.is_op(id) else "미션", card.get("name", ""), role]
	var days := game.card_days_left(id)
	if days >= 0:
		s += " · 남은 %d일" % days
	var st := game.card_status(id)
	if st != "":
		s += " · " + st
	return s


# ------------------------------------------------------------------ 그리기

static var draw_usec := 0     # Z5 측정: 그리기에 쓴 시간 합(마이크로초)과 횟수 (tour perf)
static var draw_count := 0


func _draw() -> void:
	if _map_tex == null:
		return
	var t0 := Time.get_ticks_usec()
	_draw_all()
	draw_usec += Time.get_ticks_usec() - t0
	draw_count += 1


func _draw_all() -> void:
	var side := minf(size.x, size.y)
	draw_texture_rect(_map_tex, Rect2(0, 0, side, side), false)
	draw_rect(Rect2(0, 0, side, side), FADE)
	_draw_tiles()
	_draw_marks()
	_draw_scene_place()
	_draw_danger()
	_draw_highlights()
	_draw_reach()
	_draw_preview()
	_draw_prints()
	if draw_pieces:
		_draw_players()
	_draw_chase()
	if draw_pieces:
		_draw_police()
	_draw_markers()
	_draw_targets()
	_draw_preview_label()


func _draw_tiles() -> void:
	var font := Style.serif(700)
	var s := _scale()
	for c in game.board:
		if hidden_tiles.has(c):
			continue
		var info: Dictionary = game.board[c]
		var t: String = info["type"]
		if t == "start":
			continue
		var def: Dictionary = game.data.tile_art.get(t, {})
		if def.is_empty():
			_draw_plain_tile(c, t)
			continue
		var key: String = def.get("used_texture", def["texture"]) if info.get("used", false) else def["texture"]
		var art := _tile_art(c, t, info.get("used", false))   # V 연출 타일 그림 (없으면 지금 그림)
		var face: Texture2D = art if art != null else _tex[key]
		var r := cell_rect(c).grow(-3.0 * s)
		if _reveal.has(c):
			var t01: float = _reveal[c]
			var w := absf(cos(t01 * PI))
			var lift := sin(t01 * PI) * r.size.y * 0.12
			var rr := Rect2(r.get_center().x - r.size.x * w / 2.0, r.position.y - lift, r.size.x * w, r.size.y)
			draw_rect(Rect2(rr.position + Vector2(0, 4 + lift), rr.size), Color(0, 0, 0, 0.3))
			draw_texture_rect(_back_tex() if t01 < 0.5 else face, rr, false)
			continue
		draw_rect(Rect2(r.position + Vector2(1, 4), r.size), Color(0, 0, 0, 0.35))
		draw_rect(r, Style.PAPER_HI if t != "base" else Color("#d6c6a2"))
		draw_texture_rect(face, r.grow(-3.0) if art == null else r, false)
		if t != "base":
			draw_rect(r, Color(0.16, 0.12, 0.08, 0.14))   # 길 · 칸 그림을 한 단계 눌러 말 · 마커가 위로 뜨게
		if "hideout" in info.get("flags", []):
			draw_rect(r.grow(-1), Color(Style.GOOD, 0.8), false, 3.0)
		if _can_hide_at(c):
			var bf := maxi(10, int(r.size.x * 0.16))
			var bw := font.get_string_size("숨", HORIZONTAL_ALIGNMENT_LEFT, -1, bf).x + 6
			draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(bw, bf * 1.3)), Color(Style.GOOD, 0.9))
			draw_string(font, r.position + Vector2(5, bf * 1.05 + 2), "숨", HORIZONTAL_ALIGNMENT_LEFT, -1, bf, Color.WHITE)
		if t == "base":
			var bi := game.data.bases.find(c)
			var label: String = game.data.base_names[bi]
			var fs := maxi(12, int(r.size.x * 0.19))
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var lp := Vector2(r.get_center().x - w / 2.0, r.end.y + fs * 0.35)
			draw_rect(Rect2(lp.x - 5, lp.y - fs * 0.95, w + 10, fs * 1.3), Style.INK)
			draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.PAPER)
			_draw_intel(r, bi)


func _draw_plain_tile(c: Vector2i, t: String) -> void:
	## 그림이 아직 없는 새 타일(골목·감시탑·장터·주막)은 글자로 그린다 (제대로 된 그림은 F단계)
	var s := _scale()
	var r := cell_rect(c).grow(-3.0 * s)
	if _reveal.has(c):
		var t01: float = _reveal[c]
		var w := absf(cos(t01 * PI))
		var lift := sin(t01 * PI) * r.size.y * 0.12
		r = Rect2(r.get_center().x - r.size.x * w / 2.0, r.position.y - lift, r.size.x * w, r.size.y)
		if t01 < 0.5:
			draw_texture_rect(_back_tex(), r, false)
			return
	var art := _tile_art(c, t, false)
	if art != null:
		draw_rect(Rect2(r.position + Vector2(1, 4), r.size), Color(0, 0, 0, 0.35))
		draw_texture_rect(art, r, false)
		_draw_hide_badge(c, r)
		return
	if _tex.has("new:" + t):
		draw_rect(Rect2(r.position + Vector2(1, 4), r.size), Color(0, 0, 0, 0.35))
		draw_rect(r, Style.PAPER_HI)
		draw_texture_rect(_tex["new:" + t], r.grow(-3.0), false)
		_draw_hide_badge(c, r)
		return
	var col := Color.from_hsv(float(t.hash() % 360) / 360.0, 0.5, 0.55)
	draw_rect(Rect2(r.position + Vector2(1, 4), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Style.PAPER_HI)
	draw_rect(r.grow(-3.0), col, false, 3.0)
	var label: String = game.tile_label(t)
	var font := Style.serif(900)
	var fs := maxi(16, int(r.size.x * 0.46))
	var g := label.substr(0, 1)
	var gw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, r.get_center() + Vector2(-gw / 2.0, fs * 0.2), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var sf := maxi(9, int(r.size.x * 0.15))
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sf).x
	draw_string(font, Vector2(r.get_center().x - lw / 2.0, r.end.y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, sf, col.darkened(0.2))
	_draw_hide_badge(c, r)


func _tile_art(c: Vector2i, t: String, used: bool) -> Texture2D:
	## V 연출 타일 그림 (art/tile). 길은 칸 위치로 4장 중 하나(늘 같은 그림), 쓴 이벤트·아이템 칸은 길, 거점은 거점마다
	if t == "base":
		var bi := game.data.bases.find(c)
		return ArtV2.get_tex("tile", "base_" + game.data.base_ids[bi]) if bi >= 0 else null
	if t == "normal" or used:
		return ArtV2.get_tex("tile", "normal_%d" % (posmod(c.x * 7 + c.y * 13, 4) + 1))
	return ArtV2.get_tex("tile", t)


func _back_tex() -> Texture2D:
	return ArtV2.get_tex("tile", "back", _tex["back"])


func _draw_hide_badge(c: Vector2i, r: Rect2) -> void:
	if _reveal.has(c) or not _can_hide_at(c):
		return
	var font := Style.serif(700)
	var bf := maxi(10, int(r.size.x * 0.16))
	var bw := font.get_string_size("숨", HORIZONTAL_ALIGNMENT_LEFT, -1, bf).x + 6
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(bw, bf * 1.3)), Color(Style.GOOD, 0.9))
	draw_string(font, r.position + Vector2(5, bf * 1.05 + 2), "숨", HORIZONTAL_ALIGNMENT_LEFT, -1, bf, Color.WHITE)


func _tag(r: Rect2, corner: int, text: String, col: Color) -> void:
	## 칸 모서리에 작은 글자 표지 (corner 0 왼쪽 위 · 1 오른쪽 위 · 2 왼쪽 아래 · 3 오른쪽 아래)
	var font := Style.sans(800)
	var fs := maxi(9, int(r.size.x * 0.13))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6
	var h := fs * 1.35
	var x := r.position.x + 2 if corner % 2 == 0 else r.end.x - w - 2
	var y := r.position.y + 2 if corner < 2 else r.end.y - h - 2
	draw_rect(Rect2(x, y, w, h), col)
	draw_string(font, Vector2(x + 3, y + fs * 1.05), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_marks() -> void:
	## 정찰로 미리 깐 칸, 이번 차례에 칸 효과를 이미 받은 칸
	for c in scouted:
		if game.board.has(c) and not hidden_tiles.has(c):
			_tag(cell_rect(c).grow(-3.0), 3, "정찰", Color(Style.INK_2, 0.9))
	if game.phase == "turn" and game.current == human_id:
		for c in game.players[human_id]["fx_cells"]:
			if game.board.has(c) and game.tile_type(c) not in ["normal", "start"] and not hidden_tiles.has(c):
				_tag(cell_rect(c).grow(-3.0), 1, "받음", Color(Style.INK_3, 0.9))


func _draw_reach() -> void:
	## 행동 메뉴에서 이동에 올려 놓으면 갈 수 있는 칸을 밝힌다 (걸음 수를 작게)
	if reach.is_empty() or game.phase == "over":
		return
	var font := Style.sans(800)
	for c in reach:
		var r := cell_rect(c).grow(-4)
		draw_rect(r, Color(Style.GOLD_HI, 0.38))
		draw_rect(r, Color(Style.GOLD, 0.9), false, 2.0)
		var fs := maxi(10, int(r.size.x * 0.22))
		var t := str(reach[c])
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, r.get_center() + Vector2(-w / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.INK)


func _draw_chase() -> void:
	## 경찰이 누구를 쫓는지 선으로 잇고, 거리(걸음)와 따돌림까지 남은 거리를 적는다
	var font := Style.sans(800)
	var esc := int(game.data.rules["police"]["escape_distance"])
	for pid in vis_police:
		if not vis_players.has(pid) or vis_jailed.get(pid, false):
			continue
		var a: Vector2 = cell_center(Vector2i(vis_police[pid]["pos"].round()))
		var bpt: Vector2 = cell_center(Vector2i(vis_players[pid].round()))
		var col: Color = Style.seat(pid)
		var alpha: float = float(vis_police[pid]["alpha"]) * (0.85 if vis_police[pid]["active"] else 0.5)
		draw_dashed_line(a, bpt, Color(0.1, 0.07, 0.04, 0.45 * alpha), 5.0, 9.0)
		draw_dashed_line(a, bpt, Color(col, alpha), 3.0, 9.0)
		var d := game.walk_dist(Vector2i(vis_police[pid]["pos"].round()), Vector2i(vis_players[pid].round()))
		var text := "%d칸" % d if d < 100 else "길이 끊김"
		if pid == human_id and d < 100:
			text += " · %d칸 넘게 벌어지면 따돌림" % (esc + 1)
		var fs := 12
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
		var mid := (a + bpt) / 2.0
		draw_rect(Rect2(mid - Vector2(w / 2.0, 10), Vector2(w, 20)), Color(Style.INK, 0.82 * alpha))
		draw_string(font, mid + Vector2(-w / 2.0 + 5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Style.PAPER, alpha))


func _marker_short(m: Dictionary) -> String:
	## 마커 곁에 적는 진행 (공작: 바친 합·남은 눈, 잠복: 쌓은 날, 연락: 든 요원, 암살: 동선 파악)
	var id := str(m["id"])
	var st: Dictionary = game.mission_state.get(id, {})
	var cond := game.card_cond(id)
	match str(m["role"]):
		"work":
			match str(cond.get("mode", "")):
				"sum": return "%d/%d" % [int(st.get("sum", 0)), int(st.get("need", 0))]
				"combo": return "·".join(st.get("left", []).map(func(v): return str(v)))
				"each": return "%d곳 남음" % game.markers_of(id, "work").size()
		"spot":
			return "%d/%d일" % [int(st.get("lurk", 0)), int(cond.get("days", 1))]
		"pickup":
			var h := int(st.get("holder", -1))
			return ("%s 듦" % TextV2.agent(game, h).replace(" ", "")) if h >= 0 else ""
		"target":
			return "멈춤" if bool(st.get("informed", false)) else ""
	return ""


func _draw_marker_tags() -> void:
	var font := Style.sans(800)
	for m in game.markers:
		var t := _marker_short(m)
		if t == "" or str(m["role"]) == "base":
			continue
		var r := cell_rect(m["pos"])
		var fs := maxi(9, int(r.size.x * 0.125))
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8
		var at := Vector2(r.position.x + 2, r.position.y + r.size.y * 0.52)
		var col: Color = Style.SEAL if game.data.is_op(str(m["id"])) else Style.MISSION
		draw_rect(Rect2(at, Vector2(w, fs * 1.4)), Color(Style.INK, 0.86))
		draw_rect(Rect2(at, Vector2(3, fs * 1.4)), col)
		draw_string(font, at + Vector2(5, fs * 1.08), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.PAPER)


func _can_hide_at(c: Vector2i) -> bool:
	## 「숨기」를 할 수 있는 칸 (rules.hide의 타일 종류나 표시가 있는 칸)
	var h: Dictionary = game.data.rules["hide"]
	if game.tile_type(c) in h["tiles"]:
		return true
	for f in game.board.get(c, {}).get("flags", []):
		if f in h["flags"]:
			return true
	return false


func _draw_intel(r: Rect2, bi: int) -> void:
	var n: int = int(game.intel.get(game.data.base_ids[bi], 0))
	if n <= 0:
		return
	var font := Style.sans(800)
	var fs := maxi(10, int(r.size.x * 0.16))
	var t := "%d" % n
	var c := r.position + Vector2(r.size.x * 0.12, r.size.y * 0.12)
	var rad := fs * 0.85
	draw_circle(c + Vector2(1, 2), rad, Color(0, 0, 0, 0.35))
	draw_circle(c, rad, Style.SEAL)
	draw_arc(c, rad, 0, TAU, 20, Style.PAPER_HI, 1.5, true)
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w / 2, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_scene_place() -> void:
	## 2막: 지금 장면을 돌파하는 자리 (금색 점선)
	if game.act != 2 or game.phase == "over":
		return
	var glow := 0.35 + 0.2 * sin(_pulse * 2.5)
	for c in game.scene_place_cells():
		var r := cell_rect(c).grow(-2)
		draw_rect(r, Color(Style.GOLD_HI, glow * 0.35))
		_dashed_rect(r, Color(Style.GOLD, 0.9), 2.5)


func _hatch(r: Rect2, col: Color, n := 5) -> void:
	for k in range(1, n):
		var o := r.size.x * k / n
		draw_line(r.position + Vector2(o, 0), r.position + Vector2(0, o), col, 3.0)
		draw_line(r.end - Vector2(o, 0), r.end - Vector2(0, o), col, 3.0)
	draw_line(r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), col, 3.0)


func _draw_danger() -> void:
	if not interactive or game.current != human_id or game.phase != "turn":
		return
	var me: Dictionary = game.players[human_id]
	for c in game.police_danger(me):
		var r := cell_rect(c).grow(-2)
		draw_rect(r, Color(Style.SEAL, 0.14))
		_hatch(r, Color(Style.SEAL, 0.42))
		draw_rect(r, Color(Style.SEAL, 0.6), false, 2.0)


func _flag(r: Rect2, tag: String, col: Color, wave: float) -> void:
	var font := Style.serif(800)
	var fs := maxi(11, int(r.size.x * 0.17))
	var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16
	var pole := Vector2(r.end.x - 6, r.position.y - fs * 1.1)
	draw_line(pole + Vector2(1, 2), pole + Vector2(1, fs * 2.4 + 2), Color(0, 0, 0, 0.3), 3.0)
	draw_line(pole, pole + Vector2(0, fs * 2.4), Color("#3a2a1a"), 3.0)
	var fl := pole + Vector2(2, 0)
	var dy := sin(wave) * 1.5
	var pts := PackedVector2Array([fl, fl + Vector2(w, dy), fl + Vector2(w - 8, fs * 0.72), fl + Vector2(w, fs * 1.45 + dy), fl + Vector2(0, fs * 1.45)])
	draw_colored_polygon(pts, col)
	draw_string(font, fl + Vector2(5, fs * 1.07), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func mission_targets() -> Dictionary:
	## 거점 자체가 마커인 미션(잠입)의 목표 칸 {칸: 이름}
	var out := {}
	if game.act != 1:
		return out
	for m in game.markers:
		if str(m["role"]) == "base":
			out[m["pos"]] = "미션"
	return out


func _draw_markers() -> void:
	## 보드 위 마커: 역할 글자가 든 동그라미(미션은 파랑 계열, 일제 작전은 붉은색), 기한이 있으면 남은 날, 표적이 움직인 자리
	if game.act != 1 or game.phase == "over":
		return
	_draw_marker_tags()
	var font := Style.sans(900)
	for id in marker_trails:
		var tr: Dictionary = marker_trails[id]
		var a := 1.0 - float(tr["age"]) / TRAIL_SECONDS
		draw_dashed_line(cell_center(tr["from"]), cell_center(tr["to"]), Color(Style.SEAL, 0.7 * a), 4.0, 8.0)
		draw_circle(cell_center(tr["from"]), cell_rect(tr["from"]).size.x * 0.08, Color(Style.SEAL, 0.6 * a))
	for m in game.markers:
		var role := str(m["role"])
		if role == "base":
			continue
		var id := str(m["id"])
		var is_op := game.data.is_op(id)
		var col: Color = Style.SEAL if is_op else Style.MISSION
		var r := cell_rect(m["pos"])
		var rad := r.size.x * 0.24
		var ctr := r.position + Vector2(r.size.x * 0.29, r.size.y * 0.31)
		var held := role == "pickup" and int(game.mission_state.get(id, {}).get("holder", -1)) >= 0
		var alpha := 0.45 if held else 1.0
		draw_circle(ctr + Vector2(1, 3), rad + 2, Color(0, 0, 0, 0.4 * alpha))
		draw_circle(ctr, rad + 2, Color(Style.PAPER_HI, alpha))
		draw_circle(ctr, rad, Color(col, alpha))
		var fs := maxi(10, int(rad * 1.25))
		var g: String = str(game.data.ui.get("marker_glyph", {}).get(role, "?"))
		var gw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, ctr + Vector2(-gw / 2.0, fs * 0.36), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var days := game.card_days_left(id)
		if days >= 0 and role in ["target", "work", "spot", "pickup"]:
			var dc := ctr + Vector2(rad * 0.95, -rad * 0.95)
			var dfs := maxi(9, int(rad * 0.95))
			draw_circle(dc, dfs * 0.62, Color(Style.INK, alpha))
			var dt := str(days)
			var dw := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs).x
			draw_string(font, dc + Vector2(-dw / 2.0, dfs * 0.36), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs, Color.WHITE)


func _draw_targets() -> void:
	if game.phase == "over":
		return
	var marks := {}
	if game.act == 2:
		var bi := game.data.base_index(str(game.launch_info.get("target", "")))
		if bi >= 0:
			marks[game.data.bases[bi]] = ["결행", Style.SEAL]
	var mt := mission_targets()
	for c in mt:
		if not marks.has(c):
			marks[c] = [mt[c], Style.MISSION]
	for q in game.players:
		if q["jailed"] and q["id"] != human_id:
			if not marks.has(q["pos"]):
				marks[q["pos"]] = ["구출", Style.seat(1)]
	var glow := 0.55 + 0.35 * sin(_pulse * 3.0)
	for c in marks:
		var r := cell_rect(c).grow(-1)
		var col: Color = marks[c][1]
		draw_rect(r, Color(col, glow * 0.8), false, 3.0)
		_flag(r, marks[c][0], col, _pulse * 3.0 + c.x)


func _draw_preview() -> void:
	if _preview.is_empty() or not _my_move_turn() or _preview["path"].is_empty():
		return
	var me: Dictionary = game.players[human_id]
	var ok: bool = _preview["reachable"]
	var col := Style.GOLD_HI if ok else Color(0.55, 0.5, 0.45)
	var pts: Array[Vector2] = [cell_center(me["pos"])]
	for c in _preview["path"]:
		pts.append(cell_center(c))
	for i in pts.size() - 1:
		draw_dashed_line(pts[i], pts[i + 1], Color(0.2, 0.14, 0.05, 0.5), 7.0, 10.0)
		draw_dashed_line(pts[i], pts[i + 1], col, 5.0, 10.0)
	var font := Style.sans(800)
	var rad := cell_rect(me["pos"]).size.x * 0.16
	for i in range(1, pts.size()):
		if i == pts.size() - 1:
			draw_circle(pts[i], rad * 1.9, Color(col, 0.28))
			draw_arc(pts[i], rad * 1.9, 0, TAU, 32, col, 3.0, true)
		draw_circle(pts[i], rad, col)
		draw_arc(pts[i], rad, 0, TAU, 24, Color("#fff6dc"), 2.0, true)
		var n := str(i)
		var w := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, int(rad * 1.2)).x
		draw_string(font, pts[i] + Vector2(-w / 2, rad * 0.42), n, HORIZONTAL_ALIGNMENT_LEFT, -1, int(rad * 1.2), Style.INK)


func _draw_preview_label() -> void:
	if _preview.is_empty() or not _my_move_turn() or _preview["path"].is_empty():
		return
	var me: Dictionary = game.players[human_id]
	var ok: bool = _preview["reachable"]
	var danger := game.police_danger(me).has(hover)
	var parts := []
	parts.append(("%d칸" % _preview["steps"]) if ok else _preview["reason"])
	if _preview["checks"] > 0:
		parts.append("검문 %d회" % _preview["checks"])
	if _preview["unknown"] > 0:
		parts.append("미탐색 %d칸" % _preview["unknown"])
	if danger:
		parts.append("체포 위험!")
	var text := " · ".join(parts)
	var font := Style.sans(700)
	var fs := 16
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var hr := cell_rect(hover)
	var at := hr.position + Vector2(hr.size.x / 2 - w / 2 - 8, -34)
	at.x = clampf(at.x, 4, size.x - w - 20)
	at.y = maxf(at.y, 4)
	var box := Rect2(at, Vector2(w + 16, 28))
	draw_rect(Rect2(box.position + Vector2(0, 3), box.size), Color(0, 0, 0, 0.3))
	draw_rect(box, Style.INK)
	draw_rect(Rect2(box.position, Vector2(4, box.size.y)), Style.SEAL if danger else (Style.GOLD if ok else Style.INK_3))
	draw_string(font, at + Vector2(10, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ff9a8e") if danger else Style.PAPER)


func _dashed_rect(r: Rect2, col: Color, width := 2.0, dash := 7.0) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, width, dash)


func _draw_highlights() -> void:
	var font := Style.serif(900)
	var glow := 0.2 + 0.1 * sin(_pulse * 4.0)
	if interactive and not pick_cells.is_empty():
		for c in pick_cells:
			var r := cell_rect(c).grow(-3)
			draw_rect(r, Color(Style.GOLD_HI, 0.45 if c == hover else glow + 0.15))
			_dashed_rect(r, Style.SEAL, 3.0)
		return
	if _my_move_turn():
		var me: Dictionary = game.players[human_id]
		for c in game.legal_steps(me):
			var r := cell_rect(c).grow(-3)
			var risky := game.tile_type(c) == "check"
			var col := Color("#d9822b") if risky else Style.GOLD
			draw_rect(r, Color(col.lightened(0.25), 0.55 if c == hover else glow + 0.22))
			draw_rect(r.grow(1.5), Color(Style.PAPER_HI, 0.9), false, 4.0)
			draw_rect(r, col.darkened(0.3), false, 3.0)
			if not game.board.has(c):
				var fs := int(r.size.x * 0.5)
				var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, r.get_center() + Vector2(-w / 2, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#7a5a1e"))
	elif hover.x >= 0:
		draw_rect(cell_rect(hover), Color(1, 1, 1, 0.12))


func _draw_police() -> void:
	for pid in vis_police:
		var v: Dictionary = vis_police[pid]
		var r := cell_rect_f(v["pos"])
		var ctr := r.get_center() + Vector2(r.size.x * 0.26, -r.size.y * 0.24)
		var alpha: float = v["alpha"] * (1.0 if v["active"] else 0.7)
		var rad := r.size.x * 0.31
		if v["active"]:
			var pulse := 0.5 + 0.5 * sin(_pulse * 5.0 + pid)
			draw_circle(ctr, rad + 6 + pulse * 5, Color(Style.SEAL, 0.25 * alpha * (0.6 + pulse * 0.4)))
		draw_circle(ctr + Vector2(2, 5), rad + 3, Color(0, 0, 0, 0.45 * alpha))
		draw_circle(ctr, rad + 3, Color(Style.SEAL if v["active"] else Color("#8a6d3b"), alpha))
		draw_circle(ctr, rad, Color(0.12, 0.1, 0.09, alpha))
		var ir := rad * 1.02
		draw_texture_rect(_police_tex, Rect2(ctr - Vector2(ir, ir), Vector2(ir, ir) * 2), false, Color(1, 1, 1, alpha))
		draw_circle(ctr + Vector2(rad * 0.72, rad * 0.72), rad * 0.24, Color(Style.seat(pid), alpha))
		draw_arc(ctr + Vector2(rad * 0.72, rad * 0.72), rad * 0.24, 0, TAU, 16, Color(1, 1, 1, alpha), 1.5, true)


func _draw_prints() -> void:
	for fp in _prints:
		var r := cell_rect(fp["c"])
		var a: float = 1.0 - float(fp["t"]) / 4.0
		var col := Color(Style.seat(fp["pid"]).darkened(0.5), 0.55 * a)
		var ctr := r.get_center()
		var w := r.size.x * 0.07
		for k in 2:   # 발자국 두 개
			var o := Vector2(-w * 1.4 if k == 0 else w * 1.4, w * 1.2 if k == 0 else -w * 1.2)
			draw_set_transform(ctr + o, 0.0, Vector2(0.7, 1.0))
			draw_circle(Vector2.ZERO, w, col)
			draw_circle(Vector2(0, -w * 1.2), w * 0.55, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_players() -> void:
	var stacks := {}
	for id in vis_players:
		var key: Vector2 = vis_players[id].round()
		stacks[key] = stacks.get(key, []) + [id]
	var font := Style.sans(800)
	for key in stacks:
		var group: Array = stacks[key]
		for i in group.size():
			var id: int = group[i]
			var p: Dictionary = game.players[id]
			var r := cell_rect_f(vis_players[id])
			var rad := r.size.x * (0.33 if group.size() == 1 else 0.24)
			var ctr := r.get_center() + Vector2(0, -r.size.y * 0.04)
			if group.size() > 1:
				var ang := TAU * i / group.size() - PI / 2
				ctr += Vector2(cos(ang), sin(ang)) * r.size.x * 0.22
			var jailed: bool = vis_jailed.get(id, false)
			var is_cur: bool = id == game.current and game.phase in ["turn", "choice"]
			var lift := 0.0
			if is_cur:
				lift = 3.0 + 3.0 * sin(_pulse * 3.5)
				draw_circle(ctr - Vector2(0, lift), rad + r.size.x * 0.1, Color(Style.GOLD_HI, 0.45 + 0.2 * sin(_pulse * 4.0)))
			lift += _move_lift.get(id, 0.0)
			var ring: Color = Style.seat(id)
			var fac: String = str(game.char_def(p).get("faction", ""))
			var cid := str(p["character"])
			var portrait := ArtV2.has("token", cid)   # 동그랗게 자른 초상이 있으면 얼굴, 없으면 세력 문양
			_token(ctr - Vector2(0, lift), rad, ArtV2.get_tex("token", cid, _faction_tex.get(fac)), ring, 0.6 if jailed else 1.0, lift, portrait)
			if jailed:
				for k in 4:
					var x := ctr.x - rad * 0.75 + k * rad * 0.5
					draw_line(Vector2(x, ctr.y - rad - 2), Vector2(x, ctr.y + rad + 2), Color(0.1, 0.08, 0.06), 3.0)
				draw_line(Vector2(ctr.x - rad, ctr.y - rad * 0.3), Vector2(ctr.x + rad, ctr.y - rad * 0.3), Color(0.1, 0.08, 0.06), 3.0)
			if group.size() > 1:
				continue   # 여럿이 한 칸이면 이름표를 아래에서 하나로 합친다
			if id != human_id and not is_cur and Vector2i(vis_players[id].round()) != hover:
				continue   # U2: 동료 이름표는 지금 차례이거나 마우스를 올렸을 때만 (초상 고리 색으로 구분)
			var tag: String = TextV2.agent_tag(game, id, human_id)
			var fs := maxi(10, int(r.size.x * 0.14))
			var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
			var tr := Rect2(ctr.x - w / 2, ctr.y - lift - rad - fs * 1.35, w, fs * 1.3)
			draw_rect(tr, Style.seat(id))
			draw_rect(tr, Color(Style.PAPER_HI, 0.9), false, 1.5)
			draw_string(font, tr.position + Vector2(5, fs * 1.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if group.size() > 1:
			var r2 := cell_rect_f(vis_players[group[0]])
			var mine := group.has(human_id)
			var tag2 := ("나 외 %d명" % (group.size() - 1)) if mine else "%d명" % group.size()
			var fs2 := maxi(10, int(r2.size.x * 0.14))
			var w2 := font.get_string_size(tag2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x + 10
			var tr2 := Rect2(r2.get_center().x - w2 / 2, r2.position.y - fs2 * 0.9, w2, fs2 * 1.3)
			draw_rect(tr2, Style.seat(human_id) if mine else Style.INK)
			draw_rect(tr2, Color(Style.PAPER_HI, 0.9), false, 1.5)
			draw_string(font, tr2.position + Vector2(5, fs2 * 1.0), tag2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color.WHITE)


func _token(ctr: Vector2, rad: float, t: Texture2D, ring: Color, alpha: float, lift := 0.0, full := false) -> void:
	draw_circle(ctr + Vector2(2, 6 + lift), rad + 4, Color(0, 0, 0, 0.4 * alpha))
	draw_circle(ctr, rad + 4, Color(ring, alpha))
	draw_circle(ctr, rad + 1, Color(Style.PAPER_HI, alpha))
	draw_circle(ctr, rad - 1, Color(1, 1, 1, alpha))
	if t:
		var ir := rad if full else rad * 0.8
		draw_texture_rect(t, Rect2(ctr - Vector2(ir, ir), Vector2(ir, ir) * 2), false, Color(1, 1, 1, alpha))
