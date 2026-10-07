"""R_그림.md 1부의 표 → 그림_프롬프트_GPT.md (GPT 이미지 생성용 완성 프롬프트 92장). 표를 고치면 다시 돌린다."""
import io, os, re

SRC = os.path.join(os.path.dirname(__file__), "..", "..", "v2_구현", "지시서", "R_그림.md")
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "v2_구현", "그림_프롬프트_GPT.md")

STYLE = ("Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching "
         "on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) "
         "and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. "
         "Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. "
         "Do not show the Japanese rising sun flag. Never draw the sun or moon as a solid red disc or any red circle "
         "in the sky or behind a figure (it reads as the Japanese flag); show sunrise or sunset only as warm light in the clouds. "
         "No gore or blood. Not photorealistic, not 3D, not anime.")

# 섹션 제목 → (폴더, 크기, 구도 문장, 자를 비율 안내)
SECTIONS = [
    ("1.4", "char", "1024×1536 (세로)",
     "Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. "
     "This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.",
     "3:4로 위아래를 조금 자름"),
    ("1.5", "mission", "1024×1024 (정사각)",
     "Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.",
     "그대로"),
    ("1.6", "op", "1024×1024 (정사각)",
     "Composition: one central subject with empty margin, ominous mood with seal red accents; it must read at small size.",
     "그대로"),
    ("1.8", "strike", "1536×1024 (가로)",
     "Composition: wide establishing shot of 1940s Gyeongseong on the night before a raid, tense. "
     "Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.",
     "16:9로 위아래를 자름"),
    ("1.9", "ending", "1536×1024 (가로)",
     "Composition: wide shot in dawn light, emotional. "
     "Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.",
     "16:9로 위아래를 자름"),
    ("1.10", "item", "1536×1024 (가로)",
     "Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.",
     "4:3으로 양옆을 자름"),
    ("1.11", "event", "1536×1024 (가로)",
     "Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.",
     "4:3으로 양옆을 자름"),
    ("1.12", "threat", "1536×1024 (가로)",
     "Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.",
     "4:3으로 양옆을 자름"),
    ("1.13", "scene", "1536×1024 (가로)",
     "Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.",
     "4:3으로 양옆을 자름"),
]

src = io.open(SRC, encoding="utf-8").read()
# 섹션별로 자른다
parts = re.split(r"\n### ", src)
by_num = {}
for p in parts:
    m = re.match(r"(\d+\.\d+) ", p)
    if m:
        by_num[m.group(1)] = p

out = []
out.append("# 그림 프롬프트 (GPT 이미지 생성용)\n")
out.append("> `지시서/R_그림.md` 1부를 GPT에 바로 붙일 수 있게 펼친 것이다. 목록·의도·넣는 법은 R_그림.md가 정본이다.")
out.append("> R_그림.md의 표를 바꾸면 이 파일도 맞춘다.\n")
out.append("## 쓰는 법\n")
out.append("1. **기준 그림 먼저.** 아래 001(윤 소위)을 만든다. 마음에 들 때까지 다시 뽑는다. 이것이 그림체 기준이다.")
out.append("2. **이후 모든 요청에 기준 그림을 함께 올리고**, 프롬프트 맨 앞에 이 한 줄을 붙인다:")
out.append("   `Match the exact art style, line weight, paper texture and color palette of the attached reference image.`")
out.append("3. 한 요청에 **한 장씩.** 여러 장을 한 번에 시키면 결이 흔들린다.")
out.append("4. 크기는 각 항목에 적힌 것으로 고른다(ChatGPT에서는 \"세로로/가로로/정사각으로\"라고 적어도 된다).")
out.append("5. 받은 그림은 `game/assets/art/{폴더}/{id}.png`로 저장한다(사연 뒷면은 `game/assets/art/saga_back.png`, 세력 문양은 `game/assets/ui/faction_uy.png`·`faction_ug.png`). 자르기·WebP 변환은 넣는 작업자가 한 번에 한다(R_그림.md 2부). 직접 자르지 않아도 된다.")
out.append("6. 글자가 섞여 나오면 \"Remove all text from the image\"로 고친다. 욱일기가 나오면 버리고 다시 뽑는다.")
out.append("7. 세력 문양 2장(마지막 2개)은 **투명 배경**으로 받는다.\n")
out.append("**공통 그림체 문장** (모든 프롬프트 안에 이미 들어 있다)\n")
out.append("```\n" + STYLE + "\n```\n")

n = 0
def block(folder, id_, kname, size, comp, crop, subject, transparent=False):
    global n
    n += 1
    prompt = "Create an illustration. " + STYLE + "\n" + comp + "\nSubject: " + subject.rstrip(".") + "."
    if transparent:
        prompt += "\nBackground: fully transparent (PNG with alpha). The emblem only, centered."
    out.append("### %03d · `%s/%s` · %s" % (n, folder, id_, kname))
    out.append("크기 **%s** · 넣을 때 %s\n" % (size, crop))
    out.append("```\n" + prompt + "\n```\n")

ORDER_TITLE = {"1.4": "1순위 · 요원 초상 12", "1.5": "1순위 · 미션 종류 7", "1.6": "1순위 · 일제 작전 4",
               "1.8": "1순위 · 결행 거점 4", "1.9": "1순위 · 엔딩 5", "1.10": "2순위 · 아이템 10",
               "1.11": "2순위 · 이벤트 10", "1.12": "2순위 · 일제 위협 9", "1.13": "2순위 · 장면 28"}

for num, folder, size, comp, crop in SECTIONS:
    sec = by_num[num]
    out.append("## " + ORDER_TITLE[num] + "\n")
    for line in sec.split("\n"):
        m = re.match(r"\|\s*`([a-z0-9_]+)`\s*\|(.*)\|\s*$", line)
        if not m:
            continue
        cells = [c.strip() for c in m.group(2).split("|")]
        id_ = m.group(1)
        subject = cells[-1]
        kname = cells[0]
        if num == "1.12":   # 위협: 묶음 이름 + 쓰는 카드
            kname = "위협 묶음 (" + cells[0] + ")"
        block(folder, id_, kname, size, comp, crop, subject)
    if num == "1.6":   # 사연 뒷면은 1.7, 일제 작전 뒤에 둔다
        out.append("## 1순위 · 사연 카드 뒷면 1\n")
        block("art", "saga_back", "사연 카드 뒷면", "1024×1536 (세로)",
              "Composition: vertical card-back design, intimate and personal mood, objects centered with paper margin all around.",
              "2:3 그대로", "a single faded photograph and a folded letter tied with red thread, lying on aged paper")

out.append("## 3순위 · 세력 문양 2\n")
block("assets/ui", "faction_uy", "조선의용대 문양 (덮어씀)", "1024×1024 (정사각)", "Composition: a flat emblem design, symmetrical, bold.",
      "256×256 PNG", "a rifle crossed with a writing brush inside a circle, black and seal red", transparent=True)
block("assets/ui", "faction_ug", "경성 지하조직 문양 (덮어씀)", "1024×1024 (정사각)", "Composition: a flat emblem design, symmetrical, bold.",
      "256×256 PNG", "a printing-press type block and an old key inside a square seal, black and seal red", transparent=True)

io.open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(n)
