# Отчеты заказчика - Рейсы и контракты (анализ)

## Описание задачи
Реализовать API для отчета "Рейсы/Контракты" с анализом сравнения контрактных и разовых перевозок, статистикой эффективности.

## Frontend UI референс
- Компонент: `RouteContractsReport.vue`
- Фильтры: тип соглашения, статус, исполнитель, период
- Метрики: всего соглашений, контрактных рейсов, разовых рейсов, средняя стоимость
- Kanban-метрики: статистика по маршрутам  
- Графики: месячные тренды, распределение типов рейсов
- Таблица: детальная информация по соглашениям и рейсам

## Эндпоинты для реализации

### 1. GET `/api/reports/routes-contracts/analysis`
Получение анализа рейсов и контрактов

**Параметры запроса:**
```json
{
  "agreementType": "string (optional)", // contract, single
  "agreementStatus": "string (optional)", // active, completed, cancelled
  "executorId": "number (optional)",
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
      "agreementNumber": "string",
      "agreementType": "string", // contract, single
      "executorName": "string",
      "routeCount": "number",
      "totalCost": "number",
      "avgCostPerRoute": "number",
      "status": "string",
      "signedAt": "string",
      "validUntil": "string",
      "completedRoutes": "number",
      "efficiency": "number" // процент выполнения
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalAgreements": "number",
    "contractRoutes": "number",
    "singleRoutes": "number", 
    "avgContractCost": "number",
    "avgSingleCost": "number",
    "contractEfficiency": "number",
    "singleEfficiency": "number"
  }
}
```

### 2. GET `/api/reports/routes-contracts/metrics`
Получение метрик для Kanban-карточек

**Ответ:**
```json
{
  "routeMetrics": {
    "totalRoutes": "number",
    "avgDistance": "number",
    "totalDistance": "number",
    "avgDuration": "number"
  },
  "contractMetrics": {
    "activeContracts": "number",
    "totalContractValue": "number", 
    "avgContractDuration": "number",
    "contractUtilization": "number"
  },
  "performanceMetrics": {
    "onTimeDelivery": "number", // процент
    "costEfficiency": "number", // процент
    "customerSatisfaction": "number" // процент
  }
}
```

### 3. GET `/api/reports/routes-contracts/charts`
Получение данных для графиков

**Ответ:**
```json
{
  "monthlyTrends": {
    "months": ["string"],
    "contractRoutes": ["number"],
    "singleRoutes": ["number"],
    "contractCosts": ["number"],
    "singleCosts": ["number"]
  },
  "routeTypeDistribution": {
    "labels": ["Контрактные", "Разовые"],
    "values": ["number", "number"],
    "costs": ["number", "number"]
  },
  "executorComparison": {
    "executors": ["string"],
    "contractRoutes": ["number"],
    "singleRoutes": ["number"],
    "efficiency": ["number"]
  }
}
```

### 4. GET `/api/reports/routes-contracts/export`
Экспорт анализа рейсов и контрактов в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

## SQL запросы (базовая логика)

```sql
-- Основной запрос для анализа соглашений и рейсов
WITH agreement_stats AS (
    SELECT 
        a.id,
        a.agreement_number as agreementNumber,
        CASE 
            WHEN a.agreement_type = 'CONTRACT' THEN 'contract'
            ELSE 'single'
        END as agreementType,
        o.organization_name as executorName,
        a.status,
        a.signed_at as signedAt,
        a.valid_until as validUntil,
        COUNT(t.id) as routeCount,
        SUM(tc.cost) as totalCost,
        AVG(tc.cost) as avgCostPerRoute,
        COUNT(CASE WHEN t.status = 'COMPLETED' THEN 1 END) as completedRoutes,
        CASE 
            WHEN COUNT(t.id) > 0 
            THEN ROUND((COUNT(CASE WHEN t.status = 'COMPLETED' THEN 1 END)::float / COUNT(t.id)) * 100, 1)
            ELSE 0 
        END as efficiency
    FROM agreement.agreement a
        LEFT JOIN user.organization o ON a.executor_organization_id = o.id
        LEFT JOIN applications.transportation t ON a.id = t.agreement_id
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    WHERE 
        ($organizationId IS NULL OR a.customer_organization_id = $organizationId)
        AND ($agreementType IS NULL OR 
            CASE 
                WHEN a.agreement_type = 'CONTRACT' THEN 'contract'
                ELSE 'single'
            END = $agreementType)
        AND ($agreementStatus IS NULL OR a.status = $agreementStatus)
        AND ($executorId IS NULL OR a.executor_organization_id = $executorId)
        AND ($dateFrom IS NULL OR a.signed_at >= $dateFrom)
        AND ($dateTo IS NULL OR a.signed_at <= $dateTo)
    GROUP BY a.id, a.agreement_number, a.agreement_type, o.organization_name, 
             a.status, a.signed_at, a.valid_until
)
SELECT * FROM agreement_stats
ORDER BY signedAt DESC;
```

