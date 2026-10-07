# 지시서 R: 그림 (목록 · 프롬프트 · 넣는 법)

> 1부(목록·프롬프트)는 **사용자가 그림을 만들 때** 쓴다. 2부(넣는 법)는 그림이 들어온 뒤 **구현 작업자**가 쓴다.
> 먼저 `00_공통.md`를 읽어라. 앞 단계: Q. 규칙·수치는 바꾸지 않는다.

## 0. 지금 그림 상태 (2026-10-07 점검)

| 묶음 | 지금 | 문제 |
|---|---|---|
| 타이틀 · 보드 지도 | 원작 팀 그림 | 괜찮음. 그대로 둔다 |
| 지형 타일 12종 | 색 종이 + 흰 선 아이콘 | 괜찮음. 그대로 둔다(보드는 아이콘이 읽기 쉽다) |
| **미션 카드 그림** | 타일 그림을 빌려 씀. 암살 · 폭파 · 공작은 **글자만 쓴 임시 그림**(「암살미션」, 「폭파공작」, 「방해작전」), 연락은 **없어진 전차 그림** | 가장 눈에 띄는 임시 그림 |
| **요원 12명** | 얼굴이 없다. 세력 문양 4개를 같이 씀 | 명부 · 요원 고르기 · 보드 말이 모두 문양뿐 |
| **사연 카드** | 이벤트 카드 뒷면을 빌려 씀 | 사연만의 그림이 없음 |
| **아이템 10 · 이벤트 10 · 위협 22 · 장면 28** | 그림 없음(뒷면 하나, 순사 모자 하나) | 큰 카드가 글뿐 |
| **결행 거점 4 · 엔딩** | 그림 없음 | 클라이맥스와 결말이 글뿐 |
| 세력 문양 | 조선의용대는 영문 글자 로고, 지하조직은 코드로 만든 문양 | 다른 둘과 결이 다름 |

## 1부. 목록과 프롬프트

### 1.1 그림체 (모든 그림에 공통)

**정한 방향: 1940년대 목판화(판화) 느낌, 4색 안팎.** 이유:
- 화면이 「종이 · 먹 · 인주」로 되어 있어 판화가 가장 잘 붙는다.
- 작은 크기(카드 안 40px)에서도 실루엣이 읽힌다.
- AI로 여러 장을 뽑아도 결이 잘 맞는다(사진풍은 장마다 결이 흔들림).
- 역사 인물·사건을 사실적으로 그리지 않아 무게를 지키기 쉽다.

**색:** 먹 검정 `#231d17` · 바랜 종이 `#efe4cc` · 인주 빨강 `#b3261e` · 황토 `#b8893a` · 국방색 `#5b5a3c` (한두 색만 더해도 됨)

**공통 스타일 문장 (모든 프롬프트 앞에 붙인다)**
```
1940s Korean woodblock print style, linocut, bold carved black ink lines, cross-hatching,
limited palette of sumi black, aged cream paper, seal red and muted ochre,
textured rice paper background, strong silhouette, dramatic but restrained,
no text, no letters, no watermark
```

**공통 빼기 (네거티브 프롬프트를 받는 도구라면)**
```
text, letters, caption, watermark, signature, logo, rising sun flag, swastika,
photorealistic, 3d render, anime, chibi, gore, blood, modern clothing, smartphone
```

**지킬 것**
- **욱일기 금지**(이미 한 번 바꾼 적 있음). 일제 쪽은 제복 · 모자 · 건물 · 서류로만 나타낸다.
- 실존 인물을 닮게 하지 않는다. 요원은 모두 가상 인물이다.
- 고문 · 처형 같은 장면은 **빈 방, 남은 물건**으로 암시한다.
- 그림 속에 글자를 넣지 않는다(한글이 깨져 나온다). 이름은 게임이 얹는다.

**만든 뒤:** 결이 다른 그림이 섞이면 마지막에 같은 색 보정(대비, 종이색)을 한 번 거는 것을 권한다.

### 1.2 크기와 파일

