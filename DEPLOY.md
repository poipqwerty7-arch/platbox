# Деплой Platbox на Railway

Пошаговая инструкция, чтобы бэкенд + база данных жили в облаке (Railway), а не только на твоём ноуте.

## Шаг 1. Аккаунт и проект

1. Зайди на https://railway.app и войди через GitHub.
2. Нажми **New Project**.

## Шаг 2. Добавь Postgres

1. В новом проекте: **+ New → Database → Add PostgreSQL**.
2. Railway сам поднимет базу и создаст переменную `DATABASE_URL` — она понадобится следующему шагу, копировать вручную не нужно, Railway подключит её автоматически внутри проекта.

## Шаг 3. Задеплой бэкенд

Проще всего — через GitHub:

1. Залей папку `backend/` (или весь проект `platbox/`) к себе на GitHub в отдельный репозиторий.
2. В Railway: **+ New → GitHub Repo** → выбери репозиторий.
3. Если в репозитории лежит весь `platbox/`, а не только `backend/` — в настройках сервиса (**Settings → Root Directory**) укажи `backend`, чтобы Railway собирал именно бэкенд.
4. Railway автоматически определит Node.js проект по `package.json` и запустит `npm install && npm start`.

**Альтернатива без GitHub** — через Railway CLI:
```bash
npm install -g @railway/cli
cd backend
railway login
railway init
railway up
```

## Шаг 4. Подключи базу к серверу

1. В сервисе бэкенда → вкладка **Variables**.
2. Добавь переменную `DATABASE_URL` со значением `${{Postgres.DATABASE_URL}}` — так Railway сам подставит адрес базы из шага 2 (набери `${{` и появится автокомплит с доступными сервисами).
3. Добавь `JWT_SECRET` — любая длинная случайная строка (например, сгенерируй на https://1password.com/password-generator/, 40+ символов).

## Шаг 5. Публичный адрес

1. В сервисе бэкенда → **Settings → Networking → Generate Domain**.
2. Получишь адрес вида `platbox-production.up.railway.app`.
3. Проверь в браузере: `https://platbox-production.up.railway.app/api/games` — должен вернуться JSON со списком игр.

## Шаг 6. Обнови Godot-клиент

В `godot-client/scripts/session.gd` замени:
```gdscript
const RAILWAY_URL := "https://твой-проект.up.railway.app/api"
```
на свой реальный адрес из шага 5 (не забудь `/api` на конце и `https`).

## Шаг 7. Веб-версия сайта

Сервер уже раздаёт `web/` как статику, так что сайт Platbox будет доступен прямо на том же домене:
```
https://platbox-production.up.railway.app
```
Отдельно хостить веб-часть не нужно.

## Стоимость и лимиты

- Railway даёт бесплатный starter-кредит (обычно ~5$ в месяц), после — платно по использованию.
- Такой лёгкий проект (простой Node-сервер + маленькая Postgres-база) обычно укладывается в бесплатный лимит при небольшом трафике.
- Сервис не "засыпает" как на Render, но при превышении бесплатного лимита Railway попросит привязать карту.

## Локальная разработка после переезда на Postgres

Если хочешь тестировать локально без облака — подними Postgres на ноуте (например, через Docker):
```bash
docker run --name platbox-db -e POSTGRES_PASSWORD=platbox -e POSTGRES_DB=platbox -p 5432:5432 -d postgres
```
Затем создай `backend/.env` (по образцу `.env.example`):
```
DATABASE_URL=postgresql://postgres:platbox@localhost:5432/platbox
JWT_SECRET=любая-строка-для-разработки
```
И запускай сервер как обычно: `node server.js` (переменные из `.env` подхватятся, если добавишь `require('dotenv').config()` в начало `server.js`, либо экспортируй их в терминале вручную перед запуском).
