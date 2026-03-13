# 06. Чеклист реализации (Упрощённая версия)

## 🎯 Цель: MVP за 4 недели (1 разработчик)

---

## Неделя 1: База данных + JPA Layer

### День 1-2: База данных (2 дня)

**Flyway миграции**:
- [ ] Создать `V1.0__billing_schema_simple.sql`
  - [ ] CREATE SCHEMA billing
  - [ ] CREATE TABLE billing.account (с constraints)
  - [ ] CREATE TABLE billing.transaction
  - [ ] CREATE TABLE billing.reservation
  - [ ] CREATE TABLE billing.invoice
  - [ ] CREATE TABLE billing.payment
  - [ ] Индексы для всех таблиц
  - [ ] Комментарии COMMENT ON
- [ ] Создать `V1.1__billing_triggers_simple.sql`
  - [ ] Функция update_updated_at()
  - [ ] Триггеры для account, reservation
  - [ ] Функция generate_invoice_number()
  - [ ] Триггер для invoice
- [ ] Создать `V1.2__billing_views_simple.sql`
  - [ ] VIEW v_account_status
  - [ ] VIEW v_transaction_history
- [ ] Создать `V1.3__billing_foreign_keys_simple.sql`
  - [ ] ALTER TABLE users.organization ADD billing_account_id
  - [ ] ALTER TABLE applications.transportation ADD commission_reservation_id
- [ ] Запустить миграции: `./gradlew flywayMigrate`
- [ ] Проверить схему в DBeaver/pgAdmin
- [ ] Вставить тестовые данные вручную
- [ ] Проверить constraints (попробовать вставить невалидные данные)

**Время**: 2 дня

---

### День 3-4: JPA Entities (2 дня)

- [ ] Создать пакет `kz.coube.backend.billing.entity`
- [ ] Создать `Account.java`
  - [ ] @Entity, @Table(name = "account", schema = "billing")
  - [ ] @Id, @GeneratedValue
  - [ ] Поля: organizationId, balance, reservedBalance, subscriptionActive, etc.
  - [ ] @Column annotations
  - [ ] getters/setters (или Lombok @Data)
- [ ] Создать `Transaction.java`
  - [ ] Enum TransactionType (TOPUP, SUBSCRIPTION_CHARGE, COMMISSION_RESERVE, etc.)
  - [ ] @Enumerated(EnumType.STRING)
- [ ] Создать `Reservation.java`
  - [ ] Enum ReservationStatus (HOLD, CAPTURED, RELEASED)
- [ ] Создать `Invoice.java`
  - [ ] Enum InvoiceStatus (PENDING, PAID, CANCELLED)
- [ ] Создать `Payment.java`
  - [ ] Enum PaymentMethod (MANUAL, ONLINE)
- [ ] Добавить в существующие entities:
  - [ ] `Organization.java` → добавить `billingAccountId`
  - [ ] `Transportation.java` → добавить `commissionReservationId`
- [ ] Unit тесты (простые):
  - [ ] Проверить создание объектов
  - [ ] Проверить getters/setters

**Время**: 2 дня

---

### День 5: Repositories (1 день)

- [ ] Создать пакет `kz.coube.backend.billing.repository`
- [ ] Создать `AccountRepository extends JpaRepository<Account, Long>`
  - [ ] `Optional<Account> findByOrganizationId(Long organizationId)`
  - [ ] `List<Account> findByStatus(String status)`
  - [ ] `List<Account> findBySubscriptionActiveAndSubscriptionNextBillingDateBefore(boolean active, LocalDate date)`
- [ ] Создать `TransactionRepository`
  - [ ] `Page<Transaction> findByAccountIdOrderByCreatedAtDesc(Long accountId, Pageable pageable)`
  - [ ] `List<Transaction> findByAccountIdAndCreatedAtBetween(Long accountId, LocalDateTime from, LocalDateTime to)`
- [ ] Создать `ReservationRepository`
  - [ ] `Optional<Reservation> findByTransportationId(Long transportationId)`
  - [ ] `List<Reservation> findByAccountIdAndStatus(Long accountId, String status)`
