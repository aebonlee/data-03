/* =====================================================================
 * app.js — 모든 페이지가 함께 쓰는 공통 스크립트
 *  · 헤더 / 푸터 렌더링
 *  · 로그인 상태 관리
 *  · 날짜 포맷, HTML 이스케이프 등 유틸
 *  · 토스트 알림 / 비밀번호 입력 모달
 * ===================================================================== */

const App = (() => {

  /* ------------------------------------------------------------------
   * 1. 상수
   * ---------------------------------------------------------------- */
  const BOARDS = {
    notice: { key: 'notice', name: '공지사항',      emoji: '📢', desc: '동호회 운영 소식과 안내를 전합니다', layout: 'list',    adminOnly: true  },
    free:   { key: 'free',   name: '자유게시판',    emoji: '💬', desc: '라이더들이 자유롭게 이야기 나누는 공간', layout: 'list',    adminOnly: false },
    review: { key: 'review', name: '라이딩 후기',   emoji: '📸', desc: '함께 달린 그날의 기록과 사진',        layout: 'gallery', adminOnly: false },
    qna:    { key: 'qna',    name: 'Q&A 문의',      emoji: '❓', desc: '궁금한 점을 남겨주시면 운영진이 답변합니다', layout: 'list', adminOnly: false }
  };

  const REGIONS    = ['서울', '경기', '인천', '강원', '충청', '전라', '경상', '제주'];
  const BIKE_TYPES = ['로드', '하이브리드', 'MTB', '미니벨로', '그래블', '기타'];

  const DIFFICULTY  = { easy: '입문', normal: '중급', hard: '상급' };
  const MEETUP_TYPE = { regular: '정기모임', small: '소규모 모임' };
  const STATUS      = { open: '신청 접수중', closed: '접수 마감', done: '종료' };
  const APP_STATUS  = { pending: '대기', confirmed: '확정', cancelled: '취소' };

  /* ------------------------------------------------------------------
   * 2. 유틸
   * ---------------------------------------------------------------- */
  const $  = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  /** URL 쿼리스트링 값 읽기 — qs('id') */
  const qs = (key, fallback = null) =>
    new URLSearchParams(location.search).get(key) ?? fallback;

  /** XSS 방지: 사용자 입력을 화면에 넣기 전에 반드시 통과시킵니다. */
  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
  }

  /** 줄바꿈을 <br>로 — escapeHtml 이후에 사용 */
  const nl2br = (str) => escapeHtml(str).replaceAll('\n', '<br>');

  const pad = (n) => String(n).padStart(2, '0');

  function fmtDate(v) {
    if (!v) return '-';
    const d = new Date(v);
    return `${d.getFullYear()}.${pad(d.getMonth() + 1)}.${pad(d.getDate())}`;
  }
  function fmtDateTime(v) {
    if (!v) return '-';
    const d = new Date(v);
    return `${fmtDate(v)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  /** 목록용: 오늘 글이면 시:분, 아니면 날짜 */
  function fmtListDate(v) {
    if (!v) return '-';
    const d = new Date(v), now = new Date();
    return d.toDateString() === now.toDateString()
      ? `${pad(d.getHours())}:${pad(d.getMinutes())}`
      : `${String(d.getFullYear()).slice(2)}.${pad(d.getMonth() + 1)}.${pad(d.getDate())}`;
  }
  function fmtMeetupDate(v) {
    if (!v) return '-';
    const d = new Date(v);
    const week = ['일', '월', '화', '수', '목', '금', '토'][d.getDay()];
    return `${d.getFullYear()}년 ${d.getMonth() + 1}월 ${d.getDate()}일 (${week}) ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  const isNew   = (v) => (Date.now() - new Date(v)) < 3 * 24 * 3600 * 1000;
  const isPast  = (v) => new Date(v) < new Date();
  const won     = (n) => Number(n || 0).toLocaleString('ko-KR');

  /** D-day 계산 */
  function dday(v) {
    const t = new Date(v); t.setHours(0, 0, 0, 0);
    const n = new Date();  n.setHours(0, 0, 0, 0);
    const diff = Math.round((t - n) / 86400000);
    if (diff === 0) return 'D-DAY';
    return diff > 0 ? `D-${diff}` : `종료`;
  }

  /* ------------------------------------------------------------------
   * 3. 토스트 알림
   * ---------------------------------------------------------------- */
  function toast(message, type = '') {
    let wrap = $('.toast-wrap');
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.className = 'toast-wrap';
      document.body.appendChild(wrap);
    }
    const el = document.createElement('div');
    el.className = 'toast ' + type;
    el.textContent = message;
    wrap.appendChild(el);
    setTimeout(() => {
      el.style.transition = 'opacity .3s, transform .3s';
      el.style.opacity = '0';
      el.style.transform = 'translateX(24px)';
      setTimeout(() => el.remove(), 320);
    }, 3000);
  }
  const ok  = (m) => toast(m, 'ok');
  const err = (m) => toast(m, 'error');

  /* ------------------------------------------------------------------
   * 4. 비밀번호 입력 모달 (비회원 수정/삭제용)
   * ---------------------------------------------------------------- */
  function askPassword(title = '비밀번호 확인', desc = '작성 시 입력한 비밀번호를 넣어주세요.') {
    return new Promise((resolve) => {
      const back = document.createElement('div');
      back.className = 'modal-back';
      back.innerHTML = `
        <div class="modal" role="dialog" aria-modal="true">
          <div class="modal-head"><h3 class="mb-0">${escapeHtml(title)}</h3></div>
          <div class="modal-body">
            <p class="small muted mb-2">${escapeHtml(desc)}</p>
            <input type="password" class="input" id="pwInput" placeholder="비밀번호" autocomplete="current-password">
          </div>
          <div class="modal-foot">
            <button class="btn btn-ghost btn-sm" data-act="cancel">취소</button>
            <button class="btn btn-primary btn-sm" data-act="ok">확인</button>
          </div>
        </div>`;
      document.body.appendChild(back);
      const input = $('#pwInput', back);
      input.focus();

      const close = (val) => { back.remove(); resolve(val); };
      back.addEventListener('click', (e) => {
        if (e.target === back) close(null);
        const act = e.target.dataset.act;
        if (act === 'cancel') close(null);
        if (act === 'ok') close(input.value);
      });
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') close(input.value);
        if (e.key === 'Escape') close(null);
      });
    });
  }

  function confirmBox(message) { return window.confirm(message); }

  /**
   * 같은 컨테이너를 여러 번 다시 그릴 때 이벤트 리스너가 중복 등록되는 문제를 막습니다.
   * 기존 요소를 같은 id의 새 요소로 갈아끼우고 그 요소를 돌려줍니다.
   */
  function fresh(selector) {
    const old = document.querySelector(selector);
    if (!old) return null;
    const el = old.cloneNode(false);   // 자식 없이 속성만 복사 → 리스너는 따라오지 않음
    old.replaceWith(el);
    return el;
  }

  /* ------------------------------------------------------------------
   * 5. 인증 상태
   * ---------------------------------------------------------------- */
  let _session = null;
  let _profile = null;

  async function loadSession() {
    const { data } = await sb.auth.getSession();
    _session = data.session;
    if (_session) {
      // 프로필이 없으면 이 시점에 만들어 줍니다(회원가입 직후 대비).
      const { data: p } = await sb.from(T('profiles')).select('*').eq('id', _session.user.id).maybeSingle();
      if (p) {
        _profile = p;
      } else {
        const meta = _session.user.user_metadata || {};
        const { data: created } = await sb.from(T('profiles')).insert({
          id:     _session.user.id,
          email:  _session.user.email,
          name:   meta.name || _session.user.email.split('@')[0],
          phone:  meta.phone || null,
          region: meta.region || '서울'
        }).select().maybeSingle();
        _profile = created;
      }
    } else {
      _profile = null;
    }
    return _session;
  }

  const session  = () => _session;
  const user     = () => _session?.user ?? null;
  const profile  = () => _profile;
  const isLogin  = () => !!_session;
  const isAdmin  = () => _profile?.role === 'admin';
  const myName   = () => _profile?.nickname || _profile?.name || '회원';

  async function logout() {
    await sb.auth.signOut();
    location.href = 'index.html';
  }

  /* ------------------------------------------------------------------
   * 6. 헤더 / 푸터
   * ---------------------------------------------------------------- */
  const NAV = [
    { key: 'home',     href: 'index.html',   label: '홈' },
    { key: 'about',    href: 'about.html',   label: '동호회 소개' },
    { key: 'meetups',  href: 'meetups.html', label: '모임 일정' },
    { key: 'courses',  href: 'courses.html', label: '지역 코스' }
  ];

  function headerHtml(active) {
    const nav = NAV.map(n =>
      `<a href="${n.href}" class="${active === n.key ? 'active' : ''}">${n.label}</a>`).join('');

    const boardMenu = Object.values(BOARDS).map(b =>
      `<a href="board.html?board=${b.key}">${b.emoji} ${b.name}</a>`).join('');

    return `
    <header class="site-header">
      <div class="inner">
        <a href="index.html" class="logo">
          <span class="mark">🚴</span>
          <span>스카이라이더스<small>SKY RIDERS</small></span>
        </a>
        <button class="nav-toggle" id="navToggle" aria-label="메뉴 열기">☰</button>
        <nav class="nav" id="mainNav">
          ${nav}
          <div class="nav-drop ${active === 'board' ? 'active' : ''}" id="boardDrop">
            <button type="button">커뮤니티 ▾</button>
            <div class="menu">${boardMenu}</div>
          </div>
          <div class="nav-auth" id="navAuth"></div>
        </nav>
      </div>
    </header>`;
  }

  function renderAuthArea() {
    const box = $('#navAuth');
    if (!box) return;
    if (isLogin()) {
      box.innerHTML = `
        ${isAdmin() ? '<a href="admin.html" class="btn btn-soft btn-sm">⚙️ 관리자</a>' : ''}
        <a href="mypage.html" class="btn btn-ghost btn-sm">${escapeHtml(myName())} 님</a>
        <button class="btn btn-ghost btn-sm" id="btnLogout">로그아웃</button>`;
      $('#btnLogout').addEventListener('click', logout);
    } else {
      box.innerHTML = `
        <a href="mypage.html" class="btn btn-ghost btn-sm">신청 조회</a>
        <a href="login.html" class="btn btn-primary btn-sm">로그인</a>`;
    }
  }

  function footerHtml() {
    const boardLinks = Object.values(BOARDS).map(b =>
      `<li><a href="board.html?board=${b.key}">${b.name}</a></li>`).join('');
    return `
    <footer class="site-footer">
      <div class="container">
        <div class="footer-grid">
          <div>
            <div class="logo mb-2"><span class="mark">🚴</span><span>스카이라이더스<small>SKY RIDERS</small></span></div>
            <p class="small" style="max-width:380px">
              하늘길을 달리는 로드 자전거 동호회입니다. 연 4회 정기모임과 매달 소규모 모임으로
              전국 방방곡곡을 함께 달립니다. ☁️🚲
            </p>
          </div>
          <div>
            <h4>바로가기</h4>
            <ul>${NAV.map(n => `<li><a href="${n.href}">${n.label}</a></li>`).join('')}</ul>
          </div>
          <div>
            <h4>커뮤니티</h4>
            <ul>${boardLinks}</ul>
          </div>
        </div>
        <div class="footer-bottom">
          <span>© 2026 SKY RIDERS · 강의용 샘플 사이트</span>
          <span>문의 hello@skyriders.example · 매주 토요일 정기 라이딩</span>
        </div>
      </div>
    </footer>`;
  }

  function bindNav() {
    const toggle = $('#navToggle'), nav = $('#mainNav'), drop = $('#boardDrop');
    toggle?.addEventListener('click', () => nav.classList.toggle('open'));
    drop?.querySelector('button')?.addEventListener('click', (e) => {
      e.stopPropagation();
      drop.classList.toggle('open');
    });
    document.addEventListener('click', (e) => {
      if (drop && !drop.contains(e.target)) drop.classList.remove('open');
    });
    if (window.matchMedia('(hover: hover)').matches && drop) {
      drop.addEventListener('mouseenter', () => drop.classList.add('open'));
      drop.addEventListener('mouseleave', () => drop.classList.remove('open'));
    }
  }

  /* ------------------------------------------------------------------
   * 7. 페이지 부트스트랩
   *    각 페이지에서 App.mount('meetups').then(...) 형태로 호출합니다.
   * ---------------------------------------------------------------- */
  async function mount(activeKey = '') {
    document.body.insertAdjacentHTML('afterbegin', headerHtml(activeKey));
    document.body.insertAdjacentHTML('beforeend', footerHtml());
    bindNav();
    await loadSession();
    renderAuthArea();
    return { session: _session, profile: _profile };
  }

  /** 로그인이 반드시 필요한 페이지에서 사용 */
  function requireLogin(redirect = true) {
    if (isLogin()) return true;
    if (redirect) {
      err('로그인이 필요합니다.');
      setTimeout(() => location.href = `login.html?next=${encodeURIComponent(location.pathname.split('/').pop() + location.search)}`, 800);
    }
    return false;
  }

  /* ------------------------------------------------------------------
   * 8. Supabase 에러 메시지를 사람이 읽을 수 있게
   * ---------------------------------------------------------------- */
  function readError(error) {
    if (!error) return '알 수 없는 오류가 발생했습니다.';
    const m = error.message || String(error);
    if (m.includes('Invalid login credentials')) return '이메일 또는 비밀번호가 올바르지 않습니다.';
    if (m.includes('User already registered'))   return '이미 가입된 이메일입니다.';
    if (m.includes('Password should be'))        return '비밀번호는 6자 이상이어야 합니다.';
    if (m.includes('Email not confirmed'))       return '이메일 인증이 완료되지 않았습니다.';
    if (m.includes('duplicate key'))             return '이미 등록된 내용입니다.';
    if (m.includes('violates row-level security')) return '권한이 없습니다.';
    return m;
  }

  /* ------------------------------------------------------------------
   * 9. 공개 API
   * ---------------------------------------------------------------- */
  return {
    BOARDS, REGIONS, BIKE_TYPES, DIFFICULTY, MEETUP_TYPE, STATUS, APP_STATUS,
    $, $$, qs, escapeHtml, nl2br,
    fmtDate, fmtDateTime, fmtListDate, fmtMeetupDate, isNew, isPast, won, dday,
    toast, ok, err, askPassword, confirmBox, fresh,
    mount, loadSession, renderAuthArea,
    session, user, profile, isLogin, isAdmin, myName, logout, requireLogin,
    readError
  };
})();
