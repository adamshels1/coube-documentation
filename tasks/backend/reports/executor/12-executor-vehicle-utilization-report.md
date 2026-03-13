# Отчеты перевозчика - Утилизация ТС (загруженность)

## Описание задачи
Реализовать API для отчета "Утилизация ТС (загруженность)" - отчет по анализу загруженности транспортных средств перевозчика.

**Перекрытие с отчетами заказчика:** Уникальный отчет для перевозчика, нет прямого аналога в отчетах заказчика.

## Frontend UI референс
- Компонент: `ExecutorVehicleUtilizationReport.vue`
- Фильтры: номер ТС, период, тип кузова
- Таблица: номер ТС, количество рейсов, перевезено (т), общая грузоподъемность (т), коэффициент загрузки (%)
- Метрики: общее количество ТС, средняя загрузка, общая перевезенная масса
- Графики: график загрузки по месяцам, топ самых загруженных ТС, распределение по типам ТС

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/vehicle-utilization`
Получение данных по утилизации транспортных средств

**Параметры запроса:**
```json
{
  "vehicleId": "number (optional)",
  "vehiclePlate": "string (optional)",
  "bodyType": "string (optional)",
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
      "vehicleId": "number",
      "vehiclePlate": "string",
      "vehicleModel": "string",
      "vehicleBodyType": "string",
      "totalRoutes": "number",
      "totalCargoWeight": "number",
      "vehicleCapacity": "number",
      "utilizationRate": "number",
      "averageRouteWeight": "number",
      "lastRouteDate": "string",
      "status": "string" // active, inactive, maintenance
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalVehicles": "number",
    "activeVehicles": "number",
    "averageUtilization": "number",
    "totalCargoWeight": "number",
    "totalCapacity": "number",
    "bestUtilizedVehicle": "string",
    "leastUtilizedVehicle": "string"
  }
}
```

### 2. GET `/api/reports/executor/vehicle-utilization/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/vehicle-utilization/timeline`
Получение динамики загрузки по времени

**Параметры:**
```json
{
  "vehicleId": "number (optional)",
  "period": "string", // week, month, quarter
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "timeline": [
    {
      "period": "2024-W01",
      "totalRoutes": "number",
      "totalCargoWeight": "number",
      "totalCapacity": "number",
      "utilizationRate": "number",
      "activeVehicles": "number"
    }
  ],
  "vehicles": [
    {
      "vehicleId": "number",
      "vehiclePlate": "string",
      "timeline": [
        {
          "period": "2024-W01",
          "utilizationRate": "number",
          "routes": "number"
        }
      ]
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по утилизации ТС
WITH vehicle_stats AS (
    SELECT
        v.id as vehicleId,
        v.registration_plate as vehiclePlate,
        v.brand || ' ' || v.model as vehicleModel,
        vbt.name_ru as vehicleBodyType,
        v.capacity_value as vehicleCapacity,
        COUNT(t.id) as totalRoutes,
        COALESCE(SUM(t.cargo_weight), 0) as totalCargoWeight,
        -- Коэффициент загрузки: (перевезено / (грузоподъемность × рейсы)) × 100
        CASE
            WHEN v.capacity_value > 0 AND COUNT(t.id) > 0
            THEN (COALESCE(SUM(t.cargo_weight), 0) * 100.0) / (v.capacity_value * COUNT(t.id))
            ELSE 0
        END as utilizationRate,
        -- Средний вес за рейс
        CASE
            WHEN COUNT(t.id) > 0
            THEN COALESCE(SUM(t.cargo_weight), 0) / COUNT(t.id)
            ELSE 0
        END as averageRouteWeight,
        -- Дата последнего рейса
        MAX(t.updated_at) as lastRouteDate,
        -- Статус ТС (упрощенно)
        CASE
            WHEN MAX(t.updated_at) >= CURRENT_DATE - INTERVAL '30 days'
            THEN 'active'
            ELSE 'inactive'
        END as status
    FROM applications.vehicle v
        LEFT JOIN dictionaries.vehicle_body_type vbt ON v.vehicle_body_type_id = vbt.id
        LEFT JOIN applications.transport tr ON v.id = tr.vehicle_id
        LEFT JOIN applications.transportation t ON tr.id = (
            SELECT transport_id FROM applications.transport
            WHERE vehicle_id = v.id AND transportation_id IS NOT NULL
            AND transportation_id IN (
                SELECT id FROM applications.transportation
                WHERE executor_organization_id = $executorOrganizationId
                AND ($dateFrom IS NULL OR created_at >= $dateFrom)
                AND ($dateTo IS NULL OR created_at <= $dateTo)
            )
            LIMIT 1
        )
    WHERE
        v.executor_organization_id = $executorOrganizationId
        AND ($vehicleId IS NULL OR v.id = $vehicleId)
        AND ($vehiclePlate IS NULL OR v.registration_plate ILIKE '%' || $vehiclePlate || '%')
        AND ($bodyType IS NULL OR vbt.name_ru ILIKE '%' || $bodyType || '%')
    GROUP BY v.id, v.registration_plate, v.brand, v.model, vbt.name_ru, v.capacity_value
    HAVING COUNT(t.id) > 0 OR MAX(t.updated_at) >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT
    ROW_NUMBER() OVER (ORDER BY vs.utilizationRate DESC) as id,
    vs.*
FROM vehicle_stats vs
WHERE
    ($minUtilization IS NULL OR vs.utilizationRate >= $minUtilization)
    AND ($maxUtilization IS NULL OR vs.utilizationRate <= $maxUtilization)
ORDER BY vs.utilizationRate DESC, vs.totalRoutes DESC
```

## Основные таблицы БД
- `applications.vehicle` - информация о транспортных средствах
- `applications.transport` - связь ТС с перевозками
- `applications.transportation` - информация о перевозках
- `applications.transportation_cost` - исполнитель перевозки
- `dictionaries.vehicle_body_type` - справочник типов кузова
- `gis.veh_latest_loc` - последняя локация ТС

## Техническая реализация
1. Создать сервис `ExecutorVehicleUtilizationReportService`
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по утилизации ТС
3. Создать DTO для запроса и ответа
4. Реализовать расчет коэффициента загрузки на основе реальных данных
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных для таймлайна
7. Добавить кэширование для расчетных данных (Redis)
8. Добавить интеграцию с GPS данными для определения активности ТС
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по утилизации ТС
- ✅ Коэффициент загрузки рассчитывается правильно
- ✅ Фильтрация по ТС работает корректно
- ✅ Статусы ТС определяются правильно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Таймлайн по периодам формируется корректно

## Дополнительные улучшения
- Добавление анализа простоев ТС
- Интеграция с GPS треками для точного отслеживания активности
- Расчет экономической эффективности каждого ТС
- Добавление прогнозирования оптимального количества ТС
- Создание системы мониторинга технического состояния
- Добавление анализа по водителям ТС