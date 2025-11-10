# 13. Блокировка завершения заявки при возврате товаров

**Дата создания**: 2025-11-10
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali (Backend Analysis)

---

## 📋 Проблема

Согласно ТЗ "Проект решения Coube-Teez_v2.md" (24 октября 2024):

> **"Курьер НЕ МОЖЕТ завершить поездку, пока из TEEZ_PVZ не придет по API в COUBE возврат товаров."**
>
> **"Если из TEEZ_PVZ не пришел в COUBE возврат товаров, логист (диспетчер) может завершить поездку принудительно."**

**Текущая реализация:**
```java
// DriverService.java:442-443
if (nextOrderNum == transportation.getCargoLoadings().size()) {
    transportation.setStatus(TransportationStatus.FINISHED); // ❌ Сразу ставит FINISHED
}
```

При завершении последней точки маршрута статус `Transportation` **сразу становится `FINISHED`**, БЕЗ проверки:
- ❌ Есть ли заказы со статусом `RETURNED` или `NOT_DELIVERED`?
- ❌ Должны ли товары быть возвращены на склад?
- ❌ Подтвердил ли логист/TEEZ_PVZ возврат?

**Результат:**
- Заявка завершается автоматически, даже если есть возврат
- Курьер не видит, что нужно вернуть товары на склад
- Логист не может контролировать процесс возврата

---

## ✅ Решение (согласно ТЗ)

### Бизнес-логика

1. **Автоматическая блокировка при возврате:**
   - Если курьер завершил все точки маршрута
   - И есть заказы со статусом `RETURNED`, `NOT_DELIVERED` или `PARTIALLY_RETURNED`
   - → Статус заявки НЕ становится `FINISHED`
   - → Статус заявки становится `AWAITING_RETURN_CONFIRMATION` (новый)

2. **Заявка остается у курьера:**
   - Заявка продолжает отображаться в списке активных заявок курьера
   - Курьер видит сообщение: "Верните товары на склад и дождитесь подтверждения"

3. **Подтверждение возврата логистом:**
   - Логист/диспетчер/админ через веб-интерфейс может:
     - Просмотреть список товаров к возврату
     - Подтвердить возврат товаров
     - Принудительно завершить маршрут
   - После подтверждения → статус меняется на `FINISHED`

4. **Интеграция с TEEZ_PVZ (будущее):**
   - TEEZ_PVZ отправляет API запрос о подтверждении возврата
   - Автоматическое завершение после получения подтверждения от TEEZ_PVZ

---

## 🔍 Анализ текущей реализации

### ✅ Что уже есть:

#### 1. Entity: `CourierRouteOrder`
```java
// File: coube-backend/.../applications/entity/CourierRouteOrder.java
@Entity
@Table(name = "courier_route_order")
public class CourierRouteOrder {
    private CourierOrderStatus status; // ✅ Есть статусы возврата
    private CourierOrderStatusReason statusReason;
    private String courierComment;
    ...
}
```

#### 2. Enum: `CourierOrderStatus`
```java
// File: coube-backend/.../applications/enums/CourierOrderStatus.java
public enum CourierOrderStatus {
    PENDING,
    IN_PROGRESS,
    DELIVERED,
    RETURNED,              // ✅ Возврат
    PARTIALLY_RETURNED,    // ✅ Частичный возврат
    NOT_DELIVERED          // ✅ Недоставка (тоже возврат)
}
```

#### 3. Service: `CourierRouteOrderService`
```java
// File: coube-backend/.../courier/service/CourierRouteOrderService.java
@Service
public class CourierRouteOrderService {
    public List<CourierRouteOrder> getByCargoLoadingHistory(CargoLoadingHistory clh);
    ...
}
```

#### 4. Enum: `TransportationStatus`
```java
// File: coube-backend/.../dictionaries/enumeration/TransportationStatus.java
public enum TransportationStatus {
    FORMING, CREATED, WAITING_CUSTOMER_DECISION, SIGNED_CUSTOMER,
    WAITING_DRIVER_RESPONSE, WAITING_DRIVER_CONFIRMATION,
    DRIVER_ACCEPTED, ON_THE_WAY, SOS, FINISHED, IMPORTED, VALIDATED, CANCELED
}
```

### ❌ Что отсутствует:

1. ❌ Нет статуса `AWAITING_RETURN_CONFIRMATION` в `TransportationStatus`
2. ❌ Нет проверки на возврат в `DriverService.processDeparture()`
3. ❌ Нет метода для подсчета заказов с возвратом
4. ❌ Нет API endpoint для подтверждения возврата логистом
5. ❌ Нет блокировки завершения маршрута при наличии возврата

---

## 🛠️ Изменения

### 1. Добавить новый статус в `TransportationStatus`

**File:** `coube-backend/src/main/java/kz/coube/backend/dictionaries/enumeration/TransportationStatus.java`

```java
public enum TransportationStatus {
  FORMING,
  CREATED,
  WAITING_CUSTOMER_DECISION,
  SIGNED_CUSTOMER,
  WAITING_DRIVER_RESPONSE,
  WAITING_DRIVER_CONFIRMATION,
  DRIVER_ACCEPTED,
  ON_THE_WAY,
  SOS,
  AWAITING_RETURN_CONFIRMATION, // ⭐ NEW: Ожидает подтверждения возврата товаров
  FINISHED,
  IMPORTED,
  VALIDATED,
  CANCELED;

  public static final List<TransportationStatus> EDITABLE_STATUSES = List.of(FORMING);

  public static final List<TransportationStatus> EXECUTOR_NEW_STATUSES =
      List.of(CREATED, WAITING_CUSTOMER_DECISION);

  public static final List<TransportationStatus> EXECUTOR_IDN_FILTER_STATUSES =
      List.of(
          SIGNED_CUSTOMER,
          WAITING_DRIVER_RESPONSE,
          WAITING_DRIVER_CONFIRMATION,
          DRIVER_ACCEPTED,
          ON_THE_WAY,
          SOS,
          AWAITING_RETURN_CONFIRMATION, // ⭐ NEW: Добавить в фильтр "в работе"
          FINISHED);
}
```

---

### 2. Добавить метод проверки возврата в `CourierRouteOrderService`

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/service/CourierRouteOrderService.java`

```java
@Service
@AllArgsConstructor
public class CourierRouteOrderService {
    private final CourierRouteOrderRepository courierRouteOrderRepository;

    // ⭐ NEW: Проверка наличия заказов с возвратом
    public boolean hasReturnedOrders(Transportation transportation) {
        if (transportation.getCargoLoadings() == null || transportation.getCargoLoadings().isEmpty()) {
            return false;
        }

        return transportation.getCargoLoadings().stream()
            .flatMap(cargoLoading ->
                courierRouteOrderRepository.findByCargoLoadingHistory(cargoLoading).stream()
            )
            .anyMatch(order ->
                order.getStatus() == CourierOrderStatus.RETURNED ||
                order.getStatus() == CourierOrderStatus.NOT_DELIVERED ||
                order.getStatus() == CourierOrderStatus.PARTIALLY_RETURNED
            );
    }

    // ⭐ NEW: Получить список заказов с возвратом
    public List<CourierRouteOrder> getReturnedOrders(Transportation transportation) {
        if (transportation.getCargoLoadings() == null || transportation.getCargoLoadings().isEmpty()) {
            return Collections.emptyList();
        }

        return transportation.getCargoLoadings().stream()
            .flatMap(cargoLoading ->
                courierRouteOrderRepository.findByCargoLoadingHistory(cargoLoading).stream()
            )
            .filter(order ->
                order.getStatus() == CourierOrderStatus.RETURNED ||
                order.getStatus() == CourierOrderStatus.NOT_DELIVERED ||
                order.getStatus() == CourierOrderStatus.PARTIALLY_RETURNED
            )
            .collect(Collectors.toList());
    }

    // Existing methods...
    public CourierRouteOrder getCourierRouteOrder(Long id) {
        return courierRouteOrderRepository.findById(id).orElseThrow(ResourceNotFoundException::new);
    }

    public CourierRouteOrder save(CourierRouteOrder courierRouteOrder) {
        return courierRouteOrderRepository.save(courierRouteOrder);
    }