| 묶음 | 쓸 비율 | 만들 크기 (GPT) | 넣을 크기·형식 | 폴더 |
|---|---|---|---|---|
| 요원 초상 | 3:4 | 1024×1536 세로 → 3:4로 자름 | 600×800 WebP | `game/assets/art/char/` |
| 미션 종류 · 일제 작전 | 1:1 | 1024×1024 | 512×512 WebP | `game/assets/art/mission/`, `art/op/` |
| 아이템 · 이벤트 · 위협 · 장면 | 4:3 | 1536×1024 가로 → 4:3으로 자름 | 800×600 WebP | `art/item/`, `art/event/`, `art/threat/`, `art/scene/` |
| 결행 거점 · 엔딩 | 16:9 | 1536×1024 가로 → 16:9로 자름 | 1600×900 WebP | `art/strike/`, `art/ending/` |
| 사연 카드 뒷면 | 2:3 | 1024×1536 세로 | 400×600 WebP | `art/saga_back.webp` |
| 세력 문양 | 1:1 | 1024×1024 투명 배경 | 256×256 PNG(투명) | `assets/ui/faction_*.png`(덮어씀) |

- **만드는 도구: GPT 이미지 생성.** 92장 전부의 완성 프롬프트(그림체 · 구도 · 자를 부분 안내 포함)는 `v2_구현/그림_프롬프트_GPT.md`에 있다. 받은 그림은 **PNG 그대로** `그림_원본/{폴더}/{번호}_{이미지이름}.png`(프로젝트 맨 위, git에 올리지 않는 폴더)에 둔다. 자르기·크기·WebP 변환은 넣는 작업자가 한 번에 한다(2부).
- 원본 파일 이름은 **3자리 번호 + 이미지 이름**을 쓴다. 공백은 `_`로 바꾸고 `(덮어씀)` 표시는 뺀다. 예: `그림_원본/char/001_윤_소위.png`. 게임에 넣는 파일의 **id**는 아래 표대로 유지한다.
- **웹 용량:** 목표가 30MB 안이다. PNG 그대로 92장이면 넘친다. WebP 품질 80이면 한 장 60~150KB라 전부 10MB 안팎이다.

### 1.3 우선순위
| 순위 | 묶음 | 장수 | 효과 |
|---|---|---|---|
| **1** | 요원 초상 12 · 미션 종류 7 · 일제 작전 4 · 사연 뒷면 1 · 결행 거점 4 · 엔딩 5 | **33** | 임시 그림이 사라지고, 첫 화면 · 매 차례 · 결말에 얼굴과 장면이 생긴다 |
| 2 | 아이템 10 · 이벤트 10 · 위협 9(묶어서) · 장면 28 | 57 | 큰 카드마다 그림 |
| 3 | 세력 문양 2 | 2 | 결 맞추기 |
| | **합계** | **92** | |

1순위 33장만 넣어도 "임시 그림"이라는 인상은 사라진다.

---

### 1.4 [1순위] 요원 초상 12장 — `art/char/{id}`

공통 뒤에 붙일 문장: `head-and-shoulders portrait, three-quarter view, face centered in the upper half, plain paper background, 1940s Korea`
(얼굴을 위쪽 가운데에 두어야 보드 말의 동그라미로 잘라도 얼굴이 남는다.)

