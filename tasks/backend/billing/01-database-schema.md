# 01. Схема базы данных для биллинга

## Обзор

Документ описывает все изменения в БД Coube для поддержки системы биллинга. Используется отдельная схема `billing` в существующей PostgreSQL базе данных платформы.

**Важно**: Kill Bill имеет свою отдельную БД — мы её не трогаем. В Coube DB добавляем только связующие таблицы и бизнес-логику.

---

## Архитектура данных

```
┌─────────────────────────────────────────────────────────────┐
│               Coube Platform Database (PostgreSQL)           │
│                                                               │
│  Existing schemas:                                            │
│  ├─ user (организации, сотрудники, роли)                     │
│  ├─ applications (перевозки, контракты, акты, инвойсы)       │
│  ├─ dictionaries (справочники)                               │
│  ├─ factoring (факторинг)                                    │
│  ├─ file (файлы, подписи)                                    │
│  ├─ gis (геоданные)                                          │
│  └─ notifications (уведомления)                              │
│                                                               │
│  NEW schema:                                                  │
│  └─ billing (биллинг-аккаунты, резервы, транзакции, баланс)  │
│                                                               │
└───────────────────────────────────────────────────────────────┘
                                │
                                │ REST API calls
                                ▼
┌───────────────────────────────────────────────────────────────┐
│                 Kill Bill Database (PostgreSQL)               │
│  - accounts (биллинг-аккаунты)                                │
│  - subscriptions (подписки)                                   │
│  - invoices (счета)                                           │
│  - payments (платежи)                                         │
│  - catalog (тарифные планы)                                   │
└───────────────────────────────────────────────────────────────┘
```

---

## Создание схемы `billing`

```sql
-- Создание схемы
CREATE SCHEMA IF NOT EXISTS billing;

-- Комментарий
COMMENT ON SCHEMA billing IS 'Схема для биллинга: аккаунты, балансы, резервы, транзакции, документы';
```

---

## 1. Таблица `billing.account`

**Назначение**: Связь между пользователями Coube и биллинг-аккаунтами Kill Bill. Хранение баланса и метаданных.

```sql
CREATE TABLE billing.account (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с платформой
    organization_id BIGINT NOT NULL REFERENCES users.organization(id),
    
    -- Связь с Kill Bill
    kb_account_id UUID NOT NULL UNIQUE,
    kb_external_key TEXT NOT NULL UNIQUE,
    
    -- Баланс (в тенге, копейках)
    total_balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    available_balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    reserved_balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Определение new/old клиента
    is_new_client BOOLEAN NOT NULL DEFAULT true,
    trial_ends_at TIMESTAMP,
    trial_granted_at TIMESTAMP,
    
    -- Статус аккаунта
    status TEXT NOT NULL DEFAULT 'active', -- active, trial, blocked, suspended
    blocked_reason TEXT,
    blocked_at TIMESTAMP,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_balance_non_negative CHECK (total_balance + reserved_balance >= 0),
    CONSTRAINT check_available_balance CHECK (available_balance = total_balance - reserved_balance),
    CONSTRAINT check_reserved_non_negative CHECK (reserved_balance >= 0)
);

-- Индексы
CREATE INDEX idx_billing_account_organization ON billing.account(organization_id);
CREATE INDEX idx_billing_account_kb_id ON billing.account(kb_account_id);
CREATE INDEX idx_billing_account_status ON billing.account(status) WHERE status IN ('blocked', 'suspended');

-- Комментарии
COMMENT ON TABLE billing.account IS 'Биллинг-аккаунт: связь организации с Kill Bill и баланс';
COMMENT ON COLUMN billing.account.kb_account_id IS 'UUID аккаунта в Kill Bill';
COMMENT ON COLUMN billing.account.kb_external_key IS 'External key для Kill Bill (обычно organization_id)';
COMMENT ON COLUMN billing.account.total_balance IS 'Общий баланс в тенге (с учетом резервов)';
COMMENT ON COLUMN billing.account.available_balance IS 'Доступный баланс = total - reserved';
COMMENT ON COLUMN billing.account.reserved_balance IS 'Зарезервированная сумма (комиссии)';
COMMENT ON COLUMN billing.account.is_new_client IS 'Новый клиент (true) или старый (false)';
COMMENT ON COLUMN billing.account.trial_ends_at IS 'Дата окончания пробного периода';
COMMENT ON COLUMN billing.account.status IS 'active, trial, blocked, suspended';
```

