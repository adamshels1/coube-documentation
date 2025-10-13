# Отчеты перевозчика - Логи уведомлений

## Описание задачи
Реализовать API для отчета "Логи уведомлений" - отчет по истории отправки уведомлений (Email, SMS, WhatsApp, Webhook) для перевозчика.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `12-reports-notification-logs.md`, но с фокусом на уведомления перевозчика.

## Frontend UI референс
- Компонент: `ExecutorNotificationLogsReport.vue`
- Фильтры: канал уведомления, статус, период, тип сообщения
- Таблица: дата, канал (Email/SMS/WhatsApp/Webhook), сообщение, статус, получатель
- Метрики: общее количество уведомлений, доставлено, ошибок, по каналам
- Графики: график доставки по времени, распределение по каналам, статистика ошибок

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/notification-logs`
Получение данных по логам уведомлений

**Параметры запроса:**
```json
{
  "channelType": "string (optional)", // email, sms, whatsapp, webhook
  "status": "string (optional)", // delivered, failed, pending
  "messageType": "string (optional)",
  "recipient": "string (optional)",
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
      "sentAt": "string",
      "channelType": "string", // email, sms, whatsapp, webhook
      "recipient": "string",
      "subject": "string",
      "message": "string",
      "status": "string", // delivered, failed, pending
      "deliveredAt": "string",
      "errorMessage": "string",
      "attemptCount": "number",
      "notificationType": "string", // transport_update, payment_received, etc.
      "transportationId": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalNotifications": "number",
    "deliveredNotifications": "number",
    "failedNotifications": "number",
    "pendingNotifications": "number",
    "deliveryRate": "number",
    "byChannel": {
      "email": "number",
      "sms": "number",
      "whatsapp": "number",
      "webhook": "number"
    }
  }
}
```

### 2. GET `/api/reports/executor/notification-logs/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/notification-logs/statistics`
Получение статистики по уведомлениям

**Параметры:**
```json
{
  "period": "string", // hour, day, week, month
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)",
  "groupBy": "string" // channel, status, type
}
```

**Ответ:**
```json
{
  "timeline": [
    {
      "period": "2024-01-15 10:00",
      "total": "number",
      "delivered": "number",
      "failed": "number",
      "deliveryRate": "number"
    }
  ],
  "byChannel": [
    {
      "channel": "email",
      "total": "number",
      "delivered": "number",
      "failed": "number",
      "deliveryRate": "number"
    }
  ],
  "byType": [
    {
      "type": "transport_update",
      "total": "number",
      "delivered": "number",
      "failed": "number"
    }
  ],
  "topErrors": [
    {
      "errorMessage": "string",
      "count": "number",
      "percentage": "number"
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по логам уведомлений
SELECT
    nl.id,
    nl.created_at as sentAt,
    nl.channel_type,
    COALESCE(
        CASE
            WHEN nl.channel_type = 'email' THEN
                (SELECT e.email FROM user.employee e WHERE e.id = nl.user_id LIMIT 1)
            WHEN nl.channel_type = 'sms' THEN
                (SELECT e.phone FROM user.employee e WHERE e.id = nl.user_id LIMIT 1)
            ELSE 'System'
        END,
        'Unknown'
    ) as recipient,
    nl.title as subject,
    nl.body as message,
    nl.status,
    nl.delivered_at,
    nl.error_message,
    da.attempt_no as attemptCount,
    -- Определение типа уведомления на основе payload
    CASE
        WHEN nl.payload::text LIKE '%transportation%' THEN 'transport_update'
        WHEN nl.payload::text LIKE '%payment%' THEN 'payment_update'
        WHEN nl.payload::text LIKE '%document%' THEN 'document_update'
        WHEN nl.payload::text LIKE '%system%' THEN 'system_notification'
        ELSE 'other'
    END as notificationType,
    nl.transportation_id
FROM notifications.notification_logs nl
    LEFT JOIN notifications.delivery_attempt da ON nl.notification_id = da.notification_id
WHERE
    nl.user_id IN (
        SELECT e.id FROM user.employee e WHERE e.organization_id = $executorOrganizationId
    )
    AND ($channelType IS NULL OR nl.channel_type = $channelType)
    AND ($status IS NULL OR nl.status = $status)
    AND ($recipient IS NULL OR COALESCE(
        CASE
            WHEN nl.channel_type = 'email' THEN
                (SELECT e.email FROM user.employee e WHERE e.id = nl.user_id LIMIT 1)
            WHEN nl.channel_type = 'sms' THEN
                (SELECT e.phone FROM user.employee e WHERE e.id = nl.user_id LIMIT 1)
            ELSE ''
        END,
        ''
    ) ILIKE '%' || $recipient || '%')
    AND ($dateFrom IS NULL OR nl.created_at >= $dateFrom)
    AND ($dateTo IS NULL OR nl.created_at <= $dateTo)
ORDER BY nl.created_at DESC
```

## Основные таблицы БД
- `notifications.notification_logs` - основные логи уведомлений
- `notifications.delivery_attempt` - попытки доставки
- `notifications.notification` - информация об уведомлениях
- `notifications.user_delivery_channels` - каналы доставки пользователей
- `user.employee` - информация о сотрудниках (получатели уведомлений)

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `NotificationLogsReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по уведомлениям
3. Создать DTO для запроса и ответа
4. Реализовать фильтрацию по сотрудникам организации-перевозчика
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных для статистики
7. Добавить кэширование для статистических данных (Redis)
8. Добавить детализацию ошибок доставки
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по логам уведомлений
- ✅ Фильтрация по каналам и статусам работает правильно
- ✅ Получатели определяются корректно для организации
- ✅ Статусы доставки отображаются корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Детализация ошибок доступна

## Дополнительные улучшения
- Добавление группировки по типам уведомлений
- Реализация аналитики по времени доставки
- Добавление heatmap по активным часам отправки
- Создание системы мониторинга качества доставки
- Добавление возможности ре-отправки неудачных уведомлений
- Интеграция с сервисами аналитики для отслеживания метрик