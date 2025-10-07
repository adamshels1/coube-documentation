# 01. Упрощённая схема базы данных

## Обзор

Минималистичная схема биллинга: **всего 5 таблиц** вместо 9.

---

## Создание схемы

```sql
CREATE SCHEMA IF NOT EXISTS billing;
COMMENT ON SCHEMA billing IS 'Упрощённая система биллинга без Kill Bill';
```

---

## Таблица 1: `billing.account`

**Назначение**: Баланс и подписка клиента (всё в одной таблице).

```sql
CREATE TABLE billing.account (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с организацией
    organization_id BIGINT NOT NULL UNIQUE REFERENCES users.organization(id),
    
    -- Баланс (в тенге)
    balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    reserved_balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    currency TEXT NOT NULL DEFAULT 'KZT',
    
    -- Подписка (упрощённо)
    subscription_active BOOLEAN NOT NULL DEFAULT false,
    subscription_amount NUMERIC(19, 2) DEFAULT 10000.00,
    subscription_start_date DATE,
    subscription_next_billing_date DATE,
    
    -- Пробный период
    is_new_client BOOLEAN NOT NULL DEFAULT true,
    trial_ends_at TIMESTAMP,
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'active', -- active, trial, blocked
    blocked_reason TEXT,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_balance CHECK (balance >= -reserved_balance),
    CONSTRAINT check_reserved CHECK (reserved_balance >= 0),
    CONSTRAINT check_status CHECK (status IN ('active', 'trial', 'blocked'))
);

-- Индексы
CREATE INDEX idx_billing_account_org ON billing.account(organization_id);
CREATE INDEX idx_billing_account_status ON billing.account(status) WHERE status = 'blocked';
CREATE INDEX idx_billing_account_next_billing ON billing.account(subscription_next_billing_date) 
    WHERE subscription_active = true;

-- Комментарии
COMMENT ON TABLE billing.account IS 'Баланс и подписка клиента (упрощённая версия)';
COMMENT ON COLUMN billing.account.balance IS 'Общий баланс (может быть отрицательным при резервах)';
COMMENT ON COLUMN billing.account.reserved_balance IS 'Зарезервированная сумма (комиссии)';
COMMENT ON COLUMN billing.account.subscription_amount IS 'Сумма ежемесячной подписки';
COMMENT ON COLUMN billing.account.trial_ends_at IS 'Конец пробного периода';
```

**Пример данных**:
```sql
INSERT INTO billing.account (
    organization_id, balance, reserved_balance, 
    subscription_active, subscription_amount, subscription_start_date,
    is_new_client, trial_ends_at, status,
    created_by, updated_by
) VALUES (
    123, 150000.00, 10000.00,
    true, 10000.00, '2025-01-01',
    true, '2025-02-01', 'trial',
    'system', 'system'
);
```

---

## Таблица 2: `billing.transaction`

**Назначение**: Все финансовые операции (единый журнал).

```sql
CREATE TABLE billing.transaction (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Тип операции
    type TEXT NOT NULL,
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    balance_before NUMERIC(19, 2) NOT NULL,
    balance_after NUMERIC(19, 2) NOT NULL,
    
    -- Связи
    transportation_id BIGINT REFERENCES applications.transportation(id),
    invoice_id BIGINT,
    reservation_id BIGINT,
    
    -- Описание
    description TEXT,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_transaction_type CHECK (type IN (
        'topup',                 -- Пополнение баланса
        'subscription_charge',   -- Списание подписки
        'commission_reserve',    -- Резерв комиссии
        'commission_capture',    -- Зачисление комиссии
        'commission_release',    -- Освобождение резерва
        'adjustment'             -- Корректировка админом
    ))
);

-- Индексы
CREATE INDEX idx_billing_transaction_account ON billing.transaction(account_id);
CREATE INDEX idx_billing_transaction_type ON billing.transaction(type);
CREATE INDEX idx_billing_transaction_created ON billing.transaction(created_at DESC);
CREATE INDEX idx_billing_transaction_transportation ON billing.transaction(transportation_id) 
    WHERE transportation_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE billing.transaction IS 'Все финансовые операции (единый журнал)';
COMMENT ON COLUMN billing.transaction.type IS 'topup, subscription_charge, commission_reserve, commission_capture, commission_release, adjustment';
```