**Пример данных**:
```sql
INSERT INTO billing.account (
    organization_id, kb_account_id, kb_external_key, 
    total_balance, available_balance, reserved_balance,
    is_new_client, trial_ends_at, status, created_by, updated_by
) VALUES (
    123, 'a3f1b5c9-8d2e-4f7a-9c1d-5e6f7a8b9c0d', 'org_123',
    150000.00, 140000.00, 10000.00,
    true, '2025-11-01 00:00:00', 'trial', 'system', 'system'
);
```

---

## 2. Таблица `billing.subscription`

**Назначение**: Локальная копия подписок из Kill Bill для быстрого доступа и отчётности.

```sql
CREATE TABLE billing.subscription (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом
    account_id BIGINT NOT NULL REFERENCES billing.account(id) ON DELETE CASCADE,
    
    -- Связь с Kill Bill
    kb_subscription_id UUID NOT NULL UNIQUE,
    kb_bundle_id UUID NOT NULL,
    
    -- Тарифный план
    plan_name TEXT NOT NULL, -- standard-monthly, premium-monthly
    billing_period TEXT NOT NULL DEFAULT 'MONTHLY', -- MONTHLY, ANNUAL
    
    -- Стоимость
    amount NUMERIC(19, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Даты
    start_date DATE NOT NULL,
    billing_start_date DATE NOT NULL,
    next_billing_date DATE,
    cancelled_date DATE,
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'active', -- active, cancelled, expired
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);

-- Индексы
CREATE INDEX idx_billing_subscription_account ON billing.subscription(account_id);
CREATE INDEX idx_billing_subscription_kb_id ON billing.subscription(kb_subscription_id);
CREATE INDEX idx_billing_subscription_status ON billing.subscription(status) WHERE status = 'active';
CREATE INDEX idx_billing_subscription_next_billing ON billing.subscription(next_billing_date) WHERE status = 'active';

-- Комментарии
COMMENT ON TABLE billing.subscription IS 'Подписки Заказчиков (копия из Kill Bill)';
COMMENT ON COLUMN billing.subscription.plan_name IS 'Название тарифного плана';
COMMENT ON COLUMN billing.subscription.next_billing_date IS 'Дата следующего списания';
```

---

## 3. Таблица `billing.reservation`

**Назначение**: Резервирование средств Исполнителей для оплаты комиссии (агентская модель 5%).

```sql
CREATE TABLE billing.reservation (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом и заявкой
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    transportation_id BIGINT NOT NULL REFERENCES applications.transportation(id),
    transportation_cost_id BIGINT REFERENCES applications.transportation_cost(id),
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'KZT',
    commission_percentage NUMERIC(5, 2) NOT NULL DEFAULT 5.00,
    
    -- Статус резерва
    status TEXT NOT NULL DEFAULT 'hold', -- hold, captured, released, expired
    
    -- Даты
    reserved_at TIMESTAMP NOT NULL DEFAULT now(),
    captured_at TIMESTAMP,
    released_at TIMESTAMP,
    expires_at TIMESTAMP, -- автоотмена резерва через N дней
    
    -- Причина capture/release
    capture_reason TEXT,
    release_reason TEXT,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_reservation_amount_positive CHECK (amount > 0),
    CONSTRAINT check_reservation_status CHECK (status IN ('hold', 'captured', 'released', 'expired'))
);

-- Индексы
CREATE INDEX idx_billing_reservation_account ON billing.reservation(account_id);
CREATE INDEX idx_billing_reservation_transportation ON billing.reservation(transportation_id);
CREATE INDEX idx_billing_reservation_status ON billing.reservation(status) WHERE status = 'hold';
CREATE INDEX idx_billing_reservation_expires ON billing.reservation(expires_at) WHERE status = 'hold';

-- Комментарии
COMMENT ON TABLE billing.reservation IS 'Резервы комиссии для Исполнителей (агентская модель)';
COMMENT ON COLUMN billing.reservation.status IS 'hold - зарезервировано, captured - зачислено, released - возвращено, expired - истёк срок';
COMMENT ON COLUMN billing.reservation.commission_percentage IS 'Процент комиссии (обычно 5%)';
COMMENT ON COLUMN billing.reservation.expires_at IS 'Дата автоматического освобождения резерва';
```

