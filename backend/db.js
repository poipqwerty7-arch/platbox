// db.js — подключение к Postgres (Railway) и инициализация схемы.
// Локально можно поднять свой Postgres или указать DATABASE_URL от Railway.
const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.warn('⚠️  DATABASE_URL не задан. Установи переменную окружения (см. README).');
}

const pool = new Pool({
  connectionString,
  // Railway требует SSL для внешних подключений; для внутреннего сервиса тоже безопасно.
  ssl: connectionString && connectionString.includes('railway') ? { rejectUnauthorized: false } : false,
});

async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      display_name TEXT,
      avatar_color TEXT DEFAULT '#4f9dde',
      coins INTEGER DEFAULT 500,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS games (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      author_id INTEGER REFERENCES users(id),
      thumbnail_color TEXT DEFAULT '#6c5ce7',
      play_count INTEGER DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id),
      created_at TIMESTAMPTZ DEFAULT now(),
      expires_at TIMESTAMPTZ NOT NULL
    );
  `);

  const { rows } = await pool.query('SELECT COUNT(*)::int AS c FROM games');
  if (rows[0].c === 0) {
    const insert = 'INSERT INTO games (title, description, thumbnail_color, play_count) VALUES ($1, $2, $3, $4)';
    await pool.query(insert, ['Obby: Башня Испытаний', 'Классический платформер-полоса препятствий. Доберись до вершины!', '#e74c3c', 15234]);
    await pool.query(insert, ['Город Свободы', 'Открытый мир, катайся на машинах, стройся дом.', '#27ae60', 8921]);
    await pool.query(insert, ['Симулятор Пекаря', 'Пеки, продавай, прокачивай пекарню.', '#f39c12', 4310]);
    await pool.query(insert, ['Арена Битв 1v1', 'PvP арена с оружием и прокачкой.', '#9b59b6', 22110]);
  }
}

module.exports = { pool, initSchema };
