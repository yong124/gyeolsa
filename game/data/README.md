# 데이터 편집 가이드

게임의 수치, 카드, 세력은 전부 이 폴더의 JSON 파일에 들어 있습니다. **코드를 고치지 않고** 파일만 수정하면 게임에 반영됩니다.

| 파일 | 내용 |
|---|---|
| `balance.json` | 보드 배치, 타일 수, 날짜 트랙, 판정 기준, 경찰, 목표 광복수치 |
| `factions.json` | 세력 이름·설명·문양·특성 |
| `cards.json` | 이벤트·아이템·폭탄·미션 카드 |
| `text.json` | 타이틀, 시놉시스, 엔딩 문구, 도움말 |

수정한 뒤에는 검증 테스트를 돌려 오타가 없는지 확인하세요.

```bash
godot --headless --path game --script res://tests/data_test.gd
```

밸런스가 어떻게 바뀌었는지는 시뮬레이션으로 확인합니다. 인원별로 500판씩 AI끼리 돌립니다.

```bash
godot --headless --path game --script res://tests/sim_test.gd -- 500
```

---

## 1. 카드 예시

### 아이템: 지속 보정 (가지고 있는 동안 효과)
```json
{"id": "boots", "name": "전투화", "count": 1, "kind": "persistent", "ai_value": 7,
 "text": "질기고 단단한 미국제 전투화입니다.",
 "effect_text": "(지속) 이동 +1",
 "modifiers": [{"stat": "move_bonus", "value": 1}]}
```

### 아이템: 직접 사용
```json
{"id": "ticket", "name": "승차권", "count": 3, "kind": "consumable",
 "use": {"phases": ["move"], "consume": true,
         "effects": [{"op": "add_steps", "value": 3}]}}
```

### 아이템: 상황이 오면 사용 여부를 물음 (react)
```json
{"id": "smoke", "name": "연막탄",
 "react": {"trigger": "evade", "effect": "auto_success", "consume": true,
           "prompt": "연막탄을 써서 회피 판정을 자동 성공시키겠습니까?"}}
```

### 이벤트
```json
{"id": "trip", "name": "꽈당", "count": 4, "bad": true,
 "text": "한눈팔던 소년 노동자와 부딪혔습니다.",
 "effect_text": "다음 차례 이동 -1",
 "effects": [{"op": "move_mod", "value": -1}]}
```

### 공통 필드
| 필드 | 설명 |
|---|---|
| `id` | 고유 이름 (영문). 코드와 데이터가 이 이름으로 카드를 찾습니다 |
| `name`, `text`, `effect_text` | 화면에 보이는 이름, 설명, 효과 문구 |
| `count` | 덱에 들어가는 장수 |
| `kind` | `persistent`(지속) 또는 `consumable`(소모). 화면 표시용 |
| `ai_value` | AI가 아이템을 버릴 때 쓰는 가치. 낮을수록 먼저 버림 |
| `bad` | 이벤트가 해로운지. AI가 신호탄을 쓸지 판단할 때 사용 |
| `image` | (선택) 카드 팝업에 쓸 이미지 경로 |

---

## 2. 효과 연산 `op` (effects 안에 씀)

| op | 추가 값 | 효과 |
|---|---|---|
| `add_steps` | `value` | 이번 차례 남은 이동 +value |
| `move_mod` | `value` | 다음 차례 이동 ±value |
| `remove_my_police` | – | 나를 쫓는 경찰 제거 |
| `remove_all_police` | – | 모든 경찰 제거 |
| `skip_next_turn` | – | 다음 차례 쉼 |
| `police_next_turn` | – | 다음 차례 시작 시 내 자리에 경찰 소환 |
| `summon_police` | – | 지금 내 자리에 경찰 소환 |
| `free_all_jailed` | – | 감옥의 모든 요원 탈옥 (경찰 없음) |
| `escape_jail` | `summon` (true/false) | 나만 탈옥. summon이 true면 경찰 소환 |
| `add_score` | `value` | 광복수치 +value |
| `draw_item` | – | 아이템 1장 뽑기 (한도 초과 시 버릴 카드 선택) |
| `discard_item` | – | 가진 아이템 1장 버리기 (2장 이상이면 선택) |
| `target_move_mod` | `value` | (세력 능력 전용) 고른 동료의 다음 차례 이동 ±value |
| `remove_target_police` | – | (세력 능력 전용) 고른 경찰 제거 |
| `pull_target` | – | (세력 능력 전용) 고른 동료를 내 옆 빈칸으로 데려옴 |

