# Задача 9: Firebase API ключи фронта -> env

**Приоритет:** Critical (Credential Management — 2 проблемы)
**Риск поломки:** Низкий
**Компонент:** coube-frontend

## Проблема

Firebase конфигурация (apiKey, projectId и т.д.) захардкожена в двух файлах.

> **Примечание:** Firebase API Key по дизайну является публичным (это не секрет как таковой). Но Fortify всё равно помечает это как Critical. Исправление простое и не навредит.

## Затронутые файлы

### 1. `coube-frontend/src/firebase.js`

**БЫЛО:**
```javascript
const firebaseConfig = {
  apiKey: 'YOUR_FIREBASE_API_KEY',
  authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
  projectId: 'YOUR_PROJECT_ID',
  storageBucket: 'YOUR_PROJECT_ID.firebasestorage.app',
  messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
  appId: 'YOUR_APP_ID',
};
```

**СТАЛО:**
```javascript
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};
```

### 2. `coube-frontend/public/firebase-messaging-sw.js`

Этот файл сложнее — Service Worker не имеет доступа к `import.meta.env`.

**Решение**: подставлять конфиг при сборке через скрипт или передавать через `postMessage`.

**Вариант A (простой) — шаблонизация при сборке:**

Создать `firebase-messaging-sw.template.js`:
```javascript
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '%VITE_FIREBASE_API_KEY%',
  authDomain: '%VITE_FIREBASE_AUTH_DOMAIN%',
  projectId: '%VITE_FIREBASE_PROJECT_ID%',
  messagingSenderId: '%VITE_FIREBASE_MESSAGING_SENDER_ID%',
  appId: '%VITE_FIREBASE_APP_ID%',
});
```

Добавить скрипт в `package.json`:
```json
"prebuild": "node scripts/generate-sw.js"
```

### 3. Создать `.env` файлы

**`.env` (для разработки, добавить в .gitignore):**
```
VITE_FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY
VITE_FIREBASE_AUTH_DOMAIN=YOUR_PROJECT_ID.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=YOUR_PROJECT_ID
VITE_FIREBASE_STORAGE_BUCKET=YOUR_PROJECT_ID.firebasestorage.app
VITE_FIREBASE_MESSAGING_SENDER_ID=YOUR_MESSAGING_SENDER_ID
VITE_FIREBASE_APP_ID=...
```

**`.env.example` (без реальных значений, коммитится):**
```
VITE_FIREBASE_API_KEY=your_api_key
VITE_FIREBASE_AUTH_DOMAIN=your_auth_domain
VITE_FIREBASE_PROJECT_ID=your_project_id
VITE_FIREBASE_STORAGE_BUCKET=your_storage_bucket
VITE_FIREBASE_MESSAGING_SENDER_ID=your_sender_id
VITE_FIREBASE_APP_ID=your_app_id
```

## Проверка

```bash
cd coube-frontend
npm run dev
# Открыть приложение -> push-уведомления должны работать
# Проверить что firebase инициализируется (консоль браузера без ошибок)
```

## Риски

- Если `.env` не настроен — Firebase не инициализируется, push-уведомления не работают
- Service Worker может закэшироваться — пользователям может потребоваться hard refresh
- CI/CD должен подставлять `.env` значения при сборке
