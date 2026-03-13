# Backend задачи — Интеграция с MOST FinTech API

> Базовый путь API MOST: `/api/v1/coube`
> Аутентификация: `X-API-Key` header
> Формат: `multipart/form-data` для POST/PUT, JSON для GET

---

## Текущее состояние бэкенда

### Что реализовано
- Модуль `factoring` с 3 контроллерами (Customer, Executor, Payout) — 15+ эндпоинтов
- Подписание факторингового договора через ЭЦП (Kalkan)
- Генерация PDF (мультиязычные шаблоны: kk, ru, en)
- OTP-подтверждение через WhatsApp
- Отправка email с документами факторинговой компании (fallback)
- Тарифная система с расчётом комиссий по отсрочке платежа
- Управление факторами (компании, реквизиты, тарифы)
- Scheduled-джобы: retry email (5 мин), обработка подписанных АВР (5 мин), WhatsApp-напоминания (ежедневно 10:00)
- Статусы PayoutRequest: `INITIATED → SMS_PENDING → CONFIRMED → DOCUMENTS_SENT → AVR_DOCS_SENT → PAID`

### Что НЕ реализовано
- HTTP-клиент к API MOST FinTech
- Регистрация клиентов в MOST (`POST /client`)
- Проверка лимитов клиентов (`GET /client`)
- Создание факторинговой заявки в MOST (`POST /factoring`)
- Загрузка документов в MOST (`PUT /factoring`)
- Получение статуса заявки из MOST (`GET /factoring`)
- Маппинг статусов MOST ↔ Coube

### Текущий flow отправки данных
Сейчас данные отправляются **по email** факторинговой компании:
1. При подтверждении OTP — email с PDF заявки + OTP лог + договор факторинга
2. При подписании АВР — email с ZIP (АВР + счёт-фактура + договор перевозки + ЭЦП)

**Email-отправка сохраняется** как дублирующий канал наряду с API.

---

## Задачи

### BACK-1. Конфигурация и HTTP-клиент MOST API

**Приоритет:** Критический (блокирует все остальные задачи)

**Описание:**
Создать конфигурируемый HTTP-клиент для вызовов API MOST FinTech.

**Что сделать:**

1. Добавить properties в `application.yml`:
```yaml
most:
  api:
    base-url: https://api.most.kz/api/v1/coube  # или актуальный URL
    api-key: ${MOST_API_KEY}
    environment: dev  # dev | test | prod
    timeout:
      connect: 10000
      read: 30000
    retry:
      max-attempts: 3
      delay: 2000
```

2. Создать `MostApiProperties` — `@ConfigurationProperties(prefix = "most.api")`

3. Создать `MostApiClient` — сервис-обёртка над RestTemplate/WebClient:
   - Базовые методы для GET, POST (multipart), PUT (multipart)
   - Автоматическая подстановка `X-API-Key` header
   - Автоматическая подстановка `environment` поля
   - Обработка ошибок MOST (401, 404, 409, 422) → кастомные exceptions
   - Логирование запросов/ответов
   - Retry-логика для transient ошибок

4. Создать exception-классы:
   - `MostApiException` (базовый)
   - `MostClientNotFoundException` (404)
   - `MostValidationException` (422, с полем `fields`)
   - `MostConflictException` (409)
   - `MostUnauthorizedException` (401)

5. Создать DTO для ответов MOST:
   - `MostClientResponse` — { tax_id, title, kind, limit_amount }
   - `MostClientCreateResponse` — { request_id, tax_id, status, created_at }
   - `MostFactoringResponse` — { application_number, status }
   - `MostErrorResponse` — { detail: String | { message, fields[] } }

**Файлы:**
- `factoring/integration/most/MostApiProperties.java`
- `factoring/integration/most/MostApiClient.java`
- `factoring/integration/most/dto/*.java`
- `factoring/integration/most/exception/*.java`
- `application.yml` — добавить секцию `most`

---

### BACK-2. Регистрация клиентов в MOST (`POST /client`)

**Приоритет:** Критический (блокирует создание заявок)

