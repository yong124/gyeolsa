extends SceneTree
## 번역 검사: 코드의 Loc.t("…")와 데이터(JSON)의 한글 문구가 모두 data/i18n/<언어>.json에 있고,
## 자리표시자(%s, %d, %+d, %%, {이름})가 원문과 같은 순서인지 확인한다.
## 실행: godot --headless --path game --script res://tests/loc_test.gd


func _init() -> void:
	var failures := 0
	var hangul := RegEx.create_from_string("[가-힣]")
	var spec := RegEx.create_from_string("%[+]?[ds%]|\\{\\w+\\}")
	var lit := RegEx.create_from_string("Loc\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var keys := {}
	# 코드
	for dir in ["res://scripts/core/", "res://scripts/ui/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + f)
			for m in lit.search_all(src):
				var s: String = m.get_string(1).c_unescape()
				if hangul.search(s):
					keys[s] = f
	# 데이터
	for f in ["balance", "factions", "cards", "text", "scenarios", "achievements"]:
		_walk(JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % f)), keys, f, hangul)
	for lang in Loc.LANGS:
		if lang == "ko":
			continue
		var dict = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/%s.json" % lang))
		var missing := 0
		for k in keys:
			if not dict.has(k):
				missing += 1
				failures += 1
				if missing <= 10:
					push_error("[%s] 번역 없음 (%s): %s" % [lang, keys[k], k.left(60)])
				continue
			var a := spec.search_all(k).map(func(x): return x.get_string())
			var b := spec.search_all(dict[k]).map(func(x): return x.get_string())
			if a != b:
				failures += 1
				push_error("[%s] 자리표시자 다름: %s %s → %s" % [lang, k.left(40), a, b])
		print("%s: 문구 %d개, 번역 없음 %d개" % [lang, keys.size(), missing])
	quit(1 if failures > 0 else 0)


func _walk(v: Variant, keys: Dictionary, src: String, hangul: RegEx) -> void:
	match typeof(v):
		TYPE_STRING:
			if hangul.search(v):
				keys[v] = src
		TYPE_ARRAY:
			for x in v:
				_walk(x, keys, src, hangul)
		TYPE_DICTIONARY:
			for k in v:
				if not str(k).begins_with("_"):
					_walk(v[k], keys, src, hangul)
