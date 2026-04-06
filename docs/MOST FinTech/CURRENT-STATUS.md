# MOST FinTech — Текущий статус интеграции

> Дата: 2026-04-06  
> Цель: зафиксировать что реализовано, что не работает и что нужно сделать

---

## Что уже реализовано в коде

### HTTP-клиент (`MostApiClient`)
- GET, POST multipart, PUT multipart
- Автоматический `X-API-Key` header
- Автоматический `environment` параметр
- Retry на 5xx ошибки
- Маппинг ошибок: 401 → `MostUnauthorizedException`, 404 → `MostClientNotFoundException`, 409 → `MostConflictException`, 422 → `MostValidationException`

### Сервисы
| Сервис | Назначение | Статус |
|--------|-----------|--------|
| `MostClientRegistrationService` | POST /client — регистрация организации | ✅ Реализован |
| `MostClientCheckService` | GET /client — проверка лимита | ✅ Реализован |
| `MostCreateApplicationService` | POST /factoring — создание заявки | ✅ Реализован |
| `MostUploadDocumentsService` | PUT /factoring — загрузка документов АВР | ✅ Реализован (но не вызывается) |
| `MostFactoringStatusService` | GET /factoring — получение статуса | ✅ Реализован |
| `MostStatusPollingService` | Polling статусов каждые 15 мин | ✅ Реализован |
| `MostClientPollingService` | Polling клиентов каждые 10 мин | ✅ Реализован |
| `MostApiOutboxService` | Outbox retry-механизм каждую минуту | ✅ Реализован |

### Outbox (retry-механизм)
- Таблица `factoring.most_api_outbox` существует
- Операции: `CREATE_APPLICATION`, `UPLOAD_DOCUMENTS`
- Exponential backoff: 1 → 2 → 4 → 8 → 16 мин
- После 5 попыток — статус `FAILED`

### Конфиг (application-prod.yml)
```yaml
most:
  api:
    base-url: https://cf.mfomost.kz/api/v1/coube
    api-key: 5gcb8mZnIkHTIjHpkUxQZLcqxVDljPPu
    environment: dev   # ⚠️ нужно поменять на prod
    timeout:
      connect: 10000
      read: 30000
    retry:
      max-attempts: 3
      delay: 2000
```

---

## Что не работает и почему

### Проблема 1 — POST /factoring не уходит (критично)

**Где:** `PayoutFactoringServiceImpl.confirmPayout()`

**Что происходит:** После подтверждения OTP вызывается:
```java
mostApiOutboxService.scheduleCreateApplication(payout.getId());
```
Запись попадает в `most_api_outbox`, но нужно проверить что `MostApiOutboxService` корректно её обрабатывает и вызывает `MostCreateApplicationService`.

**Факт:** По данным MOST — заявки 1931 и 1932 у них не создавались. `most_application_number = NULL` в БД.

**Нужно проверить:**
1. Есть ли записи в `most_api_outbox` для этих payout_request
2. Если есть — какой статус и `last_error`
3. Корректно ли `MostApiOutboxService` вызывает `MostCreateApplicationService`

---

### Проблема 2 — PUT /factoring не уходит (критично)

**Где:** `FactoringActProcessingService.processSignedFactoringActs()` строка ~139

**Что происходит:**
```java
// Mono возвращается но никто не подписывается → HTTP-запрос не уходит
mostUploadDocumentsService.uploadDocuments(payout, act, invoice, contract);
```

**Причина:** `uploadDocuments` возвращает `Mono<MostApplicationResponse>`. Без `.block()` или `.subscribe()` реактивный поток никогда не выполняется.

**Факт:** `most_documents_sent_at = NULL` для всех заявок, нет ни одного лога MOST API при обработке АВР.

**Нужно:** добавить `.block()` или использовать outbox (scheduleUploadDocuments).

---

### Проблема 3 — environment = "dev" в prod конфиге

**Где:** `application-prod.yml`

```yaml
environment: dev  # ← должно быть prod
```

**Влияние:** MOST может обрабатывать запросы в тестовом режиме вместо продового.

---

## План исправлений

### Шаг 1 — Проверить outbox для заявок 1931 и 1932
```sql
SELECT id, operation, status, attempts, last_error, next_retry_at, created_at
FROM factoring.most_api_outbox
WHERE payout_request_id IN (
  '64822fcb-c6e9-4676-b458-c0aeb23d7b96',  -- заявка 58 (транспортировка 1931)
  'b233d01a-b4e6-4d25-9c37-13062507a6bf'   -- заявка 59 (транспортировка 1932)
);
```

### Шаг 2 — Исправить PUT /factoring (Mono не подписан)

**Файл:** `FactoringActProcessingService.java` ~строка 139

```java
// БЫЛО (не работает):
mostUploadDocumentsService.uploadDocuments(payout, act, invoice, contract);

// НУЖНО (вариант 1 — синхронно):
MostApplicationResponse response = mostUploadDocumentsService
    .uploadDocuments(payout, act, invoice, contract)
    .block();

// НУЖНО (вариант 2 — через outbox, надёжнее):
mostApiOutboxService.scheduleUploadDocuments(payout.getId());
```

### Шаг 3 — Исправить environment в prod конфиге

**Файл:** `application-prod.yml`

```yaml
environment: prod  # было: dev
```

### Шаг 4 — Проверить MostApiOutboxService

Убедиться что outbox корректно вызывает:
- `MostCreateApplicationService` для `CREATE_APPLICATION`
- `MostUploadDocumentsService` для `UPLOAD_DOCUMENTS`

---

## Проверка после исправлений

1. Создать тестовую перевозку с факторингом
2. Подтвердить OTP → проверить что в `most_api_outbox` появилась запись `CREATE_APPLICATION` и она ушла в `COMPLETED`
3. Проверить что `most_application_number` заполнился в `payout_request`
4. Подписать АВР → проверить что `most_documents_sent_at` заполнился
5. Убедиться что статус в MOST перешёл в `processing`
