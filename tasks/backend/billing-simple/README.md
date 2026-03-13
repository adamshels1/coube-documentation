# Упрощённый биллинг (без Kill Bill)

## 🎯 Главная идея

**Простая система биллинга БЕЗ Kill Bill** — всё делаем внутри Coube Platform.

**Преимущества**:
- ✅ Быстрая реализация: **3-4 недели** вместо 5-6 месяцев
- ✅ Нет сложной интеграции с внешней системой
- ✅ Полный контроль над логикой
- ✅ Легко поддерживать и расширять
- ✅ Подходит для MVP

**Что теряем**:
- ❌ Сложные тарифные планы (trial periods, upgrades)
- ❌ Автоматическое управление подписками
- ❌ Готовые плагины для PSP

**Но для MVP этого достаточно!**

---

## 📊 Архитектура

```
┌────────────────────────────────────────────────────┐
│           Coube Platform (Spring Boot)             │
│                                                     │
│  ┌──────────────┐  ┌──────────────────────────┐   │
│  │ Applications │  │   Billing Module (NEW)   │   │
│  │   Module     │  │                          │   │
│  └──────────────┘  │  - Balance Service       │   │
│         │          │  - Subscription Service  │   │
│         │          │  - Reservation Service   │   │
│         │          │  - Invoice Service       │   │
│         ▼          │  - Payment Service       │   │
│    Reserve         │  - Scheduler (Jobs)      │   │
│    Commission      │                          │   │
│                    └──────────────────────────┘   │
└────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │    PostgreSQL        │
              │  schema: billing     │
              │  - 5 таблиц          │
              └──────────────────────┘
```

---

## 🗂️ База данных (5 таблиц вместо 9)

### 1. `billing.account` — Баланс клиента
```sql
CREATE TABLE billing.account (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT NOT NULL REFERENCES users.organization(id),
    
    -- Баланс
    balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    reserved_balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Подписка (упрощённо)
    subscription_active BOOLEAN NOT NULL DEFAULT false,
    subscription_amount NUMERIC(19, 2) DEFAULT 10000.00, -- фиксированная сумма
    subscription_start_date DATE,
    trial_ends_at TIMESTAMP,
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'active', -- active, trial, blocked
    
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);
```

### 2. `billing.transaction` — Все операции
```sql
CREATE TABLE billing.transaction (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Тип операции
    type TEXT NOT NULL, -- topup, subscription_charge, commission_reserve, 
                        -- commission_capture, commission_release
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    balance_before NUMERIC(19, 2) NOT NULL,
    balance_after NUMERIC(19, 2) NOT NULL,
    
    -- Связи
    transportation_id BIGINT REFERENCES applications.transportation(id),
    invoice_id BIGINT,
    
    -- Описание
    description TEXT,
    
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL
);
```

### 3. `billing.reservation` — Резервы комиссии
```sql
CREATE TABLE billing.reservation (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    transportation_id BIGINT NOT NULL REFERENCES applications.transportation(id),
    
    amount NUMERIC(19, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'hold', -- hold, captured, released
    
    reserved_at TIMESTAMP NOT NULL DEFAULT now(),
    captured_at TIMESTAMP,
    released_at TIMESTAMP,
    
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now()
);
```

### 4. `billing.invoice` — Счета
```sql
CREATE TABLE billing.invoice (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    invoice_number TEXT NOT NULL UNIQUE,
    amount NUMERIC(19, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, paid, cancelled
    
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    paid_at TIMESTAMP
);
```

### 5. `billing.payment` — Платежи
```sql
CREATE TABLE billing.payment (
    id BIGSERIAL PRIMARY KEY,
    invoice_id BIGINT NOT NULL REFERENCES billing.invoice(id),
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    amount NUMERIC(19, 2) NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'manual', -- manual, online
    status TEXT NOT NULL DEFAULT 'success',
    
    psp_transaction_id TEXT,
    
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL
);
```

