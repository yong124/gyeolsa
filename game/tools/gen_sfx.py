"""효과음 합성기. 외부 음원 없이 numpy로 만든다 (라이선스 걱정 없음).

실행: python tools/gen_sfx.py  →  assets/sfx/*.wav
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(1945)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.005, decay=0.2):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / decay)


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def bell(freq, sec, decay, partials=((1, 1.0), (2.01, 0.4), (3.02, 0.2), (4.1, 0.1))):
    x = t(sec)
    s = sum(a * np.sin(2 * np.pi * freq * m * x) for m, a in partials)
    return s * env(len(x), 0.004, decay)


def place(buf, clip, at):
    i = int(at * SR)
    buf[i:i + len(clip)] += clip[: max(0, len(buf) - i)]


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(name, f"{len(x) / SR:.2f}s")


def dice():
    # 나무 탁자 위를 구르는 주사위: 짧은 딸깍 소리가 점점 잦아든다
    buf = np.zeros(int(SR * 0.7))
    at = 0.0
    for k in range(9):
        n = int(SR * 0.03)
        click = rng.normal(0, 1, n) * env(n, 0.001, 0.006)
        click += 0.6 * np.sin(2 * np.pi * rng.uniform(900, 1600) * t(0.03)) * env(n, 0.001, 0.01)
        place(buf, click * (1.0 - k * 0.07), at)
        at += 0.035 + k * 0.012 + rng.uniform(0, 0.02)
    return lowpass(buf, 0.5)


def step():
    x = t(0.09)
    thud = np.sin(2 * np.pi * (140 - 400 * x) * x) * env(len(x), 0.002, 0.03)
    noise = lowpass(rng.normal(0, 1, len(x)), 0.08) * env(len(x), 0.001, 0.02)
    return thud + 0.6 * noise


def flip():
    # 종이 타일을 뒤집는 사각 소리
    x = t(0.18)
    n = rng.normal(0, 1, len(x))
    n = n - lowpass(n, 0.15)  # 고음만
    e = np.sin(np.pi * np.clip(x / 0.18, 0, 1)) ** 2
    buf = n * e
    place(buf, 0.4 * step(), 0.1)
    return buf


def card():
    x = t(0.32)
    n = rng.normal(0, 1, len(x))
    n = n - lowpass(n, 0.25)
    e = np.clip(x / 0.05, 0, 1) * np.exp(-np.clip(x - 0.05, 0, None) / 0.08)
    return n * e


def success():
    buf = np.zeros(int(SR * 1.1))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        place(buf, bell(f, 0.8, 0.35), i * 0.09)
    return buf


def fail():
    buf = np.zeros(int(SR * 0.9))
    for i, f in enumerate([311.1, 233.1]):
        x = t(0.5)
        tone = np.sign(np.sin(2 * np.pi * f * x)) * 0.3 + np.sin(2 * np.pi * f * x)
        place(buf, lowpass(tone * env(len(x), 0.01, 0.2), 0.2), i * 0.22)
    return buf


def whistle():
    # 순사의 호루라기: 떨리는 높은 음 두 번
    buf = np.zeros(int(SR * 0.75))
    for at, dur in [(0.0, 0.22), (0.3, 0.38)]:
        x = t(dur)
        f = 2900 + 180 * np.sin(2 * np.pi * 28 * x)
        ph = 2 * np.pi * np.cumsum(f) / SR
        tone = np.sin(ph) + 0.15 * rng.normal(0, 1, len(x))
        e = np.clip(x / 0.02, 0, 1) * np.clip((dur - x) / 0.04, 0, 1)
        place(buf, tone * e, at)
    return buf


def day():
    # 절의 종소리처럼 낮게 울리는 하루의 시작
    partials = ((1, 1.0), (2.76, 0.5), (5.4, 0.25), (8.9, 0.12))
    buf = bell(110, 2.6, 1.1, partials)
    place(buf, 0.5 * bell(220.5, 2.0, 0.7), 0.0)
    return buf


def alert():
    # 일제 동향: 낮고 불길한 두 음
    buf = np.zeros(int(SR * 1.2))
    for i, f in enumerate([146.8, 138.6]):
        x = t(0.55)
        tone = np.sin(2 * np.pi * f * x) + 0.5 * np.sin(2 * np.pi * f * 2 * x) + 0.3 * np.sign(np.sin(2 * np.pi * f * x))
        place(buf, lowpass(tone * env(len(x), 0.03, 0.35), 0.1), i * 0.4)
    return buf


def click():
    x = t(0.03)
    return np.sin(2 * np.pi * 1800 * x) * env(len(x), 0.001, 0.005)


def score():
    buf = np.zeros(int(SR * 1.3))
    for i, f in enumerate([392.0, 523.25, 659.25, 783.99, 1046.5]):
        place(buf, bell(f, 0.9, 0.45), i * 0.07)
    place(buf, bell(1046.5, 1.0, 0.6) * 0.8, 0.4)
    return buf


# ------------------------------------------------------------------ V 연출 (2026-10-08)

def noise(sec):
    return rng.standard_normal(int(SR * sec))


def stamp():
    # 도장 「쾅」: 낮은 나무 울림 + 종이에 닿는 짧은 철썩
    x = t(0.45)
    body = np.sin(2 * np.pi * 70 * x) * env(len(x), 0.002, 0.09) + 0.5 * np.sin(2 * np.pi * 140 * x) * env(len(x), 0.002, 0.05)
    slap = lowpass(noise(0.45), 0.25) * env(len(x), 0.001, 0.025)
    return body + 0.8 * slap


def whoosh():
    # 컷인 「휙」: 바람이 스치며 커졌다 사라진다 (높낮이가 올라감)
    sec = 0.5
    n = noise(sec)
    x = t(sec)
    shape = np.sin(np.pi * np.clip(x / sec, 0, 1)) ** 2
    lo = lowpass(n, 0.05)
    hi = lowpass(n, 0.35) - lowpass(n, 0.08)
    mix = lo * (1 - x / sec) + hi * (x / sec)
    return mix * shape


def boom():
    # 먹 전환: 깊게 번지는 울림
    sec = 1.4
    x = t(sec)
    f = 55 * np.exp(-x * 0.8)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.08, 0.6)
    air = lowpass(noise(sec), 0.03) * env(len(x), 0.2, 0.5)
    return tone + 0.6 * air


def clang():
    # 감옥 철문: 쇠가 부딪히는 낮은 울림 (어긋난 배음)
    return bell(110, 1.6, 0.7, ((1, 1.0), (2.76, 0.6), (5.4, 0.35), (8.9, 0.2))) + 0.5 * lowpass(noise(1.6), 0.3) * env(int(SR * 1.6), 0.001, 0.02)


def spark():
    # 결행 준비 불꽃: 타닥타닥 튀는 소리
    buf = np.zeros(int(SR * 0.6))
    at = 0.0
    while at < 0.5:
        x = t(0.02)
        place(buf, noise(0.02) * env(len(x), 0.0005, 0.004) * rng.uniform(0.4, 1.0), at)
        at += rng.uniform(0.015, 0.06)
    return buf + 0.3 * bell(1568, 0.6, 0.25)


def cheer():
    # 만세 삼창: 군중이 세 번 크게 외친다 (사람 목소리 대역의 소음 + 낮은 웅성거림)
    sec = 3.6
    buf = np.zeros(int(SR * sec))
    for k in range(3):
        at = 0.15 + k * 1.15
        x = t(1.0)
        swell = np.sin(np.pi * np.clip(x / 0.9, 0, 1)) ** 1.5
        voice = lowpass(noise(1.0), 0.18) - lowpass(noise(1.0), 0.03)
        for f in (180, 230, 300):   # 여러 사람의 「만」 모음 비슷한 울림
            voice += 0.15 * np.sin(2 * np.pi * (f + rng.uniform(-15, 15)) * x) * rng.uniform(0.5, 1.0)
        place(buf, voice * swell, at)
    return buf + 0.15 * lowpass(noise(sec), 0.05)


def heart():
    # 심장 박동 (1.1초 한 바퀴, 반복 재생): 쿵-쿵
    buf = np.zeros(int(SR * 1.1))
    for at, g in ((0.0, 1.0), (0.24, 0.7)):
        x = t(0.18)
        place(buf, g * np.sin(2 * np.pi * 52 * x) * env(len(x), 0.004, 0.06), at)
    return buf


def rain():
    # 빗소리 (3초, 반복 재생): 쏴아 + 빗방울. 끝과 처음이 이어지게 양 끝을 섞는다
    sec = 3.0
    base = lowpass(noise(sec), 0.12) - lowpass(noise(sec), 0.02)
    for _ in range(140):
        x = t(0.012)
        place(base, noise(0.012) * env(len(x), 0.0003, 0.003) * rng.uniform(0.5, 1.5), rng.uniform(0, sec - 0.02))
    fade = int(SR * 0.3)
    w = np.linspace(0, 1, fade)
    base[:fade] = base[:fade] * w + base[-fade:] * (1 - w)
    return base[:-fade]


def siren():
    # 공습 사이렌 (4초, 반복 재생): 천천히 오르내림
    sec = 4.0
    x = t(sec)
    f = 420 + 160 * np.sin(2 * np.pi * x / sec - np.pi / 2)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)


ALL = [("dice", dice, 0.7), ("step", step, 0.5), ("flip", flip, 0.5),
       ("card", card, 0.5), ("success", success, 0.7), ("fail", fail, 0.6),
       ("whistle", whistle, 0.45), ("day", day, 0.7), ("alert", alert, 0.7),
       ("click", click, 0.35), ("score", score, 0.7),
       # V 연출
       ("stamp", stamp, 0.8), ("whoosh", whoosh, 0.5), ("boom", boom, 0.75), ("clang", clang, 0.6),
       ("spark", spark, 0.45), ("cheer", cheer, 0.6), ("heart", heart, 0.8), ("rain", rain, 0.35), ("siren", siren, 0.3)]

if __name__ == "__main__":
    # python tools/gen_sfx.py [이름 ...]  — 이름을 주면 그것만 만든다 (기존 소리를 다시 쓰지 않게)
    import sys
    only = set(sys.argv[1:])
    for name, fn, gain in ALL:
        if not only or name in only:
            save(name, fn(), gain)
