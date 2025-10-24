# 03. Примеры API запросов/ответов для MVP

## Обзор

Практические примеры вызовов API для интеграции курьерской доставки.

**🔄 Важное обновление** (16.10.2025):
- ✅ **TEEZ запрашивает статусы по трек-номерам** (раздел 2)
- ✅ **Pull-модель**: TEEZ делает GET запросы для получения статусов заказов
- ✅ **Rate limiting**: 60 запросов/минуту, 1000 запросов/час
- 📌 Рекомендуемая частота: каждые 5-10 минут

---

## 1. Импорт маршрутного листа от TEEZ

### Request

**Endpoint**: `POST /api/v1/integration/waybills`  
**Authentication**: `X-API-Key: {your-api-key}`  
**Content-Type**: `application/json`

```json
{
  "sourceSystem": "TEEZ_PVZ",
  "orgId": "ORG-TEEZ-001",
  "waybill": {
    "id": "WB-2025-001",
    "deliveryType": "courier",
    "warehouseExternalId": "WH-TEEZ-001",
    "targetDeliveryDay": "2025-01-07"
  },
  "deliveries": [
    {
      "sort": 1,
      "isCourierWarehouse": true,
      "loadType": "loading",
      "warehouseId": "WH-TEEZ-001",
      "address": "Алматы, ул. Абая 150, склад TEEZ",
      "latitude": 43.2220,
      "longitude": 76.8512,
      "isSmsRequired": false,
      "isPhotoRequired": false,
      "comment": "Забрать посылки со склада",
      "orders": []
    },
    {
      "sort": 2,
      "isCourierWarehouse": false,
      "loadType": "unloading",
      "address": "Алматы, мкр. Самал-2, дом 58, кв. 12",
      "latitude": 43.2385,
      "longitude": 76.9562,
      "deliveryDesiredDatetime": "2025-01-07T10:00:00Z",
      "deliveryDesiredDatetimeAfter": "2025-01-07T09:00:00Z",
      "deliveryDesiredDatetimeBefore": "2025-01-07T18:00:00Z",
      "isSmsRequired": true,
      "isPhotoRequired": true,
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77771234567"
      },
      "comment": "Домофон 12, звонить за 15 минут",
      "orders": [
        {
          "trackNumber": "TRACK-123456",
          "externalId": "ORDER-TEEZ-001",
          "orderLoadType": "unload",
          "positions": [
            {
              "positionCode": "POS-001",
              "positionShortname": "Товар 1"
            },
            {
              "positionCode": "POS-002",
              "positionShortname": "Товар 2"
            }
          ]
        }
      ]
    },
    {
      "sort": 3,
      "isCourierWarehouse": false,
      "loadType": "unloading",
      "address": "Алматы, пр. Достык 97, офис 301",
      "latitude": 43.2350,
      "longitude": 76.9450,
      "deliveryDesiredDatetime": "2025-01-07T14:00:00Z",
      "isSmsRequired": false,
      "isPhotoRequired": true,
      "receiver": {
        "name": "Петрова Анна",
        "phone": "+77779876543"
      },
      "orders": [
        {
          "trackNumber": "TRACK-123457",
          "externalId": "ORDER-TEEZ-002",
          "orderLoadType": "unload",
          "positions": [
            {
              "positionCode": "POS-003",
              "positionShortname": "Документы"
            }
          ]
        }
      ]
    },
    {
      "sort": 4,
      "isCourierWarehouse": true,
      "loadType": "unloading",
      "warehouseId": "WH-TEEZ-001",
      "address": "Алматы, ул. Абая 150, склад TEEZ",
      "latitude": 43.2220,
      "longitude": 76.8512,
      "isSmsRequired": false,
      "isPhotoRequired": false,
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
  "transportationId": 12345,
  "externalWaybillId": "WB-2025-001",
  "orgId": "ORG-TEEZ-001",
  "routePointsCount": 4,
  "ordersCount": 2,
  "createdAt": "2025-01-06T12:00:00Z",
  "message": "Waybill imported successfully"
}
```

### Response (Duplicate)

**Status**: `200 OK` (если статус IMPORTED - обновляем)

