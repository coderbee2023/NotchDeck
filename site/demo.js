(function () {
  var I = {
    spaces: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="8" height="7" rx="1.6"/><rect x="13" y="4" width="8" height="7" rx="1.6"/><rect x="3" y="13" width="18" height="7" rx="1.6"/></svg>',
    music: '<svg viewBox="0 0 24 24"><path d="M9 18.5a3 3 0 1 1-2-2.83V5l11-2.2v12.7a3 3 0 1 1-2-2.83V6.4L9 7.8z"/></svg>',
    gauge: '<svg viewBox="0 0 24 24"><path d="M12 4a9 9 0 0 0-7.8 13.5l1.7-1A7 7 0 1 1 18.1 16.5l1.7 1A9 9 0 0 0 12 4z"/><path d="M12 13.5 8.2 9.3 12 10.6 15.8 9.3z"/><circle cx="12" cy="13.5" r="1.6"/></svg>',
    gear: '<svg viewBox="0 0 24 24"><path d="M19.4 13a7.6 7.6 0 0 0 0-2l2-1.5-2-3.4-2.4.9a7.4 7.4 0 0 0-1.7-1L15 3.5H9l-.3 2.5a7.4 7.4 0 0 0-1.7 1l-2.4-.9-2 3.4 2 1.5a7.6 7.6 0 0 0 0 2l-2 1.5 2 3.4 2.4-.9a7.4 7.4 0 0 0 1.7 1l.3 2.5h6l.3-2.5a7.4 7.4 0 0 0 1.7-1l2.4.9 2-3.4zM12 15.2a3.2 3.2 0 1 1 0-6.4 3.2 3.2 0 0 1 0 6.4z"/></svg>',
    shuffle: '<svg viewBox="0 0 24 24"><path d="M17 4l4 3.5L17 11V8.5h-2.2c-1 0-1.6.4-2.3 1.3L11.3 12l1.2 2.2c.7.9 1.3 1.3 2.3 1.3H17V13l4 3.5L17 20v-2.5h-2.2c-1.8 0-3-.8-4-2.4l-.9-1.5-.9 1.5c-1 1.6-2.2 2.4-4 2.4H3v-2h2c1 0 1.6-.4 2.3-1.3L8.6 12 7.3 9.8C6.6 8.9 6 8.5 5 8.5H3v-2h2c1.8 0 3 .8 4 2.4l.9 1.5.9-1.5c1-1.6 2.2-2.4 4-2.4H17z"/></svg>',
    prev: '<svg viewBox="0 0 24 24"><path d="M12 12 21 5.5v13zM3 12l9-6.5v13z"/></svg>',
    next: '<svg viewBox="0 0 24 24"><path d="M12 12 3 5.5v13zM21 12l-9-6.5v13z"/></svg>',
    play: '<svg viewBox="0 0 24 24"><path d="M7 4.5v15L20 12z"/></svg>',
    pause: '<svg viewBox="0 0 24 24"><rect x="5.5" y="4" width="4.5" height="16" rx="1"/><rect x="14" y="4" width="4.5" height="16" rx="1"/></svg>',
    repeat: '<svg viewBox="0 0 24 24"><path d="M17 3l4 3.5L17 10V7.5H7A2.5 2.5 0 0 0 4.5 10v2h-2v-2A4.5 4.5 0 0 1 7 5.5h10zM7 21l-4-3.5L7 14v2.5h10a2.5 2.5 0 0 0 2.5-2.5v-2h2v2a4.5 4.5 0 0 1-4.5 4.5H7z"/></svg>',
    speaker: '<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 4V5L7 9zM15.5 8.5a4.5 4.5 0 0 1 0 7l-1.2-1.2a2.8 2.8 0 0 0 0-4.6zM17.8 5.8a8 8 0 0 1 0 12.4l-1.2-1.3a6.3 6.3 0 0 0 0-9.8z"/></svg>',
    speaker2: '<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 4V5L7 9zM15.5 8.5a4.5 4.5 0 0 1 0 7l-1.2-1.2a2.8 2.8 0 0 0 0-4.6z"/></svg>',
    sun: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1 7 17M17 7l2.1-2.1" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/></svg>',
    drop: '<svg viewBox="0 0 24 24"><path d="M12 2.5S5 10 5 14.5a7 7 0 0 0 14 0C19 10 12 2.5 12 2.5z"/></svg>',
    timer: '<svg viewBox="0 0 24 24"><path d="M12 5a8 8 0 1 0 8 8 8 8 0 0 0-8-8zm0 14a6 6 0 1 1 6-6 6 6 0 0 1-6 6zm.8-10h-1.6v5l3.8 2.3.8-1.3-3-1.8zM9 2h6v2H9z"/></svg>',
    power: '<svg viewBox="0 0 24 24"><path d="M11 3h2v9h-2zM7.4 6.2l1.4 1.4A6 6 0 1 0 15.2 7.6l1.4-1.4a8 8 0 1 1-9.2 0z"/></svg>',
    cursor: '<svg viewBox="0 0 24 24"><path d="M6 3l13 8.5-6 1.4L9.8 19z"/><path d="M15 3.5h6M16 6.5h5M17 9.5h4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>',
    wave: '<svg viewBox="0 0 24 24"><path d="M3 10v4M6.5 7v10M10 4v16M13.5 8v8M17 5.5v13M20.5 9.5v5" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/></svg>',
    sparkles: '<svg viewBox="0 0 24 24"><path d="M10 3l1.6 4.4L16 9l-4.4 1.6L10 15l-1.6-4.4L4 9l4.4-1.6zM18 13l.9 2.4 2.4.9-2.4.9L18 19.6l-.9-2.4-2.4-.9 2.4-.9z"/></svg>',
    notch: '<svg viewBox="0 0 24 24"><path d="M3 4h18a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zm1 2v12h16V6h-3.5v1.5a1.5 1.5 0 0 1-1.5 1.5H9A1.5 1.5 0 0 1 7.5 7.5V6z"/></svg>',
    clock: '<svg viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 10 10A10 10 0 0 0 12 2zm.9 10.5V6h-1.8v7.2l4.6 2.7.9-1.5z"/></svg>',
    battery: '<svg viewBox="0 0 24 24"><rect x="2" y="7" width="17" height="10" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/><rect x="4.2" y="9.2" width="10" height="5.6" rx="1.2"/><path d="M20.5 10v4a2 2 0 0 0 1.5-2 2 2 0 0 0-1.5-2z"/></svg>',
    cpu: '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v3M12 2v3M15 2v3M9 19v3M12 19v3M15 19v3M2 9h3M2 12h3M2 15h3M19 9h3M19 12h3M19 15h3" stroke="currentColor" stroke-width="1.6" fill="none"/></svg>',
    memory: '<svg viewBox="0 0 24 24"><rect x="2.5" y="6" width="19" height="10" rx="2"/><path d="M6 17v3M10 17v3M14 17v3M18 17v3" stroke="currentColor" stroke-width="1.8" fill="none"/></svg>',
    disk: '<svg viewBox="0 0 24 24"><rect x="2.5" y="8" width="19" height="9" rx="2.5"/><circle cx="17" cy="12.5" r="1.4" fill="#0f0f12"/></svg>',
    network: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
    thermo: '<svg viewBox="0 0 24 24"><path d="M10 4a2 2 0 0 1 4 0v9.3a4 4 0 1 1-4 0zm2 8.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z"/></svg>',
    flame: '<svg viewBox="0 0 24 24"><path d="M12 2s6 5.5 6 11a6 6 0 0 1-12 0c0-2.2 1-4 2-5.3 0 2 1 3.3 2.3 3.3C11.8 9.5 9.5 6 12 2z"/></svg>',
    hourglass: '<svg viewBox="0 0 24 24"><path d="M6 2h12v2l-5 8 5 8v2H6v-2l5-8-5-8zm2.6 2 4 6.4h-1.2L8.6 4z"/></svg>',
    bolt: '<svg viewBox="0 0 24 24"><path d="M13 2 4 14h6l-1 8 9-12h-6z"/></svg>',
    lock: '<svg viewBox="0 0 24 24"><path d="M7 10V7a5 5 0 0 1 10 0v3h1a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2zm2 0h6V7a3 3 0 0 0-6 0z"/></svg>',
    moon: '<svg viewBox="0 0 24 24"><path d="M14 2.5a9.5 9.5 0 1 0 7.5 15.2A8 8 0 0 1 14 2.5z"/></svg>',
    mission: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="8" height="6" rx="1.4"/><rect x="13" y="4" width="8" height="6" rx="1.4"/><rect x="3" y="12" width="8" height="8" rx="1.4"/><rect x="13" y="12" width="8" height="8" rx="1.4"/></svg>',
    contrast: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 3a9 9 0 0 1 0 18z"/></svg>',
    camera: '<svg viewBox="0 0 24 24"><path d="M3 8V4h4v1.8H4.8V8zm14-4h4v4h-1.8V5.8H17zM3 16h1.8v2.2H7V20H3zm16.2 0H21v4h-4v-1.8h2.2z"/><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>',
    cup: '<svg viewBox="0 0 24 24"><path d="M4 7h13v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zm14 1h1.5a2.5 2.5 0 0 1 0 5H18zM3 19h16v1.6H3z"/></svg>',
    paint: '<svg viewBox="0 0 24 24"><path d="M12 3a9 9 0 0 0 0 18c1.3 0 2-.8 2-1.7 0-.6-.3-1-.5-1.4-.3-.5-.5-.8-.5-1.3 0-.9.8-1.6 1.7-1.6H16a5 5 0 0 0 5-5c0-3.9-4-7-9-7zm-4.5 9a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm3-4a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm4.5 0a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm3 4a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z"/></svg>',
    sliders: '<svg viewBox="0 0 24 24"><path d="M3 6h18M3 12h18M3 18h18" stroke="currentColor" stroke-width="2" fill="none"/><circle cx="8" cy="6" r="2.4"/><circle cx="15" cy="12" r="2.4"/><circle cx="10" cy="18" r="2.4"/></svg>',
    grid: '<svg viewBox="0 0 24 24"><rect x="3" y="3" width="8" height="8" rx="1.8"/><rect x="13" y="3" width="8" height="8" rx="1.8"/><rect x="3" y="13" width="8" height="8" rx="1.8"/><rect x="13" y="13" width="8" height="8" rx="1.8"/></svg>',
    fullscreen: '<svg viewBox="0 0 24 24"><path d="M3 3h7v2H6.4l4.3 4.3-1.4 1.4L5 6.4V10H3zm11 0h7v7h-2V6.4l-4.3 4.3-1.4-1.4L17.6 5H14zM3 14h2v3.6l4.3-4.3 1.4 1.4L6.4 19H10v2H3zm18 0v7h-7v-2h3.6l-4.3-4.3 1.4-1.4 4.3 4.3V14z"/></svg>'
  };

  var SPACES = [
    { title: 'Desktop 1', hue: 205, app: 'code', apps: ['#3b82f6', '#f97316', '#ef4444'] },
    { title: 'Full Screen', hue: 150, app: 'music', apps: ['#1db954'], fs: true },
    { title: 'Desktop 2', hue: 225, app: 'browser', apps: ['#f97316'] },
    { title: 'Desktop 3', hue: 215, app: null, apps: [] },
    { title: 'Desktop 4', hue: 200, app: 'terminal', apps: ['#9ca3af'] },
    { title: 'Desktop 5', hue: 235, app: 'calendar', apps: ['#ef4444'] }
  ];
  var PRESETS = ['#FFFFFF', '#4DA3FF', '#3DDC84', '#FF8A3D', '#9B6CFF', '#FF5C8A'];
  var WIDGETS = [
    ['clock', 'Clock', 'clock'], ['battery', 'Battery', 'battery'], ['cpu', 'CPU', 'cpu'], ['memory', 'Memory', 'memory'],
    ['disk', 'Disk', 'disk'], ['network', 'Network', 'network'], ['thermal', 'Thermals', 'thermo'], ['top', 'Top App', 'flame'], ['uptime', 'Uptime', 'hourglass']
  ];

  var S = {
    open: false, pinned: false, page: 0, active: 3, playing: true, pos: 92, dur: 206, vol: 82, shuffle: false, repeat: 0,
    accent: '#3DDC84', glass: 0.11, tint: 0, vis: true, volbar: true, glow: true, pill: true, login: false, hover: true, delay: 0,
    widgets: ['clock', 'battery', 'cpu', 'memory', 'disk', 'network', 'thermal', 'top'], actions: true, sysvol: true, sysVolume: 0.5, muted: false, awake: false,
    cpu: 0.13, mem: 0.69, disk: 0.66, batt: 1.0, down: 0, up: 0
  };

  var root = document.getElementById('nd-demo');
  if (!root) return;
  var screenEl = root.querySelector('.nd-screen');
  var deck = root.querySelector('.nd-deck');
  var body = root.querySelector('.nd-body');
  var pillEl = root.querySelector('.nd-pill');

  function hex2rgb(h) { var v = parseInt(h.slice(1), 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
  function lum(h) { var c = hex2rgb(h); return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255; }
  function hsl2hex(h, s, l) {
    var a = s * Math.min(l, 1 - l);
    var f = function (n) { var k = (n + h * 12) % 12; var c = l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)); return Math.round(c * 255).toString(16).padStart(2, '0'); };
    return '#' + f(0) + f(8) + f(4);
  }
  function hueOf(h) { var c = hex2rgb(h).map(function (x) { return x / 255; }); var mx = Math.max.apply(null, c), mn = Math.min.apply(null, c); if (mx - mn < 0.1) return null; var d = mx - mn, hh; if (mx === c[0]) hh = ((c[1] - c[2]) / d) % 6; else if (mx === c[1]) hh = (c[2] - c[0]) / d + 2; else hh = (c[0] - c[1]) / d + 4; hh /= 6; if (hh < 0) hh += 1; return hh; }
  function accentRGBA(a) { var c = hex2rgb(S.accent); return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  function fmt(s) { s = Math.round(s); return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
  function esc(s) { return s.replace(/</g, '&lt;'); }

  function applyTheme() {
    root.style.setProperty('--nd-accent', S.accent);
    root.style.setProperty('--nd-on-accent', lum(S.accent) > 0.6 ? '#000' : '#fff');
    root.style.setProperty('--nd-glass', 'rgb(' + Math.round(S.glass * 255) + ',' + Math.round(S.glass * 255) + ',' + Math.round(S.glass * 255) + ')');
    root.style.setProperty('--nd-tint', accentRGBA(S.tint * 0.35));
    root.style.setProperty('--nd-accent-22', accentRGBA(0.22));
    root.style.setProperty('--nd-accent-80', accentRGBA(0.8));
  }

  /* ---------- header ---------- */
  function renderHeader() {
    var d = new Date();
    var t = ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
    var tabs = [['Spaces', 'spaces'], ['Music', 'music'], ['System', 'gauge'], [null, 'gear']];
    return '<div class="nd-hdr"><span class="nd-clock">' + t + '</span><span class="nd-dot">·</span><span class="nd-space">' + SPACES[S.active].title + '</span><span class="nd-flex"></span>' +
      '<div class="nd-tabs">' + tabs.map(function (tb, i) {
        return '<button class="nd-tab' + (S.page === i ? ' on' : '') + (tb[0] ? '' : ' icon') + '" data-page="' + i + '">' + I[tb[1]] + (tb[0] ? '<span>' + tb[0] + '</span>' : '') + '</button>';
      }).join('') + '</div></div>';
  }

  /* ---------- spaces ---------- */
  function thumb(sp) {
    var win = '';
    if (sp.app === 'code') win = '<div class="nd-fw" style="left:6%;top:12%;width:88%;height:78%;background:#1c1f26"><i style="width:22%;background:#151820"></i><b style="left:26%;top:14%;width:60%;background:linear-gradient(90deg,#9b6cff 0 30%,transparent 30% 34%,#4da3ff 34% 55%,transparent 55% 58%,#ff8a3d 58% 70%,transparent 70%)"></b><b style="left:26%;top:26%;width:45%;background:linear-gradient(90deg,#4da3ff 0 40%,transparent 40% 44%,#e5e7eb 44% 80%,transparent 80%)"></b><b style="left:26%;top:38%;width:55%;background:linear-gradient(90deg,#ff5c8a 0 20%,transparent 20% 24%,#9ca3af 24% 70%,transparent 70%)"></b><b style="left:26%;top:50%;width:35%;background:#9ca3af"></b></div>';
    if (sp.app === 'music') win = '<div class="nd-fw" style="left:0;top:0;width:100%;height:100%;background:#121212;border-radius:0"><i style="width:26%;background:#000"></i><div style="position:absolute;left:34%;top:18%;width:22%;height:40%;border-radius:6%;background:linear-gradient(135deg,#f0d9b5,#7a4b2a)"></div><b style="left:60%;top:22%;width:28%;background:#fff"></b><b style="left:60%;top:34%;width:20%;background:#8a8a8a"></b><b style="left:60%;top:46%;width:24%;background:#1db954"></b></div>';
    if (sp.app === 'browser') win = '<div class="nd-fw" style="left:5%;top:10%;width:90%;height:82%;background:#1a1b20"><b style="left:4%;top:5%;width:92%;background:#2a2c33;height:8%"></b><b style="left:8%;top:24%;width:50%;background:#e5e7eb"></b><b style="left:8%;top:36%;width:70%;background:#6b7280"></b><b style="left:8%;top:46%;width:64%;background:#6b7280"></b><div style="position:absolute;left:8%;top:58%;width:84%;height:26%;border-radius:4%;background:linear-gradient(135deg,#1f3a5f,#2b6cb0)"></div></div>';
    if (sp.app === 'terminal') win = '<div class="nd-fw" style="left:18%;top:20%;width:64%;height:56%;background:#101214"><b style="left:6%;top:16%;width:40%;background:#3ddc84"></b><b style="left:6%;top:32%;width:60%;background:#9ca3af"></b><b style="left:6%;top:48%;width:30%;background:#9ca3af"></b><b style="left:6%;top:64%;width:10%;background:#e5e7eb"></b></div>';
    if (sp.app === 'calendar') win = '<div class="nd-fw" style="left:8%;top:10%;width:84%;height:80%;background:#1c1c1e"><i style="width:24%;background:#161618"></i><div style="position:absolute;left:28%;top:14%;width:66%;height:74%;background:repeating-linear-gradient(90deg,#26262a 0 13%,#1c1c1e 13% 14.3%),repeating-linear-gradient(0deg,#26262a 0 18%,transparent 18% 20%)"></div><b style="left:44%;top:30%;width:12%;background:#ef4444;height:10%"></b><b style="left:62%;top:52%;width:12%;background:#4da3ff;height:10%"></b></div>';
    return '<div class="nd-wall" style="--h:' + sp.hue + '"><span class="nd-moon"></span>' + win + '</div>';
  }
  function renderSpaces() {
    var rows = [SPACES.slice(0, 4), SPACES.slice(4)];
    return '<div class="nd-page nd-spaces">' + rows.map(function (row) {
      return '<div class="nd-row">' + row.map(function (sp) {
        var i = SPACES.indexOf(sp), on = i === S.active;
        return '<div class="nd-card' + (on ? ' on' : '') + '" data-space="' + i + '">' + thumb(sp) + '<div class="nd-cardlbl">' + (on ? '<i class="nd-adot"></i>' : '') + '<span>' + sp.title + '</span><em>' + sp.apps.map(function (c) { return '<u style="background:' + c + '"></u>'; }).join('') + '</em></div></div>';
      }).join('') + (row.length < 4 ? '<div class="nd-card nd-ghost"></div>'.repeat(4 - row.length) : '') + '</div>';
    }).join('') + '</div>';
  }

  /* ---------- music ---------- */
  function activeColor() { return hueOf(S.accent) === null ? '#1DB954' : S.accent; }
  function renderMusic() {
    var frac = S.pos / S.dur;
    var vi = S.vol === 0 ? 'speaker' : 'speaker';
    return '<div class="nd-page nd-music' + (S.playing ? ' playing' : '') + '">' +
      '<div class="nd-artwrap">' + (S.glow ? '<div class="nd-glow"></div>' : '') + '<div class="nd-art"><div class="nd-artimg"><span class="nd-artname">NEON<br>COAST</span></div><div class="nd-badge">' + I.wave + '</div></div></div>' +
      '<div class="nd-mcol">' +
      '<div class="nd-mtitle"><span>Night Drive</span>' + (S.vis ? '<div class="nd-vis" data-bars="6"></div>' : '') + '</div>' +
      '<div class="nd-martist">Nova Kade</div><div class="nd-malbum">Neon Coast</div><div class="nd-flex"></div>' +
      '<div class="nd-scrub" id="nd-scrub"><div class="nd-track"><div class="nd-fill" style="width:' + (frac * 100) + '%"></div></div><div class="nd-times"><span>' + fmt(S.pos) + '</span><span>-' + fmt(S.dur - S.pos) + '</span></div></div>' +
      '<div class="nd-ctrls"><button class="nd-cb sm' + (S.shuffle ? ' act' : '') + '" data-act="shuffle" style="' + (S.shuffle ? 'color:' + activeColor() : '') + '">' + I.shuffle + '</button><span class="nd-flex"></span>' +
      '<button class="nd-cb" data-act="prev">' + I.prev + '</button><button class="nd-cb prom" data-act="play">' + (S.playing ? I.pause : I.play) + '</button><button class="nd-cb" data-act="next">' + I.next + '</button>' +
      '<span class="nd-flex"></span><button class="nd-cb sm' + (S.repeat ? ' act' : '') + '" data-act="repeat" style="' + (S.repeat ? 'color:' + activeColor() : '') + '">' + I.repeat + (S.repeat === 2 ? '<b class="nd-r1">1</b>' : '') + '</button></div>' +
      (S.volbar ? '<div class="nd-slider nd-vol" data-slider="vol"><span class="nd-sicon">' + I[vi] + '</span><div class="nd-track"><div class="nd-fill" style="width:' + S.vol + '%"></div><div class="nd-knob" style="left:' + S.vol + '%"></div></div></div>' : '') +
      '</div></div>';
  }

  /* ---------- system ---------- */
  function ring(v, big, cls) { var r = 20.5, c = 2 * Math.PI * r; return '<div class="nd-ring ' + (cls || '') + '"><svg viewBox="0 0 46 46"><circle cx="23" cy="23" r="' + r + '" class="bg"/><circle cx="23" cy="23" r="' + r + '" class="fg" style="stroke-dasharray:' + c + ';stroke-dashoffset:' + (c * (1 - v)) + '"/></svg><span>' + big + '</span></div>'; }
  function tile(inner) { return '<div class="nd-tile">' + inner + '</div>'; }
  function widget(w) {
    var d = new Date();
    if (w === 'clock') return tile('<div class="nd-wclock"><b>' + ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2) + '</b><i>' + d.toLocaleDateString('en-US', { weekday: 'long' }) + '</i><span>' + d.getDate() + ' ' + d.toLocaleDateString('en-US', { month: 'long' }) + '</span></div>');
    if (w === 'battery') return tile('<div class="nd-gauge">' + ring(S.batt, Math.round(S.batt * 100)) + '<div><b>Battery</b><span>13h 51m left</span></div></div>');
    if (w === 'cpu') return tile('<div class="nd-gauge">' + ring(S.cpu, Math.round(S.cpu * 100) + '%') + '<div><b>CPU</b><span>12 cores</span></div></div>');
    if (w === 'memory') return tile('<div class="nd-gauge">' + ring(S.mem, Math.round(S.mem * 100) + '%') + '<div><b>Memory</b><span>18 GB of<br>26 GB</span></div></div>');
    if (w === 'disk') return tile('<div class="nd-gauge">' + ring(S.disk, Math.round(S.disk * 100) + '%') + '<div><b>Disk</b><span>165 GB free</span></div></div>');
    if (w === 'network') return tile('<div class="nd-info"><div class="nd-ih"><i class="ac">' + I.network + '</i><b>Network</b></div><div class="nd-flex"></div><div class="nd-rate"><i class="ac">↓</i><b>' + S.down + ' KB/s</b></div><div class="nd-rate dim"><i>↑</i><b>' + S.up + ' KB/s</b></div></div>');
    if (w === 'thermal') return tile('<div class="nd-info"><div class="nd-ih"><i style="color:#34c759">' + I.thermo + '</i><b>Thermals</b></div><div class="nd-flex"></div><div class="nd-big">Cool</div><div class="nd-sub">Thermal pressure</div></div>');
    if (w === 'top') return tile('<div class="nd-gauge"><div class="nd-appic">' + I.flame + '</div><div><b>Top App</b><strong>WindowServer</strong><span>' + Math.round(S.cpu * 400) + '% CPU</span></div></div>');
    if (w === 'uptime') return tile('<div class="nd-info"><div class="nd-ih"><i class="ac">' + I.hourglass + '</i><b>Uptime</b></div><div class="nd-flex"></div><div class="nd-big">3d 4h</div><div class="nd-sub">since Tue 09:12</div></div>');
    return '';
  }
  function renderSystem() {
    var ws = S.widgets, rows = [];
    for (var i = 0; i < ws.length; i += 4) rows.push(ws.slice(i, i + 4));
    var dock = S.actions || S.sysvol;
    var html = '<div class="nd-page nd-system' + (dock ? ' hasdock' : '') + '" style="--rows:' + Math.max(rows.length, 1) + '">' +
      rows.map(function (r) { return '<div class="nd-srow">' + r.map(widget).join('') + (rows.length > 1 && r.length < 4 ? '<div class="nd-tile nd-ghost"></div>'.repeat(4 - r.length) : '') + '</div>'; }).join('');
    if (!ws.length) html += '<div class="nd-empty">No widgets enabled — turn some on in Settings</div>';
    if (dock) {
      html += '<div class="nd-dock">' + (S.actions ? ['lock', 'moon', 'mission', 'contrast', 'camera', 'cup'].map(function (k) { return '<button class="nd-qb' + (k === 'cup' && S.awake ? ' on' : '') + '" data-q="' + k + '" title="' + { lock: 'Lock screen', moon: 'Sleep display', mission: 'Mission Control', contrast: 'Toggle dark mode', camera: 'Screenshot', cup: 'Keep awake' }[k] + '">' + I[k] + '</button>'; }).join('') : '') +
        '<span class="nd-flex"></span>' + (S.sysvol ? '<div class="nd-slider nd-sysvol" data-slider="sys"><span class="nd-sicon" data-mute>' + I[S.muted ? 'speaker2' : 'speaker'] + '</span><div class="nd-track"><div class="nd-fill" style="width:' + (S.muted ? 0 : S.sysVolume * 100) + '%"></div><div class="nd-knob" style="left:' + (S.muted ? 0 : S.sysVolume * 100) + '%"></div></div></div>' : '') + '</div>';
    }
    return html + '</div>';
  }

  /* ---------- settings ---------- */
  function chip(label, icon, on, key) { return '<button class="nd-chip' + (on ? ' on' : '') + '" data-chip="' + key + '">' + I[icon] + '<span>' + label + '</span></button>'; }
  function lslider(title, icon, v, key) { return '<div class="nd-lslider"><label>' + title + '</label><div class="nd-slider" data-slider="' + key + '"><span class="nd-sicon">' + I[icon] + '</span><div class="nd-track"><div class="nd-fill" style="width:' + (v * 100) + '%"></div><div class="nd-knob" style="left:' + (v * 100) + '%"></div></div></div></div>'; }
  function renderSettings() {
    var hue = hueOf(S.accent);
    return '<div class="nd-page nd-settings">' +
      '<div class="nd-tile nd-st"><div class="nd-sh"><i>' + I.paint + '</i><b>Appearance</b></div><div class="nd-lbl">Accent</div>' +
      '<div class="nd-swatches">' + PRESETS.map(function (p) { return '<button class="nd-sw' + (S.accent === p ? ' on' : '') + '" data-sw="' + p + '" style="background:' + p + '"></button>'; }).join('') + '</div>' +
      '<div class="nd-hue" data-slider="hue">' + (hue !== null ? '<i style="left:' + (hue * 100) + '%"></i>' : '') + '</div>' +
      lslider('Glass', 'sun', (S.glass - 0.04) / 0.26, 'glass') + lslider('Tint', 'drop', S.tint, 'tint') +
      '<div class="nd-flex"></div><button class="nd-reset" data-act="reset">Reset to defaults</button></div>' +
      '<div class="nd-tile nd-st"><div class="nd-sh"><i>' + I.sliders + '</i><b>General</b></div>' +
      chip('Launch at login', 'power', S.login, 'login') + chip('Open on hover', 'cursor', S.hover, 'hover') + lslider('Delay', 'timer', S.delay, 'delay') +
      '<div class="nd-sh" style="margin-top:2px"><i>' + I.music + '</i><b>Music</b></div>' +
      '<div class="nd-chips2">' + chip('Visualizer', 'wave', S.vis, 'vis') + chip('Volume', 'speaker', S.volbar, 'volbar') + '</div>' +
      '<div class="nd-chips2">' + chip('Glow', 'sparkles', S.glow, 'glow') + chip('In notch', 'notch', S.pill, 'pill') + '</div>' +
      '<div class="nd-flex"></div><div class="nd-foot">⌃⌥Space toggles the deck · Esc closes it</div></div>' +
      '<div class="nd-tile nd-st"><div class="nd-sh"><i>' + I.grid + '</i><b>System widgets</b></div><div class="nd-wgrid">' +
      WIDGETS.map(function (w) { return chip(w[1], w[2], S.widgets.indexOf(w[0]) >= 0, 'w:' + w[0]); }).join('') +
      chip('Actions', 'bolt', S.actions, 'actions') + chip('Volume', 'speaker', S.sysvol, 'sysvol') + '</div></div></div>';
  }

  function renderBody() {
    var pages = [renderSpaces(), renderMusic(), renderSystem(), renderSettings()];
    body.innerHTML = renderHeader() + '<div class="nd-pages"><div class="nd-strip" style="transform:translateX(' + (-S.page * 25) + '%)">' + pages.join('') + '</div></div>';
    startVis();
  }
  function renderPill() {
    var show = !S.open && S.pill && S.playing;
    deck.classList.toggle('pill', show);
    pillEl.innerHTML = show ? '<div class="nd-pillart"><span>NC</span></div><span class="nd-flex"></span><div class="nd-vis small" data-bars="5"></div>' : '';
    startVis();
  }
  function renderScreen() {
    var sp = SPACES[S.active];
    screenEl.style.setProperty('--h', sp.hue);
    screenEl.querySelector('.nd-desktop').innerHTML = thumb(sp);
    var mb = screenEl.querySelector('.nd-mbapp');
    if (mb) mb.textContent = { code: 'Code', music: 'Spotify', browser: 'Safari', terminal: 'Terminal', calendar: 'Calendar' }[sp.app] || 'Finder';
  }
  function renderAll() { applyTheme(); renderBody(); renderPill(); renderScreen(); }

  /* ---------- visualizer ---------- */
  var visT0 = performance.now();
  function startVis() {
    root.querySelectorAll('.nd-vis').forEach(function (el) {
      if (el.children.length) return;
      var n = +el.dataset.bars || 6;
      for (var i = 0; i < n; i++) el.appendChild(document.createElement('i'));
    });
  }
  function tickVis(now) {
    var ph = ((now - visT0) / 900) * Math.PI * 2;
    root.querySelectorAll('.nd-vis').forEach(function (el) {
      var mx = el.classList.contains('small') ? 16 : 16;
      Array.prototype.forEach.call(el.children, function (b, i) {
        var v = S.playing ? (Math.sin(ph + i * 1.3) * 0.5 + 0.5) : 0;
        b.style.height = (S.playing ? 3 + v * (mx - 3) : 3) + 'px';
        b.style.opacity = S.playing ? 0.9 : 0.3;
      });
    });
    requestAnimationFrame(tickVis);
  }
  requestAnimationFrame(tickVis);

  /* ---------- timers ---------- */
  setInterval(function () {
    if (S.playing) { S.pos += 1; if (S.pos >= S.dur) S.pos = 0; }
    if (S.page === 1 && S.open) {
      var sc = body.querySelector('#nd-scrub'); if (sc) { sc.querySelector('.nd-fill').style.width = (S.pos / S.dur * 100) + '%'; var t = sc.querySelectorAll('.nd-times span'); t[0].textContent = fmt(S.pos); t[1].textContent = '-' + fmt(S.dur - S.pos); }
    }
  }, 1000);
  setInterval(function () {
    S.cpu = Math.max(0.05, Math.min(0.4, S.cpu + (Math.random() - 0.5) * 0.06));
    S.mem = Math.max(0.6, Math.min(0.75, S.mem + (Math.random() - 0.5) * 0.01));
    S.down = Math.round(Math.random() * 40); S.up = Math.round(Math.random() * 6);
    if (S.open && S.page === 2) renderBody();
  }, 2000);

  /* ---------- open / close ---------- */
  var closeT;
  function setOpen(v) {
    if (S.open === v) return;
    S.open = v; deck.classList.toggle('open', v); root.parentElement.classList.toggle('open', v);
    if (v) { renderBody(); body.hidden = false; } else { S.pinned = false; }
    renderPill();
    if (!v) setTimeout(function () { if (!S.open) body.hidden = true; }, 350);
  }
  root.querySelector('.nd-hot').addEventListener('mouseenter', function () { if (S.hover) { clearTimeout(closeT); setTimeout(function () { setOpen(true); }, S.delay * 800); } });
  deck.addEventListener('mouseenter', function () { clearTimeout(closeT); if (!S.open && S.hover) setTimeout(function () { if (deck.matches(':hover')) setOpen(true); }, S.delay * 800); });
  deck.addEventListener('click', function () { if (!S.open) { S.pinned = true; setOpen(true); } });
  deck.addEventListener('mouseleave', function () { if (S.open && !S.pinned) closeT = setTimeout(function () { setOpen(false); }, 350); });
  root.querySelector('.nd-hot').addEventListener('click', function () { S.pinned = true; setOpen(true); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && S.open) setOpen(false);
    if (e.code === 'Space' && e.ctrlKey && e.altKey) { e.preventDefault(); if (S.open) setOpen(false); else { S.pinned = true; setOpen(true); } }
  });

  /* ---------- gestures: two-finger horizontal scroll pages ---------- */
  var acc = 0, fired = false, accT;
  deck.addEventListener('wheel', function (e) {
    if (!S.open || Math.abs(e.deltaX) < Math.abs(e.deltaY)) return;
    e.preventDefault(); acc += e.deltaX; clearTimeout(accT); accT = setTimeout(function () { acc = 0; fired = false; }, 350);
    if (!fired && Math.abs(acc) > 40) { fired = true; S.page = Math.max(0, Math.min(3, S.page + (acc > 0 ? 1 : -1))); renderBody(); }
  }, { passive: false });

  /* ---------- clicks ---------- */
  body.addEventListener('click', function (e) {
    var t = e.target.closest('[data-page],[data-space],[data-act],[data-chip],[data-sw],[data-q],[data-mute]');
    if (!t) return;
    if (t.dataset.page !== undefined) { S.page = +t.dataset.page; renderBody(); return; }
    if (t.dataset.space !== undefined) { S.active = +t.dataset.space; renderAll(); return; }
    if (t.dataset.sw) { S.accent = t.dataset.sw; renderAll(); return; }
    if (t.dataset.q) { if (t.dataset.q === 'cup') { S.awake = !S.awake; renderBody(); } else { t.classList.add('flash'); setTimeout(function () { t.classList.remove('flash'); }, 300); } return; }
    if (t.hasAttribute('data-mute')) { S.muted = !S.muted; renderBody(); return; }
    if (t.dataset.chip) {
      var k = t.dataset.chip;
      if (k.indexOf('w:') === 0) { var w = k.slice(2), i = S.widgets.indexOf(w); if (i >= 0) S.widgets.splice(i, 1); else { S.widgets.push(w); S.widgets.sort(function (a, b) { return WIDGETS.findIndex(function (x) { return x[0] === a; }) - WIDGETS.findIndex(function (x) { return x[0] === b; }); }); } }
      else S[k] = !S[k];
      renderAll(); return;
    }
    var a = t.dataset.act;
    if (a === 'play') { S.playing = !S.playing; renderBody(); renderPill(); }
    if (a === 'next') { S.pos = 0; renderBody(); }
    if (a === 'prev') { S.pos = 0; renderBody(); }
    if (a === 'shuffle') { S.shuffle = !S.shuffle; renderBody(); }
    if (a === 'repeat') { S.repeat = (S.repeat + 1) % 3; renderBody(); }
    if (a === 'reset') { S.accent = '#FFFFFF'; S.glass = 0.11; S.tint = 0; S.vis = S.volbar = S.glow = S.pill = S.actions = S.sysvol = S.hover = true; S.delay = 0; S.widgets = ['clock', 'battery', 'cpu', 'memory', 'disk', 'network', 'thermal', 'top']; renderAll(); }
  });

  /* ---------- sliders / drag ---------- */
  function sliderFrac(el, e) { var r = (el.querySelector('.nd-track') || el).getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); }
  function applySlider(key, f) {
    if (key === 'vol') S.vol = Math.round(f * 100);
    if (key === 'sys') { S.sysVolume = f; S.muted = false; }
    if (key === 'glass') S.glass = 0.04 + f * 0.26;
    if (key === 'tint') S.tint = f;
    if (key === 'delay') S.delay = Math.round(f * 0.8 * 20) / 20 / 0.8;
    if (key === 'hue') S.accent = hsl2hex(Math.min(f, 0.999), 0.72, 0.62);
    applyTheme();
  }
  var drag = null;
  body.addEventListener('pointerdown', function (e) {
    var sc = e.target.closest('#nd-scrub'); if (sc) { S.pos = sliderFrac(sc, e) * S.dur; renderBody(); return; }
    var el = e.target.closest('[data-slider]'); if (!el) return;
    drag = { el: el, key: el.dataset.slider }; el.classList.add('live'); e.preventDefault();
    applySlider(drag.key, sliderFrac(el, e)); paintSlider(el, drag.key);
  });
  function paintSlider(el, key) {
    var v = { vol: S.vol / 100, sys: S.muted ? 0 : S.sysVolume, glass: (S.glass - 0.04) / 0.26, tint: S.tint, delay: S.delay, hue: hueOf(S.accent) || 0 }[key];
    var f = el.querySelector('.nd-fill'), k = el.querySelector('.nd-knob'), hi = el.querySelector('i');
    if (f) f.style.width = (v * 100) + '%'; if (k) k.style.left = (v * 100) + '%'; if (hi && key === 'hue') hi.style.left = (v * 100) + '%';
    if (key === 'hue') body.querySelectorAll('.nd-sw').forEach(function (s) { s.classList.toggle('on', s.dataset.sw === S.accent); });
  }
  window.addEventListener('pointermove', function (e) { if (!drag) return; applySlider(drag.key, sliderFrac(drag.el, e)); paintSlider(drag.el, drag.key); });
  window.addEventListener('pointerup', function () { if (!drag) return; drag.el.classList.remove('live'); var k = drag.key; drag = null; if (k === 'hue') renderAll(); });

  /* ---------- scale to stage ---------- */
  function fit() {
    var w = root.clientWidth; var k = w / 1040;
    root.style.setProperty('--k', k);
    root.style.height = (430 * k) + 'px';
  }
  window.addEventListener('resize', fit); fit();
  renderAll();
  body.hidden = true;
  if (!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches)) {
    setTimeout(function () { setOpen(true); setTimeout(function () { if (!S.pinned && !deck.matches(':hover')) setOpen(false); }, 3200); }, 1200);
  }
})();
