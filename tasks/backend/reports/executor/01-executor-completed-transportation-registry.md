# Отчеты перевозчика - Реестр завершенных заявок и перевозок

## Описание задачи
Реализовать API для отчета "Реестр завершенных заявок и перевозок" для перевозчика - отчет по всем выполненным перевозкам с возможностью фильтрации и экспорта в Excel.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `01-reports-application-registry.md`, но с фильтрацией по организации-перевозчику и только завершенные перевозки.

## Frontend UI референс
- Компонент: `ExecutorCompletedTransportationRegistryReport.vue`
- Фильтры: номер заявки, номер рейса, заказчик, статус, период
- Таблица: номер заявки, номер рейса, заказчик, груз, вес, маршрут, статус, даты, стоимость, пробег
- Метрики: общее количество заявок, завершенных рейсов, общая стоимость, общий пробег
- Графики: статусы перевозок, динамика по месяцам, сравнение заказчиков

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/completed-transportation-registry`
Получение данных реестра завершенных перевозок для перевозчика

**Параметры запроса:**
```json
{
  "applicationId": "string (optional)",
  "routeNumber": "string (optional)",
  "customerId": "number (optional)",
  "status": "string (optional)", // new, in_progress, completed, cancelled
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
      "applicationNumber": "string",
      "routeNumber": "string",
      "customerName": "string",
      "cargoName": "string",
      "weight": "number",
      "weightUnit": "string",
      "routeFrom": "string",
      "routeTo": "string",
      "status": "string",
      "createdAt": "string",
      "completedAt": "string",
      "cost": "number",
      "distance": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalApplications": "number",
    "completedRoutes": "number",
    "totalCost": "number",
    "totalDistance": "number"
  }
}
```

### 2. GET `/api/reports/executor/completed-transportation-registry/export`
Экспорт реестра в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

## SQL запросы (базовая логика)

```sql
SELECT
    t.id,
    tc.transportation_number as applicationNumber,
    tc.transportation_number as routeNumber,
    o.organization_name as customerName,
    t.cargo_name as cargoName,
    t.cargo_weight as weight,
    t.cargo_weight_unit as weightUnit,
    cl_from.address as routeFrom,
    cl_to.address as routeTo,
    t.status,
    t.created_at as createdAt,
    t.updated_at as completedAt,
    tc.cost,
    COALESCE(
        ST_Distance(
            ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
            ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
        ) / 1000, 0
    ) as distance
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
    LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id AND cl_from.loading_type = 'LOADING'
    LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id AND cl_to.loading_type = 'UNLOADING'
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND ($applicationId IS NULL OR tc.transportation_number ILIKE '%' || $applicationId || '%')
    AND ($customerId IS NULL OR t.organization_id = $customerId)
    AND ($status IS NULL OR t.status = $status)
    AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
    AND ($dateTo IS NULL OR t.created_at <= $dateTo)
ORDER BY t.created_at DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость и номера перевозок, исполнитель
- `applications.cargo_loading` - точки погрузки/выгрузки
- `user.organization` - информация об организациях (заказчики)
- `dictionaries.cargo_type` - справочник типов грузов

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `ApplicationRegistryReportService` для фильтрации по перевозчику
2. Создать контроллер `ExecutorReportsController` с эндпоинтами для перевозчика
3. Создать DTO для запроса и ответа
4. Реализовать пагинацию через `Pageable`
5. Добавить экспорт в Excel через Apache POI
6. Добавить кэширование для метрик (Redis)
7. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные согласно фильтрам для перевозчика
- ✅ Пагинация работает корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Метрики рассчитываются правильно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Фильтруется только по перевозкам, где текущая организация является исполнителем