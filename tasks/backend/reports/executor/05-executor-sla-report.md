# Отчеты перевозчика - SLA / дедлайны / опоздания

## Описание задачи
Реализовать API для отчета "SLA / дедлайны / опоздания" - отчет по соблюдению сроков доставки и анализу опозданий.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `09-reports-sla-performance.md`, но с фокусом на анализ производительности перевозчика.

## Frontend UI референс
- Компонент: `ExecutorSLAReport.vue`
- Фильтры: номер рейса, период, отклонение (часы)
- Таблица: номер рейса, плановое время, фактическое, отклонение (часы), простой (часы), SLA %
- Метрики: общее количество рейсов, процент SLA, среднее опоздание, средний простой
- Графики: столбчатая диаграмма план-факт, распределение опозданий

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/sla-performance`
Получение данных по SLA и опозданиям

**Параметры запроса:**
```json
{
  "routeNumber": "string (optional)",
  "dateFrom": "string (optional)", // ISO date
  "dateTo": "string (optional)", // ISO date
  "minDeviationHours": "number (optional)",
  "maxDeviationHours": "number (optional)",
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
      "routeNumber": "string",
      "plannedArrivalTime": "string",
      "actualArrivalTime": "string",
      "deviationHours": "number",
      "loadingHours": "number",
      "unloadingHours": "number",
      "totalIdleHours": "number",
      "slaPercentage": "number",
      "status": "string" // on_time, delayed, early
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "onTimeRoutes": "number",
    "delayedRoutes": "number",
    "slaPercentage": "number",
    "averageDeviation": "number",
    "averageIdleTime": "number"
  }
}
```

### 2. GET `/api/reports/executor/sla-performance/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/sla-performance/statistics`
Получение агрегированной статистики SLA

**Параметры:**
```json
{
  "period": "string", // week, month, quarter
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "periods": [
    {
      "period": "2024-W01",
      "totalRoutes": "number",
      "onTimeRoutes": "number",
      "slaPercentage": "number",
      "averageDeviation": "number",
      "averageIdleTime": "number"
    }
  ],
  "overallSLA": "number"
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по SLA и опозданиям
WITH route_times AS (
    SELECT
        t.id,
        tc.transportation_number as routeNumber,
        -- Плановое время прибытия (рассчитывается на основе времени погрузки + нормативное время)
        cl_loading.loading_datetime as plannedStartTime,
        -- Фактическое время прибытия на выгрузку
        cl_unloading.loading_datetime as actualArrivalTime,
        -- Время простоя на погрузке
        cl_loading.loading_time_hours as loadingHours,
        -- Время простоя на выгрузке
        cl_unloading.loading_time_hours as unloadingHours,
        -- Расчет нормативного времени в пути (упрощенно)
        COALESCE(
            ST_Distance(
                ST_MakePoint(cl_loading.longitude::float, cl_loading.latitude::float)::geography,
                ST_MakePoint(cl_unloading.longitude::float, cl_unloading.latitude::float)::geography
            ) / 1000 / 60, -- Расстояние в км / средняя скорость 60 км/ч
            0
        ) as estimatedTravelHours
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN applications.cargo_loading cl_loading ON t.id = cl_loading.transportation_id AND cl_loading.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_unloading ON t.id = cl_unloading.transportation_id AND cl_unloading.loading_type = 'UNLOADING'
    WHERE
        tc.executor_organization_id = $executorOrganizationId
        AND t.status = 'completed'
        AND cl_loading.loading_datetime IS NOT NULL
        AND cl_unloading.loading_datetime IS NOT NULL
)
SELECT
    rt.*,
    -- Расчет планового времени прибытия
    (rt.plannedStartTime + INTERVAL '1 hour' * rt.estimatedTravelHours) as plannedArrivalTime,
    -- Расчет отклонения в часах
    EXTRACT(EPOCH FROM (rt.actualArrivalTime - (rt.plannedStartTime + INTERVAL '1 hour' * rt.estimatedTravelHours))) / 3600 as deviationHours,
    -- Общий простой
    (rt.loadingHours + rt.unloadingHours) as totalIdleHours,
    -- Статус опоздания
    CASE
        WHEN rt.actualArrivalTime > (rt.plannedStartTime + INTERVAL '1 hour' * rt.estimatedTravelHours) THEN 'delayed'
        WHEN rt.actualArrivalTime < (rt.plannedStartTime + INTERVAL '1 hour' * rt.estimatedTravelHours) THEN 'early'
        ELSE 'on_time'
    END as status
FROM route_times rt
WHERE
    ($routeNumber IS NULL OR rt.routeNumber ILIKE '%' || $routeNumber || '%')
    AND ($dateFrom IS NULL OR rt.actualArrivalTime >= $dateFrom)
    AND ($dateTo IS NULL OR rt.actualArrivalTime <= $dateTo)
    AND ($minDeviationHours IS NULL OR ABS(EXTRACT(EPOCH FROM (rt.actualArrivalTime - (rt.plannedStartTime + INTERVAL '1 hour' * rt.estimatedTravelHours))) / 3600) >= $minDeviationHours)
    AND ($maxDeviationHours IS NULL OR ABS(EXTRACT(EPOCH FROM (rt.actualArrivalTime - (rt.plannedStartTime + INTERVAL '1 hour' * rt.estimatedTravelHours))) / 3600) <= $maxDeviationHours)
ORDER BY rt.actualArrivalTime DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - номера рейсов и исполнитель
- `applications.cargo_loading` - точки погрузки/выгрузки с временами
- `gis.transportation_route_history` - история маршрутов (для GPS данных)
- `gis.driver_location` - данные о местоположении водителя
- `dictionaries.cities` - справочник городов для расчета расстояний

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `SLAPerformanceReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с SLA эндпоинтами
3. Создать DTO для запроса и ответа
4. Реализовать расчет планового времени на основе расстояний и нормативов
5. Добавить интеграцию с GPS данными для более точного анализа
6. Добавить экспорт в Excel через Apache POI
7. Реализовать агрегацию данных для статистики
8. Добавить кэширование для расчетных данных (Redis)
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по SLA и опозданиям
- ✅ Расчет отклонений работает правильно
- ✅ Процент SLA рассчитывается корректно
- ✅ Время простоя учитывается корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика

## Дополнительные улучшения
- Интеграция с реальными GPS данными для отслеживания маршрута
- Добавление нормативных баз времени в зависимости от типа дороги и груза
- Расчет стоимости опозданий и простоев
- Прогнозирование времени прибытия на основе исторических данных