# 그림 프롬프트 (GPT 이미지 생성용)

> `지시서/R_그림.md` 1부를 GPT에 바로 붙일 수 있게 펼친 것이다. 목록·의도·넣는 법은 R_그림.md가 정본이다.
> R_그림.md의 표를 바꾸면 이 파일도 맞춘다.

## 쓰는 법

1. **기준 그림 먼저.** 아래 001(윤 소위)을 만든다. 마음에 들 때까지 다시 뽑는다. 이것이 그림체 기준이다.
2. **이후 모든 요청에 기준 그림을 함께 올리고**, 프롬프트 맨 앞에 이 한 줄을 붙인다:
   `Match the exact art style, line weight, paper texture and color palette of the attached reference image.`
3. 한 요청에 **한 장씩.** 여러 장을 한 번에 시키면 결이 흔들린다.
4. 크기는 각 항목에 적힌 것으로 고른다(ChatGPT에서는 "세로로/가로로/정사각으로"라고 적어도 된다).
5. 받은 그림은 PNG 그대로 `그림_원본/{폴더}/{id}.png`로 저장한다(프로젝트 맨 위 폴더, git에 올리지 않음. 예: `그림_원본/char/yun.png`, `그림_원본/saga_back.png`, `그림_원본/ui/faction_uy.png`). 자르기·WebP 변환은 넣는 작업자가 한 번에 한다(R_그림.md 2부). 직접 자르지 않아도 된다.
6. 글자가 섞여 나오면 "Remove all text from the image"로 고친다. 욱일기가 나오면 버리고 다시 뽑는다.
7. 세력 문양 2장(마지막 2개)은 **투명 배경**으로 받는다.

**공통 그림체 문장** (모든 프롬프트 안에 이미 들어 있다)

```
Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
```

## 1순위 · 요원 초상 12

### 001 · `char/yun` · 윤 소위
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: young Korean man around 22, former student soldier who deserted the Japanese army, now a Korean Liberation Army second lieutenant, khaki Chinese-style officer uniform with peaked cap, lean face, steady resolute eyes.
```

### 002 · `char/park` · 박 하사
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: Korean sergeant in his early 30s, radio operator from Chongqing, khaki uniform, headphones hanging around his neck, canvas radio strap over shoulder, square jaw, calm and practical.
```

### 003 · `char/han` · 한 간호장교
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: Korean woman in her late 20s, army nurse officer back from the front, khaki uniform with a red cross armband, hair pinned back under a cap, medical satchel, gentle but unshaken expression.
```

### 004 · `char/oh` · 저격수 오
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: Korean man in his 30s, sniper from the North China front, padded cotton winter uniform, rifle with telescopic sight slung across his back, narrowed watchful eye, weathered skin.
```

### 005 · `char/seok` · 석 기술자
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: Korean man in his 40s, bomb-making engineer, round wire-rimmed glasses, rolled-up sleeves, leather apron, coil of fuse wire and small tools, focused careful look.
```

### 006 · `char/mun` · 문 선전대원
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: young Korean woman around 20, former schoolgirl turned propaganda corps member, short bobbed hair, plain jacket over a school-style blouse, holding a bundle of leaflets to her chest, bright defiant eyes.
```

### 007 · `char/gaeddong` · 포수 김개똥
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: rugged Korean mountain hunter in his 40s, weathered face, cloth headband, hanbok jacket with a fur vest, old matchlock hunting rifle on his shoulder, wry half smile.
```

### 008 · `char/makrye` · 주모 막례
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: Korean tavern-keeper woman in her 50s, plain hanbok with an apron, hair in a low bun with a wooden binyeo pin, sleeves tied up, holding a ladle, warm but tough expression.
```

### 009 · `char/choi` · 최 훈장
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: elderly Korean village schoolmaster in his 60s, white hanbok and black horsehair gat hat, long thin white beard, holding a bound book and a brush, dignified quiet gaze.
```

### 010 · `char/jeong` · 정 인쇄공
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: Korean man in his 30s, underground print shop typesetter, flat cap, ink-stained fingers and apron, holding a small tray of metal type, tired but sharp eyes.
```

### 011 · `char/seo` · 서 마담
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: elegant Korean woman in her 30s, owner of a 1930s Gyeongseong coffee house that police frequent, permed short hair, Western-style dress with a brooch, coffee cup in hand, composed knowing smile.
```

### 012 · `char/lee` · 이 차장
크기 **1024×1536 (세로)** · 넣을 때 3:4로 위아래를 조금 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: head-and-shoulders portrait, three-quarter view, face in the upper-middle of the frame, plain paper background. This will be cropped to 3:4 and to a circle around the face, so keep the whole head well inside the frame. Setting: 1940s Korea.
Subject: young Korean man in his 20s, streetcar conductor, conductor uniform and cap, ticket punch and leather ticket bag, friendly face with alert eyes.
```

