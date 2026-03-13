# 05. Назначение курьера БЕЗ транспортного средства

## 🎯 Проблема

В текущей реализации FLT перевозок:
- **Обязательно** нужен `Transport` (связка Vehicle + Driver)
- Водитель назначается **только через** `Transport`
- В `Transportation` есть поля:
  - `transport` → связь с Transport (Vehicle + EmployeeTransport)
  - `executorEmployee` → поле для исполнителя (**НЕ используется для водителя**)

Для курьерской доставки нужно:
- ✅ Назначать курьера **напрямую** (без Transport)
- ✅ Курьер может работать **пешком** или на **своем транспорте**
- ✅ Transport **опционален** (можно назначить, если курьер на машине компании)

---

## 📊 Текущая архитектура

### FLT перевозки (как есть сейчас)

```
Transportation
  ├── transport: Transport (ОБЯЗАТЕЛЬНО!)
  │     ├── vehicle: Vehicle (фура, грузовик)
  │     └── employeeLinks: EmployeeTransport[]
  │           └── employee: Employee (роль DRIVER)
  └── executorEmployee: Employee (НЕ используется!)
```

**Процесс назначения** (FLT):
1. Исполнитель выбирает `Transport` (Vehicle + закрепленный водитель)
2. `ExecutorService.assignDriverToTransportation(transportationId, transportId)`
3. `transportation.setTransport(transport)` ← назначает Transport
4. Из `transport.employeeLinks` находится водитель
5. `transportation.setExecutorEmployee(driver)` ← назначает водителя

**Проблема**: Без `Transport` нельзя назначить водителя!

---

## ✅ Решение для курьерской доставки

### Новая архитектура (для COURIER_DELIVERY)

```
Transportation (тип = COURIER_DELIVERY)
  ├── executorEmployee: Employee (роль DRIVER) ← ИСПОЛЬЗУЕМ ЭТО ПОЛЕ!
  │     └── Курьер назначается НАПРЯМУЮ
  └── transport: Transport (ОПЦИОНАЛЬНО!)
        └── Если курьер на машине компании
```

### Два варианта назначения

#### Вариант 1: Курьер БЕЗ транспорта (пешком, на своем авто)
```java
Transportation courierDelivery = ...;
courierDelivery.setTransportationType(TransportationType.COURIER_DELIVERY);
courierDelivery.setExecutorEmployee(courierEmployee); // ← Назначаем напрямую!
courierDelivery.setTransport(null); // ← Транспорт не нужен
```

#### Вариант 2: Курьер С транспортом компании
```java
Transportation courierDelivery = ...;
courierDelivery.setTransportationType(TransportationType.COURIER_DELIVERY);
courierDelivery.setExecutorEmployee(courierEmployee); // ← Назначаем курьера
courierDelivery.setTransport(companyTransport); // ← Опционально: машина компании
```

---

## 🔧 Изменения в коде

### 1. Обновить `ExecutorService` (добавить новый метод)

**Файл**: `/src/main/java/kz/coube/backend/executor/service/ExecutorService.java`