    public List<CourierRouteOrder> getByCargoLoadingHistory(CargoLoadingHistory cargoLoadingHistory) {
        return courierRouteOrderRepository.findByCargoLoadingHistory(cargoLoadingHistory);
    }
}
```

---

### 3. Изменить логику `processDeparture()` в `DriverService`

**File:** `coube-backend/src/main/java/kz/coube/backend/driver/service/DriverService.java`

```java
@Transactional
public TransportationResponse processDeparture(
        final Long transportationId, final CargoLoadingUpdateRequest request) {
    var transportation = getTransportationById(transportationId);
    var cargoLoading =
            cargoLoadingService.findCargoLoadingByTransportationIdAndIsActiveTrue(transportationId);
    TransportationHistoryEventType eventType;

    if (!cargoLoading.getId().equals(request.cargoLoadingId())
            || !cargoLoading.getIsDriverAtLocation()) {
        throw new NoAccessException("error.access.universal");
    }
    cargoLoading.setIsDriverAtLocation(false);
    cargoLoading.setIsActive(false);
    cargoLoadingService.save(cargoLoading);

    var nextOrderNum = cargoLoading.getOrderNum() + 1;

    if (nextOrderNum == transportation.getCargoLoadings().size()) {
        // ⭐ CHANGED: Проверка на наличие возврата товаров
        boolean isCourierDelivery = TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType());
        boolean hasReturnedOrders = isCourierDelivery && courierRouteOrderService.hasReturnedOrders(transportation);

        if (hasReturnedOrders) {
            // Есть возврат товаров - блокируем завершение
            transportation.setStatus(TransportationStatus.AWAITING_RETURN_CONFIRMATION);
            eventType = TransportationHistoryEventType.AWAITING_RETURN_CONFIRMATION; // ⭐ NEW event type

            log.info("Transportation {} has returned orders, status set to AWAITING_RETURN_CONFIRMATION",
                     transportationId);
        } else {
            // Нет возврата - завершаем как обычно
            transportation.setStatus(TransportationStatus.FINISHED);
            eventType = TransportationHistoryEventType.TRIP_FINISHED;
        }

        if (transportation.getTransport() != null) {
            transportation.getTransport().setStatus(TransportStatus.AVAILABLE);
        }
        transportationService.save(transportation);
    } else {
        var nextCargoLoading =
                cargoLoadingService.findByTransportationIdAndOrderNum(
                        transportationId, cargoLoading.getOrderNum() + 1);
        nextCargoLoading.setIsActive(true);
        cargoLoadingService.save(nextCargoLoading);
        eventType = TransportationHistoryEventType.WAYPOINT_LEFT;
    }

    historyService.save(
            HistoryRequestDto.builder()
                    .transportation(transportation)
                    .eventType(eventType)
                    .loading(cargoLoading)
                    .build());

    // ... rest of the method (location update, notifications)

    return toDto(transportation);
}
```

---

### 4. Добавить новый event type в `TransportationHistoryEventType`

**File:** `coube-backend/src/main/java/kz/coube/backend/dictionaries/enumeration/TransportationHistoryEventType.java`

```java
public enum TransportationHistoryEventType {
    // Existing events...
    TRIP_STARTED,
    TRIP_FINISHED,
    WAYPOINT_ARRIVED,
    WAYPOINT_LEFT,

    // ⭐ NEW: Ожидание подтверждения возврата
    AWAITING_RETURN_CONFIRMATION,
    RETURN_CONFIRMED_BY_LOGIST,  // Логист подтвердил возврат
    RETURN_CONFIRMED_BY_API,     // TEEZ_PVZ подтвердил через API

    // ... other events
}
```

---

### 5. Создать DTO для подтверждения возврата

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/ReturnConfirmationRequest.java`

```java
package kz.coube.backend.courier.dto;

import jakarta.validation.constraints.NotNull;
import lombok.Builder;

@Builder
public record ReturnConfirmationRequest(
    @NotNull(message = "Transportation ID is required")
    Long transportationId,

    String comment,  // Комментарий логиста

    Boolean forcedCompletion  // Принудительное завершение без проверок
) {}
```

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/ReturnConfirmationResponse.java`

```java
package kz.coube.backend.courier.dto;

import kz.coube.backend.dictionaries.enumeration.TransportationStatus;
import lombok.Builder;

import java.time.LocalDateTime;
import java.util.List;

@Builder
public record ReturnConfirmationResponse(
    Long transportationId,
    TransportationStatus oldStatus,
    TransportationStatus newStatus,
    LocalDateTime confirmedAt,
    String confirmedBy,  // Email логиста
    List<ReturnedOrderInfo> returnedOrders
) {
    @Builder
    public record ReturnedOrderInfo(
        Long orderId,
        String trackNumber,
        String status,
        String comment
    ) {}
}
```

---

### 6. Создать сервис для подтверждения возврата

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/service/CourierReturnConfirmationService.java`

