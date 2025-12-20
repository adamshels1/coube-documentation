# 21. ⚠️ DEPRECATED - Разграничение доступа логистов к заявкам внутри одной компании

**Дата создания**: 2025-12-14
**Дата устаревания**: 2025-12-19
**Статус**: ❌ DEPRECATED
**Приоритет**: ~~HIGH~~ → CANCELLED
**Автор**: Ali

---

## ⚠️ ВНИМАНИЕ: ЭТОТ ФАЙЛ УСТАРЕЛ

**Причина**: Подход основан на неправильном понимании поля `createdBy`

**Проблемы**:
1. ❌ `createdBy` - это String поле из `BasedAuditEntity`, а не Foreign Key к Employee
2. ❌ `createdBy` хранит username (например "ivan.logist"), а не ID сотрудника
3. ❌ Для импортированных заявок от TEEZ `createdBy = "SYSTEM_IMPORT"`, а не конкретный логист
4. ❌ Невозможно отфильтровать заявки по `createdBy.getId()` (поле не существует)

**Правильное решение**:
- ✅ См. задачу #21: `21-warehouse-logist-assignment-api.md` - использование существующего поля `contactEmployee`
- ✅ См. задачу #22: `22-logist-transportation-filter-by-contact.md` - фильтрация по `contactEmployee`

