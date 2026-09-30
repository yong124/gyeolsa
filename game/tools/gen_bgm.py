"""배경음 합성기. 외부 음원 없이 numpy로 만든 반복(loop)용 곡 3개.

실행: python tools/gen_bgm.py  →  assets/music/{main,tension,ending}.wav
- main: 평상시. D단조 5음계 드론 + 패드 + 가야금풍 뜯는 소리
- tension: 경계 3단계. 심장 박동 같은 북 + 불협 드론 + 초침
- ending: 엔딩. G장조 5음계 패드 + 종소리 선율
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")
rng = np.random.default_rng(815)


def note(n):
    """MIDI 번호 → 주파수"""
    return 440.0 * 2 ** ((n - 69) / 12)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def place(buf, clip, at):
    i = int(at * SR) % len(buf)
    end = i + len(clip)
    if end <= len(buf):
        buf[i:end] += clip
    else:  # 끝을 넘으면 앞으로 감아 붙인다 (이음매 없는 반복)
        k = len(buf) - i
        buf[i:] += clip[:k]
        buf[: len(clip) - k] += clip[k:]


def pluck(freq, sec, bright=0.5):
    """카플러스-스트롱 현 뜯는 소리 (가야금 느낌)"""
    n = int(SR * sec)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period) * bright
    out = np.empty(n)
    for i in range(n):
        v = buf[i % period]
        out[i] = v
        buf[i % period] = 0.498 * (v + buf[(i + 1) % period])
    # 농현(떨림) 느낌으로 살짝 음정 흔들기 대신 끝을 부드럽게
    out *= np.exp(-np.arange(n) / (SR * sec * 0.45))
    return out


def pad(freqs, sec, cutoff=0.02):
    x = t(sec)
    s = np.zeros_like(x)
    for f in freqs:
        for det in (-0.25, 0.25):
            ph = rng.uniform(0, 2 * np.pi)
            saw = 2 * ((x * (f + det) + ph / (2 * np.pi)) % 1.0) - 1
            s += saw
    s = lowpass(s / (len(freqs) * 2), cutoff)
    env = np.sin(np.pi * np.clip(x / sec, 0, 1)) ** 1.5
    return s * env


def drone(freqs, sec, wobble=0.07):
    x = t(sec)
    s = np.zeros_like(x)
    for f in freqs:
        s += np.sin(2 * np.pi * f * x + 0.3 * np.sin(2 * np.pi * wobble * x))
        s += 0.3 * np.sin(2 * np.pi * f * 2 * x)
    return s / len(freqs)


def bell(freq, sec, decay):
    x = t(sec)
    s = np.sin(2 * np.pi * freq * x) + 0.4 * np.sin(2 * np.pi * freq * 2.01 * x) + 0.15 * np.sin(2 * np.pi * freq * 3.02 * x)
    return s * np.exp(-x / decay) * np.clip(x / 0.005, 0, 1)


def drum(sec=0.5, pitch=55):
    x = t(sec)
    f = pitch * (1 + 2.5 * np.exp(-x / 0.03))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-x / 0.18) + 0.2 * lowpass(rng.normal(0, 1, len(x)), 0.05) * np.exp(-x / 0.05)


def save(name, x, gain=0.55):
    # 반복 이음매: 처음과 끝 0.05초를 살짝 줄여 튐 방지
    n = int(SR * 0.05)
    x[:n] *= np.linspace(0.6, 1, n)
    x[-n:] *= np.linspace(1, 0.6, n)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(name, f"{len(x) / SR:.0f}s")


def main_theme():
    L = 64.0
    buf = np.zeros(int(SR * L))
    buf += 0.35 * drone([note(38), note(45)], L)                     # D2, A2
    chords = [[62, 65, 69], [60, 65, 67], [62, 67, 70], [57, 62, 65]]  # Dm 계열 5음계 화음
    for i in range(8):
        place(buf, 0.3 * pad([note(n) for n in chords[i % 4]], 9.0), i * 8.0 - 0.5)
    scale = [62, 65, 67, 69, 72, 74, 77]                              # D F G A C D F
    at = 1.0
    while at < L - 1:
        n = scale[rng.integers(len(scale))]
        place(buf, 0.45 * pluck(note(n), 2.2), at)
        if rng.random() < 0.3:                                          # 가끔 두 음을 잇달아
            place(buf, 0.3 * pluck(note(n - 5 if n > 65 else n + 3), 1.8), at + 0.25)
        at += rng.choice([1.0, 1.5, 2.0, 3.0])
    return buf


def tension_theme():
    L = 32.0
    buf = np.zeros(int(SR * L))
    buf += 0.3 * drone([note(38), note(39)], L, wobble=0.25)          # D2 + Eb2 불협
    beat = 60 / 72
    k = 0.0
    while k < L:
        place(buf, 0.9 * drum(), k)
        place(buf, 0.55 * drum(pitch=50), k + beat * 0.32)             # 심장 박동 두 번
        k += beat * 2
    tick = np.sin(2 * np.pi * 2400 * t(0.02)) * np.exp(-t(0.02) / 0.004)
    for i in range(int(L)):
        place(buf, 0.12 * tick, i + 0.5)
    for i in range(4):
        place(buf, 0.25 * pad([note(50), note(51), note(57)], 7.5, 0.01), i * 8.0)
    return buf


def ending_theme():
    L = 48.0
    buf = np.zeros(int(SR * L))
    chords = [[55, 59, 62], [60, 64, 67], [57, 62, 64], [55, 59, 62]]  # G 장조 5음계 화음
    for i in range(6):
        place(buf, 0.35 * pad([note(n) for n in chords[i % 4]], 9.0, 0.03), i * 8.0 - 0.5)
    buf += 0.2 * drone([note(43)], L, wobble=0.05)
    melody = [74, 71, 69, 67, 69, 71, 74, 76, 74, 71, 69, 67, 64, 67, 69, 67]
    for i, n in enumerate(melody):
        place(buf, 0.35 * bell(note(n), 2.8, 0.9), 2.0 + i * 2.75)
    return buf


if __name__ == "__main__":
    save("main", main_theme())
    save("tension", tension_theme())
    save("ending", ending_theme())
