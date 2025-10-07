# 03. Примеры API запросов/ответов для MVP

## Обзор

Практические примеры вызовов API для интеграции курьерской доставки.

---

## 1. Импорт маршрутного листа от TEEZ

### Request

**Endpoint**: `POST /api/v1/integration/waybills`  
**Authentication**: `X-API-Key: {your-api-key}`  
**Content-Type**: `application/json`

```json
{
  "source_system": "TEEZ_PVZ",
  "waybill": {
    "id": "WB-2025-001",
    "delivery_type": "courier",
    "target_delivery_day": "2025-01-07"
  },
  "deliveries": [
    {
      "sort": 1,
      "is_courier_warehouse": true,
      "load_type": "loading",
      "warehouse_id": "WH-TEEZ-001",
      "address": "Алматы, ул. Абая 150, склад TEEZ",
      "latitude": 43.2220,
      "longitude": 76.8512,
      "is_sms_required": false,
      "is_photo_required": false,
      "comment": "Забрать посылки со склада",
      "orders": []
    },
    {
      "sort": 2,
      "is_courier_warehouse": false,
      "load_type": "unloading",
      "address": "Алматы, мкр. Самал-2, дом 58, кв. 12",
      "latitude": 43.2385,
      "longitude": 76.9562,
      "delivery_desired_datetime": "2025-01-07T10:00:00Z",
      "delivery_desired_datetime_after": "2025-01-07T09:00:00Z",
      "delivery_desired_datetime_before": "2025-01-07T18:00:00Z",
      "is_sms_required": true,
      "is_photo_required": true,
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77771234567"
      },
      "comment": "Домофон 12, звонить за 15 минут",
      "orders": [
        {
          "track_number": "TRACK-123456",
          "external_id": "ORDER-TEEZ-001",
          "order_load_type": "unload",
          "positions": [
            {
              "position_code": "POS-001",
              "position_shortname": "Товар 1"
            },
            {
              "position_code": "POS-002",
              "position_shortname": "Товар 2"
            }
          ]
        }
      ]
    },
    {
      "sort": 3,
      "is_courier_warehouse": false,
      "load_type": "unloading",
      "address": "Алматы, пр. Достык 97, офис 301",
      "latitude": 43.2350,
      "longitude": 76.9450,
      "delivery_desired_datetime": "2025-01-07T14:00:00Z",
      "is_sms_required": false,
      "is_photo_required": true,
      "receiver": {
        "name": "Петрова Анна",
        "phone": "+77779876543"
      },
      "orders": [
        {
          "track_number": "TRACK-123457",
          "external_id": "ORDER-TEEZ-002",
          "order_load_type": "unload",
          "positions": [
            {
              "position_code": "POS-003",
              "position_shortname": "Документы"
            }
          ]
        }
      ]
    },
    {
      "sort": 4,
      "is_courier_warehouse": true,
      "load_type": "unloading",
      "warehouse_id": "WH-TEEZ-001",
      "address": "Алматы, ул. Абая 150, склад TEEZ",
      "latitude": 43.2220,
      "longitude": 76.8512,
      "is_sms_required": false,
      "is_photo_required": false,
      "comment": "Возврат на склад",
      "orders": []
    }
  ]
}
```

### Response (Success)

**Status**: `200 OK`

```json
{
  "status": "imported",
  "transportation_id": 12345,
  "external_waybill_id": "WB-2025-001",
  "courier_validation_status": "IMPORTED",
  "route_points_count": 4,
  "orders_count": 2,
  "created_at": "2025-01-06T12:00:00Z",
  "message": "Waybill imported successfully"
}
```

### Response (Duplicate)

**Status**: `200 OK` (если статус IMPORTED - обновляем)

```json
{
  "status": "updated",
  "transportation_id": 12345,
  "external_waybill_id": "WB-2025-001",
  "courier_validation_status": "IMPORTED",
  "route_points_count": 4,
  "orders_count": 2,
  "updated_at": "2025-01-06T12:30:00Z",
  "message": "Waybill updated successfully"
}
```

### Response (Locked)

**Status**: `409 Conflict`

```json
{
  "status": "locked",
  "error": "WAYBILL_LOCKED",
  "message": "Waybill already validated and cannot be updated",
  "external_waybill_id": "WB-2025-001",
  "current_status": "VALIDATED"
}
```

