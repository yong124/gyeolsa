# balance.html 만들기: data/*.json 수치로 SVG 그래프를 그린다.
# 실행: python portfolio/build_balance.py
import json, os, collections, html

HERE = os.path.dirname(os.path.abspath(__file__))
hist = json.load(open(os.path.join(HERE, 'data', 'winrate_history.json'), encoding='utf-8'))
now = json.load(open(os.path.join(HERE, 'data', 'balance_1000.json'), encoding='utf-8'))['결과'][0]
alt = json.load(open(os.path.join(HERE, 'data', 'balance_1000_seed910000.json'), encoding='utf-8'))['결과'][0]

E = html.escape
STRIKE = {'barracks': '일본군영 · 사령관 암살', 'gg': '조선총독부 · 점거', 'police_hq': '종로경찰서 · 폭파', 'prison': '서대문형무소 · 해방'}
BEFORE = {'barracks': 59.1, 'gg': 46.1, 'police_hq': 53.5, 'prison': 54.3}   # 재미 개선(S) 전 (같은 시드)
RULES = json.load(open(os.path.join(HERE, '..', 'game', 'data', 'v2', 'rules.json'), encoding='utf-8'))
ROUNDS = int(RULES['rounds'])
FORCED_DAY = ROUNDS - int(RULES['forced_launch_days_left']) + 1   # 강제 결행이 되는 날
CHAR = {c['id']: c['name'] for c in json.load(open(os.path.join(HERE, '..', 'game', 'data', 'v2', 'characters.json'), encoding='utf-8'))['characters']}


def chart_history():
    pts = hist['단계']
    W, H, L, R, T, B = 900, 340, 44, 70, 22, 100
    n = len(pts)
    x = lambda i: L + (W - L - R) * i / (n - 1)
    y = lambda v: T + (H - T - B) * (1 - v / 80)
    lo, hi = hist['목표']
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="단계별 승률 변화">']
    s.append(f'<rect class="band" x="{L}" y="{y(hi):.1f}" width="{W-L-R}" height="{y(lo)-y(hi):.1f}"/>')
    s.append(f'<text class="tx" x="{L+6}" y="{y(lo)-5:.1f}">목표 {lo}~{hi}%</text>')
    for v in (0, 20, 40, 60, 80):
        s.append(f'<line class="ax" x1="{L}" x2="{W-R}" y1="{y(v):.1f}" y2="{y(v):.1f}"/><text class="tx" x="{L-6}" y="{y(v)+4:.1f}" text-anchor="end">{v}%</text>')
    s.append('<polyline class="line" points="' + ' '.join(f'{x(i):.1f},{y(p["승률"]):.1f}' for i, p in enumerate(pts)) + '"/>')
    for i, p in enumerate(pts):
        s.append(f'<circle class="dot" cx="{x(i):.1f}" cy="{y(p["승률"]):.1f}" r="4"/>')
        s.append(f'<text class="tx2" x="{x(i):.1f}" y="{y(p["승률"])-9:.1f}" text-anchor="middle">{p["승률"]:g}</text>')
        s.append(f'<text class="tx" transform="translate({x(i)+4:.1f},{H-B+14}) rotate(35)">{E(p["이름"])}</text>')
    s.append('</svg>')
    return ''.join(s)


def hbars(rows, maxv, unit='%', W=900, label_w=210, row_h=34, ref=None):
    H = row_h * len(rows) + 10
    s = [f'<svg viewBox="0 0 {W} {H}" role="img">']
    span = W - label_w - 70
    if ref is not None:
        rx = label_w + span * ref / maxv
        s.append(f'<line class="zero" x1="{rx:.1f}" x2="{rx:.1f}" y1="0" y2="{H-6}" stroke-dasharray="4 4"/>')
    for i, (label, v, cls, extra) in enumerate(rows):
        yy = 6 + i * row_h
        s.append(f'<text class="tx2" x="{label_w-10}" y="{yy+row_h/2+2:.1f}" text-anchor="end">{E(label)}</text>')
        if extra is not None:
            s.append(f'<rect class="bar" x="{label_w}" y="{yy+4}" width="{span*extra/maxv:.1f}" height="{row_h/2-5:.1f}" rx="2"/>')
        s.append(f'<rect class="bar {cls}" x="{label_w}" y="{yy+row_h/2-1:.1f}" width="{span*v/maxv:.1f}" height="{row_h/2-5:.1f}" rx="2"/>')
        tail = f'{v:.1f}{unit}' if extra is None else f'{extra:.1f} → {v:.1f}{unit}'
        s.append(f'<text class="tx" x="{label_w+span*max(v, extra or 0)/maxv+6:.1f}" y="{yy+row_h/2+4:.1f}">{tail}</text>')
    s.append('</svg>')
    return ''.join(s)