- [ ] Создать `InvoiceRepository`
  - [ ] `List<Invoice> findByAccountIdOrderByCreatedAtDesc(Long accountId)`
  - [ ] `Optional<Invoice> findByInvoiceNumber(String invoiceNumber)`
- [ ] Создать `PaymentRepository`
  - [ ] `List<Payment> findByInvoiceId(Long invoiceId)`
- [ ] Тесты (@DataJpaTest):
  - [ ] Вставить тестовые данные
  - [ ] Проверить findBy... методы

**Время**: 1 день

---

## Неделя 2: Services (Бизнес-логика)

### День 1: AccountService (1 день)

- [ ] Создать пакет `kz.coube.backend.billing.service`
- [ ] Создать `AccountService.java`
- [ ] Метод `createAccount(Long organizationId, boolean isNew) → Account`
  - [ ] Проверить: аккаунт уже существует?
  - [ ] Создать Account
  - [ ] Если isNew → trial_ends_at = now() + 1 month, status = 'trial'
  - [ ] Иначе → status = 'active', subscription_active = true
  - [ ] Сохранить в БД
  - [ ] Обновить organization.billing_account_id
  - [ ] return account
- [ ] Метод `getAccount(Long organizationId) → Account`
  - [ ] findByOrganizationId() или throw
- [ ] Метод `blockAccount(Long accountId, String reason)`
  - [ ] Обновить status = 'blocked', blocked_reason
- [ ] Метод `activateAccount(Long accountId)`
  - [ ] Обновить status = 'active'
- [ ] Unit тесты (Mockito):
  - [ ] createAccount для нового клиента
  - [ ] createAccount для старого клиента
  - [ ] blockAccount / activateAccount

**Время**: 1 день

---

### День 2: BalanceService (1 день)

- [ ] Создать `BalanceService.java`
- [ ] Метод `getBalance(Long accountId) → BalanceDto`
  - [ ] balance, reserved_balance, available_balance
  - [ ] days_until_blocked (примерная оценка)
- [ ] Метод `topup(Long accountId, BigDecimal amount, String invoiceNumber) → Transaction`
  - [ ] Получить account
  - [ ] balance_before = account.balance
  - [ ] account.balance += amount
  - [ ] Сохранить account
  - [ ] Создать Transaction (type=TOPUP)
  - [ ] return transaction
- [ ] Метод `chargeSubscription(Long accountId, BigDecimal amount) → Transaction`
  - [ ] Получить account
  - [ ] balance_before = account.balance
  - [ ] account.balance -= amount
  - [ ] Если balance < 0 → blockAccount()
  - [ ] Сохранить account
  - [ ] Создать Transaction (type=SUBSCRIPTION_CHARGE)
  - [ ] return transaction
- [ ] Unit тесты:
  - [ ] topup увеличивает баланс
  - [ ] chargeSubscription списывает
  - [ ] chargeSubscription блокирует при отрицательном балансе

**Время**: 1 день

---

### День 3-4: ReservationService (2 дня)

- [ ] Создать `ReservationService.java`
- [ ] Метод `reserve(Long accountId, Long transportationId, BigDecimal amount) → Reservation`
  - [ ] Получить account
  - [ ] Проверить: `(balance - reserved_balance) >= amount`
  - [ ] Если нет → throw InsufficientBalanceException
  - [ ] Создать Reservation (status=HOLD)
  - [ ] account.reserved_balance += amount
  - [ ] Сохранить account и reservation
  - [ ] Создать Transaction (type=COMMISSION_RESERVE, amount=0)
  - [ ] Обновить transportation.commission_reservation_id
  - [ ] return reservation
- [ ] Метод `capture(Long reservationId) → Transaction`
  - [ ] Получить reservation (status должен быть HOLD)
  - [ ] Получить account
  - [ ] balance_before = account.balance
  - [ ] account.balance -= reservation.amount
  - [ ] account.reserved_balance -= reservation.amount
  - [ ] reservation.status = CAPTURED, captured_at = now()
  - [ ] Сохранить account и reservation
  - [ ] Создать Transaction (type=COMMISSION_CAPTURE, amount=-reservation.amount)
  - [ ] return transaction
