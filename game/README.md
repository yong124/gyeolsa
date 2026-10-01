# 광복 IF (보드게임 「결사」 디지털판)

Godot 4.7로 만든 1인 + AI 동료 협력 게임입니다. 규칙은 `../결사_기획서.md` v1.3을 따릅니다.

## 실행
- Godot 4.7.1에서 `project.godot`을 열고 F5를 누릅니다.
- 명령줄: `godot --path game`
- 이동 중 효과 없이 지나온 공개 칸은 `Backspace` 또는 화면의 `되돌리기` 버튼으로 되돌릴 수 있습니다. 이동이 남았을 때 `Space`로 종료하면 확인창이 열립니다.
- 테스트용 인자
  - `-- autostart`: 설정 화면을 건너뛰고 바로 시작합니다.
  - `-- autostart autoplay`: 내 자리도 AI가 조작합니다 (화면 확인·녹화용).

## 폴더 구조
```
game/
├─ data/                  ← 게임 수치·카드·문구 (JSON). 편집법은 data/README.md
├─ assets/                ← 이미지·폰트 (ui/paper_*·desk는 tools/gen_ui_art.py로 생성, ui/icons는 SVG)
├─ scenes/main.tscn
├─ scripts/
│  ├─ core/               ← 화면과 무관한 게임 로직
│  │  ├─ game_data.gd     데이터 로드·조회·검증
│  │  ├─ rules.gd         규칙 엔진 (액션 → 상태 변화)
│  │  └─ ai.gd            AI 동료의 판단
│  └─ ui/                 ← 화면
│     ├─ main.gd          화면 흐름 (도입부 → 메뉴 → 게임/튜토리얼 → 엔딩)
│     ├─ intro_screen.gd  도입부 (첫 실행 시)
│     ├─ style.gd         디자인 체계: 색·글꼴·종이 재질·버튼 종류·테마 ("기밀 작전 문서" 톤)
│     ├─ fx_layer.gd      판정(주사위+도장)·결과 띠·날짜 넘김·경보·날아가는 점수/카드
│     ├─ prefs.gd         설정 (autoload "Prefs")
│     ├─ sfx.gd           효과음 (autoload "Sfx")
│     ├─ title_screen.gd  메인 메뉴·새 작전 설정
│     ├─ ending_screen.gd 엔딩·작전 보고서·역사 해설
│     ├─ settings_panel.gd 설정 창
│     ├─ rulebook.gd      규칙 도감 (데이터에서 자동 생성)
│     ├─ save_game.gd     자동 저장·이어하기
│     ├─ music.gd         배경음 (autoload "Music")
│     ├─ game_screen.gd   게임 화면: 부품 배치, 연출 큐 재생, AI 차례 진행
│     ├─ top_bar.gd       상단 바: 달력·남은 날·광복수치 게이지·경계 단계·오늘의 일제 동향
│     ├─ agent_panel.gd   요원 명부: 초상·미션/아이템/상태 칩(툴팁)·차례 도장
│     ├─ hand_panel.gd    내 손패: 미션·아이템 카드, 폭탄 슬롯 (쓸 수 있는 카드는 빛남)
│     ├─ action_bar.gd    지금 할 일 + 주 행동 버튼 + 보조 행동(능력·건네기·미끼·교체)
│     ├─ log_ticker.gd    작전 기록 한 줄 + 펼치는 서랍
│     ├─ board_view.gd    보드 그리기·클릭
│     ├─ card_view.gd     카드 앞면 (손패의 작은 카드, 가운데 뜨는 큰 카드)
│     ├─ overlay.gd       반투명 오버레이
│     └─ ui_kit.gd        공용 위젯 헬퍼 (라벨·버튼·서류 창·도장)
├─ tests/                 ← 헤드리스 테스트
└─ tools/                 ← 개발 도구 (빌드에서 제외)
   ├─ gen_sfx.py, gen_bgm.py  효과음·배경음 합성
   ├─ gen_ui_art.py           종이·책상 재질 텍스처 생성
   ├─ tour.gd                 화면 둘러보기 캡처: godot --path game -- tour out=<폴더> [w=1366 h=768] [store | act2]
   └─ build_release.ps1       출시 빌드
```

