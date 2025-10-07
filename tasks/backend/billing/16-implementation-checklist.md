# 16. Чеклист реализации биллинга

## Обзор

Полный чеклист для пошаговой реализации системы биллинга на базе Kill Bill.

---

## Phase 1: MVP (Базовая функциональность)

### Неделя 1-2: Инфраструктура и БД

#### 1.1. Docker и Kill Bill
- [ ] Установить Docker и Docker Compose
- [ ] Создать `killbill-docker/docker-compose.yml`
- [ ] Создать `.env` с секретами (добавить в `.gitignore`)
- [ ] Запустить Kill Bill: `docker-compose up -d`
- [ ] Проверить healthcheck: `curl http://localhost:8080/healthcheck`
- [ ] Открыть админку Kaui: http://localhost:3000
- [ ] Создать тенант `coube` с API ключами
- [ ] Загрузить каталог тарифов (`catalog-coube.xml`)
- [ ] Протестировать создание аккаунта через Kaui
- [ ] Протестировать создание подписки через Kaui

#### 1.2. База данных Coube
- [ ] Создать схему `billing` в PostgreSQL платформы
- [ ] Написать Flyway миграцию `V1.0__billing_schema.sql`
  - [ ] Таблица `billing.account`
  - [ ] Таблица `billing.subscription`
  - [ ] Таблица `billing.reservation`
  - [ ] Таблица `billing.transaction`
  - [ ] Таблица `billing.invoice`
  - [ ] Таблица `billing.payment`
  - [ ] Таблица `billing.document`
  - [ ] Таблица `billing.balance_history`
  - [ ] Таблица `billing.webhook_log`
- [ ] Написать миграцию `V1.1__billing_triggers.sql`
  - [ ] Триггер `update_updated_at` для всех таблиц
  - [ ] Триггер `update_available_balance` для `billing.account`
  - [ ] Триггер `generate_invoice_number`
- [ ] Написать миграцию `V1.2__billing_views.sql`
  - [ ] View `v_account_status`
  - [ ] View `v_transaction_history`
- [ ] Написать миграцию `V1.3__billing_indexes.sql` (оптимизация)
- [ ] Написать миграцию `V1.4__billing_foreign_keys.sql`
  - [ ] Добавить `billing_account_id` в `users.organization`
  - [ ] Добавить `commission_reservation_id` в `applications.transportation_cost`
- [ ] Запустить миграции: `./gradlew flywayMigrate`
- [ ] Проверить схему в DBeaver/pgAdmin

#### 1.3. Проверка данных
- [ ] Вставить тестовые данные в `users.organization`
- [ ] Создать тестовый `billing.account` вручную
- [ ] Проверить constraints (balance, available_balance)
- [ ] Проверить триггеры (updated_at, available_balance)

---

### Неделя 3: Интеграция с Kill Bill

#### 3.1. Kill Bill Client
- [ ] Добавить зависимость в `build.gradle.kts`:
  ```kotlin
  implementation("org.kill-bill.billing:killbill-client-java:2.1.0")
  ```
- [ ] Создать конфигурацию `KillBillConfig.java`
- [ ] Создать `application-killbill.yml` с настройками
- [ ] Написать `KillBillProperties` для конфигурации
- [ ] Написать `KillBillService` для вызовов API

#### 3.2. Модуль Billing (Spring Boot)
- [ ] Создать пакет `kz.coube.backend.billing`
- [ ] Создать подпакеты:
  - [ ] `entity` (JPA сущности)
  - [ ] `repository` (Spring Data JPA)
  - [ ] `service` (бизнес-логика)
  - [ ] `dto` (DTO для API)
  - [ ] `mapper` (маппинг Entity ↔ DTO)
  - [ ] `controller` (REST API)
  - [ ] `exception` (кастомные исключения)
  - [ ] `event` (Spring Events для интеграции)