**Итого: 5 таблиц вместо 9!**

---

## 🚀 Функциональность

### Для Заказчиков (Подписка)

**1. Регистрация**
- Создаётся `billing.account`
- Если новый клиент → `trial_ends_at = now() + 1 month`
- Если старый → обычная подписка

**2. Пробный период**
- `trial_ends_at` != null → бесплатно
- После истечения → ежемесячное списание

**3. Ежемесячное списание**
- **Scheduled Job** (1-го числа каждого месяца):
  - Списать `subscription_amount` с баланса
  - Создать транзакцию `subscription_charge`
  - Если `balance < 0` → заблокировать (`status = 'blocked'`)

**4. Пополнение баланса**
- Создать счёт (`billing.invoice`)
- Админ вручную подтверждает оплату
- Увеличить баланс
- Создать транзакцию `topup`

---

### Для Исполнителей (Комиссия 5%)

**1. При подписании заявки**
```java
// Event: TransportationSignedByExecutorEvent
reserveCommission(executorOrgId, transportationId, cost * 0.05);
```

**2. Резервирование**
- Проверить: `balance >= commission`
- Создать резерв (`status = 'hold'`)
- Увеличить `reserved_balance`
- Создать транзакцию `commission_reserve`

**3. При подтверждении заявки**
```java
// Event: TransportationConfirmedEvent
captureReservation(reservationId);
```

**4. Capture**
- Изменить статус → `captured`
- Уменьшить `balance`
- Уменьшить `reserved_balance`
- Создать транзакцию `commission_capture`

**5. При отмене заявки**
```java
// Event: TransportationCancelledEvent
releaseReservation(reservationId);
```

**6. Release**
- Изменить статус → `released`
- Уменьшить `reserved_balance`
- Создать транзакцию `commission_release`

---

## 📁 Структура кода

```
kz.coube.backend.billing/
├── entity/
│   ├── Account.java
│   ├── Transaction.java
│   ├── Reservation.java
│   ├── Invoice.java
│   └── Payment.java
├── repository/
│   ├── AccountRepository.java
│   ├── TransactionRepository.java
│   ├── ReservationRepository.java
│   ├── InvoiceRepository.java
│   └── PaymentRepository.java
├── service/
│   ├── AccountService.java         // Управление аккаунтами
│   ├── BalanceService.java         // Операции с балансом
│   ├── ReservationService.java     // Hold/Capture/Release
│   ├── InvoiceService.java         // Счета
│   ├── PaymentService.java         // Платежи
│   └── SubscriptionService.java    // Подписки
├── scheduler/
│   ├── MonthlySubscriptionJob.java // Ежемесячное списание
│   └── LowBalanceNotificationJob.java // Уведомления
├── event/
│   └── TransportationEventListener.java // Слушатель событий
├── controller/
│   ├── BillingController.java      // API для клиентов
│   └── BillingAdminController.java // API для админов
└── dto/
    ├── BalanceDto.java
    ├── TransactionDto.java
    └── InvoiceDto.java
```

**~15-20 классов вместо 50+!**

---

## ⏱️ Оценка времени (1 разработчик)

### Неделя 1: База данных + Entities
- **День 1-2**: Flyway миграции (5 таблиц)
- **День 3-4**: JPA Entities (5 классов)
- **День 5**: Repositories (5 классов)

### Неделя 2: Services
- **День 1**: AccountService
- **День 2**: BalanceService (списание, пополнение)
- **День 3-4**: ReservationService (hold/capture/release)
- **День 5**: InvoiceService + PaymentService

### Неделя 3: Интеграция + Jobs
- **День 1-2**: Event Listeners (резервирование при подписании)
- **День 3**: MonthlySubscriptionJob
- **День 4**: LowBalanceNotificationJob
- **День 5**: Unit тесты

