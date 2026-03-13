# Отчеты заказчика - Гео-аналитика маршрутов

## Описание задачи
Реализовать API для отчета "Гео-аналитика маршрутов" с анализом маршрутов на карте, метриками стоимости и эффективности.

## Frontend UI референс
- Компонент: `GeoAnalyticsReport.vue`
- Карта: Yandex Maps с отображением маршрутов
- Фильтры: номер рейса, тип груза, направление, период
- Метрики: всего маршрутов, общий пробег, средняя цена за тонну, цена за т/км
- Графики: стоимость по маршрутам, эффективность маршрутов
- Таблица: детальная информация по каждому маршруту

## Эндпоинты для реализации

### 1. GET `/api/reports/geo-analytics/routes`
Получение данных маршрутов для гео-аналитики

**Параметры запроса:**
```json
{
  "routeId": "string (optional)",
  "cargoType": "string (optional)",
  "routeDirection": "string (optional)", // north, south, east, west
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
      "id": "string",
      "routeNumber": "string",
      "routeFrom": "string",
      "routeTo": "string",
      "weight": "number", // тонны
      "distance": "number", // км
      "cost": "number", // тенге
      "costPerTon": "number",
      "costPerTonKm": "number",
      "date": "string",
      "fromCoords": [
        "number", // longitude
        "number"  // latitude
      ],
      "toCoords": [
        "number", // longitude  
        "number"  // latitude
      ],
      "cargoType": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "totalDistance": "number",
    "avgCostPerTon": "number",
    "avgCostPerTonKm": "number"
  }
}
```

### 2. GET `/api/reports/geo-analytics/map-data`
Получение данных для отображения на карте

**Параметры:** те же что и для основного эндпоинта

**Ответ:**
```json
{
  "routes": [
    {
      "id": "string",
      "routeNumber": "string",
      "fromCoords": ["number", "number"],
      "toCoords": ["number", "number"],
      "routeFrom": "string",
      "routeTo": "string",
      "status": "string", // active, completed
      "cost": "number",
      "weight": "number"
    }
  ],
  "regions": [
    {
      "name": "string",
      "center": ["number", "number"],
      "routeCount": "number",
      "totalCost": "number"
    }
  ]
}
```

### 3. GET `/api/reports/geo-analytics/charts`
Получение данных для графиков

**Ответ:**
```json
{
  "routeCostChart": {
    "routes": ["string"], // названия маршрутов
    "costs": ["number"]   // стоимости в тысячах
  },
  "efficiencyChart": {
    "routes": ["string"],
    "costPerTonKm": ["number"] // эффективность ₸/т/км
  },
  "monthlyTrends": {
    "months": ["string"],
    "routeCount": ["number"],
    "avgCost": ["number"]
  }
}
```

### 4. GET `/api/reports/geo-analytics/export`
Экспорт гео-аналитики в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

## SQL запросы (базовая логика)

