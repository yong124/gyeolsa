"""UI 재질 텍스처 생성 (종이 패널, 책상 배경).

실행: python game/tools/gen_ui_art.py
결과: game/assets/ui/paper_panel.png (9-slice, 그림자 포함), paper_tile.png (이음새 없는 종이),
      desk.png (게임 배경), paper_card.png (카드 앞면 9-slice)
"""
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


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    tile = paper_tile(256)
    save(tile, "paper_tile.png")
    panel(tile, 512, 16, 22, "paper_panel.png")
    panel(tile, 120, 8, 10, "paper_card.png", radius=5)
    desk()
