# Отчеты заказчика - Дебиторская задолженность

## Описание задачи
Реализовать API для отчета по дебиторской задолженности с анализом просроченных платежей, рисками и рекомендациями по взысканию.

## Frontend UI референс
- Компонент: `DebtorReport.vue`
- Статус: В разработке (placeholder компонент)
- Планируемые фильтры: контрагент, статус просрочки, сумма задолженности, период
- Планируемые метрики: общая дебиторка, просроченная задолженность, средний срок погашения
- Планируемые графики: структура задолженности, динамика погашения, риски по контрагентам

## Эндпоинты для реализации

### 1. GET `/api/reports/debtors/analysis`
Получение анализа дебиторской задолженности

**Параметры запроса:**
```json
{
  "debtorId": "number (optional)",
  "overdueStatus": "string (optional)", // current, overdue_30, overdue_60, overdue_90
  "minAmount": "number (optional)",
  "maxAmount": "number (optional)",
  "riskLevel": "string (optional)", // low, medium, high, critical
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
      "debtorName": "string",
      "debtorBin": "string",
      "totalDebt": "number",
      "overdueDebt": "number", 
      "currentDebt": "number",
      "maxOverdueDays": "number",
      "avgPaymentDays": "number",
      "riskLevel": "string", // low, medium, high, critical
      "riskScore": "number", // 0-100
      "activeInvoices": "number",
      "overdueInvoices": "number",
      "lastPaymentDate": "string",
      "creditLimit": "number",
      "paymentHistory": "string" // good, average, poor
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalDebtors": "number",
    "totalDebt": "number",
    "currentDebt": "number",
    "overdueDebt": "number",
    "criticalDebtors": "number",
    "avgPaymentTime": "number",
    "collectionRate": "number" // процент взыскания
  }
}
```

### 2. GET `/api/reports/debtors/aging`
Получение анализа старения задолженности

**Ответ:**
```json
{
  "agingAnalysis": [
    {
      "debtorName": "string",
      "current": "number", // 0-30 дней
      "overdue30": "number", // 31-60 дней  
      "overdue60": "number", // 61-90 дней
      "overdue90": "number", // 90+ дней
      "total": "number",
      "riskLevel": "string"
    }
  ],
  "agingSummary": {
    "current": "number",
    "overdue30": "number", 
    "overdue60": "number",
    "overdue90": "number",
    "total": "number",
    "overdue30Count": "number",
    "overdue60Count": "number", 
    "overdue90Count": "number"
  }
}
```

### 3. GET `/api/reports/debtors/risk-assessment`
Получение оценки рисков по дебиторам

**Ответ:**
```json
{
  "riskAnalysis": [
    {
      "debtorId": "number",
      "debtorName": "string",
      "riskScore": "number", // 0-100
      "riskLevel": "string",
      "riskFactors": [
        {
          "factor": "string", // payment_delay, amount_size, payment_frequency
          "weight": "number",
          "impact": "string" // positive, negative, neutral
        }
      ],
      "recommendations": ["string"],
      "creditLimit": "number",
      "suggestedLimit": "number"
    }
  ],
  "riskDistribution": {
    "low": "number",
    "medium": "number", 
    "high": "number",
    "critical": "number"
  }
}
```

### 4. GET `/api/reports/debtors/charts`
Получение данных для графиков дебиторки

**Ответ:**
```json
{
  "debtStructure": {
    "labels": ["Текущая", "30 дней", "60 дней", "90+ дней"],
    "amounts": ["number"],
    "colors": ["#10b981", "#f59e0b", "#ef4444", "#991b1b"]
  },
  "paymentDynamics": {
    "months": ["string"],
    "paid": ["number"],
    "overdue": ["number"],
    "collectionRate": ["number"]
  },
  "topDebtors": {
    "debtors": ["string"],
    "amounts": ["number"],
    "riskLevels": ["string"]
  },
  "riskTrends": {
    "months": ["string"],
    "lowRisk": ["number"],
    "mediumRisk": ["number"],
    "highRisk": ["number"],
    "criticalRisk": ["number"]
  }
}
```

### 5. GET `/api/reports/debtors/export`
Экспорт анализа дебиторской задолженности в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл с несколькими листами