#### 3.3. JPA Entities
- [ ] Создать `Account.java` (mapping к `billing.account`)
- [ ] Создать `Subscription.java`
- [ ] Создать `Reservation.java`
- [ ] Создать `Transaction.java`
- [ ] Создать `Invoice.java`
- [ ] Создать `Payment.java`
- [ ] Создать `Document.java`
- [ ] Создать `BalanceHistory.java`
- [ ] Создать `WebhookLog.java`
- [ ] Добавить аннотации: `@Entity`, `@Table`, `@Id`, etc.
- [ ] Добавить `@PreUpdate` для `updated_at`

#### 3.4. Repositories
- [ ] Создать `AccountRepository extends JpaRepository<Account, Long>`
- [ ] Создать `SubscriptionRepository`
- [ ] Создать `ReservationRepository`
- [ ] Создать `TransactionRepository`
- [ ] Создать `InvoiceRepository`
- [ ] Создать `PaymentRepository`
- [ ] Создать `DocumentRepository`
- [ ] Создать `BalanceHistoryRepository`
- [ ] Создать `WebhookLogRepository`
- [ ] Добавить custom query methods (findByOrganizationId, etc.)

#### 3.5. KillBillService
- [ ] Метод `createAccount(CreateAccountRequest) → UUID`
- [ ] Метод `getAccount(UUID accountId) → KBAccount`
- [ ] Метод `createSubscription(CreateSubscriptionRequest) → UUID`
- [ ] Метод `cancelSubscription(UUID subscriptionId)`
- [ ] Метод `getInvoices(UUID accountId) → List<KBInvoice>`
- [ ] Метод `recordPayment(UUID invoiceId, amount)`
- [ ] Обработка ошибок Kill Bill API
- [ ] Retry механизм (Spring Retry)
- [ ] Логирование всех вызовов

---

### Неделя 4: API и UI интеграция

#### 4.1. Account Service
- [ ] Метод `createBillingAccount(organizationId, isNew) → Account`
  - [ ] Проверка new/old клиента (логика определения)
  - [ ] Вызов Kill Bill `createAccount`
  - [ ] Сохранение в `billing.account`
  - [ ] Обновление `users.organization.billing_account_id`
  - [ ] Назначение пробного периода (если new)
- [ ] Метод `getBalance(accountId) → BalanceDto`
  - [ ] total_balance, available_balance, reserved_balance
  - [ ] Количество дней до блокировки
- [ ] Метод `getTransactionHistory(accountId, pageable) → Page<TransactionDto>`

#### 4.2. Subscription Service
- [ ] Метод `createSubscription(accountId, planName)`
  - [ ] Вызов Kill Bill
  - [ ] Сохранение в `billing.subscription`
  - [ ] Создание транзакции
- [ ] Метод `cancelSubscription(subscriptionId)`
- [ ] Метод `getActiveSubscription(accountId) → Subscription`

#### 4.3. Reservation Service (Агентская модель)
- [ ] Метод `reserveCommission(accountId, transportationId, amount)`
  - [ ] Проверка `available_balance >= amount`
  - [ ] Создание резерва в статусе `hold`
  - [ ] Обновление `reserved_balance`
  - [ ] Создание транзакции `commission_reserve`
  - [ ] Сохранение в `billing.balance_history`
- [ ] Метод `captureReservation(reservationId)`
  - [ ] Изменение статуса `hold → captured`
  - [ ] Уменьшение `total_balance`
  - [ ] Уменьшение `reserved_balance`
  - [ ] Создание транзакции `commission_capture`
- [ ] Метод `releaseReservation(reservationId, reason)`
  - [ ] Изменение статуса `hold → released`
  - [ ] Уменьшение `reserved_balance`
  - [ ] Создание транзакции `commission_release`
- [ ] Метод `expireOldReservations()` (для scheduled job)

#### 4.4. Invoice Service
- [ ] Метод `createTopupInvoice(accountId, amount) → Invoice`
  - [ ] Генерация номера счёта
  - [ ] Создание в `billing.invoice`
  - [ ] Генерация PDF (Phase 2)
  - [ ] Возврат ссылки на скачивание
- [ ] Метод `syncInvoicesFromKillBill(accountId)`
  - [ ] Получение инвойсов из Kill Bill
  - [ ] Сохранение/обновление в `billing.invoice`
- [ ] Метод `getInvoices(accountId) → List<InvoiceDto>`

