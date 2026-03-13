# Задача 26: Автоматическое назначение курьера при импорте заявки

**Дата создания:** 2025-01-28
**Приоритет:** HIGH
**Статус:** Ready for Development
**Оценка:** 1.5 дня (12 часов)
**Инициатор:** TEEZ

---

## 📋 Описание проблемы

TEEZ хочет отправлять заявку с уже назначенным курьером, чтобы заявка сразу попадала в мобильное приложение курьера без действий логиста.

**Текущая ситуация:**
- TEEZ импортирует маршрутный лист через `POST /api/v1/integration/waybills`
- Заявка создается в статусе `IMPORTED`
- Логист вручную валидирует и назначает курьера через веб-интерфейс
- Только после этого заявка попадает курьеру

**Что хочет TEEZ:**
- Передать телефон курьера при импорте
- Если все данные корректны - заявка автоматически валидируется и назначается курьеру
- Курьер сразу видит заявку в приложении

---

## 🎯 Требования от TEEZ

### 1. Новый метод получения списка курьеров

**GET /api/v1/integration/couriers**

**Описание:** Возвращает список всех активных сотрудников с ролью "Водитель"

**Атрибуты:**
- Имя
- Фамилия
- Номер телефона

**Пример ответа:**
```json
[
  {
    "id": 123,
    "firstName": "Иван",
    "lastName": "Петров",
    "phoneNumber": "+77051234567"
  }
]
```

---

### 2. Доработка метода создания заявки

**POST /api/v1/integration/waybills**

#### Новое поле в `waybill`:
- `courierPhone` (String, опциональное) - номер телефона курьера

#### Поля в `deliveries[]` для автоматического назначения:
- `address` (String) - текстовый адрес
- `latitude` (Double) - широта
- `longitude` (Double) - долгота

---

### 3. Логика автоматического назначения

**Условия для автоматического назначения:**

✅ Передан `courierPhone`
✅ Для всех точек доставки (кроме складов) переданы: `address`, `latitude`, `longitude`
✅ Курьер найден по телефону и активен (`employeeStatus = ACTIVE`)
✅ Курьер не занят другой заявкой
✅ Все склады существуют (проверка `warehouseId` уже работает)

**Если ВСЕ условия выполнены:**
1. Заявка создается
2. Автоматически вызывается валидация (`validateAndApprove`)
3. Курьер назначается (`assignCourier`)
4. Статус заявки: `VALIDATED` → `WAITING_DRIVER_CONFIRMATION`
5. Заявка появляется в приложении курьера

**Если НЕ все условия выполнены:**
1. Заявка создается со статусом `IMPORTED`
2. Логист доработает вручную через веб-интерфейс
3. HTTP 201 с обычным ответом

---

### 4. Обработка ошибок

#### Сценарий 1: Курьер не найден или неактивен
**HTTP 404**
```json
{
  "message": "Курьер с номером телефона +77051234567 не найден или неактивен"
}
```
**Результат:** Заявка НЕ создается

---

#### Сценарий 2: Курьер занят другой заявкой
**HTTP 409**
```json
{
  "message": "Заявка не была создана, т.к. курьер занят другой заявкой. Обратитесь к логисту"
}
```
**Результат:** Заявка НЕ создается, можно повторить запрос с другим курьером

---

#### Сценарий 3: Неполные данные (нет адресов/координат или нет courierPhone)
**HTTP 201**
```json
{
  "status": "imported",
  "transportationId": 12345,
  "externalWaybillId": "TEEZ-123",
  "courierValidationStatus": "IMPORTED",
  "routePointsCount": 5,
  "message": "Заявка создана. Для автоматического назначения курьера требуются: номер телефона курьера и полные данные всех точек доставки (адрес + координаты)"
}
```
**Результат:** Заявка создана в статусе `IMPORTED`, логист назначит курьера вручную

---

#### Сценарий 4: ПВЗ не найден
**HTTP 404**
```json
{
  "message": "Передан неправильный ID ПВЗ: WH-123"
}
```
**Результат:** Заявка НЕ создается (эта проверка уже работает)

---

## 🛠️ Техническая реализация

### Изменения в коде

#### 1. DTO: WaybillHeader.java
```java
public record WaybillHeader(
        String id,
        String deliveryType,
        ResponsibleManagerContactInfo responsibleManagerContactInfo,
        LocalDate targetDeliveryDay,
        String courierPhone  // 👈 NEW - опциональное поле
) {}
```

