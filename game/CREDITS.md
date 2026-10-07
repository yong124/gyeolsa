# 크레딧 · 에셋 출처

배포 빌드에 들어가는 에셋의 출처를 기록합니다. 새 에셋을 넣을 때마다 이 표에 추가합니다.

## 원작
- 보드게임 「결사」 기획·아트: 원작 팀 (보드게임 설명서 `5.보드게임_결사_설명서.pdf` 및 `assets/` 원본 이미지)

## 이미지
| 파일 | 내용 | 출처 | 비고 |
|---|---|---|---|
| `assets/ui/title.png` | 타이틀 아트 「光復 IF」 | 원작 팀 (`광복 IF.png`) | 교육기관 로고를 지운 편집본 |
| `assets/ui/board.png` | 보드판 (옛 경성 지도 배경) | 원작 팀 (`베이스 맵.png`) | ⚠️ 지도 원본 출처 미상. 1945년 이전 지도로 추정 |
| `assets/tiles/*.png` | 타일 아트 | 원작 팀 (원본 이미지 및 설명서 PDF에서 추출) | |
| `assets/cards/*.png` | 카드 뒷면·폭탄 카드 | 원작 팀 | |
| `assets/ui/faction_kb.png`, `faction_ub.png` | 세력 문양 (광복군 · 의병) | 원작 팀 (설명서 PDF에서 추출) | 조선의용대 · 지하조직 문양은 아래 AI 생성으로 바뀜 |
| `assets/ui/police.png` | 순사 제모 토큰 | 코드로 직접 그림 (Python PIL) | 욱일기 이미지를 대체 |
| `assets/ui/paper_*.png`, `desk.png` | 종이 패널·카드 재질, 책상 배경 | `tools/gen_ui_art.py`로 직접 생성 (잡음 합성) | |
| `assets/art/**/*.webp` (91장 + 보드 말 12장) | v2 그림: 요원 초상 12, 미션 7, 일제 작전 4, 사연 카드 뒷면, 결행 거점 4, 엔딩 5, 아이템 10, 이벤트 10, 위협 9, 장면 28 | **AI 이미지 생성** (OpenAI GPT 이미지 생성, Codex에서 실행). 그림체 기준 1장(윤 소위)을 사용자가 고르고, 나머지는 그 그림을 참고 이미지로 붙여 생성. 프롬프트는 `v2_구현/그림_프롬프트_GPT.md`. 전체 검토(사용자 요청으로 Claude Code가 검토하고 사용자가 확인) 뒤 10장을 다시 생성(닮은 얼굴 2, 일장기처럼 읽히는 붉은 해 7, 정책 거절 1). 손으로 그리거나 고친 그림은 없음 | 원본은 저장소 밖 `그림_원본/`. `tools/prep_art.py`로 자르고 줄여 WebP로 변환 |
| `assets/ui/faction_uy.png`, `faction_ug.png` | 조선의용대 · 경성 지하조직 문양 | 위와 같은 AI 이미지 생성 (원작 팀 문양을 대체) | |
| `assets/ui/icons/*.svg` | 행동 버튼 아이콘 (주사위, 무전, 건네기, 미끼, 교체, 탈옥, 메뉴 등) | 직접 그린 SVG | |

## 폰트
| 파일 | 출처 | 라이선스 |
|---|---|---|
| `assets/fonts/NotoSansKR-VF.ttf` | Google Noto Sans KR (가변 굵기, 본문) | SIL Open Font License 1.1 |
| `assets/fonts/NotoSerifKR-VF.ttf` | Google Noto Serif KR (가변 굵기, 제목) | SIL Open Font License 1.1 |

라이선스 전문: `assets/fonts/OFL.txt` (배포 zip에는 `글꼴_라이선스_OFL.txt`)

## 사운드
| 파일 | 내용 | 출처 |
|---|---|---|
| `assets/sfx/*.wav` (11종) | 주사위, 발걸음, 타일, 카드, 성공, 실패, 호루라기, 날짜 종, 경고, 클릭, 광복 상승 | `tools/gen_sfx.py`로 직접 합성 (외부 음원 없음) |
| `assets/music/*.wav` (3곡) | 평상시(main), 긴장(tension), 엔딩(ending) | `tools/gen_bgm.py`로 직접 합성 (외부 음원 없음) |

## 역사 해설
엔딩의 "실제 역사에서는" 문구(`data/text.json`의 `history_notes`)는 널리 알려진 사실만 담았습니다. 배포 전에 원작 팀이 한 번 더 확인합니다 (PRD Q8).

## 사용하지 않는 에셋
- `assets/옆면.png` (박스 옆면): 교육기관 로고가 있어 빌드에서 제외
