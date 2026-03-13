# 02. API для приема маршрутных листов от внешних систем

## Обзор

Внешние системы (маркетплейсы: TEEZ_PVZ, Kaspi, Wildberries, Ozon и др.) используют эти эндпоинты для создания и обновления курьерских маршрутных листов в Coube.

**Base URL**: `/api/v1/integration`

**Поддерживаемые маркетплейсы**:
- `TEEZ_PVZ` - TEEZ ПВЗ система
- `KASPI` - Kaspi маркетплейс
- `WILDBERRIES` - Wildberries
- `OZON` - Ozon
- Другие (расширяемо)

---

## 1. Создание/обновление маршрутного листа

### `POST /api/v1/integration/waybills`

**Описание**: Создание нового маршрутного листа или обновление существующего черновика.

**Авторизация**: API Key (см. [08-api-key-authentication.md](./08-api-key-authentication.md))

**Headers**:
```
Content-Type: application/json
X-API-Key: {api_key}
X-Request-ID: {unique_request_id}  // для идемпотентности
```

### Request Body

```json
{
  "source_system": "TEEZ_PVZ",  // ОБЯЗАТЕЛЬНО: TEEZ_PVZ, KASPI, WILDBERRIES, OZON
  "waybill": {
    "id": "WB-2025-001",
    "delivery_type": "courier",
    "responsible_courier_warehouse_id": "W-ALM-01",
    "target_delivery_day": "2025-04-15"
  },
  "deliveries": [
    {
      "sort": 1,
      "is_courier_warehouse": false,
      "load_type": "unload",
      "delivery_desired_datetime": null,
      "delivery_desired_datetime_after": "2025-04-15T14:00:00+06:00",
      "delivery_desired_datetime_before": "2025-04-15T16:00:00+06:00",
      "warehouse_id": null,
      "address": "г. Алматы, ул. Абая 150, кв. 25",
      "is_sms_required": true,
      "is_photo_required": false,
      "comment": "Позвонить за 30 минут",
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77012345678"
      },
      "orders": [
        {
          "track_number": "AC-323123123",
          "externalId": "ORD-123456",
          "marketplace_order_id": "TP-789",  // ID заказа в маркетплейсе (опционально)
          "order_load_type": "unload",
          "positions": [
            {
              "position_code": "POS-001",
              "position_shortname": "Холодильник Samsung, 200кг"
            },
            {
              "position_code": "POS-002",
              "position_shortname": "Телевизор LG 55''"
            }
          ]
        }
      ]
    },
    {
      "sort": 2,
      "is_courier_warehouse": false,
      "load_type": "unload",
      "delivery_desired_datetime": "2025-04-15T10:30:00+06:00",
      "delivery_desired_datetime_after": null,
      "delivery_desired_datetime_before": null,
      "warehouse_id": null,
      "address": "г. Алматы, мкр. Аксай-4, д. 25",
      "is_sms_required": false,
      "is_photo_required": true,
      "comment": "",
      "receiver": {
        "name": "ТОО РомашкаName (Петров П.)",
        "phone": "+77017654321"
      },
      "orders": [
        {
          "track_number": "AC-555666777",
          "externalId": "ORD-789012",
          "teezpostId": "TP-456",
          "order_load_type": "unload",
          "positions": [
            {
              "position_code": "POS-100",
              "position_shortname": "Ноутбук Dell"
            }
          ]
        }
      ]
    },
    {
      "sort": 3,
      "is_courier_warehouse": true,
      "load_type": null,
      "warehouse_id": "W-ALM-01",
      "address": null,
      "is_sms_required": false,
      "is_photo_required": false,
      "comment": "Финальный склад",
      "receiver": null,
      "orders": []
    }
  ]
}
```

### Request Parameters (Query)

Отсутствуют (все данные в body).

### Response Codes

| Code | Description |
|------|-------------|
| `201 Created` | Маршрутный лист успешно создан |
| `202 Accepted` | Маршрутный лист обновлен (существующий черновик) |
| `400 Bad Request` | Невалидный JSON или отсутствуют обязательные поля |
| `409 Conflict` | Маршрутный лист уже в работе, обновление невозможно |
| `422 Unprocessable Entity` | Ошибки валидации бизнес-логики |
| `500 Internal Server Error` | Внутренняя ошибка сервера |

### Response Body - `201 Created`

```json
{
  "status": "imported",
  "transportation_id": 98765,
  "external_waybill_id": "WB-2025-001",
  "validation_status": "imported_draft",
  "created_at": "2025-04-14T09:00:00Z",
  "route_points_count": 3,
  "orders_count": 2,
  "message": "Waybill successfully imported"
}
```

### Response Body - `202 Accepted`