```json
{
  "status": "updated",
  "transportationId": 12345,
  "externalWaybillId": "WB-2025-001",
  "orgId": "ORG-TEEZ-001",
  "routePointsCount": 4,
  "ordersCount": 2,
  "updatedAt": "2025-01-06T12:30:00Z",
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
  "externalWaybillId": "WB-2025-001",
  "orgId": "ORG-TEEZ-001",
  "currentStatus": "VALIDATED"
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

## 1.1. Реимпорт маршрутного листа от TEEZ (обновление)

### Request

**Endpoint**: `POST /api/v1/integration/waybills/reimport`
**Authentication**: `X-API-Key: {your-api-key}`
**Content-Type**: `application/json`

**Описание**: Обновление ранее импортированного маршрутного листа. Возможно только для маршрутов в статусе "импортированный черновик", до внесения изменений из UI.

```json
{
  "sourceSystem": "TEEZ_PVZ",
  "orgId": "ORG-TEEZ-001",
  "waybill": {
    "id": "WB-2025-001",
    "deliveryType": "courier",
    "warehouseExternalId": "WH-TEEZ-001",
    "responsibleManagerContactInfo": {
      "name": "Менеджер Алишер",
      "phone": "+7 000 000000"
    },
    "targetDeliveryDay": "2025-01-07"
  },
  "deliveries": [
    // ... полная структура как при первичном импорте
  ]
}
```

**Важные ограничения**:
- Возможно только из той же системы, из которой был первичный импорт
- Маршрут должен быть в статусе "импортированный черновик" (IMPORTED)
- После любых изменений из UI реимпорт заблокирован
- Идентификация по комбинации: externalWaybillId + sourceSystem + orgId

### Response (Success)

**Status**: `200 OK`

```json
{
  "status": "reimported",
  "transportationId": 12345,
  "externalWaybillId": "WB-2025-001",
  "orgId": "ORG-TEEZ-001",
  "previousVersion": 1,
  "newVersion": 2,
  "updatedAt": "2025-01-06T13:00:00Z",
  "message": "Waybill reimported successfully"
}
```

### Response (Forbidden)

**Status**: `403 Forbidden`

```json
{
  "status": "forbidden",
  "error": "WAYBILL_MODIFIED",
  "message": "Waybill has been modified in UI and cannot be reimported",
  "externalWaybillId": "WB-2025-001",
  "lastModifiedBy": "logist@teez.kz",
  "lastModifiedAt": "2025-01-06T12:45:00Z"
}
```

---

## 2. Получение статусов заказов по номерам (для TEEZ)

### Request

**Endpoint**: `GET /api/v1/integration/courier/orders/status`
**Authentication**: `X-API-Key: {your-api-key}`

**Описание**: TEEZ запрашивает текущие статусы заказов, передавая список трек-номеров. Этот endpoint позволяет получить актуальные статусы заказов в любое время, независимо от статуса маршрутного листа.

#### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `track_numbers` | String | Yes | Список трек-номеров через запятую (до 100 номеров за запрос) |
| `source_system` | String | No | Источник данных (default: `TEEZ_PVZ`) |

```bash
curl -X GET "https://api.coube.kz/api/v1/integration/courier/orders/status?track_numbers=TRACK-123456,TRACK-123457,TRACK-123458&source_system=TEEZ_PVZ" \
  -H "X-API-Key: your-api-key-here"