---

#### 2. DTO: CourierListDto.java (NEW)
```java
package kz.coube.backend.courier.dto;

public record CourierListDto(
        Long id,
        String firstName,
        String lastName,
        String phoneNumber
) {}
```

---

#### 3. Controller: CourierIntegrationController.java

```java
@GetMapping("/couriers")
@Operation(summary = "Получение списка курьеров для TEEZ")
public ResponseEntity<List<CourierListDto>> getCouriers() {
    return ResponseEntity.ok(courierIntegrationService.getActiveCouriers());
}
```

---

#### 4. Service: CourierIntegrationService.java

```java
@Transactional(readOnly = true)
public List<CourierListDto> getActiveCouriers() {
    Long organizationId = RequestContext.getOrganizationId();

    Page<EmployeeDto> drivers = executorService.getDrivers(
        null,  // name filter
        null,  // mapped filter
        Pageable.unpaged()
    );

    return drivers.getContent().stream()
        .filter(d -> d.employeeStatus() == UserStatus.ACTIVE)
        .map(d -> new CourierListDto(
            d.id(),
            d.firstName(),
            d.lastName(),
            d.phoneNumber()
        ))
        .toList();
}

@Transactional
public WaybillImportResponse importWaybill(WaybillImportRequest request) {
    String sourceSystem = String.valueOf(request.sourceSystem());
    String externalWaybillId = request.waybill().id();
    String courierPhone = request.waybill().courierPhone();

    // Проверка существующей заявки
    Optional<Transportation> existingOpt =
        transportationService.findTransportationByExternalWaybillIdAndSourceSystem(
            externalWaybillId, sourceSystem
        );

    try {
        if (existingOpt.isPresent()) {
            // ... существующая логика обновления
        }

        // Проверить курьера ПЕРЕД созданием заявки
        Employee courier = null;
        if (courierPhone != null) {
            courier = validateCourier(courierPhone);  // может бросить 404 или 409
        }

        // Создать заявку (существующая логика)
        Transportation transportation = createTransportation(request);

        // Проверить возможность автоназначения
        boolean canAutoAssign = canAutoAssignCourier(request, courier);

        if (canAutoAssign) {
            // Автоматическая валидация и назначение
            validateAndApprove(transportation.getId());
            assignCourier(transportation.getId(), courier.getId(), null);

            return WaybillImportResponse.builder()
                .status("assigned")
                .transportationId(transportation.getId())
                .externalWaybillId(externalWaybillId)
                .courierValidationStatus("WAITING_DRIVER_CONFIRMATION")
                .courierName(courier.getFullName())
                .routePointsCount(transportation.getCargoLoadings().size())
                .message("Заявка создана и назначена курьеру")
                .build();
        } else {
            // Обычный импорт
            return WaybillImportResponse.builder()
                .status("imported")
                .transportationId(transportation.getId())
                .externalWaybillId(externalWaybillId)
                .courierValidationStatus("IMPORTED")
                .routePointsCount(transportation.getCargoLoadings().size())
                .message("Заявка создана. Для автоматического назначения курьера требуются: " +
                        "номер телефона курьера и полные данные всех точек доставки (адрес + координаты)")
                .build();
        }

    } catch (CourierNotFoundException | CourierInactiveException e) {
        // Заявка НЕ создается
        throw new ResourceNotFoundException(e.getMessage());  // HTTP 404

    } catch (CourierBusyException e) {
        // Заявка НЕ создается
        throw new ValidationException("Courier busy", e.getMessage());  // HTTP 409
    }
}

private Employee validateCourier(String phone) {
    // Найти курьера по телефону
    Employee courier = employeeService.findByPhoneNumber(phone)
        .orElseThrow(() -> new CourierNotFoundException(
            "Курьер с номером телефона " + phone + " не найден или неактивен"
        ));

    // Проверить статус
    if (courier.getEmployeeStatus() != UserStatus.ACTIVE) {
        throw new CourierInactiveException(
            "Курьер с номером телефона " + phone + " не найден или неактивен"
        );
    }

    // Проверить занятость
    boolean isBusy = transportationService.hasActiveCourierTransportation(courier.getId());
    if (isBusy) {
        throw new CourierBusyException(
            "Заявка не была создана, т.к. курьер занят другой заявкой. Обратитесь к логисту"
        );
    }

    return courier;
}

private boolean canAutoAssignCourier(WaybillImportRequest request, Employee courier) {
    if (courier == null) {
        return false;  // нет курьера
    }

    // Проверить что все точки доставки имеют полные данные
    for (DeliveryPoint point : request.deliveries()) {
        if (Boolean.TRUE.equals(point.isCourierWarehouse())) {
            continue;  // склады не проверяем
        }

        // Для точек доставки требуются: адрес + координаты
        if (point.address() == null || point.address().isBlank() ||
            point.latitude() == null || point.longitude() == null) {
            return false;
        }
    }

    return true;
}
```