- [ ] Метод `release(Long reservationId) → Transaction`
  - [ ] Получить reservation (status должен быть HOLD)
  - [ ] Получить account
  - [ ] account.reserved_balance -= reservation.amount
  - [ ] reservation.status = RELEASED, released_at = now()
  - [ ] Сохранить account и reservation
  - [ ] Создать Transaction (type=COMMISSION_RELEASE, amount=0)
  - [ ] return transaction
- [ ] Unit тесты:
  - [ ] reserve успешно
  - [ ] reserve throw InsufficientBalanceException
  - [ ] capture успешно
  - [ ] release успешно
  - [ ] capture/release на уже captured/released → throw

**Время**: 2 дня

---

### День 5: InvoiceService + PaymentService (1 день)

**InvoiceService**:
- [ ] Создать `InvoiceService.java`
- [ ] Метод `createInvoice(Long accountId, BigDecimal amount) → Invoice`
  - [ ] Создать Invoice (status=PENDING)
  - [ ] invoice_number генерируется триггером (или вручную)
  - [ ] Сохранить
  - [ ] return invoice

**PaymentService**:
- [ ] Создать `PaymentService.java`
- [ ] Метод `recordManualPayment(Long invoiceId, BigDecimal amount, String adminUsername) → Payment`
  - [ ] Получить invoice (status должен быть PENDING)
  - [ ] Создать Payment (payment_method=MANUAL, status=SUCCESS)
  - [ ] Вызвать balanceService.topup(account_id, amount, invoice_number)
  - [ ] invoice.status = PAID, paid_at = now()
  - [ ] Сохранить invoice и payment
  - [ ] Отправить уведомление пользователю (опционально)
  - [ ] return payment
- [ ] Unit тесты:
  - [ ] createInvoice
  - [ ] recordManualPayment увеличивает баланс
  - [ ] recordManualPayment меняет статус invoice

**Время**: 1 день

---

## Неделя 3: Интеграция + Jobs

### День 1-2: Event Listeners (2 дня)

- [ ] Создать пакет `kz.coube.backend.billing.event`
- [ ] Создать `TransportationEventListener.java`
- [ ] **Event 1**: `@EventListener(TransportationSignedByExecutorEvent.class)`
  - [ ] onTransportationSignedByExecutor(event)
  - [ ] Получить transportation
  - [ ] Получить executor organization
  - [ ] Получить billing account
  - [ ] Рассчитать комиссию: `cost * 0.05`
  - [ ] Вызвать `reservationService.reserve(accountId, transportationId, commission)`
  - [ ] Обработка ошибок (InsufficientBalanceException)
  - [ ] Логирование
- [ ] **Event 2**: `@EventListener(TransportationConfirmedEvent.class)`
  - [ ] onTransportationConfirmed(event)
  - [ ] Получить transportation
  - [ ] Получить reservation по transportation.commission_reservation_id
  - [ ] Вызвать `reservationService.capture(reservationId)`
  - [ ] Логирование
- [ ] **Event 3**: `@EventListener(TransportationCancelledEvent.class)`
  - [ ] onTransportationCancelled(event)
  - [ ] Получить reservation
  - [ ] Вызвать `reservationService.release(reservationId)`
  - [ ] Логирование
- [ ] Integration тесты:
  - [ ] Эмулировать событие → проверить резерв создан
  - [ ] Эмулировать подтверждение → проверить capture

**Время**: 2 дня

---

### День 3: MonthlySubscriptionJob (1 день)

- [ ] Создать пакет `kz.coube.backend.billing.scheduler`
- [ ] Создать `MonthlySubscriptionJob.java`
- [ ] `@Scheduled(cron = "0 0 2 1 * *")` — 1-го числа в 2:00
- [ ] Метод `chargeMonthlySubscriptions()`
  - [ ] Получить все аккаунты где `subscription_active = true`
  - [ ] Для каждого:
    - [ ] Вызвать `balanceService.chargeSubscription(accountId, subscription_amount)`
    - [ ] Обновить `subscription_next_billing_date += 1 month`
    - [ ] Если balance < 0 → отправить уведомление
  - [ ] Логирование: сколько обработано, сколько заблокировано