**Пример данных**:
```sql
-- Резервирование комиссии при подписании заявки
INSERT INTO billing.reservation (
    account_id, transportation_id, amount, commission_percentage,
    status, expires_at, created_by, updated_by
) VALUES (
    456, 789, 5000.00, 5.00,
    'hold', now() + interval '30 days', 'system', 'system'
);
```

---

## 4. Таблица `billing.transaction`

**Назначение**: Все проводки и финансовые операции. Источник истины для бухгалтерии.

```sql
CREATE TABLE billing.transaction (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Тип операции
    type TEXT NOT NULL, -- subscription_charge, commission_reserve, commission_capture, 
                        -- balance_topup, refund, adjustment
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Баланс до/после
    balance_before NUMERIC(19, 2) NOT NULL,
    balance_after NUMERIC(19, 2) NOT NULL,
    
    -- Связанные сущности
    reservation_id BIGINT REFERENCES billing.reservation(id),
    subscription_id BIGINT REFERENCES billing.subscription(id),
    invoice_id BIGINT REFERENCES billing.invoice(id),
    transportation_id BIGINT REFERENCES applications.transportation(id),
    
    -- Kill Bill данные (опционально)
    kb_payment_id UUID,
    kb_transaction_id UUID,
    
    -- Описание
    description TEXT,
    metadata JSONB, -- дополнительные данные
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_transaction_type CHECK (type IN (
        'subscription_charge', 'commission_reserve', 'commission_capture', 
        'commission_release', 'balance_topup', 'refund', 'adjustment'
    ))
);

-- Индексы
CREATE INDEX idx_billing_transaction_account ON billing.transaction(account_id);
CREATE INDEX idx_billing_transaction_type ON billing.transaction(type);
CREATE INDEX idx_billing_transaction_created ON billing.transaction(created_at DESC);
CREATE INDEX idx_billing_transaction_reservation ON billing.transaction(reservation_id) WHERE reservation_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE billing.transaction IS 'Все финансовые операции (проводки)';
COMMENT ON COLUMN billing.transaction.type IS 'Тип: subscription_charge, commission_reserve, balance_topup, refund, adjustment';
COMMENT ON COLUMN billing.transaction.balance_before IS 'Баланс до операции';
COMMENT ON COLUMN billing.transaction.balance_after IS 'Баланс после операции';
COMMENT ON COLUMN billing.transaction.metadata IS 'JSON с дополнительными данными';
```

---

## 5. Таблица `billing.invoice`

**Назначение**: Счета на пополнение баланса и ежемесячные счета за подписку/комиссию.

```sql
CREATE TABLE billing.invoice (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Связь с Kill Bill
    kb_invoice_id UUID UNIQUE,
    kb_invoice_number TEXT,
    
    -- Номер и дата
    invoice_number TEXT NOT NULL UNIQUE,
    invoice_date DATE NOT NULL,
    due_date DATE,
    
    -- Тип счёта
    type TEXT NOT NULL, -- subscription, commission, topup, refund
    
    -- Суммы
    amount_without_vat NUMERIC(19, 2) NOT NULL,
    vat_amount NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    amount_with_vat NUMERIC(19, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'draft', -- draft, pending, paid, overdue, cancelled
    paid_at TIMESTAMP,
    
    -- Документ
    file_id UUID REFERENCES file.file_meta_info(id),
    file_name TEXT,
    
    -- Связанные сущности
    subscription_id BIGINT REFERENCES billing.subscription(id),
    period_start DATE,
    period_end DATE,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_invoice_type CHECK (type IN ('subscription', 'commission', 'topup', 'refund')),
    CONSTRAINT check_invoice_status CHECK (status IN ('draft', 'pending', 'paid', 'overdue', 'cancelled')),
    CONSTRAINT check_invoice_vat CHECK (amount_with_vat = amount_without_vat + vat_amount)
);

-- Индексы
CREATE INDEX idx_billing_invoice_account ON billing.invoice(account_id);
CREATE INDEX idx_billing_invoice_number ON billing.invoice(invoice_number);
CREATE INDEX idx_billing_invoice_kb_id ON billing.invoice(kb_invoice_id) WHERE kb_invoice_id IS NOT NULL;
CREATE INDEX idx_billing_invoice_status ON billing.invoice(status) WHERE status IN ('pending', 'overdue');
CREATE INDEX idx_billing_invoice_due_date ON billing.invoice(due_date) WHERE status = 'pending';

-- Комментарии
COMMENT ON TABLE billing.invoice IS 'Счета на оплату (подписка, комиссия, пополнение баланса)';
COMMENT ON COLUMN billing.invoice.type IS 'subscription - за подписку, commission - комиссия, topup - пополнение';
COMMENT ON COLUMN billing.invoice.period_start IS 'Начало расчётного периода (для subscription/commission)';
```

