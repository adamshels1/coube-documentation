# 01. Постоянное отслеживание локации водителя (Always-On Location)

**Дата создания**: 2026-02-11
**Статус**: TO DO
**Приоритет**: MEDIUM
**Автор**: Ali

---

## Проблема

**Бизнес-кейс:**
Нужно знать текущее местоположение всех водителей (включая курьеров без ТС), даже когда у них нет активного заказа.

**Текущая ситуация:**
- ✅ Локация сохраняется при активной перевозке (ON_THE_WAY, DRIVER_ACCEPTED) в `gis.driver_location`
- ✅ Для ТС обновляется `gis.veh_latest_loc`
- ❌ Если у водителя нет активной перевозки — запрос игнорируется, ничего не сохраняется
- ❌ Мобилка отправляет локацию только при активном заказе
- ❌ Курьеры без ТС и без заказа — полностью невидимы

**Решение:**
Всегда сохранять последнюю позицию водителя в новую таблицу `gis.employee_latest_loc`. Мобилка всегда отправляет локацию: часто при заказе, редко (раз в 30 мин) без заказа.

---

## Архитектура решения

```
┌─────────────────────────────────────────────────┐
│  Mobile App                                     │
│                                                 │
│  С заказом (ON_THE_WAY):                        │
│    distanceFilter: 30м                          │
│    interval: 30 сек                             │
│    accuracy: MEDIUM                             │
│                                                 │
│  Без заказа (idle):                             │
│    distanceFilter: 500м                         │
│    interval: 30 мин                             │
│    accuracy: LOW                                │
└────────────────┬────────────────────────────────┘
                 │
                 │ POST /api/v1/driver/location
                 ↓
┌─────────────────────────────────────────────────┐
│  DriverLocationService.save()                   │
│                                                 │
│  1. ВСЕГДА → upsert в employee_latest_loc       │
│  2. Есть перевозка → insert в driver_location   │
│  3. Есть ТС → update veh_latest_loc             │
└─────────────────────────────────────────────────┘
```

---

## Изменения в БД

### Новая таблица `gis.employee_latest_loc`

```sql
CREATE TABLE gis.employee_latest_loc (
    employee_id  BIGINT PRIMARY KEY REFERENCES users.employee(id) ON DELETE CASCADE,
    location     GEOGRAPHY(Point, 4326) NOT NULL,
    timestamp    TIMESTAMP NOT NULL,
    accuracy     NUMERIC,
    speed        NUMERIC,
    heading      NUMERIC,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_employee_latest_loc_location ON gis.employee_latest_loc USING GIST (location);
```

**Характеристики:**
- 1 строка на водителя (upsert)
- Маленькая таблица — только текущая позиция
- Не зависит от transportation и vehicle
- Работает для всех: водители с ТС, курьеры без ТС, с заказом и без

---

## Backend изменения

### 1. Flyway миграция

**File:** `coube-backend/src/main/resources/db/migration/gis/V{timestamp}__add_employee_latest_loc.sql`

Создать таблицу `gis.employee_latest_loc` (SQL выше).

### 2. Entity: EmployeeLatestLocation

**File:** `coube-backend/src/main/java/kz/coube/backend/driver/model/EmployeeLatestLocation.java`

```java
@Entity
@Table(name = "employee_latest_loc", schema = "gis")
public class EmployeeLatestLocation {
    @Id
    @Column(name = "employee_id")
    private Long employeeId;

    @OneToOne(fetch = FetchType.LAZY)
    @MapsId
    @JoinColumn(name = "employee_id")
    private Employee employee;

    @Column(columnDefinition = "geography(Point, 4326)", nullable = false)
    private Point location;

    @Column(nullable = false)
    private LocalDateTime timestamp;

    private BigDecimal accuracy;
    private BigDecimal speed;
    private BigDecimal heading;
}
```

### 3. Repository: EmployeeLatestLocationRepository

**File:** `coube-backend/src/main/java/kz/coube/backend/driver/repository/EmployeeLatestLocationRepository.java`

Методы:
- `findByEmployeeId(Long employeeId)` — последняя позиция конкретного водителя
- `findAllByEmployee_Organization_Id(Long orgId)` — все водители организации
- Upsert через native query или `save()` (PK = employee_id, JPA сделает merge)

### 4. Изменения в DriverLocationService.save()

**File:** `coube-backend/src/main/java/kz/coube/backend/driver/DriverLocationService.java`

