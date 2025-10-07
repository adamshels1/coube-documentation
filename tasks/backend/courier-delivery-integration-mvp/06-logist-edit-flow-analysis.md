# 06. Анализ флоу: Редактирование маршрутных листов логистом

## 🎯 Флоу из ТЗ

Согласно ТЗ "Проект решения Coube-Teez.md":

### Шаг 1: TEEZ загружает маршрутный лист через API
```
TEEZ_PVZ → POST /api/v1/integration/waybills
Статус: "Импортированный непровалидированный черновик"
```

### Шаг 2: Логист компании Teez редактирует в COUBE
**ТЗ цитата**:
> "Маршрутный лист (МЛ) могут редактировать все логисты компании (Teez). 
> Логист должен визуально проверить и дозаполнить маршрутный лист через интерфейс платформы COUBE."

**Логист может**:
- ✅ Добавлять точки
- ✅ Удалять точки
- ✅ Редактировать данные точек
- ✅ Синхронизировать адреса с картой
- ✅ После валидации: перевести в статус "Сохранено" (провалидированный черновик)

### Шаг 3: Логист назначает курьера
**ТЗ цитата**:
> "Логист назначает курьера на маршрутный лист"

### Шаг 4: Курьер выполняет доставку
(в мобильном приложении)

### Шаг 5: Логист закрывает поездку
**ТЗ цитата**:
> "Логист закрывает поездку в COUBE"

---

## ❌ Проблема: В MVP документации это НЕ учтено!

### Что пропущено в текущей MVP документации:

1. ❌ **API для логиста** - редактирование маршрутного листа через веб-интерфейс
2. ❌ **Статус "провалидированный черновик"** - после проверки логистом
3. ❌ **Блокировка обновления** - если маршрут уже провалидирован
4. ❌ **Роль логиста** - кто именно может редактировать (LOGISTICIAN)
5. ❌ **Веб UI endpoints** - для работы логиста с маршрутом

### Что есть в текущей MVP документации:

✅ Импорт маршрутного листа от TEEZ (API)  
✅ Назначение курьера (но не описано КТО назначает)  
✅ Мобильное API для курьера  
✅ Отправка результатов обратно в TEEZ  
✅ Закрытие маршрута  

---

## ✅ Решение: Дополнить MVP функционалом логиста

### 1. Статусы маршрутного листа (расширить)

Из ТЗ:
```
imported_draft       → Импортированный непровалидированный черновик
validated            → Сохранено (провалидированный черновик)
assigned             → Назначен курьер
in_route             → Курьер в пути
completed            → Маршрут выполнен
closed               → Закрыт логистом
```

**Реализация**: Уже есть в `CourierValidationStatus` enum!

### 2. API для логиста (ДОБАВИТЬ в MVP!)

#### GET /api/v1/courier/waybills (список маршрутных листов)

**Роль**: `LOGISTICIAN` (логист компании Teez)

```java
@GetMapping("/waybills")
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
public ResponseEntity<Page<CourierWaybillListResponse>> getWaybills(
    @RequestParam(required = false) String status,
    @RequestParam(required = false) String search,
    Pageable pageable) {
    
    // Фильтрация по:
    // - status (imported_draft, validated, assigned, etc.)
    // - search (по внешнему ID, номеру)
    // - организация логиста (автоматически из RequestContext)
    
    return ResponseEntity.ok(courierWaybillService.getWaybills(status, search, pageable));
}
```

#### GET /api/v1/courier/waybills/{id} (детали маршрутного листа)

```java
@GetMapping("/waybills/{id}")
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
public ResponseEntity<CourierWaybillDetailResponse> getWaybillDetails(
    @PathVariable Long id) {
    
    Transportation waybill = courierWaybillService.getWaybillById(id);
    
    // Проверка доступа: логист должен быть из организации-исполнителя
    if (!waybill.getExecutorOrganization().getId().equals(RequestContext.getOrganizationId())) {
        throw new AccessDeniedException("You don't have access to this waybill");
    }
    
    return ResponseEntity.ok(courierWaybillMapper.toDetailResponse(waybill));
}
```

#### PUT /api/v1/courier/waybills/{id} (редактирование маршрута)

**Важно**: Можно редактировать только в статусе `imported_draft`!

