# Отчеты перевозчика - Выполненные перевозки (АВР, страховые полисы)

## Описание задачи
Реализовать API для отчета "Выполненные перевозки (АВР, страховые полисы)" - отчет по выполненным перевозкам с актами выполненных работ и страховыми полисами.

**Перекрытие с отчетами заказчика:** Уникальный отчет для перевозчика, нет прямого аналога в отчетах заказчика.

## Frontend UI референс
- Компонент: `ExecutorAVRInsuranceReport.vue`
- Фильтры: номер перевозки, заказчик, статус документа, период
- Таблица: номер перевозки, заказчик, сумма, АВР (ссылка), страховой полис, премия, статус документа
- Метрики: общее количество перевозок, общая сумма, количество подписанных документов
- Графики: статусы документов, динамика выплат по месяцам

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/avr-insurance`
Получение данных по АВР и страховым полисам

**Параметры запроса:**
```json
{
  "routeNumber": "string (optional)",
  "customerId": "number (optional)",
  "documentStatus": "string (optional)", // signed, pending, rejected
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
      "customerName": "string",
      "amount": "number",
      "avrDocumentUrl": "string",
      "insurancePolicyNumber": "string",
      "insuranceDocumentUrl": "string",
      "bonusAmount": "number",
      "documentStatus": "string", // signed, pending, rejected
      "completedAt": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "totalAmount": "number",
    "signedDocuments": "number",
    "pendingDocuments": "number"
  }
}
```

### 2. GET `/api/reports/executor/avr-insurance/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/avr-insurance/{routeId}/documents`
Получение документов для конкретной перевозки

**Ответ:**
```json
{
  "avrDocument": {
    "id": "number",
    "fileName": "string",
    "fileUrl": "string",
    "signedAt": "string"
  },
  "insuranceDocument": {
    "id": "number",
    "policyNumber": "string",
    "fileName": "string",
    "fileUrl": "string",
    "signedAt": "string"
  }
}
```

## SQL запросы (базовая логика)

```sql
SELECT
    t.id,
    tc.transportation_number as routeNumber,
    o.organization_name as customerName,
    tc.cost as amount,
    -- АВР документ (из актов)
    a.act_number,
    a.file_id as avrFileId,
    a.file_name as avrFileName,
    a.status as avrStatus,
    a.signed_date as avrSignedDate,
    -- Страховой полис (дополнительная логика)
    'POL-' || tc.transportation_number as insurancePolicyNumber,
    tc.status as documentStatus,
    t.updated_at as completedAt,
    -- Премия (дополнительная плата)
    tc.idle_payment as bonusAmount
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
    LEFT JOIN applications.acts a ON t.id = a.transportation_id
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND t.status = 'completed'
    AND ($routeNumber IS NULL OR tc.transportation_number ILIKE '%' || $routeNumber || '%')
    AND ($customerId IS NULL OR t.organization_id = $customerId)
    AND ($documentStatus IS NULL OR tc.status = $documentStatus)
    AND ($dateFrom IS NULL OR t.updated_at >= $dateFrom)
    AND ($dateTo IS NULL OR t.updated_at <= $dateTo)
ORDER BY t.updated_at DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость, исполнитель, статус
- `applications.acts` - акты выполненных работ (АВР)
- `file.file_meta_info` - метаданные файлов документов
- `user.organization` - информация об организациях (заказчики)
- `file.signature` - информация о подписях документов

## Техническая реализация
1. Создать сервис `ExecutorAVRInsuranceReportService`
2. Создать контроллер `ExecutorReportsController` с эндпоинтами
3. Создать DTO для запроса и ответа
4. Реализовать генерацию URL для файлов из S3/MinIO
5. Добавить экспорт в Excel через Apache POI
6. Реализовать проверку прав доступа к документам
7. Добавить интеграцию с сервисом цифровых подписей для проверки статуса
8. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по АВР и страховым полисам
- ✅ Ссылки на документы работают корректно
- ✅ Статусы документов отображаются правильно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Документы доступны только для соответствующей организации-перевозчика