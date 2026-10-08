"""그림 원본 만들기 도우미: v2_구현/그림_프롬프트_GPT.md의 92장 (Codex 이미지 생성용 --next · --check, 또는 API로 직접 --api).

- 매 장 기준 그림(그림_원본/char/001_윤_소위.png)을 함께 보내 그림체를 맞춘다.
- 결과는 그림_원본/{폴더}/{번호}_{이미지이름}.png (git 밖). 이미 있는 파일은 건너뛴다(다시 만들려면 --redo).
- 기록: 그림_원본/_log.jsonl (번호, 파일, 성공/실패, 이유)

필요: `pip install pillow` (--api를 쓸 때만 OPENAI_API_KEY와 openai 패키지)

예:
  python game/tools/gen_art.py --list                 # 목록만 (API 호출 없음)
  python game/tools/gen_art.py --next 1               # 다음에 만들 그림의 완성 프롬프트·저장 경로 (Codex 이미지 생성용)
  python game/tools/gen_art.py --check               # 만든 그림의 비율·투명 배경 확인
  python game/tools/gen_art.py --api --only 1-33      # (API 키가 있을 때만) 1순위 33장을 API로
  python game/tools/gen_art.py --api --only 13,20 --redo  # (API) 이 번호만 다시
  python game/tools/gen_art.py --sheet                # 만든 그림을 한 장에 모아 보기 (그림_원본/_sheet.png)
"""
import argparse
import base64
import io
import json
import os
import re
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROMPTS = [os.path.join(ROOT, "v2_구현", "그림_프롬프트_GPT.md"),   # R: 001~092
           os.path.join(ROOT, "v2_구현", "그림_프롬프트_V.md"),     # V 연출: 093~116 (타일 · 책상 · 컷신)
           os.path.join(ROOT, "v2_구현", "그림_프롬프트_미션.md")]  # 미션 카드별: 117~138
OUT = os.path.join(ROOT, "그림_원본")
REF = os.path.join(OUT, "char", "001_윤_소위.png")
LOG = os.path.join(OUT, "_log.jsonl")
# 초상(002~012)은 얼굴이 기준 인물(윤 소위)을 닮지 않게, 사람 얼굴이 없는 그림을 그림체 기준으로 쓴다
REF_PORTRAIT = os.path.join(OUT, "mission", "016_공작.png")
# 타일(093~110)은 물건 하나를 가운데 둔 그림이 그림체 기준으로 더 맞다
REF_TILE = os.path.join(OUT, "mission", "015_폭파.png")
PORTRAIT_LINE = ("Match the exact art style, line weight, cross-hatching, paper texture and color palette "
                 "of the attached reference image, which shows no face on purpose. Draw a completely new, distinct person "
                 "exactly as described below; do not reuse any face, hairstyle or uniform from other images.")

REF_LINE = ("Match the exact art style, line weight, cross-hatching, paper texture and color palette "
            "of the attached reference image. Use the reference only for style; do not copy its person, pose or uniform "
            "unless the subject below asks for it.")


def parse():
    """프롬프트 파일 → [{"no", "path", "name", "size", "prompt", "transparent", "out"}]"""
    text = "\n".join(io.open(p, encoding="utf-8").read() for p in PROMPTS if os.path.exists(p))
    items = []
    for m in re.finditer(r"^### (\d{3}) · `([^`]+)` · (.+?)\n크기 \*\*(\d+)×(\d+)[^\n]*\n+```\n(.*?)\n```", text, re.S | re.M):
        no, path, name, w, h, prompt = m.groups()
        transparent = "transparent" in prompt.lower()
        # 분류 폴더는 유지하고, 파일 이름은 3자리 번호와 이미지 이름으로 만든다.
        rel = path
        for pre in ("art/", "assets/"):
            if rel.startswith(pre):
                rel = rel[len(pre):]
        filename = re.sub(r'[<>:"/\\|?*\s·]+', '_', name.strip().removesuffix(" (덮어씀)")).strip('_')
        filename = "%03d_%s.png" % (int(no), filename)
        items.append({"no": int(no), "path": path, "name": name.strip(), "size": "%sx%s" % (w, h),
                      "prompt": prompt.strip(), "transparent": transparent,
                      "out": os.path.join(OUT, *rel.split("/")[:-1], filename)})
    return items


def pick(items, only):
    if not only:
        return items
    want = set()
    for part in only.split(","):
        if "-" in part:
            a, b = part.split("-")
            want.update(range(int(a), int(b) + 1))
        else:
            want.add(int(part))
    return [it for it in items if it["no"] in want]


def log(rec):
    os.makedirs(OUT, exist_ok=True)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def generate(client, it, model, quality, retries=3):
    prompt = REF_LINE + "\n\n" + it["prompt"]
    kw = {"model": model, "prompt": prompt, "size": it["size"], "quality": quality, "n": 1}
    if it["transparent"]:
        kw["background"] = "transparent"
    for attempt in range(1, retries + 1):
        try:
            with open(REF, "rb") as ref:
                r = client.images.edit(image=[ref], **kw)
            data = base64.b64decode(r.data[0].b64_json)
            os.makedirs(os.path.dirname(it["out"]), exist_ok=True)
            with open(it["out"], "wb") as f:
                f.write(data)
            return True, ""
        except Exception as e:  # 거절(안전 정책)은 다시 해도 같으므로 바로 넘긴다
            msg = str(e)
            if "safety" in msg.lower() or "moderation" in msg.lower() or attempt == retries:
                return False, msg[:300]
            time.sleep(5 * attempt)
    return False, "unknown"