```java
@PutMapping("/waybills/{id}")
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
public ResponseEntity<CourierWaybillDetailResponse> updateWaybill(
    @PathVariable Long id,
    @Valid @RequestBody UpdateWaybillRequest request) {
    
    Transportation waybill = courierWaybillService.getWaybillById(id);
    
    // Проверка статуса - можно редактировать только черновик
    if (!CourierValidationStatus.IMPORTED.equals(waybill.getCourierValidationStatus())) {
        throw new BusinessException("Can only edit waybills in IMPORTED status");
    }
    
    // Обновление точек маршрута
    courierWaybillService.updateWaybillPoints(id, request.getDeliveryPoints());
    
    return ResponseEntity.ok(courierWaybillMapper.toDetailResponse(waybill));
}
```

#### POST /api/v1/courier/waybills/{id}/validate (валидация маршрута)

**Действие**: Перевод из `imported_draft` → `validated`

```java
@PostMapping("/waybills/{id}/validate")
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
public ResponseEntity<Void> validateWaybill(@PathVariable Long id) {
    
    Transportation waybill = courierWaybillService.getWaybillById(id);
    
    // Проверка что все адреса геокодированы
    // Проверка что последняя точка - склад
    // Проверка уникальности sort_order
    courierWaybillService.validateAndApprove(id);
    
    // Меняем статус
    waybill.setCourierValidationStatus(CourierValidationStatus.VALIDATED);
    
    return ResponseEntity.ok().build();
}
```

#### POST /api/v1/courier/waybills/{id}/assign (назначение курьера)

**Действие**: Назначает курьера и переводит в статус `assigned`

```java
@PostMapping("/waybills/{id}/assign")
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
public ResponseEntity<Void> assignCourier(
    @PathVariable Long id,
    @RequestBody AssignCourierRequest request) {
    
    Transportation waybill = courierWaybillService.getWaybillById(id);
    
    // Проверка что маршрут провалидирован
    if (!CourierValidationStatus.VALIDATED.equals(waybill.getCourierValidationStatus())) {
        throw new BusinessException("Waybill must be validated before assigning courier");
    }
    
    // Назначение курьера (используем новый метод из 05-courier-without-transport.md)
    executorService.assignCourierToTransportation(id, request.getCourierId());
    
    // Меняем статус
    waybill.setCourierValidationStatus(CourierValidationStatus.ASSIGNED);
    waybill.setStatus(TransportationStatus.WAITING_DRIVER_CONFIRMATION);
    
    return ResponseEntity.ok().build();
}
```

#### POST /api/v1/courier/waybills/{id}/close (закрытие маршрута)

**Действие**: Логист закрывает маршрут после выполнения

```java
@PostMapping("/waybills/{id}/close")
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
public ResponseEntity<Void> closeWaybill(@PathVariable Long id) {
    
    Transportation waybill = courierWaybillService.getWaybillById(id);
    
    // Проверка что маршрут выполнен
    if (!TransportationStatus.FINISHED.equals(waybill.getStatus())) {
        throw new BusinessException("Can only close finished waybills");
    }
    
    // Закрытие маршрута
    waybill.setCourierValidationStatus(CourierValidationStatus.CLOSED);
    
    // Отправка результатов в TEEZ (если еще не отправлены)
    courierResultsService.sendResultsSync(id);
    
    return ResponseEntity.ok().build();
}
```

### 3. DTO для логиста

```java
// Response для списка
@Data @Builder
public class CourierWaybillListResponse {
    private Long id;
    private String externalWaybillId;
    private String sourceSystem;
    private CourierValidationStatus validationStatus;
    private TransportationStatus status;
    private Integer pointsCount;
    private Integer ordersCount;
    private String courierName; // если назначен
    private LocalDate targetDeliveryDay;
    private Instant createdAt;
}

// Response для деталей
@Data @Builder
public class CourierWaybillDetailResponse {
    private Long id;
    private String externalWaybillId;
    private String sourceSystem;
    private CourierValidationStatus validationStatus;
    private TransportationStatus status;
    
    private CourierInfo courier; // если назначен
    private List<RoutePointInfo> routePoints;
    
    // Статистика
    private Integer totalPoints;
    private Integer totalOrders;
    private Integer deliveredOrders;
    private Integer returnedOrders;
    
    private Instant createdAt;
    private Instant updatedAt;
}

// Request для обновления
@Data
public class UpdateWaybillRequest {
    private List<DeliveryPointUpdateDto> deliveryPoints;
}

// Request для назначения курьера
@Data
public class AssignCourierRequest {
    private Long courierId;
}
```

