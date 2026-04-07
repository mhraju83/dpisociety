// ============================================================
//  DPI Society — Shared Configuration
//  config.js  |  Include this in every page's <head>
//
//  What this file provides:
//  ─ Supabase credentials (ONE place to update)
//  ─ window.sb          → ready Supabase client
//  ─ window.DPI.session → current user + profile
//  ─ window.DPI.initNav → updates nav bar for any page
//  ─ window.DPI.utils   → shared helpers (esc, timeAgo, etc.)
//  ─ window.DPI.toast   → global toast notification
// ============================================================

// ════════════════════════════════════════════════════════════
//  🔑  CREDENTIALS — ONLY CHANGE THESE TWO LINES
// ════════════════════════════════════════════════════════════
const SUPABASE_URL = 'https://mktdbwokfonynfmpsqcx.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1rdGRid29rZm9ueW5mbXBzcWN4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0OTA4OTEsImV4cCI6MjA5MTA2Njg5MX0.J-75lBzdoxIfQaR386M_nhY7i6r69VQnXFT3AFEMH0o';

// ════════════════════════════════════════════════════════════
//  AVATAR COLOUR PALETTE  (consistent across all pages)
// ════════════════════════════════════════════════════════════
const DPI_AV_COLORS = [
  { bg:'#D1F5E8', tc:'#006A4E' },
  { bg:'#FDEEF0', tc:'#C8102E' },
  { bg:'#FFF3D4', tc:'#B87800' },
  { bg:'#E8F0FD', tc:'#2B5DB8' },
  { bg:'#D4F5F0', tc:'#0D7A6A' },
  { bg:'#FDE8F0', tc:'#B82B6A' },
  { bg:'#EDE8FD', tc:'#5B2BB8' },
  { bg:'#F0FAFF', tc:'#0A6A9E' },
];

// ════════════════════════════════════════════════════════════
//  LOAD SUPABASE SDK + INITIALISE CLIENT
// ════════════════════════════════════════════════════════════
(function loadSupabase() {
  const script  = document.createElement('script');
  script.src    = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  script.onload = () => {
    window.sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    window.dispatchEvent(new Event('dpi:supabase-ready'));
    if (window.DPI && window.DPI._onReady) window.DPI._onReady();
  };
  document.head.appendChild(script);
})();

