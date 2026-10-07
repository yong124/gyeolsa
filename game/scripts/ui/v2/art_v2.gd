class_name ArtV2
extends RefCounted
## 그림 찾기 (v2_구현/지시서/R_그림.md 2부). res://assets/art/{kind}/{id}.webp가 있으면 그것, 없으면 fallback.
## 그림이 일부만 들어와도 게임이 돌아가게 한다. 원본 → WebP 변환은 tools/prep_art.py.

static var _cache := {}
static var disabled := false   # 시험: 그림이 하나도 없을 때처럼 늘 fallback을 돌려준다 (v2uitest noart)


static func get_tex(kind: String, id: String, fallback: Texture2D = null) -> Texture2D:
	var key := kind + "/" + id
	if not _cache.has(key):
		var found: Texture2D = null
		for ext in ["webp", "png"]:
			var path := "res://assets/art/%s.%s" % [key, ext] if kind != "" else "res://assets/art/%s.%s" % [id, ext]
			if ResourceLoader.exists(path):
				found = load(path)
				break
		_cache[key] = found
	var t: Texture2D = null if disabled else _cache[key]
	return t if t != null else fallback


static func has(kind: String, id: String) -> bool:
	return get_tex(kind, id) != null
