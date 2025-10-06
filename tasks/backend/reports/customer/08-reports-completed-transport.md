# Отчеты заказчика - Выполненные перевозки

## Описание задачи
Реализовать API для отчета "Выполненные перевозки" с детальным анализом завершенных транспортировок, КПИ производительности и качества выполнения.

## Frontend UI референс
- Компонент: `CompletedTransportReport.vue` (существующий)
- Фильтры: период, исполнитель, статус, тип груза, маршрут
- Метрики: всего перевозок, общая стоимость, средняя длительность, процент выполнения в срок
- Графики: динамика выполнения, распределение по исполнителям, анализ производительности
- Таблица: детальная информация по каждой завершенной перевозке

## Эндпоинты для реализации

### 1. GET `/api/reports/completed-transport/list`
Получение списка выполненных перевозок

**Параметры запроса:**
```json
{
  "executorId": "number (optional)",
  "cargoType": "string (optional)",
  "transportStatus": "string (optional)", // completed, completed_late, completed_with_issues
  "routeFrom": "string (optional)",
  "routeTo": "string (optional)",
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
      "cargoName": "string",
      "cargoWeight": "number",
      "routeFrom": "string", 
      "routeTo": "string",
      "distance": "number",
      "cost": "number",
      "plannedStartDate": "string",
      "actualStartDate": "string",
      "plannedDeliveryDate": "string",
      "actualDeliveryDate": "string",
      "durationPlanned": "number", // часы
      "durationActual": "number", // часы
      "delayHours": "number",
      "onTimeDelivery": "boolean",
      "qualityRating": "number", // 1-5
      "completionStatus": "string", // completed, completed_late, completed_with_issues
      "issues": ["string"], // массив проблем если были
      "documents": {
        "contractSigned": "boolean",
        "invoiceGenerated": "boolean", 
        "actSigned": "boolean",
        "paymentReceived": "boolean"
      }
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalTransports": "number",
    "totalCost": "number",
    "totalDistance": "number",
    "avgDuration": "number",
    "onTimeRate": "number", // процент
    "avgQualityRating": "number",
    "completedWithIssues": "number"
  }
}
```

### 2. GET `/api/reports/completed-transport/performance`
Получение КПИ производительности

**Ответ:**
```json
{
  "kpi": {
    "deliveryPerformance": {
      "onTimeDeliveries": "number",
      "lateDeliveries": "number", 
      "onTimePercentage": "number",
      "avgDelayHours": "number"
    },
    "qualityMetrics": {
      "avgRating": "number",
      "ratingsDistribution": {
        "excellent": "number", // 5 звезд
        "good": "number",      // 4 звезды
        "average": "number",   // 3 звезды
        "poor": "number",      // 2 звезды
        "terrible": "number"   // 1 звезда
      },
      "issueTypes": [
        {
          "type": "string",
          "count": "number",
          "percentage": "number"
        }
      ]
    },
    "efficiency": {
      "avgCostPerKm": "number",
      "avgCostPerTon": "number",
      "avgSpeedKmh": "number",
      "utilization": "number" // процент загрузки
    },
    "documentation": {
      "contractsSignedRate": "number",
      "invoicesGeneratedRate": "number",
      "actsSignedRate": "number", 
      "paymentsReceivedRate": "number"
    }
  }
}
```

### 3. GET `/api/reports/completed-transport/executors`
Получение анализа по исполнителям

**Ответ:**
```json
{
  "executors": [
    {
      "executorId": "number",
      "executorName": "string",
      "totalTransports": "number",
      "totalCost": "number",
      "avgCost": "number",
      "onTimeRate": "number",
      "avgQualityRating": "number",
      "avgDelay": "number", // часы
      "issuesCount": "number",
      "efficiency": "number", // общая оценка 0-100
      "rank": "number" // место в рейтинге
    }
  ],
  "comparison": {
    "bestPerformer": {
      "executorName": "string",
      "onTimeRate": "number",
      "qualityRating": "number"
    },
    "mostCostEffective": {
      "executorName": "string", 
      "avgCostPerKm": "number"
    },
    "mostReliable": {
      "executorName": "string",
      "issueRate": "number"
    }
  }
}
```

### 4. GET `/api/reports/completed-transport/charts`
Получение данных для графиков

**Ответ:**
```json
{
  "completionDynamics": {
    "months": ["string"],
    "completed": ["number"],
    "onTime": ["number"],
    "late": ["number"],
    "withIssues": ["number"]
  },
  "executorPerformance": {
    "executors": ["string"],
    "onTimeRates": ["number"],
    "qualityRatings": ["number"],
    "costs": ["number"]
  },
  "cargoTypeAnalysis": {
    "cargoTypes": ["string"],
    "avgDuration": ["number"],
    "avgCost": ["number"],
    "onTimeRate": ["number"]
  },
  "routeEfficiency": {
    "routes": ["string"],
    "avgDuration": ["number"],
    "avgCost": ["number"],
    "frequency": ["number"]
  }
}
```

### 5. GET `/api/reports/completed-transport/export`
Экспорт отчета о выполненных перевозках в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

