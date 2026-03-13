# Отчеты перевозчика - Кол-во контрактов, заявки по контракту и без контракта

## Описание задачи
Реализовать API для отчета "Кол-во контрактов, заявки по контракту и без контракта" - отчет по анализу контрактов и заявок для перевозчика.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `04-reports-routes-contracts.md`, но с фокусом на контракты перевозчика.

## Frontend UI референс
- Компонент: `ExecutorContractsAnalysisReport.vue`
- Фильтры: номер контракта, заказчик, наличие контракта, период
- Таблица: номер контракта, заказчик, количество заявок, количество рейсов, контракт (да/нет)
- Метрики: общее количество контрактов, общее количество заявок, заявок без контракта
- Графики: диаграмма (контрактные vs разовые), динамика по месяцам, топ заказчиков

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/contracts-analysis`
Получение данных по анализу контрактов

**Параметры запроса:**
```json
{
  "contractId": "number (optional)",
  "customerId": "number (optional)",
  "hasContract": "boolean (optional)",
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
      "contractId": "number",
      "contractNumber": "string",
      "customerName": "string",
      "totalApplications": "number",
      "completedRoutes": "number",
      "hasContract": "boolean",
      "contractStatus": "string", // active, expired, draft
      "contractStartDate": "string",
      "contractEndDate": "string",
      "totalValue": "number",
      "currency": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalContracts": "number",
    "totalApplications": "number",
    "contractApplications": "number",
    "nonContractApplications": "number",
    "contractPercentage": "number",
    "totalValue": "number"
  }
}
```

### 2. GET `/api/reports/executor/contracts-analysis/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/contracts-analysis/statistics`
Получение статистики по контрактам

**Параметры:**
```json
{
  "period": "string", // month, quarter, year
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)",
  "groupBy": "string" // customer, contract_type, status
}
```

**Ответ:**
```json
{
  "timeline": [
    {
      "period": "2024-01",
      "contractApplications": "number",
      "nonContractApplications": "number",
      "totalApplications": "number",
      "contractPercentage": "number",
      "totalValue": "number"
    }
  ],
  "byCustomer": [
    {
      "customerId": "number",
      "customerName": "string",
      "totalContracts": "number",
      "totalApplications": "number",
      "contractValue": "number",
      "loyaltyRate": "number"
    }
  ],
  "contractTypes": [
    {
      "type": "string",
      "count": "number",
      "totalValue": "number",
      "averageValue": "number"
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по анализу контрактов
WITH contract_data AS (
    -- Данные по контрактам
    SELECT
        agr.id as contractId,
        'AGR-' || agr.id::text as contractNumber,
        o.organization_name as customerName,
        COUNT(t.id) as totalApplications,
        COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as completedRoutes,
        true as hasContract,
        agr.status as contractStatus,
        agr.created_at as contractStartDate,
        agr.agreement_end_date as contractEndDate,
        -- Расчет общей стоимости по контракту (упрощенно)
        COALESCE(SUM(tc.cost), 0) as totalValue,
        'KZT' as currency
    FROM applications.agreement agr
        LEFT JOIN applications.agreement_executor age ON agr.id = age.agreement_id
        LEFT JOIN user.organization o ON agr.organization_id = o.id
        LEFT JOIN applications.transportation t ON o.id = t.organization_id
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    WHERE
        age.organization_id = $executorOrganizationId
        AND ($contractId IS NULL OR agr.id = $contractId)
        AND ($customerId IS NULL OR o.id = $customerId)
        AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
        AND ($dateTo IS NULL OR t.created_at <= $dateTo)
    GROUP BY agr.id, o.organization_name, agr.status, agr.created_at, agr.agreement_end_date

    UNION ALL

    -- Данные по заявкам без контрактов
    SELECT
        NULL as contractId,
        'РАЗОВАЯ' as contractNumber,
        o.organization_name as customerName,
        COUNT(t.id) as totalApplications,
        COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as completedRoutes,
        false as hasContract,
        'active' as contractStatus,
        t.created_at as contractStartDate,
        t.created_at as contractEndDate,
        COALESCE(SUM(tc.cost), 0) as totalValue,
        'KZT' as currency
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN user.organization o ON t.organization_id = o.id
    WHERE
        tc.executor_organization_id = $executorOrganizationId
        AND NOT EXISTS (
            SELECT 1 FROM applications.agreement_executor age
            WHERE age.organization_id = $executorOrganizationId
            AND age.organization_id = o.id
            AND age.contract_id IS NOT NULL
        )
        AND ($customerId IS NULL OR o.id = $customerId)
        AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
        AND ($dateTo IS NULL OR t.created_at <= $dateTo)
    GROUP BY o.organization_name, t.created_at
)
SELECT
    ROW_NUMBER() OVER (ORDER BY cd.totalValue DESC) as id,
    cd.*
FROM contract_data cd
WHERE
    ($hasContract IS NULL OR cd.hasContract = $hasContract)
ORDER BY cd.totalValue DESC, cd.customerName ASC
```

## Основные таблицы БД
- `applications.agreement` - информация о соглашениях
- `applications.agreement_executor` - исполнители по соглашениям
- `applications.transportation` - информация о перевозках
- `applications.transportation_cost` - стоимость и исполнитель
- `user.organization` - информация об организациях (заказчики)
- `applications.contract` - контракты (если используются отдельно)

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `RoutesContractsReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по контрактам
3. Создать DTO для запроса и ответа
4. Реализовать объединение данных по контрактам и разовым заявкам
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных для статистики
7. Добавить кэширование для расчетных данных (Redis)
8. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по анализу контрактов
- ✅ Разделение на контрактные и разовые заявки работает правильно
- ✅ Фильтрация по заказчикам и контрактам работает корректно
- ✅ Процент контрактных перевозок рассчитывается правильно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Агрегация по периодам работает корректно

## Дополнительные улучшения
- Добавление анализа прибыльности контрактов
- Расчет lifetime value (LTV) клиентов
- Анализ эффективности разных типов контрактов
- Создание прогнозирования продления контрактов
- Добавление системы напоминаний об окончании контрактов
- Интеграция с CRM для управления отношениями с клиентами