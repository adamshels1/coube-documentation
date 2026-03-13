# Отчеты заказчика - SLA и дедлайны

## Описание задачи
Реализовать API для отчета "SLA / Дедлайны" с мониторингом соблюдения сервисных соглашений, анализом просрочек и прогнозированием рисков.

## Frontend UI референс
- Компонент: `SLAPerformanceReport.vue` (существующий)
- Фильтры: исполнитель, тип SLA, статус выполнения, период
- Метрики: общий SLA, процент соблюдения, средняя просрочка, критические нарушения
- Графики: динамика SLA, топ нарушителей, прогноз рисков
- Уведомления: предупреждения о приближающихся дедлайнах

## Эндпоинты для реализации

### 1. GET `/api/reports/sla/performance`
Получение данных по выполнению SLA

**Параметры запроса:**
```json
{
  "executorId": "number (optional)",
  "slaType": "string (optional)", // delivery, response, resolution, documentation
  "complianceStatus": "string (optional)", // compliant, violated, at_risk
  "severityLevel": "string (optional)", // low, medium, high, critical
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
      "transportationNumber": "string",
      "executorName": "string",
      "slaType": "string",
      "slaDescription": "string",
      "agreedSlaHours": "number",
      "actualHours": "number",
      "complianceStatus": "string", // compliant, violated, at_risk
      "violationHours": "number", // просрочка в часах
      "severityLevel": "string",
      "deadline": "string",
      "completedAt": "string",
      "riskScore": "number", // 0-100 риск нарушения
      "contractualPenalty": "number", // штраф за нарушение
      "mitigationActions": ["string"], // действия по устранению
      "escalationLevel": "number" // уровень эскалации 0-3
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalSlas": "number",
    "compliantSlas": "number",
    "violatedSlas": "number",
    "atRiskSlas": "number",
    "complianceRate": "number", // процент
    "avgViolationHours": "number",
    "totalPenalties": "number"
  }
}
```

### 2. GET `/api/reports/sla/dashboard`
Получение SLA дашборда

**Ответ:**
```json
{
  "overview": {
    "overallSlaScore": "number", // 0-100
    "complianceRate": "number", // процент
    "avgResponseTime": "number", // часы
    "criticalViolations": "number",
    "upcomingDeadlines": "number" // в ближайшие 24 часа
  },
  "slaTypes": [
    {
      "type": "string",
      "name": "string",
      "complianceRate": "number",
      "avgTime": "number",
      "violations": "number",
      "target": "number" // целевой показатель
    }
  ],
  "riskAlerts": [
    {
      "transportationId": "number",
      "transportationNumber": "string",
      "riskLevel": "string",
      "hoursToDeadline": "number",
      "probability": "number", // вероятность нарушения %
      "recommendedActions": ["string"]
    }
  ],
  "trends": {
    "improving": "number", // количество улучшающихся SLA
    "declining": "number", // количество ухудшающихся SLA
    "stable": "number"
  }
}
```

### 3. GET `/api/reports/sla/violations`
Получение детального анализа нарушений SLA

**Ответ:**
```json
{
  "violations": [
    {
      "id": "number",
      "transportationNumber": "string",
      "executorName": "string",
      "slaType": "string",
      "violationHours": "number",
      "violationCost": "number", // стоимость нарушения
      "rootCause": "string",
      "impactLevel": "string", // low, medium, high
      "correctionActions": ["string"],
      "recurrence": "boolean", // повторное нарушение
      "clientNotified": "boolean",
      "escalatedAt": "string"
    }
  ],
  "violationAnalysis": {
    "topViolators": [
      {
        "executorName": "string",
        "violationCount": "number",
        "violationRate": "number", // процент
        "totalCost": "number"
      }
    ],
    "rootCauses": [
      {
        "cause": "string",
        "frequency": "number",
        "percentage": "number"
      }
    ],
    "timePatterns": {
      "hoursOfDay": ["number"], // нарушения по часам
      "daysOfWeek": ["number"], // нарушения по дням недели
      "months": ["number"] // нарушения по месяцам
    }
  }
}
```

### 4. GET `/api/reports/sla/predictions`
Получение прогнозов и предиктивной аналитики

**Ответ:**
```json
{
  "activeSlas": [
    {
      "transportationId": "number",
      "transportationNumber": "string",
      "executorName": "string",
      "deadline": "string",
      "currentProgress": "number", // процент выполнения
      "riskScore": "number", // 0-100
      "predictedCompletion": "string",
      "riskFactors": [
        {
          "factor": "string",
          "impact": "number", // вес фактора
          "description": "string"
        }
      ],
      "recommendations": ["string"]
    }
  ],
  "predictions": {
    "nextWeekViolations": "number", // прогноз нарушений на неделю
    "nextMonthTrend": "string", // improving, stable, declining
    "seasonalRisks": [
      {
        "period": "string",
        "riskLevel": "string",
        "description": "string"
      }
    ]
  }
}
```

