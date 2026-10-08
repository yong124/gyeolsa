# balance.html 만들기: data/*.json 수치로 SVG 그래프를 그린다.
# 실행: python portfolio/build_balance.py
import json, os, collections, html

HERE = os.path.dirname(os.path.abspath(__file__))
hist = json.load(open(os.path.join(HERE, 'data', 'winrate_history.json'), encoding='utf-8'))
now = json.load(open(os.path.join(HERE, 'data', 'balance_1000.json'), encoding='utf-8'))['결과'][0]
alt = json.load(open(os.path.join(HERE, 'data', 'balance_1000_seed910000.json'), encoding='utf-8'))['결과'][0]

E = html.escape
STRIKE = {'barracks': '일본군영 · 사령관 암살', 'gg': '조선총독부 · 점거', 'police_hq': '종로경찰서 · 폭파', 'prison': '서대문형무소 · 해방'}
BEFORE = {'barracks': 44.5, 'gg': 62.7, 'police_hq': 60.0, 'prison': 52.3}   # P6 전 (같은 시드)
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
    days = list(range(2, 11))
    mx = max(c.values())
    W, H, L, B = 900, 230, 30, 40
    bw = (W - L) / len(days)
    y = lambda v: 24 + (H - B - 24) * (1 - v / mx)
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="결행한 날 분포">']
    for i, d in enumerate(days):
        v = c.get(d, 0)
        x = L + i * bw
        s.append(f'<rect class="bar {"force" if d == 10 else "now"}" x="{x+8:.1f}" y="{y(v):.1f}" width="{bw-16:.1f}" height="{H-B-y(v):.1f}" rx="2"/>')
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
    <tr><td>승률</td><td>45~55%</td><td class="n ok">{100*now['win_rate']:.1f}%</td><td class="n">{100*alt['win_rate']:.1f}%</td></tr>
    <tr><td>결행 대상별 승률 차이</td><td>15%p 안</td><td class="n ok">{spread:.1f}%p</td><td class="n">{spread_alt:.1f}%p</td></tr>
    <tr><td>요원별 승률 차이</td><td>±10%p 안</td><td class="n ok">{min(now['character_diff_pp'].values()):+.1f} ~ {max(now['character_diff_pp'].values()):+.1f}</td><td class="n">{min(alt['character_diff_pp'].values()):+.1f} ~ {max(alt['character_diff_pp'].values()):+.1f}</td></tr>
    <tr><td>일제 작전 막은 비율</td><td>50~70%</td><td class="n ok">{ops:.1f}%</td><td class="n">–</td></tr>
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
    <div class="cap">2. 결행 대상별 승률 (회색: 출시 뒤 조정 전 → 빨강: 지금)</div>
    {chart_strikes()}
    <div class="read">출시 뒤 미션을 손본 뒤 격차가 18.2%p로 벌어졌다. 마지막 장면은 눈금 1에 20%p 넘게 흔들려서, 군영 마지막 장면만 한 칸 낮추고 같은 거점의 다른 장면으로 되돌렸다(9가지 조합 비교). 격차 {spread:.1f}%p.</div>
  </div>
</section>

<section class="page">
  <div class="chart">
    <div class="cap">3. 요원 12명의 승률 차이 (그 요원이 있는 판 − 전체, %p · 초록 띠: 목표 ±10)</div>
    {chart_chars()}
    <div class="read">모두 목표 안. 가장 약한 정 인쇄공(−6.0)은 능력이 「주사위 건네기」라, AI가 협력을 덜 하는 만큼 낮게 나올 수 있다.</div>
  </div>

  <div class="chart">
    <div class="cap">4. 엔딩 분포 (1,000판)</div>
    {end_svg}
    <div class="read">{end_legend}. 지는 판은 대부분 2막에서 난다. 1막을 넘기면 「어디까지 뚫느냐」의 싸움이 된다.</div>
  </div>

  <div class="chart">
    <div class="cap">5. 결행한 날 (11일 중)</div>
    {chart_days()}
    <div class="read">투표로 결행한 판 {100*now['vote_rate']:.1f}%. 2일째부터 9일째까지 고르게 퍼져 <b>「언제 칠까」가 판마다 다르다.</b> 10일째(금색)는 남은 날이 모자라 강제로 결행한 판이다.</div>
  </div>
</section>

<section class="page">
  <h3>그 밖의 수치</h3>
  <ul>
    <li>일제 작전 {sum(now['ops_blocked'].values()) + sum(now['ops_missed'].values()):,}번 중 {ops:.1f}%를 막음 · 반격 {now['counter_days']}번 중 {counter:.1f}%를 막음</li>
    <li>판당 이룬 사연 {now['saga_per_game']:.2f}장</li>
    <li>결행 혜택 선택: 첩보 +2 ({ben.get('intel_tokens',0)}) · 경비 강화 없음 ({ben.get('no_reinforce',0)}) · 주사위 +1 ({ben.get('dice_plus',0)}) · 위협 보기 ({ben.get('threat_look',0)}) · 군자금 ({ben.get('funds',0)})</li>
  </ul>
  <h3>남은 문제</h3>
  <ul>
    <li><b>사람 플레이테스트가 없다.</b> 모든 수치는 AI 기준이다. itch.io 공개로 사람 판을 모으는 중이다.</li>
    <li><b>결행 혜택 「군자금」은 거의 고르지 않는다</b>({ben.get('funds',0)}번). 다른 혜택보다 약하거나, AI가 돈의 값을 낮게 본다. 사람 판을 보고 고친다.</li>
    <li><b>다른 시드에서는 격차가 {spread_alt:.1f}%p</b>로 목표 경계선이다. 형무소는 고르는 판이 적어(1,000판 중 {now['strikes']['prison']}판) 흔들림이 크다.</li>
    <li>장교 숙소(판정 12)처럼 다른 길이 없는 높은 판정은 첩보 토큰이 있어야 닿는다. 사람에게 막막하게 느껴지는지 봐야 한다.</li>
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