**Пример данных**:
```sql
-- Пополнение баланса
INSERT INTO billing.transaction (
    account_id, type, amount, balance_before, balance_after,
    description, created_by
) VALUES (
    123, 'topup', 100000.00, 50000.00, 150000.00,
    'Пополнение баланса по счёту INV-001', 'admin'
);

-- Резерв комиссии
INSERT INTO billing.transaction (
    account_id, type, amount, balance_before, balance_after,
    transportation_id, reservation_id, description, created_by
) VALUES (
    123, 'commission_reserve', -5000.00, 150000.00, 150000.00,
    789, 1, 'Резерв комиссии 5% для заявки #789', 'system'
);
```

---

## Таблица 3: `billing.reservation`

**Назначение**: Резервы комиссии (агентская модель).

```sql
CREATE TABLE billing.reservation (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связи
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    transportation_id BIGINT NOT NULL REFERENCES applications.transportation(id),
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'hold',
    
    -- Даты
    reserved_at TIMESTAMP NOT NULL DEFAULT now(),
    captured_at TIMESTAMP,
    released_at TIMESTAMP,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    
    -- Constraints
    CONSTRAINT check_reservation_status CHECK (status IN ('hold', 'captured', 'released')),
    CONSTRAINT check_reservation_amount CHECK (amount > 0)
);

-- Индексы
CREATE INDEX idx_billing_reservation_account ON billing.reservation(account_id);
CREATE INDEX idx_billing_reservation_transportation ON billing.reservation(transportation_id);
CREATE INDEX idx_billing_reservation_status ON billing.reservation(status) WHERE status = 'hold';

-- Комментарии
COMMENT ON TABLE billing.reservation IS 'Резервы комиссии для Исполнителей';
COMMENT ON COLUMN billing.reservation.status IS 'hold - зарезервировано, captured - зачислено, released - возвращено';
```

**Пример данных**:
```sql
-- Создание резерва
INSERT INTO billing.reservation (
    account_id, transportation_id, amount, status
) VALUES (
    456, 789, 5000.00, 'hold'
);

-- Capture резерва
UPDATE billing.reservation 
SET status = 'captured', captured_at = now(), updated_at = now()
WHERE id = 1;
```

---

## Таблица 4: `billing.invoice`

**Назначение**: Счета на пополнение баланса.

```sql
CREATE TABLE billing.invoice (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связь с аккаунтом
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Номер и сумма
    invoice_number TEXT NOT NULL UNIQUE,
    amount NUMERIC(19, 2) NOT NULL,
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'pending',
    
    -- Даты
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    paid_at TIMESTAMP,
    
    -- Constraints
    CONSTRAINT check_invoice_status CHECK (status IN ('pending', 'paid', 'cancelled')),
    CONSTRAINT check_invoice_amount CHECK (amount > 0)
);

-- Индексы
CREATE INDEX idx_billing_invoice_account ON billing.invoice(account_id);
CREATE INDEX idx_billing_invoice_number ON billing.invoice(invoice_number);
CREATE INDEX idx_billing_invoice_status ON billing.invoice(status) WHERE status = 'pending';

-- Комментарии
COMMENT ON TABLE billing.invoice IS 'Счета на пополнение баланса';
```

-- Триггер для автогенерации номера
```sql
CREATE OR REPLACE FUNCTION billing.generate_invoice_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.invoice_number IS NULL THEN
        NEW.invoice_number := 'INV-' || TO_CHAR(NEW.created_at, 'YYYYMMDD') || '-' || LPAD(NEW.id::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_invoice_number
AFTER INSERT ON billing.invoice
FOR EACH ROW
WHEN (NEW.invoice_number IS NULL)
EXECUTE FUNCTION billing.generate_invoice_number();
```