## SQL запросы (базовая логика)

### Основной запрос для анализа дебиторов
```sql
WITH debtor_analysis AS (
    SELECT 
        o.id as debtorId,
        o.organization_name as debtorName,
        o.bin as debtorBin,
        SUM(p.amount) as totalDebt,
        SUM(CASE 
            WHEN p.due_date < NOW() AND p.payment_status != 'paid' 
            THEN p.amount ELSE 0 
        END) as overdueDebt,
        SUM(CASE 
            WHEN p.due_date >= NOW() AND p.payment_status != 'paid' 
            THEN p.amount ELSE 0 
        END) as currentDebt,
        MAX(CASE 
            WHEN p.due_date < NOW() AND p.payment_status != 'paid'
            THEN EXTRACT(DAYS FROM (NOW() - p.due_date))
            ELSE 0
        END) as maxOverdueDays,
        AVG(CASE 
            WHEN p.payment_status = 'paid' AND p.paid_at IS NOT NULL
            THEN EXTRACT(DAYS FROM (p.paid_at - p.created_at))
            ELSE NULL
        END) as avgPaymentDays,
        COUNT(CASE WHEN p.payment_status != 'paid' THEN 1 END) as activeInvoices,
        COUNT(CASE 
            WHEN p.due_date < NOW() AND p.payment_status != 'paid' 
            THEN 1 
        END) as overdueInvoices,
        MAX(p.paid_at) as lastPaymentDate,
        dc.credit_limit as creditLimit
    FROM user.organization o
        LEFT JOIN finance.invoice i ON o.id = i.contractor_organization_id
        LEFT JOIN finance.payment p ON i.id = p.invoice_id
        LEFT JOIN finance.debtor_credit dc ON o.id = dc.organization_id
    WHERE i.organization_id = $organizationId
        AND i.status != 'cancelled'
    GROUP BY o.id, o.organization_name, o.bin, dc.credit_limit
),
risk_assessment AS (
    SELECT 
        debtorId,
        CASE 
            WHEN maxOverdueDays > 90 OR (overdueDebt / NULLIF(totalDebt, 0)) > 0.5 THEN 'critical'
            WHEN maxOverdueDays > 60 OR (overdueDebt / NULLIF(totalDebt, 0)) > 0.3 THEN 'high'
            WHEN maxOverdueDays > 30 OR (overdueDebt / NULLIF(totalDebt, 0)) > 0.1 THEN 'medium'
            ELSE 'low'
        END as riskLevel,
        CASE 
            WHEN maxOverdueDays > 90 THEN 90
            WHEN maxOverdueDays > 60 THEN 70
            WHEN maxOverdueDays > 30 THEN 50
            ELSE 20
        END + 
        CASE 
            WHEN (overdueDebt / NULLIF(totalDebt, 0)) > 0.5 THEN 30
            WHEN (overdueDebt / NULLIF(totalDebt, 0)) > 0.3 THEN 20
            WHEN (overdueDebt / NULLIF(totalDebt, 0)) > 0.1 THEN 10
            ELSE 0
        END as riskScore,
        CASE 
            WHEN avgPaymentDays <= 30 THEN 'good'
            WHEN avgPaymentDays <= 60 THEN 'average'
            ELSE 'poor'
        END as paymentHistory
    FROM debtor_analysis
)
SELECT 
    da.*,
    ra.riskLevel,
    ra.riskScore,
    ra.paymentHistory
FROM debtor_analysis da
    LEFT JOIN risk_assessment ra ON da.debtorId = ra.debtorId
WHERE 
    ($debtorId IS NULL OR da.debtorId = $debtorId)
    AND ($overdueStatus IS NULL OR 
        CASE $overdueStatus
            WHEN 'current' THEN da.currentDebt > 0
            WHEN 'overdue_30' THEN da.maxOverdueDays BETWEEN 1 AND 30
            WHEN 'overdue_60' THEN da.maxOverdueDays BETWEEN 31 AND 60
            WHEN 'overdue_90' THEN da.maxOverdueDays > 90
        END)
    AND ($minAmount IS NULL OR da.totalDebt >= $minAmount)
    AND ($maxAmount IS NULL OR da.totalDebt <= $maxAmount)
    AND ($riskLevel IS NULL OR ra.riskLevel = $riskLevel)
ORDER BY da.overdueDebt DESC, da.totalDebt DESC;
```

