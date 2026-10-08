// 밝기 바꾸기 (규칙서와 같은 저장 키)
(function () {
  var root = document.documentElement, btn = document.getElementById('themeBtn');
  try { var t = localStorage.getItem('gyeolsa-theme'); if (t) root.setAttribute('data-theme', t); } catch (e) {}
  if (!btn) return;
  btn.onclick = function () {
    var cur = root.getAttribute('data-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    var next = cur === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('gyeolsa-theme', next); } catch (e) {}
  };
})();
