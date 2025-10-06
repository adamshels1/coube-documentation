# Отчеты заказчика - Финансовый отчет и платежи

## Описание задачи
Реализовать API для финансового отчета с анализом платежей, счетов, дебиторской задолженности и cash flow.

## Frontend UI референс
- Компонент: `FinancialPaymentReport.vue`
- Статус: В разработке (placeholder компонент)
- Планируемые фильтры: период, тип платежа, статус, контрагент
- Планируемые метрики: общий оборот, просроченная задолженность, средний срок оплаты
- Планируемые графики: динамика платежей, структура расходов, cash flow

## Эндпоинты для реализации

### 1. GET `/api/reports/financial/payments`
Получение данных по платежам и финансам

**Параметры запроса:**
```json
{
  "paymentType": "string (optional)", // incoming, outgoing
  "paymentStatus": "string (optional)", // paid, pending, overdue
  "contractorId": "number (optional)",
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
      "paymentNumber": "string",
      "invoiceNumber": "string",
      "contractorName": "string",
      "amount": "number",
      "paymentType": "string", // incoming, outgoing
      "paymentStatus": "string", // paid, pending, overdue
      "dueDate": "string",
      "paidAt": "string",
      "overdueDays": "number",
      "transportationNumber": "string",
      "paymentMethod": "string" // bank_transfer, cash, card
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalTurnover": "number",
    "incomingTotal": "number",
    "outgoingTotal": "number",
    "overdueAmount": "number",
    "avgPaymentDays": "number",
    "cashFlow": "number" // incoming - outgoing
  }
}
```

### 2. GET `/api/reports/financial/dashboard`
Получение данных для финансового дашборда

**Ответ:**
```json
{
  "metrics": {
    "totalRevenue": "number",
    "totalExpenses": "number", 
    "netProfit": "number",
    "profitMargin": "number", // процент
    "overdueDebt": "number",
    "avgPaymentTime": "number", // дни
    "activeInvoices": "number",
    "paidInvoices": "number"
  },
  "cashFlow": {
    "currentBalance": "number",
    "projectedIncome": "number", // ожидаемые поступления
    "projectedExpenses": "number", // планируемые расходы
    "projectedBalance": "number"
  },
  "paymentStructure": {
    "bankTransfers": "number",
    "cashPayments": "number", 
    "cardPayments": "number",
    "digitalWallet": "number"
  }
}
```

### 3. GET `/api/reports/financial/charts`
Получение данных для финансовых графиков

**Ответ:**
```json
{
  "paymentDynamics": {
    "months": ["string"],
    "incoming": ["number"],
    "outgoing": ["number"],
    "netFlow": ["number"]
  },
  "expenseStructure": {
    "categories": ["Топливо", "Зарплата", "Техобслуживание", "Прочее"],
    "amounts": ["number"],
    "percentages": ["number"]
  },
  "debtAging": {
    "ranges": ["0-30 дней", "31-60 дней", "61-90 дней", "90+ дней"],
    "amounts": ["number"],
    "counts": ["number"]
  },
  "profitability": {
    "months": ["string"],
    "revenue": ["number"],
    "costs": ["number"],
    "profit": ["number"],
    "margin": ["number"] // процент
  }
}
```

### 4. GET `/api/reports/financial/export`
Экспорт финансового отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл с несколькими листами

## SQL запросы (базовая логика)

**Потребуется создать новые таблицы для финансового модуля:**

### Основной запрос для платежей
```sql
-- Запрос для анализа платежей
SELECT 
    p.id,
    p.payment_number as paymentNumber,
    i.invoice_number as invoiceNumber,
    o.organization_name as contractorName,
    p.amount,
    p.payment_type as paymentType,
    p.payment_status as paymentStatus,
    p.due_date as dueDate,
    p.paid_at as paidAt,
    CASE 
        WHEN p.payment_status = 'overdue' AND p.due_date < NOW()
        THEN EXTRACT(DAYS FROM (NOW() - p.due_date))
        ELSE 0
    END as overdueDays,
    tc.transportation_number as transportationNumber,
    p.payment_method as paymentMethod
FROM finance.payment p
    LEFT JOIN finance.invoice i ON p.invoice_id = i.id
    LEFT JOIN user.organization o ON i.contractor_organization_id = o.id
    LEFT JOIN applications.transportation_cost tc ON i.transportation_cost_id = tc.id
WHERE 
    ($organizationId IS NULL OR i.organization_id = $organizationId)
    AND ($paymentType IS NULL OR p.payment_type = $paymentType)
    AND ($paymentStatus IS NULL OR p.payment_status = $paymentStatus)
    AND ($contractorId IS NULL OR i.contractor_organization_id = $contractorId)
    AND ($dateFrom IS NULL OR p.created_at >= $dateFrom)
    AND ($dateTo IS NULL OR p.created_at <= $dateTo)
ORDER BY p.created_at DESC;
```

