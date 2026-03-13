# Отчеты заказчика - Комиссии платформы

## Описание задачи
Реализовать API для отчета "Комиссии платформы" с анализом подписок, тарифных планов, начислений комиссий и биллинга.

## Frontend UI референс
- Компонент: `PlatformCommissionReport.vue`
- Фильтры: тип подписки, период, статус платежа
- Метрики: текущий тариф, использование лимитов, общая сумма комиссий
- Сравнение тарифов: базовый, стандарт, премиум, корпоративный
- Графики: динамика использования, структура комиссий, прогноз расходов

## Эндпоинты для реализации

### 1. GET `/api/reports/platform-commission/billing`
Получение данных по комиссиям и биллингу

**Параметры запроса:**
```json
{
  "subscriptionType": "string (optional)", // basic, standard, premium, enterprise
  "billingPeriod": "string (optional)", // monthly, quarterly, yearly
  "paymentStatus": "string (optional)", // paid, pending, overdue
  "dateFrom": "string (optional)", // ISO date
  "dateTo": "string (optional)", // ISO date
  "page": "number (default: 0)",
  "size": "number (default: 20)"
}
```

**Ответ:**
```json
{
  "data": [
    {
      "id": "number",
      "billingNumber": "string",
      "subscriptionType": "string",
      "billingPeriod": "string",
      "amount": "number",
      "commissionRate": "number", // процент
      "transactionCount": "number",
      "volumeUsed": "number", // тонны или рейсы
      "volumeLimit": "number",
      "utilizationRate": "number", // процент использования
      "billingDate": "string",
      "dueDate": "string",
      "paymentStatus": "string",
      "paidAt": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalCommissions": "number",
    "avgCommissionRate": "number",
    "totalTransactions": "number",
    "currentSubscription": "string",
    "subscriptionCost": "number",
    "nextBillingDate": "string"
  }
}
```

### 2. GET `/api/reports/platform-commission/subscription`
Получение информации о текущей подписке

**Ответ:**
```json
{
  "currentSubscription": {
    "type": "string", // basic, standard, premium, enterprise
    "name": "string",
    "monthlyFee": "number",
    "commissionRate": "number",
    "transactionLimit": "number",
    "volumeLimit": "number", // тонны в месяц
    "supportLevel": "string",
    "features": ["string"],
    "startDate": "string",
    "endDate": "string",
    "autoRenewal": "boolean"
  },
  "usage": {
    "currentPeriodStart": "string",
    "currentPeriodEnd": "string",
    "transactionsUsed": "number",
    "volumeUsed": "number",
    "commissionsPaid": "number",
    "utilizationRate": "number"
  },
  "nextBilling": {
    "date": "string",
    "amount": "number",
    "description": "string"
  }
}
```

### 3. GET `/api/reports/platform-commission/plans`
Получение доступных тарифных планов

**Ответ:**
```json
{
  "plans": [
    {
      "type": "string",
      "name": "string",
      "monthlyFee": "number",
      "yearlyFee": "number",
      "commissionRate": "number",
      "transactionLimit": "number",
      "volumeLimit": "number",
      "features": ["string"],
      "supportLevel": "string",
      "recommended": "boolean",
      "popular": "boolean"
    }
  ],
  "comparison": {
    "features": [
      {
        "name": "string",
        "basic": "boolean",
        "standard": "boolean", 
        "premium": "boolean",
        "enterprise": "boolean"
      }
    ]
  }
}
```

### 4. GET `/api/reports/platform-commission/charts`
Получение данных для графиков комиссий

**Ответ:**
```json
{
  "usageDynamics": {
    "months": ["string"],
    "transactions": ["number"],
    "volume": ["number"],
    "commissions": ["number"],
    "limits": ["number"]
  },
  "commissionStructure": {
    "categories": ["Базовая подписка", "Комиссия за транзакции", "Дополнительные услуги"],
    "amounts": ["number"],
    "percentages": ["number"]
  },
  "forecastExpenses": {
    "months": ["string"],
    "projected": ["number"],
    "actual": ["number"],
    "savings": ["number"] // экономия при годовой подписке
  },
  "planComparison": {
    "plans": ["string"],
    "costs": ["number"],
    "transactions": ["number"],
    "features": ["number"]
  }
}
```

### 5. GET `/api/reports/platform-commission/export`
Экспорт отчета по комиссиям в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

## SQL запросы (базовая логика)