**Пример данных**:
```sql
INSERT INTO billing.invoice (
    account_id, invoice_number, amount, status
) VALUES (
    123, 'INV-20250107-000001', 50000.00, 'pending'
);
```

---

## Таблица 5: `billing.payment`

**Назначение**: Платежи клиентов.

```sql
CREATE TABLE billing.payment (
    id BIGSERIAL PRIMARY KEY,
    
    -- Связи
    invoice_id BIGINT NOT NULL REFERENCES billing.invoice(id),
    account_id BIGINT NOT NULL REFERENCES billing.account(id),
    
    -- Сумма
    amount NUMERIC(19, 2) NOT NULL,
    
    -- Метод оплаты
    payment_method TEXT NOT NULL DEFAULT 'manual',
    
    -- Статус
    status TEXT NOT NULL DEFAULT 'success',
    
    -- PSP данные (для будущей интеграции)
    psp_transaction_id TEXT,
    
    -- Метаданные
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL,
    
    -- Constraints
    CONSTRAINT check_payment_method CHECK (payment_method IN ('manual', 'online')),
    CONSTRAINT check_payment_status CHECK (status IN ('success', 'failed')),
    CONSTRAINT check_payment_amount CHECK (amount > 0)
);

-- Индексы
CREATE INDEX idx_billing_payment_invoice ON billing.payment(invoice_id);
CREATE INDEX idx_billing_payment_account ON billing.payment(account_id);
CREATE INDEX idx_billing_payment_psp ON billing.payment(psp_transaction_id) 
    WHERE psp_transaction_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE billing.payment IS 'Платежи клиентов';
COMMENT ON COLUMN billing.payment.payment_method IS 'manual - ручное подтверждение админом, online - автоматическое';
```

**Пример данных**:
```sql
INSERT INTO billing.payment (
    invoice_id, account_id, amount, payment_method, status, created_by
) VALUES (
    1, 123, 50000.00, 'manual', 'success', 'admin'
);
```

---

## Триггеры

### Автообновление `updated_at`

```sql
CREATE OR REPLACE FUNCTION billing.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_account_updated_at 
BEFORE UPDATE ON billing.account 
FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();

CREATE TRIGGER trigger_reservation_updated_at 
BEFORE UPDATE ON billing.reservation 
FOR EACH ROW EXECUTE FUNCTION billing.update_updated_at();
```

---

## Представления (Views)

### View: Статус аккаунта с балансом

```sql
CREATE OR REPLACE VIEW billing.v_account_status AS
SELECT 
    a.id AS account_id,
    a.organization_id,
    o.organization_name,
    a.balance,
    a.reserved_balance,
    (a.balance - a.reserved_balance) AS available_balance,
    a.subscription_active,
    a.subscription_amount,
    a.subscription_next_billing_date,
    a.is_new_client,
    a.trial_ends_at,
    a.status,
    -- Дней до блокировки (примерная оценка)
    CASE 
        WHEN a.subscription_active AND a.subscription_amount > 0 
        THEN FLOOR((a.balance - a.reserved_balance) / a.subscription_amount * 30)
        ELSE NULL
    END AS days_until_blocked
FROM billing.account a
LEFT JOIN users.organization o ON a.organization_id = o.id;
```

### View: История транзакций

```sql
CREATE OR REPLACE VIEW billing.v_transaction_history AS
SELECT 
    t.id,
    t.account_id,
    o.organization_name,
    t.type,
    t.amount,
    t.balance_before,
    t.balance_after,
    t.description,
    t.created_at,
    t.created_by,
    tr.id AS transportation_id
FROM billing.transaction t
LEFT JOIN billing.account a ON t.account_id = a.id
LEFT JOIN users.organization o ON a.organization_id = o.id
LEFT JOIN applications.transportation tr ON t.transportation_id = tr.id
ORDER BY t.created_at DESC;
```