```

### Response (Success)

**Status**: `200 OK`

```json
{
  "orders": [
    {
      "track_number": "TRACK-123456",
      "external_id": "ORDER-TEEZ-001",
      "status": "with_courier",
      "status_reason": null,
      "status_datetime": "2025-01-07T09:00:00Z",
      "delivery_datetime": "2025-01-07T10:15:00Z",
      "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg",
      "receiver_name": "Иванов Иван Иванович",
      "receiver_phone": "+77771234567",
      "delivery_address": "Алматы, мкр. Самал-2, дом 58, кв. 12",
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
      "status": "delivered",
      "status_reason": null,
      "status_datetime": "2025-01-07T14:05:00Z",
      "delivery_datetime": "2025-01-07T14:05:00Z",
      "photo_url": "https://s3.coube.kz/courier/photos/789012.jpg",
      "receiver_name": "Петрова Анна",
      "receiver_phone": "+77779876543",
      "delivery_address": "Алматы, пр. Достык 97, офис 301",
      "courier_comment": null,
      "positions": [
        {
          "code": "POS-003",
          "name": "Документы",
          "qty": 1,
          "returned_qty": 0
        }
      ]
    },
    {
      "track_number": "TRACK-123458",
      "external_id": "ORDER-TEEZ-003",
      "status": "not_delivered",
      "status_reason": "customer_not_available",
      "status_datetime": "2025-01-07T15:30:00Z",
      "delivery_datetime": null,
      "photo_url": null,
      "receiver_name": "Сидоров Петр",
      "receiver_phone": "+77775554433",
      "delivery_address": "Алматы, ул. Розыбакиева 247",
      "courier_comment": "Клиент не отвечает на звонки",
      "positions": [
        {
          "code": "POS-004",
          "name": "Телефон",
          "qty": 1,
          "returned_qty": 1
        }
      ]
    }
  ],
  "not_found": ["TRACK-999999"]
}
```

#### Order Status Values (для TEEZ)

| Coube Status | TEEZ Mapping | Описание | Когда используется |
|--------------|--------------|----------|-------------------|
| `with_courier` | "Заказ у курьера" | Курьер принял маршрут с этим заказом | После старта маршрута курьером |
| `delivered` | "Доставлено курьером" | Успешная доставка | Курьер доставил и получил подтверждение |
| `not_delivered` | "Курьер не смог доставить" | Курьер не смог доставить (возврат) | Клиент недоступен/отказался/адрес не найден |
| `returned_to_sender` | "Возвращено отправителю" | Заказ возвращен на склад | Курьер вернул заказ на склад TEEZ |

#### Status Reason Values (для not_delivered)

| Reason Code | Описание для TEEZ |
|-------------|-------------------|
| `customer_not_available` | Клиент недоступен (не отвечает, не открывает) |
| `customer_refused` | Клиент отказался от заказа |
| `customer_postponed` | Клиент попросил перенести доставку |
| `address_not_found` | Адрес не найден |
| `other` | Другая причина |

**Примечание**: Если `status_reason` заполнен, значит доставка не состоялась по указанной причине.

### Response (Validation Error)

**Status**: `400 Bad Request`

**Описание**: Неверные параметры запроса (например, слишком много трек-номеров).

```json
{
  "error": "VALIDATION_ERROR",
  "message": "Too many track numbers. Maximum 100 per request",
  "max_allowed": 100,
  "provided": 150
}
```

### Response (No Orders Found)

**Status**: `200 OK`

**Описание**: Ни один из запрошенных заказов не найден.

```json
{
  "orders": [],
  "not_found": ["TRACK-111", "TRACK-222", "TRACK-333"]
}
```

### Rate Limiting

**Ограничения**:
- **60 запросов в минуту** на API key
- **1000 запросов в час** на API key
- **100 трек-номеров максимум** за один запрос

**Response при превышении лимита**:

**Status**: `429 Too Many Requests`

```json
{
  "error": "RATE_LIMIT_EXCEEDED",
  "message": "Rate limit exceeded. Try again later",
  "retry_after_seconds": 60,
  "limit": "60 requests per minute"
}
```

### Рекомендации по использованию

1. **Частота polling**: Рекомендуем запрашивать статусы каждые **5-10 минут**
2. **Batch requests**: Отправляйте до 100 трек-номеров за один запрос для оптимизации
3. **Обработка not_found**: Если заказ в `not_found`, он еще не создан в Coube или неверный номер
4. **Retry policy**: При `429` ошибке используйте exponential backoff

---

## 2.1. Редактирование маршрутного листа логистом

### Request

**Endpoint**: `PUT /api/v1/courier/waybills/{id}`
**Authentication**: `Bearer {keycloak-token}` (роль LOGISTICIAN)
**Content-Type**: `application/json`

**Описание**: Редактирование импортированного маршрутного листа. Доступно только для маршрутов в статусе FORMING.

```json
{
  "deliveries": [
    {
      "id": 5001,
      "sort": 1,
      "isCourierWarehouse": true,
      "loadType": "loading",
      "warehouseId": "WH-TEEZ-001",
      "address": "Алматы, ул. Абая 150, склад TEEZ",
      "latitude": 43.2220,
      "longitude": 76.8512,
      "orders": []
    },
    {
      "id": 5002,
      "sort": 2,
      "isCourierWarehouse": false,
      "loadType": "unloading",
      "address": "Алматы, мкр. Самал-1, дом 10",  // Изменен адрес
      "latitude": 43.2400,
      "longitude": 76.9600,
      "deliveryDesiredDatetime": "2025-01-07T11:00:00Z",  // Изменено время
      "isSmsRequired": true,
      "isPhotoRequired": true,
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77771234567"
      },
      "orders": [
        {
          "trackNumber": "TRACK-123456",  // READ-ONLY
          "externalId": "ORDER-TEEZ-001"   // READ-ONLY
        }
      ]
    },
    {
      "id": null,  // Новая точка
      "sort": 3,
      "isCourierWarehouse": false,
      "loadType": "unloading",
      "address": "Алматы, ул. Сатпаева 90",
      "latitude": 43.2350,
      "longitude": 76.9300,
      "deliveryDesiredDatetime": "2025-01-07T14:00:00Z",
      "receiver": {
        "name": "Новый получатель",
        "phone": "+77012345678"
      },
      "orders": []
    },
    {
      "id": 5004,
      "sort": 4,
      "isCourierWarehouse": true,
      "loadType": "unloading",
      "warehouseId": "WH-TEEZ-001",
      "address": "Алматы, ул. Абая 150, склад TEEZ",
      "orders": []
    }
  ]
}
```

### Response (Success)

**Status**: `200 OK`

```json
{
  "status": "success",
  "transportationId": 12345,
  "externalWaybillId": "WB-2025-001",
  "message": "Waybill updated successfully",
  "statistics": {
    "totalPoints": 4,
    "addedPoints": 1,
    "removedPoints": 1,
    "modifiedPoints": 1
  }
}
```

### Response (Invalid Status)

**Status**: `409 Conflict`

```json
{
  "status": "error",
  "error": "INVALID_STATUS",
  "message": "Waybill cannot be edited in current status",
  "currentStatus": "SIGNED_CUSTOMER",
  "allowedStatuses": ["FORMING"]
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

## 10. Интеграция с TEEZ: Резюме

### Что нужно TEEZ

**Endpoint для получения статусов**: `GET /api/v1/integration/courier/orders/status` (см. раздел 2)

**4 статуса для отслеживания**:
1. ✅ **"Заказ у курьера"** → `status: "with_courier"` - когда курьер начал маршрут
2. ✅ **"Доставлено курьером"** → `status: "delivered"` - успешная доставка
3. ✅ **"Курьер не смог доставить"** → `status: "not_delivered"` + `status_reason` - возврат из-за недоставки
4. ✅ **"Возвращено отправителю"** → `status: "returned_to_sender"` - заказ вернулся на склад

### Как различать статусы 3 и 4?

**Статус 3** (`not_delivered`): Курьер не смог доставить
- `status_reason` указывает причину: `customer_not_available`, `customer_refused`, `address_not_found`, etc.
- Заказ еще у курьера или на пути возврата

**Статус 4** (`returned_to_sender`): Заказ физически вернулся на склад TEEZ
- Курьер доставил заказ обратно на точку возврата (последняя точка маршрута с `is_courier_warehouse: true`)

### Рекомендуемый flow для TEEZ

```
1. TEEZ создает маршрутный лист → POST /api/v1/integration/waybills
2. TEEZ запускает polling каждые 5-10 минут
3. TEEZ запрашивает статусы → GET /api/v1/integration/courier/orders/status
   - Передает track_numbers через запятую (до 100 за раз)
4. TEEZ обрабатывает статусы и обновляет свою систему
5. При 429 ошибке - использовать exponential backoff
```

### Ограничения API

- ⏱️ **60 запросов в минуту** на API key
- ⏱️ **1000 запросов в час** на API key
- 📦 **100 трек-номеров максимум** за один запрос
- 🔁 **Рекомендуемая частота**: каждые 5-10 минут

### Открытые вопросы для TEEZ

1. ❓ Какая будет частота запросов статусов? (рекомендуем 5-10 минут)
2. ❓ Сколько заказов в среднем в одном маршруте? (для оценки нагрузки)
3. ❓ Нужно ли webhook-уведомление вместо polling? (опционально для оптимизации)

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
**Последнее обновление**: 2025-10-16 (webhook pull-модель)
**Версия**: 1.1
**Статус**: Ready for Testing
