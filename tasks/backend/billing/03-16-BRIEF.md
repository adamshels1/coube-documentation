# Краткий обзор остальных файлов задач (03-15)

## Обзор

Этот документ содержит краткое описание остальных файлов задач для реализации биллинга. Полные версии можно создать по мере необходимости.

---

## 03. Integration Layer (03-integration-layer.md)

**Назначение**: Слой интеграции между Coube Platform и Kill Bill.

**Основные компоненты**:
- `KillBillClient` — wrapper для Kill Bill REST API
- `KillBillService` — бизнес-логика взаимодействия
- Retry mechanism для устойчивости
- Error handling и маппинг ошибок
- WebClient настройка (connection pool, timeouts)

**Ключевые методы**:
```java
createAccount(CreateAccountRequest) → UUID
createSubscription(UUID accountId, String planName) → UUID
getInvoices(UUID accountId) → List<Invoice>
recordPayment(UUID invoiceId, BigDecimal amount) → Payment
```

---

## 04. API Accounts (04-api-accounts.md)

**Назначение**: API управления биллинг-аккаунтами.

**Endpoints**:
- `POST /api/v1/billing/accounts` — создать аккаунт
- `GET /api/v1/billing/accounts/{id}` — получить аккаунт
- `GET /api/v1/billing/balance` — текущий баланс пользователя
- `GET /api/v1/billing/transactions` — история операций

**Бизнес-логика**:
- Определение new/old клиента (проверка `users.organization.deleted_at`)
- Создание в Kill Bill + локальное сохранение
- Назначение пробного периода для новых клиентов
- Синхронизация данных между Kill Bill и Coube DB

---

## 05. API Subscriptions (05-api-subscriptions.md)

**Назначение**: API подписок для Заказчиков.

**Endpoints**:
- `POST /api/v1/billing/subscriptions` — создать подписку
- `GET /api/v1/billing/subscriptions/{id}` — получить подписку
- `PUT /api/v1/billing/subscriptions/{id}/cancel` — отменить подписку
- `GET /api/v1/billing/subscriptions/active` — активные подписки пользователя

**Бизнес-логика**:
- Выбор тарифа (trial vs standard)
- Создание подписки в Kill Bill
- Локальное сохранение в `billing.subscription`
- Автоматическое продление подписки
- Обработка изменения тарифа (upgrade/downgrade)

---

## 06. API Commissions (06-api-commissions.md)

**Назначение**: API резервов и комиссий для Исполнителей (агентская модель 5%).

**Endpoints**:
- `POST /api/v1/billing/reservations` — резервировать комиссию
- `POST /api/v1/billing/reservations/{id}/capture` — зачислить комиссию
- `POST /api/v1/billing/reservations/{id}/release` — освободить резерв
- `GET /api/v1/billing/reservations` — список резервов

**Бизнес-логика**:
- Проверка `available_balance >= commission_amount`
- Создание резерва в статусе `hold`
- Обновление `reserved_balance`
- Capture при подтверждении заявки
- Release при отмене заявки
- Автоматическое истечение резервов (expires_at)

**Формула комиссии**:
```
commission_amount = transportation.cost * 0.05
```

---

## 07. API Invoices (07-api-invoices.md)

**Назначение**: API счетов и пополнения баланса.

**Endpoints**:
- `POST /api/v1/billing/invoices/topup` — создать счёт на пополнение
- `GET /api/v1/billing/invoices` — список счетов
- `GET /api/v1/billing/invoices/{id}` — детали счёта
- `GET /api/v1/billing/invoices/{id}/pdf` — скачать PDF

**Бизнес-логика**:
- Генерация номера счёта (`INV-YYYYMMDD-000001`)
- Создание в `billing.invoice`
- Генерация PDF с реквизитами
- Синхронизация с Kill Bill инвойсами
- Автоматические счета за подписку (ежемесячно)
- Статусы: draft → pending → paid/overdue

---

## 08. API Payments (08-api-payments.md)

**Назначение**: API обработки платежей (webhook от PSP).

**Endpoints**:
- `POST /api/v1/billing/webhook/bcc` — webhook от BCC
- `POST /api/v1/billing/webhook/jusan` — webhook от Jusan
- `POST /api/v1/admin/billing/payments/manual` — ручное подтверждение (MVP)

**Бизнес-логика**:
- Проверка подписи webhook (HMAC SHA256)
- Логирование в `billing.webhook_log`
- Парсинг payload
- Поиск invoice по `invoiceId`
- Создание `Payment` (status=success)
- Увеличение баланса
- Вызов Kill Bill `recordPayment`
- Идемпотентность (проверка `psp_transaction_id`)

**Безопасность**:
- Проверка IP адреса PSP
- Signature verification
- Rate limiting (max 100 req/min)

---

## 09. Daily Jobs (09-daily-jobs.md)

**Назначение**: Ежедневные автоматические задачи.

**Джобы**:

### 1. Subscription Amortization Job
- **Когда**: Каждый день в 2:00
- **Что**: Списание ежедневной амортизации подписки
- **Формула**: `daily_cost = monthly_fee / days_in_month`
- **Действия**:
  - Получить активные подписки
  - Рассчитать daily_cost
  - Уменьшить total_balance
  - Создать транзакцию `subscription_charge`

