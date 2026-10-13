# 결사 — 1945, 경성 (Godot 프로젝트)

Godot 4.7로 만든 1인 + AI 동료 3명 협력 게임입니다. 규칙은 `../docs/기획/결사_규칙서_v2.html`을 따릅니다. 처음 만든 규칙(v1) 코드는 지웠고, 기획 문서만 `../docs/기획/`에 기록으로 남아 있습니다.

## 실행
- Godot 4.7.1에서 `project.godot`을 열고 F5를 누릅니다.
- 명령줄: `godot --path game`
- 실행 인자
  - `-- v2`: 메뉴를 건너뛰고 요원 고르기부터 시작합니다.
  - `-- server [port=8910]`: 온라인 서버 (헤드리스)
  - `-- v2uitest [판 수]`: 화면으로 판을 끝까지 두는 시험
  - `-- tour out=<폴더> [모드]`: 화면 캡처 (개발용, 모드는 `tools/tour.gd` 맨 위)

## 폴더 구조
```
game/
├─ data/v2/               ← 규칙 수치 · 카드 · 문장 · 튜토리얼 대본 (JSON). 파일별 열쇠는 ../v2_구현/데이터_구조.md
├─ assets/                ← 그림 · 글꼴 · 소리
├─ scenes/main.tscn
├─ scripts/
│  ├─ core/v2/            ← 화면과 무관한 게임 로직
│  │  ├─ game_data_v2.gd  데이터 로드 · 조회 · 검증
│  │  ├─ rules_v2.gd      규칙 엔진 (액션 → 상태 변화 + 연출 이벤트)
│  │  └─ ai_v2.gd         AI 동료의 판단
│  ├─ net/                ← 온라인: 서버 권위 · 보기 거르기 · 클라이언트
│  └─ ui/                 ← 화면
│     ├─ main.gd          화면 흐름 (도입부 → 메뉴 → 게임 · 튜토리얼 · 온라인 → 엔딩)
│     ├─ title_screen.gd  첫 화면 (바로 시작 · 이어하기 · 튜토리얼 · 온라인)
│     ├─ style.gd · ui_kit.gd · overlay.gd   디자인 체계와 공용 위젯
│     ├─ fx_layer.gd      판정 주사위 · 배너 · 날짜 넘김 연출
│     ├─ settings_panel.gd · prefs.gd · sfx.gd · music.gd
│     └─ v2/              게임 화면(game_screen_v2)과 역할별 모듈, 튜토리얼, 엔딩, 요원 고르기, 온라인 로비
├─ tests/                 ← 헤드리스 시험 (v2_*)
└─ tools/                 ← 개발 도구 (빌드에서 제외): 밸런스 측정 · 성능 · 화면 캡처 · 웹 빌드 · 그림 · 글꼴 · 소리
```

## 설계 원칙
- **규칙과 화면 분리:** `RulesV2`는 화면을 모릅니다. UI는 `apply(action)`으로 조작하고, `events` 큐와 상태를 읽어 그립니다.
- **데이터 주도:** 규칙 수치 · 카드 · 문장은 `data/v2/*.json`에 있고, 코드에 카드 id나 밸런스 수치를 쓰지 않습니다. 검증기(`game_data_v2.gd`)가 오타 · 모르는 효과 · 빠진 필드를 잡습니다.
- **같은 시드 = 같은 판:** 액션만 주고받으면 모든 클라이언트의 상태가 같아집니다 (온라인 · 저장).

## 시험
```bash
godot --headless --path game --script res://tests/v2_data_test.gd        # 데이터 검증
godot --headless --path game --script res://tests/v2_mechanics_test.gd   # 규칙 시험
godot --headless --path game --script res://tests/v2_engine_test.gd      # 엔진 200판
godot --headless --path game --script res://tests/v2_ai_test.gd          # AI 220판 (멈춤 · 반칙 0)
godot --headless --path game --script res://tests/v2_validator_selftest.gd
godot --headless --path game --script res://tests/v2_net_test.gd         # 온라인
godot --headless --path game -- v2uitest 1                              # 화면으로 한 판
godot --headless --path game --script res://tools/v2_balance.gd -- games=1000   # 밸런스 측정
```

## 빌드
- 웹(itch.io): 프로젝트 루트에서 `powershell -ExecutionPolicy Bypass -File game\tools\build_web.ps1 -Version 2.2.0` → `build/web/`, `build/GwangbokIF_web_v2.2.0.zip`
- 온라인 서버: `../v2_구현/서버_배포.md`