**Описание:**
Перед созданием факторинговой заявки обе стороны (carrier и customer) должны быть зарегистрированы в MOST. Нужно автоматически регистрировать организации при первом использовании факторинга.

**Что сделать:**

1. Добавить поле в БД:
```sql
ALTER TABLE users.organization ADD COLUMN most_registered_at TIMESTAMP;
ALTER TABLE users.organization ADD COLUMN most_tax_id VARCHAR(12);
```

2. Создать `MostClientRegistrationService`:
   - `registerIfNeeded(Organization org, String role)` — проверяет `most_registered_at`, если null — регистрирует
   - `registerClient(Organization org, String role)` — вызывает `POST /client`
   - Маппинг данных Coube → MOST:
     - `tax_id` ← Organization.bin
     - `title` ← Organization.name
     - `role` ← "carrier" (executor) | "customer" (customer)
     - `ceo_fullname` ← данные директора из Employee (роль CEO)
     - `ceo_phone` ← телефон директора
     - `ceo_email` ← email директора
     - `contact_fullname` ← текущий пользователь-подписант (SIGNER)
     - `contact_phone` ← телефон подписанта
     - `contact_email` ← email подписанта

3. Вызвать регистрацию в двух точках:
   - При создании payout (`PayoutFactoringServiceImpl.createPayout`) — регистрируем carrier (executor org)
   - Там же — регистрируем customer (customer org из transportation)

4. Обработка ошибок:
   - Если клиент уже зарегистрирован (повторный вызов) — обработать gracefully
   - Если ошибка валидации — пробросить пользователю понятное сообщение
   - Логировать все вызовы

**Файлы:**
- Новая миграция: `V2026XXXX__add_most_registration_to_organization.sql`
- `factoring/integration/most/MostClientRegistrationService.java`
- Изменение: `factoring/service/PayoutFactoringServiceImpl.java`
- Изменение: `Organization.java` — добавить поля

---

### BACK-3. Проверка лимита клиента (`GET /client`)

**Приоритет:** Высокий

**Описание:**
Перед созданием факторинговой заявки нужно проверять, что у carrier есть одобренный лимит в MOST и что сумма факторинга не превышает лимит.

**Что сделать:**

1. Создать `MostClientCheckService`:
   - `checkClientLimit(String taxId)` → `MostClientResponse`
   - `hasApprovedLimit(String taxId)` → boolean (limit_amount != null)
   - `isAmountWithinLimit(String taxId, BigDecimal amount)` → boolean

2. Интегрировать проверку лимита:
   - В `PayoutFactoringServiceImpl.createPayout()` — перед созданием payout проверить лимит carrier
   - Если `limit_amount == null` — вернуть ошибку "Клиент на стадии проверки, факторинг пока недоступен"
   - Если `factoring_amount > limit_amount` — вернуть ошибку "Сумма превышает лимит"

3. Добавить эндпоинт для фронтенда:
   - `GET /api/v1/factoring/executor/limit` — проверка лимита текущей организации в MOST
   - Возвращает: `{ taxId, title, limitAmount, available: boolean }`

4. Опционально: кэшировать лимиты на короткий период (5-10 мин), чтобы не дёргать MOST на каждый запрос

**Файлы:**
- `factoring/integration/most/MostClientCheckService.java`
- Изменение: `factoring/service/PayoutFactoringServiceImpl.java`
- Изменение: `factoring/api/ExecutorFactoringController.java` — новый эндпоинт

---

### BACK-4. Создание факторинговой заявки в MOST (`POST /factoring`)

**Приоритет:** Критический

**Описание:**
После подтверждения OTP, помимо отправки email, нужно создать заявку в MOST через API. Это ключевая задача интеграции.

**Что сделать:**

1. Добавить поля в БД:
```sql
ALTER TABLE factoring.payout_request ADD COLUMN most_application_number VARCHAR(50);
ALTER TABLE factoring.payout_request ADD COLUMN most_status VARCHAR(30);
ALTER TABLE factoring.payout_request ADD COLUMN most_created_at TIMESTAMP;
ALTER TABLE factoring.payout_request ADD COLUMN most_last_checked_at TIMESTAMP;
```