```java
/**
 * Назначение курьера БЕЗ транспортного средства (для COURIER_DELIVERY)
 */
@Transactional
public void assignCourierToTransportation(Long transportationId, Long courierId) {
    Transportation transportation = transportationService.findById(transportationId);
    
    // Проверка типа перевозки
    if (!TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType())) {
        throw new BusinessException("This method is only for COURIER_DELIVERY type. Use assignDriverToTransportation for FLT.");
    }
    
    // Проверка статуса
    if (!TransportationStatus.SIGNED_CUSTOMER.equals(transportation.getStatus())) {
        throw new BusinessException("Transportation must be in SIGNED_CUSTOMER status");
    }
    
    // Находим курьера
    Employee courier = employeeService.findById(courierId);
    
    // Проверка что это водитель/курьер
    if (!employeeService.hasRole(courier, KeycloakRole.DRIVER)) {
        throw new BusinessException("Employee must have DRIVER role");
    }
    
    // Проверка что курьер из организации исполнителя
    if (!Objects.equals(courier.getOrganizationId(), transportation.getExecutorOrganization().getId())) {
        throw new BusinessException("Courier must be from executor organization");
    }
    
    // Назначаем курьера НАПРЯМУЮ через executorEmployee
    transportation.setExecutorEmployee(courier);
    transportation.setStatus(TransportationStatus.WAITING_DRIVER_CONFIRMATION);
    
    // Transport остается null (курьер без ТС компании)
    transportation.setTransport(null);
    
    transportationService.save(transportation);
    
    // Отправляем уведомление курьеру
    notificationService.notifyCourierAssigned(transportation, courier);
    
    log.info("Assigned courier {} to COURIER_DELIVERY transportation {}", 
             courierId, transportationId);
}

/**
 * Назначение курьера С транспортным средством (опционально для COURIER_DELIVERY)
 */
@Transactional
public void assignCourierWithTransportToTransportation(
        Long transportationId, 
        Long courierId, 
        Long transportId) {
    
    Transportation transportation = transportationService.findById(transportationId);
    
    // Проверка типа
    if (!TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType())) {
        throw new BusinessException("This method is only for COURIER_DELIVERY type");
    }
    
    // Находим курьера и транспорт
    Employee courier = employeeService.findById(courierId);
    Transport transport = transportService.getById(transportId);
    
    // Проверки (роль, организация и т.д.)
    // ...
    
    // Назначаем И курьера И транспорт
    transportation.setExecutorEmployee(courier);
    transportation.setTransport(transport);
    transportation.setStatus(TransportationStatus.WAITING_DRIVER_CONFIRMATION);
    
    transportationService.save(transportation);
    
    log.info("Assigned courier {} with transport {} to COURIER_DELIVERY transportation {}", 
             courierId, transportId, transportationId);
}
```

### 2. Обновить `ExecutorController`

**Файл**: `/src/main/java/kz/coube/backend/executor/api/ExecutorController.java`

```java
/**
 * Назначение курьера БЕЗ транспорта (для COURIER_DELIVERY)
 */
@PostMapping("/{transportationId}/assign-courier")
@Operation(summary = "Назначить курьера на курьерскую доставку (без ТС)")
public ResponseEntity<Void> assignCourier(
    @PathVariable Long transportationId,
    @RequestBody AssignCourierRequest request) {
    
    executorService.assignCourierToTransportation(transportationId, request.courierId());
    return ResponseEntity.ok().build();
}

/**
 * Назначение курьера С транспортом (опционально для COURIER_DELIVERY)
 */
@PostMapping("/{transportationId}/assign-courier-with-transport")
@Operation(summary = "Назначить курьера с транспортным средством")
public ResponseEntity<Void> assignCourierWithTransport(
    @PathVariable Long transportationId,
    @RequestBody AssignCourierWithTransportRequest request) {
    
    executorService.assignCourierWithTransportToTransportation(
        transportationId, 
        request.courierId(), 
        request.transportId()
    );
    return ResponseEntity.ok().build();
}

// DTOs
record AssignCourierRequest(Long courierId) {}
record AssignCourierWithTransportRequest(Long courierId, Long transportId) {}
```

### 3. Обновить валидацию в `DriverService`

**Файл**: `/src/main/java/kz/coube/backend/driver/service/DriverService.java`

```java
public Page<TransportationResponse> getOrders(Pageable pageable) {
    Employee currentEmployee = employeeService.getCurrentEmployee();
    
    // Для COURIER_DELIVERY ищем по executorEmployee
    // Для FLT ищем по transport.employeeLinks
    
    Specification<Transportation> spec = (root, query, cb) -> {
        Predicate courierDeliveryPredicate = cb.and(
            cb.equal(root.get("transportationType"), TransportationType.COURIER_DELIVERY),
            cb.equal(root.get("executorEmployee").get("id"), currentEmployee.getId())
        );
        
        Predicate fltPredicate = cb.and(
            cb.notEqual(root.get("transportationType"), TransportationType.COURIER_DELIVERY),
            // Существующая логика поиска через transport.employeeLinks
            // ...
        );
        
        return cb.or(courierDeliveryPredicate, fltPredicate);
    };
    
    return transportationRepository.findAll(spec, pageable)
        .map(transportationMapper::toResponse);
}
```