### Основной запрос для биллинга
```sql
SELECT 
    b.id,
    b.billing_number as billingNumber,
    s.subscription_type as subscriptionType,
    b.billing_period as billingPeriod,
    b.amount,
    sp.commission_rate as commissionRate,
    bu.transaction_count as transactionCount,
    bu.volume_used as volumeUsed,
    sp.volume_limit as volumeLimit,
    CASE 
        WHEN sp.volume_limit > 0 
        THEN ROUND((bu.volume_used::float / sp.volume_limit) * 100, 1)
        ELSE 0 
    END as utilizationRate,
    b.billing_date as billingDate,
    b.due_date as dueDate,
    b.payment_status as paymentStatus,
    b.paid_at as paidAt
FROM billing.billing b
    LEFT JOIN billing.subscription s ON b.subscription_id = s.id
    LEFT JOIN billing.subscription_plan sp ON s.plan_id = sp.id
    LEFT JOIN billing.billing_usage bu ON b.id = bu.billing_id
WHERE s.organization_id = $organizationId
    AND ($subscriptionType IS NULL OR s.subscription_type = $subscriptionType)
    AND ($billingPeriod IS NULL OR b.billing_period = $billingPeriod)
    AND ($paymentStatus IS NULL OR b.payment_status = $paymentStatus)
    AND ($dateFrom IS NULL OR b.billing_date >= $dateFrom)
    AND ($dateTo IS NULL OR b.billing_date <= $dateTo)
ORDER BY b.billing_date DESC;
```

### Запрос для текущей подписки
```sql
SELECT 
    s.subscription_type as type,
    sp.plan_name as name,
    sp.monthly_fee as monthlyFee,
    sp.commission_rate as commissionRate,
    sp.transaction_limit as transactionLimit,
    sp.volume_limit as volumeLimit,
    sp.support_level as supportLevel,
    sp.features,
    s.start_date as startDate,
    s.end_date as endDate,
    s.auto_renewal as autoRenewal,
    -- Использование за текущий период
    COALESCE(SUM(bu.transaction_count), 0) as transactionsUsed,
    COALESCE(SUM(bu.volume_used), 0) as volumeUsed,
    COALESCE(SUM(b.amount), 0) as commissionsPaid
FROM billing.subscription s
    LEFT JOIN billing.subscription_plan sp ON s.plan_id = sp.id
    LEFT JOIN billing.billing b ON s.id = b.subscription_id
        AND b.billing_date >= DATE_TRUNC('month', NOW())
    LEFT JOIN billing.billing_usage bu ON b.id = bu.billing_id
WHERE s.organization_id = $organizationId
    AND s.status = 'active'
GROUP BY s.id, s.subscription_type, sp.plan_name, sp.monthly_fee, 
         sp.commission_rate, sp.transaction_limit, sp.volume_limit,
         sp.support_level, sp.features, s.start_date, s.end_date, s.auto_renewal;
```

## Необходимые таблицы БД

