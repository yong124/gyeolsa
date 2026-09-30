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


if __name__ == "__main__":
    for name, fn, gain in [("dice", dice, 0.7), ("step", step, 0.5), ("flip", flip, 0.5),
                           ("card", card, 0.5), ("success", success, 0.7), ("fail", fail, 0.6),
                           ("whistle", whistle, 0.45), ("day", day, 0.7), ("alert", alert, 0.7),
                           ("click", click, 0.35), ("score", score, 0.7)]:
        save(name, fn(), gain)