#### 4.5. Payment Service (MVP: ручное подтверждение)
- [ ] Метод `recordManualPayment(invoiceId, amount, adminUserId)`
  - [ ] Создание записи в `billing.payment` (status=success)
  - [ ] Увеличение `total_balance`
  - [ ] Обновление статуса invoice → `paid`
  - [ ] Вызов Kill Bill `recordPayment`
  - [ ] Создание транзакции `balance_topup`
  - [ ] Отправка уведомления пользователю

#### 4.6. REST API Controllers
- [ ] `BillingAccountController`
  - [ ] `GET /api/v1/billing/balance` → текущий баланс
  - [ ] `GET /api/v1/billing/transactions` → история операций
- [ ] `BillingInvoiceController`
  - [ ] `POST /api/v1/billing/invoices/topup` → создать счёт на пополнение
  - [ ] `GET /api/v1/billing/invoices` → список счетов
  - [ ] `GET /api/v1/billing/invoices/{id}/pdf` → скачать PDF
- [ ] `BillingReservationController` (внутренний API)
  - [ ] `POST /api/v1/billing/reservations` → резервировать комиссию
  - [ ] `POST /api/v1/billing/reservations/{id}/capture`
  - [ ] `POST /api/v1/billing/reservations/{id}/release`
- [ ] `BillingAdminController` (для админов)
  - [ ] `POST /api/v1/admin/billing/payments/manual` → ручное подтверждение оплаты

#### 4.7. Интеграция с модулем Applications
- [ ] При подписании заявки Исполнителем:
  - [ ] Event `TransportationSignedByExecutorEvent`
  - [ ] EventListener: вызов `reserveCommission()`
- [ ] При подтверждении заявки Заказчиком:
  - [ ] Event `TransportationConfirmedEvent`
  - [ ] EventListener: вызов `captureReservation()`
- [ ] При отмене заявки:
  - [ ] Event `TransportationCancelledEvent`
  - [ ] EventListener: вызов `releaseReservation()`

#### 4.8. Frontend интеграция (ЛК)
- [ ] Добавить компонент "Баланс" в хедер ЛК
- [ ] Страница "Биллинг" с:
  - [ ] Текущий баланс (total, available, reserved)
  - [ ] Кнопка "Пополнить баланс"
  - [ ] История операций (таблица)
  - [ ] Список счетов с кнопкой "Скачать PDF"
- [ ] Модальное окно "Пополнение баланса":
  - [ ] Ввод суммы
  - [ ] Генерация счёта
  - [ ] Отображение реквизитов для оплаты

---

## Phase 2: Автоматизация

### Неделя 5: Webhook от PSP

#### 5.1. Webhook Controller
- [ ] Создать `WebhookController`
  - [ ] `POST /api/v1/billing/webhook/bcc`
  - [ ] `POST /api/v1/billing/webhook/jusan`
- [ ] Проверка подписи webhook (HMAC SHA256)
- [ ] Логирование в `billing.webhook_log`
- [ ] Обработка callback:
  - [ ] Парсинг payload
  - [ ] Поиск invoice по invoiceId
  - [ ] Создание `Payment` (status=success)
  - [ ] Увеличение баланса
  - [ ] Вызов Kill Bill `recordPayment`
- [ ] Идемпотентность (проверка `psp_transaction_id`)
- [ ] Обработка ошибок

#### 5.2. PSP Integrations
- [ ] Интеграция с BCC:
  - [ ] Конфигурация (merchant_id, secret_key)
  - [ ] Метод генерации payment URL
  - [ ] Метод проверки подписи webhook
  - [ ] Документация
- [ ] (Опционально) Интеграция с Jusan

---

### Неделя 6: Ежедневные джобы

#### 6.1. Daily Subscription Amortization Job
- [ ] Создать `SubscriptionAmortizationJob`
- [ ] Расписание: `@Scheduled(cron = "0 0 2 * * *")` (каждый день в 2:00)
- [ ] Логика:
  - [ ] Получить все активные подписки
  - [ ] Для каждой рассчитать `daily_cost = monthly_fee / days_in_month`
  - [ ] Уменьшить `total_balance` на `daily_cost`
  - [ ] Создать транзакцию `subscription_charge`
  - [ ] Сохранить в `billing.balance_history`
