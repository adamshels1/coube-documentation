# 10. Endpoint обновления статуса заказа курьера

**Дата создания**: 2025-10-29
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali (Mobile Dev)

---

## Проблема

Сейчас курьер может:
- ✅ Прибыть на точку (`PUT /driver/orders/{id}/arrival`)
- ✅ Отбыть с точки (`PUT /driver/orders/{id}/departure`)
- ✅ Загрузить фото (`POST /driver/upload-photo`)

НО не может:
- ❌ Обновить статус заказа (доставлено/не доставлено/возврат)
- ❌ Сохранить SMS код подтверждения
- ❌ Указать причину недоставки

**Текущая проблема**: После departure все заказы остаются в статусе `PENDING`, хотя курьер уже их доставил или не смог доставить.

---

## Решение

Добавить endpoint для обновления статуса заказа курьера с поддержкой:
- SMS подтверждения доставки
- Привязки фото к заказу
- Частичного возврата товаров
- Причин недоставки

---

## API Specification

### Endpoint
```
PUT /api/v1/driver/orders/{transportationId}/courier-orders/{orderId}/status
```

**Аутентификация**: Bearer token (роль DRIVER)

### Path Parameters
| Parameter | Type | Description |
|-----------|------|-------------|
| `transportationId` | Long | ID маршрута (Transportation) |
| `orderId` | Long | ID заказа курьера (CourierRouteOrder) |

---

## Request DTOs

### CourierOrderStatusUpdateRequest
```java
package kz.coube.backend.driver.dto;

import jakarta.validation.constraints.NotNull;
import kz.coube.backend.applications.enums.CourierOrderStatus;
import kz.coube.backend.applications.enums.CourierOrderStatusReason;
import java.util.List;
import java.util.UUID;

public record CourierOrderStatusUpdateRequest(
    @NotNull(message = "Status is required")
    CourierOrderStatus status,

    String smsCode,  // Обязательно если isSmsRequired=true

    UUID photoId,    // Опционально, фото можно загрузить отдельно

    CourierOrderStatusReason statusReason,  // Обязательно для NOT_DELIVERED

    String comment,  // Опциональный комментарий курьера

    List<ReturnedPosition> returnedPositions  // Обязательно для PARTIALLY_RETURNED
) {
    public record ReturnedPosition(
        String positionCode,
        Integer returnedQty
    ) {}
}
```

### CourierOrderStatusResponse
```java
package kz.coube.backend.driver.dto;

import kz.coube.backend.applications.enums.CourierOrderStatus;
import java.time.LocalDateTime;

public record CourierOrderStatusResponse(
    Long orderId,
    String trackNumber,
    CourierOrderStatus status,
    LocalDateTime statusDatetime,
    String photoUrl  // Может быть null
) {}
```

---

## Request Examples

### 1. Доставлено (с SMS и фото)
```json
POST /api/v1/driver/orders/12345/courier-orders/7001/status
Content-Type: application/json
Authorization: Bearer {driver-token}

{
  "status": "DELIVERED",
  "sms_code": "1234",
  "photo_id": "550e8400-e29b-41d4-a716-446655440000",
  "comment": "Получатель подписал накладную"
}
```

**Response 200 OK**:
```json
{
  "order_id": 7001,
  "track_number": "TRACK-123456",
  "status": "DELIVERED",
  "status_datetime": "2025-10-29T10:15:00Z",
  "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg"
}
```

---

### 2. Не доставлено (клиент недоступен)
```json
{
  "status": "NOT_DELIVERED",
  "status_reason": "CUSTOMER_NOT_AVAILABLE",
  "comment": "Клиент не отвечает на звонки, попробуем завтра"
}
```

**Response 200 OK**:
```json
{
  "order_id": 7001,
  "track_number": "TRACK-123456",
  "status": "NOT_DELIVERED",
  "status_datetime": "2025-10-29T10:30:00Z",
  "photo_url": null
}
```

---