def sheet(items):
    from PIL import Image, ImageDraw, ImageFont
    have = [it for it in items if os.path.exists(it["out"])]
    if not have:
        print("만든 그림이 없습니다.")
        return
    W, cols = 220, 8
    rows = (len(have) + cols - 1) // cols
    img = Image.new("RGB", (cols * W, rows * (W + 24)), (239, 228, 204))
    d = ImageDraw.Draw(img)
    font_path = os.path.join(os.environ.get("WINDIR", ""), "Fonts", "malgun.ttf")
    font = ImageFont.truetype(font_path, 12) if os.path.exists(font_path) else ImageFont.load_default()
    for i, it in enumerate(have):
        im = Image.open(it["out"]).convert("RGBA")
        im.thumbnail((W - 10, W - 10))
        x, y = (i % cols) * W, (i // cols) * (W + 24)
        bg = Image.new("RGBA", im.size, (239, 228, 204, 255))
        bg.alpha_composite(im)
        img.paste(bg.convert("RGB"), (x + 5, y + 5))
        label = os.path.basename(it["out"])
        while font.getlength(label) > W - 10:
            label = label[:-4] + "..."
        d.text((x + 5, y + W), label, font=font, fill=(35, 29, 23))
    p = os.path.join(OUT, "_sheet.png")
    img.save(p)
    print("모아 보기:", p, "(%d장)" % len(have))


def next_items(items, n):
    """아직 없는 그림 n개: Codex가 자기 이미지 생성 기능으로 만들 때 쓰는 완성 프롬프트와 저장 경로"""
    out = []
    for it in items:
        if os.path.exists(it["out"]):
            continue
        portrait = it["path"].startswith("char/") and it["no"] != 1
        out.append({"no": it["no"], "name": it["name"], "save_to": it["out"], "size": it["size"],
                    "transparent": it["transparent"], "reference": REF_PORTRAIT if portrait else (REF_TILE if it["path"].startswith("tile/") else REF),
                    "prompt": (PORTRAIT_LINE if portrait else REF_LINE) + "\n\n" + it["prompt"]})
        if len(out) >= n:
            break
    return out


def check(items):
    """있는 그림이 맞는 비율인지, 열리는지, 문양은 투명인지 확인한다"""
    from PIL import Image
    bad = 0
    have = 0
    for it in items:
        if not os.path.exists(it["out"]):
            continue
        have += 1
        w, h = (int(x) for x in it["size"].split("x"))
        try:
            im = Image.open(it["out"])
            iw, ih = im.size
            if abs(iw / ih - w / h) > 0.03:
                bad += 1
                print("%03d 비율이 다름: %dx%d (원래 %s) %s" % (it["no"], iw, ih, it["size"], it["out"]))
            elif it["transparent"] and im.mode != "RGBA":
                bad += 1
                print("%03d 투명 배경이 아님 (%s) %s" % (it["no"], im.mode, it["out"]))
        except Exception as e:
            bad += 1
            print("%03d 열리지 않음: %s" % (it["no"], e))
    print("있음 %d / %d · 문제 %d" % (have, len(items), bad))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="번호 범위 예: 1-33 또는 13,20,41")
    ap.add_argument("--redo", action="store_true", help="이미 있는 파일도 다시 만든다")
    ap.add_argument("--list", action="store_true", help="목록만 보여 준다 (API 호출 없음)")
    ap.add_argument("--sheet", action="store_true", help="만든 그림을 한 장에 모은다")
    ap.add_argument("--next", type=int, default=0, metavar="N", help="아직 없는 그림 N개의 완성 프롬프트·저장 경로를 JSON으로 (API 호출 없음)")
    ap.add_argument("--check", action="store_true", help="있는 그림의 비율·투명 배경을 확인한다")
    ap.add_argument("--api", action="store_true", help="OpenAI API로 직접 만든다 (OPENAI_API_KEY 필요)")
    ap.add_argument("--model", default=os.environ.get("ART_MODEL", "gpt-image-1"))
    ap.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    a = ap.parse_args()

    items = parse()
    if len(items) != 116:
        print("경고: 프롬프트가 %d장입니다 (R 92장 + V 24장 = 116장이어야 함)" % len(items))
    todo = pick(items, a.only)

    if a.sheet:
        sheet(todo)
        return
    if a.list:
        for it in todo:
            mark = "있음" if os.path.exists(it["out"]) else "  - "
            print("%03d %s %-10s %-34s %s" % (it["no"], mark, it["size"], it["path"], it["name"]))
        return
    if a.next:
        print(json.dumps(next_items(todo, a.next), ensure_ascii=False, indent=1))
        return
    if a.check:
        check(todo)
        return
    if not a.api:
        sys.exit("만들기는 --api(API 키) 또는 --next(Codex 이미지 생성 기능)로 한다. 지시서 R0를 보라.")
    if not os.path.exists(REF):
        sys.exit("기준 그림이 없습니다: " + REF)
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("OPENAI_API_KEY 환경 변수가 없습니다.")

    from openai import OpenAI
    client = OpenAI()
    made = fail = skip = 0
    for it in todo:
        if os.path.exists(it["out"]) and not a.redo:
            skip += 1
            continue
        print("%03d %s (%s) ..." % (it["no"], it["path"], it["name"]), flush=True)
        ok, why = generate(client, it, a.model, a.quality)
        log({"no": it["no"], "path": it["path"], "ok": ok, "why": why, "model": a.model, "quality": a.quality,
             "time": time.strftime("%Y-%m-%d %H:%M:%S")})
        if ok:
            made += 1
        else:
            fail += 1
            print("   실패:", why)
    print("만듦 %d · 건너뜀 %d · 실패 %d" % (made, skip, fail))


if __name__ == "__main__":
    main()