## 1순위 · 미션 종류 7

### 013 · `mission/assassin` · 암살
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: a pistol lying on a folded newspaper under a single hanging street lamp.
```

### 014 · `mission/infiltrate` · 잠입
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: a shadowed figure slipping through the iron gate of a colonial stone building at night.
```

### 015 · `mission/bomb` · 폭파
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: a tin canister bomb with a lit fuse, sparks.
```

### 016 · `mission/work` · 공작
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: two hands working by lamplight over leaflets and a small ink roller.
```

### 017 · `mission/contact` · 연락
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: a sealed envelope tied with string, passing from one hand to another.
```

### 018 · `mission/lurk` · 잠복
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: a pair of eyes watching through a torn gap in a paper window at night.
```

### 019 · `mission/coop` · 협동
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central emblem-like subject with generous empty margin around it; it must still read at 40 pixels wide.
Subject: two hands clasping firmly, wrists in different sleeves (hanbok and uniform).
```

## 1순위 · 일제 작전 4

### 020 · `op/op_roundup` · 일제 검거령
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central subject with empty margin, ominous mood with seal red accents; it must read at small size.
Subject: a police whistle and handcuffs on a list of names, one name circled in red.
```

### 021 · `op/op_rice_levy` · 쌀 공출
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central subject with empty margin, ominous mood with seal red accents; it must read at small size.
Subject: stacked rice sacks stamped with a red seal, a soldier's bayonet shadow across them.
```

### 022 · `op/op_spy_raid` · 밀정 침투
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central subject with empty margin, ominous mood with seal red accents; it must read at small size.
Subject: a man in a trench coat and fedora with his face hidden in shadow, standing in a crowd.
```

### 023 · `op/op_censorship` · 신문 검열
크기 **1024×1024 (정사각)** · 넣을 때 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: one central subject with empty margin, ominous mood with seal red accents; it must read at small size.
Subject: a newspaper page with many lines blacked out and a large red censor stamp.
```

## 1순위 · 사연 카드 뒷면 1

### 024 · `art/saga_back` · 사연 카드 뒷면
크기 **1024×1536 (세로)** · 넣을 때 2:3 그대로

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: vertical card-back design, intimate and personal mood, objects centered with paper margin all around.
Subject: a single faded photograph and a folded letter tied with red thread, lying on aged paper.
```

## 1순위 · 결행 거점 4

### 025 · `strike/prison` · 형무소 해방
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide establishing shot of 1940s Gyeongseong on the night before a raid, tense. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: the high brick walls and watchtower of Seodaemun Prison at night, searchlight beam, silhouettes of agents crouching at the foot of the wall.
```

### 026 · `strike/barracks` · 사령관 암살
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide establishing shot of 1940s Gyeongseong on the night before a raid, tense. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: a Japanese army barracks compound behind barbed wire at night, a lit window in the commander's quarters, sentry silhouettes.
```

### 027 · `strike/police_hq` · 경찰서 폭파
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide establishing shot of 1940s Gyeongseong on the night before a raid, tense. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: a colonial-era police headquarters building on a city street at night, a lone figure approaching the back door with a bundle.
```

### 028 · `strike/gg` · 총독부 점거
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide establishing shot of 1940s Gyeongseong on the night before a raid, tense. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: the massive domed Government-General building seen from below at dusk, tiny figures at the main gate, empty flagpole on the dome.
```

## 1순위 · 엔딩 5

### 029 · `ending/prison_win` · 형무소 해방 성공
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide shot in dawn light, emotional. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: prison cell doors standing open, prisoners walking out into the dawn, a crowd waiting outside the gate.
```

### 030 · `ending/barracks_win` · 사령관 암살 성공
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide shot in dawn light, emotional. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: an empty commander's office at dawn, a fallen officer's cap on the floor, scattered maps, window open.
```

### 031 · `ending/police_hq_win` · 경찰서 폭파 성공
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide shot in dawn light, emotional. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: smoke rising from a police headquarters at dawn, people in the street looking up, papers drifting in the air.
```

### 032 · `ending/gg_win` · 총독부 점거 성공
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide shot in dawn light, emotional. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: the Korean taegukgi flag being raised on the flagpole of the domed Government-General building at sunrise, crowd below.
```

### 033 · `ending/fail` · 실패 · 정사
크기 **1536×1024 (가로)** · 넣을 때 16:9로 위아래를 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: wide shot in dawn light, emotional. Keep all important content inside the central horizontal band, because the top and bottom will be cropped to 16:9.
Subject: an empty Gyeongseong street at dawn on August 15 1945, a distant crowd cheering liberation, a lone figure standing still with an unopened letter.
```

## 2순위 · 아이템 10

### 034 · `item/train_ticket` · 승차권
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a 1940s paper train ticket with a punched hole.
```

