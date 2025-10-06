# 05. API для мобильного приложения курьера

## Обзор

API для работы курьеров через мобильное приложение Coube Mobile.

**Base URL**: `/api/v1/courier/mobile`  
**Авторизация**: Bearer Token (JWT) с ролью `COURIER_DRIVER`

---

## 1. Активный маршрут курьера

### `GET /api/v1/courier/mobile/waybills/active`

**Описание**: Получение текущего активного маршрутного листа курьера.

**Headers**:
```
Authorization: Bearer {jwt_token}
```

**Response - `200 OK` (есть активный маршрут)**:

```json
{
  "waybill": {
    "id": 98765,
    "external_waybill_id": "WB-2025-001",
    "target_delivery_day": "2025-04-15",
    "status": "assigned",
    "responsible_warehouse": {
      "id": "W-ALM-01",
      "name": "Склад Алматы Центральный",
      "address": "г. Алматы, ул. Складская 1",
      "coordinates": {
        "longitude": 76.945624,
        "latitude": 43.238293
      },
      "phone": "+77012220000"
    },
    "route_started": false,
    "started_at": null,
    "current_point_index": 0,
    "points": [
      {
        "id": 111,
        "sort_order": 1,
        "status": "pending",
        "is_courier_warehouse": false,
        "address": "г. Алматы, ул. Абая 150, кв. 25",
        "coordinates": {
          "longitude": 76.950000,
          "latitude": 43.240000
        },
        "desired_window": {
          "from": "2025-04-15T14:00:00+06:00",
          "to": "2025-04-15T16:00:00+06:00"
        },
        "comment": "Позвонить за 30 минут. Домофон 25",
        "receiver": {
          "name": "Иванов Иван Иванович",
          "phone": "+77012345678"
        },
        "distance_from_current_km": 5.2,
        "estimated_arrival_minutes": 15,
        "orders": [
          {
            "id": 999,
            "track_number": "AC-323123123",
            "external_id": "ORD-123456",
            "status": "pending",
            "is_sms_required": true,
            "is_photo_required": false,
            "positions": [
              {
                "position_code": "POS-001",
                "position_shortname": "Холодильник Samsung, 200кг",
                "quantity": 1
              }
            ]
          }
        ]
      },
      {
        "id": 112,
        "sort_order": 2,
        "status": "pending",
        "is_courier_warehouse": false,
        "address": "г. Алматы, мкр. Аксай-4, д. 25",
        "coordinates": {
          "longitude": 76.960000,
          "latitude": 43.245000
        },
        "desired_window": {
          "at": "2025-04-15T10:30:00+06:00"
        },
        "comment": "",
        "receiver": {
          "name": "ТОО Ромашка (Петров П.)",
          "phone": "+77017654321"
        },
        "distance_from_current_km": 10.5,
        "estimated_arrival_minutes": 30,
        "orders": [
          {
            "id": 1000,
            "track_number": "AC-555666777",
            "external_id": "ORD-789012",
            "status": "pending",
            "is_sms_required": false,
            "is_photo_required": true,
            "positions": [
              {
                "position_code": "POS-100",
                "position_shortname": "Ноутбук Dell",
                "quantity": 1
              }
            ]
          }
        ]
      },
      {
        "id": 113,
        "sort_order": 3,
        "status": "pending",
        "is_courier_warehouse": true,
        "address": "г. Алматы, ул. Складская 1",
        "coordinates": {
          "longitude": 76.945624,
          "latitude": 43.238293
        },
        "comment": "Финальный склад",
        "receiver": null,
        "distance_from_current_km": 15.2,
        "estimated_arrival_minutes": 45,
        "orders": []
      }
    ],
    "statistics": {
      "total_points": 3,
      "completed_points": 0,
      "pending_points": 3,
      "total_orders": 2,
      "pending_orders": 2,
      "total_distance_km": 15.2
    },
    "assigned_at": "2025-04-14T10:00:00Z"
  }
}
```

**Response - `200 OK` (нет активного маршрута)**:

```json
{
  "waybill": null,
  "message": "No active waybill assigned"
}
```

---

## 2. История маршрутов

