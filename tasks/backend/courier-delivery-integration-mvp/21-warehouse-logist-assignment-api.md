# 21. Автоматическое назначение ответственного логиста при импорте маршрутов от TEEZ

**Дата создания**: 2025-12-19
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali

---

## Проблема

При импорте маршрутных листов от TEEZ через API нужно автоматически назначать ответственного логиста. В одном городе (например, Алматы) может работать несколько логистов, и маршруты должны распределяться между ними на основе склада отправления.

**Текущая ситуация**:
- ✅ TEEZ отправляет waybill с полем `warehouseId` (например, "58")
- ✅ Backend находит склад по `partner_warehouse_id` = 58
- ❌ Но не назначает ответственного логиста
- ❌ Импортированные заявки имеют `createdBy = "SYSTEM_IMPORT"`
- ❌ Логист не может отфильтровать свои заявки

**Решение TEEZ**:
TEEZ предложил использовать существующее поле `warehouseId`. Их admin-логист будет привязывать склады к логистам в UI Coube, используя понятное название склада (поле `abbreviation`, например "PET-55").

---

## Решение

### Используем существующее поле `contactEmployee`

**Важно**: В Transportation уже есть поле `contactEmployee` - это логист TEEZ, ответственный за управление маршрутом.

**Существующие поля в Transportation**:
- `contactEmployee` - логист TEEZ, ответственный за управление маршрутом (**используем это**)
- `executorEmployee` - водитель/курьер TEEZ, выполняющий маршрут (назначается позже)
- `createdBy` - String username создателя (например "SYSTEM_IMPORT")

**Логика**:
1. Создать таблицу `courier_warehouse_logist_assignment` для привязки складов к логистам
2. При импорте от TEEZ: найти логиста по warehouse → назначить в `contactEmployee`
3. Логист фильтрует свои заявки по `contactEmployee.id = currentEmployeeId`

---

### Шаг 1: Создать таблицу для привязки складов к логистам

#### Миграция: Создать таблицу courier_warehouse_logist_assignment

**Файл**: `V20251219_1__create_warehouse_logist_assignment.sql`

```sql
CREATE TABLE applications.courier_warehouse_logist_assignment (
    id BIGSERIAL PRIMARY KEY,

    -- Склад (Foreign Key к courier_warehouse)
    warehouse_id UUID NOT NULL,

    -- Ответственный логист (Foreign Key к employee)
    logist_employee_id BIGINT NOT NULL,

    -- Приоритет (для случая когда несколько логистов на один склад)
    priority INT DEFAULT 1,

    -- Активность
    is_active BOOLEAN DEFAULT TRUE,

    -- Аудит
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by VARCHAR(255),

    -- Constraints
    CONSTRAINT fk_warehouse_logist_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES applications.courier_warehouse(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_warehouse_logist_employee
        FOREIGN KEY (logist_employee_id)
        REFERENCES users.employee(id)
        ON DELETE CASCADE,

    -- Уникальная комбинация (один склад - один логист)
    CONSTRAINT uq_warehouse_logist
        UNIQUE (warehouse_id, logist_employee_id)
);

-- Индексы
CREATE INDEX idx_warehouse_assignment_warehouse
    ON applications.courier_warehouse_logist_assignment(warehouse_id)
    WHERE is_active = TRUE;

CREATE INDEX idx_warehouse_assignment_employee
    ON applications.courier_warehouse_logist_assignment(logist_employee_id)
    WHERE is_active = TRUE;

-- Комментарии
COMMENT ON TABLE applications.courier_warehouse_logist_assignment IS
    'Привязка складов к ответственным логистам для автоматического назначения';

COMMENT ON COLUMN applications.courier_warehouse_logist_assignment.priority IS
    'Приоритет логиста (1 = высший). Используется если несколько логистов на один склад';
```

**Поля таблицы**:
- `warehouse_id` - UUID склада из таблицы `courier_warehouse`
- `logist_employee_id` - ID логиста из таблицы `employee`
- `priority` - приоритет (1 = высший) для балансировки нагрузки
- `is_active` - флаг активности (для архивации старых назначений)

---

### Шаг 2: Backend - Entity

**Файл**: `src/main/java/kz/coube/backend/applications/entity/CourierWarehouseLogistAssignment.java`