| id | 요원 | 세력 | 프롬프트 (공통 문장 뒤에) |
|---|---|---|---|
| `yun` | 윤 소위 | 한국광복군 | young Korean man around 22, former student soldier who deserted the Japanese army, now a Korean Liberation Army second lieutenant, khaki Chinese-style officer uniform with peaked cap, lean face, steady resolute eyes |
| `park` | 박 하사 | 한국광복군 | stocky Korean sergeant in his early 30s with a broad round face, heavy brows, a short trimmed mustache and close-cropped hair, wearing a soft khaki field cap (not a peaked officer cap), radio operator from Chongqing, headphones hanging around his neck, canvas radio strap over shoulder, calm and practical |
| `han` | 한 간호장교 | 한국광복군 | Korean woman in her late 20s, army nurse officer back from the front, khaki uniform with a red cross armband, hair pinned back under a cap, medical satchel, gentle but unshaken expression |
| `oh` | 저격수 오 | 조선의용대 | Korean man in his 30s, sniper from the North China front, padded cotton winter uniform, rifle with telescopic sight slung across his back, narrowed watchful eye, weathered skin |
| `seok` | 석 기술자 | 조선의용대 | Korean man in his 40s, bomb-making engineer, round wire-rimmed glasses, rolled-up sleeves, leather apron, coil of fuse wire and small tools, focused careful look |
| `mun` | 문 선전대원 | 조선의용대 | young Korean woman around 20, former schoolgirl turned propaganda corps member, short bobbed hair, plain jacket over a school-style blouse, holding a bundle of leaflets to her chest, bright defiant eyes |
| `gaeddong` | 포수 김개똥 | 의병 | rugged Korean mountain hunter in his 40s, weathered face, cloth headband, hanbok jacket with a fur vest, old matchlock hunting rifle on his shoulder, wry half smile |
| `makrye` | 주모 막례 | 의병 | Korean tavern-keeper woman in her 50s, plain hanbok with an apron, hair in a low bun with a wooden binyeo pin, sleeves tied up, holding a ladle, warm but tough expression |
| `choi` | 최 훈장 | 의병 | elderly Korean village schoolmaster in his 60s, white hanbok and black horsehair gat hat, long thin white beard, holding a bound book and a brush, dignified quiet gaze |
| `jeong` | 정 인쇄공 | 경성 지하조직 | Korean man in his 30s, underground print shop typesetter, flat cap, ink-stained fingers and apron, holding a small tray of metal type, tired but sharp eyes |
| `seo` | 서 마담 | 경성 지하조직 | elegant Korean woman in her 30s, owner of a 1930s Gyeongseong coffee house that police frequent, permed short hair, Western-style dress with a brooch, coffee cup in hand, composed knowing smile |
| `lee` | 이 차장 | 경성 지하조직 | young Korean civilian man in his 20s with a slim oval face, soft features and a slight friendly smile, Gyeongseong streetcar conductor in a dark navy civilian transit uniform with a round flat-topped conductor cap (not military, no peaked army cap, no shoulder straps), ticket punch in hand and a leather ticket bag across his chest |

### 1.5 [1순위] 미션 종류 7장 — `art/mission/{type}`

카드 안에서 **40px 안팎**으로 보인다. 물건 하나, 실루엣 하나로.
공통 뒤에: `single central emblem-like subject, simple composition, generous empty margin, readable at very small size`

| id | 종류 | 프롬프트 |
|---|---|---|
| `assassin` | 암살 | a pistol lying on a folded newspaper under a single hanging street lamp |
| `infiltrate` | 잠입 | a shadowed figure slipping through the iron gate of a colonial stone building at night |
| `bomb` | 폭파 | a tin canister bomb with a lit fuse, sparks |
| `work` | 공작 | two hands working by lamplight over leaflets and a small ink roller |
| `contact` | 연락 | a sealed envelope tied with string, passing from one hand to another |
| `lurk` | 잠복 | a pair of eyes watching through a torn gap in a paper window at night |
| `coop` | 협동 | two hands clasping firmly, wrists in different sleeves (hanbok and uniform) |

### 1.6 [1순위] 일제 작전 4장 — `art/op/{id}` (지금은 「암살미션」 글자 그림을 씀)

공통 뒤에: `single central subject, ominous, seal red accents, readable at small size`

| id | 작전 | 프롬프트 |
|---|---|---|
| `op_roundup` | 일제 검거령 | a police whistle and handcuffs on a list of names, one name circled in red |
| `op_rice_levy` | 쌀 공출 | stacked rice sacks stamped with a red seal, a soldier's bayonet shadow across them |
| `op_spy_raid` | 밀정 침투 | a man in a trench coat and fedora with his face hidden in shadow, standing in a crowd |
| `op_censorship` | 신문 검열 | a newspaper page with many lines blacked out and a large red censor stamp |

### 1.7 [1순위] 사연 카드 뒷면 1장 — `art/saga_back`
```
(공통) + a single faded photograph and a folded letter tied with red thread,
lying on aged paper, intimate and personal mood, vertical card back composition
```

### 1.8 [1순위] 결행 거점 4장 — `art/strike/{id}`

2막 결행 선언 연출과 결행 줄 머리에 쓴다. 공통 뒤에: `wide establishing shot, 1940s Gyeongseong, night before a raid, tense`

| id | 결행 | 프롬프트 |
|---|---|---|
| `prison` | 형무소 해방 | the high brick walls and watchtower of Seodaemun Prison at night, searchlight beam, silhouettes of agents crouching at the foot of the wall |
| `barracks` | 사령관 암살 | a Japanese army barracks compound behind barbed wire at night, a lit window in the commander's quarters, sentry silhouettes |
| `police_hq` | 경찰서 폭파 | a colonial-era police headquarters building on a city street at night, a lone figure approaching the back door with a bundle |
| `gg` | 총독부 점거 | the massive domed Government-General building seen from below at dusk, tiny figures at the main gate, empty flagpole on the dome |