```java
package kz.coube.backend.courier.service;

import kz.coube.backend.applications.HistoryRequestDto;
import kz.coube.backend.applications.HistoryService;
import kz.coube.backend.applications.TransportationService;
import kz.coube.backend.applications.entity.Transportation;
import kz.coube.backend.auth.currentuser.CurrentUserService;
import kz.coube.backend.common.exception.BadRequestException;
import kz.coube.backend.courier.dto.ReturnConfirmationRequest;
import kz.coube.backend.courier.dto.ReturnConfirmationResponse;
import kz.coube.backend.dictionaries.enumeration.TransportationHistoryEventType;
import kz.coube.backend.dictionaries.enumeration.TransportationStatus;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class CourierReturnConfirmationService {

    private final TransportationService transportationService;
    private final CourierRouteOrderService courierRouteOrderService;
    private final HistoryService historyService;
    private final CurrentUserService currentUserService;

    @Transactional
    public ReturnConfirmationResponse confirmReturn(ReturnConfirmationRequest request) {
        // 1. Найти заявку
        Transportation transportation = transportationService.findById(request.transportationId());

        // 2. Валидация статуса
        if (transportation.getStatus() != TransportationStatus.AWAITING_RETURN_CONFIRMATION) {
            throw new BadRequestException(
                "Transportation is not in AWAITING_RETURN_CONFIRMATION status. Current status: "
                + transportation.getStatus()
            );
        }

        // 3. Проверить наличие возвратов (если не принудительное завершение)
        if (!Boolean.TRUE.equals(request.forcedCompletion())) {
            boolean hasReturns = courierRouteOrderService.hasReturnedOrders(transportation);
            if (!hasReturns) {
                throw new BadRequestException("No returned orders found for this transportation");
            }
        }

        // 4. Получить список возвратов для ответа
        var returnedOrders = courierRouteOrderService.getReturnedOrders(transportation);

        // 5. Обновить статус
        TransportationStatus oldStatus = transportation.getStatus();
        transportation.setStatus(TransportationStatus.FINISHED);
        transportation.setCompletedAt(LocalDateTime.now());
        transportationService.save(transportation);

        // 6. Логирование
        historyService.save(
            HistoryRequestDto.builder()
                .transportation(transportation)
                .eventType(TransportationHistoryEventType.RETURN_CONFIRMED_BY_LOGIST)
                .comment(request.comment())
                .build()
        );

        log.info("Return confirmed for transportation {} by user {}",
                 request.transportationId(),
                 currentUserService.get().getEmail());

        // 7. Формируем ответ
        return ReturnConfirmationResponse.builder()
            .transportationId(transportation.getId())
            .oldStatus(oldStatus)
            .newStatus(TransportationStatus.FINISHED)
            .confirmedAt(LocalDateTime.now())
            .confirmedBy(currentUserService.get().getEmail())
            .returnedOrders(
                returnedOrders.stream()
                    .map(order -> ReturnConfirmationResponse.ReturnedOrderInfo.builder()
                        .orderId(order.getId())
                        .trackNumber(order.getTrackNumber())
                        .status(order.getStatus().name())
                        .comment(order.getCourierComment())
                        .build()
                    )
                    .collect(Collectors.toList())
            )
            .build();
    }
}
```

---

### 7. Создать API endpoint для логиста

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/api/CourierReturnConfirmationController.java`

```java
package kz.coube.backend.courier.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import kz.coube.backend.auth.annotations.AuthorizationRequired;
import kz.coube.backend.auth.roles.KeycloakRole;
import kz.coube.backend.courier.dto.ReturnConfirmationRequest;
import kz.coube.backend.courier.dto.ReturnConfirmationResponse;
import kz.coube.backend.courier.service.CourierReturnConfirmationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/courier")
@RequiredArgsConstructor
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
@Tag(name = "Courier Return Confirmation", description = "API для подтверждения возврата товаров логистом")
public class CourierReturnConfirmationController {

    private final CourierReturnConfirmationService returnConfirmationService;

