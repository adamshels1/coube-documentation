# Задачи по реализации QR подписания - Backend

## Обзор

Реализация интеграции с eGov Mobile для подписания документов (договоры, счета-фактуры, акты, реестры) через QR код и cross-signing (deep links).

## Список задач

### ✅ TASK-1: Создать схему БД для QR подписания
**Файл**: `TASK-1-database-schema.md`
**Story Points**: 3
**Приоритет**: High

Создать таблицу `egov_signing_session` и расширить таблицу `signature`.

**Deliverables:**
- SQL миграция Flyway
- Entity класс `EgovSigningSession`
- Индексы для производительности

---

### ✅ TASK-2: API №1 - Получение информации о подписании
**Файл**: `TASK-2-api-get-signing-info.md`
**Story Points**: 5
**Приоритет**: High

Реализовать `GET /api/egov-sign/info/{sessionId}` для eGov Mobile.

**API:**
```
GET /api/egov-sign/info/{sessionId}?token={token}
Response: { description, expiryDate, organisation, document }
```

**Deliverables:**
- Controller `EgovSignController`
- Service `EgovSigningService`
- DTO: `SigningInfoDTO`, `OrganisationDTO`, `DocumentAuthDTO`
- Exception handlers (404, 410)
- Unit тесты

---

### ✅ TASK-3: API №2 - Получение документов для подписания
**Файл**: `TASK-3-api-get-documents.md`
**Story Points**: 8
**Приоритет**: High

Реализовать API для получения документов с поддержкой 3 типов аутентификации.

**API:**
```
GET /api/egov-sign/documents/{sessionId}  (NONE, TOKEN)
POST /api/egov-sign/documents/{sessionId} (EDS)
Response: { signMethod, version, documentsToSign[] }
```

**Deliverables:**
- Service `DocumentPreparationService`
- Расширение `EgovSigningService`
- DTO: `DocumentsToSignDTO`, `DocumentToSignDTO`, `DocumentFileDTO`
- Поддержка методов подписания: XML, CMS_WITH_DATA, SIGN_BYTES_ARRAY
- Кодирование файлов в base64
- Unit и integration тесты

---

### ✅ TASK-4: API №2 - Прием подписанных документов
**Файл**: `TASK-4-api-submit-signed-documents.md`
**Story Points**: 13
**Приоритет**: Critical

Реализовать прием и валидацию подписанных документов согласно НУЦ РК.

**API:**
```
PUT /api/egov-sign/documents/{sessionId}
Request: { signMethod, documentsToSign[] }
Response: { status: "success" | "failed", message }
```

**Deliverables:**
- Service `SignatureValidationService`
- Service `KalkanIntegrationService`
- OCSP интеграция с НУЦ РК
- CRL проверка (fallback)
- Проверка цепочки сертификатов
- Проверка KeyUsage, алгоритма ГОСТ
- Сохранение подписей в БД
- Обновление статуса документов
- Unit тесты для каждого метода валидации

---

### ✅ TASK-5: Генерация QR кода и создание сессии
**Файл**: `TASK-5-qr-generation-session.md`
**Story Points**: 5
**Приоритет**: High

Реализовать создание сессии подписания и генерацию QR кода.

**API:**
```
POST /api/contracts/{contractId}/create-signing-session
POST /api/invoices/{invoiceId}/create-signing-session
POST /api/acts/{actId}/create-signing-session
POST /api/registries/{registryId}/create-signing-session

Response: { sessionId, qrCodeUrl, qrCodeImage, expiresAt, status }
```

**Deliverables:**
- Service `QrCodeGenerator`
- Service `SigningSessionManager`
- Service `DeepLinkGenerator` (для iOS/Android)
- Service `TokenGenerator`
- Controllers для всех типов документов
- Зависимость ZXing для QR
- Unit тесты

---

### ✅ TASK-6: Журналирование и аудит для SIEM
**Файл**: `TASK-6-audit-logging.md`
**Story Points**: 5
**Приоритет**: Medium

Реализовать журналирование событий для SIEM системы.

**Deliverables:**
- Service `AuditLoggingService`
- Logback конфигурация (syslog appender)
- Scheduled задача очистки истекших сессий
- Логирование событий:
  - Создание сессии
  - Успешное подписание
  - Ошибки валидации
  - OCSP/CRL запросы
  - Истечение сессии
- Метрики подписания (опционально)
- Unit тесты

---

## Общая информация

### Суммарные Story Points
**Всего**: 39 SP (~7-8 рабочих дней для 1 разработчика)