### `GET /api/v1/courier/mobile/waybills/history`

**Описание**: История выполненных маршрутов курьера.

**Query Parameters**:
- `page` (integer, default: 0)
- `size` (integer, default: 10)
- `date_from` (date, optional)
- `date_to` (date, optional)

**Response - `200 OK`**:

```json
{
  "waybills": [
    {
      "id": 98764,
      "external_waybill_id": "WB-2025-002",
      "target_delivery_day": "2025-04-14",
      "status": "closed",
      "started_at": "2025-04-14T09:00:00Z",
      "completed_at": "2025-04-14T17:00:00Z",
      "statistics": {
        "total_orders": 15,
        "delivered": 12,
        "returned": 1,
        "not_delivered": 2
      },
      "rating": {
        "success_rate": 80.0,
        "on_time_rate": 90.0
      }
    }
  ],
  "page": {
    "number": 0,
    "size": 10,
    "total_elements": 25,
    "total_pages": 3
  }
}
```

---

## 3. Принять назначение

### `POST /api/v1/courier/mobile/waybills/{id}/accept`

**Описание**: Курьер принимает назначенный маршрут.

**Path Parameters**:
- `id` (required, integer) - ID маршрутного листа

**Request Body**:

```json
{
  "accepted_at": "2025-04-15T08:00:00+06:00",
  "device_info": {
    "device_id": "device-uuid-123",
    "platform": "android",
    "app_version": "1.5.0"
  }
}
```

**Response - `200 OK`**:

```json
{
  "status": "accepted",
  "waybill_id": 98765,
  "message": "Waybill accepted successfully",
  "accepted_at": "2025-04-15T08:00:00+06:00"
}
```

**Response - `409 Conflict`**:

```json
{
  "status": "error",
  "error_code": "waybill_already_started",
  "message": "Waybill is already in progress"
}
```

---

## 4. Отклонить назначение

### `POST /api/v1/courier/mobile/waybills/{id}/decline`

**Описание**: Курьер отклоняет назначенный маршрут.

**Request Body**:

```json
{
  "reason": "Болен",
  "comment": "Температура, не смогу работать сегодня"
}
```

**Response - `200 OK`**:

```json
{
  "status": "declined",
  "waybill_id": 98765,
  "message": "Waybill declined, logist will be notified",
  "declined_at": "2025-04-15T08:00:00+06:00"
}
```

---

## 5. Начать маршрут

### `POST /api/v1/courier/mobile/waybills/{id}/start`

**Описание**: Курьер начинает выполнение маршрута.

**Request Body**:

```json
{
  "current_location": {
    "longitude": 76.945624,
    "latitude": 43.238293,
    "accuracy": 10.5
  },
  "started_at": "2025-04-15T09:00:00+06:00"
}
```

**Response - `200 OK`**:

```json
{
  "status": "started",
  "waybill_id": 98765,
  "new_status": "in_route",
  "started_at": "2025-04-15T09:00:00+06:00",
  "first_point": {
    "id": 111,
    "sort_order": 1,
    "address": "г. Алматы, ул. Абая 150, кв. 25",
    "distance_km": 5.2
  }
}
```

---

## 6. Изменить статус точки маршрута

### `POST /api/v1/courier/mobile/waybills/{waybillId}/points/{pointId}/status`

**Описание**: Изменение статуса точки и заказов в ней.

**Path Parameters**:
- `waybillId` (required, integer)
- `pointId` (required, integer)

**Request Body - Успешная доставка**:

```json
{
  "point_status": "completed",
  "arrival_location": {
    "longitude": 76.950000,
    "latitude": 43.240000,
    "accuracy": 5.0
  },
  "arrival_time": "2025-04-15T14:30:00+06:00",
  "orders": [
    {
      "order_id": 999,
      "status": "delivered",
      "sms_code": "123456",
      "photo_id": "3f6b0f6e-1234-5678-9abc-def012345678",
      "comment": "Доставлен успешно",
      "delivered_at": "2025-04-15T14:35:00+06:00"
    }
  ]
}
```

**Request Body - Возврат (полный)**:

```json
{
  "point_status": "completed",
  "arrival_location": {
    "longitude": 76.950000,
    "latitude": 43.240000,
    "accuracy": 5.0
  },
  "arrival_time": "2025-04-15T15:00:00+06:00",
  "orders": [
    {
      "order_id": 1000,
      "status": "returned",
      "sms_code": "654321",
      "photo_id": "abc123-5678-9abc-def012345678",
      "comment": "Клиент полностью вернул заказ",
      "returned_at": "2025-04-15T15:05:00+06:00"
    }
  ]
}
```

**Request Body - Частичный возврат**:

```json
{
  "point_status": "completed",
  "arrival_location": {
    "longitude": 76.950000,
    "latitude": 43.240000,
    "accuracy": 5.0
  },
  "arrival_time": "2025-04-15T13:00:00+06:00",
  "orders": [
    {
      "order_id": 1001,
      "status": "partially_returned",
      "sms_code": "999888",
      "photo_id": "partial-return-photo-id",
      "comment": "Клиент принял телевизор, холодильник вернул",
      "return_parts": [
        {
          "position_code": "POS-001",
          "quantity": 1,
          "reason": "Клиент передумал"
        }
      ],
      "delivered_at": "2025-04-15T13:10:00+06:00"
    }
  ]
}
```

**Request Body - Не доставлен**:

```json
{
  "point_status": "completed",
  "arrival_location": {
    "longitude": 76.950000,
    "latitude": 43.240000,
    "accuracy": 5.0
  },
  "arrival_time": "2025-04-15T16:00:00+06:00",
  "orders": [
    {
      "order_id": 1002,
      "status": "not_delivered",
      "status_reason": "customer_not_available",
      "comment": "Не дозвонился, клиент не отвечает на звонки",
      "attempt_time": "2025-04-15T16:00:00+06:00"
    }
  ]
}
```

**Request Body - Курьер не доехал до точки**:

```json
{
  "point_status": "skipped",
  "current_location": {
    "longitude": 76.940000,
    "latitude": 43.235000,
    "accuracy": 10.0
  },
  "skip_time": "2025-04-15T17:00:00+06:00",
  "orders": [
    {
      "order_id": 1003,
      "status": "not_reached",
      "status_reason": "force_majeure",
      "comment": "ДТП на дороге, проезд перекрыт. Не смог добраться"
    }
  ]
}
```

### Response - `200 OK`

```json
{
  "status": "point_completed",
  "point_id": 111,
  "orders_processed": 1,
  "next_point": {
    "id": 112,
    "sort_order": 2,
    "address": "г. Алматы, мкр. Аксай-4, д. 25",
    "distance_km": 5.0,
    "estimated_arrival_minutes": 15
  },
  "route_progress": {
    "completed_points": 1,
    "total_points": 3,
    "completed_orders": 1,
    "total_orders": 2,
    "remaining_distance_km": 10.0
  }
}
```

### Возможные значения `status` для заказа

| Status | Description | Обязательные поля |
|--------|-------------|-------------------|
| `delivered` | Доставлен успешно | `sms_code` (если требуется), `photo_id` (если требуется) |
| `returned` | Полный возврат | `sms_code`, `photo_id` |
| `partially_returned` | Частичный возврат | `sms_code`, `photo_id`, `return_parts[]` |
| `not_delivered` | Не доставлен | `status_reason`, `comment` |
| `not_reached` | Курьер не доехал | `status_reason`, `comment` |

### Возможные значения `status_reason`

- `customer_not_available` - Клиент недоступен (не дозвонились/не открыл)
- `customer_postponed` - Клиент попросил отложить
- `force_majeure` - Форс-мажор (ДТП, дорога перекрыта и т.д.)

---

## 7. Завершить маршрут

### `POST /api/v1/courier/mobile/waybills/{id}/complete`

**Описание**: Курьер завершает маршрут после прохождения всех точек.

**Request Body**:

```json
{
  "completion_location": {
    "longitude": 76.945624,
    "latitude": 43.238293,
    "accuracy": 5.0
  },
  "completion_time": "2025-04-15T16:00:00+06:00",
  "comment": "Все точки пройдены, возвращаюсь на склад"
}
```

