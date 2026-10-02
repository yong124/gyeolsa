"""UI 재질 텍스처 생성 (종이 패널, 책상 배경).

실행: python game/tools/gen_ui_art.py
새 타일 그림: python game/tools/gen_ui_art.py tiles  (골목·감시탑·장터·주막: game/assets/tiles/<타일 종류>.png)
결과: game/assets/ui/paper_panel.png (9-slice, 그림자 포함), paper_tile.png (이음새 없는 종이),
      desk.png (게임 배경), paper_card.png (카드 앞면 9-slice)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"
rng = np.random.default_rng(1945)

PAPER = np.array([234, 223, 196], float)
PAPER_LO = np.array([214, 196, 158], float)


def periodic_noise(n: int, scale: float) -> np.ndarray:
    """주기적인(이음새 없는) 저주파 잡음, 0..1"""
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx ** 2 + fy ** 2)
    r[0, 0] = 1.0
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / (r ** scale)
    spec[0, 0] = 0
    img = np.real(np.fft.ifft2(spec))
    img -= img.min()
    return img / img.max()


def paper_tile(n: int = 256) -> np.ndarray:
    """종이 결: 큰 얼룩 + 섬유 + 잔점, RGB float"""
    blot = periodic_noise(n, 1.6)
    fiber = periodic_noise(n, 0.9)
    grain = rng.random((n, n))
    t = 0.55 * blot + 0.3 * fiber + 0.15 * grain
    t = (t - t.mean()) / (t.std() + 1e-6)
    base = PAPER[None, None, :] + (PAPER_LO - PAPER)[None, None, :] * np.clip(0.5 + 0.22 * t, 0, 1)[..., None]
    # 드문드문 얼룩 점
    spots = periodic_noise(n, 2.2)
    base -= (np.clip(spots - 0.82, 0, 1) * 90)[..., None] * np.array([0.6, 0.7, 0.9])
    return np.clip(base, 0, 255)


def save(arr: np.ndarray, name: str) -> None:
    Image.fromarray(arr.astype(np.uint8)).save(OUT / name)
    print("저장:", OUT / name)


def panel(tile: np.ndarray, size: int, shadow: int, edge: int, name: str, radius: int = 3) -> None:
    """가장자리가 살짝 어두운 종이 패널 + 바깥 그림자 (9-slice 원본)"""
    n = tile.shape[0]
    inner = size - 2 * shadow
    reps = inner // n + 2
    big = np.tile(tile, (reps, reps, 1))
    # 가운데(9-slice의 center)가 타일 원점과 맞도록 잘라 이어 붙였을 때 이음새가 없게 한다
    off = (n - (edge % n)) % n
    paper = big[off:off + inner, off:off + inner].copy()
    # 가장자리 어둡게 (edge 폭 안에서만)
    yy, xx = np.mgrid[0:inner, 0:inner]
    d = np.minimum(np.minimum(xx, yy), np.minimum(inner - 1 - xx, inner - 1 - yy)).astype(float)
    shade = np.clip(1 - d / edge, 0, 1) ** 2
    paper = paper * (1 - 0.22 * shade[..., None]) + np.array([90, 60, 30]) * 0.22 * shade[..., None] * 0.3
    rgba = np.zeros((size, size, 4), float)
    # 그림자
    sh = Image.new("L", (size, size), 0)
    sh.paste(255, (shadow, shadow + 4, size - shadow, size - shadow + 4))
    sh = sh.filter(ImageFilter.GaussianBlur(shadow / 2.2))
    rgba[..., 3] = np.array(sh, float) * 0.55
    rgba[shadow:size - shadow, shadow:size - shadow, :3] = paper
    rgba[shadow:size - shadow, shadow:size - shadow, 3] = 255
    # 모서리를 아주 살짝 둥글게
    for cy in (shadow, size - shadow - 1):
        for cx in (shadow, size - shadow - 1):
            for dy in range(radius):
                for dx in range(radius):
                    if dx + dy < radius - 1:
                        y = cy + (dy if cy == shadow else -dy)
                        x = cx + (dx if cx == shadow else -dx)
                        rgba[y, x] = rgba[min(max(y, 0), size - 1), min(max(x, 0), size - 1)] * 0
    Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA").save(OUT / name)
    print("저장:", OUT / name)


def desk(w: int = 1600, h: int = 900) -> None:
    """어두운 나무 책상: 결 + 가운데 조명"""
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    grain = periodic_noise(1024, 1.2)
    grain = np.array(Image.fromarray((grain * 255).astype(np.uint8)).resize((w // 6, h), Image.BILINEAR), float) / 255
    grain = np.array(Image.fromarray((grain * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR), float) / 255
    fine = rng.random((h, w))
    base = np.array([44, 33, 25], float)
    wood = base[None, None, :] * (0.78 + 0.35 * grain[..., None] + 0.05 * fine[..., None])
    stripes = 0.06 * np.sin(yy / 3.1 + grain * 18)[..., None]
    wood *= (1 + stripes)
    cx, cy = w * 0.42, h * 0.48
    r = np.sqrt(((xx - cx) / w) ** 2 + ((yy - cy) / h) ** 2)
    light = np.clip(1.25 - 1.3 * r, 0.45, 1.2)
    save(np.clip(wood * light[..., None], 0, 255), "desk.png")


TILE_OUT = Path(__file__).resolve().parent.parent / "assets" / "tiles"
TILE_SIZE = 472
SS = 3   # 선을 부드럽게 그리려 3배로 그린 뒤 줄인다


def _stroke(d, pts, w):
    """둥근 끝을 가진 굵은 선"""
    d.line(pts, fill=255, width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=255)


def _arc(d, box, a0, a1, w):
    d.arc(box, a0, a1, fill=255, width=w)


def _icon_alley(d, w):
    """골목: 양쪽 담장 사이로 난 좁은 길"""
    s = SS
    _stroke(d, [(130 * s, 380 * s), (190 * s, 110 * s)], w)    # 왼쪽 담
    _stroke(d, [(342 * s, 380 * s), (282 * s, 110 * s)], w)    # 오른쪽 담
    for k, y in enumerate((170, 240, 310)):                      # 벽돌 줄눈
        t = (y - 110) / 270.0
        xl = 190 - 60 * t
        xr = 282 + 60 * t
        _stroke(d, [(xl * s, y * s), ((xl - 34) * s, y * s)], int(w * 0.6))
        _stroke(d, [(xr * s, y * s), ((xr + 34) * s, y * s)], int(w * 0.6))
    _stroke(d, [(236 * s, 150 * s), (236 * s, 190 * s)], int(w * 0.6))   # 길 가운데 점선
    _stroke(d, [(236 * s, 240 * s), (236 * s, 290 * s)], int(w * 0.6))
    _stroke(d, [(236 * s, 330 * s), (236 * s, 370 * s)], int(w * 0.6))


def _icon_tower(d, w):
    """감시탑: 망루"""
    s = SS
    _stroke(d, [(180 * s, 200 * s), (150 * s, 390 * s)], w)     # 다리 둘
    _stroke(d, [(292 * s, 200 * s), (322 * s, 390 * s)], w)
    _stroke(d, [(168 * s, 290 * s), (304 * s, 290 * s)], int(w * 0.7))   # 가로대
    _stroke(d, [(160 * s, 340 * s), (312 * s, 340 * s)], int(w * 0.7))
    _stroke(d, [(150 * s, 200 * s), (322 * s, 200 * s)], w)    # 망루 바닥
    _stroke(d, [(150 * s, 200 * s), (150 * s, 130 * s), (322 * s, 130 * s), (322 * s, 200 * s)], w)   # 난간 방
    _stroke(d, [(128 * s, 130 * s), (236 * s, 60 * s), (344 * s, 130 * s)], w)   # 지붕
    d.ellipse((218 * s, 150 * s, 254 * s, 186 * s), fill=255)    # 감시하는 눈 (불빛)


def _icon_market(d, w):
    """장터: 차양 노점"""
    s = SS
    _stroke(d, [(110 * s, 200 * s), (150 * s, 100 * s), (322 * s, 100 * s), (362 * s, 200 * s)], w)   # 차양 윗선
    for k in range(4):                                                                                 # 차양 물결
        x0 = (110 + k * 63) * s
        _arc(d, (x0, 150 * s, x0 + 63 * s, 250 * s), 0, 180, w)
    _stroke(d, [(130 * s, 215 * s), (130 * s, 390 * s)], w)    # 기둥
    _stroke(d, [(342 * s, 215 * s), (342 * s, 390 * s)], w)
    _stroke(d, [(120 * s, 330 * s), (352 * s, 330 * s)], w)    # 판매대
    _stroke(d, [(160 * s, 330 * s), (160 * s, 390 * s)], int(w * 0.7))
    _stroke(d, [(312 * s, 330 * s), (312 * s, 390 * s)], int(w * 0.7))
    d.ellipse((205 * s, 262 * s, 265 * s, 322 * s), outline=255, width=int(w * 0.8))   # 항아리 (물건)


def _icon_tavern(d, w):
    """주막: 술병과 사발"""
    s = SS
    _stroke(d, [(176 * s, 90 * s), (176 * s, 170 * s)], w)     # 병 목
    _stroke(d, [(130 * s, 170 * s), (222 * s, 170 * s)], int(w * 0.8))
    _stroke(d, [(128 * s, 200 * s), (128 * s, 370 * s), (224 * s, 370 * s), (224 * s, 200 * s)], w)   # 병 몸
    _stroke(d, [(128 * s, 200 * s), (176 * s, 170 * s), (224 * s, 200 * s)], int(w * 0.8))
    _arc(d, (262 * s, 230 * s, 410 * s, 378 * s), 0, 180, w)   # 사발
    _stroke(d, [(262 * s, 304 * s), (410 * s, 304 * s)], int(w * 0.8))
    _stroke(d, [(310 * s, 378 * s), (362 * s, 378 * s)], int(w * 0.8))   # 굽
    _stroke(d, [(300 * s, 200 * s), (300 * s, 250 * s)], int(w * 0.5))   # 김
    _stroke(d, [(366 * s, 200 * s), (366 * s, 250 * s)], int(w * 0.5))


NEW_TILES = {
    "alley": ((122, 104, 84), _icon_alley),
    "watchtower": ((160, 72, 62), _icon_tower),
    "market": ((184, 137, 47), _icon_market),
    "tavern": ((106, 80, 124), _icon_tavern),
}


def new_tiles() -> None:
    """새 타일 4종: 지금 타일과 같은 모양 — 종이 결이 있는 색 바탕 + 흰 선 아이콘 + 흰 테두리"""
    n = TILE_SIZE
    margin = 10
    grain_big = periodic_noise(256, 1.4)
    grain_fine = rng.random((n, n))
    for name, (color, icon) in NEW_TILES.items():
        base = np.array(color, float)
        g = np.array(Image.fromarray((grain_big * 255).astype(np.uint8)).resize((n, n), Image.BILINEAR), float) / 255
        shade = 0.84 + 0.22 * g + 0.06 * (grain_fine - 0.5)
        fill = base[None, None, :] * shade[..., None]
        for k in range(26):   # 종이 잔 얼룩
            cx, cy = rng.integers(margin, n - margin, 2)
            fill[max(cy - 1, 0):cy + 2, max(cx - 4, 0):cx + 5] *= 0.72
        img = np.full((n, n, 4), 255.0)
        img[margin:n - margin, margin:n - margin, :3] = fill[margin:n - margin, margin:n - margin]
        mask = Image.new("L", (n * SS, n * SS), 0)
        from PIL import ImageDraw
        d = ImageDraw.Draw(mask)
        icon(d, int(20 * SS))
        mask = mask.resize((n, n), Image.LANCZOS)
        m = np.array(mask, float)[..., None] / 255.0
        img[..., :3] = img[..., :3] * (1 - m) + 255 * m
        Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA").save(TILE_OUT / f"{name}.png")
        print("저장:", TILE_OUT / f"{name}.png")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tiles":
        new_tiles()
        sys.exit(0)
    OUT.mkdir(parents=True, exist_ok=True)
    tile = paper_tile(256)
    save(tile, "paper_tile.png")
    panel(tile, 512, 16, 22, "paper_panel.png")
    panel(tile, 120, 8, 10, "paper_card.png", radius=5)
    desk()