```java
package kz.coube.backend.applications.entity;

import jakarta.persistence.*;
import kz.coube.backend.common.entity.BasedAuditEntity;
import kz.coube.backend.users.entity.Employee;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

@Entity
@Table(
    name = "courier_warehouse_logist_assignment",
    schema = "applications",
    uniqueConstraints = {
        @UniqueConstraint(
            name = "uq_warehouse_logist",
            columnNames = {"warehouse_id", "logist_employee_id"}
        )
    },
    indexes = {
        @Index(name = "idx_warehouse_assignment_warehouse", columnList = "warehouse_id"),
        @Index(name = "idx_warehouse_assignment_employee", columnList = "logist_employee_id")
    }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class CourierWarehouseLogistAssignment extends BasedAuditEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Склад курьерской доставки
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "warehouse_id", nullable = false)
    private CourierWarehouse warehouse;

    /**
     * Ответственный логист TEEZ
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "logist_employee_id", nullable = false)
    private Employee logistEmployee;

    /**
     * Приоритет логиста (1 = высший)
     * Используется для балансировки нагрузки между несколькими логистами
     */
    @Column(name = "priority", nullable = false)
    private Integer priority = 1;

    /**
     * Флаг активности
     */
    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;
}
```

---

### Шаг 3: Backend - Repository

**Файл**: `src/main/java/kz/coube/backend/applications/repository/CourierWarehouseLogistAssignmentRepository.java`

```java
package kz.coube.backend.applications.repository;

import kz.coube.backend.applications.entity.CourierWarehouseLogistAssignment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface CourierWarehouseLogistAssignmentRepository extends JpaRepository<CourierWarehouseLogistAssignment, Long> {

    /**
     * Найти активное назначение для склада с наивысшим приоритетом
     */
    @Query("""
        SELECT a FROM CourierWarehouseLogistAssignment a
        WHERE a.warehouse.id = :warehouseId
          AND a.isActive = true
        ORDER BY a.priority ASC
        LIMIT 1
        """)
    Optional<CourierWarehouseLogistAssignment> findActiveByWarehouseIdOrderByPriority(
        @Param("warehouseId") UUID warehouseId
    );

    /**
     * Найти все активные назначения для склада
     */
    List<CourierWarehouseLogistAssignment> findByWarehouse_IdAndIsActiveTrueOrderByPriorityAsc(UUID warehouseId);

    /**
     * Найти все склады, назначенные на логиста
     */
    List<CourierWarehouseLogistAssignment> findByLogistEmployee_IdAndIsActiveTrue(Long employeeId);

    /**
     * Проверить существует ли активное назначение для склада и логиста
     */
    boolean existsByWarehouse_IdAndLogistEmployee_IdAndIsActiveTrue(UUID warehouseId, Long employeeId);

    /**
     * Найти назначение для конкретного склада и логиста
     */
    Optional<CourierWarehouseLogistAssignment> findByWarehouse_IdAndLogistEmployee_Id(
        UUID warehouseId,
        Long employeeId
    );
}
```

---

### Шаг 4: Backend - Service

**Файл**: `src/main/java/kz/coube/backend/applications/service/CourierWarehouseLogistAssignmentService.java`