### 3. Частичный возврат
```json
{
  "status": "PARTIALLY_RETURNED",
  "comment": "Клиент принял только 1 товар из 2",
  "photo_id": "550e8400-e29b-41d4-a716-446655440001",
  "returned_positions": [
    {
      "position_code": "POS-002",
      "returned_qty": 1
    }
  ]
}
```

**Response 200 OK**:
```json
{
  "order_id": 7001,
  "track_number": "TRACK-123456",
  "status": "PARTIALLY_RETURNED",
  "status_datetime": "2025-10-29T10:45:00Z",
  "photo_url": "https://s3.coube.kz/courier/photos/123457.jpg"
}
```

---

### 4. Полный возврат
```json
{
  "status": "RETURNED",
  "status_reason": "CUSTOMER_REFUSED",
  "comment": "Клиент отказался от заказа полностью"
}
```

---

## Бизнес-логика

### 1. Валидация запроса

```java
@Service
public class CourierOrderStatusValidator {

    public void validate(
        CourierRouteOrder order,
        CargoLoadingHistory point,
        CourierOrderStatusUpdateRequest request
    ) {
        // 1. Проверка SMS кода
        if (point.getIsSmsRequired() &&
            request.status() == CourierOrderStatus.DELIVERED &&
            StringUtils.isBlank(request.smsCode())) {
            throw new ValidationException("SMS code is required for this delivery point");
        }

        // 2. Проверка причины для NOT_DELIVERED
        if (request.status() == CourierOrderStatus.NOT_DELIVERED &&
            request.statusReason() == null) {
            throw new ValidationException("Status reason is required for NOT_DELIVERED status");
        }

        // 3. Проверка returnedPositions для PARTIALLY_RETURNED
        if (request.status() == CourierOrderStatus.PARTIALLY_RETURNED) {
            if (CollectionUtils.isEmpty(request.returnedPositions())) {
                throw new ValidationException("Returned positions are required for PARTIALLY_RETURNED status");
            }

            // Проверить что position_code существует в заказе
            validateReturnedPositions(order, request.returnedPositions());
        }

        // 4. Проверка photo_id если передан
        if (request.photoId() != null) {
            fileMetaInfoRepository.findById(request.photoId())
                .orElseThrow(() -> new NotFoundException("Photo not found"));
        }
    }

    private void validateReturnedPositions(
        CourierRouteOrder order,
        List<ReturnedPosition> returnedPositions
    ) {
        // Парсим JSONB positions из CourierRouteOrder
        List<String> validPositionCodes = parsePositionCodes(order.getPositions());

        for (ReturnedPosition returned : returnedPositions) {
            if (!validPositionCodes.contains(returned.positionCode())) {
                throw new ValidationException(
                    "Position code not found in order: " + returned.positionCode()
                );
            }

            if (returned.returnedQty() <= 0) {
                throw new ValidationException(
                    "Returned quantity must be greater than 0"
                );
            }
        }
    }
}
```

### 2. Обновление заказа

