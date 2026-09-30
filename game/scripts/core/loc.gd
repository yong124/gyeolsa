class_name Loc
extends RefCounted
## 번역. 한국어 원문을 키로 하는 사전(data/i18n/<언어>.json)에서 찾는다. 사전에 없으면 원문 그대로.
## 코드의 문구는 Loc.t("…")로, 데이터(JSON)의 문구는 GameData가 불러올 때 translate_tree()로 바꾼다.
## 문구만 바꾸고 규칙 판단에는 쓰지 않으므로, 언어가 달라도 같은 시드·액션이면 같은 결과가 나온다.

const LANGS := {"ko": "한국어", "en": "English"}
const MONTHS_EN := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

static var lang := "ko"
static var _dict: Dictionary
static var _loaded := ""


static func set_lang(l: String) -> void:
	lang = l if LANGS.has(l) else "ko"


static func _table() -> Dictionary:
	if _loaded != lang:
		_loaded = lang
		_dict = {}
		var path := "res://data/i18n/%s.json" % lang
		if lang != "ko" and FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				_dict = parsed
				_dict.erase("_comment")
	return _dict


static func t(s: String) -> String:
	if lang == "ko":
		return s
	return _table().get(s, s)


static func translate_tree(v: Variant) -> Variant:
	## JSON 트리의 문자열 값을 번역한다 ("_"로 시작하는 키와 id류 값은 사전에 없으니 그대로 남는다)
	if lang == "ko":
		return v
	match typeof(v):
		TYPE_STRING:
			return t(v)
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(translate_tree(x))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = v[k] if str(k).begins_with("_") else translate_tree(v[k])
			return out
	return v


static func month(m: int) -> String:
	return MONTHS_EN[m] if lang == "en" and m >= 1 and m <= 12 else "%d월" % m


static func date(m: int, d: int) -> String:
	return "%s %d" % [MONTHS_EN[m], d] if lang == "en" and m >= 1 and m <= 12 else "%d월 %d일" % [m, d]