- [ ] Обработка ошибок
- [ ] Логирование

#### 6.2. Low Balance Notification Job
- [ ] Создать `LowBalanceNotificationJob`
- [ ] Расписание: `@Scheduled(cron = "0 0 10 * * *")` (каждый день в 10:00)
- [ ] Логика:
  - [ ] Получить аккаунты с `days_until_blocked <= 7`
  - [ ] Отправить уведомление (email + push)
  - [ ] Пороги: 7 дней, 3 дня, 1 день
  - [ ] Если `balance < 0` → блокировка аккаунта
- [ ] Интеграция с модулем `notifications`

#### 6.3. Reservation Expiration Job
- [ ] Создать `ReservationExpirationJob`
- [ ] Расписание: `@Scheduled(cron = "0 */30 * * * *")` (каждые 30 минут)
- [ ] Логика:
  - [ ] Получить резервы со статусом `hold` и `expires_at < now()`
  - [ ] Изменить статус на `expired`
  - [ ] Освободить `reserved_balance`
  - [ ] Логирование

---

### Неделя 7: Генерация документов

#### 7.1. Document Generation Service
- [ ] Добавить зависимость Apache PDFBox:
  ```kotlin
  implementation("org.apache.pdfbox:pdfbox:2.0.29")
  ```
- [ ] Создать `DocumentGenerationService`
- [ ] Метод `generateInvoicePdf(invoiceId) → UUID fileId`
  - [ ] Получить данные invoice
  - [ ] Сгенерировать PDF с реквизитами
  - [ ] Сохранить в MinIO
  - [ ] Создать запись в `file.file_meta_info`
  - [ ] Обновить `invoice.file_id`
- [ ] Метод `generateAvrPdf(accountId, periodStart, periodEnd)`
  - [ ] Получить транзакции за период
  - [ ] Сгенерировать АВР (подписка или комиссия)
  - [ ] Сохранить в MinIO
  - [ ] Создать запись в `billing.document`
- [ ] Шаблоны PDF (дизайн с лого, реквизиты, таблицы)

#### 7.2. Monthly AVR Generation Job
- [ ] Создать `MonthlyAvrGenerationJob`
- [ ] Расписание: `@Scheduled(cron = "0 0 3 1 * *")` (1-го числа в 3:00)
- [ ] Логика:
  - [ ] Получить все аккаунты с активной подпиской
  - [ ] Для каждого сгенерировать АВР за прошлый месяц
  - [ ] Отправить уведомление с ссылкой на документ
- [ ] Для Исполнителей: АВР по комиссии

---

## Phase 3: Продакшн

### Неделя 8: Доработки

#### 8.1. Admin Panel (Kaui + Custom)
- [ ] Настроить доступ к Kaui только для админов
- [ ] Создать страницу "Управление тарифами"
  - [ ] Просмотр/редактирование каталога
  - [ ] Изменение стоимости подписки
  - [ ] Настройка пробного периода
- [ ] Страница "Ручное подтверждение оплаты"
  - [ ] Список pending инвойсов
  - [ ] Кнопка "Подтвердить оплату"
  - [ ] Поле для суммы и комментария
- [ ] Страница "Мониторинг балансов"
  - [ ] Список аккаунтов с низким балансом
  - [ ] Фильтры по статусу

#### 8.2. Reports для бухгалтерии
- [ ] Отчёт "Платежи за период" (CSV/Excel)
- [ ] Отчёт "Комиссии по Исполнителям"
- [ ] Отчёт "Ежемесячные подписки"
- [ ] Реестр всех АВР
- [ ] Экспорт в 1С (опционально)

#### 8.3. Security
- [ ] Настроить mTLS для Platform ↔ Kill Bill (опционально)
- [ ] JWT токены для API
- [ ] Rate limiting для webhook endpoints
- [ ] Подпись webhook от PSP (HMAC SHA256)
- [ ] Аудит всех финансовых операций
- [ ] Secrets в Kubernetes Secrets / AWS Secrets Manager

---

### Неделя 9: Тестирование и деплой