// ════════════════════════════════════════════════════════════
//  DPI NAMESPACE
// ════════════════════════════════════════════════════════════
window.DPI = {

  // Current session — populated by initSession()
  session: {
    user:    null,
    profile: null,
  },

  // Internal ready callback queue
  _onReady: null,

  // ── WAIT FOR SUPABASE ──────────────────────────────────────
  // Ensures window.sb is ready before using it.
  // Usage: await DPI.ready()
  ready() {
    return new Promise(resolve => {
      if (window.sb) { resolve(); return; }
      window.addEventListener('dpi:supabase-ready', resolve, { once: true });
    });
  },

  // ══════════════════════════════════════════════════════════
  //  SESSION — load current user + profile
  // ══════════════════════════════════════════════════════════
  async initSession() {
    await this.ready();
    try {
      const { data: { session } } = await window.sb.auth.getSession();
      if (!session) return null;

      this.session.user = session.user;

      const { data: profile } = await window.sb
        .from('profiles')
        .select('full_name, avatar_url, user_type, batch, department, status')
        .eq('id', session.user.id)
        .single();

      this.session.profile = profile;
      return { user: session.user, profile };
    } catch (e) {
      // Supabase not yet configured — silent fail
      return null;
    }
  },

  // ══════════════════════════════════════════════════════════
  //  NAV — update the nav bar based on session state
  //  Call after initSession() on every page.
  //  Expects a <div id="navActions"> in the page.
  //  activePage: 'home'|'members'|'events'|'resources'|'forum'
  // ══════════════════════════════════════════════════════════
  initNav(activePage) {
    // Update active nav link
    document.querySelectorAll('.nav-links a').forEach(a => {
      a.classList.remove('active');
    });
    if (activePage) {
      const link = document.querySelector(`.nav-links a[data-page="${activePage}"]`);
      if (link) link.classList.add('active');
    }

    // Update nav actions (login/join → avatar)
    const navEl = document.getElementById('navActions');
    if (!navEl) return;

    const { user, profile } = this.session;

    if (!user) {
      // Visitor — show Login + Join
      navEl.innerHTML = `
        <a href="login.html" class="dpi-btn-outline">Log In</a>
        <a href="register.html" class="dpi-btn-primary">Join Free</a>`;
      return;
    }

    // Logged in — show avatar
    const name     = profile?.full_name || '';
    const initials = name
      ? name.trim().split(/\s+/).slice(0,2).map(n => n[0].toUpperCase()).join('')
      : '?';

    const avatarHtml = profile?.avatar_url
      ? `<img src="${this.utils.esc(profile.avatar_url)}"
              style="width:32px;height:32px;border-radius:50%;object-fit:cover;"
              alt="${this.utils.esc(name)}"
              onerror="this.outerHTML='${initials}'">`
      : initials;

    navEl.innerHTML = `
      <a href="index.html" class="dpi-nav-avatar" title="${this.utils.esc(name) || 'My Profile'}">
        ${avatarHtml}
      </a>`;

    // Admin shortcut
    if (profile?.user_type === 'admin') {
      navEl.innerHTML += `
        <a href="admin.html" class="dpi-btn-primary" style="margin-left:8px;">⚙ Admin</a>`;
    }

    // ── Show Finance link for all logged-in members ──
    // The link exists in the nav but is hidden (display:none) by default.
    // We reveal it here once we confirm the user is authenticated.
    const financeLink = document.getElementById('financeNavLink');
    if (financeLink) {
      financeLink.style.display = '';

      // Mark as active if we're currently on finance.html
      if (window.location.pathname.endsWith('finance.html')) {
        financeLink.classList.add('active');
      }
    }
  },

  // ══════════════════════════════════════════════════════════
  //  AUTH GUARDS
  // ══════════════════════════════════════════════════════════

  // Redirect to login if not authenticated
  requireAuth() {
    if (!this.session.user) {
      window.location.href = 'login.html?redirect=' +
        encodeURIComponent(window.location.pathname + window.location.search);
      return false;
    }
    return true;
  },

  // Redirect away if already logged in (for login/register pages)
  redirectIfLoggedIn() {
    if (this.session.user) {
      const params   = new URLSearchParams(window.location.search);
      const redirect = params.get('redirect');
      window.location.href = redirect
        ? decodeURIComponent(redirect)
        : (this.session.profile?.user_type === 'admin' ? 'admin.html' : 'index.html');
      return true;
    }
    return false;
  },

  // ══════════════════════════════════════════════════════════
  //  AUTH HELPERS
  // ══════════════════════════════════════════════════════════
  async logout() {
    await this.ready();
    await window.sb.auth.signOut();
    this.session.user    = null;
    this.session.profile = null;
    window.location.href = 'index.html';
  },

  // ══════════════════════════════════════════════════════════
  //  TOAST — global notification (needs a #dpiToast element)
  //  Each page should include: <div id="dpiToast"></div>
  // ══════════════════════════════════════════════════════════
  toast(msg, duration = 3200) {
    let el = document.getElementById('dpiToast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'dpiToast';
      document.body.appendChild(el);
    }
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => el.classList.remove('show'), duration);
  },

  // ══════════════════════════════════════════════════════════
  //  SHARED UTILITIES
  // ══════════════════════════════════════════════════════════
  utils: {

    // HTML escape — prevent XSS
    esc(str) {
      if (!str) return '';
      return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    },

    // Relative time string
    timeAgo(iso) {
      if (!iso) return '—';
      const diff = Date.now() - new Date(iso);
      if (diff < 60000)     return 'just now';
      if (diff < 3600000)   return Math.floor(diff / 60000)   + ' min ago';
      if (diff < 86400000)  return Math.floor(diff / 3600000) + ' hr ago';
      if (diff < 604800000) return Math.floor(diff / 86400000)+ ' days ago';
      if (diff < 2592000000)return Math.floor(diff / 604800000)+ ' weeks ago';
      return new Date(iso).toLocaleDateString('en-GB',
        { day:'numeric', month:'short', year:'numeric' });
    },

    // Format date
    formatDate(iso) {
      if (!iso) return '—';
      return new Date(iso).toLocaleDateString('en-GB',
        { day:'numeric', month:'short', year:'numeric' });
    },

    // Is within past 7 days?
    isNew(iso) {
      if (!iso) return false;
      return (Date.now() - new Date(iso)) < 7 * 86400000;
    },

    // Avatar colour from name string
    avatarColor(name) {
      const sum = (name||'').split('').reduce((s,c) => s + c.charCodeAt(0), 0);
      return DPI_AV_COLORS[sum % DPI_AV_COLORS.length];
    },

    // Get initials from full name
    initials(name) {
      if (!name) return '?';
      return name.trim().split(/\s+/).slice(0,2).map(n => n[0].toUpperCase()).join('');
    },

    // Check if a resource countdown is needed
    getCountdown(dateObj) {
      const diff = dateObj - new Date();
      if (diff <= 0) return null;
      return {
        days:  Math.floor(diff / 86400000),
        hours: Math.floor((diff % 86400000) / 3600000),
        mins:  Math.floor((diff % 3600000) / 60000),
      };
    },
  },
};