효과는 적힌 순서대로 실행됩니다. 예: `[{"op": "remove_all_police"}, {"op": "skip_next_turn"}]`

---

## 3. 보정 `stat` (modifiers 안에 씀)

| stat | 기본값 | 의미 |
|---|---|---|
| `move_bonus` | 0 | 이동 칸 수 ±value |
| `move_min` | 0 | 이동 주사위 최소값 (의병: 3, `"mode": "max"`) |
| `assassin_bonus` | 0 | 암살 판정 주사위 합 +value |
| `assassin_threshold` | 9 | 암살 성공 기준. `"mode": "min"`이면 더 낮은 쪽을 씀 (저격총: 7) |
| `assassin_rerolls` | 0 | 암살 실패 시 다시 굴리는 횟수 |
| `evade_bonus` | 0 | 회피 판정 주사위 합 +value |
| `evade_auto` | 0 | 1이면 회피 판정 항상 성공 |
| `evade_auto_after_assassin` | 0 | 1이면 암살 직후 회피 판정 항상 성공 |
| `escape_bonus` | 0 | 탈옥 판정 주사위 합 +value |
| `base_no_police` | 0 | 1이면 거점에 들어가도 경찰이 소환되지 않음 |

`mode`는 여러 보정을 합치는 방식입니다. `add`(기본, 더하기), `min`(작은 값), `max`(큰 값), `set`(덮어쓰기) 중 하나입니다.

`when`을 붙이면 조건이 맞을 때만 적용됩니다. 예: `{"stat": "base_no_police", "value": 1, "when": {"alert_max": 2}}`

---

## 4. 조건 (use.requires, modifiers.when 안에 씀)

| 조건 | 값 | 의미 |
|---|---|---|
| `alert_max` | 1~3 | 경계 단계가 값 이하일 때 |
| `alert_min` | 1~3 | 경계 단계가 값 이상일 때 |
| `jailed` | true/false | 감옥에 있을 때만 / 없을 때만. 아이템 사용 조건에 없으면 감옥에서는 못 씀 |
| `has_my_police` | true/false | 나를 쫓는 경찰이 있을 때 |
| `any_police` | true/false | 보드에 경찰이 하나라도 있을 때 |
| `other_items_min` | 숫자 | 이 카드 말고도 아이템을 N장 이상 가졌을 때 |

---

## 5. 아이템 사용 `use`

| 필드 | 설명 |
|---|---|
| `phases` | 쓸 수 있는 시점. `start`(주사위 굴리기 전), `move`(이동 중) |
| `requires` | 사용 조건 (4번 표) |
| `cost.discard_other` | 대가로 다른 아이템을 N장 버림 (뇌물) |
| `consume` | true면 쓰고 나서 버림 |
| `ends_turn` | true면 쓰고 나서 차례 종료 (옷핀) |
| `effects` | 실행할 효과 목록 (2번 표) |

## 6. 자동 발동 `react`

| trigger | effect | 언제 |
|---|---|---|
| `evade` | `auto_success` | 회피 판정 직전에 "쓰겠습니까?"를 묻고, 쓰면 자동 성공 |
| `event` | `cancel_event` | 이벤트 카드를 뽑은 직전에 묻고, 쓰면 이벤트 무효 |