```java
package kz.coube.backend.applications.service;

import kz.coube.backend.applications.entity.CourierWarehouse;
import kz.coube.backend.applications.entity.CourierWarehouseLogistAssignment;
import kz.coube.backend.applications.repository.CourierWarehouseLogistAssignmentRepository;
import kz.coube.backend.applications.repository.CourierWarehouseRepository;
import kz.coube.backend.common.exception.NotFoundException;
import kz.coube.backend.users.entity.Employee;
import kz.coube.backend.users.repository.EmployeeRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class CourierWarehouseLogistAssignmentService {

    private final CourierWarehouseLogistAssignmentRepository assignmentRepository;
    private final CourierWarehouseRepository warehouseRepository;
    private final EmployeeRepository employeeRepository;

    /**
     * Найти ответственного логиста для склада
     * Возвращает логиста с наивысшим приоритетом
     */
    @Transactional(readOnly = true)
    public Optional<Employee> findLogistForWarehouse(CourierWarehouse warehouse) {
        return assignmentRepository
            .findActiveByWarehouseIdOrderByPriority(warehouse.getId())
            .map(CourierWarehouseLogistAssignment::getLogistEmployee);
    }

    /**
     * Найти ответственного логиста по partner_warehouse_id и source_system
     * Используется при импорте маршрутов от TEEZ
     */
    @Transactional(readOnly = true)
    public Optional<Employee> findLogistByPartnerWarehouseId(
            String partnerWarehouseId,
            String sourceSystem) {

        log.debug("Finding logist for warehouse: partnerWarehouseId={}, sourceSystem={}",
            partnerWarehouseId, sourceSystem);

        Integer partnerId = Integer.parseInt(partnerWarehouseId);

        Optional<CourierWarehouse> warehouse = warehouseRepository
            .findActiveByPartnerIdAndSource(partnerId, sourceSystem);

        if (warehouse.isEmpty()) {
            log.warn("Warehouse not found: partnerWarehouseId={}, sourceSystem={}",
                partnerWarehouseId, sourceSystem);
            return Optional.empty();
        }

        Optional<Employee> logist = findLogistForWarehouse(warehouse.get());

        if (logist.isEmpty()) {
            log.warn("No logist assigned to warehouse: id={}, abbreviation={}",
                warehouse.get().getId(), warehouse.get().getAbbreviation());
        } else {
            log.info("Found logist: {} for warehouse: {}",
                logist.get().getFullName(), warehouse.get().getAbbreviation());
        }

        return logist;
    }

    /**
     * Создать новое назначение склада на логиста
     */
    @Transactional
    public CourierWarehouseLogistAssignment createAssignment(
            UUID warehouseId,
            Long employeeId,
            Integer priority) {

        CourierWarehouse warehouse = warehouseRepository.findById(warehouseId)
            .orElseThrow(() -> new NotFoundException("Warehouse not found: " + warehouseId));

        Employee employee = employeeRepository.findById(employeeId)
            .orElseThrow(() -> new NotFoundException("Employee not found: " + employeeId));

        // Проверка что назначение не существует
        if (assignmentRepository.existsByWarehouse_IdAndLogistEmployee_IdAndIsActiveTrue(
                warehouseId, employeeId)) {
            throw new IllegalStateException(
                "Active assignment already exists for warehouse " + warehouse.getAbbreviation() +
                " and employee " + employee.getFullName()
            );
        }

        CourierWarehouseLogistAssignment assignment = new CourierWarehouseLogistAssignment();
        assignment.setWarehouse(warehouse);
        assignment.setLogistEmployee(employee);
        assignment.setPriority(priority != null ? priority : 1);
        assignment.setIsActive(true);

        assignment = assignmentRepository.save(assignment);

        log.info("Created warehouse-logist assignment: warehouse={}, logist={}, priority={}",
            warehouse.getAbbreviation(), employee.getFullName(), assignment.getPriority());

        return assignment;
    }

    /**
     * Обновить приоритет назначения
     */
    @Transactional
    public CourierWarehouseLogistAssignment updateAssignmentPriority(
            Long assignmentId,
            Integer newPriority) {

        CourierWarehouseLogistAssignment assignment = assignmentRepository.findById(assignmentId)
            .orElseThrow(() -> new NotFoundException("Assignment not found: " + assignmentId));

        assignment.setPriority(newPriority);
        return assignmentRepository.save(assignment);
    }

    /**
     * Деактивировать назначение
     */
    @Transactional
    public void deactivateAssignment(Long assignmentId) {
        CourierWarehouseLogistAssignment assignment = assignmentRepository.findById(assignmentId)
            .orElseThrow(() -> new NotFoundException("Assignment not found: " + assignmentId));

        assignment.setIsActive(false);
        assignmentRepository.save(assignment);

        log.info("Deactivated warehouse-logist assignment: id={}", assignmentId);
    }

    /**
     * Получить все назначения для склада
     */
    @Transactional(readOnly = true)
    public List<CourierWarehouseLogistAssignment> getAssignmentsByWarehouse(UUID warehouseId) {
        return assignmentRepository.findByWarehouse_IdAndIsActiveTrueOrderByPriorityAsc(warehouseId);
    }

    /**
     * Получить все склады, назначенные на логиста
     */
    @Transactional(readOnly = true)
    public List<CourierWarehouseLogistAssignment> getAssignmentsByLogist(Long employeeId) {
        return assignmentRepository.findByLogistEmployee_IdAndIsActiveTrue(employeeId);
    }
}
```

