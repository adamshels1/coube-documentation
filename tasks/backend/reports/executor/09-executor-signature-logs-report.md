# Отчеты перевозчика - Логи подписей и ЭЦП

## Описание задачи
Реализовать API для отчета "Логи подписей и ЭЦП" - отчет по логам подписания документов с использованием ЭЦП и ПЭП (подписание по SMS).

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `11-reports-signature-logs.md`, но с фокусом на документы перевозчика.

## Frontend UI референс
- Компонент: `ExecutorSignatureLogsReport.vue`
- Фильтры: документ, подписант, статус подписи, период
- Таблица: документ, дата, подписал, статус, тип подписи (ЭЦП/ПЭП)
- Метрики: общее количество документов, подписанных документов, ожидают подписания, отклонено
- Графики: динамика подписаний по времени, распределение по типам подписей

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/signature-logs`
Получение данных по логам подписей

**Параметры запроса:**
```json
{
  "documentType": "string (optional)", // contract, act, invoice, agreement
  "signerName": "string (optional)",
  "signatureType": "string (optional)", // eds, sms
  "status": "string (optional)", // signed, pending, rejected
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
      "documentType": "string",
      "documentNumber": "string",
      "documentName": "string",
      "signedAt": "string",
      "signerName": "string",
      "signerIin": "string",
      "status": "string", // signed, pending, rejected
      "signatureType": "string", // eds, sms
      "organizationName": "string",
      "documentUrl": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalDocuments": "number",
    "signedDocuments": "number",
    "pendingDocuments": "number",
    "rejectedDocuments": "number",
    "edsSignatures": "number",
    "smsSignatures": "number"
  }
}
```

### 2. GET `/api/reports/executor/signature-logs/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/signature-logs/statistics`
Получение статистики по подписям

**Параметры:**
```json
{
  "period": "string", // day, week, month
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "periods": [
    {
      "period": "2024-01-15",
      "totalSignatures": "number",
      "edsSignatures": "number",
      "smsSignatures": "number",
      "successRate": "number"
    }
  ],
  "byDocumentType": [
    {
      "documentType": "contract",
      "count": "number",
      "signedCount": "number",
      "pendingCount": "number"
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Запрос по логам подписей из разных источников
WITH contract_signatures AS (
    -- Подписи контрактов
    SELECT
        'contract' as documentType,
        tc.transportation_number as documentNumber,
        'Контракт на перевозку ' || tc.transportation_number as documentName,
        s.tsp_gen_time as signedAt,
        s.sur_name || ' ' || s.common_name as signerName,
        s.iin as signerIin,
        'signed' as status,
        'eds' as signatureType,
        o.organization_name as organizationName,
        -- URL файла (из S3)
        'contracts/' || tc.transportation_number || '.pdf' as documentUrl
    FROM applications.contract c
        LEFT JOIN applications.transportation t ON c.transportation_id = t.id
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN file.signature s ON c.signature_with_two_signs = s.id
        LEFT JOIN user.organization o ON tc.executor_organization_id = o.id
    WHERE
        tc.executor_organization_id = $executorOrganizationId
        AND s.tsp_gen_time IS NOT NULL
),
act_signatures AS (
    -- Подписи актов
    SELECT
        'act' as documentType,
        a.act_number as documentNumber,
        'Акт выполненных работ ' || a.act_number as documentName,
        s.tsp_gen_time as signedAt,
        s.sur_name || ' ' || s.common_name as signerName,
        s.iin as signerIin,
        a.status as status,
        'eds' as signatureType,
        o.organization_name as organizationName,
        'acts/' || a.act_number || '.pdf' as documentUrl
    FROM applications.acts a
        LEFT JOIN applications.transportation t ON a.transportation_id = t.id
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN file.signature s ON a.file_id = s.signed_file_id
        LEFT JOIN user.organization o ON tc.executor_organization_id = o.id
    WHERE
        tc.executor_organization_id = $executorOrganizationId
),
factoring_signatures AS (
    -- Подписи факторинговых соглашений (ПЭП по SMS)
    SELECT
        'factoring_agreement' as documentType,
        fa.id::text as documentNumber,
        'Факторинговое соглашение ' || fa.id as documentName,
        fa.signed_at as signedAt,
        'SMS Подпись' as signerName,
        fa.signed_by_iin as signerIin,
        fa.status as status,
        'sms' as signatureType,
        o.organization_name as organizationName,
        fa.signed_contract_url as documentUrl
    FROM factoring.factoring_agreement fa
        LEFT JOIN user.organization o ON fa.organization_id = o.id
    WHERE
        fa.organization_id = $executorOrganizationId
        AND fa.role = 'executor'
)
-- Объединение всех подписей
SELECT * FROM contract_signatures
UNION ALL
SELECT * FROM act_signatures
UNION ALL
SELECT * FROM factoring_signatures
WHERE
    ($documentType IS NULL OR documentType = $documentType)
    AND ($signerName IS NULL OR signerName ILIKE '%' || $signerName || '%')
    AND ($signatureType IS NULL OR signatureType = $signatureType)
    AND ($status IS NULL OR status = $status)
    AND ($dateFrom IS NULL OR signedAt >= $dateFrom)
    AND ($dateTo IS NULL OR signedAt <= $dateTo)
ORDER BY signedAt DESC
```

## Основные таблицы БД
- `file.signature` - информация об ЭЦП подписях
- `applications.contract` - контракты на перевозку
- `applications.acts` - акты выполненных работ
- `factoring.factoring_agreement` - факторинговые соглашения (ПЭП)
- `applications.transportation_cost` - связь с организациями
- `user.organization` - информация об организациях
- `file.file_meta_info` - метаданные файлов документов

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `SignatureLogsReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по подписям
3. Создать DTO для запроса и ответа
4. Реализовать объединение данных из разных источников подписей
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных для статистики
7. Добавить кэширование для статистических данных (Redis)
8. Интеграция с сервисом ЭЦП для получения актуальной информации
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по логам подписей
- ✅ Данные объединяются из разных источников корректно
- ✅ Фильтрация по типам подписей работает правильно
- ✅ Статусы подписей отображаются корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Ссылки на документы работают корректно

## Дополнительные улучшения
- Добавление логов ПЭП (подписание по SMS) в отдельную таблицу
- Интеграция с сервисом Kalkan для проверки статуса ЭЦП
- Добавление уведомлений об истекающих сертификатах
- Реализация массовой подписи документов
- Добавление истории версий подписанных документов