```java
@Service
@RequiredArgsConstructor
public class CourierOrderStatusService {

    private final CourierRouteOrderRepository courierRouteOrderRepository;
    private final FileMetaInfoRepository fileMetaInfoRepository;
    private final TransportationRepository transportationRepository;
    private final CargoLoadingHistoryRepository cargoLoadingHistoryRepository;
    private final CourierOrderStatusValidator validator;

    @Transactional
    public CourierOrderStatusResponse updateStatus(
        Long transportationId,
        Long orderId,
        CourierOrderStatusUpdateRequest request,
        String driverEmail  // Из Security Context
    ) {
        // 1. Найти и проверить заказ
        CourierRouteOrder order = courierRouteOrderRepository.findById(orderId)
            .orElseThrow(() -> new NotFoundException("Courier order not found"));

        // 2. Проверить что заказ принадлежит маршруту
        CargoLoadingHistory point = order.getCargoLoadingHistory();
        if (!point.getTransportationId().equals(transportationId)) {
            throw new ValidationException("Order does not belong to this transportation");
        }

        // 3. Проверить что водитель назначен на маршрут
        Transportation transportation = transportationRepository.findById(transportationId)
            .orElseThrow(() -> new NotFoundException("Transportation not found"));

        if (!transportation.getDriver().getUser().getEmail().equals(driverEmail)) {
            throw new ForbiddenException("Driver not assigned to this route");
        }

        // 4. Валидация запроса
        validator.validate(order, point, request);

        // 5. Обновить заказ
        order.setStatus(request.status());
        order.setStatusDatetime(LocalDateTime.now());

        if (request.smsCode() != null) {
            order.setSmsCodeUsed(request.smsCode());
        }

        if (request.statusReason() != null) {
            order.setStatusReason(request.statusReason());
        }

        if (request.comment() != null) {
            order.setCourierComment(request.comment());
        }

        // 6. Привязать фото если передан photo_id
        if (request.photoId() != null) {
            FileMetaInfo photo = fileMetaInfoRepository.findById(request.photoId()).get();
            order.setPhoto(photo);
        }

        // 7. Обновить JSONB positions для частичного возврата
        if (request.status() == CourierOrderStatus.PARTIALLY_RETURNED) {
            updateReturnedQuantities(order, request.returnedPositions());
        }

        courierRouteOrderRepository.save(order);

        // 8. Вернуть response
        return new CourierOrderStatusResponse(
            order.getId(),
            order.getTrackNumber(),
            order.getStatus(),
            order.getStatusDatetime(),
            order.getPhoto() != null ? order.getPhoto().getMinioFilePath() : null
        );
    }

    private void updateReturnedQuantities(
        CourierRouteOrder order,
        List<ReturnedPosition> returnedPositions
    ) {
        // Парсим JSONB, обновляем returned_qty, сохраняем обратно
        ObjectMapper mapper = new ObjectMapper();
        try {
            JsonNode positions = mapper.readTree(order.getPositions());

            // Обновляем returned_qty для каждой позиции
            for (ReturnedPosition returned : returnedPositions) {
                for (JsonNode position : positions) {
                    if (position.get("positionCode").asText().equals(returned.positionCode())) {
                        ((ObjectNode) position).put("returned_qty", returned.returnedQty());
                    }
                }
            }

            order.setPositions(mapper.writeValueAsString(positions));
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Failed to update returned quantities", e);
        }
    }
}
```

### 3. Controller

```java
@RestController
@RequestMapping("/api/v1/driver")
@RequiredArgsConstructor
@AuthorizationRequired(roles = {KeycloakRole.DRIVER})
public class DriverController {

    private final CourierOrderStatusService courierOrderStatusService;

    @PutMapping("/orders/{transportationId}/courier-orders/{orderId}/status")
    @Operation(summary = "Обновить статус заказа курьера")
    public ResponseEntity<CourierOrderStatusResponse> updateCourierOrderStatus(
        @PathVariable Long transportationId,
        @PathVariable Long orderId,
        @Valid @RequestBody CourierOrderStatusUpdateRequest request,
        @AuthenticationPrincipal Jwt jwt
    ) {
        String driverEmail = jwt.getClaimAsString("email");

        CourierOrderStatusResponse response = courierOrderStatusService.updateStatus(
            transportationId,
            orderId,
            request,
            driverEmail
        );

        return ResponseEntity.ok(response);
    }
}
```

---

## Дополнительные изменения

### 1. Добавить в enum CourierOrderStatusReason

Файл: `kz/coube/backend/applications/enums/CourierOrderStatusReason.java`

```java
@Getter
public enum CourierOrderStatusReason {
    CUSTOMER_NOT_AVAILABLE("Клиент недоступен (не отвечает, не открывает)"),
    CUSTOMER_POSTPONED("Клиент попросил перенести доставку"),
    CUSTOMER_REFUSED("Клиент отказался от заказа"),  // ⭐ NEW
    ADDRESS_NOT_FOUND("Адрес не найден"),              // ⭐ NEW
    FORCE_MAJEURE("Форс мажор");

    private final String description;

    CourierOrderStatusReason(String description) {
        this.description = description;
    }
}
```

---

## Error Responses

