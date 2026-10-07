"""그림 원본(그림_원본/, git 밖) → 게임용 그림 (game/assets/art/**.webp).

v2_구현/지시서/R_그림.md 1.2절 표대로 비율에 맞게 자르고 줄여 WebP(품질 80)로 쓴다.
- 초상은 3:4로 자를 때 위를 30%, 아래를 70% 잘라 얼굴을 남긴다. 보드 말용 동그라미 그림(art/token/{id}.webp)도 만든다.
- 세력 문양은 투명 PNG 256×256으로 assets/ui/faction_*.png를 덮어쓴다.
- 원본이 없는 id는 건너뛰고 목록만 알린다. 다시 돌려도 같은 결과.

실행: python game/tools/prep_art.py
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import gen_art  # noqa: E402  원본 경로와 게임 id를 잇는 parse()

GAME = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ART = os.path.join(GAME, "assets", "art")

# 폴더 → (가로:세로 비율, 넣을 크기)
SPEC = {
    "char": ((3, 4), (600, 800)),
    "mission": ((1, 1), (512, 512)),
    "op": ((1, 1), (512, 512)),
    "item": ((4, 3), (640, 480)),   # 큰 카드 그림 띠 폭(약 420px)의 1.5배
    "event": ((4, 3), (640, 480)),
    "threat": ((4, 3), (640, 480)),
    "scene": ((4, 3), (640, 480)),
    "strike": ((16, 9), (1280, 720)),   # 화면 가운데 크게 · 엔딩 머리 (논리 화면 1600 폭에서 충분)
    "ending": ((16, 9), (1280, 720)),
    "art": ((2, 3), (400, 600)),     # 사연 카드 뒷면
    "tile": ((1, 1), (320, 320)),    # 보드 칸 (V단계): 확대해도 깨지지 않게 칸 크기의 2배 남짓
    "screen": ((3, 2), (1536, 1024)),  # 책상 배경
    "cut": ((3, 2), (1536, 1024)),   # 오프닝 · 투옥 컷신
}


def crop_to(im, ratio, top_bias=0.5):
    """비율에 맞게 자른다. top_bias: 세로로 자를 때 위에서 잘라 낼 몫 (0.5 = 가운데)"""
    w, h = im.size
    rw, rh = ratio
    if w * rh > h * rw:   # 너무 넓다 → 양옆을 자름
        nw = h * rw // rh
        x = (w - nw) // 2
        return im.crop((x, 0, x + nw, h))
    nh = w * rh // rw     # 너무 높다 → 위아래를 자름
    y = int((h - nh) * top_bias)
    return im.crop((0, y, w, y + nh))


def token(portrait, out, size=256):
    """보드 말: 3:4 초상의 위쪽(얼굴)을 정사각으로 잘라 동그라미로"""
    w, h = portrait.size
    side = w
    y = int(h * 0.12)
    sq = portrait.crop((0, y, side, y + side)).resize((size, size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    sq.putalpha(mask.resize((size, size), Image.LANCZOS))
    sq.save(out, "WEBP", quality=85)


def main():
    made, missing = 0, []
    for it in gen_art.parse():
        src = it["out"]
        parts = it["path"].split("/")
        if not os.path.exists(src):
            missing.append("%03d %s" % (it["no"], it["path"]))
            continue
        im = Image.open(src)
        if parts[0] == "assets":   # 세력 문양: 투명 PNG로 ui 폴더에 덮어씀
            dst = os.path.join(GAME, *parts) + ".png"
            im.convert("RGBA").resize((256, 256), Image.LANCZOS).save(dst, "PNG")
            made += 1
            continue
        folder, gid = (parts[0], parts[-1])
        ratio, size = SPEC[folder]
        im = crop_to(im.convert("RGB"), ratio, 0.3 if folder == "char" else 0.5).resize(size, Image.LANCZOS)
        sub = "" if folder == "art" else folder
        os.makedirs(os.path.join(ART, sub), exist_ok=True)
        im.save(os.path.join(ART, sub, gid + ".webp"), "WEBP", quality=76)
        if folder == "char":
            os.makedirs(os.path.join(ART, "token"), exist_ok=True)
            token(im, os.path.join(ART, "token", gid + ".webp"))
        made += 1
    # 일반 길 칸은 규칙상 사방으로 다 이어진다. 일자·굽은 길·다리 그림(normal_1·3·4)은 「옆으로 못 간다」로 읽히므로
    # 사방이 뚫린 십자 길(normal_2)을 90°씩 돌린 네 장으로 덮어쓴다 (칸마다 모양만 조금 달라 보이게)
    cross = os.path.join(ART, "tile", "normal_2.webp")
    if os.path.exists(cross):
        base = Image.open(cross).convert("RGB")
        for k in range(4):
            base.rotate(-90 * k).save(os.path.join(ART, "tile", "normal_%d.webp" % (k + 1)), "WEBP", quality=76)
    total = 0
    for dp, _, fs in os.walk(ART):
        total += sum(os.path.getsize(os.path.join(dp, f)) for f in fs if f.endswith(".webp"))
    print("만듦 %d · 원본 없음 %d · assets/art 합계 %.1fMB" % (made, len(missing), total / 1e6))
    for m in missing:
        print("  없음:", m)


if __name__ == "__main__":
    main()