---

### Шаг 5: Backend - DTO

**Файл**: `src/main/java/kz/coube/backend/applications/dto/CourierWarehouseLogistAssignmentDto.java`

```java
package kz.coube.backend.applications.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class CourierWarehouseLogistAssignmentDto {
    private Long id;
    private UUID warehouseId;
    private String warehouseAbbreviation;  // Человекочитаемое название склада (PET-55)
    private String warehouseName;
    private Long logistEmployeeId;
    private String logistEmployeeName;
    private Integer priority;
    private Boolean isActive;
}
```

**Файл**: `src/main/java/kz/coube/backend/applications/dto/CreateWarehouseLogistAssignmentRequest.java`

```java
package kz.coube.backend.applications.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.UUID;

@Data
public class CreateWarehouseLogistAssignmentRequest {

    @NotNull(message = "Warehouse ID is required")
    private UUID warehouseId;

    @NotNull(message = "Employee ID is required")
    private Long employeeId;

    @Min(value = 1, message = "Priority must be at least 1")
    private Integer priority = 1;
}
```

---

### Шаг 6: Backend - REST Controller

**Файл**: `src/main/java/kz/coube/backend/applications/controller/CourierWarehouseLogistAssignmentController.java`

```java
package kz.coube.backend.applications.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import kz.coube.backend.applications.dto.CourierWarehouseLogistAssignmentDto;
import kz.coube.backend.applications.dto.CreateWarehouseLogistAssignmentRequest;
import kz.coube.backend.applications.entity.CourierWarehouseLogistAssignment;
import kz.coube.backend.applications.service.CourierWarehouseLogistAssignmentService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/courier/warehouse-logist-assignments")
@RequiredArgsConstructor
@Tag(name = "Warehouse Logist Assignment", description = "Управление назначением логистов на склады")
public class CourierWarehouseLogistAssignmentController {

    private final CourierWarehouseLogistAssignmentService assignmentService;

    @Operation(summary = "Создать назначение склада на логиста")
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO')")
    public ResponseEntity<CourierWarehouseLogistAssignmentDto> createAssignment(
            @Valid @RequestBody CreateWarehouseLogistAssignmentRequest request) {

        CourierWarehouseLogistAssignment assignment = assignmentService.createAssignment(
            request.getWarehouseId(),
            request.getEmployeeId(),
            request.getPriority()
        );

        return ResponseEntity.status(HttpStatus.CREATED)
            .body(toDto(assignment));
    }

    @Operation(summary = "Получить все назначения для склада")
    @GetMapping("/by-warehouse/{warehouseId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO', 'LOGISTICIAN')")
    public ResponseEntity<List<CourierWarehouseLogistAssignmentDto>> getAssignmentsByWarehouse(
            @PathVariable UUID warehouseId) {

        List<CourierWarehouseLogistAssignment> assignments =
            assignmentService.getAssignmentsByWarehouse(warehouseId);

        return ResponseEntity.ok(
            assignments.stream()
                .map(this::toDto)
                .collect(Collectors.toList())
        );
    }

    @Operation(summary = "Получить все склады, назначенные на логиста")
    @GetMapping("/by-logist/{employeeId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO', 'LOGISTICIAN')")
    public ResponseEntity<List<CourierWarehouseLogistAssignmentDto>> getAssignmentsByLogist(
            @PathVariable Long employeeId) {

        List<CourierWarehouseLogistAssignment> assignments =
            assignmentService.getAssignmentsByLogist(employeeId);

        return ResponseEntity.ok(
            assignments.stream()
                .map(this::toDto)
                .collect(Collectors.toList())
        );
    }

    @Operation(summary = "Обновить приоритет назначения")
    @PutMapping("/{id}/priority")
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO')")
    public ResponseEntity<CourierWarehouseLogistAssignmentDto> updatePriority(
            @PathVariable Long id,
            @RequestParam Integer priority) {

        CourierWarehouseLogistAssignment assignment =
            assignmentService.updateAssignmentPriority(id, priority);

        return ResponseEntity.ok(toDto(assignment));
    }

    @Operation(summary = "Деактивировать назначение")
    @DeleteMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO')")
    public ResponseEntity<Void> deactivateAssignment(@PathVariable Long id) {
        assignmentService.deactivateAssignment(id);
        return ResponseEntity.noContent().build();
    }

    private CourierWarehouseLogistAssignmentDto toDto(CourierWarehouseLogistAssignment assignment) {
        return new CourierWarehouseLogistAssignmentDto(
            assignment.getId(),
            assignment.getWarehouse().getId(),
            assignment.getWarehouse().getAbbreviation(),
            assignment.getWarehouse().getName(),
            assignment.getLogistEmployee().getId(),
            assignment.getLogistEmployee().getFullName(),
            assignment.getPriority(),
            assignment.getIsActive()
        );
    }
}
```