### 035 · `item/pocket_watch` · 회중시계
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: an open brass pocket watch on its chain.
```

### 036 · `item/smoke_bomb` · 연막탄
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a small canister releasing thick billowing smoke.
```

### 037 · `item/safety_pin` · 옷핀
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a bent safety pin next to an old padlock.
```

### 038 · `item/forged_pass` · 위조 통행증
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: an official travel pass with a photograph, a forger's pen and a carved stamp beside it.
```

### 039 · `item/cipher_book` · 암호 수첩
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a small worn notebook open to columns of number codes, a pencil.
```

### 040 · `item/telegram` · 전보
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a folded telegram slip and a telegraph key.
```

### 041 · `item/comrade_cover` · 동지들의 엄호
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: silhouettes of comrades on a rooftop covering an alley below.
```

### 042 · `item/telescope` · 망원경
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a brass spyglass on a windowsill overlooking rooftops.
```

### 043 · `item/western_suit` · 양장
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: still life of a single object on paper, close-up, centered. Will be cropped to 4:3, keep the object away from the left and right edges.
Subject: a 1930s Western suit jacket and fedora hanging on a coat stand.
```

## 2순위 · 이벤트 10

### 044 · `event/print_shop` · 지하 인쇄소
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a hidden basement print shop, hand press, fresh leaflets hanging to dry.
```

### 045 · `event/back_alley` · 뒷골목 발견
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a narrow hidden alley between tiled roofs opening onto another street.
```

### 046 · `event/hideout` · 동지의 은신처
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a small room behind a sliding wall panel, a lamp and a bedroll, someone beckoning.
```

### 047 · `event/into_crowd` · 군중 속으로
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a figure disappearing into a bustling market crowd, a policeman looking the wrong way.
```

### 048 · `event/secret_letter` · 국내 동지의 밀서
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a secret letter hidden inside a hollowed book, coins wrapped in cloth.
```

### 049 · `event/informer` · 밀고자
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a man whispering into a policeman's ear in a doorway, pointing down the street.
```

### 050 · `event/cop_eye` · 순사의 눈
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a colonial policeman's cap and watchful eyes under the brim, a new barricade behind him.
```

### 051 · `event/student` · 쫓기는 학생
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a frightened student in a school uniform running into an alley, footsteps behind.
```

### 052 · `event/rickshaw` · 딱한 인력거꾼 김첨지
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a poor rickshaw puller in the rain offering a ride, worn straw sandals.
```

### 053 · `event/old_comrade` · 옛 동지와의 재회
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a narrative street moment in 1940s Gyeongseong. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: two old comrades recognizing each other across a crowded tram platform.
```

## 2순위 · 일제 위협 9

### 054 · `threat/dispatch` · 위협 묶음 (surprise_search, mp_reinforce, reinforce, informer_bounty)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: military police in a column marching out of a gate at dawn.
```

### 055 · `threat/hunt` · 위협 묶음 (arrest_order, tailing)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: a wanted poster with a blank face, a shadowy tail following at a distance.
```

### 056 · `threat/patrol` · 위협 묶음 (mp_patrol, special_alert, full_alert, emergency_muster)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: policemen with lanterns and swords patrolling a night street, whistles blowing.
```

### 057 · `threat/checkpoint` · 위협 묶음 (checkpoint_add, blockade, sweep)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: a checkpoint barricade with barbed wire across a street, a guard checking papers.
```

### 058 · `threat/weather` · 위협 묶음 (curfew, monsoon, air_raid)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: an empty street in heavy rain at night, curfew bell, searchlights in the sky.
```

### 059 · `threat/money` · 위협 묶음 (house_search, fund_freeze)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: an overturned room after a house search, a broken cash box, scattered coins.
```

### 060 · `threat/prison` · 위협 묶음 (prison_riot, torture)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: an empty interrogation room, a single bare bulb over a chair, a barred window (no people, no violence).
```

### 061 · `threat/calm` · 위협 묶음 (calm_day)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: a quiet morning alley, laundry drying, a cat on a wall.
```

### 062 · `threat/chaos` · 위협 묶음 (chaos)
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: oppressive colonial atmosphere seen from the resistance agents' point of view. Will be cropped to 4:3, keep the subject away from the left and right edges.
Subject: a confused crowd and overturned carts, police running in different directions.
```

## 2순위 · 장면 28

### 063 · `scene/prison_wall` · 담 넘기
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: agents climbing a high brick prison wall with a rope at night.
```

### 064 · `scene/prison_guards` · 간수 제압
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: two agents pinning a guard against a corridor wall, keys falling.
```