**Генерация номера**:
```sql
-- Trigger для автогенерации invoice_number
CREATE OR REPLACE FUNCTION billing.generate_invoice_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.invoice_number IS NULL THEN
        NEW.invoice_number := 'INV-' || TO_CHAR(NEW.invoice_date, 'YYYYMMDD') || '-' || LPAD(NEW.id::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_invoice_number
BEFORE INSERT ON billing.invoice
FOR EACH ROW
EXECUTE FUNCTION billing.generate_invoice_number();
```

---

## 6. Таблица `billing.payment`

**Назначение**: Платежи от клиентов (онлайн или вручную подтверждённые).

```sql
CREATE TABLE billing.payment (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с счётом
    invoice_id BIGINT NOT NULL REFERENCES billing.invoice(id),
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Связь с Kill Bill
    kb_payment_id UUID UNIQUE,
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Метод оплаты
    payment_method TEXT NOT NULL, -- manual, bcc, jusan, kaspi
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'pending', -- pending, success, failed, refunded
    
    -- PSP данные
    psp_transaction_id TEXT,
    psp_name TEXT, -- BCC, Jusan, Kaspi
    psp_response JSONB,
    
    -- Даты
    paid_at TIMESTAMP,
    refunded_at TIMESTAMP,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_payment_status CHECK (status IN ('pending', 'success', 'failed', 'refunded')),
    CONSTRAINT check_payment_amount_positive CHECK (amount > 0)
);

-- Индексы
CREATE INDEX idx_billing_payment_invoice ON billing.payment(invoice_id);
CREATE INDEX idx_billing_payment_account ON billing.payment(account_id);
CREATE INDEX idx_billing_payment_kb_id ON billing.payment(kb_payment_id) WHERE kb_payment_id IS NOT NULL;
CREATE INDEX idx_billing_payment_psp_txn ON billing.payment(psp_transaction_id) WHERE psp_transaction_id IS NOT NULL;
CREATE INDEX idx_billing_payment_status ON billing.payment(status) WHERE status = 'pending';

-- Комментарии
COMMENT ON TABLE billing.payment IS 'Платежи клиентов (онлайн или вручную)';
COMMENT ON COLUMN billing.payment.payment_method IS 'manual - ручное подтверждение, bcc/jusan/kaspi - онлайн';
COMMENT ON COLUMN billing.payment.psp_response IS 'JSON-ответ от платёжной системы';
```

---

## 7. Таблица `billing.document`

**Назначение**: Метаданные документов (АВР, счета, акты).

```sql
CREATE TABLE billing.document (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с сущностями
    invoice_id BIGINT REFERENCES billing.invoice(id),
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    subscription_id BIGINT REFERENCES billing.subscription(id),
    
    -- Тип документа
    type TEXT NOT NULL, -- invoice_pdf, avr, act, registry, statement
    
    -- Файл
    file_id UUID NOT NULL REFERENCES file.file_meta_info(id),
    file_name TEXT NOT NULL,
    file_url TEXT, -- URL для скачивания (из MinIO)
    
    -- Период (для АВР)
    period_start DATE,
    period_end DATE,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_document_type CHECK (type IN ('invoice_pdf', 'avr', 'act', 'registry', 'statement'))
);

-- Индексы
CREATE INDEX idx_billing_document_invoice ON billing.document(invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX idx_billing_document_account ON billing.document(account_id);
CREATE INDEX idx_billing_document_type ON billing.document(type);
CREATE INDEX idx_billing_document_created ON billing.document(created_at DESC);

-- Комментарии
COMMENT ON TABLE billing.document IS 'Документы биллинга (АВР, счета, акты)';
COMMENT ON COLUMN billing.document.type IS 'invoice_pdf, avr (акт выполненных работ), act, registry, statement';
```

---

## 8. Таблица `billing.balance_history`

**Назначение**: История изменения баланса для аудита и отчётности.