## 설계 원칙
- **규칙과 화면 분리:** `GameRules`는 화면을 모릅니다. UI는 `apply(action)`으로 조작하고, `events` 큐와 상태를 읽어 그립니다.
- **연출 큐:** 엔진은 상태를 즉시 바꾸고 이벤트(`move`, `dice`, `banner`, `day` …)를 쌓습니다. 각 이벤트에는 그 시점의 요원·경찰 위치 스냅숏이 들어 있습니다. `GameScreen`은 이벤트를 하나씩 `await`로 재생하고, 큐가 비면 보드를 실제 상태와 맞춥니다.
- **온라인 멀티 대비:** 같은 시드로 엔진을 만들고 액션(`{"type": "step", "to": ...}` 등)만 주고받으면 모든 클라이언트의 상태가 같아집니다.
- **디자인 체계:** 화면 코드는 색·글꼴을 직접 적지 않고 `Style`(style.gd)의 값과 버튼 종류(primary/paper/dark/tab)를 씁니다. 톤을 바꾸려면 style.gd만 고칩니다.
- **데이터 주도:** 카드 효과는 코드가 아니라 `data/cards.json`의 효과 연산(`op`)과 보정(`stat`)의 조합입니다. 새 연산이 필요할 때만 `rules.gd`의 `_effect()`에 추가하고, `game_data.gd`의 `KNOWN_OPS`에 이름을 등록합니다.

## 출시 빌드
익스포트 템플릿(4.7.1)을 설치한 뒤 프로젝트 루트에서:
```
powershell -ExecutionPolicy Bypass -File game\tools\build_release.ps1
```
테스트 → Windows 내보내기 → 실행 파일로 한 판 자동 검증 → `build/GwangbokIF_v1.1.0_win64.zip`. 자세한 절차는 `release/출시_체크리스트.md`.

## 테스트
```bash
# 데이터 검증 (오타, 알 수 없는 효과 이름)
godot --headless --path game --script res://tests/data_test.gd
# AI끼리 인원별 N판 → 엔딩 확률, 불법 액션·교착 검사
godot --headless --path game --script res://tests/sim_test.gd -- 500
# 경로 미리보기 검증 (계산한 경로를 실제로 걸을 수 있는지)
godot --headless --path game --script res://tests/path_test.gd -- 100
# 저장·불러오기 (불러온 게임이 원본과 똑같이 진행되는지)
godot --headless --path game --script res://tests/save_test.gd -- 60
# 튜토리얼 시나리오 (설정 적용, 이길 수 있는지)
godot --headless --path game --script res://tests/tutorial_test.gd
# 세력 밸런스 (4인 모두 같은 세력)
godot --headless --path game --script res://tests/faction_test.gd -- 500
```

### 2막 구조 검증
```bash
# 인원별(2~4인) 대성공·결행 시점·거점 선택률·사건별 성공률
godot --headless --path game --script res://tests/act2_test.gd -- 500
```

### 플레이테스트 · 규칙 정돈
```bash
# 기록 재생: 시드 + 액션 목록으로 다시 두면 같은 결말이 나오는지
godot --headless --path game --script res://tests/replay_test.gd -- 60
# 플레이테스트 기록 요약 (폴더를 안 주면 이 컴퓨터의 user://playtests)
godot --headless --path game --script res://tools/playtest_report.gd -- [폴더] [md=요약.md]
# 규칙별 사용 빈도와, 하나씩 껐을 때의 승률·판 길이 변화 (보고서용, 오래 걸림)
godot --headless --path game --script res://tests/rule_audit.gd -- 300 [md=결과.md]
```
- 새 작전에서 **사람** 수를 2명 이상으로 고르면 한 컴퓨터에서 돌아가며 두는 핫시트가 됩니다. 사람 차례가 바뀔 때마다 "자리 교대" 안내가 뜹니다.
- 설정의 **플레이테스트**가 켜져 있으면(기본) 판마다 `user://playtests/날짜_시각.json`에 설정·시드·액션 전부·매일 아침 상태·사람의 생각 시간이 남고, 판이 끝나면 설문을 받습니다. 설정 창의 [기록 폴더 열기]로 파일을 찾을 수 있습니다.
- 규칙 끄기 실험: `GameRules.scenario["off"]`에 `ability, give, decoy, swap, items, events, occupation, exposure, vote` 중 원하는 것을 넣습니다.
