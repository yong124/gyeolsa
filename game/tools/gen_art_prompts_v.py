"""V단계(연출) 그림 24장의 GPT 프롬프트 → v2_구현/그림_프롬프트_V.md. 목록과 의도는 v2_구현/지시서/V_연출.md 1부."""
import io
import os
import re


def _style():
    """gen_art_prompts.py의 공통 그림체 문장(STYLE)을 그대로 읽는다 (그 파일은 import하면 바로 실행되므로 문장만 꺼냄)"""
    src = io.open(os.path.join(os.path.dirname(__file__), "gen_art_prompts.py"), encoding="utf-8").read()
    return eval(re.search(r"^STYLE = (\(.*?\))\n", src, re.S | re.M).group(1))


STYLE = _style()

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "v2_구현", "그림_프롬프트_V.md")

TILE = ("Composition: a square board-game map tile seen from directly above (top-down). The whole tile is filled with "
        "a flat tinted paper background in {color}, with a thin darker border. In the center, one bold woodblock-carved motif "
        "in cream and black ink, large and simple, readable at 60 pixels wide. No perspective scenery, no frame ornaments.")
CUT = ("Composition: a wide cinematic cutscene panel, 1940s Gyeongseong. Keep all important content inside the central "
       "horizontal band, because the top and bottom will be cropped to 16:9.")

# (번호, 저장 경로, 이름, 크기, 구도, 대상)
ITEMS = [
    (93, "tile/normal_1", "길 1", "1024×1024", TILE.format(color="muted moss green"), "a straight stone-paved road running vertically with faint cart ruts"),
    (94, "tile/normal_2", "길 2", "1024×1024", TILE.format(color="muted moss green"), "a crossroads of two narrow dirt streets with a small stone at the corner"),
    (95, "tile/normal_3", "길 3", "1024×1024", TILE.format(color="muted moss green"), "a curving alley road with a low tiled wall along one side"),
    (96, "tile/normal_4", "길 4", "1024×1024", TILE.format(color="muted moss green"), "a road with a small stone bridge over a narrow stream"),
    (97, "tile/event", "이벤트", "1024×1024", TILE.format(color="faded terracotta red"), "a folded paper rumor note with a small exclamation-shaped ink drop beside it"),
    (98, "tile/item", "아이템", "1024×1024", TILE.format(color="faded indigo blue"), "a cloth-wrapped bundle tied with string, seen from above"),
    (99, "tile/check", "검문소", "1024×1024", TILE.format(color="dark umber brown"), "a striped wooden barrier gate with a small sentry box"),
    (100, "tile/supply", "보급", "1024×1024", TILE.format(color="burnt orange"), "an open wooden crate with straw and a round canister bomb inside"),
    (101, "tile/alley", "골목", "1024×1024", TILE.format(color="warm grey"), "a narrow zigzag back alley between dark rooftops, a hiding nook"),
    (102, "tile/watchtower", "감시탑", "1024×1024", TILE.format(color="brick red"), "a wooden watchtower seen from above with a searchlight beam crossing the tile"),
    (103, "tile/market", "장터", "1024×1024", TILE.format(color="mustard ochre"), "market stalls with awnings and baskets of goods seen from above"),
    (104, "tile/tavern", "주막", "1024×1024", TILE.format(color="muted plum purple"), "a low wooden table with a rice-wine jug and two bowls"),
    (105, "tile/base_prison", "거점 · 서대문형무소", "1024×1024", TILE.format(color="near-black ink"), "a fortress-like brick prison seen from above with a central watchtower and cell blocks"),
    (106, "tile/base_barracks", "거점 · 일본군영", "1024×1024", TILE.format(color="near-black ink"), "an army barracks compound seen from above with rows of buildings and barbed wire"),
    (107, "tile/base_police_hq", "거점 · 종로경찰서", "1024×1024", TILE.format(color="near-black ink"), "a square colonial police station building seen from above with a courtyard"),
    (108, "tile/base_gg", "거점 · 조선총독부", "1024×1024", TILE.format(color="near-black ink"), "a massive domed stone government building seen from above"),
    (109, "tile/start", "출발점", "1024×1024", TILE.format(color="aged cream"), "a small hidden courtyard house seen from above, a lamp glowing, the meeting place of the resistance"),
    (110, "tile/back", "덮인 칸 (뒷면)", "1024×1024", TILE.format(color="pale parchment with a faint old map pattern"), "a faint compass rose, very subtle, as the unrevealed back of a tile"),
    (111, "screen/desk", "책상 배경", "1536×1024", "Composition: a wide, dim top-down view of an old wooden desk at night, papers, a map corner, an oil lamp glow at one edge; the center must stay calm and empty because game panels cover it. Will be cropped to 16:9.",
     "a resistance operation desk in 1945 Gyeongseong"),
    (112, "cut/opening_1", "오프닝 1 · 1945년 8월 경성", "1536×1024", CUT, "a crowded 1945 Gyeongseong street at dusk under colonial rule, streetcar, police in white uniforms watching passers-by, tense quiet"),
    (113, "cut/opening_2", "오프닝 2 · 결사", "1536×1024", CUT, "four resistance members from different backgrounds (a soldier, a hunter in hanbok, a woman in a 1930s dress, a printer) gathered around a table with a map under one oil lamp in a hidden room"),
    (114, "cut/opening_3", "오프닝 3 · 표적", "1536×1024", CUT, "the four targets of the city at night seen from a hill: a prison, an army barracks, a police station and a domed government building, linked by faint ink lines on a map overlay"),
    (115, "cut/opening_4", "오프닝 4 · 열하루", "1536×1024", CUT, "hands of four people stacked together over the map in a vow, a calendar on the wall with eleven days, lamp light"),
    (116, "cut/jail", "투옥", "1536×1024", CUT, "a silhouette of a captured agent behind iron bars in a dim cell, a single shaft of light, dignified not violent"),
]


def main():
    out = ["# 그림 프롬프트 · V단계 연출 (GPT 이미지 생성용)\n",
           "> 목록과 의도는 `지시서/V_연출.md` 1부. 쓰는 법은 `그림_프롬프트_GPT.md`와 같다(기준 그림 첨부, 한 장씩, 같은 공통 그림체).",
           "> 타일은 **보드에서 60px 안팎**으로 보인다. 색이 칸 종류를 알려 주므로 배경색을 꼭 지킨다.\n"]
    for no, path, name, size, comp, subject in ITEMS:
        prompt = "Create an illustration. " + STYLE + "\n" + comp + "\nSubject: " + subject + "."
        crop = "그대로" if size == "1024×1024" else "16:9로 위아래를 자름"
        out.append("### %03d · `%s` · %s" % (no, path, name))
        out.append("크기 **%s** · 넣을 때 %s\n" % (size + (" (정사각)" if size == "1024×1024" else " (가로)"), crop))
        out.append("```\n" + prompt + "\n```\n")
    io.open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(len(ITEMS))


if __name__ == "__main__":
    main()