2. Создать `MostFactoringService`:
   - `createFactoringApplication(FactoringPayoutRequest payout)` → `MostFactoringResponse`
   - Маппинг данных:
     - `environment` ← из конфига (dev/test/prod)
     - `coube_application_id` ← payout.transportation.id (или payout.id)
     - `carrier_tax_id` ← executor Organization.bin
     - `carrier_iban` ← BankRequisite.account (активные реквизиты executor)
     - `carrier_contact_fullname` ← signer FullName
     - `carrier_contact_phone` ← signer phone
     - `carrier_contact_email` ← signer email
     - `customer_tax_id` ← customer Organization.bin
     - `customer_contact_fullname` ← customer контактное лицо
     - `customer_contact_phone` ← customer phone
     - `customer_contact_email` ← customer email
     - `service_amount` ← transportation cost (полная сумма)
     - `factoring_amount` ← payout.financingAmount
     - `tariff` ← factorTariff.name или tariffPercentage
     - `factoring_agreement` ← PDF файл подписанного договора факторинга
     - `factoring_payout` ← PDF файл заявки на факторинг (со штампом OTP)
     - `otp_validation` ← текстовый файл с OTP логом

3. Встроить вызов в `PayoutFactoringServiceImpl.confirmPayout()`:
   - После успешной валидации OTP
   - Перед/параллельно с отправкой email
   - При успехе — сохранить `most_application_number` и `most_status` в payout
   - При ошибке — логировать, не блокировать основной flow (email всё равно отправляется)

4. Обработка ошибок:
   - 422 (клиенты не найдены) — вернуть пользователю "Необходимо зарегистрировать клиентов"
   - 422 (валидация) — логировать конкретные поля из `detail.fields`

**Файлы:**
- Новая миграция: `V2026XXXX__add_most_fields_to_payout_request.sql`
- `factoring/integration/most/MostFactoringService.java`
- Изменение: `factoring/service/PayoutFactoringServiceImpl.java`
- Изменение: `factoring/entity/FactoringPayoutRequest.java` — новые поля

---

### BACK-5. Загрузка документов в MOST (`PUT /factoring`)

**Приоритет:** Критический

**Описание:**
После подписания АВР (акта выполненных работ) нужно отправить документы в MOST через PUT `/factoring`. Это переводит заявку из статуса `new` → `processing`.

**Что сделать:**

1. Создать метод в `MostFactoringService`:
   - `uploadDocuments(FactoringPayoutRequest payout, Act act, Invoice invoice, Contract contract)` → `MostFactoringResponse`
   - Маппинг данных:
     - `environment` ← из конфига
     - `coube_application_id` ← тот же что при создании
     - `application_number` ← payout.mostApplicationNumber
     - `carrier_tax_id`, `carrier_iban`, `customer_tax_id` ← те же значения
     - `service_amount`, `factoring_amount`, `tariff` ← те же значения
     - `avr` ← PDF файл АВР (со штампами подписей)
     - `contract` ← PDF файл договора перевозки
     - `invoice` ← PDF файл счёт-фактуры
     - `cms` ← CMS-подпись (PKCS7, файл подписи)

2. Встроить вызов в `FactoringActProcessingService.processSignedFactoringActs()`:
   - После обнаружения подписанного АВР
   - Перед/параллельно с отправкой email
   - При успехе — обновить `most_status = "processing"`
   - При ошибке 409 (Conflict) — заявка уже не в статусе `new`, логировать
   - При ошибке 422 — несовпадение полей, логировать `detail.fields`

3. Добавить поля для отслеживания:
```sql
ALTER TABLE factoring.payout_request ADD COLUMN most_documents_sent_at TIMESTAMP;
```

**Файлы:**
- Новая миграция: `V2026XXXX__add_most_documents_sent_to_payout.sql`
- Изменение: `factoring/integration/most/MostFactoringService.java`
- Изменение: `factoring/service/FactoringActProcessingService.java`
- Изменение: `factoring/entity/FactoringPayoutRequest.java`

---

### BACK-6. Polling статуса заявок из MOST (`GET /factoring`)

**Приоритет:** Высокий