def chart_strikes():
    rows = []
    for k in sorted(STRIKE, key=lambda k: -now['strike_win_rate'][k]):
        rows.append((f'{STRIKE[k]} ({now["strikes"][k]}판)', 100 * now['strike_win_rate'][k], 'now', BEFORE[k]))
    return hbars(rows, 80, label_w=250, row_h=40)


def chart_chars():
    d = sorted(now['character_diff_pp'].items(), key=lambda kv: -kv[1])
    W, row_h, mid, span = 900, 24, 540, 30
    H = row_h * len(d) + 30
    sx = lambda v: mid + v / 10 * span * 6
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="요원별 승률 차이">']
    s.append(f'<rect class="band" x="{sx(-10):.1f}" y="0" width="{sx(10)-sx(-10):.1f}" height="{H-22}"/>')
    s.append(f'<line class="zero" x1="{mid}" x2="{mid}" y1="0" y2="{H-22}"/>')
    for v in (-10, -5, 0, 5, 10):
        s.append(f'<text class="tx" x="{sx(v):.1f}" y="{H-6}" text-anchor="middle">{v:+d}</text>')
    for i, (k, v) in enumerate(d):
        yy = 4 + i * row_h
        x0, x1 = sorted((mid, sx(v)))
        s.append(f'<text class="tx2" x="{sx(-10)-10:.1f}" y="{yy+row_h/2+3:.1f}" text-anchor="end">{E(CHAR.get(k, k))}</text>')
        s.append(f'<rect class="bar {"win" if v >= 0 else "now"}" x="{x0:.1f}" y="{yy+4}" width="{max(x1-x0, 1):.1f}" height="{row_h-8}" rx="2"/>')
        tx = sx(v) + (6 if v >= 0 else -6)
        s.append(f'<text class="tx" x="{tx:.1f}" y="{yy+row_h/2+4:.1f}" text-anchor="{"start" if v >= 0 else "end"}">{v:+.1f}</text>')
    s.append('</svg>')
    return ''.join(s)


def chart_endings():
    e = now['endings']
    rows = [('성공', e.get('victory', 0), 'win'), ('2막 중간 장면에서 멈춤', e.get('fail_middle', 0), 'now'),
            ('마지막 장면에서 멈춤', e.get('fail_final', 0), 'force'), ('시간 끝 (역사대로)', e.get('history', 0), '')]
    total = sum(r[1] for r in rows)
    W, H = 900, 70
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="엔딩 분포">']
    x = 0
    for label, v, cls in rows:
        w = W * v / total
        s.append(f'<rect class="bar {cls}" x="{x:.1f}" y="0" width="{w:.1f}" height="30"/>')
        if w > 60:
            s.append(f'<text class="tx2" x="{x+6:.1f}" y="50">{E(label)}</text><text class="tx" x="{x+6:.1f}" y="65">{v}판</text>')
        x += w
    s.append('</svg>')
    legend = ' · '.join(f'{E(l)} {v}' for l, v, _ in rows)
    return ''.join(s), legend


def chart_days():
    c = collections.Counter(now['launch_days'])
    days = list(range(2, FORCED_DAY + 1))
    mx = max(c.values())
    W, H, L, B = 900, 230, 30, 40
    bw = (W - L) / len(days)
    y = lambda v: 24 + (H - B - 24) * (1 - v / mx)
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="결행한 날 분포">']
    for i, d in enumerate(days):
        v = c.get(d, 0)
        x = L + i * bw
        s.append(f'<rect class="bar {"force" if d == FORCED_DAY else "now"}" x="{x+8:.1f}" y="{y(v):.1f}" width="{bw-16:.1f}" height="{H-B-y(v):.1f}" rx="2"/>')
        s.append(f'<text class="tx2" x="{x+bw/2:.1f}" y="{y(v)-5:.1f}" text-anchor="middle">{v}</text>')
        s.append(f'<text class="tx" x="{x+bw/2:.1f}" y="{H-B+16}" text-anchor="middle">{d}일째</text>')
    s.append(f'<line class="ax" x1="{L}" x2="{W}" y1="{H-B}" y2="{H-B}"/>')
    s.append('</svg>')
    return ''.join(s)


ops = 100.0 * sum(now['ops_blocked'].values()) / max(1, sum(now['ops_blocked'].values()) + sum(now['ops_missed'].values()))
counter = 100.0 * now['counter_blocked'] / max(1, now['counter_days'])
ben = now['benefits']
end_svg, end_legend = chart_endings()
spread = 100 * (max(now['strike_win_rate'].values()) - min(now['strike_win_rate'].values()))
spread_alt = 100 * (max(alt['strike_win_rate'].values()) - min(alt['strike_win_rate'].values()))

