# Задача 12: False Positives — обоснование для отчёта

**Компонент:** Все

## Цель

Подготовить обоснование для уязвимостей, которые являются false positive или не требуют исправления. Этот документ предоставляется аудиторам/заказчику ГТС.

---

## 1. Cross-Site Request Forgery (3 проблемы) — FALSE POSITIVE

**Файлы:**
- `coube-mobile/src/api/index.ts:393` (uploadCourierPhoto)
- `coube-mobile/src/services/telegram.ts:40` (sendToBot)
- `coube-frontend/src/utils/notifications.js:104` (sendTokenToBackend)

**Обоснование:**
CSRF-атаки актуальны только для приложений, использующих cookie-based аутентификацию. Наша система использует **token-based аутентификацию (Bearer JWT)** через OAuth2/Keycloak. Токен передаётся в заголовке `Authorization`, а не через cookies. Браузер не автоматически прикрепляет Bearer-токены к запросам, поэтому CSRF-атака невозможна.

**Ссылка:** [OWASP CSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html) — "If your application uses token-based authentication (e.g., JWT), CSRF protection is generally not needed."

**Статус:** Не требует исправления.

---

## 2. Insecure Transport: Disabled App Transport Security (1 проблема) — ACCEPTED RISK

**Файл:** `coube-mobile/ios/coube/Info.plist:60`

**Что найдено:** `NSAllowsLocalNetworking = true`

**Обоснование:**
- `NSAllowsArbitraryLoads` установлен в `false` — основная защита включена
- `NSAllowsLocalNetworking = true` — разрешает только локальные сетевые подключения
- Это **стандартная настройка React Native** для работы Metro bundler и hot-reload при разработке
- В production эта настройка не влияет на безопасность, так как локальные подключения не используются
- Apple не отклоняет приложения с этой настройкой

**Статус:** Accepted risk. Не влияет на безопасность в production.

---

## 3. Android Bad Practices: Missing Component Permission (1 проблема) — FALSE POSITIVE

**Файл:** `coube-mobile/android/app/src/main/AndroidManifest.xml:42`

**Что найдено:** MainActivity с `android:exported="true"` без `android:permission`

**Обоснование:**
- Это **LAUNCHER Activity** — точка входа в приложение
- По спецификации Android, launcher activity ОБЯЗАТЕЛЬНО должна быть `exported="true"` без permission
- Добавление `android:permission` к launcher activity сделает приложение незапускаемым с домашнего экрана
- Это стандартная конфигурация для всех Android приложений

**Ссылка:** [Android Developer Docs — App Manifest](https://developer.android.com/guide/topics/manifest/activity-element#exported)

**Статус:** Не требует исправления. False positive.

---

## 4. Cleartext Traffic в Debug Manifest (1 проблема) — BY DESIGN

**Файл:** `coube-mobile/android/app/src/debug/AndroidManifest.xml:6`

**Что найдено:** `android:usesCleartextTraffic="true"`

**Обоснование:**
- Этот файл применяется **ТОЛЬКО** к debug-сборкам (не попадает в release APK)
- Необходим для работы React Native Metro bundler (подключение к localhost)
- В release-сборке используется `network_security_config.xml` с запретом cleartext
- Debug-сборка никогда не публикуется в Google Play

**Статус:** By design. Исправляется в рамках задачи #11 (Network Security Config).

---

## 5. Firebase API Key в Frontend (2 проблемы) — LOW RISK

**Файлы:**
- `coube-frontend/public/firebase-messaging-sw.js:5`
- `coube-frontend/src/firebase.js:5`

**Обоснование:**
Firebase API Key **по дизайну является публичным**. Согласно документации Google:
- API Key используется только для идентификации проекта, не для авторизации
- Безопасность обеспечивается Firebase Security Rules на стороне сервера
- Все официальные примеры Google включают API Key в клиентский код

**Ссылка:** [Firebase — Use API keys with Firebase](https://firebase.google.com/docs/projects/api-keys)

> Тем не менее, мы выносим ключи в env-переменные (задача #9) для соответствия best practices и требованиям аудита.

**Статус:** Исправляется в задаче #9, но риск минимальный.

---

## 6. Credential Management: Bearer в документации (4 проблемы) — LOW RISK

**Файл:** `coube-backend/docs/routes-contracts-api.md`

**Что найдено:** `Authorization: Bearer eyJhbGci...`

**Обоснование:**
- Это усечённые примеры в **внутренней документации** (не публичной)
- Токены заканчиваются на `...` — они неполные и невалидные
- JWT-токены имеют срок действия (обычно 15-30 минут)
- Документация не публикуется для внешних пользователей

> Тем не менее, заменяем на плейсхолдеры (задача #5) для чистоты отчёта.

**Статус:** Исправляется в задаче #5.

---

## Итого

| Проблема | Статус | Причина |
|----------|--------|---------|
| CSRF (3) | False positive | Token-based auth, не cookie |
| iOS ATS (1) | Accepted risk | Стандарт React Native |
| Android exported Activity (1) | False positive | Launcher activity |
| Debug cleartext (1) | By design | Только debug-сборка |
| Firebase API Key frontend (2) | Low risk + fix | Публичный ключ по дизайну |
| Bearer в docs (4) | Low risk + fix | Внутренняя документация |

**Всего false positives / accepted risks: 9 из 181 (5%)**