### Response (Validation Error)

**Status**: `400 Bad Request`

```json
{
  "status": "validation_failed",
  "message": "Validation failed",
  "errors": [
    {
      "field": "deliveries[1].address",
      "code": "REQUIRED",
      "message": "Address is required for non-warehouse points",
      "value": null
    },
    {
      "field": "deliveries[2].orders",
      "code": "EMPTY_ORDERS",
      "message": "At least one order is required for delivery points",
      "value": []
    }
  ]
}
```

---

## 2. Получение статусов заказов

### Request

**Endpoint**: `GET /api/v1/integration/waybills/{externalWaybillId}/orders?source_system=TEEZ_PVZ`  
**Authentication**: `X-API-Key: {your-api-key}`

```bash
curl -X GET "https://api.coube.kz/api/v1/integration/waybills/WB-2025-001/orders?source_system=TEEZ_PVZ" \
  -H "X-API-Key: your-api-key-here"
```

### Response

**Status**: `200 OK`

```json
{
  "waybill_id": "WB-2025-001",
  "transportation_id": 12345,
  "status": "completed",
  "orders": [
    {
      "track_number": "TRACK-123456",
      "external_id": "ORDER-TEEZ-001",
      "status": "delivered",
      "status_reason": null,
      "delivery_datetime": "2025-01-07T10:15:00Z",
      "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg",
      "courier_comment": null,
      "positions": [
        {
          "code": "POS-001",
          "name": "Товар 1",
          "qty": 1,
          "returned_qty": 0
        },
        {
          "code": "POS-002",
          "name": "Товар 2",
          "qty": 1,
          "returned_qty": 0
        }
      ]
    },
    {
      "track_number": "TRACK-123457",
      "external_id": "ORDER-TEEZ-002",
      "status": "not_delivered",
      "status_reason": "customer_not_available",
      "delivery_datetime": "2025-01-07T14:05:00Z",
      "photo_url": null,
      "courier_comment": "Клиент не отвечает на звонки, попробуем завтра",
      "positions": [
        {
          "code": "POS-003",
          "name": "Документы",
          "qty": 1,
          "returned_qty": 1
        }
      ]
    }
  ]
}
```

---

## 3. Курьер: Список заявок

### Request

**Endpoint**: `GET /api/v1/driver/orders`  
**Authentication**: `Bearer {keycloak-token}` (роль DRIVER)

```bash
curl -X GET "https://api.coube.kz/api/v1/driver/orders?page=0&size=20" \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Response

**Status**: `200 OK`

```json
{
  "content": [
    {
      "id": 12345,
      "transportation_type": "COURIER_DELIVERY",
      "status": "WAITING_DRIVER_CONFIRMATION",
      "external_waybill_id": "WB-2025-001",
      "source_system": "TEEZ_PVZ",
      "target_delivery_day": "2025-01-07",
      "route_points_count": 4,
      "orders_count": 2,
      "created_at": "2025-01-06T12:00:00Z"
    },
    {
      "id": 12340,
      "transportation_type": "FLT",
      "status": "DRIVER_ACCEPTED",
      "cargo_name": "Строительные материалы",
      "route_points_count": 3,
      "created_at": "2025-01-05T08:00:00Z"
    }
  ],
  "page": 0,
  "size": 20,
  "total_elements": 2,
  "total_pages": 1
}
```

---

## 4. Курьер: Принять маршрут

### Request

**Endpoint**: `PUT /api/v1/driver/orders/{transportationId}/accept`  
**Authentication**: `Bearer {keycloak-token}`

```bash
curl -X PUT "https://api.coube.kz/api/v1/driver/orders/12345/accept" \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Response

**Status**: `200 OK`

```json
{
  "transportation_id": 12345,
  "status": "DRIVER_ACCEPTED",
  "message": "Order accepted successfully"
}
```

---

## 5. Курьер: Начать маршрут

### Request

**Endpoint**: `PUT /api/v1/driver/orders/{transportationId}/start`  
**Authentication**: `Bearer {keycloak-token}`