**Что использовать вместо этого**:
1. Использовать существующее поле `contact_employee_id` в Transportation (задача #21)
2. Автоматически назначать ответственного логиста при импорте от TEEZ в `contactEmployee` (задача #21)
3. Фильтровать заявки по `contactEmployee` вместо `createdBy` (задача #22)

---

## ~~Проблема~~ (НЕПРАВИЛЬНЫЙ ПОДХОД)

## Проблема

В одной компании могут работать несколько логистов. Сейчас все логисты компании видят все заявки компании, созданные любым сотрудником. Это нарушает принцип разграничения доступа - каждый логист должен видеть только свои заявки.

**Текущая ситуация**:
- ✅ API `/api/v1/customer/transportations` возвращает все заявки организации
- ❌ Логист А видит заявки логиста Б (и наоборот)
- ❌ Нет фильтрации по создателю заявки
- ❌ Логисты могут редактировать чужие заявки

**Пример**:
```
Компания "Teez"
├── Логист Иванов (user_id: 123)
│   ├── Заявка #1001 ✅ должен видеть
│   └── Заявка #1002 ✅ должен видеть
└── Логист Петров (user_id: 456)
    ├── Заявка #1003 ✅ должен видеть
    └── Заявка #1004 ✅ должен видеть

❌ СЕЙЧАС: Иванов видит все заявки #1001-#1004
✅ НУЖНО: Иванов видит только #1001-#1002
```

---

## Решение

Добавить фильтрацию по `createdById` (создатель заявки) для роли `LOGISTICIAN`. Роли `ADMIN` и `CEO` продолжают видеть все заявки компании.

**Логика доступа**:
- `LOGISTICIAN` → видит только свои заявки (`createdById = currentUserId`)
- `ADMIN`, `CEO` → видят все заявки компании
- Организации-заказчики → видят все заявки своей организации (без изменений)

---

## Изменения в коде

### 1. Обновить запрос в CustomerService

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Метод**: `getTransportations` (или аналогичный метод для получения списка заявок)

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
    Long currentUserId = RequestContext.getUserId();
    KeycloakRole currentUserRole = RequestContext.getRole();

    Specification<Transportation> spec = (root, query, cb) -> {
        List<Predicate> predicates = new ArrayList<>();

        // Фильтр по организации-исполнителю
        predicates.add(cb.equal(
            root.get("executorOrganization").get("id"),
            organizationId
        ));

        // ⭐ NEW: Фильтр по создателю для логистов
        if (currentUserRole == KeycloakRole.LOGISTICIAN) {
            predicates.add(cb.equal(
                root.get("createdBy").get("id"),
                currentUserId
            ));
        }
        // ADMIN и CEO видят все заявки компании (без дополнительного фильтра)

        // Дополнительные фильтры (статус, дата, etc.)
        // ...

        return cb.and(predicates.toArray(new Predicate[0]));
    };

    return transportationRepository.findAll(spec, pageable)
        .map(transportationMapper::toResponse);
}
```

### 2. Добавить проверку доступа при редактировании заявки

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Метод**: `updateTransportation` (или `getTransportationById`)

**Добавить проверку**:
```java
@Transactional
public TransportationResponse updateTransportation(
        Long id,
        UpdateTransportationRequest request) {

    Transportation transportation = transportationRepository.findById(id)
        .orElseThrow(() -> new NotFoundException("Transportation not found"));

    // ⭐ NEW: Проверка доступа для логистов
    Long currentUserId = RequestContext.getUserId();
    KeycloakRole currentUserRole = RequestContext.getRole();

    if (currentUserRole == KeycloakRole.LOGISTICIAN) {
        // Логист может редактировать только свои заявки
        if (!transportation.getCreatedBy().getId().equals(currentUserId)) {
            throw new AccessDeniedException(
                "You don't have access to this transportation"
            );
        }
    }
    // ADMIN и CEO могут редактировать любые заявки компании

    // Обновление заявки
    // ...

    return transportationMapper.toResponse(transportation);
}
```

### 3. Обновить метод получения деталей заявки

**Файл**: `src/main/java/kz/coube/backend/customer/service/CustomerService.java`

**Метод**: `getTransportationById`

**Добавить проверку**:
```java
@Transactional(readOnly = true)
public TransportationResponse getTransportationById(Long id) {

    Transportation transportation = transportationRepository.findById(id)
        .orElseThrow(() -> new NotFoundException("Transportation not found"));

    // Проверка что заявка принадлежит организации пользователя
    Long organizationId = RequestContext.getOrganizationId();
    if (!transportation.getExecutorOrganization().getId().equals(organizationId)) {
        throw new AccessDeniedException("You don't have access to this transportation");
    }

    // ⭐ NEW: Дополнительная проверка для логистов
    Long currentUserId = RequestContext.getUserId();
    KeycloakRole currentUserRole = RequestContext.getRole();

    if (currentUserRole == KeycloakRole.LOGISTICIAN) {
        if (!transportation.getCreatedBy().getId().equals(currentUserId)) {
            throw new AccessDeniedException(
                "You don't have access to this transportation"
            );
        }
    }

    return transportationMapper.toResponse(transportation);
}
```

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
    Long currentUserId = RequestContext.getUserId();
    KeycloakRole currentUserRole = RequestContext.getRole();

    // Проверка организации
    if (!transportation.getExecutorOrganization().getId().equals(organizationId)) {
        throw new AccessDeniedException("You don't have access to this transportation");
    }

    // Дополнительная проверка для логистов
    if (currentUserRole == KeycloakRole.LOGISTICIAN) {
        if (transportation.getCreatedBy() == null
                || !transportation.getCreatedBy().getId().equals(currentUserId)) {
            throw new AccessDeniedException(
                "Logistician can only access their own transportations"
            );
        }
    }

    // ADMIN и CEO проходят проверку автоматически
}
```

**Использование**:
```java
public TransportationResponse getTransportationById(Long id) {
    Transportation transportation = transportationRepository.findById(id)
        .orElseThrow(() -> new NotFoundException("Transportation not found"));

    checkTransportationAccess(transportation);  // ⭐ Использование метода

    return transportationMapper.toResponse(transportation);
}
```

---

## База данных

### Проверка существующих полей

Убедиться что в таблице `transportation` есть поле `created_by_id`:

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'transportation'
  AND column_name = 'created_by_id';
```

**Ожидаемый результат**:
```
column_name    | data_type
---------------+-----------
created_by_id  | bigint
```

Если поля нет, нужна миграция:

```sql
-- V20251214__add_created_by_to_transportation.sql
ALTER TABLE public.transportation
ADD COLUMN created_by_id BIGINT,
ADD CONSTRAINT fk_transportation_created_by
    FOREIGN KEY (created_by_id)
    REFERENCES public.employee(id);

CREATE INDEX idx_transportation_created_by
    ON public.transportation(created_by_id);
```

---

## API Behavior

### Endpoint: GET /api/v1/customer/transportations

**До изменений**:
```bash
# Логист Иванов (user_id: 123)
GET /api/v1/customer/transportations?page=0&size=10

Response:
{
  "content": [
    { "id": 1001, "createdBy": { "id": 123, "name": "Иванов" } },  # Своя
    { "id": 1002, "createdBy": { "id": 123, "name": "Иванов" } },  # Своя
    { "id": 1003, "createdBy": { "id": 456, "name": "Петров" } },  # Чужая ❌
    { "id": 1004, "createdBy": { "id": 456, "name": "Петров" } }   # Чужая ❌
  ],
  "totalElements": 4
}
```

**После изменений**:
```bash
# Логист Иванов (user_id: 123)
GET /api/v1/customer/transportations?page=0&size=10

Response:
{
  "content": [
    { "id": 1001, "createdBy": { "id": 123, "name": "Иванов" } },  # Своя ✅
    { "id": 1002, "createdBy": { "id": 123, "name": "Иванов" } }   # Своя ✅
  ],
  "totalElements": 2
}
```

### Endpoint: GET /api/v1/customer/transportations/{id}

**Сценарий**: Логист Иванов пытается получить чужую заявку

```bash
# Логист Иванов (user_id: 123) пытается открыть заявку Петрова
GET /api/v1/customer/transportations/1003

Response: 403 Forbidden
{
  "error": "ACCESS_DENIED",
  "message": "Logistician can only access their own transportations"
}
```

### Endpoint: PUT /api/v1/customer/transportations/{id}

**Сценарий**: Логист Иванов пытается редактировать чужую заявку

```bash
# Логист Иванов (user_id: 123) пытается редактировать заявку Петрова
PUT /api/v1/customer/transportations/1003
{
  "status": "CANCELLED"
}

Response: 403 Forbidden
{
  "error": "ACCESS_DENIED",
  "message": "You don't have access to this transportation"
}
```

---

## Роли и права доступа

| Роль          | Список заявок                    | Редактирование заявок              |
|---------------|----------------------------------|------------------------------------|
| `LOGISTICIAN` | Только свои заявки               | Только свои заявки                 |
| `ADMIN`       | Все заявки компании              | Все заявки компании                |
| `CEO`         | Все заявки компании              | Все заявки компании                |
| `CUSTOMER`    | Все заявки своей организации     | Все заявки своей организации       |

---

## Тестирование

### 1. Unit тесты для CustomerService

**Файл**: `CustomerServiceTest.java`

```java
@Test
void logistician_shouldSeeOnlyOwnTransportations() {
    // Given
    Long logistId = 123L;
    when(RequestContext.getUserId()).thenReturn(logistId);
    when(RequestContext.getRole()).thenReturn(KeycloakRole.LOGISTICIAN);

    // When
    Page<TransportationResponse> result = customerService.getTransportations(
        new TransportationFilterRequest(),
        PageRequest.of(0, 10)
    );

    // Then
    assertTrue(result.stream()
        .allMatch(t -> t.getCreatedBy().getId().equals(logistId)));
}

@Test
void admin_shouldSeeAllCompanyTransportations() {
    // Given
    when(RequestContext.getRole()).thenReturn(KeycloakRole.ADMIN);

    // When
    Page<TransportationResponse> result = customerService.getTransportations(
        new TransportationFilterRequest(),
        PageRequest.of(0, 10)
    );

    // Then
    assertTrue(result.getTotalElements() > 0);
    // Проверить что есть заявки от разных создателей
}

@Test
void logistician_cannotAccessOtherLogistTransportation() {
    // Given
    Long logistId = 123L;
    Long otherLogistId = 456L;

    Transportation transportation = new Transportation();
    transportation.setCreatedBy(createEmployee(otherLogistId));

    when(RequestContext.getUserId()).thenReturn(logistId);
    when(RequestContext.getRole()).thenReturn(KeycloakRole.LOGISTICIAN);
    when(transportationRepository.findById(1L)).thenReturn(Optional.of(transportation));

    // When & Then
    assertThrows(AccessDeniedException.class, () -> {
        customerService.getTransportationById(1L);
    });
}
```

### 2. Integration тесты

**Файл**: `CustomerControllerIntegrationTest.java`

```java
@Test
@WithMockUser(roles = "LOGISTICIAN")
void getTransportations_asLogistician_returnsOnlyOwnTransportations() throws Exception {
    // Given
    createTransportation(123L, "Logist A");  // Своя заявка
    createTransportation(123L, "Logist A");  // Своя заявка
    createTransportation(456L, "Logist B");  // Чужая заявка

    // When & Then
    mockMvc.perform(get("/api/v1/customer/transportations"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.totalElements").value(2))
        .andExpect(jsonPath("$.content[*].createdBy.id").value(everyItem(is(123))));
}

@Test
@WithMockUser(roles = "ADMIN")
void getTransportations_asAdmin_returnsAllCompanyTransportations() throws Exception {
    // Given
    createTransportation(123L, "Logist A");
    createTransportation(456L, "Logist B");

    // When & Then
    mockMvc.perform(get("/api/v1/customer/transportations"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.totalElements").value(2));
}

@Test
@WithMockUser(roles = "LOGISTICIAN")
void getTransportationById_asLogistician_accessDenied() throws Exception {
    // Given
    Long otherLogistTransportationId = createTransportation(456L, "Logist B");

    // When & Then
    mockMvc.perform(get("/api/v1/customer/transportations/" + otherLogistTransportationId))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.error").value("ACCESS_DENIED"));
}
```

### 3. Тестирование на stage

```bash
# 1. Создать 2 логистов в одной компании
POST /api/v1/admin/employees
{
  "name": "Логист Иванов",
  "role": "LOGISTICIAN",
  "organizationId": 100
}

POST /api/v1/admin/employees
{
  "name": "Логист Петров",
  "role": "LOGISTICIAN",
  "organizationId": 100
}

# 2. Создать заявки от каждого логиста
# Залогиниться как Иванов
POST /api/v1/customer/transportations
{ ... }

# Залогиниться как Петров
POST /api/v1/customer/transportations
{ ... }

# 3. Проверить что Иванов видит только свои заявки
# Залогиниться как Иванов
GET /api/v1/customer/transportations
# Должен вернуть только заявки Иванова

# 4. Проверить что Петров не может открыть заявку Иванова
# Залогиниться как Петров
GET /api/v1/customer/transportations/{ivanov_transportation_id}
# Должен вернуть 403 Forbidden

# 5. Проверить что ADMIN видит все заявки
# Залогиниться как ADMIN той же организации
GET /api/v1/customer/transportations
# Должен вернуть заявки всех логистов
```

---

## Testing Checklist

### Backend
- [ ] Логист видит только свои заявки в списке
- [ ] ADMIN видит все заявки компании
- [ ] CEO видит все заявки компании
- [ ] Логист не может открыть чужую заявку (403 Forbidden)
- [ ] Логист не может редактировать чужую заявку (403 Forbidden)
- [ ] ADMIN может редактировать любую заявку компании
- [ ] Поле `created_by_id` заполняется при создании заявки
- [ ] Unit тесты для проверки фильтрации
- [ ] Integration тесты для API endpoints

### База данных
- [ ] Поле `created_by_id` существует в таблице `transportation`
- [ ] Индекс на `created_by_id` создан
- [ ] Foreign key constraint установлен
- [ ] Все существующие заявки имеют корректный `created_by_id`

### Frontend (для проверки)
- [ ] Список заявок показывает только доступные заявки
- [ ] При попытке открыть чужую заявку показывается ошибка
- [ ] ADMIN/CEO видят все заявки компании

---

## Impact Analysis

### Backward Compatibility
⚠️ **BREAKING CHANGE для логистов**: После внедрения логисты перестанут видеть чужие заявки

**План миграции**:
1. Убедиться что все существующие заявки имеют `created_by_id`
2. Уведомить пользователей о предстоящих изменениях
3. Развернуть изменения
4. Мониторить обращения от логистов

### Database Migration
✅ **Безопасно**: Если поле `created_by_id` уже существует и заполнено

⚠️ **Требует миграции**: Если поле отсутствует или есть NULL значения

### Security Improvement
✅ **Улучшение безопасности**: Разграничение доступа между логистами одной компании

---

## Что нужно сделать

### Backend (3-4 изменения)
1. ❌ `CustomerService.java` - добавить фильтр по `createdById` для LOGISTICIAN
2. ❌ `CustomerService.java` - добавить проверку доступа в `getTransportationById`
3. ❌ `CustomerService.java` - добавить проверку доступа в `updateTransportation`
4. ❌ Добавить вспомогательный метод `checkTransportationAccess`

### Database
5. ❌ Проверить существование поля `created_by_id`
6. ❌ Создать миграцию если поле отсутствует
7. ❌ Проверить заполненность поля для существующих заявок

### Testing
8. ❌ Unit тесты для фильтрации
9. ❌ Integration тесты для API
10. ❌ Ручное тестирование на stage

---

## Estimated

**Backend**: 3 часа
- Обновление CustomerService: 1.5 часа
- Добавление проверок доступа: 1 час
- Вспомогательные методы: 30 мин

**Database**: 30 мин - 1 час
- Проверка и миграция: 30 мин
- Заполнение NULL значений: 30 мин (если требуется)

**Testing**: 2 часа
- Unit тесты: 1 час
- Integration тесты: 1 час

**Итого**: 5.5 - 6 часов (1 рабочий день)

---

## Альтернативные решения

### Вариант 1: Добавить параметр API для фильтрации (отклонен)
```
GET /api/v1/customer/transportations?createdByMe=true
```

**Минусы**:
- Логист может убрать параметр и увидеть все заявки
- Нет реального разграничения доступа
- Потенциальная уязвимость

### Вариант 2: Создать отдельную таблицу для прав доступа (избыточно)
```sql
CREATE TABLE transportation_access (
  transportation_id BIGINT,
  user_id BIGINT,
  access_level VARCHAR(20)
);
```

**Минусы**:
- Избыточная сложность для простой задачи
- Требует дополнительных JOIN запросов
- Увеличивает время разработки

### ✅ Выбранное решение: Фильтрация на уровне Specification
- Простая реализация
- Производительная (использует индекс)
- Централизованная логика доступа
- Легко расширяется для других ролей

---

**Приоритет**: HIGH - критично для безопасности и разграничения доступа
**Риски**: Средние - breaking change для существующих логистов
**Зависимости**: Требует наличия поля `created_by_id` в таблице `transportation`
