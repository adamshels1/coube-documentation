# 03. API для отправки результатов внешним системам (Coube → Маркетплейсы)

## Обзор

Coube отправляет результаты выполнения курьерских маршрутов обратно во внешние системы (TEEZ_PVZ, Kaspi, Wildberries и др.).

**Направление**: Coube Backend → Marketplace API  
**Механизм**: Асинхронная отправка через очередь с ретраями  
**Базовый URL**: Настраивается для каждого маркетплейса в конфигурации

**Поддерживаемые маркетплейсы**:
- TEEZ_PVZ
- Kaspi
- Wildberries
- Ozon

---

## 1. Отправка результатов по маршрутному листу

### `POST {marketplaceBaseUrl}/api/waybill/results`

**Описание**: Отправка результатов доставки по всем заказам маршрутного листа обратно в маркетплейс.

**Когда вызывается**:
- Курьер завершил маршрут (нажал "Завершить маршрут")
- Курьер изменил статус заказа (доставлен/возврат/не доставлен)
- Периодический job для отправки накопленных результатов

**Авторизация**: Зависит от маркетплейса (Bearer Token, API Key, или HMAC)

**Headers** (пример для TEEZ):
```
Content-Type: application/json
Authorization: Bearer {marketplace_api_token}
X-Integration-Source: COUBE
X-Coube-Request-ID: {unique_request_id}
```

**URL endpoints по маркетплейсам**:
- TEEZ_PVZ: `{teezBaseUrl}/api/waybill/results`
- Kaspi: `{kaspiBaseUrl}/api/v1/courier/delivery-results`
- Wildberries: `{wbBaseUrl}/api/v3/delivery/results`
- Ozon: `{ozonBaseUrl}/api/v2/posting/complete`

### Request Body

```json
{
  "source_system": "COUBE",  // Всегда COUBE при отправке результатов
  "marketplace": "TEEZ_PVZ",  // Куда отправляем: TEEZ_PVZ, KASPI, WILDBERRIES
  "waybill_id": "WB-2025-001",
  "record_datetime": "2025-04-15T16:30:00Z",
  "responsible_courier_warehouse_id": "W-ALM-01",
  "courier": {
    "email": "courier@teez.kz",
    "phone": "+77011234567",
    "full_name": "Петров Петр Петрович",
    "employee_id": 123
  },
  "route_summary": {
    "started_at": "2025-04-15T09:00:00Z",
    "completed_at": "2025-04-15T16:00:00Z",
    "total_orders": 5,
    "delivered": 3,
    "returned": 1,
    "not_delivered": 1
  },
  "orders": [
    {
      "track_number": "AC-323123123",
      "externalId": "ORD-123456",
      "teezpostId": "TP-789",
      "address": "г. Алматы, ул. Абая 150, кв. 25",
      "reason": "received_success",
      "to_return_partially": false,
      "parts": [],
      "status_datetime": "2025-04-15T14:45:00Z",
      "sms_code": "123456",
      "photo_url": "https://coube-storage.s3.amazonaws.com/courier/photos/3f6b0f6e.jpg",
      "courier_comment": "Доставлен успешно"
    },
    {
      "track_number": "AC-555666777",
      "externalId": "ORD-789012",
      "teezpostId": "TP-456",
      "address": "г. Алматы, мкр. Аксай-4, д. 25",
      "reason": "customer_not_available",
      "to_return_partially": false,
      "parts": null,
      "status_datetime": "2025-04-15T15:20:00Z",
      "sms_code": null,
      "photo_url": null,
      "courier_comment": "Не дозвонился, клиент не отвечает"
    },
    {
      "track_number": "AC-888999000",
      "externalId": "ORD-333444",
      "teezpostId": "TP-222",
      "address": "г. Алматы, ул. Толе би 100",
      "reason": "returned",
      "to_return_partially": true,
      "parts": [
        {
          "position_code": "POS-001",
          "position_name": "Холодильник Samsung",
          "quantity": 1
        }
      ],
      "status_datetime": "2025-04-15T13:30:00Z",
      "sms_code": "654321",
      "photo_url": "https://coube-storage.s3.amazonaws.com/courier/photos/abc123.jpg",
      "courier_comment": "Клиент принял только телевизор, холодильник вернул"
    }
  ]
}
```