---

### Шаг 7: Интеграция в CourierIntegrationService

**Файл**: `src/main/java/kz/coube/backend/courier/service/CourierIntegrationService.java`

**Изменения в методе `importWaybill`**:

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CourierIntegrationService {

    private final CourierWarehouseLogistAssignmentService warehouseAssignmentService;
    // ... другие зависимости

    @Transactional
    public WaybillImportResponse importWaybill(WaybillImportRequest request) {

        log.info("Importing waybill from TEEZ: id={}, sourceSystem={}",
            request.waybill().id(), request.sourceSystem());

        // 1. Валидация
        validateWaybillRequest(request);

        // 2. ⭐ NEW: Найти ответственного логиста TEEZ для склада
        Employee contactLogist = findContactLogistForWaybill(request);

        if (contactLogist == null) {
            // ⚠️ Строгий режим: блокировать импорт если логист не назначен
            throw new ValidationException(
                "No logist assigned to warehouse. " +
                "Please configure warehouse-logist assignment first."
            );

            // 🔧 Мягкий режим (для тестирования): импортировать без назначения
            // log.warn("No logist assigned to warehouse. " +
            //     "Transportation will be created without contact employee.");
        }

        // 3. Создать Transportation
        Transportation transportation = createTransportation(request);

        // ⭐ NEW: Установить contactEmployee (логист TEEZ)
        if (contactLogist != null) {
            transportation.setContactEmployee(contactLogist);
            log.info("Assigned contact logist: {} for transportation",
                contactLogist.getFullName());
        }

        // 4. Создать cargo loadings, orders, etc.
        // ...

        // 5. Сохранить
        transportation = transportationRepository.save(transportation);

        log.info("Waybill imported successfully: transportationId={}, contactLogist={}",
            transportation.getId(),
            contactLogist != null ? contactLogist.getFullName() : "NONE");

        return new WaybillImportResponse(
            transportation.getId(),
            "SUCCESS",
            contactLogist != null ? contactLogist.getFullName() : null
        );
    }

    /**
     * ⭐ NEW: Найти контактного логиста TEEZ для маршрутного листа
     */
    private Employee findContactLogistForWaybill(WaybillImportRequest request) {

        // Найти точку с warehouseId (склад отправления TEEZ)
        Optional<DeliveryPoint> warehousePoint = request.deliveries().stream()
            .filter(p -> Boolean.TRUE.equals(p.isCourierWarehouse()) && p.warehouseId() != null)
            .findFirst();

        if (warehousePoint.isEmpty()) {
            log.warn("No warehouse delivery point found in waybill");
            return null;
        }

        String warehouseId = warehousePoint.get().warehouseId();
        String sourceSystem = String.valueOf(request.sourceSystem());

        return warehouseAssignmentService
            .findLogistByPartnerWarehouseId(warehouseId, sourceSystem)
            .orElse(null);
    }
}
```

---

## Настройка (First-time setup)

### Вариант 1: Через SQL (быстрее)

```sql
-- Пример: Назначить склад "PET-55" на логиста Алишера

-- 1. Найти ID склада по abbreviation
SELECT id, abbreviation, name, partner_warehouse_id
FROM applications.courier_warehouse
WHERE abbreviation = 'PET-55' AND is_active = TRUE;
-- Результат: id = 'a1b2c3d4-...'

