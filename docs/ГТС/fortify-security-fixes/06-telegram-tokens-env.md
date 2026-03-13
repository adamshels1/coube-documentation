# Задача 6: Telegram токены -> env переменные

**Приоритет:** Critical (Credential Management — 4 проблемы)
**Риск поломки:** Средний
**Компонент:** coube-mobile

## Проблема

Telegram Bot токены и Chat ID захардкожены в исходном коде. Оба набора (stage + production) видны в репозитории.

## Затронутые файлы

### 1. `coube-mobile/src/config/env.ts`

**БЫЛО:**
```typescript
// Stage конфигурация
export const ENV = {
  API_HOST: 'https://stage-platform.coube.kz',
  TELEGRAM_SUCCESS_BOT_TOKEN: 'YOUR_TELEGRAM_SUCCESS_BOT_TOKEN',
  TELEGRAM_ERROR_BOT_TOKEN: 'YOUR_TELEGRAM_ERROR_BOT_TOKEN',
  TELEGRAM_CHAT_ID: 'YOUR_TELEGRAM_CHAT_ID',
};

// Production конфигурация
// export const ENV = {
//   API_HOST: 'https://platform.coube.kz',
//   TELEGRAM_CHAT_ID: 'YOUR_TELEGRAM_CHAT_ID',
//   TELEGRAM_ERROR_BOT_TOKEN: 'YOUR_TELEGRAM_PROD_ERROR_BOT_TOKEN',
//   TELEGRAM_SUCCESS_BOT_TOKEN: 'YOUR_TELEGRAM_PROD_SUCCESS_BOT_TOKEN',
// };

export default ENV;
```

**СТАЛО:**

Шаг 1 — Установить `react-native-config`:
```bash
cd coube-mobile && npm install react-native-config
```

Шаг 2 — Создать `.env` (добавить в `.gitignore`):
```
API_HOST=https://stage-platform.coube.kz
TELEGRAM_SUCCESS_BOT_TOKEN=YOUR_TELEGRAM_SUCCESS_BOT_TOKEN
TELEGRAM_ERROR_BOT_TOKEN=YOUR_TELEGRAM_ERROR_BOT_TOKEN
TELEGRAM_CHAT_ID=YOUR_TELEGRAM_CHAT_ID
```

Шаг 3 — Создать `.env.example` (БЕЗ реальных значений):
```
API_HOST=https://stage-platform.coube.kz
TELEGRAM_SUCCESS_BOT_TOKEN=your_token_here
TELEGRAM_ERROR_BOT_TOKEN=your_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

Шаг 4 — Обновить `env.ts`:
```typescript
import Config from 'react-native-config';

export const ENV = {
  API_HOST: Config.API_HOST || 'https://stage-platform.coube.kz',
  TELEGRAM_SUCCESS_BOT_TOKEN: Config.TELEGRAM_SUCCESS_BOT_TOKEN || '',
  TELEGRAM_ERROR_BOT_TOKEN: Config.TELEGRAM_ERROR_BOT_TOKEN || '',
  TELEGRAM_CHAT_ID: Config.TELEGRAM_CHAT_ID || '',
};

export default ENV;
```

Шаг 5 — Удалить закомментированную production конфигурацию полностью.

### 2. `coube-mobile/src/services/telegram.ts`

Файл не требует изменений — он уже читает из `ENV`.

## После исправления

1. **Ротация токенов**: текущие токены скомпрометированы (есть в git history). Создать новые через @BotFather
2. **CI/CD**: добавить `.env` файлы как secrets в CI/CD пайплайн
3. **`.gitignore`**: добавить `.env` и `.env.production`

## Проверка

```bash
# Запуск Metro
cd coube-mobile && npm start

# Проверить что ENV загружается
# В отладчике: console.log(ENV.API_HOST) -> должен показать значение из .env

# Telegram уведомления работают
# Сделать действие которое триггерит отправку -> проверить что сообщение пришло в чат
```

## Риски

- Если `react-native-config` не настроен правильно для iOS/Android, ENV будут пустые
- Нужна native пересборка (`npx pod-install` для iOS, rebuild для Android)
- CI/CD должен подставлять `.env` файл перед сборкой