- [ ] Unit тест:
  - [ ] Проверить списание для нескольких аккаунтов
  - [ ] Проверить блокировку при недостатке средств

**Время**: 1 день

---

### День 4: LowBalanceNotificationJob (1 день)

- [ ] Создать `LowBalanceNotificationJob.java`
- [ ] `@Scheduled(cron = "0 0 10 * * *")` — каждый день в 10:00
- [ ] Метод `checkLowBalances()`
  - [ ] Получить все активные аккаунты
  - [ ] Для каждого:
    - [ ] Рассчитать `days_until_blocked = available_balance / (subscription_amount / 30)`
    - [ ] Если <= 7 дней → отправить уведомление
    - [ ] Пороги: 7, 3, 1 день
  - [ ] Интеграция с модулем notifications:
    - [ ] Вызвать `notificationService.sendLowBalanceNotification(userId, days)`
  - [ ] Логирование
- [ ] Unit тест:
  - [ ] Проверить отправку уведомления для аккаунта с низким балансом

**Время**: 1 день

---

### День 5: Unit тесты (1 день)

- [ ] Дописать недостающие тесты:
  - [ ] AccountService coverage >= 80%
  - [ ] BalanceService coverage >= 80%
  - [ ] ReservationService coverage >= 80%
  - [ ] InvoiceService coverage >= 80%
  - [ ] PaymentService coverage >= 80%
- [ ] Исправить failing тесты
- [ ] Code review (самостоятельно или сеньор)

**Время**: 1 день

---

## Неделя 4: API + Frontend + Деплой

### День 1-2: REST API (2 дня)

**BillingController** (для клиентов):
- [ ] Создать пакет `kz.coube.backend.billing.controller`
- [ ] Создать `BillingController.java`
- [ ] `GET /api/v1/billing/balance`
  - [ ] @GetMapping
  - [ ] Получить organizationId из SecurityContext
  - [ ] Вызвать balanceService.getBalance()
  - [ ] return BalanceDto
- [ ] `GET /api/v1/billing/transactions?page=0&size=20`
  - [ ] @GetMapping
  - [ ] Вызвать transactionRepository.findByAccountId(pageable)
  - [ ] Map to TransactionDto
  - [ ] return Page<TransactionDto>
- [ ] `POST /api/v1/billing/invoices/topup`
  - [ ] @PostBody TopupRequest { amount }
  - [ ] Вызвать invoiceService.createInvoice()
  - [ ] return InvoiceDto
- [ ] `GET /api/v1/billing/invoices`
  - [ ] Вызвать invoiceRepository.findByAccountId()
  - [ ] return List<InvoiceDto>

**BillingAdminController** (для админов):
- [ ] Создать `BillingAdminController.java`
- [ ] `POST /api/v1/admin/billing/payments/manual`
  - [ ] @PostBody ManualPaymentRequest { invoiceId, amount }
  - [ ] @PreAuthorize("hasRole('ADMIN')")
  - [ ] Вызвать paymentService.recordManualPayment()
  - [ ] return PaymentDto

**DTO**:
- [ ] Создать пакет `kz.coube.backend.billing.dto`
- [ ] BalanceDto, TransactionDto, InvoiceDto, PaymentDto
- [ ] Mapper (MapStruct или вручную)

**Swagger**:
- [ ] Аннотации @Operation, @ApiResponse

**Время**: 2 дня

---

### День 3: Frontend (1 день)

**Страница "Баланс"** в ЛК:
- [ ] Создать компонент `BillingPage.vue`
- [ ] **Блок "Баланс"**:
  - [ ] Показать: total balance, reserved, available
  - [ ] Кнопка "Пополнить баланс"
