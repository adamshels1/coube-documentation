# API спецификация для редактирования маршрутного листа логистом

> **📌 Примечание**: Основная документация находится в файле **06-logist-edit-flow-analysis.md**
> Этот файл создан как детализация для Jira SCRUM-423

## Endpoint: PUT /api/v1/courier/waybills/{id}

### Описание
Редактирование импортированного маршрутного листа логистом. Позволяет изменять точки маршрута до валидации и назначения курьера.

### Важные ограничения
- ✅ Можно редактировать только маршруты в статусе `FORMING` (импортированный черновик)
- ❌ Нельзя редактировать после валидации (статус `SIGNED_CUSTOMER` и выше)
- ❌ Нельзя редактировать после назначения курьера
- ✅ При редактировании автоматически ставится отметка об изменении из UI (блокирует реимпорт)

### Что может делать логист
1. ✅ Добавлять новые точки доставки
2. ✅ Удалять существующие точки
3. ✅ Изменять адреса точек
4. ✅ Менять последовательность точек (поле `sort`)
5. ✅ Изменять временные окна доставки
6. ✅ Изменять контактную информацию получателей

---

## Request Structure

### URL Parameters
- `{id}` - ID транспортировки (transportationId) в системе Coube

### Headers
```
Authorization: Bearer {keycloak-token}
Content-Type: application/json
```

### Request Body

```json
{
  "deliveries": [
    {
      "id": 5001,  // ID существующей точки (опционально, null для новых)
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
      "orders": []  // Заказы не редактируются, только читаются
    },
    {
      "id": 5002,  // Существующая точка с изменениями
      "sort": 2,
      "isCourierWarehouse": false,
      "loadType": "unloading",
      "address": "Алматы, мкр. Самал-2, дом 58, кв. 12",  // Можно изменить
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
          "trackNumber": "TRACK-123456",  // READ-ONLY
          "externalId": "ORDER-TEEZ-001",  // READ-ONLY
          "orderLoadType": "unload",       // READ-ONLY
          "positions": [...]               // READ-ONLY
        }
      ]
    },
    {
      "id": null,  // Новая точка (без ID)
      "sort": 3,
      "isCourierWarehouse": false,
      "loadType": "unloading",
      "address": "Алматы, ул. Розыбакиева 247",
      "deliveryDesiredDatetime": "2025-01-07T15:00:00Z",
      "isSmsRequired": false,
      "isPhotoRequired": true,
      "receiver": {
        "name": "Новый получатель",
        "phone": "+77012345678"
      },
      "comment": "Новая точка добавлена логистом",
      "orders": []  // Для новых точек можно добавить заказы
    }
    // Точка с id=5003 удалена (не включена в массив)
  ]
}
```

### Важные правила

#### 1. Идентификация точек
- **Существующие точки**: Имеют поле `id` (ID из CargoLoadingHistory)
- **Новые точки**: `id: null` или отсутствует
- **Удаляемые точки**: Не включаются в массив deliveries

#### 2. Неизменяемые поля (READ-ONLY)
Для существующих точек с заказами следующие поля **НЕ могут быть изменены**:
- Все поля в массиве `orders` (trackNumber, externalId, positions и т.д.)
- Сами заказы нельзя удалять или переносить между точками

#### 3. Последняя точка
- Должна быть курьерским складом (`isCourierWarehouse: true`)
- Если это не так, система автоматически добавит возврат на склад

#### 4. Валидация
- Минимум 2 точки (загрузка + минимум одна доставка)
- Первая точка должна быть складом с типом `loading`
- Последняя точка должна быть складом для возврата
- Все адреса должны быть геокодированы (иметь координаты)

---

## Response Examples

### Success Response (200 OK)
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
    "modifiedPoints": 2,
    "totalOrders": 5
  },
  "warnings": [
    "Последняя точка автоматически добавлена как возврат на склад"
  ]
}
```

### Validation Error (400 Bad Request)
```json
{
  "status": "error",
  "error": "VALIDATION_ERROR",
  "message": "Validation failed",
  "errors": [
    {
      "field": "deliveries[1].address",
      "code": "GEOCODING_FAILED",
      "message": "Не удалось определить координаты адреса"
    },
    {
      "field": "deliveries",
      "code": "MISSING_RETURN_POINT",
      "message": "Последняя точка должна быть складом для возврата"
    }
  ]
}
```

### Status Conflict (409 Conflict)
```json
{
  "status": "error",
  "error": "INVALID_STATUS",
  "message": "Waybill cannot be edited in current status",
  "currentStatus": "SIGNED_CUSTOMER",
  "allowedStatuses": ["FORMING"]
}
```

### Not Found (404 Not Found)
```json
{
  "status": "error",
  "error": "NOT_FOUND",
  "message": "Transportation not found",
  "transportationId": 12345
}
```

---

## Пример полного флоу

### 1. Получить текущее состояние маршрута
```bash
GET /api/v1/executor/transportations/{id}
```

### 2. Редактировать маршрут
```bash
PUT /api/v1/courier/waybills/{id}
Content-Type: application/json
Authorization: Bearer {token}