### 065 · `scene/prison_keys` · 열쇠 꾸러미
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a heavy ring of iron keys hanging from a jailer's belt, a hand reaching for it.
```

### 066 · `scene/prison_search` · 감방 수색
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a long corridor of cell doors, a lantern searching faces behind bars.
```

### 067 · `scene/prison_bell` · 비상종
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a hand stopping the clapper of a large alarm bell.
```

### 068 · `scene/prison_door` · 옥문
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a massive iron prison gate with a huge lock, a lockpick in trembling hands.
```

### 069 · `scene/barracks_wire` · 철조망
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: wire cutters cutting through barbed wire at night.
```

### 070 · `scene/barracks_shift` · 보초 교대
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: two sentries changing guard, an agent hiding in the shadow of a truck.
```

### 071 · `scene/barracks_ammo` · 탄약고
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: stacked ammunition crates in a dark depot, a bomb being placed.
```

### 072 · `scene/barracks_officers` · 장교 숙소
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a corridor of officers' quarters, light under one door, boots outside.
```

### 073 · `scene/barracks_dogs` · 군견
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a guard dog straining on its leash, agents frozen behind a wall.
```

### 074 · `scene/barracks_commander` · 사령관실
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a pistol aimed at a desk lamp in a commander's office, a map on the wall.
```

### 075 · `scene/police_back_door` · 뒷문 잠입
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: two agents slipping through the back door of a police station.
```

### 076 · `scene/police_duty` · 당직 순사
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a dozing duty policeman at a front desk, a figure creeping past.
```

### 077 · `scene/police_alarm` · 경보 차단
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a hand cutting the wires of an alarm box on a wall.
```

### 078 · `scene/police_records` · 서류 창고
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: shelves of police files, an agent pulling out a dossier.
```

### 079 · `scene/police_cells` · 지하 유치장
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a basement lockup, prisoners' hands reaching through bars.
```

### 080 · `scene/police_bomb` · 폭탄 설치
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a bomb with a fuse placed under a staircase in a police station.
```

### 081 · `scene/gg_gate` · 정문
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: agents rushing the main gate of a huge domed stone building.
```

### 082 · `scene/gg_corridor` · 회랑
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a vast marble corridor, agents moving between columns.
```

### 083 · `scene/gg_comms` · 통신실
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a room of telephone switchboards and telegraph machines, cables being pulled.
```

### 084 · `scene/gg_archive` · 문서고
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a dark archive of endless file cabinets, agents barricading the door.
```

### 085 · `scene/gg_guard` · 근위대
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a line of guards with rifles at the top of a grand staircase.
```

### 086 · `scene/gg_flag` · 깃발
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a folded taegukgi being carried up a spiral stair toward the dome.
```

### 087 · `scene/reinforce_post` · 초소
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a sandbagged guard post with a sentry at night.
```

### 088 · `scene/reinforce_searchlight` · 탐조등
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a sweeping searchlight beam crossing a courtyard.
```

### 089 · `scene/reinforce_dogs` · 군견대
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a handler with several guard dogs at a gate.
```

### 090 · `scene/reinforce_gate` · 철문
크기 **1536×1024 (가로)** · 넣을 때 4:3으로 양옆을 자름

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a tense, cinematic interior or close action moment during a night raid. Will be cropped to 4:3, keep the action away from the left and right edges.
Subject: a heavy steel gate slamming shut.
```

## 3순위 · 세력 문양 2

### 091 · `assets/ui/faction_uy` · 조선의용대 문양 (덮어씀)
크기 **1024×1024 (정사각)** · 넣을 때 256×256 PNG

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a flat emblem design, symmetrical, bold.
Subject: a rifle crossed with a writing brush inside a circle, black and seal red.
Background: fully transparent (PNG with alpha). The emblem only, centered.
```

### 092 · `assets/ui/faction_ug` · 경성 지하조직 문양 (덮어씀)
크기 **1024×1024 (정사각)** · 넣을 때 256×256 PNG

```
Create an illustration. Style: a 1940s Korean woodblock print (linocut). Bold carved black ink lines and cross-hatching on textured, aged cream rice paper. Limited palette: sumi ink black, aged cream paper, seal red (#b3261e) and muted ochre, with olive drab only where needed. Strong, readable silhouette; dramatic but restrained mood. Absolutely no text, letters, numbers, captions, signatures, watermarks or logos anywhere in the image. Do not show the Japanese rising sun flag. No gore or blood. Not photorealistic, not 3D, not anime.
Composition: a flat emblem design, symmetrical, bold.
Subject: a printing-press type block and an old key inside a square seal, black and seal red.
Background: fully transparent (PNG with alpha). The emblem only, centered.
```