- [ ] **Модальное окно "Пополнить баланс"**:
  - [ ] Ввод суммы
  - [ ] Кнопка "Создать счёт"
  - [ ] API: POST /api/v1/billing/invoices/topup
  - [ ] Показать: "Счёт создан, номер INV-XXX. Свяжитесь с админом для подтверждения оплаты"
- [ ] **Список счетов**:
  - [ ] API: GET /api/v1/billing/invoices
  - [ ] Таблица: номер, сумма, статус, дата
- [ ] **История операций**:
  - [ ] API: GET /api/v1/billing/transactions
  - [ ] Таблица: дата, тип, сумма, описание

**Компонент в хедере**:
- [ ] Показать текущий баланс (запрос при логине)
- [ ] Красный цвет если balance < subscription_amount

**Время**: 1 день

---

### День 4: Integration тесты + Деплой (1 день)

**Integration тесты**:
- [ ] E2E сценарий: Пополнение баланса
  - [ ] POST /invoices/topup → invoice создан
  - [ ] POST /admin/payments/manual → баланс увеличен
  - [ ] GET /balance → проверить новый баланс
- [ ] E2E сценарий: Резерв → Capture
  - [ ] Эмулировать событие подписания заявки
  - [ ] Проверить: резерв создан, reserved_balance увеличен
  - [ ] Эмулировать подтверждение
  - [ ] Проверить: capture, balance уменьшен
- [ ] E2E сценарий: Ежемесячное списание
  - [ ] Запустить job вручную
  - [ ] Проверить: баланс уменьшен, transaction создан

**Деплой на dev**:
- [ ] Запустить миграции на dev БД
- [ ] Задеплоить backend
- [ ] Задеплоить frontend
- [ ] Smoke tests:
  - [ ] Зайти в ЛК
  - [ ] Проверить баланс
  - [ ] Создать счёт
  - [ ] Подтвердить оплату через админку
  - [ ] Проверить увеличение баланса

**Время**: 1 день

---

### День 5: Документация + Буфер (1 день)

**Документация**:
- [ ] README для модуля billing
  - [ ] Архитектура
  - [ ] Как работает резервирование
  - [ ] Как работает подписка
- [ ] Postman коллекция:
  - [ ] GET /balance
  - [ ] GET /transactions
  - [ ] POST /invoices/topup
  - [ ] POST /admin/payments/manual
- [ ] Инструкция для админа:
  - [ ] Как подтвердить оплату
  - [ ] Где посмотреть балансы клиентов

**Буфер**:
- [ ] Исправление багов, найденных при тестировании
- [ ] Рефакторинг
- [ ] Оптимизация запросов (если есть N+1)

**Время**: 1 день

---

## ✅ Критерии приёмки (Definition of Done)

### Функциональность
- [ ] Создание биллинг-аккаунта при регистрации работает
- [ ] Пробный период для новых клиентов работает
- [ ] Ежемесячное списание подписки работает (job)
- [ ] Резервирование комиссии при подписании заявки работает
- [ ] Capture комиссии при подтверждении работает
- [ ] Release при отмене работает
- [ ] Пополнение баланса (ручное подтверждение) работает
- [ ] Блокировка при отрицательном балансе работает
- [ ] Уведомления о низком балансе работают (job)
- [ ] История операций отображается в ЛК
- [ ] Баланс отображается корректно (total, reserved, available)

### Качество кода
- [ ] Unit тесты coverage >= 70%
- [ ] Integration тесты для критичных сценариев
- [ ] Нет N+1 query проблем
- [ ] Код прошёл code review
- [ ] Нет magic numbers (константы вынесены)
- [ ] Error handling везде

### Документация
- [ ] README для модуля
- [ ] Postman коллекция
- [ ] Swagger документация
- [ ] Комментарии в коде (где нужно)

---

## 🎉 Результат

**После 4 недель**:
- ✅ Рабочий биллинг MVP
- ✅ 5 таблиц в БД
- ✅ ~15-20 классов кода
- ✅ REST API
- ✅ Frontend интеграция
- ✅ Автоматические джобы
- ✅ Тесты

**Готово к использованию в production!**

---

**Следующий шаг**: Начать с недели 1, день 1 — создать Flyway миграции.

