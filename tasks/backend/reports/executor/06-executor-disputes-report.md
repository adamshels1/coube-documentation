# Отчеты перевозчика - Споры и претензии [Фьючерс]

## Описание задачи
Реализовать API для отчета "Споры и претензии" - отчет по спорам и претензиям от заказчиков.

**Важно:** Отчет будет активным при подключении платежной системы позже. Пока в разработке оставить.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `02-reports-disputes-claims.md`, но с фокусом на споры для перевозчика.

## Frontend UI референс
- Компонент: `ExecutorDisputesReport.vue`
- Фильтры: номер спора, заказчик, статус, результат, период
- Таблица: номер спора, заказчик, сумма, статус, результат, комментарии
- Метрики: общее количество споров, сумма претензий, решенные споры, среднее время решения
- Графики: Канбан доска (Новый → В рассмотрении → Решен), динамика споров

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/disputes-claims`
Получение данных по спорам и претензиям

**Параметры запроса:**
```json
{
  "disputeId": "string (optional)",
  "customerId": "number (optional)",
  "status": "string (optional)", // new, under_review, resolved
  "result": "string (optional)",
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
      "disputeNumber": "string",
      "customerName": "string",
      "routeNumber": "string",
      "claimAmount": "number",
      "currency": "string",
      "status": "string", // new, under_review, resolved
      "result": "string",
      "description": "string",
      "createdAt": "string",
      "resolvedAt": "string",
      "resolutionDays": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalDisputes": "number",
    "totalClaimAmount": "number",
    "resolvedDisputes": "number",
    "underReviewDisputes": "number",
    "averageResolutionDays": "number"
  }
}
```

### 2. GET `/api/reports/executor/disputes-claims/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/disputes-claims/kanban`
Получение данных для Канбан доски

**Ответ:**
```json
{
  "columns": [
    {
      "status": "new",
      "title": "Новые",
      "items": [
        {
          "id": "number",
          "disputeNumber": "string",
          "customerName": "string",
          "claimAmount": "number",
          "createdAt": "string"
        }
      ]
    },
    {
      "status": "under_review",
      "title": "В рассмотрении",
      "items": [...]
    },
    {
      "status": "resolved",
      "title": "Решенные",
      "items": [...]
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Запрос по спорам и претензиям (placeholder - структура для будущей реализации)
SELECT
    'DISP-' || t.id::text || '-' || ROW_NUMBER() OVER (ORDER BY t.created_at DESC) as disputeNumber,
    o.organization_name as customerName,
    tc.transportation_number as routeNumber,
    -- Сумма претензии (пока на основе стоимости перевозки, потом будет из таблицы claims)
    tc.cost as claimAmount,
    tc.cost_currency_code as currency,
    -- Статус спора (заглушка для будущей реализации)
    CASE
        WHEN t.status = 'completed' AND tc.status = 'paid' THEN 'resolved'
        WHEN t.status = 'completed' AND tc.status != 'paid' THEN 'under_review'
        ELSE 'new'
    END as status,
    -- Результат рассмотрения (заглушка)
    CASE
        WHEN tc.status = 'paid' THEN 'Выплачено'
        ELSE 'В обработке'
    END as result,
    -- Описание претензии (заглушка)
    'Претензия по рейсу ' || tc.transportation_number as description,
    t.created_at,
    t.updated_at as resolvedAt,
    -- Время решения в днях
    EXTRACT(DAYS FROM (t.updated_at - t.created_at)) as resolutionDays
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND t.status = 'completed'
    AND ($disputeId IS NULL OR tc.transportation_number ILIKE '%' || $disputeId || '%')
    AND ($customerId IS NULL OR t.organization_id = $customerId)
    AND ($status IS NULL OR
         CASE
             WHEN t.status = 'completed' AND tc.status = 'paid' THEN 'resolved'
             WHEN t.status = 'completed' AND tc.status != 'paid' THEN 'under_review'
             ELSE 'new'
         END = $status)
    AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
    AND ($dateTo IS NULL OR t.created_at <= $dateTo)
ORDER BY t.created_at DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость и статус оплаты
- `user.organization` - информация об организациях (заказчики)
- **Будущие таблицы (для будущей реализации):**
  - `claims.disputes` - информация о спорах
  - `claims.claim_documents` - документы по претензиям
  - `claims.resolution_history` - история рассмотрения споров

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `DisputesClaimsReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по спорам
3. Создать DTO для запроса и ответа
4. Реализовать базовую логику на основе существующих данных (как заглушка)
5. Добавить экспорт в Excel через Apache POI
6. Реализовать Канбан доску для управления спорами
7. Добавить кэширование для агрегированных данных (Redis)
8. **Будущая интеграция:** Подготовить структуру для полноценной системы споров
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные структуру данных по спорам
- ✅ Фильтрация по статусам работает корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Канбан доска отображается корректно
- ✅ Метрики рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Структура готова для будущей интеграции с системой управления спорами

## Заметки для будущей разработки
- Создать полноценную таблицу `claims.disputes` для хранения информации о спорах
- Добавить систему документооборота для споров (загрузка документов, переписка)
- Реализовать автоматическое создание споров на основе просроченных платежей
- Добавить интеграцию с юридическими сервисами для консультаций
- Создать систему эскалации споров
- Добавить аналитику по причинам споров и рекомендаций по их предотвращению