### 4. Проверка в validation logic

Добавить проверку что для `COURIER_DELIVERY` поле `executorEmployee` заполнено:

```java
// В TransportationService или валидаторе
public void validateTransportation(Transportation transportation) {
    if (TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType())) {
        // Для курьерской доставки ОБЯЗАТЕЛЬНО назначен executorEmployee
        if (transportation.getExecutorEmployee() == null) {
            throw new ValidationException("Courier must be assigned for COURIER_DELIVERY");
        }
        // Transport опционален - может быть null
    } else {
        // Для FLT ОБЯЗАТЕЛЬНО назначен transport
        if (transportation.getTransport() == null) {
            throw new ValidationException("Transport must be assigned for FLT deliveries");
        }
    }
}
```

---

## 📱 Изменения в UI (Frontend/Mobile)

### Web (для логиста)

**Текущее**: Выбор Transport (Vehicle + Driver)
```jsx
// OLD - для FLT
<TransportSelect 
  onChange={handleTransportSelect} 
  required={true}
/>
```

**Новое**: Для COURIER_DELIVERY отдельный выбор курьера
```jsx
// NEW - для COURIER_DELIVERY
{transportation.transportationType === 'COURIER_DELIVERY' ? (
  <>
    <EmployeeSelect 
      role="DRIVER"
      label="Выбрать курьера"
      onChange={handleCourierSelect}
      required={true}
    />
    
    <TransportSelect 
      label="Транспорт (опционально)"
      onChange={handleTransportSelect}
      required={false}
      helpText="Оставьте пустым если курьер пешком/на своем авто"
    />
  </>
) : (
  <TransportSelect 
    onChange={handleTransportSelect} 
    required={true}
  />
)}
```

### Mobile (для курьера)

**Без изменений!** Курьер видит свои заявки через `DriverController.getOrders()` независимо от того, назначен через `Transport` или напрямую.

---

## 🧪 Тесты

### Unit тесты

```java
@Test
void shouldAssignCourier_withoutTransport_forCourierDelivery() {
    // Given
    Transportation courierDelivery = createCourierDeliveryTransportation();
    Employee courier = createCourierEmployee();
    
    // When
    executorService.assignCourierToTransportation(
        courierDelivery.getId(), 
        courier.getId()
    );
    
    // Then
    Transportation updated = transportationRepository.findById(courierDelivery.getId()).get();
    assertThat(updated.getExecutorEmployee()).isEqualTo(courier);
    assertThat(updated.getTransport()).isNull(); // ← Транспорт не назначен
    assertThat(updated.getStatus()).isEqualTo(TransportationStatus.WAITING_DRIVER_CONFIRMATION);
}

@Test
void shouldThrowException_whenAssignCourierToFLT() {
    // Given
    Transportation flt = createFLTTransportation();
    Employee courier = createCourierEmployee();
    
    // When/Then
    assertThatThrownBy(() -> 
        executorService.assignCourierToTransportation(flt.getId(), courier.getId())
    ).isInstanceOf(BusinessException.class)
     .hasMessageContaining("only for COURIER_DELIVERY type");
}

@Test
void shouldAssignCourier_withTransport_forCourierDelivery() {
    // Given
    Transportation courierDelivery = createCourierDeliveryTransportation();
    Employee courier = createCourierEmployee();
    Transport transport = createTransport();
    
    // When
    executorService.assignCourierWithTransportToTransportation(
        courierDelivery.getId(), 
        courier.getId(),
        transport.getId()
    );
    
    // Then
    Transportation updated = transportationRepository.findById(courierDelivery.getId()).get();
    assertThat(updated.getExecutorEmployee()).isEqualTo(courier);
    assertThat(updated.getTransport()).isEqualTo(transport); // ← Транспорт назначен
}
```

### Integration тесты