-- 2. Найти ID логиста TEEZ
SELECT e.id, e.first_name, e.last_name, u.username
FROM users.employee e
JOIN users.user u ON e.user_id = u.id
WHERE u.username = 'alisher.logist';
-- Результат: id = 123

-- 3. Создать назначение
INSERT INTO applications.courier_warehouse_logist_assignment
    (warehouse_id, logist_employee_id, priority, is_active, created_at, created_by)
VALUES
    ('a1b2c3d4-...', 123, 1, TRUE, NOW(), 'SYSTEM_SETUP');
```

### Вариант 2: Через REST API (для UI)

```bash
# 1. Получить список складов TEEZ
GET /api/v1/courier/warehouses
Response:
[
  {
    "id": "a1b2c3d4-...",
    "abbreviation": "PET-55",
    "name": "Курьерская доставка Петропавловск",
    "partnerWarehouseId": 58
  }
]

# 2. Получить список логистов TEEZ
GET /api/v1/employees?role=LOGISTICIAN
Response:
[
  {
    "id": 123,
    "fullName": "Алишер Нурланов",
    "username": "alisher.logist"
  }
]

# 3. Создать назначение склада на логиста
POST /api/v1/courier/warehouse-logist-assignments
{
  "warehouseId": "a1b2c3d4-...",
  "employeeId": 123,
  "priority": 1
}

Response: 201 Created
{
  "id": 1,
  "warehouseId": "a1b2c3d4-...",
  "warehouseAbbreviation": "PET-55",
  "warehouseName": "Курьерская доставка Петропавловск",
  "logistEmployeeId": 123,
  "logistEmployeeName": "Алишер Нурланов",
  "priority": 1,
  "isActive": true
}
```

---

## Тестирование

### 1. Unit тесты

**Файл**: `CourierWarehouseLogistAssignmentServiceTest.java`

```java
@Test
void findLogistForWarehouse_shouldReturnEmployeeWithHighestPriority() {
    // Given
    CourierWarehouse warehouse = createWarehouse("PET-55");
    Employee logist1 = createEmployee("Алишер", 123L);
    Employee logist2 = createEmployee("Асель", 456L);

    createAssignment(warehouse, logist1, priority: 2);  // Низкий приоритет
    createAssignment(warehouse, logist2, priority: 1);  // Высокий приоритет

    // When
    Optional<Employee> result = assignmentService.findLogistForWarehouse(warehouse);

    // Then
    assertTrue(result.isPresent());
    assertEquals("Асель", result.get().getFirstName());
}

@Test
void findLogistByPartnerWarehouseId_shouldFindCorrectLogist() {
    // Given
    CourierWarehouse warehouse = createWarehouse("PET-55", partnerId: 58);
    Employee logist = createEmployee("Алишер", 123L);
    createAssignment(warehouse, logist, priority: 1);

    // When
    Optional<Employee> result = assignmentService
        .findLogistByPartnerWarehouseId("58", "TEEZ_PVZ");

    // Then
    assertTrue(result.isPresent());
    assertEquals("Алишер", result.get().getFirstName());
}
```

### 2. Integration тест для импорта

**Файл**: `CourierIntegrationServiceTest.java`

```java
@Test
void importWaybill_shouldAssignContactEmployee() {
    // Given
    CourierWarehouse warehouse = createWarehouse(partnerId: 58);
    Employee logist = createEmployee("Алишер");
    createAssignment(warehouse, logist);

    WaybillImportRequest request = createWaybillRequest(warehouseId: "58");

    // When
    WaybillImportResponse response = courierIntegrationService.importWaybill(request);

    // Then
    assertEquals("SUCCESS", response.getStatus());

    Transportation transportation = transportationRepository
        .findById(response.getTransportationId()).get();

    assertNotNull(transportation.getContactEmployee());
    assertEquals("Алишер", transportation.getContactEmployee().getFirstName());
}

@Test
void importWaybill_noLogistAssigned_shouldThrowException() {
    // Given
    CourierWarehouse warehouse = createWarehouse(partnerId: 58);
    // НЕ создаем назначение логиста

    WaybillImportRequest request = createWaybillRequest(warehouseId: "58");

    // When & Then
    assertThrows(ValidationException.class, () -> {
        courierIntegrationService.importWaybill(request);
    });
}
```

### 3. REST API тестирование

```bash
# 1. Создать назначение
POST /api/v1/courier/warehouse-logist-assignments
{
  "warehouseId": "a1b2c3d4-...",
  "employeeId": 123,
  "priority": 1
}
# Ожидается: 201 Created