---

## Изменения в существующих таблицах

### Добавить в `users.organization`

```sql
ALTER TABLE users.organization
ADD COLUMN IF NOT EXISTS billing_account_id BIGINT REFERENCES billing.account(id);

CREATE INDEX idx_organization_billing_account 
ON users.organization(billing_account_id) 
WHERE billing_account_id IS NOT NULL;

COMMENT ON COLUMN users.organization.billing_account_id IS 'Связь с биллинг-аккаунтом';
```

### Добавить в `applications.transportation`

```sql
ALTER TABLE applications.transportation
ADD COLUMN IF NOT EXISTS commission_reservation_id BIGINT REFERENCES billing.reservation(id);

CREATE INDEX idx_transportation_reservation 
ON applications.transportation(commission_reservation_id) 
WHERE commission_reservation_id IS NOT NULL;

COMMENT ON COLUMN applications.transportation.commission_reservation_id IS 'Резерв комиссии для этой заявки';
```

---

## Миграции Flyway

### V1.0__billing_schema_simple.sql

```sql
-- Создание схемы и таблиц (код выше)
```

### V1.1__billing_triggers_simple.sql

```sql
-- Триггеры (код выше)
```

### V1.2__billing_views_simple.sql

```sql
-- Представления (код выше)
```

### V1.3__billing_foreign_keys_simple.sql

```sql
-- Изменения в существующих таблицах (код выше)
```

---

## Примеры использования

### Создание биллинг-аккаунта

```sql
-- Для нового клиента
INSERT INTO billing.account (
    organization_id, balance, is_new_client, trial_ends_at,
    status, created_by, updated_by
) VALUES (
    123, 0.00, true, now() + interval '1 month',
    'trial', 'system', 'system'
) RETURNING id;

-- Обновить организацию
UPDATE users.organization 
SET billing_account_id = <new_account_id>
WHERE id = 123;
```

### Резервирование комиссии

```sql
-- 1. Проверить баланс
SELECT balance, reserved_balance 
FROM billing.account 
WHERE id = 456;

-- 2. Создать резерв
INSERT INTO billing.reservation (
    account_id, transportation_id, amount, status
) VALUES (
    456, 789, 5000.00, 'hold'
) RETURNING id;

-- 3. Увеличить reserved_balance
UPDATE billing.account 
SET reserved_balance = reserved_balance + 5000.00,
    updated_at = now()
WHERE id = 456;

-- 4. Записать транзакцию
INSERT INTO billing.transaction (
    account_id, type, amount, balance_before, balance_after,
    transportation_id, reservation_id, description, created_by
) VALUES (
    456, 'commission_reserve', 0.00, 
    (SELECT balance FROM billing.account WHERE id = 456),
    (SELECT balance FROM billing.account WHERE id = 456),
    789, <reservation_id>, 
    'Резерв комиссии 5% для заявки #789', 'system'
);
```

### Capture резерва

```sql
-- 1. Обновить резерв
UPDATE billing.reservation 
SET status = 'captured', captured_at = now(), updated_at = now()
WHERE id = 1;

-- 2. Списать с баланса и уменьшить резерв
UPDATE billing.account 
SET balance = balance - 5000.00,
    reserved_balance = reserved_balance - 5000.00,
    updated_at = now()
WHERE id = 456;

-- 3. Записать транзакцию
INSERT INTO billing.transaction (
    account_id, type, amount, balance_before, balance_after,
    reservation_id, description, created_by
) VALUES (
    456, 'commission_capture', -5000.00, 150000.00, 145000.00,
    1, 'Зачисление комиссии 5% на платформу', 'system'
);
```

---

## Готово! 🎉

**5 таблиц** готовы к использованию.  
**Следующий шаг**: `02-services-implementation.md`