### 4. CourierWaybillService (новый сервис)

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CourierWaybillService {
    
    private final TransportationRepository transportationRepo;
    private final EmployeeService employeeService;
    private final TransportationRouteService routeService;
    
    /**
     * Получение списка маршрутных листов для логиста
     */
    @Transactional(readOnly = true)
    public Page<CourierWaybillListResponse> getWaybills(
            String status, 
            String search, 
            Pageable pageable) {
        
        Long organizationId = RequestContext.getOrganizationId();
        
        // Specification для фильтрации
        Specification<Transportation> spec = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();
            
            // Только COURIER_DELIVERY
            predicates.add(cb.equal(root.get("transportationType"), 
                                   TransportationType.COURIER_DELIVERY));
            
            // Только для организации логиста
            predicates.add(cb.equal(root.get("executorOrganization").get("id"), 
                                   organizationId));
            
            // Фильтр по статусу
            if (status != null) {
                predicates.add(cb.equal(root.get("courierValidationStatus"), 
                                       CourierValidationStatus.valueOf(status)));
            }
            
            // Поиск
            if (search != null && !search.isBlank()) {
                predicates.add(cb.or(
                    cb.like(root.get("externalWaybillId"), "%" + search + "%"),
                    cb.like(root.get("id").as(String.class), "%" + search + "%")
                ));
            }
            
            return cb.and(predicates.toArray(new Predicate[0]));
        };
        
        return transportationRepo.findAll(spec, pageable)
            .map(this::toListResponse);
    }
    
    /**
     * Валидация и перевод в статус VALIDATED
     */
    @Transactional
    public void validateAndApprove(Long waybillId) {
        Transportation waybill = transportationRepo.findById(waybillId)
            .orElseThrow(() -> new NotFoundException("Waybill not found"));
        
        // Проверка статуса
        if (!CourierValidationStatus.IMPORTED.equals(waybill.getCourierValidationStatus())) {
            throw new BusinessException("Can only validate waybills in IMPORTED status");
        }
        
        // Валидации
        List<CargoLoadingHistory> points = waybill.getCargoLoadings();
        
        // 1. Проверка уникальности sort_order
        Set<Integer> sortOrders = points.stream()
            .map(CargoLoadingHistory::getOrderNum)
            .collect(Collectors.toSet());
        if (sortOrders.size() != points.size()) {
            throw new ValidationException("Duplicate sort orders found");
        }
        
        // 2. Проверка что последняя точка - склад
        CargoLoadingHistory lastPoint = points.stream()
            .max(Comparator.comparing(CargoLoadingHistory::getOrderNum))
            .orElseThrow(() -> new ValidationException("No route points"));
        if (lastPoint.getCourierWarehouseId() == null) {
            throw new ValidationException("Last point must be a warehouse");
        }
        
        // 3. Проверка что все адреса геокодированы
        boolean hasUngeoc codedPoints = points.stream()
            .anyMatch(p -> p.getLocation() == null && p.getCourierWarehouseId() == null);
        if (hasUngeocodedPoints) {
            throw new ValidationException("All addresses must be geocoded");
        }
        
        // Переводим в статус VALIDATED
        waybill.setCourierValidationStatus(CourierValidationStatus.VALIDATED);
        transportationRepo.save(waybill);
        
        log.info("Waybill {} validated by logist", waybillId);
    }
    
    /**
     * Обновление точек маршрута (только в статусе IMPORTED)
     */
    @Transactional
    public void updateWaybillPoints(Long waybillId, List<DeliveryPointUpdateDto> points) {
        Transportation waybill = transportationRepo.findById(waybillId)
            .orElseThrow(() -> new NotFoundException("Waybill not found"));
        
        // Проверка что можно редактировать
        if (!CourierValidationStatus.IMPORTED.equals(waybill.getCourierValidationStatus())) {
            throw new BusinessException("Can only edit waybills in IMPORTED status");
        }
        
        // Обновление через TransportationRouteService
        // (переиспользуем существующий функционал!)
        routeService.updateRoute(waybill, points);
        
        log.info("Waybill {} points updated by logist", waybillId);
    }
    
    // Helper methods...
}
```

---

## 📋 Обновленный чеклист MVP

### Добавить в Week 2-3:

**Новые компоненты**:
- [ ] `CourierWaybillService` - управление маршрутными листами для логиста
- [ ] `CourierWaybillController` - REST API для веб-интерфейса логиста
- [ ] DTOs для логиста (3-4 класса)

**Новые endpoints** (5 шт):
- [ ] `GET /api/v1/courier/waybills` - список маршрутных листов
- [ ] `GET /api/v1/courier/waybills/{id}` - детали маршрута
- [ ] `PUT /api/v1/courier/waybills/{id}` - редактирование маршрута
- [ ] `POST /api/v1/courier/waybills/{id}/validate` - валидация маршрута
- [ ] `POST /api/v1/courier/waybills/{id}/close` - закрытие маршрута

**Переиспользуем**:
- ✅ `POST /executor/{id}/assign-courier` - уже добавлен в `05-courier-without-transport.md`

---

## 🎯 Полный флоу (обновленный)

```
1. TEEZ → POST /api/v1/integration/waybills
   Status: IMPORTED (imported_draft)