    @PostMapping("/transportations/{transportationId}/confirm-return")
    @Operation(summary = "Подтвердить возврат товаров на склад")
    public ResponseEntity<ReturnConfirmationResponse> confirmReturn(
        @PathVariable Long transportationId,
        @Valid @RequestBody(required = false) ReturnConfirmationRequest request
    ) {
        // Если request не передан, создаем пустой
        if (request == null) {
            request = ReturnConfirmationRequest.builder()
                .transportationId(transportationId)
                .forcedCompletion(false)
                .build();
        } else {
            // Переопределяем transportationId из path
            request = ReturnConfirmationRequest.builder()
                .transportationId(transportationId)
                .comment(request.comment())
                .forcedCompletion(request.forcedCompletion())
                .build();
        }

        ReturnConfirmationResponse response = returnConfirmationService.confirmReturn(request);
        return ResponseEntity.ok(response);
    }
}
```

---

### 8. Обновить список активных заявок для курьера

**File:** `coube-backend/src/main/java/kz/coube/backend/applications/TransportationService.java`

```java
// Добавить AWAITING_RETURN_CONFIRMATION в список активных статусов для курьера

public Page<Transportation> findAllActiveForDriver(Pageable pageable, Employee employee) {
    List<TransportationStatus> activeStatuses = List.of(
        TransportationStatus.WAITING_DRIVER_CONFIRMATION,
        TransportationStatus.DRIVER_ACCEPTED,
        TransportationStatus.ON_THE_WAY,
        TransportationStatus.AWAITING_RETURN_CONFIRMATION  // ⭐ NEW: Добавить
    );

    // ... existing logic
}
```

---

## 📊 Example Request/Response

### Request: Подтверждение возврата логистом

```http
POST /api/v1/courier/transportations/12345/confirm-return
Authorization: Bearer {logist-token}
Content-Type: application/json

{
  "comment": "Товары возвращены на склад, проверены",
  "forcedCompletion": false
}
```

### Response: Success

```json
{
  "transportationId": 12345,
  "oldStatus": "AWAITING_RETURN_CONFIRMATION",
  "newStatus": "FINISHED",
  "confirmedAt": "2025-11-10T14:30:00Z",
  "confirmedBy": "logist@teez.kz",
  "returnedOrders": [
    {
      "orderId": 7001,
      "trackNumber": "TRACK-123456",
      "status": "RETURNED",
      "comment": "Клиент отказался от заказа"
    },
    {
      "orderId": 7002,
      "trackNumber": "TRACK-123457",
      "status": "NOT_DELIVERED",
      "comment": "Клиент недоступен"
    }
  ]
}
```

---

## 🧪 Testing Checklist

### Unit Tests

- [ ] `CourierRouteOrderService.hasReturnedOrders()` - проверка наличия возвратов
- [ ] `CourierRouteOrderService.getReturnedOrders()` - получение списка возвратов
- [ ] `CourierReturnConfirmationService.confirmReturn()` - подтверждение возврата
- [ ] Валидация статуса при подтверждении возврата
- [ ] Принудительное завершение (forcedCompletion=true)

### Integration Tests

- [ ] `DriverService.processDeparture()` с возвратом → статус `AWAITING_RETURN_CONFIRMATION`
- [ ] `DriverService.processDeparture()` без возврата → статус `FINISHED`
- [ ] API endpoint `/confirm-return` с ролью LOGISTICIAN
- [ ] API endpoint `/confirm-return` с ролью ADMIN
- [ ] API endpoint `/confirm-return` без прав → 403 Forbidden
- [ ] Заявка с `AWAITING_RETURN_CONFIRMATION` отображается у курьера в активных

### E2E Tests

- [ ] Полный flow: курьер завершает точки → есть возврат → статус блокируется
- [ ] Логист подтверждает возврат → статус меняется на FINISHED
- [ ] Принудительное завершение логистом без проверок

---

## 🔗 References

- **ТЗ**: `coube-documentation/business_analysis/converted/Проект решения Coube-Teez_v2.md` (строки 418-584)
- **Entity**: `CourierRouteOrder.java`
- **Current Logic**: `DriverService.java:425-500` (метод `processDeparture`)
- **Related Task**: `10-courier-order-status-update-endpoint.md`

---

## 📝 Notes

1. **MVP версия**: В первой версии подтверждение только через веб-интерфейс логистом
2. **Будущее**: Интеграция с TEEZ_PVZ API для автоматического подтверждения возврата
3. **Уведомления**: При блокировке завершения отправить уведомление курьеру и логисту
4. **Мобильное приложение**: Обновить UI для отображения статуса `AWAITING_RETURN_CONFIRMATION`

---

**Estimated**: 2-3 дня разработки + 1 день тестирования
**Priority**: HIGH - блокирует корректный flow курьерской доставки
