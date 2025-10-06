# 04. API для веб-интерфейса логиста

## Обзор

API для работы логистов с курьерскими маршрутными листами через веб-интерфейс Coube.

**Base URL**: `/api/v1/courier`  
**Авторизация**: Bearer Token (JWT) с ролью `LOGIST` или `ADMIN`

---

## 1. Список курьерских маршрутных листов

### `GET /api/v1/courier/waybills`

**Описание**: Получение списка маршрутных листов с фильтрацией и пагинацией.

**Query Parameters**:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | integer | No | 0 | Номер страницы (0-based) |
| `size` | integer | No | 20 | Размер страницы (max 100) |
| `sort` | string | No | `targetDeliveryDay,desc` | Сортировка: `field,direction` |
| `validationStatus` | string | No | - | Фильтр по статусу |
| `assignedCourierId` | integer | No | - | ID назначенного курьера |
| `responsibleWarehouseId` | string | No | - | ID ответственного склада |
| `targetFrom` | date | No | - | Дата доставки от (YYYY-MM-DD) |
| `targetTo` | date | No | - | Дата доставки до (YYYY-MM-DD) |
| `externalWaybillId` | string | No | - | Поиск по ID из внешней системы (partial match) |
| `sourceSystem` | string | No | - | Фильтр по источнику (TEEZ_PVZ) |

**Возможные значения `validationStatus`**:
- `imported_draft` - Импортированный черновик
- `validated` - Провалидирован
- `assigned` - Назначен курьеру
- `in_route` - В пути
- `completed` - Завершен
- `closed` - Закрыт

**Возможные значения `sort`**:
- `targetDeliveryDay,asc|desc`
- `createdAt,asc|desc`
- `validationStatus,asc|desc`
- `externalWaybillId,asc|desc`

**Response - `200 OK`**:

```json
{
  "content": [
    {
      "id": 98765,
      "external_waybill_id": "WB-2025-001",
      "source_system": "TEEZ_PVZ",
      "delivery_type": "courier",
      "validation_status": "assigned",
      "responsible_courier_warehouse": {
        "id": "W-ALM-01",
        "name": "Склад Алматы Центральный",
        "address": "г. Алматы, ул. Складская 1"
      },
      "target_delivery_day": "2025-04-15",
      "assigned_courier": {
        "id": 543,
        "full_name": "Петров Петр Петрович",
        "phone": "+77011234567",
        "current_status": "assigned"
      },
      "statistics": {
        "total_points": 5,
        "total_orders": 8,
        "completed_orders": 0,
        "pending_orders": 8
      },
      "created_at": "2025-04-14T09:00:00Z",
      "updated_at": "2025-04-14T10:00:00Z",
      "last_event": {
        "type": "assigned",
        "datetime": "2025-04-14T10:00:00Z",
        "actor": "logist@coube.kz"
      }
    },
    {
      "id": 98764,
      "external_waybill_id": "WB-2025-002",
      "source_system": "TEEZ_PVZ",
      "delivery_type": "marketplace_delivery",
      "validation_status": "completed",
      "responsible_courier_warehouse": {
        "id": "W-ALM-02",
        "name": "ПВЗ Алматы Сатпаева",
        "address": "г. Алматы, пр. Сатпаева 50"
      },
      "target_delivery_day": "2025-04-14",
      "assigned_courier": {
        "id": 542,
        "full_name": "Иванова Мария Сергеевна",
        "phone": "+77017654321",
        "current_status": "free"
      },
      "statistics": {
        "total_points": 10,
        "total_orders": 15,
        "completed_orders": 12,
        "pending_orders": 0,
        "not_delivered_orders": 3
      },
      "created_at": "2025-04-13T08:00:00Z",
      "updated_at": "2025-04-14T17:00:00Z",
      "last_event": {
        "type": "completed",
        "datetime": "2025-04-14T17:00:00Z",
        "actor": "courier@teez.kz"
      }
    }
  ],
  "page": {
    "number": 0,
    "size": 20,
    "total_elements": 120,
    "total_pages": 6
  }
}
```

---

## 2. Просмотр маршрутного листа

### `GET /api/v1/courier/waybills/{id}`

**Описание**: Получение полной информации о маршрутном листе.

**Path Parameters**:
- `id` (required, integer) - ID маршрутного листа в Coube (transportation_id)

**Query Parameters**:
- `include_history` (boolean, default: false) - Включить историю изменений

**Response - `200 OK`**:

