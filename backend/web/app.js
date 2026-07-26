// app.js — логика Platbox: авторизация, загрузка игр, состояние пользователя
const API = '/api';

const state = {
  token: localStorage.getItem('platbox_token') || null,
  user: null,
};

// ---------- DOM ----------
const authOverlay = document.getElementById('authOverlay');
const loginForm = document.getElementById('loginForm');
const registerForm = document.getElementById('registerForm');
const navActions = document.getElementById('navActions');
const gamesGrid = document.getElementById('gamesGrid');

function openAuth(mode = 'login') {
  authOverlay.classList.add('open');
  if (mode === 'login') {
    loginForm.style.display = 'block';
    registerForm.style.display = 'none';
  } else {
    loginForm.style.display = 'none';
    registerForm.style.display = 'block';
  }
}
function closeAuth() {
  authOverlay.classList.remove('open');
  document.getElementById('loginError').classList.remove('show');
  document.getElementById('registerError').classList.remove('show');
}

document.getElementById('loginBtn').addEventListener('click', () => openAuth('login'));
document.getElementById('registerBtn').addEventListener('click', () => openAuth('register'));
document.getElementById('heroCta').addEventListener('click', () => {
  if (state.user) {
    document.getElementById('games').scrollIntoView({ behavior: 'smooth' });
  } else {
    openAuth('register');
  }
});
document.getElementById('modalClose').addEventListener('click', closeAuth);
authOverlay.addEventListener('click', (e) => { if (e.target === authOverlay) closeAuth(); });
document.getElementById('switchToRegister').addEventListener('click', () => openAuth('register'));
document.getElementById('switchToLogin').addEventListener('click', () => openAuth('login'));

// ---------- API helpers ----------
async function apiFetch(path, options = {}) {
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (state.token) headers['Authorization'] = `Bearer ${state.token}`;
  const res = await fetch(API + path, { ...options, headers });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Что-то пошло не так');
  return data;
}

function showError(id, message) {
  const el = document.getElementById(id);
  el.textContent = message;
  el.classList.add('show');
}

// ---------- Auth actions ----------
document.getElementById('registerSubmit').addEventListener('click', async () => {
  const username = document.getElementById('regUsername').value.trim();
  const email = document.getElementById('regEmail').value.trim();
  const password = document.getElementById('regPassword').value;
  const btn = document.getElementById('registerSubmit');

  document.getElementById('registerError').classList.remove('show');
  btn.disabled = true; btn.textContent = 'Создаём…';
  try {
    const data = await apiFetch('/auth/register', { method: 'POST', body: JSON.stringify({ username, email, password }) });
    setSession(data.token, data.user);
    closeAuth();
  } catch (err) {
    showError('registerError', err.message);
  } finally {
    btn.disabled = false; btn.textContent = 'Создать аккаунт';
  }
});

document.getElementById('loginSubmit').addEventListener('click', async () => {
  const username = document.getElementById('loginIdentifier').value.trim();
  const password = document.getElementById('loginPassword').value;
  const btn = document.getElementById('loginSubmit');

  document.getElementById('loginError').classList.remove('show');
  btn.disabled = true; btn.textContent = 'Входим…';
  try {
    const data = await apiFetch('/auth/login', { method: 'POST', body: JSON.stringify({ username, password }) });
    setSession(data.token, data.user);
    closeAuth();
  } catch (err) {
    showError('loginError', err.message);
  } finally {
    btn.disabled = false; btn.textContent = 'Войти';
  }
});

function setSession(token, user) {
  state.token = token;
  state.user = user;
  localStorage.setItem('platbox_token', token);
  renderNav();
}

function logout() {
  apiFetch('/auth/logout', { method: 'POST' }).catch(() => {});
  state.token = null;
  state.user = null;
  localStorage.removeItem('platbox_token');
  renderNav();
}

// ---------- Nav rendering ----------
function renderNav() {
  if (!state.user) {
    navActions.innerHTML = `
      <button class="btn btn-ghost" id="loginBtn">Войти</button>
      <button class="btn btn-primary" id="registerBtn">Создать аккаунт</button>
    `;
    document.getElementById('loginBtn').addEventListener('click', () => openAuth('login'));
    document.getElementById('registerBtn').addEventListener('click', () => openAuth('register'));
    return;
  }
  const initial = state.user.display_name?.[0]?.toUpperCase() || '?';
  navActions.innerHTML = `
    <div class="user-pill" id="userPill">
      <div class="avatar" style="background:${state.user.avatar_color}">${initial}</div>
      <span>${state.user.display_name}</span>
      <span class="coins">🪙 ${state.user.coins}</span>
    </div>
    <button class="btn btn-sm btn-ghost" id="logoutBtn">Выйти</button>
  `;
  document.getElementById('logoutBtn').addEventListener('click', logout);
}

// ---------- Games ----------
async function loadGames() {
  try {
    const data = await apiFetch('/games');
    renderGames(data.games);
  } catch (err) {
    gamesGrid.innerHTML = `<p style="color:#c0392b;">Не удалось загрузить игры: ${err.message}</p>`;
  }
}

function renderGames(games) {
  if (!games.length) {
    gamesGrid.innerHTML = `<p style="color:#8b849f;">Пока нет игр. Стань первым, кто опубликует свою!</p>`;
    return;
  }
  gamesGrid.innerHTML = games.map(g => `
    <div class="game-card" data-id="${g.id}">
      <div class="game-thumb" style="background:${g.thumbnail_color}"></div>
      <div class="game-body">
        <p class="game-title">${escapeHtml(g.title)}</p>
        <div class="game-meta">
          <span>${escapeHtml(g.author_name || 'Platbox')}</span>
          <span>▶ ${g.play_count.toLocaleString('ru-RU')}</span>
        </div>
      </div>
    </div>
  `).join('');

  gamesGrid.querySelectorAll('.game-card').forEach(card => {
    card.addEventListener('click', async () => {
      const id = card.dataset.id;
      if (!state.user) { openAuth('login'); return; }
      try {
        await apiFetch(`/games/${id}/play`, { method: 'POST' });
        alert('Запускаем игру в Godot-клиенте (см. godot-client/) — веб-плеер в разработке.');
        loadGames();
      } catch (err) {
        alert(err.message);
      }
    });
  });
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// ---------- Init ----------
async function init() {
  if (state.token) {
    try {
      const data = await apiFetch('/me');
      state.user = data.user;
    } catch (e) {
      state.token = null;
      localStorage.removeItem('platbox_token');
    }
  }
  renderNav();
  loadGames();
}

init();