### Порядок выполнения
1. **TASK-1** → Database schema (база для всего)
2. **TASK-5** → QR generation (создание сессий)
3. **TASK-2** → API №1 (информация о подписании)
4. **TASK-3** → API №2 GET/POST (получение документов)
5. **TASK-4** → API №2 PUT (валидация подписей) - самая сложная
6. **TASK-6** → Audit logging (логирование)

### Зависимости

```
TASK-1 (DB)
  ├── TASK-2 (API №1)
  │     └── TASK-3 (API №2 GET/POST)
  │           └── TASK-4 (API №2 PUT)
  │                 └── TASK-6 (Audit)
  └── TASK-5 (QR Generation)
```

### Технологии и библиотеки

**Обязательные:**
- Spring Boot 3.x
- PostgreSQL
- Flyway
- ZXing (QR generation) - `com.google.zxing:core:3.5.1`
- BouncyCastle (криптография) - `org.bouncycastle:bcprov-jdk15on:1.70`
- Logback Syslog appender

**Опциональные:**
- JWT - `io.jsonwebtoken:jjwt:0.9.1`
- Micrometer (метрики)

### API Endpoints Summary

| Method | Path | Описание | Task |
|--------|------|----------|------|
| GET | `/api/egov-sign/info/{sessionId}` | API №1 - Информация о подписании | TASK-2 |
| GET | `/api/egov-sign/documents/{sessionId}` | API №2 - Получить документы (NONE/TOKEN) | TASK-3 |
| POST | `/api/egov-sign/documents/{sessionId}` | API №2 - Получить документы (EDS) | TASK-3 |
| PUT | `/api/egov-sign/documents/{sessionId}` | API №2 - Принять подписанные документы | TASK-4 |
| POST | `/api/contracts/{id}/create-signing-session` | Создать сессию для договора | TASK-5 |
| POST | `/api/invoices/{id}/create-signing-session` | Создать сессию для счета | TASK-5 |
| POST | `/api/acts/{id}/create-signing-session` | Создать сессию для акта | TASK-5 |
| POST | `/api/registries/{id}/create-signing-session` | Создать сессию для реестра | TASK-5 |

### Конфигурация

**application.yml:**
```yaml
app:
  egov:
    base-url: ${EGOV_BASE_URL:https://backend.coube.kz}
    qr-expiry-minutes: 30
    deep-link-base: https://mgovsign.page.link/
    nuc:
      ocsp-url: ${NUC_OCSP_URL:http://ocsp.pki.gov.kz}
      crl-url: ${NUC_CRL_URL:http://crl.pki.gov.kz}

logging:
  siem:
    enabled: ${SIEM_ENABLED:false}
    host: ${SIEM_HOST:localhost}
    port: ${SIEM_PORT:514}
```

### Таблицы БД

**Новые:**
- `applications.egov_signing_session` - сессии подписания

**Расширенные:**
- `file.signature` - добавлены поля для eGov подписания

**Используемые:**
- `applications.contract`
- `applications.invoices`
- `applications.acts`
- `applications.registries`
- `file.file_meta_info`
- `user.organization`
- `user.employee`

### Тестирование

**Unit тесты:**
- Все сервисы
- Все контроллеры
- Валидация подписей
- Генерация QR
- Форматирование логов

**Integration тесты:**
- API эндпоинты (все 8)
- База данных (миграции, entity)
- OCSP интеграция (mock)

**Manual тестирование:**
- QR сканирование через eGov Mobile
- Deep links на iOS/Android
- Валидация реальных подписей НУЦ РК

### Связанная документация

- [Flow диаграммы](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md)
- [Smart Bridge требования](../../business_analysis/converted/QR%20sign/Smart%20Bridge.md)
- [Документация QR и кросс подписания](../../business_analysis/converted/QR%20sign/Документация_к_QR_и_Кросс_подписанию.md)
- [Архитектура БД](../../database-architecture/database-architecture-auto-generated.md)

### Контакты для вопросов

**eGov Mobile интеграция:**
- Сервис: https://sb.egov.kz/
- НУЦ РК OCSP: http://ocsp.pki.gov.kz
- НУЦ РК CRL: http://crl.pki.gov.kz

### Чеклист перед деплоем

- [ ] Все миграции применены
- [ ] Все тесты проходят (unit + integration)
- [ ] Swagger документация обновлена
- [ ] Конфигурация для prod окружения
- [ ] SIEM логирование настроено
- [ ] OCSP/CRL URLs проверены
- [ ] QR коды валидируются в eGov Mobile
- [ ] Deep links работают на iOS/Android
- [ ] Валидация подписей НУЦ РК работает
- [ ] Scheduled задачи запускаются