### Запрос для cash flow анализа
```sql
-- Анализ денежного потока
WITH cash_flow AS (
    SELECT 
        DATE_TRUNC('month', p.paid_at) as month,
        SUM(CASE WHEN p.payment_type = 'incoming' THEN p.amount ELSE 0 END) as incoming,
        SUM(CASE WHEN p.payment_type = 'outgoing' THEN p.amount ELSE 0 END) as outgoing,
        SUM(CASE WHEN p.payment_type = 'incoming' THEN p.amount ELSE -p.amount END) as net_flow
    FROM finance.payment p
    WHERE p.organization_id = $organizationId
        AND p.payment_status = 'paid'
        AND p.paid_at >= $dateFrom
        AND p.paid_at <= $dateTo
    GROUP BY DATE_TRUNC('month', p.paid_at)
)
SELECT 
    TO_CHAR(month, 'YYYY-MM') as month,
    incoming,
    outgoing,
    net_flow,
    SUM(net_flow) OVER (ORDER BY month) as running_balance
FROM cash_flow
ORDER BY month;
```

### Анализ просроченной задолженности
```sql
-- Анализ дебиторской задолженности по срокам
SELECT 
    CASE 
        WHEN EXTRACT(DAYS FROM (NOW() - p.due_date)) <= 30 THEN '0-30 дней'
        WHEN EXTRACT(DAYS FROM (NOW() - p.due_date)) <= 60 THEN '31-60 дней'
        WHEN EXTRACT(DAYS FROM (NOW() - p.due_date)) <= 90 THEN '61-90 дней'
        ELSE '90+ дней'
    END as aging_range,
    COUNT(*) as invoice_count,
    SUM(p.amount) as total_amount,
    AVG(EXTRACT(DAYS FROM (NOW() - p.due_date))) as avg_overdue_days
FROM finance.payment p
    LEFT JOIN finance.invoice i ON p.invoice_id = i.id
WHERE i.organization_id = $organizationId
    AND p.payment_status IN ('pending', 'overdue')
    AND p.due_date < NOW()
GROUP BY aging_range
ORDER BY 
    CASE aging_range
        WHEN '0-30 дней' THEN 1
        WHEN '31-60 дней' THEN 2  
        WHEN '61-90 дней' THEN 3
        ELSE 4
    END;
```

## Необходимые таблицы БД

### `finance.invoice` - счета
```sql
CREATE TABLE finance.invoice (
    id BIGSERIAL PRIMARY KEY,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    organization_id BIGINT REFERENCES user.organization(id),
    contractor_organization_id BIGINT REFERENCES user.organization(id),
    transportation_cost_id BIGINT REFERENCES applications.transportation_cost(id),
    amount DECIMAL(15,2) NOT NULL,
    tax_amount DECIMAL(15,2) DEFAULT 0,
    total_amount DECIMAL(15,2) NOT NULL,
    invoice_date DATE NOT NULL,
    due_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'draft', -- draft, sent, paid, cancelled
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `finance.payment` - платежи
```sql
CREATE TABLE finance.payment (
    id BIGSERIAL PRIMARY KEY,
    payment_number VARCHAR(50) UNIQUE NOT NULL,
    invoice_id BIGINT REFERENCES finance.invoice(id),
    organization_id BIGINT REFERENCES user.organization(id),
    amount DECIMAL(15,2) NOT NULL,
    payment_type VARCHAR(20) NOT NULL, -- incoming, outgoing
    payment_status VARCHAR(20) DEFAULT 'pending', -- pending, paid, overdue, cancelled
    payment_method VARCHAR(30), -- bank_transfer, cash, card, digital_wallet
    due_date DATE NOT NULL,
    paid_at TIMESTAMP,
    reference_number VARCHAR(100),
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `finance.expense_category` - категории расходов
```sql
CREATE TABLE finance.expense_category (
    id BIGSERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    category_code VARCHAR(20) UNIQUE NOT NULL,
    parent_category_id BIGINT REFERENCES finance.expense_category(id),
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `finance.expense` - расходы
```sql
CREATE TABLE finance.expense (
    id BIGSERIAL PRIMARY KEY,
    expense_number VARCHAR(50) UNIQUE NOT NULL,
    organization_id BIGINT REFERENCES user.organization(id),
    category_id BIGINT REFERENCES finance.expense_category(id),
    transportation_id BIGINT REFERENCES applications.transportation(id),
    amount DECIMAL(15,2) NOT NULL,
    expense_date DATE NOT NULL,
    description TEXT,
    receipt_path VARCHAR(500),
    created_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

## Техническая реализация

1. Создать схему `finance` в БД
2. Создать новый модуль `finance` в backend  
3. Создать контроллер `FinancialReportController`
4. Создать сервис `FinancialReportService`
5. Создать DTO для финансовых данных
6. Реализовать расчет КПИ и метрик
7. Добавить автоматическое определение просроченных платежей
8. Реализовать экспорт в Excel с несколькими листами
9. Добавить интеграцию с банковскими API для импорта выписок
10. Настроить автоматические уведомления о просроченных платежах

## Критерии приемки

- ✅ API корректно рассчитывает финансовые метрики
- ✅ Cash flow анализ показывает точные данные
- ✅ Просроченная задолженность группируется по срокам
- ✅ Структура расходов анализируется по категориям  
- ✅ Прибыльность рассчитывается с учетом всех доходов/расходов
- ✅ Экспорт содержит детализированные финансовые отчеты
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для больших объемов транзакций
- ✅ Автоматическое обновление статусов просроченных платежей