# 2. Получить назначения для склада
GET /api/v1/courier/warehouse-logist-assignments/by-warehouse/a1b2c3d4-...
# Ожидается: Список логистов для этого склада

# 3. Получить склады для логиста
GET /api/v1/courier/warehouse-logist-assignments/by-logist/123
# Ожидается: Список складов, назначенных на этого логиста

# 4. Импортировать маршрут от TEEZ и проверить назначение
POST /api/v1/integration/waybills
{
  "waybill": {
    "id": "WB-TEST-001",
    ...
  },
  "deliveries": [
    {
      "isCourierWarehouse": true,
      "warehouseId": "58",  # partner_warehouse_id
      ...
    }
  ]
}

# 5. Проверить что Transportation создан с contactEmployee
GET /api/v1/customer/transportations/{transportationId}
Response:
{
  "id": 1001,
  "contactEmployee": {
    "id": 123,
    "fullName": "Алишер Нурланов"
  },
  ...
}
```

---

## Checklist для разработки

### Phase 1: Backend Core
- [ ] Миграция: Создать таблицу `courier_warehouse_logist_assignment`
- [ ] Entity: `CourierWarehouseLogistAssignment`
- [ ] Repository: `CourierWarehouseLogistAssignmentRepository`
- [ ] Service: `CourierWarehouseLogistAssignmentService`
- [ ] DTO: Request/Response классы

### Phase 2: REST API
- [ ] Controller: CRUD endpoints для управления назначениями
- [ ] Swagger документация для endpoints
- [ ] Тесты для REST API

### Phase 3: Integration
- [ ] Обновить `CourierIntegrationService.importWaybill()`
- [ ] Добавить метод `findContactLogistForWaybill()`
- [ ] Тесты для импорта с назначением

### Phase 4: Testing
- [ ] Unit тесты для Service
- [ ] Integration тесты для импорта
- [ ] REST API тесты
- [ ] Ручное тестирование на dev/stage

---

## Estimated Time

**Backend Core**: 1.5 дня
- Миграция: 30 мин
- Entity + Repository: 2 часа
- Service: 3 часа
- DTO: 1 час

**REST API**: 1 день
- Controller: 2 часа
- Swagger docs: 1 час
- REST тесты: 2 часа

**Integration**: 0.5 дня
- CourierIntegrationService: 2 часа
- Integration тесты: 2 часа

**Testing & Fixes**: 0.5 дня

**Итого**: 3-4 дня

---

## Риски и ограничения

### Риск 1: Импорт без назначенного логиста
**Проблема**: Что делать если склад не привязан к логисту?

**Решение**:
- Строгий режим (production): Блокировать импорт с ValidationException
- Мягкий режим (dev/testing): Импортировать с `contactEmployee = null`

### Риск 2: Множественные логисты на один склад
**Проблема**: Как выбрать между несколькими логистами?

**Решение**: Использовать поле `priority` (1 = высший приоритет)

### Риск 3: Удаление логиста
**Проблема**: Что происходит с заявками если логист удален?

**Решение**: `ON DELETE CASCADE` в mapping таблице. В Transportation поле `contact_employee_id` имеет `ON DELETE SET NULL` - заявки сохраняются, только снимается назначение

---

## Поток данных

```
TEEZ отправляет waybill
  warehouseId: "58"
      ↓
Backend: CourierIntegrationService.importWaybill()
      ↓
Находит warehouse по partner_warehouse_id = 58
  (abbreviation = "PET-55")
      ↓
Ищет в courier_warehouse_logist_assignment:
  warehouse_id = ... → logist_employee_id = 123
      ↓
Находит Employee с id = 123 (Алишер Нурланов)
      ↓
Создает Transportation:
  contactEmployee = Алишер Нурланов
  createdBy = "SYSTEM_IMPORT"
      ↓
Логист Алишер видит заявку (фильтр по contactEmployee)
```

---

**Приоритет**: HIGH
**Статус**: Ready for development
**Зависимости**: Требует наличия таблиц `courier_warehouse` и `employee`