```sql
-- Запрос для метрик маршрутов
SELECT 
    COUNT(t.id) as totalRoutes,
    ROUND(AVG(
        COALESCE(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        )
    ), 0) as avgDistance,
    SUM(
        COALESCE(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        )
    ) as totalDistance,
    ROUND(AVG(
        CASE 
            WHEN t.completed_at IS NOT NULL AND t.started_at IS NOT NULL
            THEN EXTRACT(DAYS FROM (t.completed_at - t.started_at))
            ELSE NULL
        END
    ), 1) as avgDuration
FROM applications.transportation t
    LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id 
        AND cl_from.loading_type = 'LOADING'
    LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id 
        AND cl_to.loading_type = 'UNLOADING'
WHERE t.organization_id = $organizationId;
```

```sql
-- Запрос для месячных трендов
SELECT 
    TO_CHAR(a.signed_at, 'YYYY-MM') as month,
    COUNT(CASE WHEN a.agreement_type = 'CONTRACT' THEN t.id END) as contractRoutes,
    COUNT(CASE WHEN a.agreement_type != 'CONTRACT' THEN t.id END) as singleRoutes,
    SUM(CASE WHEN a.agreement_type = 'CONTRACT' THEN tc.cost ELSE 0 END) as contractCosts,
    SUM(CASE WHEN a.agreement_type != 'CONTRACT' THEN tc.cost ELSE 0 END) as singleCosts
FROM agreement.agreement a
    LEFT JOIN applications.transportation t ON a.id = t.agreement_id
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
WHERE a.customer_organization_id = $organizationId
    AND a.signed_at >= $dateFrom
    AND a.signed_at <= $dateTo
GROUP BY TO_CHAR(a.signed_at, 'YYYY-MM')
ORDER BY month;
```

## Основные таблицы БД
- `agreement.agreement` - соглашения и контракты
- `applications.transportation` - перевозки связанные с соглашениями
- `applications.transportation_cost` - стоимость перевозок
- `applications.cargo_loading` - точки погрузки/выгрузки для расчета расстояний
- `user.organization` - информация об организациях-исполнителях

## Техническая реализация

1. Создать контроллер `RoutesContractsReportController`
2. Создать сервис `RoutesContractsReportService`
3. Создать DTO для запросов и ответов
4. Реализовать расчет эффективности соглашений
5. Добавить агрегацию данных по месяцам
6. Реализовать сравнительный анализ типов соглашений
7. Добавить кэширование метрик (Redis)
8. Реализовать экспорт в Excel с графиками

## Дополнительные расчеты

### Эффективность контрактов
```sql
-- Расчет KPI эффективности
WITH contract_kpi AS (
    SELECT 
        a.id,
        COUNT(t.id) as planned_routes,
        COUNT(CASE WHEN t.status = 'COMPLETED' THEN 1 END) as completed_routes,
        COUNT(CASE WHEN t.completed_at <= t.planned_delivery_date THEN 1 END) as ontime_routes,
        AVG(tc.cost) as avg_route_cost,
        SUM(tc.cost) as total_cost
    FROM agreement.agreement a
        LEFT JOIN applications.transportation t ON a.id = t.agreement_id
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    WHERE a.agreement_type = 'CONTRACT'
    GROUP BY a.id
)
SELECT 
    *,
    CASE 
        WHEN planned_routes > 0 
        THEN ROUND((completed_routes::float / planned_routes) * 100, 1)
        ELSE 0 
    END as completion_rate,
    CASE 
        WHEN completed_routes > 0 
        THEN ROUND((ontime_routes::float / completed_routes) * 100, 1)
        ELSE 0 
    END as ontime_rate
FROM contract_kpi;
```

### Сравнение стоимости
```sql
-- Сравнение средней стоимости контрактных и разовых перевозок
SELECT 
    a.agreement_type,
    COUNT(t.id) as route_count,
    AVG(tc.cost) as avg_cost,
    MIN(tc.cost) as min_cost,
    MAX(tc.cost) as max_cost,
    STDDEV(tc.cost) as cost_deviation
FROM agreement.agreement a
    LEFT JOIN applications.transportation t ON a.id = t.agreement_id
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
WHERE a.customer_organization_id = $organizationId
GROUP BY a.agreement_type;
```

## Критерии приемки

- ✅ API корректно разделяет контрактные и разовые перевозки  
- ✅ Метрики эффективности рассчитываются точно
- ✅ Сравнительный анализ типов соглашений работает
- ✅ Месячные тренды отображают динамику
- ✅ Фильтрация по всем параметрам функционирует
- ✅ Экспорт в Excel включает графики и метрики
- ✅ Производительность оптимизирована для больших данных
- ✅ API работает только для авторизованных пользователей организации
- ✅ Расчет расстояний через PostGIS выполняется корректно