### Request Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source_system` | string | Yes | Всегда "COUBE" |
| `marketplace` | string | Yes | TEEZ_PVZ, KASPI, WILDBERRIES, OZON |
| `waybill_id` | string | Yes | ID маршрутного листа из маркетплейса |
| `record_datetime` | timestamp | Yes | Дата/время формирования отчета (для ретраев) |
| `responsible_courier_warehouse_id` | string | Yes | ID ответственного склада |
| `courier.email` | string | Yes | Email курьера |
| `courier.phone` | string | Yes | Телефон курьера |
| `courier.full_name` | string | Yes | ФИО курьера |
| `route_summary.started_at` | timestamp | No | Время начала маршрута |
| `route_summary.completed_at` | timestamp | No | Время завершения маршрута |
| `orders[].track_number` | string | Yes | Трек-номер заказа |
| `orders[].externalId` | string | Yes | ID заказа из TEEZ_PVZ |
| `orders[].teezpostId` | string | No | ID заказа из TEEZ_POST |
| `orders[].address` | string | Yes | Адрес доставки |
| `orders[].reason` | string | Yes | Причина (см. таблицу ниже) |
| `orders[].to_return_partially` | boolean | Yes | Частичный возврат |
| `orders[].parts` | array | No | Возвращаемые позиции (если partial) |
| `orders[].status_datetime` | timestamp | Yes | Время изменения статуса |
| `orders[].sms_code` | string | No | Использованный SMS код |
| `orders[].photo_url` | string | No | URL фото подтверждения |
| `orders[].courier_comment` | string | No | Комментарий курьера |

### Значения `reason`

| Значение | Описание |
|----------|----------|
| `received_success` | Товар успешно доставлен |
| `returned` | Полный возврат товара |
| `customer_not_available` | Клиент недоступен (не дозвонились/не открыл) |
| `customer_postponed` | Клиент попросил отложить доставку |
| `force_majeure` | Форс-мажорные обстоятельства |

### Response Codes

| Code | Description |
|------|-------------|
| `200 OK` | Результаты успешно приняты TEEZ |
| `202 Accepted` | Результаты приняты в обработку |
| `400 Bad Request` | Невалидные данные |
| `404 Not Found` | Маршрутный лист не найден в TEEZ |
| `409 Conflict` | Конфликт данных (дубликат отправки) |
| `500 Internal Server Error` | Ошибка на стороне TEEZ |

### Response Body - `200 OK`

```json
{
  "status": "accepted",
  "waybill_id": "WB-2025-001",
  "processed_orders": 3,
  "message": "Results processed successfully",
  "timestamp": "2025-04-15T16:30:15Z"
}
```

### Response Body - `400 Bad Request`

```json
{
  "status": "error",
  "error_code": "invalid_request",
  "message": "Invalid order data",
  "errors": [
    {
      "field": "orders[0].reason",
      "message": "Unknown reason value: 'invalid_reason'"
    }
  ]
}
```

### Response Body - `404 Not Found`

```json
{
  "status": "error",
  "error_code": "waybill_not_found",
  "message": "Waybill WB-2025-001 not found in TEEZ system",
  "waybill_id": "WB-2025-001"
}
```

---

## 2. Механизм ретраев

### Стратегия повторных попыток

**Расписание**:
1. Первая попытка: сразу после события
2. Ретраи: каждые 30 минут
3. Максимальное время: 24 часа (48 попыток)
4. После 24 часов: переход в статус `failed`, алерт администратору

### Таблица логирования

Каждая попытка записывается в `applications.courier_integration_log`:

```sql
INSERT INTO applications.courier_integration_log (
    integration_type,
    source_system,
    endpoint,
    http_method,
    object_type,
    object_id,
    request_payload,
    response_payload,
    http_status_code,
    status,
    error_message,
    retry_count,
    request_datetime,
    response_datetime
) VALUES (
    'outgoing',
    'TEEZ_PVZ',
    '/api/waybill/results',
    'POST',
    'waybill_results',
    'WB-2025-001',
    '{"waybill_id": ...}',
    '{"status": "accepted"}',
    200,
    'success',
    null,
    0,
    '2025-04-15T16:30:00Z',
    '2025-04-15T16:30:01Z'
);
```

### Очередь задач

Используется pub/sub очередь `courier_result_queue`:

**Структура сообщения**:
```json
{
  "waybill_id": "WB-2025-001",
  "transportation_id": 98765,
  "order_ids": [999, 1000, 1001],
  "payload": { ... },
  "retry_count": 0,
  "next_retry_at": "2025-04-15T17:00:00Z",
  "created_at": "2025-04-15T16:30:00Z"
}
```

