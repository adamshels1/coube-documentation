# Отчеты перевозчика - Кол-во рейсов за период

## Описание задачи
Реализовать API для отчета "Кол-во рейсов за период" - отчет по анализу количества рейсов, пробега и времени в пути за выбранный период.

**Перекрытие с отчетами заказчика:** Уникальный отчет для перевозчика, нет прямого аналога в отчетах заказчика.

## Frontend UI референс
- Компонент: `ExecutorRoutesPeriodReport.vue`
- Фильтры: номер рейса, период, водитель, ТС
- Таблица: номер рейса, дата, пробег (км), время ожидания (часы), время в пути (часы)
- Метрики: всего рейсов, общий пробег, среднее время ожидания, среднее время в пути
- Графики: график рейсов по месяцам, распределение времени ожидания, анализ пробега

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/routes-period`
Получение данных по рейсам за период

**Параметры запроса:**
```json
{
  "routeNumber": "string (optional)",
  "driverId": "number (optional)",
  "vehicleId": "number (optional)",
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
      "routeNumber": "string",
      "routeDate": "string",
      "distance": "number",
      "waitingTimeHours": "number",
      "travelTimeHours": "number",
      "loadingTimeHours": "number",
      "unloadingTimeHours": "number",
      "totalTimeHours": "number",
      "averageSpeed": "number",
      "driverName": "string",
      "vehiclePlate": "string",
      "routeFrom": "string",
      "routeTo": "string",
      "cargoWeight": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "totalDistance": "number",
    "totalWaitingTime": "number",
    "totalTravelTime": "number",
    "averageWaitingTime": "number",
    "averageTravelTime": "number",
    "averageSpeed": "number"
  }
}
```

### 2. GET `/api/reports/executor/routes-period/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/routes-period/analytics`
Получение аналитики по рейсам

**Параметры:**
```json
{
  "period": "string", // week, month, quarter
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)",
  "groupBy": "string" // driver, vehicle, route, month
}
```

**Ответ:**
```json
{
  "timeline": [
    {
      "period": "2024-W01",
      "routeCount": "number",
      "totalDistance": "number",
      "averageWaitingTime": "number",
      "averageTravelTime": "number",
      "averageSpeed": "number"
    }
  ],
  "byDriver": [
    {
      "driverId": "number",
      "driverName": "string",
      "routeCount": "number",
      "totalDistance": "number",
      "averageWaitingTime": "number",
      "averageTravelTime": "number",
      "efficiency": "number"
    }
  ],
  "byVehicle": [
    {
      "vehicleId": "number",
      "vehiclePlate": "string",
      "routeCount": "number",
      "totalDistance": "number",
      "utilizationRate": "number"
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по рейсам за период
WITH route_details AS (
    SELECT
        t.id,
        tc.transportation_number as routeNumber,
        t.created_at::date as routeDate,
        -- Расчет расстояния между точками погрузки и выгрузки
        COALESCE(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        ) as distance,
        -- Время ожидания на погрузке/выгрузке
        COALESCE(cl_from.loading_time_hours, 0) + COALESCE(cl_to.loading_time_hours, 0) as waitingTimeHours,
        -- Расчет времени в пути (упрощенно)
        CASE
            WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
            THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
            ELSE 0
        END as travelTimeHours,
        cl_from.loading_time_hours as loadingTimeHours,
        cl_to.loading_time_hours as unloadingTimeHours,
        -- Общее время
        CASE
            WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
            THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
            ELSE 0
        END + COALESCE(cl_from.loading_time_hours, 0) + COALESCE(cl_to.loading_time_hours, 0) as totalTimeHours,
        -- Средняя скорость
        CASE
            WHEN COALESCE(
                ST_Distance(
                    ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                    ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                ) / 1000, 0
            ) > 0 AND
            CASE
                WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
                THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
                ELSE 0
            END > 0
            THEN COALESCE(
                ST_Distance(
                    ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                    ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                ) / 1000, 0
            ) / CASE
                WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
                THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
                ELSE 1
            END
            ELSE 0
        END as averageSpeed,
        -- Информация о водителе и ТС
        e.first_name || ' ' || e.last_name as driverName,
        v.registration_plate as vehiclePlate,
        cl_from.address as routeFrom,
        cl_to.address as routeTo,
        t.cargo_weight
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id AND cl_from.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id AND cl_to.loading_type = 'UNLOADING'
        LEFT JOIN applications.transport tr ON tc.transportation_id = (
            SELECT transportation_number FROM applications.transportation_cost
            WHERE executor_organization_id = $executorOrganizationId
            AND id = t.id
            LIMIT 1
        )
        LEFT JOIN applications.employee_transport et ON tr.id = et.transport_id AND et.active = true
        LEFT JOIN user.employee e ON et.employee_id = e.id
        LEFT JOIN applications.vehicle v ON tr.vehicle_id = v.id
    WHERE
        tc.executor_organization_id = $executorOrganizationId
        AND t.status = 'completed'
        AND ($routeNumber IS NULL OR tc.transportation_number ILIKE '%' || $routeNumber || '%')
        AND ($driverId IS NULL OR e.id = $driverId)
        AND ($vehicleId IS NULL OR v.id = $vehicleId)
        AND ($dateFrom IS NULL OR t.created_at::date >= $dateFrom::date)
        AND ($dateTo IS NULL OR t.created_at::date <= $dateTo::date)
)
SELECT * FROM route_details
WHERE distance > 0 OR travelTimeHours > 0
ORDER BY routeDate DESC, routeNumber DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость и исполнитель
- `applications.cargo_loading` - точки погрузки/выгрузки с временами
- `applications.transport` - информация о транспорте
- `applications.employee_transport` - связь водителей с транспортом
- `applications.vehicle` - информация о транспортных средствах
- `user.employee` - информация о водителях
- `gis.driver_location` - GPS данные для расчета времени и расстояния

## Техническая реализация
1. Создать сервис `ExecutorRoutesPeriodReportService`
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по рейсам
3. Создать DTO для запроса и ответа
4. Реализовать расчет времени и расстояния на основе данных о погрузке/выгрузке
5. Добавить интеграцию с GPS данными для более точного расчета
6. Добавить экспорт в Excel через Apache POI
7. Реализовать агрегацию данных для аналитики
8. Добавить кэширование для расчетных данных (Redis)
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по рейсам за период
- ✅ Расчет расстояния и времени работает правильно
- ✅ Фильтрация по водителям и ТС работает корректно
- ✅ Агрегированные метрики рассчитываются правильно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Аналитика по группировке работает корректно

## Дополнительные улучшения
- Интеграция с реальными GPS треками для точного времени в пути
- Добавление анализа причин простоев
- Расчет эффективности маршрутов
- Создание прогнозирования времени на основе исторических данных
- Добавление анализа качества дорог и времени суток
- Интеграция с метеоданными для анализа влияния погоды