```java
@Test
@WithMockUser(roles = "EXECUTOR")
void shouldAllowCourierToSeeAssignedDelivery_withoutTransport() {
    // Given: Курьер назначен БЕЗ транспорта
    Transportation delivery = createAndAssignCourierDelivery(courier, null);
    
    // When: Курьер запрашивает свои заявки
    mockMvc.perform(get("/api/v1/driver/orders")
            .principal(courierPrincipal))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.content[0].id").value(delivery.getId()))
        .andExpect(jsonPath("$.content[0].transportationType").value("COURIER_DELIVERY"));
}
```

---

## 📋 Чеклист реализации

### Backend изменения

- [ ] Добавить метод `assignCourierToTransportation` в `ExecutorService`
- [ ] Добавить метод `assignCourierWithTransportToTransportation` в `ExecutorService`
- [ ] Добавить endpoints в `ExecutorController`:
  - [ ] `POST /{id}/assign-courier`
  - [ ] `POST /{id}/assign-courier-with-transport`
- [ ] Обновить `DriverService.getOrders()` для поиска по `executorEmployee` для COURIER_DELIVERY
- [ ] Добавить валидацию: для COURIER_DELIVERY обязателен `executorEmployee`, но не `transport`
- [ ] Обновить `TransportationMapper` для корректного маппинга курьера
- [ ] Unit тесты (5+ тестов)
- [ ] Integration тесты (3+ теста)

### Frontend изменения

- [ ] Обновить форму назначения исполнителя:
  - [ ] Для COURIER_DELIVERY: выбор курьера + опциональный транспорт
  - [ ] Для FLT: выбор транспорта (как было)
- [ ] API клиент: добавить вызовы новых endpoints
- [ ] Обновить отображение информации о курьере в деталях заявки

### Mobile (без изменений!)

- [x] Курьер видит свои заявки через существующий `GET /driver/orders`
- [x] Все существующие endpoints работают без изменений

---

## 🎯 Итоговая схема

### Для FLT (без изменений)
```
Transportation (FLT)
  └── transport: Transport (ОБЯЗАТЕЛЬНО)
        ├── vehicle: Vehicle
        └── employeeLinks → Employee (DRIVER)
```

**Назначение**: `POST /executor/{id}/assign-driver` с `transportId`

### Для COURIER_DELIVERY (новое)

#### Вариант 1: Без транспорта
```
Transportation (COURIER_DELIVERY)
  ├── executorEmployee: Employee (DRIVER) ← Курьер
  └── transport: null
```

**Назначение**: `POST /executor/{id}/assign-courier` с `courierId`

#### Вариант 2: С транспортом
```
Transportation (COURIER_DELIVERY)
  ├── executorEmployee: Employee (DRIVER) ← Курьер
  └── transport: Transport ← Машина компании (опционально)
```

**Назначение**: `POST /executor/{id}/assign-courier-with-transport` с `courierId` + `transportId`

---

## ✅ Преимущества решения

1. ✅ **Минимальные изменения**: используем существующее поле `executorEmployee`
2. ✅ **Обратная совместимость**: FLT работает как раньше
3. ✅ **Гибкость**: курьер может быть с транспортом или без
4. ✅ **Без миграций БД**: не нужно добавлять новые поля
5. ✅ **Простая логика**: четкое разделение по типу Transportation

---

## 📝 Примечания

### Почему используем `executorEmployee` а не новое поле?

- ✅ Поле уже существует в БД
- ✅ Не нужны миграции
- ✅ Логически правильно: "исполнитель заявки"
- ✅ В FLT это поле заполняется из `transport.employeeLinks`
- ✅ В COURIER_DELIVERY заполняем напрямую

### Можно ли назначить Transport без executorEmployee?

**Нет!** Для COURIER_DELIVERY:
- `executorEmployee` - **ОБЯЗАТЕЛЬНО** (курьер)
- `transport` - **ОПЦИОНАЛЬНО** (машина)

Логика: Курьер всегда назначен, а машина - по необходимости.

---

**Дата создания**: 2025-01-07  
**Версия**: 1.0  
**Оценка времени реализации**: 1-2 дня (backend + frontend)  
**Приоритет**: High (критично для MVP)