**Описание:**
Нужно периодически проверять статус заявок в MOST и обновлять статус в Coube. Это позволит автоматически переводить заявки в статус PAID.

**Что сделать:**

1. Создать `MostStatusPollingService` (scheduled job):
   - Запускать каждые 10-15 минут
   - Выбирать все payouts где `most_application_number IS NOT NULL` и `most_status NOT IN ('issued', 'rejected', 'closed')`
   - Для каждого — вызвать `GET /factoring?application_number=XXX`
   - Обновить `most_status` и `most_last_checked_at`

2. Маппинг статусов MOST → Coube:

| Статус MOST | Действие в Coube |
|-------------|------------------|
| `new` | Без изменений (ждём загрузки документов) |
| `processing` | Без изменений (документы в обработке) |
| `ready_for_issue` | Логировать, уведомить (опционально) |
| `issued` | Обновить PayoutStatus → `PAID`, установить `paidAt` |
| `rejected` | Новый статус `REJECTED`, уведомить executor |
| `closed` | Обновить PayoutStatus → `PAID` (если не был), установить `paidAt` |

3. Добавить новый PayoutStatus:
   - `REJECTED` — заявка отклонена MOST
   - Обновить enum `PayoutStatus`

4. Уведомления при смене статуса:
   - `issued` → push/WhatsApp executor: "Оплата по заявке №{number} произведена"
   - `rejected` → push/WhatsApp executor: "Заявка №{number} отклонена"

**Файлы:**
- `factoring/integration/most/MostStatusPollingService.java`
- Изменение: `factoring/entity/PayoutStatus.java` — добавить REJECTED
- Новая миграция для обновления enum (если хранится в БД)
- Опционально: уведомления через NotificationService

---

### BACK-7. Retry-механизм для вызовов MOST API

**Приоритет:** Высокий

**Описание:**
Вызовы к внешнему API могут падать. Нужен надёжный retry-механизм.

**Что сделать:**

1. Создать таблицу для outbox-паттерна:
```sql
CREATE TABLE factoring.most_api_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_request_id UUID REFERENCES factoring.payout_request(id),
    operation VARCHAR(30) NOT NULL,  -- CREATE_APPLICATION, UPLOAD_DOCUMENTS
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING, PROCESSING, COMPLETED, FAILED
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 5,
    last_error TEXT,
    next_retry_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);
```

2. Создать `MostApiOutboxService`:
   - `scheduleOperation(payoutId, operation, payload)` — добавить в outbox
   - `processOutbox()` — @Scheduled(fixedRate = 60000) — каждую минуту
   - Exponential backoff: 1 мин → 2 мин → 4 мин → 8 мин → 16 мин
   - После max_attempts — статус FAILED, alert в логи

3. Переписать вызовы MOST через outbox:
   - `confirmPayout()` → `scheduleOperation(CREATE_APPLICATION)`
   - `processSignedFactoringActs()` → `scheduleOperation(UPLOAD_DOCUMENTS)`

**Файлы:**
- Новая миграция: `V2026XXXX__create_most_api_outbox.sql`
- `factoring/integration/most/MostApiOutboxService.java`
- `factoring/integration/most/entity/MostApiOutbox.java`
- `factoring/integration/most/repository/MostApiOutboxRepository.java`

---

### BACK-8. Исправление существующих TODO и проблем

**Приоритет:** Средний

**Описание:**
В коде есть несколько TODO-комментариев и проблем, которые стоит исправить параллельно с интеграцией.

**Что сделать:**

1. **TODO в PayoutFactoringServiceImpl:113** — добавить проверку что executor действительно принят customer-ом для данной перевозки (проверить статус TransportationCost)

2. **TODO в PayoutFactoringServiceImpl:318** — реализовать PAID статус:
   - Теперь решается через BACK-6 (polling статусов MOST)
   - Добавить также ручной endpoint для admin: `POST /api/v1/admin/factoring/payout/{id}/mark-paid`

3. **TODO в PayoutFactoringServiceImpl:328** — вынести email `no-reply@coube.kz` в properties:
```yaml
coube:
  email:
    from: no-reply@coube.kz
```