**Response - `200 OK`**:

```json
{
  "status": "route_completed",
  "waybill_id": 98765,
  "new_status": "completed",
  "completed_at": "2025-04-15T16:00:00+06:00",
  "final_statistics": {
    "total_orders": 5,
    "delivered": 3,
    "returned": 1,
    "not_delivered": 1,
    "completion_rate": 80.0
  },
  "return_to_warehouse": {
    "warehouse_id": "W-ALM-01",
    "warehouse_name": "Склад Алматы Центральный",
    "address": "г. Алматы, ул. Складская 1",
    "distance_km": 5.0
  },
  "message": "Маршрут завершен. Возвращайтесь на склад для сдачи возвратов"
}
```

---

## 8. Подтвердить возврат на склад

### `POST /api/v1/courier/mobile/waybills/{id}/finish`

**Описание**: Курьер подтверждает возвращение на склад и сдачу возвратов.

**Request Body**:

```json
{
  "arrival_at_warehouse_time": "2025-04-15T16:30:00+06:00",
  "arrival_location": {
    "longitude": 76.945624,
    "latitude": 43.238293,
    "accuracy": 5.0
  },
  "returned_orders": [
    {
      "order_id": 1000,
      "track_number": "AC-555666777",
      "handed_over": true,
      "warehouse_employee_name": "Склад работник",
      "comment": "Возврат сдан"
    }
  ],
  "comment": "Все возвраты сданы на склад"
}
```

**Response - `200 OK`**:

```json
{
  "status": "finished",
  "waybill_id": 98765,
  "finished_at": "2025-04-15T16:30:00+06:00",
  "message": "Маршрут полностью завершен. Спасибо за работу!",
  "performance": {
    "total_orders": 5,
    "delivered": 3,
    "returned": 1,
    "not_delivered": 1,
    "success_rate": 80.0,
    "on_time_deliveries": 4,
    "on_time_rate": 80.0,
    "total_distance_km": 15.2,
    "total_duration_hours": 7.5
  }
}
```

---

## 9. Загрузка фото

### `POST /api/v1/courier/mobile/upload-photo`

**Описание**: Загрузка фото подтверждения доставки.

**Content-Type**: `multipart/form-data`

**Form Data**:
- `file` (required, file) - Фото файл (JPEG, PNG, max 5MB)
- `order_id` (required, integer) - ID заказа
- `photo_type` (required, string) - Тип фото: `delivery_confirmation`, `return_confirmation`, `problem_photo`

**Response - `201 Created`**:

```json
{
  "photo_id": "3f6b0f6e-1234-5678-9abc-def012345678",
  "photo_url": "https://coube-storage.s3.amazonaws.com/courier/photos/3f6b0f6e.jpg",
  "uploaded_at": "2025-04-15T14:32:00Z",
  "file_size_bytes": 1024000,
  "order_id": 999
}
```

---

## 10. Отправка геолокации (фоновая)

### `POST /api/v1/courier/mobile/location`

**Описание**: Периодическая отправка геолокации курьера во время маршрута.

**Частота**: Каждые 30 секунд (во время активного маршрута)

**Request Body**:

```json
{
  "waybill_id": 98765,
  "location": {
    "longitude": 76.950000,
    "latitude": 43.240000,
    "accuracy": 5.0,
    "speed": 40.0,
    "heading": 180.0
  },
  "timestamp": "2025-04-15T14:30:00+06:00",
  "device_id": "device-uuid-123"
}
```

**Response - `202 Accepted`**:

```json
{
  "status": "location_recorded",
  "timestamp": "2025-04-15T14:30:00+06:00"
}
```

---

## 11. Получение краткой сводки

### `GET /api/v1/courier/mobile/dashboard`

**Описание**: Краткая сводка для главного экрана мобильного приложения.

**Response - `200 OK`**:

```json
{
  "courier": {
    "id": 543,
    "full_name": "Петров Петр Петрович",
    "current_status": "in_route"
  },
  "active_waybill": {
    "id": 98765,
    "external_waybill_id": "WB-2025-001",
    "status": "in_route",
    "current_point_index": 1,
    "progress": {
      "completed_points": 1,
      "total_points": 3,
      "completed_orders": 1,
      "total_orders": 2
    }
  },
  "today_statistics": {
    "completed_routes": 0,
    "total_deliveries": 1,
    "total_distance_km": 5.2
  },
  "notifications": [
    {
      "id": 1,
      "type": "reminder",
      "message": "Не забудьте взять SMS код у клиента",
      "created_at": "2025-04-15T14:00:00Z"
    }
  ]
}
```

---

## 12. Сообщить о проблеме

### `POST /api/v1/courier/mobile/report-problem`

**Описание**: Сообщить логисту о проблеме во время маршрута.

**Request Body**:

```json
{
  "waybill_id": 98765,
  "point_id": 111,
  "order_id": 999,
  "problem_type": "address_not_found",
  "description": "Указанный адрес не существует, дом снесен",
  "photos": [
    "photo-id-1",
    "photo-id-2"
  ],
  "current_location": {
    "longitude": 76.950000,
    "latitude": 43.240000
  },
  "reported_at": "2025-04-15T15:00:00+06:00"
}
```

**Возможные значения `problem_type`**:
- `address_not_found` - Адрес не найден
- `road_blocked` - Дорога перекрыта
- `customer_aggressive` - Агрессивное поведение клиента
- `vehicle_breakdown` - Поломка транспорта
- `other` - Другое

**Response - `200 OK`**:

```json
{
  "problem_id": 123,
  "status": "reported",
  "message": "Проблема зарегистрирована. Логист свяжется с вами в ближайшее время",
  "ticket_number": "PROB-2025-123",
  "reported_at": "2025-04-15T15:00:00+06:00"
}
```

---

## 13. Получить помощь / SOS

### `POST /api/v1/courier/mobile/sos`

**Описание**: Экстренный вызов помощи.

**Request Body**:

```json
{
  "waybill_id": 98765,
  "sos_type": "accident",
  "description": "ДТП, нужна помощь",
  "current_location": {
    "longitude": 76.950000,
    "latitude": 43.240000,
    "accuracy": 5.0
  },
  "timestamp": "2025-04-15T16:00:00+06:00"
}
```

**Возможные значения `sos_type`**:
- `accident` - ДТП
- `medical` - Медицинская помощь
- `security` - Угроза безопасности
- `other` - Другое

**Response - `200 OK`**:

```json
{
  "sos_id": 456,
  "status": "alert_sent",
  "message": "Экстренный сигнал отправлен. С вами свяжутся в течение 2 минут",
  "emergency_contact": {
    "name": "Служба поддержки Coube",
    "phone": "+77010000000"
  },
  "timestamp": "2025-04-15T16:00:00+06:00"
}
```

---

## 14. Коды ошибок

| Код | HTTP | Описание |
|-----|------|----------|
| `no_active_waybill` | 404 | Нет активного маршрута |
| `waybill_not_assigned` | 403 | Маршрут не назначен данному курьеру |
| `waybill_already_started` | 409 | Маршрут уже начат |
| `point_not_found` | 404 | Точка маршрута не найдена |
| `order_not_found` | 404 | Заказ не найден |
| `invalid_sms_code` | 422 | Неверный SMS код |
| `photo_required` | 422 | Требуется фото |
| `location_accuracy_low` | 422 | Низкая точность геолокации |
| `unauthorized` | 401 | Неверный токен |
| `forbidden` | 403 | Недостаточно прав |

---

## 15. WebSocket для реального времени (опционально)

### `WS /api/v1/courier/mobile/ws`

**Описание**: WebSocket соединение для получения уведомлений в реальном времени.

**События**:
- `waybill.assigned` - Новый маршрут назначен
- `waybill.unassigned` - Маршрут снят
- `message.from_logist` - Сообщение от логиста
- `route.updated` - Маршрут обновлен

**Пример сообщения**:
```json
{
  "event": "message.from_logist",
  "timestamp": "2025-04-15T15:00:00Z",
  "data": {
    "message": "Клиент по адресу Абая 150 перенес доставку на 17:00",
    "waybill_id": 98765,
    "point_id": 111
  }
}
```