---

## 7. 세력 능력 `active` (factions.json)
하루에 한 번 쓰는 능력입니다. 대상은 화면에서 고릅니다.
```json
"active": {"name": "무전 지원", "desc": "동료 1명의 다음 차례 이동 +1",
           "phases": ["start", "move"], "target": "ally",
           "effects": [{"op": "target_move_mod", "value": 1}]}
```
| target | 고를 수 있는 대상 |
|---|---|
| `ally` | 감옥에 없는 동료 |
| `ally_pullable` | 감옥에 없고, 나와 붙어 있지 않은 동료 (내 옆에 빈칸이 있어야 함) |
| `police_near` | 내 위치에서 `range` 칸 안의 경찰 (0이면 내 칸만) |

## 8. 일제 동향 덱 `occupation` (cards.json)
둘째 날부터 매일 아침 1장을 뽑아 판 전체에 적용합니다. 특정 요원이 아니라 **판 전체**에 걸리는 연산을 씁니다.

| op | 추가 값 | 효과 |
|---|---|---|
| `place_checkpoints` | `value` | 무작위 요원 value명의 옆 빈칸에 검문소 설치 |
| `raid_police` | `value` | 무작위 거점에서 경찰이 나와, 경찰에 쫓기지 않는 가장 가까운 요원을 쫓음 |
| `police_advance` | `value` | 추격 중인 경찰이 모두 즉시 value칸 다가옴 (닿으면 체포) |
| `all_move_mod` | `value` | 모든 요원의 이번 날 이동 ±value |
| `police_speed_today` | `value` | 오늘 경찰 이동 ±value |

`effects`를 빈 배열로 두면 아무 일도 없는 카드가 됩니다(평온한 하루). `balance.json`의 `occupation.enabled`를 false로 하면 덱을 끌 수 있습니다.

## 9. balance.json 주요 항목

| 항목 | 설명 |
|---|---|
| `board.bases` | 거점 좌표와 이름 (정보탈취 미션, 감옥) |
| `board.stations` | 전차 역 좌표 |
| `board.map` | 보드 이미지와 격자 위치 (이미지를 바꾸면 origin·cell도 맞춰야 함) |
| `tiles` | 타일 종류별 이름, 장수, 이미지 |
| `calendar.rounds_by_players` | 인원별 작전 일수. **하루 늘리면 대성공 확률이 약 10%p 오릅니다** |
| `goal_by_players` | 인원별 목표 광복수치 |
| `checks` | 암살·회피·탈옥 판정 기준 (주사위 2개 합) |
| `police.speed_by_alert` | 경계 1~3단계 경찰 이동 칸 수 |
| `police.speed_mod_by_players` | 인원별 경찰 이동 보정 (2인 −1) |
| `police.rescued_player_summons` | 구출된 요원에게 경찰을 소환할지 |
| `endings` | 엔딩 구간 (`min_score`가 −1이면 목표치 달성) |
| `cooperation.give_range` | 아이템을 건넬 수 있는 거리 (1 = 옆 칸) |
| `cooperation.give_counts_as_item_use` | 건네기를 아이템 사용 횟수(차례당 2회)에 포함할지 |
| `cooperation.decoy_range` | 미끼로 끌어올 수 있는 경찰까지의 거리 |
| `cooperation.decoy_per_turn` | 한 차례에 미끼를 쓸 수 있는 횟수 |
| `occupation.enabled` | 일제 동향 덱 사용 여부 |

## 10. 세력 추가하기
`factions.json`에 항목을 하나 더 넣으면 타이틀 화면의 세력 목록에 바로 나타납니다.
```json
"kh": {"name": "새 세력", "emblem": "res://assets/ui/faction_kb.png",
       "desc": "설명", "ability": "특성 요약",
       "modifiers": [{"stat": "evade_bonus", "value": 2}]}
```