### 400 Bad Request - Validation Error
```json
{
  "error": "VALIDATION_ERROR",
  "message": "SMS code is required for this delivery point",
  "field": "sms_code"
}
```

### 403 Forbidden - Wrong Driver
```json
{
  "error": "FORBIDDEN",
  "message": "Driver not assigned to this route"
}
```

### 404 Not Found - Order Not Found
```json
{
  "error": "NOT_FOUND",
  "message": "Courier order not found",
  "order_id": 7001
}
```

### 404 Not Found - Photo Not Found
```json
{
  "error": "NOT_FOUND",
  "message": "Photo not found",
  "photo_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

## Что уже готово

✅ **База данных**:
- Таблица `courier_route_order` с нужными полями
- Migration: `V20251022133610__create_courier_route_order.sql`

✅ **Entity**:
- `CourierRouteOrder.java` с полями `status`, `smsCodeUsed`, `photo`, `statusReason`, `courierComment`, `positions`

✅ **Enums**:
- `CourierOrderStatus`: PENDING, DELIVERED, NOT_DELIVERED, RETURNED, PARTIALLY_RETURNED
- `CourierOrderStatusReason`: CUSTOMER_NOT_AVAILABLE, CUSTOMER_POSTPONED, FORCE_MAJEURE

✅ **Загрузка фото**:
- `POST /api/v1/driver/upload-photo` уже работает

---

## Что нужно сделать

### Backend (Java)
1. ❌ Добавить 2 новых значения в `CourierOrderStatusReason` enum
2. ❌ Создать DTO: `CourierOrderStatusUpdateRequest`, `CourierOrderStatusResponse`
3. ❌ Создать `CourierOrderStatusValidator` для валидации
4. ❌ Создать `CourierOrderStatusService` с методом `updateStatus()`
5. ❌ Добавить endpoint в `DriverController`
6. ❌ Написать тесты

### Mobile (React Native)
1. ❌ Добавить API метод в `src/api/driver.ts`
2. ❌ Обновить UI `CourierOrderScreen` для вызова нового endpoint
3. ❌ Обновить flow: arrival → upload photo → **update status** → departure

---

## Testing Checklist

### Happy Path
- [ ] Доставлено с SMS кодом и фото
- [ ] Доставлено без SMS (когда не требуется)
- [ ] Не доставлено с причиной
- [ ] Частичный возврат с 1 позицией
- [ ] Частичный возврат с несколькими позициями
- [ ] Полный возврат

### Validation
- [ ] SMS код обязателен когда `isSmsRequired=true`
- [ ] `statusReason` обязателен для `NOT_DELIVERED`
- [ ] `returnedPositions` обязателен для `PARTIALLY_RETURNED`
- [ ] `position_code` существует в заказе
- [ ] `photo_id` существует в базе

### Security
- [ ] Водитель не может обновить чужой маршрут
- [ ] Заказ принадлежит указанному маршруту
- [ ] Только роль DRIVER может вызвать endpoint

### Edge Cases
- [ ] Дублирование обновления статуса (идемпотентность)
- [ ] Фото уже привязано через `POST /driver/upload-photo`
- [ ] Частичный возврат всех позиций (должен быть RETURNED?)

---

## References

- API Examples: `03-api-examples.md` раздел 7
- Entity: `CourierRouteOrder.java`
- Migration: `V20251022133610__create_courier_route_order.sql`
- Upload Photo: `DriverService.java:215-226`

---

## Notes

1. **Идемпотентность**: Если статус уже установлен, просто возвращаем текущий статус (не ошибку)
2. **Photo upload flow**: Фото можно загрузить ДО обновления статуса через `POST /driver/upload-photo`, тогда `photo_id` не нужен в request
3. **JSONB positions**: При частичном возврате обновляем поле `returned_qty` в JSONB
4. **Integration**: TEEZ получит обновленные статусы через `GET /api/v1/integration/courier/orders/status`

---

**Приоритет**: HIGH - блокирует мобильное приложение
**Estimated**: 2-3 дня разработки + тестирование