---

#### 5. Repository/Service: Проверка занятости курьера

```java
// TransportationRepository.java
boolean existsByExecutorEmployeeIdAndStatusIn(
    Long courierId,
    List<TransportationStatus> statuses
);

// TransportationService.java
public boolean hasActiveCourierTransportation(Long courierId) {
    List<TransportationStatus> activeStatuses = List.of(
        TransportationStatus.WAITING_DRIVER_CONFIRMATION,
        TransportationStatus.DRIVER_ACCEPTED,
        TransportationStatus.ON_THE_WAY,
        TransportationStatus.AWAITING_RETURN_CONFIRMATION
    );

    return transportationRepository.existsByExecutorEmployeeIdAndStatusIn(
        courierId,
        activeStatuses
    );
}
```

---

#### 6. EmployeeService: Поиск по телефону

```java
// EmployeeService.java (если еще нет)
public Optional<Employee> findByPhoneNumber(String phone) {
    return employeeRepository.findByPhone(phone);
}
```

---

#### 7. Exception классы (NEW)

```java
package kz.coube.backend.courier.exception;

public class CourierNotFoundException extends RuntimeException {
    public CourierNotFoundException(String message) {
        super(message);
    }
}

public class CourierInactiveException extends RuntimeException {
    public CourierInactiveException(String message) {
        super(message);
    }
}

public class CourierBusyException extends RuntimeException {
    public CourierBusyException(String message) {
        super(message);
    }
}
```

---

#### 8. Response DTO: WaybillImportResponse.java (обновить)

```java
@Builder
public class WaybillImportResponse {
    private String status;  // "imported", "updated", "assigned"
    private Long transportationId;
    private String externalWaybillId;
    private String courierValidationStatus;  // "IMPORTED", "WAITING_DRIVER_CONFIRMATION"
    private Integer routePointsCount;
    private String courierName;  // 👈 NEW - опциональное
    private String message;      // 👈 NEW - опциональное
}
```

---

## 🧪 Тестовые сценарии

### 1. Успешное автоназначение
**Входные данные:**
- `courierPhone`: "+77051234567" (активный, свободный курьер)
- Все точки доставки с адресами и координатами

**Ожидаемый результат:**
- HTTP 201
- Заявка создана
- Статус: `WAITING_DRIVER_CONFIRMATION`
- Курьер назначен
- Заявка видна в мобильном приложении

---

### 2. Импорт без курьера
**Входные данные:**
- `courierPhone`: null

**Ожидаемый результат:**
- HTTP 201
- Заявка создана
- Статус: `IMPORTED`
- Курьер не назначен

---

### 3. Импорт с неполными данными точек
**Входные данные:**
- `courierPhone`: "+77051234567"
- Одна точка без координат

**Ожидаемый результат:**
- HTTP 201
- Заявка создана
- Статус: `IMPORTED`
- Курьер не назначен
- Сообщение о необходимости полных данных

---

### 4. Курьер не найден
**Входные данные:**
- `courierPhone`: "+77059999999" (не существует)

**Ожидаемый результат:**
- HTTP 404
- Заявка НЕ создана
- Сообщение: "Курьер с номером телефона +77059999999 не найден или неактивен"

---

### 5. Курьер неактивен
**Входные данные:**
- `courierPhone`: "+77051111111" (статус BLOCKED)

**Ожидаемый результат:**
- HTTP 404
- Заявка НЕ создана
- Сообщение: "Курьер с номером телефона +77051111111 не найден или неактивен"

---

### 6. Курьер занят
**Входные данные:**
- `courierPhone`: "+77051234567" (уже выполняет другую заявку)