### Анализ старения задолженности
```sql
SELECT 
    o.organization_name as debtorName,
    SUM(CASE 
        WHEN p.due_date >= NOW() - INTERVAL '30 days' AND p.payment_status != 'paid'
        THEN p.amount ELSE 0 
    END) as current,
    SUM(CASE 
        WHEN p.due_date < NOW() - INTERVAL '30 days' 
        AND p.due_date >= NOW() - INTERVAL '60 days'
        AND p.payment_status != 'paid'
        THEN p.amount ELSE 0 
    END) as overdue30,
    SUM(CASE 
        WHEN p.due_date < NOW() - INTERVAL '60 days'
        AND p.due_date >= NOW() - INTERVAL '90 days' 
        AND p.payment_status != 'paid'
        THEN p.amount ELSE 0 
    END) as overdue60,
    SUM(CASE 
        WHEN p.due_date < NOW() - INTERVAL '90 days'
        AND p.payment_status != 'paid'
        THEN p.amount ELSE 0 
    END) as overdue90,
    SUM(CASE WHEN p.payment_status != 'paid' THEN p.amount ELSE 0 END) as total
FROM user.organization o
    LEFT JOIN finance.invoice i ON o.id = i.contractor_organization_id
    LEFT JOIN finance.payment p ON i.id = p.invoice_id
WHERE i.organization_id = $organizationId
    AND i.status != 'cancelled'
GROUP BY o.id, o.organization_name
HAVING SUM(CASE WHEN p.payment_status != 'paid' THEN p.amount ELSE 0 END) > 0
ORDER BY total DESC;
```

## Необходимые таблицы БД