// ════════════════════════════════════════════════════════════
//  GLOBAL SHARED STYLES injected once into every page
//  (nav buttons, avatar, toast — consistent across all pages)
// ════════════════════════════════════════════════════════════
(function injectSharedStyles() {
  const style = document.createElement('style');
  style.textContent = `
    /* ── Shared nav button styles ── */
    .dpi-btn-outline {
      font-size:13px; font-weight:500; padding:7px 16px; border-radius:7px;
      border:1.5px solid var(--green,#006A4E); color:var(--green,#006A4E);
      background:transparent; cursor:pointer; text-decoration:none; transition:all 0.2s;
      display:inline-block;
    }
    .dpi-btn-outline:hover { background:var(--green-pale,#E8F5F0); }

    .dpi-btn-primary {
      font-size:13px; font-weight:500; padding:7px 16px; border-radius:7px;
      border:none; background:var(--green,#006A4E); color:white;
      cursor:pointer; text-decoration:none; transition:all 0.2s; display:inline-block;
    }
    .dpi-btn-primary:hover { background:var(--green-light,#00875F); }

    /* ── Nav avatar ── */
    .dpi-nav-avatar {
      width:32px; height:32px; border-radius:50%;
      display:inline-flex; align-items:center; justify-content:center;
      font-size:11px; font-weight:700;
      background:var(--green-pale,#E8F5F0); color:var(--green,#006A4E);
      cursor:pointer; border:2px solid var(--green,#006A4E);
      text-decoration:none; transition:all 0.2s; overflow:hidden;
    }
    .dpi-nav-avatar:hover { background:var(--green,#006A4E); color:white; }

    /* ── Global toast ── */
    #dpiToast {
      position:fixed; bottom:28px; right:24px;
      background:#0D1A13; color:white;
      font-size:13px; font-weight:500;
      padding:11px 20px; border-radius:10px;
      opacity:0; transition:all 0.3s;
      pointer-events:none; z-index:9999;
      transform:translateY(6px); max-width:320px;
      font-family:'DM Sans',sans-serif;
    }
    #dpiToast.show { opacity:1; transform:translateY(0); }
  `;
  document.head.appendChild(style);
})();
