"""한글 글꼴 서브셋: 게임에 나오는 글자 + KS X 1001 한글 2,350자 + 기본 기호만 남긴다 (웹 빌드 크기, 지시서 W 2절).

원본 가변 글꼴(NotoSansKR-VF.ttf, NotoSerifKR-VF.ttf)은 그대로 두고 *-Sub.ttf를 만든다. 굵기 축(wght)은 남긴다.
웹 내보내기는 원본을 빼고(export_filter) 서브셋만 넣는다. 글자를 새로 쓰면 다시 돌린다.

실행: python game/tools/subset_fonts.py
"""
import glob
import os

from fontTools import subset
from fontTools.ttLib import TTFont

GAME = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FONTS = os.path.join(GAME, "assets", "fonts")


def ksx1001_hangul():
    out = []
    for b1 in range(0xB0, 0xC9):
        for b2 in range(0xA1, 0xFF):
            try:
                out.append(bytes([b1, b2]).decode("euc-kr"))
            except UnicodeDecodeError:
                pass
    return out


def game_chars():
    chars = set()
    pats = ["data/**/*.json", "scripts/**/*.gd", "scenes/**/*.tscn", "project.godot"]
    for pat in pats:
        for f in glob.glob(os.path.join(GAME, pat), recursive=True):
            try:
                chars.update(open(f, encoding="utf-8").read())
            except UnicodeDecodeError:
                pass
    return chars


def main():
    chars = set(game_chars())
    chars.update(ksx1001_hangul())
    chars.update(chr(c) for c in range(0x20, 0x7F))               # ASCII
    chars.update(chr(c) for c in range(0x3131, 0x3164))           # 한글 호환 자모 (ㄱ ~ ㅣ)
    chars.update("·…—–―‘’“”「」『』《》〈〉○●◎★☆✓✗×÷±→←↑↓▸▴▾▲▼◆◇■□※%~°₩")
    chars = {c for c in chars if c.isprintable() or c == " "}
    text = "".join(sorted(chars))
    print("글자 수", len(chars))
    for src, dst in [("NotoSansKR-VF.ttf", "NotoSansKR-Sub.ttf"), ("NotoSerifKR-VF.ttf", "NotoSerifKR-Sub.ttf")]:
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.hinting = False
        opts.notdef_outline = True
        opts.name_IDs = ["*"]
        opts.name_languages = ["*"]
        font = TTFont(os.path.join(FONTS, src))
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        out = os.path.join(FONTS, dst)
        font.save(out)
        print("%s → %s  %.1f MB → %.1f MB" % (src, dst, os.path.getsize(os.path.join(FONTS, src)) / 1e6, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    main()
