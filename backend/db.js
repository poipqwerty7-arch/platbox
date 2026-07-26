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
      coins INTEGER DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS games (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      author_id INTEGER REFERENCES users(id),
      thumbnail_color TEXT DEFAULT '#6c5ce7',
      play_count INTEGER DEFAULT 0,
      level_data JSONB,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id),
      created_at TIMESTAMPTZ DEFAULT now(),
      expires_at TIMESTAMPTZ NOT NULL
    );
  `);

  // Миграция: если таблица games уже существовала до появления level_data
  // (например, с прошлого деплоя), добавляем колонку явно.
  await pool.query(`ALTER TABLE games ADD COLUMN IF NOT EXISTS level_data JSONB;`);

  // Миграция: раньше новым пользователям выдавалось 500 монет по умолчанию —
  // меняем дефолт на 0 (сами монеты пока выдаются только вручную через БД).
  await pool.query(`ALTER TABLE users ALTER COLUMN coins SET DEFAULT 0;`);

  // Разовая чистка: удаляем старые демо-игры-заглушки (без автора и без
  // реального уровня) — они остались с прошлой версии сида. Реальные
  // опубликованные игры всегда имеют author_id, поэтому безопасно отличимы.
  await pool.query(`DELETE FROM games WHERE author_id IS NULL AND level_data IS NULL;`);
}

module.exports = { pool, initSchema };
