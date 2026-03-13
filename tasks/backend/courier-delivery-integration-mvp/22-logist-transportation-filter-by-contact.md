# 22. Фильтрация заявок логистов по contactEmployee

**Дата создания**: 2025-12-19
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali
**Зависит от**: Задача #21 (автоматическое назначение `contactEmployee` при импорте от TEEZ)

---

## Проблема

После автоматического назначения ответственного логиста TEEZ при импорте маршрутов (задача #21), логисты должны видеть только свои заявки.

**Текущая ситуация** (после задачи #21):
- ✅ Transportation имеет поле `contactEmployee` - логист TEEZ, ответственный за маршрут
- ✅ При импорте от TEEZ автоматически назначается логист в `contactEmployee`
- ❌ Но логисты все еще видят ВСЕ заявки организации
- ❌ Логист А видит заявки логиста Б

**Пример**:
```
Компания "TEEZ" (выполняет курьерские доставки)
├── Логист Алишер (employee_id: 123)
│   ├── Заявка #1001 (contactEmployee: Алишер) ✅ должен видеть
│   └── Заявка #1002 (contactEmployee: Алишер) ✅ должен видеть
└── Логист Асель (employee_id: 456)
    ├── Заявка #1003 (contactEmployee: Асель) ✅ должен видеть
    └── Заявка #1004 (contactEmployee: Асель) ✅ должен видеть

❌ СЕЙЧАС: Алишер видит все заявки #1001-#1004
✅ НУЖНО: Алишер видит только #1001-#1002
```

---

## Решение

Добавить фильтрацию по `contactEmployeeId` для роли `LOGISTICIAN`. Роли `ADMIN` и `CEO` продолжают видеть все заявки компании.

**Логика доступа**:
- `LOGISTICIAN` → видит только свои заявки (`contactEmployeeId = currentEmployeeId`)
- `ADMIN`, `CEO` → видят все заявки компании
- `CUSTOMER` (организации-заказчики) → видят все заявки своей организации (без изменений)

---

## Изменения в коде

### 1. Обновить запрос в CustomerService

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Метод**: `getTransportations`

**Было**:
```java
@Transactional(readOnly = true)
public Page<TransportationResponse> getTransportations(
        TransportationFilterRequest filter,
        Pageable pageable) {

    Long organizationId = RequestContext.getOrganizationId();

    Specification<Transportation> spec = (root, query, cb) -> {
        List<Predicate> predicates = new ArrayList<>();

        // Фильтр по организации-исполнителю
        predicates.add(cb.equal(
            root.get("executorOrganization").get("id"),
            organizationId
        ));

        // Дополнительные фильтры (статус, дата, etc.)
        // ...

        return cb.and(predicates.toArray(new Predicate[0]));
    };

    return transportationRepository.findAll(spec, pageable)
        .map(transportationMapper::toResponse);
}
```

**Стало**:
```java
@Transactional(readOnly = true)
public Page<TransportationResponse> getTransportations(
        TransportationFilterRequest filter,
        Pageable pageable) {

    Long organizationId = RequestContext.getOrganizationId();
    Long currentEmployeeId = RequestContext.getEmployeeId();
    KeycloakRole currentUserRole = RequestContext.getRole();

    Specification<Transportation> spec = (root, query, cb) -> {
        List<Predicate> predicates = new ArrayList<>();

        // Фильтр по организации-исполнителю
        predicates.add(cb.equal(
            root.get("executorOrganization").get("id"),
            organizationId
        ));

        // ⭐ NEW: Фильтр по contactEmployee для логистов TEEZ
        if (currentUserRole == KeycloakRole.LOGISTICIAN) {
            predicates.add(cb.equal(
                root.get("contactEmployee").get("id"),
                currentEmployeeId
            ));
        }
        // ADMIN и CEO видят все заявки компании (без дополнительного фильтра)

        // Дополнительные фильтры (статус, дата, etc.)
        if (filter.getStatus() != null) {
            predicates.add(cb.equal(root.get("status"), filter.getStatus()));
        }
        // ...

        return cb.and(predicates.toArray(new Predicate[0]));
    };

    return transportationRepository.findAll(spec, pageable)
        .map(transportationMapper::toResponse);
}
```

---

### 2. Добавить проверку доступа при получении деталей заявки

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Метод**: `getTransportationById`

```java
@Transactional(readOnly = true)
public TransportationResponse getTransportationById(Long id) {

    Transportation transportation = transportationRepository.findById(id)
        .orElseThrow(() -> new NotFoundException("Transportation not found"));

    // Проверка доступа
    checkTransportationAccess(transportation);

    return transportationMapper.toResponse(transportation);
}
```

---

### 3. Добавить проверку доступа при редактировании заявки

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Метод**: `updateTransportation`

```java
@Transactional
public TransportationResponse updateTransportation(
        Long id,
        UpdateTransportationRequest request) {

    Transportation transportation = transportationRepository.findById(id)
        .orElseThrow(() -> new NotFoundException("Transportation not found"));

    // ⭐ Проверка доступа
    checkTransportationAccess(transportation);

    // Обновление заявки
    // ...

    return transportationMapper.toResponse(transportation);
}
```

---

### 4. Добавить вспомогательный метод для проверки доступа

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Новый метод**:

```java
/**
 * Проверяет имеет ли текущий пользователь доступ к заявке
 *
 * @param transportation заявка для проверки
 * @throws AccessDeniedException если доступ запрещен
 */
private void checkTransportationAccess(Transportation transportation) {
    Long organizationId = RequestContext.getOrganizationId();
    Long currentEmployeeId = RequestContext.getEmployeeId();
    KeycloakRole currentUserRole = RequestContext.getRole();

    // 1. Проверка организации
    if (!transportation.getExecutorOrganization().getId().equals(organizationId)) {
        throw new AccessDeniedException("You don't have access to this transportation");
    }

    // 2. Дополнительная проверка для логистов TEEZ
    if (currentUserRole == KeycloakRole.LOGISTICIAN) {

        // Проверить что логист назначен как contactEmployee
        if (transportation.getContactEmployee() == null) {
            throw new AccessDeniedException(
                "This transportation has no contact employee assigned"
            );
        }

        if (!transportation.getContactEmployee().getId().equals(currentEmployeeId)) {
            throw new AccessDeniedException(
                "Logistician can only access transportations where they are contact employee"
            );
        }
    }

    // ADMIN и CEO проходят проверку автоматически
}
```

---

## База данных

Поле `contact_employee_id` уже существует в Transportation (с момента создания таблицы).

**Проверка**:
```sql
-- Убедиться что поле существует
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'applications'
  AND table_name = 'transportation'
  AND column_name = 'contact_employee_id';

-- Проверить индекс (может потребоваться добавить для производительности)
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'transportation'
  AND indexname LIKE '%contact_employee%';
```

**Если индекса нет, добавить миграцию**:
```sql
-- V20251219_2__add_index_contact_employee.sql
CREATE INDEX IF NOT EXISTS idx_transportation_contact_employee
    ON applications.transportation(contact_employee_id)
    WHERE contact_employee_id IS NOT NULL;

COMMENT ON INDEX applications.idx_transportation_contact_employee IS
    'Индекс для быстрой фильтрации заявок по contact_employee (логисты видят только свои заявки)';
```

---

## API Behavior

### Endpoint: GET /api/v1/customer/transportations

**До изменений**:
```bash
# Логист Алишер (employee_id: 123)
GET /api/v1/customer/transportations?page=0&size=10

Response:
{
  "content": [
    { "id": 1001, "contactEmployee": { "id": 123, "name": "Алишер" } },  # Своя
    { "id": 1002, "contactEmployee": { "id": 123, "name": "Алишер" } },  # Своя
    { "id": 1003, "contactEmployee": { "id": 456, "name": "Асель" } },    # Чужая ❌
    { "id": 1004, "contactEmployee": { "id": 456, "name": "Асель" } }     # Чужая ❌
  ],
  "totalElements": 4
}
```

**После изменений**:
```bash
# Логист Алишер (employee_id: 123)
GET /api/v1/customer/transportations?page=0&size=10

Response:
{
  "content": [
    { "id": 1001, "contactEmployee": { "id": 123, "name": "Алишер" } },  # Своя ✅
    { "id": 1002, "contactEmployee": { "id": 123, "name": "Алишер" } }   # Своя ✅
  ],
  "totalElements": 2
}
```

---

### Endpoint: GET /api/v1/customer/transportations/{id}

**Сценарий**: Логист Алишер пытается получить чужую заявку

```bash
# Логист Алишер (employee_id: 123) пытается открыть заявку Асель
GET /api/v1/customer/transportations/1003

Response: 403 Forbidden
{
  "error": "ACCESS_DENIED",
  "message": "Logistician can only access transportations where they are contact employee"
}
```

---

### Endpoint: PUT /api/v1/customer/transportations/{id}

**Сценарий**: Логист Алишер пытается редактировать чужую заявку

```bash
# Логист Алишер (employee_id: 123) пытается редактировать заявку Асель
PUT /api/v1/customer/transportations/1003
{
  "status": "CANCELLED"
}

Response: 403 Forbidden
{
  "error": "ACCESS_DENIED",
  "message": "Logistician can only access transportations where they are contact employee"
}
```

---

## Роли и права доступа

| Роль          | Список заявок                            | Редактирование заявок                     |
|---------------|------------------------------------------|-------------------------------------------|
| `LOGISTICIAN` | Только где `contactEmployee = self`      | Только где `contactEmployee = self`       |
| `ADMIN`       | Все заявки компании                      | Все заявки компании                       |
| `CEO`         | Все заявки компании                      | Все заявки компании                       |
| `CUSTOMER`    | Все заявки своей организации (заказчик)  | Все заявки своей организации              |

---

## Тестирование

### 1. Unit тесты для CustomerService

**Файл**: `CustomerServiceTest.java`

```java
@Test
void logistician_shouldSeeOnlyOwnTransportations() {
    // Given
    Long logistId = 123L;
    when(RequestContext.getEmployeeId()).thenReturn(logistId);
    when(RequestContext.getRole()).thenReturn(KeycloakRole.LOGISTICIAN);

    Transportation t1 = createTransportation(contactEmployeeId: logistId);
    Transportation t2 = createTransportation(contactEmployeeId: logistId);
    Transportation t3 = createTransportation(contactEmployeeId: 456L);  // Чужая

    // When
    Page<TransportationResponse> result = customerService.getTransportations(
        new TransportationFilterRequest(),
        PageRequest.of(0, 10)
    );

    // Then
    assertEquals(2, result.getTotalElements());
    assertTrue(result.stream()
        .allMatch(t -> t.getContactEmployee().getId().equals(logistId)));
}

@Test
void admin_shouldSeeAllCompanyTransportations() {
    // Given
    when(RequestContext.getRole()).thenReturn(KeycloakRole.ADMIN);

    createTransportation(contactEmployeeId: 123L);
    createTransportation(contactEmployeeId: 456L);

    // When
    Page<TransportationResponse> result = customerService.getTransportations(
        new TransportationFilterRequest(),
        PageRequest.of(0, 10)
    );

    // Then
    assertEquals(2, result.getTotalElements());
}

@Test
void logistician_cannotAccessOtherLogistTransportation() {
    // Given
    Long logistId = 123L;
    Long otherLogistId = 456L;

    Transportation transportation = createTransportation(
        contactEmployeeId: otherLogistId
    );

    when(RequestContext.getEmployeeId()).thenReturn(logistId);
    when(RequestContext.getRole()).thenReturn(KeycloakRole.LOGISTICIAN);
    when(transportationRepository.findById(1L)).thenReturn(Optional.of(transportation));

    // When & Then
    assertThrows(AccessDeniedException.class, () -> {
        customerService.getTransportationById(1L);
    });
}

@Test
void logistician_cannotAccessTransportationWithoutContactEmployee() {
    // Given
    Transportation transportation = createTransportation(
        contactEmployee: null  // Нет contactEmployee
    );

    when(RequestContext.getEmployeeId()).thenReturn(123L);
    when(RequestContext.getRole()).thenReturn(KeycloakRole.LOGISTICIAN);
    when(transportationRepository.findById(1L)).thenReturn(Optional.of(transportation));

    // When & Then
    assertThrows(AccessDeniedException.class, () -> {
        customerService.getTransportationById(1L);
    });
}
```

---

### 2. Integration тесты

**Файл**: `CustomerControllerIntegrationTest.java`

```java
@Test
@WithMockUser(roles = "LOGISTICIAN")
void getTransportations_asLogistician_returnsOnlyOwnTransportations() throws Exception {
    // Given
    Employee logist = createEmployee("Алишер", employeeId: 123L);
    createTransportation(contactEmployee: logist);  // Своя
    createTransportation(contactEmployee: logist);  // Своя
    createTransportation(contactEmployee: anotherLogist);  // Чужая

    mockRequestContext(employeeId: 123L, role: LOGISTICIAN);

    // When & Then
    mockMvc.perform(get("/api/v1/customer/transportations"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.totalElements").value(2))
        .andExpect(jsonPath("$.content[*].contactEmployee.id")
            .value(everyItem(is(123))));
}

@Test
@WithMockUser(roles = "ADMIN")
void getTransportations_asAdmin_returnsAllCompanyTransportations() throws Exception {
    // Given
    createTransportation(contactEmployeeId: 123L);
    createTransportation(contactEmployeeId: 456L);

    // When & Then
    mockMvc.perform(get("/api/v1/customer/transportations"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.totalElements").value(2));
}

@Test
@WithMockUser(roles = "LOGISTICIAN")
void getTransportationById_asLogistician_accessDenied() throws Exception {
    // Given
    Employee otherLogist = createEmployee(employeeId: 456L);
    Transportation transportation = createTransportation(
        contactEmployee: otherLogist
    );

    mockRequestContext(employeeId: 123L, role: LOGISTICIAN);

    // When & Then
    mockMvc.perform(get("/api/v1/customer/transportations/" + transportation.getId()))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.error").value("ACCESS_DENIED"));
}
```

---

### 3. Тестирование на stage

```bash
# 1. Создать 2 логистов в TEEZ
POST /api/v1/admin/employees
{
  "firstName": "Алишер",
  "lastName": "Нурланов",
  "role": "LOGISTICIAN",
  "organizationId": 100  # TEEZ
}

POST /api/v1/admin/employees
{
  "firstName": "Асель",
  "lastName": "Токаева",
  "role": "LOGISTICIAN",
  "organizationId": 100  # TEEZ
}

# 2. Привязать склады к логистам (из задачи #21)
POST /api/v1/courier/warehouse-logist-assignments
{
  "warehouseId": "warehouse-almaty-1",
  "employeeId": 123  # Алишер
}

POST /api/v1/courier/warehouse-logist-assignments
{
  "warehouseId": "warehouse-almaty-2",
  "employeeId": 456  # Асель
}

# 3. Импортировать маршруты от TEEZ
POST /api/v1/integration/waybills
{
  "waybill": { "id": "WB-001" },
  "deliveries": [
    { "warehouseId": "58" }  # Привязан к Алишеру → contactEmployee = Алишер
  ]
}

POST /api/v1/integration/waybills
{
  "waybill": { "id": "WB-002" },
  "deliveries": [
    { "warehouseId": "59" }  # Привязан к Асель → contactEmployee = Асель
  ]
}

# 4. Залогиниться как Алишер и проверить список
GET /api/v1/customer/transportations
# Должен вернуть только WB-001 (свою заявку)

# 5. Залогиниться как Асель и проверить список
GET /api/v1/customer/transportations
# Должен вернуть только WB-002 (свою заявку)

# 6. Проверить что Алишер не может открыть чужую заявку
# Залогиниться как Алишер
GET /api/v1/customer/transportations/{id_заявки_асель}
# Должен вернуть 403 Forbidden

# 7. Проверить что ADMIN видит все заявки
# Залогиниться как ADMIN
GET /api/v1/customer/transportations
# Должен вернуть WB-001 и WB-002
```

---

## Testing Checklist

### Backend
- [ ] Логист видит только заявки где он `contactEmployee`
- [ ] ADMIN видит все заявки компании
- [ ] CEO видит все заявки компании
- [ ] Логист не может открыть чужую заявку (403 Forbidden)
- [ ] Логист не может редактировать чужую заявку (403 Forbidden)
- [ ] Логист не может открыть заявку без `contactEmployee` (403 Forbidden)
- [ ] ADMIN может редактировать любую заявку компании
- [ ] Unit тесты для проверки фильтрации
- [ ] Integration тесты для API endpoints

### Database
- [ ] Поле `contact_employee_id` существует в Transportation
- [ ] Индекс на `contact_employee_id` создан (для производительности)

### Frontend (для проверки)
- [ ] Список заявок показывает только доступные заявки
- [ ] При попытке открыть чужую заявку показывается ошибка 403
- [ ] ADMIN/CEO видят все заявки компании

---

## Impact Analysis

### Backward Compatibility
⚠️ **BREAKING CHANGE для логистов**: После внедрения логисты перестанут видеть чужие заявки

**Миграция**:
1. Убедиться что все импортированные заявки от TEEZ имеют `contact_employee_id` (задача #21)
2. Уведомить пользователей о предстоящих изменениях
3. Развернуть изменения
4. Мониторить обращения от логистов

### Security Improvement
✅ **Улучшение безопасности**: Разграничение доступа между логистами одной компании TEEZ

---

## Что нужно сделать

### Backend
1. ❌ `CustomerService.getTransportations()` - добавить фильтр по `contactEmployee` для LOGISTICIAN
2. ❌ `CustomerService.checkTransportationAccess()` - создать метод проверки доступа
3. ❌ `CustomerService.getTransportationById()` - добавить проверку доступа
4. ❌ `CustomerService.updateTransportation()` - добавить проверку доступа

### Database (опционально)
5. ❌ Добавить индекс на `contact_employee_id` если его нет (для производительности)

### Testing
6. ❌ Unit тесты для фильтрации
7. ❌ Unit тесты для проверки доступа
8. ❌ Integration тесты для API
9. ❌ Ручное тестирование на stage

---

## Estimated Time

**Backend**: 2 часа
- Обновление `getTransportations()`: 30 мин
- Создание `checkTransportationAccess()`: 30 мин
- Добавление проверок в CRUD методы: 1 час

**Database**: 15 мин (если нужен индекс)

**Testing**: 2 часа
- Unit тесты: 1 час
- Integration тесты: 1 час

**Итого**: 4-5 часов (полдня)

---

## Зависимости

**Требует завершения задачи #21**:
- Автоматическое назначение `contactEmployee` должно работать при импорте от TEEZ

---

**Приоритет**: HIGH
**Статус**: Ready for development (after task #21)
**Зависимости**: Задача #21 (Warehouse-Logist Assignment API)