```bash
curl -X PUT "https://api.coube.kz/api/v1/driver/orders/12345/start" \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Response

**Status**: `200 OK`

```json
{
  "id": 12345,
  "status": "ON_THE_WAY",
  "current_route": {
    "version": 1,
    "points": [
      {
        "id": 5001,
        "order_num": 1,
        "address": "Алматы, ул. Абая 150, склад TEEZ",
        "loading_type": "LOADING",
        "is_courier_warehouse": true,
        "courier_warehouse_id": "WH-TEEZ-001",
        "is_driver_at_location": false,
        "orders": []
      },
      {
        "id": 5002,
        "order_num": 2,
        "address": "Алматы, мкр. Самал-2, дом 58, кв. 12",
        "loading_type": "UNLOADING",
        "is_courier_warehouse": false,
        "contact_person_name": "Иванов Иван Иванович",
        "contact_number": "+77771234567",
        "is_sms_required": true,
        "is_photo_required": true,
        "is_driver_at_location": false,
        "orders": [
          {
            "id": 7001,
            "track_number": "TRACK-123456",
            "external_id": "ORDER-TEEZ-001",
            "status": "pending",
            "positions": [
              {"code": "POS-001", "name": "Товар 1", "qty": 1},
              {"code": "POS-002", "name": "Товар 2", "qty": 1}
            ]
          }
        ]
      },
      {
        "id": 5003,
        "order_num": 3,
        "address": "Алматы, пр. Достык 97, офис 301",
        "loading_type": "UNLOADING",
        "contact_person_name": "Петрова Анна",
        "contact_number": "+77779876543",
        "is_photo_required": true,
        "is_driver_at_location": false,
        "orders": [
          {
            "id": 7002,
            "track_number": "TRACK-123457",
            "status": "pending"
          }
        ]
      },
      {
        "id": 5004,
        "order_num": 4,
        "address": "Алматы, ул. Абая 150, склад TEEZ",
        "loading_type": "UNLOADING",
        "is_courier_warehouse": true,
        "is_driver_at_location": false,
        "orders": []
      }
    ]
  }
}
```

---

## 6. Курьер: Прибытие на точку

### Request

**Endpoint**: `PUT /api/v1/driver/orders/{transportationId}/arrival`  
**Authentication**: `Bearer {keycloak-token}`

```json
{
  "cargo_loading_id": 5002,
  "location": {
    "latitude": 43.2385,
    "longitude": 76.9562
  },
  "arrival_time": "2025-01-07T10:00:00Z"
}
```

### Response

**Status**: `200 OK`

```json
{
  "id": 12345,
  "status": "ON_THE_WAY",
  "current_point": {
    "id": 5002,
    "order_num": 2,
    "is_driver_at_location": true,
    "arrival_time": "2025-01-07T10:00:00Z"
  }
}
```

---

## 7. Курьер: Обновить статус заказа

### Request (Доставлено)

**Endpoint**: `PUT /api/v1/driver/orders/{transportationId}/courier-orders/{orderId}/status`  
**Authentication**: `Bearer {keycloak-token}`

```json
{
  "status": "delivered",
  "sms_code": "1234",
  "comment": null,
  "photo_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

### Request (Не доставлено)

```json
{
  "status": "not_delivered",
  "status_reason": "customer_not_available",
  "comment": "Клиент не отвечает на звонки, попробуем завтра",
  "photo_id": null
}
```

### Request (Частичный возврат)

```json
{
  "status": "partially_returned",
  "comment": "Клиент принял только 1 товар из 2",
  "returned_positions": [
    {
      "position_code": "POS-002",
      "returned_qty": 1
    }
  ]
}
```

### Response

**Status**: `200 OK`

```json
{
  "order_id": 7001,
  "track_number": "TRACK-123456",
  "status": "delivered",
  "status_datetime": "2025-01-07T10:15:00Z",
  "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg"
}
```

---

## 8. Курьер: Отбытие с точки

### Request

**Endpoint**: `PUT /api/v1/driver/orders/{transportationId}/departure`  
**Authentication**: `Bearer {keycloak-token}`

```json
{
  "cargo_loading_id": 5002,
  "location": {
    "latitude": 43.2385,
    "longitude": 76.9562
  },
  "departure_time": "2025-01-07T10:20:00Z"
}
```

### Response

**Status**: `200 OK`

```json
{
  "id": 12345,
  "status": "ON_THE_WAY",
  "completed_points": 2,
  "total_points": 4,
  "next_point": {
    "id": 5003,
    "order_num": 3,
    "address": "Алматы, пр. Достык 97, офис 301"
  }
}
```

---

## 9. Курьер: Загрузить фото

### Request

**Endpoint**: `POST /api/v1/driver/upload-photo`  
**Authentication**: `Bearer {keycloak-token}`  
**Content-Type**: `multipart/form-data`

```bash
curl -X POST "https://api.coube.kz/api/v1/driver/upload-photo" \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -F "file=@/path/to/photo.jpg" \
  -F "order_id=7001"
```

### Response

**Status**: `200 OK`

```json
{
  "file_id": "550e8400-e29b-41d4-a716-446655440000",
  "file_url": "https://s3.coube.kz/courier/photos/123456.jpg",
  "uploaded_at": "2025-01-07T10:15:00Z"
}
```

---

## 10. Отправка результатов в TEEZ

### Request (из Coube в TEEZ)

**Endpoint**: `POST {teez_api_url}/api/waybill/results`  
**Authentication**: `Bearer {teez-token}` или другая их аутентификация  
**Content-Type**: `application/json`

```json
{
  "waybill_id": "WB-2025-001",
  "completed_at": "2025-01-07T16:00:00Z",
  "delivery_results": [
    {
      "track_number": "TRACK-123456",
      "external_id": "ORDER-TEEZ-001",
      "status": "delivered",
      "status_reason": null,
      "delivery_datetime": "2025-01-07T10:15:00Z",
      "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg",
      "courier_comment": null,
      "positions": [
        {
          "code": "POS-001",
          "name": "Товар 1",
          "qty": 1,
          "returned_qty": 0
        },
        {
          "code": "POS-002",
          "name": "Товар 2",
          "qty": 1,
          "returned_qty": 0
        }
      ]
    },
    {
      "track_number": "TRACK-123457",
      "external_id": "ORDER-TEEZ-002",
      "status": "not_delivered",
      "status_reason": "customer_not_available",
      "delivery_datetime": "2025-01-07T14:05:00Z",
      "photo_url": null,
      "courier_comment": "Клиент не отвечает на звонки, попробуем завтра",
      "positions": [
        {
          "code": "POS-003",
          "name": "Документы",
          "qty": 1,
          "returned_qty": 1
        }
      ]
    }
  ]
}
```

### Response от TEEZ

**Status**: `200 OK`

```json
{
  "status": "accepted",
  "waybill_id": "WB-2025-001",
  "processed_orders": 2,
  "message": "Results received successfully"
}
```

---

## Коды ошибок

### 400 Bad Request
- `VALIDATION_ERROR` - ошибка валидации запроса
- `INVALID_PAYLOAD` - некорректный формат данных
- `MISSING_REQUIRED_FIELD` - отсутствует обязательное поле

### 401 Unauthorized
- `INVALID_API_KEY` - неверный API ключ
- `EXPIRED_TOKEN` - токен истек

### 403 Forbidden
- `ACCESS_DENIED` - доступ запрещен
- `WRONG_DRIVER` - водитель не назначен на эту заявку

### 404 Not Found
- `WAYBILL_NOT_FOUND` - маршрутный лист не найден
- `ORDER_NOT_FOUND` - заказ не найден

### 409 Conflict
- `WAYBILL_LOCKED` - маршрутный лист заблокирован для изменений
- `ALREADY_ACCEPTED` - заявка уже принята другим водителем
- `INVALID_STATUS_TRANSITION` - недопустимый переход статуса

### 500 Internal Server Error
- `INTEGRATION_ERROR` - ошибка интеграции с внешней системой
- `DATABASE_ERROR` - ошибка базы данных

---

## Postman Collection

Для удобства тестирования создайте Postman коллекцию с этими примерами:

```json
{
  "info": {
    "name": "Coube Courier Delivery API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "variable": [
    {
      "key": "base_url",
      "value": "https://api.coube.kz"
    },
    {
      "key": "api_key",
      "value": "your-api-key-here"
    },
    {
      "key": "driver_token",
      "value": "your-driver-jwt-token-here"
    }
  ]
}
```

---

**Дата создания**: 2025-01-06  
**Версия**: 1.0  
**Статус**: Ready for Testing