4. **TODO в PayoutFactoringServiceImpl:229** — добавить проверку даты создания originalFile при отправке OTP (не старше 24 часов)

5. **Hardcoded URL** в FactorService — `https://mfomost.kz/coube_offer` — вынести в properties с fallback

6. **Hardcoded 26 дней** в FactoringActProcessingService — вынести в properties или таблицу factor_tariff

**Файлы:**
- Изменение: `factoring/service/PayoutFactoringServiceImpl.java`
- Изменение: `factoring/service/FactorService.java`
- Изменение: `factoring/service/FactoringActProcessingService.java`
- Изменение: `application.yml`

---

### BACK-9. Новый эндпоинт — статус заявки в MOST

**Приоритет:** Средний

**Описание:**
Фронтенду нужен эндпоинт для отображения статуса заявки в MOST.

**Что сделать:**

1. Добавить в `PayoutFactoringController`:
   - `GET /api/v1/factoring/payout/{id}/most-status`
   - Возвращает: `{ applicationNumber, mostStatus, lastCheckedAt, coube_status }`

2. Расширить `PayoutResponseDto`:
   - Добавить поля `mostApplicationNumber`, `mostStatus`

3. Расширить `GET /api/v1/factoring/payout/{id}` — включить MOST-данные в ответ

**Файлы:**
- Изменение: `factoring/api/PayoutFactoringController.java`
- Изменение: `factoring/dto/PayoutResponseDto.java`

---

### BACK-10. Миграция базы данных — сводная

**Приоритет:** Критический (делать перед всеми задачами)

**Описание:**
Единая миграция для всех новых полей, необходимых для интеграции с MOST.

```sql
-- Новые поля в organization
ALTER TABLE users.organization ADD COLUMN most_registered_at TIMESTAMP;
ALTER TABLE users.organization ADD COLUMN most_tax_id VARCHAR(12);

-- Новые поля в payout_request
ALTER TABLE factoring.payout_request ADD COLUMN most_application_number VARCHAR(50);
ALTER TABLE factoring.payout_request ADD COLUMN most_status VARCHAR(30);
ALTER TABLE factoring.payout_request ADD COLUMN most_created_at TIMESTAMP;
ALTER TABLE factoring.payout_request ADD COLUMN most_last_checked_at TIMESTAMP;
ALTER TABLE factoring.payout_request ADD COLUMN most_documents_sent_at TIMESTAMP;

-- Outbox таблица
CREATE TABLE factoring.most_api_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_request_id UUID REFERENCES factoring.payout_request(id),
    operation VARCHAR(30) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 5,
    last_error TEXT,
    next_retry_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);

CREATE INDEX idx_most_outbox_status ON factoring.most_api_outbox(status, next_retry_at);
CREATE INDEX idx_payout_most_status ON factoring.payout_request(most_status);
```

**Файлы:**
- `db/migration/factoring/V2026XXXX__add_most_fintech_integration.sql`

---

## Порядок выполнения

```
BACK-10 (миграция БД)
    ↓
BACK-1 (HTTP-клиент)
    ↓
 ┌──────────────────────┐
 ↓                      ↓
BACK-2 (регистрация)   BACK-8 (TODO-фиксы)
 ↓
BACK-3 (проверка лимита)
 ↓
BACK-4 (создание заявки)
 ↓
BACK-5 (загрузка документов)
 ↓
 ┌──────────────────────┐
 ↓                      ↓
BACK-6 (polling)       BACK-7 (retry/outbox)
 ↓
BACK-9 (эндпоинт статуса)
```

---

## Маппинг: что есть сейчас → что будет

| Текущее поведение | Новое поведение |
|-------------------|-----------------|
| Email с PDF → фактору | Email **+ API POST /factoring** → MOST |
| Email с ZIP (АВР) → фактору | Email **+ API PUT /factoring** → MOST |
| Статус PAID — нет механизма | **Polling GET /factoring** → автоматический PAID |
| Нет регистрации клиентов | **Авторегистрация POST /client** при первом payout |
| Нет проверки лимитов | **Проверка GET /client** перед созданием payout |
| Нет номера заявки MOST | Сохраняется `most_application_number` |