## SQL запросы (базовая логика)

### Основной запрос для выполненных перевозок
```sql
WITH transport_details AS (
    SELECT 
        t.id,
        tc.transportation_number as transportationNumber,
        eo.organization_name as executorName,
        t.cargo_name as cargoName,
        t.cargo_weight as cargoWeight,
        cl_from.address as routeFrom,
        cl_to.address as routeTo,
        COALESCE(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        ) as distance,
        tc.cost,
        t.planned_start_date as plannedStartDate,
        t.actual_start_date as actualStartDate,
        t.planned_delivery_date as plannedDeliveryDate,
        t.actual_delivery_date as actualDeliveryDate,
        EXTRACT(EPOCH FROM (t.planned_delivery_date - t.planned_start_date))/3600 as durationPlanned,
        EXTRACT(EPOCH FROM (t.actual_delivery_date - t.actual_start_date))/3600 as durationActual,
        CASE 
            WHEN t.actual_delivery_date > t.planned_delivery_date 
            THEN EXTRACT(EPOCH FROM (t.actual_delivery_date - t.planned_delivery_date))/3600
            ELSE 0
        END as delayHours,
        (t.actual_delivery_date <= t.planned_delivery_date) as onTimeDelivery,
        COALESCE(tr.rating, 0) as qualityRating,
        CASE 
            WHEN t.actual_delivery_date <= t.planned_delivery_date AND ti.issue_count = 0 THEN 'completed'
            WHEN t.actual_delivery_date > t.planned_delivery_date AND ti.issue_count = 0 THEN 'completed_late'
            ELSE 'completed_with_issues'
        END as completionStatus,
        ti.issues,
        -- Статус документов
        (a.id IS NOT NULL AND a.status = 'SIGNED') as contractSigned,
        (i.id IS NOT NULL) as invoiceGenerated,
        (ta.id IS NOT NULL AND ta.status = 'SIGNED') as actSigned,
        (p.id IS NOT NULL AND p.payment_status = 'paid') as paymentReceived
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN user.organization eo ON tc.executor_organization_id = eo.id
        LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id 
            AND cl_from.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id 
            AND cl_to.loading_type = 'UNLOADING'
        LEFT JOIN (
            -- Рейтинг качества
            SELECT transportation_id, AVG(rating) as rating
            FROM transportation.quality_rating 
            GROUP BY transportation_id
        ) tr ON t.id = tr.transportation_id
        LEFT JOIN (
            -- Проблемы и их количество
            SELECT 
                transportation_id, 
                COUNT(*) as issue_count,
                ARRAY_AGG(issue_type) as issues
            FROM transportation.transport_issue 
            GROUP BY transportation_id
        ) ti ON t.id = ti.transportation_id
        LEFT JOIN agreement.agreement a ON t.agreement_id = a.id
        LEFT JOIN invoice.invoice i ON t.id = i.transportation_id
        LEFT JOIN invoice.transportation_act ta ON t.id = ta.transportation_id
        LEFT JOIN finance.payment p ON i.id = p.invoice_id
    WHERE t.status = 'COMPLETED'
        AND t.organization_id = $organizationId
        AND ($executorId IS NULL OR tc.executor_organization_id = $executorId)
        AND ($cargoType IS NULL OR t.cargo_type_id IN (
            SELECT id FROM dictionaries.cargo_type WHERE cargo_type_name = $cargoType
        ))
        AND ($transportStatus IS NULL OR 
            CASE 
                WHEN t.actual_delivery_date <= t.planned_delivery_date AND COALESCE(ti.issue_count, 0) = 0 THEN 'completed'
                WHEN t.actual_delivery_date > t.planned_delivery_date AND COALESCE(ti.issue_count, 0) = 0 THEN 'completed_late'
                ELSE 'completed_with_issues'
            END = $transportStatus)
        AND ($routeFrom IS NULL OR cl_from.address ILIKE '%' || $routeFrom || '%')
        AND ($routeTo IS NULL OR cl_to.address ILIKE '%' || $routeTo || '%')
        AND ($dateFrom IS NULL OR t.actual_delivery_date >= $dateFrom)
        AND ($dateTo IS NULL OR t.actual_delivery_date <= $dateTo)
)
SELECT * FROM transport_details
ORDER BY actualDeliveryDate DESC;
```

