# 16. Добавление курьерских локаций в /customer/locations

## Проблема

Текущий endpoint `/api/v1/customer/locations` возвращает только локации водителей FTL перевозок (через `veh_latest_loc` -> `vehicle` -> `transport` -> `transportation`).

Курьерские перевозки без транспортного средства (`transport = null`) не отображаются, так как у них нет `vehicle`.

## Решение

Добавить в существующий SQL запрос `UNION ALL` для получения локаций курьеров из `gis.driver_location`.

---

## Изменения в коде

### 1. Обновить `DriverLocationRepository`

**Файл**: `/src/main/java/kz/coube/backend/driver/repository/DriverLocationRepository.java`

Обновить метод `findAllLatestLocationsForCustomerOrganizationId`:

```java
@Query(value = """
    -- FTL перевозки (через vehicle)
    SELECT
        vll.vehicle_id,
        v.registration_plate AS vehiclePlate,
        vll.timestamp AS timestamp,
        ST_Y(vll.location::geometry) AS latitude,
        ST_X(vll.location::geometry) AS longitude,
        vll.accuracy,
        vll.status AS status,
        t.id AS transportationId,
        vll.is_sos AS isSos,
        t.status AS transportationStatus,
        e.full_name AS courierName
    FROM gis.veh_latest_loc vll
    JOIN applications.vehicle v ON v.id = vll.vehicle_id
    JOIN applications.transport tr ON tr.vehicle_id = v.id
    JOIN applications.transportation t ON t.transport_id = tr.id
        AND (t.status IN ('ON_THE_WAY', 'DRIVER_ACCEPTED')
             OR (t.status = 'FINISHED' AND t.updated_at >= now() - interval '12 hours'))
    JOIN applications.transportation_cost tc ON t.id = tc.transportation_id AND tc.status = 'ACCEPTED'
    JOIN users.organization o ON o.id = t.organization_id AND o.id = :organizationId
    LEFT JOIN users.employee e ON e.id = t.executor_employee_id

    UNION ALL

    -- Курьерские перевозки БЕЗ vehicle (через driver_location)
    SELECT DISTINCT ON (dl.transportation_id)
        NULL AS vehicle_id,
        NULL AS vehiclePlate,
        dl.timestamp AS timestamp,
        ST_Y(dl.location::geometry) AS latitude,
        ST_X(dl.location::geometry) AS longitude,
        dl.accuracy,
        NULL AS status,
        t.id AS transportationId,
        COALESCE(t.is_sos, false) AS isSos,
        t.status AS transportationStatus,
        e.full_name AS courierName
    FROM gis.driver_location dl
    JOIN applications.transportation t ON dl.transportation_id = t.id
    JOIN users.organization o ON o.id = t.organization_id AND o.id = :organizationId
    LEFT JOIN users.employee e ON e.id = t.executor_employee_id
    WHERE t.transportation_type = 'COURIER_DELIVERY'
        AND t.transport_id IS NULL
        AND (t.status IN ('ON_THE_WAY', 'DRIVER_ACCEPTED')
             OR (t.status = 'FINISHED' AND t.updated_at >= now() - interval '12 hours'))
    ORDER BY dl.transportation_id, dl.timestamp DESC

    ORDER BY timestamp DESC
    """, nativeQuery = true)
List<Map<String, Object>> findAllLatestLocationsForCustomerOrganizationId(@Param("organizationId") Long organizationId);
```

### 2. Обновить маппинг в `DriverLocationService`

**Файл**: `/src/main/java/kz/coube/backend/driver/DriverLocationService.java`

Добавить поддержку `courierName` в `mapToVehicleLatestLocationDto`:

```java
private VehicleLatestLocationDto mapToVehicleLatestLocationDto(Map<String, Object> map) {
    Number transportationIdNum = (Number) map.get("transportationId");
    Number lon = (Number) map.get("longitude");
    Number lat = (Number) map.get("latitude");
    Timestamp timestamp = (Timestamp) map.get("timestamp");
    LocalDateTime updateTimestamp = timestamp != null ? timestamp.toLocalDateTime() : null;
    String statusStr = (String) map.get("status");
    VehicleStatus status = statusStr != null ? VehicleStatus.valueOf(statusStr) : null;
    Boolean isSos = (Boolean) map.get("isSos");

    // Для курьеров без авто используем имя курьера вместо номера
    String vehiclePlate = (String) map.get("vehiclePlate");
    String courierName = (String) map.get("courierName");
    String displayName = vehiclePlate != null ? vehiclePlate : courierName;

    TransportationJournalResponse transportation = null;
    if (transportationIdNum != null) {
        transportation = customerMapper.toTransportationJournal(
            transportationService.findByIdFull(transportationIdNum.longValue())
        );
    }

    return VehicleLatestLocationDto.builder()
        .vehiclePlate(displayName)  // номер авто или имя курьера
        .point(lon != null && lat != null
            ? new GeoPointDto(lon.doubleValue(), lat.doubleValue())
            : null)
        .status(status)
        .isSos(isSos != null && isSos)
        .timestamp(updateTimestamp)
        .transportation(transportation)
        .build();
}
```

---

## Тестирование

### Сценарии для проверки

1. **FTL перевозки** - должны работать как раньше (с vehiclePlate)
2. **Курьерские перевозки с авто** - vehiclePlate от vehicle
3. **Курьерские перевозки БЕЗ авто** - courierName вместо vehiclePlate
4. **Фильтрация по статусу** - работает для обоих типов

### Curl примеры

```bash
# Все локации
curl -X GET "http://localhost:8080/api/v1/customer/locations" \
  -H "Authorization: Bearer {token}"

# С фильтром по статусу
curl -X GET "http://localhost:8080/api/v1/customer/locations?status=ON_THE_WAY" \
  -H "Authorization: Bearer {token}"
```

### Ожидаемый результат

```json
[
  {
    "vehiclePlate": "123ABC",  // FTL - номер авто
    "point": {"lat": 43.238949, "lon": 76.945465},
    "status": "ON_THE_WAY",
    "isSos": false,
    "timestamp": "2025-01-20T10:30:00",
    "transportation": { ... }
  },
  {
    "vehiclePlate": "Иванов Иван",  // Курьер без авто - имя
    "point": {"lat": 43.240000, "lon": 76.950000},
    "status": null,
    "isSos": false,
    "timestamp": "2025-01-20T10:35:00",
    "transportation": { ... }
  }
]
```

---

## Чеклист реализации

- [ ] Обновить SQL запрос в `DriverLocationRepository.findAllLatestLocationsForCustomerOrganizationId()`
- [ ] Добавить `courierName` в маппинг `DriverLocationService.mapToVehicleLatestLocationDto()`
- [ ] Протестировать с FTL перевозками (не сломать!)
- [ ] Протестировать с курьерскими перевозками без авто
- [ ] Протестировать фильтрацию по статусу

---

## Примечания

### Почему UNION ALL а не отдельный endpoint?

- Заказчик видит все свои перевозки в одном месте
- Не нужно менять фронтенд
- Один запрос к БД вместо двух

### Почему `courierName` а не пустой `vehiclePlate`?

- Заказчику важно видеть кто везёт груз
- Для курьера это имя, для FTL - номер авто
- Фронтенд может отображать это по-разному

---

**Дата создания**: 2025-11-21
**Версия**: 1.0
**Оценка времени реализации**: 2-3 часа
**Приоритет**: Medium