### 1.9 [1순위] 엔딩 5장 — `art/ending/{id}`

공통 뒤에: `dawn light, emotional, wide shot`

| id | 언제 | 프롬프트 |
|---|---|---|
| `prison_win` | 형무소 해방 성공 | prison cell doors standing open, prisoners walking out into the dawn, a crowd waiting outside the gate |
| `barracks_win` | 사령관 암살 성공 | an empty commander's office at dawn, a fallen officer's cap on the floor, scattered maps, window open |
| `police_hq_win` | 경찰서 폭파 성공 | smoke rising from a police headquarters at dawn, people in the street looking up, papers drifting in the air |
| `gg_win` | 총독부 점거 성공 | the Korean taegukgi flag being raised on the flagpole of the domed Government-General building at sunrise, crowd below |
| `fail` | 실패 · 정사 | an empty Gyeongseong street at dawn on August 15 1945, a distant crowd cheering liberation, a lone figure standing still with an unopened letter |

---

### 1.10 [2순위] 아이템 10장 — `art/item/{id}`
공통 뒤에: `still life of a single object on paper, close-up`

| id | 아이템 | 프롬프트 |
|---|---|---|
| `train_ticket` | 승차권 | a 1940s paper train ticket with a punched hole |
| `pocket_watch` | 회중시계 | an open brass pocket watch on its chain |
| `smoke_bomb` | 연막탄 | a small canister releasing thick billowing smoke |
| `safety_pin` | 옷핀 | a single small brass safety pin lying on a folded white handkerchief, close-up |
| `forged_pass` | 위조 통행증 | an official travel pass with a photograph, a forger's pen and a carved stamp beside it |
| `cipher_book` | 암호 수첩 | a small worn notebook open to columns of number codes, a pencil |
| `telegram` | 전보 | a folded telegram slip and a telegraph key |
| `comrade_cover` | 동지들의 엄호 | silhouettes of comrades on a rooftop covering an alley below |
| `telescope` | 망원경 | a brass spyglass on a windowsill overlooking rooftops |
| `western_suit` | 양장 | a 1930s Western suit jacket and fedora hanging on a coat stand |

### 1.11 [2순위] 이벤트 10장 — `art/event/{id}`
공통 뒤에: `street scene in 1940s Gyeongseong, narrative moment`

| id | 이벤트 | 프롬프트 |
|---|---|---|
| `print_shop` | 지하 인쇄소 | a hidden basement print shop, hand press, fresh leaflets hanging to dry |
| `back_alley` | 뒷골목 발견 | a narrow hidden alley between tiled roofs opening onto another street |
| `hideout` | 동지의 은신처 | a small room behind a sliding wall panel, a lamp and a bedroll, someone beckoning |
| `into_crowd` | 군중 속으로 | a figure disappearing into a bustling market crowd, a policeman looking the wrong way |
| `secret_letter` | 국내 동지의 밀서 | a secret letter hidden inside a hollowed book, coins wrapped in cloth |
| `informer` | 밀고자 | a man whispering into a policeman's ear in a doorway, pointing down the street |
| `cop_eye` | 순사의 눈 | a colonial policeman's cap and watchful eyes under the brim, a new barricade behind him |
| `student` | 쫓기는 학생 | a frightened student in a school uniform running into an alley, footsteps behind |
| `rickshaw` | 딱한 인력거꾼 김첨지 | a poor rickshaw puller in the rain offering a ride, worn straw sandals |
| `old_comrade` | 옛 동지와의 재회 | two old comrades recognizing each other across a crowded tram platform |

### 1.12 [2순위] 일제 위협 — `art/threat/{group}` (22장을 9장으로 묶음)

위협 카드는 매일 아침 한 장씩 나온다. 같은 그림을 묶어 쓴다.
공통 뒤에: `oppressive colonial atmosphere, seen from the agents' point of view`

