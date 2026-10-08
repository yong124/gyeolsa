"""itch.io용 짧은 GIF: tour gif가 찍은 낱장(f_0000.png …)을 하나로 묶는다.

실행: python game/tools/make_gif.py <낱장 폴더> <출력.gif> [폭=720] [한 장 ms=150]
"""
import glob
import os
import sys

from PIL import Image


def main():
    src = sys.argv[1]
    out = sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 720
    ms = int(sys.argv[4]) if len(sys.argv) > 4 else 150
    files = sorted(glob.glob(os.path.join(src, "f_*.png")))
    frames = []
    for f in files:
        im = Image.open(f).convert("RGB")
        h = round(im.height * width / im.width)
        im = im.resize((width, h), Image.LANCZOS)
        frames.append(im.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.Dither.NONE))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=ms, loop=0, optimize=True, disposal=1)
    print("%d장 · %.1f초 · %.1f MB → %s" % (len(frames), len(frames) * ms / 1000.0, os.path.getsize(out) / 1e6, out))


if __name__ == "__main__":
    main()