### `finance.debtor_credit` - кредитные лимиты дебиторов
```sql
CREATE TABLE finance.debtor_credit (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT REFERENCES user.organization(id),
    debtor_organization_id BIGINT REFERENCES user.organization(id),
    credit_limit DECIMAL(15,2) DEFAULT 0,
    current_exposure DECIMAL(15,2) DEFAULT 0,
    risk_level VARCHAR(20) DEFAULT 'medium', -- low, medium, high, critical
    credit_rating VARCHAR(10), -- AAA, AA, A, BBB, BB, B, CCC, CC, C, D
    last_review_date DATE,
    next_review_date DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `finance.payment_reminder` - напоминания о платежах
```sql
CREATE TABLE finance.payment_reminder (
    id BIGSERIAL PRIMARY KEY,
    payment_id BIGINT REFERENCES finance.payment(id),
    reminder_type VARCHAR(20) NOT NULL, -- email, sms, call, letter
    reminder_level VARCHAR(20) NOT NULL, -- first, second, final, legal
    sent_at TIMESTAMP,
    response_received BOOLEAN DEFAULT false,
    notes TEXT,
    created_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `finance.debtor_communication` - история коммуникаций
```sql
CREATE TABLE finance.debtor_communication (
    id BIGSERIAL PRIMARY KEY,
    debtor_organization_id BIGINT REFERENCES user.organization(id),
    organization_id BIGINT REFERENCES user.organization(id),
    communication_type VARCHAR(30) NOT NULL, -- email, phone, meeting, letter
    subject VARCHAR(255),
    content TEXT,
    outcome VARCHAR(100), -- promise_to_pay, dispute, no_response, partial_payment
    follow_up_date DATE,
    created_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

## Техническая реализация

1. Расширить схему `finance` новыми таблицами
2. Создать контроллер `DebtorReportController` 
3. Создать сервис `DebtorReportService`
4. Реализовать алгоритм оценки рисков дебиторов
5. Добавить автоматический расчет кредитных лимитов
6. Создать систему автоматических напоминаний
7. Реализовать трекинг коммуникаций с дебиторами
8. Добавить интеграцию с кредитными бюро для проверки рейтингов
9. Настроить автоматические отчеты по просроченной задолженности

## Алгоритмы оценки рисков

### Расчет риск-скора дебитора
```sql
CREATE OR REPLACE FUNCTION calculate_debtor_risk_score(debtor_id BIGINT) 
RETURNS INTEGER AS $$
DECLARE
    overdue_factor INTEGER := 0;
    amount_factor INTEGER := 0;
    history_factor INTEGER := 0;
    frequency_factor INTEGER := 0;
    total_score INTEGER := 0;
BEGIN
    -- Фактор просрочки (0-40 баллов)
    SELECT CASE 
        WHEN MAX(EXTRACT(DAYS FROM (NOW() - p.due_date))) > 90 THEN 40
        WHEN MAX(EXTRACT(DAYS FROM (NOW() - p.due_date))) > 60 THEN 30
        WHEN MAX(EXTRACT(DAYS FROM (NOW() - p.due_date))) > 30 THEN 20
        WHEN MAX(EXTRACT(DAYS FROM (NOW() - p.due_date))) > 0 THEN 10
        ELSE 0
    END INTO overdue_factor
    FROM finance.payment p
        LEFT JOIN finance.invoice i ON p.invoice_id = i.id
    WHERE i.contractor_organization_id = debtor_id
        AND p.payment_status != 'paid';
    
    -- Фактор суммы задолженности (0-30 баллов)
    SELECT CASE 
        WHEN SUM(p.amount) > 10000000 THEN 30 -- более 10 млн
        WHEN SUM(p.amount) > 5000000 THEN 20  -- более 5 млн
        WHEN SUM(p.amount) > 1000000 THEN 10  -- более 1 млн
        ELSE 0
    END INTO amount_factor
    FROM finance.payment p
        LEFT JOIN finance.invoice i ON p.invoice_id = i.id
    WHERE i.contractor_organization_id = debtor_id
        AND p.payment_status != 'paid';
    
    -- Фактор истории платежей (0-20 баллов)
    SELECT CASE 
        WHEN AVG(EXTRACT(DAYS FROM (p.paid_at - p.created_at))) > 60 THEN 20
        WHEN AVG(EXTRACT(DAYS FROM (p.paid_at - p.created_at))) > 45 THEN 15
        WHEN AVG(EXTRACT(DAYS FROM (p.paid_at - p.created_at))) > 30 THEN 10
        ELSE 0
    END INTO history_factor
    FROM finance.payment p
        LEFT JOIN finance.invoice i ON p.invoice_id = i.id
    WHERE i.contractor_organization_id = debtor_id
        AND p.payment_status = 'paid'
        AND p.paid_at >= NOW() - INTERVAL '1 year';
    
    -- Фактор частоты просрочек (0-10 баллов)
    SELECT CASE 
        WHEN (COUNT(CASE WHEN p.due_date < p.paid_at THEN 1 END)::float / COUNT(*)) > 0.5 THEN 10
        WHEN (COUNT(CASE WHEN p.due_date < p.paid_at THEN 1 END)::float / COUNT(*)) > 0.3 THEN 7
        WHEN (COUNT(CASE WHEN p.due_date < p.paid_at THEN 1 END)::float / COUNT(*)) > 0.1 THEN 3
        ELSE 0
    END INTO frequency_factor
    FROM finance.payment p
        LEFT JOIN finance.invoice i ON p.invoice_id = i.id
    WHERE i.contractor_organization_id = debtor_id
        AND p.payment_status = 'paid'
        AND p.paid_at >= NOW() - INTERVAL '1 year';
    
    total_score := overdue_factor + amount_factor + history_factor + frequency_factor;
    
    RETURN LEAST(total_score, 100); -- Максимум 100 баллов
END;
$$ LANGUAGE plpgsql;
```

## Критерии приемки

- ✅ API корректно рассчитывает дебиторскую задолженность по срокам
- ✅ Риск-скор дебиторов вычисляется точно по алгоритму
- ✅ Анализ старения задолженности группирует по периодам
- ✅ Система автоматически определяет критических дебиторов
- ✅ Рекомендации по взысканию формируются на основе риск-анализа
- ✅ Экспорт содержит детализированную информацию по каждому дебитору
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для больших объемов дебиторки
- ✅ Автоматические напоминания настраиваются по уровням просрочки