```sql
CREATE TABLE billing.balance_history (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Изменение баланса
    balance_before NUMERIC(19, 2) NOT NULL,
    balance_after NUMERIC(19, 2) NOT NULL,
    change_amount NUMERIC(19, 2) NOT NULL,
    
    -- Тип операции
    operation_type TEXT NOT NULL,
    
    -- Связь с транзакцией
    transaction_id BIGINT REFERENCES billing.transaction(id),
    
    -- Описание
    description TEXT,
    
    -- Дата
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL
);

-- Индексы
CREATE INDEX idx_billing_balance_history_account ON billing.balance_history(account_id);
CREATE INDEX idx_billing_balance_history_created ON billing.balance_history(created_at DESC);

-- Комментарии
COMMENT ON TABLE billing.balance_history IS 'История изменения баланса для аудита';
```

---

## 9. Таблица `billing.webhook_log`

**Назначение**: Лог всех webhook'ов от платёжных систем для отладки.

```sql
CREATE TABLE billing.webhook_log (
    id BIGSERIAL PRIMARY KEY,
    
    -- PSP
    psp_name TEXT NOT NULL, -- bcc, jusan, kaspi
    
    -- Payload
    payload JSONB NOT NULL,
    headers JSONB,
    
    -- Обработка
    status TEXT NOT NULL DEFAULT 'received', -- received, processing, success, failed
    processed_at TIMESTAMP,
    error_message TEXT,
    
    -- Связь с платежом
    payment_id BIGINT REFERENCES billing.payment(id),
    
    -- IP адрес
    ip_address INET,
    
    -- Дата
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

-- Индексы
CREATE INDEX idx_billing_webhook_log_psp ON billing.webhook_log(psp_name);
CREATE INDEX idx_billing_webhook_log_status ON billing.webhook_log(status) WHERE status IN ('received', 'processing');
CREATE INDEX idx_billing_webhook_log_created ON billing.webhook_log(created_at DESC);
CREATE INDEX idx_billing_webhook_log_payment ON billing.webhook_log(payment_id) WHERE payment_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE billing.webhook_log IS 'Лог webhook от PSP для отладки';
```

---

## 10. Изменения в существующих таблицах

### 10.1. Таблица `users.organization`

**Добавить поле для быстрого доступа к биллинг-аккаунту**:

```sql
ALTER TABLE users.organization
ADD COLUMN IF NOT EXISTS billing_account_id BIGINT REFERENCES billing.account(id);

CREATE INDEX idx_organization_billing_account ON users.organization(billing_account_id) WHERE billing_account_id IS NOT NULL;

COMMENT ON COLUMN users.organization.billing_account_id IS 'Связь с биллинг-аккаунтом';
```

### 10.2. Таблица `applications.transportation_cost`

**Добавить поле для резерва комиссии**:

```sql
ALTER TABLE applications.transportation_cost
ADD COLUMN IF NOT EXISTS commission_reservation_id BIGINT REFERENCES billing.reservation(id);

CREATE INDEX idx_transportation_cost_reservation ON applications.transportation_cost(commission_reservation_id) WHERE commission_reservation_id IS NOT NULL;

COMMENT ON COLUMN applications.transportation_cost.commission_reservation_id IS 'Связь с резервом комиссии (агентская модель)';
```

---

## Триггеры и автоматизация

### Триггер обновления `updated_at`

```sql
-- Функция для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION billing.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Применить ко всем таблицам
CREATE TRIGGER trigger_update_updated_at BEFORE UPDATE ON billing.account FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
CREATE TRIGGER trigger_update_updated_at BEFORE UPDATE ON billing.subscription FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
CREATE TRIGGER trigger_update_updated_at BEFORE UPDATE ON billing.reservation FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
CREATE TRIGGER trigger_update_updated_at BEFORE UPDATE ON billing.invoice FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
CREATE TRIGGER trigger_update_updated_at BEFORE UPDATE ON billing.payment FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
CREATE TRIGGER trigger_update_updated_at BEFORE UPDATE ON billing.document FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
```

### Триггер для автообновления `available_balance`

```sql
CREATE OR REPLACE FUNCTION billing.update_available_balance()
RETURNS TRIGGER AS $$
BEGIN
    NEW.available_balance = NEW.total_balance - NEW.reserved_balance;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_available_balance 
BEFORE INSERT OR UPDATE OF total_balance, reserved_balance ON billing.account
FOR EACH ROW 
EXECUTE FUNCTION billing.update_available_balance();
```

---

## Представления (Views)

### View: Актуальный баланс со статусом подписки