```sql
-- Основной запрос для гео-аналитики
SELECT 
    t.id,
    tc.transportation_number as routeNumber,
    cl_from.address as routeFrom,
    cl_to.address as routeTo,
    t.cargo_weight as weight,
    tc.cost,
    CASE 
        WHEN t.cargo_weight > 0 
        THEN ROUND(tc.cost / t.cargo_weight, 0)
        ELSE 0 
    END as costPerTon,
    CASE 
        WHEN t.cargo_weight > 0 AND distance > 0
        THEN ROUND(tc.cost / t.cargo_weight / distance, 2)
        ELSE 0 
    END as costPerTonKm,
    t.created_at as date,
    cl_from.longitude::float as fromLongitude,
    cl_from.latitude::float as fromLatitude,
    cl_to.longitude::float as toLongitude,
    cl_to.latitude::float as toLatitude,
    ct.cargo_type_name as cargoType,
    COALESCE(
        ST_Distance(
            ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
            ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
        ) / 1000, 0
    ) as distance,
    CASE
        WHEN cl_to.latitude::float > cl_from.latitude::float THEN 'north'
        WHEN cl_to.latitude::float < cl_from.latitude::float THEN 'south'
        WHEN cl_to.longitude::float > cl_from.longitude::float THEN 'east'
        ELSE 'west'
    END as routeDirection
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id 
        AND cl_from.loading_type = 'LOADING'
    LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id 
        AND cl_to.loading_type = 'UNLOADING'
    LEFT JOIN dictionaries.cargo_type ct ON t.cargo_type_id = ct.id
WHERE 
    ($organizationId IS NULL OR t.organization_id = $organizationId)
    AND ($routeId IS NULL OR tc.transportation_number ILIKE '%' || $routeId || '%')
    AND ($cargoType IS NULL OR ct.cargo_type_name = $cargoType)
    AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
    AND ($dateTo IS NULL OR t.created_at <= $dateTo)
    AND cl_from.longitude IS NOT NULL 
    AND cl_from.latitude IS NOT NULL
    AND cl_to.longitude IS NOT NULL 
    AND cl_to.latitude IS NOT NULL
    AND ($routeDirection IS NULL OR 
        CASE
            WHEN cl_to.latitude::float > cl_from.latitude::float THEN 'north'
            WHEN cl_to.latitude::float < cl_from.latitude::float THEN 'south'
            WHEN cl_to.longitude::float > cl_from.longitude::float THEN 'east'
            ELSE 'west'
        END = $routeDirection)
ORDER BY t.created_at DESC;
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость перевозок
- `applications.cargo_loading` - точки погрузки/выгрузки с координатами
- `dictionaries.cargo_type` - справочник типов грузов
- `user.organization` - информация об организациях

## Техническая реализация

1. Создать контроллер `GeoAnalyticsReportController`
2. Создать сервис `GeoAnalyticsReportService`
3. Создать DTO для запросов и ответов
4. Реализовать расчет расстояний через PostGIS функции
5. Добавить кэширование расчетов расстояний (Redis)
6. Реализовать группировку по регионам
7. Добавить экспорт в Excel с координатами
8. Оптимизировать запросы для больших объемов данных

## Дополнительные функции

### Расчет направления маршрута
```sql
-- Функция для определения направления
CREATE OR REPLACE FUNCTION get_route_direction(
    from_lat FLOAT, 
    from_lon FLOAT, 
    to_lat FLOAT, 
    to_lon FLOAT
) RETURNS VARCHAR(10) AS $$
BEGIN
    IF to_lat > from_lat THEN 
        RETURN 'north';
    ELSIF to_lat < from_lat THEN 
        RETURN 'south';
    ELSIF to_lon > from_lon THEN 
        RETURN 'east';
    ELSE 
        RETURN 'west';
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### Группировка по регионам
```sql
-- Запрос для группировки маршрутов по регионам
SELECT 
    CASE 
        WHEN cl_from.address LIKE '%Алматы%' OR cl_to.address LIKE '%Алматы%' THEN 'Алматинская область'
        WHEN cl_from.address LIKE '%Нур-Султан%' OR cl_to.address LIKE '%Нур-Султан%' THEN 'Акмолинская область'
        WHEN cl_from.address LIKE '%Шымкент%' OR cl_to.address LIKE '%Шымкент%' THEN 'Туркестанская область'
        ELSE 'Другие регионы'
    END as region,
    COUNT(*) as routeCount,
    SUM(tc.cost) as totalCost,
    AVG(cl_from.latitude::float) as centerLat,
    AVG(cl_from.longitude::float) as centerLon
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id 
        AND cl_from.loading_type = 'LOADING'
    LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id 
        AND cl_to.loading_type = 'UNLOADING'
WHERE t.organization_id = $organizationId
GROUP BY region;
```

## Критерии приемки

- ✅ API возвращает корректные данные с координатами
- ✅ Расстояния рассчитываются точно через PostGIS
- ✅ Метрики эффективности вычисляются правильно
- ✅ Фильтрация по направлениям работает корректно
- ✅ Данные для карты включают все необходимые поля
- ✅ Экспорт в Excel содержит координаты
- ✅ Производительность оптимизирована для больших объемов
- ✅ API работает только для авторизованных пользователей организации