**Ожидаемый результат:**
- HTTP 409
- Заявка НЕ создана
- Сообщение: "Заявка не была создана, т.к. курьер занят другой заявкой. Обратитесь к логисту"

---

## 📝 Чеклист реализации

### Backend (8 часов)

- [ ] **Шаг 1:** Добавить поле `courierPhone` в `WaybillHeader` (15 мин)
- [ ] **Шаг 2:** Создать `CourierListDto` (10 мин)
- [ ] **Шаг 3:** Добавить endpoint `GET /api/v1/integration/couriers` (1 час)
- [ ] **Шаг 4:** Реализовать `getActiveCouriers()` в сервисе (30 мин)
- [ ] **Шаг 5:** Создать exception классы (15 мин)
- [ ] **Шаг 6:** Реализовать `validateCourier()` (1 час)
- [ ] **Шаг 7:** Реализовать `hasActiveCourierTransportation()` (1 час)
- [ ] **Шаг 8:** Реализовать `canAutoAssignCourier()` (30 мин)
- [ ] **Шаг 9:** Модифицировать `importWaybill()` с логикой автоназначения (2 часа)
- [ ] **Шаг 10:** Обновить `WaybillImportResponse` (15 мин)
- [ ] **Шаг 11:** Написать unit-тесты (1.5 часа)

### Тестирование (3 часа)

- [ ] **Тест 1:** Успешное автоназначение курьера
- [ ] **Тест 2:** Импорт без курьера (текущий сценарий)
- [ ] **Тест 3:** Импорт с неполными данными
- [ ] **Тест 4:** Курьер не найден (404)
- [ ] **Тест 5:** Курьер неактивен (404)
- [ ] **Тест 6:** Курьер занят (409)
- [ ] **Тест 7:** ПВЗ не найден (404, существующая логика)
- [ ] **Тест 8:** Проверка появления заявки в мобильном приложении курьера

### Документация (1 час)

- [ ] Обновить API документацию (Swagger)
- [ ] Создать примеры запросов для TEEZ
- [ ] Обновить README.md в папке задачи

---

## ⚡ Оценка времени

| Этап | Время |
|------|-------|
| Backend разработка | 8 часов |
| Тестирование | 3 часа |
| Документация | 1 час |
| **Итого** | **12 часов (1.5 дня)** |

---

## 🔄 Обратная совместимость

✅ **Все изменения полностью обратно совместимы:**

1. Если TEEZ не передает `courierPhone` - работает как раньше (статус `IMPORTED`)
2. Существующие импорты не сломаются
3. Ручное назначение курьера через веб-интерфейс продолжает работать
4. Поля `address`, `latitude`, `longitude` остаются опциональными (обязательны только для автоназначения)

---

## 📌 Зависимости

**Требуется для работы:**
- ✅ Существующий метод `POST /api/v1/integration/waybills`
- ✅ Существующий метод `GET /api/v1/executor/drivers`
- ✅ Существующая логика валидации заявки
- ✅ Существующая логика назначения курьера

**Никаких дополнительных зависимостей не требуется!**

---

## 🎯 Success Criteria

Задача считается выполненной, если:

✅ TEEZ может получить список активных курьеров через `GET /api/v1/integration/couriers`
✅ TEEZ может передать `courierPhone` при импорте заявки
✅ При передаче всех данных заявка автоматически валидируется и назначается курьеру
✅ Курьер сразу видит заявку в мобильном приложении со статусом "Ожидает подтверждения"
✅ При неполных данных заявка создается в статусе `IMPORTED` (как раньше)
✅ Все ошибки возвращаются с корректными HTTP кодами и сообщениями
✅ Существующий процесс ручного назначения не сломан

---

## 📞 Вопросы для уточнения

**Для TEEZ:**
1. ✅ Устраивает ли формат ответа `GET /api/v1/integration/couriers`?
2. ✅ Согласны ли с логикой обработки ошибок?
3. ✅ Готовы ли передавать координаты для всех точек доставки?
4. ⏳ Нужна ли информация о ТС курьера в списке курьеров?
5. ⏳ Нужна ли проверка, что курьер привязан к нужному складу?

---

**Дата последнего обновления:** 2025-01-28
**Версия документа:** 1.0
**Автор:** Ali (based on TEEZ requirements)
