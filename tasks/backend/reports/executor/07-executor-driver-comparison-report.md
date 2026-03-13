# Отчеты перевозчика - Сравнение исполнителей (водителей/субподрядчиков)

## Описание задачи
Реализовать API для отчета "Сравнение исполнителей" - отчет по сравнению производительности водителей и субподрядчиков.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `10-reports-executor-comparison.md`, но с фокусом на собственных исполнителей перевозчика.

## Frontend UI референс
- Компонент: `ExecutorDriverComparisonReport.vue`
- Фильтры: водитель/ТС, период, рейтинг
- Таблица: водитель/ТС, средняя ставка (₸/км), рейтинг, % SLA, количество рейсов
- Метрики: общее количество исполнителей, средняя ставка, средний рейтинг, средний SLA
- Графики: линейный график цен, распределение рейтингов, топ исполнителей

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/drivers-comparison`
Получение данных по сравнению исполнителей

**Параметры запроса:**
```json
{
  "driverId": "number (optional)",
  "vehicleId": "number (optional)",
  "minRating": "number (optional)",
  "maxRating": "number (optional)",
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
      "driverName": "string",
      "vehicleId": "number",
      "vehiclePlate": "string",
      "vehicleModel": "string",
      "averageRatePerKm": "number",
      "rating": "number",
      "slaPercentage": "number",
      "totalRoutes": "number",
      "totalDistance": "number",
      "totalEarnings": "number",
      "onTimeRoutes": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalExecutors": "number",
    "averageRatePerKm": "number",
    "averageRating": "number",
    "averageSLA": "number",
    "totalRoutes": "number"
  }
}
```

### 2. GET `/api/reports/executor/drivers-comparison/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/drivers-comparison/top-performers`
Получение топ исполнителей по различным метрикам

**Параметры:**
```json
{
  "metric": "string", // rating, sla, earnings, routes
  "limit": "number (default: 10)",
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "topPerformers": [
    {
      "rank": "number",
      "driverName": "string",
      "vehiclePlate": "string",
      "value": "number",
      "additionalData": {
        "rating": "number",
        "slaPercentage": "number",
        "totalRoutes": "number"
      }
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по водителям и их производительности
WITH driver_performance AS (
    SELECT
        e.id as driverId,
        e.first_name || ' ' || e.last_name as driverName,
        v.id as vehicleId,
        v.registration_plate as vehiclePlate,
        v.brand || ' ' || v.model as vehicleModel,
        COUNT(t.id) as totalRoutes,
        COALESCE(SUM(tc.cost), 0) as totalEarnings,
        COALESCE(
            SUM(
                ST_Distance(
                    ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                    ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                ) / 1000
            ), 0
        ) as totalDistance,
        -- Средняя ставка за км
        CASE
            WHEN COALESCE(
                SUM(
                    ST_Distance(
                        ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                        ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                    ) / 1000
                ), 0
            ) > 0
            THEN COALESCE(SUM(tc.cost), 0) / COALESCE(
                SUM(
                    ST_Distance(
                        ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                        ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                    ) / 1000
                ), 1
            )
            ELSE 0
        END as averageRatePerKm,
        -- Расчет SLA (упрощенно - завершенные рейсы)
        CASE
            WHEN COUNT(t.id) > 0
            THEN (COUNT(CASE WHEN t.status = 'completed' THEN 1 END) * 100.0 / COUNT(t.id))
            ELSE 0
        END as slaPercentage,
        -- Рейтинг (заглушка - потом будет из таблицы рейтингов)
        4.5 as rating,
        -- Рейсы выполненные вовремя (заглушка для SLA)
        COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as onTimeRoutes
    FROM user.employee e
        LEFT JOIN applications.employee_transport et ON e.id = et.employee_id AND et.active = true
        LEFT JOIN applications.transport tr ON et.transport_id = tr.id
        LEFT JOIN applications.vehicle v ON tr.vehicle_id = v.id
        LEFT JOIN applications.transportation t ON tr.id = (
            SELECT transport_id FROM applications.transport
            WHERE vehicle_id = v.id AND transportation_id IS NOT NULL
            LIMIT 1
        )
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id AND cl_from.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id AND cl_to.loading_type = 'UNLOADING'
    WHERE
        e.organization_id = $executorOrganizationId
        AND ($driverId IS NULL OR e.id = $driverId)
        AND ($vehicleId IS NULL OR v.id = $vehicleId)
        AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
        AND ($dateTo IS NULL OR t.created_at <= $dateTo)
    GROUP BY e.id, v.id, v.registration_plate, v.brand, v.model
    HAVING COUNT(t.id) > 0
)
SELECT
    dp.*,
    -- Фильтрация по рейтингу
    CASE
        WHEN ($minRating IS NULL OR dp.rating >= $minRating)
        AND ($maxRating IS NULL OR dp.rating <= $maxRating)
        THEN true
        ELSE false
    END as passesRatingFilter
FROM driver_performance dp
WHERE
    CASE
        WHEN ($minRating IS NULL OR dp.rating >= $minRating)
        AND ($maxRating IS NULL OR dp.rating <= $maxRating)
        THEN true
        ELSE false
    END
ORDER BY dp.totalRoutes DESC, dp.rating DESC
```

## Основные таблицы БД
- `user.employee` - информация о водителях
- `applications.employee_transport` - связь водителей с транспортом
- `applications.transport` - информация о транспорте
- `applications.vehicle` - информация о транспортных средствах
- `applications.transportation` - информация о перевозках
- `applications.transportation_cost` - стоимость перевозок
- `applications.cargo_loading` - точки погрузки/выгрузки
- **Будущие таблицы:**
  - `ratings.driver_ratings` - рейтинги водителей
  - `ratings.route_ratings` - рейтинги по маршрутам

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `ExecutorComparisonReportService` для собственных исполнителей
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по водителям
3. Создать DTO для запроса и ответа
4. Реализовать расчет производительности на основе существующих данных
5. Добавить экспорт в Excel через Apache POI
6. Реализовать систему рейтингов (пока с заглушками)
7. Добавить кэширование для расчетных данных (Redis)
8. **Будущая интеграция:** Подготовить структуру для системы рейтингов
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по производительности водителей
- ✅ Расчет средних ставок и SLA работает правильно
- ✅ Рейтинги отображаются корректно
- ✅ Топ исполнители определяются правильно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Структура готова для будущей интеграции с системой рейтингов

## Дополнительные улучшения
- Интеграция с реальной системой рейтингов и отзывов
- Добавление расчета эффективности использования топлива
- Включение данных о нарушениях и штрафах
- Добавление прогнозирования производительности
- Создание системы мотивации и бонусов на основе рейтингов