### 5. GET `/api/reports/sla/charts`
Получение данных для графиков SLA

**Ответ:**
```json
{
  "complianceTrend": {
    "dates": ["string"],
    "complianceRate": ["number"],
    "violationCount": ["number"],
    "target": ["number"] // целевой уровень
  },
  "executorPerformance": {
    "executors": ["string"],
    "complianceRates": ["number"],
    "avgResponseTimes": ["number"],
    "violationCounts": ["number"]
  },
  "slaTypeBreakdown": {
    "types": ["string"],
    "compliance": ["number"],
    "violations": ["number"],
    "avgTimes": ["number"]
  },
  "riskDistribution": {
    "levels": ["Низкий", "Средний", "Высокий", "Критический"],
    "counts": ["number"],
    "percentages": ["number"]
  }
}
```

### 6. GET `/api/reports/sla/export`
Экспорт SLA отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл с несколькими листами

## SQL запросы (базовая логика)

### Основной запрос для SLA метрик
```sql
WITH sla_metrics AS (
    SELECT 
        t.id,
        tc.transportation_number as transportationNumber,
        eo.organization_name as executorName,
        sla.sla_type as slaType,
        sla.description as slaDescription,
        sla.target_hours as agreedSlaHours,
        CASE sla.sla_type
            WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
            WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
            WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
            ELSE 0
        END as actualHours,
        sla.target_hours - 
        CASE sla.sla_type
            WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
            WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
            WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
            ELSE 0
        END as remainingHours,
        CASE 
            WHEN sla.target_hours > 
                CASE sla.sla_type
                    WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
                    WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
                    WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
                    ELSE 0
                END 
            THEN 'compliant'
            WHEN sla.target_hours - 
                CASE sla.sla_type
                    WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
                    WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
                    WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
                    ELSE 0
                END BETWEEN -24 AND 0
            THEN 'at_risk'
            ELSE 'violated'
        END as complianceStatus,
        GREATEST(0, 
            CASE sla.sla_type
                WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
                WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
                WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
                ELSE 0
            END - sla.target_hours
        ) as violationHours,
        CASE 
            WHEN GREATEST(0, 
                CASE sla.sla_type
                    WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
                    WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
                    WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
                    ELSE 0
                END - sla.target_hours
            ) > 72 THEN 'critical'
            WHEN GREATEST(0, 
                CASE sla.sla_type
                    WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
                    WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
                    WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
                    ELSE 0
                END - sla.target_hours
            ) > 24 THEN 'high'
            WHEN GREATEST(0, 
                CASE sla.sla_type
                    WHEN 'delivery' THEN EXTRACT(EPOCH FROM (COALESCE(t.actual_delivery_date, NOW()) - t.created_at))/3600
                    WHEN 'response' THEN EXTRACT(EPOCH FROM (COALESCE(t.accepted_at, NOW()) - t.created_at))/3600
                    WHEN 'documentation' THEN EXTRACT(EPOCH FROM (COALESCE(ta.signed_at, NOW()) - t.completed_at))/3600
                    ELSE 0
                END - sla.target_hours
            ) > 0 THEN 'medium'
            ELSE 'low'
        END as severityLevel,
        t.created_at + INTERVAL '1 hour' * sla.target_hours as deadline,
        CASE sla.sla_type
            WHEN 'delivery' THEN t.actual_delivery_date
            WHEN 'response' THEN t.accepted_at
            WHEN 'documentation' THEN ta.signed_at
            ELSE NULL
        END as completedAt,
        sla.penalty_amount as contractualPenalty
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN user.organization eo ON tc.executor_organization_id = eo.id
        LEFT JOIN invoice.transportation_act ta ON t.id = ta.transportation_id
        CROSS JOIN sla.sla_definition sla
    WHERE t.organization_id = $organizationId
        AND ($executorId IS NULL OR tc.executor_organization_id = $executorId)
        AND ($slaType IS NULL OR sla.sla_type = $slaType)
        AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
        AND ($dateTo IS NULL OR t.created_at <= $dateTo)
),
risk_calculation AS (
    SELECT 
        *,
        CASE 
            WHEN complianceStatus = 'violated' THEN 100
            WHEN complianceStatus = 'at_risk' THEN 
                GREATEST(50, 50 + (violationHours / 24.0) * 50)
            ELSE LEAST(50, (actualHours / agreedSlaHours) * 50)
        END as riskScore
    FROM sla_metrics
)
SELECT * FROM risk_calculation
WHERE ($complianceStatus IS NULL OR complianceStatus = $complianceStatus)
    AND ($severityLevel IS NULL OR severityLevel = $severityLevel)
ORDER BY riskScore DESC, deadline ASC;
```