Добавить в начало метода `save()`, **до всех проверок на transportation/transport**:

```java
// ВСЕГДА обновляем последнюю позицию водителя
var employee = employeeService.getEmployeeByPhone(phone);
Point location = geometryFactory.createPoint(
    new Coordinate(request.location().point().lng(), request.location().point().lat()));
employeeLatestLocationService.upsert(employee, location, request.location());
```

Остальная логика (сохранение в `driver_location`, обновление `veh_latest_loc`) — без изменений.

### 5. Service: EmployeeLatestLocationService

**File:** `coube-backend/src/main/java/kz/coube/backend/driver/EmployeeLatestLocationService.java`

```java
@Transactional
public void upsert(Employee employee, Point location, DriverLocationRequest.Location data) {
    var loc = repository.findById(employee.getId())
        .orElseGet(() -> {
            var newLoc = new EmployeeLatestLocation();
            newLoc.setEmployee(employee);
            return newLoc;
        });
    loc.setLocation(location);
    loc.setTimestamp(data.timestamp());
    loc.setAccuracy(data.accuracy());
    loc.setSpeed(data.speed());
    loc.setHeading(data.heading());
    repository.save(loc);
}
```

---

## Mobile изменения

### 1. Два режима трекинга

**File:** `coube-mobile/src/service/geolocation.ts`

| Параметр | С заказом (active) | Без заказа (idle) |
|---|---|---|
| `distanceFilter` | 30м | 500м |
| `locationUpdateInterval` | 30 сек | 30 мин (1800000 мс) |
| `fastestLocationUpdateInterval` | 15 сек | 15 мин |
| `heartbeatInterval` | 60 сек | 30 мин |
| `desiredAccuracy` | MEDIUM | LOW |

### 2. Запуск трекинга при логине

**Файлы:**
- `coube-mobile/src/screens/auth/` — после успешной авторизации вызвать `geolocationService.startTracking()` в idle-режиме
- `coube-mobile/src/screens/order/OrderScreen.tsx` — при ON_THE_WAY переключить на active-режим
- `coube-mobile/src/screens/order/CourierOrderScreen.tsx` — аналогично

### 3. Переключение режимов

```typescript
// При получении заказа (ON_THE_WAY)
geolocationService.switchToActiveMode();

// При завершении заказа (FINISHED)
geolocationService.switchToIdleMode();

// При логауте
geolocationService.stopTracking();
```

---

## API

Существующий endpoint — без изменений:

```http
POST /api/v1/driver/location
Authorization: Bearer {token}

{
  "location": {
    "point": { "lat": 42.5189, "lng": 69.9936 },
    "timestamp": "2026-02-11T14:23:01.757Z",
    "speed": 0,
    "heading": 0,
    "accuracy": 50
  }
}
```

Ответ всегда 200 OK. Разница только в частоте вызовов с мобилки.

---

## Testing Checklist

### Backend
- [ ] Flyway миграция — таблица создается
- [ ] Водитель с заказом — `employee_latest_loc` + `driver_location` + `veh_latest_loc` обновляются
- [ ] Водитель с ТС без заказа — `employee_latest_loc` обновляется, `driver_location` НЕ пишется
- [ ] Курьер без ТС без заказа — `employee_latest_loc` обновляется
- [ ] Повторные вызовы — upsert (не дублируются записи)
- [ ] Курьер с заказом — `employee_latest_loc` + `driver_location` обновляются

### Mobile
- [ ] Трекинг стартует после логина (idle-режим)
- [ ] При ON_THE_WAY — переключается на active-режим (30 сек)
- [ ] При FINISHED — обратно на idle-режим (30 мин)
- [ ] При логауте — трекинг останавливается
- [ ] Background tracking работает в idle-режиме

---

## Что нужно сделать

### Backend (5 изменений)
1. [ ] Flyway миграция `gis.employee_latest_loc`
2. [ ] Entity `EmployeeLatestLocation`
3. [ ] Repository `EmployeeLatestLocationRepository`
4. [ ] Service `EmployeeLatestLocationService`
5. [ ] Изменить `DriverLocationService.save()` — добавить upsert в начало

### Mobile (3 изменения)
6. [ ] Два режима трекинга в `geolocation.ts` (active / idle)
7. [ ] Запуск idle-трекинга при логине
8. [ ] Переключение режимов при смене статуса заказа

### Testing
9. [ ] Unit tests backend
10. [ ] E2E тестирование на устройстве