| group | 쓰는 위협 (id) | 프롬프트 |
|---|---|---|
| `dispatch` | surprise_search, mp_reinforce, reinforce, informer_bounty | military police in a column marching out of a gate at dawn |
| `hunt` | arrest_order, tailing | a wanted poster with a blank face, a shadowy tail following at a distance |
| `patrol` | mp_patrol, special_alert, full_alert, emergency_muster | policemen with lanterns and swords patrolling a night street, whistles blowing |
| `checkpoint` | checkpoint_add, blockade, sweep | a checkpoint barricade with barbed wire across a street, a guard checking papers |
| `weather` | curfew, monsoon, air_raid | an empty street in heavy rain at night, curfew bell, searchlights in the sky |
| `money` | house_search, fund_freeze | an overturned room after a house search, a broken cash box, scattered coins |
| `prison` | prison_riot, torture | an empty interrogation room, a single bare bulb over a chair, a barred window (no people, no violence) |
| `calm` | calm_day | a quiet morning alley, laundry drying, a cat on a wall |
| `chaos` | chaos | a confused crowd and overturned carts, police running in different directions |

### 1.13 [2순위] 장면 28장 — `art/scene/{id}`

장면 카드(2막)마다. 공통 뒤에: `interior or close action scene during a night raid, tense, cinematic framing`

**형무소 해방**
| id | 장면 | 프롬프트 |
|---|---|---|
| `prison_wall` | 담 넘기 | agents climbing a high brick prison wall with a rope at night |
| `prison_guards` | 간수 제압 | two agents pinning a guard against a corridor wall, keys falling |
| `prison_keys` | 열쇠 꾸러미 | a heavy ring of iron keys hanging from a jailer's belt, a hand reaching for it |
| `prison_search` | 감방 수색 | a long corridor of cell doors, a lantern searching faces behind bars |
| `prison_bell` | 비상종 | a hand stopping the clapper of a large alarm bell |
| `prison_door` | 옥문 | a massive iron prison gate with a huge lock, a lockpick in trembling hands |

**사령관 암살 (일본군영)**
| id | 장면 | 프롬프트 |
|---|---|---|
| `barracks_wire` | 철조망 | wire cutters cutting through barbed wire at night |
| `barracks_shift` | 보초 교대 | two sentries changing guard, an agent hiding in the shadow of a truck |
| `barracks_ammo` | 탄약고 | stacked ammunition crates in a dark depot, a bomb being placed |
| `barracks_officers` | 장교 숙소 | a corridor of officers' quarters, light under one door, boots outside |
| `barracks_dogs` | 군견 | a guard dog straining on its leash, agents frozen behind a wall |
| `barracks_commander` | 사령관실 | a pistol aimed at a desk lamp in a commander's office, a map on the wall |

**경찰서 폭파 (종로경찰서)**
| id | 장면 | 프롬프트 |
|---|---|---|
| `police_back_door` | 뒷문 잠입 | two agents slipping through the back door of a police station |
| `police_duty` | 당직 순사 | a dozing duty policeman at a front desk, a figure creeping past |
| `police_alarm` | 경보 차단 | a hand cutting the wires of an alarm box on a wall |
| `police_records` | 서류 창고 | shelves of police files, an agent pulling out a dossier |
| `police_cells` | 지하 유치장 | a basement lockup, prisoners' hands reaching through bars |
| `police_bomb` | 폭탄 설치 | a bomb with a fuse placed under a staircase in a police station |

**총독부 점거 (조선총독부)**
| id | 장면 | 프롬프트 |
|---|---|---|
| `gg_gate` | 정문 | agents rushing the main gate of a huge domed stone building |
| `gg_corridor` | 회랑 | a vast marble corridor, agents moving between columns |
| `gg_comms` | 통신실 | a room of telephone switchboards and telegraph machines, cables being pulled |
| `gg_archive` | 문서고 | a dark archive of endless file cabinets, agents barricading the door |
| `gg_guard` | 근위대 | a line of guards with rifles at the top of a grand staircase |
| `gg_flag` | 깃발 | a folded taegukgi being carried up a spiral stair toward the dome |

**경비 강화 (어느 결행에나)**
| id | 장면 | 프롬프트 |
|---|---|---|
| `reinforce_post` | 초소 | a sandbagged guard post with a sentry at night |
| `reinforce_searchlight` | 탐조등 | a sweeping searchlight beam crossing a courtyard |
| `reinforce_dogs` | 군견대 | a handler with several guard dogs at a gate |
| `reinforce_gate` | 철문 | a heavy steel gate slamming shut |

### 1.14 [3순위] 세력 문양 2장 — `assets/ui/faction_*.png`