### Запрос для прогнозирования рисков
```sql
WITH current_transports AS (
    SELECT 
        t.id,
        tc.transportation_number,
        eo.organization_name as executorName,
        t.created_at + INTERVAL '1 hour' * sla.target_hours as deadline,
        EXTRACT(EPOCH FROM (t.created_at + INTERVAL '1 hour' * sla.target_hours - NOW()))/3600 as hoursToDeadline,
        -- Расчет прогресса выполнения
        CASE 
            WHEN t.status = 'COMPLETED' THEN 100
            WHEN t.status = 'IN_PROGRESS' THEN 
                CASE 
                    WHEN t.actual_start_date IS NOT NULL 
                    THEN LEAST(90, (EXTRACT(EPOCH FROM (NOW() - t.actual_start_date))/3600 / 
                                   NULLIF(EXTRACT(EPOCH FROM (t.planned_delivery_date - t.actual_start_date))/3600, 0)) * 90)
                    ELSE 10
                END
            WHEN t.status = 'ACCEPTED' THEN 30
            ELSE 5
        END as currentProgress,
        -- Факторы риска
        CASE 
            WHEN eh.avg_delay > 24 THEN 20 ELSE 0 
        END + 
        CASE 
            WHEN EXTRACT(DOW FROM NOW()) IN (0, 6) THEN 10 ELSE 0 -- выходные
        END +
        CASE 
            WHEN t.cargo_type_id IN (SELECT id FROM dictionaries.cargo_type WHERE is_hazardous = true) THEN 15 ELSE 0
        END as riskFactorScore
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN user.organization eo ON tc.executor_organization_id = eo.id
        CROSS JOIN sla.sla_definition sla
        LEFT JOIN (
            -- История задержек исполнителя
            SELECT 
                tc.executor_organization_id,
                AVG(CASE 
                    WHEN t.actual_delivery_date > t.planned_delivery_date 
                    THEN EXTRACT(EPOCH FROM (t.actual_delivery_date - t.planned_delivery_date))/3600
                    ELSE 0
                END) as avg_delay
            FROM applications.transportation t
                LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
            WHERE t.status = 'COMPLETED'
                AND t.actual_delivery_date >= NOW() - INTERVAL '3 months'
            GROUP BY tc.executor_organization_id
        ) eh ON tc.executor_organization_id = eh.executor_organization_id
    WHERE t.status NOT IN ('COMPLETED', 'CANCELLED')
        AND sla.sla_type = 'delivery'
        AND t.organization_id = $organizationId
)
SELECT 
    *,
    LEAST(100, GREATEST(0, 
        (100 - currentProgress) * 0.6 + 
        riskFactorScore * 0.3 + 
        CASE 
            WHEN hoursToDeadline < 24 THEN 30
            WHEN hoursToDeadline < 48 THEN 20
            WHEN hoursToDeadline < 72 THEN 10
            ELSE 0
        END * 0.1
    )) as riskScore,
    ROUND((1 - currentProgress/100.0) * hoursToDeadline + 
          (riskFactorScore/100.0) * 24, 1) as predictedDelayHours
FROM current_transports
WHERE hoursToDeadline > 0
ORDER BY riskScore DESC;
```

## Необходимые таблицы БД

### `sla.sla_definition` - определения SLA
```sql
CREATE SCHEMA IF NOT EXISTS sla;

CREATE TABLE sla.sla_definition (
    id BIGSERIAL PRIMARY KEY,
    sla_type VARCHAR(30) NOT NULL, -- delivery, response, resolution, documentation
    description TEXT NOT NULL,
    target_hours INTEGER NOT NULL,
    penalty_amount DECIMAL(15,2) DEFAULT 0,
    escalation_hours INTEGER, -- через сколько часов эскалировать
    is_critical BOOLEAN DEFAULT false,
    applies_to VARCHAR(20) DEFAULT 'all', -- all, contracts, single_orders
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `sla.sla_violation` - нарушения SLA
```sql
CREATE TABLE sla.sla_violation (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT REFERENCES applications.transportation(id),
    sla_definition_id BIGINT REFERENCES sla.sla_definition(id),
    violation_hours DECIMAL(8,2) NOT NULL,
    severity_level VARCHAR(20) NOT NULL,
    root_cause VARCHAR(100),
    impact_assessment TEXT,
    penalty_applied DECIMAL(15,2) DEFAULT 0,
    client_notified BOOLEAN DEFAULT false,
    escalation_level INTEGER DEFAULT 0,
    corrective_actions TEXT,
    resolved BOOLEAN DEFAULT false,
    detected_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);