```sql
CREATE OR REPLACE VIEW billing.v_account_status AS
SELECT 
    a.id AS account_id,
    a.organization_id,
    o.organization_name,
    o.iin_bin,
    a.total_balance,
    a.available_balance,
    a.reserved_balance,
    a.currency,
    a.is_new_client,
    a.trial_ends_at,
    a.status AS account_status,
    s.id AS subscription_id,
    s.plan_name,
    s.status AS subscription_status,
    s.next_billing_date,
    -- Дней до блокировки (примерная оценка)
    CASE 
        WHEN s.amount > 0 THEN FLOOR(a.available_balance / (s.amount / 30))
        ELSE NULL
    END AS days_until_blocked
FROM billing.account a
LEFT JOIN users.organization o ON a.organization_id = o.id
LEFT JOIN billing.subscription s ON a.id = s.account_id AND s.status = 'active';

COMMENT ON VIEW billing.v_account_status IS 'Статус биллинг-аккаунта с подпиской';
```

### View: История операций по аккаунту

```sql
CREATE OR REPLACE VIEW billing.v_transaction_history AS
SELECT 
    t.id,
    t.account_id,
    o.organization_name,
    t.type,
    t.amount,
    t.currency,
    t.balance_before,
    t.balance_after,
    t.description,
    t.created_at,
    t.created_by,
    -- Связанные сущности
    r.transportation_id AS reservation_transportation_id,
    i.invoice_number
FROM billing.transaction t
LEFT JOIN billing.account a ON t.account_id = a.id
LEFT JOIN users.organization o ON a.organization_id = o.id
LEFT JOIN billing.reservation r ON t.reservation_id = r.id
LEFT JOIN billing.invoice i ON t.invoice_id = i.id
ORDER BY t.created_at DESC;

COMMENT ON VIEW billing.v_transaction_history IS 'История всех операций по счетам';
```

---

## Миграции Flyway

**Путь**: `coube-backend/src/main/resources/db/migration/`

### V1.0__billing_schema.sql
```sql
-- Создание схемы и основных таблиц
-- (Код выше)
```

### V1.1__billing_triggers.sql
```sql
-- Триггеры для автоматизации
-- (Код выше)
```

### V1.2__billing_views.sql
```sql
-- Представления для отчётности
-- (Код выше)
```

### V1.3__billing_indexes.sql
```sql
-- Дополнительные индексы для оптимизации
-- (Код выше)
```

---

## Пример использования

### Создание биллинг-аккаунта при регистрации

```sql
-- 1. Проверка new/old клиента
SELECT id FROM users.organization 
WHERE (organization_name = 'ООО РЕЙС-1' OR iin_bin = '123456789012')
  AND deleted_at IS NOT NULL;

-- 2. Создание биллинг-аккаунта
INSERT INTO billing.account (
    organization_id, kb_account_id, kb_external_key,
    is_new_client, trial_ends_at, status, created_by, updated_by
) VALUES (
    123, 'uuid-from-killbill', 'org_123',
    true, now() + interval '1 month', 'trial', 'system', 'system'
);

-- 3. Обновление организации
UPDATE users.organization 
SET billing_account_id = (SELECT id FROM billing.account WHERE organization_id = 123)
WHERE id = 123;
```

### Резервирование комиссии

```sql
-- 1. Проверка баланса
SELECT available_balance FROM billing.account WHERE id = 456;

-- 2. Создание резерва
INSERT INTO billing.reservation (
    account_id, transportation_id, amount, commission_percentage,
    status, expires_at, created_by, updated_by
) VALUES (
    456, 789, 5000.00, 5.00,
    'hold', now() + interval '30 days', 'system', 'system'
) RETURNING id;

-- 3. Обновление reserved_balance
UPDATE billing.account 
SET reserved_balance = reserved_balance + 5000.00
WHERE id = 456;

-- 4. Запись в историю
INSERT INTO billing.transaction (
    account_id, type, amount, balance_before, balance_after,
    reservation_id, description, created_by
) VALUES (
    456, 'commission_reserve', -5000.00, 150000.00, 145000.00,
    <reservation_id>, 'Резерв комиссии 5% для заявки #789', 'system'
);
```

---

## Следующие шаги

1. ✅ Создать Flyway миграции на основе этого документа
2. → Перейти к `02-killbill-setup.md` для установки Kill Bill
3. → Реализовать слой интеграции в `03-integration-layer.md`

---

**Документ подготовлен**: 2025-01-XX  
**Версия**: 1.0  
**Проверено**: Backend Team