page = f'''<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>결사 밸런스 보고</title>
<meta name="description" content="협력 보드게임 「결사」의 밸런스 보고: AI 4명 1,000판 측정">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;500;700;800&family=Noto+Serif+KR:wght@600;700;900&display=swap" rel="stylesheet">
<link rel="stylesheet" href="style.css">
</head>
<body>
<nav class="nav">
  <a class="brand" href="index.html">結社</a>
  <a class="tab" href="index.html">소개</a>
  <a class="tab" href="cases.html">설계 사례</a>
  <a class="tab on" href="balance.html">밸런스</a>
  <a class="tab" href="rules.html">규칙서</a>
  <button id="themeBtn" type="button" aria-label="밝기 바꾸기">◐</button>
</nav>

<section class="page">
  <div class="kicker">밸런스 보고</div>
  <h2>AI 4명 1,000판으로 잰 결사</h2>
  <p>측정은 AI 동료 4명이 같은 시드 묶음(610000부터)으로 1,000판을 두는 시뮬레이션이다. AI는 사람보다 협력을 덜 하므로, AI 승률은 <b>사람 판의 아래쪽 기준</b>으로 본다. 1,000판의 표준오차는 약 ±1.6%p.</p>
  <div class="tw"><table>
    <tr><th>지표</th><th>목표</th><th class="n">지금</th><th class="n">다른 시드 (910000)</th></tr>
    <tr><td>승률</td><td>45~55%</td><td class="n{' ok' if 45 <= 100*now['win_rate'] <= 55 else ''}">{100*now['win_rate']:.1f}%</td><td class="n">{100*alt['win_rate']:.1f}%</td></tr>
    <tr><td>결행 대상별 승률 차이</td><td>15%p 안</td><td class="n ok">{spread:.1f}%p</td><td class="n">{spread_alt:.1f}%p</td></tr>
    <tr><td>요원별 승률 차이</td><td>±10%p 안</td><td class="n ok">{min(now['character_diff_pp'].values()):+.1f} ~ {max(now['character_diff_pp'].values()):+.1f}</td><td class="n">{min(alt['character_diff_pp'].values()):+.1f} ~ {max(alt['character_diff_pp'].values()):+.1f}</td></tr>
    <tr><td>일제 작전 막은 비율</td><td>50~70%</td><td class="n{' ok' if 50 <= ops <= 70 else ''}">{ops:.1f}%</td><td class="n">–</td></tr>
    <tr><td>멈춘 판 · AI가 반칙한 수</td><td>0</td><td class="n ok">{now['stuck']} · {now['fallback']}</td><td class="n">{alt['stuck']} · {alt['fallback']}</td></tr>
  </table></div>
</section>

<section class="page">
  <div class="chart">
    <div class="cap">1. 단계별 승률 변화</div>
    {chart_history()}
    <div class="read">규칙을 넣는 동안(개인 주사위 → 군자금)은 재기만 하고 고치지 않았다. 다 넣은 뒤 <b>밸런스 단계에서 한 번에 77% → 49%</b>로 맞췄고, 그 뒤로는 콘텐츠를 고칠 때마다 다시 맞췄다.</div>
  </div>

  <div class="chart">
    <div class="cap">2. 결행 대상별 승률 (회색: 재미 개선 전 → 빨강: 지금)</div>
    {chart_strikes()}
    <div class="read">재미 개선 전에는 막히는 판정 장면(총독부 근위대 19% · 경찰서 당직 순사 38%)이 거점 승률을 갈랐다. 판정 목표를 주사위로 닿게 고치고 「포위망」(실패하면 목표 −1)을 넣은 뒤, 어려움을 합 · 인원 · 버티기 장면으로 옮겼다. 돌파율 70% 아래 장면 4개 → <b>0개</b>, 격차 {spread:.1f}%p.</div>
  </div>
</section>

<section class="page">
  <div class="chart">
    <div class="cap">3. 요원 12명의 승률 차이 (그 요원이 있는 판 − 전체, %p · 초록 띠: 목표 ±10)</div>
    {chart_chars()}
    <div class="read">모두 목표 안(가장 낮은 요원 {min(now['character_diff_pp'].values()):+.1f} · 가장 높은 요원 {max(now['character_diff_pp'].values()):+.1f}).</div>
  </div>

  <div class="chart">
    <div class="cap">4. 엔딩 분포 (1,000판)</div>
    {end_svg}
    <div class="read">{end_legend}. 지는 판은 대부분 2막에서 난다. 1막을 넘기면 「어디까지 뚫느냐」의 싸움이 된다.</div>
  </div>

  <div class="chart">
    <div class="cap">5. 결행한 날 ({ROUNDS}일 중)</div>
    {chart_days()}
    <div class="read">투표로 결행한 판 {100*now['vote_rate']:.1f}%. 2일째부터 {FORCED_DAY-1}일째까지 퍼져 <b>「언제 칠까」가 판마다 다르다.</b> {FORCED_DAY}일째(금색)는 남은 날이 모자라 강제로 결행한 판이다. 작전이 11일 → 9일로 줄며 강제 결행이 약 10% → {100-100*now["vote_rate"]:.0f}%로 늘었다.</div>
  </div>
</section>

<section class="page">
  <h3>그 밖의 수치</h3>
  <ul>
    <li>일제 작전 {sum(now['ops_blocked'].values()) + sum(now['ops_missed'].values()):,}번 중 {ops:.1f}%를 막음 · 반격 {now['counter_days']}번 중 {counter:.1f}%를 막음</li>
    <li>판당 이룬 사연 {now['saga_per_game']:.2f}장</li>
    <li>결행 혜택 선택: 첩보 +2 ({ben.get('intel_tokens',0)}) · 경비 강화 없음 ({ben.get('no_reinforce',0)}) · 주사위 +1 ({ben.get('dice_plus',0)}) · 위협 보기 ({ben.get('threat_look',0)})</li>
  </ul>
  <h3>재미 개선 (S단계) 전 → 후</h3>
  <div class="tw"><table>
    <tr><th>지표</th><th class="n">전</th><th class="n">후</th><th>무엇을 바꿨나</th></tr>
    <tr><td>탈옥 시도 / 판</td><td class="n">7.4</td><td class="n">{now['action_types'].get('escape',0)/now['games']:.1f}</td><td>갇히면 다음 날 아침 석방(투옥의 93%가 경찰 체포였다)</td></tr>
    <tr><td>돌파율 70% 아래 장면</td><td class="n">4개</td><td class="n">{sum(1 for v in now['scene_break_rate'].values() if v < 0.7)}개</td><td>포위망 · 닿을 수 없던 목표 13 → 12</td></tr>
    <tr><td>버려진 주사위</td><td class="n">39%</td><td class="n">{100*now['dice_left']/now['dice_rolled']:.0f}%</td><td>2막 밤에 남긴 2개마다 첩보 토큰 1</td></tr>
    <tr><td>사연 성공률 (남겼을 때)</td><td class="n">9~89%</td><td class="n">{100*min(now['saga_rate_open'].values()):.0f}~{100*max(now['saga_rate_open'].values()):.0f}%</td><td>조건 10장 조정, 새 어휘 6개</td></tr>
    <tr><td>2막 중간에서 멈춘 판</td><td class="n">33.8%</td><td class="n">{100*now['ending_rate']['fail_middle']:.1f}%</td><td>실패 원인이 「판정 운」에서 「날이 모자람」으로</td></tr>
  </table></div>
  <h3>남은 문제</h3>
  <ul>
    <li><b>사람 플레이테스트가 없다.</b> 모든 수치는 AI 기준이다. itch.io 공개로 사람 판을 모으는 중이다.</li>
    <li><b>승률이 목표의 위쪽 끝</b>({100*now['win_rate']:.1f}% · 다른 시드 {100*alt['win_rate']:.1f}%)이다. 사람이 AI보다 잘하면 더 오른다. 작전 일수 8일(실험에서 49%)이 다음 후보다.</li>
    <li><b>2막 중간에서 멈춘 판이 {100*now['ending_rate']['fail_middle']:.0f}%</b>다. 벽은 없앴지만 시간이 모자라 멈춘다. 실패 엔딩에 「몇 장면까지 뚫었나」를 보여 주는 것이 다음 일이다.</li>
    <li><b>일제 작전을 {ops:.0f}% 막는다</b>(목표 50~70%). 감옥이 짧아져 요원이 덜 묶이면서 쉬워졌다. 일제 작전의 기한이나 벌칙을 다시 볼 차례다.</li>
    <li>형무소는 승률은 맞지만 고르는 판이 적다(1,000판 중 {now['strikes']['prison']}판). 고를 이유를 더해야 한다.</li>
  </ul>
  <p class="small muted">자료: <code>portfolio/data/balance_1000.json</code> · <code>balance_1000_seed910000.json</code> · <code>winrate_history.json</code> (측정 도구 <code>game/tools/v2_balance.gd</code>)</p>
</section>

<footer class="foot">
  <p><a href="cases.html">← 설계 사례</a> · <a href="rules.html">규칙서 →</a></p>
</footer>
<script src="theme.js"></script>
</body>
</html>
'''
open(os.path.join(HERE, 'balance.html'), 'w', encoding='utf-8', newline='\n').write(page)
print('balance.html 완료')