### `billing.subscription_plan` - тарифные планы
```sql
CREATE TABLE billing.subscription_plan (
    id BIGSERIAL PRIMARY KEY,
    plan_code VARCHAR(20) UNIQUE NOT NULL, -- basic, standard, premium, enterprise
    plan_name VARCHAR(100) NOT NULL,
    monthly_fee DECIMAL(10,2) NOT NULL,
    yearly_fee DECIMAL(10,2),
    commission_rate DECIMAL(5,2) NOT NULL, -- процент комиссии
    transaction_limit INTEGER DEFAULT 0, -- 0 = unlimited
    volume_limit DECIMAL(10,2) DEFAULT 0, -- тонны в месяц, 0 = unlimited
    support_level VARCHAR(20) DEFAULT 'basic', -- basic, priority, premium
    features JSONB, -- список функций плана
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `billing.subscription` - подписки организаций
```sql
CREATE TABLE billing.subscription (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT REFERENCES user.organization(id),
    plan_id BIGINT REFERENCES billing.subscription_plan(id),
    subscription_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'active', -- active, suspended, cancelled
    start_date DATE NOT NULL,
    end_date DATE,
    auto_renewal BOOLEAN DEFAULT true,
    billing_period VARCHAR(10) DEFAULT 'monthly', -- monthly, yearly
    next_billing_date DATE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `billing.billing` - счета за использование
```sql
CREATE TABLE billing.billing (
    id BIGSERIAL PRIMARY KEY,
    billing_number VARCHAR(50) UNIQUE NOT NULL,
    subscription_id BIGINT REFERENCES billing.subscription(id),
    billing_period VARCHAR(10) NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    base_amount DECIMAL(15,2) NOT NULL, -- базовая подписка
    commission_amount DECIMAL(15,2) DEFAULT 0, -- комиссии за транзакции
    additional_amount DECIMAL(15,2) DEFAULT 0, -- дополнительные услуги
    total_amount DECIMAL(15,2) NOT NULL,
    billing_date DATE NOT NULL,
    due_date DATE NOT NULL,
    payment_status VARCHAR(20) DEFAULT 'pending',
    paid_at TIMESTAMP,
    payment_method VARCHAR(30),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `billing.billing_usage` - использование ресурсов
```sql
CREATE TABLE billing.billing_usage (
    id BIGSERIAL PRIMARY KEY,
    billing_id BIGINT REFERENCES billing.billing(id),
    transaction_count INTEGER DEFAULT 0,
    volume_used DECIMAL(10,2) DEFAULT 0, -- тонны
    api_calls INTEGER DEFAULT 0,
    storage_used DECIMAL(10,2) DEFAULT 0, -- GB
    additional_services JSONB, -- дополнительные услуги
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `billing.transaction_log` - лог транзакций для комиссий
```sql
CREATE TABLE billing.transaction_log (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT REFERENCES user.organization(id),
    transportation_id BIGINT REFERENCES applications.transportation(id),
    transaction_type VARCHAR(30) NOT NULL, -- transportation, invoice, payment
    amount DECIMAL(15,2) NOT NULL,
    commission_rate DECIMAL(5,2),
    commission_amount DECIMAL(15,2),
    billing_period VARCHAR(7), -- YYYY-MM
    created_at TIMESTAMP DEFAULT NOW()
);
```

## Техническая реализация

1. Создать схему `billing` в БД
2. Создать новый модуль `billing` в backend
3. Создать контроллер `PlatformCommissionReportController`
4. Создать сервис `PlatformCommissionReportService`
5. Реализовать автоматический расчет комиссий при создании транзакций
6. Добавить систему автоматического биллинга
7. Создать планировщик для генерации ежемесячных счетов
8. Реализовать уведомления о приближении лимитов
9. Добавить возможность смены тарифного плана
10. Интегрировать с платежными системами

## Автоматизация биллинга

### Функция расчета комиссий
```sql
CREATE OR REPLACE FUNCTION calculate_commission(
    organization_id BIGINT,
    transaction_amount DECIMAL,
    transaction_type VARCHAR
) RETURNS DECIMAL AS $$
DECLARE
    commission_rate DECIMAL;
    commission_amount DECIMAL;
BEGIN
    -- Получаем текущую ставку комиссии для организации
    SELECT sp.commission_rate INTO commission_rate
    FROM billing.subscription s
        LEFT JOIN billing.subscription_plan sp ON s.plan_id = sp.id
    WHERE s.organization_id = organization_id
        AND s.status = 'active';
    
    IF commission_rate IS NULL THEN
        commission_rate := 3.0; -- базовая ставка по умолчанию
    END IF;
    
    commission_amount := (transaction_amount * commission_rate / 100);
    
    -- Логируем транзакцию
    INSERT INTO billing.transaction_log (
        organization_id, 
        transaction_type, 
        amount, 
        commission_rate, 
        commission_amount,
        billing_period
    ) VALUES (
        organization_id,
        transaction_type,
        transaction_amount,
        commission_rate,
        commission_amount,
        TO_CHAR(NOW(), 'YYYY-MM')
    );
    
    RETURN commission_amount;
END;
$$ LANGUAGE plpgsql;
```

### Процедура ежемесячного биллинга
```sql
CREATE OR REPLACE FUNCTION generate_monthly_billing()
RETURNS VOID AS $$
DECLARE
    sub_record RECORD;
    billing_amount DECIMAL;
    commission_total DECIMAL;
    usage_data RECORD;
BEGIN
    FOR sub_record IN 
        SELECT s.*, sp.monthly_fee, sp.commission_rate, sp.plan_name
        FROM billing.subscription s
            LEFT JOIN billing.subscription_plan sp ON s.plan_id = sp.id
        WHERE s.status = 'active'
            AND s.next_billing_date <= NOW()::DATE
    LOOP
        -- Рассчитываем использование за период
        SELECT 
            COUNT(*) as transaction_count,
            COALESCE(SUM(tl.amount), 0) as total_volume,
            COALESCE(SUM(tl.commission_amount), 0) as commission_total
        INTO usage_data
        FROM billing.transaction_log tl
        WHERE tl.organization_id = sub_record.organization_id
            AND tl.billing_period = TO_CHAR(NOW() - INTERVAL '1 month', 'YYYY-MM');
        
        -- Создаем счет
        billing_amount := sub_record.monthly_fee + usage_data.commission_total;
        
        INSERT INTO billing.billing (
            billing_number,
            subscription_id,
            billing_period,
            period_start,
            period_end,
            base_amount,
            commission_amount,
            total_amount,
            billing_date,
            due_date
        ) VALUES (
            'BILL-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || sub_record.organization_id,
            sub_record.id,
            'monthly',
            (NOW() - INTERVAL '1 month')::DATE,
            (NOW() - INTERVAL '1 day')::DATE,
            sub_record.monthly_fee,
            usage_data.commission_total,
            billing_amount,
            NOW()::DATE,
            (NOW() + INTERVAL '30 days')::DATE
        );
        
        -- Обновляем дату следующего биллинга
        UPDATE billing.subscription 
        SET next_billing_date = (NOW() + INTERVAL '1 month')::DATE
        WHERE id = sub_record.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## Критерии приемки

- ✅ API корректно отображает информацию о текущей подписке
- ✅ Расчет комиссий выполняется автоматически при транзакциях
- ✅ Сравнение тарифных планов работает корректно
- ✅ Отслеживание использования лимитов функционирует
- ✅ Ежемесячный автоматический биллинг настроен
- ✅ Уведомления о приближении лимитов отправляются
- ✅ Экспорт содержит детализированную информацию по биллингу
- ✅ API работает только для авторизованных пользователей
- ✅ Смена тарифного плана проходит без потери данных
- ✅ Интеграция с платежными системами работает стабильно