```json
{
  "status": "updated",
  "transportation_id": 98765,
  "external_waybill_id": "WB-2025-001",
  "validation_status": "imported_draft",
  "updated_at": "2025-04-14T09:30:00Z",
  "route_points_count": 3,
  "orders_count": 2,
  "message": "Waybill draft updated successfully"
}
```

### Response Body - `409 Conflict`

```json
{
  "status": "locked",
  "error": "waybill_already_in_work",
  "message": "Waybill WB-2025-001 is already validated and cannot be updated",
  "transportation_id": 98765,
  "current_status": "validated",
  "locked_at": "2025-04-14T08:00:00Z",
  "locked_by": "logist@coube.kz"
}
```

### Response Body - `422 Unprocessable Entity`

```json
{
  "status": "validation_failed",
  "error": "validation_errors",
  "message": "Waybill validation failed",
  "errors": [
    {
      "field": "deliveries[1].sort",
      "code": "duplicate_sort_order",
      "message": "Sort order 1 is duplicated",
      "value": 1
    },
    {
      "field": "waybill.target_delivery_day",
      "code": "past_date",
      "message": "Target delivery day cannot be in the past",
      "value": "2025-04-10"
    },
    {
      "field": "deliveries[0].address",
      "code": "address_validation_failed",
      "message": "Address could not be geocoded",
      "value": "г. Алматы, несуществующая улица 999"
    },
    {
      "field": "deliveries[2].is_courier_warehouse",
      "code": "missing_final_warehouse",
      "message": "Last delivery point must be a courier warehouse",
      "value": false
    }
  ]
}
```

### Правила валидации

1. **Обязательные поля для всех маркетплейсов**:
   - `source_system` (TEEZ_PVZ, KASPI, WILDBERRIES, OZON)
   - `waybill.id`, `waybill.delivery_type`, `waybill.responsible_courier_warehouse_id`, `waybill.target_delivery_day`
   - `deliveries[].sort`, `deliveries[].is_courier_warehouse`
   - Если `is_courier_warehouse = false`: `address`, `load_type`, `receiver.name`, `receiver.phone`
   - Если `is_courier_warehouse = true`: `warehouse_id`

2. **Уникальность**:
   - `deliveries[].sort` должен быть уникальным в пределах маршрута
   - `orders[].track_number` должен быть уникальным глобально

3. **Бизнес-правила**:
   - Последняя точка маршрута (`max(sort)`) должна быть складом (`is_courier_warehouse = true`)
   - Если последняя точка не склад, система автоматически добавляет финальный склад
   - `target_delivery_day` не может быть в прошлом
   - Временные окна: можно заполнить либо `delivery_desired_datetime`, либо пару `_after` и `_before`

4. **Идемпотентность**:
   - Уникальность по паре (`external_waybill_id`, `source_system`)
   - Если маршрутный лист с таким `external_waybill_id` и `source_system` уже существует:
     - Статус `imported_draft` → перезаписывается (202)
     - Статус `validated` и далее → возвращается 409
   - Это позволяет разным маркетплейсам иметь одинаковые ID без конфликтов

---

## 2. Обновление существующего черновика

### `PUT /api/v1/integration/waybills/{externalWaybillId}`

**Описание**: Явное обновление маршрутного листа (альтернатива POST для ясности).

**Path Parameters**:
- `externalWaybillId` (required, string) - ID маршрутного листа во внешней системе

**Request/Response**: Идентичны `POST /waybills`

**Отличия от POST**:
- 404 если маршрутный лист не найден
- Явная семантика обновления (PUT vs POST для создания/обновления)

---

## 3. Получение статуса маршрутного листа

### `GET /api/v1/integration/waybills/{externalWaybillId}`

**Описание**: Получение полной информации о маршрутном листе.

**Path Parameters**:
- `externalWaybillId` (required, string)

**Query Parameters**:
- `source_system` (optional, string) - Фильтр по источнику (если не указан, ищет по ID)
- `include_history` (optional, boolean, default: false) - Включить историю изменений
- `include_orders` (optional, boolean, default: true) - Включить заказы

**Response - `200 OK`**:

```json
{
  "transportation_id": 98765,
  "external_waybill_id": "WB-2025-001",
  "source_system": "TEEZ_PVZ",
  "delivery_type": "courier",
  "responsible_courier_warehouse_id": "W-ALM-01",
  "target_delivery_day": "2025-04-15",
  "validation_status": "assigned",
  "assigned_courier": {
    "id": 543,
    "employee_id": 123,
    "full_name": "Петров Петр Петрович",
    "phone": "+77011234567",
    "email": "courier@teez.kz",
    "status": "assigned",
    "assigned_at": "2025-04-14T10:00:00Z"
  },
  "route_points": [
    {
      "id": 111,
      "sort_order": 1,
      "is_courier_warehouse": false,
      "warehouse_id": null,
      "address": "г. Алматы, ул. Абая 150, кв. 25",
      "longitude": 76.945624,
      "latitude": 43.238293,
      "desired_window": {
        "at": null,
        "from": "2025-04-15T14:00:00+06:00",
        "to": "2025-04-15T16:00:00+06:00"
      },
      "is_sms_required": true,
      "is_photo_required": false,
      "load_type": "unload",
      "comment": "Позвонить за 30 минут",
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77012345678"
      },
      "status": "pending",
      "status_datetime": null,
      "orders": [
        {
          "id": 999,
          "track_number": "AC-323123123",
          "external_id": "ORD-123456",
          "teezpost_id": "TP-789",
          "load_type": "unload",
          "status": "pending",
          "status_reason": null,
          "status_datetime": null,
          "sms_code_used": null,
          "photo_id": null,
          "courier_comment": null,
          "positions": [
            {
              "id": 1,
              "position_code": "POS-001",
              "position_shortname": "Холодильник Samsung, 200кг",
              "quantity": 1,
              "returned_quantity": 0
            }
          ]
        }
      ]
    }
  ],
  "statistics": {
    "total_points": 3,
    "total_orders": 2,
    "completed_orders": 0,
    "pending_orders": 2,
    "returned_orders": 0
  },
  "history": [
    {
      "id": 1,
      "event_type": "imported",
      "event_datetime": "2025-04-14T09:00:00Z",
      "actor_id": null,
      "actor_type": "integration",
      "description": "Waybill imported from TEEZ_PVZ"
    },
    {
      "id": 2,
      "event_type": "validated",
      "event_datetime": "2025-04-14T09:30:00Z",
      "actor_id": 456,
      "actor_type": "logist",
      "description": "Waybill validated by logist@coube.kz"
    }
  ],
  "created_at": "2025-04-14T09:00:00Z",
  "updated_at": "2025-04-14T10:00:00Z"
}
```

**Response - `404 Not Found`**:

```json
{
  "status": "not_found",
  "error": "waybill_not_found",
  "message": "Waybill WB-2025-001 not found in system",
  "external_waybill_id": "WB-2025-001"
}
```

---

## 4. Получение статусов всех заказов

### `GET /api/v1/integration/waybills/{externalWaybillId}/orders`

**Описание**: Получение актуальных статусов всех заказов в маршрутном листе.

**Path Parameters**:
- `externalWaybillId` (required, string)

**Query Parameters**:
- `source_system` (optional, string) - Фильтр по источнику
- `status` (optional, string) - Фильтр по статусу: `pending`, `delivered`, `returned`, `not_delivered`

**Response - `200 OK`**:

```json
{
  "external_waybill_id": "WB-2025-001",
  "transportation_id": 98765,
  "orders": [
    {
      "route_point_id": 111,
      "route_point_sort": 1,
      "track_number": "AC-323123123",
      "external_id": "ORD-123456",
      "marketplace_order_id": "TP-789",
      "status": "delivered",
      "status_reason": null,
      "status_datetime": "2025-04-15T14:45:00Z",
      "sms_code_used": "123456",
      "photo_id": "3f6b0f6e-1234-5678-9abc-def012345678",
      "courier_comment": "Доставлен успешно",
      "return_parts": []
    },
    {
      "route_point_id": 112,
      "route_point_sort": 2,
      "track_number": "AC-555666777",
      "external_id": "ORD-789012",
      "teezpost_id": "TP-456",
      "status": "not_delivered",
      "status_reason": "customer_not_available",
      "status_datetime": "2025-04-15T15:20:00Z",
      "sms_code_used": null,
      "photo_id": null,
      "courier_comment": "Не дозвонился, клиент не отвечает",
      "return_parts": null
    }
  ],
  "summary": {
    "total": 2,
    "delivered": 1,
    "not_delivered": 1,
    "returned": 0,
    "pending": 0
  }
}
```

---

## 5. Пометка проблемного адреса

### `POST /api/v1/integration/problem-address`

**Описание**: Регистрация проблемного адреса (для будущих проверок).

**Request Body**:

```json
{
  "source_system": "TEEZ_PVZ",  // ОБЯЗАТЕЛЬНО
  "address": "г. Алматы, ул. Несуществующая 999",
  "order_external_id": "ORD-123456",
  "reason": "previous_order_not_received",
  "comment": "Клиент не получал предыдущий заказ по этому адресу"
}
```

**Response - `202 Accepted`**:

```json
{
  "status": "queued",
  "problem_id": 123,
  "message": "Problem address registered and queued for processing"
}
```

---

## 6. Коды ошибок