{
  "deliveries": [
    // Измененный список точек
  ]
}
```

### 3. Валидировать и сохранить
```bash
POST /api/v1/executor/transportations/{id}/save
```
После этого шага маршрут переходит в статус `SIGNED_CUSTOMER` и редактирование блокируется.

---

## Backend Implementation Notes

### Сервис: CourierWaybillEditService

```java
@Service
@Transactional
public class CourierWaybillEditService {

  public Transportation editWaybill(Long transportationId, WaybillEditRequest request) {
    // 1. Проверка статуса
    Transportation transportation = transportationRepository.findById(transportationId)
        .orElseThrow(() -> new NotFoundException("Transportation not found"));

    if (!TransportationStatus.FORMING.equals(transportation.getStatus())) {
      throw new InvalidStatusException("Can only edit waybills in FORMING status");
    }

    // 2. Получение текущих точек
    List<CargoLoadingHistory> currentPoints = transportation.getCurrentRouteHistory()
        .getCargoLoadingsHistory();

    // 3. Обработка изменений
    Map<Long, CargoLoadingHistory> existingPointsMap = currentPoints.stream()
        .collect(Collectors.toMap(CargoLoadingHistory::getId, Function.identity()));

    List<CargoLoadingHistory> updatedPoints = new ArrayList<>();

    for (DeliveryPointEditDto pointDto : request.getDeliveries()) {
      if (pointDto.getId() != null) {
        // Существующая точка - обновляем
        CargoLoadingHistory existing = existingPointsMap.get(pointDto.getId());
        if (existing != null) {
          updateExistingPoint(existing, pointDto);
          updatedPoints.add(existing);
        }
      } else {
        // Новая точка - создаем
        CargoLoadingHistory newPoint = createNewPoint(pointDto);
        updatedPoints.add(newPoint);
      }
    }

    // 4. Удаление точек, которых нет в запросе
    Set<Long> requestPointIds = request.getDeliveries().stream()
        .map(DeliveryPointEditDto::getId)
        .filter(Objects::nonNull)
        .collect(Collectors.toSet());

    List<CargoLoadingHistory> pointsToDelete = currentPoints.stream()
        .filter(p -> !requestPointIds.contains(p.getId()))
        .collect(Collectors.toList());

    // 5. Валидация
    validateRoute(updatedPoints);

    // 6. Сохранение
    transportation.getCurrentRouteHistory().setCargoLoadingsHistory(updatedPoints);
    transportation.setLastModifiedBy(getCurrentUser());
    transportation.setLastModifiedAt(Instant.now());

    // 7. Логирование
    logWaybillEdit(transportation, pointsToDelete.size(),
                   updatedPoints.size() - currentPoints.size());

    return transportationRepository.save(transportation);
  }

  private void validateRoute(List<CargoLoadingHistory> points) {
    // - Минимум 2 точки
    // - Первая точка - склад загрузки
    // - Последняя точка - склад возврата
    // - Все адреса геокодированы
  }
}
```

---

## Дополнительные замечания

### Для Jira задачи SCRUM-423

1. **Endpoint path**: Предлагаю использовать `/api/v1/courier/waybills/{id}` вместо общего executor API, чтобы четко разделить курьерскую логику

2. **Права доступа**: Роли `LOGISTICIAN`, `MANAGER` компании-исполнителя

3. **Аудит**: Все изменения должны логироваться с указанием:
   - Кто внес изменения
   - Когда
   - Что именно изменилось (добавлено/удалено/изменено точек)

4. **Блокировка реимпорта**: После любого редактирования через UI, реимпорт из внешней системы должен быть заблокирован

5. **Transactional**: Все операции в одной транзакции - либо все изменения применяются, либо откатываются

---

## Вопросы для уточнения

1. Нужно ли версионирование маршрутов (хранить историю изменений)?
2. Можно ли редактировать заказы внутри точек или они полностью READ-ONLY?
3. Нужна ли возможность массового переноса заказов между точками?
4. Требуется ли уведомление курьера при изменении его маршрута?