```json
{
  "id": 98765,
  "external_waybill_id": "WB-2025-001",
  "source_system": "TEEZ_PVZ",
  "delivery_type": "courier",
  "validation_status": "assigned",
  "responsible_courier_warehouse": {
    "id": "W-ALM-01",
    "name": "Склад Алматы Центральный",
    "address": "г. Алматы, ул. Складская 1",
    "coordinates": {
      "longitude": 76.945624,
      "latitude": 43.238293
    }
  },
  "target_delivery_day": "2025-04-15",
  "assigned_courier": {
    "id": 543,
    "employee_id": 123,
    "full_name": "Петров Петр Петрович",
    "phone": "+77011234567",
    "email": "courier@teez.kz",
    "current_status": "assigned",
    "assigned_at": "2025-04-14T10:00:00Z",
    "primary_pickup_point": "W-ALM-01"
  },
  "route_points": [
    {
      "id": 111,
      "sort_order": 1,
      "is_courier_warehouse": false,
      "warehouse_id": null,
      "address": "г. Алматы, ул. Абая 150, кв. 25",
      "coordinates": {
        "longitude": 76.945624,
        "latitude": 43.238293,
        "validated": true
      },
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
      ],
      "distance_from_prev_km": null,
      "estimated_arrival_time": null
    },
    {
      "id": 112,
      "sort_order": 2,
      "is_courier_warehouse": true,
      "warehouse_id": "W-ALM-01",
      "address": "г. Алматы, ул. Складская 1",
      "coordinates": {
        "longitude": 76.945624,
        "latitude": 43.238293,
        "validated": true
      },
      "desired_window": null,
      "is_sms_required": false,
      "is_photo_required": false,
      "load_type": null,
      "comment": "Финальный склад",
      "receiver": null,
      "status": "pending",
      "orders": [],
      "distance_from_prev_km": 5.2,
      "estimated_arrival_time": "2025-04-15T17:00:00+06:00"
    }
  ],
  "statistics": {
    "total_points": 2,
    "total_orders": 1,
    "completed_orders": 0,
    "pending_orders": 1,
    "delivered_orders": 0,
    "returned_orders": 0,
    "not_delivered_orders": 0,
    "total_distance_km": 5.2,
    "estimated_duration_hours": 2.5
  },
  "history": [
    {
      "id": 1,
      "event_type": "imported",
      "event_datetime": "2025-04-14T09:00:00Z",
      "actor_id": null,
      "actor_type": "integration",
      "description": "Waybill imported from TEEZ_PVZ",
      "details": null
    },
    {
      "id": 2,
      "event_type": "validated",
      "event_datetime": "2025-04-14T09:30:00Z",
      "actor_id": 456,
      "actor_type": "logist",
      "description": "Waybill validated by logist@coube.kz",
      "details": {
        "addresses_synced": true,
        "final_warehouse_added": false
      }
    },
    {
      "id": 3,
      "event_type": "assigned",
      "event_datetime": "2025-04-14T10:00:00Z",
      "actor_id": 456,
      "actor_type": "logist",
      "description": "Courier Петров П.П. assigned",
      "details": {
        "courier_id": 543,
        "courier_name": "Петров Петр Петрович"
      }
    }
  ],
  "metadata": {
    "editable": false,
    "allowed_actions": ["unassign", "view_on_map"],
    "can_assign_courier": false,
    "can_validate": false,
    "can_edit_points": false
  },
  "created_at": "2025-04-14T09:00:00Z",
  "updated_at": "2025-04-14T10:00:00Z"
}
```

**Response - `404 Not Found`**:

```json
{
  "status": "error",
  "error_code": "waybill_not_found",
  "message": "Waybill with id 98765 not found"
}
```

---

## 3. Редактирование маршрутного листа

### `PUT /api/v1/courier/waybills/{id}`

**Описание**: Редактирование точек маршрута, адресов, временных окон.

**Ограничения**: Только для статусов `imported_draft` или `validated`.

**Path Parameters**:
- `id` (required, integer)

**Request Body**:

```json
{
  "target_delivery_day": "2025-04-15",
  "route_points": [
    {
      "id": 111,
      "sort_order": 1,
      "address": "г. Алматы, ул. Абая 150, кв. 25",
      "desired_window": {
        "from": "2025-04-15T14:00:00+06:00",
        "to": "2025-04-15T16:00:00+06:00"
      },
      "is_sms_required": true,
      "is_photo_required": false,
      "comment": "Позвонить за 30 минут. Домофон 25",
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77012345678"
      }
    },
    {
      "id": null,
      "sort_order": 2,
      "address": "г. Алматы, ул. Новая 99",
      "desired_window": {
        "at": "2025-04-15T11:00:00+06:00"
      },
      "is_sms_required": false,
      "is_photo_required": true,
      "comment": "",
      "receiver": {
        "name": "Новый клиент",
        "phone": "+77019999999"
      },
      "orders": []
    }
  ]
}
```

**Логика**:
- Если `id` точки указан — обновление существующей
- Если `id = null` — создание новой точки
- Если точка отсутствует в запросе — она удаляется (кроме финального склада)

**Response - `200 OK`**:

```json
{
  "status": "updated",
  "transportation_id": 98765,
  "updated_points": 2,
  "added_points": 1,
  "deleted_points": 0,
  "validation_errors": [],
  "message": "Waybill updated successfully"
}
```

**Response - `409 Conflict`**:

```json
{
  "status": "error",
  "error_code": "waybill_locked",
  "message": "Cannot edit waybill in status 'in_route'",
  "current_status": "in_route"
}
```

---

## 4. Валидация маршрутного листа

### `POST /api/v1/courier/waybills/{id}/validate`

**Описание**: Перевод черновика в статус `validated` после ручной проверки логистом.

**Path Parameters**:
- `id` (required, integer)

**Request Body**:

```json
{
  "force_sync_addresses": true,
  "add_final_warehouse": true,
  "comment": "Все адреса проверены вручную"
}
```

**Валидации перед переводом**:
- Все адреса должны быть синхронизированы с картой (геокодированы)
- Последняя точка — курьерский склад
- Нет дублирующихся `sort_order`
- Все обязательные поля заполнены

**Response - `200 OK`**:

```json
{
  "status": "validated",
  "transportation_id": 98765,
  "validation_status": "validated",
  "validated_at": "2025-04-14T09:30:00Z",
  "validated_by": "logist@coube.kz",
  "message": "Waybill validated successfully"
}
```

**Response - `422 Unprocessable Entity`**:

```json
{
  "status": "validation_failed",
  "errors": [
    {
      "field": "route_points[1].address",
      "code": "address_not_geocoded",
      "message": "Address must be synced with map before validation"
    }
  ]
}
```

---

## 5. Назначение курьера

### `POST /api/v1/courier/waybills/{id}/assign`

**Описание**: Назначение курьера на маршрутный лист.

**Ограничения**: Только для статуса `validated`.

**Path Parameters**:
- `id` (required, integer)

**Request Body**:

```json
{
  "courier_id": 543,
  "send_notification": true,
  "comment": "Назначен Петров П.П., опыт 3 года"
}
```

**Валидации**:
- Маршрут должен быть в статусе `validated`
- Курьер не должен иметь активных маршрутов
- Курьер должен быть в статусе `free`

**Response - `200 OK`**:

```json
{
  "status": "assigned",
  "transportation_id": 98765,
  "assigned_courier": {
    "id": 543,
    "full_name": "Петров Петр Петрович",
    "phone": "+77011234567",
    "current_status": "assigned"
  },
  "notification_sent": true,
  "assigned_at": "2025-04-14T10:00:00Z"
}
```

**Response - `409 Conflict`**:

```json
{
  "status": "error",
  "error_code": "courier_already_assigned",
  "message": "Courier Петров П.П. already has active waybill WB-2025-003",
  "conflicting_waybill_id": "WB-2025-003"
}
```

---

## 6. Снятие курьера

### `POST /api/v1/courier/waybills/{id}/unassign`

**Описание**: Снятие курьера с маршрута.

**Path Parameters**:
- `id` (required, integer)

**Request Body**:

```json
{
  "reason": "Курьер заболел",
  "send_notification": true
}
```

**Response - `200 OK`**:

```json
{
  "status": "unassigned",
  "transportation_id": 98765,
  "previous_courier": {
    "id": 543,
    "full_name": "Петров Петр Петрович"
  },
  "new_status": "validated",
  "unassigned_at": "2025-04-14T11:00:00Z"
}
```

---

## 7. Закрытие маршрута

### `POST /api/v1/courier/waybills/{id}/close`

**Описание**: Финальное закрытие маршрута логистом после возврата курьера на склад.

**Ограничения**: Только для статуса `completed`.

**Request Body**:

```json
{
  "comment": "Все заказы сверены на складе",
  "confirmed_returns": [
    {
      "order_id": 999,
      "track_number": "AC-323123123",
      "confirmed_status": "delivered"
    },
    {
      "order_id": 1000,
      "track_number": "AC-555666777",
      "confirmed_status": "returned",
      "warehouse_acceptance_confirmed": true
    }
  ]
}
```

**Response - `200 OK`**:

```json
{
  "status": "closed",
  "transportation_id": 98765,
  "closed_at": "2025-04-15T18:00:00Z",
  "closed_by": "logist@coube.kz",
  "final_statistics": {
    "total_orders": 5,
    "delivered": 3,
    "returned": 1,
    "not_delivered": 1
  }
}
```

---

## 8. Управление курьерами

### `GET /api/v1/courier/couriers`

**Описание**: Получение списка курьеров.

**Query Parameters**:
- `status` (string) - Фильтр по статусу: `free`, `in_route`, `unavailable`
- `primary_pickup_point_id` (string) - Фильтр по ПВЗ
- `search` (string) - Поиск по имени/телефону/email
- `page`, `size`, `sort`

**Response - `200 OK`**:

```json
{
  "content": [
    {
      "id": 543,
      "employee_id": 123,
      "full_name": "Петров Петр Петрович",
      "phone": "+77011234567",
      "email": "courier@teez.kz",
      "current_status": "free",
      "primary_pickup_point": {
        "id": "W-ALM-01",
        "name": "Склад Алматы Центральный"
      },
      "active_waybill": null,
      "integration_data": [
        {
          "system": "TEEZ_PVZ",
          "external_id": "courier-123"
        }
      ],
      "created_at": "2025-01-01T00:00:00Z"
    }
  ],
  "page": {
    "number": 0,
    "size": 20,
    "total_elements": 50,
    "total_pages": 3
  }
}
```

### `POST /api/v1/courier/couriers`

**Описание**: Создание нового курьера.

**Request Body**:

```json
{
  "person": {
    "first_name": "Петр",
    "last_name": "Петров",
    "middle_name": "Петрович",
    "phone": "+77011234567",
    "email": "courier@teez.kz",
    "iin": "900101123456"
  },
  "organization_id": 321,
  "primary_pickup_point_id": "W-ALM-01",
  "integration_payload": [
    {
      "system": "TEEZ_PVZ",
      "external_id": "courier-123"
    }
  ],
  "comment": "Опыт работы 3 года"
}
```

**Response - `201 Created`**:

```json
{
  "id": 543,
  "employee_id": 123,
  "full_name": "Петров Петр Петрович",
  "phone": "+77011234567",
  "email": "courier@teez.kz",
  "current_status": "free",
  "role": "COURIER_DRIVER",
  "created_at": "2025-04-14T12:00:00Z"
}
```

### `PATCH /api/v1/courier/couriers/{id}`

**Описание**: Обновление атрибутов курьера.

**Request Body**:

```json
{
  "current_status": "unavailable",
  "primary_pickup_point_id": "W-ALM-02",
  "phone": "+77017777777",
  "comment": "Переведен на другой склад"
}
```

**Response - `200 OK`**: Обновленный объект курьера.

---

## 9. Аналитика и отчеты

### `GET /api/v1/courier/analytics/summary`

**Описание**: Сводная аналитика по курьерским доставкам.

**Query Parameters**:
- `date_from`, `date_to` (required)
- `warehouse_id` (optional)
- `courier_id` (optional)

**Response**:

```json
{
  "period": {
    "from": "2025-04-01",
    "to": "2025-04-30"
  },
  "total_waybills": 120,
  "total_orders": 500,
  "delivered": 450,
  "returned": 30,
  "not_delivered": 20,
  "delivery_success_rate": 90.0,
  "avg_orders_per_route": 4.2,
  "top_couriers": [
    {
      "courier_id": 543,
      "full_name": "Петров П.П.",
      "completed_routes": 25,
      "success_rate": 95.0
    }
  ]
}
```

---

## 10. Коды ошибок

| Код | HTTP | Описание |
|-----|------|----------|
| `waybill_not_found` | 404 | Маршрутный лист не найден |
| `waybill_locked` | 409 | Маршрут заблокирован для редактирования |
| `courier_already_assigned` | 409 | Курьер уже занят другим маршрутом |
| `validation_failed` | 422 | Ошибки валидации |
| `unauthorized` | 401 | Неверный токен |
| `forbidden` | 403 | Недостаточно прав |