---

## 3. Фоновые задачи (Scheduler)

### Job: Отправка результатов

**Имя**: `CourierResultsDispatcherJob`  
**Расписание**: Каждые 5 минут  
**Endpoint**: `GET /internal/jobs/courier/results/dispatch`

**Логика**:
1. Выбрать из очереди все сообщения с `next_retry_at <= NOW()`
2. Для каждого сообщения вызвать `POST /api/waybill/results` в TEEZ
3. При успехе: удалить из очереди, записать в лог
4. При ошибке: увеличить `retry_count`, обновить `next_retry_at` (+30 мин)
5. Если `retry_count >= 48`: переместить в `failed_queue`, отправить алерт

**Response**:
```json
{
  "job_name": "CourierResultsDispatcherJob",
  "execution_time": "2025-04-15T17:00:00Z",
  "processed": 5,
  "successful": 4,
  "failed": 1,
  "details": [
    {
      "waybill_id": "WB-2025-001",
      "status": "success",
      "http_status": 200
    },
    {
      "waybill_id": "WB-2025-002",
      "status": "retry",
      "http_status": 500,
      "retry_count": 3,
      "next_retry_at": "2025-04-15T17:30:00Z"
    }
  ]
}
```

---

## 4. Webhook уведомления (опционально)

Если TEEZ предоставит webhook endpoint, Coube может отправлять события в реальном времени.

### `POST {teezWebhookUrl}/courier/events`

**События**:
- `waybill.validated` - Маршрут провалидирован логистом
- `waybill.assigned` - Курьер назначен
- `waybill.started` - Курьер начал маршрут
- `order.delivered` - Заказ доставлен
- `order.returned` - Заказ возвращен
- `waybill.completed` - Маршрут завершен

**Payload пример**:
```json
{
  "event_type": "order.delivered",
  "timestamp": "2025-04-15T14:45:00Z",
  "waybill_id": "WB-2025-001",
  "order": {
    "track_number": "AC-323123123",
    "external_id": "ORD-123456",
    "status": "delivered",
    "status_datetime": "2025-04-15T14:45:00Z"
  }
}
```

---

## 5. Мониторинг и алерты

### Метрики

1. **Успешность отправки**: `courier_results_success_rate`
2. **Средний retry count**: `courier_results_avg_retries`
3. **Failed jobs**: `courier_results_failed_count`

### Алерты

- **High retry rate**: Если >20% запросов требуют ретраев
- **Failed delivery**: Если задача достигла 48 ретраев
- **TEEZ API down**: Если >5 последовательных ошибок 5xx

**Канал алертов**: Email + Slack канал `#coube-integrations`

---

## 6. Ручное управление

### Переотправка результатов

**Endpoint**: `POST /internal/courier/waybills/{id}/resend-results`

**Описание**: Принудительная переотправка результатов в TEEZ (для случаев ручного вмешательства).

**Request**:
```json
{
  "force": true,
  "reason": "TEEZ requested re-send after data correction"
}
```

**Response**:
```json
{
  "status": "queued",
  "waybill_id": "WB-2025-001",
  "queued_at": "2025-04-15T18:00:00Z",
  "message": "Results re-queued for delivery"
}
```

### Просмотр логов интеграции

**Endpoint**: `GET /api/v1/integration/logs`

**Query Parameters**:
- `object_type=courier_waybill`
- `object_id=WB-2025-001`
- `integration_type=outgoing`
- `status=success|failure|retry`
- `from=2025-04-15`
- `to=2025-04-16`

**Response**:
```json
{
  "logs": [
    {
      "id": 12345,
      "integration_type": "outgoing",
      "source_system": "TEEZ_PVZ",
      "endpoint": "/api/waybill/results",
      "object_id": "WB-2025-001",
      "http_status_code": 200,
      "status": "success",
      "retry_count": 0,
      "request_datetime": "2025-04-15T16:30:00Z",
      "response_datetime": "2025-04-15T16:30:01Z"
    }
  ],
  "total": 1
}
```

---

## 7. Безопасность

### Аутентификация
- **Bearer Token**: TEEZ предоставляет API key, хранится в Coube Secrets Manager
- **HMAC подпись** (опционально): Подпись payload с shared secret

### Rate Limiting
- Coube самостоятельно ограничивает исходящие запросы: max 60 запросов/минуту к TEEZ API

### Retry Backoff
- Экспоненциальный backoff при 429 (Too Many Requests) от TEEZ
