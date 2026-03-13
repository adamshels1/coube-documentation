# Отчеты перевозчика - Гео-аналитика маршрутов

## Описание задачи
Реализовать API для отчета "Гео-аналитика маршрутов" - отчет по анализу маршрутов, стоимости и эффективности перевозок.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `03-reports-geo-analytics.md`, но с фокусом на анализ для перевозчика.

## Frontend UI референс
- Компонент: `ExecutorGeoAnalyticsReport.vue`
- Фильтры: маршрут, период, тип груза, стоимость
- Таблица: номер рейса, маршрут, груз (т), пробег (км), стоимость (₸), цена/т, цена/т/км
- Метрики: общее количество рейсов, общий пробег, средняя цена/т, средняя цена/т/км
- Графики: карта с маршрутами, всплывающие подсказки с ценой, анализ прибыльности маршрутов

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/geo-analytics`
Получение данных по гео-аналитике маршрутов

**Параметры запроса:**
```json
{
  "routeFrom": "string (optional)",
  "routeTo": "string (optional)",
  "cargoType": "string (optional)",
  "minCost": "number (optional)",
  "maxCost": "number (optional)",
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
      "routeFrom": "string",
      "routeTo": "string",
      "routeFromCoords": {
        "lat": "number",
        "lng": "number"
      },
      "routeToCoords": {
        "lat": "number",
        "lng": "number"
      },
      "cargoName": "string",
      "cargoWeight": "number",
      "distance": "number",
      "cost": "number",
      "currency": "string",
      "pricePerTon": "number",
      "pricePerTonKm": "number",
      "completedAt": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "totalDistance": "number",
    "totalCargo": "number",
    "totalCost": "number",
    "averagePricePerTon": "number",
    "averagePricePerTonKm": "number"
  }
}
```

### 2. GET `/api/reports/executor/geo-analytics/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/geo-analytics/map-data`
Получение данных для отображения на карте

**Параметры:**
```json
{
  "routeFrom": "string (optional)",
  "routeTo": "string (optional)",
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "routes": [
    {
      "id": "number",
      "routeNumber": "string",
      "from": {
        "city": "string",
        "coords": [number, number],
        "address": "string"
      },
      "to": {
        "city": "string",
        "coords": [number, number],
        "address": "string"
      },
      "cargo": {
        "name": "string",
        "weight": "number"
      },
      "cost": "number",
      "pricePerTonKm": "number",
      "profitability": "high|medium|low"
    }
  ],
  "hotspots": [
    {
      "coords": [number, number],
      "city": "string",
      "routeCount": "number",
      "totalCargo": "number"
    }
  ]
}
```

### 4. GET `/api/reports/executor/geo-analytics/route-efficiency`
Получение анализа эффективности маршрутов

**Параметры:**
```json
{
  "groupBy": "string", // route, cargo_type, month
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "efficiencyData": [
    {
      "groupKey": "string",
      "routeCount": "number",
      "averagePricePerTonKm": "number",
      "totalRevenue": "number",
      "profitability": "number"
    }
  ],
  "mostProfitableRoutes": [...],
  "leastProfitableRoutes": [...]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по гео-аналитике маршрутов
SELECT
    t.id,
    tc.transportation_number as routeNumber,
    cl_from.address as routeFrom,
    cl_to.address as routeTo,
    cl_from.longitude::float as fromLng,
    cl_from.latitude::float as fromLat,
    cl_to.longitude::float as toLng,
    cl_to.latitude::float as toLat,
    t.cargo_name as cargoName,
    t.cargo_weight as cargoWeight,
    -- Расчет расстояния
    COALESCE(
        ST_Distance(
            ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
            ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
        ) / 1000, 0
    ) as distance,
    tc.cost,
    tc.cost_currency_code as currency,
    -- Цена за тонну
    CASE
        WHEN t.cargo_weight > 0
        THEN tc.cost / t.cargo_weight
        ELSE 0
    END as pricePerTon,
    -- Цена за тонно-километр
    CASE
        WHEN t.cargo_weight > 0 AND
             COALESCE(
                 ST_Distance(
                     ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                     ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                 ) / 1000, 0
             ) > 0
        THEN tc.cost / t.cargo_weight / COALESCE(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 1
        )
        ELSE 0
    END as pricePerTonKm,
    t.updated_at as completedAt
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id AND cl_from.loading_type = 'LOADING'
    LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id AND cl_to.loading_type = 'UNLOADING'
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND t.status = 'completed'
    AND ($routeFrom IS NULL OR cl_from.address ILIKE '%' || $routeFrom || '%')
    AND ($routeTo IS NULL OR cl_to.address ILIKE '%' || $routeTo || '%')
    AND ($cargoType IS NULL OR t.cargo_name ILIKE '%' || $cargoType || '%')
    AND ($minCost IS NULL OR tc.cost >= $minCost)
    AND ($maxCost IS NULL OR tc.cost <= $maxCost)
    AND ($dateFrom IS NULL OR t.updated_at >= $dateFrom)
    AND ($dateTo IS NULL OR t.updated_at <= $dateTo)
ORDER BY t.updated_at DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость и исполнитель
- `applications.cargo_loading` - точки погрузки/выгрузки с координатами
- `gis.transportation_route_history` - история маршрутов
- `dictionaries.cargo_type` - справочник типов грузов
- `dictionaries.cities` - справочник городов

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `GeoAnalyticsReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с гео-аналитическими эндпоинтами
3. Создать DTO для запроса и ответа
4. Реализовать расчет расстояний через PostGIS
5. Добавить экспорт в Excel через Apache POI
6. Реализовать подготовку данных для карты (GeoJSON или кастомный формат)
7. Добавить кэширование для гео-данных (Redis)
8. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по гео-аналитике
- ✅ Расчет цен за тонну и тонно-километр работает правильно
- ✅ Координаты определяются корректно
- ✅ Данные для карты генерируются в правильном формате
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика

## Дополнительные улучшения
- Интеграция с реальными GPS треками для построения фактических маршрутов
- Добавление анализа загруженности дорог и времени в пути
- Расчет оптимальных маршрутов и их стоимости
- Добавление прогнозирования спроса по регионам
- Интеграция с картографическими сервисами (Яндекс.Карты, Google Maps)