다른 두 문양(광복군 휘장, 의병 태극기)은 원작 그림이라 그대로 둔다.
```
uy (조선의용대): emblem design, a rifle crossed with a writing brush inside a circle,
  woodcut style, black and seal red on transparent background, no text
ug (경성 지하조직): emblem design, a printing press letter block and a key inside a square seal,
  woodcut style, black and seal red on transparent background, no text
```

---

## 2부. 넣는 법 (구현 작업자용)

그림이 일부만 들어와도 돌아가게 한다. **없으면 지금 그림으로 대신한다.**

### 2.0 원본을 게임용으로 (`game/tools/prep_art.py`)
- 원본은 `그림_원본/{폴더}/{번호}_{이미지이름}.png`(git 밖)에 있다. `game/tools/gen_art.py`의 `parse()`가 원본 경로와 게임용 id를 연결한다. 스크립트가 1.2절 표대로 **가운데를 기준으로 비율에 맞게 자르고**, 크기를 줄여 `game/assets/art/{폴더}/{id}.webp`(품질 80)로 쓴다. 세력 문양만 투명 PNG 256×256으로 `game/assets/ui/`에 덮어쓴다.
- 초상은 3:4로 자를 때 위쪽을 더 남긴다(얼굴이 위에 있으므로 위 30% · 아래 70% 비율로 자름).
- 다시 돌려도 같은 결과가 나오게 한다. 원본이 없는 id는 건너뛰고 목록만 출력한다(몇 장 들어왔는지 보고용).

### 2.1 그림 찾기 도우미
- `ArtV2.get(kind, id, fallback: Texture2D)` 정적 함수를 만든다. `res://assets/art/{kind}/{id}.webp`(없으면 `.png`)가 있으면 그것을, 없으면 `fallback`을 돌려준다. 캐시한다.
- 위협은 `art/threat/{group}`. id→group 표를 `data/v2/threats.json`의 카드에 `"art": "dispatch"`처럼 넣는다(데이터 주도).

### 2.2 붙일 곳
| 그림 | 화면 | 코드 |
|---|---|---|
| 요원 초상 | 요원 고르기 카드(72px 문양 자리를 초상 3:4로) · 명부 줄 얼굴 · 큰 카드 · **보드 말**(동그라미로 잘라 위쪽 얼굴) | `setup_screen_v2.gd` `_card`, `game_screen_v2.gd` `_make_row`·`_char_info`, `board_view_v2.gd` `_token` |
| 미션 종류 · 일제 작전 | 미션 줄 카드 · 큰 카드 · 일제 작전 줄 | `game_screen_v2.gd` `MISSION_ART` · `_op_info` |
| 사연 뒷면 | 손패 사연 카드 · 큰 카드 | `_refresh_hand`, `_saga_info` |
| 아이템 · 이벤트 · 위협 · 장면 | **큰 카드에 그림 띠**(아래 2.3) | `card_peek_v2.gd`, `_threat_info`, `_scene_info` |
| 결행 거점 | 결행 선언 연출(가운데 크게 1.5초) · 2막 결행 줄 머리 | `_play_event`의 `launch` · `_refresh_mid` |
| 엔딩 | 엔딩 종이 맨 위 그림 | `ending_screen_v2.gd` (승리면 `{대상}_win`, 아니면 `fail`) |

### 2.3 큰 카드 그림 띠
- 지금 큰 카드(`CardPeekV2`)의 그림은 머리 옆 64×64다. 정보에 `"illus": Texture2D`가 있으면 **카드 맨 위에 폭 가득 4:3 그림 띠**를 그리고 64px 그림은 숨긴다.
- 화면 밖으로 넘치지 않게 그림 띠 높이는 화면 높이의 35%를 넘지 않는다.

### 2.4 시험과 확인
- 그림 파일이 하나도 없어도 화면 시험이 통과해야 한다(대체 그림).
- tour에 `art` 모드: 요원 고르기 · 명부 · 큰 카드(미션 · 아이템 · 장면) · 결행 선언 · 엔딩을 캡처.
- 웹 빌드 크기를 다시 잰다(목표 30MB 안).

### 2.5 기록
- `game/CREDITS.md` 이미지 표에 `assets/art/**`를 더한다. **만든 방법(사용한 이미지 생성 도구와 사람이 고친 범위)을 사실대로** 적는다. 포트폴리오에서도 같은 문장을 쓴다.
