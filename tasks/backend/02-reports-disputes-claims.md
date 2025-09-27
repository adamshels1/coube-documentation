# Отчеты заказчика - Споры и претензии

## Описание задачи
Реализовать API для отчета "Споры и претензии" с Kanban-доской для управления спорными ситуациями и претензиями по перевозкам.

## Frontend UI референс
- Компонент: `DisputesReport.vue`
- Kanban-доска: Новые, В рассмотрении, Решенные
- Фильтры: номер спора, статус, тип претензии, период
- Метрики: всего споров, новые, в рассмотрении, решенные, общая сумма претензий, среднее время решения
- Графики: статистика споров, время решения споров

## Эндпоинты для реализации

### 1. GET `/api/reports/disputes/list`
Получение списка споров и претензий

**Параметры запроса:**
```json
{
  "disputeId": "string (optional)",
  "status": "string (optional)", // new, in_progress, resolved
  "disputeType": "string (optional)", // damage, delay, payment, quality
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
      "transportationNumber": "string",
      "customerName": "string",
      "executorName": "string",
      "amount": "number",
      "status": "string", // new, in_progress, resolved
      "disputeType": "string",
      "createdAt": "string",
      "resolution": "string (optional)",
      "resolvedAt": "string (optional)",
      "resolutionTime": "number (optional)", // дни
      "assignedTo": "string (optional)",
      "daysInProgress": "number (optional)"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalDisputes": "number",
    "newDisputes": "number",
    "inProgressDisputes": "number", 
    "resolvedDisputes": "number",
    "totalAmount": "number",
    "avgResolutionTime": "number"
  }
}
```

### 2. GET `/api/reports/disputes/kanban`
Получение данных для Kanban-доски

**Ответ:**
```json
{
  "newDisputes": [
    {
      "id": "number",
      "disputeNumber": "string",
      "transportationNumber": "string",
      "customerName": "string",
      "amount": "number",
      "disputeType": "string",
      "createdAt": "string"
    }
  ],
  "inProgressDisputes": [
    {
      "id": "number",
      "disputeNumber": "string", 
      "transportationNumber": "string",
      "customerName": "string",
      "amount": "number",
      "disputeType": "string",
      "assignedTo": "string",
      "daysInProgress": "number"
    }
  ],
  "resolvedDisputes": [
    {
      "id": "number",
      "disputeNumber": "string",
      "transportationNumber": "string", 
      "customerName": "string",
      "amount": "number",
      "resolution": "string",
      "resolvedAt": "string",
      "resolutionTime": "number"
    }
  ]
}
```

### 3. GET `/api/reports/disputes/export`
Экспорт отчета по спорам в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

## SQL запросы (базовая логика)

```sql
-- Основной запрос для списка споров
SELECT 
    d.id,
    d.dispute_number as disputeNumber,
    t.transportation_number as transportationNumber,
    c_org.organization_name as customerName,
    e_org.organization_name as executorName,
    d.claim_amount as amount,
    d.status,
    d.dispute_type as disputeType,
    d.created_at as createdAt,
    d.resolution,
    d.resolved_at as resolvedAt,
    CASE 
        WHEN d.resolved_at IS NOT NULL 
        THEN EXTRACT(DAYS FROM (d.resolved_at - d.created_at))
        ELSE NULL 
    END as resolutionTime,
    u.full_name as assignedTo,
    CASE 
        WHEN d.status = 'in_progress' 
        THEN EXTRACT(DAYS FROM (NOW() - d.created_at))
        ELSE NULL 
    END as daysInProgress
FROM disputes.dispute d
    LEFT JOIN applications.transportation t ON d.transportation_id = t.id
    LEFT JOIN user.organization c_org ON t.organization_id = c_org.id
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization e_org ON tc.executor_organization_id = e_org.id
    LEFT JOIN user.user u ON d.assigned_user_id = u.id
WHERE 
    ($organizationId IS NULL OR t.organization_id = $organizationId)
    AND ($disputeId IS NULL OR d.dispute_number ILIKE '%' || $disputeId || '%')
    AND ($status IS NULL OR d.status = $status)
    AND ($disputeType IS NULL OR d.dispute_type = $disputeType)
    AND ($dateFrom IS NULL OR d.created_at >= $dateFrom)
    AND ($dateTo IS NULL OR d.created_at <= $dateTo)
ORDER BY d.created_at DESC;
```

## Основные таблицы БД

**Потребуется создать новые таблицы:**

### `disputes.dispute` - основная таблица споров
```sql
CREATE TABLE disputes.dispute (
    id BIGSERIAL PRIMARY KEY,
    dispute_number VARCHAR(50) UNIQUE NOT NULL,
    transportation_id BIGINT REFERENCES applications.transportation(id),
    dispute_type VARCHAR(50) NOT NULL, -- damage, delay, payment, quality
    status VARCHAR(20) NOT NULL DEFAULT 'new', -- new, in_progress, resolved
    claim_amount DECIMAL(15,2),
    description TEXT,
    resolution TEXT,
    assigned_user_id BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);
```

### `disputes.dispute_document` - документы по спорам
```sql
CREATE TABLE disputes.dispute_document (
    id BIGSERIAL PRIMARY KEY,
    dispute_id BIGINT REFERENCES disputes.dispute(id),
    document_name VARCHAR(255),
    document_path VARCHAR(500),
    document_type VARCHAR(50), -- claim, evidence, resolution
    uploaded_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `disputes.dispute_history` - история изменений спора
```sql
CREATE TABLE disputes.dispute_history (
    id BIGSERIAL PRIMARY KEY,
    dispute_id BIGINT REFERENCES disputes.dispute(id),
    previous_status VARCHAR(20),
    new_status VARCHAR(20),
    comment TEXT,
    changed_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW()
);
```

## Техническая реализация

1. Создать схему `disputes` в БД
2. Создать новый модуль `disputes` в backend
3. Создать контроллер `DisputesReportController`
4. Создать сервис `DisputesReportService`
5. Создать DTO для запросов и ответов
6. Реализовать пагинацию через `Pageable`
7. Добавить экспорт в Excel через Apache POI
8. Добавить автоматическую генерацию номеров споров
9. Реализовать workflow для смены статусов

## Критерии приемки

- ✅ API возвращает корректные данные согласно фильтрам
- ✅ Kanban-доска отображает споры по статусам
- ✅ Пагинация работает корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Метрики рассчитываются правильно (время решения, суммы)
- ✅ API работает только для авторизованных пользователей
- ✅ Автоматически рассчитывается время решения споров
- ✅ Поддерживается назначение ответственных за рассмотрение