2. Логист (через веб) → GET /api/v1/courier/waybills
   Видит список всех импортированных маршрутов

3. Логист → GET /api/v1/courier/waybills/{id}
   Открывает детали маршрута

4. Логист → PUT /api/v1/courier/waybills/{id}
   Редактирует точки маршрута (добавляет/удаляет/изменяет)
   Статус: IMPORTED (можно редактировать)

5. Логист → POST /api/v1/courier/waybills/{id}/validate
   Проверяет и валидирует маршрут
   Status: IMPORTED → VALIDATED

6. Логист → POST /api/v1/courier/waybills/{id}/assign
   Назначает курьера
   Status: VALIDATED → ASSIGNED
   TransportationStatus: WAITING_DRIVER_CONFIRMATION

7. Курьер (мобильное приложение) → выполняет доставку
   (через существующий DriverController)
   Status: ASSIGNED → IN_ROUTE → COMPLETED
   TransportationStatus: DRIVER_ACCEPTED → ON_THE_WAY → FINISHED

8. Логист → POST /api/v1/courier/waybills/{id}/close
   Закрывает маршрут
   Status: COMPLETED → CLOSED
   → Автоматически: отправка результатов в TEEZ

9. Coube → POST {teez_api_url}/api/waybill/results
   Отправка результатов
```

---

## ✅ Что добавить в MVP документацию

1. **01-mvp-plan.md**: Добавить раздел "API для логиста" с endpoints
2. **02-implementation-checklist.md**: Добавить раздел 2.X "Логист Web API"
3. **03-api-examples.md**: Добавить примеры запросов для логиста
4. **Этот документ (06)**: Детальное описание флоу редактирования

---

## ⏱️ Оценка времени

**Дополнительное время на функционал логиста**:
- `CourierWaybillService`: 4-6 часов
- `CourierWaybillController` + DTOs: 3-4 часа
- Тесты: 2-3 часа
- **Итого: +9-13 часов (1-1.5 дня)**

**Обновленная оценка MVP**: 2.5-3.5 недели (вместо 2-3)

---

## 🔑 Ключевые выводы

### ✅ Что УЖЕ учтено в MVP:
- Импорт маршрутного листа от TEEZ
- Назначение курьера (но нужно уточнить КТО назначает)
- Мобильное API для курьера
- Отправка результатов в TEEZ
- Закрытие маршрута

### ❌ Что ПРОПУЩЕНО и нужно добавить:
- **API для логиста** - просмотр списка маршрутов
- **Редактирование маршрута** - добавление/удаление точек
- **Валидация маршрута** - перевод в статус "провалидирован"
- **Блокировка обновления** - после валидации нельзя редактировать
- **Роль LOGISTICIAN** - доступ к функционалу

### 🎯 Решение:
Добавить **5 новых endpoints** для логиста + `CourierWaybillService` (примерно 1-1.5 дня работы)

---

**Дата создания**: 2025-01-07  
**Версия**: 1.0  
**Приоритет**: HIGH (критично для корректной работы по ТЗ)