#### 9.1. Unit Tests
- [ ] `AccountServiceTest` (coverage >= 80%)
- [ ] `ReservationServiceTest`
- [ ] `InvoiceServiceTest`
- [ ] `PaymentServiceTest`
- [ ] `DocumentGenerationServiceTest`
- [ ] Тесты репозиториев (Spring Data JPA)

#### 9.2. Integration Tests
- [ ] `BillingAccountIntegrationTest` (TestContainers + PostgreSQL)
- [ ] `KillBillIntegrationTest` (Mock Kill Bill API)
- [ ] `WebhookIntegrationTest` (Mock PSP callback)
- [ ] `DailyJobsIntegrationTest`

#### 9.3. End-to-End Tests
- [ ] Сценарий: Регистрация нового клиента → пробный период → оплата подписки
- [ ] Сценарий: Резервирование комиссии → capture → генерация АВР
- [ ] Сценарий: Пополнение баланса через webhook
- [ ] Сценарий: Блокировка при отрицательном балансе

#### 9.4. Load Testing
- [ ] JMeter / Gatling тесты:
  - [ ] 1000 RPS на `GET /api/v1/billing/balance`
  - [ ] 100 RPS на `POST /api/v1/billing/reservations`
  - [ ] 50 RPS на webhook endpoints
- [ ] Проверка времени отклика (p95 < 200ms)

#### 9.5. Резервное копирование
- [ ] Настроить ежедневный бэкап PostgreSQL (Kill Bill)
- [ ] Настроить ежедневный бэкап PostgreSQL (Platform)
- [ ] Тест восстановления из бэкапа

#### 9.6. Мониторинг
- [ ] Настроить Spring Actuator
- [ ] Healthcheck для Kill Bill
- [ ] Prometheus metrics:
  - [ ] `billing_balance_total`
  - [ ] `billing_reservations_active`
  - [ ] `billing_payments_success_rate`
- [ ] Grafana dashboard
- [ ] Alerting в Slack/Telegram при критических ошибках

#### 9.7. Документация
- [ ] README для `killbill-docker/`
- [ ] Swagger UI для Billing API
- [ ] Руководство для админа (Confluence/Notion)
- [ ] Архитектурная диаграмма (draw.io)

#### 9.8. Production Deployment
- [ ] Перевести Kill Bill на отдельный сервер
- [ ] Настроить HTTPS для Kill Bill
- [ ] Настроить firewall (только Platform → Kill Bill)
- [ ] Деплой через CI/CD (GitLab CI / GitHub Actions)
- [ ] Smoke tests на проде

---

## Критерии приёмки (Definition of Done)

### Функциональные требования
- [x] Новые/старые клиенты определяются корректно
- [x] Пробный период работает (1 месяц бесплатно)
- [x] Ежедневная амортизация подписки списывается автоматически
- [x] Резервы (hold/capture/release) работают без багов
- [x] Баланс отображается корректно (total, available, reserved)
- [x] Уведомления отправляются за 7/3/1 день до блокировки
- [x] Документы (счета, АВР) генерируются автоматически
- [x] Webhook от PSP обрабатываются корректно
- [x] Ручное подтверждение оплаты работает (MVP)

### Нефункциональные требования
- [x] Uptime Kill Bill >= 99.9%
- [x] Latency API < 200ms (p95)
- [x] Успешность webhook >= 99%
- [x] Unit tests coverage >= 80%
- [x] Integration tests для критичных сценариев
- [x] Документация API (Swagger)
- [x] Резервное копирование БД настроено

### Безопасность
- [x] Secrets не в коде (env variables)
- [x] Подпись webhook проверяется
- [x] Аудит всех финансовых операций
- [x] HTTPS для продакшн Kill Bill

---

## Следующие шаги после завершения

1. ✅ Мониторить метрики первые 2 недели
2. ✅ Собирать feedback от бухгалтерии
3. → Добавить интеграцию с остальными PSP (Kaspi, Jusan)
4. → Автоматическая генерация реестров для налоговой
5. → Интеграция с 1С

---

**Документ подготовлен**: 2025-01-XX  
**Версия**: 1.0  
**Проверено**: Backend Team + QA