| Код ошибки | HTTP Status | Описание |
|------------|-------------|----------|
| `waybill_already_in_work` | 409 | Маршрут уже провалидирован и в работе |
| `duplicate_sort_order` | 422 | Дублирующийся номер точки маршрута |
| `past_date` | 422 | Дата доставки в прошлом |
| `address_validation_failed` | 422 | Адрес не прошел геокодирование |
| `missing_final_warehouse` | 422 | Отсутствует финальный склад |
| `invalid_warehouse_id` | 422 | Неверный ID склада |
| `duplicate_track_number` | 422 | Трек-номер уже существует |
| `missing_required_field` | 400 | Отсутствует обязательное поле |
| `invalid_json` | 400 | Невалидный JSON |
| `waybill_not_found` | 404 | Маршрутный лист не найден |
| `unauthorized` | 401 | Неверный токен авторизации |
| `forbidden` | 403 | Недостаточно прав |
| `rate_limit_exceeded` | 429 | Превышен лимит запросов |
| `internal_server_error` | 500 | Внутренняя ошибка сервера |

---

## 7. Rate Limiting

- **Лимит**: 100 запросов в минуту на один API Key (маркетплейс)
- **Response Header**: `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- **При превышении**: HTTP 429 с телом:

```json
{
  "status": "rate_limit_exceeded",
  "message": "Too many requests. Please retry after 60 seconds",
  "retry_after": 60
}
```

---

## 8. Идемпотентность

Использовать заголовок `X-Request-ID` для предотвращения дублирования:

```
X-Request-ID: req-2025-04-14-001
```

Если запрос с таким ID уже обработан в течение 24 часов, возвращается результат предыдущего запроса.

---

## 9. Примеры для разных маркетплейсов

### Пример 1: TEEZ_PVZ

```bash
POST /api/v1/integration/waybills
X-API-Key: coube_teez_production_key
Content-Type: application/json

{
  "source_system": "TEEZ_PVZ",
  "waybill": {
    "id": "TEEZ-WB-001",
    "delivery_type": "courier",
    ...
  }
}
```

### Пример 2: Kaspi

```bash
POST /api/v1/integration/waybills
X-API-Key: coube_kaspi_production_key
Content-Type: application/json

{
  "source_system": "KASPI",
  "waybill": {
    "id": "KASPI-2025-12345",
    "delivery_type": "courier",
    "responsible_courier_warehouse_id": "W-KASPI-ALM",
    "target_delivery_day": "2025-04-15"
  },
  "deliveries": [
    {
      "sort": 1,
      "address": "г. Алматы, ул. Достык 123",
      "receiver": {
        "name": "Айдар Серикбаев",
        "phone": "+77051234567"
      },
      "orders": [
        {
          "track_number": "KASPI-AC-99887766",
          "externalId": "KASPI-ORD-555",
          "marketplace_order_id": "555",  // ID в Kaspi системе
          "order_load_type": "unload",
          "positions": [
            {
              "position_code": "SKU-12345",
              "position_shortname": "iPhone 15 Pro"
            }
          ]
        }
      ]
    }
  ]
}
```

### Пример 3: Wildberries

```bash
POST /api/v1/integration/waybills
X-API-Key: coube_wildberries_key
Content-Type: application/json

{
  "source_system": "WILDBERRIES",
  "waybill": {
    "id": "WB-DL-2025-789",
    "delivery_type": "courier",
    "responsible_courier_warehouse_id": "W-WB-AST",
    "target_delivery_day": "2025-04-16"
  },
  "deliveries": [
    {
      "sort": 1,
      "address": "г. Астана, р-н Есиль, ул. Кабанбай батыр 53",
      "receiver": {
        "name": "Ерлан Нурлыбеков",
        "phone": "+77011239876"
      },
      "orders": [
        {
          "track_number": "WB-1234567890",
          "externalId": "WB-ORD-777888",
          "marketplace_order_id": "777888",
          "order_load_type": "unload",
          "positions": [
            {
              "position_code": "WB-ART-99999",
              "position_shortname": "Куртка зимняя"
            }
          ]
        }
      ]
    }
  ]
}
```

---

## 10. Особенности интеграции для разных маркетплейсов

### TEEZ_PVZ
- **Специфические поля**: `teezpost_id` может быть в `marketplace_order_id`
- **Warehouse naming**: `W-TEEZ-{CITY}`
- **Track number format**: `AC-XXXXXXXXX`

### Kaspi
- **Track number format**: `KASPI-AC-XXXXXXXX`
- **Warehouse naming**: `W-KASPI-{CITY}`
- **Особенности**: может требовать QR код для получения

### Wildberries
- **Track number format**: `WB-XXXXXXXXXX`
- **Warehouse naming**: `W-WB-{CITY}`
- **Особенности**: строгие временные окна доставки

### Ozon
- **Track number format**: `OZON-XXXXXXXXXXX`
- **Warehouse naming**: `W-OZON-{CITY}`
- **Особенности**: может быть предоплата/постоплата