### 2. Low Balance Notification Job
- **Когда**: Каждый день в 10:00
- **Что**: Уведомления о низком балансе
- **Пороги**: 7 дней, 3 дня, 1 день
- **Действия**:
  - Рассчитать `days_until_blocked`
  - Отправить email/push уведомление
  - Если `balance < 0` → блокировка аккаунта

### 3. Reservation Expiration Job
- **Когда**: Каждые 30 минут
- **Что**: Истечение старых резервов
- **Действия**:
  - Найти резервы с `expires_at < now()`
  - Изменить статус на `expired`
  - Освободить `reserved_balance`

---

## 10. Document Generation (10-document-generation.md)

**Назначение**: Генерация документов (АВР, счета).

**Технологии**: Apache PDFBox или iText

**Документы**:

### 1. Счёт на оплату (Invoice PDF)
- Логотип компании
- Реквизиты Coube
- Сумма к оплате
- Назначение платежа
- QR-код для оплаты (опционально)

### 2. АВР за подписку (Subscription AVR)
- Период (месяц)
- Сумма ежедневных списаний
- Итоговая сумма за месяц
- Подписи (ЭЦП)

### 3. АВР за комиссию (Commission AVR)
- Список заявок с комиссией
- Суммы по каждой заявке
- Итоговая комиссия за месяц

**Хранение**: MinIO + метаданные в `billing.document`

---

## 11. Notifications (11-notifications.md)

**Назначение**: Уведомления о балансе и платежах.

**Интеграция**: Модуль `notifications` (существующий)

**Типы уведомлений**:
1. Низкий баланс (за 7/3/1 день)
2. Успешное пополнение баланса
3. Неуспешный платёж
4. Блокировка аккаунта
5. Истечение пробного периода
6. Новый счёт на оплату
7. АВР сгенерирован

**Каналы**: Email, Push (Firebase), SMS (опционально)

---

## 12. Admin Panel (12-admin-panel.md)

**Назначение**: Админка для управления тарифами и ручного подтверждения оплаты.

**Страницы**:

### 1. Управление тарифами
- Просмотр каталога (catalog.xml)
- Создание нового тарифа
- Изменение стоимости
- Настройка пробного периода

### 2. Ручное подтверждение оплаты
- Список pending инвойсов
- Форма подтверждения:
  - Invoice ID
  - Сумма
  - Дата оплаты
  - Комментарий
- Кнопка "Подтвердить"

### 3. Мониторинг балансов
- Таблица аккаунтов
- Фильтры: низкий баланс, заблокированные
- Экспорт в CSV

### 4. Отчёты
- Платежи за период
- Комиссии по Исполнителям
- Ежемесячные подписки

---

## 13. Security (13-security.md)

**Назначение**: Безопасность биллинговой системы.

**Меры**:
1. **mTLS** для Platform ↔ Kill Bill (опционально)
2. **JWT** для API аутентификации
3. **HMAC SHA256** для webhook подписи
4. **Rate Limiting** (max 100 req/min на webhook)
5. **IP Whitelist** для PSP
6. **Secrets Management** (Kubernetes Secrets)
7. **Аудит** всех финансовых операций
8. **Логирование** (created_by, updated_by)

---

## 14. Docker Compose (14-docker-compose.md)

**Назначение**: Полная конфигурация для развёртывания.

**Сервисы**:
- `coube-backend` — Spring Boot
- `coube-db` — PostgreSQL (Platform)
- `killbill` — Kill Bill Server
- `killbill-db` — PostgreSQL (Kill Bill)
- `kaui` — Kill Bill Admin UI
- `minio` — File Storage
- `nginx` — Reverse Proxy (опционально)

**Volumes**:
- `coube-db-data`
- `killbill-db-data`
- `minio-data`

**Networks**:
- `coube-network` (bridge)

---

## 15. Testing Strategy (15-testing-strategy.md)

**Назначение**: Стратегия тестирования.

**Уровни**:

### 1. Unit Tests
- JUnit 5 + Mockito
- Coverage >= 80%
- Тесты сервисов, репозиториев, маппинг

### 2. Integration Tests
- Spring Boot Test + TestContainers
- PostgreSQL в контейнере
- Mock Kill Bill API (WireMock)

### 3. E2E Tests
- Selenium / Playwright
- Критичные сценарии (регистрация → оплата)

### 4. Load Tests
- JMeter / Gatling
- 1000 RPS на read endpoints
- 100 RPS на write endpoints

### 5. Security Tests
- OWASP ZAP
- SQL Injection
- XSS
- CSRF

---

## Приоритеты реализации

### Критично (MVP)
1. ✅ 01-database-schema.md
2. ✅ 02-killbill-setup.md
3. ⚠️ 03-integration-layer.md
4. ⚠️ 04-api-accounts.md
5. ⚠️ 05-api-subscriptions.md
6. ⚠️ 06-api-commissions.md
7. ⚠️ 07-api-invoices.md

### Важно (Phase 2)
8. 08-api-payments.md
9. 09-daily-jobs.md
10. 10-document-generation.md
11. 11-notifications.md

### Опционально (Phase 3)
12. 12-admin-panel.md
13. 13-security.md
14. 14-docker-compose.md
15. 15-testing-strategy.md

---

**Следующие шаги**:
1. Начать с `16-implementation-checklist.md`
2. Реализовать по чеклисту
3. Создавать полные версии файлов 03-15 по мере необходимости

---

**Документ подготовлен**: 2025-01-XX  
**Версия**: 1.0