### Запрос для КПИ производительности
```sql
WITH performance_metrics AS (
    SELECT 
        COUNT(*) as totalTransports,
        COUNT(CASE WHEN t.actual_delivery_date <= t.planned_delivery_date THEN 1 END) as onTimeDeliveries,
        COUNT(CASE WHEN t.actual_delivery_date > t.planned_delivery_date THEN 1 END) as lateDeliveries,
        AVG(CASE 
            WHEN t.actual_delivery_date > t.planned_delivery_date 
            THEN EXTRACT(EPOCH FROM (t.actual_delivery_date - t.planned_delivery_date))/3600
            ELSE 0
        END) as avgDelayHours,
        AVG(COALESCE(qr.avg_rating, 0)) as avgQualityRating,
        AVG(tc.cost / NULLIF(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        )) as avgCostPerKm,
        AVG(tc.cost / NULLIF(t.cargo_weight, 0)) as avgCostPerTon
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id 
            AND cl_from.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id 
            AND cl_to.loading_type = 'UNLOADING'
        LEFT JOIN (
            SELECT transportation_id, AVG(rating) as avg_rating
            FROM transportation.quality_rating 
            GROUP BY transportation_id
        ) qr ON t.id = qr.transportation_id
    WHERE t.status = 'COMPLETED'
        AND t.organization_id = $organizationId
        AND t.actual_delivery_date >= $dateFrom
        AND t.actual_delivery_date <= $dateTo
)
SELECT 
    *,
    ROUND((onTimeDeliveries::float / totalTransports) * 100, 1) as onTimePercentage
FROM performance_metrics;
```

### Анализ по исполнителям
```sql
SELECT 
    eo.id as executorId,
    eo.organization_name as executorName,
    COUNT(t.id) as totalTransports,
    SUM(tc.cost) as totalCost,
    AVG(tc.cost) as avgCost,
    ROUND((COUNT(CASE WHEN t.actual_delivery_date <= t.planned_delivery_date THEN 1 END)::float / COUNT(t.id)) * 100, 1) as onTimeRate,
    ROUND(AVG(COALESCE(qr.avg_rating, 0)), 2) as avgQualityRating,
    AVG(CASE 
        WHEN t.actual_delivery_date > t.planned_delivery_date 
        THEN EXTRACT(EPOCH FROM (t.actual_delivery_date - t.planned_delivery_date))/3600
        ELSE 0
    END) as avgDelay,
    COUNT(ti.transportation_id) as issuesCount,
    -- Общая оценка эффективности (0-100)
    ROUND(
        (COUNT(CASE WHEN t.actual_delivery_date <= t.planned_delivery_date THEN 1 END)::float / COUNT(t.id)) * 40 + -- 40% за пунктуальность
        (AVG(COALESCE(qr.avg_rating, 0)) / 5) * 30 + -- 30% за качество
        GREATEST(0, (1 - COUNT(ti.transportation_id)::float / COUNT(t.id))) * 30 -- 30% за отсутствие проблем
    , 0) as efficiency,
    RANK() OVER (ORDER BY 
        (COUNT(CASE WHEN t.actual_delivery_date <= t.planned_delivery_date THEN 1 END)::float / COUNT(t.id)) * 0.4 + 
        (AVG(COALESCE(qr.avg_rating, 0)) / 5) * 0.3 + 
        GREATEST(0, (1 - COUNT(ti.transportation_id)::float / COUNT(t.id))) * 0.3 DESC
    ) as rank
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization eo ON tc.executor_organization_id = eo.id
    LEFT JOIN (
        SELECT transportation_id, AVG(rating) as avg_rating
        FROM transportation.quality_rating 
        GROUP BY transportation_id
    ) qr ON t.id = qr.transportation_id
    LEFT JOIN transportation.transport_issue ti ON t.id = ti.transportation_id
WHERE t.status = 'COMPLETED'
    AND t.organization_id = $organizationId
    AND t.actual_delivery_date >= $dateFrom
    AND t.actual_delivery_date <= $dateTo
GROUP BY eo.id, eo.organization_name
HAVING COUNT(t.id) > 0
ORDER BY efficiency DESC;
```

## Необходимые таблицы БД

### `transportation.quality_rating` - рейтинги качества
```sql
CREATE TABLE transportation.quality_rating (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT REFERENCES applications.transportation(id),
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    rating_criteria JSONB, -- детализация оценки
    rated_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `transportation.transport_issue` - проблемы при перевозке
```sql
CREATE TABLE transportation.transport_issue (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT REFERENCES applications.transportation(id),
    issue_type VARCHAR(50) NOT NULL, -- delay, damage, route_change, communication, documentation
    issue_description TEXT,
    severity VARCHAR(20) DEFAULT 'medium', -- low, medium, high, critical
    resolved BOOLEAN DEFAULT false,
    resolution_description TEXT,
    reported_by BIGINT REFERENCES user.user(id),
    resolved_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);
```

## Техническая реализация

1. Создать схему `transportation` для новых таблиц
2. Создать контроллер `CompletedTransportReportController`
3. Создать сервис `CompletedTransportReportService`
4. Реализовать расчет КПИ производительности
5. Добавить систему рейтингов качества
6. Создать механизм отслеживания проблем
7. Реализовать ранжирование исполнителей
8. Добавить экспорт с детализированными КПИ

## Критерии приемки

- ✅ API корректно возвращает данные о завершенных перевозках
- ✅ КПИ производительности рассчитываются точно
- ✅ Ранжирование исполнителей работает корректно
- ✅ Отслеживание проблем и их классификация функционирует
- ✅ Система рейтингов качества интегрирована
- ✅ Анализ эффективности маршрутов выполняется
- ✅ Экспорт содержит все КПИ и метрики
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для больших объемов данных