```

### `sla.escalation_rule` - правила эскалации
```sql
CREATE TABLE sla.escalation_rule (
    id BIGSERIAL PRIMARY KEY,
    sla_definition_id BIGINT REFERENCES sla.sla_definition(id),
    escalation_level INTEGER NOT NULL,
    trigger_hours INTEGER NOT NULL, -- через сколько часов срабатывает
    action_type VARCHAR(30) NOT NULL, -- email, sms, call, auto_reassign
    recipients JSONB, -- список получателей уведомлений
    auto_actions JSONB, -- автоматические действия
    is_active BOOLEAN DEFAULT true
);
```

### `sla.performance_metric` - метрики производительности SLA
```sql
CREATE TABLE sla.performance_metric (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT REFERENCES user.organization(id),
    executor_organization_id BIGINT REFERENCES user.organization(id),
    metric_date DATE NOT NULL,
    sla_type VARCHAR(30) NOT NULL,
    total_count INTEGER DEFAULT 0,
    compliant_count INTEGER DEFAULT 0,
    violated_count INTEGER DEFAULT 0,
    avg_completion_hours DECIMAL(8,2),
    avg_violation_hours DECIMAL(8,2),
    compliance_rate DECIMAL(5,2), -- процент
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(organization_id, executor_organization_id, metric_date, sla_type)
);
```

## Техническая реализация

1. Создать схему `sla` в БД
2. Создать контроллер `SLAReportController`
3. Создать сервис `SLAReportService`
4. Реализовать систему мониторинга SLA в реальном времени
5. Добавить автоматическую эскалацию нарушений
6. Создать предиктивную модель для прогнозирования рисков
7. Реализовать уведомления о приближающихся дедлайнах
8. Добавить автоматический расчет штрафов

## Автоматизация SLA мониторинга

### Функция проверки SLA
```sql
CREATE OR REPLACE FUNCTION check_sla_compliance()
RETURNS VOID AS $$
DECLARE
    transport_record RECORD;
    violation_record RECORD;
BEGIN
    -- Проверяем активные перевозки на нарушения SLA
    FOR transport_record IN 
        SELECT t.*, tc.executor_organization_id
        FROM applications.transportation t
            LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        WHERE t.status NOT IN ('COMPLETED', 'CANCELLED')
    LOOP
        -- Проверяем каждый тип SLA
        FOR violation_record IN
            SELECT 
                sla.*,
                CASE sla.sla_type
                    WHEN 'delivery' THEN t.created_at + INTERVAL '1 hour' * sla.target_hours
                    WHEN 'response' THEN t.created_at + INTERVAL '1 hour' * sla.target_hours
                    ELSE t.created_at + INTERVAL '1 hour' * sla.target_hours
                END as deadline
            FROM sla.sla_definition sla
            WHERE NOT EXISTS (
                SELECT 1 FROM sla.sla_violation sv 
                WHERE sv.transportation_id = transport_record.id 
                    AND sv.sla_definition_id = sla.id
            )
        LOOP
            IF NOW() > violation_record.deadline THEN
                -- Создаем запись о нарушении
                INSERT INTO sla.sla_violation (
                    transportation_id,
                    sla_definition_id,
                    violation_hours,
                    severity_level,
                    penalty_applied
                ) VALUES (
                    transport_record.id,
                    violation_record.id,
                    EXTRACT(EPOCH FROM (NOW() - violation_record.deadline))/3600,
                    CASE 
                        WHEN EXTRACT(EPOCH FROM (NOW() - violation_record.deadline))/3600 > 72 THEN 'critical'
                        WHEN EXTRACT(EPOCH FROM (NOW() - violation_record.deadline))/3600 > 24 THEN 'high'
                        WHEN EXTRACT(EPOCH FROM (NOW() - violation_record.deadline))/3600 > 0 THEN 'medium'
                        ELSE 'low'
                    END,
                    violation_record.penalty_amount
                );
            END IF;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## Критерии приемки

- ✅ API корректно отслеживает все типы SLA
- ✅ Автоматическое обнаружение нарушений работает в реальном времени
- ✅ Система эскалации активируется по установленным правилам
- ✅ Прогнозирование рисков показывает точные результаты
- ✅ Уведомления о дедлайнах отправляются своевременно
- ✅ Расчет штрафов за нарушения выполняется автоматически
- ✅ Анализ корневых причин нарушений функционирует
- ✅ Экспорт содержит все SLA метрики и нарушения
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для мониторинга больших объемов