// server.js — Platbox API: чистый Node.js (http), Postgres через pg.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { pool, initSchema } = require('./db');
const { hashPassword, verifyPassword, signToken, verifyToken } = require('./auth');

const PORT = process.env.PORT || 3000;
const STATIC_DIR = path.join(__dirname, 'web');

function sendJSON(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 1e6) req.destroy(); // защита от слишком больших тел запроса
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (e) {
        resolve({});
      }
    });
    req.on('error', reject);
  });
}

async function getUserFromAuth(req) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const token = authHeader.slice(7);
  const payload = verifyToken(token);
  if (!payload) return null;

  const { rows: sessionRows } = await pool.query('SELECT * FROM sessions WHERE token = $1', [token]);
  const session = sessionRows[0];
  if (!session) return null;
  if (new Date(session.expires_at).getTime() < Date.now()) return null;

  const { rows: userRows } = await pool.query(
    'SELECT id, username, email, display_name, avatar_color, coins, created_at FROM users WHERE id = $1',
    [payload.userId]
  );
  return userRows[0] || null;
}

// --- Валидация ---
const USERNAME_RE = /^[a-zA-Z0-9_]{3,20}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isValidUsername(u) { return typeof u === 'string' && USERNAME_RE.test(u); }
function isValidEmail(e) { return typeof e === 'string' && EMAIL_RE.test(e); }
function isValidPassword(p) { return typeof p === 'string' && p.length >= 6 && p.length <= 128; }

// --- Роуты ---
const routes = {
  'POST /api/auth/register': async (req, res) => {
    const { username, email, password } = await readBody(req);

    if (!isValidUsername(username)) {
      return sendJSON(res, 400, { error: 'Никнейм: 3-20 символов, латиница/цифры/подчёркивание' });
    }
    if (!isValidEmail(email)) {
      return sendJSON(res, 400, { error: 'Некорректный email' });
    }
    if (!isValidPassword(password)) {
      return sendJSON(res, 400, { error: 'Пароль должен быть от 6 до 128 символов' });
    }

    const { rows: existingRows } = await pool.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2', [username, email]
    );
    if (existingRows[0]) {
      return sendJSON(res, 409, { error: 'Пользователь с таким ником или email уже существует' });
    }

    const { hash, salt } = hashPassword(password);
    const colors = ['#e74c3c', '#3498db', '#2ecc71', '#f39c12', '#9b59b6', '#1abc9c'];
    const avatarColor = colors[Math.floor(Math.random() * colors.length)];

    const { rows: insertRows } = await pool.query(
      `INSERT INTO users (username, email, password_hash, salt, display_name, avatar_color)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
      [username, email, hash, salt, username, avatarColor]
    );
    const userId = insertRows[0].id;

    const token = signToken({ userId });
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    await pool.query('INSERT INTO sessions (token, user_id, expires_at) VALUES ($1, $2, $3)', [token, userId, expiresAt]);

    const { rows: userRows } = await pool.query(
      'SELECT id, username, email, display_name, avatar_color, coins, created_at FROM users WHERE id = $1',
      [userId]
    );
    return sendJSON(res, 201, { token, user: userRows[0] });
  },

  'POST /api/auth/login': async (req, res) => {
    const { username, password } = await readBody(req);
    if (!username || !password) {
      return sendJSON(res, 400, { error: 'Введите ник/email и пароль' });
    }

    const { rows } = await pool.query('SELECT * FROM users WHERE username = $1 OR email = $1', [username]);
    const user = rows[0];
    if (!user || !verifyPassword(password, user.salt, user.password_hash)) {
      return sendJSON(res, 401, { error: 'Неверный логин или пароль' });
    }

    const token = signToken({ userId: user.id });
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    await pool.query('INSERT INTO sessions (token, user_id, expires_at) VALUES ($1, $2, $3)', [token, user.id, expiresAt]);

    const { password_hash, salt, ...safeUser } = user;
    return sendJSON(res, 200, { token, user: safeUser });
  },

  'POST /api/auth/logout': async (req, res) => {
    const authHeader = req.headers['authorization'];
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.slice(7);
      await pool.query('DELETE FROM sessions WHERE token = $1', [token]);
    }
    return sendJSON(res, 200, { ok: true });
  },

  'GET /api/me': async (req, res) => {
    const user = await getUserFromAuth(req);
    if (!user) return sendJSON(res, 401, { error: 'Не авторизован' });
    return sendJSON(res, 200, { user });
  },

  'GET /api/games': async (req, res) => {
    const { rows: games } = await pool.query(`
      SELECT games.*, users.username as author_name
      FROM games LEFT JOIN users ON games.author_id = users.id
      ORDER BY play_count DESC
    `);
    return sendJSON(res, 200, { games });
  },

  'POST /api/games/:id/play': async (req, res, params) => {
    const id = Number(params.id);
    const { rows } = await pool.query(
      'UPDATE games SET play_count = play_count + 1 WHERE id = $1 RETURNING *',
      [id]
    );
    if (!rows[0]) return sendJSON(res, 404, { error: 'Игра не найдена' });
    return sendJSON(res, 200, { game: rows[0] });
  },
};

function matchRoute(method, pathname) {
  const key = `${method} ${pathname}`;
  if (routes[key]) return { handler: routes[key], params: {} };

  for (const routeKey of Object.keys(routes)) {
    const [routeMethod, routePath] = routeKey.split(' ');
    if (routeMethod !== method) continue;
    const routeParts = routePath.split('/');
    const pathParts = pathname.split('/');
    if (routeParts.length !== pathParts.length) continue;
    const params = {};
    let matched = true;
    for (let i = 0; i < routeParts.length; i++) {
      if (routeParts[i].startsWith(':')) {
        params[routeParts[i].slice(1)] = pathParts[i];
      } else if (routeParts[i] !== pathParts[i]) {
        matched = false;
        break;
      }
    }
    if (matched) return { handler: routes[routeKey], params };
  }
  return null;
}

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

function serveStatic(req, res, pathname) {
  let filePath = path.join(STATIC_DIR, pathname === '/' ? 'index.html' : pathname);
  if (!filePath.startsWith(STATIC_DIR)) {
    res.writeHead(403);
    return res.end('Forbidden');
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      fs.readFile(path.join(STATIC_DIR, 'index.html'), (err2, data2) => {
        if (err2) {
          res.writeHead(404);
          return res.end('Not found');
        }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(data2);
      });
      return;
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    res.end(data);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  if (req.method === 'OPTIONS') {
    return sendJSON(res, 204, {});
  }

  if (pathname.startsWith('/api/')) {
    const match = matchRoute(req.method, pathname);
    if (!match) {
      return sendJSON(res, 404, { error: 'Route not found' });
    }
    try {
      await match.handler(req, res, match.params);
    } catch (err) {
      console.error('Server error:', err);
      sendJSON(res, 500, { error: 'Внутренняя ошибка сервера' });
    }
    return;
  }

  serveStatic(req, res, pathname);
});

initSchema()
  .then(() => {
    server.listen(PORT, () => {
      console.log(`🎮 Platbox API запущен на порту ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Не удалось инициализировать базу данных:', err);
    process.exit(1);
  });