### Неделя 4: API + UI
- **День 1-2**: REST Controllers (2 штуки)
- **День 3**: Frontend (страница "Баланс")
- **День 4**: Integration тесты
- **День 5**: Деплой на dev, тестирование

**ИТОГО: 4 недели = 1 месяц!**

---

## 📋 API Endpoints

### Для клиентов

```
GET  /api/v1/billing/balance
→ { balance: 150000, reserved: 10000, available: 140000 }

GET  /api/v1/billing/transactions?page=0&size=20
→ история операций

POST /api/v1/billing/invoices/topup
Body: { amount: 50000 }
→ создать счёт на пополнение

GET  /api/v1/billing/invoices
→ список счетов
```

### Для админов

```
POST /api/v1/admin/billing/payments/manual
Body: { invoiceId: 123, amount: 50000 }
→ подтвердить оплату вручную
```

### Внутренние (для Applications модуля)

```
POST /internal/billing/reservations
Body: { accountId: 456, transportationId: 789, amount: 5000 }
→ зарезервировать комиссию

POST /internal/billing/reservations/{id}/capture
→ зачислить комиссию

POST /internal/billing/reservations/{id}/release
→ освободить резерв
```

---

## 🎯 Что НЕ делаем (упрощения)

1. ❌ **Kill Bill** — не интегрируем
2. ❌ **Сложные тарифы** — только фиксированная подписка 10,000₸/мес
3. ❌ **Автоматическая генерация PDF** — простой текстовый счёт
4. ❌ **Webhook от PSP** — только ручное подтверждение админом
5. ❌ **Ежедневная амортизация** — только ежемесячное списание
6. ❌ **АВР генерация** — делаем позже, если нужно

**Но все основные бизнес-требования выполняются!**

---

## ✅ Что ДЕЛАЕМ

1. ✅ Баланс клиентов (total, reserved, available)
2. ✅ Подписка для Заказчиков (ежемесячная)
3. ✅ Пробный период для новых клиентов
4. ✅ Агентская модель 5% для Исполнителей
5. ✅ Резервирование комиссии (hold/capture/release)
6. ✅ Пополнение баланса (счета + ручное подтверждение)
7. ✅ История операций
8. ✅ Блокировка при отрицательном балансе
9. ✅ Уведомления о низком балансе

---

## 🚀 Миграция на Kill Bill (если понадобится позже)

Если в будущем понадобится Kill Bill:
1. Данные уже в правильной структуре
2. Можно написать синхронизацию
3. Постепенно переключать функции на Kill Bill

**Но для MVP простого решения достаточно!**

---

## 📊 Сравнение решений

| Параметр | Простое решение | Kill Bill |
|----------|-----------------|-----------|
| **Время реализации** | 4 недели | 20-24 недели |
| **Сложность** | Низкая | Высокая |
| **Таблиц в БД** | 5 | 9 + таблицы Kill Bill |
| **Внешние зависимости** | Нет | Kill Bill (Docker) |
| **Поддержка** | Лёгкая | Сложная |
| **Гибкость тарифов** | Ограничена | Высокая |
| **Стоимость разработки** | 1x | 5-6x |

---

## 📁 Файлы в этой папке

1. **README.md** (этот файл) — обзор
2. **01-database-schema-simple.md** — SQL миграции (5 таблиц)
3. **02-services-implementation.md** — Реализация сервисов (6 сервисов с кодом)
4. **03-api-endpoints.md** — REST API (все endpoints с примерами)
5. **04-event-integration.md** — Интеграция с Applications (события)
6. **05-scheduled-jobs.md** — Джобы (ежемесячное списание, уведомления)
7. **06-implementation-checklist.md** — Чеклист на 4 недели
8. **COMPARISON.md** — Сравнение с Kill Bill решением

---

## 🎯 Следующий шаг

Переходи к **01-database-schema-simple.md** для создания БД.

---

**Преимущество этого подхода**: Быстро, просто, работает. MVP за 1 месяц вместо 6!

